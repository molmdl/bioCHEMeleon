---
phase: 16-mvp-core-loop-sphere
plan: 05
subsystem: vmd-mol-bridge
tags: [vmd, tcl, mol-bridge, reps, user2, vdw, colorid, sentinel, headless-smoke]

# Dependency graph
requires:
  - phase: 15-mutation-safety-hider-registry
    provides: game::start_game/cleanup composition root, GAM/beta<0 sentinel contract, backup::apply rep ordering (deterministic base index), staging + BCHM_SMOKE_RESULT smoke conventions
  - phase: 16-mvp-core-loop-sphere (16-01..16-03, parallel Wave-1 siblings)
    provides: registry found-state surface (status_of/mark_found idempotence) and game_logic three-way guard that the CALLER composes around mark_found_visual
provides:
  - "::biochemeleon::hiders::add_hider_reps {molid} -- exactly 2 reps on the game molid: hidden (VDW + Element + user2<1) and found (VDW + ColorID 7 + user2>0), indices recorded in namespace vars"
  - "::biochemeleon::hiders::mark_found_visual {molid idx} -- user2=1 on the picked index + mandatory mol modselect re-assert on BOTH hider reps, range-guarded"
  - "vmd/smoke/phase16_hiders_smoke.tcl -- 11-assert headless proof of the two-rep split + user2 mechanism through the real Phase-15 pipeline (PASS=1 first run)"
affects: [16-08 (game.tcl: start_game gains the add_hider_reps step; on_pick calls mark_found_visual), 16-07 (sphere placement swap coexists with the rep layer), game-tab plans (remaining display + found visuals), Phase 19 (found-hider dropdown toggles the found rep via the whole-rep off switch)]

# Tech tracking
tech-stack:
  added: []   # zero new libraries -- VMD 1.9.3 built-ins only (mol addrep/modstyle/modcolor/modselect, atomselect user2)
  patterns:
    - "Two-rep split for per-atom found-state (VMD colors per-REP, not per-atom -- FEATURES.md:77): user2 flag partitions the sentinel population across a hidden rep and a found rep"
    - "Mandatory mol modselect re-assert after every user2 write (rep selections re-evaluate per TIMESTEP only -- static molecules never re-evaluate on atom-field change, UG node140/probe F17)"
    - "Never hide a rep during play (UG node140: hidden reps cannot be picked) -- double-count prevention lives in the caller's registry-status guard"
    - "COMBINED-BRACES molinfo read-back `molinfo $m get \"{rep $i} {selection $i} {color $i} {material $i}\"` + foreach/break destructure (single-field form FAILS -- Pitfall 2)"

key-files:
  created:
    - vmd/lib/hiders.tcl
    - vmd/smoke/phase16_hiders_smoke.tcl
  modified: []

key-decisions:
  - "hiders.tcl sources NOTHING (sibling mol bridge like backup.tcl) -- game.tcl stays the only composition root; Plan 16-08 wires it in"
  - "Sentinel selectors are braced literals, verbatim: hidden {resname GAM and beta < 0 and user2 < 1}, found {resname GAM and beta < 0 and user2 > 0} -- beta is NEVER written (reconstruct/cleanup depend on beta<0 matching ALL hiders)"
  - "Bare VDW style (defaults res 8.0 scale 1.0) -- a 3rd param ERRORS (probe C3); Element coloring for the hidden rep auto-tracks the hider element (C -> cyan, radius 1.7 == real carbons); ColorID 7 (green) for the found rep, id as 4th arg"
  - "mark_found_visual errors with a clear message when hidden_rep/found_rep are -1 or out of range for the molid -- rep indices renumber on delrep (Pitfall 9), so indices are re-checked against numreps, never blindly trusted"

patterns-established:
  - "user2 as the per-atom found channel (floats: 1.0/0.0 -- numeric compare only, never string-eq \"1\"); 'user' stays reserved for tag_sentinels ordinals"
  - "user2 writes are ALWAYS followed by re-issuing BOTH modselects with unchanged strings (idempotent re-evaluation re-assert)"

# Metrics
duration: 6 min
completed: 2026-08-30
---

# Phase 16 Plan 05: Hiders Mol Bridge Summary

**Two-rep hider visual layer (hidden VDW+Element / found VDW+ColorID 7) split by a per-atom user2 flag, with the mandatory modselect re-assert, proven headlessly through game::start_game on 1k8p (PASS=1 first run)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-08-30T09:40:08Z
- **Completed:** 2026-08-30T09:45:54Z
- **Tasks:** 2/2
- **Files modified:** 2 (both created)

## Accomplishments
- `vmd/lib/hiders.tcl` (124 lines, STANDALONE -- sources nothing): `add_hider_reps` adds exactly 2 reps to the game molid (hidden rep VDW + Element + `user2 < 1`, found rep VDW + ColorID 7 + `user2 > 0`) at base..base+1 after backup::apply, recording indices in namespace vars; `mark_found_visual` sets user2=1 on the picked index and re-issues BOTH modselects with the UNCHANGED sentinel strings (the mandatory timestep-based re-evaluation re-assert), guarded against -1/out-of-range rep indices.
- `vmd/smoke/phase16_hiders_smoke.tcl` (219 lines, 11-step): proves through the REAL Phase-15 pipeline (demos::load_demo 1k8p -> game::start_game $m 5 -> add_hider_reps -> read-backs -> mark_found_visual -> cleanup) that the two-rep split + user2 mechanism works end-to-end. **PASS=1 FAIL=none on the first staged run**; full log scanned -- zero `ERROR)` / `bad switch` lines, VMD "Exiting normally".
- All plan gates green: Tcl 8.6-idiom grep zero matches on both files; zero `mol showrep` in hiders.tcl (UG node140: hidden reps cannot be picked -- neither hider rep is ever hidden); zero beta writes (sentinel `resname GAM and beta < 0` integrity asserted == 5 after marking); zero `label` calls.

## Task Commits

Each task was committed atomically on branch exec/16-05:

1. **Task 1: Write vmd/lib/hiders.tcl (mol bridge)** - `9f955d9` (feat)
2. **Task 2: Write + run the headless smoke** - `95846d1` (test, PASS=1 first run)

## Files Created/Modified
- `vmd/lib/hiders.tcl` - `::biochemeleon::hiders` namespace (add_hider_reps / mark_found_visual); the exact rep + found-marking surface Plan 16-08's game.tcl consumes
- `vmd/smoke/phase16_hiders_smoke.tcl` - headless smoke: rep read-backs (COMBINED-BRACES molinfo form), user2 float semantics, found/hidden split 1/4, sentinel integrity 5, idempotent re-mark, cleanup leak guard (registry 0 + game_molid deleted)

## Decisions Made
- hiders.tcl sources NOTHING and holds hidden_rep/found_rep in namespace vars (one `variable` per line, init -1) -- game_state shape stays FROZEN; mark_found_visual re-checks the vars against `numreps` before use (Pitfall 9 delrep renumbering).
- Read-back verification uses ONLY the COMBINED-BRACES molinfo form + `foreach ... break` destructure (single-field `molinfo get {rep $i}` FAILS -- Pitfall 2); selectors compared with exact string `eq` against the braced-literal sentinels.
- user2 comparisons in both the module contract and the smoke are NUMERIC (`expr {double($v) > 0}`) -- values are floats (1.0/0.0), string-eq to "1" is a trap (Pitfall 7).
- Idempotency sub-case added to the smoke (re-mark 555: no error, user2 still > 0, found sel still 1) to lock the caller-guard contract from Pitfall 5 / probe F19.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. The smoke passed on the first staged run. (Run used the established Phase-16 invocation: `echo exit | timeout 300 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase16_hiders_smoke.tcl -eofexit'` -- the `exit`-pipe pattern prevents Windows vmd.exe blocking at its prompt.)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The mol-bridge surface Plans 16-08 (game.tcl) consumes is live and regression-guarded: start_game gains ONE step (`hiders::add_hider_reps $game_molid` after backup::apply) and on_pick calls `hiders::mark_found_visual $gm $idx` after the registry three-way guard.
- Headless-verified preconditions for the Phase-16 GUI human-verify checkpoint are all green (radius 1.7 == carbons, Element -> cyan, ColorID 7 green, reps shown, user2 split works); what remains GUI-only is the real pick-callback contract and the visual blending look.
- Found flags are session-only by design (user2 not written by writepdb) -- cross-session found-state is Phase 20's .bcm sidecar; Phase 19's found-hider dropdown will toggle the whole found rep (the one legitimate use of the rep-hide switch).

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
