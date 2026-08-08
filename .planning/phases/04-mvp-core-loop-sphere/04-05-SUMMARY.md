---
phase: 04-mvp-core-loop-sphere
plan: 05
subsystem: integration
tags: [qt, pymol-qt, btn-07, start-button, plugin-dialog, on-start, generate-sphere-positions, gamecontroller-start, tab-switch, countdown-wiring, QMessageBox-warning, fan-in]

# Dependency graph
requires:
  - phase: 04-mvp-core-loop-sphere
    provides: "generators.generate_sphere_positions (04-01 — pure sphere gen called in _on_start); GameController.start(hider_specs) UNCHANGED (04-03 — snapshot->insert->register); GameTab.start_countdown(controller) (04-04 — 3-2-1 countdown + _begin_play); PickWizard (04-02 — activated by GameTab._begin_play)"
  - phase: 02-setup-tab-config-bundled-demos
    provides: "demos.fetch_pdb/load_demo/list_loaded_molecule_objects (02-03 — target resolution); SetupTab.collect_state() + Setup actions QGroupBox (02-03/02-07 — Start button joins Reset/Randomize/Save/Load)"
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: "PluginDialog (__init__.py owns tabs/setup_tab/game_tab; this plan extends it with _on_start + _controller + start_btn wiring)"
provides:
  - "PluginDialog._on_start — full BTN-07 flow (resolve target -> generate sphere positions -> GameController.start -> show spheres -> switch tab -> start_countdown)"
  - "SetupTab.start_btn — bold Start QPushButton in Setup actions group (BTN-07), connected to PluginDialog._on_start"
  - "PluginDialog._controller — holds the active GameController across the round (so Phase 7 cleanup/restart can reach it)"
  - "QMessageBox.warning abort paths on every target-resolution failure (no object / fetch failed / demo failed / unknown mode / double-start RuntimeError) — no partial game state"
affects: [04-06 (headless smoke + human-verify of the 4 success criteria — the loop is now runnable), Phase 5 (line/stick/cartoon reps added to hider_specs in _on_start; generate_sphere_positions -> generate_*_positions), Phase 7 (Cleanup/Restart buttons use self._controller.cleanup()/abort_on_error()), Phase 8 (Save/Import wire into _on_start flow)]

# Tech tracking
tech-stack:
  added: []  # no new libraries (from pymol import cmd is std for cmd-coupled modules; QtWidgets.QMessageBox via pymol.Qt already imported)
  patterns: [lazy-import-in-method (generators/game/demos imported inside _on_start not at module load), signal-connection (start_btn.clicked.connect(self._on_start)), QMessageBox-warning-on-failure-abort (no partial game state), sentinel-selector-show (cmd.show spheres "%s and segi GAME"), fan-in-wiring (PluginDialog is the composition root tying 04-01..04-04 together)]

key-files:
  created: []
  modified:
    - biochemeleon/gui_setup.py
    - biochemeleon/__init__.py

key-decisions:
  - "Lazy import generators/game/demos INSIDE _on_start (not at module load) — avoids circular imports + module-load cost; only needed when Start is pressed (mirrors 04-04 lazy PickWizard pattern)"
  - "hider_specs = [(pos, 'spheres') for pos in positions] — the ONLY rep in Phase 4 (HIDER-04 sphere hiders; 04-RESEARCH.md E Q19); Phase 5 adds line/stick/cartoon reps"
  - "QMessageBox.warning on EVERY target-resolution failure path (no object / fetch failed / demo failed / unknown mode) — abort with no partial game state (BTN-07 contract)"
  - "Catch RuntimeError from GameController.start (double-start guard from Phase 3) — warn via QMessageBox instead of crashing the dialog"
  - "cmd.show('spheres', '%s and segi GAME') reveals hiders (mutation.insert_hider uses elem='PS' which renders as spheres; 04-RESEARCH.md C Q15) — lowercase segi in selector expression per AGENTS.md"
  - "self._controller held on PluginDialog across the round so Phase 7 cleanup/restart can reach it later (Phase 4 only needs it to stay referenced)"
  - "Main plugin dialog stays modeless (.show(), NEVER .exec_()); QMessageBox.warning is a static helper (no explicit .exec_() call in our code per AGENTS.md)"
  - "2 atomic commits (e866c2e gui_setup.py + 226741d __init__.py) instead of 1 combined commit (minor process deviation from plan Task 3's 'commit both files together' — better bisect granularity, end state identical)"

patterns-established:
  - "Fan-in composition root: PluginDialog._on_start is the single point that ties together generators (04-01) + wizard (04-02) + GameController (04-03) + GameTab (04-04) — the four Phase 4 success criteria are now reachable through this one method"
  - "Lazy sibling import inside _on_start: `from . import generators, game, demos` keeps __init__.py module load cheap + avoids pulling cmd-coupled siblings until a game actually starts (mirrors 04-04 lazy PickWizard pattern)"
  - "Abort-on-failure with QMessageBox.warning: every target-resolution branch returns early on failure with a modal warning — no partial game state leaks into the controller/GameTab"

# Metrics
duration: 3min
completed: 2026-08-08
---

# Phase 4 Plan 05: Wire Start Button -> _on_start (BTN-07 Core Loop Fan-In) Summary

**PluginDialog._on_start ties together generators (04-01) + GameController.start (04-03) + GameTab.start_countdown (04-04) via a bold Start button in Setup actions — resolve target (loaded/fetch/demo, QMessageBox.warning on failure) -> generate sphere positions -> start game -> show hiders as spheres -> switch to Game tab -> 3-2-1 countdown, with the active GameController held as self._controller for Phase 7 cleanup/restart**

## Performance

- **Duration:** 3 min (190 sec)
- **Started:** 2026-08-08T04:47:21Z
- **Completed:** 2026-08-08T04:50:31Z
- **Tasks:** 3 (Start button in gui_setup.py, _on_start + wiring in __init__.py, integration gate sweep)
- **Files modified:** 2 (biochemeleon/gui_setup.py, biochemeleon/__init__.py)

## Accomplishments
- Added a bold "Start" QPushButton to the Setup actions QGroupBox (gui_setup.py), placed last in the Reset/Randomize/Save/Load row, exposed as self.start_btn — BTN-07 now visible in the Setup tab
- Implemented PluginDialog._on_start in __init__.py — the full BTN-07 flow: collect_state -> resolve target (loaded/fetch/demo) -> cmd.get_extent -> generators.generate_sphere_positions -> hider_specs [(pos,'spheres')] -> GameController.start (UNCHANGED Phase 3 proven) -> cmd.show spheres segi GAME -> tabs.setCurrentWidget(game_tab) -> game_tab.start_countdown(controller)
- QMessageBox.warning abort on every target-resolution failure (no object / fetch failed / demo failed / unknown mode) + RuntimeError catch on double-start — no partial game state
- Wired start_btn.clicked -> self._on_start; held active controller as self._controller across the round (Phase 7 cleanup/restart hook)
- Closed the full core loop chain: _on_start -> GameController.start -> GameTab.start_countdown -> _begin_play (PickWizard + set_callbacks) -> PickWizard.do_pick -> GameController.on_pick -> mark_found + cmd.color + callbacks -> win -> _on_win (stop timer + QMessageBox.information)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Start button to gui_setup.py Setup actions** - `e866c2e` (feat)
2. **Task 2: Add PluginDialog._on_start + connect start_btn in __init__.py** - `226741d` (feat)
3. **Task 3: Commit + integration gate sweep** - no separate commit (see Deviations)

**Plan metadata:** (pending — see final commit below)

## Files Created/Modified
- `biochemeleon/gui_setup.py` — added bold Start QPushButton to Setup actions QGroupBox (BTN-07), placed last in the row tuple, not yet connected here (wired in __init__.py); updated BTN-01..04 comment to BTN-01..04 + BTN-07
- `biochemeleon/__init__.py` — added `from pymol import cmd` (module level); added `self._controller = None` instance attr; added `self.setup_tab.start_btn.clicked.connect(self._on_start)` wiring; added `_on_start(self)` method (lazy import generators/game/demos, resolve target, generate sphere positions, GameController.start, cmd.show spheres, setCurrentWidget, start_countdown) with QMessageBox.warning abort paths + RuntimeError catch (66 -> 122 lines)

## Decisions Made
- Lazy import generators/game/demos INSIDE _on_start (mirrors 04-04 lazy PickWizard pattern — avoids circular imports + module-load cost)
- hider_specs = [(pos, "spheres") for pos in positions] — only rep in Phase 4 (Phase 5 adds line/stick/cartoon)
- QMessageBox.warning on every target-resolution failure path — abort with no partial game state
- Catch RuntimeError from GameController.start (Phase 3 double-start guard) — warn instead of crashing the dialog
- cmd.show("spheres", "%s and segi GAME") reveals hiders (lowercase segi in selector per AGENTS.md)
- 2 atomic commits instead of 1 combined (better bisect granularity — minor process deviation from plan Task 3)

## Deviations from Plan

### Process Deviation (minor — not a code/correctness issue)

**1. [Process] 2 atomic commits instead of 1 combined commit**
- **Found during:** Task 3 (commit + integration gate sweep)
- **Issue:** Plan Task 3 specified committing both files together in one commit (`git add biochemeleon/__init__.py biochemeleon/gui_setup.py && git commit -m "feat(04-05): wire Start button -> _on_start (BTN-07 core loop wiring)"`). The executor's task-commit-protocol guidance says to commit after each task completes.
- **Resolution:** Committed Task 1 (gui_setup.py) and Task 2 (__init__.py) as 2 separate atomic commits (e866c2e + 226741d), then verified in Task 3 that both files are committed and all gates pass. No third/redundant empty commit was made.
- **Files modified:** none (process-only)
- **Verification:** `git log --oneline -4` shows both feat(04-05) commits; `git status --short` clean; all WSL gates green
- **Impact:** End state identical to plan intent (both files committed, gates pass). The 2 atomic commits provide BETTER bisect granularity (each task independently revertable; git blame traces lines to specific task context) — a stated system-prompt benefit. No scope creep.

---

**Total deviations:** 1 process deviation (no code/correctness deviations)
**Impact on plan:** None — plan executed exactly as written for all code changes. The process deviation produces equivalent (arguably better) git history. No scope creep.

## Issues Encountered
None — plan executed cleanly. All WSL gates green on first pass (py_compile + 160 tests + exec_=0 package-wide + Pitfall-1=0 package-wide). The Qt+cmd-coupled _on_start cannot be runtime-tested in WSL (no real PyMOL/Qt) — deferred to plan 04-06 (headless smoke + human-verify of the 4 success criteria).

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- **Ready for 04-06:** The full core loop is now WIRED and runnable: Start -> backup -> generate spheres -> insert -> show -> switch tab -> countdown -> activate wizard -> start timer -> click -> on_pick -> mark_found + recolor + remaining -> win -> stop timer + QMessageBox.information. Plan 04-06 will run the headless smoke test (sphere gen + insertion + simulate find + cleanup via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`) and the human-verify checkpoint (play a complete round in Windows PyMOL to confirm all 4 Phase 4 success criteria).
- **No blockers.** The chain is internally consistent (verified read-only in Task 3): the controller passed to game_tab.start_countdown is the same object that GameTab._begin_play sets _wizard on and registers callbacks against; PickWizard.do_pick calls controller.on_pick(aid); GameController.on_pick reads the registry and fires the callbacks back to GameTab.
- **Runtime behavior deferred to 04-06:** _on_start is Qt+cmd-coupled (uses QtWidgets.QMessageBox, cmd.get_extent, cmd.show, QTabWidget.setCurrentWidget) — WSL can only verify syntax (py_compile) + regression (unit tests) + grep gates. Real Start-button behavior (target resolution, sphere generation, tab switch, countdown kickoff) requires a real PyMOL session.

---
*Phase: 04-mvp-core-loop-sphere*
*Completed: 2026-08-08*
