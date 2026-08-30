---
phase: 16-mvp-core-loop-sphere
plan: 07
subsystem: core-loop
tags: [sphere, placement, bbox, measure-minmax, uniform-random, mutation, game-loop, tcl, vmd]

# Dependency graph
requires:
  - phase: 16-mvp-core-loop-sphere (16-01)
    provides: "::biochemeleon::generators::sphere_positions {minmax n {seed {}}} — the pure uniform-bbox sampler this plan body-swaps into make_placeholder_hiders"
  - phase: 15-mutation-safety-hider-registry (15-02/15-04/15-05)
    provides: the make_placeholder_hiders swap point with FROZEN {molid count} signature + {name x y z} record shape; game.tcl composition root whose start_game call site must work unchanged
provides:
  - "make_placeholder_hiders performs REAL sphere placement: `measure minmax` on 'all' -> generators::sphere_positions (uniform-random inside the molecule's bounding box); signature/record shape frozen"
  - "mutation.tcl sources generators.tcl (pure, same lib/ dir) via the [file dirname [info script]] pattern — the dependency edge the entry (16-10) also carries"
  - "vmd/smoke/phase16_placement_smoke.tcl — headless proof of real placement geometry (bbox containment + non-degenerate) with sentinel/registry/cleanup regression (PASS=1 first run)"
affects: [16-08/16-09 (on_pick + game_logic score against genuinely-placed hiders), 16-10 (entry sources generators.tcl), 16-12 (GUI human-verify of the blending visual)]

# Tech tracking
tech-stack:
  added: []  # zero external deps — measure minmax (VMD built-in) + stdlib rand()
  patterns:
    - "Viewer-bridge fetch + pure sampler split: mutation.tcl measures the bbox (measure minmax) and feeds it IN; generators.tcl stays pure — the 16-01 boundary honored at the call site"
    - "Frozen-contract body swap: only the coordinate math changed; every downstream consumer (start_game, registry, cleanup) works with zero edits"

key-files:
  created:
    - vmd/smoke/phase16_placement_smoke.tcl
  modified:
    - vmd/lib/mutation.tcl

key-decisions:
  - "Port strategy 1:1 from v1 (04-01): uniform random in bbox, NO min-distance, NO overlap avoidance, NO clamping/inset — overlapping a real atom is harmless; do not invent surface-projection"
  - "NO seed in the production call path (sphere_positions $mm $count) — the global PRNG stream continues, same convention as randomize_state; reseeding per call would correlate placements with prior rand() consumers"
  - "Dropped the old catch-wrapped molinfo center: no molinfo call remains, so `measure minmax` on a bad molid raises naturally and game.tcl propagates (caller aborts — 15-05 behavior); errors are not swallowed"
  - "measure minmax return shape {{xmin ymin zmin} {xmax ymax zmax}} consumed via lassign into lo/hi then per-axis (probe-verified; molinfo-center nested-form Pitfall 4 not applicable — no molinfo in the body)"

patterns-established:
  - "Placement epsilon convention: smoke asserts containment within [min-0.001, max+0.001] per axis — covers the %8.3f PDB write round-trip (a value just under max can round up by <= 0.0005)"

# Metrics
duration: 8min
completed: 2026-08-30

---

# Phase 16 Plan 07: Real Sphere Placement Summary

**Body-swapped make_placeholder_hiders from center+jitter placeholders to real uniform-bbox placement (measure minmax -> pure 16-01 sampler) with the {molid count} / {name x y z} / G%02d contract frozen and zero downstream edits; phase16_placement_smoke proves bbox containment + non-degenerate geometry PASS=1 first run.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-30T10:01:12Z
- **Completed:** 2026-08-30T10:09:19Z
- **Tasks:** 2/2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- `mutation::make_placeholder_hiders` now places hiders at uniform-random points inside the molecule's bounding box: `measure minmax` on "all" -> `$all delete` -> `::biochemeleon::generators::sphere_positions $mm $count` -> `G%02d`-named `{name x y z}` records. Old center+jitter math fully removed.
- Frozen Phase-15 contract held: `{molid count}` signature and `{name x y z}` record shape unchanged; `write_combined_pdb` / `tag_sentinels` / `fetch_hider_indices` / `mutate` untouched; game.tcl's call site works with zero edits.
- `vmd/smoke/phase16_placement_smoke.tcl` (11-step headless proof, modeled on phase15_smoke): 1k8p 555->560 atoms, sentinels at indices 555-559, EVERY hider coordinate within the original real-atom bbox ±0.001, the 5 points not all identical, names G01..G05, registry 5->0 across cleanup, game_molid deleted (leak guard). **PASS=1 first run.**
- Regression insurance: phase15_mutation_smoke.tcl (direct make_placeholder_hiders caller) and phase15_smoke.tcl (capstone) re-run green against the swapped body — all Phase-15 behavior holds.

## Task Commits

Each task was committed atomically on branch `exec/16-07`:

1. **Task 1: Body-swap make_placeholder_hiders** - `b77f296` (feat)
2. **Task 2: Write + run the placement smoke** - `53a5e5d` (test)

_Plan metadata commit follows this summary (docs(16-07))._

## Files Created/Modified
- `vmd/lib/mutation.tcl` - make_placeholder_hiders body-swapped to measure-minmax + generators::sphere_positions; generators.tcl source line added; docstring rewritten (no molinfo/catch remains — bad molid raises naturally, game.tcl propagates)
- `vmd/smoke/phase16_placement_smoke.tcl` - headless placement smoke: bbox containment (±0.001), non-degenerate points, frozen sentinel/name/record contract, registry + cleanup regression

## Decisions Made
- Followed the plan's pre-derived key facts exactly (all four research-sourced decisions listed in key-decisions above): 1:1 v1 port, no seed in production, natural error propagation (no catch), minmax-as-2-element-list.
- Docstring reworded so `grep "generators::sphere_positions"` hits exactly the 1 call site (the verify criterion) — the comment names the module ("the PURE sampler in vmd/lib/generators.tcl") instead of repeating the qualified symbol.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `tclsh` is not installed in this WSL environment (STATE.md decision 13-01 documented this): the planned tclsh load-syntax check was replaced by the headless VMD smoke run, which sources mutation.tcl (and its new generators.tcl source line) in Task 2 — a strictly stronger check.
- Full-log discipline applied per the 14-02 false-PASS lesson: run logs scanned beyond the BCHM_SMOKE_RESULT marker; only benign VMD output present (1k8p "Unusual bond" nucleic-acid warnings on load, CUDA driver warning, top-level set echo).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- start_game now produces genuinely blended, uniformly-placed VDW sphere candidates on every demo (geometry proven headless; the blending VISUAL is 16-12's GUI human-verify checkpoint).
- Zero downstream changes were required — 16-08/16-09 (on_pick/game_logic) score against real coordinates with no further placement work; 16-10 sources generators.tcl in the entry (mutation.tcl already carries the edge itself).
- No blockers or concerns.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
