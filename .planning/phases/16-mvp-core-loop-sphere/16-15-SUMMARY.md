---
phase: 16-mvp-core-loop-sphere
plan: 15
subsystem: smoke-verification
tags: [tcl, vmd, headless-smoke, regression-gate, active-game-guard, double-start, restart, pdb-rebuild, viewpoint, tcl-8.5]

# Dependency graph
requires:
  - phase: 16-mvp-core-loop-sphere (16-13)
    provides: the active-game guard in game::start_game (cleanup-then-start with the CALLER's settings; dead-target remap by LIVENESS; stale-stash recovery) — the code under test
  - phase: 16-mvp-core-loop-sphere (16-11)
    provides: the $failures capstone harness pattern (per-stage catch + _bail + marker-only-when-empty) and BCHM_SMOKE_RESULT conventions
  - phase: 15-mutation-safety-hider-registry (15-05)
    provides: phase15_smoke.tcl's _flat/_vp_maxdiff recursive viewpoint flattener + the 4-matrix combined capture form; the game::start_game/cleanup public API; the catch-molinfo-nonzero leak-guard pattern
provides:
  - vmd/smoke/phase16_restart_smoke.tcl — the always-runnable headless gate that makes stacked hider generations a TESTED-IMPOSSIBLE state: 4 direct public-surface start_game calls (fresh start, mid-round double-start on the game molecule with a NEW count, after-win double-start [registry remaining 0], different-target restart) each asserting single-generation invariants (atoms = original + N, exactly N sentinels at the top indices, registry N rebuilt-per-round, old game molid DELETED, numreps = the round's own base + 2, viewpoint < 1e-4)
  - Probe-verified VMD 1.9.3 view model (probes in gitignored tmp/, not committed): the molinfo 4-matrix get reads the CURRENT SCENE VIEW for any molid and the scene view RESETS on every `mol new` (reference numbers: 0.7602817 = maxd(1k8p-fresh-default, rotated-lineage view); 35.525988 = inter-molecule center scale)
  - Regression proof that the 16-13 guard is a NO-OP for fresh-session starts: phase15_game_smoke / phase15_smoke / phase16_onpick_smoke / phase16_smoke all PASS=1 FAIL=none on the same fresh staging
affects: [16-16 (GUI re-check of the double-start defect — this smoke is its headless half), phase-19 (Game-tab Cleanup/Restart buttons build on the now-guarded start_game; documented cosmetic view wart on different-target start while a round is active), phase-17 rep generators (the guard path they start under is now regression-gated)]

# Tech tracking
tech-stack:
  added: []   # no new deps — VMD 1.9.3 tcl 8.5 stdlib only
  patterns:
    - "Guard regression-gate shape: repeated DIRECT invocation of the guarded public proc (never via on_pick/pick_bridge), one stage per scenario, each round asserted with the SAME single-generation invariant block via a shared _assert_round helper (atoms/sentinel-set/registry-count/numreps/viewpoint) + per-scenario leak guards (catch-molinfo-nonzero on the old game molid)"
    - "After-win simulation without game_logic: the game.tcl layer cannot distinguish won vs mid-round (both keep current_state), so registry::mark_found on every sentinel + count_remaining == 0 IS the faithful won-state precondition (mark_found is the same call on_pick makes)"
    - "Stage-C viewpoint reference = the round's OWN snapshot viewpoint (dict get $gs snapshot viewpoint) — model-independent SC4-forward fidelity — because the guard's cleanup legitimately resets the scene view via its restore's mol new before the new round's snapshot"
    - "_bail appends to ::failures GLOBALLY (lappend ::failures, not upvar 1) so calls from inside _assert_round (one frame deeper) cannot silently create a local list and lose tags"

key-files:
  created:
    - vmd/smoke/phase16_restart_smoke.tcl
  modified: []   # NO lib files touched — game.tcl's 16-13 guard proven correct as-is

key-decisions:
  - "Stage A2 targets the OLD GAME MOLECULE with a NEW count (2) — the exact observed defect path — and asserts NEW-count semantics (gs2.hider_count == 2, 555+2=557 atoms, sentinels {555 556}, registry 2 NEVER 5): a stacked generation would show 558+2=560 atoms with 5 sentinels."
  - "Stage B simulates the won state registry-side ONLY (mark_found x2 -> count_remaining == 0 + status_of == found) and does NOT source game_logic — the game.tcl layer cannot distinguish won vs mid-round, so remaining-0-with-all-found IS the won state as far as the guard can see."
  - "Stage C captures 1znf's liveness + rep base BEFORE start_game and asserts the live-target pass-through branch specifically (gs3's game molecule alive pre-start, dead post-start; the round-3 restored 1k8p original SURVIVES loaded via a [molinfo list] scan for a 555-atom 0-sentinel molecule; the 1znf original consumed by the mutate)."
  - "Stage-C viewpoint asserted against gs4's OWN snapshot viewpoint (not the vp_orig lineage): probe-verified that VMD 1.9.3's scene view resets on `mol new`, so the guard's cleanup (restore = mol new + apply) leaves the snapshot carrying the restored original's fresh-load view — a VMD semantics fact, NOT a guard defect; stages A/B keep the stronger vp_orig-lineage assert (0.0 there)."
  - "Stage-C numreps asserted against 1znf's OWN base (1) + 2 = 3: the round honors the NEW target's own snapshot, not the 1k8p setup's saved rep count — expecting 4 would actually require cross-target state bleed (a bug)."

# Metrics
duration: 22min
completed: 2026-08-30
---

# Phase 16 Plan 15: Active-Game Guard Restart Regression Smoke Summary

**Headless regression gate making the observed 561-atom/Segments-3 stacking defect TESTED-IMPOSSIBLE: 4 direct public-surface start_game calls (fresh start -> mid-round double-start -> after-win double-start -> different-target restart) each prove single-generation rounds (555->558->557->558->426 atom narrative, exact sentinel sets, per-round registry, dead old molids) — PASS=1 with the 4-smoke start_game suite green and zero lib changes (the 16-13 guard proven correct as-is).**

## Performance

- **Duration:** 22 min
- **Started:** 2026-08-30T16:21:37Z
- **Completed:** 2026-08-30T16:43:52Z
- **Tasks:** 2/2
- **Files modified:** 1 (1 created; stage-C invariants corrected in the same file after probe-driven diagnosis)

## Accomplishments

- `vmd/smoke/phase16_restart_smoke.tcl` (467 lines, min 150 met): the VERIFICATION gap-1 headless half. $failures capstone harness (per-stage catch + `_bail` + marker derives from the REAL list), `_flat`/`_vp_maxdiff` lifted verbatim from phase15_smoke.tcl, shared `_assert_round` invariant block, per-scenario leak guards. `BCHM_SMOKE_RESULT PASS=1 FAIL=none`, zero `ERROR)`/`bad switch`.
- All three gap scenarios proven through the public game surface ONLY (never on_pick, never pick_bridge):
  - **A (mid-round, NEW-count):** gs2 = start_game(gs1's game molid, 2) -> 557 atoms, sentinels {555 556}, registry 2 (never 5), gs1 game molid DEAD, numreps 4, vp < 1e-4.
  - **B (after win):** registry remaining 0 -> gs3 = start_game(gs2's game molid, 3) -> 558 atoms, {555 556 557}, registry 3, gs2 DEAD.
  - **C (different target):** 1znf (424, LIVE) with gs3 active -> gs4 = 426 atoms, {424 425}, registry 2, gs3 DEAD, 1znf consumed, the round-3 restored 1k8p original SURVIVES loaded (555-atom 0-sentinel scan).
- Regression sweep on the same fresh staging: phase15_game_smoke, phase15_smoke, phase16_onpick_smoke, phase16_smoke — all `PASS=1 FAIL=none`, zero `ERROR)`/`bad switch` (the guard is a no-op without an active stash).
- Log narrative verified: atom chain 555 -> 558 -> 557 -> 558 -> 426 (+ three 555 restores, one 424 load); `Segments: 2` on all 4 combined reloads, never 3; guard INFO fired 3x with 2 "starting on the restored original" remaps (A2, B) and a pass-through at C.
- **NO game.tcl / backup.tcl / any lib change needed** — the two red assertions in the first run were smoke-side model errors, diagnosed with three gitignored probes and fixed in the smoke (the owning file).

## Task Commits

Each task was committed atomically:

1. **Task 1: Write phase16_restart_smoke.tcl** - `926a2b9` (test)
2. **Task 2: Stage, run, regression-sweep; stage-C invariant corrections** - `69db365` (fix)

**Plan metadata:** `docs(16-15): complete plan` (this commit).

## Files Created/Modified

- `vmd/smoke/phase16_restart_smoke.tcl` (NEW) — the double-start regression gate: stage 0 (1k8p + VDW rep + mutated viewpoint -> saved_numreps + vp_orig), stage A1 (fresh start, guard must NOT fire, shape-frozen game_state), stage A2 (mid-round double-start, NEW-count semantics), stage B (after-win double-start via registry-side won-state), stage C (different-target live pass-through + survivor scan), marker + exit. Tcl 8.5 only; braced expr; sorted-list sentinel compares; every atomselect `$sel delete`; `BCHM_SMOKE_RESULT` marker before `exit`.

## Decisions Made

See key-decisions in frontmatter (summarized): exact-defect-path targeting for A2; registry-side won-state simulation for B (game_logic deliberately not sourced); liveness/rep-base pre-captures for C; stage-C viewpoint asserted against the round's own snapshot viewpoint; stage-C numreps against 1znf's own base.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stage-C numreps expectation used the wrong base (exp=4, got=3)**

- **Found during:** Task 2 (first run of the new smoke — `c_numreps:exp=4 got=3`)
- **Issue:** the shared `_assert_round` hardcoded the global `saved_numreps` (1k8p setup = 2). Stage C's round is built on 1znf's OWN snapshot (1 default rep), so the correct single-generation invariant is base + 2 = 3. Expecting 4 would demand cross-target rep bleed — i.e., would only pass if the guard were WRONG.
- **Fix:** `_assert_round` takes an explicit `base_reps` argument; stages A/B pass `saved_numreps`, stage C passes 1znf's own numreps captured after load.
- **Files modified:** vmd/smoke/phase16_restart_smoke.tcl
- **Verification:** re-run -> c_numreps green; sweep green.
- **Committed in:** 69db365

**2. [Rule 1 - Bug] Stage-C viewpoint reference assumed per-molecule stored views (exp vp_orig, maxdiff 35.5 then 0.76)**

- **Found during:** Task 2 (first run `c_vp:maxdiff=35.525988`; after the numreps fix `c_vp:maxdiff=0.7602817`)
- **Issue:** the first draft asserted gs4's view against 1znf's just-loaded default, then against the vp_orig lineage. Three gitignored probes (tmp/probe_vp*.tcl) proved VMD 1.9.3's molinfo 4-matrix get reads the CURRENT SCENE VIEW for any molid and the scene view RESETS on every `mol new` (probe3: the residual 0.7602817 is EXACTLY maxd(1k8p-fresh-default, vp_orig); 35.525988 is the inter-molecule scale). The guard's cleanup legitimately does a `mol new` (restore) before the new round's snapshot, so in the different-target flow the snapshot carries the restored original's fresh-load view — VMD semantics intersecting the cleanup ordering, NOT a stacking defect and NOT a guard defect.
- **Fix:** stage C asserts the model-independent SC4-forward fidelity: gs4's applied view == gs4's OWN snapshot viewpoint (`dict get $gs4 snapshot viewpoint`, < 1e-4). Stages A/B keep the stronger vp_orig-lineage assert (0.0 there: each cleanup's `mol new` runs on an otherwise-empty molecule set and its apply re-sets the view before the next snapshot). Mechanism documented in the smoke's VIEWPOINT MODEL NOTE header.
- **Files modified:** vmd/smoke/phase16_restart_smoke.tcl (NO lib files — game.tcl's guard confirmed correct)
- **Verification:** re-run -> PASS=1 FAIL=none; 4-smoke sweep green.
- **Committed in:** 69db365

---

**Total deviations:** 2 auto-fixed (2 bugs — both in the new smoke's first-draft assertions, found by the smoke's own red run and fixed in the owning file per the plan's Task-2 rule)
**Impact on plan:** No scope creep; no lib changes. The probes' VMD view-model finding is documented for Phase 19 (cosmetic wart: starting on a NEW target while a round is active shows the restored original's fresh-load view rather than the new target's last view — bounded, view-only, identical in kind to a plain fresh Start).

## Issues Encountered

- First run red (`c_numreps` + `c_vp`): resolved via the two deviations above; the guard narrative (3x "active game found", 2x remap) was already correct in that run.
- `tclsh` is not on PATH in this worktree shell, so the pre-run parse check (`info complete`) could not run; the headless VMD run itself is the authoritative parse/behavior gate and the full-log scan (zero `ERROR)` / `bad switch`) covers parse errors.
- VMD log lines are CRLF-terminated: `grep "Atoms: N$"` anchors fail — use `grep -oE "Atoms: [0-9]+"` style for narrative checks (runner-side note).
- Benign log noise as in all prior smokes: "Unusual bond" warnings (1k8p/1znf), CUDA banner, top-level `set` echoes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VERIFICATION gap 1 is now closed headlessly: the stacked-generation defect is a TESTED-IMPOSSIBLE state, re-runnable by any future verifier via `mkdir -p tmp/restart16 && cp -r vmd tmp/restart16/ && timeout 300 bash -ic 'cd tmp/restart16 && vmd -dispdev text -e vmd/smoke/phase16_restart_smoke.tcl -eofexit < /dev/null'`.
- 16-16 (GUI re-check) owns the interactive half of the double-start defect; this smoke is its always-runnable backstop.
- Phase 19 note carried: the Game-tab Cleanup/Restart work inherits the guarded start_game plus the documented VMD view-reset-on-mol-new wart (different-target start while a round is active shows the restored original's fresh-load view; if undesired, `mol top`/view re-assert after the guard's cleanup is the candidate fix — deliberately NOT changed here, out of 16-15 scope and the guard is not defective).
- VMD view-model facts for future viewpoint work (probe-verified, this plan): 4-matrix `molinfo get` reads the scene view for ANY molid; the scene view resets on `mol new`; `molinfo set` on the top molecule updates the scene view (stages A/B bit-stability).

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
