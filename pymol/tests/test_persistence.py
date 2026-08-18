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
import shutil
import tempfile
import time
import unittest
import zipfile
from unittest.mock import MagicMock

# Stub pymol so importing biochemeleon.* (whose __init__.py does
# `from pymol.Qt import ...`) doesn't fail in WSL without PyMOL.
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()

# Ensure repo root is on sys.path when run as a script
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from biochemeleon.persistence import (
    build_bcm_dict, parse_bcm_dict, apply_bcm_dict,
    write_bcmz, read_bcmz, resolve_target,
    BCM_MAGIC, BCM_VERSION,
)
from biochemeleon.registry import (
    HiderRegistry, HIDER_STATUS_FOUND, HIDER_STATUS_HIDDEN, ReconcileMismatches,
)


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


# ---- apply_bcm_dict (Plan 03) ----

class TestApplyBcmDict(unittest.TestCase):
    """6 tests for apply_bcm_dict (the LOAD path: .bcm dict -> controller).

    Uses MockController with a sentinel-rebuilt registry (call
    reconstruct_from_sentinels first), then apply_bcm_dict sets the
    controller's state fields + reconciles the registry. Pure (no pymol).
    """

    def _rebuilt_ctrl(self, keys=None):
        """Build a MockController with a sentinel-rebuilt registry.

        Defaults to [('o', 1), ('o', 2), ('o', 3)] — the canonical
        3-sentinel fixture mirroring test_registry.py's
        TestReconcileFromBcm._rebuilt.
        """
        if keys is None:
            keys = [('o', 1), ('o', 2), ('o', 3)]
        ctrl = MockController(target_obj='o')
        ctrl.registry.reconstruct_from_sentinels(lambda: keys)
        return ctrl

    def test_sets_controller_state_fields(self):
        """apply_bcm_dict sets _reveal_count, _hint_count, _found_color
        from the .bcm dict.
        """
        ctrl = self._rebuilt_ctrl()
        bcm = {
            'magic': BCM_MAGIC, 'version': BCM_VERSION,
            'reveal_count': 1, 'hint_count': 2, 'found_color': 'cyan',
            'registry': {'version': 1, 'hiders': []},
        }
        apply_bcm_dict(ctrl, bcm)
        self.assertEqual(ctrl._reveal_count, 1)
        self.assertEqual(ctrl._hint_count, 2)
        self.assertEqual(ctrl._found_color, 'cyan')

    def test_reconciles_registry(self):
        """3 sentinels + 3 .bcm hiders (1 found, reps spheres/sticks/cartoon)
        -> registry records have real rep + 1 found; mismatches empty.
        """
        ctrl = self._rebuilt_ctrl()
        bcm = {
            'magic': BCM_MAGIC, 'version': BCM_VERSION,
            'reveal_count': 0, 'hint_count': 0, 'found_color': 'green',
            'registry': {'version': 1, 'hiders': [
                {'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'found'},
                {'id': 2, 'object': 'o', 'rep': 'sticks', 'status': 'hidden'},
                {'id': 3, 'object': 'o', 'rep': 'cartoon', 'status': 'hidden'},
            ]},
        }
        mismatches = apply_bcm_dict(ctrl, bcm)
        self.assertEqual(ctrl.registry.get('o', 1).rep, 'spheres')
        self.assertEqual(ctrl.registry.get('o', 1).status, HIDER_STATUS_FOUND)
        self.assertEqual(ctrl.registry.get('o', 2).rep, 'sticks')
        self.assertEqual(ctrl.registry.get('o', 3).rep, 'cartoon')
        self.assertEqual(mismatches.missing_from_bcm, [])
        self.assertEqual(mismatches.missing_from_pse, [])
        self.assertEqual(mismatches.bad_rep, [])

    def test_refuses_wrong_magic(self):
        """apply_bcm_dict with magic='OTHER' -> ValueError."""
        ctrl = self._rebuilt_ctrl()
        bcm = {'magic': 'OTHER', 'version': BCM_VERSION,
               'registry': {'hiders': []}}
        with self.assertRaises(ValueError):
            apply_bcm_dict(ctrl, bcm)

    def test_refuses_unsupported_version(self):
        """apply_bcm_dict with version=2 (> BCM_VERSION) -> ValueError."""
        ctrl = self._rebuilt_ctrl()
        bcm = {'magic': BCM_MAGIC, 'version': 2, 'registry': {'hiders': []}}
        with self.assertRaises(ValueError):
            apply_bcm_dict(ctrl, bcm)

    def test_tolerates_missing_registry_key(self):
        """apply_bcm_dict with no 'registry' key -> reconcile_with_bcm([])
        -> all sentinel records stay rep=None, hidden (graceful).
        """
        ctrl = self._rebuilt_ctrl()
        bcm = {'magic': BCM_MAGIC, 'version': BCM_VERSION}  # no 'registry'
        mismatches = apply_bcm_dict(ctrl, bcm)
        for rec in ctrl.registry.all():
            self.assertIsNone(rec.rep)
            self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(len(mismatches.missing_from_bcm), 3)

    def test_tolerates_missing_state_fields(self):
        """apply_bcm_dict with no 'reveal_count' -> defaults to 0; no
        'found_color' -> 'green'.
        """
        ctrl = self._rebuilt_ctrl()
        bcm = {'magic': BCM_MAGIC, 'version': BCM_VERSION,
               'registry': {'hiders': []}}
        apply_bcm_dict(ctrl, bcm)
        self.assertEqual(ctrl._reveal_count, 0)
        self.assertEqual(ctrl._found_color, 'green')


# ---- write_bcmz / read_bcmz (Plan 03) ----

class TestWriteReadBcmz(unittest.TestCase):
    """3 tests for the .bcmz archive write/read round-trip.

    Uses tempfile.mkdtemp for the .bcmz + .pse paths. Writes a dummy
    .pse file (empty bytes — testing the zip mechanics, not PyMOL).
    """

    def test_write_then_read_round_trip(self):
        """write_bcmz -> read_bcmz: bcm scalar fields preserved + extracted
        pse_path exists with the right content.
        """
        tmpdir = tempfile.mkdtemp(prefix='bchm_test_')
        self.addCleanup(shutil.rmtree, tmpdir, True)
        bcmz_path = os.path.join(tmpdir, 'test.bcmz')
        pse_path = os.path.join(tmpdir, 'game.pse')
        pse_content = b'FAKE_PSE_CONTENT'
        with open(pse_path, 'wb') as f:
            f.write(pse_content)
        ctrl = MockController()
        bcm = build_bcm_dict(ctrl, _sample_setup(), 'checkpoint', elapsed=42.5)
        write_bcmz(bcmz_path, bcm, pse_path)
        read_pse_path, read_bcm = read_bcmz(bcmz_path)
        self.addCleanup(shutil.rmtree, os.path.dirname(read_pse_path), True)
        for key in ('magic', 'version', 'kind', 'target_object', 'started',
                    'timer_elapsed', 'reveal_count', 'hint_count',
                    'found_color'):
            self.assertEqual(read_bcm[key], bcm[key],
                             "scalar %r not preserved through bcmz round trip"
                             % (key,))
        self.assertTrue(os.path.exists(read_pse_path))
        with open(read_pse_path, 'rb') as f:
            self.assertEqual(f.read(), pse_content)

    def test_read_bcmz_missing_bcm_raises(self):
        """Archive with only game.pse (no game.bcm) -> ValueError."""
        tmpdir = tempfile.mkdtemp(prefix='bchm_test_')
        self.addCleanup(shutil.rmtree, tmpdir, True)
        bcmz_path = os.path.join(tmpdir, 'bad.bcmz')
        with zipfile.ZipFile(bcmz_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.writestr('game.pse', b'FAKE')
        with self.assertRaises(ValueError):
            read_bcmz(bcmz_path)

    def test_read_bcmz_missing_pse_raises(self):
        """Archive with only game.bcm (no game.pse) -> ValueError."""
        tmpdir = tempfile.mkdtemp(prefix='bchm_test_')
        self.addCleanup(shutil.rmtree, tmpdir, True)
        bcmz_path = os.path.join(tmpdir, 'bad.bcmz')
        bcm_json = json.dumps({'magic': BCM_MAGIC, 'version': BCM_VERSION})
        with zipfile.ZipFile(bcmz_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.writestr('game.bcm', bcm_json)
        with self.assertRaises(ValueError):
            read_bcmz(bcmz_path)


# ---- resolve_target (Plan 03) ----

class TestResolveTarget(unittest.TestCase):
    """3 tests for resolve_target (the imported target object name resolver)."""

    def test_prefer_bcm_target_object(self):
        """bcm has target_object='1ubq' and it's in loaded_molecules -> '1ubq'."""
        bcm = {'target_object': '1ubq'}
        result = resolve_target(bcm, set(), ['1ubq'])
        self.assertEqual(result, '1ubq')

    def test_fallback_diff(self):
        """bcm target_object='missing' not in loaded; names_before=[] so the
        diff picks up the single new object '1ubq'.
        """
        bcm = {'target_object': 'missing'}
        result = resolve_target(bcm, set(), ['1ubq'])
        self.assertEqual(result, '1ubq')

    def test_returns_none_if_ambiguous(self):
        """bcm target_object='missing'; 2 new objects -> ambiguous -> None."""
        bcm = {'target_object': 'missing'}
        result = resolve_target(bcm, set(), ['obj_a', 'obj_b'])
        self.assertIsNone(result)


# ---- build -> apply round-trip (Plan 03) ----

class TestBuildApplyRoundTrip(unittest.TestCase):
    """1 full round-trip test: build_bcm_dict -> apply_bcm_dict.

    Builds a .bcm from ctrl1 (populated registry + state fields), then
    sentinel-rebuilds ctrl2's registry + applies the .bcm. Asserts
    ctrl2's state fields + registry records match ctrl1's.

    NOTE: The plan called this class ``TestBcmRoundTrip``, but a class
    with that name already exists above (2 build<->parse round-trip
    tests). Reusing the name would shadow the existing class + silently
    drop those 2 tests (count would be 26, not the plan's 28). Renamed
    to ``TestBuildApplyRoundTrip`` to avoid the collision (Rule 1 fix).
    """

    def test_build_then_apply_preserves_state(self):
        ctrl1 = MockController(target_obj='1ubq', started=True,
                               reveal_count=3, hint_count=1,
                               found_color='cyan')
        ctrl1.registry.register('1ubq', 101, 'spheres',
                                status=HIDER_STATUS_FOUND)
        ctrl1.registry.register('1ubq', 102, 'sticks',
                                status=HIDER_STATUS_HIDDEN)
        ctrl1.registry.register('1ubq', 103, 'cartoon',
                                status=HIDER_STATUS_FOUND)
        setup = _sample_setup()
        bcm = build_bcm_dict(ctrl1, setup, 'checkpoint', elapsed=42.5)
        # ctrl2: sentinel-rebuilt registry (fake keys matching ctrl1's ids)
        ctrl2 = MockController(target_obj='1ubq')
        ctrl2.registry.reconstruct_from_sentinels(
            lambda: [('1ubq', 101), ('1ubq', 102), ('1ubq', 103)])
        apply_bcm_dict(ctrl2, bcm)
        # State fields preserved
        self.assertEqual(ctrl2._reveal_count, ctrl1._reveal_count)
        self.assertEqual(ctrl2._hint_count, ctrl1._hint_count)
        self.assertEqual(ctrl2._found_color, ctrl1._found_color)
        # Registry records match (id/object/rep/status)
        for orig, rebuilt in zip(ctrl1.registry.all(), ctrl2.registry.all()):
            self.assertEqual(rebuilt.id, orig.id)
            self.assertEqual(rebuilt.object, orig.object)
            self.assertEqual(rebuilt.rep, orig.rep)
            self.assertEqual(rebuilt.status, orig.status)


# ---- alt-conf .bcm round-trip (Plan 11-03, Task 1) ----

class TestBcmAltconfRoundtrip(unittest.TestCase):
    """6 tests proving the 3 Phase 11 alt-conf fields (is_altconf,
    endpoint_resvs, alt_tag) survive the full .bcm persistence chain
    (build_bcm_dict -> parse_bcm_dict -> apply_bcm_dict) with NO version
    bump, AND that list->tuple coercion happens on the apply path.

    Reuses the MockController + _sample_setup() helpers (do NOT
    duplicate them). persistence.py is a PASS-THROUGH layer for the new
    fields (build_bcm_dict calls controller.registry.to_dict();
    apply_bcm_dict calls registry.reconcile_with_bcm) — both were
    extended in Plan 02 to carry the 3 fields. These tests prove the
    END-TO-END chain preserves them, closing research Open Risk 3 (.bcm
    round-trip of alt-conf metadata) at the pure WSL tier.
    """

    def test_build_carries_altconf_fields(self):
        """build_bcm_dict carries is_altconf/endpoint_resvs/alt_tag through
        the registry.to_dict() passthrough; version stays 1 (NO bump).
        endpoint_resvs is a LIST in the dict (JSON form; to_dict emits
        list(self.endpoint_resvs)).
        """
        mc = MockController()
        reg = mc.registry
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        d = build_bcm_dict(mc, _sample_setup(), 'checkpoint')
        h = d['registry']['hiders'][0]
        self.assertIs(h['is_altconf'], True)
        self.assertEqual(h['endpoint_resvs'], [2, 4])   # list (JSON form)
        self.assertEqual(h['alt_tag'], 'B')
        self.assertEqual(d['version'], 1)               # NO version bump

    def test_build_omits_defaults(self):
        """A NON-alt-conf record (sphere) emits NONE of the 3 alt-conf keys
        (compact sidecar; backward-compatible with Phase 8 readers).
        """
        mc = MockController()
        reg = mc.registry
        reg.register('1ubq', 101, 'spheres')
        d = build_bcm_dict(mc, _sample_setup(), 'checkpoint')
        h = d['registry']['hiders'][0]
        self.assertNotIn('is_altconf', h)
        self.assertNotIn('endpoint_resvs', h)
        self.assertNotIn('alt_tag', h)

    def test_parse_accepts_altconf_fields(self):
        """parse_bcm_dict does NOT reject the 3 new optional fields (no
        version bump, no schema validation of per-hider fields). The
        parsed dict carries is_altconf=True through; version stays 1.
        """
        mc = MockController()
        reg = mc.registry
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        d = build_bcm_dict(mc, _sample_setup(), 'checkpoint')
        raw = json.dumps(d)
        d2 = parse_bcm_dict(raw)
        self.assertIs(d2['registry']['hiders'][0]['is_altconf'], True)
        self.assertEqual(d2['version'], 1)   # parse does NOT reject new fields

    def test_apply_restores_altconf_on_sentinel_rebuild(self):
        """apply_bcm_dict -> reconcile_with_bcm restores the 3 alt-conf
        fields on a sentinel-rebuilt registry (rep=None -> 'cartoon').
        endpoint_resvs is coerced list->tuple. Mismatches empty (perfect
        match between sentinel and .bcm entry).
        """
        mc = MockController()
        reg = mc.registry
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        d = build_bcm_dict(mc, _sample_setup(), 'checkpoint')
        # mc2: sentinel-rebuilt registry (rep=None, default alt-conf fields)
        mc2 = MockController()
        mc2.registry.register('1ubq', 100, rep=None)
        mm = apply_bcm_dict(mc2, d)
        rec = mc2.registry.get('1ubq', 100)
        self.assertIs(rec.is_altconf, True)
        self.assertEqual(rec.endpoint_resvs, (2, 4))   # TUPLE (list->tuple)
        self.assertEqual(rec.alt_tag, 'B')
        self.assertEqual(rec.rep, 'cartoon')            # reconcile restores rep
        self.assertIsInstance(mm, ReconcileMismatches)
        self.assertEqual(mm.missing_from_bcm, [])
        self.assertEqual(mm.missing_from_pse, [])
        self.assertEqual(mm.bad_rep, [])

    def test_apply_restores_altconf_mixed_registry(self):
        """A mixed registry (alt-conf id 100 + sphere id 101) round-trips:
        the alt-conf record gets is_altconf=True/endpoint_resvs=(2,4)/
        alt_tag='B' AND the sphere gets the DEFAULTS (is_altconf=False/
        endpoint_resvs=None/alt_tag='') — the sphere was never alt-conf.
        """
        mc = MockController()
        reg = mc.registry
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        reg.register('1ubq', 101, 'spheres')
        d = build_bcm_dict(mc, _sample_setup(), 'checkpoint')
        mc2 = MockController()
        mc2.registry.register('1ubq', 100, rep=None)
        mc2.registry.register('1ubq', 101, rep=None)
        apply_bcm_dict(mc2, d)
        r100 = mc2.registry.get('1ubq', 100)
        r101 = mc2.registry.get('1ubq', 101)
        self.assertIs(r100.is_altconf, True)
        self.assertEqual(r100.endpoint_resvs, (2, 4))
        self.assertEqual(r100.alt_tag, 'B')
        self.assertIs(r101.is_altconf, False)
        self.assertIsNone(r101.endpoint_resvs)
        self.assertEqual(r101.alt_tag, '')

    def test_altconf_endpoint_resvs_json_list_roundtrip(self):
        """endpoint_resvs serializes as a JSON list (JSON has no tuples);
        parse_bcm_dict returns it as a list; apply_bcm_dict coerces it
        back to a TUPLE on the record (so rv1 < resv < rv2 works — lists
        fail < in py3).
        """
        mc = MockController()
        reg = mc.registry
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        d = build_bcm_dict(mc, _sample_setup(), 'checkpoint')
        raw = json.dumps(d)
        d2 = parse_bcm_dict(raw)
        # Parsed endpoint_resvs is a list (JSON has no tuples)
        self.assertEqual(d2['registry']['hiders'][0]['endpoint_resvs'], [2, 4])
        self.assertIsInstance(d2['registry']['hiders'][0]['endpoint_resvs'], list)
        # apply_bcm_dict coerces the list back to a tuple on the record
        mc2 = MockController()
        mc2.registry.register('1ubq', 100, rep=None)
        apply_bcm_dict(mc2, d2)
        rec = mc2.registry.get('1ubq', 100)
        self.assertIsInstance(rec.endpoint_resvs, tuple)
        self.assertEqual(rec.endpoint_resvs, (2, 4))


# ---- alt-conf backward-compat (Plan 11-03, Task 2) ----

class TestBcmAltconfBackwardCompat(unittest.TestCase):
    """3 tests proving a Phase 8 sidecar (NO alt-conf fields) still
    round-trips on Phase 11 code and degrades to defaults (backward
    compatible), AND that the no-version-bump contract holds.

    Research §8: Phase 11 adds OPTIONAL fields, NOT a schema version
    bump. A Phase 8 sidecar (made BEFORE Phase 11) has no
    is_altconf/endpoint_resvs/alt_tag keys -> from_dict/reconcile read
    them with defaults (is_altconf=False, endpoint_resvs=None,
    alt_tag='') -> the game loads as non-altconf (degraded but playable:
    only the anchor CA scores; the 'click any middle atom' UX is lost
    until the .bcm is re-saved on Phase 11 code).
    """

    def test_phase8_sidecar_loads_with_defaults(self):
        """A hand-constructed Phase 8 sidecar (hider dict with ONLY
        object/id/rep/status — NO is_altconf/endpoint_resvs/alt_tag)
        parses + applies on Phase 11 code, restoring the record with
        DEFAULT alt-conf values (is_altconf=False, endpoint_resvs=None,
        alt_tag=''). Proves a Phase 8 save made BEFORE Phase 11 still
        loads on Phase 11 code (backward compatible).
        """
        # Hand-construct a Phase 8-style .bcm dict (no alt-conf fields)
        d = {
            'magic': BCM_MAGIC, 'version': 1, 'kind': 'checkpoint',
            'target_object': '1ubq', 'started': True, 'timer_elapsed': 0.0,
            'reveal_count': 0, 'hint_count': 0, 'found_color': 'green',
            'found_color_rgb': None,
            'registry': {'version': 1, 'hiders': [
                {'id': 100, 'object': '1ubq', 'rep': 'cartoon',
                 'status': 'hidden'},
            ]},
            'setup': _sample_setup(),
        }
        raw = json.dumps(d)
        d2 = parse_bcm_dict(raw)   # accepts (version 1, no rejection)
        mc2 = MockController()
        mc2.registry.register('1ubq', 100, rep=None)   # sentinel-rebuilt
        apply_bcm_dict(mc2, d2)
        rec = mc2.registry.get('1ubq', 100)
        self.assertIs(rec.is_altconf, False)   # default
        self.assertIsNone(rec.endpoint_resvs)  # default
        self.assertEqual(rec.alt_tag, '')      # default
        # rep is still restored from the Phase 8 sidecar (non-altconf field)
        self.assertEqual(rec.rep, 'cartoon')

    def test_phase11_sidecar_loads_on_phase8_reconcile(self):
        """reconcile_with_bcm does NOT raise when the 3 alt-conf fields
        are PRESENT (Phase 11 sidecar) AND when ABSENT (Phase 8 sidecar)
        — no KeyError on .get (the _altconf_fields_from_hider_dict
        helper uses h.get(...) with defaults). Both return a
        ReconcileMismatches (degraded is playable, never raises).
        """
        # Phase 11 sidecar WITH alt-conf fields -> reconcile must NOT raise
        mc_a = MockController()
        mc_a.registry.register('1ubq', 100, rep=None)
        hiders_with = [
            {'id': 100, 'object': '1ubq', 'rep': 'cartoon', 'status': 'hidden',
             'is_altconf': True, 'endpoint_resvs': [2, 4], 'alt_tag': 'B'},
        ]
        mm_a = mc_a.registry.reconcile_with_bcm(hiders_with)
        self.assertIsInstance(mm_a, ReconcileMismatches)
        self.assertIs(mc_a.registry.get('1ubq', 100).is_altconf, True)

        # Phase 8 sidecar WITHOUT alt-conf fields -> reconcile must NOT raise
        mc_b = MockController()
        mc_b.registry.register('1ubq', 100, rep=None)
        hiders_without = [
            {'id': 100, 'object': '1ubq', 'rep': 'cartoon', 'status': 'hidden'},
        ]
        mm_b = mc_b.registry.reconcile_with_bcm(hiders_without)
        self.assertIsInstance(mm_b, ReconcileMismatches)
        self.assertIs(mc_b.registry.get('1ubq', 100).is_altconf, False)

    def test_no_version_bump(self):
        """build_bcm_dict always emits version == 1 for BOTH alt-conf and
        non-alt-conf controllers (Phase 11 adds OPTIONAL fields, NOT a
        schema version bump; research §8). parse_bcm_dict rejecting
        version > 1 is covered by the existing
        test_parse_unsupported_version_raises (confirmed still green by
        the full suite run — not duplicated here).
        """
        # Alt-conf controller
        mc_alt = MockController()
        mc_alt.registry.register('1ubq', 100, 'cartoon', is_altconf=True,
                                 endpoint_resvs=(2, 4), alt_tag='B')
        d_alt = build_bcm_dict(mc_alt, _sample_setup(), 'checkpoint')
        self.assertEqual(d_alt['version'], 1)
        # Non-alt-conf controller
        mc_plain = MockController()
        mc_plain.registry.register('1ubq', 101, 'spheres')
        d_plain = build_bcm_dict(mc_plain, _sample_setup(), 'checkpoint')
        self.assertEqual(d_plain['version'], 1)


if __name__ == '__main__':
    unittest.main()
