---
phase: 15-mutation-safety-hider-registry
plan: 05
plan_name: Phase-15 capstone smoke (SC1-SC4 integration gate)
subsystem: smoke-verification
tags: [tcl, vmd, capstone, integration-smoke, headless, pdb-rebuild, registry, viewpoint-restore, sc1-sc4, composition-root, game-api]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: "[pwd]-based headless smoke conventions + BCHM_SMOKE_RESULT marker ([info script] empty under -e; VMD never propagates exit codes)"
  - phase: 14-setup-tab-bundled-demos
    provides: demos::load_demo (1k8p bundled, 555 atoms) + to_vmd_path staging pattern
  - phase: 15-mutation-safety-hider-registry (Plan 01)
    provides: registry::count_hiders + is_hider + reset (the SC3 assertions)
  - phase: 15-mutation-safety-hider-registry (Plan 02)
    provides: mutation::make_placeholder_hiders + mutate (writepdb-then-splice PDB-rebuild producing 555+5=560 atoms with tagged sentinels)
  - phase: 15-mutation-safety-hider-registry (Plan 03)
    provides: backup::snapshot/apply/restore (reps + viewpoint round-trip; 2-arg restore deleting the LIVE game_molid)
  - phase: 15-mutation-safety-hider-registry (Plan 04)
    provides: game::start_game/cleanup (the composition-root API this capstone exercises exclusively) + the 1-arg-molinfo 4-matrix combined get form
provides:
  - "vmd/smoke/phase15_smoke.tcl -- the Phase-15 EXIT GATE: the full backup -> mutate -> reconstruct -> cleanup -> restore pipeline proven end-to-end through the public composition-root API only (game::start_game / game::cleanup), with rigorous SC1-SC4 assertions (sentinel indices + segid + original-atom intact + registry exact-set + rep count + viewpoint maxdiff < 1e-4)"
  - "Proof the highest-risk VMD-specific unknown (PDB-rebuild; VMD has no in-place atom insertion) is de-risked: a real 555-atom demo + 5 hiders round-trips cleanly"
  - "The recursive _flat/_vp_maxdiff viewpoint-flattener pattern (nested 4x4 matrices; naive abs() errors) established for any future viewpoint compare"
affects:
  - "16-mvp-loop (sphere generator + PickBridge click loop): builds directly on this proven foundation -- Phase 16 only swaps make_placeholder_hiders for real sphere placement; start_game/cleanup/game_state are frozen"
  - "17.1/17.2 rep generators: the SC4 rep-restore path (backup::apply form B) is the mechanism generators' reps survive the PDB-rebuild"

# Tech tracking
tech-stack:
  added: []   # no new deps -- VMD 1.9.3 tcl 8.5 stdlib only
  patterns:
    - "Capstone-through-public-API: the integration smoke calls ONLY game::start_game + game::cleanup; backup/mutation/registry are never called directly (their isolated behavior is already proven by the Wave-1/2 module smokes) -- proves the composition root wires everything"
    - "Recursive viewpoint flattener (_flat/_vp_maxdiff, from 15-RESEARCH-backup-restore.md lines 360-377, probe-verified): molinfo's 4-matrix combined get is NESTED; flatten then per-element abs() with 1e-4 tolerance -- NOT string-eq (float drift), NOT naive abs (errors)"
    - "Viewpoint capture uses the EXACT positional field order backup::snapshot uses ({rotate_matrix center_matrix scale_matrix global_matrix}) so the round-trip compare is apples-to-apples"
    - "False-pass guards layered: (a) every step in catch + _bail so a mid-script error can't silently skip asserts; (b) SC2d catch-molinfo-nonzero proving the LIVE game_molid was DELETED (not the dead snapshot.molid); (c) runner greps the marker AND scans for ERROR) lines (VMD -e catches top-level errors and continues)"

key-files:
  created:
    - vmd/smoke/phase15_smoke.tcl
  modified: []   # no lib files touched -- zero deviations, zero bug fixes needed

key-decisions:
  - "1k8p (555 atoms) + 5 hiders per the plan -- larger than 15-04's 1znf (424+2), proving the pipeline scales beyond the module-smoke body. 555+5=560; sentinels at indices 555-559."
  - "Capstone drives ONLY game::start_game/game::cleanup (the orchestrator) -- this is the plan's explicit requirement (proves integration through the public composition-root API, unlike the Wave-1/2 module smokes which called bridges directly)."
  - "vp_orig/vp_restored captured with the SAME combined-braces molinfo get form + positional field order as backup::snapshot -- the flattener then compares identical structures (the viewpoint_maxdiff debug path: field-order mismatch is exactly what this prevents)."
  - "dict get $gs game_molid wrapped in its own catch (gs_key_game_molid tag) so a malformed game_state records a FAIL tag instead of raising a top-level error VMD -e would swallow (false-PASS hardening; within the plan's wrap-every-op-in-catch guidance)."
  - "SC2d implemented as catch {molinfo $game_molid get numatoms} nonzero -> game_molid_leaked tag -- the plan's explicit false-pass guard proving cleanup's backup::restore deleted the LIVE game_molid (not the dead snapshot.molid; the Plan-03/04 leak blocker)."

# Metrics
duration: 18min
completed: 2026-08-30
---

# Phase 15 Plan 05: Mutation Safety & Hider Registry Capstone Summary

**The Phase-15 exit gate: one headless smoke drives the full backup -> mutate -> reconstruct -> cleanup -> restore pipeline on 1k8p (555 atoms) + 5 hiders EXCLUSIVELY through `game::start_game`/`game::cleanup` and proves all 4 success criteria with rigorous assertions -- `BCHM_SMOKE_RESULT PASS=1 FAIL=none` on the first run, zero `ERROR)` lines, zero lib fixes needed.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-08-30T06:56:10Z
- **Completed:** 2026-08-30T07:13:43Z
- **Tasks:** 1/1 complete
- **Files:** 1 created (vmd/smoke/phase15_smoke.tcl); 0 modified

## Accomplishments

- Wrote `vmd/smoke/phase15_smoke.tcl` (209 lines) -- the Phase-15 capstone. Sources the 6 lib files in dependency order directly (`setup_state -> registry -> demos -> backup -> mutation -> game`; mirrors the entry, avoids GUI/dialog baggage; registry sourced ONCE). Drives the pipeline ONLY through the public composition-root API: `game::start_game $orig_molid 5` -> `game::cleanup $gs`.
- SETUP stage: `demos::load_demo 1k8p` (asserted 555 atoms), VDW rep added (numreps 1 -> 2), viewpoint mutated (`rotate x by 30; rotate y by 45; scale to 0.8; translate by 0.5 0.5 0.5`), `saved_numreps` + `vp_orig` recorded with backup::snapshot's exact positional 4-matrix form.
- ALL 4 success criteria asserted rigorously and passed on the first run under headless VMD (`BCHM_SMOKE_RESULT PASS=1 FAIL=none`; zero `ERROR)` lines in the full log):

| SC | Assertion | Result |
| --- | --- | --- |
| SC1a | game_molid numatoms == 560 (555+5) | PASS (log: Atoms: 560, Segments: 2) |
| SC1b | `resname GAM and beta < 0` num==5; indices `{555 556 557 558 559}`; segid `GAME`x5 | PASS |
| SC1c | atom 0 name == "N1" (original intact) | PASS |
| SC2a | restored numatoms == 555 | PASS (log: Atoms: 555) |
| SC2b | restored numreps == saved_numreps (2) | PASS |
| SC2c | restored sentinel count == 0 | PASS |
| SC2d | `catch {molinfo $game_molid get numatoms}` nonzero (LIVE game_molid DELETED) | PASS |
| SC3a | count_hiders == 5; is_hider 555..559 all true; is_hider 0 false | PASS |
| SC3b | count_hiders == 0 after cleanup | PASS |
| SC4-forward | game_molid numreps == saved_numreps (backup::apply) | PASS |
| SC4-restore | `_vp_maxdiff(vp_orig, vp_restored) < 1e-4` on restored molid | PASS |

- Phase 15 is now COMPLETE: all 5 plans (15-01 registry, 15-02 mutation, 15-03 backup, 15-04 game, 15-05 capstone) green. The highest-risk v2 architectural bet (PDB-rebuild because VMD has NO in-place atom insertion) is proven de-risked end-to-end.

## Verification Results

| Gate | Result |
| --- | --- |
| Tcl 8.6 gate on phase15_smoke.tcl (`\b(lmap\|try\|throw\|tailcall\|coroutine\|yield\|finally)\b`) | ZERO matches |
| Headless VMD run (staged tmp/phase15-cap, 1k8p + 5 hiders) | `BCHM_SMOKE_RESULT PASS=1 FAIL=none` (first run) |
| Full-log `ERROR)` scan (false-PASS guard) | ZERO matches |
| Log narrative trace | 555 load -> mutated-viewpoint matrix echo (45/30 deg, 0.8, 0.5s) -> combined PDB reload 560 atoms / Segments: 2 -> restore reload 555 atoms -> `nfail` echo 0 |
| SC1-SC4 assertion table (above) | 11/11 PASS |
| Regression | Not required -- no lib files were modified (the capstone is a NEW smoke only); all Phase-15 smokes remain green from their own plans |

## Task Commits

1. **Task 1: Write phase15_smoke.tcl (the full SC1-SC4 capstone)** - `08c321d` (test)

**Plan metadata:** `docs(15-05): complete phase-15 capstone plan` (this commit).

## Files Created/Modified

- `vmd/smoke/phase15_smoke.tcl` (NEW) -- the Phase-15 capstone headless smoke. Full backup -> mutate -> reconstruct -> cleanup -> restore pipeline on 1k8p + 5 placeholder hiders, driven exclusively through `game::start_game`/`game::cleanup`; 11 assertions covering SC1 (560 atoms / 5 sentinels at 555-559 / segid GAME / N1 intact), SC2 (555 atoms / same numreps / 0 sentinels / game_molid DELETED), SC3 (registry 5 -> 0, exact-set is_hider), SC4 (reps on game_molid + viewpoint maxdiff < 1e-4 via the recursive flattener). Conventions: `[pwd]`-based sourcing, `BCHM_SMOKE_RESULT` marker, `exit`, every atomselect `$sel delete`'d, Tcl 8.5 only.

## Decisions Made

1. **1k8p + 5 hiders per the plan** (not 15-04's 1znf + 2) -- larger body proves the pipeline scales; 555+5=560 atoms, sentinels land at indices 555-559.
2. **Public-API-only capstone** -- backup/mutation/registry are never called directly; the smoke proves the composition root wires them (their isolated behavior was proven by the Wave-1/2 module smokes). The plan's explicit requirement.
3. **Viewpoint compare via the probe-verified recursive flattener** (`_flat`/`_vp_maxdiff`, 15-RESEARCH-backup-restore.md lines 360-377) + 1e-4 tolerance -- NOT string-eq (float formatting drift) and NOT naive abs() (errors on the nested 4x4 matrices). Capture form is byte-identical to backup::snapshot's positional field order, making the round-trip apples-to-apples.
4. **SC2d as the leak false-pass guard** -- `catch {molinfo $game_molid get numatoms}` must return NONZERO after cleanup; a live game_molid means `backup::restore` deleted the dead `snapshot.molid` instead of the passed `game_molid` (the Plan-03/04 integration blocker).
5. **gs-shape hardening** -- `dict get $gs game_molid` wrapped in its own catch (`gs_key_game_molid` tag) so a malformed game_state records a FAIL tag rather than raising a top-level error VMD -e would swallow into a potential false-PASS.

## Deviations from Plan

None -- plan executed exactly as written. The capstone passed on the first run (`PASS=1 FAIL=none`), no lib files were touched, and no debugging was needed.

### Notes on plan fidelity (not deviations)

- **Per-step catch + `_bail` + defensive-init structure** mirrors `phase15_game_smoke.tcl` (the plan's referenced closest-pattern) rather than the research skeleton's bare-source form -- the established Phase 13/14/15 smoke convention (VMD -e catches top-level errors and continues, so unwrapped steps could false-PASS).
- **Stray numeric echoes in the VMD log** (`-1` x3, the viewpoint matrix, a lone `0`) are VMD text-mode echoes of top-level command results (my defensive `set` inits, the `vp_orig` capture, and `set nfail` -> 0), not script output; verified against the log narrative and the zero-failure marker.

## Issues Encountered

- **`bash -ic` tcsetattr hang at VMD exit** (known WSL/VMD interaction) -- the wrapper exits cleanly with `< /dev/null` + `timeout 300`; the marker is printed before any hang so grep finds it regardless. Authoritative result is the marker line, NEVER `$?`.

## Authentication Gates

None -- VMD 1.9.3 runs locally via the WSL alias; no external auth required.

## User Setup Required

None -- the capstone uses only VMD 1.9.3 tcl 8.5 stdlib + the bundled 1k8p demo. Re-run recipe: `mkdir -p tmp/phase15-cap && cp -r vmd tmp/phase15-cap/ && timeout 300 bash -ic 'cd tmp/phase15-cap && vmd -dispdev text -e vmd/smoke/phase15_smoke.tcl -eofexit < /dev/null' > out 2>&1; grep BCHM_SMOKE_RESULT out`.

## Next Phase Readiness

- **Phase 15 COMPLETE (all 5 plans).** All 4 phase success criteria proven end-to-end through the composition root; the PDB-rebuild mechanism (write combined PDB -> mol delete -> mol new -> tag sentinels), cleanup restore, registry reconstruct-from-sentinels, and rep+viewpoint round-trip all work together on a real demo.
- **Phase 16 (MVP loop: sphere generator + PickBridge) unblocked:** it swaps `mutation::make_placeholder_hiders` for real sphere placement; `start_game {molid hider_count}`, the `game_state` dict shape, and the DI injection line stay frozen. The click loop calls `registry::mark_found` (already exported).
- **Phase 17.1/17.2 (rep generators) unblocked:** SC4's proven `backup::apply` path (form-B addrep + modselect/modcolor/modmaterial, delrep-0 loop) is the mechanism that will keep generated reps alive across the PDB-rebuild.
- **No blockers / concerns.** Zero deviations, zero lib fixes; the Wave-1/2 module contracts (2-arg mutate, 2-arg restore w/ live game_molid, apply-lambda DI) all held under the capstone.

---
*Phase: 15-mutation-safety-hider-registry*
*Plan: 05*
*Completed: 2026-08-30*
