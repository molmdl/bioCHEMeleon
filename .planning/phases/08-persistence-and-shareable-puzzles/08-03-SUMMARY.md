---
phase: 08-persistence-and-shareable-puzzles
plan: 03
subsystem: persistence
tags: [persistence, bcmz-archive, zipfile, apply-bcm, import-state, file-io, pure-layer, orchestrator]

# Dependency graph
requires:
  - phase: 08-01
    provides: HiderRegistry.reconcile_with_bcm + ReconcileMismatches namedtuple (apply_bcm_dict calls reconcile_with_bcm; returns the namedtuple)
  - phase: 08-02
    provides: build_bcm_dict + parse_bcm_dict + BCM_MAGIC + BCM_VERSION constants in persistence.py (apply_bcm_dict validates magic/version; read_bcmz calls parse_bcm_dict)
  - phase: 03-game-state-and-mutation-safety
    provides: GameController.reconstruct_registry + backup.snapshot (import_state calls both)
provides:
  - persistence.apply_bcm_dict(controller, bcm_dict) -> ReconcileMismatches (pure — validates magic/version, sets controller fields, calls reconcile_with_bcm)
  - persistence.write_bcmz(bcmz_path, bcm_dict, pse_path) (pure file I/O — zipfile bundles .pse + .bcm)
  - persistence.read_bcmz(bcmz_path) -> (pse_path, bcm_dict) (pure file I/O — extracts .pse to temp + reads .bcm)
  - persistence.resolve_target(bcm_dict, names_before, loaded_molecules) -> str|None (pure — prefer target_object, fallback before/after diff)
  - GameController.import_state(bcm_dict) (cmd-coupled orchestrator — reconstruct_registry + apply_bcm_dict + cmd.color re-apply + backup.snapshot + _is_imported/_imported_bcm)
  - GameController._is_imported + _imported_bcm fields (route Restart/Cleanup-on-imported in Plan 04 GUI handlers)
  - 13 new unit tests in tests/test_persistence.py (TestApplyBcmDict 6, TestWriteReadBcmz 3, TestResolveTarget 3, TestBuildApplyRoundTrip 1)
affects: [08-04, 08-05]

# Tech tracking
tech-stack:
  added: []  # stdlib os + tempfile + zipfile (already available)
  patterns:
    - "Pure file-I/O archive helpers: write_bcmz/read_bcmz use stdlib zipfile + json + tempfile only (NO pymol). The cmd.save/cmd.load calls live in the GUI handler (Plan 04), NOT here — keeps persistence.py WSL-testable."
    - "Lazy import for circular-avoidance: GameController.import_state does `from . import persistence` inside the method body (persistence imports registry, game imports persistence — lazy breaks the cycle at module load)."
    - "Defensive found-color re-apply: import_state re-applies cmd.color(_found_color) to all found hiders after apply_bcm_dict. Idempotent (.pse preserves color per importing.py:143) but future-proofs against a format change that drops color preservation."
    - "Fresh backup on import: import_state calls backup.snapshot AFTER apply_bcm_dict (not before) — the post-import state (hiders + found-status) IS the 'original' for an imported game (research §6.2). Cleanup/Restart restore to this point."
    - "resolve_target before/after diff: prefer bcm_dict['target_object'] if in loaded_molecules; else diff (loaded - names_before, excluding _-prefixed); None if ambiguous. Handles rename-on-collision (Discrepancy 1 refuse-first defense)."

key-files:
  created: []
  modified:
    - biochemeleon/persistence.py
    - biochemeleon/game.py
    - tests/test_persistence.py

key-decisions:
  - "persistence.py stays PURE (0 from pymol at module level OR inside function bodies). write_bcmz needs cmd.save but that call lives in the GUI handler (Plan 04); write_bcmz takes an already-written pse_path and just zips it. read_bcmz is pure file I/O (extract .pse to temp + read .bcm); cmd.load lives in the GUI handler. This keeps persistence.py WSL-testable (Discrepancy 1 resolution)."
  - "GameController.import_state mirrors start()'s end-state (_started=True, _backup_name set, registry populated) but skips snapshot-before-insert + insert loop — the hiders came from the .pse, not from mutation.insert_hider. The FRESH backup is taken AFTER apply_bcm_dict (post-import state = the 'original' for an imported game)."
  - "_is_imported flag routes Restart + Cleanup-on-imported (Plan 04 GUI handlers check this flag to decide whether to re-reconcile from _imported_bcm or re-generate from setup). _imported_bcm stores the .bcm dict so Restart-on-imported can re-reconcile rep without re-reading the file."
  - "Test class named TestBuildApplyRoundTrip (NOT TestBcmRoundTrip as the plan specified) — the plan's name collided with the existing TestBcmRoundTrip class (2 build<->parse round-trip tests from Plan 02). Reusing the name would shadow the existing class + silently drop those 2 tests (count would be 26, not the plan's 28). Renamed for clarity + collision avoidance (Rule 1 fix)."
  - "Fixed pre-existing docstring inaccuracy in persistence.py module docstring (Rule 1): Plan 02's forward-looking description called write_bcmz/read_bcmz/resolve_target 'cmd-coupled file I/O' and claimed they 'import cmd lazily inside the function body'. Per the plan, these functions are PURE (stdlib zipfile/json/tempfile + dict/set ops, NO cmd). Corrected to 'pure file-I/O archive helpers' + updated the purity note."

patterns-established:
  - "Lazy import pattern for orchestrator -> persistence: game.py does `from . import persistence` inside import_state's method body (NOT at module level). This breaks the circular dependency (persistence imports registry, game imports persistence) at module load time. Same pattern as __init__.py's lazy wizard import."
  - ".bcmz archive format: single zipfile containing game.pse (PyMOL session) + game.bcm (JSON sidecar). write_bcmz uses ZIP_DEFLATED. read_bcmz validates both members exist + parses .bcm via parse_bcm_dict (magic/version guard). The .pse is extracted to a tempfile.mkdtemp(prefix='bchm_import_') directory; the caller (GUI handler) does cmd.load(pse_path, partial=1) afterward."
  - "resolve_target collision-defense pattern: the GUI handler (Plan 04) captures names_before = set(demos.list_loaded_molecule_objects()) BEFORE cmd.load(pse_path, partial=1), then passes (bcm_dict, names_before, loaded_molecules_after) to resolve_target. The diff (loaded - names_before, excluding _-prefixed) catches any rename-on-collision. Returns None if ambiguous (GUI shows error)."

# Metrics
duration: 13min
completed: 2026-08-12
---

# Phase 8 Plan 03: Apply + Archive I/O + Import State Summary

**apply_bcm_dict (pure registry reconcile + controller field set) + write_bcmz/read_bcmz (stdlib zipfile .bcmz archive) + resolve_target + GameController.import_state (orchestrator entry point for imported games)**

## Performance

- **Duration:** 13 min
- **Started:** 2026-08-11T22:45:11Z
- **Completed:** 2026-08-11T22:58:03Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- persistence.py extended with 4 new functions (apply_bcm_dict + write_bcmz + read_bcmz + resolve_target) — all PURE (stdlib only, 0 from pymol). apply_bcm_dict validates magic/version, sets controller._reveal_count/_hint_count/_found_color, and calls reconcile_with_bcm (Plan 01). write_bcmz/read_bcmz bundle/extract the .bcmz archive (zipfile with game.pse + game.bcm). resolve_target resolves the imported target object name via dict/set ops.
- game.py extended with GameController.import_state (the orchestrator entry point the GUI _on_import handler in Plan 04 calls after cmd.load(.pse, partial=1)). Mirrors start()'s end-state but skips insert loop — reconstructs registry from sentinels, applies .bcm state, re-applies found-color defensively, snapshots a FRESH backup, sets _started/_is_imported/_imported_bcm.
- 13 new unit tests added (TestApplyBcmDict 6 + TestWriteReadBcmz 3 + TestResolveTarget 3 + TestBuildApplyRoundTrip 1) = 28 total persistence tests, all pass. No regression (206 total: 28 persistence + 167 setup_state/registry + 24 game_controller).

## Task Commits

Each task was committed atomically (Tasks 1+2 deferred to Task 3 per plan's combined-commit instruction):

1. **Task 1: Implement apply_bcm_dict + write_bcmz + read_bcmz + resolve_target in persistence.py** - `91e8049` (feat) — committed together with Task 2+3
2. **Task 2: Implement GameController.import_state + _is_imported + _imported_bcm in game.py** - `91e8049` (feat) — committed together with Task 1+3
3. **Task 3: Add apply_bcm_dict + write_bcmz/read_bcmz round-trip tests + commit** - `91e8049` (feat) — combined commit per plan's step 6

**Plan metadata:** (pending — created after this summary)

## Files Created/Modified
- `biochemeleon/persistence.py` — +4 functions (apply_bcm_dict, write_bcmz, read_bcmz, resolve_target) + imports (os, tempfile, zipfile, ReconcileMismatches) + docstring fix (Rule 1: "cmd-coupled" → "pure file-I/O")
- `biochemeleon/game.py` — +import_state method (reconstruct_registry + apply_bcm_dict + cmd.color re-apply + backup.snapshot + _is_imported/_imported_bcm set) + _is_imported/_imported_bcm fields in __init__
- `tests/test_persistence.py` — +13 tests (TestApplyBcmDict 6, TestWriteReadBcmz 3, TestResolveTarget 3, TestBuildApplyRoundTrip 1) + imports (shutil, tempfile, zipfile, apply_bcm_dict/write_bcmz/read_bcmz/resolve_target, HIDER_STATUS_HIDDEN/ReconcileMismatches)

## Decisions Made
- persistence.py stays PURE (0 from pymol at module level OR inside function bodies). The cmd.save/cmd.load calls live in the GUI handler (Plan 04), NOT in write_bcmz/read_bcmz. This keeps persistence.py WSL-testable (Discrepancy 1 resolution).
- GameController.import_state takes a FRESH backup AFTER apply_bcm_dict (not before) — the post-import state (hiders + found-status) IS the "original" for an imported game (research §6.2). Cleanup/Restart restore to this point.
- _is_imported flag routes Restart + Cleanup-on-imported (Plan 04 GUI handlers check this flag). _imported_bcm stores the .bcm dict so Restart-on-imported can re-reconcile rep without re-reading the file.
- Lazy import pattern: `from . import persistence` inside import_state's method body breaks the circular dependency (persistence imports registry, game imports persistence) at module load.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing docstring inaccuracy in persistence.py module docstring**
- **Found during:** Task 1 (implementing the 4 new functions)
- **Issue:** Plan 02's forward-looking module docstring described write_bcmz/read_bcmz/resolve_target as "cmd-coupled file I/O" and claimed they "import cmd lazily inside the function body". Per the Plan 03 spec, these functions are PURE (stdlib zipfile/json/tempfile + dict/set ops, NO cmd). Leaving the inaccuracy would mislead future readers + the purity grep gate.
- **Fix:** Rewrote the docstring header to "pure file-I/O archive helpers" + updated the purity note to "NO `pymol` import at module level OR inside any function body" + clarified that cmd-coupled steps (cmd.save, cmd.load, cmd.color, backup.snapshot) live in the GUI handler (Plan 04) + game.py.import_state, NOT in persistence.py.
- **Files modified:** biochemeleon/persistence.py (docstring only)
- **Verification:** py_compile clean; 0 `from pymol` matches in persistence.py; 28 tests pass
- **Committed in:** 91e8049 (part of Task 1+2+3 combined commit)

**2. [Rule 1 - Bug] Renamed TestBcmRoundTrip -> TestBuildApplyRoundTrip to avoid class-name collision**
- **Found during:** Task 3 (adding the build->apply round-trip test class)
- **Issue:** The plan specified a new class `TestBcmRoundTrip` (1 test: test_build_then_apply_preserves_state). But a class with that name already exists (lines 196-251, 2 tests: test_build_then_parse_preserves_state + test_parse_then_build_round_trip, added in Plan 02). Adding a second class with the same name would shadow the existing class in the module namespace, silently dropping those 2 tests (unittest would only run the second class's 1 test). Total count would be 26, not the plan's expected 28.
- **Fix:** Named the new class `TestBuildApplyRoundTrip` (more descriptive — it tests the build->apply round-trip, distinct from the existing build<->parse round-trip). Added a NOTE comment in the class docstring explaining the rename. All 28 tests now run (15 from Plan 02 + 13 new).
- **Files modified:** tests/test_persistence.py
- **Verification:** `python3.6 -m unittest tests.test_persistence -v` shows "Ran 28 tests" with all 3 existing round-trip classes (TestBcmRoundTrip 2 + TestBuildApplyRoundTrip 1) running
- **Committed in:** 91e8049 (part of Task 1+2+3 combined commit)

---

**Total deviations:** 2 auto-fixed (2 bugs — docstring inaccuracy + test class name collision)
**Impact on plan:** Both auto-fixes necessary for correctness (accurate documentation + no silent test loss). No scope creep. End state matches plan intent (28 tests, all functions implemented as specified).

## Issues Encountered
None — all 3 tasks executed cleanly. py_compile + 206 tests pass on first run after implementation. No debugging iterations needed.

## User Setup Required
None — no external service configuration required. All work is pure Python (stdlib zipfile/json/tempfile + biochemeleon internals).

## Next Phase Readiness
- **Ready for 08-04-PLAN.md (GUI wiring):** apply_bcm_dict + write_bcmz/read_bcmz/resolve_target + GameController.import_state are all implemented + unit-tested. Plan 04's GUI handlers (_on_export/_on_import/_on_save/_on_restart_imported) can call these directly. The _is_imported flag is set; Plan 04's Restart/Cleanup handlers check it.
- **Ready for 08-05-PLAN.md (headless smoke + human-verify):** the headless smoke can call persistence.apply_bcm_dict + write_bcmz/read_bcmz + GameController.import_state directly (no GUI) to verify the export/import round-trip.
- **No blockers.** The lazy import pattern (game.py -> persistence) is the only cross-module dependency; it's tested implicitly by the 24 game_controller tests (which import game.py, which no longer fails on the persistence import because it's lazy).
- **Discrepancy 1 resolved:** cmd.load(pse_path, partial=1) lives in the GUI handler (Plan 04), NOT in read_bcmz. read_bcmz is pure file I/O (extract .pse to temp + read .bcm). The refuse-first collision detection (if target_obj already loaded -> refuse) also lives in the GUI handler. resolve_target's before/after diff fallback handles any rename-on-collision case.

---
*Phase: 08-persistence-and-shareable-puzzles*
*Completed: 2026-08-12*
