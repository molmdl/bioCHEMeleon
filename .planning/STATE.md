# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-02)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** Phase 2 — Setup Tab Configuration & Bundled Demos (02-07 gap closure done; 02-04 smoke test re-run is the gate to Phase 2 completion)

## Current Position

Phase: 2 of 10 (in progress — 02-07 "Choose random" button gap closure done; 02-04 smoke test re-run is the gate to Phase 2 completion)
Plan: 02-07 done (gap closure — Choose random button); 02-04 smoke test re-run is the gate to Phase 2 completion
Status: 02-07 gap closure complete (WSL tier); awaiting user re-run of 02-04 Windows PyMOL smoke test to confirm the Choose random button + the QListWidget pool editor + tightened validator
Last activity: 2026-08-04 — Completed 02-07-PLAN.md (1 enhancement: Choose random button next to the pool buttons that picks a random pool entry into the fetch field)

Progress: [█████████░] 90% (7 concrete plans done: 01-01, 02-01, 02-02, 02-03, 02-05, 02-06, 02-07; 02-04 smoke test re-run is the gate to Phase 2 completion)

## Performance Metrics

**Velocity:**
- Total plans completed: 7
- Average duration: ~12 min
- Total execution time: ~1.3 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1 | ~35 min | ~35 min |
| 2. Setup Tab Configuration & Bundled Demos | 6/6 + 02-06 + 02-07 gap closures | ~31 min | ~4 min |

**Recent Trend:**
- Last 7 plans: 01-01 ~35min, 02-01 ~2min, 02-02 ~1min, 02-03 ~4min, 02-05 ~19min, 02-06 ~4min, 02-07 ~1min
- Trend: 02-07 was the smallest plan yet (1 UI-only button + slot, no pure-layer change, no new test — WSL-only verified; runtime behavior deferred to 02-04 smoke test re-run)

*Updated after each plan completion*

## Accumulated Context

### Wave 1 outputs (02-01 + 02-02 — STILL AVAILABLE)

- **setup_state.py (Plan 02-01)**: GAME_REPS (5 reps), DEMO_MANIFEST (6 demos), DEFAULTS (9 keys), SETUP_FORMAT, hider_count_cap, randomize_state, validate_state. 48 unit tests pass.
- **data/demos/*.pdb (Plan 02-02)**: 6 valid PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) + SOURCES.md (64 lines, 6 DOIs). Git-tracked.

### Wave 2 outputs (02-03 — STILL AVAILABLE; extended by 02-05)

- **demos.py (137 lines)**: 5 cmd-coupled utilities — to_windows_path (WSL guard), list_loaded_molecule_objects, fetch_pdb (async_=0), get_active_reps (`rep <name>` selector), load_demo (__file__-relative + cmd.load). Imports GAME_REPS, DEMO_MANIFEST from setup_state. (UNCHANGED by 02-05)
- **gui_setup.py (390 -> 472 lines)**: full SetupTab — PyMOLObjectCombo, 3-mode QStackedWidget, capped hider spinbox, lock-scene auto-detect, 5 per-rep rows, difficulty toggle, 4 buttons, collect/apply round-trip, JSON save/load, randomize/validate. 02-05 added: current_target_object returns combo text (Gap 1), _recompute_per_rep_maxes (Gap 2 UI), lock_source_cb checkbox (Gap 3), pool_edit + _pool_list (Gap 4), _randomize passes lock_source/locked_state/pdb_pool.

### Wave 3 outputs (02-05 gap closure — STILL AVAILABLE; extended by 02-06)

- **setup_state.py (169 -> 313 lines)**: PDB_POOL (33 verified RCSB entries — 6 bundled demos + 14 proteins + 3 DNA + 4 RNA + 6 hybrid; plan prose said "34" but the actual list + category breakdown both sum to 33, used verbatim), _validate_pdb_code/_validate_pdb_pool helpers, DEFAULTS extended to 11 keys (+ lock_source, pdb_pool), randomize_state(lock_source, locked_state, pdb_pool), validate_state per_rep-sum clamp + new-field validation. Module still pure (no pymol, no Qt). 02-06 TIGHTENED _validate_pdb_code to exactly 4-char (was 3-5); _validate_pdb_pool + PDB_POOL + DEFAULTS + randomize_state + validate_state UNCHANGED.
- **tests/test_setup_state.py (244 -> 471 lines)**: 6 new test classes from 02-05 (TestPdbPool, TestDefaultsExtended, TestValidateStatePerRepSum, TestValidateStateNewFields, TestRandomizeLockSource, TestRandomizePdbPool) + TestDefaults.test_has_all_keys updated for 11-key schema. 02-06 added TestValidatePdbCode (10 tests) + updated test_pdb_pool_filters_invalid (input "12345" 5-char now rejected at _validate_pdb_code). 90 tests pass (48 pre-02-05 + 32 from 02-05 + 10 from 02-06).
- **gui_setup.py (390 -> 472 -> 552 lines)**: full SetupTab. 02-05 added: current_target_object (Gap 1), _recompute_per_rep_maxes (Gap 2 UI), lock_source_cb (Gap 3), pool_edit QPlainTextEdit + _pool_list (Gap 4), _randomize passes lock_source/locked_state/pdb_pool. 02-06 REPLACED pool_edit QPlainTextEdit with pool_list QListWidget (ExtendedSelection) inside a QGroupBox "Pool of PDB IDs (Randomize picks fetch codes from here)" + 4 buttons (+ Add, ✎ Edit, − Remove, Use bundled pool) + 4 slot methods (_add_pool_entry/_edit_pool_entry/_remove_pool_entry/_use_bundled_pool); _pool_list reads QListWidget items; apply_state clears + repopulates QListWidget (validates each); _validate_pdb_code + PDB_POOL imported.
- **All 4 smoke-test gaps closed at WSL tier (02-05) + 2 UX issues closed at WSL tier (02-06) + 1 enhancement closed at WSL tier (02-07)**. Awaiting user re-run of 02-04 Windows PyMOL smoke test to confirm runtime behavior (QListWidget populate on first show, Add/Edit/Remove/Use-bundled-pool/Choose-random buttons, QMessageBox on invalid, cmd.count_atoms, QSpinBox.setMaximum are WSL-unverifiable).

### Wave 4 outputs (02-07 gap closure — STILL AVAILABLE; UI-only enhancement)

- **gui_setup.py (552 -> 581 lines)**: 02-07 added a "Choose random" button (`self.pool_choose_btn`, QPushButton) as the 5th button in the pool button row (inside the pool QGroupBox, visually associated with the pool — not with the main Reset/Randomize/Save/Load Setup actions). Wired `pool_choose_btn.clicked -> _choose_random_from_pool` slot. The slot picks `random.choice(self._pool_list() or list(PDB_POOL))`, switches `mode_combo` to index 1 (fetch) so the field is visible, sets `pdb_edit` to the chosen code; returns early if both lists empty (defensive — PDB_POOL has 33 entries so unreachable). Does NOT touch any other setup field (hider count, lock scene, per-rep, difficulty, lock source, demo, loaded object) — focused, single-purpose. `import random` added at module level (line 15, next to `import json`). PDB_POOL import (line 22, from 02-06) verified present, not re-added. NO pure-layer change; NO new test (UI-only behavior; pre-existing 90 tests pin the pure layer).

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- [Roadmap]: PyMOL plugin (PyQt5 via `pymol.Qt`) is v1; VMD tcl is v2 — phased delivery
- [Roadmap]: Phase order de-risks object mutation (Phase 3) BEFORE generators, ships sphere MVP (Phase 4) ASAP
- [Roadmap]: Cartoon/ribbon generators (Phase 5) flagged as highest-risk / highest-research area
- [Roadmap]: Hider sentinels `segi='GAME'` + `b=-999` are the cleanup-safety and session-reload mechanism
- [Phase 1]: PluginDialog lives in `__init__.py`; all GUI modules use `from pymol.Qt import` (never raw PyQt5); dialog is modeless `.show()`
- [02-01]: GAME_REPS and DEMO_MANIFEST live in setup_state.py (pure layer); demos.py imports FROM it
- [02-02]: PDB filenames lowercase, package-relative under biochemeleon/data/demos/
- [02-03]: hider_count_cap imported from setup_state (NOT demos) — single source of truth for pure layer
- [02-03]: apply_state uses a _loading flag (not blockSignals) to suppress cascading signal handlers during programmatic state application — ensures Save->Load round-trips verbatim
- [02-03]: demos.py is the cmd-coupled bridge; gui_setup.py imports FROM setup_state (pure) AND demos (cmd bridge) — never the reverse
- [02-03]: load_demo imported by gui_setup per key_links API contract but not called in Phase 2 (demo loading deferred to Phase 4 Start button)
- [02-05]: PDB_POOL = 33 verified RCSB entries (curled 2026-08-05; all HEADER + ATOM + <6000 atoms); plan prose said "34" but the actual list + category breakdown (6+14+3+4+6) both sum to 33 — used the list verbatim, did NOT add an unverified 34th entry (AGENTS.md "all claims verified" rule)
- [02-05]: _validate_pdb_pool enforces 4-char alnum (PDB_POOL convention); _validate_pdb_code accepts 3-5 for general code validation (robustness for legacy/extended IDs) — **SUPERSEDED by 02-06** (tightened to exactly 4-char; the 3-5 tolerance let 5-char entries pass the code validator only to be silently dropped by the pool validator)
- [02-05]: Empty pdb_pool user input -> DEFAULTS pool (not []); an empty pool signals "use defaults" and the randomize re-roll relies on a non-empty pool internally
- [02-05]: Per-rep-sum clamp uses insertion order (dicts preserve order in 3.6+) — keeps first entries, drops overflow (deterministic, predictable)
- [02-05]: lock_source=True without locked_state -> falls back to lock_source=False (defensive; UI always passes collect_state() when checkbox checked)
- [02-06]: _validate_pdb_code tightened to EXACTLY 4-char lowercase alphanumeric (drops 3-5 tolerance) — PDB IDs are 4 chars by format; the 3-5 tolerance caused silent loss (5-char "12345" passed the code validator but was dropped by _validate_pdb_pool). _validate_pdb_pool's len==4 check kept for defense-in-depth (redundant but harmless). PDB_POOL (33 entries) UNCHANGED.
- [02-06]: Pool editor is a QListWidget (ExtendedSelection) inside a QGroupBox "Pool of PDB IDs (Randomize picks fetch codes from here)" + 4 buttons (+ Add, ✎ Edit, − Remove, Use bundled pool) — list semantics match the affordance (the QPlainTextEdit read as "might be a dropdown" but was free-text). Add/Edit validate via _validate_pdb_code BEFORE entry + QMessageBox.warning on invalid — invalid IDs never enter the list (no silent loss on Save/Load round-trip). No reorder buttons (out of scope).
- [02-06]: _randomize left UNCHANGED per the plan (it already calls self._pool_list() which now reads from the QListWidget — behavior identical). Its docstring still references "pool_edit text area" (stale, but plan-protected — "do NOT touch _randomize").
- [02-07]: "Choose random" button placed INSIDE the pool QGroupBox's button row (5th button after + Add / ✎ Edit / − Remove / Use bundled pool), NOT with the main Setup actions — per the user's enhancement spec, the button is visually associated with the pool it picks from. Empty pool falls back to list(PDB_POOL) (mirrors the 02-05 randomize_state convention that empty pool = use bundled pool; never produces an empty pdb_code box). mode_combo.setCurrentIndex(1) triggers _on_mode_changed -> target_stack.setCurrentIndex(1) only; it does NOT trigger _on_target_changed (wired to obj_combo/demo_combo, not mode_combo) so the hider-count cap recompute is NOT triggered — focused, single-purpose. import random at module level (not local); PDB_POOL import (02-06, line 22) verified, not re-added. No new test (UI-only; runtime behavior deferred to 02-04 smoke test).

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 5]: Cartoon/ribbon hider geometry is genuinely novel (no reference plugin) — likely to need a research spike and is the most likely phase to slip into a sub-phase or v1.x
- [Phase 9]: MemProtMD was unreachable at research time — per-entry license MUST be verified before bundling membrane coordinates
- [Cross-phase]: PyMOL Open Source has NO undo — every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (Phase 3 establishes this; all later phases rely on it)
- [02-04]: The `rep <name>` selector and the hider-count cap are WSL-unverifiable (need Windows PyMOL); the 02-04 smoke test is the formal confirmation (research 12.1 mitigation: per-rep try/except degrades gracefully)
- [02-05]: All 4 smoke-test gaps closed at WSL tier (pure tests + py_compile + grep gates); the cap recompute (Gap 1) and per-rep max bounding (Gap 2 UI) call cmd.count_atoms / QSpinBox.setMaximum at runtime — only the 02-04 smoke test re-run can confirm them. ROADMAP.md NOT updated (Phase 2 not complete until smoke test approved).
- [02-06]: Both pool-editor UX issues closed at WSL tier (90 tests + py_compile + grep gates); the QListWidget populate-on-first-show, Add/Edit/Remove/Use-bundled-pool button behavior, and QMessageBox on invalid input are WSL-unverifiable (need a live PyMOL Qt session) — only the 02-04 smoke test re-run can confirm them. ROADMAP.md NOT updated (Phase 2 not complete until smoke test re-approved after this fix).
- [02-07]: The "Choose random" button gap closure closed at WSL tier (90 tests + py_compile + grep gates + git diff stats confirming setup_state.py/tests/other modules/ROADMAP.md untouched); the button's live-Qt behavior (appears in the pool group; clicking it switches to fetch mode + populates the pdb_code field with a random pool entry; does not change any other field) is WSL-unverifiable — only the 02-04 smoke test re-run can confirm it. ROADMAP.md NOT updated (Phase 2 not complete until smoke test re-approved after this enhancement).

## Session Continuity

Last session: 2026-08-04 (Plan 02-07 executed — 1 enhancement: "Choose random" button added next to the pool buttons in gui_setup.py; picks random.choice(self._pool_list() or list(PDB_POOL)) into the fetch field, switches mode to fetch, does NOT touch any other field; import random at module level; UI-only, no pure-layer change, no new test, 90 tests pass)
Stopped at: Completed 02-07-PLAN.md. 1 task commit done (feat). Awaiting user re-run of 02-04 Windows PyMOL smoke test to confirm the Choose random button + the QListWidget pool editor + tightened validator at runtime.
Resume file: .planning/phases/02-setup-tab-configuration-bundled-demos/02-07-SUMMARY.md
