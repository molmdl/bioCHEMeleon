---
phase: 06-hint-reveal
plan: 02
subsystem: ui
tags: [pymol, qt, gui, game-tab, hint, reveal, buttons, qmessagebox, callbacks, duck-typed]

# Dependency graph
requires:
  - phase: 06-hint-reveal
    provides: GameController.hint()/reveal_one()/reveal_all() + on_counts_changed 4th set_callbacks param + _reveal_count/_hint_count counters
  - phase: 04-mvp-core-loop-sphere
    provides: GameTab(QWidget) layout — log/timer/remaining/countdown/_begin_play/_finish_win
provides:
  - GameTab Hint/Reveal-one/Reveal-all QPushButtons + reveal counter QLabel (Phase 6 Game-status-tab surface)
  - GameTab._confirm(title, text) Yes/No helper using QMessageBox.question(self.window(), ...) (above-OpenGL-window pattern from _finish_win)
  - GameTab._on_counts_changed(hint_count, reveal_count) slot updating the reveal-counter label
  - GameTab._on_hint_clicked/_on_reveal_one_clicked/_on_reveal_all_clicked handlers (guard: None/not-started/remaining==0; reveal paths show confirm before calling controller)
  - 4th callback (on_counts_changed) registered in _begin_play set_callbacks call
affects: [06-03 (headless smoke + human-verify checkpoint for the full Hint/Reveal GUI flow), Phase 7 (restart reuses GameTab; counters reset via controller.start), Phase 10 (win screen consumes hint_count via the on_counts_changed signature)]

# Tech tracking
tech-stack:
  added: []
  patterns: [QMessageBox.question static method for Yes/No confirm (no exec_ from our code — the static method owns its own event loop), self.window() top-level parent for child dialogs (above PyMOL OpenGL window — same fix as _finish_win Bug B), button guards early-return on None/not-started/remaining==0 (defensive for pre-game + post-win clicks), duck-typed controller (NO game.py import — controller passed via start_countdown)]

key-files:
  created: []
  modified:
    - biochemeleon/gui_game.py

key-decisions:
  - "Hint button has NO confirm dialog (hint is help, not give-up); Reveal-one + Reveal-all DO show a Yes/No confirm BEFORE calling the controller (give-up actions warrant a confirmation gate)"
  - "_confirm uses QMessageBox.question(self.window(), title, text, Yes|No) static method — does NOT call .exec_() from our code (the static method owns its modal event loop); exec_ gate stays at 1 (only the existing _finish_win)"
  - "_on_counts_changed stores hint_count implicitly via the callback signature (param accepted but only reveal_count is displayed in Phase 6 — hint_count is reserved for the Phase 10 win screen)"
  - "All 3 button handlers share the same 2-guard preamble (controller is None/not _started; _remaining()==0) — early-return, no log, no error (defensive for clicks before countdown completes, after win, or after all-found)"
  - "4th callback registered in _begin_play set_callbacks — the ONLY change to _begin_play; everything else (lazy wizard import, activate, _start_time, timer.start, _update_remaining) untouched"

patterns-established:
  - "Reveal/give-up actions require a confirm dialog; help actions (hint) do not — UX rule for future give-up features"
  - "Child dialogs (confirm, win message) use self.window() as parent (the top-level PluginDialog) so they appear above the PyMOL OpenGL window — reuses the Phase 4 _finish_win Bug B fix"
  - "GUI handlers guard against no-active-game (controller None / not _started / remaining 0) — silent early-return, no log spam, so the buttons are safe to click at any tab state"

# Metrics
duration: 2 min
completed: 2026-08-09
---

# Phase 6 Plan 2: GUI Hint/Reveal Buttons Summary

**Wired 3 QPushButtons (Hint/Reveal-one/Reveal-all) + reveal counter QLabel into GameTab, with a QMessageBox.question confirm helper and the on_counts_changed callback — closing GAME-05/06/07/DIFF-01 at the GUI tier**

## Performance

- **Duration:** 2 min
- **Started:** 2026-08-09T18:38:00Z
- **Completed:** 2026-08-09T18:40:49Z
- **Tasks:** 2 (both auto, not TDD)
- **Files modified:** 1

## Accomplishments
- GameTab now has a Hint QPushButton, a Reveal-one QPushButton, a Reveal-all QPushButton, and a reveal-counter QLabel ("Reveals: N") in a new btn_row below the timer/remaining row (Phase 6 GUI surface for GAME-05/06/07 + DIFF-01)
- _confirm(title, text) Yes/No helper uses QMessageBox.question(self.window(), ...) — the static method owns its modal event loop (no .exec_() from our code); reuses the Phase 4 _finish_win Bug B fix (top-level parent → dialog appears above the PyMOL OpenGL window)
- _on_counts_changed(hint_count, reveal_count) slot updates the reveal-counter label via the 4th controller callback (hint_count accepted but not displayed in Phase 6 — reserved for the Phase 10 win screen)
- 3 button handlers (_on_hint_clicked / _on_reveal_one_clicked / _on_reveal_all_clicked) all share a 2-guard preamble (controller None/not _started → return; _remaining()==0 → return); Hint calls controller.hint() directly (help, no confirm); Reveal-one + Reveal-all show a confirm dialog BEFORE calling the controller (give-up actions warrant a gate)
- _begin_play registers on_counts_changed as the 4th set_callbacks param (the ONLY change to _begin_play; existing on_log/on_remaining_changed/on_win + lazy wizard import + activate + _start_time + timer.start + _update_remaining all untouched)
- All WSL gates green: py_compile all + 183 tests (18 controller + 90 setup_state + 54 registry + 21 generators, no regression) + Pitfall-1=0 package-wide + exec_=1 (existing _finish_win only, allowed) + no game.py import (duck-typed) + no walrus := + 3 clicked.connect + 2 self.window() + 1 QMessageBox.question

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Hint/Reveal buttons + reveal counter label to GameTab layout** - `7d119dd` (feat)
2. **Task 2: Wire button click handlers + _confirm helper + _on_counts_changed + 4th callback in _begin_play** - `1a0c273` (feat)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified
- `biochemeleon/gui_game.py` - Extended 141→194 lines (+53). Task 1 added a btn_row with 3 QPushButtons (Hint/Reveal one/Reveal all) + a reveal counter QLabel below the timer/remaining row. Task 2 added 5 methods (_confirm, _on_counts_changed, _on_hint_clicked, _on_reveal_one_clicked, _on_reveal_all_clicked), wired 3 clicked.connect signals in __init__, and registered on_counts_changed as the 4th set_callbacks param in _begin_play. Existing widgets/methods (log, timer, remaining, QTimer, countdown, _on_win, _finish_win, _on_tick, start_countdown, _countdown_step, _log, _update_remaining) untouched.

## Decisions Made
- **Hint = no confirm; Reveal = confirm** — hint is help (GAME-05: color neighbors orange, does NOT mark_found), so it needs no confirmation gate. Reveal-one (GAME-06) + Reveal-all (GAME-07) are give-up actions that mark hiders found + count as reveals, so they show a Yes/No confirm BEFORE calling the controller. The confirm text explicitly says "Give up" + "counts as a reveal use" / "ends the game" so the player understands the consequence.
- **_confirm uses QMessageBox.question static method (not a constructed QMessageBox.exec_())** — the static method owns its own modal event loop internally; our code never calls .exec_(). This keeps the exec_ gate at 1 (only the existing _finish_win, allowed by AGENTS.md). Same self.window() top-level parent as _finish_win so the dialog appears above the PyMOL OpenGL window (Phase 4 Bug B fix reused).
- **hint_count is accepted by _on_counts_changed but not displayed in Phase 6** — the callback signature is `(self, hint_count, reveal_count)`; only reveal_count feeds the label ("Reveals: %d"). hint_count is reserved for the Phase 10 win screen (per the plan's "stored for Phase 10" note). Storing it now means the callback signature is forward-compatible — Phase 10 won't need to change the set_callbacks contract.
- **All 3 button handlers share the same 2-guard preamble** — `if self._controller is None or not self._controller._started: return` + `if self._controller._remaining() == 0: return`. Silent early-return (no log, no error). This makes the buttons safe to click at any Game-tab state: before the countdown completes (controller not started), after a win (remaining 0), or after reveal-all ends the game (remaining 0). No log spam, no crash.
- **4th callback registered in _begin_play — the ONLY change to _begin_play** — added `on_counts_changed=self._on_counts_changed,` to the existing set_callbacks call. Everything else in _begin_play (lazy PickWizard import, activate, controller._wizard assignment, _start_time set on both tab + controller, timer.start, _update_remaining call) is untouched. The controller's set_callbacks already accepted the 4th param as a default no-op (Phase 6 plan 06-01), so this is backward-compatible wiring.

## Deviations from Plan

None - plan executed exactly as written. Both tasks followed the plan's verbatim code sketches; all verification gates passed on the first run (py_compile clean, 183 tests pass, Pitfall-1=0, exec_=1 existing-only, no game.py import, no walrus, 3 clicked.connect, 2 self.window(), 1 QMessageBox.question, on_counts_changed >=2). No Rule 1-4 deviations triggered.

## Issues Encountered
None — both tasks were clean. The plan's verbatim code sketches (the btn_row layout, the 5 methods, the signal wiring, the 4th callback) compiled and passed all gates on the first attempt. No docstring-rewording was needed (unlike 06-01's "around" false-positive) because the plan's prose avoided the literal tokens that the grep gates match on.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Ready for 06-03 (smoke + human-verify checkpoint):** The GUI surface (buttons + label + confirm dialogs + callback) is complete and WSL-syntax-verified. Plan 06-03 will add a headless smoke test (pure pymol.cmd.* — no Qt; the controller methods are already smoke-ready via 06-01's mock-tested logic) + a human-verify checkpoint for the full GUI flow (button clicks, confirm dialogs, reveal counter updating, hint coloring). Qt/GUI runtime behavior (button rendering, confirm dialog above OpenGL window, label updates on reveal) is WSL-unverifiable and deferred to the 06-03 human-verify.
- **No blockers.** The GUI is decoupled from the controller (duck-typed — no game.py import; controller passed via start_countdown, same pattern as Phase 4). The controller methods (hint/reveal_one/reveal_all + on_counts_changed) were WSL-unit-tested in 06-01 (18 tests pass); this plan wires them into Qt without changing controller logic.
- **Dependency direction intact:** gui_game.py imports only `pymol.Qt` (QtCore, QtWidgets) + stdlib `time` + lazily `pymol.cmd` (in _on_win) + `.wizard` (lazy in _begin_play). NO import of `game.py` (controller is duck-typed). The architecture direction (setup_state pure ← demos/cmd ← gui_setup/gui_game) is preserved.
- **Phase 7 hook:** The buttons' guard preamble (controller None/not _started → return) means a Phase 7 restart can safely re-enter the Game tab before the new countdown completes — the buttons no-op until _begin_play sets the new controller + _started=True. The reveal counter resets via the controller's start() (which resets _reveal_count=0 per 06-01) → on_counts_changed fires → label shows "Reveals: 0".

---
*Phase: 06-hint-reveal*
*Completed: 2026-08-09*
