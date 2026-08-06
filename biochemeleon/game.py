"""GameController — thin orchestrator wiring backup + mutation + registry (Phase 3). Generators (sphere/line/stick/cartoon) plug into start() in Phase 4/5; Phase 3 proves the mechanism with a placeholder insert."""

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
