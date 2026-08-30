---
phase: 16-mvp-core-loop-sphere
plan: 06
subsystem: vmd-pick
tags: [vmd, tcl, trace, pick-event, mouse-mode, label-api, headless-smoke, pickbridge]

# Dependency graph
requires:
  - phase: 16-mvp-core-loop-sphere (research)
    provides: 16-RESEARCH-pick.md -- the probe-verified pick contract (trace ::vmd_pick_event / {args} / vmd_pick_atom+vmd_pick_mol / mouse mode pick 2 / label API)
  - phase: 15-mutation-safety-hider-registry
    provides: game.tcl composition root (the on_pick contract target; registry keyed by 0-based atom index) + the headless smoke conventions
provides:
  - vmd/lib/pick_bridge.tcl -- ::biochemeleon::pick_bridge::activate/deactivate/set_view_mode (mol bridge, sources NOTHING)
  - vmd/smoke/phase16_pick_smoke.tcl -- headless proof of the tcl-side pick machinery (PASS=1)
  - the locked-tcl-side contract game::on_pick <index> for Plan 16-08
affects: [16-08 game.tcl on_pick, 16-09 game_tab GUI (radiobuttons->set_view_mode, GO->activate, on_win->deactivate), 16-12 GUI human-verify (locks real-click firing)]

# Tech tracking
tech-stack:
  added: []   # zero new dependencies (VMD 1.9.3 built-ins only: trace, mouse, label, after, vmdcon)
  patterns:
    - "Write-trace callback pattern: {args} signature + fully catch-wrapped body + rc==1 error classifier (never propagate -- an error in a write-trace proc blocks VMD's own variable write)"
    - "Mode snapshot/restore with rotate fallback (mouse mode set is non-atomic)"
    - "Baseline-guarded label hygiene (delete from the END down to the activate-time baseline; never 'label delete Atoms all')"

key-files:
  created:
    - vmd/lib/pick_bridge.tcl
    - vmd/smoke/phase16_pick_smoke.tcl
  modified: []

key-decisions:
  - "rc==1 error classifier inside _on_event: probe16 measured catch{bare return} = rc 2 (TCL_RETURN); a truthy catch test would misreport every filtered pick as an error and print spurious 'ERROR)' lines (the gate greps for them). Report only TCL_ERROR."
  - "set_view_mode rotate uses VMD's own 1-arg hotkey-r form -- probe16 verified it resets vmd_mouse_submode to -1, matching the fresh-session default the smoke asserts."
  - "activate arms the first labelpoll 'after' tick AFTER set active 1 (the seed _poll_once call runs while active==0 and cannot self-arm); deactivate cancels labelpoll_after -- keeps the dormant fallback self-consistent."
  - "Header documents the forbidden forms without the literal 'mouse mode 4' substring (phrased as the numeric form '4 2' under mouse mode) so the userpoint-trap grep gate stays zero-match while the warning is preserved."
  - "Labelpoll forwards per-entry (molid-filtered) then clears all new labels baseline-guarded; re-arms only while active in labelpoll mode -- trace mode never schedules a timer."

patterns-established:
  - "PickBridge contract: _on_event forwards EXACTLY ::biochemeleon::game::on_pick <0-based index> -- ONE argument; game.tcl owns all game state"
  - "Phantom compat shim: lappend to ::vmd_pick_atom_callbacks is a no-op gesture; NEVER read/branch on the list"
  - "Smoke stubs a not-yet-existing cross-module proc via namespace eval + proc (proc does NOT auto-create namespaces)"

# Metrics
duration: 13 min
completed: 2026-08-30
---

# Phase 16 Plan 06: Pick Bridge Summary

**PickBridge (v2 PickWizard equivalent): trace-on-::vmd_pick_event delivery with {args} handler, mouse-mode snapshot/restore, idempotent activate, molid+index filters, baseline-guarded label hygiene -- proven headlessly (PASS=1), with the game::on_pick <index> contract locked for 16-08.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-08-30T09:40:37Z
- **Completed:** 2026-08-30T09:54:03Z
- **Tasks:** 2
- **Files modified:** 2 created

## Accomplishments
- `vmd/lib/pick_bridge.tcl` (252 lines): activate/deactivate/set_view_mode + _on_event/_clear_new_labels/_poll_once; sources NOTHING (backup.tcl precedent); file/namespace parity; Tcl 8.5 only.
- `vmd/smoke/phase16_pick_smoke.tcl` (203 lines): 9-step headless proof -- phantom absence, set_view_mode round-trip (pick->labelatom/2, rotate->rotate/-1), activate on 1k8p + flag/mode asserts, idempotent activate (exactly ONE delivery after double activate), simulated fire {3}, molid filter (9999 ignored), index filter (99999 rejected), deactivate (trace gone + mode restored + only OUR label cleaned + active cleared), {args} signature guard via `info args`.
- Real-click firing cleanly quarantined: both files state it is GUI-only and locked by the Plan 16-12 human-verify checkpoint; the smoke certifies tcl-side machinery exclusively.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write vmd/lib/pick_bridge.tcl** - `fc00eb2` (feat)
2. **Task 2: Write + run the headless smoke** - `d7c9012` (test)

## Files Created/Modified
- `vmd/lib/pick_bridge.tcl` - the pick contract module (trace primary / labelpoll dormant fallback / phantom shim only)
- `vmd/smoke/phase16_pick_smoke.tcl` - headless smoke, BCHM_SMOKE_RESULT PASS=1 FAIL=none

## Decisions Made
- **rc==1 classifier in the catch-wrapped handler** (probe16): `set rc [catch {...} err]` + report only when rc==1. The plan's reference pattern (`if {[catch ...]} {vmdcon -err ...}`) treats the guards' bare `return` (TCL_RETURN=2) as an error and would print spurious `ERROR) bioCHEMeleon pick handler:` lines on every filtered pick -- failing the gate's ERROR) scan. The body remains fully catch-wrapped; early exits are silent; genuine errors are reported and swallowed.
- **1-arg rotate in set_view_mode** (probe16): `mouse mode rotate` resets the submode to -1 -- VMD's own hotkey-r form, and exactly what the smoke's rotate/-1 assertion expects.
- **labelpoll self-re-arm + activate-armed first tick**: deactivate cancels `labelpoll_after`, so something must set it; the seed call in activate runs while active==0 (per the plan's ordering), so activate arms the first tick after `set active 1`. Trace mode never schedules a timer.
- **Forbidden-forms phrasing**: the header lists the numeric userpoint form as `"4 2" under mouse mode` so the gate grep (`mouse mode 4`) stays at zero matches while the warning is fully documented. `pick 0` (query) is documented literally.
- **Smoke stub created via `namespace eval ::biochemeleon::game {}` first** -- `proc ::ns::name` errors with "unknown namespace" when the namespace is absent (Tcl proc does NOT auto-create namespaces); the resulting bare top-level error is caught by VMD -e and silently continues (the false-PASS trap), so this must be explicit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Catch-classifier: bare-return exits are TCL_RETURN (rc 2), not errors**
- **Found during:** Task 1 (design probe before writing)
- **Issue:** The plan's reference handler used a truthy `if {[catch {...} err]}` error branch; probe16 measured `catch {return}` = rc 2, so every early-exit guard (missing globals, molid/index filters) would have fired `vmdcon -err` with an empty message -- spurious `ERROR)` lines in every run (the gate greps for exactly that).
- **Fix:** `set rc [catch {...} err]` + `if {$rc == 1}` report. Everything else per plan (full catch wrap, never propagate).
- **Files modified:** vmd/lib/pick_bridge.tcl
- **Verification:** run3 log has zero `ERROR)` lines despite 4 simulated fires (2 legitimately filtered); the one genuine error injected in run1 was reported exactly once.
- **Committed in:** fc00eb2

**2. [Rule 1 - Bug] Smoke run1: recording stub died with "unknown namespace" (silent -- no ERROR) prefix)**
- **Found during:** Task 2 (first smoke run)
- **Issue:** `proc ::biochemeleon::game::on_pick ...` without a pre-existing `::biochemeleon::game` namespace raises `can't create procedure ...: unknown namespace`; VMD -e catches the bare top-level error and CONTINUES, so the whole smoke ran without a delivery target (PICK_LOG empty -- would have been a false PASS if the delivery asserts were weaker).
- **Fix:** `namespace eval ::biochemeleon::game {}` before the stub proc; lesson recorded in a smoke comment.
- **Files modified:** vmd/smoke/phase16_pick_smoke.tcl
- **Verification:** run3 delivers exactly {3}.
- **Committed in:** d7c9012

**3. [Rule 1 - Bug] Smoke: pre-activate snapshot captured after activate + stale assertion**
- **Found during:** Task 2 (runs 1-2)
- **Issue:** `pre_act_mode/pre_act_sub` were captured inside the post-activate else-branch (so step 8's restore check compared against labelatom/2 instead of the pre-activate rotate/-1), and after moving the capture the step-3 assertion still read the snapshot variable instead of the current globals.
- **Fix:** Capture before the activate call; step-3 asserts current `::vmd_mouse_mode`/`::vmd_mouse_submode`.
- **Files modified:** vmd/smoke/phase16_pick_smoke.tcl
- **Verification:** run3 PASS=1 (mode_restored green: rotate/-1 restored).
- **Committed in:** d7c9012

---

**Total deviations:** 3 auto-fixed (3 bugs -- 1 design-level caught by probe before implementation, 2 smoke-level)
**Impact on plan:** All fixes required for a truthful PASS; the bridge's public surface, mechanism, and contract are exactly as planned. No scope creep.

## Issues Encountered
- Smoke needed 3 staged runs to reach PASS=1 (run1: missing namespace + snapshot-position bugs; run2: stale assertion; run3: clean). Each iteration's lesson is baked into the smoke as comments.
- `tclsh` is not installed in this WSL (13-01 lesson re-confirmed) -- all behavior probes ran through headless VMD (`echo exit | timeout 300 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e <file> -eofexit'`, the exit-piped stdin pattern).
- vmdcon -err confirmed to print the `ERROR)` prefix in -dispdev text mode (probe16), making the gate's ERROR) scan meaningful for handler errors.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **16-08 (game.tcl on_pick):** the contract is locked tcl-side -- implement `::biochemeleon::game::on_pick <index>` (ONE arg); the bridge forwards only valid, game-molid, in-range indices. Entry source order should insert pick_bridge.tcl after game.tcl (both standalone).
- **16-09 (game_tab GUI):** call `pick_bridge::set_view_mode pick|rotate` from the radiobuttons, `activate [dict get $game_state game_molid]` on GO (AFTER start_game -- PDB-rebuild changes the molid), `deactivate` on win/close.
- **16-12 (GUI human-verify):** locks real-click firing + the final `mechanism` value (trace vs labelpoll); the smoke and this module make no real-click claims.
- Note: 1k8p smoke used the demo molid directly as the "game molid" (the bridge only needs a molid); the start_game integration path is exercised in 16-08/16-09.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
