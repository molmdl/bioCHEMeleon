# Technology Stack

**Analysis Date:** 2026-08-18

## Languages

**Primary:**
- Python 3.6.9 — WSL dev shell (`python3.6`); used for syntax checks (`py_compile`) and pure-layer unit tests ONLY. PyMOL is NOT importable in WSL (no C extension, no Qt display). Hard constraint: nothing may be installed in WSL (no `pip`, no `apt`, no `conda` — `opencode.json` denies `pip*`, `apt*`, `conda*`, `rm*`).
- Python (bundled with conda PyMOL 2.5.0, Windows) — the actual runtime interpreter that executes the plugin. ≥3.6. Imports `pymol.cmd`, `pymol.Qt`, `pymol.wizard`, `pymol.editor`, `pymol.plugins`.

**Secondary:**
- Windows batch (`setenv.bat`, `run-conda-pymol.bat`) — conda env activation + headless PyMOL invocation.
- Bash (`wsl2win_cp.sh`) — WSL→Windows path staging for headless smoke runs.

## Runtime

**Environment (dual-environment split — read `AGENTS.md` before any runtime work):**
- **Dev shell:** WSL Ubuntu. `python3.6` (3.6.9). Syntax checks + pure unit tests only. CANNOT run `pymol.Qt.*` (no display). CANNOT `pip install`.
- **PyMOL runtime:** Windows conda env `chemtools-win10` (Miniconda3 at `C:\ProgramData\Miniconda3`; env at `%USERPROFILE%\.conda\envs\chemtools-win10`). PyMOL 2.5.0 (anaconda, open-source build). Launched via `setenv.bat` (interactive GUI) or `run-conda-pymol.bat` (headless cmd-only).
- **Headless bridge (WSL→Windows, discovered Phase 3):** A WSL agent CAN run pure-`cmd` PyMOL scripts (no Qt, no viewer) headlessly: stage the package via `bash wsl2win_cp.sh`, then `cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq <script>" 2>&1 | tail -50`. `-cq` = command-line + quiet (no GUI). Qt/GUI smoke tests remain human-verify checkpoints.

**Package Manager:**
- conda (Windows side only — `chemtools-win10` env). NEVER invoked from WSL.
- No `pip` in WSL (`opencode.json` denies `pip*`).
- Lockfile: Not applicable (no `requirements.txt`/`pyproject.toml` — dependency policy is "only what pymol-open-source ships").

## Frameworks

**Core:**
- **PyMOL 2.5.0** (open-source, anaconda) — Host application. Provides `pymol.cmd` (molecular commands), `pymol.wizard.Wizard` (pick callback base class), `pymol.plugins.addmenuitemqt` (plugin menu registration), `pymol.editor` (fragment attach). Verified against `v2.5.0` source tag (`tmp/pymol-src/modules/pymol/`). Source mirror is gitignored and for API verification ONLY — NOT a runtime dependency.
- **PyQt5 via `pymol.Qt`** — Plugin GUI. `pymol.Qt` auto-selects PyQt5/PySide2/PyQt4/PySide (sets `QT_API`). ALWAYS import via `from pymol.Qt import QtCore, QtGui, QtWidgets` — NEVER `from PyQt5 import` (breaks on PySide2 builds; grep-gated). PyQt5 is a conda-forge `pymol-open-source` run-dep, so already present — no install/approval/vendoring needed.
- **PyMOL Wizard API** (`pymol.wizard.Wizard`) — Click-to-find picking. `do_pick(self, bondFlag)` fires on atom picks regardless of Tk/Qt GUI. GUI-agnostic.

**Testing:**
- `unittest` (stdlib) — pure-layer unit tests run via `python3.6 -m unittest tests.test_setup_state -v` in WSL. No pytest (cannot install). Test files stub `pymol`/`pymol.Qt` with `MagicMock` via `sys.modules` before importing `biochemeleon.*`.

**Build/Dev:**
- `python3.6 -m py_compile biochemeleon/*.py` — syntax gate (checks syntax, NOT imports).
- `wsl2win_cp.sh` — stages `biochemeleon/` → `tmp/bioCHEMeleon/biochemeleon/` (Windows-facing path) for headless runs.
- Grep gates (run from repo root): Tkinter/Pmw/legacy gates + `.exec_()` gate (see `AGENTS.md` Commands).

## Key Dependencies

**Critical (all bundled with pymol-open-source — zero external installs):**
- `pymol` (2.5.0) — host app + API surface. `from pymol import cmd` is the central API.
- `pymol.Qt` → PyQt5 — GUI widgets (`QtWidgets.QDialog`, `QTabWidget`, `QGroupBox`, `QComboBox`, `QPushButton`, `QLineEdit`, `QCheckBox`, `QFileDialog`, `QProgressDialog`, `QTimer`, `QTextEdit`).
- Python stdlib — the ONLY other imports in the package. Confirmed by grep across `biochemeleon/*.py`: `json`, `os`, `tempfile`, `time`, `zipfile`, `random`, `copy`, `threading`, `queue`, `ssl`, `urllib.request`, `urllib.error`, `collections` (`OrderedDict`, `namedtuple`).

**NOT used (important correction):**
- **numpy** — available as a pymol-open-source build/run dep, but the actual biochemeleon code does NOT import it. `biochemeleon/generators.py` explicitly documents "NO numpy" and uses stdlib `random` + `math` for coordinate math. The research STACK.md (`/.planning/research/STACK.md`) listed numpy as expected; the implemented code chose pure-stdlib instead. Do not assume numpy is available in plugin code without an explicit `import numpy`.

**Infrastructure (dev environment bridge):**
- `setenv.bat` — Windows cmd.exe batch; activates `chemtools-win10` conda env. Does NOT launch PyMOL (run `pymol` from the activated shell).
- `run-conda-pymol.bat` — Windows cmd.exe batch; activates env + runs `python %ENVPATH%\Lib\site-packages\pymol\__init__.py %*`. Accepts passthrough args (e.g. `-cq <script>` for headless). Located at `C:\src\run-conda-pymol.bat` on the Windows side.
- `wsl2win_cp.sh` — `cp -r ./biochemeleon tmp/bioCHEMeleon/` (stages package to Windows-facing path).
- `opencode.json` — OpenCode config + command permission rules. Denies `rm*`, `rg*`; `pip*`/`apt*`/`conda*`/`python*`/`wget*`/`curl*`/`mv*`/edit are "ask".

## Configuration

**Environment:**
- No `.env` files (`.gitignore` excludes `*.env`). No env vars required at runtime — conda env activation handles PATH.
- PyMOL plugin discovery: installed via PyMOL GUI *Plugin → Plugin Manager → Install New Plugin* (accepts a package dir with `__init__.py`). Lands in `%APPDATA%/pymol/startup/` (Windows) or `~/.pymol/startup/` (Linux). For dev, run from the repo via the Windows path.
- Fetched-demo cache: `<cwd>/tmp/phase9-demos/cache/` (consistent with `cmd.fetch`, which downloads PDBs into the cwd; created on first finalize via `os.makedirs`). Persists across PyMOL sessions as long as the user launches PyMOL from the same dir (the same limitation `cmd.fetch` has — acceptable for v1). The cwd-based layout matches the Phase 9 smoke test's staging paths (smoke lines 103 + 237) AND `cmd.fetch`'s convention (Pitfall E / Open Risk 4 reframe).

**Build:**
- No build step. Python package is interpreted directly by PyMOL's bundled Python.
- `biochemeleon.zip` — staged fallback install artifact (gitignored). Used for Plugin Manager zip-install path if needed; package-dir install is the primary path.

**Git ignore (`.gitignore`):**
- `Pymol-script-repo` (reference plugins for learning), `3rd_party_lib/**` (vendored libs), `tmp`, `biochemeleon.zip`, `*.pyc`, `*.npy`, `*.npz`, `*.env`, `**/secrets.toml`, `**/auth.json`.

## Platform Requirements

**Development (WSL Ubuntu):**
- `python3.6` (3.6.9) for `py_compile` + `unittest` on the pure layer.
- `git` for version control.
- `cmd.exe` reachable (WSL interop) for headless PyMOL smoke runs.
- NO installs permitted. NO conda envs in WSL.

**Production (runtime):**
- Windows 10 conda env `chemtools-win10` with `pymol-open-source` 2.5.0 (pulls PyQt5 + pmw as run-deps).
- PyMOL launched via `setenv.bat` (interactive) or `run-conda-pymol.bat -cq` (headless).
- Optional: network access for `cmd.fetch` (RCSB PDB) and large-demo downloads (MemProtMD, SASBDB). Bundled demos (6 PDBs) work offline.

## Dependency Policy (spec.md constraint — critical)

- Assume ONLY what `pymol-open-source` ships: PyQt5 (via `pymol.Qt`), numpy (available but unused), Python stdlib.
- Any additional Python lib MUST be: (1) written to an approval file, (2) explicitly approved by the user, (3) then EITHER user-installed into `chemtools-win10` OR vendored into `./3rd_party_lib/` (git-ignored) with its license noted. State whether the user needs a Linux-like env or can keep the "call cmd from WSL" approach.
- Do NOT `pip install` silently. `opencode.json` denies/asks on `pip*`.
- v1 currently uses ZERO external libs beyond pymol + stdlib — the approval step has never triggered.

## Entry Point Contract

- Plugin entry: `biochemeleon/__init__.py` → `__init_plugin__(app=None)` (modern signature; NOT legacy `__init__(self)`).
- `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` imported locally inside `__init_plugin__` (clean failure if Qt unavailable).
- Module-level singleton `dialog = None` (GC prevention — must be module scope, not inside `__init_plugin__`).
- Main dialog is MODELESS: `dialog.show()` + `raise_()` + `activateWindow()`. NEVER `.exec_()` on the main `PluginDialog` (blocks the PyMOL event loop + 3D viewer). `.exec_()` on child `QFileDialog`/`QMessageBox`/`QInputDialog`/Help `QDialog` IS allowed.

---

*Stack analysis: 2026-08-18*
