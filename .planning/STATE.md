# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-02)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** Phase 3 — Mutation Safety & Hider Registry Foundation (in progress, Wave 1)

## Current Position

Phase: 3 of 10 (Mutation Safety & Hider Registry Foundation)
Plan: 03-01 + 03-02 complete (2 of 20 Phase 3 plans summarized; Wave 1 parallel — 03-03 may be concurrent)
Status: In progress
Last activity: 2026-08-05 — Completed 03-01-PLAN.md (registry.py HiderRecord + HiderRegistry core CRUD; 03-02 also complete)

Progress: [████░░░░░░] 36%

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: ~12 min
- Total execution time: ~1.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1 | ~35 min | ~35 min |
| 2. Setup Tab Configuration & Bundled Demos | 6/6 + 02-06 + 02-07 gap closures | ~31 min | ~4 min |
| 3. Mutation Safety & Hider Registry Foundation | 2/20 (03-01, 03-02) | ~3 min | ~1.5 min |

**Recent Trend:**
- Last 9 plans: 01-01 ~35min, 02-01 ~2min, 02-02 ~1min, 02-03 ~4min, 02-05 ~19min, 02-06 ~4min, 02-07 ~1min, 03-02 ~1min, 03-01 ~2min
- Trend: 03-01 was the TDD pure-layer registry foundation (biochemeleon/registry.py: HiderRecord + HiderRegistry core CRUD register/get/all/remove, 148 lines, stdlib+GAME_REPS only — NO pymol import; keyed by (object, atom_id) per Pitfall 4; __slots__ + OrderedDict + int coercion). 33 unit tests pass; 123 total (90 setup_state + 33 registry). 1 in-task fix (walrus `:=` is 3.8+; python3.6 is 3.6.9 — replaced with plain assertEqual). All WSL gates green. 03-02 (backup.py snapshot+discard) ran concurrently; files disjoint (backup.py vs registry.py+test_registry.py) — no conflict.

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

### Phase 3 Wave 1 outputs (03-02 — STILL AVAILABLE; cmd-coupled, standalone)

- **backup.py (41 lines, NEW)**: cmd-coupled backup module (standalone — no import of setup_state/registry/mutation; mirrors demos.py's `from pymol import cmd` + section-comment style). `BACKUP_PREFIX = '_bchm_backup'` (underscore => private, hidden from `cmd.get_names('public_objects')` per RESEARCH Q6). `snapshot(target_obj)` = `cmd.delete(BACKUP_PREFIX)` (idempotent stale-backup discard) + `cmd.create(BACKUP_PREFIX, target_obj)` (fresh independent deep copy, creating.py:960) + return backup name. `discard(backup_name=BACKUP_PREFIX)` = `cmd.delete(backup_name)` (idempotent — safe on absent objects). `restore()` and `verify_intact()` deliberately NOT added (plans 03-05 + 03-08). 1 Rule-3 auto-fix: reworded the module docstring NOTE from `` `from pymol import cmd` will FAIL `` to "The pymol.cmd import will FAIL" to avoid a false-positive `from pymol` grep match (mirrors the AGENTS.md-documented "from PyQt5 import" docstring false positive). All WSL gates green (py_compile biochemeleon/*.py + 90 tests + Pitfall-1/11 grep gates zero matches). Runtime (cmd.delete/cmd.create deep-copy independence, idempotent delete, underscore-prefix privacy) deferred to the Phase 3 smoke test (plans 03-13/03-14, run via 03-15 checkpoint).

### Phase 3 Wave 1 outputs (03-01 — STILL AVAILABLE; pure-layer, WSL-tested)

- **registry.py (148 lines, NEW)**: HiderRegistry pure data model — stdlib + `setup_state.GAME_REPS` only (NO `from pymol`, NO `from pymol.Qt`), WSL-unit-testable, mirroring setup_state.py. `HIDER_STATUS_HIDDEN='hidden'` + `HIDER_STATUS_FOUND='found'` constants. `HiderRecord` with `__slots__=('id','object','rep','status','pos')`; `__init__` validates `rep in GAME_REPS` (ValueError else — 'surface' out of scope) + coerces `id` to int; `key()` returns `(self.object, self.id)`; `to_dict()` omits `pos` when None, includes it as a list when set. `HiderRegistry` with `OrderedDict`-backed store keyed by `(object, id)` (Pitfall 4: id stable across add/remove; index is not); `register()` raises KeyError on duplicate `(object,id)`, returns HiderRecord; `get()` returns record or None; `all()` returns a fresh insertion-order list; `remove()` returns True then False (idempotent — never raises on absent). All three of register/get/remove coerce id to int (str '1' ↔ int 1 round-trip). Core CRUD only — `by_rep`/`counts_by_rep`/`mark_found` (03-02 research-wave) + `reconstruct_from_sentinels`/`to_dict`/`from_dict` (03-03) deliberately deferred per plan. 33 unit tests pass (TestHiderRecord + TestHiderRegistryCore); 123 total (90 setup_state + 33 registry). All WSL gates green (py_compile + tests + purity `from pymol` zero matches in registry.py + Pitfall-1/11 zero matches). No runtime/PyMOL behavior to defer — pure layer is fully verified at WSL tier.

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
- [03-02]: backup.py snapshot = delete-then-create (`cmd.delete(BACKUP_PREFIX)` to discard any stale backup, then `cmd.create(BACKUP_PREFIX, target_obj)` for a fresh independent deep copy) — unambiguous; no merge-vs-replace question (RESEARCH Q2 flagged single-call `cmd.create(existing, other)` as UNVERIFIED C-side; the snapshot direction creates a fresh name so no merge question, but deleting stale first guarantees cleanliness even if a prior game crashed without discarding). `BACKUP_PREFIX='_bchm_backup'` underscore-prefixed so it's hidden from `public_objects`. `discard` is idempotent (`cmd.delete` safe on absent objects). `restore` (03-05) + `verify_intact` (03-08) deliberately deferred — snapshot+discard subset only per plan scope.
- [03-01]: Registry keyed by `(object, id)` tuple, NOT `id` alone — future-safe for multi-target-object games (Pitfall 4 lock; ids are per-object; the tuple is the stable primary key). HiderRecord uses `__slots__=('id','object','rep','status','pos')` (compact + AttributeError on typos). OrderedDict (not plain dict) for the store — explicit insertion-order contract even on Python 3.6 (plain-dict order is an impl detail, not language-guaranteed). Int coercion on `id` at register/get/remove (str '1' ↔ int 1 round-trip; defensive for cmd.identify results + deserialized sidecar strings). `to_dict` omits `pos` when None, includes it as a list when set (compact Phase 8 .bcm sidecar). `register` raises KeyError on duplicate (caller bug); `remove` idempotent (False on absent, never raises). Core CRUD only — by_rep/counts_by_rep/mark_found + reconstruct_from_sentinels/to_dict/from_dict deferred to 03-02/03-03 per plan.

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
- [03-02]: backup.py is cmd-coupled — `cmd.delete`/`cmd.create` behavior (deep-copy independence, idempotent delete on absent objects, underscore-prefix privacy in `public_objects`) is WSL-unverifiable (no PyMOL in WSL; py_compile is syntax-only). Only the Phase 3 smoke test (plans 03-13/03-14, run via 03-15 Windows PyMOL checkpoint) can confirm runtime behavior. The RESEARCH Q2 MEDIUM flag (cmd.create merge-vs-replace) does NOT affect snapshot (fresh-name create) — it only affects the restore path (plan 03-05, which uses delete+create to sidestep it).
- [03-01]: registry.py is PURE and FULLY verified at WSL tier (no runtime/PyMOL behavior to defer — 33 unit tests + py_compile + purity + Pitfall-1/11 gates all green). No blocker. One in-task fix: walrus `:=` is Python 3.8+; python3.6 is 3.6.9 — reaffirms the AGENTS.md constraint to avoid 3.7+ syntax (walrus, f-string `=`, positional-only params). Parallel Wave 1 execution (03-01/03-02 observed committing concurrently; 03-03 may also be in flight) — files are disjoint across the three Wave-1 tracks (registry.py / backup.py / mutation.py), so no merge conflict; STATE.md is the only shared file (last writer wins; phase not "complete" until all 20 plans summarize).

## Session Continuity

Last session: 2026-08-05 (Plan 03-01 executed — TDD pure-layer registry foundation: biochemeleon/registry.py HiderRecord + HiderRegistry core CRUD register/get/all/remove, 148 lines, stdlib+GAME_REPS only — NO pymol import; keyed by (object, atom_id) per Pitfall 4; __slots__ + OrderedDict + int coercion; to_dict omits pos when None. 33 unit tests pass (123 total). RED→GREEN→REFACTOR; REFACTOR produced no commit (code clean). All WSL gates green. 03-02 ran concurrently; files disjoint.)
Stopped at: Completed 03-01-PLAN.md. 2 task commits done (test 3811370, feat 7236dfc). Phase 3 Wave 1 in progress (03-02 also complete; 03-03 may be concurrent — parallelization enabled).
Resume file: .planning/phases/03-mutation-safety-hider-registry-foundation/03-01-SUMMARY.md
