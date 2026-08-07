---
phase: 04-mvp-core-loop-sphere
plan: 01
subsystem: core-loop
tags: [random, sphere, generator, pure, tdd, geometry]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry
    provides: GameController.start(hider_specs) — the proven orchestrator that consumes (pos, rep) specs
provides:
  - "generate_sphere_positions(extent, n, seed) -> list[[x,y,z],...] — pure geometry core for sphere hiders"
  - "tests/test_generators.py — 8 WSL unit tests (count, bounds, determinism, edge cases)"
affects: [04-05 (__init__.py wiring calls generate_sphere_positions), 05 (line/stick/cartoon generators extend generators.py)]

# Tech tracking
tech-stack:
  added: []  # stdlib random only — no new dependencies
  patterns:
    - "Pure geometry module (generators.py) — stdlib random only, NO from pymol, WSL-unit-testable (mirrors registry.py/setup_state.py purity convention)"

key-files:
  created:
    - biochemeleon/generators.py
    - tests/test_generators.py
  modified: []

key-decisions:
  - "generators.py is PURE (stdlib random only, NO from pymol) — mirrors registry.py purity convention; the cmd-coupled caller (__init__.py in 04-05) fetches the bounding box via cmd.get_extent and feeds it here"
  - "Uniform random within bounding box is spec-compliant for MVP (HIDER-04: 'place anywhere'); min-distance/near-atom placement is Phase 5+"

patterns-established:
  - "Pure geometry module pattern: generators.py (pure) <- __init__.py (cmd-coupled caller). The pure function takes extent + n + seed, returns [[x,y,z],...]; the caller builds hider_specs = [(pos, 'spheres') for pos in positions] and calls GameController.start(hider_specs)"

# Metrics
duration: 20min
completed: 2026-08-08
---

# Phase 4 Plan 01: Sphere Generator Summary

**Pure stdlib-random sphere-hider generator (generate_sphere_positions) with 8 WSL unit tests, feeding (pos, 'spheres') specs to the proven GameController.start**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-07T19:52:53Z
- **Completed:** 2026-08-07T20:12:53Z
- **Tasks:** 3 (RED, GREEN, REFACTOR)
- **Files modified:** 2 (1 created source, 1 created test)

## Accomplishments
- Implemented `generate_sphere_positions(extent, n, seed)` — pure geometry function returning `n` uniform-random `[x,y,z]` positions within the bounding box
- 8 WSL unit tests covering count, bounds, seed determinism, seed difference, n=0, n=1, negative extent, and return-type verification (list of 3-element float lists)
- Confirmed purity: NO `from pymol`, NO `import pymol`, NO `import numpy` — stdlib `random` only
- No regression: 152 total tests green (8 generators + 90 setup_state + 54 registry)
- Ready for plan 04-05 to call `generators.generate_sphere_positions(cmd.get_extent(target), hider_count)`

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): add failing tests for generate_sphere_positions** - `e87e9ca` (test)
2. **Task 2 (GREEN): implement generate_sphere_positions (pure sphere generator)** - `e716db6` (feat)
3. **Task 3 (REFACTOR): no changes needed** - no commit (implementation was clean on first pass)

**Plan metadata:** pending (docs commit below)

## Files Created/Modified
- `biochemeleon/generators.py` — Pure sphere-hider generator (33 lines, stdlib random only). `generate_sphere_positions(extent, n, seed)` returns `n` uniform-random `[x,y,z]` positions within the bounding box. NO `from pymol`, NO `from pymol.Qt` — WSL-unit-testable, mirroring `registry.py` and `setup_state.py`.
- `tests/test_generators.py` — 8 WSL unit tests (106 lines). Mirrors the `test_registry.py` stub pattern (sys.modules MagicMock for pymol/pymol.Qt). Tests: count, bounds, seed_determinism, seed_difference, n_zero, n_one, negative_extent, returns_lists.

## Decisions Made
- **generators.py is PURE (stdlib random only):** mirrors `registry.py` purity convention (AGENTS.md: pure layer <- cmd-coupled layer; never reversed). The cmd-coupled caller (`__init__.py` in plan 04-05) fetches the bounding box via `cmd.get_extent` and feeds it here; the returned positions become `(pos, 'spheres')` specs for `GameController.start`.
- **Uniform random within bounding box is spec-compliant for MVP:** HIDER-04 says "place anywhere in the bounding region." No min-distance constraint or near-atom placement — those are Phase 5+ improvements. `rng.uniform` handles reversed bounds (min > max) by drawing in [max, min], so negative-extent boxes don't crash.
- **`seed` parameter for testability:** `random.Random(seed)` makes output deterministic. Tests use `seed=42` for determinism check and `seed=1` vs `seed=2` for difference check. Production callers pass `seed=None` (non-deterministic).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded docstring to avoid `from pymol` grep false-positive**
- **Found during:** Task 2 (GREEN — implement generators.py)
- **Issue:** The plan's `<implementation>` block specified the module docstring as "NO from pymol, NO from pymol.Qt." This literal text trips the purity gate grep (`grep -rnE "from pymol|import pymol"` returns 1 match — the docstring text, not an actual import). This is the exact AGENTS.md-documented false-positive pattern ("literal tokens in comments/docstrings trip this grep too") and mirrors the 03-02/03-03/03-06/03-09/03-10 precedent where "the plan's literal docstring would have tripped its own verification gate."
- **Fix:** Reworded to "NO ``pymol`` import, NO ``pymol.Qt`` import" (mirrors `registry.py` lines 7-8 exactly). The meaning is identical; only the literal grep-tripping tokens changed.
- **Files modified:** biochemeleon/generators.py (docstring line 3)
- **Verification:** Purity gate grep returns 0 matches after rewording. All 8 tests still pass.
- **Committed in:** e716db6 (Task 2 GREEN commit)

**2. [Rule 3 - Blocking] Recovered from parallel-agent git collision (wizard.py swept into GREEN commit)**
- **Found during:** Task 2 (GREEN — commit step)
- **Issue:** The initial GREEN commit (`3a4f8db`, now superseded) accidentally included `biochemeleon/wizard.py` (53 insertions belonging to the parallel 04-02 agent). The 04-02 agent had staged `wizard.py` in the shared git index before my `git add biochemeleon/generators.py && git commit`, so `git commit` swept in both files. This is the exact concurrent-execution git collision documented in STATE.md (03-03 precedent: "a concurrent-execution git collision — `git commit --amend` swept in the 03-02 agent's staged planning docs from the shared index").
- **Fix:** Recovered using the safe-amend-pattern: (1) `git reset --soft e87e9ca` (undo GREEN commit, keep changes staged), (2) `git reset HEAD biochemeleon/wizard.py` (unstage wizard.py), (3) `git commit` (re-commit only generators.py). wizard.py was left in the working tree (unstaged) for the 04-02 agent to commit. The superseded commit `3a4f8db` is in the reflog but not in the branch history.
- **Files modified:** none (git history fix only — generators.py content unchanged)
- **Verification:** `git show --stat e716db6` confirms only `biochemeleon/generators.py` (1 file, 33 insertions). wizard.py is in the working tree for 04-02.
- **Committed in:** e716db6 (clean re-commit, replaces superseded 3a4f8db)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both auto-fixes necessary for correct verification (purity gate) and clean git history (collision recovery). No scope creep.

## Issues Encountered
- Concurrent-execution git collision during the GREEN commit: the parallel 04-02 agent had staged `wizard.py` in the shared index, which was swept into my initial GREEN commit. Recovered via soft-reset + unstage + re-commit, leaving wizard.py in the working tree for 04-02. The parallel 04-03 agent's commit was also briefly orphaned by the recovery reset; 04-03 re-committed successfully on top of the clean history.

## User Setup Required

None — no external service configuration required. The sphere generator uses only stdlib `random` (no PyMOL, no numpy, no external dependencies).

## Next Phase Readiness
- `generate_sphere_positions(extent, n, seed)` is ready for plan 04-05 (`__init__.py` wiring) to call it as `generators.generate_sphere_positions(cmd.get_extent(target), hider_count)`.
- The returned positions become `hider_specs = [(pos, 'spheres') for pos in positions]`, fed into the proven `GameController.start(hider_specs)` (Phase 3, smoke-verified 24/24).
- Phase 5 will extend `generators.py` with `generate_line_stick_positions()` and `generate_cartoon_positions()` (following the same pure-module pattern).

---
*Phase: 04-mvp-core-loop-sphere*
*Completed: 2026-08-08*
