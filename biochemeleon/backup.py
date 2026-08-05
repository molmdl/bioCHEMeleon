"""Backup snapshot/restore/discard — cmd-coupled (PyMOL Open Source has NO undo; manual backup mandatory).

This module provides the snapshot/discard half of the backup lifecycle.
PyMOL Open Source ships a no-op `undocontext` stub (editor.py:25-36), so
every destructive mutation MUST be preceded by a snapshot and followed by
either a discard (happy path) or a restore (failure path).

  - BACKUP_PREFIX: '_bchm_backup' (underscore => private, hidden from
    cmd.get_names('public_objects') per RESEARCH section Q6).
  - snapshot(target_obj): fresh independent deep copy; discards any stale
    backup first. Returns the backup name.
  - discard(backup_name): delete the backup object. Idempotent.

restore() and verify_intact() are added in plans 03-05 and 03-08.

NOTE: This module is cmd-coupled. The pymol.cmd import will FAIL at
import/runtime in WSL (no PyMOL installed), but `python3.6 -m py_compile`
checks SYNTAX only (not imports) so it passes in WSL. Runtime behavior is
verified by the Phase 3 smoke test.
"""
from pymol import cmd


# ---- Backup object name (private, underscore-prefixed) ----

BACKUP_PREFIX = '_bchm_backup'   # underscore => private (hidden from public_objects)


# ---- Snapshot / discard (plans 03-02) ----

def snapshot(target_obj):
    """Create a private independent backup copy of target_obj. Returns backup name.
    Discards any stale backup first."""
    cmd.delete(BACKUP_PREFIX)                       # commanding.py:496 (idempotent)
    cmd.create(BACKUP_PREFIX, target_obj)           # creating.py:960 (fresh independent copy)
    return BACKUP_PREFIX


def discard(backup_name=BACKUP_PREFIX):
    """Delete the backup object. Idempotent."""
    cmd.delete(backup_name)                         # commanding.py:496 (safe on absent objects)
