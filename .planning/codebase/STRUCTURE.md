# Codebase Structure

**Analysis Date:** 2026-09-08

## Directory Layout

```
bioCHEMeleon/                        # repo root (git repo) — multi-viewer monorepo
├── AGENTS.md                        # shared/environment agent notes (READ FIRST); points to viewer AGENTS.md
├── spec.md                          # project spec: gameplay + per-viewer requirements + demo list
├── pymol/                           # v1 PyMOL 2.5.0 plugin — SHIPPED, FROZEN
│   ├── AGENTS.md                    # v1 domain rules, commands, pitfall gates
│   ├── biochemeleon/                # the importable plugin package (12 flat .py modules)
│   │   ├── __init__.py              # COMPOSITION ROOT: __init_plugin__, PluginDialog, button wiring
│   │   ├── setup_state.py           # PURE: schema, GAME_REPS, DEMO_MANIFEST, validation
│   │   ├── registry.py              # PURE: HiderRecord/HiderRegistry + sentinel reconstruction (DI)
│   │   ├── generators.py            # PURE: hider geometry (sphere/line-stick/cartoon)
│   │   ├── persistence.py           # PURE: .bcm sidecar + .bcmz archive I/O
│   │   ├── backup.py                # cmd: snapshot/restore/discard/verify_intact
│   │   ├── mutation.py              # cmd: insert_hider (pseudoatom in-place) + per-rep dispatch
│   │   ├── demos.py                 # cmd: demo loader, fetch_pdb, to_windows_path
│   │   ├── wizard.py                # cmd: PickWizard (click→on_pick bridge)
│   │   ├── game.py                  # cmd orchestrator: GameController
│   │   ├── gui_setup.py             # Qt: SetupTab + PyMOLObjectCombo
│   │   ├── gui_game.py              # Qt: GameTab (log/timer/remaining/countdown/win)
│   │   └── data/demos/              # 6 bundled demo PDBs + SOURCES.md (CANONICAL demo set)
│   ├── tests/                       # pure-layer unittest suites (WSL-runnable via sys.modules stubs)
│   └── smoke/                       # phase*_smoke.py + diag_*.py diagnostics (headless via cmd.exe)
├── vmd/                             # v2 VMD 1.9.3 tcl script — ACTIVE milestone (v2.0)
│   ├── AGENTS.md                    # v2 domain rules (Tcl 8.5, PDB-rebuild, pick mechanism, gates)
│   ├── biochemeleon.tcl             # ENTRY: re-source guard + namespace + source chain + menu registration
│   ├── pkgIndex.tcl                 # optional packaged-install form (package ifneeded biochemeleon 2.0)
│   ├── wsl2win_cp.sh                # stages vmd/ → tmp/biochemeleon-vmd/ for headless Windows VMD
│   ├── lib/                         # 12 modules: 6 PURE + 5 mol bridges + 1 composition root
│   │   ├── setup_state.tcl          # PURE: GAME_REPS, DEMO_MANIFEST, validate/randomize, hider_count_cap
│   │   ├── registry.tcl             # PURE: hider registry (index-keyed) + DI sentinel reconstruction
│   │   ├── generators.tcl           # PURE: sphere_positions, bonded placement, seeded sample
│   │   ├── game_logic.tcl           # PURE: round state machine (idle→countdown→playing→won), timer, log
│   │   ├── rep_tiers.tcl            # PURE: N-tier dispatch (IMPLEMENTED_TIERS, TIER_KINDS, resolve_per_rep)
│   │   ├── splice.tcl               # PURE: residue-splice geometry (perp_vector, assemble_record, atom_record)
│   │   ├── demos.tcl                # mol: load_demo, fetch_pdb, to_vmd_path, save/load_setup
│   │   ├── backup.tcl               # mol: snapshot/apply/restore (viewpoint + reps + original PDB path)
│   │   ├── mutation.tcl             # mol: PDB-rebuild engine (make_*_hiders, write_combined_pdb, mutate)
│   │   ├── hiders.tcl               # mol: N-tier hidden/found rep pairs, stamp_tier_codes, mark_found_visual
│   │   ├── pick_bridge.tcl          # mol: pick_event trace → game::on_pick; labelpoll fallback; mouse modes
│   │   └── game.tcl                 # COMPOSITION ROOT: start_game (4-arg tier dispatch), cleanup, on_pick
│   ├── gui/                         # Tk+ttk layer (GUI-only; cannot run in -dispdev text)
│   │   ├── dialog.tcl               # open_dialog (modeless notebook), on_close, on_start
│   │   ├── setup_tab.tcl            # Setup tab: target/hiders/difficulty groups, collect/apply_state
│   │   └── game_tab.tcl             # Game tab: start_round, countdown, tick, on_log_line, on_win
│   ├── smoke/                       # 31 headless end-to-end smokes, phase-prefixed (phase13–17)
│   ├── tests/                       # 6 pure-layer tcltest suites + 2 GUI verify auto-drivers
│   └── data/demos/                  # copies of the 6 demo PDBs + SOURCES.md (reused from v1)
├── chimeraX/                        # EMPTY placeholder (.gitkeep) — future milestone candidate
├── .planning/                       # GSD workflow — source of truth for scope/state (committed)
│   ├── PROJECT.md / ROADMAP.md / STATE.md / REQUIREMENTS.md / config.json
│   ├── research/                    # STACK.md, ARCHITECTURE.md, PITFALLS.md, FEATURES.md, SUMMARY.md
│   ├── phases/<NN-name>/            # NN-MM-PLAN.md + NN-MM-SUMMARY.md (+ RESEARCH/VERIFICATION/UAT)
│   ├── milestones/                  # v1-ROADMAP.md, v1-REQUIREMENTS.md, v1-MILESTONE-AUDIT.md
│   ├── codebase/                    # ← THIS analysis (ARCHITECTURE.md, STRUCTURE.md, etc.)
│   ├── debug/ + quick/              # debug notes; quick-task rationale
├── Pymol-script-repo/               # GIT-IGNORED v1 reference plugins
├── vmd-ref/                         # GIT-IGNORED v2 reference (VMD UG PDF, bundled plugins, core scripts)
├── 3rd_party_lib/                   # GIT-IGNORED v1 vendored libs
├── vmd/3rd_party_lib/               # GIT-IGNORED v2 vendored libs (empty; tooltip.tcl NOT needed)
├── tmp/                             # GIT-IGNORED: biochemeleon-vmd/ staging, smoke logs, probe scripts
├── cache/                           # GIT-IGNORED
├── setenv.bat / run-conda-pymol.bat # Windows: conda env activation + headless PyMOL runner (v1)
├── wsl2win_cp.sh                    # root-level v1 staging script (→ tmp/bioCHEMeleon/)
├── opencode.json                    # agent command denylist (pip*, apt*, conda*, rm*)
├── README.md / DATA_SOURCES.md / LICENSE / LICENSE_pymol-open-source
├── bioCHEMeleon_v1*.zip             # GIT-IGNORED release artifacts
└── reg-*.log, splice-smoke-run*.log, dbg_pin.tcl   # scratch probes (repo-root litter; not part of the build)
```

## Directory Purposes

**`vmd/` (active milestone):**
- Purpose: the v2 VMD port — a sourced tcl extension, organized as `lib/` (engine) + `gui/` (Tk) + `smoke/` + `tests/` + `data/`.
- Contains: 1 entry script + `pkgIndex.tcl`, 12 lib modules, 3 GUI modules, 31 smokes, 8 test files, demo PDBs.
- Key rule: the entry (`vmd/biochemeleon.tcl`) sources the lib chain in a FIXED dependency order; `registry.tcl` is sourced exactly once.

**`vmd/lib/`:**
- Purpose: the game engine, split pure/mol by the strict dependency direction (see ARCHITECTURE.md).
- Purity split within the directory: `setup_state.tcl`, `registry.tcl`, `generators.tcl`, `game_logic.tcl`, `rep_tiers.tcl`, `splice.tcl` are PURE (no `mol`, no `tk`); `demos.tcl`, `backup.tcl`, `mutation.tcl`, `hiders.tcl`, `pick_bridge.tcl` are mol bridges; `game.tcl` is the composition root (sources nothing).

**`vmd/smoke/`:**
- Purpose: headless end-to-end verification of mol-coupled behavior (pure tcl cannot prove `mol`/`atomselect` semantics). Run from the staged copy `tmp/biochemeleon-vmd/`.
- Contains: 31 scripts, phase-prefixed: `phase13_*` (entry bootstrap), `phase14_*` (setup/mol bridges), `phase15_*` (backup/mutation/registry/game), `phase16_*` (core loop: entry/gametab/hiders/onpick/pick/placement/restart), `phase17_*` (tiers: bonded/cartoon/capstone/cpk/dispatch/dynbonds/e2e/licorice/lines/newcartoon/points/residue_dispatch/splice/tiers/trace/tube).
- Pattern: each smoke sources the lib files in dep order directly (mirrors the entry, NOT the entry itself — avoids GUI/dialog baggage), asserts with PASS/FAIL prints, and must end `Exiting normally` with 0 `ERROR)` / bad-switch lines in the log.

**`vmd/tests/`:**
- Purpose: pure-layer unit suites + GUI verification drivers.
- Contains: 6 tcltest suites (`test_setup_state.test` 47, `test_registry.test` 37, `test_generators.test` 26, `test_rep_tiers.test` 49, `test_game_logic.test` 15, `test_splice.test` 31 — 205 tests total) + 2 Tk-guarded auto-drivers (`pick_verify.tcl` — Phase-16 pick checkpoint, superseded by `rep_verify.tcl`; `rep_verify.tcl` — the consolidated 17.1/17.2 GUI rep-verify driver with `pv_round2`/`pv_round3`/`pv_report`/`pv_cleanup` commands).

**`vmd/data/demos/`:**
- Purpose: committed copies of the 6 demo PDBs (`1k8p` `1xdn` `1znf` `2qbz` `4wb3` `5e54`) + `SOURCES.md`. PDBs are viewer-agnostic; the canonical source set lives in `pymol/biochemeleon/data/demos/`.

**`pymol/` (shipped, frozen):**
- Purpose: v1 plugin. Flat package `pymol/biochemeleon/` (12 sibling modules — no subpackages), plus `tests/` (5 pure suites, WSL-runnable) and `smoke/` (headless scripts + `diag_*.py` diagnostics).
- Reference for v2: `pymol/AGENTS.md` documents the original pitfall gates; v2 mirrors its layering 1:1 in tcl.

**`.planning/`:**
- Purpose: GSD workflow state — `PROJECT.md`, `ROADMAP.md` (v1 ✅ / v2.0 phases 13-23 🚧 / chimeraX candidate), `STATE.md` (current position: Phase 17.2, 12/12 plans built, GUI checkpoint pending), `REQUIREMENTS.md` (54 v2 reqs), `research/` (verified VMD API behavior + pitfalls), `phases/<NN-name>/` (per-plan PLAN/SUMMARY/RESEARCH/VERIFICATION docs), `milestones/` (v1 archive), `codebase/` (this analysis).

**`chimeraX/`:**
- Purpose: empty placeholder for a future ChimeraX port (per `.planning/ROADMAP.md`). Contains only `.gitkeep`. No research, no code.

## Key File Locations

**Entry Points:**
- `vmd/biochemeleon.tcl`: v2 entry — guard, namespace, source chain, `biochemeleon` console proc, `biochemeleon_tk_cb`, `vmd_install_extension ... "Visualization/bioCHEMeleon"`.
- `vmd/pkgIndex.tcl`: optional `package require` install form.
- `vmd/gui/dialog.tcl`: `open_dialog` (what the menu item actually calls).
- `pymol/biochemeleon/__init__.py`: v1 entry (`__init_plugin__`, `run_plugin_gui`, `PluginDialog`).

**Configuration:**
- `vmd/lib/setup_state.tcl`: `GAME_REPS` (10 reps), `SETUP_FORMAT`, `DEFAULTS`, `DEMO_MANIFEST` (the schema constants every other module reads).
- `vmd/lib/rep_tiers.tcl`: `IMPLEMENTED_TIERS` + `TIER_KINDS` + `style_args` (the per-tier generator routing table).
- `vmd/lib/splice.tcl`: splice constants (`RESID_BASE 9001`, `SPLICE_DISPLACEMENT 1.0`, `MIN_ANCHOR_SEP 5.0`).
- `vmd/lib/mutation.tcl`: sentinel constants (`HID_RESNAME GAM`, `HID_BETA -999`, `HID_SEGID GAME`).
- `vmd/lib/generators.tcl`: bonded-placement constants (`D_MIN 1.2`, `D_MAX 1.6`, `MIN_SEP_HIDER 4.0`).
- `spec.md`, `AGENTS.md` (root), `vmd/AGENTS.md`, `pymol/AGENTS.md`: requirements + constraints.

**Core Logic:**
- `vmd/lib/game.tcl`: the round lifecycle + pick scoring (`start_game`/`cleanup`/`restart`/`on_pick`/`_resolve_pick`).
- `vmd/lib/mutation.tcl`: the PDB-rebuild engine (the v1→v2 keystone).
- `vmd/lib/registry.tcl`: hider state (single source of truth).
- `vmd/lib/pick_bridge.tcl`: click delivery mechanism.

**Testing:**
- Pure suites: `vmd/tests/test_*.test` (tcltest; run via `tclsh` in WSL or the staged headless VMD suite driver).
- Smokes: `vmd/smoke/phase*_smoke.tcl` (headless VMD on the staged copy).
- GUI drivers: `vmd/tests/rep_verify.tcl` (current), `vmd/tests/pick_verify.tcl` (superseded, unrepaired).
- v1 tests: `pymol/tests/test_*.py`; v1 smokes: `pymol/smoke/*.py`.

## Naming Conventions

**Files:**
- tcl modules: `snake_case.tcl`, one namespace per file, module name == namespace suffix (`vmd/lib/rep_tiers.tcl` → `::biochemeleon::rep_tiers`).
- v2 smokes: `phase<NN>_<topic>_smoke.tcl` (e.g. `phase17_residue_dispatch_smoke.tcl`); GUI drivers: `<name>_verify.tcl`.
- v2 unit suites: `test_<module>.test` (tcltest, NOT `.tcl`).
- v1 modules: `snake_case.py`, flat package; v1 tests: `test_<module>.py`; v1 smokes: `phase<NN>_smoke.py` + `diag_<topic>.py`.

**Namespaces:**
- Everything v2 lives under `::biochemeleon::*` — one child namespace per module: `::biochemeleon::setup_state`, `::biochemeleon::registry`, `::biochemeleon::generators`, `::biochemeleon::game_logic`, `::biochemeleon::rep_tiers`, `::biochemeleon::splice`, `::biochemeleon::demos`, `::biochemeleon::backup`, `::biochemeleon::mutation`, `::biochemeleon::hiders`, `::biochemeleon::pick_bridge`, `::biochemeleon::game`, `::biochemeleon::setup_tab`, `::biochemeleon::game_tab`; dialog-level procs (`open_dialog`, `on_start`, `on_close`) sit directly in `::biochemeleon`.
- Global user command: `biochemeleon` (unqualified, defined by the entry).
- Every namespace declares `namespace export <public procs>` — the export list documents the public contract (callers use fully-qualified names; `namespace import` is not used in production code).

**Procs:** `snake_case`; private helpers prefixed `_` (`_resolve_pick`, `_on_event`, `_hider_record`, `_cross`); GUI builders `build_*`; widget handlers `do_*`/`on_*`.

**Constants:** `UPPER_SNAKE` namespace variables, one `variable` declaration per line (the multi-name `variable a b` form is a scalar set, not two declarations — the 14-04 lesson).

## Where to Add New Code

**New pure module (v2):**
- Implementation: `vmd/lib/<name>.tcl` — stdlib tcl 8.5 ONLY (no `mol`, no `tk`, no 8.6 idioms), `namespace eval ::biochemeleon::<name>`, `namespace export` the contract.
- Wire-up: add ONE `source [file join $_dir lib <name>.tcl]` line in `vmd/biochemeleon.tcl` in the PURE block (before the mol bridges) if the mol layer must call it; state the dependency in the module header comment.
- Tests: `vmd/tests/test_<name>.test` (tcltest; source under `[file join [pwd] vmd lib <name>.tcl]` — under `vmd -e`, `[info script]` is EMPTY).

**New representation tier (v2):**
- Tier table: add the rep to `IMPLEMENTED_TIERS` + `TIER_KINDS` in `vmd/lib/rep_tiers.tcl` and to `style_args` (explicit cutoff args if any).
- Generator: a `make_<kind>_hiders`-style proc in `vmd/lib/mutation.tcl` (or extend the existing one); pure geometry goes in `vmd/lib/generators.tcl`/`splice.tcl`.
- Dispatch: extend the per-tier loop in `vmd/lib/game.tcl::start_game` (steps 4–14) if introducing a NEW kind; new tiers of an EXISTING kind need no game.tcl change (the tables drive it).
- Verify: tier smoke `vmd/smoke/phase<NN>_<rep>_smoke.tcl` + suite updates in `vmd/tests/test_rep_tiers.test` (re-probe the pinned PRNG seeds — any domain widening changes every draw).

**New GUI tab/panel (v2):**
- Implementation: `vmd/gui/<name>_tab.tcl`, namespace `::biochemeleon::<name>_tab`, `build {parent}` entry proc.
- Wire-up: `source` it at the TOP LEVEL of `vmd/gui/dialog.tcl` (NEVER inside a proc body — `[info script]` is empty at call time) and add the tab to the notebook in `open_dialog`.

**New mol-bridge capability (v2):**
- Implementation: extend the owning bridge (`demos.tcl` for loading/paths, `backup.tcl` for scene state, `mutation.tcl` for atom/PDB changes, `hiders.tcl` for reps/visuals, `pick_bridge.tcl` for input) — do NOT create cross-bridge imports; if two bridges need shared logic, it belongs in the pure layer or `game.tcl`.

**New smoke (v2):**
- Location: `vmd/smoke/phase<NN>_<topic>_smoke.tcl`; copy the newest smoke's harness structure (source chain in dep order, PASS/FAIL counters, `Exiting normally`). Run it from the staged copy: `bash vmd/wsl2win_cp.sh` then `bash -ic "cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/<file> -eofexit < /dev/null"`.

**New demo PDB:**
- Canonical: `pymol/biochemeleon/data/demos/` + attribution in `pymol/biochemeleon/data/demos/SOURCES.md` (human-approved sources only); copy into `vmd/data/demos/` and add the entry to `DEMO_MANIFEST` in `vmd/lib/setup_state.tcl` (and v1's `setup_state.py` if shipped in both).

**Utilities:**
- Shared pure helpers (math, list/dict): the owning pure module (`generators.tcl` geometry, `splice.tcl` vector math, `setup_state.tcl` list sampling) — keep private helpers `_`-prefixed and unexported.

**v1 additions:** only if a shipped-v1 bug warrants a fix — the milestone is frozen; `pymol/AGENTS.md` gates apply.

## Special Directories

**`tmp/`:**
- Purpose: headless-run staging and artifacts — `tmp/biochemeleon-vmd/` (the staged `vmd/` copy that Windows VMD runs from; the ONLY cwd headless smokes/suites run from), smoke logs, probe scripts, v1 staging (`tmp/bioCHEMeleon/`), `tmp/pymol-src/` (v1 API reference mirror).
- Generated: Yes (rebuild with `bash vmd/wsl2win_cp.sh` / `bash wsl2win_cp.sh`). Committed: NO (git-ignored).

**`vmd-ref/`:**
- Purpose: VMD 1.9.3 reference material — `ug.pdf` (User's Guide), `plugins/` (5 curated bundled tcl plugins: clonerep, ramaplot, autoionize, viewmaster, mergestructs — the extension-pattern references), `scripts/` (17 VMD core tcl scripts), `tooltip/` (tklib tooltip, license reference only). Use THESE paths in plans, never `/mnt/c/Program Files (x86)/...`.
- Generated: No. Committed: NO (git-ignored; UIUC license).

**`vmd/3rd_party_lib/` and `3rd_party_lib/`:**
- Purpose: vendored external libs if ever user-approved (v2 currently needs NONE — tooltip.tcl is not needed).
- Generated: No. Committed: NO (git-ignored); any vendored lib must ship its license terms.

**`Pymol-script-repo/`:**
- Purpose: v1 learning reference (community plugins). Generated: No. Committed: NO.

**`pymol/smoke/__pycache__/`, `pymol/tests/__pycache__/`:**
- Python bytecode. Generated: Yes. Committed: NO (`*.pyc` ignored).

**Repo-root scratch (`reg-*.log`, `splice-smoke-run*.log`, `dbg_pin.tcl`, `bioCHEMeleon_v1*.zip`):**
- Probe/debug litter from 17.2 sessions and release artifacts; NOT part of any build or test path. The zips are git-ignored; the logs/dbg_pin.tcl are currently untracked scratch — do not import from them.

---

*Structure analysis: 2026-09-08*
