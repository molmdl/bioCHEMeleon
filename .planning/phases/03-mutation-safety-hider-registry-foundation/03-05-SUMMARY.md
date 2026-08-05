---
phase: 03-mutation-safety-hider-registry-foundation
plan: 05
subsystem: infra
tags: [pymol, backup, restore, delete-create, no-undo, cmd-coupled, failure-path]

# Dependency graph
requires:
  - phase: 03-02
    provides: backup.py with snapshot/discard + BACKUP_PREFIX ('_bchm_backup', underscore-private)
provides:
  - "restore(target_obj, backup_name) FAILURE-PATH restore via cmd.delete+cmd.create two-step (try/except returns True/False)"
affects: [03-08, 03-13, 03-14, 03-15, game.py orchestrator, all later phases relying on restore-on-failure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "delete+create two-step restore (sidesteps UNVERIFIED merge-vs-replace of single-call cmd.create(existing, backup) — RESEARCH Q2)"

key-files:
  created: []
  modified:
    - biochemeleon/backup.py

key-decisions:
  - "restore uses cmd.delete(target_obj) + cmd.create(target_obj, backup_name) two-step — NEVER single-call cmd.create(existing, backup) (RESEARCH Q2 MEDIUM flag: single-call create merge-vs-replace is UNVERIFIED C-dispatched)"
  - "restore placed AFTER discard, BEFORE future verify_intact (mirrors RESEARCH Backup/Restore Design order)"

patterns-established:
  - "FAILURE-PATH restore pattern: delete mutated target entirely + create fresh atom-for-atom copy from backup, wrapped in try/except returning True/False (caller aborts game on False)"

# Metrics
duration: ~2 min
completed: 2026-08-05
---

# Phase 3 Plan 5: backup.py restore Summary

**FAILURE-PATH restore via cmd.delete+cmd.create two-step (sidesteps RESEARCH Q2 UNVERIFIED merge-vs-replace of single-call create), try/except returns True/False**

## Performance

- **Duration:** ~2 min (114 sec)
- **Started:** 2026-08-05T20:33:11Z
- **Completed:** 2026-08-05T20:35:05Z
- **Tasks:** 2 (1 implementation + 1 verification-only)
- **Files modified:** 1 (biochemeleon/backup.py)

## Accomplishments
- Added `restore(target_obj, backup_name=BACKUP_PREFIX)` to biochemeleon/backup.py — the FAILURE-PATH restore that brings the target back to its pre-mutation state (criterion 4 restore half).
- Uses the unambiguous `cmd.delete(target_obj)` + `cmd.create(target_obj, backup_name)` two-step — sidesteps RESEARCH section Q2's MEDIUM flag (single-call `cmd.create(existing, backup)` has UNVERIFIED C-dispatched merge-vs-replace semantics). The delete removes the mutated object entirely; the create makes a clean atom-for-atom copy from the backup.
- `try/except Exception` returns `True` on success, `False` on failure — caller aborts the game on `False` (never raises into the orchestrator).
- Updated module docstring for accuracy now that restore exists: lifecycle line "snapshot/restore/discard" (was "snapshot/discard half"), added a `restore` bullet to the API list, and updated the forward-ref line to "restore() added in plan 03-05; verify_intact() added in plan 03-08" (was "restore() and verify_intact() are added in plans 03-05 and 03-08").
- All WSL gates green: py_compile all modules + 90 unit tests + Pitfall-1/11 zero matches + anti-pattern gate visually confirmed (delete precedes create inside the try block).

## Task Commits

Each task was committed atomically:

1. **Task 1: add backup.py restore (delete+create, never single-call create)** - `d48c0d5` (feat)
2. **Task 2: run full WSL gate suite (no regression)** - no commit (verification-only per plan)

**Plan metadata:** _TBD — final docs commit below_

## Files Created/Modified
- `biochemeleon/backup.py` (41 -> 58 lines) — added `restore(target_obj, backup_name=BACKUP_PREFIX)` FAILURE-PATH restore (delete+create two-step, try/except returns True/False) after `discard` with a `# ---- Restore (plan 03-05) ----` section comment; updated module docstring (lifecycle line, restore bullet, forward-ref line). Inline source citations mirror the 03-02 snapshot style (commanding.py:496, creating.py:960).

## Decisions Made
- **restore uses delete+create two-step — NEVER single-call create.** RESEARCH section Q2 flags single-call `cmd.create(existing, backup)` as a MEDIUM-risk UNVERIFIED C-dispatched merge-vs-replace. The two-step is unambiguous: `cmd.delete(target_obj)` removes the mutated object entirely (commanding.py:496), then `cmd.create(target_obj, backup_name)` makes a fresh independent atom-for-atom copy from the backup (creating.py:960). This is the "restore" half of criterion 4.
- **restore placed AFTER discard, BEFORE the future verify_intact.** Mirrors the RESEARCH section "Backup/Restore Design" ordering (snapshot -> restore -> discard -> verify_intact) and keeps the failure-path restore grouped with the happy-path discard under the backup lifecycle section comments.
- **Docstring uses "RESEARCH section Q2" (prose "section") instead of the plan's literal "section Q2" symbol form.** Matches the existing in-file style precedent — backup.py line 9 already uses the prose form "per RESEARCH section Q6". In-file consistency wins over the plan's literal token; the substance (Q2 reference, the "single-call cmd.create(existing, backup) is UNVERIFIED C-dispatched" warning) is preserved verbatim.

## Deviations from Plan

None material — plan executed exactly as written. Two cosmetic notes (documented in Decisions Made, not functional deviations):

- The docstring reference uses the prose form "RESEARCH section Q2" (matching the existing in-file "RESEARCH section Q6" precedent) instead of the plan's literal "section Q2" symbol — in-file consistency.
- The plan's anti-pattern gate (`cmd\.create\(.*backup`) returns 2 matches, not 1: line 51 is the docstring WARNING text describing the anti-pattern we avoid (`single-call cmd.create(existing, backup) is UNVERIFIED C-dispatched`), and line 55 is the actual two-step call. This is plan-sanctioned — the plan's exact code includes the literal docstring mention, and the plan's gate explicitly anticipates it with a "visually confirm the delete precedes the create inside the try block" disambiguation step (line 54 delete precedes line 55 create — confirmed).

## Issues Encountered
None.

## User Setup Required
None — no external service configuration. Runtime/cmd-coupled behavior (delete+create atom-for-atom identity, try/except on missing backup/target) is deferred to the Phase 3 smoke test.

## Next Phase Readiness
- **backup.py lifecycle progress:** snapshot (03-02) + restore (03-05) + discard (03-02) now in place; `verify_intact` (03-08) remains — the full backup lifecycle will be complete after 03-08. The orchestrator's `abort_on_error` (game.py, later plan) will call `restore` then `verify_intact` to confirm the rollback landed atom-for-atom.
- **Runtime behavior deferred (WSL-unverifiable):** restore is cmd-coupled — `cmd.delete`/`cmd.create` behavior (atom-for-atom identity of the two-step, `try/except` returning `False` rather than raising on a missing backup or target) is WSL-unverifiable (no PyMOL in WSL; `py_compile` is syntax-only). Only the Phase 3 smoke test (plans 03-13/03-14, run via the 03-15 Windows PyMOL checkpoint) can confirm runtime behavior. The smoke test asserts: after restore, the target's atom count + structure match the pre-game backup exactly (criterion 4); `restore` returns `False` (not raises) when the backup is missing.
- **RESEARCH Q2 MEDIUM flag now sidestepped at implementation level** — the delete+create two-step avoids the UNVERIFIED merge-vs-replace question entirely; the smoke test will validate the sidestep by confirming atom-for-atom identity post-restore.
- **Wave 2 concurrent execution:** 03-05 (backup.py) is file-disjoint from 03-04 (registry.py + tests/test_registry.py) and 03-06 (mutation.py) — no merge conflict. STATE.md is the only shared file. Used plain `git commit` (never `--amend`) per the 03-03 concurrent-execution lesson; staged only `biochemeleon/backup.py`.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
