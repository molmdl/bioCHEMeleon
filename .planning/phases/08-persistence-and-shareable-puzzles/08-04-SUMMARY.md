---
phase: 08-persistence-and-shareable-puzzles
plan: 04
subsystem: ui
tags: [gui, qt, export, import, save, checkpoint, puzzle, timer-resume, restart, cleanup, bcmz, wiring]

# Dependency graph
requires:
  - phase: 08-01
    provides: HiderRegistry.reconcile_with_bcm (apply_bcm_dict calls it in _on_restart_imported)
  - phase: 08-02
    provides: build_bcm_dict + parse_bcm_dict + BCM_MAGIC + BCM_VERSION (build_bcm_dict called by _on_export + _on_save)
  - phase: 08-03
    provides: apply_bcm_dict + write_bcmz + read_bcmz + resolve_target + GameController.import_state + _is_imported/_imported_bcm (all called by the 4 new GUI handlers)
  - phase: 07-found-hider-management-restart-cleanup
    provides: _on_restart + _on_cleanup + wizard-lifecycle teardown pattern (extended, not replaced)
  - phase: 04-mvp-core-loop
    provides: _on_start (refactored into _prepare_and_start + thin wrapper)
affects: [08-05, 09-large-demo-fetch, 10-polish-endgame-help]

# Tech tracking
tech-stack:
  added: []  # stdlib tempfile + os only (already available)
  patterns:
    - "Behavior-preserving refactor: _prepare_and_start extracts _on_start steps 1-4 (resolve target, collapse, build hider_specs, free valences, clean prior game, GameController + start) into a shared helper returning (controller, target_obj, _gen_warnings) or (None, None, []). _on_start + _on_export both call it — eliminates ~160 lines of duplication (research §2.4)."
    - "Pause-capture-dialog-save-resume timer pattern (PITFALLS.md): _on_save stops the timer + captures elapsed BEFORE the modal file dialog, then rebases _start_time = time.time() - elapsed after the dialog so the dialog+save time is NOT counted. Also applied on cancel + on save-failure (rebase + resume in all 3 exit paths)."
    - "Refuse-first collision defense (Discrepancy 1): _on_import checks if bcm_dict['target_object'] is already loaded BEFORE cmd.load(pse_path, partial=1) — defends against the unverified C-level collision. cmd.load(partial=1) MERGES the .pse into the session (preserves the player's scene)."
    - "_is_imported flag routing: _on_restart checks getattr(controller, '_is_imported', False) -> _on_restart_imported (restore + re-reconcile, NO re-generation) OR _on_start (re-generate from Setup). _on_cleanup checks the same flag -> two-step (backup.restore + mutation.cleanup_hiders) OR existing c.cleanup()."
    - "Timer resume guard in _begin_play: if self._controller._start_time is None: self._controller._start_time = self._start_time — prevents clobbering a resumed timer set by import_state for checkpoint import. _saved_elapsed is consumed (self._start_time = time.time() - elapsed) then reset to 0.0."

key-files:
  created: []
  modified:
    - biochemeleon/gui_setup.py
    - biochemeleon/gui_game.py
    - biochemeleon/__init__.py

key-decisions:
  - "_prepare_and_start is a behavior-preserving refactor of _on_start. Start still works unchanged — verified by py_compile + existing tests (the Plan 05 smoke + human-verify will confirm runtime behavior). The refactor returns (controller, target_obj, _gen_warnings) so _on_export can reuse the prepare path without the tab switch + countdown."
  - "_on_export stays on Setup tab after export (does NOT switch to Game tab). The educator's model keeps the generated hiders (press Cleanup to restore the scene). On cancel, controller.cleanup() removes the generated hiders so they don't linger."
  - "_on_save captures elapsed BEFORE the file dialog (PITFALLS.md timer pitfall). The timer is stopped, elapsed = time.time() - _start_time, then the dialog runs. After the dialog (cancel, success, or failure), _start_time is rebased to time.time() - elapsed so the dialog+save time is NOT counted. The timer resumes in all 3 exit paths."
  - "_on_import uses cmd.load(pse_path, partial=1) MERGE (Discrepancy 1 resolution) with refuse-first collision detection. resolve_target's before/after diff fallback handles any rename-on-collision. The imported controller's _is_imported flag routes Restart + Cleanup to the imported-game paths."
  - "_on_restart_imported restores from the post-import backup (re-hides all hiders, resets found-status, clears hint colors), re-reconciles rep from _imported_bcm (rep is lost on restore — sentinels carry no rep), resets counters, takes a FRESH backup.snapshot (so the NEXT Restart/Cleanup restores to the same imported initial state), restarts countdown. NO re-generation."
  - "_on_cleanup two-step for imported games: backup.restore (fixes hint-orange real atoms) THEN mutation.cleanup_hiders (removes the restored hiders). For non-imported games, the existing c.cleanup() path (backup is pre-game, restore removes hiders). Both paths reset UI labels + release _controller=None."
  - "Atomic commits per task (3 commits: 5118bcb + 199b54a + f2adbee) instead of the plan's combined-commit instruction (Task 3 step 8 said to commit all 3 files together). Followed the task_commit_protocol (commit immediately after each task's verification passes) — better bisect granularity, end state identical."

patterns-established:
  - "_prepare_and_start shared prepare helper: the canonical way to resolve target + build hider_specs + start a game. _on_start (fresh game) and _on_export (puzzle generation) both call it. Future handlers that need to prepare a game WITHOUT the tab switch + countdown should reuse it."
  - "Refuse-first collision pattern for import: check if the .bcm's target_object is already loaded BEFORE cmd.load(partial=1). This defends against the unverified C-level collision (Discrepancy 1) and gives the user a clear message (rename or delete the existing object)."
  - "Timer pause-capture-resume pattern: any GUI handler that shows a modal dialog during a running game MUST stop the timer + capture elapsed BEFORE the dialog, then rebase _start_time after. Applied in _on_save (3 exit paths: cancel, success, failure). Future handlers that pause the game for a modal dialog should follow this."

# Metrics
duration: 7min
completed: 2026-08-12
---

# Phase 8 Plan 04: GUI Wiring — Export/Import/Save + Timer Resume + Restart/Cleanup-on-imported Summary

**3 new GUI handlers (_on_export BTN-05, _on_import GAME-04, _on_save GAME-09) wired to buttons + _prepare_and_start behavior-preserving refactor of _on_start + timer-resume fix in _begin_play + _is_imported flag routing for Restart/Cleanup-on-imported**

## Performance

- **Duration:** 7 min
- **Started:** 2026-08-11T23:12:57Z
- **Completed:** 2026-08-11T23:20:18Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- 3 Phase 8 buttons wired: export_btn (Generate & export, Setup tab, between Load Setup and Cleanup model — spec order) + begin_row (Import puzzle… + Save checkpoint, Game tab, above the existing btn_row). All 3 connect to their handlers in PluginDialog.__init__.
- _prepare_and_start refactor: extracted _on_start steps 1-4 (resolve target, collapse, build hider_specs, free valences, clean prior game, GameController + start) into a shared helper returning (controller, target_obj, _gen_warnings) or (None, None, []). _on_start is now a 6-line thin wrapper. _on_export reuses the prepare path without ~160 lines of duplication. Behavior-preserving (Start works unchanged — verified by py_compile + tests; runtime deferred to Plan 05).
- _on_export (BTN-05): _prepare_and_start + QFileDialog.getSaveFileName + build_bcm_dict(kind='puzzle') + cmd.save(pse_path, target_obj) + write_bcmz + stays on Setup. On cancel, controller.cleanup() removes generated hiders. On failure, QMessageBox.warning. On success, QMessageBox.information telling the user to press Cleanup.
- _on_save (GAME-09): pause-capture-dialog-save-resume pattern (PITFALLS.md timer pitfall). Stops timer + captures elapsed BEFORE the dialog, then rebases _start_time = time.time() - elapsed in all 3 exit paths (cancel, success, failure). build_bcm_dict(kind='checkpoint', elapsed) + cmd.save + write_bcmz. Logs "Saved checkpoint to <path>".
- _on_import (GAME-04): QFileDialog.getOpenFileName + read_bcmz + refuse-first collision check (Discrepancy 1) + cmd.load(pse_path, partial=1) MERGE + resolve_target + GameController.import_state + switch to Game tab + start_countdown(elapsed). NO re-generation.
- _on_restart routes on _is_imported: imported -> _on_restart_imported (restore + re-reconcile rep from _imported_bcm + reset counters + fresh backup.snapshot + start_countdown, NO re-generation); non-imported -> _on_start (re-generate from Setup).
- _on_cleanup two-step for imported: backup.restore + discard + mutation.cleanup_hiders (restore fixes hint-orange real atoms, then remove hiders). Non-imported: existing c.cleanup(). Both reset UI labels + release _controller=None.
- Timer resume fix in gui_game.py: start_countdown accepts elapsed=0 (backward-compatible), seeds _reveal_label from controller._reveal_count, shows resumed timer during countdown. _begin_play resumes from _saved_elapsed with guard `if self._controller._start_time is None` so checkpoint import does NOT clobber a resumed timer.

## Task Commits

Each task was committed atomically (3 commits — the plan's Task 3 combined-commit instruction was superseded by the atomic-commit-per-task protocol for better bisect granularity):

1. **Task 1: export_btn + begin_row + start_countdown(elapsed) + _begin_play resume fix** - `5118bcb` (feat)
2. **Task 2: _prepare_and_start refactor + _on_export + _on_save + button wiring** - `199b54a` (refactor)
3. **Task 3: _on_import + _on_restart_imported + modified _on_restart + modified _on_cleanup** - `f2adbee` (feat)

**Plan metadata:** (pending — created after this summary)

## Files Created/Modified
- `biochemeleon/gui_setup.py` — export_btn (Generate & export) QPushButton added between load_btn and cleanup_btn (spec order) with tooltip; included in the button row for-loop (588 → 600 lines, +12)
- `biochemeleon/gui_game.py` — begin_row QHBoxLayout (_import_btn + _save_btn) added ABOVE btn_row; start_countdown accepts elapsed=0 + seeds _reveal_label from controller._reveal_count + shows resumed timer; _begin_play resumes from _saved_elapsed with guard `if _controller._start_time is None` (275 → 307 lines, +32)
- `biochemeleon/__init__.py` — _on_start refactored into thin wrapper + _prepare_and_start helper; _on_export (BTN-05); _on_save (GAME-09); _on_import (GAME-04); _on_restart routes on _is_imported; _on_restart_imported; _on_cleanup two-step for imported; 3 button wirings in __init__ (286 → 512 lines, +226)

## Decisions Made
- _prepare_and_start is a behavior-preserving refactor of _on_start. Start still works unchanged — the refactor returns (controller, target_obj, _gen_warnings) so _on_export can reuse the prepare path without the tab switch + countdown.
- _on_export stays on Setup tab after export. The educator's model keeps the generated hiders (press Cleanup to restore). On cancel, controller.cleanup() removes the generated hiders so they don't linger.
- _on_save captures elapsed BEFORE the file dialog (PITFALLS.md timer pitfall). _start_time is rebased to time.time() - elapsed in all 3 exit paths (cancel, success, failure) so the dialog+save time is NOT counted.
- _on_import uses cmd.load(pse_path, partial=1) MERGE (Discrepancy 1 resolution) with refuse-first collision detection. The imported controller's _is_imported flag routes Restart + Cleanup to the imported-game paths.
- _on_restart_imported restores from the post-import backup, re-reconciles rep from _imported_bcm (rep is lost on restore), resets counters, takes a FRESH backup.snapshot, restarts countdown. NO re-generation.
- _on_cleanup two-step for imported games (backup.restore + mutation.cleanup_hiders); existing c.cleanup() for non-imported. Both reset UI + release _controller=None.
- Atomic commits per task (3 commits) instead of the plan's combined-commit instruction — better bisect granularity, end state identical.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded _on_export comment to avoid literal `.exec_()` token tripping the exec_ grep gate**
- **Found during:** Task 2 (adding _on_export)
- **Issue:** The _on_export comment "NOT .exec_() from our code" contained the literal `.exec_()` string, tripping the exec_ grep gate (returned 2 instead of the expected 1 — the existing _finish_win QMessageBox.exec_()). AGENTS.md warns about this false-positive pattern (a docstring that said "from PyQt5 import" tripped the gate before).
- **Fix:** Reworded to "NOT the exec_ modal call from our code" — the comment still explains the modeless-main rule but avoids the literal `.exec_()` token. Mirrors the 03-02/03-06/03-09/03-10/07-02 precedent.
- **Files modified:** biochemeleon/__init__.py (1 comment line)
- **Verification:** exec_ grep gate back to 1 (the existing _finish_win only); py_compile clean
- **Committed in:** 199b54a (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — grep gate false positive)
**Impact on plan:** Auto-fix necessary for the exec_ gate to stay green (acceptance contract). No scope creep. End state matches plan intent (3 handlers + refactor + wiring, all gates green).

## Issues Encountered
None — all 3 tasks executed cleanly. py_compile + 219 tests pass on every task. No debugging iterations needed. The _prepare_and_start refactor was behavior-preserving on the first pass (all existing tests pass; runtime behavior deferred to Plan 05).

## User Setup Required
None — no external service configuration required. All work is Qt GUI wiring + stdlib tempfile/os (already available). The GUI behavior (button clicks, dialog flow, timer resume) is deferred to the Plan 05 human-verify checkpoint.

## Next Phase Readiness
- **Ready for 08-05-PLAN.md (headless smoke + human-verify):** all 3 GUI handlers (_on_export, _on_import, _on_save) + _prepare_and_start refactor + _on_restart_imported + _on_cleanup two-step are implemented + py_compile clean + 219 tests pass. The headless smoke can exercise persistence.build_bcm_dict + write_bcmz/read_bcmz + GameController.import_state directly (no GUI) to verify the export/import round-trip. The human-verify checkpoint confirms the GUI button flow (export -> import -> play; save -> reload -> resume; restart-on-imported; cleanup-on-imported).
- **No blockers.** The _prepare_and_start refactor is behavior-preserving (Start works unchanged). The _is_imported flag routing is in place. The timer-resume fix is guarded against clobbering. All Pitfall gates green (Pitfall-1=0, exec_=1 unchanged, no PyQt5).
- **Discrepancy 1 implemented:** cmd.load(pse_path, partial=1) MERGE + refuse-first collision check in _on_import. resolve_target's before/after diff fallback handles any rename-on-collision.
- **Qt+cmd-coupled — runtime deferred to Plan 05:** the GUI button flow (file dialog, tab switch, timer resume display, countdown with elapsed) is WSL-unverifiable (no PyMOL GUI in WSL). Plan 05's headless smoke exercises the cmd-layer round-trip; the human-verify confirms the GUI flow.

---
*Phase: 08-persistence-and-shareable-puzzles*
*Completed: 2026-08-12*
