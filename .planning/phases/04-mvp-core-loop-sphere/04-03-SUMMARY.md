---
phase: 04-mvp-core-loop-sphere
plan: 03
subsystem: game-logic
tags: [tdd, click-to-find, game-controller, callback-interface, pymol-cmd]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: GameController (start/cleanup/abort_on_error/reconstruct_registry) + HiderRegistry (register/get/all/mark_found/HIDER_STATUS_HIDDEN/FOUND) + mutation.insert_hider
provides:
  - GameController.on_pick (click-to-find logic: registry lookup -> miss/found/already-found -> mark_found + recolor + callbacks + win check)
  - GameController.win (elapsed time + on_win callback + wizard deactivate)
  - GameController.set_callbacks (on_log/on_remaining_changed/on_win callback interface)
  - GameController._remaining (count of hidden-status records)
  - GameController._start_time / _wizard instance attrs (set by caller)
affects: [04-04 (gui_game registers callbacks via set_callbacks), 04-05 (__init__ wires wizard ref into gc._wizard), 04-06 (smoke test), Phase 6 (hint/reveal extends on_pick flow)]

# Tech tracking
tech-stack:
  added: []  # no new libraries (import time is stdlib)
  patterns: [callback-interface (keeps controller WSL-testable without Qt), mock-cmd-unit-testing (sys.modules MagicMock + manually-populated registry)]

key-files:
  created:
    - tests/test_game_controller.py
  modified:
    - biochemeleon/game.py

key-decisions:
  - "Callback interface (on_log/on_remaining_changed/on_win) keeps GameController WSL-testable without Qt imports"
  - "Tests construct GameController WITHOUT calling start() and manually populate the registry — start() needs real cmd (mocked cmd.identify returns MagicMock that fails mutation's assert)"
  - "lowercase id in cmd.color selection expression (PyMOL selector keyword, selecting.py:142) — NOT UPPERCASE ID (which is only for iterate expressions)"
  - "_started STAYS True after win() — hiders remain until cleanup() is called (04-RESEARCH Q29)"

patterns-established:
  - "Callback interface pattern: controller fires callbacks (on_log/on_remaining_changed/on_win) instead of importing Qt widgets — GUI registers callbacks via set_callbacks()"
  - "Mock-cmd test pattern for cmd-coupled logic: stub pymol via sys.modules MagicMock, construct controller without start(), manually populate registry, use MagicMock callbacks"

# Metrics
duration: 9min
completed: 2026-08-08
---

# Phase 4 Plan 03: GameController Click-to-Find Logic Summary

**TDD'd GameController.on_pick/win/set_callbacks/_remaining — the click-to-find logic with registry-as-single-source-of-truth, cmd.color recolor feedback, and a callback interface keeping the controller WSL-testable without Qt**

## Performance

- **Duration:** 9 min
- **Started:** 2026-08-07T19:54:56Z
- **Completed:** 2026-08-07T20:04:06Z
- **Tasks:** 3 (RED, GREEN, REFACTOR)
- **Files modified:** 2 (biochemeleon/game.py, tests/test_game_controller.py)

## Accomplishments
- GameController.on_pick implements the full click-to-find loop: registry lookup → miss (no harm, LOOP-01) / found (mark_found + cmd.color green + callbacks) / already-found (no double-count, LOOP-02) → win check (LOOP-03)
- Callback interface (set_callbacks: on_log/on_remaining_changed/on_win) ready for plan 04-04 (gui_game registers callbacks) and 04-05 (__init__ wires wizard ref into gc._wizard)
- 8 WSL unit tests covering all behavior cases: miss, found (last hider → win), already-found, found-not-last, win-no-wizard, win-with-wizard, _remaining, set_callbacks defaults
- Phase 3 orchestrator methods (start/cleanup/abort_on_error/reconstruct_registry) UNCHANGED — 144 prior tests green (no regression), total now 152

## Task Commits

Each task was committed atomically:

1. **RED: failing tests for GameController.on_pick/win/set_callbacks** - `d937a5f` (test)
2. **GREEN: implement on_pick/win/set_callbacks/_remaining** - `9e96b79` (feat)
3. **REFACTOR: no-op (code clean on first pass)** - no commit

_TDD: RED wrote 8 failing tests (AttributeError — methods absent), GREEN implemented the 4 methods + import time + 5 instance attrs, REFACTOR found no cleanup needed._

## Files Created/Modified
- `tests/test_game_controller.py` - 8 WSL unit tests for on_pick/win/set_callbacks/_remaining with mocked cmd + mock callbacks + manually-populated registry (no start() call)
- `biochemeleon/game.py` - Extended GameController with 4 new methods (on_pick/win/set_callbacks/_remaining) + import time + _start_time/_wizard/_on_log/_on_remaining_changed/_on_win attrs (69 → 133 lines); start/cleanup/abort_on_error/reconstruct_registry UNCHANGED

## Decisions Made
- **Callback interface over direct GameTab reference:** set_callbacks(on_log, on_remaining_changed, on_win) keeps GameController testable in WSL (pass mock callbacks, no Qt needed) and avoids importing Qt widgets in the controller. The GUI (plan 04-04) registers callbacks when the game starts.
- **Tests construct without start():** start() needs real cmd (mocked cmd.identify returns a MagicMock that fails mutation's `assert len(ids) == 1`). Instead, tests manually populate `gc.registry.register(...)` and set `gc._start_time`/`gc._wizard` directly. This tests the on_pick LOGIC without the cmd-coupled insertion path.
- **lowercase `id` in selection expression:** `"obj and id N"` uses lowercase `id` — a PyMOL selector keyword (selecting.py:142). UPPERCASE `ID` is ONLY for iterate expressions (AGENTS.md Pitfall). The cmd.color call correctly uses lowercase.
- **_started stays True after win():** Per 04-RESEARCH Q29, hiders remain in the object after winning; cleanup() removes them when the player is ready. win() only fires the callback + deactivates the wizard.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Recovered from concurrent git collision (parallel agent reset orphaned RED commit)**
- **Found during:** Task 2 (GREEN commit)
- **Issue:** The parallel agent (04-01/04-02) did a `git reset HEAD~1` that orphaned my RED commit `8aec632` (visible in reflog as HEAD@{1}). The test file was on disk (untracked) and game.py was staged with GREEN changes, but the RED commit was no longer in the branch history.
- **Fix:** Verified the test file on disk matched the orphaned commit via `git show 8aec632:tests/test_game_controller.py | diff`. Unstaged game.py, re-committed RED (test only, `d937a5f`), then committed GREEN (game.py only, `9e96b79`). This mirrors the safe-amend-pattern documented in STATE.md from the 03-03 incident.
- **Files modified:** None (recovery only — re-created commits in correct order)
- **Verification:** `git log --oneline` shows RED then GREEN in correct order; 152 tests pass
- **Committed in:** d937a5f (RED re-commit) + 9e96b79 (GREEN)

---

**Total deviations:** 1 auto-fixed (1 blocking — git collision recovery)
**Impact on plan:** No scope creep. The git collision was a concurrency issue with the parallel agent, not a plan deficiency. All planned work completed as specified.

## Issues Encountered
- Concurrent git collision: parallel agent's `git reset` orphaned the RED commit. Recovered via reflog verification + re-commit in correct order. No data loss — the test file on disk was identical to the orphaned commit.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Ready for plan 04-04 (gui_game):** set_callbacks interface is ready — gui_game's GameTab will call `gc.set_callbacks(on_log=self._log, on_remaining_changed=self._update_remaining, on_win=self._on_win)` to wire the UI.
- **Ready for plan 04-05 (__init__ wiring):** gc._wizard is a plain attribute (set to None in __init__); the caller (__init__.py PluginDialog._on_start or GameTab._begin_play) sets `gc._wizard = wiz` after creating the PickWizard, and `gc._start_time = time.time()` after countdown. win() will call `self._wizard.deactivate()` on win.
- **Ready for plan 04-06 (smoke test):** on_pick logic is WSL-verified; the cmd.color call uses lowercase `id` selector (verified correct per selecting.py:142). Headless smoke can simulate picks via `cmd.select("pk1", ...)` + `wizard.do_pick(0)`.
- **No blockers.** game.py imports only pymol.cmd + sibling .backup/.mutation/.registry (no Qt/wizard/gui_game/generators imports). Dependency direction strict.

---
*Phase: 04-mvp-core-loop-sphere*
*Completed: 2026-08-08*
