---
phase: 03-mutation-safety-hider-registry-foundation
plan: 02
subsystem: infra
tags: [pymol, backup, snapshot, undo-safety, cmd-coupled, mutation-safety]

# Dependency graph
requires:
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: the biochemeleon/ package this module lives in (standalone cmd module — no import of setup_state/registry/mutation)
provides:
  - backup.BACKUP_PREFIX ('_bchm_backup' — underscore-prefixed private backup object name)
  - backup.snapshot(target_obj) — fresh independent deep copy; discards stale backup first; returns backup name
  - backup.discard(backup_name) — idempotent backup deletion (cmd.delete safe on absent objects)
affects: [03-05 (restore), 03-08 (verify_intact), 03-11/03-12 (game.py GameController start/cleanup/abort_on_error), Phase 4+ (every destructive mutation needs snapshot+discard)]

# Tech tracking
tech-stack:
  added: []  # no new libs — only pymol.cmd which ships with pymol-open-source
  patterns:
    - "Pre-mutation backup lifecycle: snapshot before any destructive cmd op; discard on success / restore on failure (PyMOL Open Source has NO undo — undocontext is a no-op stub, editor.py:25-36)"
    - "Private object naming: underscore prefix (_bchm_backup) hides from cmd.get_names('public_objects') so user-facing object lists stay clean"
    - "Unambiguous fresh copy via delete-then-create (sidesteps the UNVERIFIED merge-vs-replace semantics of single-call cmd.create(existing, other))"

key-files:
  created:
    - biochemeleon/backup.py
  modified: []

key-decisions:
  - "snapshot uses delete+create (delete stale _bchm_backup first, then cmd.create fresh) — unambiguous fresh independent copy; no merge-vs-replace question (RESEARCH Q2)"
  - "BACKUP_PREFIX='_bchm_backup' — underscore prefix hides it from cmd.get_names('public_objects') so the user never sees the backup in the object panel (RESEARCH Q6)"
  - "discard is idempotent — cmd.delete is safe on absent objects, so calling discard twice or on a non-existent backup is a no-op (defensive cleanup)"
  - "Scope discipline: restore() and verify_intact() are NOT in this plan — they belong to plans 03-05 and 03-08 (snapshot+discard subset only)"

patterns-established:
  - "Pre-mutation backup lifecycle: snapshot before any destructive cmd op; discard on success / restore on failure (PyMOL Open Source has NO undo)"
  - "Private object naming: underscore prefix (_bchm_backup) hides from public_objects — user-facing object lists stay clean"
  - "Idempotent cleanup helpers: discard uses cmd.delete which is safe on absent objects"

# Metrics
duration: 1 min
completed: 2026-08-05
---

# Phase 3 Plan 02: backup.py snapshot + discard Summary

**Standalone cmd-coupled backup module with BACKUP_PREFIX + snapshot (delete-stale-then-create fresh copy) + idempotent discard — the snapshot/discard half of the PyMOL-has-no-undo backup lifecycle**

## Performance

- **Duration:** 1 min
- **Started:** 2026-08-05T03:54:04Z
- **Completed:** 2026-08-05T03:55:28Z
- **Tasks:** 2 (1 committed; 1 gate-run-only)
- **Files modified:** 1 (biochemeleon/backup.py created)

## Accomplishments
- Created `biochemeleon/backup.py` — the cmd-coupled backup module (standalone: no import of setup_state/registry/mutation; mirrors demos.py's `from pymol import cmd` + section-comment style)
- `BACKUP_PREFIX = '_bchm_backup'` — underscore-prefixed so it's hidden from `cmd.get_names('public_objects')` (RESEARCH Q6); user never sees the backup in the object panel
- `snapshot(target_obj)` — discards any stale backup first (`cmd.delete(BACKUP_PREFIX)` is idempotent), then `cmd.create(BACKUP_PREFIX, target_obj)` makes a fresh independent deep copy (creating.py:960); returns the backup name. This is the pre-mutation safety net mandated by AGENTS.md ("PyMOL Open Source has NO undo")
- `discard(backup_name=BACKUP_PREFIX)` — `cmd.delete(backup_name)`; idempotent (safe on absent objects) — the happy-path cleanup after a successful game
- Scope discipline maintained: `restore()` (plan 03-05) and `verify_intact()` (plan 03-08) deliberately NOT added — this plan ships only the snapshot+discard subset
- All WSL gates green: `py_compile` clean across `biochemeleon/*.py`; existing 90 tests still pass (no pure-layer touch); Pitfall-1 + Pitfall-11 grep gates zero matches

## Task Commits

Each task was committed atomically:

1. **Task 1: Create backup.py with BACKUP_PREFIX + snapshot + discard** - `07abca1` (feat)
2. **Task 2: Run full gate suite (no regression)** - no commit (gate-run only; all 4 gates green)

**Plan metadata:** pending (docs commit after SUMMARY + STATE)

## Files Created/Modified
- `biochemeleon/backup.py` — NEW (41 lines). Cmd-coupled backup module. Module docstring explains the no-undo rationale + cmd-coupled/WSL-py_compile-only note. `from pymol import cmd` (exactly one such line). `BACKUP_PREFIX = '_bchm_backup'`. `snapshot(target_obj)` = delete-stale + create-fresh + return name. `discard(backup_name)` = idempotent delete. Inline source citations (commanding.py:496, creating.py:960).

## Decisions Made
- **snapshot = delete-then-create, not single-call create.** RESEARCH Q2 flagged single-call `cmd.create(existing, other)` merge-vs-replace semantics as UNVERIFIED (C-dispatched, creating.py:1024). For the *snapshot* direction (`create('_bchm_backup', target_obj)`) `_bchm_backup` doesn't exist yet so there's no merge question — but deleting any stale backup first guarantees a clean fresh copy even if a previous game crashed without discarding. This matches the RESEARCH Q6 code sketch verbatim.
- **discard default arg = BACKUP_PREFIX.** Callers can `discard()` with no args for the common case (single-target Phase 3 game), or pass a custom name if a future phase supports per-target backup suffixes (RESEARCH Open Question 5). The default keeps the Phase 3 call sites minimal.
- **Idempotent discard via cmd.delete.** `cmd.delete` (commanding.py:496) is safe on absent objects (no exception), so `discard()` can be called defensively in cleanup paths without a guard. This is the same property `snapshot` relies on for its stale-backup delete.
- **Docstring NOTE reworded to avoid a literal `from pymol import cmd` token.** See Deviations §1.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded module docstring NOTE to avoid a false-positive grep match**
- **Found during:** Task 1 (Create backup.py with BACKUP_PREFIX + snapshot + discard)
- **Issue:** The plan's verification requires "exactly ONE `from pymol` match in biochemeleon/backup.py (the import line)". The initial docstring NOTE contained the literal text `` `from pymol import cmd` `` to explain the WSL/py_compile behavior. That literal matched the `from pymol` grep pattern, producing TWO matches (the docstring token + the real import) — failing the verification gate. AGENTS.md explicitly documents this exact false-positive pattern: "literal tokens in comments/docstrings trip this grep too (we hit a false positive on a docstring that said 'from PyQt5 import')."
- **Fix:** Reworded the NOTE from `` `from pymol import cmd` will FAIL at import/runtime `` to "The pymol.cmd import will FAIL at import/runtime" — removes the literal `from pymol` token while preserving the meaning (the note still explains that the pymol.cmd import fails at runtime in WSL but py_compile passes because it's syntax-only).
- **Files modified:** biochemeleon/backup.py (docstring NOTE only; no code change)
- **Verification:** Grep tool `from pymol` in biochemeleon/backup.py → exactly 1 match (line 21, the real import). py_compile still passes.
- **Committed in:** 07abca1 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — false-positive grep match)
**Impact on plan:** Necessary to satisfy the plan's own verification gate. No scope creep; no behavior change (docstring wording only).

## Issues Encountered
None. The cmd-coupled module's `from pymol import cmd` correctly fails at runtime in WSL (no PyMOL) but passes `py_compile` (syntax-only) as the plan predicted — no surprises.

## User Setup Required
None - no external service configuration required. This is a standalone cmd-coupled module using only `pymol.cmd` (ships with pymol-open-source, already installed in the Windows conda env).

## Next Phase Readiness
- **Ready:** `backup.snapshot` + `backup.discard` + `BACKUP_PREFIX` are available for the game.py orchestrator (plans 03-11/03-12) to wire into `start()` (snapshot before insert loop) and `cleanup()` (discard after verify_intact). They are also the foundation `restore` (03-05) and `verify_intact` (03-08) will build on.
- **Not yet ready:** The full backup lifecycle requires `restore` (03-05, failure path) and `verify_intact` (03-08, structure-equality check) — both deferred per plan scope. `game.py` cannot complete the abort-on-error path until restore lands.
- **Runtime verification deferred:** backup.py is cmd-coupled — its `cmd.delete`/`cmd.create` behavior (deep-copy independence, idempotent delete, underscore-prefix privacy in `public_objects`) is WSL-unverifiable. The Phase 3 smoke test (plan 03-13/03-14, run in Windows PyMOL via plan 03-15 checkpoint) is the formal runtime confirmation. The smoke test asserts: backup name == `_bchm_backup`, backup not in `public_objects`, backup in `objects`, backup count == orig count.
- **Blockers/concerns:** None for this plan. The RESEARCH Q2 MEDIUM flag (cmd.create merge-vs-replace) does NOT affect snapshot (fresh-name create has no merge question) — it only affects the restore path (plan 03-05, which uses delete+create to sidestep it).

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
