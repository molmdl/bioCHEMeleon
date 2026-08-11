"""Tests for biochemeleon.persistence - build_bcm_dict + parse_bcm_dict.

Pure-layer tests (no PyMOL needed). persistence.py imports only stdlib +
biochemeleon.registry + biochemeleon.setup_state, but biochemeleon/__init__.py
does `from pymol.Qt import ...` at module level, so we stub pymol/pymol.Qt
via sys.modules (same pattern as tests/test_registry.py lines 13-15 + 19-21)
before importing biochemeleon.*.

Run: python3.6 -m unittest tests.test_persistence -v
Or:  python3.6 tests/test_persistence.py
"""
import os
import sys
import json
import time
import unittest
from unittest.mock import MagicMock

# Stub pymol so importing biochemeleon.* (whose __init__.py does
# `from pymol.Qt import ...`) doesn't fail in WSL without PyMOL.
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()

# Ensure repo root is on sys.path when run as a script
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from biochemeleon.persistence import (
    build_bcm_dict, parse_bcm_dict, BCM_MAGIC, BCM_VERSION,
)
from biochemeleon.registry import HiderRegistry, HIDER_STATUS_FOUND


# ---- Test helpers ----

class MockController(object):
    """Minimal stand-in for GameController with the attrs build_bcm_dict reads.

    build_bcm_dict reads: target_obj, registry, _reveal_count, _hint_count,
    _found_color, _started, _start_time (and optionally _found_color_rgb via
    getattr — not set here so the forward-compat hook returns None). It does
    NOT read _backup_name / _wizard / callbacks (transient).
    """

    def __init__(self, target_obj='1ubq', started=True, reveal_count=1,
                 hint_count=2, found_color='green', start_time=None):
        self.target_obj = target_obj
        self.registry = HiderRegistry()
        self._started = started
        self._reveal_count = reveal_count
        self._hint_count = hint_count
        self._found_color = found_color
        self._start_time = start_time


def _sample_setup():
    """Return a representative gui_setup.collect_state() dict for tests."""
    return {
        'format': 'biochemeleon-setup-v1',
        'target_mode': 'fetch',
        'pdb_code': '1ubq',
        'hider_count': 5,
        'per_rep': {'spheres': 3, 'sticks': 2},
    }


# ---- build_bcm_dict ----

class TestBuildBcmDict(unittest.TestCase):
    """8 tests for build_bcm_dict (the SAVE path: controller -> .bcm dict)."""

    def test_checkpoint_dict_shape(self):
        ctrl = MockController(started=True, reveal_count=1, hint_count=2,
                              start_time=time.time() - 42.5)
        setup = _sample_setup()
        d = build_bcm_dict(ctrl, setup, 'checkpoint', elapsed=42.5)
        self.assertEqual(d['magic'], BCM_MAGIC)
        self.assertEqual(d['version'], BCM_VERSION)
        self.assertEqual(d['kind'], 'checkpoint')
        self.assertEqual(d['target_object'], '1ubq')
        self.assertEqual(d['started'], True)
        self.assertEqual(d['timer_elapsed'], 42.5)
        self.assertEqual(d['reveal_count'], 1)
        self.assertEqual(d['hint_count'], 2)
        self.assertEqual(d['found_color'], 'green')
        self.assertIsNone(d['found_color_rgb'])
        self.assertEqual(d['registry'], ctrl.registry.to_dict())
        self.assertEqual(d['setup'], setup)

    def test_puzzle_dict_shape(self):
        # started=True simulates the post-gc.start() state (hiders inserted,
        # controller._started True) — build_bcm_dict must force started=False
        # for kind='puzzle' (the educator did not play the puzzle).
        ctrl = MockController(started=True)
        setup = _sample_setup()
        d = build_bcm_dict(ctrl, setup, 'puzzle')
        self.assertEqual(d['kind'], 'puzzle')
        self.assertEqual(d['timer_elapsed'], 0.0)
        self.assertEqual(d['started'], False)

    def test_puzzle_started_true_forces_false(self):
        # Isates the forcing so a regression to bool(controller._started) is
        # caught even if test_puzzle_dict_shape used a started=False controller.
        ctrl = MockController(started=True)
        d = build_bcm_dict(ctrl, _sample_setup(), 'puzzle')
        self.assertEqual(d['started'], False)

    def test_invalid_kind_raises(self):
        ctrl = MockController()
        with self.assertRaises(ValueError):
            build_bcm_dict(ctrl, _sample_setup(), 'frob')

    def test_elapsed_none_checkpoint_uses_start_time(self):
        # elapsed=None + kind='checkpoint' + _start_time set -> falls back to
        # time.time() - controller._start_time.
        start = time.time() - 10.0
        ctrl = MockController(started=True, start_time=start)
        d = build_bcm_dict(ctrl, _sample_setup(), 'checkpoint', elapsed=None)
        # Allow a small delta for execution time between start_time capture
        # and the time.time() call inside build_bcm_dict.
        self.assertAlmostEqual(d['timer_elapsed'], 10.0, delta=2.0)

    def test_elapsed_none_puzzle_is_zero(self):
        # elapsed=None + kind='puzzle' -> 0.0 (no _start_time fallback for
        # puzzles; the educator did not play).
        ctrl = MockController(started=True, start_time=time.time())
        d = build_bcm_dict(ctrl, _sample_setup(), 'puzzle', elapsed=None)
        self.assertEqual(d['timer_elapsed'], 0.0)

    def test_does_not_serialize_transient_fields(self):
        # The .bcm sidecar must NOT carry _backup_name / _wizard / callbacks
        # / _start_time (transient / non-JSON-serializable / session-local).
        ctrl = MockController(started=True, start_time=time.time())
        d = build_bcm_dict(ctrl, _sample_setup(), 'checkpoint', elapsed=5.0)
        for transient_key in ('_backup_name', '_wizard', '_on_log',
                              '_start_time'):
            self.assertNotIn(transient_key, d,
                             "transient key %r leaked into .bcm dict" %
                             (transient_key,))

    def test_setup_embedded_verbatim(self):
        # build_bcm_dict embeds the setup_state dict verbatim under 'setup'
        # so an exported puzzle shows the educator's configuration and a
        # checkpoint can re-generate on Restart.
        ctrl = MockController()
        setup = _sample_setup()
        d = build_bcm_dict(ctrl, setup, 'checkpoint', elapsed=1.0)
        self.assertEqual(d['setup'], setup)


# ---- parse_bcm_dict ----

class TestParseBcmDict(unittest.TestCase):
    """5 tests for parse_bcm_dict (the LOAD path: raw JSON -> validated dict)."""

    def test_parse_valid_dict(self):
        payload = {'magic': BCM_MAGIC, 'version': 1, 'kind': 'checkpoint',
                   'target_object': '1ubq', 'started': True,
                   'timer_elapsed': 42.5, 'reveal_count': 1, 'hint_count': 2,
                   'found_color': 'green', 'found_color_rgb': None,
                   'registry': {'version': 1, 'hiders': []},
                   'setup': _sample_setup()}
        d = parse_bcm_dict(json.dumps(payload))
        self.assertEqual(d['magic'], BCM_MAGIC)
        self.assertEqual(d['version'], 1)
        self.assertEqual(d['kind'], 'checkpoint')
        self.assertEqual(d['timer_elapsed'], 42.5)

    def test_parse_wrong_magic_raises(self):
        raw = json.dumps({'magic': 'OTHER', 'version': 1})
        with self.assertRaises(ValueError):
            parse_bcm_dict(raw)

    def test_parse_unsupported_version_raises(self):
        raw = json.dumps({'magic': BCM_MAGIC, 'version': 2})
        with self.assertRaises(ValueError):
            parse_bcm_dict(raw)

    def test_parse_bytes_input(self):
        # bytes input is decoded utf-8 before json.loads.
        payload = {'magic': BCM_MAGIC, 'version': 1, 'kind': 'puzzle'}
        raw_bytes = json.dumps(payload).encode('utf-8')
        d = parse_bcm_dict(raw_bytes)
        self.assertEqual(d['magic'], BCM_MAGIC)
        self.assertEqual(d['kind'], 'puzzle')

    def test_parse_invalid_json_raises(self):
        # JSON parse failure (json.JSONDecodeError is a ValueError subclass)
        # propagates as ValueError.
        with self.assertRaises(ValueError):
            parse_bcm_dict('not json')


# ---- round-trip ----

class TestBcmRoundTrip(unittest.TestCase):
    """2 round-trip tests: build -> dumps -> parse, and parse -> build."""

    def test_build_then_parse_preserves_state(self):
        # build a .bcm dict from a controller, serialize to JSON, parse it
        # back, and assert the scalar fields survive the round trip.
        ctrl = MockController(started=True, reveal_count=3, hint_count=1,
                              found_color='cyan')
        setup = _sample_setup()
        built = build_bcm_dict(ctrl, setup, 'checkpoint', elapsed=99.5)
        parsed = parse_bcm_dict(json.dumps(built))
        for key in ('magic', 'version', 'kind', 'target_object', 'started',
                    'timer_elapsed', 'reveal_count', 'hint_count',
                    'found_color'):
            self.assertEqual(parsed[key], built[key],
                             "scalar %r not preserved through round trip" %
                             (key,))
        # The embedded registry + setup should also survive verbatim.
        self.assertEqual(parsed['registry'], built['registry'])
        self.assertEqual(parsed['setup'], built['setup'])

    def test_parse_then_build_round_trip(self):
        # Start from a hand-crafted .bcm JSON (the canonical structure a
        # parse_bcm_dict consumer would receive), parse it, then build a
        # fresh dict from a controller whose attrs match the parsed scalars.
        # The rebuilt dict's controller-derived scalars must match the
        # parsed dict's — proving build_bcm_dict produces the structure
        # parse_bcm_dict expects (symmetric contract).
        original = {'magic': BCM_MAGIC, 'version': BCM_VERSION,
                    'kind': 'checkpoint', 'target_object': '1ubq',
                    'started': True, 'timer_elapsed': 12.25,
                    'reveal_count': 2, 'hint_count': 0,
                    'found_color': 'green', 'found_color_rgb': None,
                    'registry': {'version': 1, 'hiders': []},
                    'setup': _sample_setup()}
        parsed = parse_bcm_dict(json.dumps(original))
        ctrl = MockController(target_obj=parsed['target_object'],
                              started=parsed['started'],
                              reveal_count=parsed['reveal_count'],
                              hint_count=parsed['hint_count'],
                              found_color=parsed['found_color'])
        rebuilt = build_bcm_dict(ctrl, parsed['setup'], parsed['kind'],
                                 elapsed=parsed['timer_elapsed'])
        for key in ('magic', 'version', 'kind', 'target_object', 'started',
                    'timer_elapsed', 'reveal_count', 'hint_count',
                    'found_color', 'found_color_rgb'):
            self.assertEqual(rebuilt[key], parsed[key],
                             "rebuilt %r != parsed %r" %
                             (rebuilt[key], parsed[key]))


if __name__ == '__main__':
    unittest.main()
