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


class TestOnPickFragment(unittest.TestCase):
    """Test GameController.on_pick fragment (cartoon/ribbon) scoring truth table
    (Phase 11 single-state refactor).

    The single-state cartoon/ribbon hider is a REAL backbone copy on a NEW chain
    'H' with a NEW resi range. cmd.create preserves source ids (backup=snapshot),
    so the copy SHARES its id with the real-trace CA at the same segment position;
    the copy's resv (NEW range) differs from the real CA's resv (original range).
    on_pick(picked_id, alt, resv) does a dual lookup (anchor-id then
    get_altconf_by_resv, dormant for new games) + gates scoring on
    ``rec.endpoint_resvs is not None AND rv1 < resv < rv2`` (resv-range gate; NO
    alt check -- alt-conf is gone). The resv gate scores the hider (resv in the
    NEW range) and misses the real trace (resv in the ORIGINAL range). Only the
    anchor middle-CA is registered (like main/legacy cartoon), so a non-anchor
    middle atom (N/C/O) misses. These 7 tests encode the truth table + sphere
    backward compat.

    Each test builds a GameController('1ubq') WITHOUT calling start() and
    manually populates the registry with a fragment record (is_altconf=False,
    endpoint_resvs=NEW range, alt_tag=''). Mock callbacks verify the wiring.
    """

    def setUp(self):
        """Build a fresh GameController with a clean mock cmd history."""
        self.gc = GameController('1ubq')
        game.cmd.reset_mock()

    # NEW resi range mirrors mutation.cartoon_hider_resi_range (offset 10000):
    # real segment resi 2-4 -> NEW resi 10002-10004; anchor (middle) at 10003.
    _NEW_START, _NEW_END = 10002, 10004
    _NEW_MID = 10003

    def _register_fragment(self, hider_id=100,
                           endpoint_resvs=(_NEW_START, _NEW_END),
                           status=HIDER_STATUS_HIDDEN, rep='cartoon',
                           obj='1ubq'):
        """Helper: register one fragment (cartoon/ribbon) hider record with the
        new single-state fields (is_altconf=False, alt_tag='')."""
        return self.gc.registry.register(
            obj, hider_id, rep, status=status,
            endpoint_resvs=endpoint_resvs)

    # ---- 1. anchor middle CA scores ----

    def test_fragment_anchor_middle_ca_scores(self):
        """on_pick(anchor_id, resv=NEW_MID) where NEW_MID is strictly between
        rv1=NEW_START and rv2=NEW_END -> status FOUND; cmd.color 'green' with the
        GAME middle-range selection 'segi GAME and resi <NEW_MID>-<NEW_MID>'.

        The anchor CA is the registered middle CA; clicking it scores via the
        anchor-id lookup (registry.get hit) + the resv-range gate (resv in range)."""
        self._register_fragment(hider_id=100)
        log = MagicMock()
        rem = MagicMock()
        self.gc.set_callbacks(log, rem)

        self.gc.on_pick(100, alt='', resv=self._NEW_MID)

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with(
            'green', "1ubq and segi GAME and resi %d-%d" % (
                self._NEW_MID, self._NEW_MID))
        log.assert_called_once()
        self.assertIn("Found one!", log.call_args[0][0])
        rem.assert_called_once_with(0)

    # ---- 2. non-anchor middle atom MISSES (only the anchor CA is registered) ----

    def test_fragment_non_anchor_middle_atom_misses(self):
        """on_pick(non_registered_id=200, resv=NEW_MID) -> registry.get(200) is
        None (only the anchor 100 is registered) -> get_altconf_by_resv(NEW_MID)
        is dormant (is_altconf=False -> returns None) -> 'Miss!'; status HIDDEN.

        Like main/legacy cartoon: only the clickable C-alpha is registered, so
        clicking another backbone atom (N/C/O) of the fragment misses. (The old
        alt-conf 'click ANY middle atom' feature is dropped with alt-conf.)"""
        self._register_fragment(hider_id=100)
        log = MagicMock()
        self.gc.set_callbacks(log)

        self.gc.on_pick(200, alt='', resv=self._NEW_MID)

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        log.assert_called_once_with("Miss!")
        game.cmd.color.assert_not_called()

    # ---- 3. endpoint miss ----

    def test_fragment_endpoint_miss(self):
        """on_pick(100, resv=NEW_START) where resv == rv1 (endpoint) -> gate
        'rv1 < resv < rv2' is False -> 'Miss!'; status stays HIDDEN.

        Endpoints coincide with the real trace (blend); they are NOT clickable."""
        self._register_fragment(hider_id=100)
        log = MagicMock()
        self.gc.set_callbacks(log)

        self.gc.on_pick(100, alt='', resv=self._NEW_START)

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        log.assert_called_once_with("Miss!")
        game.cmd.color.assert_not_called()

    # ---- 4. real-trace miss (shared id, resv NOT in NEW range) ----

    def test_fragment_real_trace_miss(self):
        """on_pick(100, resv=3) -- clicking the REAL trace (shares the anchor
        id 100 via cmd.create id-preservation) at the ORIGINAL resv 3, which is
        NOT in the NEW range (10002-10004) -> resv gate 'rv1 < resv < rv2' is
        False -> 'Miss!'; status HIDDEN.

        This is the load-bearing scoring fix: the copy shares its id with the
        real-trace CA, so id alone can't distinguish. The resv gate (NEW resi
        range) rejects the real trace (original resv). The single-state refactor
        replaces the old alt='B' alt-gate with the resv gate."""
        self._register_fragment(hider_id=100)
        log = MagicMock()
        self.gc.set_callbacks(log)

        self.gc.on_pick(100, alt='', resv=3)  # 3 = original resv, not in NEW range

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        log.assert_called_once_with("Miss!")
        game.cmd.color.assert_not_called()

    # ---- 5. no resv miss (backward-compat call without resv) ----

    def test_fragment_no_resv_miss(self):
        """on_pick(100) (no resv) on a fragment record -> gate 'resv is None' ->
        'Miss!'; status HIDDEN. A bare on_pick(id) call on a fragment record does
        NOT score -- the resv gate requires resv to confirm the click is in the
        NEW middle range. Backward-compatible: old callers passing on_pick(id) on
        non-fragment (sphere/line/stick) records still score (gate skipped)."""
        self._register_fragment(hider_id=100)
        log = MagicMock()
        self.gc.set_callbacks(log)

        self.gc.on_pick(100)

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        log.assert_called_once_with("Miss!")
        game.cmd.color.assert_not_called()

    # ---- 6. already-found check BEFORE the resv gate (order matters) ----

    def test_fragment_already_found(self):
        """on_pick(100, resv=NEW_MID) on an already-found fragment record ->
        'Already found!' (the found-check runs BEFORE the resv gate; order
        matters -- a found hider should not re-enter the gate)."""
        self._register_fragment(hider_id=100, status=HIDER_STATUS_FOUND)
        log = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)

        self.gc.on_pick(100, alt='', resv=self._NEW_MID)

        log.assert_called_once_with("Already found!")
        rem.assert_not_called()
        win_cb.assert_not_called()
        game.cmd.color.assert_not_called()

    # ---- 7. sphere backward compat (gate skipped, colors by id) ----

    def test_sphere_backward_compat(self):
        """on_pick(100) on a non-fragment sphere record -> endpoint_resvs is
        None -> gate skipped -> _mark_found(rec.id=100, rec) -> else branch
        (by id) -> cmd.color('green', '1ubq and id 100'). MUST match the existing
        test_found assertion (backward-compatible signature + behavior)."""
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


class TestMarkFoundAltconf(unittest.TestCase):
    """Test GameController._mark_found is_altconf branch (Phase 11, Pitfall 14).

    For alt-conf hiders, _mark_found colors ONLY the GAME middle-range atoms
    (``segi GAME and resi <rv1+1>-<rv2-1>``) -- NOT the shared id (coloring by
    id colors the real trace too, since alt-conf atoms share ids with their
    originals). For non-alt-conf (rec=None or rec.is_altconf=False), color by
    id (existing behavior; backward compat).

    These are UNIT tests for _mark_found directly (complement the TestOnPickAltconf
    integration tests which exercise _mark_found via on_pick).
    """

    def setUp(self):
        """Build a fresh GameController with a clean mock cmd history."""
        self.gc = GameController('1ubq')
        game.cmd.reset_mock()

    # ---- 1. alt-conf colors middle range (3-residue segment -> 1 middle resi) ----

    def test_mark_found_altconf_colors_middle_range(self):
        """_mark_found(100, rec) where rec.is_altconf=True, endpoint_resvs=(2,4)
        -> cmd.color('green', '1ubq and segi GAME and resi 3-3').

        The middle range is rv1+1=3 to rv2-1=3 (the single middle residue of a
        3-residue segment 2-4). Assert the selection contains 'segi GAME and
        resi 3-3' and does NOT contain 'id 100' (Pitfall 14: coloring by shared
        id would color the real trace too)."""
        rec = self.gc.registry.register(
            '1ubq', 100, 'cartoon', is_altconf=True,
            endpoint_resvs=(2, 4), alt_tag='B')

        self.gc._mark_found(100, rec)

        self.assertEqual(self.gc.registry.get('1ubq', 100).status,
                         HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once()
        sele = game.cmd.color.call_args[0][1]
        self.assertIn('segi GAME and resi 3-3', sele)
        self.assertNotIn('id 100', sele)

    # ---- 2. alt-conf 5-residue segment -> 3 middle residues ----

    def test_mark_found_altconf_5residue_range(self):
        """_mark_found(100, rec) where endpoint_resvs=(2,6) -> middle range
        rv1+1=3 to rv2-1=5 -> 'resi 3-5' (3 middle residues for a 5-residue
        segment). Assert the selection contains 'resi 3-5'."""
        rec = self.gc.registry.register(
            '1ubq', 100, 'cartoon', is_altconf=True,
            endpoint_resvs=(2, 6), alt_tag='B')

        self.gc._mark_found(100, rec)

        game.cmd.color.assert_called_once()
        sele = game.cmd.color.call_args[0][1]
        self.assertIn('resi 3-5', sele)

    # ---- 3. non-altconf rec=None colors by id (backward compat) ----

    def test_mark_found_non_altconf_colors_by_id(self):
        """_mark_found(100) with rec=None (the legacy call signature used by
        reveal_one/reveal_all) -> else branch -> cmd.color('green',
        '1ubq and id 100'). Backward compatible with Phase 3-7 callers."""
        self.gc.registry.register('1ubq', 100, 'spheres')

        self.gc._mark_found(100)

        self.assertEqual(self.gc.registry.get('1ubq', 100).status,
                         HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with('green', "1ubq and id 100")

    # ---- 4. non-altconf with explicit rec still colors by id ----

    def test_mark_found_non_altconf_with_rec(self):
        """_mark_found(100, rec) where rec.is_altconf=False (a sphere record
        passed explicitly) -> else branch -> cmd.color('green',
        '1ubq and id 100'). The is_altconf gate is False so the middle-range
        branch is skipped even though rec is passed."""
        rec = self.gc.registry.register('1ubq', 100, 'spheres')

        self.gc._mark_found(100, rec)

        self.assertEqual(self.gc.registry.get('1ubq', 100).status,
                         HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with('green', "1ubq and id 100")


class TestGameControllerHintReveal(unittest.TestCase):
    """Test GameController.hint / reveal_one / reveal_all / _mark_found /
    counters / on_counts_changed (Phase 6).

    Each test builds a GameController('1ubq') WITHOUT calling start() and
    manually populates the registry. _started is set True (hint/reveal guard
    on _started; the existing on_pick tests don't set it because on_pick has
    no such guard — but hint/reveal do). Mock callbacks verify the hint/reveal
    wiring. The mocked cmd.color / cmd.count_atoms are inspected to confirm
    recolor + gate behavior.
    """

    def setUp(self):
        """Build a fresh GameController with _started=True and clean mock cmd."""
        self.gc = GameController('1ubq')
        self.gc._started = True
        # Reset mock cmd call history (shared via sys.modules) so call_count
        # assertions are isolated per test.
        game.cmd.reset_mock()
        # count_atoms must return an int for the hint() gate `> 0` comparison
        # (MagicMock default returns NotImplemented for `>`). 5 = any positive.
        game.cmd.count_atoms.return_value = 5

    # ---- hint (GAME-05): color neighbors orange ----

    def test_hint_colors_neighbors(self):
        """hint() with 3 hidden -> _hint_count==1; counts(1,0); color 'orange'
        with a sele containing 'around' and 'not segi GAME'; all 3 still hidden;
        count_atoms called (the gate before cmd.color)."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc.registry.register('1ubq', 101, 'spheres')
        self.gc.registry.register('1ubq', 102, 'spheres')
        counts = MagicMock()
        self.gc.set_callbacks(on_counts_changed=counts)

        self.gc.hint()

        self.assertEqual(self.gc._hint_count, 1)
        counts.assert_called_once_with(1, 0)
        game.cmd.color.assert_called_once()
        # First arg is 'orange'
        self.assertEqual(game.cmd.color.call_args[0][0], 'orange')
        # Second arg (sele) contains 'around' and 'not segi GAME'
        sele_arg = game.cmd.color.call_args[0][1]
        self.assertIn('around', sele_arg)
        self.assertIn('not segi GAME', sele_arg)
        # CRITICAL: selection restricted to target object (the `around` operator
        # crosses object boundaries; without `and <obj>` it colors backup atoms)
        self.assertIn('and 1ubq', sele_arg)
        # count_atoms was called (the gate before cmd.color)
        self.assertGreaterEqual(game.cmd.count_atoms.call_count, 1)
        # All 3 records still hidden (hint does NOT mark_found)
        for rid in (100, 101, 102):
            rec = self.gc.registry.get('1ubq', rid)
            self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)

    def test_hint_no_started(self):
        """hint() before start (_started=False) -> no-op: _hint_count stays 0,
        cmd.color NOT called."""
        gc2 = GameController('1ubq')  # _started stays False
        gc2.registry.register('1ubq', 100, 'spheres')
        game.cmd.reset_mock()

        gc2.hint()

        self.assertEqual(gc2._hint_count, 0)
        game.cmd.color.assert_not_called()

    def test_hint_no_hidden(self):
        """hint() with all found (no hidden) -> no-op: _hint_count stays 0."""
        self.gc.registry.register('1ubq', 100, 'spheres',
                                  status=HIDER_STATUS_FOUND)

        self.gc.hint()

        self.assertEqual(self.gc._hint_count, 0)
        game.cmd.color.assert_not_called()

    def test_hint_no_neighbors(self):
        """hint() when all hidden hiders have 0 neighbors within HINT_RADIUS
        -> no-op: _hint_count stays 0, cmd.color NOT called, no log lie.

        Regression test: previously hint() picked a random hidden hider,
        found 0 neighbors, skipped coloring but STILL incremented _hint_count
        + fired on_counts_changed + logged 'highlighted neighbors' (a lie).
        Now it filters to candidates with neighbors first; no candidates ->
        silent no-op (don't count a useless hint).
        """
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc.registry.register('1ubq', 101, 'spheres')
        # count_atoms returns 0 for every sele -> no hider has neighbors
        game.cmd.count_atoms.return_value = 0
        counts = MagicMock()
        log = MagicMock()
        self.gc.set_callbacks(on_log=log, on_counts_changed=counts)

        self.gc.hint()

        self.assertEqual(self.gc._hint_count, 0)
        game.cmd.color.assert_not_called()
        counts.assert_not_called()
        log.assert_not_called()

    # ---- reveal_one (GAME-06 + DIFF-01): mark one hidden found ----

    def test_reveal_one(self):
        """reveal_one() with 3 hidden -> exactly 1 found; _reveal_count==1;
        counts(0,1); rem(2); color 'green' once; win NOT fired (2 remaining)."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc.registry.register('1ubq', 101, 'spheres')
        self.gc.registry.register('1ubq', 102, 'spheres')
        counts = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(on_remaining_changed=rem, on_win=win_cb,
                              on_counts_changed=counts)

        self.gc.reveal_one()

        # Exactly 1 of the 3 is now found
        found_count = sum(1 for r in self.gc.registry.all()
                          if r.status == HIDER_STATUS_FOUND)
        self.assertEqual(found_count, 1)
        self.assertEqual(self.gc._reveal_count, 1)
        counts.assert_called_once_with(0, 1)
        rem.assert_called_once_with(2)
        game.cmd.color.assert_called_once()
        self.assertEqual(game.cmd.color.call_args[0][0], 'green')
        win_cb.assert_not_called()

    def test_reveal_one_last(self):
        """reveal_one() with 1 hidden -> found; _reveal_count==1; win fires."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc._start_time = 1000.0
        win_cb = MagicMock()
        self.gc.set_callbacks(on_win=win_cb)

        self.gc.reveal_one()

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        self.assertEqual(self.gc._reveal_count, 1)
        win_cb.assert_called_once()

    # ---- reveal_all (GAME-07 + DIFF-01): mark all hidden found ----

    def test_reveal_all(self):
        """reveal_all() with 3 hidden -> all 3 found; _reveal_count==3;
        counts(0,3); rem(0); win fires once."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc.registry.register('1ubq', 101, 'spheres')
        self.gc.registry.register('1ubq', 102, 'spheres')
        self.gc._start_time = 1000.0
        counts = MagicMock()
        rem = MagicMock()
        win_cb = MagicMock()
        self.gc.set_callbacks(on_remaining_changed=rem, on_win=win_cb,
                              on_counts_changed=counts)

        self.gc.reveal_all()

        for rid in (100, 101, 102):
            rec = self.gc.registry.get('1ubq', rid)
            self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        self.assertEqual(self.gc._reveal_count, 3)
        counts.assert_called_once_with(0, 3)
        rem.assert_called_once_with(0)
        win_cb.assert_called_once()

    def test_reveal_all_no_started(self):
        """reveal_all() before start -> no-op: _reveal_count stays 0, record
        still hidden, cmd.color NOT called."""
        gc2 = GameController('1ubq')  # _started stays False
        gc2.registry.register('1ubq', 100, 'spheres')
        game.cmd.reset_mock()

        gc2.reveal_all()

        self.assertEqual(gc2._reveal_count, 0)
        rec = gc2.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        game.cmd.color.assert_not_called()

    # ---- _mark_found helper ----

    def test_mark_found_helper(self):
        """_mark_found(id) -> registry status 'found'; cmd.color called once
        with ('green', '1ubq and id 100')."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        game.cmd.reset_mock()

        self.gc._mark_found(100)

        self.assertEqual(self.gc.registry.get('1ubq', 100).status,
                         HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with('green', '1ubq and id 100')

    # ---- counters init zero ----

    def test_counters_init_zero(self):
        """Fresh GameController has _reveal_count==0 and _hint_count==0."""
        gc2 = GameController('1ubq')
        self.assertEqual(gc2._reveal_count, 0)
        self.assertEqual(gc2._hint_count, 0)

    # ---- set_callbacks 4th param (on_counts_changed) ----

    def test_set_callbacks_4th_param(self):
        """set_callbacks() with no args -> _on_counts_changed is a no-op
        (returns None). set_callbacks(on_counts_changed=cb) -> cb(h, r) fires."""
        gc2 = GameController('1ubq')
        gc2.set_callbacks()  # all None
        self.assertIsNone(gc2._on_counts_changed(0, 0))

        cb = MagicMock()
        gc3 = GameController('1ubq')
        gc3.set_callbacks(on_counts_changed=cb)
        gc3._on_counts_changed(1, 2)
        cb.assert_called_once_with(1, 2)

    # ---- cleanup / abort_on_error reset counters (Phase 6 deviation) ----

    def test_cleanup_resets_counters(self):
        """cleanup() restores from backup + resets _reveal_count + _hint_count
        to 0 (Phase 6 deviation: cleanup now restores from backup to clear hint
        orange coloring on real neighbor atoms; counters reset because the
        game is over)."""
        self.gc._started = True
        self.gc._backup_name = '_bchm_backup'
        self.gc._reveal_count = 3
        self.gc._hint_count = 2

        result = self.gc.cleanup()

        self.assertTrue(result)  # backup.restore returns True (mocked)
        self.assertEqual(self.gc._reveal_count, 0)
        self.assertEqual(self.gc._hint_count, 0)
        self.assertFalse(self.gc._started)
        self.assertIsNone(self.gc._backup_name)

    def test_abort_on_error_resets_counters(self):
        """abort_on_error() resets _reveal_count + _hint_count to 0 (consistency
        with cleanup; game aborting -> counters reset)."""
        self.gc._started = True
        self.gc._backup_name = '_bchm_backup'
        self.gc._reveal_count = 3
        self.gc._hint_count = 2

        result = self.gc.abort_on_error()

        self.assertTrue(result)  # backup.restore returns True (mocked)
        self.assertEqual(self.gc._reveal_count, 0)
        self.assertEqual(self.gc._hint_count, 0)
        self.assertFalse(self.gc._started)
        self.assertIsNone(self.gc._backup_name)

    def test_cleanup_idempotent_not_started(self):
        """cleanup() when not started -> returns True, no-op, counters stay 0."""
        gc2 = GameController('1ubq')  # _started stays False
        gc2._reveal_count = 0
        gc2._hint_count = 0

        result = gc2.cleanup()

        self.assertTrue(result)
        self.assertEqual(gc2._reveal_count, 0)
        self.assertEqual(gc2._hint_count, 0)

    # ---- _found_color threading (Phase 7 DIFF-04) ----

    def test_found_color_default_green(self):
        """Fresh GameController._found_color == 'green' (default; DIFF-04
        overrides via cmd.set_color + assignment in the GUI). The default
        preserves the legacy behavior so existing tests asserting
        cmd.color('green', ...) pass unchanged."""
        gc = GameController('1ubq')
        self.assertEqual(gc._found_color, 'green')

    def test_found_color_threading(self):
        """_mark_found uses self._found_color instead of hardcoded 'green'.
        Set gc._found_color = 'cyan'; _mark_found(100) -> cmd.color called
        with 'cyan' (NOT 'green'). This is the WSL-testable proof that
        DIFF-04's parameterization works; the GUI color picker (Plan 02)
        assigns _found_color + cmd.set_color('found_highlight', ...) and
        relies on _mark_found reading it back here."""
        self.gc.registry.register('1ubq', 100, 'spheres')
        self.gc._found_color = 'cyan'
        game.cmd.reset_mock()

        self.gc._mark_found(100)

        self.assertEqual(self.gc.registry.get('1ubq', 100).status,
                         HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with('cyan', "1ubq and id 100")


if __name__ == '__main__':
    unittest.main(verbosity=2)
