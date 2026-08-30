---
phase: 16-mvp-core-loop-sphere
plan: 09
subsystem: gui
tags: [tcl, tk-8.5, vmd, after-timers, countdown, game-loop, view-layer, pick-bridge]

# Dependency graph
requires:
  - phase: 16-03
    provides: game_logic.tcl pure round state machine (round_reset/begin_countdown/countdown_tick/begin_play/timer_elapsed/format_mmss/log_append)
  - phase: 16-06
    provides: pick_bridge.tcl (set_view_mode/activate/deactivate -- the tab's ONLY mouse-switching path)
  - phase: 16-04
    provides: setup_state::format_remaining (pure remaining-count label formatter)
  - phase: 15
    provides: registry count_remaining/remaining_by_rep + game.tcl controller seam
provides:
  - vmd/gui/game_tab.tcl -- the player-facing Game tab VIEW (11 procs + private win-box helper); countdown chain, 1 Hz tick, rolling log, remaining label, win message, pick-vs-rotate control
  - vmd/smoke/phase16_gametab_smoke.tcl -- headless load-gate smoke (PASS=1)
affects: [16-08 (set_callbacks 1/0/2-arg contract co-documented), 16-10 (dialog wiring: source game_tab, build, on_close stop_all_timers, Start handler), 16-11 (integration), 16-12 (GUI human-verify)]

# Tech tracking
tech-stack:
  added: []   # zero new dependencies -- core Tk 8.5 + existing repo modules only
  patterns:
    - "tracked after ids + catch-cancel before every re-arm (viewmaster.tcl:202-207 idiom)"
    - "winfo-exists guard FIRST in every after callback (stray-callback-after-close protection)"
    - "conditional re-arm: tick only while state==playing; countdown only while not done"
    - "no-arg radiobutton -command handler reading the shared -variable (avoids wrong # args)"
    - "pull-model remaining label (registry count -> pure formatter -> textvariable)"
    - "log text widget written ONLY by on_log_line (normal -> insert -> disabled -> see end)"

key-files:
  created:
    - vmd/gui/game_tab.tcl
    - vmd/smoke/phase16_gametab_smoke.tcl
  modified: []

key-decisions:
  - "Third tracked timer id (after_winbox) + private _show_win_box proc: the plan mandates a 100 ms-delayed guarded win box and the verification rule 'every after assigned to a tracked var' -- a fire-and-forget after 100 would have violated it; stop_all_timers now cancels all three ids (a superset of the must-have 'cancels both ids')"
  - "on_win calls stop_all_timers (not a bare tick-cancel): same first action as the spec's 'cancel tick' but DRY and also retires a stale win box; the winbox is scheduled AFTER the cancel, so no conflict"
  - "set_mouse_mode is NO-ARG (reads the shared $mouse_mode the radiobutton updates before firing -command); a 1-arg signature would raise wrong # args on the first radio click"
  - "start_round stashes game_state via the fully-qualified path (the parameter shadows the same-named ns var -- the setup_tab select_demo / Pitfall-7 lesson)"
  - "Countdown GO branch logs the done label as the literal 'GO!' (== the 4th tick's label per the 16-03 contract), never label-plus-GO!, so no duplicate GO! line"
  - "update_remaining defaults easy_mode to 1 when set_difficulty has not run (SETUP-05 default), so the label never errors pre-round"

patterns-established:
  - "Game-tab view contract: the tab owns ONLY Tk widgets + after scheduling + callback registration; all decisions live in game_logic/registry/game.tcl"
  - "Mouse-switching discipline: the tab never issues viewer mouse commands -- everything routes through pick_bridge (set_view_mode/activate/deactivate)"
  - "Load-gate smoke shape: source deps + tab under -dispdev text, assert procs exist, assert widget-bound vars UNSET at source, string-match forbidden viewer/event-loop strings"

# Metrics
duration: 23min
completed: 2026-08-30
---

# Phase 16 Plan 09: Game Tab GUI Summary

**Tk 8.5 Game tab VIEW: 3-2-1 one-shot countdown chain + 1 Hz drift-free timer tick with tracked/cancelled after ids, read-only rolling log + plain scrollbar, pull-model remaining label, 100 ms-delayed parented win box, and Rotate/Pick radios wired exclusively through pick_bridge.**

## Performance

- **Duration:** 23 min
- **Started:** 2026-08-30T10:01:18Z
- **Completed:** 2026-08-30T10:24:07Z
- **Tasks:** 2/2
- **Files modified:** 2 (both created)

## Accomplishments
- `vmd/gui/game_tab.tcl` (446 lines): the complete Game tab view -- build (status labels with -textvariable, core-Tk read-only text + PLAIN scrollbar, Mouse-mode ttk::labelframe with Rotate/Pick radios), start_round (stop_all_timers-first defensive restart parity, 16-08 set_callbacks registration, initial update_remaining so the label reads "Remaining: N" from round start), countdown_step (one-shot after 1000 chain; GO branch = begin_play -> pick_bridge::activate -> Pick label/radio -> tick loop), tick (self-rescheduling, re-arms ONLY while state==playing, reschedules at body end), on_win (stop timers -> deactivate bridge exactly once -> Rotate label -> after 100 guarded tk_messageBox parented to the dialog), set_mouse_mode (NO-ARG), set_difficulty, stop_all_timers, raise_tab (notebook select, never raise).
- Every after-discipline rule from 16-RESEARCH-gametab SS4 implemented: tracked ids (after_tick/after_countdown/after_winbox), catch-cancel before EVERY re-arm, winfo-exists guard FIRST in every callback + widget writes catch-wrapped, conditional re-arms, schedule-by-value with fully-qualified literals, reschedule-at-end, zero event-loop re-entry.
- `vmd/smoke/phase16_gametab_smoke.tcl`: load-gate PASS=1 first full run -- sources clean under -dispdev text, 11/11 procs present, pure-layer round trip green (4-tick countdown sequence, frozen-elapsed win via injected now, format_remaining exact string, registry remaining round trip), widget-bound vars proven UNSET at source, forbidden-string scan clean.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write vmd/gui/game_tab.tcl** - `236c818` (feat)
2. **Task 2: Write + run the load-gate smoke** - `6d4eee2` (test)

**Plan metadata:** (this commit) `docs(16-09): complete game tab GUI plan`

## Files Created/Modified
- `vmd/gui/game_tab.tcl` - the Game tab VIEW (11 exported-surface procs + private _show_win_box; headless-safe at source)
- `vmd/smoke/phase16_gametab_smoke.tcl` - headless load-gate smoke (BCHM_SMOKE_RESULT marker + trailing exit per 15/16-06 convention)

## Decisions Made
- **Tracked win-box id + private _show_win_box proc (12th proc):** the plan mandates a 100 ms-delayed guarded message box; the plan's own verification rule ("every after in the file is assigned to a tracked var") rules out an untracked fire-and-forget. stop_all_timers cancels all three ids -- a superset of the "cancels both ids" must-have.
- **on_win uses stop_all_timers:** identical first action to the spec's "cancel tick" plus retirement of a stale win box; the new win box is scheduled after the cancel, so ordering is safe.
- **set_mouse_mode NO-ARG canonical form** reads the shared variable (radiobuttons update it before -command fires) and forwards to pick_bridge::set_view_mode inside catch -- the tab never touches viewer mouse commands.
- **game_state stash via fully-qualified set** in start_round (parameter shadows the same-named ns var; the 14-04/Pitfall-7 name-VALUE + shadow lesson).
- **GO! logged only in the done branch** (the 4th tick's label IS "GO!" per the 16-03 contract) -- an unconditional label log plus a done-branch log would emit a duplicate GO! line.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Smoke hung VMD at its prompt after PASS (first run exit=124)**

- **Found during:** Task 2 (smoke run)
- **Issue:** the smoke printed `BCHM_SMOKE_RESULT PASS=1 FAIL=none` but had no trailing `exit`, so vmd.exe sat at its `vmd >` prompt and the piped `echo exit` was not consumed in that run -- the outer timeout reaped it (exit=124, marker already green)
- **Fix:** appended the trailing `exit`, matching the shipped phase15_smoke.tcl / phase16_pick_smoke.tcl convention; re-run exited 0 with "Exiting normally."
- **Files modified:** vmd/smoke/phase16_gametab_smoke.tcl
- **Verification:** staged re-run: exit=0, PASS=1, zero ERROR)/bad switch in full log
- **Committed in:** 6d4eee2 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** runner reliability only; no scope creep. The tracked after_winbox/_show_win_box addition is recorded under Decisions Made (it implements the plan's own verification rule rather than deviating from it).

## Issues Encountered
- None beyond the deviation above. Note (documented plan posture, not an issue): start_round calls `game::set_callbacks` per the 16-08 contract (log_cb 1 arg / remaining_cb 0 args / win_cb 2 args); 16-08 is a parallel sibling not yet merged into this worktree's base -- call-time proc resolution makes this safe, and 16-10/16-11 verify the integration. If EITHER side changes arity or the callback list, both specs must move together.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Game tab VIEW complete; remaining Phase-16 work is wiring + integration: 16-08 (controller on_pick/set_callbacks + hider visuals), 16-10 (dialog sources game_tab.tcl at top level, build call in open_dialog replacing the placeholder, on_close gains stop_all_timers, Start handler: collect_state -> start_game -> raise_tab -> set_difficulty -> start_round), 16-11 (integration smoke), 16-12 (GUI human-verify -- widget rendering, pick contract, win-box render timing are all deferred there by design)
- Carry-forward for 16-10: `game_tab::build $nb.game` is eager; widget paths are `$w.nb.game.{status,loglab,logf,mouse}`; `set_difficulty` must be called BEFORE `start_round` for a correct easy-mode label

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
