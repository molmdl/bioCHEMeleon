# Codebase Structure

**Analysis Date:** 2026-08-18

## Directory Layout

```
bioCHEMeleon/                      # repo root (git repo)
├── biochemeleon/                  # the importable plugin package (12 .py modules, FLAT — no subpackages)
│   ├── __init__.py                # COMPOSITION ROOT: __init_plugin__, PluginDialog, HELP_HTML, all button wiring
│   ├── setup_state.py             # PURE: game config schema, GAME_REPS, DEMO_MANIFEST, PDB_POOL, validation
│   ├── registry.py                # PURE: HiderRecord + HiderRegistry + sentinel reconstruction (DI)
│   ├── generators.py              # PURE: hider geometry (sphere/line-stick/cartoon positions + segment pick)
│   ├── persistence.py             # PURE: .bcm sidecar assembly + .bcmz archive I/O
│   ├── backup.py                  # cmd: snapshot/restore/discard/verify_intact
│   ├── mutation.py                # cmd: insert_hider/fetch_all_hider_ids/cleanup_hiders + per-rep dispatchers
│   ├── demos.py                   # cmd: demo loader + WSL→Windows path + fetch_pdb + get_active_reps
│   ├── wizard.py                  # cmd: PickWizard (Wizard subclass) — click→on_pick bridge
│   ├── game.py                    # cmd orchestrator: GameController (composition root of cmd layer)
│   ├── gui_setup.py               # Qt+cmd: SetupTab + PyMOLObjectCombo
│   ├── gui_game.py                # Qt: GameTab (rolling log/timer/remaining/countdown/win/debrief)
│   └── data/demos/                # 6 bundled demo PDBs + SOURCES.md (committed)
├── tests/                         # pure-layer unit tests (5 files; WSL-runnable via sys.modules stub)
│   ├── __init__.py
│   ├── test_setup_state.py
│   ├── test_registry.py
│   ├── test_generators.py
│   ├── test_persistence.py
│   └── test_game_controller.py
├── smoke/                         # PyMOL smoke + diagnostic scripts (run headlessly via Windows cmd.exe)
├── .planning/                     # GSD workflow — the source of truth for scope/state
│   ├── PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md, config.json
│   ├── research/                  # ARCHITECTURE.md, STACK.md, PITFALLS.md, FEATURES.md, SUMMARY.md
│   ├── phases/<NN-name>/         # NN-MM-PLAN.md + NN-MM-SUMMARY.md per plan (11 phases + 4.1)
│   ├── codebase/                  # ← THIS analysis (ARCHITECTURE.md, STRUCTURE.md)
│   ├── debug/                     # pending/ + resolved/ debug notes
│   └── quick/                     # quick-task subdirs (e.g. 001-parallel-execution-...)
├── Pymol-script-repo/             # GIT-IGNORED reference plugins (learning material)
├── tmp/                           # GIT-IGNORED (pymol-src mirror, staged Windows copies, exec worktrees)
├── 3rd_party_lib/                 # GIT-IGNORED vendored libs (if any approved)
├── setenv.bat                     # Windows cmd.exe: activates conda env chemtools-win10 (does NOT launch PyMOL)
├── run-conda-pymol.bat             # Windows: runs headless PyMOL with args (C:\src\run-conda-pymol.bat -cq <script>)
├── wsl2win_cp.sh                  # WSL bash: copies biochemeleon/ → tmp/bioCHEMeleon/ for Windows PyMOL
├── opencode.json                  # agent command denylist (pip*, apt*, conda*, rm*)
├── biochemeleon.zip               # GIT-IGNORED staged fallback install artifact
├── spec.md                        # project spec + constraints
├── AGENTS.md                      # high-signal agent notes (READ FIRST)
├── README.md                      # install + usage
├── DATA_SOURCES.md                # demo PDB source attributions
├── LICENSE                        # project license
└── LICENSE_pymol-open-source       # PyMOL open-source license
```

## Directory Purposes

**`biochemeleon/`:**
- Purpose: the importable PyMOL plugin package. Flat — all 12 modules are siblings (no `gui/`+`game/`+`pymol_io/` subpackages; the nested sketch in `.planning/research/ARCHITECTURE.md` was NOT the shipped shape).
- Contains: 12 `.py` modules + `data/demos/`.
- Key files: `__init__.py` (entry + GUI composition root), `game.py` (cmd orchestrator), `setup_state.py`+`registry.py`+`generators.py`+`persistence.py` (pure layer), `backup.py`+`mutation.py`+`demos.py`+`wizard.py` (cmd bridges), `gui_setup.py`+`gui_game.py` (Qt).

**`tests/`:**
- Purpose: WSL-runnable pure-layer unit tests (125 tests). Each file stubs `pymol`/`pymol.Qt` via `sys.modules` before importing `biochemeleon.*` (because `__init__.py` does `from pymol.Qt import ...` at module level).
- Contains: 5 `test_*.py` files + `__init__.py`.
- Key files: `test_setup_state.py` (90), `test_registry.py` (54), `test_generators.py` (21), `test_game_controller.py` (18), `test_persistence.py`.

**`smoke/`:**
- Purpose: PyMOL integration smoke tests + ad-hoc diagnostics. Pure `pymol.cmd.*` (NO Qt) so they run headlessly from WSL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`.
- Contains: `phase<N>_smoke.py` (per-phase round-trip verification), `diag_*.py` + `verify_*.py` (ad-hoc).
- Key files: `phase3_smoke.py` through `phase11_smoke.py`, `phase4_1_smoke.py`, `phase10_smoke.py`.

**`.planning/`:**
- Purpose: GSD ("get-shit-done") workflow — the source of truth for scope and state. Read before non-trivial work.
- Contains: `PROJECT.md`/`ROADMAP.md`/`STATE.md`/`REQUIREMENTS.md` (top-level), `research/` (verified PyMOL API behavior + pitfalls), `phases/<NN-name>/` (per-plan PLAN+SUMMARY), `codebase/` (this analysis), `debug/`, `quick/`.
- Key files: `.planning/research/PITFALLS.md` (load-bearing PyMOL pitfalls), `.planning/research/ARCHITECTURE.md` (composition-root rationale), `.planning/STATE.md` (current position — large file, read first ~200 lines only).

**`biochemeleon/data/demos/`:**
- Purpose: 6 bundled small demo PDBs (offline demos work without network) + source attributions.
- Contains: `1znf.pdb`, `1xdn.pdb`, `5e54.pdb`, `1k8p.pdb`, `2qbz.pdb`, `4wb3.pdb` + `SOURCES.md`.
- Generated: No. Committed: Yes (with sources in `SOURCES.md` + repo-root `DATA_SOURCES.md`).

**`Pymol-script-repo/` (GIT-IGNORED):**
- Purpose: reference open-source PyMOL plugins for learning how to write plugins (`optimize.py`, `outline.py`, `show_contacts.py`, etc. were consulted for the Qt/plugin patterns).
- Generated: No. Committed: No (gitignored).

**`tmp/` (GIT-IGNORED):**
- Purpose: the PyMOL 2.5.0 open-source module mirror (`tmp/pymol-src/modules/pymol/` — readable from any worktree via the main-repo absolute path for API verification), staged Windows-facing copies (`tmp/bioCHEMeleon/`), and parallel-execution worktrees (`tmp/exec-NN-MM`).
- Generated: Yes (by `wsl2win_cp.sh` / orchestrator worktree protocol). Committed: No.

## Key File Locations

**Entry Points:**
- `biochemeleon/__init__.py:129` — `__init_plugin__(app=None)` (PyMOL plugin loader entry).
- `biochemeleon/__init__.py:141` — `run_plugin_gui()` (lazy singleton dialog + modeless `show()`).
- `biochemeleon/__init__.py:160` — `PluginDialog` class (GUI composition root).

**Configuration:**
- `biochemeleon/setup_state.py` — `GAME_REPS` (5 reps), `DEMO_MANIFEST`, `PDB_POOL` (33 RCSB entries), `DEFAULTS` (11-key schema), `SETUP_FORMAT`, `TIER_LABELS`, `STRIP_RESN_MEMPROTMD`.
- `biochemeleon/backup.py` — `BACKUP_PREFIX = '_bchm_backup'`.
- `biochemeleon/game.py` — `HINT_RADIUS = 5.0`, `HINT_COLOR = 'orange'`.
- `opencode.json` — agent command denylist (`pip*`, `apt*`, `conda*`, `rm*`).
- `.planning/config.json` — GSD config (e.g. `parallelization`).

**Core Logic:**
- `biochemeleon/game.py:15` — `GameController` (cmd orchestrator; `start`/`on_pick`/`hint`/`reveal_one`/`reveal_all`/`win`/`cleanup`/`abort_on_error`/`import_state`/`reconstruct_registry`).
- `biochemeleon/registry.py:56` — `HiderRecord`; `:164` — `HiderRegistry`; `:515`/`:537` — `build_found_selection`/`group_found_by_rep`.
- `biochemeleon/mutation.py` — `insert_hider`/`insert_hider_for_rep`/`insert_line_stick_hider`/`insert_cartoon_hider`/`insert_cartoon_segment_hider`/`fetch_all_hider_ids`/`cleanup_hiders`/`cartoon_hider_resi_range`.
- `biochemeleon/backup.py` — `snapshot`/`restore`/`discard`/`verify_intact`.
- `biochemeleon/wizard.py:34` — `PickWizard` (click→`on_pick` bridge).
- `biochemeleon/generators.py` — `generate_sphere_positions`/`generate_line_stick_offsets`/`pick_terminal_residues`/`pick_segments`/`generate_middle_displacement`.

**GUI:**
- `biochemeleon/gui_setup.py:67` — `SetupTab`; `:47` — `PyMOLObjectCombo`.
- `biochemeleon/gui_game.py:18` — `GameTab` (rolling log + timer + remaining + countdown + win + debrief + found-hider management).
- `biochemeleon/__init__.py:14` — `HELP_HTML` (rich-text help shown in the modal `_show_help` QDialog).

**Testing:**
- `tests/test_setup_state.py`, `tests/test_registry.py`, `tests/test_generators.py`, `tests/test_persistence.py`, `tests/test_game_controller.py`.
- `smoke/phase3_smoke.py` … `smoke/phase11_smoke.py`, `smoke/phase4_1_smoke.py`, `smoke/phase10_smoke.py`.

**Build/Run Scripts:**
- `setenv.bat` — Windows conda env activator (does NOT launch PyMOL).
- `run-conda-pymol.bat` — Windows headless PyMOL launcher (`-cq` flags).
- `wsl2win_cp.sh` — WSL→Windows package stager.

## Naming Conventions

**Files (modules):**
- lowercase snake_case `.py`: `setup_state.py`, `gui_setup.py`, `gui_game.py`, `test_setup_state.py`.
- Pure-layer modules use single nouns/domains (`registry.py`, `generators.py`, `persistence.py`); cmd bridges use the verb/noun of their cmd role (`backup.py`, `mutation.py`, `demos.py`, `wizard.py`); GUI modules are prefixed `gui_` (`gui_setup.py`, `gui_game.py`).

**Package vs display name:**
- Importable package: lowercase `biochemeleon`. Display name shown to users: mixed-case `bioCHEMeleon` (window title, menu item, help HTML).

**Directories:**
- lowercase: `biochemeleon/`, `tests/`, `smoke/`, `.planning/`, `data/demos/`.
- Phase dirs use `NN-name-with-hyphens`: `.planning/phases/03-mutation-safety-hider-registry-foundation/`.

**Classes:**
- PascalCase: `PluginDialog`, `SetupTab`, `GameTab`, `PyMOLObjectCombo`, `GameController`, `HiderRecord`, `HiderRegistry`, `PickWizard`, `ReconcileMismatches`.

**Functions/methods:**
- snake_case: `__init_plugin__`, `run_plugin_gui`, `start`, `on_pick`, `mark_found`, `reconstruct_from_sentinels`, `build_bcm_dict`, `to_windows_path`, `insert_hider_for_rep`.
- Private/internal prefixed `_`: `_on_start`, `_prepare_and_start`, `_continue_after_large_demo_fetch`, `_resolve_large_demo`, `_mark_found`, `_show_help`, `_remaining`.

**Constants:**
- UPPER_SNAKE: `GAME_REPS`, `DEMO_MANIFEST`, `PDB_POOL`, `DEFAULTS`, `SETUP_FORMAT`, `BACKUP_PREFIX`, `HIDER_STATUS_HIDDEN`, `HIDER_STATUS_FOUND`, `HINT_RADIUS`, `HINT_COLOR`, `HELP_HTML`, `TIER_LABELS`, `STRIP_RESN_MEMPROTMD`.

**Tests:**
- `tests/test_<module>.py` mirrors the module under test (pure layer only): `test_setup_state`, `test_registry`, `test_generators`, `test_persistence`, `test_game_controller`.
- Test classes: `Test<Area>` (e.g. `TestHiderCountCap`, `TestGameControllerHintReveal`).

**Smoke scripts:**
- `smoke/phase<N>_smoke.py` — per-phase integration smoke (e.g. `phase3_smoke.py`, `phase4_1_smoke.py`, `phase10_smoke.py`).
- `smoke/diag_*.py` + `smoke/verify_*.py` — ad-hoc diagnostics/verifications.

## Where to Add New Code

**New pure logic (no pymol, no Qt — WSL-unit-testable):**
- Add to: `biochemeleon/setup_state.py` (config schema/validation/formatting), `biochemeleon/registry.py` (registry data model), `biochemeleon/generators.py` (geometry/selection), or `biochemeleon/persistence.py` (sidecar/archive).
- Tests: `tests/test_<module>.py` (mirror the module; use the `sys.modules` pymol/pymol.Qt stub pattern from `tests/test_registry.py`).
- Constraint: NO `from pymol import cmd` and NO `from pymol.Qt import` in these modules. Keep them WSL-unit-testable.

**New cmd-coupled bridge logic (calls `cmd.*`, standalone):**
- Add to: `biochemeleon/backup.py` (snapshot/restore lifecycle), `biochemeleon/mutation.py` (insertion/cleanup), `biochemeleon/demos.py` (demo loading + path utilities), or `biochemeleon/wizard.py` (click handling).
- Constraint: do NOT import sibling bridges (keep them standalone). A bridge MAY import from the pure layer (`from .setup_state import ...`) — bridge→pure is allowed; bridge→bridge is not.
- Verify via: a new section in `smoke/phase<N>_smoke.py` (pure `pymol.cmd.*`, headless-runnable) OR a new `smoke/diag_*.py`.

**New orchestrator logic (wires bridges + registry):**
- Add to: `biochemeleon/game.py` (`GameController` methods). Use DI to keep the registry pure (inject cmd-coupled callables as parameters, like `reconstruct_from_sentinels(iterate_fn)`).
- Tests: `tests/test_game_controller.py` (construct `GameController` WITHOUT calling `start()`; manually populate the registry; mock `cmd` + callbacks).

**New GUI (Qt widgets / button wiring):**
- New tab widget: a new `gui_<area>.py` module exposing a `QWidget` subclass; lazy-import it inside `PluginDialog.__init__` (mirrors `from .gui_setup import SetupTab` at `__init__.py:177`).
- New button on an existing tab: add the `QPushButton` in `gui_setup.py`/`gui_game.py` and wire `btn.clicked.connect(self._on_<verb>)` in `PluginDialog.__init__` (mirrors `self.setup_tab.start_btn.clicked.connect(self._on_start)` at `__init__.py:201`).
- Constraint: Qt imports via `from pymol.Qt import QtWidgets` ONLY (NEVER raw `PyQt5`). The main `PluginDialog` stays modeless (`dialog.show()`, NEVER `.exec_()`). Modal `.exec_()` is allowed ONLY on child `QMessageBox`/`QFileDialog`/`QDialog`.
- Verify via: a `smoke/phase<N>_smoke.py` section exercising the underlying cmd path (Qt itself needs a human-verify checkpoint in a real Windows PyMOL session).

**New utilities / shared helpers:**
- Pure helpers → the relevant pure module (`setup_state.py` / `registry.py`).
- cmd helpers → the relevant bridge (`backup.py` / `mutation.py` / `demos.py`).
- Cross-cutting constants → `setup_state.py` (the pure layer is the canonical home for `GAME_REPS`/`DEMO_MANIFEST` so pure functions can reference them without importing cmd-coupled modules).

**New demo PDBs:**
- Bundled (small): add the `.pdb` to `biochemeleon/data/demos/` + an entry in `DEMO_MANIFEST` (`setup_state.py`) + a citation in `biochemeleon/data/demos/SOURCES.md` and repo-root `DATA_SOURCES.md`.
- Fetched (large, MemProtMD/SASBDB): add a manifest entry with `source` field; cache is gitignored (fetched on demand by `demos.load_demo` → `_resolve_large_demo`).

## Special Directories

**`biochemeleon/data/demos/`:**
- Purpose: bundled small demo PDBs + `SOURCES.md` attributions.
- Generated: No. Committed: Yes.

**`.planning/research/`:**
- Purpose: verified PyMOL API behavior + the pitfalls behind the grep gates (read before non-trivial PyMOL work).
- Generated: No (research artifacts). Committed: Yes.

**`.planning/phases/<NN-name>/`:**
- Purpose: per-plan `NN-MM-PLAN.md` + `NN-MM-SUMMARY.md` (+ optional `RESEARCH.md`/`VERIFICATION.md`/`UAT.md`/`AUDIT.md`).
- Generated: Yes (by `/gsd-plan-phase` and `/gsd-execute-phase`). Committed: Yes (`commit_docs: true`).

**`.planning/debug/`:**
- Purpose: `pending/` + `resolved/` debug notes (e.g. `phase11-cartoon-ribbon-hider-keyerror.md`).
- Generated: Yes (during debugging). Committed: Yes.

**`.planning/quick/`:**
- Purpose: quick-task subdirs (`001-parallel-execution-worktree-protocol/`, `002-fix-rg-to-grep-in-agents-md/`).
- Generated: Yes (by `/gsd-quick`). Committed: Yes.

**`tmp/` (GIT-IGNORED):**
- Purpose: `pymol-src/` mirror (API verification), staged Windows copies (`bioCHEMeleon/`), parallel-exec worktrees (`exec-NN-MM`).
- Generated: Yes. Committed: No.

**`Pymol-script-repo/` (GIT-IGNORED):**
- Purpose: reference plugins consulted for Qt/plugin patterns.
- Generated: No. Committed: No.

**`3rd_party_lib/` (GIT-IGNORED):**
- Purpose: vendored approved libs (with license noted), if any non-PyMOL dependency is approved.
- Generated: No. Committed: No.

---

*Structure analysis: 2026-08-18*
