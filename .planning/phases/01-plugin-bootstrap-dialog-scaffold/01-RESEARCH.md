# Phase 1: Plugin Bootstrap & Dialog Scaffold - Research

**Researched:** 2026-08-03
**Domain:** PyMOL 2.5.0 plugin entry-point + PyQt5 dialog scaffold
**Confidence:** HIGH (entry-point pattern, package structure, dialog scaffold, install mechanism, pitfalls) / MEDIUM (Plugin Manager "Install from directory" quirks on `\\wsl$\` paths — see §9)

---

## Summary

Phase 1 is the **stable shell every later phase builds on**. The deliverable is narrow and mechanical: a `biochemeleon/` package directory that (a) installs cleanly via PyMOL's GUI Plugin Manager, (b) registers a "bioCHEMeleon" item under the Plugins menu on launch via `__init_plugin__(app=None)` + `addmenuitemqt`, and (c) opens a modeless `QDialog` containing a `QTabWidget` with two placeholder tabs ("Setup" and "Game status") when the user clicks that menu item. Everything else — the Setup form fields, the 7 buttons, the DemoLoader, the PymolAdapter, the PickWizard, the game logic — is explicitly out of scope and deferred to later phases.

The technical pattern is fully settled at HIGH confidence by the project research (`.planning/research/STACK.md`, `ARCHITECTURE.md`, `PITFALLS.md`) and verified directly against six modern reference plugins in `Pymol-script-repo/plugins/` (`outline.py`, `optimize.py`, `dynoplot.py`, `views.py`, `vina.py`, `colorama.py`), all of which use the identical `def __init_plugin__(app=None):` + `from pymol.plugins import addmenuitemqt` + `addmenuitemqt(label, run_plugin_gui)` + module-level `dialog = None` singleton + `dialog.show()` (modeless) pattern. The single remaining LOW-confidence gap — "does `pymol.Qt` import actually work in the user's `setenv.bat`-launched conda PyMOL?" — is closed by a one-time smoke test the executor runs in Windows PyMOL (§6). On the conda `pymol-open-source` 2.5.0 build this is expected to pass trivially (PyQt5 is a conda run-dep), but the test is the formal gate that upgrades the last LOW-confidence item to HIGH.

**Primary recommendation:** Build `biochemeleon/__init__.py` with the exact `outline.py`/`optimize.py` entry-point pattern (verbatim shape), put a minimal `PluginDialog(QDialog)` + `QTabWidget` with two placeholder-tab `QWidget`s in the same `__init__.py` (or split into `gui_setup.py`/`gui_game.py` stubs), create the other three named stub modules (`wizard.py`, `game.py`, `demos.py`) as importable placeholders, syntax-check all of it in WSL with `python3.6 -m py_compile`, then install via the Plugin Manager in Windows PyMOL launched by `setenv.bat` + `pymol` and verify the three success criteria.

---

## 1. Phase 1 Scope Summary

**IN scope (Phase 1 deliverables):**
- `biochemeleon/` package directory with `__init__.py` + 5 named sibling modules (PLUGIN-03).
- `__init_plugin__(app=None)` entry point registering `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` (PLUGIN-02).
- Module-level `dialog = None` singleton + `run_plugin_gui()` factory that lazily creates and `.show()`s the dialog (GC prevention; pattern from `outline.py:38-47`, `optimize.py:33-44`).
- `PluginDialog(QtWidgets.QDialog)` with a `QTabWidget` containing two tabs: "Setup" and "Game status", each with placeholder content (a `QLabel` is enough).
- Install via PyMOL GUI Plugin Manager; load on launch without errors (PLUGIN-01).
- End-to-end verification via `setenv.bat` → Windows-conda PyMOL (closes the Qt smoke-test flag).

**Explicitly OUT of scope (deferred to later phases — do NOT build these in Phase 1):**
- Setup form fields (object selector, hider count, lock-scene checkbox, per-rep list, difficulty toggle) → Phase 2.
- The 7 Setup buttons (Reset, Randomize, Save/Load Setup, Generate & export, Cleanup, Start) → Phase 2/4/7/8.
- `DemoLoader` (manifest, bundled PDBs, `data/` layout) → Phase 2.
- `PymolAdapter` read-only `cmd.*` wrappers → Phase 2.
- `ObjectMutator`, `HiderRegistry` → Phase 3.
- `PickWizard`, `GameController`, `GameTab` real content, `SphereStrategy` → Phase 4.
- `to_windows_path()` helper — **note**: PITFALLS.md says this lands in Phase 0-1 (the "setup" phase). Phase 1 doesn't load any files, so the *runtime* path helper is not strictly needed yet. BUT the *install path itself* crosses the WSL/Windows boundary (§5, §8 Pitfall 11), so the planner should be aware of it. Recommendation: defer the `to_windows_path()` helper to Phase 2 (when `DemoLoader` first loads a file) but document the WSL→Windows install path here.
- Any `cmd.*` calls beyond what the entry point needs (which is none — Phase 1 is pure GUI scaffold).

**Phase boundary rationale:** Phase 1 proves the plugin loads, registers, and opens a window. Nothing more. Every later phase assumes this shell works. If Phase 1 is wrong (e.g., Tk accidentally used, dialog GC'd, modal blocks viewer), every later phase inherits the bug. Keep Phase 1 tiny and correct.

---

## 2. Exact Entry-Point Pattern

The pattern below is the verbatim shape used by `outline.py` (Schrodinger-authored, the cleanest modern template), `optimize.py`, and `colorama.py`. Copy this shape exactly.

### 2.1 The `__init_plugin__(app=None)` signature

```python
# biochemeleon/__init__.py

def __init_plugin__(app=None):
    """
    PyMOL plugin entry point. Called by the PyMOL plugin loader once at
    startup (or on manual plugin load via the Plugin Manager).
    Registers a menu item under the Plugins menu.
    """
    from pymol.plugins import addmenuitemqt
    addmenuitemqt('bioCHEMeleon', run_plugin_gui)
```

**Source citations:**
- `outline.py:29-31` — `def __init_plugin__(app=None) -> None:` + `from pymol.plugins import addmenuitemqt` + `addmenuitemqt('Outliner', run_plugin_gui)`.
- `optimize.py:29-31` — identical shape, label `'OpenBabel Optimize'`.
- `colorama.py:559-565` — identical shape; docstring literally reads *"PyMOL 3.x plugin initialization. This function is called by PyMOL when the plugin is loaded."*

**Critical details:**
1. **Signature is `def __init_plugin__(app=None):`** — NOT `def __init__(self):`. The `__init__(self)` form is the **legacy Tk entry point** (used by `msms.py:78`, `mole.py:117`, `pytms.py:1884`, etc.). The loader checks for `__init_plugin__` first; only if absent does it fall back to the legacy `__init__(self)` class pattern. Modern plugins use `__init_plugin__`.
2. **`addmenuitemqt` is imported INSIDE the function** (local import), not at module top level. This is deliberate and consistent across all 6 modern reference plugins. If the import were at module top level and failed (no Qt), the entire module would fail to import. By keeping it local to `__init_plugin__`, a Qt failure is caught cleanly by the loader (which prints `"Plugin 'X' only available with PyQt GUI."` and skips registration) rather than crashing the whole module load.
3. **`addmenuitemqt(label, callable)`** — first arg is the menu label string (must be `'bioCHEMeleon'` per PLUGIN-02); second arg is a callable (the `run_plugin_gui` factory function) invoked when the user clicks the menu item. The callable takes no args.
4. **`addmenuitemqt` is itself the fail-fast Qt check.** Per PyMOL 2.5.0 source (`modules/pymol/plugins/__init__.py`), `addmenuitemqt` raises `QtNotAvailableError` if no Qt binding is available; the plugin loader catches this and prints a diagnostic. No additional Qt-availability check is needed in `__init_plugin__` — `addmenuitemqt` IS the check. (See §6 for the smoke-test procedure and an optional diagnostic-enhanced variant.)

### 2.2 The lazy singleton `dialog = None` pattern (GC prevention)

```python
# Module-level singleton — MUST be at module scope, not inside __init_plugin__
dialog = None

def run_plugin_gui():
    """
    Create the dialog on first open, reuse on subsequent opens.
    The module-level `dialog` ref prevents Python from garbage-collecting
    the QDialog (without it, the window flashes and vanishes immediately).
    """
    global dialog
    if dialog is None:
        dialog = PluginDialog()
    dialog.show()
    dialog.raise_()        # bring to front (colorama.py:555 pattern)
    dialog.activateWindow()  # optional, for focus (colorama.py:556)
```

**Source citations:**
- `outline.py:46-47` — `# global reference to avoid garbage collection` / `dialog = None`.
- `outline.py:34-43` — `def run_plugin_gui():` with `global dialog` + lazy create + `dialog.show()`.
- `optimize.py:33-44` — identical pattern.
- `colorama.py:545-556` — uses `_colorama_dialog = None` (prefixed name) + `show()` + `raise_()` + `activateWindow()`. Also adds a `isVisible()` check before recreating.

**Why `dialog = None` must be module-level (not inside `__init_plugin__`):** The singleton ref must persist for the entire PyMOL session. If it were a local variable inside `__init_plugin__`, it would be garbage-collected when `__init_plugin__` returns (immediately after startup), and the first `run_plugin_gui` call would create a dialog with no persistent ref → it vanishes instantly. The module-level `dialog = None` is the canonical fix — verified in all 6 modern reference plugins.

**`dialog.show()` vs `dialog.exec_()`:** Always `.show()` (modeless). NEVER `.exec_()` (modal — blocks the PyMOL event loop and the 3D viewer). See §4 for the modal-vs-modeless decision.

### 2.3 Complete minimal `__init__.py` entry-point section

```python
# biochemeleon/__init__.py
"""bioCHEMeleon — a hide-and-seek molecular game plugin for PyMOL 2.5.0."""

# Module-level singleton dialog reference (GC prevention — see outline.py:46)
dialog = None


def __init_plugin__(app=None):
    """PyMOL plugin entry point. Registers the Plugins-menu item."""
    from pymol.plugins import addmenuitemqt
    addmenuitemqt('bioCHEMeleon', run_plugin_gui)


def run_plugin_gui():
    """Lazily create and show the plugin dialog (singleton)."""
    global dialog
    if dialog is None:
        dialog = PluginDialog()
    dialog.show()
    dialog.raise_()
    dialog.activateWindow()
```

(`PluginDialog` class defined further down in the same file, or imported from a sibling — see §3, §4.)

---

## 3. Package Structure for PLUGIN-03

### 3.1 The `__init__.py` vs `__init_plugin__` distinction (resolve the naming confusion)

These two names are **completely different things** that share a confusing prefix. The planner/executor must not conflate them:

| Name | What it is | Required? | Who uses it |
|------|-----------|-----------|-------------|
| `__init__.py` | A **file** (the Python package marker). Its presence makes `biochemeleon/` an importable Python package. | YES — required for ANY package directory. The PyMOL Plugin Manager won't recognize a dir as a plugin package without it. | Python's import system + PyMOL plugin loader |
| `__init_plugin__` | A **function** defined inside `__init__.py` (module-level). The PyMOL loader calls it to register the plugin. | YES — the modern PyMOL 2.x entry point. | PyMOL plugin loader only |

**Loader flow for a package-directory plugin** (verified against PyMOL 2.5.0 source `modules/pymol/plugins/__init__.py` + `installation.py`, cited in STACK.md):
1. Plugin Manager copies the package dir into the per-user startup dir (`%APPDATA%/pymol/startup/biochemeleon/` on Windows).
2. At PyMOL launch, the loader imports each startup plugin as a Python package: `import biochemeleon` → this runs `biochemeleon/__init__.py`.
3. The loader then looks for `biochemeleon.__init_plugin__` in the imported module's namespace. If present, it calls `__init_plugin__(app=None)`.
4. If `__init_plugin__` is absent, the loader falls back to the legacy `__init__(self)` class-instantiation pattern (the Tk-era entry point — NOT what we want).

**Net:** `__init__.py` makes it a package; `__init_plugin__` (inside `__init__.py`) makes it a PyMOL plugin. Both are required. Define `__init_plugin__` as a top-level function inside `__init__.py`.

### 3.2 Package layout (matches PLUGIN-03's named files)

PLUGIN-03 (from REQUIREMENTS.md) explicitly names the multi-file structure: *"Plugin packaged as a `biochemeleon/` package directory with `__init__.py` (multi-file: gui_setup, gui_game, wizard, game, demos)."* This is a **flat** 5-module layout, not the nested `gui/`/`game/`/`pymol_io/` structure in ARCHITECTURE.md. **Follow PLUGIN-03's flat naming** — it is the locked requirement.

```
biochemeleon/
├── __init__.py       # POPULATED: __init_plugin__ + addmenuitemqt + run_plugin_gui + dialog singleton + PluginDialog class
├── gui_setup.py      # POPULATED (minimal): SetupTab(QWidget) placeholder for Phase 1; full form in Phase 2
├── gui_game.py       # POPULATED (minimal): GameTab(QWidget) placeholder for Phase 1; full content in Phase 4
├── wizard.py         # STUB: empty/comment — PickWizard lands in Phase 4
├── game.py           # STUB: empty/comment — GameController + HiderRegistry land in Phase 3/4
└── demos.py          # STUB: empty/comment — DemoLoader lands in Phase 2
```

**Phase 1 population vs stubs:**

| File | Phase 1 status | Minimal content |
|------|----------------|-----------------|
| `__init__.py` | **POPULATED** | Entry point + singleton + `PluginDialog` (QDialog + QTabWidget + 2 tabs). See §2.3 + §4. |
| `gui_setup.py` | **POPULATED (placeholder)** | `class SetupTab(QtWidgets.QWidget)` with a `QLabel("Setup — coming in Phase 2")`. Must be importable + constructible so `PluginDialog` can `addTab(SetupTab(), "Setup")`. |
| `gui_game.py` | **POPULATED (placeholder)** | `class GameTab(QtWidgets.QWidget)` with a `QLabel("Game status — coming in Phase 4")`. Same constructibility requirement. |
| `wizard.py` | **STUB** | A module docstring `"""PickWizard — populated in Phase 4."""` is enough. No class needed yet (nothing imports it in Phase 1). |
| `game.py` | **STUB** | A module docstring `"""GameController, HiderRegistry — populated in Phase 3/4."""` is enough. |
| `demos.py` | **STUB** | A module docstring `"""DemoLoader — populated in Phase 2."""` is enough. |

**Why `gui_setup.py` and `gui_game.py` must be constructible (not empty stubs):** The Phase-1 success criterion 3 requires the dialog to actually show two tabs with placeholder content. `PluginDialog` will `addTab(SetupTab(), "Setup")` and `addTab(GameTab(), "Game status")`, so both classes must exist and instantiate to a valid `QWidget`. The stub modules (`wizard.py`, `game.py`, `demos.py`) are never imported in Phase 1, so they can be docstring-only.

**Where does `PluginDialog` live?** Two valid options for Phase 1:
- **Option A (recommended for Phase 1):** Define `PluginDialog` in `__init__.py` itself. Simplest; matches `outline.py`'s "everything in one file" approach (adapted to a package). The dialog is small enough for Phase 1 (just a QDialog + QTabWidget + 2 placeholder tabs).
- **Option B:** Define `PluginDialog` in a separate module (e.g., a new `gui_dialog.py`) and import it in `__init__.py`. Cleaner separation but adds a file PLUGIN-03 doesn't name.

Recommendation: **Option A** for Phase 1 (keep it in `__init__.py`). If `PluginDialog` grows large in later phases, extract it then. PLUGIN-03 doesn't name a `gui_dialog.py`, so don't add one in Phase 1.

**Note on the ARCHITECTURE.md nested structure:** ARCHITECTURE.md envisions a deeper `gui/`, `game/`, `pymol_io/`, `util/` tree. That is the aspirational final structure. PLUGIN-03's flat 5-module naming is the locked requirement. The planner should build the flat structure now; a refactor to nested subpackages can happen in a later phase if module count grows. Do NOT over-engineer the directory tree in Phase 1.

### 3.3 Minimal placeholder tab modules (ready to paste)

```python
# biochemeleon/gui_setup.py
"""Setup tab — populated with the full config form in Phase 2."""
from pymol.Qt import QtWidgets


class SetupTab(QtWidgets.QWidget):
    """Placeholder Setup tab. Phase 2 adds the object selector, hider count,
    lock-scene checkbox, per-rep list, difficulty toggle, and 7 buttons."""

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(QtWidgets.QLabel("Setup — coming in Phase 2"))
```

```python
# biochemeleon/gui_game.py
"""Game status tab — populated with timer/remaining/info/buttons in Phase 4."""
from pymol.Qt import QtWidgets


class GameTab(QtWidgets.QWidget):
    """Placeholder Game status tab. Phase 4 adds the rolling info box, timer,
    remaining counter, and hint/reveal/save/restart buttons."""

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(QtWidgets.QLabel("Game status — coming in Phase 4"))
```

```python
# biochemeleon/wizard.py
"""PickWizard (pymol.wizard.Wizard subclass) — populated in Phase 4."""
```

```python
# biochemeleon/game.py
"""GameController + HiderRegistry — populated in Phase 3/4."""
```

```python
# biochemeleon/demos.py
"""DemoLoader (manifest + bundled PDBs) — populated in Phase 2."""
```

---

## 4. PluginDialog Scaffold

### 4.1 The dialog class (QDialog + QTabWidget, two placeholder tabs)

```python
# Inside biochemeleon/__init__.py (Option A) — or a separate module (Option B)

from pymol.Qt import QtCore, QtGui, QtWidgets


class PluginDialog(QtWidgets.QDialog):
    """bioCHEMeleon main dialog: a tabbed window with Setup and Game status tabs."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("bioCHEMeleon")
        self.setMinimumWidth(420)

        # Tab widget (pattern from optimize.py:73 — QTabWidget replaces Pmw.NoteBook)
        self.tabs = QtWidgets.QTabWidget(self)

        # Placeholder tabs — import the widget classes lazily inside __init__
        # so a bug in a sibling module doesn't break plugin load.
        from .gui_setup import SetupTab
        from .gui_game import GameTab

        self.setup_tab = SetupTab()
        self.game_tab = GameTab()

        self.tabs.addTab(self.setup_tab, "Setup")
        self.tabs.addTab(self.game_tab, "Game status")

        # Layout
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.tabs)
```

**Source citations:**
- `optimize.py:53-79` — `class OptimizeDialog(QtWidgets.QDialog)` with `self.tabs = QtWidgets.QTabWidget()` + `self._create_local_opt_tab()` / `self._create_global_opt_tab()` / `self._create_about_tab()` + `self.tabs.addTab(local_tab, " Local optimization ")`. Comments explicitly note `# Tab widget (replaces Pmw.NoteBook)`.
- `outline.py:311-326` — `class RepresentationOutlineDialog(QtWidgets.QDialog)` + `self.setWindowTitle("Outliner")`.

**Key patterns:**
1. **`from pymol.Qt import QtCore, QtGui, QtWidgets`** — NEVER `from PyQt5 import ...`. `pymol.Qt` auto-selects PyQt5/PySide2/PyQt4/PySide; raw `from PyQt5 import` breaks on PySide2 builds. (STACK.md "What NOT to Use"; `outline.py:10-12`, `optimize.py:25`.)
2. **`QDialog`, not `QMainWindow`.** A `QDialog` is the right top-level for a plugin panel (matches all 6 reference plugins). `QMainWindow` is overkill (adds menu bar/status bar the plugin doesn't need).
3. **`QTabWidget` for the two tabs.** This is the direct modern replacement for the legacy `Pmw.NoteBook` (per `optimize.py:72` comment). Tab labels must be exactly `"Setup"` and `"Game status"` (per success criterion 3 + SETUP-01).
4. **Lazy import of `SetupTab`/`GameTab` inside `PluginDialog.__init__`.** This keeps `__init__.py` importable even if a sibling stub has a runtime issue — the import only runs when the dialog is first constructed (on first menu click), not at plugin load. This is a defensive pattern; the reference plugins import at top level because they're single-file. For a multi-file package, lazy import in `__init__` is safer.
5. **`self.setMinimumWidth(420)`** — optional but reasonable; prevents the dialog from being too narrow. `optimize.py:61` uses `self.setMinimumWidth(450)`.

### 4.2 Modal vs modeless decision: MODELESS (`dialog.show()`)

**Decision: use `dialog.show()` (modeless). NEVER `dialog.exec_()` (modal).**

**Reference plugins' choice:** All 6 modern reference plugins use `.show()` (modeless):
- `outline.py:43` — `dialog.show()`
- `optimize.py:42` — `dialog.show()`
- `colorama.py:554` — `_colorama_dialog.show()`

**Reasoning:**
1. **The core game loop (Phase 4+) requires the user to click atoms in the 3D viewer while the dialog is open.** A modal dialog (`exec_()`) blocks the PyMOL event loop and the viewer — the user couldn't click anything. This is PITFALLS.md Pitfall 1: *"For modeless behavior (player must click atoms in the viewer while the game panel is open), use `dialog.show()` — never `dialog.exec_()` (which is modal and blocks the PyMOL event loop)."*
2. **Even in Phase 1 (no clicking yet), modeless is the right default** because (a) it matches all reference plugins, (b) every later phase needs modeless, and (c) changing modal→modeless later is a trivial one-liner that's easy to forget.
3. **`emovie.py` has a literal comment** `# self.grab_set()  #comment this out so that user can keep storyboard open` — direct evidence that modal grab blocks PyMOL viewer interaction (PITFALLS.md cites this).

**Do NOT call `QApplication.exec_()` either** — PyMOL already runs its own Qt event loop. The plugin just shows its dialog and lets PyMOL's loop drive it. (PITFALLS.md "Integration Gotchas": *"Use the existing pymol.Qt QApplication; dialog.show() only, never call exec_() on a new loop."*)

### 4.3 Anti-patterns to avoid in the Phase-1 dialog

- **DO NOT** inherit from `tkinter.Tk` / `tkinter.Toplevel` / `Pmw.Dialog` (Pitfall 1 — see §8).
- **DO NOT** call `dialog.exec_()` or `app.exec_()` (modal / spins a new event loop).
- **DO NOT** use `grab_set()` (Tk modal grab — blocks viewer).
- **DO NOT** import `from PyQt5 import ...` (use `from pymol.Qt import ...`).
- **DO NOT** put the `dialog = None` singleton inside `__init_plugin__` (must be module-level for GC prevention).
- **DO NOT** build the Setup form fields or buttons in Phase 1 (out of scope — see §1).

---

## 5. Install Mechanism for the WSL→Windows-conda Workflow

### 5.1 How `setenv.bat` launches PyMOL (READ THE FILE — critical detail)

`setenv.bat` (repo root, 23 lines) does **only one thing: it activates the `chemtools-win10` conda env in the current cmd session.** It does **NOT** launch PyMOL. Concretely:

```bat
set CONDAPATH=C:\ProgramData\Miniconda3
set ENVNAME=chemtools-win10
if %ENVNAME%==base (set ENVPATH=%CONDAPATH%) else (set ENVPATH=%USERPROFILE%\.conda\envs\%ENVNAME%)
call %CONDAPATH%\Scripts\activate.bat %ENVPATH%
```

**Key facts the planner/executor must internalize:**
1. **Conda env name: `chemtools-win10`** (locked; from `setenv.bat:12`).
2. **Conda env path: `%USERPROFILE%\.conda\envs\chemtools-win10`** — note this is under the user profile's `.conda/envs/`, NOT the default `C:\ProgramData\Miniconda3\envs/`. This is a user-local env. (from `setenv.bat:18`).
3. **Miniconda root: `C:\ProgramData\Miniconda3`** (from `setenv.bat:10`).
4. **`setenv.bat` ends after `activate.bat`** — there is no `pymol` or `pymol.exe` invocation. The user must run `pymol` in the SAME cmd session after `setenv.bat` activates the env.

**The actual launch sequence (what the user runs):**
- **Option 1 (Windows cmd, interactive):** Open `cmd.exe` → `cd` to the repo root → run `setenv.bat` → run `pymol`. Two commands in the same cmd window.
- **Option 2 (from WSL, one-liner):** `cmd.exe /c "setenv.bat && pymol"` run from the repo root. This activates the env then launches PyMOL in one go.
- **Option 3 (WSL, two-step):** `cmd.exe /c setenv.bat` then `cmd.exe /c pymol` — but this does NOT work because each `cmd.exe /c` is a separate session; the env activation from the first doesn't persist to the second. **Use Option 2 (`&&`) for the one-liner.**

### 5.2 How the Plugin Manager discovers and installs plugins

Per PyMOL 2.5.0 source (`modules/pymol/plugins/installation.py`, cited in STACK.md at HIGH confidence):

1. **Plugin Manager GUI path:** In PyMOL: `Plugin → Plugin Manager → Install New Plugin`.
2. **The file picker accepts:** a single `.py` file OR a **package directory** containing `__init__.py` OR a `.zip` of a package. For bioCHEMeleon, point it at the **`biochemeleon/` package directory**.
3. **Install destination:** The Manager copies the plugin into the per-user startup directory:
   - **Windows:** `%APPDATA%/pymol/startup/biochemeleon/` (i.e., `C:\Users\<user>\AppData\Roaming\pymol\startup\biochemeleon\`)
   - **Linux/macOS:** `~/.pymol/startup/biochemeleon/`
4. **Auto-load on next launch:** On the NEXT PyMOL launch (not the current one), the loader (`pymol/plugins/__init__.py`) imports each startup plugin package and calls `__init_plugin__(app=None)`. So: **install via Manager → restart PyMOL → menu item appears.** (The Manager may also offer to load the plugin immediately in the current session — if so, the menu item can appear without a restart. But the reliable gate is: restart and confirm it auto-loads.)
5. **Plugin Settings (Settings tab of Plugin Manager):** Installed plugins can be enabled/disabled. If a plugin is installed but disabled, its menu item won't appear. The default state after install is "enabled". If the menu item doesn't show after restart, check `Plugin Manager → Settings` and ensure `biochemeleon` is enabled.

### 5.3 The concrete install path for the WSL-dev / Windows-run workflow

The Plugin Manager's file picker runs in the **Windows PyMOL process**, so it sees **Windows paths**, not WSL paths. The repo lives at `C:\Users\nglok\Desktop\WORKDIR\molmdl\bioCHEMeleon\` (Windows path) = `/mnt/c/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/` (WSL path). Two clean install options:

**Option A (recommended — point Manager at the Windows path directly):**
The repo is already on the Windows filesystem (`C:\...`). In the Plugin Manager file picker, navigate to `C:\Users\nglok\Desktop\WORKDIR\molmdl\bioCHEMeleon\biochemeleon\` and select the `biochemeleon` folder. The Manager copies it to `%APPDATA%/pymol/startup/biochemeleon/`.

**Option B (WSL path via `\\wsl$\`):**
If the repo were on the WSL filesystem (not the Windows side), point the file picker at `\\wsl$\<distro>\…\bioCHEMeleon\biochemeleon\` (or `\\wsl.localhost\…` on newer Windows). Since this repo is on `C:\` (the Windows side, accessed from WSL as `/mnt/c/`), **Option A is simpler** — no `\\wsl$\` indirection needed.

**Dev-iteration shortcuts (NOT the documented end-user install, but useful during Phase 1):**
- **Direct copy:** `copy /s biochemeleon %APPDATA%\pymol\startup\biochemeleon` (Windows cmd) — bypasses the Manager; useful for rapid edit→reload cycles.
- **Symlink (dev-only):** `mklink /D %APPDATA%\pymol\startup\biochemeleon C:\...\biochemeleon` (Windows cmd, admin) — the loader follows the symlink; edits in the repo are live without re-copying.
- These are **dev conveniences only.** The documented end-user install (README.md, PLUGIN-01) is the GUI Plugin Manager.

### 5.4 Does the plugin auto-load on launch, or need a restart / manual enable?

- **After install via Manager:** The Manager copies the package to the startup dir. The menu item appears on the **next PyMOL launch** (the loader scans the startup dir at launch). Some Manager flows offer "load now" — if so, the item can appear immediately. The **reliable verification gate** is: install → quit PyMOL → relaunch via `setenv.bat` + `pymol` → confirm "bioCHEMeleon" is under the Plugins menu.
- **Manual enable:** If the menu item doesn't appear after restart, check `Plugin Manager → Settings` → ensure `biochemeleon` is in the installed list and enabled (not disabled). Default post-install state is enabled.

---

## 6. Qt Runtime Smoke-Test Procedure

**Purpose:** Close the last LOW-confidence gap from SUMMARY.md ("Phase 0-1: Qt-vs-Tk runtime validation — confirm `pymol.Qt` import works in the setenv.bat-launched PyMOL"). On the conda `pymol-open-source` 2.5.0 build this is expected to pass trivially (PyQt5 is a conda run-dep), but this test is the formal gate that upgrades the item to HIGH confidence. **Since this agent cannot run Windows PyMOL from Linux, this section DEFINES the exact procedure the executor will run later. Do not attempt to execute it from WSL.**

### 6.1 What the smoke test proves

1. `from pymol.Qt import QtWidgets` does not raise `ImportError` in the user's conda PyMOL.
2. `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` does not raise `QtNotAvailableError` during `__init_plugin__`.
3. The plugin loads on launch without errors and the "bioCHEMeleon" menu item appears.
4. Clicking the menu item opens the dialog with two visible tabs.

If all four pass, the Qt-vs-Tk question is empirically settled for the user's env and the LOW-confidence flag is closed.

### 6.2 The fail-fast code (already in `__init_plugin__` via `addmenuitemqt`)

`addmenuitemqt` is itself the fail-fast: per PyMOL 2.5.0 source (`modules/pymol/plugins/__init__.py`), it raises `QtNotAvailableError` if no Qt binding is available, and the loader catches it and prints `"Plugin '%s' only available with PyQt GUI."`. No additional check is strictly needed. The minimal entry point (§2.3) already fails fast.

**Optional diagnostic-enhanced variant** (clearer console message if Qt is missing — useful for the smoke test, harmless if Qt is present):

```python
def __init_plugin__(app=None):
    """PyMOL plugin entry point. Registers the Plugins-menu item."""
    try:
        from pymol.Qt import QtWidgets  # noqa: F401 — fail-fast Qt availability probe
    except ImportError as e:
        print("[bioCHEMeleon] ERROR: Qt binding not available (%s)" % e)
        print("[bioCHEMeleon] This plugin requires PyQt5 (bundled with conda pymol-open-source).")
        print("[bioCHEMeleon] If you see this, PyMOL was launched without a Qt GUI (-x / batch mode).")
        return  # don't register the menu item; the game needs the GUI
    from pymol.plugins import addmenuitemqt
    addmenuitemqt('bioCHEMeleon', run_plugin_gui)
```

This variant is optional — the reference plugins (`outline.py`, `optimize.py`) do NOT have it; they rely on `addmenuitemqt`'s built-in check. The diagnostic variant just gives a friendlier message. The planner can choose either; the minimal variant (§2.3) is sufficient.

### 6.3 Exact user steps (the executor runs these in Windows, NOT in WSL)

**Precondition:** Phase 1 code is written and `py_compile`-checked in WSL (§7.1). The `biochemeleon/` package dir exists at `C:\Users\nglok\Desktop\WORKDIR\molmdl\bioCHEMeleon\biochemeleon\`.

**Step 1 — Install the plugin via the Plugin Manager:**
1. Launch Windows `cmd.exe` (not WSL).
2. `cd` to the repo root: `cd C:\Users\nglok\Desktop\WORKDIR\molmdl\bioCHEMeleon`
3. Activate the conda env: `setenv.bat`
4. Launch PyMOL: `pymol`
   - (One-liner from WSL: `cmd.exe /c "setenv.bat && pymol"` from the repo root.)
5. In PyMOL: `Plugin → Plugin Manager → Install New Plugin`.
6. In the file picker, navigate to `C:\Users\nglok\Desktop\WORKDIR\molmdl\bioCHEMeleon\` and select the **`biochemeleon`** folder (the package directory, NOT the repo root).
7. Confirm the install. The Manager should report success and copy the package to `%APPDATA%\pymol\startup\biochemeleon\`.

**Step 2 — Restart PyMOL and verify clean load:**
8. Quit PyMOL (`File → Quit` or close the window).
9. Relaunch: `setenv.bat` then `pymol` (same cmd session or fresh one).
10. **Watch the PyMOL console (the text output window) for errors during launch.**
    - **PASS:** No errors/tracebacks mentioning `biochemeleon` or `pymol.Qt` or `addmenuitemqt`. (A missing-Qt message would be a FAIL, but on conda pymol-open-source this won't happen — PyQt5 is a run-dep.)
    - **FAIL:** Any `ImportError`, `QtNotAvailableError`, `ModuleNotFoundError`, or traceback mentioning `biochemeleon`.

**Step 3 — Verify the menu item appears:**
11. In the running PyMOL, open the **Plugins** menu (top menu bar).
12. **PASS:** A **"bioCHEMeleon"** item is visible in the Plugins menu.
    - **FAIL:** "bioCHEMeleon" is missing. Check `Plugin Manager → Settings` → ensure `biochemeleon` is enabled. If missing entirely, the install step failed silently — re-check Step 1.

**Step 4 — Verify clicking opens the dialog with two tabs:**
13. Click **Plugins → bioCHEMeleon**.
14. **PASS:** A window titled "bioCHEMeleon" opens. It contains a tab bar with two tabs: **"Setup"** and **"Game status"**. Clicking each tab shows its placeholder content ("Setup — coming in Phase 2" / "Game status — coming in Phase 4").
    - **FAIL (dialog flashes and vanishes):** The `dialog = None` singleton is not module-level (GC ate it). Check §2.2.
    - **FAIL (dialog doesn't appear at all):** `run_plugin_gui` raised. Check the PyMOL console for a traceback.
    - **FAIL (dialog appears but blocks the viewer — can't rotate the 3D scene):** `dialog.exec_()` was used instead of `dialog.show()` (modal). Check §4.2.
    - **FAIL (window appears but has no tabs):** `QTabWidget` setup is wrong. Check §4.1.

**Step 5 — Verify the viewer is not blocked (modeless check):**
15. With the bioCHEMeleon dialog open, click into the 3D viewer and try to rotate the scene (drag with mouse).
16. **PASS:** The 3D scene rotates normally; the dialog stays open but doesn't block interaction.
    - **FAIL:** The viewer is unresponsive while the dialog is open → modal dialog bug (§4.2).

### 6.4 Expected outcome

On conda `pymol-open-source` 2.5.0 with the `chemtools-win10` env, **all steps should PASS** because:
- PyQt5 is a conda run-dep of `pymol-open-source` (verified in the conda-forge feedstock `meta.yaml`, cited in STACK.md).
- `pymol.Qt` auto-selects PyQt5 (verified in `modules/pymol/Qt/__init__.py`).
- `addmenuitemqt` works whenever Qt is available (verified in `modules/pymol/plugins/__init__.py`).
- The entry-point + singleton + `.show()` pattern is the verified canonical form (6/6 modern reference plugins).

If any step FAILS, the failure mode tells us exactly what's wrong (§6.3 Step 4 enumerates the failure modes). The most likely failure (if any) is a WSL→Windows path issue during install (Step 1), not a Qt issue.

---

## 7. Verification Strategy for Phase 1

Phase 1 verification is **split across two environments** because of the hard WSL constraint (spec.md: "DO NOT install anything" in WSL; `python3.6` only for syntax checks). The planner must encode both tiers as separate verification steps.

### 7.1 WSL tier — syntax checks only (runnable in WSL python3.6)

WSL `python3.6` has NO PyMOL, NO PyQt5, NO `pymol.Qt`. It can only run `py_compile`, which checks **syntax** but does NOT execute imports or runtime code. (Verified: `py_compile` passes on a file containing `from pymol.Qt import QtWidgets` even though `pymol.Qt` is not installed in WSL — `py_compile` does not resolve imports.)

**WSL verification commands (runnable from the repo root):**

```bash
# Syntax-check every Phase-1 module
python3.6 -m py_compile biochemeleon/__init__.py
python3.6 -m py_compile biochemeleon/gui_setup.py
python3.6 -m py_compile biochemeleon/gui_game.py
python3.6 -m py_compile biochemeleon/wizard.py
python3.6 -m py_compile biochemeleon/game.py
python3.6 -m py_compile biochemeleon/demos.py
```

**What this catches:** syntax errors (unclosed parens, bad indentation, missing colons, invalid Python).
**What this does NOT catch:** `ImportError` (e.g., `from pymol.Qt import` fails because pymol isn't in WSL), `AttributeError`, runtime logic errors, wrong class hierarchy, dialog not showing, modal blocks viewer, GC'd dialog, menu item missing.

**Pitfall-1 grep checks (runnable in WSL — see §8):**

```bash
# Must return ZERO matches (no Tkinter/Pmw anywhere in the plugin)
grep -rn -E "import[[:space:]]+(Tkinter|tkinter|Pmw)|from[[:space:]]+(Tkinter|tkinter|Pmw)|app\.root|grab_set|menuBar\.addmenuitem|def[[:space:]]__init__\(self\)" biochemeleon/
# Should return matches (confirm pymol.Qt is used, not PyQt5 directly)
grep -rn "from pymol.Qt import" biochemeleon/
# Must return ZERO matches (no raw PyQt5 import)
grep -rn "from PyQt5 import\|import PyQt5" biochemeleon/
# Must return ZERO matches (no dialog.exec_ modal call)
grep -rn "\.exec_()" biochemeleon/
```

### 7.2 Windows tier — functional checks (requires user to run PyMOL via `setenv.bat`)

The three Phase-1 success criteria **cannot be verified in WSL** — they require a running PyMOL with PyQt5. The executor must hand these steps to the user (or run them via `cmd.exe /c "setenv.bat && pymol"` if the agent can drive Windows cmd). The exact procedure is §6.3 (the smoke test). Mapping to success criteria:

| Success Criterion | Verification step (from §6.3) | Environment |
|-------------------|------------------------------|-------------|
| 1. Installs via Plugin Manager + loads on launch without errors | Steps 1-2 (install, restart, check console for errors) | Windows PyMOL via `setenv.bat` |
| 2. "bioCHEMeleon" menu item appears; clicking opens dialog | Steps 3-4 (check menu, click, dialog opens) | Windows PyMOL |
| 3. Dialog shows tabbed interface with "Setup" and "Game status" tabs | Step 4 (two tabs visible with placeholder content) | Windows PyMOL |

**Additional functional check (modeless — critical for later phases):** Step 5 (viewer not blocked while dialog open). This is not a Phase-1 success criterion per se, but verifying it now prevents a Phase-4 rewrite.

### 7.3 What "done" looks like for Phase 1

- All 6 `py_compile` commands pass in WSL (§7.1).
- All 4 Pitfall-1 grep checks pass (no Tkinter/Pmw/app.root/exec_; pymol.Qt used; no raw PyQt5) (§7.1, §8).
- The user confirms §6.3 Steps 1-5 all PASS in Windows PyMOL.
- The repo has a `biochemeleon/` package dir with 6 files matching §3.2.

---

## 8. Pitfalls Active in Phase 1

Two pitfalls from `.planning/research/PITFALLS.md` directly affect Phase 1. Both are prevention-by-pattern (cheap to avoid now, expensive to retrofit later).

### 8.1 Pitfall 1 — Tkinter/Pmw GUI (the must-not list)

**What goes wrong in Phase 1:** If the dialog is accidentally built with `tkinter`/`Pmw` (copying from a legacy reference plugin like `msms.py` or `mole.py`), it won't render under the Qt GUI build (`get_tk_root()` returns `None`), or it renders but modal `grab_set()` blocks the viewer, or the menu item doesn't register (legacy `__init__(self)` entry instead of `__init_plugin__`).

**Concrete MUST-NOT list for the biochemeleon/ codebase:**

| Must NOT appear | Why | Use instead |
|-----------------|-----|-------------|
| `import Tkinter` / `import tkinter` / `from tkinter import ...` | Legacy; no live Tk root under Qt GUI | `from pymol.Qt import QtWidgets, QtCore, QtGui` |
| `import Pmw` / `from Pmw import ...` | Not bundled with pymol-open-source; unmaintained | `QtWidgets.QTabWidget`, `QDialog`, `QGroupBox`, etc. |
| `app.root` | `legacysupport.get_tk_root()` returns `None` under Qt | N/A — no Tk parent |
| `grab_set()` | Tk modal grab; blocks viewer | `dialog.show()` (modeless) |
| `self.menuBar.addmenuitem(...)` | Legacy Tk entry-point registration | `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` |
| `def __init__(self):` (as the plugin entry point) | Legacy Tk entry signature | `def __init_plugin__(app=None):` |
| `mainloop()` | Spins a competing event loop | Let PyMOL's Qt event loop drive the dialog |
| `Toplevel(...)` | Tk top-level window | `QtWidgets.QDialog(...)` |
| `Pmw.NoteBook` | Legacy tab widget | `QtWidgets.QTabWidget` |
| `Pmw.Dialog` | Legacy dialog | `QtWidgets.QDialog` |

**Verification grep patterns (runnable in WSL — §7.1):**
```bash
# Must return ZERO matches:
grep -rn -E "import[[:space:]]+(Tkinter|tkinter|Pmw)|from[[:space:]]+(Tkinter|tkinter|Pmw)|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|Pmw\.|def[[:space:]]__init__\(self\)" biochemeleon/
```

**Why this matters in Phase 1 specifically:** Pitfall 1's recovery cost is HIGH (full UI rewrite). If Tk leaks in during Phase 1, every later phase inherits a broken foundation. Catch it now with the grep; the prevention is just "use the §2/§4 patterns verbatim."

### 8.2 Pitfall 11 — WSL/Windows path mismatch

**What goes wrong in Phase 1:** The *install path itself* crosses the WSL/Windows boundary. The repo is at `/mnt/c/Users/.../bioCHEMeleon/` (WSL view) = `C:\Users\...\bioCHEMeleon\` (Windows view). The Plugin Manager's file picker runs in the Windows PyMOL process and sees Windows paths. If the user tries to pass a `/mnt/c/...` path to the Manager, it won't resolve.

**Phase 1 does NOT load files** (no `cmd.load`, no `DemoLoader`, no bundled PDBs) — so the *runtime* `to_windows_path()` helper is NOT needed yet. But the *install step* (§5.3) already crosses the boundary: the planner must instruct the user to point the Manager at the **Windows path** (`C:\Users\nglok\Desktop\WORKDIR\molmdl\bioCHEMeleon\biochemeleon\`), not the WSL path (`/mnt/c/...`).

**What Phase 1 should do:**
- **DO** document the install path as a Windows path in the verification steps (§6.3, §5.3).
- **DO NOT** build the `to_windows_path()` helper yet — it has no runtime consumer in Phase 1. Defer it to Phase 2 (when `DemoLoader` first calls `cmd.load` on a bundled PDB). PITFALLS.md maps this helper to "setup" phase, but since Phase 1 loads no files, the earliest phase that actually needs it is Phase 2.
- **DO** note in the Phase-1 plan that the `to_windows_path()` helper + an end-to-end `cmd.load` test is a Phase-2 deliverable (so the planner doesn't forget it then).

**Warning signs (if the install fails):** `Plugin Manager` reports "No `__init__.py` found" or "Invalid plugin directory" → the user pointed at the wrong path (probably a `/mnt/c/...` path the Windows file picker can't resolve, or the repo root instead of the `biochemeleon/` subfolder). Fix: point at `C:\...\biochemeleon\` (the package dir, Windows path).

---

## 9. Open Questions / Risks for the Planner

These are MEDIUM/LOW-confidence items that affect plan structure. The planner should encode mitigation for each.

### 9.1 Plugin Manager "Install from directory" quirks on the package dir (MEDIUM)

**Question:** Does the conda PyMOL 2.5.0 Plugin Manager reliably accept a package *directory* (not a `.py` file or `.zip`)?

**What we know (HIGH):** PyMOL 2.5.0 source `modules/pymol/plugins/installation.py` accepts a single `.py` OR a package dir with `__init__.py` OR a `.zip` (cited in STACK.md). All 6 modern reference plugins are single `.py` files, so there's no direct repo evidence of a *package dir* install — but the source code supports it.

**What's unclear:** Whether the Manager's GUI file picker on Windows cleanly handles "select a folder" vs "select a file." Some PyMOL versions' file pickers default to selecting files and need an explicit "directory" mode.

**Mitigation for the planner:** Encode a fallback in the verification steps: if "Install from directory" with the `biochemeleon/` folder doesn't work, fall back to (a) zipping the folder and installing the `.zip`, or (b) direct-copying the folder to `%APPDATA%\pymol\startup\biochemeleon\` (§5.3 dev shortcut). The direct-copy fallback always works because the loader scans the startup dir at launch regardless of how the plugin got there.

### 9.2 Does the menu item need the plugin enabled in Plugin Settings? (LOW)

**Question:** After install, is the plugin enabled by default, or could it be installed-but-disabled?

**What we know (HIGH):** Default post-install state is "enabled." The menu item appears on next launch if enabled.

**Mitigation:** Encode a verification sub-step: if the menu item is missing after restart, check `Plugin Manager → Settings` → ensure `biochemeleon` is enabled. (Already in §6.3 Step 3 FAIL branch.)

### 9.3 Conda env name and path from `setenv.bat` (LOW — confirmed, but flag for the executor)

**Fact:** `setenv.bat` locks `ENVNAME=chemtools-win10` and `ENVPATH=%USERPROFILE%\.conda\envs\chemtools-win10`. The executor must use exactly this env name. If the user's env is named differently, `setenv.bat` must be edited first — but per spec, `setenv.bat` is the authoritative launcher, so this is a given.

**Risk:** If the executor assumes the default conda envs dir (`C:\ProgramData\Miniconda3\envs\`), they won't find the env — it's under `%USERPROFILE%\.conda\envs\`. The `setenv.bat` handles this correctly; the executor just needs to run `setenv.bat` and trust it.

### 9.4 Whether `pmg_qt` or `pmg_tk` is the external GUI on the user's open-source build (LOW — but doesn't affect the plugin)

**Nuance:** STACK.md notes a subtlety — the open-source `pymol-open-source` build's `pmg_qt` module is a "3-line dummy module placeholder" (the real Qt external GUI is closed-source Incentive-only). So the open-source build's *external* GUI may default to `pmg_tk` (Tk). BUT this is **irrelevant to the plugin's toolkit**: the *plugin* GUI is PyQt5 via `pymol.Qt` regardless of which external GUI hosts it. `pymol.Qt` + `addmenuitemqt` work whenever PyQt5 is installed (which it is, as a conda run-dep), even when the external GUI is Tk-based. The plugin's Qt dialog renders as a Qt window inside the (possibly Tk-hosted) environment.

**Why this is LOW risk for Phase 1:** The plugin uses `pymol.Qt` (PyQt5), not the external GUI's toolkit. The smoke test (§6) confirms `pymol.Qt` works empirically. No plan mitigation needed beyond the smoke test.

### 9.5 `dynoplot.py` uses `def __init_plugin__(self):` not `(app=None)` — minor inconsistency in the reference repo (LOW)

**Observation:** `dynoplot.py:445` uses `def __init_plugin__(self):` (with `self` instead of `app=None`) — a slightly non-canonical signature, despite being "Ported to PyQt 2024." This still works because the loader calls `__init_plugin__` and doesn't strictly enforce the signature, but it's not the clean form.

**Recommendation:** Follow `outline.py`/`optimize.py`/`colorama.py`'s canonical `def __init_plugin__(app=None):` signature, NOT `dynoplot.py`'s `(self)` variant. The `app=None` form is the documented, future-proof signature (it receives the PyMOL app object if the loader passes one; `None` if not).

### 9.6 Whether to include a `raise_()` / `activateWindow()` call (LOW)

**Observation:** `outline.py` uses just `dialog.show()`. `colorama.py:554-556` uses `dialog.show()` + `dialog.raise_()` + `dialog.activateWindow()`. The latter brings the dialog to front and gives it focus, which is slightly better UX if PyMOL's window is in front.

**Recommendation:** Include `raise_()` + `activateWindow()` (the colorama pattern) — it's harmless and improves UX. Already in §2.2/§2.3.

---

## Sources

### Primary (HIGH confidence — project research, already verified)
- `.planning/research/STACK.md` — PyQt5 via `pymol.Qt` recommendation; `__init_plugin__` vs legacy `__init__`; `addmenuitemqt` raises `QtNotAvailableError`; `pymol.Qt` auto-selects PyQt5/PySide2/PyQt4/PySide; Plugin Manager accepts `.py`/package-dir/`.zip`; user plugin dir `%APPDATA%/pymol/startup/` (Windows); conda-forge `pymol-open-source` run-dep `pyqt`; the FOLLOW-UP VERIFICATION section (6/6 modern plugins use `__init_plugin__` + `pymol.Qt`).
- `.planning/research/ARCHITECTURE.md` — Pattern 1 (Plugin entry point + lazy singleton dialog); Pattern 3 (Singleton dialog with QTabWidget); component table (`__init_plugin__`, `PluginDialog`); `dialog = None` GC-prevention pattern; `.show()` modeless.
- `.planning/research/PITFALLS.md` — Pitfall 1 (Tkinter — must-not list, recovery cost HIGH); Pitfall 11 (WSL/Windows path — `to_windows_path()` helper, install path crosses boundary); "Looks Done But Isn't" checklist (missing `global dialog` → dialog flashes and disappears).
- `.planning/research/SUMMARY.md` — Phase 0-1 research flag (Qt-vs-Tk runtime smoke test); key risks; build order rationale.

### Primary (HIGH confidence — reference plugins, directly read)
- `Pymol-script-repo/plugins/outline.py` — Schrodinger-authored modern Qt template. `:29-31` (`__init_plugin__(app=None)` + `addmenuitemqt`), `:34-43` (`run_plugin_gui` + `global dialog` + lazy create + `.show()`), `:46-47` (`dialog = None` "global reference to avoid garbage collection"), `:311-326` (`QDialog` subclass + `setWindowTitle`). Caveat: `:20-24` imports Pillow — do NOT copy.
- `Pymol-script-repo/plugins/optimize.py` — `:25` (`from pymol.Qt import QtCore, QtWidgets, QtGui`), `:29-31` (`__init_plugin__`), `:33-44` (`run_plugin_gui` + `dialog = None`), `:53-79` (`OptimizeDialog(QDialog)` + `QTabWidget` + `addTab`), `:72` comment `# Tab widget (replaces Pmw.NoteBook)`.
- `Pymol-script-repo/plugins/colorama.py` — `:545-556` (`_colorama_dialog = None` + `show()` + `raise_()` + `activateWindow()`), `:559-565` (`__init_plugin__(app=None)` with docstring *"PyMOL 3.x plugin initialization. This function is called by PyMOL when the plugin is loaded."*).
- `Pymol-script-repo/plugins/dynoplot.py` — `:10` ("Ported to PyQt 2024 by Thomas Holder"), `:21` (`from pymol.Qt import QtCore, QtGui, QtWidgets`), `:445-447` (`__init_plugin__(self)` — non-canonical `(self)` signature; use `(app=None)` instead per §9.5).
- `Pymol-script-repo/plugins/vina.py` — `:1445` (`__init_plugin__(app=None)`), `:1463-1465` (two `addmenuitemqt` calls), `:1469` (`if __name__ in ["pymol", ...]: __init_plugin__()`).

### Primary (HIGH confidence — environment files, directly read)
- `setenv.bat` (repo root) — `CONDAPATH=C:\ProgramData\Miniconda3`, `ENVNAME=chemtools-win10`, `ENVPATH=%USERPROFILE%\.conda\envs\chemtools-win10`, ends after `activate.bat` (does NOT launch `pymol`).
- `spec.md` (repo root) — WSL constraint ("DO NOT install anything"), `setenv.bat` is the Windows-conda access path, PyMOL 2.5.0 from anaconda.
- `.gitignore` (repo root) — `Pymol-script-repo` and `3rd_party_lib/**` are git-ignored; `.planning` is NOT ignored.
- `README.md` (repo root) — documented install via Plugin Manager; `\\wsl$\` note for WSL dev.
- `.planning/REQUIREMENTS.md` — PLUGIN-01/02/03 exact text; PLUGIN-03 names the 5 modules (`gui_setup, gui_game, wizard, game, demos`).
- `.planning/ROADMAP.md` — Phase 1 goal/scope/success criteria.
- `.planning/config.json` — `commit_docs: true` (planning docs are committed).

### Empirically verified during this research
- WSL `python3.6 -m py_compile` passes on a stub containing `from pymol.Qt import QtWidgets` even though `pymol.Qt` is not installed in WSL — confirms `py_compile` checks syntax only, not imports (§7.1). Python 3.6.9 confirmed available.

---

## Metadata

**Confidence breakdown:**
- Entry-point pattern (`__init_plugin__` + `addmenuitemqt` + singleton): **HIGH** — 6/6 modern reference plugins + PyMOL 2.5.0 source + in-tree `lightingsettings_gui` template all agree verbatim.
- Package structure (`biochemeleon/` dir + 5 named modules): **HIGH** — PLUGIN-03 locks the naming; PyMOL source confirms package-dir install.
- Dialog scaffold (QDialog + QTabWidget + modeless `.show()`): **HIGH** — `optimize.py` is a direct analogue; Pitfall 1 forbids the modal/Tk alternatives.
- Install mechanism (Plugin Manager → startup dir → load on launch): **HIGH** for the mechanism, **MEDIUM** for the GUI file-picker "select folder" UX on Windows (§9.1).
- Qt smoke-test procedure: **HIGH** (procedure is well-defined) — the *outcome* is expected PASS but must be empirically confirmed by the executor (closes the last LOW-confidence gap).
- Pitfalls (1 and 11): **HIGH** — directly from project PITFALLS.md, verified against reference plugins.

**Research date:** 2026-08-03
**Valid until:** 2026-09-03 (30 days — stable domain; PyMOL 2.5.0 and the reference plugins are not fast-moving)
