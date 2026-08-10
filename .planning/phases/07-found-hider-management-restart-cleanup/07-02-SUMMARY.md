---
phase: 07-found-hider-management-restart-cleanup
plan: 02
subsystem: ui
tags: [qt, gui, qcombobox, qcolordialog, restart, cleanup, wizard-lifecycle, pymol-cmd, button-wiring]

# Dependency graph
requires:
  - phase: 07-found-hider-management-restart-cleanup
    provides: Plan 01 pure helpers (build_found_selection + group_found_by_rep) + GameController._found_color attribute (default 'green') + _mark_found parameterized
  - phase: 04-core-game-loop
    provides: GameTab btn_row QHBoxLayout pattern + start_btn wiring pattern (PluginDialog method) + _finish_win wizard deactivate idiom
  - phase: 06-hint-reveal
    provides: GameTab _on_hint_clicked / _on_reveal_*_clicked handler + _confirm guard preamble pattern + start_countdown _reveal_label reset
provides:
  - "Found-hider management dropdown (QComboBox) on Game tab — hide/show/recolor found hiders (GAME-08), filters by HIDER_STATUS_FOUND (NOT color)"
  - "Color picker (QColorDialog) on Game tab — player-chosen highlight color (DIFF-04), auto-recolors existing found + new finds use it"
  - "Restart button on Game tab wired to _on_restart (GAME-10) — deactivate wizard + stop timer + _on_start (fresh round)"
  - "Cleanup button on Setup tab wired to _on_cleanup (BTN-06) — restore original object + reset UI + release controller"
  - "Wizard-lifecycle fix folded into _on_start — deactivates old PickWizard before cleanup (fixes BOTH Start-mid-game AND Restart mouse_selection_mode corruption)"
  - "start_countdown clears _info_log (fresh round = clean log); _begin_play defensively stops timer before start"
affects: [07-found-hider-management-restart-cleanup (Plan 03 human-verify checkpoint), 08-persistence-shareable-puzzles (cleanup/restart state transitions), 10-polish-endgame-help (win-screen + post-game debrief)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — QColorDialog + QComboBox from pymol.Qt QtWidgets (already imported)
  patterns:
    - "Wizard-lifecycle fix FOLDED INTO _on_start (not just _on_restart) — fixes BOTH Start-mid-game AND Restart with one change; _on_restart is belt-and-suspenders (also deactivates, no-op if already None)"
    - "Dropdown filters by HIDER_STATUS_FOUND (NOT by color) — found hiders may be recolored to any color, so status is the only reliable predicate"
    - "QColorDialog.getColor() static method runs its own modal event loop (NOT .exec_()) — child-dialog modal pattern, does NOT violate the modeless-main rule; exec_ grep gate stays at 1"
    - "Combo uses `activated` signal (NOT `currentIndexChanged`) so the index-0 placeholder doesn't fire on construction; reset to 0 after handling for re-selection"
    - "Buttons created in their tab module, wired in __init__.py (composition root) — same pattern as start_btn (Phase 4)"

key-files:
  created: []
  modified:
    - biochemeleon/gui_game.py
    - biochemeleon/gui_setup.py
    - biochemeleon/__init__.py

key-decisions:
  - "Wizard-lifecycle fix folded into _on_start itself (NOT just _on_restart) — the research (07-RESEARCH.md section 2) identifies the bug exists for BOTH Start-mid-game AND Restart; folding the fix into _on_start fixes both paths with one change. _on_restart then just adds timer.stop() + calls _on_start (wizard deactivation already handled)."
  - "Dropdown filters by HIDER_STATUS_FOUND (NOT by color) — found hiders may be recolored to any color via DIFF-04, so color is not a reliable predicate; status is the canonical found-flag (set by _mark_found in game.py)."
  - "QColorDialog.getColor() static method (NOT .exec_()) — runs its own modal event loop internally; it is a child dialog (like QFileDialog/QMessageBox), allowed to be modal without violating the 'main dialog stays modeless' rule. exec_ grep gate stays at 1 (existing _finish_win msg.exec_())."
  - "Combo uses `activated` signal (NOT `currentIndexChanged`) — prevents the index-0 placeholder from firing on construction; reset to 0 after handling so the user can re-select the same action."
  - "Restart button created in gui_game.py but wired in __init__.py (same pattern as start_btn) — keeps the tab module focused on widget construction and the composition root responsible for cross-tab wiring."

patterns-established:
  - "Pattern: wizard-lifecycle fix in the composition root's _on_start — deactivate old PickWizard before any cleanup/create; idempotent (no-op if wizard is None). Fixes mouse_selection_mode corruption for both Start-mid-game and Restart."
  - "Pattern: found-hider management dropdown filters by status, NOT color — status is the canonical found-flag; color is mutable via DIFF-04."
  - "Pattern: QColorDialog.getColor() static method for color picking — modal child dialog without .exec_(), preserving the modeless-main rule."

# Metrics
duration: 4min
completed: 2026-08-11
---

# Phase 7 Plan 2: GUI Wiring — Found-Hider Dropdown + Color Picker + Restart + Cleanup Summary

**Qt GUI wiring for 4 Phase-7 requirements (GAME-08 dropdown, DIFF-04 color picker, GAME-10 restart, BTN-06 cleanup) + wizard-lifecycle fix in _on_start that prevents mouse_selection_mode corruption on BOTH Start-mid-game AND Restart**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-10T23:46:12Z
- **Completed:** 2026-08-10T23:50:50Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- **Found-hider dropdown (GAME-08)** in gui_game.py: QComboBox with 3 actions (Hide found / Show found / Recolor found) + index-0 placeholder. `_on_found_mgmt(mode)` core helper filters the registry by `HIDER_STATUS_FOUND` (NOT by color — found hiders may be recolored to any color); uses `build_found_selection` + `group_found_by_rep` from Plan 01. `_on_found_mgmt_activated(index)` maps combo index to mode and resets to 0 for re-selection. Show mode re-shows each found hider in its ORIGINAL rep (per-rep `cmd.show` via `group_found_by_rep`).
- **Color picker (DIFF-04)** in gui_game.py: `_on_pick_color` uses `QColorDialog.getColor()` static method (NOT `.exec_()` — runs its own modal loop; child-dialog pattern, modeless-main rule preserved). Sets a PyMOL named color `found_highlight` via `cmd.set_color`, assigns to `controller._found_color` (so new finds use it), and auto-recolors existing found hiders immediately.
- **Restart (GAME-10)** + **Cleanup (BTN-06)** in __init__.py: `_on_restart` deactivates wizard + stops timer + calls `_on_start` (fresh round with new hiders from Setup tab). `_on_cleanup` deactivates wizard + stops timer + `controller.cleanup()` (restores original object from backup) + resets Game tab UI (log/timer/remaining/reveals) + releases controller (`_controller = None`).
- **Wizard-lifecycle fix** folded into `_on_start`: deactivates the old PickWizard BEFORE the cleanup block. Without this, clicking Start mid-game (or Restart) created a new wizard in `_begin_play` without deactivating the old one, corrupting `mouse_selection_mode` (stays at 0) and losing the prior-wizard reference. Folding the fix into `_on_start` fixes BOTH paths with one change (research 07-RESEARCH.md section 2).
- **Fresh-round log + defensive timer stop**: `start_countdown` clears `_info_log` before "Get ready..." (fresh round = clean log; fixes the research finding for BOTH Start and Restart). `_begin_play` defensively calls `_timer.stop()` before `_timer.start(1000)` (idempotent — safe if Restart fires mid-game).
- **All WSL gates green**: py_compile all modules + 200 tests pass (no regression) + package-wide Pitfall-1=0 + exec_ gate unchanged at 1 (existing `msg.exec_()` in `_finish_win` only; NO new `.exec_()` from QColorDialog).

## Task Commits

Each task was committed atomically:

1. **Task 1: Found-hider dropdown + color picker + restart button + fixes in gui_game.py** - `971e6f0` (feat)
2. **Task 2: Cleanup button in gui_setup.py** - `8a6248e` (feat)
3. **Task 3: _on_restart + _on_cleanup + wizard-lifecycle fix + button wiring in __init__.py** - `1b70897` (feat)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified
- `biochemeleon/gui_game.py` - Added QComboBox (`_found_mgmt_combo`) + Color… QPushButton (`_color_btn`) + Restart QPushButton (`_restart_btn`) to btn_row (after Reveal-all, before stretch). Added 3 handler methods: `_on_found_mgmt(mode)` (core — filters by HIDER_STATUS_FOUND, uses build_found_selection + group_found_by_rep), `_on_found_mgmt_activated(index)` (combo index → mode, reset to 0), `_on_pick_color` (QColorDialog.getColor → cmd.set_color → _found_color assign → auto-recolor). Fixed `start_countdown` to clear `_info_log` (fresh round = clean log). Fixed `_begin_play` to defensively `_timer.stop()` before `_timer.start(1000)`. 195→275 lines.
- `biochemeleon/gui_setup.py` - Added `cleanup_btn` ("Cleanup model") to the Setup actions QGroupBox between `load_btn` and `start_btn` (BTN-06). Tooltip distinguishes Cleanup (restore original) from Restart (new round). NOT wired here (wired in __init__.py). 582→588 lines.
- `biochemeleon/__init__.py` - Added wizard-lifecycle fix in `_on_start` (deactivate old PickWizard before cleanup). Added `_on_restart` (GAME-10: deactivate wizard + stop timer + _on_start) and `_on_cleanup` (BTN-06: deactivate wizard + stop timer + controller.cleanup + UI reset + release controller). Wired `cleanup_btn.clicked → _on_cleanup` and `_restart_btn.clicked → _on_restart`. 231→287 lines.

## Decisions Made
- **Wizard-lifecycle fix folded into _on_start** (NOT just _on_restart): the research identifies the bug for BOTH Start-mid-game AND Restart. Folding the fix into _on_start fixes both paths with one change; _on_restart is then belt-and-suspenders (also deactivates, no-op if already None).
- **Dropdown filters by HIDER_STATUS_FOUND, NOT by color**: found hiders may be recolored to any color via DIFF-04, so color is not a reliable predicate. Status is the canonical found-flag (set by `_mark_found` in game.py).
- **QColorDialog.getColor() static method (NOT .exec_())**: runs its own modal event loop internally; child-dialog modal pattern (like QFileDialog/QMessageBox), does NOT violate the modeless-main rule. The exec_ grep gate stays at 1 (existing `_finish_win` `msg.exec_()` only).
- **Combo uses `activated` signal (NOT `currentIndexChanged`)**: prevents the index-0 placeholder from firing on construction. Reset to 0 after handling so the user can re-select the same action.
- **Buttons created in tab module, wired in __init__.py** (composition root): same pattern as `start_btn` (Phase 4). Keeps the tab module focused on widget construction; the composition root owns cross-tab wiring.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded _on_pick_color docstring to avoid literal `.exec_()` tokens that tripped the exec_ grep gate**
- **Found during:** Task 1 (gui_game.py handler methods)
- **Issue:** The plan's suggested docstring for `_on_pick_color` contained the literal tokens `.exec_()` and `msg.exec_()` in prose ("NOT .exec_() -- does not violate the modeless-main rule; the exec_ grep gate stays at 1 = existing _finish_win msg.exec_()"). These literal tokens tripped the exec_ grep gate, which returned 3 matches (2 docstring + 1 real `msg.exec_()` in `_finish_win`) instead of the required 1. This is the AGENTS.md-documented docstring false-positive pattern ("literal tokens in comments/docstrings trip this grep too") and mirrors the Phase 3 03-02/03-06/03-09/03-10 precedent.
- **Fix:** Reworded the docstring to describe the behavior without the literal `.exec_()` token: "it does NOT use the exec_ modal call from our code, so the modeless-main rule is preserved and the exec_ grep gate stays at 1 (the existing _finish_win modal message only)." The word "exec_" appears but NOT followed by `()` so the `\.exec_\(\)` regex no longer matches.
- **Files modified:** biochemeleon/gui_game.py
- **Verification:** exec_ grep gate returns 1 (the real `msg.exec_()` in `_finish_win` at line 271 only); py_compile clean; 200 tests pass.
- **Committed in:** 971e6f0 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — docstring false-positive on grep gate)
**Impact on plan:** The rewording is cosmetic (docstring clarity only); no behavior change. Mirrors the established repo precedent for grep-gate false-positives. No scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Plan 03 (human-verify checkpoint) is the next step**: this plan is Qt+cmd-coupled — runtime behavior (dropdown hide/show/recolor, color picker modal, Restart fresh round, Cleanup restore, wizard-lifecycle fix) is NOT verifiable in WSL beyond py_compile + grep gates + existing unit tests. Plan 03 should run a headless smoke (if a pure-cmd path exists for the cleanup/restart state transitions) OR a human-verify checkpoint in a real Windows PyMOL GUI session covering all 4 Phase-7 success criteria + the wizard-lifecycle fix (Start-mid-game + Restart both leave mouse_selection_mode correct).
- **No blockers**: all 200 tests pass, all WSL gates green (py_compile + Pitfall-1=0 + exec_=1 unchanged), module dependency direction intact (gui_game.py imports from setup_state + registry lazily; __init__.py is the composition root).
- **What Plan 03 should verify at runtime**: (1) Found-hider dropdown Hide/Show/Recolor on a partially-found game; (2) Color picker sets a visible new color on existing + new finds; (3) Restart mid-game produces a fresh round (new hiders, clean log, timer restarts, wizard re-activates with correct mouse_selection_mode); (4) Cleanup restores the original atom count + no GAME atoms + UI reset + controller released; (5) Start-mid-game (clicking Start while a game is active) deactivates the old wizard cleanly (mouse_selection_mode correct, no stale wizard reference).

---
*Phase: 07-found-hider-management-restart-cleanup*
*Completed: 2026-08-11*
