---
phase: 07-found-hider-management-restart-cleanup
plan: 01
subsystem: testing
tags: [tdd, registry, pure-helpers, pymol-selection, color-parameterization]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: HiderRegistry + HiderRecord + HIDER_STATUS_FOUND constant (registry.py pure layer)
  - phase: 06-hint-reveal
    provides: GameController._mark_found helper (hardcoded 'green'; this plan parameterizes it)
provides:
  - "build_found_selection(records, object_name) pure helper — builds 'obj and id X+Y+Z' selection for FOUND hiders"
  - "group_found_by_rep(records) pure helper — builds {rep: [ids]} dict for FOUND hiders (skips rep=None)"
  - "GameController._found_color attribute (default 'green') + _mark_found parameterized to use self._found_color"
  - "13 new unit tests (11 TestFoundSelectionHelpers + 2 _found_color threading) — WSL-verified"
affects: [07-found-hider-management-restart-cleanup (Plan 02 GUI wiring), 08-persistence-shareable-puzzles (.bcm sidecar may reference found-selection helpers)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — pure stdlib helpers + parameterization
  patterns:
    - "Pure module-level helper functions in registry.py (NOT HiderRegistry methods) — filter-by-status + selection-string building, WSL-testable"
    - "Default-preserving parameterization: _found_color='green' default keeps legacy behavior; override path (DIFF-04) is a simple attribute assignment"

key-files:
  created: []  # no new files — TDD extended existing files
  modified:
    - biochemeleon/registry.py
    - biochemeleon/game.py
    - tests/test_registry.py
    - tests/test_game_controller.py

key-decisions:
  - "build_found_selection + group_found_by_rep are MODULE-LEVEL functions (NOT HiderRegistry methods) — they take a list of records (typically registry.all()) and return a selection string / dict; placed AFTER the HiderRegistry class in a new '# Phase 7 found-hider selection helpers' section. This mirrors the pure-function style and keeps HiderRegistry focused on CRUD/queries/status/serialization."
  - "build_found_selection returns None (not an empty string) when no found records exist — signals 'no found hiders' so the GUI dropdown caller can early-return without issuing a malformed selection. PyMOL's `id` selector accepts `id 1+2+3` form; ids joined with '+'."
  - "group_found_by_rep skips rep=None records (post-.pse reload reconstruction case — sentinel carries no rep); Phase 8 .bcm sidecar reconciles rep. Same rep=None tolerance pattern as counts_by_rep (03-10)."
  - "_found_color default 'green' preserves the legacy _mark_found behavior so existing tests asserting cmd.color('green', ...) pass UNCHANGED — the parameterization is backward-compatible. DIFF-04 override is a simple attribute assignment (gc._found_color = 'cyan' / 'found_highlight')."

patterns-established:
  - "Pattern: pure module-level helpers after the class in registry.py — selection-string + dict builders that filter registry records by status, WSL-testable (no cmd, no Qt)"
  - "Pattern: default-preserving parameterization — new attribute defaults to the legacy hardcoded value so existing tests pass unchanged; override is a simple assignment"

# Metrics
duration: 6min
completed: 2026-08-11
---

# Phase 7 Plan 1: Found-Hider Selection Helpers + _found_color Threading Summary

**Two pure registry helpers (build_found_selection + group_found_by_rep) + _mark_found color parameterization — WSL-TDD foundation for Phase 7's GUI dropdown (GAME-08) and color picker (DIFF-04)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-08-10T23:34:08Z
- **Completed:** 2026-08-10T23:40:25Z
- **Tasks:** 3 (RED, GREEN, REFACTOR+gates)
- **Files modified:** 4

## Accomplishments
- **build_found_selection** (registry.py, module-level): builds `"<obj> and id X+Y+Z"` selection string for FOUND hiders; returns `None` when no found records. Pure (no cmd, no Qt). Used by GAME-08 dropdown hide/recolor modes.
- **group_found_by_rep** (registry.py, module-level): builds `{rep: [ids]}` dict for FOUND hiders with `rep is not None`; skips rep=None (post-.pse reload case). Pure. Used by GAME-08 dropdown show mode (per-rep cmd.show so each found hider re-shows in its ORIGINAL rep).
- **_found_color threading** (game.py): new `self._found_color = 'green'` attribute in GameController.__init__ (default preserves legacy); `_mark_found` uses `self._found_color` instead of hardcoded `'green'`. Enables DIFF-04 (player-chosen highlight color via QColorDialog → cmd.set_color + assignment).
- **13 new unit tests** (11 TestFoundSelectionHelpers in test_registry.py + 2 _found_color tests in test_game_controller.py) — all WSL-verified. Existing 187 tests pass UNCHANGED (default 'green' preserves behavior).
- **All WSL gates green**: py_compile all modules + 200 tests pass (187 existing + 13 new) + Pitfall-1=0 + exec_=1 (existing gui_game.py msg.exec_() only) + registry.py purity=0 (no `from pymol`).

## Task Commits

Each TDD phase was committed atomically:

1. **Task 1 (RED): Failing tests for pure helpers + _found_color threading** - `ba09ab2` (test)
2. **Task 2 (GREEN): Implement pure helpers + _found_color threading** - `4780db0` (feat)
3. **Task 3 (REFACTOR + gates): No refactor needed (clean on first pass); full WSL gate suite green** - no commit (gates-only)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified
- `biochemeleon/registry.py` - Added `build_found_selection` + `group_found_by_rep` module-level functions (after HiderRegistry class, new "Phase 7 found-hider selection helpers" section). Both pure (no cmd, no Qt); use HIDER_STATUS_FOUND constant. 272→313 lines.
- `biochemeleon/game.py` - Added `self._found_color = 'green'` to __init__ (default preserves legacy); changed `_mark_found` from `cmd.color('green', ...)` to `cmd.color(self._found_color, ...)`. 271→277 lines.
- `tests/test_registry.py` - Added TestFoundSelectionHelpers class (11 tests: 5 for build_found_selection + 6 for group_found_by_rep); updated import to include build_found_selection + group_found_by_rep. 579→683 lines.
- `tests/test_game_controller.py` - Added 2 tests to TestGameControllerHintReveal: test_found_color_default_green + test_found_color_threading. 486→517 lines.

## Decisions Made
- **Module-level functions, NOT HiderRegistry methods**: build_found_selection + group_found_by_rep take a list of records (typically `registry.all()`) and return a selection string / dict. Placed AFTER the HiderRegistry class in a new section. This keeps HiderRegistry focused on CRUD/queries/status/serialization while the helpers are pure functions over record lists — the GUI dropdown (Plan 02) will call `build_found_selection(self._controller.registry.all(), self._controller.target_obj)`.
- **None return for no-found**: build_found_selection returns `None` (not `""`) when no found records exist — the GUI dropdown caller early-returns on `None` without issuing a malformed PyMOL selection. Mirrors the "None signals absence" convention.
- **rep=None skipped in group_found_by_rep**: post-.pse reload records have rep=None (sentinel carries no rep; 03-10 decision). group_found_by_rep skips them — only records with a real rep appear in the dict. Same tolerance pattern as counts_by_rep.
- **Default 'green' preserves legacy**: _found_color defaults to 'green' so existing tests asserting `cmd.color('green', ...)` (test_game_controller.py lines 95, 343, 411) pass UNCHANGED. The DIFF-04 override is a simple attribute assignment — no API change, no migration.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Plan 02 (GUI wiring) is unblocked**: the pure helpers + _found_color attribute are WSL-tested and ready for the Qt-coupled GUI dropdown (GAME-08) + color picker (DIFF-04) + Restart button (GAME-10) + Cleanup button (BTN-06). Plan 02 is WSL-unverifiable (py_compile + grep gates only — Qt-coupled); this plan's WSL confidence in the foundation is the safety net.
- **No blockers**: all 200 tests pass, all WSL gates green, registry.py purity intact, module dependency direction unchanged (registry.py pure ← game.py orchestrator).
- **What Plan 02 will consume**: `build_found_selection(found, target_obj)` for dropdown hide/recolor selections; `group_found_by_rep(found)` for dropdown show mode (per-rep cmd.show); `controller._found_color` for the color picker assignment + auto-recolor; `controller._mark_found` already reads `self._found_color` (automatic for new finds after color change).

---
*Phase: 07-found-hider-management-restart-cleanup*
*Completed: 2026-08-11*
