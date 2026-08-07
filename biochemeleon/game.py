"""GameController — thin orchestrator wiring backup + mutation + registry (Phase 3). Generators (sphere/line/stick/cartoon) plug into start() in Phase 4/5; Phase 3 proves the mechanism with a placeholder insert."""

import time

from pymol import cmd

from . import backup, mutation, registry


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

    def start(self, hider_specs):
        """Begin a round. hider_specs: list of (pos, rep) tuples (Phase 3 placeholder;
        Phase 4/5 generators produce this list).
        Steps: snapshot -> for each (pos, rep): insert_hider -> register.
        Returns the backup name on success, None on failure."""
        if self._started:
            raise RuntimeError("game already started; call cleanup() first")
        # Snapshot BEFORE any mutation (RESEARCH: no undo; backup is mandatory)
        self._backup_name = backup.snapshot(self.target_obj)
        self.registry = registry.HiderRegistry()  # fresh per round
        for i, (pos, rep) in enumerate(hider_specs):
            handle = "H%03d" % i
            aid = mutation.insert_hider(self.target_obj, pos=pos, rep=rep, handle=handle)
            self.registry.register(object=self.target_obj, id=aid, rep=rep)
        self._started = True
        return self._backup_name

    # ---- Phase 4 play-loop (click-to-find) ----

    def set_callbacks(self, on_log=None, on_remaining_changed=None, on_win=None):
        """Register GUI callbacks. Each defaults to a no-op lambda when None.

        on_log(msg): called with a string log message (Miss! / Found one! /
            Already found!).
        on_remaining_changed(remaining): called with the int remaining count
            after a find.
        on_win(elapsed): called with a float elapsed seconds when all hiders
            are found.
        """
        self._on_log = on_log or (lambda msg: None)
        self._on_remaining_changed = on_remaining_changed or (lambda r: None)
        self._on_win = on_win or (lambda elapsed: None)

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
        self.registry.mark_found(self.target_obj, picked_id)
        cmd.color('green', "%s and id %s" % (self.target_obj, picked_id))
        remaining = self._remaining()
        self._on_log("Found one! %d remaining" % remaining)
        self._on_remaining_changed(remaining)
        if remaining == 0:
            self.win()

    def win(self):
        """All hiders found: fire on_win(elapsed) + deactivate wizard if set.

        _started STAYS True after win (hiders remain until cleanup()).
        """
        elapsed = time.time() - self._start_time if self._start_time else 0.0
        self._on_win(elapsed)
        if self._wizard is not None:
            self._wizard.deactivate()
            self._wizard = None

    def reconstruct_registry(self):
        """Rebuild the registry from sentinel atoms after .pse reload (RESEARCH §Q4).
        rep is lost on reload (set to None; Phase 8 sidecar reconciles)."""
        self.registry = registry.HiderRegistry().reconstruct_from_sentinels(
            lambda: mutation.fetch_all_hider_ids(self.target_obj))
        return self.registry

    def cleanup(self):
        """Happy-path cleanup: remove all hiders by sentinel, verify structure intact, discard backup.
        Returns True if the structure matches the pre-game backup exactly (criterion 4 happy path),
        False if the verify_intact check fails (caller should call abort_on_error).
        Idempotent: safe to call when not started (returns True, no-op)."""
        if not self._started:
            return True
        removed = mutation.cleanup_hiders(self.target_obj)
        intact = backup.verify_intact(self.target_obj, self._backup_name)
        backup.discard(self._backup_name)
        self._backup_name = None
        self._started = False
        self.registry = registry.HiderRegistry()  # reset
        return intact

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
        return ok
