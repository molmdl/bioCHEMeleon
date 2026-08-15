---
phase: 11-alt-conf-cartoon-hider
plan: 01
subsystem: testing
tags: [pymol, pure-layer, generators, tdd, random, geometry, alt-conf]

# Dependency graph
requires:
  - phase: 05-cartoon-hider
    provides: generators.py purity convention + cas_by_chain shape {chain: [(resi, ca_id), ...]} from pick_terminal_residues
provides:
  - pick_segments(cas_by_chain, count, segment_size=3) -> [(chain, start_resi, end_resi), ...] disjoint mid-chain segment picker
  - generate_middle_displacement(n, seed, magnitude=1.5) -> [[dx,dy,dz], ...] rigid unit-vector x magnitude displacements
affects: [11-04 (insert_altconf_cartoon_hider consumes both), 11-06 (_prepare_and_start 4-tuple payloads), 11-07 (headless smoke), 11-08 (human-verify)]

# Tech tracking
tech-stack:
  added: []  # stdlib random only — no new libraries
  patterns:
    - "Pure-layer generator convention (mirrors registry.py/setup_state.py): stdlib only, NO from pymol, WSL-unit-testable"
    - "TDD RED-GREEN for pure functions (RED ImportError -> GREEN implementation)"
    - "Gauss-normalized unit vectors for unbiased sphere sampling (vs uniform-in-cube directional bias)"

key-files:
  created: []
  modified:
    - biochemeleon/generators.py
    - tests/test_generators.py

key-decisions:
  - "Deterministic centered windows for single picks (no RNG) — more testable than jittered placement"
  - "Greedy spread skipping the pure N-term window for multi-picks — guarantees Bug 1 disjointness"
  - "Gauss-normalized unit vectors (3 standard-normal components normalized) for displacement — avoids directional bias of uniform-in-cube"
  - "Division-by-zero guard for vanishing all-zero gauss (defensive, Rule 2)"

patterns-established:
  - "pick_segments contract: (chain, start_resi, end_resi) 3-tuples — resi values (NOT ca_ids); consumed by Plan 04 dispatcher + Plan 06 _prepare_and_start"
  - "generate_middle_displacement contract: [[dx,dy,dz], ...] one rigid vector per hider — caller applies same vector to ALL middle atoms via alter_state (Pitfall 15)"

# Metrics
duration: 5 min
completed: 2026-08-15
---

# Phase 11 Plan 01: Pure Generators Summary

**Two pure WSL-testable generator functions for the alt-conf cartoon/ribbon hider: disjoint mid-chain segment picker + rigid unit-vector displacement (stdlib random only, NO pymol)**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-08-15T08:30:36Z
- **Completed:** 2026-08-15T08:35:12Z
- **Tasks:** 2 (each TDD RED+GREEN)
- **Files modified:** 2

## Accomplishments
- `pick_segments(cas_by_chain, count, segment_size=3)` — returns disjoint mid-chain `(chain, start_resi, end_resi)` tuples; Bug 1 fix (ranges non-overlapping so two alt-conf hiders never share a clickable middle CA id); skips short chains; longest-first; count-capped. Single pick = centered window (mid-chain, not terminal — the Phase 11 replacement of terminal-extension); multi-pick = greedy spread skipping the pure N-term window.
- `generate_middle_displacement(n, seed=None, magnitude=1.5)` — returns `n` rigid `[dx,dy,dz]` unit vectors × magnitude (default 1.5 Å); deterministic by seed; one vector per hider (caller applies same offset to ALL middle atoms — Pitfall 15 rigid translation); gauss-normalized for unbiased sphere sampling; division-by-zero guard.
- Both functions are PURE (stdlib `random` only, NO `from pymol`, NO numpy) — preserve the WSL-unit-testable convention of `generators.py`/`registry.py`/`setup_state.py`.
- 14 new unit tests (7 per function) + 21 existing generator tests = 35 green; 252 full pure-layer suite green (no regression).

## Task Commits

Each task was committed atomically (TDD RED then GREEN):

1. **Task 1 RED: pick_segments failing tests** — `e62eaf4` (test)
2. **Task 1 GREEN: implement pick_segments** — `02e21ac` (feat)
3. **Task 2 RED: generate_middle_displacement failing tests** — `0af18f4` (test)
4. **Task 2 GREEN: implement generate_middle_displacement** — `2d2b4c4` (feat)

_No REFACTOR commits — implementations were clean on first GREEN._

## Files Created/Modified
- `biochemeleon/generators.py` — added `pick_segments` (mid-chain segment picker) + `generate_middle_displacement` (rigid displacement RNG); module docstring updated with the two new functions. Pure (stdlib `random` only).
- `tests/test_generators.py` — added `TestPickSegments` (7 tests) + `TestGenerateMiddleDisplacement` (7 tests); import block extended; `import math` added for norm assertions.

## Decisions Made
- **Deterministic centered windows (no RNG) for pick_segments** — the plan permitted RNG jitter but noted "deterministic centered windows are fine and more testable — PREFER deterministic." Centered windows make the mid-chain position assertion (start_resi==2, end_resi==4 for a 5-residue chain) exact and stable.
- **Gauss-normalized unit vectors for displacement** — the plan's implementation guidance specified sampling 3 standard-normal components and normalizing (avoids the directional bias of uniform-in-cube sampling where corners are over-represented). Mirrors the `random.Random(seed)` style of the existing `generate_sphere_positions`/`generate_line_stick_offsets`.
- **Division-by-zero guard** — 3 continuous gaussians all being ~0 has probability 0, but a defensive fallback (`[1,0,0]`) prevents a crash if it ever occurs (Rule 2 — missing critical safety).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Relaxed unsatisfiable C-term assertion in test_disjoint_segments_multi_count**
- **Found during:** Task 1 (RED — TestPickSegments)
- **Issue:** The plan's test 4 specified data `{'A': [(1,101),...,(7,107)]}` with `count=2, segment_size=3` and asserted "Both must be mid-chain (not the N-term resi 1 nor the C-term resi 7 as a segment endpoint)." This is mathematically unsatisfiable: two disjoint size-3 windows need 6 of 7 residues; avoiding BOTH terminals (resi 1 and resi 7) leaves only 5 residues (< 6). The only disjoint pair avoiding the N-term is `[2-4]` & `[5-7]`, where `[5-7]` necessarily ends at the C-term resi 7.
- **Fix:** Kept the N-term avoidance assertion (the PRIMARY Phase 11 intent — replacing terminal-extension means the first segment must not start at resi 1) and relaxed the C-term part. Added `assertNotEqual(segs[0][1], 1)` (first segment not N-term) + `assertNotEqual((seg[1],seg[2]), (1,3))` (no pure N-term window). Documented the C-term inevitability in the test docstring.
- **Files modified:** tests/test_generators.py
- **Verification:** 35 generator tests green; the disjointness assertion (`end_first < start_second`) still holds for `[2-4]` & `[5-7]`.
- **Committed in:** e62eaf4 (Task 1 RED commit)

---

**Total deviations:** 1 auto-fixed (1 bug — unsatisfiable test assertion)
**Impact on plan:** Minimal — the relaxed assertion still captures the core mid-chain intent (avoiding N-term extension). The C-term avoidance is impossible with the given data and count; Plan 04/06 will use real protein chains (typically 50+ residues) where both terminals can be avoided.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required. Pure stdlib functions.

## Next Phase Readiness
- `pick_segments` and `generate_middle_displacement` are ready for Plan 04 (`insert_altconf_cartoon_hider`) which consumes `(chain, start_resi, end_resi)` tuples from `pick_segments` and `[dx,dy,dz]` vectors from `generate_middle_displacement` (applied to middle backbone atoms via `cmd.alter_state`).
- Plan 06 (`_prepare_and_start`) will build 4-tuple payloads `(chain, start_resi, end_resi, displacement_vec)` from these two functions.
- No blockers. The purity convention is intact (generators.py has NO `from pymol`), so all downstream consumers import from the pure layer as before.

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
