---
phase: 16-mvp-core-loop-sphere
plan: 14
subsystem: gui
tags: [tcl, vmd-1.9.3, tk, pick-bridge, game-loop, double-start, gap-closure]

# Dependency graph
requires:
  - phase: 16-mvp-core-loop-sphere (16-13)
    provides: guarded game::start_game (active-game guard consumes any live/prior round before starting fresh)
  - phase: 16-mvp-core-loop-sphere (16-06)
    provides: pick_bridge activate/deactivate (idempotent, molid-filtered _on_event)
  - phase: 16-mvp-core-loop-sphere (16-10)
    provides: dialog.tcl on_start BTN-07 fan-in + game_tab start_round wiring
provides:
  - on_start tears down the previous round's pick bridge (step 3.5, catch-guarded) between validate_state and game::start_game
  - start_round resets the previous round's view state (timer_text / mode_text / mouse_mode) after stop_all_timers, before the game_state stash
  - a mid-round or after-win double-Start now yields a fresh PLAYABLE round at the GUI layer: bridge re-arms on the NEW game molecule at GO; no stale timer/pick-mode indicators leak into the countdown window
affects: [16-16 (GUI checkpoint item 5 — real-click double-Start re-check), 16-15 (restart smoke), phase-19 (Cleanup/Restart buttons build on the same start flow)]

# Tech tracking
tech-stack:
  added: []   # none — Tcl 8.5 stdlib + existing pick_bridge API only
  patterns:
    - "teardown-before-start: bridge deactivate sits AFTER the abort paths (validate) and BEFORE the new round starts — a failed validation leaves a live round untouched"
    - "view-state reset immediately after timer cancellation in restart paths (stop_all_timers -> reset widget-bound vars); programmatic variable sets fire no -command"

key-files:
  created: []
  modified:
    - vmd/gui/dialog.tcl
    - vmd/gui/game_tab.tcl

key-decisions:
  - "Teardown inserted as step '3.5' (and view reset as '1.5') instead of renumbering steps 4-7 / 2-7 — comment style stays minimal-diff and the numbered steps keep their historical references"
  - "No game::cleanup added to on_close — the dialog-closed-mid-round path composes with 16-13's guard: game.tcl is never re-sourced mid-session so current_state survives the close and is consumed by the guard on the next Start (cleanup-on-close is Phase 19 scope)"
  - "gs flow from start_game into game_tab::start_round untouched — the returned (possibly remapped) game_state is already the stash source"

patterns-established:
  - "Abort-path-first ordering for pre-start side effects: anything that disturbs a live round goes after the tk_messageBox returns, immediately before start_game"
  - "Countdown-window view hygiene: a new round resets timer/mouse-mode indicators at start_round entry, since the bridge stays DOWN until GO"

# Metrics
duration: 5 min
completed: 2026-08-30
---

# Phase 16 Plan 14: Double-Start GUI Integration (gap-1 GUI half) Summary

**on_start now tears down the previous round's pick bridge between validation and start_game, and start_round resets the stale timer/mouse-mode view — a mid-round double-Start re-arms the bridge on the NEW game molecule instead of leaving it bound to the dead old molid silently dropping every pick.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-08-30T16:09:18Z
- **Completed:** 2026-08-30T16:14:37Z
- **Tasks:** 2/2
- **Files modified:** 2

## Accomplishments
- Step 3.5 in `::biochemeleon::on_start`: catch-guarded `pick_bridge::deactivate` placed AFTER the abort paths (collect_state / target resolve / validate_state) and BEFORE `game::start_game` — a failed Start leaves a running round untouched; a committed Start can no longer inherit the dead-old-molid bridge (idempotent no-op on fresh session / after a win, where on_win already deactivated it).
- Step 1.5 in `::biochemeleon::game_tab::start_round`: after `stop_all_timers` and before the game_state stash, `timer_text`/`mode_text`/`mouse_mode` reset to `0:00` / `Mouse: Rotate` / `rotate` — the previous round's frozen timer and pick-mode panel cannot leak into the new countdown window (the bridge is DOWN until GO, so the panel now reflects reality). Programmatic variable sets fire no `-command`, so no viewer call happens.
- on_start header doc-comment updated to an 8-entry flow (3.5 inserted) so the documented flow matches the code.
- Verified headlessly: entry + gametab load-gate smokes PASS=1 FAIL=none on fresh staging (`tmp/gap14`), full-log scan clean (0 `ERROR)`, 0 `bad switch`, both "Exiting normally"); 8.5-idioms and modeless (grab set) gates zero.

## Task Commits

Each task was committed atomically:

1. **Task 1: on_start tears down the previous round's pick bridge** - `f223e61` (feat)
2. **Task 2: start_round resets the previous round's view state** - `1cb5d61` (feat)

**Plan metadata:** (this commit — docs(16-14))

## Files Created/Modified
- `vmd/gui/dialog.tcl` - on_start step 3.5 catch-guarded pick_bridge teardown + header flow list updated (20 insertions)
- `vmd/gui/game_tab.tcl` - start_round step 1.5 view-state reset + one-per-line variable declarations + header sequence sync (24 insertions, 5 deletions)

## Decisions Made
- **"3.5" / "1.5" insertion over renumbering:** keeps the diff minimal and the historical step numbers (4-7 / 2-7) intact; both code and header use the same fractional labels.
- **No `game::cleanup` in on_close:** the surviving `current_state` stash is consumed by 16-13's guard on the next Start ("dialog closed mid-round" path); cleanup-on-close is Phase 19 scope per the plan.
- **`gs` flow untouched:** start_round already stashes the guard's possibly-remapped game_state (16-13 may start on the restored original molecule).

## Deviations from Plan

### Minor (doc-only, in plan spirit)

**1. start_round header doc-comment also synced** (plan only mandated the on_start header update)
- **Found during:** Task 2
- **Issue:** start_round's header sequence list ("stop_all_timers FIRST -> stash -> ...") would no longer match the code once step 1.5 was inserted — the same documented-flow-matches-code principle the plan applied to on_start.
- **Fix:** inserted "reset the PREVIOUS round's stale view state (16-14 ...)" into the header sequence line.
- **Files modified:** vmd/gui/game_tab.tcl (comment only)
- **Verification:** structural greps + smokes unaffected (comment-only)
- **Committed in:** 1cb5d61 (Task 2 commit)

---

**Total deviations:** 1 minor doc-only sync (no behavior change, no Rule 1-4 triggers)
**Impact on plan:** None — code changes match the plan verbatim.

## Issues Encountered
- `tclsh` is not installed in this WSL env (known — 13-01 decision), so the interactive `info complete` parse check was replaced by the headless VMD smokes (both touched files are sourced by them; a parse error would fail the entry smoke). Both smokes passed.
- None otherwise.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Gap 1 (double-Start stacking) now closed at BOTH layers: 16-13's guard in `game::start_game` (code half) + this plan's GUI half (bridge teardown + view reset). The observed session defects are addressed: no stacked generations, no dead-molid bridge, no frozen-timer leak into the countdown.
- **Deferred to 16-16 checkpoint (item 5):** real-click GUI re-check — press Start during a round and after a won round; expect a fresh playable round (fresh countdown, timer at 0:00, Mouse: Rotate until GO, picks land on the new molecule, no stacked generations). Tk never loads headless, so this plan's smokes prove load-level integrity only.
- Sibling plans in the wave: 16-15 (formal restart regression smoke) is independent of these files; 16-16 consumes both.
- STATE.md: dated decision entry appended (append-only) per orchestrator instruction; Current Position intentionally untouched (orchestrator reconciles post-merge).

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
