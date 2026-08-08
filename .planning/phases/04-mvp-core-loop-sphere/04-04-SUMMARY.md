---
phase: 04-mvp-core-loop-sphere
plan: 04
subsystem: ui
tags: [qt, pymol-qt, qtimer, gametab, countdown, singleShot, QMessageBox, callback-wiring]

# Dependency graph
requires:
  - phase: 04-mvp-core-loop-sphere
    provides: PickWizard (wizard.py plan 04-02 — created+activated in _begin_play) + GameController.set_callbacks/on_win/_remaining (game.py plan 04-03 — wired via set_callbacks, controller is duck-typed)
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: PluginDialog (__init__.py owns game_tab; plan 04-05 will wire start_btn -> start_countdown)
provides:
  - GameTab(QWidget) — player-facing game state surface (GAME-01 rolling log, GAME-02 timer, GAME-03 remaining)
  - GameTab.start_countdown(controller) — 3-2-1 countdown entry point (called by PluginDialog._on_start in plan 04-05)
  - GameTab._begin_play — creates+activates PickWizard, registers callbacks, starts QTimer
  - GameTab._on_win(elapsed) — stops QTimer + QMessageBox.information modal win message (LOOP-03)
  - GameTab._log / _update_remaining / _on_tick — callback targets the controller drives
affects: [04-05 (PluginDialog._on_start calls game_tab.start_countdown(controller) after tab switch), 04-06 (human-verify: ticking/clicking/win behavior in real PyMOL), Phase 6 (hint/reveal buttons add to this tab), Phase 7 (restart/cleanup buttons add to this tab), Phase 8 (save/import buttons add to this tab)]

# Tech tracking
tech-stack:
  added: []  # no new libraries (import time is stdlib; QtCore/QWidgets via pymol.Qt already used)
  patterns: [QTimer-singleShot-countdown-chain (NEVER time.sleep), lazy-import-in-method (PickWizard imported inside _begin_play not at module load), duck-typed-controller (no game.py import — passed via start_countdown), callback-wiring (set_callbacks binds GameTab methods to controller)]

key-files:
  created: []
  modified:
    - biochemeleon/gui_game.py

key-decisions:
  - "Countdown via QTimer.singleShot chain — NEVER time.sleep (blocks Qt event loop + freezes PyMOL; 04-RESEARCH.md Q21)"
  - "PickWizard imported LAZILY inside _begin_play (not at module load) — wizard.py imports pymol.wizard which may not be available at import time; gui_game.py module load must not pull it"
  - "Controller is duck-typed — passed in via start_countdown(controller), NO import of game.py in gui_game.py (avoids circular import + keeps gui_game decoupled)"
  - "Win message via QMessageBox.information (static helper, modal child dialog — allowed per AGENTS.md; main plugin dialog stays modeless)"
  - "_start_time set in _begin_play (NOT start_countdown) so timer measures play time, not countdown time"
  - "controller._wizard = self._wizard set in _begin_play so GameController.win() can deactivate the wizard on win — intentional cross-reference (controller holds a plain attr, no import of wizard)"
  - "Do NOT deactivate wizard in _on_win — GameController.win() (plan 04-03) already does that; avoid double-deactivate"

patterns-established:
  - "QTimer.singleShot countdown chain pattern: _countdown_step(n) logs n, singleShot(1000, lambda: _countdown_step(n-1)), base case n==0 -> _begin_play (NEVER time.sleep)"
  - "Lazy sibling import inside a method: `from .wizard import PickWizard` inside _begin_play keeps module load cheap + avoids pulling pymol.wizard until a game actually starts"
  - "Duck-typed controller wiring: gui_game.py receives the controller as a parameter (start_countdown), calls set_callbacks/on_pick-implicitly-via-wizard/_remaining on it — no import of game.py"

# Metrics
duration: 3min
completed: 2026-08-08
---

# Phase 4 Plan 04: GameTab UI (Log/Timer/Remaining/Countdown/Win) Summary

**Populated GameTab with QTextEdit rolling log + QLabel timer (1 Hz QTimer main-thread) + QLabel remaining + 3-2-1 QTimer.singleShot countdown chain + _begin_play (lazy PickWizard + set_callbacks + QTimer.start) + _on_win (QTimer.stop + QMessageBox.information) — the player-facing game state surface ready for plan 04-05 to wire Start**

## Performance

- **Duration:** 3 min
- **Started:** 2026-08-08T03:05:31Z
- **Completed:** 2026-08-08T03:09:12Z
- **Tasks:** 3 (UI populate, methods, commit+gate sweep)
- **Files modified:** 1 (biochemeleon/gui_game.py)

## Accomplishments
- GameTab now has all three display widgets (GAME-01/02/03): QTextEdit read-only rolling log (append-only auto-scroll), QLabel timer (M:SS, 1 Hz QTimer), QLabel remaining count — driven by a 1 Hz QTimer on the Qt main thread (PITFALLS.md Pitfall 6: NEVER threading.Thread)
- 3-2-1 countdown via QTimer.singleShot chain (NEVER time.sleep — blocks Qt event loop + freezes PyMOL; 04-RESEARCH.md Q21) then _begin_play
- _begin_play creates + activates a PickWizard (lazily imported), sets controller._wizard (so GameController.win deactivates it), registers set_callbacks(on_log/on_remaining_changed/on_win), starts the QTimer, initializes the remaining count
- _on_win stops the QTimer and shows a modal QMessageBox.information with the time taken (LOOP-03); main plugin dialog stays modeless
- All WSL gates green: py_compile clean, 152 tests pass (no regression), Pitfall-1=0 package-wide, exec_=0 package-wide, no time.sleep, singleShot=1, lazy wizard import=1, set_callbacks=1 (actual call), QMessageBox.information=1, no game.py import (duck-typed controller)

## Task Commits

Each task was committed atomically (tasks 1+2 staged the single file; task 3 made the commit per the plan's consolidated commit instruction):

1. **Task 1: Populate GameTab UI (log + timer + remaining)** - staged (no separate commit — plan consolidates at task 3)
2. **Task 2: Add countdown + _begin_play + callbacks + _on_tick + _on_win** - staged (no separate commit — plan consolidates at task 3)
3. **Task 3: Commit + final gate sweep** - `f397045` (feat)

_Single commit for the populated file (plan task 3 specifies the commit command verbatim). All three tasks built one file; commit made once all gates green._

## Files Created/Modified
- `biochemeleon/gui_game.py` - Replaced 13-line Phase-1 stub with full GameTab(QWidget): QTextEdit rolling log + QLabel timer + QLabel remaining + 1 Hz QTimer + start_countdown/_countdown_step/_begin_play/_on_tick/_on_win/_log/_update_remaining methods (13 → 94 lines)

## Decisions Made
- **Countdown via QTimer.singleShot chain (not time.sleep):** time.sleep blocks the Qt event loop AND freezes PyMOL (04-RESEARCH.md Q21). The singleShot chain logs "3", waits 1s, logs "2", waits 1s, ..., logs "GO!" then calls _begin_play — all non-blocking.
- **Lazy PickWizard import inside _begin_play:** wizard.py does `from pymol.wizard import Wizard` at module level. Importing wizard.py at gui_game.py module load would pull pymol.wizard eagerly. Instead, `from .wizard import PickWizard` runs only inside _begin_play (when a game actually starts). gui_game.py module load stays cheap + avoids any pymol.wizard availability issues at import time.
- **Duck-typed controller (no game.py import):** gui_game.py receives the controller via `start_countdown(controller)` and calls `controller.set_callbacks(...)`, `controller._wizard = ...`, `controller._remaining()`, `controller.target_obj` on it — no import of game.py. This avoids a circular import (game.py is the composition root; gui_game is wired by __init__.py in plan 04-05) and keeps gui_game decoupled.
- **controller._wizard set in _begin_play:** GameController.win() (plan 04-03) deactivates `self._wizard` on win. _begin_play sets `self._controller._wizard = self._wizard` so the controller can reach the wizard it didn't create. Intentional cross-reference (controller holds a plain attr, no import of wizard).
- **_on_win does NOT deactivate the wizard:** GameController.win() already deactivates it (sets `self._wizard = None` after deactivate). _on_win only stops the QTimer + shows the message — avoids double-deactivate.
- **_start_time set in _begin_play (not start_countdown):** the timer measures play time, not countdown time. _begin_play runs after the 3-2-1 countdown completes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded module docstring to satisfy set_callbacks exact-count grep gate**
- **Found during:** Task 2 (verification)
- **Issue:** The plan's verbatim module docstring contained "(set_callbacks)" on line 8, which tripped the plan's own verification gate `grep set_callbacks biochemeleon/gui_game.py → 1` (returned 2: the docstring mention + the actual call on line 79). This mirrors the AGENTS.md-documented docstring false-positive pattern (the "from PyQt5 import" precedent) and the Phase 3 Rule-3 docstring-rewording precedent (03-02/03-03/03-06/03-09/03-10).
- **Fix:** Removed the parenthetical "(set_callbacks)" from the docstring — changed "registers the GameController callbacks (set_callbacks) so" to "registers the GameController callbacks so". The actual set_callbacks call on line 79 is now the sole match.
- **Files modified:** biochemeleon/gui_game.py (docstring line 8)
- **Verification:** `grep set_callbacks biochemeleon/gui_game.py` → 1 match (line 79, the actual call). py_compile clean, 152 tests pass.
- **Committed in:** f397045 (part of the task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — docstring false-positive on plan's own verification grep)
**Impact on plan:** Cosmetic docstring reword to satisfy the plan's exact-count grep gate. No functional change. No scope creep. Mirrors established Phase 3 precedent.

## Issues Encountered
None — plan executed cleanly. The 1 deviation was a docstring false-positive caught and fixed during verification (standard Rule-3 pattern for this codebase).

## User Setup Required
None — no external service configuration required. gui_game.py is Qt+cmd-coupled and runs inside PyMOL (Windows conda env via setenv.bat); no WSL runtime test possible (Qt needs a real display). Real ticking/clicking/win behavior deferred to human-verify (plan 04-06) in a real PyMOL session.

## Next Phase Readiness
- **Ready for plan 04-05:** PluginDialog._on_start will call `game_tab.start_countdown(controller)` after resolving the target, generating sphere hider specs, calling `GameController.start(hider_specs)`, and switching to the Game tab. The GameTab API (start_countdown receiving a duck-typed controller) is the contract 04-05 consumes.
- **Ready for plan 04-06:** The human-verify checkpoint will confirm ticking (QTimer 1 Hz), countdown display (3-2-1 GO!), click-to-find (PickWizard do_pick -> on_pick -> log/remaining callbacks), and win message (QMessageBox.information) in a real Windows PyMOL session.
- **No blockers.** gui_game.py is Qt+cmd-coupled (verified by py_compile + grep gates only in WSL); runtime behavior deferred to human-verify (04-06). All dependency-direction rules respected: gui_game imports pymol.Qt + lazily imports .wizard inside _begin_play; does NOT import game.py (controller duck-typed).

---
*Phase: 04-mvp-core-loop-sphere*
*Completed: 2026-08-08*
