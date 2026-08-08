---
status: resolved
trigger: "Three GUI win-loop bugs in Phase 4 (found via human-verify of real PyMOL session): win time always 0:00, last hider doesn't recolor green, viewer frozen + old hiders remain + new game broken"
created: 2026-08-08T00:00:00Z
updated: 2026-08-08T00:05:00Z
---

## Current Focus

hypothesis: ALL THREE root causes pre-confirmed; fixes applied + WSL-verified
test: py_compile + 160 unit tests + pitfall-1/exec_ gates + headless smoke re-run
expecting: all gates green, smoke 19/19 — CONFIRMED
next_action: archive + commit; GUI click-cycle deferred to human-verify

## Symptoms

expected: (1) win time reflects real elapsed; (2) last hider visibly green before win dialog; (3) after win, viewer interactive + hiders cleaned + new game works
actual: (1) win time always "0:00"; (2) win dialog appears but last hider not green; (3) viewer frozen after win + old hiders remain + new game clicks always miss
errors: none (logic/wiring bugs, not crashes)
reproduction: real PyMOL GUI session, 1znf, 3 hiders, play to completion
started: Phase 4 Task 2 human-verify

## Eliminated

- (none — root causes pre-confirmed by user, verified by me reading code)

## Evidence

- timestamp: 2026-08-08T00:01
  checked: gui_game.py:84 vs game.py:94 (Bug 1)
  found: _begin_play sets self._start_time on GameTab; win() reads self._start_time on GameController (init None at game.py:21). Controller's never set -> elapsed=0.0 always.
  implication: Bug 1 confirmed. Fix: set controller._start_time in _begin_play.

- timestamp: 2026-08-08T00:02
  checked: game.py:89-98 win() order + gui_game.py:88-94 _on_win modal (Bug 2)
  found: win() calls _on_win (QMessageBox.information modal, BLOCKS Qt event loop) BEFORE deactivate. cmd.color('green') at game.py:82 never flushes to viewer before modal blocks.
  implication: Bug 2 confirmed. Fix: reorder win() to deactivate FIRST then _on_win; flush cmd.refresh()+processEvents() before modal in _on_win.

- timestamp: 2026-08-08T00:03
  checked: game.py:92 comment "_started STAYS True" + no cleanup() after win + __init__.py:111 replaces controller (Bug 3)
  found: After win, _started stays True, hiders never cleaned. New GameController created at __init__.py:111 overwrites old ref; old hiders remain in object; new registry only knows new ids -> old hider clicks = "Miss!".
  implication: Bug 3 confirmed. Fix: cleanup() in _on_win after modal dismissed; defensive cleanup in _on_start before new game.

- timestamp: 2026-08-08T00:04
  checked: tests/test_game_controller.py test_win_with_wizard + smoke phase4_smoke.py
  found: test uses assert_called_once() (no order check) -> reorder safe. Smoke sets gc._start_time=1234.0 manually (line 50), uses lambda on_win (not gui_game._on_win), calls gc.cleanup() at line 92 explicitly -> my fixes don't touch smoke paths.
  implication: Fixes safe for both unit tests and smoke.

## Resolution

root_cause: (1) _start_time set on wrong object (GameTab not GameController); (2) modal QMessageBox blocks before cmd.color flushes (win() called _on_win before deactivate); (3) no cleanup() after win + __init__ overwrites controller ref without cleanup
fix: |
  Bug 1 (gui_game.py _begin_play): set self._controller._start_time = self._start_time so win() reads a real timestamp.
  Bug 2 (game.py win() + gui_game.py _on_win): reorder win() to deactivate wizard BEFORE _on_win; in _on_win call cmd.refresh() + processEvents() before the modal QMessageBox so the last cmd.color('green') flushes to the viewer.
  Bug 3 (gui_game.py _on_win + __init__.py _on_start): call self._controller.cleanup() after the win modal is dismissed; defensive cleanup of any prior active controller in _on_start before creating a new GameController.
verification: |
  WSL gates: py_compile CLEAN; 160 unit tests OK (test_win_with_wizard/test_win_no_wizard unchanged); pitfall-1 gate 0; exec_ gate 0.
  Headless smoke (Windows PyMOL -cq): 19/19 ALL PASSED (no regression).
  GUI click-cycle (Bugs 1-3 symptoms): DEFERRED to human-verify checkpoint — cannot run Qt/GUI from WSL.
files_changed: [biochemeleon/gui_game.py, biochemeleon/game.py, biochemeleon/__init__.py]
