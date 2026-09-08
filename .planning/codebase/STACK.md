# Technology Stack

**Analysis Date:** 2026-09-08

## Languages

**Primary:**
- **Tcl 8.5.6** (exact patchlevel, verified three ways: `tcl85.dll`, `info patchlevel`, `scripts/8.5.6/` dir) — the ACTIVE v2 viewer game. Lives in `vmd/` (~5,200 lines: `vmd/lib/*.tcl` + `vmd/gui/*.tcl` + `vmd/biochemeleon.tcl`). Tcl 8.5.6 constraint is hard: `dict`, `lassign`, `lreverse`, `apply`, `trace add/remove`, `expr **`, `namespace ensemble` are available; **NO** `try`/`throw`/`finally`/`tailcall`/`coroutine`/`yield`/`lmap` (Tcl 8.6 idioms — use `catch`/`error` + `foreach`+`lappend`). Enforced by the grep gate below.
- **Python 3.6.9** — the SHIPPED v1 PyMOL plugin (`pymol/biochemeleon/`, 12 modules, ~5,800 lines, frozen since 2026-08-22). Two interpreters matter: WSL `python3.6` (3.6.9, syntax checks + pure-layer unit tests ONLY) and the conda PyMOL-bundled Python (≥3.6, the actual runtime that imports `pymol.cmd`, `pymol.Qt`, `pymol.wizard`, `pymol.editor`, `pymol.plugins`).

**Secondary:**
- Bash (WSL dev shell) — test runners, staging scripts (`vmd/wsl2win_cp.sh`, pymol-side staging).
- Windows cmd.exe batch — conda env activation + headless host invocation (`setenv.bat`, `C:\src\run-conda-pymol.bat`).
- `tcltest` — Tcl's built-in test framework, used for v2 pure-layer suites.

## Runtime

**Environment (triple-environment split — the defining constraint of this repo):**

1. **WSL Ubuntu dev shell** (where all agent work happens):
   - `python3.6` (3.6.9) — v1 syntax checks (`python3.6 -m py_compile pymol/biochemeleon/*.py`) + pure-layer unit tests (`python3.6 -m unittest tests.test_setup_state -v` from `pymol/`).
   - **`tclsh` is NOT currently installed** (as of 2026-09-08: only the `libtcl8.6` runtime library is present, no `tclsh` binary on PATH). The documented `tclsh`-based syntax checks in `vmd/AGENTS.md` therefore do not run today — **headless VMD is the primary Tcl runner** (it also matches the target version exactly: 8.5.6 vs WSL's libtcl 8.6.8, which matters for the 8.6-idiom gate).
   - NO installs permitted: `opencode.json` denies `rm*`, `rg*`; `pip*`/`apt*`/`conda*`/`mv*`/`wget*`/`curl*`/`python*` are "ask".
2. **Windows VMD 1.9.3** (November 30, 2016 build) at `C:\Program Files (x86)\University of Illinois\VMD\`, reached from WSL via the `vmd` alias (`vmd.exe`). Bundles Tcl 8.5.6 + Tk 8.5/ttk. Tk loads ONLY in GUI mode (`-dispdev win`); `package require Tk` fails in `-dispdev text`. GUI/Tk/real-mouse picking are human-verify checkpoints. 75 molfile plugins load from `C:/Program Files (x86)/.../plugins/WIN32/molfile`.
3. **Windows PyMOL 2.5.0** in conda env `chemtools-win10` (Miniconda3 at `C:\ProgramData\Miniconda3`; env at `%USERPROFILE%\.conda\envs\chemtools-win10`). Activated via `setenv.bat`; headless runs via `cmd.exe /c C:\src\run-conda-pymol.bat -cq <script>`. Qt/GUI paths are human-verify checkpoints.

**Headless VMD bridge (the v2 engine gate — mirrors v1's `run-conda-pymol.bat -cq`):**
```bash
# 1. Stage vmd/ to a Windows-visible path (VMD can't read /mnt/c in-script):
bash vmd/wsl2win_cp.sh          # -> tmp/biochemeleon-vmd/vmd/
# 2. Run headless from the staging root (bash -ic for the alias; < /dev/null prevents hang):
bash -ic "cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase17_capstone_smoke.tcl -eofexit" < /dev/null 2>&1 | tail -50
# 3. Exit 0 = clean; nonzero = crash. Smokes self-report e.g. "BCHM_SMOKE_RESULT PASS=1 FAIL=none".
```
Under `vmd -e`, `[info script]` is EMPTY inside sourced files — every module freezes its dir at source time (`vmd/lib/demos.tcl:26`, `vmd/lib/mutation.tcl:65`) or falls back to `[pwd]/vmd/lib` (`vmd/lib/splice.tcl:54-62`, `vmd/tests/test_splice.test:14`). Always run from the staging root.

**Package Manager:**
- None for either plugin. Dependency policy (spec.md constraint): assume ONLY what the host app ships. Zero external deps confirmed for v2; v1 uses zero beyond pymol + stdlib.
- conda exists on the Windows side only (PyMOL host env). NEVER invoked from WSL.
- Lockfile: Not applicable (no `requirements.txt`/`pyproject.toml`/`pkgIndex` dependency pins beyond the plugin's own `package ifneeded`).

## Frameworks

**Core:**
- **VMD 1.9.3** — v2 host application. Tcl command surface in use: `mol`, `molinfo`, `atomselect`, `measure`, `label`, `mouse`, `trace` (variable), `vmdcon`, `vmd_install_extension`. Extension patterns taken from the bundled plugins in `vmd-ref/plugins/` (gitignored reference: `clonerep1.3`, `viewmaster2.6`, `ramaplot1.1`, `autoionize1.4`, `mergestructs1.1`).
- **Tcl/Tk 8.5 + ttk** — v2 GUI. `ttk::notebook` (Setup + Game tabs) in a MODELESS `toplevel .biochemeleon` (`vmd/gui/dialog.tcl:49-55`). Never `grab set` the main panel (grep-gated; `grab set` on transient sub-dialogs is allowed).
- **PyMOL 2.5.0** (open-source, anaconda) — v1 host. `pymol.cmd`, `pymol.Qt` → PyQt5, `pymol.wizard.Wizard` (PickWizard), `pymol.editor`, `pymol.plugins.addmenuitemqt`. Verified against the source mirror at `tmp/pymol-src/modules/pymol/` (gitignored, API-verification only, NOT a runtime dep).

**Testing:**
- `tcltest` (bundled with Tcl; `package require tcltest`) — 6 pure-layer suites under `vmd/tests/`: `test_setup_state.test` (47), `test_registry.test` (37), `test_generators.test` (26), `test_game_logic.test` (15), `test_rep_tiers.test` (49), `test_splice.test` (31) — ~205 test commands. Run under headless VMD (primary) or standalone `tclsh` when present: `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/test_splice.test -eofexit < /dev/null'`.
- `unittest` (Python stdlib) — 5 suites under `pymol/tests/` (~346 tests), stubbing `pymol`/`pymol.Qt` with `MagicMock` via `sys.modules`. Run via `python3.6 -m unittest tests.test_setup_state -v` from `pymol/`.
- Headless smoke suites: `vmd/smoke/phase13…17_*.tcl` (23 files; 15 phase-17 smokes) and `pymol/smoke/*.py` (19 files) — mol-coupled verification, run on the Windows hosts.
- GUI verify drivers: `vmd/tests/rep_verify.tcl` (637 lines, the consolidated 17.1/17.2 rep-verify AUTO-DRIVER: `pv_round1/2/3`, `pv_report`, `pv_cleanup`; auto-logs to `rep_verify_log.txt`) and `vmd/tests/pick_verify.tcl` (Phase-16 historical artifact, unrepaired).

**Build/Dev:**
- No build step for either viewer — interpreted directly by the host.
- **Staging:** `vmd/wsl2win_cp.sh` — `cp -r vmd "$STAGE/"` (default `tmp/biochemeleon-vmd`); the Windows VMD `[pwd]` then resolves to `C:/...`. v1 equivalent: `bash wsl2win_cp.sh` stages `pymol/biochemeleon/` → `tmp/bioCHEMeleon/`.
- **Gates (run from repo root):**
  - Tcl 8.5 idiom gate — MUST be zero matches: `grep -rnE "\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/ vmd/gui/`
  - Modeless gate — MUST be zero matches: `grep -rnE "grab set" vmd/gui/`
  - v1 Tkinter/PyQt5 import gate + `.exec_()` gate — see `pymol/AGENTS.md` Commands.
- Dev logs: root-level `reg-*.log`, `splice-smoke-run*.log` are gitignored headless-run transcripts (`*.log` in `.gitignore`).

## Key Dependencies

**v2 (vmd/) — all shipped with VMD 1.9.3, zero external:**
- Tcl 8.5.6 core: `dict`, `lassign`, `apply`, `trace`, `clock`, `format`, `file`, `regexp`, `string is`, `tcltest`, `namespace ensemble`.
- Tk 8.5 + ttk (`tk85.dll`; `::ttk::*` bundled) — GUI-only.
- VMD C commands: `mol`/`molinfo`/`atomselect`/`measure`/`label`/`mouse`/`vmdcon`/`vmd_install_extension`/`user add key`.
- VMD's `http` package (2.7.2) exists but has **NO tls** → HTTPS (RCSB) impossible → this is why `vmd/lib/demos.tcl:106` `fetch_pdb` is a stub and the demo set is bundled-only.
- `molfile` plugins (75 loaded, PDB read/write) — host-side, used implicitly by `mol new`/PDB rebuilds.

**v1 (pymol/) — all shipped with pymol-open-source:**
- `pymol` 2.5.0 API + `pymol.Qt` → PyQt5 + Python stdlib (`json`, `os`, `tempfile`, `threading`, `queue`, `ssl`, `urllib.request`, `zipfile`, `random`, `math`, `collections`).
- **numpy is NOT imported** anywhere in `pymol/biochemeleon/` (`pymol/biochemeleon/generators.py` documents "NO numpy"; pure `random`+`math`). Do not assume it is available without an explicit import.

## Configuration

**Environment:**
- No `.env` files, no env vars, no runtime configuration. Host launchers handle everything.
- WSL→Windows path guards (mandatory whenever a path crosses the boundary):
  - `vmd/lib/demos.tcl:36` `to_vmd_path` — `/mnt/c/...` → `C:/...` (FORWARD slashes; Windows VMD cannot resolve `/mnt/c/`, `/tmp/`, `~/`).
  - `pymol/biochemeleon/demos.py:59` `to_windows_path` — `/mnt/c/...` → `C:\...` (backslashes; only for PyMOL).

**Setup persistence format (v2):**
- `SETUP_FORMAT = "biochemeleon-setup-v2"` (`vmd/lib/setup_state.tcl:13`). Key-value LINE files (locked decision — NOT `[list]`+source), `.bcm` extension, written/read by `vmd/lib/demos.tcl` `save_setup`/`load_setup` (`demos.tcl:116-181`) via `gui/setup_tab.tcl` (`tk_getSaveFile`, `demos.tcl`-backed). `load_setup` rebuilds the dict in DEFAULTS key order (tcl dict `eq` is order-sensitive) then re-validates through `setup_state::validate_state`.
- 11 setup keys: `format target_mode selected_object pdb_code demo_id hider_count lock_scene per_rep difficulty_easy lock_source pdb_pool` (`vmd/lib/setup_state.tcl:18-29`).

**Demo manifest (v2):** 6 BUNDLED entries only (`vmd/lib/setup_state.tcl:34-40`): `1znf` (protein/easy), `1xdn` (protein/hard), `5e54` (rna/easy), `1k8p` (dna/easy), `2qbz` (rna/hard), `4wb3` (mixed/hard). Files at `vmd/data/demos/*.pdb` (+ `SOURCES.md`), committed, offline. The 3 fetched demos (1gzm/3gp6/SASDPG4) are a later phase.

**v1 config:** JSON setup files (`SETUP_FORMAT = "biochemeleon-setup-v1"`), `.bcmz` game archives (`pymol/biochemeleon/persistence.py`), fetched-demo cache `<cwd>/cache/`.

**Plugin discovery:**
- v2 sourced form (primary): `source vmd/biochemeleon.tcl` (or from `.vmdrc`). Sourcing defines the `biochemeleon` console command and registers `vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"` (menu path locked — NOT `Extensions/`); it does NOT auto-open the dialog.
- v2 packaged form (optional): `vmd/pkgIndex.tcl` — `package ifneeded biochemeleon 2.0 [list source [file join $dir biochemeleon.tcl]]` for `lappend auto_path` + `package require biochemeleon`.
- v1: PyMOL GUI *Plugin → Plugin Manager → Install New Plugin* → `%APPDATA%/pymol/startup/`.

## Platform Requirements

**Development (WSL Ubuntu):**
- `python3.6` (3.6.9) for v1 py_compile/unittest.
- `vmd` alias (WSL interop) + `cmd.exe` reachable for headless runs.
- `git`; worktree protocol for parallel plans (root `AGENTS.md`).
- NO installs; `tclsh` currently absent (see Runtime) — headless VMD covers Tcl checks.

**Production (runtime):**
- v2: Windows 10 with VMD 1.9.3 (Tcl/Tk 8.5.6). Offline-capable (bundled demos); no network needed.
- v1: Windows 10 conda env `chemtools-win10` with `pymol-open-source` 2.5.0 (+PyQt5). Optional network for `cmd.fetch`/large demos.

**Performance budgets (vmd/AGENTS.md):** Generate on 3GP6 (100k+ atoms) < 30s; pick latency < 200ms; never block the Tcl event loop > 200ms (single-threaded — `after 0 ::gen_chunk` cooperative chunking, no QTimer analog).

## Version Pins Summary

| Component | Version | Where |
|---|---|---|
| Tcl (v2 target) | 8.5.6 exact | VMD 1.9.3 bundle |
| Tk/ttk | 8.5 | VMD 1.9.3 bundle |
| VMD | 1.9.3 (2016-11-30) | Windows install |
| Python (WSL dev) | 3.6.9 | `python3.6` |
| Python (v1 runtime) | ≥3.6 (conda) | chemtools-win10 |
| PyMOL | 2.5.0 open-source | conda env |
| PyQt5 | via pymol.Qt (auto-selected) | pymol-open-source dep |
| Plugin package | biochemeleon 2.0 | `vmd/biochemeleon.tcl:42` |

---

*Stack analysis: 2026-09-08*
