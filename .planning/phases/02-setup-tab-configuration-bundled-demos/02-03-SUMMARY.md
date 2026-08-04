---
phase: 02-setup-tab-configuration-bundled-demos
plan: 03
subsystem: ui
tags: [pymol, qt, pyqt5, setup-form, cmd-bridge, wsl-paths, qstackedwidget, qfiledialog, qcombobox]

# Dependency graph
requires:
  - phase: 02-setup-tab-configuration-bundled-demos (02-01)
    provides: Pure setup state model (DEFAULTS, SETUP_FORMAT, GAME_REPS, DEMO_MANIFEST, hider_count_cap, randomize_state, validate_state) imported by both demos.py and gui_setup.py
  - phase: 02-setup-tab-configuration-bundled-demos (02-02)
    provides: 6 bundled demo PDB files in biochemeleon/data/demos/ resolved by load_demo via __file__-relative paths
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: PluginDialog with 2 tabs + lazy import of SetupTab (gui_setup.py populated automatically, no __init__.py change needed)
provides:
  - "demos.py: 5 cmd-coupled utilities (to_windows_path, list_loaded_molecule_objects, fetch_pdb, get_active_reps, load_demo) bridging the pure state model to PyMOL cmd"
  - "gui_setup.py: full SetupTab widget — 3-mode target selector (QStackedWidget), hider-count spinbox (capped), lock-scene checkbox (auto-detect reps), per-rep rows (5 reps), difficulty toggle, 4 action buttons (Reset/Randomize/Save/Load)"
  - "collect_state/apply_state round-trip contract (JSON-serializable dict) for Save/Load + the Phase 4 Start button"
affects: [02-setup-tab-configuration-bundled-demos (02-04 smoke test exercises this UI), 04-mvp-core-loop (Start button calls load_demo/collect_state), 09-large-demo-fetch (DEMO_MANIFEST extension feeds demo_combo)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — uses pymol.Qt (QtWidgets), json, os (all already available)
  patterns:
    - "Refresh-on-show QComboBox: PyMOLObjectCombo overrides showPopup to repopulate from cmd.get_names (vina.py:1153 pattern)"
    - "QStackedWidget for 3-mode target selector swap (loaded/fetch/demo) — Qt's idiomatic show-one-of-N container"
    - "_loading guard flag in apply_state: suppresses cascading signal handlers (_on_target_changed, _on_lock_scene_toggled) during programmatic state application so Save->Load round-trips verbatim"
    - "collect_state/apply_state round-trip: JSON-serializable dict snapshot with SETUP_FORMAT tag + validate_state on load"
    - "Per-rep rows as QGroupBox of QHBoxLayouts (1 row per rep): QCheckBox + QSpinBox + QLabel('random') — simpler than QListWidget delegates for a fixed 5-rep set"

key-files:
  created: []  # both files existed as Phase-1 stubs; this plan overwrote them
  modified:
    - biochemeleon/demos.py
    - biochemeleon/gui_setup.py

key-decisions:
  - "hider_count_cap imported from setup_state (NOT demos) per the plan's key_links — setup_state is the single source of truth for the pure data layer"
  - "load_demo imported by gui_setup.py per the key_links contract even though the Setup form does not auto-load demos on selection (demo loading is deferred to the Phase 4 Start button); the import satisfies the declared API contract"
  - "apply_state uses a _loading flag (not blockSignals) to suppress cascading recompute/sync — cleaner than per-widget signal blocking and handles all cascading paths (mode_combo, obj_combo, demo_combo, lock_scene_cb) uniformly"
  - "Added try/except error handling in _save_setup/_load_setup (OSError/ValueError -> QMessageBox) and around cmd.count_atoms in _on_target_changed/_randomize (TOCTOU race protection) — research scaffold omitted these"
  - "Rephrased the module docstring to avoid a false-positive Pitfall-1 grep match (the prose 'NEVER from PyQt5 import' was triggering the grep pattern)"

patterns-established:
  - "Pattern: cmd-coupled bridge module (demos.py) imports FROM the pure layer (setup_state.py) and exposes functions that wrap cmd.* in try/except — keeps GUI modules decoupled from cmd failure modes"
  - "Pattern: _loading flag for programmatic widget updates — set True at the start of apply_state, False in a finally block; signal handlers early-return on _loading to prevent cascading recompute"
  - "Pattern: to_windows_path is a GUARD (only /mnt/<letter>/ converted), not an unconditional transform — portable across installed-Windows, dev-WSL, and genuine-Linux runtimes"
  - "Pattern: get_active_reps wraps each per-rep count_atoms in try/except so a single failed rep degrades gracefully (research 12.1 mitigation)"

# Metrics
duration: 4min
completed: 2026-08-04
---

# Phase 2 Plan 3: Demos + GUI Setup Summary

**PyMOL cmd-coupled utilities (demos.py) + full SetupTab form (gui_setup.py) wiring the pure state model and bundled demos into a 3-mode target selector with capped hider count, lock-scene rep detection, per-rep rows, and Save/Load/Reset/Randomize actions**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-04T16:50:28Z
- **Completed:** 2026-08-04T16:54:54Z
- **Tasks:** 2 (demos.py populate, gui_setup.py populate)
- **Files modified:** 2 (both overwritten from Phase-1 stubs)

## Accomplishments
- Populated demos.py (137 lines) with 5 cmd-coupled utilities: to_windows_path (WSL guard — only /mnt/<letter>/ converted), list_loaded_molecule_objects (cmd.get_names + get_type filter), fetch_pdb (cmd.fetch async_=0 + try/except), get_active_reps (`rep <name>` selector + per-rep try/except), load_demo (__file__-relative path + to_windows_path + cmd.load). Imports GAME_REPS + DEMO_MANIFEST from setup_state (pure layer).
- Populated gui_setup.py (390 lines) with the full SetupTab: PyMOLObjectCombo (refresh-on-show), 3-mode target selector via QStackedWidget (loaded object / PDB fetch / bundled demo), hider-count spinbox capped via hider_count_cap(cmd.count_atoms), lock-scene checkbox (auto-detects reps via get_active_reps and locks checkboxes), 5 per-rep rows (checkbox + spinbox + "random" label), difficulty toggle, 4 action buttons (Reset/Randomize/Save/Load), collect_state/apply_state round-trip with _loading guard, JSON save/load via QFileDialog (.bcm.setup.json), randomize via setup_state.randomize_state, validate on load via setup_state.validate_state.
- Verified all 10 plan verification checks pass: 7 modules py_compile, Pitfall-1 grep ZERO matches, pymol.Qt used, all 5 demos.py functions + guard, all gui_setup.py classes/methods/widgets, imports from both .setup_state and .demos, Plan 02-01's 48 tests still pass, 6 PDB files + SOURCES.md present, placeholder text gone, only 2 files changed.
- All 13 must-have truths satisfied (verified via grep + py_compile + functional to_windows_path test + 48 unit tests).

## Task Commits

Each task was committed atomically:

1. **Task 1: Populate demos.py with cmd-coupled utilities + to_windows_path** - `6435217` (feat)
2. **Task 2: Populate gui_setup.py with full SetupTab form** - `398ad37` (feat)

**Plan metadata:** pending (docs commit after this SUMMARY)

## Files Created/Modified
- `biochemeleon/demos.py` (137 lines) — PyMOL cmd bridge: to_windows_path (WSL->Windows guard), list_loaded_molecule_objects, fetch_pdb (async_=0 + try/except), get_active_reps (`rep <name>` selector), load_demo (__file__-relative + cmd.load). Imports GAME_REPS, DEMO_MANIFEST from setup_state.
- `biochemeleon/gui_setup.py` (390 lines) — Full SetupTab: PyMOLObjectCombo, 3-mode QStackedWidget target selector, capped hider spinbox, lock-scene checkbox with auto-rep-detect, 5 per-rep rows, difficulty toggle, 4 action buttons, collect_state/apply_state round-trip, JSON save/load, randomize/validate via setup_state.

## Decisions Made
- **hider_count_cap imported from setup_state, not demos.** Rationale: the plan's key_links explicitly specifies `from .setup_state import ... hider_count_cap ...`; setup_state is the single source of truth for the pure data layer. The research scaffold imported it from demos — the plan overrides this.
- **load_demo imported by gui_setup.py but not called in Phase 2.** Rationale: the plan's key_links requires the import (`from .demos import load_demo, ...`). The Setup form captures the demo_id but does not auto-load the demo on selection (demo loading is deferred to the Phase 4 Start button). The import satisfies the declared API contract and will be used by Phase 4. No verification check fails on an unused import.
- **apply_state uses a _loading flag, not blockSignals.** Rationale: the research scaffold's apply_state set lock_scene_cb.setChecked and obj_combo.setEditText without guarding against the cascading signal handlers (toggled -> _on_lock_scene_toggled -> _sync_reps_from_scene; currentTextChanged -> _on_target_changed -> cap recompute). Without a guard, a Save->Load round-trip would have the loaded per_rep values overwritten by _sync_reps_from_scene. The _loading flag (set True in apply_state, checked in _on_target_changed and _on_lock_scene_toggled) cleanly suppresses all cascading paths in one mechanism.
- **Added error handling in _save_setup/_load_setup and around cmd.count_atoms.** Rationale: the research §7.2 scaffold did not wrap file I/O in try/except; an OSError (disk full, permission denied) or ValueError (corrupt JSON) would crash the form with an unhandled exception. Similarly, cmd.count_atoms in _on_target_changed has a TOCTOU race (object deleted between the combo check and the count). Both are Rule 2 (missing critical error handling) auto-fixes.
- **Rephrased the module docstring to avoid a false-positive grep.** Rationale: the original docstring prose "NEVER `from PyQt5 import`" contained the literal string `from PyQt5 import`, which the Pitfall-1 verification grep (`grep -E "from PyQt5 import"`) matched — a false positive on a comment explaining to never use it. Rephrased to "NEVER raw PyQt5" so the grep returns ZERO matches cleanly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added _loading guard flag in apply_state**
- **Found during:** Task 2 (gui_setup.py populate)
- **Issue:** The research §7.3 apply_state scaffold set lock_scene_cb.setChecked and obj_combo.setEditText without guarding against cascading signal handlers. During a Save->Load round-trip, setting lock_scene_cb would fire _on_lock_scene_toggled -> _sync_reps_from_scene, overwriting the loaded per_rep values from the scene instead of preserving the saved state. This breaks the "collect_state / apply_state round-trip" must-have truth.
- **Fix:** Added a `self._loading` flag (set True at the start of apply_state, False in a finally block). _on_target_changed and _on_lock_scene_toggled early-return when _loading is True, so saved state is applied verbatim.
- **Files modified:** biochemeleon/gui_setup.py
- **Verification:** collect_state -> apply_state(collect_state()) preserves all fields including per_rep (confirmed by code inspection; full round-trip exercised in Plan 02-04 smoke test).
- **Committed in:** 398ad37 (Task 2 commit)

**2. [Rule 2 - Missing Critical] Added try/except error handling in _save_setup and _load_setup**
- **Found during:** Task 2 (gui_setup.py populate)
- **Issue:** The research §7.2 save/load scaffold called json.dump/json.load and open() without try/except. An OSError (disk full, permission denied, path too long) or ValueError (corrupt/non-JSON file) would raise an unhandled exception and crash the Setup form.
- **Fix:** Wrapped file I/O in try/except (OSError, ValueError) -> QtWidgets.QMessageBox.warning with the error message. The user sees a clean error dialog instead of a crash.
- **Files modified:** biochemeleon/gui_setup.py
- **Verification:** py_compile passes; error paths are unreachable in WSL (no PyMOL) but structurally sound (try/except + QMessageBox pattern matches outline.py:178-182).
- **Committed in:** 398ad37 (Task 2 commit)

**3. [Rule 2 - Missing Critical] Added try/except around cmd.count_atoms in _on_target_changed and _randomize**
- **Found during:** Task 2 (gui_setup.py populate)
- **Issue:** The research §5.2 _on_target_changed called cmd.count_atoms(obj) directly. There is a TOCTOU race: current_target_object checks `name in list_loaded_molecule_objects()`, but the object could be deleted (by the user or another plugin) between that check and the count_atoms call, raising an unhandled exception.
- **Fix:** Wrapped cmd.count_atoms in try/except -> fallback cap of 50. Same guard added in _randomize.
- **Files modified:** biochemeleon/gui_setup.py
- **Verification:** py_compile passes; the try/except is structurally sound and degrades gracefully (cap falls back to 50).
- **Committed in:** 398ad37 (Task 2 commit)

**4. [Rule 1 - Bug] Rephrased module docstring to avoid false-positive Pitfall-1 grep**
- **Found during:** Task 2 verification (Pitfall-1 grep)
- **Issue:** The gui_setup.py module docstring contained the prose "NEVER `from PyQt5 import`" (explaining to never use it). The verification grep `grep -E "from PyQt5 import"` matched this docstring text, producing a false positive that would fail the Pitfall-1 gate.
- **Fix:** Rephrased to "NEVER raw PyQt5" — preserves the intent without the literal grep-triggering string.
- **Files modified:** biochemeleon/gui_setup.py
- **Verification:** Pitfall-1 grep now returns ZERO matches across all .py files.
- **Committed in:** 398ad37 (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (3 missing critical error handling, 1 bug/false-positive)
**Impact on plan:** All auto-fixes necessary for correctness (round-trip integrity, crash prevention, verification gate). No scope creep — the added code is defensive error handling and a guard flag, not new features.

## Issues Encountered
None. Both tasks completed cleanly on the first pass. The Pitfall-1 grep false positive (deviation 4) was caught and fixed during verification, not a blocking issue. Plan 02-01's 48 unit tests passed both before Task 1's commit and after Task 2's commit, confirming setup_state.py was not disturbed.

`rg` (ripgrep) is not installed in the WSL shell, so the plan's `rg`-based verification commands were substituted with `grep -n`/`grep -nE` (functionally equivalent). This did not affect verification outcomes.

## User Setup Required
None — no external service configuration. This plan is pure Python (pymol.Qt + stdlib json/os) with no network or external dependencies beyond PyMOL itself. The functional smoke test (Plan 02-04) requires Windows PyMOL via setenv.bat.

## Next Phase Readiness
- **Ready for Plan 02-04** (Windows PyMOL smoke test): the Setup form is fully populated. The smoke test will exercise the 4 success criteria (3-mode selector, hider cap, lock-scene auto-detect, Reset/Randomize/Save/Load, 6 demo loads). The WSL tier (syntax + grep) passes; the Windows tier (functional) is 02-04's scope.
- **Ready for Phase 4** (MVP core loop): collect_state() produces the JSON-serializable setup dict that the Start button will consume to configure the hider generator. load_demo is available for the Start button to load the selected demo. The _loading guard pattern is established for Phase 4's game-state apply.
- **Ready for Phase 9** (Large demo fetch): DEMO_MANIFEST (in setup_state.py) is the extension point for large fetched demos; the demo_combo auto-populates from it. SOURCES.md (from 02-02) will be absorbed into the consolidated DATA_SOURCES.md.
- **No blockers or concerns.** Wave 2 (02-03) is complete; Wave 3 (02-04 smoke test) is the human-verify checkpoint that closes Phase 2.

---
*Phase: 02-setup-tab-configuration-bundled-demos*
*Completed: 2026-08-04*
