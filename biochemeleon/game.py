"""GameController — thin orchestrator wiring backup + mutation + registry (Phase 3). Generators (sphere/line/stick/cartoon) plug into start() in Phase 4/5; Phase 3 proves the mechanism with a placeholder insert."""

import random
import time

from pymol import cmd

from . import backup, mutation, registry

# Phase 6 hint parameters
HINT_RADIUS = 5.0  # CA-CA ~3.8 A; captures adjacent residues
HINT_COLOR = 'orange'  # distinct from green=found + blend colors


class GameController:
    """Orchestrates the hide-and-seek round: snapshot -> insert hiders -> register -> (play) -> cleanup/abort.
    Phase 3: placeholder insert (fixed positions) to prove the mechanism.
    Phase 4/5: real generators replace _placeholder_hiders."""

    def __init__(self, target_obj):
        self.target_obj = target_obj
        self.registry = registry.HiderRegistry()
        self._backup_name = None
        self._started = False
        # Phase 4 play-loop state (set by caller; not used by start/cleanup)
        self._start_time = None
        self._wizard = None
        self._on_log = lambda msg: None
        self._on_remaining_changed = lambda r: None
        self._on_win = lambda elapsed: None
        # Phase 6 hint/reveal counters (DIFF-01; reset per round in start())
        self._reveal_count = 0
        self._hint_count = 0
        self._on_counts_changed = lambda h, r: None
        # Phase 7 DIFF-04: player-chosen found-hider highlight color.
        # Default 'green' preserves the legacy _mark_found behavior so
        # existing tests asserting cmd.color('green', ...) pass unchanged.
        # The GUI color picker (Plan 02) overrides via cmd.set_color +
        # assignment: self._found_color = 'found_highlight'.
        self._found_color = 'green'
        # Phase 8 import state: _is_imported routes Restart + Cleanup
        # (Plan 04 GUI handlers check this flag). _imported_bcm stores
        # the .bcm dict so Restart-on-imported can re-reconcile rep
        # without re-reading the file.
        self._is_imported = False
        self._imported_bcm = None

    def start(self, hider_specs):
        """Begin a round. hider_specs: list of (payload, rep) tuples where
        payload is rep-specific ([x,y,z] for spheres, (offset, neighbor_id)
        for lines/sticks, (chain, terminus_resi, is_c_terminus) for
        cartoon/ribbon). Phase 4/5 generators produce this list.
        Steps: snapshot -> for each (payload, rep): per-rep dispatch
        (the dispatcher hides rep-specific insertion-signature divergence)
        -> register.
        Returns the backup name on success, None on failure."""
        if self._started:
            raise RuntimeError("game already started; call cleanup() first")
        # Snapshot BEFORE any mutation (RESEARCH: no undo; backup is mandatory)
        self._backup_name = backup.snapshot(self.target_obj)
        self.registry = registry.HiderRegistry()  # fresh per round
        self._reveal_count = 0  # reset per round (DIFF-01)
        self._hint_count = 0  # reset per round (DIFF-01)
        for i, (payload, rep) in enumerate(hider_specs):
            handle = "H%03d" % i
            aid = mutation.insert_hider_for_rep(self.target_obj, rep, payload, handle)
            self.registry.register(object=self.target_obj, id=aid, rep=rep)
        self._started = True
        return self._backup_name

    # ---- Phase 4 play-loop (click-to-find) ----

    def set_callbacks(self, on_log=None, on_remaining_changed=None,
                      on_win=None, on_counts_changed=None):
        """Register GUI callbacks. Each defaults to a no-op lambda when None.

        on_log(msg): called with a string log message (Miss! / Found one! /
            Already found!).
        on_remaining_changed(remaining): called with the int remaining count
            after a find.
        on_win(elapsed): called with a float elapsed seconds when all hiders
            are found.
        on_counts_changed(hint_count, reveal_count): called with the running
            hint + reveal usage counters (Phase 6 DIFF-01; GUI updates a
            reveal-counter label).
        """
        self._on_log = on_log or (lambda msg: None)
        self._on_remaining_changed = on_remaining_changed or (lambda r: None)
        self._on_win = on_win or (lambda elapsed: None)
        self._on_counts_changed = on_counts_changed or (lambda h, r: None)

    def _remaining(self):
        """Return the count of registry records with status == 'hidden'."""
        return sum(1 for r in self.registry.all()
                   if r.status == registry.HIDER_STATUS_HIDDEN)

    def on_pick(self, picked_id):
        """Handle a picked atom id (called by PickWizard.do_pick).

        Registry is the single source of truth (LOOP-02). Logic:
          - rec is None -> miss (non-hider); log 'Miss!', no harm (LOOP-01)
          - rec.status == 'found' -> already-found; log, no double-mark
          - else: hidden hider -> mark_found + cmd.color green + callbacks;
            if remaining == 0 -> win()
        """
        rec = self.registry.get(self.target_obj, picked_id)
        if rec is None:
            self._on_log("Miss!")
            return
        if rec.status == registry.HIDER_STATUS_FOUND:
            self._on_log("Already found!")
            return
        self._mark_found(picked_id)
        remaining = self._remaining()
        self._on_log("Found one! %d remaining" % remaining)
        self._on_remaining_changed(remaining)
        if remaining == 0:
            self.win()

    def _mark_found(self, hider_id):
        """Shared mark+color helper. Does NOT log or fire win (callers do those)."""
        self.registry.mark_found(self.target_obj, hider_id)
        cmd.color(self._found_color, "%s and id %s" % (self.target_obj, hider_id))

    def win(self):
        """All hiders found: fire on_win(elapsed). Wizard deactivation is
        deferred to the GUI callback (gui_game._finish_win) so the last
        cmd.color('green', ...) from on_pick can flush to the viewer before
        the modal win dialog blocks the Qt event loop.

        The GUI owns the wizard lifecycle (it created the wizard in
        _begin_play; it deactivates it in _finish_win after a 100 ms redraw
        delay). _started STAYS True after win (hiders remain until
        cleanup(), which gui_game._finish_win calls after the user dismisses
        the win dialog).
        """
        elapsed = time.time() - self._start_time if self._start_time else 0.0
        self._on_win(elapsed)

    # ---- Phase 6 hint / reveal ----

    def hint(self):
        """Color the residues near a random hidden hider orange (GAME-05).

        Highlights NEIGHBORS (byres vicinity), not the hider itself; excludes
        GAME atoms. Does NOT mark_found (status stays hidden). No confirm
        dialog (Hint is help, not give-up). Increments _hint_count + fires
        on_counts_changed.

        Filters to hiders that HAVE neighbors within HINT_RADIUS before
        picking (a hider in a sparse region produces no visible hint). If
        no hidden hider has neighbors, returns without counting (no-op).

        CRITICAL: the selection is restricted to self.target_obj via a
        trailing `and <obj>` because PyMOL's `around` operator crosses object
        boundaries — without it, the selection would also color atoms in the
        backup object (_bchm_backup, a coordinate-identical copy), corrupting
        the backup's colors and defeating cleanup's restore-from-backup.
        """
        if not self._started:
            return
        hidden = [r for r in self.registry.all()
                  if r.status == registry.HIDER_STATUS_HIDDEN]
        if not hidden:
            return
        # Hint selection: residues near a hidden hider, excluding GAME atoms,
        # restricted to the target object (the `around` operator crosses
        # object boundaries — without `and <obj>` it matches backup atoms too).
        def hint_sele(hider_id):
            return "(byres (%s and id %d around %s)) and not segi GAME and %s" % (
                self.target_obj, hider_id, HINT_RADIUS, self.target_obj)
        # Prefer hiders that HAVE neighbors within HINT_RADIUS (a hider in a
        # sparse region would produce no visible hint; counting a no-op would
        # mislead the player + the log).
        candidates = [r for r in hidden if cmd.count_atoms(hint_sele(r.id)) > 0]
        if not candidates:
            return  # no hider has neighbors to highlight; don't count a no-op
        rec = random.choice(candidates)
        cmd.color(HINT_COLOR, hint_sele(rec.id))
        self._hint_count += 1
        self._on_counts_changed(self._hint_count, self._reveal_count)
        self._on_log("Hint: highlighted neighbors of one hider.")

    def reveal_one(self):
        """Mark one random hidden hider found + green; count the reveal (GAME-06).

        Picks a random hidden hider, marks it found (via _mark_found),
        increments _reveal_count, fires on_counts_changed + on_remaining_changed.
        If no hiders remain, fires win(). NO confirm dialog here (the GUI shows
        it before calling).
        """
        if not self._started:
            return
        hidden = [r for r in self.registry.all()
                  if r.status == registry.HIDER_STATUS_HIDDEN]
        if not hidden:
            return
        rec = random.choice(hidden)
        self._mark_found(rec.id)
        self._reveal_count += 1
        self._on_counts_changed(self._hint_count, self._reveal_count)
        remaining = self._remaining()
        self._on_log("Revealed one! %d remaining" % remaining)
        self._on_remaining_changed(remaining)
        if remaining == 0:
            self.win()

    def reveal_all(self):
        """Mark all hidden hiders found + green; count reveals (GAME-07).

        Marks ALL hidden hiders found (via _mark_found per hider), increments
        _reveal_count by the number revealed (NOT +1 for the action), fires
        on_counts_changed + on_remaining_changed(0), logs, then calls win()
        (all found -> win fires).
        """
        if not self._started:
            return
        hidden = [r for r in self.registry.all()
                  if r.status == registry.HIDER_STATUS_HIDDEN]
        if not hidden:
            return
        for rec in hidden:
            self._mark_found(rec.id)
        self._reveal_count += len(hidden)
        self._on_counts_changed(self._hint_count, self._reveal_count)
        self._on_remaining_changed(0)
        self._on_log("Revealed all %d hiders. Game over." % len(hidden))
        self.win()

    def reconstruct_registry(self):
        """Rebuild the registry from sentinel atoms after .pse reload (RESEARCH §Q4).
        rep is lost on reload (set to None; Phase 8 sidecar reconciles)."""
        self.registry = registry.HiderRegistry().reconstruct_from_sentinels(
            lambda: mutation.fetch_all_hider_ids(self.target_obj))
        return self.registry

    def import_state(self, bcm_dict):
        """Reconstruct this controller's state from an imported .bcm dict
        WITHOUT re-inserting hiders (they came from the .pse). Mirrors
        start()'s end-state (_started=True, _backup_name set, registry
        populated) but skips the snapshot-before-insert + insert loop.

        Steps:
          1. reconstruct_registry() - sentinel rebuild (rep=None).
          2. apply_bcm_dict(self, bcm_dict) - reconcile rep + found-status
             + set _reveal_count/_hint_count/_found_color. (persistence.py)
          3. Defensive found-color re-apply (idempotent - .pse preserves
             color, but re-apply defends against a future format change).
          4. Snapshot a FRESH backup of the post-import object (hiders +
             found-status applied) so Cleanup/Restart work later. This
             is the "original" for an imported game (research §6.2):
             puzzle -> all-hidden initial state; checkpoint -> found-status
             as saved.
          5. _started = True; _is_imported = True; _imported_bcm = bcm_dict.

        Raises RuntimeError if already started (mirror start()'s guard).
        """
        if self._started:
            raise RuntimeError("game already started; call cleanup() first")
        from . import persistence  # lazy import (avoid circular at module load)
        self.reconstruct_registry()           # game.py:224 (rep=None, all hidden)
        persistence.apply_bcm_dict(self, bcm_dict)  # reconcile + set fields
        # Defensive found-color re-apply (research §4.2 - .pse preserves
        # color but re-apply is idempotent + future-proof).
        for rec in self.registry.all():
            if rec.status == registry.HIDER_STATUS_FOUND:
                cmd.color(self._found_color,
                          "%s and id %d" % (self.target_obj, rec.id))
        self._backup_name = backup.snapshot(self.target_obj)  # FRESH post-import
        self._started = True
        self._is_imported = True
        self._imported_bcm = bcm_dict

    def cleanup(self):
        """Happy-path cleanup: restore from backup (removes hiders + restores
        hint-colored real atoms to their original colors), then discard backup.
        Returns True on successful restore, False on failure (caller should
        call abort_on_error).
        Idempotent: safe to call when not started (returns True, no-op).

        Phase 6 deviation: previously this removed hiders by sentinel
        (mutation.cleanup_hiders) + verified structure (backup.verify_intact).
        But hint() colors REAL (non-GAME) neighbor atoms orange, and sentinel
        removal alone does NOT restore those colors. The backup (created in
        start() before any mutation or hint coloring) has the original atoms +
        colors, so restore from backup removes hiders AND restores colors in
        one step. mutation.cleanup_hiders + backup.verify_intact remain
        available as primitives but are no longer called here.
        """
        if not self._started:
            return True
        # Restore from backup: removes hiders + restores hint-colored real
        # atoms to their original colors. The backup was created in start()
        # before any mutation or hint coloring, so it has the original atoms
        # + colors. (Phase 6: hint() colors real neighbor atoms orange;
        # sentinel-remove alone does NOT restore those colors, so we restore
        # from backup instead of just removing hiders.)
        ok = backup.restore(self.target_obj, self._backup_name)
        backup.discard(self._backup_name)
        self._backup_name = None
        self._started = False
        self.registry = registry.HiderRegistry()  # reset
        self._reveal_count = 0  # game over -> counters reset
        self._hint_count = 0
        return ok

    def abort_on_error(self):
        """Failure-path restore: restore from backup (delete+create), then discard.
        Returns True on success, False on failure (restore failed — target may be in bad state).
        Use when cleanup() returned False OR an unexpected error occurred mid-game."""
        if not self._started:
            return True
        ok = backup.restore(self.target_obj, self._backup_name)
        backup.discard(self._backup_name)
        self._backup_name = None
        self._started = False
        self.registry = registry.HiderRegistry()  # reset
        self._reveal_count = 0  # game over -> counters reset (consistency w/ cleanup)
        self._hint_count = 0
        return ok
