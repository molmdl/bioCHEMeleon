"""Tests for biochemeleon.game.GameController Phase-4 extensions.

Tests the click-to-find LOGIC: on_pick / win / set_callbacks / _remaining.
The tests construct GameController WITHOUT calling start() (start() needs
real cmd — the mocked cmd.identify returns a MagicMock that fails the
``assert len(ids) == 1`` in mutation). Instead the registry is MANUALLY
populated and mock callbacks verify the play-loop behavior.

pymol / pymol.Qt are stubbed via sys.modules (same pattern as
tests/test_registry.py lines 1-24) so biochemeleon.* imports succeed in
WSL without PyMOL, and cmd.color is a no-op mock whose call_count can be
inspected.

Run: python3.6 -m unittest tests.test_game_controller -v
Or:  python3.6 tests/test_game_controller.py
"""
import os
import sys
import unittest
from unittest.mock import MagicMock

# Stub pymol so importing biochemeleon.* (whose __init__.py does
# `from pymol.Qt import ...`) doesn't fail in WSL without PyMOL.
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()

# Ensure repo root is on sys.path when run as a script
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from biochemeleon import game
from biochemeleon.game import GameController
from biochemeleon.registry import HIDER_STATUS_HIDDEN, HIDER_STATUS_FOUND


class TestGameControllerOnPick(unittest.TestCase):
    """Test GameController.on_pick / win / set_callbacks / _remaining (Phase 4).

    Each test builds a GameController('1ubq') WITHOUT calling start() and
    manually populates the registry. Mock callbacks (on_log /
    on_remaining_changed / on_win) verify the play-loop wiring. The mocked
    cmd.color is inspected to confirm recolor behavior.
    """

    def setUp(self):
        """Build a fresh GameController with a clean mock cmd history."""
        self.gc = GameController('1ubq')
        # Reset mock cmd call history (shared via sys.modules) so call_count
        # assertions are isolated per test.
        game.cmd.reset_mock()

    # ---- miss (non-hider click) ----

    def test_miss(self):
        """on_pick(999) where 999 not registered -> 'Miss!' log, no mark/color/win.

        LOOP-01: clicking a non-hider does nothing harmful.
        """
        self.gc.registry.register('1ubq', 100, 'spheres')
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)

        self.gc.on_pick(999)

        log.assert_called_once_with("Miss!")
        rem.assert_not_called()
        win_cb.assert_not_called()
        # Record 100 still 'hidden' (mark_found NOT called)
        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        # cmd.color NOT called (miss = no recolor)
        game.cmd.color.assert_not_called()

    # ---- found (last hider -> win) ----

    def test_found(self):
        """on_pick(hidden_id) -> status='found', color green, log/rem called, win fires.

        With only 1 hider registered, finding it means remaining==0, so
        win() fires and on_win is called.
        """
        self.gc.registry.register('1ubq', 100, 'spheres')
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)
        self.gc._start_time = 1000.0

        self.gc.on_pick(100)

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with('green', "1ubq and id 100")
        rem.assert_called_once_with(0)
        win_cb.assert_called_once()

    # ---- already found (no double-count) ----

    def test_already_found(self):
        """on_pick(already_found_id) -> 'Already found!' log, no mark/color/rem/win.

        No double-count: status stays 'found', cmd.color NOT called again.
        """
        self.gc.registry.register('1ubq', 100, 'spheres',
                                  status=HIDER_STATUS_FOUND)
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)

        color_count_before = game.cmd.color.call_count
        self.gc.on_pick(100)

        log.assert_called_once_with("Already found!")
        rem.assert_not_called()
        win_cb.assert_not_called()
        # cmd.color call_count did NOT increase
        self.assertEqual(game.cmd.color.call_count, color_count_before)
        # Status unchanged
        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)

    # ---- found not last (no win) ----

    def test_found_not_last(self):
        """on_pick(hidden) with 2 hiders -> found, rem=1, win NOT called."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc.registry.register('1ubq', 101, 'spheres')
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)

        self.gc.on_pick(100)

        rec100 = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec100.status, HIDER_STATUS_FOUND)
        rec101 = self.gc.registry.get('1ubq', 101)
        self.assertEqual(rec101.status, HIDER_STATUS_HIDDEN)
        rem.assert_called_once_with(1)
        win_cb.assert_not_called()

    # ---- win with no wizard ----

    def test_win_no_wizard(self):
        """on_pick(last hider) with _wizard=None -> win_cb(float), no error.

        _wizard is None so no deactivate is attempted; no error raised.
        """
        self.gc.registry.register('1ubq', 100, 'spheres')
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)
        self.gc._start_time = 1000.0

        self.gc.on_pick(100)

        win_cb.assert_called_once()
        elapsed = win_cb.call_args[0][0]
        self.assertIsInstance(elapsed, float)

    # ---- win with wizard ----

    def test_win_with_wizard(self):
        """on_pick(last hider) with _wizard set -> win_cb fires; wizard NOT
        deactivated in win() (deferred to GUI _finish_win).

        Deactivation moved from win() to the GUI's delayed _finish_win
        callback so the last hider's green color can flush to the viewer
        before wizard teardown. win() must NOT deactivate the wizard;
        gc._wizard stays set (the GUI clears it in _finish_win).
        """
        self.gc.registry.register('1ubq', 100, 'spheres')
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)
        self.gc._start_time = 1000.0
        wiz = MagicMock()
        self.gc._wizard = wiz

        self.gc.on_pick(100)

        win_cb.assert_called_once()
        # Deactivation moved to GUI _finish_win (not win()), so win() must
        # NOT deactivate the wizard here.
        wiz.deactivate.assert_not_called()
        # gc._wizard stays set -- the GUI clears it in _finish_win.
        self.assertIs(self.gc._wizard, wiz)

    # ---- _remaining ----

    def test_remaining(self):
        """_remaining() on 3-record registry (2 hidden, 1 found) -> 2."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc.registry.register('1ubq', 101, 'spheres')
        self.gc.registry.register('1ubq', 102, 'spheres',
                                  status=HIDER_STATUS_FOUND)

        self.assertEqual(self.gc._remaining(), 2)

    # ---- set_callbacks defaults ----

    def test_set_callbacks_defaults(self):
        """set_callbacks() with all None -> no-op lambdas return None, no error."""
        gc2 = GameController('1ubq')
        gc2.set_callbacks()
        self.assertIsNone(gc2._on_log("x"))
        self.assertIsNone(gc2._on_remaining_changed(1))
        self.assertIsNone(gc2._on_win(0.0))


if __name__ == '__main__':
    unittest.main(verbosity=2)
