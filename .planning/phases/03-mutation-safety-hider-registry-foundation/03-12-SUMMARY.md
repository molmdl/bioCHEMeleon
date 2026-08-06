---
phase: 03-mutation-safety-hider-registry-foundation
plan: 12
subsystem: orchestration
tags: [game-controller, orchestrator, pymol-plugin, cmd-coupled, cleanup, abort-on-error, restore, verify-intact, criterion-4, sentinel, idempotent, phase-3]

# Dependency graph
requires:
  - phase: 03-02
    provides: backup.discard(backup_name) — the idempotent backup-deletion primitive both cleanup() and abort_on_error() call after their happy/failure path
  - phase: 03-05
    provides: backup.restore(target_obj, backup_name) — the delete+create two-step (NEVER single-call create) abort_on_error() calls on the failure path; returns True/False
  - phase: 03-08
    provides: backup.verify_intact(target_obj, backup_name) — the structure-integrity proof (count gate + atomic-tuple multiset) cleanup() returns as its criterion-4 verdict
  - phase: 03-09
    provides: mutation.cleanup_hiders(object) — the sentinel-based happy-path remove (atoms FROM the object, not the object) cleanup() calls first
  - phase: 03-11
    provides: GameController._started flag + _backup_name — the hooks this plan consumes (cleanup resets _started so a new round can start; abort uses _backup_name to restore)
provides:
  - GameController.cleanup() — happy path: sentinel remove (mutation.cleanup_hiders) + structure verify (backup.verify_intact) + discard; returns the verify_intact result (caller aborts on False)
  - GameController.abort_on_error() — failure path: backup.restore (delete+create two-step) + discard; returns the restore result
  - The key_link "cleanup -> verify_intact -> (if False) -> abort -> restore" (criterion 4 two paths)
  - game.py is functionally complete for Phase 3 (5 methods: __init__/start/reconstruct_registry/cleanup/abort_on_error)
affects: [03-13/03-14 smoke test (exercises cleanup happy-path + abort failure-path + verify_intact on both), 03-15 Windows PyMOL checkpoint (runs the smoke test), 04-game-loop (UI calls cleanup() on round-end + abort_on_error() on unexpected error / cleanup-returned-False), 08-persistence (reconstruct_registry + .bcm sidecar rep reconciliation; cleanup resets the registry so a reloaded round re-registers from sentinels)]

# Tech tracking
tech-stack:
  added: []   # no new libraries (pymol cmd + stdlib only)
  patterns:
    - "Criterion-4 two-path cleanup: cleanup() is the happy path (sentinel remove + verify_intact proves structure match + discard), abort_on_error() is the failure path (restore from backup + discard). Both reset _started + registry; both idempotent when not started. The verify_intact result is the criterion-4 proof on the happy path; the caller branches on it (False -> abort)."
    - "Idempotent-when-not-started guard: both cleanup() and abort_on_error() open with `if not self._started: return True` — defensive for UI double-clicks (a second cleanup() after the first is a no-op; no double-remove, no double-discard). Mirrors the backup.discard idempotency pattern (03-02)."
    - "Cleanup-by-sentinel is robust against registry loss: cleanup() removes hiders by the segi GAME sentinel (via mutation.cleanup_hiders), NOT by iterating the registry — a .pse reload that loses the in-memory registry still cleans up correctly (RESEARCH sec Q4). The registry is the source of truth for what was added, but cleanup itself does not depend on it."
    - "Return-the-verdict, don't raise: cleanup() returns the verify_intact bool (not raises), abort_on_error() returns the restore bool — lets the Phase 4 UI branch on the result without try/except. backup.restore already wraps cmd errors in try/except returning False (03-05); cleanup/abort propagate that contract."

key-files:
  created: []   # game.py already existed (Phase 1 stub -> 03-11 GameController -> this plan extends it)
  modified:
    - biochemeleon/game.py

key-decisions:
  - "cleanup() returns the verify_intact result (NOT a hardcoded True) — if False, the caller (Phase 4 UI) calls abort_on_error() to restore from backup. This is the key_link: cleanup -> verify_intact -> (if False) -> abort -> restore. The verify_intact result IS the criterion-4 proof on the happy path."
  - "abort_on_error() uses backup.restore (the delete+create two-step — RESEARCH sec Q2: NEVER single-call cmd.create(existing, backup) which is UNVERIFIED C-dispatched merge-vs-replace). backup.restore already implements the two-step (03-05) + try/except returning True/False; abort_on_error() just propagates that bool."
  - "Both methods reset _started=False + clear the registry (self.registry = registry.HiderRegistry()) — the round is over; a fresh start() builds a fresh registry per the 03-11 contract (start() sets self.registry = HiderRegistry() after snapshot)."
  - "Both are idempotent when not started (if not self._started: return True) — defensive for UI double-clicks (a second cleanup() after the first returns True, no-op; no double-remove, no double-discard on an already-discarded backup_name)."
  - "Cleanup is by-sentinel (mutation.cleanup_hiders selects segi GAME) — robust against registry loss on a .pse reload (RESEARCH sec Q4); the registry is the source of truth for what was added, but cleanup itself does not depend on the registry."
  - "cleanup() assigns `removed = mutation.cleanup_hiders(...)` (the before-count of sentinel atoms) but does not assert it against the registry length in Phase 3 — the variable is retained for debugging + the future smoke-test assertion (03-13/03-14); asserting here would require the registry to be intact, which contradicts the by-sentinel robustness goal."
  - "No docstring rewording needed (unlike 03-03/03-06/03-09/03-10) — the plan's prose docstrings ('discard backup.', 'restore from backup', 'verify_intact check', 'cleanup() returned False') avoided the dotted-literal false-positives on the 4 exact-count greps; the plan executed verbatim, 0 deviations. The orchestration gate (backup.|mutation.|registry.) counted 15 = 14 real dotted module calls + 1 docstring sentence-period ('discard backup.' on line 44) — a benign false positive on a minimum-bound (>=6) gate, not an exact-count gate."

patterns-established:
  - "Criterion-4 two-path contract lives at the orchestrator: cleanup() (happy) and abort_on_error() (failure) are the two ways a round ends; both leave the target atom-for-atom identical to its pre-game backup. The orchestrator (not the mutation/backup primitives) owns the round lifecycle (start -> play -> cleanup|abort)."
  - "Idempotent-when-not-started is the defensive guard for UI-exposed lifecycle methods: cleanup()/abort_on_error() return True when _started is False (no-op), so a double-click or a post-cleanup retry cannot double-remove sentinels or double-discard an already-discarded backup. The _started flag is the single source of truth for 'is a round in progress'."
  - "Return-the-verdict pattern: lifecycle cleanup methods return a bool verdict (verify_intact result for cleanup, restore result for abort) instead of raising — lets the UI branch without try/except; the underlying primitives (backup.restore) already swallow cmd errors into a bool (03-05)."

# Metrics
duration: ~2 min
completed: 2026-08-06
---

# Phase 3 Plan 12: GameController Cleanup + Abort Summary

**GameController cleanup() (sentinel remove + verify_intact + discard) and abort_on_error() (backup.restore delete+create + discard) — the criterion-4 two-path happy/failure cleanup, both idempotent when not started; game.py functionally complete for Phase 3 (5 methods)**

## Performance

- **Duration:** ~2 min (102 sec)
- **Started:** 2026-08-06T06:01:58Z
- **Completed:** 2026-08-06T06:03:40Z
- **Tasks:** 2 (1 implementation + 1 verification-only per plan)
- **Files modified:** 1 (biochemeleon/game.py)

## Accomplishments
- cleanup() happy path: mutation.cleanup_hiders (sentinel remove — atoms FROM the object, not the object) -> backup.verify_intact (criterion 4 proof: count gate + atomic-tuple multiset) -> backup.discard -> reset; returns the verify_intact result (caller aborts on False)
- abort_on_error() failure path: backup.restore (delete+create two-step — RESEARCH sec Q2, never single-call create) -> backup.discard -> reset; returns the restore result (True/False)
- Both reset _started=False + fresh registry (round over); both idempotent when not started (return True, no-op) — defensive for UI double-clicks
- key_link wired: cleanup -> verify_intact -> (if False) -> abort -> restore (criterion 4 two paths)
- game.py functionally complete for Phase 3: 5 methods (__init__/start/reconstruct_registry/cleanup/abort_on_error)
- All WSL gates green: py_compile all + 144 tests (no regression) + Pitfall-1/11 zero + completeness gate 5 + orchestration gate 15 (>= 6) + 4 exact-count greps (mutation.cleanup_hiders=1, backup.verify_intact=1, backup.restore=1, backup.discard=2)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add cleanup() + abort_on_error() to GameController** - `14cec23` (feat)
2. **Task 2: Run full gate suite + game.py completeness** - *(no commit — verification-only per plan; game.py was committed in Task 1)*

**Plan metadata:** *(pending — docs commit at end of plan)*

## Files Created/Modified
- `biochemeleon/game.py` — GameController + cleanup() + abort_on_error() (extends 03-11's 42-line GameController). cleanup() is the happy path: guards on `not _started` (idempotent True), calls mutation.cleanup_hiders (sentinel remove), backup.verify_intact (structure proof), backup.discard, resets _backup_name/_started/registry, returns the verify_intact bool. abort_on_error() is the failure path: guards on `not _started` (idempotent True), calls backup.restore (delete+create two-step), backup.discard, resets, returns the restore bool. Both reset _started=False + fresh registry (round over). 42 -> 69 lines (28 insertions).

## Decisions Made
- cleanup() returns the verify_intact result (NOT a hardcoded True) — if False, the caller (Phase 4 UI) calls abort_on_error() to restore from backup. This is the key_link: cleanup -> verify_intact -> (if False) -> abort -> restore. The verify_intact result IS the criterion-4 proof on the happy path.
- abort_on_error() uses backup.restore (the delete+create two-step — RESEARCH sec Q2: NEVER single-call cmd.create(existing, backup) which is UNVERIFIED C-dispatched merge-vs-replace). backup.restore already implements the two-step (03-05) + try/except returning True/False; abort_on_error() just propagates that bool.
- Both methods reset _started=False + clear the registry (self.registry = registry.HiderRegistry()) — the round is over; a fresh start() builds a fresh registry per the 03-11 contract (start() sets self.registry = HiderRegistry() after snapshot).
- Both are idempotent when not started (if not self._started: return True) — defensive for UI double-clicks (a second cleanup() after the first returns True, no-op; no double-remove, no double-discard on an already-discarded backup_name).
- Cleanup is by-sentinel (mutation.cleanup_hiders selects segi GAME) — robust against registry loss on a .pse reload (RESEARCH sec Q4); the registry is the source of truth for what was added, but cleanup itself does not depend on the registry.
- cleanup() assigns `removed = mutation.cleanup_hiders(...)` (the before-count of sentinel atoms) but does not assert it against the registry length in Phase 3 — the variable is retained for debugging + the future smoke-test assertion (03-13/03-14); asserting here would require the registry to be intact, which contradicts the by-sentinel robustness goal.
- No docstring rewording needed (unlike 03-03/03-06/03-09/03-10) — the plan's prose docstrings ("discard backup.", "restore from backup", "verify_intact check", "cleanup() returned False") avoided the dotted-literal false-positives on the 4 exact-count greps; the plan executed verbatim, 0 deviations. The orchestration gate (backup.|mutation.|registry.) counted 15 = 14 real dotted module calls + 1 docstring sentence-period ("discard backup." on line 44) — a benign false positive on a minimum-bound (>=6) gate, not an exact-count gate.

## Deviations from Plan

None - plan executed exactly as written.

The plan's provided docstrings used prose forms ("discard backup.", "restore from backup (delete+create)", "the verify_intact check fails", "cleanup() returned False") that avoided the dotted-literal false-positives (`mutation.cleanup_hiders` / `backup.verify_intact` / `backup.restore` / `backup.discard`) that tripped earlier plans' exact-count greps (03-03/03-06/03-09/03-10 each needed a Rule-3 docstring rewording). No rewording was needed this time — the plan's code passed all 4 exact-count greps + the completeness gate (5) + the orchestration gate (15 >= 6) on the first write. The single orchestration-gate false positive ("discard backup." sentence-period on line 44) is benign — it adds 1 to a minimum-bound (>=6) gate, not an exact-count gate, so it does not affect the verdict.

## Issues Encountered

None.

Note: The Grep tool was avoided for exact-count verification per the logged 03-07/03-10/03-11 caution (it cross-wires batch results when called in parallel, returning matches across the whole package rather than the single file specified). Exact per-file counts were confirmed via sequential bash `grep -nE` / `grep -cE` (and `grep -rnE` for the package-wide Pitfall-1/11 gates). This is verification-methodology hygiene only — no effect on the code or the outcome.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- game.py GameController is now functionally complete for Phase 3 (5 methods: __init__/start/reconstruct_registry/cleanup/abort_on_error). The 03-11 _started flag + _backup_name are the hooks this plan consumed (cleanup resets _started so a new round can start; abort_on_error uses _backup_name to restore). All three Phase-3 modules (backup/mutation/registry) are now wired into the orchestrator's full lifecycle.
- game.py is cmd-coupled — the runtime behavior (cleanup sentinel-remove + verify_intact happy-path, abort restore failure-path, both idempotent-when-not-started, both reset _started + registry) is WSL-unverifiable (no PyMOL in WSL; py_compile is syntax-only, the 144 unit tests exercise only the pure layer). Deferred to the Phase 3 smoke test (plans 03-13/03-14, run via 03-15 Windows PyMOL checkpoint). The smoke test asserts: cleanup_hiders removes N sentinels + verify_intact returns True (criterion 4 happy path); restore brings the target back atom-for-atom + verify_intact returns True (criterion 4 failure path); both reset _started so a new round can start.
- All WSL gates green (py_compile all + 144 tests + Pitfall-1/11 zero + completeness gate 5 + orchestration gate 15 >= 6 + 4 exact-count greps). No blocker for the WSL tier; the cmd-coupled runtime is the documented deferral.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
