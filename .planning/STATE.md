# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-02)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** Phase 2 — Setup Tab Configuration & Bundled Demos (02-05 gap closure done; 02-04 smoke test re-run pending)

## Current Position

Phase: 2 of 10 (in progress — smoke test FAILED, gaps closed, re-run pending)
Plan: 4 of 5 in Phase 2 (02-05 gap closure done; 02-04 smoke test re-run is the gate to Phase 2 completion)
Status: 02-05 gap closure complete (WSL tier); awaiting user re-run of 02-04 Windows PyMOL smoke test
Last activity: 2026-08-04 — Completed 02-05-PLAN.md (4 gaps from 02-04 smoke test closed)

Progress: [█████████░] 90% (5/5 concrete plans: 01-01, 02-01, 02-02, 02-03, 02-05; 02-04 smoke test re-run pending)

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: ~13 min
- Total execution time: ~1.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1 | ~35 min | ~35 min |
| 2. Setup Tab Configuration & Bundled Demos | 4/5 | ~26 min | ~6.5 min |

**Recent Trend:**
- Last 5 plans: 01-01 ~35min, 02-01 ~2min, 02-02 ~1min, 02-03 ~4min, 02-05 ~19min
- Trend: 02-05 was slower (TDD RED->GREEN->UI fix + 32 new tests + 4 gap fixes); still WSL-only (no Windows PyMOL until 02-04 re-run)

*Updated after each plan completion*

## Accumulated Context

### Wave 1 outputs (02-01 + 02-02 — STILL AVAILABLE)

- **setup_state.py (Plan 02-01)**: GAME_REPS (5 reps), DEMO_MANIFEST (6 demos), DEFAULTS (9 keys), SETUP_FORMAT, hider_count_cap, randomize_state, validate_state. 48 unit tests pass.
- **data/demos/*.pdb (Plan 02-02)**: 6 valid PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) + SOURCES.md (64 lines, 6 DOIs). Git-tracked.

### Wave 2 outputs (02-03 — STILL AVAILABLE; extended by 02-05)

- **demos.py (137 lines)**: 5 cmd-coupled utilities — to_windows_path (WSL guard), list_loaded_molecule_objects, fetch_pdb (async_=0), get_active_reps (`rep <name>` selector), load_demo (__file__-relative + cmd.load). Imports GAME_REPS, DEMO_MANIFEST from setup_state. (UNCHANGED by 02-05)
- **gui_setup.py (390 -> 472 lines)**: full SetupTab — PyMOLObjectCombo, 3-mode QStackedWidget, capped hider spinbox, lock-scene auto-detect, 5 per-rep rows, difficulty toggle, 4 buttons, collect/apply round-trip, JSON save/load, randomize/validate. 02-05 added: current_target_object returns combo text (Gap 1), _recompute_per_rep_maxes (Gap 2 UI), lock_source_cb checkbox (Gap 3), pool_edit + _pool_list (Gap 4), _randomize passes lock_source/locked_state/pdb_pool.

### Wave 3 outputs (02-05 gap closure — JUST COMPLETED)

- **setup_state.py (169 -> 313 lines)**: PDB_POOL (33 verified RCSB entries — 6 bundled demos + 14 proteins + 3 DNA + 4 RNA + 6 hybrid; plan prose said "34" but the actual list + category breakdown both sum to 33, used verbatim), _validate_pdb_code/_validate_pdb_pool helpers, DEFAULTS extended to 11 keys (+ lock_source, pdb_pool), randomize_state(lock_source, locked_state, pdb_pool), validate_state per_rep-sum clamp + new-field validation. Module still pure (no pymol, no Qt).
- **tests/test_setup_state.py (244 -> 432 lines)**: 6 new test classes (TestPdbPool, TestDefaultsExtended, TestValidateStatePerRepSum, TestValidateStateNewFields, TestRandomizeLockSource, TestRandomizePdbPool) + TestDefaults.test_has_all_keys updated for 11-key schema. 80 tests pass (48 pre-existing + 32 new).
- **All 4 smoke-test gaps closed at WSL tier** (Gap 1 cap, Gap 2 per-rep sum, Gap 3 lock-source, Gap 4 pdb-pool). Awaiting user re-run of 02-04 Windows PyMOL smoke test to confirm the runtime behavior (cmd.count_atoms, QSpinBox.setMaximum are WSL-unverifiable).

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
- [02-05]: _validate_pdb_pool enforces 4-char alnum (PDB_POOL convention); _validate_pdb_code accepts 3-5 for general code validation (robustness for legacy/extended IDs)
- [02-05]: Empty pdb_pool user input -> DEFAULTS pool (not []); an empty pool signals "use defaults" and the randomize re-roll relies on a non-empty pool internally
- [02-05]: Per-rep-sum clamp uses insertion order (dicts preserve order in 3.6+) — keeps first entries, drops overflow (deterministic, predictable)
- [02-05]: lock_source=True without locked_state -> falls back to lock_source=False (defensive; UI always passes collect_state() when checkbox checked)

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 5]: Cartoon/ribbon hider geometry is genuinely novel (no reference plugin) — likely to need a research spike and is the most likely phase to slip into a sub-phase or v1.x
- [Phase 9]: MemProtMD was unreachable at research time — per-entry license MUST be verified before bundling membrane coordinates
- [Cross-phase]: PyMOL Open Source has NO undo — every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (Phase 3 establishes this; all later phases rely on it)
- [02-04]: The `rep <name>` selector and the hider-count cap are WSL-unverifiable (need Windows PyMOL); the 02-04 smoke test is the formal confirmation (research 12.1 mitigation: per-rep try/except degrades gracefully)
- [02-05]: All 4 smoke-test gaps closed at WSL tier (pure tests + py_compile + grep gates); the cap recompute (Gap 1) and per-rep max bounding (Gap 2 UI) call cmd.count_atoms / QSpinBox.setMaximum at runtime — only the 02-04 smoke test re-run can confirm them. ROADMAP.md NOT updated (Phase 2 not complete until smoke test approved).

## Session Continuity

Last session: 2026-08-04 (Plan 02-05 executed — 4 smoke-test gaps closed: PDB_POOL + lock_source + pdb_pool + per_rep-sum clamp in setup_state.py; current_target_object + _recompute_per_rep_maxes + lock_source_cb + pool_edit in gui_setup.py; 32 new tests, 80 total pass)
Stopped at: Completed 02-05-PLAN.md. All 3 task commits done (test/feat/fix). Awaiting user re-run of 02-04 Windows PyMOL smoke test to confirm the 4 runtime gaps.
Resume file: .planning/phases/02-setup-tab-configuration-bundled-demos/02-05-SUMMARY.md
