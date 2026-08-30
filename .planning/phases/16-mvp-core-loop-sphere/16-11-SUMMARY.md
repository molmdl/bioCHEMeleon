---
phase: 16-mvp-core-loop-sphere
plan: 11
subsystem: testing
tags: [vmd, tcl-8.5, headless-smoke, pick-bridge, game-loop, capstone, tcltest]

# Dependency graph
requires:
  - phase: 16-mvp-core-loop-sphere (16-01..16-10)
    provides: sphere placement (generators + mutation), game_logic state machine/timer/log, hiders 2-rep visuals, game::on_pick scoring + callbacks, pick_bridge (trace-based delivery), game tab GUI wiring, entry fan-in
  - phase: 15-mutation-safety-hider-registry
    provides: PDB-rebuild mutate/restore pipeline, registry, game.tcl composition root (start_game/cleanup), backup snapshot/apply/restore
provides:
  - vmd/smoke/phase16_smoke.tcl — the Phase-16 EXIT GATE: one headless smoke proving the COMPLETE core loop end-to-end through the public composition surface (start_game -> hider reps -> countdown -> play -> pick_bridge-armed simulated picks via the REAL _on_event trace -> win + frozen timer -> deactivate -> cleanup), with BCHM_SMOKE_RESULT marker and in-smoke gates
  - Placement smoke re-sourced against the evolved start_game (hiders.tcl added) — whole-repo suite green on fresh staging
affects: [16-12 (GUI human-verify session locks the only remaining claims), phase-17 rep generators (loop is the contract they plug into), phase-19 cleanup/restart UI]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Capstone loop-composition smoke: one -e'd VMD run drives start_game -> countdown -> activate -> simulated picks through the REAL trace -> win -> deactivate -> cleanup; module-level behavior is NOT re-asserted (owned by 16-05..16-08 smokes)"
    - "Simulated-pick protocol (research pick SS4 item 3): set ::vmd_pick_atom/::vmd_pick_mol + write ::vmd_pick_event fires the registered write-trace -> _on_event -> game::on_pick; never call on_pick directly in loop smokes"
    - "Deactivate trace-gone proof needs a state-machine re-drive to playing first (the 'won' state gate would swallow the fire even with a live trace)"
    - "In-smoke file gates: scan vmd/lib for the 'mouse mode 4' userpoint trap (zero) + the _on_event {args} signature (present)"

key-files:
  created:
    - vmd/smoke/phase16_smoke.tcl
  modified:
    - vmd/smoke/phase16_placement_smoke.tcl

key-decisions:
  - "Capstone stages exactly the plan's 11 stages and does NOT re-assert module-level behavior (hiders/pick/onpick/gametab smokes own those) — the capstone composes the loop through the public surface only"
  - "Trace-gone after deactivate is proven BEHAVIORALLY (re-drive round_reset -> begin_countdown -> 4 ticks -> begin_play, then simulate a fire: no delivery) because a bare fire post-win is state-gated inert regardless of the trace; a catch-guarded `trace info` introspection is belt-and-suspenders"
  - "Timer asserted range-wise + frozen (two post-win timer_elapsed reads identical AND equal to the win callback's elapsed) — never exact values; sleeping is forbidden"
  - "Click-label hygiene is exercised by adding one label mid-loop (mimicking the C-side pick-atom label) and asserting the NEXT processed pick cleans it to the baseline"

patterns-established:
  - "Phase-16 exit-gate shape: public-surface loop composition + full-log false-PASS scan (ERROR)/bad switch) + in-smoke lib-file gates"

# Metrics
duration: 16min
completed: 2026-08-30
---

# Phase 16 Plan 11: Phase-16 Capstone Loop Smoke Summary

**One headless smoke drives the complete core loop end-to-end through the public surface — start_game (real sphere placement) -> hider reps -> countdown -> pick_bridge-armed simulated picks via the REAL _on_event trace -> win + frozen timer -> deactivate -> cleanup — PASS=1 first run; whole-repo suite green on fresh staging.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-08-30T11:28:08Z
- **Completed:** 2026-08-30T11:43:47Z
- **Tasks:** 2/2
- **Files modified:** 2 (1 created, 1 fixed)

## Accomplishments
- `vmd/smoke/phase16_smoke.tcl`: the Phase-16 EXIT GATE — 11 stages, each in catch + _bail, proving SC1/SC3 logic layers + SC2's delivery machinery + SC4's loop-exit cleanup headlessly; `BCHM_SMOKE_RESULT PASS=1 FAIL=none` on the FIRST run, full-log false-PASS scan clean (zero `ERROR)` / `bad switch`).
- The pick chain is exercised through pick_bridge's REAL `_on_event` (simulated fire: set `::vmd_pick_atom`/`::vmd_pick_mol`, write `::vmd_pick_event`) — `game::on_pick` is never called directly; the smoke explicitly does NOT claim VMD's C-side firing (that is 16-12's GUI session).
- Whole-repo regression sweep on fresh staging: 4 tcltest suites (18+47+8+15, Failed=0 x4) + 7 prior smokes all PASS=1; 8.6 + modeless gates zero matches.
- The only unproven Phase-16 claims remaining are GUI-only (real-click firing, found-marker visuals, modal countdown pacing) — handed to 16-12.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write the Phase-16 capstone smoke** - `0f1f063` (test)
2. **Task 2: Regression sweep + gates (placement-smoke re-source fix)** - `0f81f95` (fix)

## Files Created/Modified
- `vmd/smoke/phase16_smoke.tcl` (created) — Phase-16 capstone: complete loop through the public composition surface (start_game / set_callbacks / game_logic countdown+timer / pick_bridge activate + real-trace simulated picks / deactivate / cleanup), in-smoke gates, BCHM_SMOKE_RESULT marker
- `vmd/smoke/phase16_placement_smoke.tcl` (modified) — added `hiders` to the source list (start_game has called `hiders::add_hider_reps` since 16-08; call-time resolution needs the namespace before the first start_game call)

## Verification Results

- Capstone: `BCHM_SMOKE_RESULT PASS=1 FAIL=none` (first run); full-log scan: zero `ERROR)`, zero `bad switch`; VMD "Exiting normally"
- test_registry.test: `BCHM_TEST_RESULT Total=18 Passed=18 Failed=0 Skipped=0`
- test_setup_state.test: `BCHM_TEST_RESULT Total=47 Passed=47 Failed=0 Skipped=0`
- test_generators.test: `BCHM_TEST_RESULT Total=8 Passed=8 Failed=0 Skipped=0`
- test_game_logic.test: `BCHM_TEST_RESULT Total=15 Passed=15 Failed=0 Skipped=0`
- Smokes (all `BCHM_SMOKE_RESULT PASS=1 FAIL=none`, errscan 0): phase16_hiders, phase16_pick, phase16_placement (after fix), phase16_onpick, phase16_gametab, phase16_entry, phase15
- Gates: 8.6 idioms over vmd/lib + vmd/gui zero matches; `grab set` over vmd/gui zero matches; `mouse mode 4` over vmd/lib zero; `_on_event {args}` present in pick_bridge.tcl (also asserted inside the smoke)

## Decisions Made
- Capstone asserts the plan's 11 stages only — module-level behavior stays owned by the 16-05..16-08 smokes (no assertion staging).
- Trace-gone after deactivate proven behaviorally via a state-machine re-drive (round_reset -> begin_countdown -> 4 ticks -> begin_play -> fire -> no delivery), because the "won" state gate would swallow any fire even with a live trace; plus a catch-guarded `trace info` introspection.
- Timer frozen check = two post-win `timer_elapsed` reads identical AND equal to the win callback's elapsed (range >= 0), never exact values.
- Click-label hygiene exercised mid-loop (one manual `label add` mimicking the C-side pick label; the next processed pick cleans it to the baseline) so stage 9's "labels cleaned" assertion is non-vacuous.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] phase16_placement_smoke.tcl failed against the evolved start_game (regression sweep red)**

- **Found during:** Task 2 (regression sweep, fresh staging)
- **Issue:** the 16-07 smoke's source list (`setup_state, registry, demos, backup, mutation, game`) predates the 16-08 start_game hider-rep step — `start_game` now calls `hiders::add_hider_reps` at CALL time, so `start_game` errored with `invalid command name "::biochemeleon::hiders::add_hider_reps"` -> PASS=0
- **Fix:** added `hiders` to the smoke's source list (canonical entry order) + header comment updated; minimal diff in the OWNING file (the smoke, not game.tcl)
- **Files modified:** vmd/smoke/phase16_placement_smoke.tcl
- **Verification:** re-run PASS=1 FAIL=none, errscan 0
- **Committed in:** 0f81f95 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The fix was required to make the whole-repo sweep green (the plan's own Task 2 "fix anything red in the OWNING file" clause). No scope creep.

## Issues Encountered
None beyond the deviation above. (Benign log noise in every VMD run: 1k8p "Unusual bond" warnings, CUDA-driver mismatch banner, the expected `Added new Atoms label` line from the hygiene step.)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 16 is headless-COMPLETE: every claim reachable without a GUI is asserted green on fresh staging.
- 16-12 (GUI human-verify session) owns the only remaining claims: VMD's C-side pick firing on a real click (`mouse mode pick 2` -> `vmd_pick_event` + globals), found-marker visuals (hidden VDW/Element vs found VDW/ColorID-7 split), and the wall-clock pacing of the countdown/timer. Its verification script can reuse the capstone's staging.
- Post-lock actions per 16-RESEARCH-pick: update `vmd/AGENTS.md` picking section with the locked contract and remove the MEDIUM flag.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
