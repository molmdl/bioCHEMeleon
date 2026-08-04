---
phase: 02-setup-tab-configuration-bundled-demos
plan: 07
subsystem: ui
tags: [pymol, qt, pyqt5, setup-form, gap-closure, pdb-pool, qpushbutton, random-choice, fetch-field]

# Dependency graph
requires:
  - phase: 02-setup-tab-configuration-bundled-demos (02-06)
    provides: QListWidget pool editor + Add/Edit/Remove/Use-bundled-pool buttons + tightened _validate_pdb_code (exactly 4-char) + PDB_POOL (33 verified RCSB entries, already imported in gui_setup.py line 22). The post-02-06 smoke test passed all 4 criteria; the user approved this 1 small enhancement before final Phase 2 approval.
provides:
  - "gui_setup.py: 'Choose random' button (self.pool_choose_btn) added as a 5th button in the pool button row (inside the pool QGroupBox, visually associated with the pool); _choose_random_from_pool slot picks random.choice(self._pool_list() or list(PDB_POOL)), switches mode_combo to index 1 (fetch), sets pdb_edit to the chosen code; does NOT touch any other setup field; import random added at module level"
  - "No pure-layer change: setup_state.py UNCHANGED (PDB_POOL 33 entries, _validate_pdb_code, randomize_state, validate_state, DEFAULTS all untouched); tests/test_setup_state.py UNCHANGED (90 tests still pass)"
affects: [02-setup-tab-configuration-bundled-demos (02-04 smoke test re-run confirms the Choose random button in a live PyMOL Qt session — button appears in the pool group, clicking it switches to fetch mode + populates pdb_edit with a random pool entry), 04-mvp-core-loop (the button gives one-click access to a random fetch code from the pool — direct path that previously required clicking Randomize repeatedly and hoping it landed on fetch mode)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — random is stdlib, QPushButton available via pymol.Qt
  patterns:
    - "Focused single-purpose UI action: _choose_random_from_pool touches ONLY mode_combo + pdb_edit (no hider count, lock scene, per-rep, difficulty, lock source, demo, or loaded object) — the explicit 'do NOT change any other setup field' contract from the plan"
    - "Empty-list fallback mirroring randomize_state semantics: `pool = self._pool_list() or list(PDB_POOL)` reuses the 02-05 convention that an empty pool signals 'use bundled pool' (never produces an empty pdb_code box)"
    - "Defense-in-depth: an explicit `if not pool: return` early-exit handles the impossible-in-practice case where both the user list and PDB_POOL are empty (PDB_POOL has 33 verified entries, but the guard is harmless)"
    - "Pool-associated button placement: the new button lives INSIDE the pool QGroupBox's button row (not with the main Reset/Randomize/Save/Load Setup actions) — its affordance is 'pick from this pool', not 'configure the whole setup'"

key-files:
  created:
    - ".planning/phases/02-setup-tab-configuration-bundled-demos/02-07-SUMMARY.md"
  modified:
    - "biochemeleon/gui_setup.py"

key-decisions:
  - "Button placed inside the pool QGroupBox's button row (as the 5th button after + Add / ✎ Edit / − Remove / Use bundled pool), NOT with the main Setup actions (Reset/Randomize/Save/Load). Per the user's enhancement spec: the button is visually associated with the pool it picks from."
  - "Empty pool falls back to the bundled PDB_POOL (33 entries) — mirrors the 02-05 `randomize_state` convention that an empty pool signals 'use bundled pool'. The user never gets an empty pdb_code box from the button."
  - "mode_combo.setCurrentIndex(1) is the only mode switch (0=loaded, 1=fetch, 2=demo). It triggers _on_mode_changed which calls target_stack.setCurrentIndex(1) (shows the fetch page). It does NOT trigger _on_target_changed (that's wired to obj_combo.currentTextChanged / demo_combo.currentIndexChanged, not mode_combo) — so the hider-count cap recompute is NOT triggered by this button. Focused, single-purpose."
  - "import random added at module level (next to import json, line 14-15), NOT as a local import inside the slot — conventional for a module that now uses the module at runtime."
  - "PDB_POOL import (line 22, added in 02-06) verified present, NOT re-added — the plan explicitly warned against duplicating it."
  - "No new test added — the button is UI-only and doesn't change pure-layer behavior (it picks a random list entry and sets a text field). The pre-existing 90 tests pin the pure layer; the WSL-unverifiable button behavior is confirmed at the 02-04 smoke test re-run."

patterns-established:
  - "Gap-closure enhancement: a single UI-only button + slot, no pure-layer change, no new test — the smallest possible plan shape. WSL-tier verification (py_compile + pitfall-1 grep + exec_ gate + 90 tests + git diff stats) is sufficient; the live PyMOL Qt behavior is the smoke test's job."
  - "Pool-button row as the home for pool-related actions: Add/Edit/Remove/Use-bundled-pool/Choose-random all live together inside the pool QGroupBox. Main Setup actions (Reset/Randomize/Save/Load) stay in their own group. The grouping makes each button's scope obvious from its placement."

# Metrics
duration: 1 min
completed: 2026-08-04
---

# Phase 2 Plan 07: Gap Closure (Choose random button) Summary

**Added a 'Choose random' button next to the pool buttons in the fetch page that picks a random entry from the user's pool list (or the 33-entry bundled PDB_POOL if empty) into the fetch field, switching source mode to fetch — a focused, single-purpose UI action that previously required clicking Randomize repeatedly and hoping it landed on fetch mode**

## Performance

- **Duration:** 1 min
- **Started:** 2026-08-04T19:41:08Z
- **Completed:** 2026-08-04T19:42:07Z
- **Tasks:** 1 (UI-only, no TDD)
- **Files modified:** 1

## Accomplishments
- **"Choose random" button added** as a 5th button in the pool button row (inside the pool `QGroupBox`, visually associated with the pool — not with the main Reset/Randomize/Save/Load Setup actions). The pool button row now has 5 short buttons: `+ Add`, `✎ Edit`, `− Remove`, `Use bundled pool`, `Choose random`.
- **`_choose_random_from_pool` slot implemented** — picks `random.choice(self._pool_list() or list(PDB_POOL))`, switches `mode_combo` to index 1 (fetch) so the field is visible, and sets `pdb_edit` to the chosen code. Does NOT touch any other setup field (hider count, lock scene, per-rep, difficulty, lock source, demo, loaded object). Returns early if both lists are empty (defensive — PDB_POOL has 33 entries so this is unreachable in practice).
- **`import random` added at module level** (line 15, next to `import json`); `PDB_POOL` import (line 22, from 02-06) verified present, not re-added.
- **All 90 tests still pass** (no pure-layer changes); `setup_state.py`, `tests/test_setup_state.py`, other modules, `data/demos/*`, and `ROADMAP.md` all UNCHANGED. PDB_POOL (33 verified entries) unchanged.

## Task Commits

Each task was committed atomically:

1. **Task 1 (UI): Add Choose random button + _choose_random_from_pool slot** - `355bf12` (feat)

**Plan metadata:** (this commit) (docs: complete plan)

## Files Created/Modified
- `biochemeleon/gui_setup.py` - Added `import random` at module level (line 15); added `self.pool_choose_btn = QPushButton("Choose random")` as the 5th button in the pool button row; wired `pool_choose_btn.clicked -> _choose_random_from_pool`; added `_choose_random_from_pool` slot method (picks `random.choice(self._pool_list() or list(PDB_POOL))`, sets `mode_combo` to index 1, sets `pdb_edit` to the chosen code; defensive early-return if both empty; touches no other field)

## Decisions Made
- Button placed inside the pool `QGroupBox`'s button row (5th button), NOT with the main Setup actions — per the user's enhancement spec, the button is visually associated with the pool it picks from.
- Empty pool falls back to `list(PDB_POOL)` — mirrors the 02-05 `randomize_state` convention (empty pool = use bundled pool; never produces an empty pdb_code box).
- `import random` at module level (not a local import) — conventional for a module that now uses `random` at runtime.
- `PDB_POOL` import (from 02-06, line 22) verified, NOT re-added — the plan explicitly warned against duplicating it.
- No new test added — the button is UI-only and doesn't change pure-layer behavior; the WSL-unverifiable live-Qt behavior is the 02-04 smoke test's job.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **WSL-tier verification complete:** py_compile (all 7 modules exit 0), pitfall-1 grep ZERO matches, exec_ gate ZERO matches, new button + slot + import all present at the expected locations, PDB_POOL referenced in the import + `_use_bundled_pool` + `_choose_random_from_pool`, 90 tests pass, `setup_state.py` + `tests/test_setup_state.py` + other modules + `ROADMAP.md` + `data/demos/*` all UNCHANGED.
- **Phase 2 NOT complete:** awaiting user re-run of the 02-04 Windows PyMOL smoke test to confirm the "Choose random" button behaves in a live Qt session (button appears in the pool group; clicking it switches to fetch mode + populates the pdb_code field with a random pool entry; does not change any other field). This is a Windows-only verification (PyMOL/Qt runtime), not WSL-verifiable.
- **ROADMAP.md NOT updated** per the plan's explicit instruction — Phase 2 stays open until the smoke test is re-approved after this enhancement.
- After the smoke test passes, Phase 2 is complete and Phase 3 (Hider Generation — `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure) can begin.

---
*Phase: 02-setup-tab-configuration-bundled-demos*
*Completed: 2026-08-04*
