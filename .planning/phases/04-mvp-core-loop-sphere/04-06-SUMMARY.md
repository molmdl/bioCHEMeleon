---
phase: 04-mvp-core-loop-sphere
plan: 06
subsystem: testing
tags: [headless-smoke, human-verify, phase4-core-loop, pymol-cmd, cmd-exe-runner, do_select-spike, win-loop, QMessageBox, real-gui-verification]

# Dependency graph
requires:
  - phase: 04-mvp-core-loop-sphere
    provides: "The full Phase 4 core loop (04-01..04-05): generators.generate_sphere_positions + GameController.start + PickWizard.do_pick + GameTab countdown/timer/remaining + PluginDialog._on_start BTN-07 wiring — this plan runtime-verifies all of it"
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: "The smoke reuses the Phase 3 headless pattern (smoke/phase3_smoke.py check/RESULTS/summary + cmd.exe /c run-conda-pymol.bat -cq) and the GameController backup/mutation/registry stack under test"
provides:
  - "smoke/phase4_smoke.py (148 lines) — headless Phase 4 smoke: sphere gen + insert+register + show spheres + simulate find (on_pick logic path) + recolor green + remaining decrement + miss + win + cleanup, plus two optional do_pick/do_select spikes"
  - "Runtime verification at BOTH tiers: headless cmd-coupled smoke (19/19 ALL PASSED, automated from WSL) AND human GUI verification (real Windows PyMOL session — all 4 success criteria APPROVED)"
  - "Three GUI bug fixes discovered during human-verify (do_select routing, win-loop three bugs, win-display three bugs) — the core loop now works end-to-end with a real mouse + real Qt event loop"
affects: [04-VERIFICATION.md / 04-SUMMARY.md phase-level handoff (next planning step), Phase 5 (rep extensions re-use the verified _on_start + on_pick + win path), Phase 7 (Cleanup/Restart buttons rely on the now-verified win->cleanup flow)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — pure pymol.cmd.* smoke + existing Qt
  patterns: [headless-smoke-via-cmd-exe-runner (AGENTS.md method: stage to tmp/bioCHEMeleon then cmd.exe /c run-conda-pymol.bat -cq), check/RESULTS/summary smoke pattern (modeled on phase3_smoke.py), do_select-select-path-routing (PickWizard.do_select builds pk1 from sele then dispatches do_pick — canonical measurement-wizard pattern), deferred-wizard-teardown-via-QTimer-singleShot (win display: 100ms gap lets PyMOL render the last green before wizard teardown), top-level-modal-parent-with-WindowStaysOnTopHint (QMessageBox parented to self.window() so the win dialog is visible/on-top), post-win-cleanup-in-_on_win (viewer stays responsive + new game works)]

key-files:
  created:
    - smoke/phase4_smoke.py
  modified:
    - biochemeleon/wizard.py        # do_select routing fix (c68a1a4 — deviation during human-verify)
    - biochemeleon/game.py          # win-loop ordering + _finish_win + cleanup (9ec0c16, 01c48f6 — deviations)
    - biochemeleon/gui_game.py      # _on_win top-level modal + cmd.refresh + _finish_win QTimer (9ec0c16, 01c48f6 — deviations)
    - biochemeleon/__init__.py      # _on_start defensive cleanup of prior controller (9ec0c16 — deviation)
    - tests/test_game_controller.py # test_win_with_wizard updated: win() no longer deactivates wizard (01c48f6 — deviation)

key-decisions:
  - "Headless smoke uses the on_pick LOGIC path (registry lookup + mark_found + cmd.color) not the pick chain — the pick chain needs a real mouse pick; the do_pick/do_select spikes are OPTIONAL and wrapped in try/except so a spike failure never breaks the smoke exit code"
  - "do_select spike added (9c9aeea) mirroring the do_pick spike: cmd.select('sele',...) then wizard.do_select('sele') -> assert marked found. Smoke now 19/19 ALL PASSED (was 18/18); the do_select routing is now headlessly testable, not just human-verified"
  - "Color assertion: assert the post-pick color CHANGED from the pre-pick color (capture orig_cols first) rather than asserting a fixed green index — the green color index varies by build (5387 pre-pick, 3 post-pick in this build; plan said 7 but that's not universal). Robust against PyMOL color-table variation"
  - "1 Rule-1 smoke bug fixed in 83e7804: reordered cleanup before the spike (both games share the global BACKUP_PREFIX name; the plan's spike-then-cleanup ordering clobbered gc's backup via gc2.start/cleanup — cleanup-then-spike runs each game's cleanup on its own fresh backup)"
  - "Human-verify is the definitive gate for Qt/GUI behavior (tab switch, countdown display, ticking timer, real mouse clicks, modal win dialog) — these CANNOT run from WSL per AGENTS.md; the headless smoke only closes the cmd-coupled gap"

patterns-established:
  - "Headless smoke = phase3_smoke.py pattern (check/RESULTS/summary + sys.exit(1)) extended to Phase 4's cmd.show/cmd.color/on_pick/win path — the template for Phase 5+ rep-extension smokes"
  - "do_select routing: selection-mode clicks (default 3-Button Viewing preset creates 'sele' + WizardDoSelect, NOT 'pk1' + WizardDoPick) are routed to do_pick via do_select(name) building pk1 from the selection. Works in any selection button mode without fragile button-mode save/restore"
  - "Win display: deactivate the wizard DEFERRED (100ms QTimer.singleShot -> _finish_win) so PyMOL renders the last green before wizard teardown clobbers the redraw; the modal win QMessageBox is parented to the top-level PluginDialog (self.window()) with WindowStaysOnTopHint so it's visible/on-top"
  - "Post-win cleanup: _on_win calls cleanup() after the modal is dismissed (hiders removed, _started reset, viewer responsive, new game works); _on_start defensively cleans up any prior active controller before creating a new one"

# Metrics
duration: ~75min (across 2 sessions — Task 1 + the human-verify checkpoint with 3 debug iterations)
completed: 2026-08-08
---

# Phase 4 Plan 06: Headless Smoke + Human-Verify Summary

**Phase 4 core loop runtime-verified at both tiers — headless cmd-coupled smoke 19/19 ALL PASSED via cmd.exe runner, and human GUI verification APPROVED (all 4 success criteria pass in real Windows PyMOL with 1znf 3-hider + 4wb3 10-hider rounds) — after 3 GUI bug-fix iterations discovered during the checkpoint (do_select routing, win-loop ordering, win-display top-level modal)**

## Performance

- **Duration:** ~75 min (across 2 sessions: Task 1 headless smoke + the human-verify checkpoint with 3 debug iterations)
- **Started:** 2026-08-08 (Task 1)
- **Completed:** 2026-08-08T06:21Z (Task 2 APPROVED + SUMMARY)
- **Tasks:** 2/2 (1 auto + 1 checkpoint:human-verify)
- **Files modified:** 6 (1 created + 5 modified during debug iterations)

## Accomplishments
- Headless smoke (`smoke/phase4_smoke.py`, 148 lines) verifies the full Phase 4 cmd-coupled path end-to-end: sphere gen (bounds-checked) → insert+register (GameController.start) → show spheres → simulate find via on_pick (mark_found + cmd.color green + callbacks) → remaining decrement → miss (non-hider no-op) → win (all found + on_win float) → cleanup (verify_intact + count-back-to-orig). Run headlessly from WSL: 19/19 ALL PASSED, exit 0.
- Human-verify checkpoint APPROVED: user confirmed all 4 Phase-4 success criteria pass in a real Windows PyMOL GUI session — Start→3-2-1 countdown (C1), click→recolor green + non-hider miss no-op (C2), log+timer+remaining (C3), win→timer stop + modal message with time (C4), plus wizard activation + mouse_selection_mode restore. Tested with 1znf (3 hiders) and 4wb3 (10 hiders); clicks recolor green including the last hider, win dialog appears on top with correct time, viewer stays responsive after, new game works.
- Three GUI bug classes found and fixed during the checkpoint (do_select routing, win-loop ordering, win-display top-level modal) — the core loop now works with a real mouse + real Qt event loop, not just the headless logic path.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write + run headless smoke test** — `83e7804` (test) — 18/18 ALL PASSED; then `9c9aeea` (test) added the do_select spike → 19/19 ALL PASSED. (STATE update for Task 1: `c786e78`.)
2. **Task 2: Human-verify checkpoint** — APPROVED (no code commit — checkpoint resolution). The 3 debug iterations during the checkpoint are listed under Deviations.

**Plan metadata:** this commit (docs: complete plan)

## Files Created/Modified
- `smoke/phase4_smoke.py` — (CREATED, 148 lines) Phase 4 headless smoke: sphere gen + insert/register + show + simulate find + recolor + remaining + miss + win + cleanup, plus optional do_pick/do_select spikes. Pure `pymol.cmd.*` (no Qt) so it runs headlessly via the cmd.exe runner.
- `biochemeleon/wizard.py` — (MODIFIED, deviation c68a1a4) added `do_select(name)` routing selection-mode clicks to do_pick via pk1 (canonical measurement-wizard pattern).
- `biochemeleon/game.py` — (MODIFIED, deviations 9ec0c16 + 01c48f6) win() reordered (deactivation deferred to GUI `_finish_win`); post-win cleanup contract.
- `biochemeleon/gui_game.py` — (MODIFIED, deviations 9ec0c16 + 01c48f6) `_on_win` top-level modal (self.window() + WindowStaysOnTopHint) + cmd.refresh() + `_finish_win` 100ms QTimer.singleShot for deferred wizard teardown; post-win cleanup() call.
- `biochemeleon/__init__.py` — (MODIFIED, deviation 9ec0c16) `_on_start` defensively cleans up any prior active controller before creating a new one.
- `tests/test_game_controller.py` — (MODIFIED, deviation 01c48f6) `test_win_with_wizard` updated: win() no longer deactivates the wizard (deactivation moved to GUI `_finish_win`); `gc._wizard` stays set.

## Decisions Made
- Smoke asserts the color CHANGED (capture pre-pick, assert post-pick differs) rather than a fixed green index — the green index varies by PyMOL build (5387→3 here; plan said 7). Robust against color-table variation.
- do_pick/do_select spikes are OPTIONAL and try/except-guarded — a spike failure logs a deferral and never breaks the smoke exit code (the main checks must all pass; the spikes are informational).
- Human-verify is the definitive gate for all Qt/GUI behavior (cannot run from WSL per AGENTS.md); the headless smoke only closes the cmd-coupled gap.

## Deviations from Plan

Three bug-fix iterations were discovered during the Task-2 human-verify checkpoint. None are part of plan 04-06's tasks (Task 1 = headless smoke, Task 2 = checkpoint); they are GUI bugs in the 04-01..04-05 deliverables that the headless smoke could not catch (the smoke exercises the on_pick LOGIC path and calls do_pick directly — it never routes a real selection-mode click or runs the win DISPLAY path through the Qt event loop). All are Rule 1 (bug) auto-fixes; no architectural changes.

### Auto-fixed Issues

**1. [Rule 1 - Bug] do_pick not firing on real GUI clicks (do_select routing)**
- **Found during:** Task 2 (human-verify — C6 click→recolor failed)
- **Issue:** PickWizard set `mouse_selection_mode=0` but never switched the BUTTON MODE from Selecting to Picking. In the default 3-Button Viewing preset, left-click is `cButModeSeleSet`, so the C layer (SceneMouse.cpp) creates `"sele"` + `WizardDoSelect` — NOT `"pk1"` + `WizardDoPick`. `do_pick` therefore never fired on real GUI clicks; the headless smoke passed only because it called `do_pick` directly.
- **Fix:** Implement `do_select(name)` following the canonical `pymol.wizard.measurement.do_select` pattern — build `pk1` from the just-created selection, clean it up (C layer recreates `"sele"` next click), dispatch through `do_pick(0)`. Reuses existing pick logic; preserves left-drag rotation; works in any selection button mode without fragile button-mode save/restore.
- **Files modified:** `biochemeleon/wizard.py`
- **Verification:** do_select spike added to smoke (`9c9aeea`, 19/19 ALL PASSED); human-verify confirmed real clicks now recolor green.
- **Committed in:** `c68a1a4` (debug session archived in `b15219c`)

**2. [Rule 1 - Bug] three GUI win-loop bugs (win time, last-hider recolor, post-win cleanup)**
- **Found during:** Task 2 (human-verify — win time always 0:00; last hider stayed gray; viewer frozen + new game broken after win)
- **Issue:** (1) `_begin_play` set `_start_time` on the GameTab but `win()` reads the GameController's `_start_time` (init None) → win time always 0:00. (2) `win()` called `_on_win` (modal QMessageBox blocks the Qt event loop) BEFORE deactivating the wizard, so the last `cmd.color('green')` from `on_pick` never flushed → last hider stayed gray. (3) No `cleanup()` ran after a win → hiders stayed in the object, `_started` stayed True, viewer frozen, new game broken.
- **Fix:** (1) `_begin_play` also sets `self._controller._start_time`. (2) Reordered `win()` to deactivate FIRST, then `_on_win`; added `cmd.refresh()` + `processEvents()` in `_on_win` before the modal. (3) `_on_win` calls `cleanup()` after the modal is dismissed; `_on_start` defensively cleans up any prior active controller before creating a new one.
- **Files modified:** `biochemeleon/__init__.py`, `biochemeleon/game.py`, `biochemeleon/gui_game.py`
- **Verification:** human-verify confirmed win time correct, last hider green, viewer responsive, new game works.
- **Committed in:** `9ec0c16` (debug session `phase4-win-loop-three-bugs.md`)

**3. [Rule 1 - Bug] three win-DISPLAY bugs (last-hider color, dialog on-top, viewer unfreeze)**
- **Found during:** Task 2 (human-verify — iteration 2: the win-loop fix's `cmd.refresh()` + `processEvents()` did not work in real GUI)
- **Issue:** (A) `win()` deactivated the wizard BEFORE `_on_win`, so the wizard-teardown `WizardRefresh` clobbered the pending `cmd.color('green')` redraw → last hider still gray. (B) `QMessageBox.information(self, ...)` used the GameTab (not top-level) as parent → win dialog hidden behind the PyMOL window. (C) Viewer frozen — consequence of (B) (hidden modal blocked the event loop).
- **Fix:** (A) Remove deactivation from `win()`; defer it to a new `_finish_win` callback triggered 100 ms later via `QTimer.singleShot` — the 100 ms gap lets PyMOL render the green before wizard teardown. `cmd.refresh()` called in `_on_win` (wizard still active, no interference). (B) Create a `QMessageBox` instance with `self.window()` (top-level PluginDialog) as parent + `WindowStaysOnTopHint`, then `exec_()`. (C) Fixed by (B) + delayed deactivation. Test `test_win_with_wizard` updated to assert `win()` does NOT deactivate the wizard (deactivation moved to GUI `_finish_win`).
- **Files modified:** `biochemeleon/game.py`, `biochemeleon/gui_game.py`, `tests/test_game_controller.py`
- **Verification:** human-verify APPROVED — last hider green, win dialog on top with correct time, viewer responsive after, new game works (tested 1znf 3-hider + 4wb3 10-hider rounds).
- **Committed in:** `01c48f6` (debug session archived in `6c5e521`)

---

**Total deviations:** 3 auto-fixed (3 Rule 1 - Bug)
**Impact on plan:** All three are GUI bugs in the 04-01..04-05 deliverables that the headless smoke structurally cannot catch (it exercises the on_pick logic path and calls do_pick directly; it never routes a real selection-mode click or runs the win display path through the Qt event loop). All necessary for the core loop to work with a real mouse + real Qt. No scope creep — no new features, only correctness fixes to already-planned behavior. WSL gates stayed green throughout (py_compile + 160 unit tests + pitfall-1=0; `exec_` gate = 1 on the allowed `QMessageBox.exec_()` child dialog per AGENTS.md).

## Issues Encountered
- The do_select routing bug (deviation 1) was masked by the headless smoke: the smoke calls `do_pick(0)` directly, so it passed 18/18 (then 19/19 with the do_select spike) headlessly while real GUI clicks silently did nothing. This is the inherent limitation of headless verification for pick-chain routing — the human-verify checkpoint is what caught it. Lesson for Phase 5+: the do_select spike now closes this gap headlessly, but real-click routing still warrants a human check when button-mode logic changes.

## Authentication Gates
None — no external authentication required.

## User Setup Required
None — no external service configuration required. (Running the plugin still requires the Windows conda env `chemtools-win10` via `setenv.bat` → `pymol`, but that is the existing dev environment, not a per-plan setup.)

## Next Phase Readiness
- Phase 4 core loop is runtime-verified at BOTH tiers (headless smoke 19/19 + human-verify APPROVED). All 8 Phase-4 requirements (LOOP-01/02/03, HIDER-04, BTN-07, GAME-01/02/03) are satisfied and the 4 ROADMAP success criteria are met.
- **Phase 4 is NOT marked fully complete by this plan** — the orchestrator will run the phase-level verifier next (04-VERIFICATION.md / 04-SUMMARY.md handoff is a later planning step, per the plan's success_criteria).
- Phase 5 (rep extensions) can re-use the now-verified `_on_start` + `on_pick` + `win` path; the do_select routing + win-display fixes carry forward.
- Phase 7 (Cleanup/Restart buttons) can rely on the now-verified win→cleanup flow (`_on_win` calls `cleanup()`; `_on_start` defensively cleans up a prior controller).

---
*Phase: 04-mvp-core-loop-sphere*
*Completed: 2026-08-08*
