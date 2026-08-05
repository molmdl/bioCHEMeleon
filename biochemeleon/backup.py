"""Backup snapshot/restore/discard/verify — cmd-coupled (PyMOL Open Source has NO undo; manual backup mandatory).

This module provides the snapshot/restore/discard/verify_intact lifecycle.
PyMOL Open Source ships a no-op `undocontext` stub (editor.py:25-36), so
every destructive mutation MUST be preceded by a snapshot and followed by
either a discard (happy path) or a restore (failure path), with verify_intact
as the structure-integrity proof (criterion 4: target matches backup
atom-for-atom after restore or cleanup).

  - BACKUP_PREFIX: '_bchm_backup' (underscore => private, hidden from
    cmd.get_names('public_objects') per RESEARCH section Q6).
  - snapshot(target_obj): fresh independent deep copy; discards any stale
    backup first. Returns the backup name.
  - restore(target_obj, backup_name): FAILURE-PATH restore via delete+create
    two-step (never single-call create; RESEARCH section Q2). Returns True/False.
  - discard(backup_name): delete the backup object. Idempotent.
  - verify_intact(target_obj, backup_name): structure-integrity check
    (atom count + atomic-tuple multiset). Returns True/False. The proof
    behind criterion 4.

snapshot() + discard() added in plan 03-02; restore() in plan 03-05;
verify_intact() in plan 03-08.

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


# ---- Restore (plan 03-05) ----

def restore(target_obj, backup_name=BACKUP_PREFIX):
    """FAILURE-PATH restore: target ends up atom-for-atom identical to backup.
    Uses delete+create to avoid merge-vs-replace ambiguity (RESEARCH section Q2:
    single-call cmd.create(existing, backup) is UNVERIFIED C-dispatched). Returns
    True on success, False on failure (caller aborts game)."""
    try:
        cmd.delete(target_obj)                       # commanding.py:496 — remove mutated object entirely
        cmd.create(target_obj, backup_name)           # creating.py:960 — fresh copy from backup
        return True
    except Exception:
        return False


# ---- Verify integrity (plan 03-08) ----

def verify_intact(target_obj, backup_name=BACKUP_PREFIX):
    """Return True iff target's structure matches backup: atom count + atomic tuple multiset.
    Tuple = (resn, resi, name, chain, segi, x, y, z). Coords are exact for a create-copy."""
    target_n = cmd.count_atoms(target_obj)           # querying.py:1412 — cheap count gate
    backup_n = cmd.count_atoms(backup_name)          # mismatch => structure changed (gross)
    if target_n != backup_n:
        return False
    target_tuples = []
    cmd.iterate(target_obj, "stored.append((resn, resi, name, chain, segi, x, y, z))",
                space={'stored': target_tuples})     # editing.py:1490
    backup_tuples = []
    cmd.iterate(backup_name, "stored.append((resn, resi, name, chain, segi, x, y, z))",
                space={'stored': backup_tuples})     # editing.py:1490
    return sorted(target_tuples) == sorted(backup_tuples)
