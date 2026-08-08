---
status: fixing
trigger: "Three remaining GUI win-flow bugs (Phase 4 human-verify iteration 3): last hider no color, win dialog behind PyMOL window, viewer frozen"
created: 2026-08-08T12:00:00Z
updated: 2026-08-08T12:05:00Z
---

## Current Focus

hypothesis: ALL THREE root causes pre-confirmed by user; applying fixes now
test: py_compile + 160 unit tests (after test update) + pitfall-1/exec_ gates + headless smoke re-run
expecting: all gates green, smoke 19/19, test_win_with_wizard updated for deferred deactivation
next_action: apply 3 edits (game.py, gui_game.py, test_game_controller.py), run gates, commit

## Symptoms

expected: (A) last hider visibly green before win dialog; (B) win dialog appears ON TOP of PyMOL window; (C) viewer interactive after win
actual: (A) last hider stays gray — win dialog appears but no green; (B) win dialog hidden behind PyMOL OpenGL window — must click plugin window to see it; (C) viewer frozen until hidden dialog is found + dismissed
errors: none (timing/parent-window bugs, not crashes)
reproduction: real PyMOL GUI session, 1znf, 3 hiders, play to completion
started: Phase 4 Task 2 human-verify iteration 3 (previous iteration fixed win-time-0:00 + cleanup, but last-hider-color fix via cmd.refresh()+processEvents() didn't work in real GUI)

## Eliminated

- hypothesis: cmd.refresh() + processEvents() before modal flushes the green (previous fix)
  evidence: User confirmed in real GUI: last hider still gray. The wizard deactivation's WizardRefresh interferes, and processEvents() processes deactivation events that clobber the pending color redraw.
  timestamp: 2026-08-08T12:00

## Evidence

- timestamp: 2026-08-08T12:01
  checked: game.py:89-104 win() + gui_game.py:92-114 _on_win
  found: win() deactivates wizard (cmd.set_wizard + restore mouse_selection_mode) BEFORE _on_win. _on_win then calls cmd.refresh()+processEvents()+QMessageBox.information. The deactivation triggers WizardRefresh which clobbers the pending green redraw from on_pick's cmd.color('green').
  implication: Bug A root cause confirmed. Fix: remove deactivation from win(); defer it to a delayed _finish_win callback (QTimer.singleShot 100ms) so the green renders first.

- timestamp: 2026-08-08T12:02
  checked: gui_game.py:105-107 QMessageBox.information(self, ...)
  found: Parent is self (GameTab, a QWidget inside PluginDialog). PyMOL OpenGL window is a separate top-level with stay-on-top, so the QMessageBox appears behind it.
  implication: Bug B root cause confirmed. Fix: use self.window() (top-level PluginDialog) as parent + WindowStaysOnTopHint.

- timestamp: 2026-08-08T12:03
  checked: gui_game.py:104-114 modal blocking + viewer interaction
  found: Modal QMessageBox blocks Qt event loop. If hidden behind PyMOL window (Bug B), viewer appears frozen — user can't interact until they find + dismiss the hidden dialog. After dismissal, cleanup() runs and viewer should be interactive (wizard deactivated, mouse mode restored).
  implication: Bug C is a consequence of Bug B. Fixing Bug B (dialog on top) resolves Bug C. The delayed deactivation in _finish_win also ensures mouse_selection_mode is restored before the user tries to interact.

- timestamp: 2026-08-08T12:04
  checked: tests/test_game_controller.py test_win_with_wizard (lines 167-186) + phase4_smoke.py
  found: test asserts wiz.deactivate.assert_called_once() + assertIsNone(gc._wizard) — both will fail after removing deactivation from win(). Smoke uses lambda on_win (no wizard lifecycle), calls w.deactivate() explicitly in spikes — unaffected.
  implication: Must update test_win_with_wizard: deactivate.assert_not_called() + gc._wizard stays set. Smoke needs no changes.

## Resolution

root_cause: |
  Bug A: win() deactivates wizard before _on_win; the deactivation's WizardRefresh clobbers the pending cmd.color('green') redraw from on_pick. The previous fix (cmd.refresh()+processEvents() in _on_win) failed because the wizard was already deactivated and processEvents() processed the deactivation events.
  Bug B: QMessageBox.information(self, ...) uses GameTab as parent (not top-level window); PyMOL OpenGL window's stay-on-top hides the dialog.
  Bug C: Consequence of Bug B — hidden modal blocks event loop, viewer appears frozen.
fix: |
  Bug A: Remove wizard deactivation from win() (game.py); move it to a new delayed _finish_win callback (gui_game.py) triggered by QTimer.singleShot(100ms) from _on_win. The 100ms gap lets PyMOL render the green before wizard teardown.
  Bug B: In _finish_win, create a QMessageBox instance with self.window() as parent + WindowStaysOnTopHint, then exec_().
  Bug C: Fixed by Bug B (dialog visible/on-top) + delayed deactivation (mouse mode restored in _finish_win).
  Test: Update test_win_with_wizard — win() no longer deactivates; gc._wizard stays set (GUI clears it in _finish_win).
verification: [pending]
files_changed: [biochemeleon/game.py, biochemeleon/gui_game.py, tests/test_game_controller.py]
