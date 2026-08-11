---
phase: 08-persistence-and-shareable-puzzles
plan: 01
subsystem: persistence
tags: [tdd, registry, reconciliation, bcm-sidecar, pure-layer, namedtuple]

# Dependency graph
requires:
  - phase: 03-game-state-and-mutation-safety
    provides: HiderRegistry + reconstruct_from_sentinels (dependency-injected sentinel rebuild, rep=None tolerance)
  - phase: 07-found-hider-management
    provides: registry.py module-level helpers section structure (reconcile_with_bcm placed after reconstruct_from_sentinels, before Phase 7 helpers)
provides:
  - HiderRegistry.reconcile_with_bcm pure method (~25 lines) — .bcm sidecar metadata merge onto sentinel-rebuilt records
  - ReconcileMismatches namedtuple (missing_from_bcm, missing_from_pse, bad_rep)
  - 12 unit tests in TestReconcileFromBcm (tests/test_registry.py)
affects: [08-02, 08-03, 08-05]

# Tech tracking
tech-stack:
  added: []  # stdlib namedtuple only (already used OrderedDict)
  patterns:
    - "Sentinel-first + .bcm reconcile: two-stage merge (.pse is loaded reality, .bcm is metadata)"
    - "Degraded-is-playable: reconcile never raises on corrupt sidecar (bad_rep stays None, bad_status defaults to hidden); refuse is the caller's policy"
    - "Ghost-entry prevention: .bcm-only hiders (not in sentinels) are NOT registered (would corrupt counts_by_rep + on_pick)"

key-files:
  created: []
  modified:
    - biochemeleon/registry.py
    - tests/test_registry.py

key-decisions:
  - "reconcile_with_bcm is pure (no pymol import) — mirrors the registry.py purity discipline; the .bcm hiders list is a plain list of dicts"
  - "Sentinel-first merge: .pse is loaded reality, .bcm is metadata; sentinel-only hider stays registered (rep=None, hidden, clickable); .bcm-only hider is NOT registered (ghost would corrupt counts_by_rep + on_pick)"
  - "Never raises on corrupt sidecar — bad_rep stays None, bad_status defaults to hidden (degraded is playable; refuse is caller's policy)"
  - "Docstring reworded to 'no pymol import' to avoid from-pymol grep false-positive (mirrors 03-10 precedent)"

patterns-established:
  - "Phase 8 reconcile pattern: reconstruct_from_sentinels (rep=None) -> reconcile_with_bcm (sets rep+status from .bcm) -> counts_by_rep reflects real reps (not all-zero)"
  - "ReconcileMismatches namedtuple as the caller-decision contract: the registry stays usable regardless; the caller logs warnings or refuses based on mismatch severity"

# Metrics
duration: 9min
completed: 2026-08-12
---

# Phase 8 Plan 01: reconcile_with_bcm TDD Summary

**Pure-layer .bcm sidecar reconciliation: HiderRegistry.reconcile_with_bcm merges .bcm per-hider metadata (rep + status + pos) onto sentinel-rebuilt records by (object, id) match, returning a ReconcileMismatches namedtuple — WSL-testable, no pymol import**

## Performance

- **Duration:** 9 min
- **Started:** 2026-08-11T22:14:07Z
- **Completed:** 2026-08-11T22:23:46Z
- **Tasks:** 3 (RED / GREEN / REFACTOR+gates)
- **Files modified:** 2

## Accomplishments
- TDD'd HiderRegistry.reconcile_with_bcm — the pure merge that overrides sentinel-rebuilt records (rep=None, all hidden) with .bcm per-hider metadata (rep + status + pos) by matching (object, int(id))
- Added ReconcileMismatches namedtuple (missing_from_bcm, missing_from_pse, bad_rep) as the caller-decision contract — the registry stays usable regardless of sidecar corruption
- 12 unit tests in TestReconcileFromBcm covering perfect match, 3 mismatch classes, bad_rep/bad_status tolerance, pos restore, empty/None bcm, object mismatch, id coercion, to_dict round-trip, and the load-bearing counts_by_rep regression
- Closed the rep=None limitation: after reconcile, counts_by_rep reflects .bcm reps (not all-zero from the sentinel-rebuild state) — reloaded games' per-rep counts + found-mgmt work again

## Task Commits

Each task was committed atomically (TDD RED/GREEN/REFACTOR cycle):

1. **Task 1 (RED): Write failing tests for reconcile_with_bcm** - `42cbd19` (test)
   - 12 tests in TestReconcileFromBcm + ReconcileMismatches added to import block
   - Failed with ImportError (ReconcileMismatches doesn't exist yet)
2. **Task 2 (GREEN): Implement reconcile_with_bcm + ReconcileMismatches** - `cb6dcc6` (feat)
   - reconcile_with_bcm method (~25 lines) + ReconcileMismatches namedtuple in registry.py
   - All 77 tests pass (65 existing + 12 new); purity intact (0 from pymol)
3. **Task 3 (REFACTOR + gates): Full WSL gate suite** - no commit (clean on first pass)
   - All 7 gates green (py_compile + 167 tests + Pitfall-1=0 + exec_=1 unchanged + purity=0 + reconcile_with_bcm=1 + ReconcileMismatches=1)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified
- `biochemeleon/registry.py` - Added `ReconcileMismatches` namedtuple (after constants section) + `HiderRegistry.reconcile_with_bcm` method (after reconstruct_from_sentinels) + `namedtuple` import from collections
- `tests/test_registry.py` - Added `ReconcileMismatches` to import block + `TestReconcileFromBcm` class (12 test methods) before `__main__` block

## Decisions Made
- **reconcile_with_bcm is pure (no pymol import)** — mirrors the registry.py purity discipline established in Phase 3. The .bcm hiders list is a plain list of dicts (the shape `registry.to_dict()` produces); the method mutates `self._records` in place and returns a ReconcileMismatches namedtuple.
- **Sentinel-first merge** — the .pse is loaded reality (atoms the player can click); the .bcm is metadata describing those atoms. A sentinel-only hider (missing from .bcm) stays registered with rep=None + status='hidden' (real atom, still clickable); a .bcm-only hider (not in sentinels) is NOT registered (ghost entry would corrupt counts_by_rep + on_pick). This follows the research §2 recommendation (Strategy A).
- **Never raises on corrupt sidecar** — bad_rep stays None (flagged in bad_rep list); unknown status defaults to hidden. Degraded is playable; refuse is the caller's policy (game.py / __init__.py decides whether to log warnings or refuse the load based on mismatch severity).
- **Docstring reworded to "no pymol import"** — the plan's implementation sketch had "Pure (no `from pymol`)" which tripped the purity grep gate (literal `from pymol` text in the docstring). Reworded to "no `pymol` import" matching the module docstring style (line 7-8) and the 03-10 precedent (reconstruct_from_sentinels docstring had the same false-positive issue).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed from-pymol grep false-positive in reconcile_with_bcm docstring**
- **Found during:** Task 2 (GREEN — implementing reconcile_with_bcm)
- **Issue:** The plan's implementation sketch had the docstring line "Pure (no ``from pymol``)." — the literal text `from pymol` in backticks tripped the registry.py purity gate (`grep -rnE "from pymol" biochemeleon/registry.py` returned 1 match instead of 0). This is the exact false-positive pattern AGENTS.md warns about (a docstring that said "from PyQt5 import" tripped the gate before) and the same issue hit in 03-10.
- **Fix:** Reworded to "Pure (no ``pymol`` import)." matching the module docstring style (line 7-8: "NO ``pymol`` import") and the 03-10 precedent (reconstruct_from_sentinels docstring reworded from "no `from pymol import cmd`" to "NO `pymol` import").
- **Files modified:** biochemeleon/registry.py (1 line in the reconcile_with_bcm docstring)
- **Verification:** `grep -rnE "from pymol" biochemeleon/registry.py | wc -l` returns 0; all 77 tests still pass.
- **Committed in:** cb6dcc6 (Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Trivial docstring reword to satisfy the purity gate. No scope creep; no behavior change.

## Issues Encountered
None - the TDD cycle was clean: RED failed with the expected ImportError, GREEN passed all 77 tests on first implementation run, no REFACTOR needed (implementation followed the plan sketch verbatim and was clean on first pass).

## User Setup Required
None - no external service configuration required. This is a pure-layer TDD plan (stdlib only, no PyMOL needed at runtime).

## Next Phase Readiness
- **Ready for 08-02-PLAN.md** — TDD build_bcm_dict + parse_bcm_dict in new persistence.py. The reconcile_with_bcm method + ReconcileMismatches namedtuple are now available for 08-03's apply_bcm_dict to call.
- **No blockers** — all WSL gates green, purity intact, existing tests pass unchanged (additive).
- **The rep=None limitation is now closable** — after reconcile, counts_by_rep reflects .bcm reps (not all-zero), and group_found_by_rep will work for found hiders (rep is no longer None). The load-bearing regression test (test_counts_by_rep_after_reconcile_reflects_bcm_reps) pins this.

---
*Phase: 08-persistence-and-shareable-puzzles*
*Completed: 2026-08-12*
