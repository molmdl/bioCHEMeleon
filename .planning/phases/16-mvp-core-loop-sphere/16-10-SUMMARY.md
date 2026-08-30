---
phase: 16-mvp-core-loop-sphere
plan: 10
subsystem: gui-integration
tags: [tcl, vmd, tcl-8.5, tk-8.5, entry-wiring, game-loop, pick-bridge, btn-07, load-gate-smoke]

# Dependency graph
requires:
  - phase: 16-mvp-core-loop-sphere (16-06)
    provides: pick_bridge.tcl (activate/deactivate/set_view_mode, trace ::vmd_pick_event contract)
  - phase: 16-mvp-core-loop-sphere (16-07)
    provides: real sphere placement in mutation::make_placeholder_hiders via generators
  - phase: 16-mvp-core-loop-sphere (16-08)
    provides: game::on_pick scoring controller + set_callbacks in game.tcl
  - phase: 16-mvp-core-loop-sphere (16-09)
    provides: game_tab.tcl 11-proc view surface (build/start_round/stop_all_timers/raise_tab/set_difficulty)
  - phase: 15-mutation-safety-hider-registry
    provides: game.tcl composition root (start_game/cleanup), registry, backup, mutation
provides:
  - Entry sources all four Phase-16 modules in dependency order (generators + game_logic pure block; hiders + pick_bridge mol block); registry still sourced EXACTLY ONCE
  - dialog.tcl sources game_tab.tcl at top level and open_dialog builds the real Game tab (Phase 13 placeholder removed)
  - "::biochemeleon::on_start -- the BTN-07 fan-in (collect_state -> resolve target -> validate/clamp -> start_game -> set_difficulty -> raise_tab -> start_round) with 6 tk_messageBox abort paths, no partial game state"
  - on_close stops all Game-tab timers + deactivates the pick bridge BEFORE destroy
  - Start button (BTN-07) in the Setup Actions group
  - vmd/smoke/phase16_entry_smoke.tcl -- headless entry load-gate (PASS=1) incl. Phase-15 regression through the public API
affects: [16-11 win/cleanup/restart wiring, 16-12 GUI human-verify, phase 17 rep generators, phase 19 cleanup/restart]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dialog-scope fan-in handler (::biochemeleon::on_start) -- needs setup_tab state + game_tab + game.tcl; dialog scope avoids cross-tab reach-ins (research SS7.5)"
    - "Abort-with-messageBox-and-return at EVERY failure path before any game state is created (v1 QMessageBox.warning parity)"
    - "Load-gate smoke bypasses the entry's re-source guard via `namespace eval ::biochemeleon { variable loaded 0 }` before sourcing"
    - "Structural order assertion inside the smoke: string-first offsets of each `lib <mod>.tcl` source line must be strictly increasing"

key-files:
  created:
    - vmd/smoke/phase16_entry_smoke.tcl
  modified:
    - vmd/biochemeleon.tcl
    - vmd/gui/dialog.tcl
    - vmd/gui/setup_tab.tcl

key-decisions:
  - "on_start lives at ::biochemeleon::on_start (dialog scope) per 16-RESEARCH-gametab SS7.5 recommendation -- it needs setup_tab state + game_tab + game.tcl"
  - "Fetch mode surfaces the demos::fetch_pdb stub's own error message and aborts (real fetch is Phase 21; VMD 1.9.3 lacks tls)"
  - "Loaded-mode resolution re-checks liveness at Start time (molinfo numatoms catch + >0), not just the menu-time selection -- a molecule deleted after selection aborts cleanly"
  - "validate_state clamp (step 3) is catch-guarded like the other steps -- the pure layer is authoritative (do_save precedent)"
  - "on_close order: collect_state persist -> trace vdelete -> stop_all_timers -> pick_bridge::deactivate -> destroy (timers + pick teardown strictly before destroy)"

patterns-established:
  - "BTN-07 wiring shape: setup_tab button -command {::biochemeleon::on_start} -> 7-step dialog fan-in -> game_tab::start_round"
  - "Entry source order contract: setup_state -> registry -> generators -> game_logic (pure) -> demos -> backup -> mutation -> hiders -> game -> pick_bridge -> dialog"
  - "Load-gate smoke asserts structural source ORDER by reading the entry text (not just file presence)"

# Metrics
duration: 15 min
completed: 2026-08-30
---

# Phase 16 Plan 10: Entry Wiring Summary

**Full entry integration: Start button -> on_start fan-in -> real spheres -> Game tab countdown -- the loop reachable end-to-end at the code level, proven by an entry load-gate smoke (PASS=1) that also re-runs the Phase-15 regression through the public API.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-08-30T11:05:27Z
- **Completed:** 2026-08-30T11:20:43Z
- **Tasks:** 3
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- Entry sources the four Phase-16 modules in dependency order: `generators.tcl` then `game_logic.tcl` join the pure block (after registry); `hiders.tcl` (after mutation) and `pick_bridge.tcl` (after game) join the mol block; `registry.tcl` is still sourced EXACTLY ONCE (order-matters comment block rewritten).
- `dialog.tcl` sources `game_tab.tcl` at TOP LEVEL next to the setup_tab line (the `[info script]` call-time lesson) and `open_dialog` now builds the real Game tab via `game_tab::build $nb.game` (eager; the Phase 13 placeholder label is gone).
- `::biochemeleon::on_start` implements the BTN-07 flow (v1 `_on_start` :242-261 parity): collect_state -> resolve target (loaded: live-molecule check; demo: `demos::load_demo`; fetch: surfaces the Phase-21 stub's error) -> `validate_state` clamp vs the target's atom count -> `game::start_game` -> `set_difficulty` -> `raise_tab` -> `start_round`. All 6 failure paths abort with a `tk_messageBox -parent $w` and return -- no partial game state, dialog stays open.
- `on_close` stops all Game-tab timers (`stop_all_timers`) and deactivates the pick bridge (`deactivate`) BEFORE `destroy` -- catch-guarded no-ops when no round was ever started; after-ids and the pick trace/mouse mode can no longer outlive the dialog.
- Start button (BTN-07) added to the Setup Actions group: `ttk::button $f.start -text "Start" -command {::biochemeleon::on_start}`, packed with BTN-01..04.
- `vmd/smoke/phase16_entry_smoke.tcl`: headless load gate -- bypasses the re-source guard, sources the FULL entry under `-dispdev text`, asserts the proc surface (pure/mol/controller/dialog/11 game_tab procs), structurally asserts the entry's source ORDER, proves registry exactly-once (source-line count + no lib re-sources + reconstruct/count/reset round trip post-load), and runs the Phase-15 regression through the public API (1k8p 555 -> start_game 5 -> 560 atoms/5 sentinels/count 5/numreps +2 -> cleanup -> 555/count 0/game_molid deleted).

## Task Commits

Each task was committed atomically:

1. **Task 1: Entry source order + dialog game-tab build + on_close** - `d16df86` (feat)
2. **Task 2: Start button + on_start (BTN-07 fan-in)** - `67ed9b6` (feat)
3. **Task 3: Entry load-gate smoke + Phase-15 regression** - `2c022b3` (test)

**Plan metadata:** this commit -- `docs(16-10): complete entry wiring plan`

## Files Created/Modified

- `vmd/biochemeleon.tcl` - extended source order (generators, game_logic, hiders, pick_bridge) + rewritten order-matters comment
- `vmd/gui/dialog.tcl` - top-level game_tab source, real Game-tab build in open_dialog, `proc ::biochemeleon::on_start`, extended on_close
- `vmd/gui/setup_tab.tcl` - Start button in build_actions (BTN-01..04 + BTN-07)
- `vmd/smoke/phase16_entry_smoke.tcl` - headless entry load gate + Phase-15 regression (NEW)

## Verification Results

- `BCHM_SMOKE_RESULT PASS=1 FAIL=none` -- zero `ERROR)` / `bad switch` in the full log (85 lines scanned; atom transitions 555 -> 560 -> 555 visible in the VMD output).
- Tcl 8.6 gate (`lmap|try|throw|tailcall|coroutine|yield|finally`) zero matches on all touched files; modeless (`grab set`) gate zero on `vmd/gui/`.
- `registry.tcl` sourced exactly once in the entry (grep: one source line; other matches are comments).
- on_start aborts every failure path (6 `tk_messageBox` call sites) and touches no game state before start_game succeeds.
- Regression re-runs against fresh staging: phase13_smoke PASS=1, phase14_gui_smoke PASS=1 (both source the entry -- the actual regression surface), phase15_smoke (capstone) PASS=1, phase16_gametab_smoke PASS=1.

## Decisions Made

- on_start at dialog scope (`::biochemeleon::on_start`) -- research SS7.5 recommendation; avoids cross-tab reach-ins between setup_tab, game_tab, and game.tcl.
- Loaded-target liveness is re-checked at Start time (`molinfo $selobj get numatoms` in catch + `> 0`), so a molecule deleted after menu selection aborts with a clear message instead of crashing start_game.
- The fetch branch surfaces `demos::fetch_pdb`'s stub message verbatim (real fetch = Phase 21; VMD 1.9.3 lacks tls for HTTPS).
- The validate_state clamp (step 3) is catch-guarded like every other step -- uniform "abort with a message box, return" contract.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Smoke's registry-source-count pattern missed the join bracket**

- **Found during:** Task 3 (first headless run)
- **Issue:** `string match "source*registry.tcl"` requires the line to END with `registry.tcl`, but every source line ends with the `file join` closing bracket `]` -> count returned 0 -> FAIL=registry_source_count:exp=1 got=0 (the smoke correctly DETECTED the mismatch -- not a false PASS)
- **Fix:** trailing `*` in the pattern: `string match "source*registry.tcl*"`
- **Files modified:** vmd/smoke/phase16_entry_smoke.tcl
- **Verification:** re-run PASS=1 FAIL=none
- **Committed in:** 2c022b3 (Task 3 commit)

**Total deviations:** 1 auto-fixed (1 bug -- in the new smoke itself, caught by its own first run)
**Impact on plan:** None beyond the smoke fix; all code landed exactly as planned.

### Benign verify-nuance (not a deviation)

- Task 2's verify expected `grep -n "f.start" vmd/gui/setup_tab.tcl` -> 1; actual output is 2 lines (the widget line + the `pack` line that displays it). Exactly ONE Start button exists; the second match is the pack. No change needed.

## Issues Encountered

None. (The first-run smoke FAIL above was the smoke's own pattern bug, fixed in-place; everything else passed first run. `tclsh` is not installed in this WSL environment, so syntax sanity relied on the headless VMD parse -- same as prior phases.)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The loop is REACHABLE at the code level: Start -> on_start -> start_game (real sphere placement) -> Game tab -> 3-2-1 countdown -> timer -> picks scored via the pick bridge -> win box. Remaining loop bits (cleanup/restart buttons) are 16-11; the full GUI run is the 16-12 human-verify checkpoint.
- GUI rendering (Game tab widgets, Start button, message boxes) is asserted only at the code level here -- Tk does not load in `-dispdev text`; 16-12 owns the human-verify pass.
- No blockers carried forward.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
