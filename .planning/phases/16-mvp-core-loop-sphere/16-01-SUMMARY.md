---
phase: 16-mvp-core-loop-sphere
plan: 01
subsystem: core-loop
tags: [random, sphere, generator, pure, tdd, geometry, tcl, tcltest]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: pure-layer tcltest-under-headless-VMD harness pattern (BCHM_TEST_RESULT marker, [pwd]-based source path) + global-PRNG seed convention
  - phase: 15-mutation-safety-hider-registry
    provides: make_placeholder_hiders swap point in mutation.tcl (frozen {molid count} signature) that Plan 16-07 body-swaps to call this sampler
provides:
  - "::biochemeleon::generators::sphere_positions {minmax n {seed {}}} -> list of {x y z} triples — pure sphere-position sampler (tcl 8.5 port of v1 generators.py::generate_sphere_positions)"
  - "vmd/tests/test_generators.test — 8-case tcltest suite under the headless-VMD BCHM_TEST_RESULT harness"
affects: [16-07 (body-swap into make_placeholder_hiders via generators::sphere_positions $mm $count), 17 (rep-tier generators extend generators.tcl)]

# Tech tracking
tech-stack:
  added: []  # stdlib rand()/srand only — zero external deps
  patterns:
    - "Pure geometry module (generators.tcl) — mirrors setup_state/registry purity convention; the viewer-bridge caller (16-07 mutation.tcl) fetches the box via measure minmax and feeds it IN"

key-files:
  created:
    - vmd/lib/generators.tcl
    - vmd/tests/test_generators.test
  modified: []

key-decisions:
  - "minmax is RECEIVED, never measured — the sampler never calls measure; fetching the bbox is the caller's (16-07) viewer-bridge job, keeping the module pure and tcltest-able"
  - "Seed seeds the GLOBAL PRNG once at proc top (expr srand($seed)); production callers pass NO seed (continuous stream, randomize_state convention, setup_state Pitfall 4)"
  - "Uniform-random-in-bbox ported 1:1 from v1 (no min-distance constraint / near-atom placement — v1 explicitly deferred those; HIDER-03 place-anywhere-in-the-bounding-region read literally)"
  - "Degenerate box (min==max) handled by the formula itself (rand()*0 == 0) — no special-casing needed; numeric-equality asserted in the test, not string equality (float-formatting independence)"

patterns-established:
  - "Pure geometry module pattern: generators.tcl (pure) <- mutation.tcl (viewer-bridge caller, Plan 16-07) — same shape as v1 generators.py <- __init__.py"

# Metrics
duration: 21min
completed: 2026-08-30
---

# Phase 16 Plan 01: Pure Sphere Sampler Summary

**Pure stdlib sphere_positions {minmax n {seed}} bbox sampler (tcl port of v1 generators.py) with an 8-case tcltest suite, green 8/8 under headless VMD — the geometry core Plan 16-07 body-swaps into make_placeholder_hiders**

## Performance

- **Duration:** 21 min
- **Started:** 2026-08-30T09:05:29Z
- **Completed:** 2026-08-30T09:26:03Z
- **Tasks:** 3 (RED, GREEN, REFACTOR+gates)
- **Files modified:** 2 (both created; nothing modified)

## Accomplishments
- `vmd/lib/generators.tcl` — PURE stdlib module exporting `sphere_positions {minmax n {seed {}}}` → list of `{x y z}` triples, uniform-random inside the box (v1 formula ported 1:1); purity gate zero matches, Tcl 8.6-idiom gate zero matches
- `vmd/tests/test_generators.test` — 8-case tcltest port of v1's `TestGenerateSpherePositions` (count, bounds, seed determinism, seed difference, n=0, n=1, degenerate box, list-of-triples), all seeded via the `seed` arg so results never depend on residual global PRNG state
- TDD cycle: RED proven (Total=8 Failed=8 on missing module), GREEN first-run pass (Total=8 Passed=8), REFACTOR skipped (implementation already minimal — no commit needed)
- Ready for Plan 16-07 to call `::biochemeleon::generators::sphere_positions $mm $count` from `make_placeholder_hiders`

## Task Commits

Each task was committed atomically (TDD pattern):

1. **Task 1 (RED): add failing test_generators suite (pure sphere sampler)** - `8f3734e` (test)
2. **Task 2 (GREEN): implement sphere_positions (uniform-random bbox sampler)** - `f417f76` (feat)
3. **Task 3 (REFACTOR): no changes needed** - no commit (implementation was clean on first pass)

**Plan metadata:** committed below as `docs(16-01): complete pure sphere sampler plan`

## Files Created/Modified
- `vmd/lib/generators.tcl` — PURE sphere-position sampler (45 lines, stdlib rand()/srand only). `sphere_positions {minmax n {seed {}}}` receives the probe-verified `measure minmax` shape `{{xmin ymin zmin} {xmax ymax zmax}}` and returns `n` uniform-random `{x y z}` triples; seeds the global PRNG once when `seed` is non-empty; n≤0 → empty list; degenerate box (min==max) → n identical points with no error. Header documents purpose (HIDER-03), purity, minmax shape, and the global-PRNG seed rule.
- `vmd/tests/test_generators.test` — 8-case tcltest suite (96 lines) mirroring `test_registry.test`'s headless-VMD harness (`package require tcltest`, `[pwd]`-based source path, `BCHM_TEST_RESULT` marker read before `cleanupTests`). Standard box `{{-10 -20 -30} {10 20 30}}`; degenerate case `{{5 5 5} {5 5 5}}` with numeric-equality tolerance (1e-9).

## Decisions Made
- **minmax is a received value, not a measurement:** the sampler never calls `measure` (that would break purity); Plan 16-07's `make_placeholder_hiders` does `[measure minmax $all]` and passes `$mm` in — exactly the research §3.3 swap shape.
- **Seed-once global-PRNG rule:** seed only when the argument is non-empty, at proc top; never reseed per point. Production callers pass no seed so the global stream stays continuous (same convention as `randomize_state` → `randomize_per_rep`).
- **v1 strategy ported as-is:** uniform-random-in-bbox, no min-distance/overlap-avoidance/surface-snapping (04-01 precedent; HIDER-03 read literally). Research §3.4: don't clamp/inset the box or avoid real atoms.
- **Numeric-equality for the degenerate box test:** `abs(coord - 5.0) < 1e-9` instead of string comparison, so the assertion is independent of float formatting.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None blocking. One benign observation for future RED phases: a missing-module RED surfaces as `couldn't read file .../generators.tcl: no such file or directory` (NO `ERROR)` prefix) and headless VMD's `-e` continues past it, so the tcltest suite still registers and fails 8/8 (`invalid command name` in each body) — the marker remains trustworthy. The full-log false-PASS guard (`ERROR)` / `bad switch` / `invalid command` / `FAILED` / `couldn't read`) was added to the GREEN/REFACTOR re-runs per the Phase-15 lesson and returned 0 matches.

## User Setup Required

None — no external service configuration required. The sampler uses only stdlib `rand()`/`srand()` (no viewer API, no GUI toolkit, zero dependencies).

## Next Phase Readiness
- `sphere_positions` is ready for Plan 16-07: `set pts [::biochemeleon::generators::sphere_positions $mm $count]` inside `make_placeholder_hiders` (research §3.3 swap point; `{name x y z}` record shape and `{molid count}` signature stay frozen per 15-05).
- The pure module + pure-test harness pattern (`generators.tcl` + `test_generators.test`) is the template Phase 17's rep-tier generators extend (line/stick/cartoon generators).
- Contract pinned by tests: count == n, per-axis bounds, seed determinism (`eq`), seed difference, n=0 → empty, n=1, degenerate box → n identical points, every element a 3-element numeric list.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
