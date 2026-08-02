# Stack Research

**Domain:** PyMOL 2.5.0 desktop plugin — interactive molecular "hide-and-seek" game
**Researched:** 2026-08-03
**Confidence:** HIGH (core), with one MEDIUM-confidence deviation flagged below

> **⚠ Read this first — a spec deviation.** PROJECT.md / spec.md state the UI must be built in **Tkinter** ("PyMOL's built-in GUI framework"). After verifying against the **official PyMOL 2.5.0 source** (`schrodinger/pymol-open-source` tag `v2.5.0`, cloned and inspected) and the **only modern plugin shipped with PyMOL itself** (`data/startup/lightingsettings_gui/`), the evidence is unambiguous: **the supported, non-legacy plugin GUI framework in PyMOL 2.5.0 is PyQt5 via `pymol.Qt`, not Tkinter.** The user confirmed this during research ("check the lighting plugin in open-source pymol, as i know its not legacy and need qt", "newer pymol dont support tk"). This file recommends PyQt5 via `pymol.Qt` and explains why. The Tkinter assumption in the spec is treated as a hypothesis that the evidence overturned — see "Why not Tkinter" below.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Python** | 3.x (bundled with conda PyMOL 2.5.0; ≥3.6 for WSL syntax checks) | Plugin implementation language | PyMOL 2.5.0 is Python 3 only. `pymol.cmd` is Python. The whole plugin is one Python package. Use `from __future__ import annotations` for forward refs if needed. |
| **PyMOL** | 2.5.0 (open-source, anaconda) | Host application; provides `pymol.cmd`, `pymol.wizard`, `pymol.Qt`, `pymol.plugins` | Hard requirement from spec. Verified against `v2.5.0` source tag (commit `9ea504e`, `_PyMOL_VERSION "2.5.0"` in `layer0/Version.h`). |
| **PyQt5 via `pymol.Qt`** | PyQt5 (preferred); `pymol.Qt` also accepts PySide2 / PyQt4 / PySide | Plugin GUI (setup tab + game-status tab) | Officially sanctioned by the only modern plugin shipped inside PyMOL 2.5.0 (`lightingsettings_gui`). `pymol.Qt` is a thin wrapper that auto-selects whichever Qt binding is installed (tries PyQt5 first). It is a **runtime dependency of conda-forge `pymol-open-source`** (`pyqt` listed in `requirements.run` of the conda-forge recipe), so it is already present in the user's env — no install, no approval, no vendoring needed. |
| **PyMOL Wizard API** (`pymol.wizard.Wizard`) | built into PyMOL 2.5.0 | Click-to-find picking callback | GUI-agnostic: `do_pick(self, bondFlag)` fires on atom picks regardless of whether PyMOL runs the Tk or Qt GUI. Every interactive pick-based workflow in PyMOL uses this (measurement, mutagenesis, mtsslWizard, etc.). See "Picking" below. |
| **numpy** | bundled with PyMOL (build/run requirement; `import numpy` at top of `setup.py`) | Coordinate math for hider placement | REQUIRED by pymol-open-source itself, therefore already available under the spec's "only libs required by pymol-open-source" rule. Use for vector ops when placing line/stick/cartoon/sphere hiders. No approval needed. |
| **Python stdlib** (json, random, math, os, gzip/zlib, pickle) | stdlib | Game-state files, randomized placement, demo-PDB bundling, compression | Always present. `json` for human-readable game-state sidecar; `gzip`/`zlib` for compressing large demo PDBs (spec: "compress before bundling"). |

### Supporting Libraries — the PyMOL API surface (not pip libs)

These are not installs; they are the PyMOL `cmd` functions central to this project. All verified present in the `v2.5.0` source.

| API | Module (v2.5.0) | Purpose in this project | When to use |
|-----|------------------|------------------------|------------|
| `cmd.create(name, selection, ...)` | `pymol/creating.py:960` | **Insert hiders INTO an existing object.** Idiom: build hiders in a temp object, then `cmd.create(existing_obj, "(existing_obj) or (tmp_hiders)", zoom=0)` — replaces `existing_obj` with the union. (Confirmed pattern: `bnitools.py:1529` does exactly `cmd.create(name, "(%s or %s)" % (a, b))`.) | Merging hider atoms so they share the player's object (spec's core "blend in" mechanic). |
| `cmd.get_model(selection, state)` | `pymol/querying.py:1053` | Read the chempy `Model` (atoms + coords + bonds) of the existing object | Compute placement (find terminal C-alpha for cartoon extension, neighbor atoms for line/stick mimic, free space for sphere). |
| `cmd.load_model(model, object, ...)` | `pymol/importing.py:319` | Load a chempy `Model` into a (temp) object | Build the temp hider object from a programmatically-constructed model. |
| `cmd.alter(selection, expression, ...)` | `pymol/editing.py:1424` | Modify atom string properties: `name`, `resn`, `resi`, `chain`, `elem`, `segi`, `text`, and numeric `b`, `q` | Give hiders atom/residue names that mimic the local representation (CA, N, C for cartoon; backbone names for line/stick). Optionally tag hiders via `b`/`q` for in-object marking. |
| `cmd.alter_state(state, selection, expression, ...)` | `pymol/editing.py:1535` | Modify atom coordinates `x,y,z` | Set hider positions (line/stick alternate positions, cartoon extended terminus, sphere anywhere). |
| `cmd.iterate(...)` / `cmd.iterate_state(...)` | `pymol/editing.py:1490` / `:1578` | Read atom properties/coords into Python (`stored.x = ID`, `stored.coords.append((x,y,z))`) | Inspect existing structure for placement; read picked atom identity. |
| `cmd.index(selection)` | `pymol/querying.py:1302` | **Returns `[(model, index), ...]` — the canonical unique atom ID in PyMOL.** | (a) record each hider's identity at generation time; (b) identify the picked atom in `do_pick`. Used by `annocryst.py:376` (`cmd.index(self.selection)`). **Core to the click-to-find check.** |
| `cmd.get_names(type, ...)` / `cmd.get_object_list(selection)` / `cmd.get_type(name)` / `cmd.count_atoms(selection)` | `pymol/querying.py:1148,131,1199,1412` | List loaded objects, filter to `object:molecule`, count atoms | Populate the setup-tab object dropdown; verify a picked atom belongs to the game object. |
| `cmd.show(rep, sel)` / `cmd.hide(rep, sel)` / `cmd.as(reps, sel)` / `cmd.cartoon(...)` | `pymol/viewing.py` | Apply representations (lines, sticks, cartoon, ribbon, spheres) | "Lock current scene" reads current reps; "randomize" applies presets. Surface is intentionally NOT used (out of scope). |
| `cmd.fetch(code, name, type=, async_=0, ...)` | `pymol/importing.py:1323` | Download a structure from the PDB/wwPDB | "Fetch large demo on demand". **Pass `async_=0`** so the structure fully loads before the game starts (interactive default is async — a subtle trap; see PITFALLS). |
| `cmd.load(filename, object, ...)` / `cmd.load_pse(filename)` | `pymol/importing.py:635` / `:823` | Load PDB/CIF/MMTF/etc.; load a PyMOL session (.pse) | Load bundled demo PDBs; restore a saved game session. |
| `cmd.save(filename, selection, state, format)` | `pymol/exporting.py:782` | Save a PyMOL session (`.pse`) or structure (`.pdb`, `.cif`, ...) | Save game state as a `.pse` (spec: "save the state of the game as a pymol session"). Format auto-detected from extension. |
| `cmd.get_session(...)` / `cmd.set_session(session, ...)` | `pymol/exporting.py:370` / `pymol/importing.py:130` | Get/set the whole session object (pickleable) | Optional advanced embedding. **Recommended simpler approach:** `.pse` + sidecar JSON. |
| `cmd.set_wizard(wiz)` / `cmd.set_wizard()` | `pymol/wizarding.py:110` | Activate / clear the active wizard | Start the picking wizard on "Start"; clear on win/restart/exit. `cmd.set_wizard()` with no args clears. |
| `cmd.refresh_wizard()` / `cmd.get_wizard()` | `pymol/wizarding.py:146` / `:156` | Update the wizard prompt / retrieve current wizard | Update the rolling info / "remaining hiders" text in the PyMOL prompt area. |
| `cmd.button(button, modifier, action)` / `cmd.set('button_mode', ...)` / `cmd.edit_mode()` | `pymol/controlling.py:799` / `:196` / `:688` | Configure mouse so single-click picks an atom (action `PkAt` / `Pk1`) | Ensure a click populates `pk1` / `(sele)` so the wizard's `do_pick` fires. Restore prior mouse mode on cleanup. |
| `cmd.extend(name, function)` | `pymol/commanding.py:532` | Register a new PyMOL command-line command | Recommended: expose `chameleon_start`, `chameleon_cleanup`, etc. for power users. |
| `cmd.color(color, selection)` / `cmd.label` | `pymol/...` | Recolor found hiders; "hint" coloring of N atoms around a hider; labels | Found-hider visibility/color dropdown (spec); Hint button (spec). |
| `cmd.delete(name)` / `cmd.remove(selection)` | `pymol/editing.py` | Cleanup model: remove game-generated atoms/representations | "Cleanup model" button (spec). Requires keeping the original atom-id set so you can select "obj and not (hiders)". |
| `cmd.select(name, selection)` | `pymol/selecting.py` | Create named selections (`_chameleon_hiders`, `_chameleon_found`) | Fast recolor/hide and cleanup. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| WSL Ubuntu shell + `python3.6` | **Syntax checking only** (`python3.6 -m py_compile <file>`). Do NOT install anything in WSL; do NOT create conda envs. | Hard constraint from spec. `py_compile` catches syntax errors but cannot run PyMOL (no Qt, no `pymol._cmd` C ext). PyMOL's `cmd` is dynamic — type-checks are limited. |
| `setenv.bat` (Windows `cmd.exe`) → `chemtools-win10` conda env | Launch PyMOL 2.5.0 with the plugin for real testing | Activates the Miniconda env. From WSL, invoke Windows commands via `cmd.exe /c setenv.bat && pymol <args>` or run a `.bat` wrapper. The "call cmd from WSL" approach works — **no Linux-like env needed** because PyQt + PyMOL run on Windows. |
| `git` | Version control; `3rd_party_lib/` and `Pymol-script-repo/` are git-ignored | Both already in `.gitignore`. |
| Reference repo `./Pymol-script-repo` (git-ignored) | Read real-world plugin examples | Studied: `mtsslWizard.py` (Wizard/do_pick), `bnitools.py` (`cmd.create` merge idiom, `cmd.alter`), `mtsslDockGui.py` (ttk + Pmw dialogs), `optimize.py` (PyQt port). The modern canonical template is `lightingsettings_gui` in the PyMOL source itself. |

## Installation

**There is nothing to install.** This is the strongest property of the recommended stack:

```bash
# Core: already present with PyMOL 2.5.0 (conda):
#   - pymol.cmd, pymol.wizard, pymol.plugins, pymol.Qt
#   - PyQt5 (conda-forge pymol-open-source run-dep: "pyqt")
#   - numpy  (pymol-open-source build/run requirement)
#   - Python stdlib (json, random, math, os, gzip, pickle)

# Plugin install (end-user, one of):
#   a) PyMOL GUI: Plugin > Plugin Manager > Install > point at the
#      biochemeleon/ package directory (its __init__.py). PyMOL's
#      installation.py accepts a single .py OR a package dir with __init__.py.
#   b) Copy/clone the package into the user plugin dir:
#        Windows: %APPDATA%/pymol/startup/biochemeleon/__init__.py
#        Linux:   ~/.pymol/startup/biochemeleon/__init__.py
#   c) During dev: symlink the repo dir into the user plugin dir, or add
#      its parent to PYMOL path so PyMOL finds biochemeleon/__init__.py at startup.

# Dev dependencies: NONE. (No pytest in WSL — can't install. Syntax-check with
# python3.6 -m py_compile; functional test in Windows PyMOL via setenv.bat.)
```

**Vendoring strategy (`./3rd_party_lib`): not needed for v1.** If a future phase needs a non-PyMOL Python lib, the workflow is: (1) write the proposed lib + version + license to an approval file, (2) get explicit user sign-off, (3) either let the user `pip install` it into the `chemtools-win10` Windows env, OR drop a vendored copy into `./3rd_party_lib/<lib>/` (git-ignored via the existing `.gitignore` entry) and `sys.path.insert(0, './3rd_party_lib')` at plugin import. Note the license in `./3rd_party_lib/<lib>/LICENSE`. The "call cmd from WSL" approach still works for pure-Python vendored libs; C-extension libs need the Windows env.

## Alternatives Considered

| Category | Recommended | Alternative | Why Not (or when alternative wins) |
|----------|-------------|-------------|-------------------------------------|
| GUI framework | **PyQt5 via `pymol.Qt`** | Tkinter + `ttk` | Tkinter is the *legacy* path; the modern PyMOL GUI is Qt and the only shipped modern plugin (`lightingsettings_gui`) uses `pymol.Qt`. On the Qt GUI build there is no live Tk root (`pymol.plugins.legacysupport.get_tk_root()` returns `None` via `createlegacypmgapp`), so a `tkinter.Toplevel` plugin GUI would not work. See "Why not Tkinter" below. Tkinter would be acceptable ONLY if the user confirms they run the open-source *Tk* GUI build — not recommended. |
| GUI framework | **PyQt5 via `pymol.Qt`** | Pmw (Python megawidgets) | Pmw is **no longer bundled** with pymol-open-source (`setup.py` raises if `--bundled-pmw`; message: "please install Pmw from github.com/schrodinger/pmw-patched"). conda-forge does pull `pmw` as a run-dep, so it *happens* to be present on conda installs — but relying on that violates the spirit of "only libs required by pymol-open-source" and is fragile. Use `QTabWidget`/`QGroupBox`/`QComboBox`/`QDoubleSpinBox` (PyQt5) instead. |
| GUI framework | **PyQt5 via `pymol.Qt`** | Raw PyQt5 import (`from PyQt5 import ...`) | Use the `pymol.Qt` wrapper, NOT raw PyQt5. `pymol.Qt` auto-selects PyQt5/PySide2/PyQt4/PySide and sets `QT_API` for qtpy compatibility. Direct `from PyQt5 import` breaks if the user's build uses PySide2. |
| Hider detection | **`cmd.index()` registry + Wizard `do_pick`** | Polling `pk1`; custom `cmd.button` only | Wizard is the canonical PyMOL pick-callback mechanism — robust, restores cleanly, shows a prompt. Polling is fragile and not event-driven. |
| Atom insertion | **`cmd.create(obj, "(obj) or (tmp)")` merge idiom** | `cmd.load_model` replace; `cmd.alter` + `cmd.load_coordset` | `load_coordset` only adds coordinate *states* to an existing object (same atom count), NOT new atoms. `load_model` on an existing name replaces the whole object (loses representations). The `create`-merge idiom is the proven pattern (`bnitools.py`). |
| Game state | **`.pse` (cmd.save) + sidecar JSON** | `cmd.get_session`/`set_session` embedding | Sidecar JSON is simpler, human-editable, and decoupled from PyMOL's session pickle format (which can change across versions). `.pse` captures the scene/objects; JSON captures hider registry, timer, found-status, setup params. |
| Math | **numpy** (already a PyMOL dep) | pure-Python `math` lists | numpy is required by pymol-open-source itself → free to use. Cleaner vector math for placement. |
| PDB fetch | **`cmd.fetch(..., async_=0)`** | `cmd.fetch` with default async | Default is async in interactive mode → next command may run before load completes. Force `async_=0` for reliable "load then play". |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Tkinter / `tkinter.ttk`** for the plugin GUI | Legacy path. No live Tk root under the Qt GUI build (the default for modern PyMOL). The official modern template (`lightingsettings_gui`) uses `pymol.Qt`. The user confirmed Tk is not supported on their newer PyMOL. | `pymol.Qt` (PyQt5): `QtWidgets.QDialog`, `QTabWidget`, `QGroupBox`, `QComboBox`, `QDoubleSpinBox`, `QPushButton`, `QLineEdit`, `QCheckBox`. |
| **Pmw** (`Pmw.NoteBook`, `Pmw.Dialog`, `Pmw.Group`, `Pmw.EntryField`, `Pmw.OptionMenu`) | No longer bundled with pymol-open-source (`setup.py` explicitly removed `--bundled-pmw`). Only present via conda-forge's `pmw` run-dep — fragile. | PyQt5 widgets: `QTabWidget` (tabs), `QDialog` (window), `QGroupBox` (group), `QLineEdit`+`QLabel` (entry), `QComboBox` (option menu). |
| **`tkintertable`** or other 3rd-party Tk widgets | Extra dependency requiring user approval + vendoring. Not needed — the game's UI is simple. | PyQt5 `QTableWidget` if a table is ever needed (it isn't for MVP). |
| **`cmd.load_coordset` / `cmd.load_coords`** to add hider atoms | These only add coordinate *states* to an existing object (same atom count) or replace coordinates of a selection. They do NOT add new atoms. | Build hiders in a temp object, then `cmd.create(obj, "(obj) or (tmp)")`. |
| **`cmd.load_model(model, existing_obj)`** to add atoms to an existing object | This *replaces* the existing object — losing its current representations/scene state. | The `cmd.create` merge idiom preserves object identity; restore representations from a saved rep-list if needed. |
| **Surface representation** for hiders | Explicitly out of scope (spec): doesn't fit the blend-in mechanic. | line/stick (mimic), cartoon/ribbon (extend-or-replicate), sphere (anywhere). |
| **Installing anything in WSL** / creating conda envs | Hard constraint from spec. | WSL = syntax check only (`python3.6 -m py_compile`). Run/test in Windows via `setenv.bat`. |
| **Auto-pip-installing extra libs** | Spec: any non-PyMOL lib must be approved first, then user-installed or vendored. | The recommended stack uses zero extra libs, so this never triggers in v1. |
| **`from PyQt5 import ...` directly** | Breaks on PySide2 builds. | `from pymol.Qt import QtGui, QtCore, QtWidgets`. |
| **Polling `pk1` in a loop** to detect clicks | Not event-driven; racy; blocks the GUI. | Subclass `pymol.wizard.Wizard`, override `do_pick(self, bondFlag)`, activate with `cmd.set_wizard(wiz)`. |

## Stack Patterns by Variant

**If the user is on the conda-forge `pymol-open-source` build (Tk GUI default + PyQt available):**
- `pymol.Qt` works (PyQt5 is a run-dep). Plugin GUI via PyQt5 renders fine inside the Tk-hosted Qt widgets.
- `pymol.plugins.addmenuitemqt(...)` works (Qt is available).

**If the user is on the Schrodinger `pymol` Incentive build (Qt GUI default):**
- `pymol.Qt` works (PyQt5 bundled). This is the natural case.
- Legacy Tk plugins would have no Tk root — another reason PyQt is the safe common denominator.

**If PyMOL is launched with `-x` / no GUI (batch):**
- `pymol.Qt` import will fail → `addmenuitemqt` raises `QtNotAvailableError` (caught by the plugin loader; the plugin is skipped with a warning). The game requires the GUI anyway, so this is acceptable.

**Picking pattern (GUI-agnostic, works in all builds):**
```
class ChameleonWizard(Wizard):
    def __init__(self, game): self.game = game; ...
    def get_event_mask(self): return Wizard.event_mask_pick
    def get_prompt(self): return self.game.prompt_text
    def get_panel(self): return [[1, 'bioCHEMeleon', ''], [2, 'Quit', 'cmd.set_wizard()']]
    def do_pick(self, bondFlag):
        picked = cmd.index('pk1')   # [(model, index)]
        if picked and picked[0] in self.game.hider_ids:
            self.game.mark_found(picked[0])
        cmd.refresh_wizard()
    def cleanup(self): ...restore mouse mode...
```

**Hider-insertion pattern:**
```
# 1. Build hider atoms in a temp chempy Model (or temp object via fragment+alter)
# 2. cmd.load_model(hider_model, '_chameleon_tmp')
# 3. cmd.alter('_chameleon_tmp', 'resn="HID"; name="CA"; ...')   # mimic local rep
# 4. cmd.create(obj, f'({obj}) or (_chameleon_tmp)', zoom=0)     # merge INTO obj
# 5. Record hider identities: hider_ids = set(cmd.index(f'{obj} and resn HID'))
# 6. cmd.delete('_chameleon_tmp')
```

## Version Compatibility

| Package / API | Compatible With | Notes |
|-----------|-----------------|-------|
| `pymol.Qt` (v2.5.0) | PyQt5, PySide2, PyQt4, PySide | Auto-selects in order; sets `QT_API` env var. Prefer PyQt5 (conda-forge default). |
| `pymol.wizard.Wizard` (v2.5.0) | Both Tk (`pmg_tk`) and Qt (`pmg_qt`) GUIs | Core PyMOL; GUI-agnostic. `do_pick` fires in both. |
| `cmd.create` merge idiom | PyMOL ≥1.x (still valid in 2.5.0) | Verified `creating.py:960` v2.5.0; same idiom used in `bnitools.py`. |
| `cmd.index` | PyMOL ≥1.x (still valid in 2.5.0) | `querying.py:1302` v2.5.0. |
| `cmd.fetch(..., async_=0)` | PyMOL 2.x | `async_` kwarg renamed from `async` (Python 2.7 keyword conflict). Use `async_=0`. |
| `pymol.plugins.addmenuitemqt` | PyMOL ≥1.x with Qt | Raises `QtNotAvailableError` if no Qt — loader catches it. |
| numpy | any version bundled with the conda PyMOL env | PyMOL 2.5.0 conda typically ships numpy 1.x or 2.x; both fine for our vector ops. |
| `lightingsettings_gui` template | v2.5.0+ | The canonical modern plugin structure — copy its `__init_plugin__` + `addmenuitemqt` + `pymol.Qt` pattern. |

## Why not Tkinter (the spec deviation, explained)

The spec's "Tkinter (PyMOL's built-in GUI framework)" was a reasonable starting hypothesis, but the evidence overturns it:

1. **The only modern plugin shipped inside PyMOL 2.5.0 uses PyQt.** `data/startup/lightingsettings_gui/__init__.py` registers via `plugins.addmenuitemqt(...)` and `main.py` does `from pymol.Qt import QtGui, QtCore, QtWidgets`. There is no shipped Tkinter plugin template in v2.5.0 except the legacy comment-only placeholder in `pmg_tk/startup/__init__.py`.

2. **Pmw is no longer bundled.** `setup.py` (v2.5.0) explicitly raises if `--bundled-pmw` is passed: *"--bundled-pmw has been removed, please install Pmw from github.com/schrodinger/pmw-patched"*. So even the legacy Tk+Pmw stack is not a "pymol-open-source required library."

3. **Under the Qt GUI there is no live Tk root.** `pymol/gui.py` `get_pmgapp()` calls `createlegacypmgapp()` when `pymol._ext_gui is None`, producing a fake PMGApp with `app.root = None` and no-op `menuBar`. `pymol.plugins.legacysupport.get_tk_root()` returns that `None`. A `tkinter.Toplevel(parent=None)` plugin GUI will not render.

4. **The community is actively porting away from Tk.** In the local `Pymol-script-repo`, `dynoplot.py` was "Ported to PyQt 2024 by Thomas Holder" and `optimize.py` uses `pymol.Qt` with `QTabWidget` (replacing `Pmw.NoteBook`).

5. **PyQt5 is already available under the spec's strictest rule.** The spec says "only libraries required by pymol-open-source may be assumed available." `pyqt` is a runtime dependency of conda-forge `pymol-open-source` (confirmed in the feedstock `meta.yaml` `requirements.run`). So using `pymol.Qt` violates nothing — it is *required* by the open-source package.

6. **Zero extra installs.** PyQt5 + numpy are both already in the conda env. This is the cleanest possible outcome for the spec's dependency-approval constraint: the approval step never triggers.

**Net:** PyQt5 via `pymol.Qt` is more correct, more future-proof, fully spec-compliant on dependencies, and works on both the open-source (Tk-host) and Incentive (Qt) builds. Tkinter would only be safe on the open-source Tk build and is the deprecated path. Recommend the roadmap adopt PyQt5 and update PROJECT.md's "UI: Tkinter" constraint to "UI: PyQt5 via `pymol.Qt`". This is flagged MEDIUM confidence only because it contradicts the written spec — the technical evidence itself is HIGH confidence.

## Sources

- **PyMOL open-source v2.5.0 source** (cloned `schrodinger/pymol-open-source` tag `v2.5.0`, commit `9ea504e`) — HIGH confidence:
  - `layer0/Version.h` — confirms `_PyMOL_VERSION "2.5.0"`.
  - `modules/pymol/__init__.py` `launch()` — confirms default GUI is `pmg_qt`, falling back to `pmg_tk` on Qt ImportError.
  - `modules/pymol/plugins/__init__.py` — plugin loader; `__init_plugin__` (modern) vs legacy `__init__`; `addmenuitemqt` raises `QtNotAvailableError` if no Qt.
  - `modules/pymol/plugins/legacysupport.py` — `get_tk_root()` returns `pmgapp.root`; `createlegacypmgapp()` sets `app.root = None` (no live Tk root under Qt).
  - `modules/pymol/plugins/installation.py` — plugin install accepts single `.py` or package dir with `__init__.py`; user plugin dir is `%APPDATA%/pymol/startup` (Windows) or `~/.pymol/startup` (Linux).
  - `modules/pymol/Qt/__init__.py` — confirms `pymol.Qt` auto-selects PyQt5/PySide2/PyQt4/PySide.
  - `modules/pymol/wizard/__init__.py` — `Wizard` base class, `event_mask_pick`, `do_pick(self, bondFlag)`, `get_prompt`, `get_panel`.
  - `modules/pymol/creating.py:960` (`cmd.create`), `editing.py:1424/1535/1490/1578` (`alter`/`alter_state`/`iterate`/`iterate_state`), `querying.py:1053/1148/1302/1199/1412/131` (`get_model`/`get_names`/`index`/`get_type`/`count_atoms`/`get_object_list`), `importing.py:635/823/1323/319/1396/1420` (`load`/`load_pse`/`fetch`/`load_model`/`load_coordset`/`load_coords`), `exporting.py:782/370` (`save`/`get_session`), `importing.py:130` (`set_session`), `commanding.py:532` (`extend`), `controlling.py:799/196/688` (`button`/`button_mode`/`edit_mode`), `wizarding.py:110/146/156` (`set_wizard`/`refresh_wizard`/`get_wizard`).
  - `data/startup/lightingsettings_gui/__init__.py` + `main.py` — the canonical modern plugin template (`__init_plugin__` + `addmenuitemqt` + `pymol.Qt` + `QtWidgets.QDialog`).
  - `setup.py` — confirms `--bundled-pmw` removed (Pmw not bundled); numpy is a build requirement.
  - `modules/pmg_qt/__init__.py` — 3-line "dummy module placeholder" (real Qt GUI is closed-source Incentive only); open-source falls back to `pmg_tk`.
- **conda-forge `pymol-open-source` feedstock `meta.yaml`** — HIGH confidence: confirms `pyqt` and `pmw` are runtime deps of the conda build (so PyQt5 is already in the user's env).
- **Local `Pymol-script-repo`** (git-ignored reference) — MEDIUM-HIGH (real-world patterns, older):
  - `plugins/mtsslWizard.py` — Wizard/do_pick pattern, `from pymol.wizard import Wizard`.
  - `plugins/bnitools.py:1529` — `cmd.create(name, "(%s or %s)" % (a, b))` merge idiom; `cmd.alter` usage.
  - `plugins/annocryst.py:376` — `cmd.index(self.selection)` for unique atom IDs.
  - `plugins/optimize.py` — PyQt port using `pymol.Qt`, `QTabWidget` (replacing `Pmw.NoteBook`), `__init_plugin__` + `addmenuitemqt`.
  - `plugins/mtsslDockGui.py` — legacy Tk+Pmw+ttk mixed pattern (example of what NOT to copy wholesale).
  - `plugins/dynoplot.py` — "Ported to PyQt 2024" header confirms the migration trend.

---
*Stack research for: PyMOL 2.5.0 plugin — bioCHEMeleon hide-and-seek game*
*Researched: 2026-08-03*

## FOLLOW-UP VERIFICATION

**Purpose:** Resolve two open questions left by the initial STACK/FEATURES research:
(1) Are the reference-repo plugins "Outliner" and "show_contacts" non-legacy (Qt-based) 3rd-party plugins? (FEATURES.md leaned Tk; STACK/ARCH/PITFALLS leaned Qt — the user expected Outliner & show_contacts to be non-legacy Qt.)
(2) Is the standard plugin install path the GUI Plugin Manager (universal across platforms), and what does that imply for bioCHEMeleon's packaging?

**Method:** Read `./Pymol-script-repo/plugins/outline.py` and `./Pymol-script-repo/plugins/show_contacts.py` in full; cross-checked the entry-point pattern against every other plugin in the same directory. Per user instruction, NO system/conda/PyMOL install location was searched or probed — all evidence below comes from files inside the workspace and `./Pymol-script-repo`.

**Confidence:** HIGH (repo evidence, directly read source). The plugin-loader mechanics below combine (a) repo pattern evidence (HIGH) with (b) the already-cloned PyMOL 2.5.0 source findings already cited earlier in this file (HIGH) — no new system probing was done.

---

### Goal 1a — "Outliner" (`plugins/outline.py`): NON-LEGACY Qt-based plugin (unambiguous)

**Location:** `Pymol-script-repo/plugins/outline.py` (481 lines). Menu label "Outliner"; window title "Outliner" (line 326).

**Authorship / version signal:** Header reads `Author: Jarrett Johnson (Schrodinger, Inc.)` (line 4), `__version__ = "0.2"` (line 26). A Schrodinger author + use of `from __future__ import annotations` (line 7) and `dataclasses` (line 14) place this firmly in the modern era (PyMOL 2.x / Python 3.7+).

**Concrete evidence (quoted lines):**

- Imports — pure Qt, no Tk/Pmw:
  - `outline.py:9`  `from pymol import cmd`
  - `outline.py:10` `from pymol.Qt import QtCore`
  - `outline.py:11` `from pymol.Qt import QtGui`
  - `outline.py:12` `from pymol.Qt import QtWidgets`
  - (No `Tkinter`, `ttk`, `Pmw`, `pmg_tk`, `app.root`, or `get_tk_root` anywhere in the file.)

- Modern entry-point symbol:
  - `outline.py:29` `def __init_plugin__(app=None) -> None:`
  - `outline.py:30`     `from pymol.plugins import addmenuitemqt`
  - `outline.py:31`     `addmenuitemqt('Outliner', run_plugin_gui)`

- GUI is a `QtWidgets.QDialog` subclass:
  - `outline.py:311` `class RepresentationOutlineDialog(QtWidgets.QDialog):`
  - `outline.py:326`     `self.setWindowTitle("Outliner")`

**Classification: (a) Qt-based / NON-LEGACY.** This is a textbook modern PyMOL plugin. It matches the canonical `lightingsettings_gui` template (cited earlier in this file) exactly: top-level `__init_plugin__(app=None)` → `addmenuitemqt(...)` → a `pymol.Qt` `QDialog`. There is no legacy `def __init__(self)` entry point, no `self.menuBar.addmenuitem(...)`, and no Tk/Pmw import anywhere.

**One caveat (unrelated to Qt-vs-Tk):** Outliner also imports `from PIL import Image` (lines 20-24) — i.e. it depends on Pillow. This is a 3rd-party dep that bioCHEMeleon should NOT inherit. It does not change the Qt classification; it just means "don't copy Outliner's imports wholesale." bioCHEMeleon's UI needs only `pymol.Qt` + stdlib + numpy.

---

### Goal 1b — "show_contacts" (`plugins/show_contacts.py`): HYBRID / transitional (Qt-preferred, Tk fallback)

**Location:** `Pymol-script-repo/plugins/show_contacts.py` (338 lines). Menu label "Show Contacts".

This plugin is the most nuanced of the two. It is **not** a clean modern Qt plugin like Outliner — it is mid-port. The user's expectation that it is "non-legacy" is *directionally* correct (Qt is the primary code path and the Tk path is only a fallback) but *technically* partial: the entry-point signature is still the legacy `def __init__(self):` form, and a full Tk+Pmw GUI class is still present in the file.

**Concrete evidence (quoted lines):**

- The plugin entry point is the LEGACY signature (note `self`, not `app=None`):
  - `show_contacts.py:329` `def __init__(self):`
  - `show_contacts.py:330`     `try:`
  - `show_contacts.py:331`         `from pymol.plugins import addmenuitemqt`
  - `show_contacts.py:332`         `addmenuitemqt('Show Contacts', Show_Contacts_Qt_Dialog)`
  - `show_contacts.py:333`         `return`
  - `show_contacts.py:334`     `except Exception as e:`
  - `show_contacts.py:335`         `print(e)`
  - `show_contacts.py:336`     `self.menuBar.addmenuitem('Plugin', 'command', 'Show Contacts', label = 'Show Contacts', command = lambda s=self : Show_Contacts(s))`

  → The body **tries Qt first** (`addmenuitemqt`) and **returns early on success**; only if Qt registration raises does it fall back to the legacy `self.menuBar.addmenuitem('Plugin', ...)` + the `Show_Contacts` Tk class. So Qt is the preferred/primary path; Tk is the legacy fallback.

- The Qt GUI class (modern):
  - `show_contacts.py:276` `class Show_Contacts_Qt_Dialog(object):`
  - `show_contacts.py:279`     `from pymol.Qt import QtWidgets`
  - `show_contacts.py:280`     `dialog = QtWidgets.QDialog()`
  - `show_contacts.py:305`     `from pymol.Qt import QtCore, QtWidgets`

- The Tk+Pmw GUI class (legacy, kept as fallback):
  - `show_contacts.py:191` `class Show_Contacts:`
  - `show_contacts.py:193`     `def __init__(self, app):`
  - `show_contacts.py:194`         `parent = app.root`            ← legacy Tk-root access pattern
  - `show_contacts.py:199`         `import Pmw`
  - `show_contacts.py:205`         `self.select_dialog = Pmw.Dialog(parent, ...)` ← Pmw megawidget
  - `show_contacts.py:214`         `self.select_object_combo_box = Pmw.ComboBox(...)`

- Pure-Python command (no GUI) also exported:
  - `show_contacts.py:174` `cmd.extend('contacts', show_contacts)` — the `show_contacts` function (lines 15-173) is a GUI-less `cmd`-level command usable from the PyMOL command line. The GUI classes wrap it.

**Classification: (c) hybrid / transitional — primarily Qt, with a legacy Tk+Pmw fallback.** It is *not* a clean `__init_plugin__(app=None)` plugin (the entry symbol is `__init__(self)`), but its runtime behavior on any Qt-capable PyMOL (which is all of PyMOL 2.5.0 conda/Incentive) is Qt: it registers `Show_Contacts_Qt_Dialog` via `addmenuitemqt` and returns before ever touching `Pmw`/`app.root`. The Tk path is dead code on a Qt build.

**What this plugin confirms for the Qt-vs-Tk question:** even a plugin that *kept* its legacy Tk fallback chose to make Qt the primary path and `return` early. That is strong community evidence that Qt is the expected modern default. It also serves as a concrete anti-pattern for bioCHEMeleon: **don't keep a Tk+Pmw fallback class** — on PyMOL 2.5.0 Qt builds the fallback is dead weight, and `app.root` would be `None` anyway (per the `legacysupport.get_tk_root()` finding already cited in this file). Just write a clean `__init_plugin__` + `pymol.Qt` plugin like Outliner.

---

### Repo-wide pattern survey (corroborating evidence)

The `plugins/` directory bifurcates cleanly into two entry-point patterns. This is the strongest evidence that the Qt + `__init_plugin__` pattern is the modern standard.

**Modern Qt plugins — entry point `def __init_plugin__(app=None):` + `addmenuitemqt` + `from pymol.Qt import ...`:**

| File | Entry point line | GUI toolkit | Notes |
|------|------------------|-------------|-------|
| `outline.py` | `:29` `def __init_plugin__(app=None) -> None:` | `pymol.Qt` (`:10-12`) | Outliner — Schrodinger author; `dataclasses`, `from __future__ import annotations` |
| `optimize.py` | `:29` `def __init_plugin__(app=None) -> None:` → `:31` `addmenuitemqt('OpenBabel Optimize', run_plugin_gui)` | `pymol.Qt` (`:25` `from pymol.Qt import QtCore, QtWidgets, QtGui`) | Osvaldo Martin; `QTabWidget` (replaces `Pmw.NoteBook`) |
| `dynoplot.py` | (header) `:10` `# Ported to PyQt 2024 by Thomas Holder` | `pymol.Qt` (`:21`) | Explicit "ported to PyQt 2024" note — migration trend on record |
| `views.py` | `:118` `def __init_plugin__(app=None):` | `pymol.Qt` (uses `pymol.gui.get_qtwindow()`, `addDockWidget`) | Adds a Qt dock widget to the Scene menu |
| `vina.py` | `:1445` `def __init_plugin__(app=None):` → `:1463-1465` `addmenuitemqt("Vina (Run)", ...)` / `addmenuitemqt("Vina (Analyze)", ...)` | `pymol.Qt` | `if __name__ in ["pymol", ...]: __init_plugin__()` at `:1468` |
| `colorama.py` | `:559` `def __init_plugin__(app=None):` → `:564-565` `addmenuitemqt('Colorama', open_colorama)` | `pymol.Qt` | Docstring at `:561` literally reads *"PyMOL 3.x plugin initialization. This function is called by PyMOL when the plugin is loaded."* |

**Legacy Tk plugins — entry point `def __init__(self):` + `self.menuBar.addmenuitem('Plugin', 'command', ...)` (+ `Pmw.Dialog` / `app.root` in the GUI class):**

| File | Entry point line | Toolkit |
|------|------------------|---------|
| `msms.py` | `:78` `def __init__(self):` → `:81` `self.menuBar.addmenuitem('Plugin', 'command', ...)` | Tk+Pmw (`:92` `self.parent = app.root`; `:93` `Pmw.Dialog`) |
| `contact_map_visualizer.py` | `:53` `def __init__(self):` → `:54` `self.menuBar.addmenuitem(...)` | Tk |
| `rendering_plugin.py` | `:40` `def __init__(self):` → `:41` `self.menuBar.addmenuitem(...)` | Tk |
| `mole.py` | `:117` `def __init__(self):` → `:118` `self.menuBar.addmenuitem(...)` | Tk |
| `pytms.py` | `:1884` `def __init__(self):` → `:1889-1890` `self.menuBar.addmenuitem('Plugin', ...)` | Tk |
| `resicolor_plugin.py` | `:14` `def __init__(self):` → `:16` `self.menuBar.addmenuitem(...)` | Tk |
| `SuperSymPlugin.py` | `:26` `def __init__(self):` → `:30+` `self.menuBar.addmenuitem('SuperSym', ...)` | Tk |
| `annocryst.py` | `:42` `def __init__(self):` → `:44` `self.menuBar.addmenuitem(...)` | Tk |
| `castp.py` | `:30` `def __init__(self):` → `:36` `self.menuBar.addmenuitem(...)` | Tk |
| `autodock_plugin.py` | `:105` `def __init__(self):` → `:106` `self.menuBar.addmenuitem(...)` | Tk |

**Hybrid (legacy `__init__(self)` signature, Qt-preferred body, Tk fallback):**

| File | Entry point line | Notes |
|------|------------------|-------|
| `show_contacts.py` | `:329` `def __init__(self):` → `:332` `addmenuitemqt('Show Contacts', Show_Contacts_Qt_Dialog); return` | Qt primary, `self.menuBar.addmenuitem(...)` + `Show_Contacts` (Pmw) fallback |

**Pattern conclusion:** The repo's modern, actively-maintained plugins (6 of them, including a Schrodinger-authored one and one explicitly "Ported to PyQt 2024") ALL use `def __init_plugin__(app=None):` + `addmenuitemqt` + `from pymol.Qt import ...`. The legacy plugins ALL use `def __init__(self):` + `self.menuBar.addmenuitem(...)`. The two entry-point symbols are the reliable classifier — `__init_plugin__` = modern Qt, `__init__(self)` = legacy Tk. Outliner is unambiguously modern; show_contacts is mid-port.

---

### Goal 2 — Plugin Manager install path & bioCHEMeleon packaging

**What the repo tells us about the loader (no system probing):**

1. Every modern repo plugin is a **single `.py` file** at the top of `plugins/`, exporting a **module-level** `def __init_plugin__(app=None):` function. (See `outline.py:29`, `optimize.py:29`, `views.py:118`, `vina.py:1445`, `colorama.py:559`.) The GUI class (`QtWidgets.QDialog` subclass) and the `run_plugin_gui` factory live in the same file or are imported from sibling modules.
2. `vina.py:1468` shows the idiomatic guard for also-runs at startup: `if __name__ in ["pymol", "pmg_tk.startup.XDrugPy"]: __init_plugin__()` — i.e. the loader imports the module under the `pymol` / `pmg_tk.startup.*` package name and then calls `__init_plugin__`.
3. `colorama.py:561` docstring is explicit: *"PyMOL 3.x plugin initialization. This function is called by PyMOL when the plugin is loaded."* — i.e. the loader calls `__init_plugin`.

**Combined with the PyMOL 2.5.0 source findings already cited earlier in this file** (`modules/pymol/plugins/__init__.py` — plugin loader, `__init_plugin__` modern vs `__init__` legacy; `modules/pymol/plugins/installation.py` — install accepts a single `.py` OR a package dir with `__init__.py`; user plugin dir `%APPDATA%/pymol/startup` on Windows, `~/.pymol/startup` on Linux), the install/discovery story is:

- **The GUI Plugin Manager** (PyMOL menu: *Plugin → Plugin Manager → Install New Plugin*) is the standard, platform-universal install path. It invokes `pymol/plugins/installation.py`, which accepts **either** a single `.py` file **or** a package directory containing `__init__.py` **or** a `.zip` archive of a package. It copies the plugin into the per-user startup directory (`%APPDATA%/pymol/startup/` on Windows; `~/.pymol/startup/` on Linux/macOS).
- **At PyMOL startup**, the loader (`pymol/plugins/__init__.py`) imports each installed plugin module/package and calls **`__init_plugin__(app=None)`** if present (modern). If `__init_plugin__` is absent, it falls back to the legacy bound-method `__init__(self)` pattern (this is how the legacy `msms.py`-style plugins still load).
- **The entry-point symbol the Plugin Manager/loader calls is `__init_plugin__(app=None)`.** Inside it, the plugin registers its menu item via `from pymol.plugins import addmenuitemqt` + `addmenuitemqt('<label>', <callable>)`.

**Packaging recommendation for bioCHEMeleon:**

- **Ship as a package directory `biochemeleon/` with an `__init__.py`** that defines `__init_plugin__(app=None)`. Reasons over a single `.py`:
  - The plugin is multi-file by nature (setup-tab GUI, game-status GUI, the `ChameleonWizard` class, game logic, bundled demo PDBs). A package directory keeps these as sibling modules (`gui_setup.py`, `gui_game.py`, `wizard.py`, `game.py`, `demos/`) imported from `__init__.py`.
  - It matches the canonical modern template shipped *inside* PyMOL itself (`data/startup/lightingsettings_gui/__init__.py` + `main.py` — cited earlier in this file). A package dir is the form the Plugin Manager most cleanly copies and the loader most cleanly imports.
  - The demo PDBs (spec: "demo PDB bundled, compress before bundling") can live under `biochemeleon/demos/` and be located via `os.path.dirname(__file__)` — which works identically whether loaded from the repo or from the installed copy in the user plugin dir.
- **Do NOT ship as a `.zip` for v1.** A zip works with the Plugin Manager, but a package directory is easier to debug (you can edit a file and reload without re-zipping) and is what every modern repo example uses. Reserve zip for a future "distribute via PyPI/wiki" phase if ever needed.
- **Entry-point code** (the exact shape the Plugin Manager expects):
  ```python
  # biochemeleon/__init__.py
  from pymol import cmd

  def __init_plugin__(app=None):
      from pymol.plugins import addmenuitemqt
      addmenuitemqt('bioCHEMeleon', run_plugin_gui)

  def run_plugin_gui():
      from .gui_setup import SetupDialog   # QtWidgets.QDialog subclass
      global dialog
      if dialog is None:
          dialog = SetupDialog()
      dialog.show()
  dialog = None
  ```
  This is the Outliner / optimize / lightingsettings_gui pattern verbatim. Do **not** use the `show_contacts` hybrid `def __init__(self):` form — that is the legacy entry signature; on a clean modern build it adds nothing but a Tk fallback that can never render (no Tk root under Qt).

**Platform-universality (Windows conda PyMOL via `setenv.bat` from WSL):**

- The Plugin Manager install path is the **same GUI action on every platform**: *Plugin → Plugin Manager → Install New Plugin → point at the package directory*. It does not depend on any platform-specific directory surgery. This is exactly the universality the user asserted.
- For the WSL-dev / Windows-run setup in PROJECT.md: launch PyMOL on Windows via `setenv.bat` (the `chemtools-win10` conda env), then inside that Windows PyMOL use the Plugin Manager to install. The only WSL consideration is that the Manager's file picker runs in the **Windows** PyMOL process, so it sees Windows paths. Two clean options:
  1. Point the Manager at the package via the Windows→WSL path `\\wsl$\<distro>\…\bioCHEMeleon\biochemeleon\` (or `\\wsl.localhost\…`), then let the Manager copy it into `%APPDATA%/pymol/startup/biochemeleon/`.
  2. Or, for dev iteration, keep the package on the Windows side (e.g. under the project's Windows path) and point the Manager there.
  Either way the install lands in the standard Windows per-user startup dir; the loader finds `biochemeleon/__init__.py` and calls `__init_plugin__` on next PyMOL launch. No `setenv.bat` changes, no `PYTHONPATH` surgery, no manual `cp` into a startup dir.
- **Correction to the earlier "Installation" section of this file:** the prior text presented copy-into-`%APPDATA%/pymol/startup` and "symlink the repo dir" as co-equal install options (b)/(c). The user has clarified that the **Plugin Manager is the standard, universal path**; direct-dir copy and symlink are dev-time conveniences, not the install path to document for end users. The Plugin Manager should be listed first; the others demoted to "dev-only shortcuts."

---

### Reconciliation: Tkinter vs PyQt5 (resolving the FEATURES.md vs STACK/ARCH/PITFALLS split)

- **Prior STACK/ARCHITECTURE/PITFALLS recommendation:** PyQt5 via `pymol.Qt` (HIGH confidence, citing the in-tree `lightingsettings_gui` plugin + official wiki Tk-deprecation + no live Tk root under the Qt GUI).
- **Prior FEATURES.md lean:** `tkinter`/`ttk` as a stdlib "anti-Pmw" option.
- **New evidence from this follow-up:**
  - **Outliner** is a 3rd-party, Schrodinger-authored, modern Qt plugin using the exact `__init_plugin__` + `addmenuitemqt` + `pymol.Qt` pattern — a second concrete exemplar beyond `lightingsettings_gui`.
  - **show_contacts**, even with its legacy entry signature, makes Qt the primary path and keeps Tk only as a fallback — community confirmation that Qt is the expected default.
  - **Six repo plugins** (outline, optimize, dynoplot, views, vina, colorama) all use the modern Qt entry point; **ten** use the legacy Tk entry point; one (show_contacts) is hybrid. The modern, actively-maintained subset is uniformly Qt.
  - `dynoplot.py:10` literally records "Ported to PyQt 2024 by Thomas Holder" — the migration is current and ongoing.

**Verdict: the prior PyQt5-via-`pymol.Qt` recommendation stands and is STRENGTHENED. The new repo evidence does not contradict it; it contradicts FEATURES.md's Tkinter lean.** Reconciliation: **Tkinter/ttk is the legacy path** (dead on PyMOL 2.5.0 Qt builds — `get_tk_root()` returns `None`); **PyQt5 via `pymol.Qt` is the modern, supported, community-adopted path.** FEATURES.md's Tkinter suggestion should be reclassified: Tkinter is NOT a stdlib "anti-Pmw" alternative for this project — it is the *same legacy family* as Pmw (both need a live Tk root, which the Qt build does not provide). The real anti-Pmw move is `pymol.Qt` widgets (`QTabWidget`, `QDialog`, `QComboBox`, `QDoubleSpinBox`), which Outliner and optimize both demonstrate.

**Net for bioCHEMeleon:**
- GUI: PyQt5 via `from pymol.Qt import QtCore, QtGui, QtWidgets` (copy the Outliner/optimize template).
- Entry point: `def __init_plugin__(app=None):` + `addmenuitemqt('bioCHEMeleon', run_plugin_gui)`.
- Packaging: package directory `biochemeleon/` with `__init__.py`; install via the GUI Plugin Manager (universal across Windows/Linux/macOS, works with the WSL-dev / Windows-conda-PyMOL-via-`setenv.bat` workflow).
- Do NOT add a Tk/Pmw fallback class (it is dead code on Qt builds and adds a Pmw dependency that violates the "only libs required by pymol-open-source" rule).

---

### Sources (this follow-up, repo-only)

- `Pymol-script-repo/plugins/outline.py` — full read; `:9-12` (Qt imports), `:29-31` (`__init_plugin__` + `addmenuitemqt`), `:311`/`:326` (`QDialog` "Outliner"), `:4` (Schrodinger author), `:20-24` (Pillow dep — caveat). HIGH.
- `Pymol-script-repo/plugins/show_contacts.py` — full read; `:329-336` (hybrid entry: Qt-try/`return` + Tk-fallback), `:276-284`/`:305` (Qt dialog), `:191-258` (Tk+Pmw fallback class with `app.root` at `:194`, `import Pmw` at `:199`, `Pmw.Dialog`/`Pmw.ComboBox`), `:174` (`cmd.extend` CLI command). HIGH.
- `Pymol-script-repo/plugins/optimize.py` — `:25` (`from pymol.Qt import …`), `:29-31` (`__init_plugin__` + `addmenuitemqt`). HIGH.
- `Pymol-script-repo/plugins/dynoplot.py` — `:10` ("Ported to PyQt 2024 by Thomas Holder"), `:21` (`from pymol.Qt import …`). HIGH.
- `Pymol-script-repo/plugins/views.py` — `:118` (`def __init_plugin__(app=None):`). HIGH.
- `Pymol-script-repo/plugins/vina.py` — `:1445` (`def __init_plugin__(app=None):`), `:1463-1465` (`addmenuitemqt`), `:1468` (`if __name__ in ["pymol", "pmg_tk.startup.XDrugPy"]: __init_plugin__()`). HIGH.
- `Pymol-script-repo/plugins/colorama.py` — `:559-565` (`def __init_plugin__(app=None):` + `addmenuitemqt`; docstring "PyMOL 3.x plugin initialization. This function is called by PyMOL when the plugin is loaded."). HIGH.
- `Pymol-script-repo/plugins/msms.py` — `:78` (`def __init__(self):`), `:81-83` (`self.menuBar.addmenuitem('Plugin', 'command', …)`), `:91-93` (`def __init__(self, app): self.parent = app.root; Pmw.Dialog(...)`) — legacy exemplar for contrast. HIGH.
- `Pymol-script-repo/README.md` — "single file plugins from the PyMOL Wiki" (no install doc; install path inferred from entry-point pattern + prior PyMOL 2.5.0 source findings already cited in this file). MEDIUM (absence of explicit install doc).
- Prior findings already cited earlier in this file (PyMOL 2.5.0 source `pymol/plugins/__init__.py` loader, `pymol/plugins/installation.py` install accepting `.py`/package-dir/zip, user plugin dirs) — HIGH, not re-probed per user instruction.

*Follow-up verification appended: 2026-08-03*
