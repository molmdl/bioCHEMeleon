# Architecture Research

**Domain:** PyMOL 2.5.0 plugin — interactive "molecular hide-and-seek" game (foreign atoms blended INTO an existing PyMOL object, click-to-find).
**Researched:** 2026-08-02
**Confidence:** HIGH (plugin mechanics, picking, save/load, object-mutation) / MEDIUM (GUI toolkit choice — see Decision Required) / HIGH (build order)

---

## ⚠️ Decision Required Before Build: GUI Toolkit (Tkinter vs Qt)

The spec (`spec.md`, `PROJECT.md`) says **"Tkinter GUI"**, but the PyMOL 2.5.0 plugin ecosystem has migrated to **Qt (PyQt)**. This is the single most consequential architectural decision and must be settled before Phase 1.

| Source | Evidence | Confidence |
|--------|----------|------------|
| Official `pymol-open-source/modules/pymol/plugins/__init__.py` | `addmenuitemqt(...)` is "Intended for plugins which open a PyQt window"; raises `QtNotAvailableError` if no Qt; on load failure prints `"Plugin '%s' only available with PyQt GUI."` | HIGH |
| `Pymol-script-repo/plugins/optimize.py` (2024) | Code comments literally say `"# Header label (replaces the original Tkinter Label)"` and `"# Tab widget (replaces Pmw.NoteBook)"` — documenting the Tk→Qt migration | HIGH |
| `show_contacts.py` | Ships BOTH a `Show_Contacts` (Tk/Pmw) and `Show_Contacts_Qt_Dialog` class; `__init__` tries Qt first, falls back to Tk | HIGH |
| Newest plugins (`outline.py`, `vina.py`, `views.py`, `dynoplot.py`) | All use `from pymol.Qt import QtCore, QtGui, QtWidgets` | HIGH |

**Recommendation: use Qt via `pymol.Qt`.** Rationale:
1. `pymol.Qt` is a thin shim that works regardless of which Qt binding (PyQt5/PyQt6/PySide2/PySide6) the anaconda PyMOL 2.5.0 was built against — code is portable.
2. The legacy Tk path requires `Pmw` (Python MegaWidgets) for `NoteBook`/`Dialog`; **Pmw is not guaranteed to be installed** in the anaconda env, and is unmaintained.
3. Picking (`do_pick`) and the OpenGL viewer are independent of GUI toolkit, so choosing Qt does not affect the core game mechanic.
4. The legacy `__init__(self)` + `self.menuBar.addmenuitem(...)` path is still *present* in PyMOL 2.5 but only fires when the Tk external GUI is active — anaconda PyMOL 2.5.0 launches the Qt external GUI by default.

**If the user explicitly requires Tkinter** (e.g., they have a Tk-only build or a hard constraint), the architecture below still applies — only the `gui/` module swaps `pymol.Qt` → `tkinter`/`ttk` + optional `Pmw`, and the entry point uses `__init__(self)` with `self.menuBar.addmenuitem`. **This swap must be validated in Phase 1** by confirming which external GUI the `setenv.bat`-launched PyMOL actually starts.

The rest of this document is written for the **Qt (recommended)** path, with Tkinter alternatives noted where they diverge.

---

## Standard Architecture

### System Overview

bioCHEMeleon is a **single-process plugin** running inside the PyMOL host. There is no backend, no networking, no threads needed for v1. All state lives in one Python module namespace plus the PyMOL session. The architecture is layered so that **game logic never calls Qt directly** and **GUI never calls `cmd` directly except through thin controller methods** — this keeps the click→found→refresh loop traceable and testable.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GUI LAYER  (gui/)  — Qt widgets only, holds NO game logic, NO cmd calls  │
│  ┌──────────────────────┐   ┌──────────────────────────┐                 │
│  │ SetupTab(QWidget)     │   │ GameTab(QWidget)          │                │
│  │  - params form        │   │  - timer/remaining labels │                │
│  │  - 7 buttons          │   │  - hint/reveal/save/restart│               │
│  └──────────┬────────────┘   └─────────────┬────────────┘                │
│             │  signals/callbacks            │  signals/callbacks          │
│  ┌──────────┴────────────────────────────────┴────────────┐              │
│  │              PluginDialog(QDialog, singleton)          │              │
│  │              QTabWidget: [Setup | Game status]          │              │
│  └──────────────────────────┬─────────────────────────────┘              │
└─────────────────────────────┼────────────────────────────────────────────┘
                              │  calls controller methods only
┌─────────────────────────────┴────────────────────────────────────────────┐
│  CONTROLLER / GAME-LOGIC LAYER  (game/)  — pure Python, Qt-free, testable │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ GameController │ │ HiderGenerator│ │ HiderRegistry│ │ StateStore   │    │
│  │  - start()    │ │  - by_rep()    │ │  - index→status│ │  - save/load │    │
│  │  - on_pick()  │ │  - line/stick/  │ │  - found/hidden │ │  - .pse+JSON │    │
│  │  - hint()     │ │     cartoon/   │ │  - per-rep counts│ │              │    │
│  │  - reveal()   │ │     sphere     │ │                  │ │              │    │
│  │  - restart()  │ │                │ │                  │ │              │    │
│  └──────┬────────┘ └───────┬────────┘ └────────┬─────────┘ └──────┬──────┘    │
│         │                  │                   │                 │            │
└─────────┼──────────────────┼───────────────────┼─────────────────┼───────────┘
          │                  │                   │                 │
┌─────────┴──────────────────┴───────────────────┴─────────────────┴───────────┐
│  PYMOL INTEROP LAYER  (pymol_io/)  — the ONLY place that calls cmd.*          │
│  ┌──────────────┐  ┌───────────────┐  ┌────────────────┐  ┌──────────────┐    │
│  │PymolAdapter │  │ PickWizard     │  │ ObjectMutator  │  │ DemoLoader   │    │
│  │ - get_names  │  │ (Wizard subclass│ │ - backup_obj  │  │ - bundle list│    │
│  │ - get_reps   │  │  do_pick→cb   │  │ - add_hider_atoms│ │ - fetch large│    │
│  │ - iterate_idx│  │ - activate/   │  │ - remove_atoms │  │ - cache dir  │    │
│  │ - color/set  │  │   deactivate  │  │ - restore_obj  │  │ - sources    │    │
│  └──────┬───────┘  └───────────────┘  └────────────────┘  └──────────────┘    │
└─────────┼──────────────────────────────────────────────────────────────────┘
          │  cmd.*  (PyMOL C API)
┌─────────┴───────────────────────────────────────────────────────────────────┐
│  PYMOL CORE  — cmd API  +  OpenGL viewer (internal)  +  session (.pse)     │
└────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation | Talks To |
|-----------|----------------|----------------------|----------|
| **`__init_plugin__`** (entry) | Register the Plugin-menu item; create singleton dialog lazily | `def __init_plugin__(app=None): addmenuitemqt('bioCHEMeleon', show_dialog)` | plugins engine, PluginDialog |
| **PluginDialog** (gui) | Hold the QTabWidget; route button signals to GameController; own the singleton lifetime | `QDialog` + module-level `dialog = None` ref to avoid GC (see `optimize.py`, `outline.py`) | SetupTab, GameTab, GameController |
| **SetupTab** (gui) | Params form + 7 buttons; emits intents ("start", "randomize", "cleanup"); never mutates PyMOL | `QWidget` with `QFormLayout`/`QGridLayout` | PluginDialog |
| **GameTab** (gui) | Timer label, remaining counters, rolling info box, hint/reveal/save/restart buttons | `QWidget`, `QTimer` for ticking display | PluginDialog |
| **GameController** (logic) | The orchestrator: `start()`, `on_pick(index)`, `hint()`, `reveal_one/all()`, `save()`, `restart()`, `cleanup()`. Holds reference to registry + state + pymol adapter. | Plain Python class; the "brain" | HiderGenerator, HiderRegistry, StateStore, PymolAdapter, PickWizard, GUI (via callbacks to refresh) |
| **HiderGenerator** (logic) | Decide *where* and *what* hider atoms to create per representation. Pure geometry decisions; delegates actual atom insertion to `ObjectMutator`. | One strategy class per rep: `LineStickStrategy`, `CartoonStrategy`, `SphereStrategy` | PymolAdapter (read geometry), ObjectMutator (insert) |
| **HiderRegistry** (logic) | The source of truth for hider atom identity + status. Maps `int index → {rep, status, found_at, hint_used}`. | `dict` + per-rep counters; built right after generation; **not** persisted across a `cmd.sort()` | GameController, StateStore (serializes it) |
| **StateStore** (logic) | Save/load: writes `.pse` (PyMOL session, via cmd) + `.bcm` companion JSON (game metadata: registry, timer, setup params, reveal counts). | JSON sidecar; `.pse` via `cmd.save`/`cmd.load` | GameController, PymolAdapter, HiderRegistry |
| **PickWizard** (pymol_io) | The atom-picking callback bridge. Subclasses `pymol.wizard.Wizard`, overrides `do_pick`, forwards the picked atom's `index` to `GameController.on_pick`. | `class PickWizard(Wizard)`; activated by `cmd.set_wizard(wiz)`; deactivated by `cmd.set_wizard()` | GameController (callback), PyMOL core |
| **PymolAdapter** (pymol_io) | Thin wrapper over `cmd.*` for queries: `get_names`, `get_reps`, `iterate_index`, `color`, `show/hide`, `select`. All read-only-ish cmd calls go here so logic layer stays Qt/cmd-free. | functions / static methods | PyMOL core |
| **ObjectMutator** (pymol_io) | The ONLY component that **adds/removes atoms** in the target object. `backup_original()`, `add_hider_atoms(spec)`, `remove_hider_atoms(indices)`, `restore_original()`. | `cmd.pseudoatom` + `cmd.create` merge + chempy `get_model`/`load_model` fallback (see Object-Mutation Safety) | PyMOL core, HiderGenerator |
| **DemoLoader** (pymol_io) | Bundled-small-PDB manifest + on-demand fetch for large membrane PDBs; caching + source attribution. | manifest JSON in `data/`; `cmd.fetch` for large; `urllib` (stdlib, no approval needed) | PyMOL core, data dir |

---

## Recommended Project Structure

```
bioCHEMeleon/
├── __init__.py                 # Plugin entry: def __init_plugin__(app=None)
├── opencode.json               # (existing) agent config
├── setenv.bat                  # (existing) Windows conda launcher
├── spec.md / .planning/...     # (existing) project planning
├── Pymol-script-repo/          # (git-ignored) reference plugins
├── 3rd_party_lib/              # (git-ignored) approved vendored libs, if any
├── data/
│   ├── manifest.json           # demo PDB catalog: id, category, size, source, license, bundled?
│   ├── sources.md              # human-readable citations (SASBDB, MemProtMD, RCSB)
│   ├── protein/                # bundled small PDBs (committed, compressed)
│   │   ├── 1znf.pdb.gz
│   │   ├── 1xdn.pdb.gz
│   │   └── ...
│   ├── nucleic/
│   │   ├── 5e54.pdb.gz
│   │   ├── 1k8p.pdb.gz
│   │   └── 2qbz.pdb.gz
│   ├── mixed/
│   │   └── 4wb3.pdb.gz
│   ├── glycoprotein/           # SASBDB Alpha-1-glycoprotein
│   │   └── <id>.pdb.gz
│   └── cache/                  # (git-ignored) on-demand fetched large PDBs
│       └── membrane/          # 1GZM, 3GP6 (MemProtMD, stripped+compressed)
├── biochemeleon/               # <<< the plugin package (importable as one unit)
│   ├── __init__.py             # re-exports __init_plugin__ for the plugin loader
│   ├── gui/
│   │   ├── __init__.py
│   │   ├── dialog.py           # PluginDialog (singleton QDialog + QTabWidget)
│   │   ├── setup_tab.py        # SetupTab widget
│   │   ├── game_tab.py         # GameTab widget (timer, remaining, buttons)
│   │   └── widgets.py          # small reusable widgets (RollingInfoBox, etc.)
│   ├── game/
│   │   ├── __init__.py
│   │   ├── controller.py       # GameController (orchestrator)
│   │   ├── registry.py         # HiderRegistry (index → status)
│   │   ├── state.py            # StateStore (.pse + .bcm JSON save/load)
│   │   ├── setup.py            # SetupParams dataclass (the 7-button config)
│   │   └── generators/
│   │       ├── __init__.py     # rep → strategy dispatch
│   │       ├── base.py         # HiderStrategy interface
│   │       ├── line_stick.py
│   │       ├── cartoon.py
│   │       └── sphere.py
│   ├── pymol_io/
│   │   ├── __init__.py
│   │   ├── adapter.py          # PymolAdapter (read-only cmd wrappers)
│   │   ├── mutator.py          # ObjectMutator (add/remove/restore atoms)
│   │   ├── pickwizard.py       # PickWizard(Wizard) — click callback bridge
│   │   └── demo_loader.py      # DemoLoader (manifest + fetch + cache)
│   └── util/
│       ├── __init__.py
│       ├── constants.py       # rep names, colors, caps, default params
│       └── ids.py             # hider residue/atom naming scheme (see Registry)
├── tests/                      # pytest, syntax-checkable in WSL python3.6 (no PyMOL needed for pure-logic)
│   ├── test_registry.py
│   ├── test_setup.py
│   └── test_generators_geometry.py
└── README.md                   # install instructions, demo sources
```

### Structure Rationale

- **`biochemeleon/` as an importable package:** The PyMOL plugin loader (verified in `plugins/__init__.py`) discovers `.py` files **or directories with `__init__.py`** on the startup path. A package (not a single flat `.py`) is the right shape for a structured, traceable repo per the user's "clean, structured" constraint. The top-level `__init__.py` defines `__init_plugin__`.
- **`gui/` vs `game/` vs `pymol_io/` split:** Enforces the layering in the diagram. `game/` has zero `cmd`/Qt imports → unit-testable in WSL python3.6 without PyMOL installed (satisfies the "syntax check in WSL" constraint and gives real test value, not just syntax). `pymol_io/` is the only layer that imports `pymol`.
- **`generators/` as a strategy per representation:** The spec mandates 3 different hider-placement algorithms (line/stick, cartoon, sphere) + explicit "surface NOT supported". A strategy class per rep makes the unsupported-surface case a clean `raise NotSupported` in dispatch, and lets cartoon (the hardest, "L" complexity) be developed/phased independently.
- **`data/` layout mirrors `manifest.json`:** small PDBs committed (offline demos work), large membrane PDBs fetched into git-ignored `cache/`. Sources in `sources.md` satisfy the "cite sources" requirement.
- **`tests/` for pure logic only:** HiderRegistry, SetupParams defaults, generator geometry math. PyMOL-dependent code can't run in WSL (no PyMOL, no installs), so those tests would run in the Windows conda env manually. Keep the WSL-runnable tests honest about what they cover.

---

## Architectural Patterns

### Pattern 1: Plugin entry point + lazy singleton dialog

**What:** The plugin loader calls `__init_plugin__(pmgapp)` once at startup (verified: `legacyinit` checks `__init_plugin__` first, then `__init__`). Register only a menu item there; build the heavy dialog lazily on first open.

**When to use:** Always — this is the canonical PyMOL 2.5 plugin entry.

**Trade-offs:** Lazy build = first-open has a small delay but PyMOL startup stays fast; singleton avoids leaking duplicate dialogs.

**Example:**
```python
# biochemeleon/__init__.py
from pymol.plugins import addmenuitemqt

_dialog = None  # module-level ref to prevent GC (pattern from optimize.py/outline.py)

def __init_plugin__(app=None):
    addmenuitemqt('bioCHEMeleon', _show_dialog)

def _show_dialog():
    global _dialog
    if _dialog is None:
        from .gui.dialog import PluginDialog
        _dialog = PluginDialog()
    _dialog.show()
    _dialog.raise_()
```

### Pattern 2: Wizard for atom-picking callbacks (THE click-to-find bridge)

**What:** PyMOL's canonical interactive-atom-picking mechanism is the **Wizard**. Subclass `pymol.wizard.Wizard`, override `do_pick(self, picked_bond)`. Activate with `cmd.set_wizard(wiz)` — this puts the viewer in picking mode so left-clicks select atoms. Deactivate with `cmd.set_wizard()`. The picked atom lands in the `(sele)` selection; read its internal `index` from there.

**When to use:** This is the ONLY clean, supported way to get a Python callback when the user clicks an atom in the OpenGL viewer. Verified against `mtsslWizard.py` (uses `do_pick` + `pick_count` + reads `(sele)`) and the official `Wizard` wiki page (`cmd.wizard(name)` / `cmd.set_wizard()`).

**Trade-offs:**
- Pro: Native, reliable, no need to poll or hijack mouse buttons.
- Pro: Wizard's `get_panel()` can show a contextual right-side menu ("Done", "Hint") in the viewer — a natural place for in-game prompts.
- Con: Only one wizard active at a time — bioCHEMeleon must install/uninstall its wizard on start/restart/exit and not clobber a user's existing wizard (cache and restore it).
- Con: `do_pick` fires on **any** pick; we must filter to our target object's atoms and ignore picks on other objects.

**Example:**
```python
# biochemeleon/pymol_io/pickwizard.py
from pymol.wizard import Wizard
from pymol import cmd, stored

class PickWizard(Wizard):
    def __init__(self, controller, target_object):
        Wizard.__init__(self)
        self.controller = controller        # GameController
        self.target = target_object
        self._saved_wizard = None

    def activate(self):
        self._saved_wizard = cmd.get_wizard()   # don't clobber user's wizard
        cmd.set_wizard(self)

    def deactivate(self):
        cmd.set_wizard(self._saved_wizard)       # restore (or None)

    def do_pick(self, picked_bond):               # PyMOL calls this on click
        # picked atom is in (sele); read its (model, index)
        rec = []
        cmd.iterate("(sele) and model %s" % self.target,
                    "rec.append((model, index))", space={"rec": rec})
        if rec:
            self.controller.on_pick(rec[0][1])   # forward internal index
        cmd.deselect()                            # clear (sele) for next pick

    def get_panel(self):                         # optional right-side viewer menu
        return [[1, 'bioCHEMeleon', ''],
                [2, 'Give up (reveal all)', 'cmd.get_wizard().controller.reveal_all()'],
                [2, 'Done', 'cmd.get_wizard().deactivate()']]
```

**Why `index` and not `ID`/`rank`:** Verified from the Iterate wiki page:
- `index` (int): *"internal atom index (**unique per object**, sensitive to sorting and removing of atoms, cannot be altered)"* ← **use this**.
- `ID`: "PDB atom id (not guaranteed to be unique)" ← do NOT use.
- `rank`: "atom index from original file import (not guaranteed to be unique)" ← do NOT use.

**Alternative (also viable):** `cmd.identify("sele")` returns atom IDs from the current pick selection without a wizard. This is simpler but only works if the user is already in a picking mouse mode; the Wizard pattern is more robust because it *forces* picking mode and gives a callback. The FEATURES.md sibling research leaned on `cmd.identify`; both compose — `do_pick` can call `cmd.identify` internally. Use the Wizard as the primary mechanism.

### Pattern 3: Singleton dialog with explicit tab state

**What:** One `QDialog` holding a `QTabWidget` with two tabs (Setup, Game status). Tab switching is driven by `GameController` state, not by user free-clicking — Setup→Game happens on Start (with a 3-2-1 countdown), Game→Setup happens on Restart/Cleanup.

**When to use:** Multi-tab plugins. `optimize.py` uses `QTabWidget` (Local/Global/About) — direct analogue to the legacy `Pmw.NoteBook` used by `msms.py`/`pyanm.py`/`emovie.py`.

**Trade-offs:** Locking tab order to game state prevents the confusing state where a user clicks Setup mid-game and changes params under a live game. Make Setup tab read-only/disabled during active play.

**Example:**
```python
# biochemeleon/gui/dialog.py
from pymol.Qt import QtWidgets

class PluginDialog(QtWidgets.QDialog):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("bioCHEMeleon")
        self.tabs = QtWidgets.QTabWidget()
        self.setup_tab = SetupTab(on_start=self._on_start, ...)
        self.game_tab  = GameTab(on_hint=..., on_reveal=..., on_save=..., on_restart=...)
        self.tabs.addTab(self.setup_tab, "Setup")
        self.tabs.addTab(self.game_tab,  "Game status")
        self.tabs.tabBar().setTabEnabled(1, False)   # Game tab locked until Start
        layout = QtWidgets.QVBoxLayout(self); layout.addWidget(self.tabs)
        self._controller = GameController(self)      # wire logic ↔ gui

    def _on_start(self, params):
        self._controller.start(params)               # logic owns the transition
```

### Pattern 4: Companion-file save — `.pse` + `.bcm` JSON

**What:** PyMOL sessions (`.pse`) capture the molecular state (objects, reps, coords, hider atoms) but **know nothing about game metadata** (which atoms are hiders, found-status, timer, reveal counts, setup params). So save TWO files with the same basename: `<name>.pse` (via `cmd.save`) + `<name>.bcm` (JSON, our metadata). Load reverses both.

**When to use:** Any plugin with state beyond the molecular scene. **Verified** against `emovie.py`: it saves `<name>.pse` via `cmd.do("save %s.pse" % fileName)` and `<name>.emov` via `pickle.dump` of the storyboard/scene/morph lists; load reverses both. bioCHEMeleon uses JSON (human-readable, debuggable) instead of pickle.

**Trade-offs:** Two files = must keep them together on share. Mitigation: on save, offer a `.zip` wrapper or just document "keep both files together". JSON > pickle here because the registry is plain dicts and we avoid pickle's version/security pitfalls.

**Example schema (`<name>.bcm`):**
```json
{
  "format": "biochemeleon-save-v1",
  "target_object": "1znf",
  "setup": { "hider_count": 8, "lock_scene": true, "difficulty": "hard", "per_rep": {...} },
  "started_at": "2026-08-02T12:00:00Z",
  "elapsed_seconds": 142.3,
  "reveal_count": 0,
  "hiders": [
    { "index": 482, "rep": "sphere",  "status": "found",  "found_at": 95.1 },
    { "index": 903, "rep": "cartoon", "status": "hidden", "found_at": null }
  ],
  "initial_state_ref": "1znf_backup"   # name of the backup object for restart
}
```

### Pattern 5: Hider registry keyed by internal `index`, built once post-insertion

**What:** After `ObjectMutator` inserts all hider atoms, `HiderRegistry` snapshots each hider's `index` via `cmd.iterate`. From then on the registry is the authority: `on_pick(i)` checks membership; found/hidden/colored state lives here. **Never `cmd.sort()` or `cmd.remove()` on the target object while a registry is live** — `index` is "sensitive to sorting and removing of atoms" (Iterate wiki). Cleanup removes hiders by a tracked selection, not by re-sorting.

**When to use:** For the entire active game session.

**Trade-offs:** Indices are stable as long as the object isn't re-sorted or atom-deleted. To stay safe: (a) build registry only after all insertion is done; (b) on cleanup, delete the *hider selection* (a named selection we keep), which removes hider atoms and invalidates the registry (fine — game is over); (c) for restart, restore from the backup object (see Pattern 6) rather than surgically deleting — this sidesteps index-shift entirely.

**Example:**
```python
# biochemeleon/game/registry.py
from dataclasses import dataclass, field
from typing import Dict

@dataclass
class HiderEntry:
    index: int
    rep: str
    status: str = "hidden"      # "hidden" | "found"
    found_at: float | None = None
    hint_used: bool = False

class HiderRegistry:
    def __init__(self):
        self._by_index: Dict[int, HiderEntry] = {}
        self._per_rep: Dict[str, int] = {}        # rep -> remaining

    def register(self, indices, rep):
        for i in indices:
            self._by_index[i] = HiderEntry(index=i, rep=rep)
        self._per_rep[rep] = self._per_rep.get(rep, 0) + len(indices)

    def is_hider(self, index) -> bool:
        return index in self._by_index

    def mark_found(self, index, t):
        e = self._by_index.get(index)
        if e and e.status == "hidden":
            e.status = "found"; e.found_at = t
            self._per_rep[e.rep] -= 1

    @property
    def remaining_total(self): return sum(1 for e in self._by_index.values() if e.status == "hidden")
    def remaining_for(self, rep): return self._per_rep.get(rep, 0)
    @property
    def all_found(self): return all(e.status == "found" for e in self._by_index.values())
```

### Pattern 6: Object-mutation safety — backup → mutate → cleanup/restore

**What:** The core spec invariant: *hiders live in the SAME object as the real structure*, so the player can't isolate them by hiding the object. This means we **mutate the user's object**, which is dangerous. The safe protocol:

1. **Backup before mutate:** `cmd.create(backup_name, target_obj)` makes a full copy of the pristine object. Keep this name (e.g. `bcm_1znf_backup`); it's the restore source for Restart/Cleanup. Mark backup as `cmd.disable(backup_name)` so it doesn't clutter the view.
2. **Insert hiders INTO the existing object** using one of:
   - `cmd.pseudoatom(target_obj, ...)` — verified: *"adds a pseudoatom to a molecular object **if the specified object already exists**"* (Pseudoatom wiki). Best for **sphere** hiders (single atom, no bonds needed) and **cartoon C-alpha** hiders (a pseudoatom with `name=CA`, a residue number/chain that places it in the cartoon path).
   - `cmd.create(target_obj, temp_frag, 0, 0, 0)` to **merge** a pre-built fragment (with bonds) into the existing object — best for **line/stick** hiders that need bond topology to blend in. *(Merge-append semantics should be confirmed in Phase 1 with a 5-line smoke test; if `create` replaces rather than appends, fall back to the chempy model API below.)*
   - **chempy model API** (robust fallback): `m = cmd.get_model(target_obj)` returns an `Indexed` model; append to `m.atom` and `m.bond`; `cmd.delete(target_obj); cmd.load_model(m, target_obj)`. This rebuilds the object with hiders included. Use if `create`-merge proves unreliable.
3. **Tag hiders with an identifiable residue name** so they're selectable for cleanup/color: e.g. `resn="HID"`. Then `cmd.select("bcm_hiders", "model target and resn HID")` gives a stable handle. (The registry keys by `index`; the `resn` tag is the bulk-selection handle.)
4. **Cleanup = delete the hider selection + re-enable backup OR restore from backup:** On Cleanup, `cmd.delete("bcm_hiders")` then either keep the (now-clean) target or `cmd.delete(target_obj); cmd.create(target_obj, backup_name)` to guarantee a pristine restore. **Deleting by selection, not by index, avoids index-shift bugs.**
5. **Restart = restore from backup, regenerate:** Don't try to surgically un-find hiders; restore the whole object from backup and re-run generation. Simpler and corruption-proof.

**When to use:** On Start, Restart, Cleanup, Generate & export, and exit.

**Trade-offs:** Keeping a full backup doubles memory for one object — negligible for demo PDBs (1znf ~ 900 atoms), acceptable even for 4WB3. For the large membrane PDBs (1GZM/3GP6 with full membrane), document that backup costs ~2× RAM; if that's a concern, snapshot only the protein chain (hiders go on the protein, not the membrane lipids).

**Anti-corruption guarantees:**
- Never mutate a backup object.
- Never `cmd.sort()` the target while a registry is live.
- Always `cmd.delete(backup_name)` on plugin exit / Cleanup to avoid polluting the user's session.

---

## Data Flow

### Flow A — Click-to-find (the critical loop)

This is the heartbeat of the game. Every component boundary is crossed exactly once per click, in one direction, traceably.

```
 USER clicks an atom in the OpenGL viewer
        │
        ▼
 PyMOL core → places picked atom in (sele) selection
        │
        ▼
 PickWizard.do_pick(picked_bond)              [pymol_io layer]
        │  cmd.iterate("(sele) and model <target>", "rec.append((model,index))")
        ▼
 GameController.on_pick(index)                [game layer — no cmd, no Qt]
        │
        ├──► HiderRegistry.is_hider(index)  →  False?  → log "miss" to GameTab; return
        │
        │   True:
        ├──► HiderRegistry.mark_found(index, elapsed)   → mutates registry
        ├──► PymolAdapter.recolor_or_hide(index)        → cmd.color / cmd.hide on that atom
        ├──► GameTab.refresh(remaining_total, remaining_per_rep)  → Qt label setText
        └──► if registry.all_found: GameController.win() → stop timer, show winning message
        │
        ▼
 (sele) cleared by PickWizard; viewer ready for next click
```

**Direction is strictly enforced:** `PickWizard → GameController → {Registry, PymolAdapter, GameTab}`. The GUI never inspects the registry directly; the registry never calls cmd; the wizard never touches Qt. This is what makes the loop testable: `GameController.on_pick` can be unit-tested with a fake registry + fake adapter.

### Flow B — Start

```
 SetupTab (user clicks Start) → PluginDialog._on_start(SetupParams)
      → GameController.start(params):
            1. PymolAdapter.resolve_target(params)              # loaded obj / fetch / demo
            2. ObjectMutator.backup_original(target)            # cmd.create backup
            3. HiderGenerator.generate(target, params)          # decides placement per rep
                 └─ ObjectMutator.add_hider_atoms(spec)          # pseudoatom / create-merge
            4. HiderRegistry.build(cmd.iterate over resn HID)    # snapshot indices
            5. StateStore.mark_started()                          # start_time, setup snapshot
            6. PluginDialog.tabs: enable Game tab, disable Setup, switch to Game
            7. GameTab.countdown(3,2,1) → PickWizard.activate()    # viewer enters picking mode
            8. GameTab.start_timer()
```

### Flow C — Save / Load (checkpointing)

```
 SAVE  (GameTab → GameController.save):
      1. StateStore.snapshot(registry, timer, setup) → dict
      2. PymolAdapter.save_session(path + ".pse")        # cmd.save "<name>.pse"
      3. StateStore.write_json(path + ".bcm", snapshot)  # stdlib json
      (share: hand user both files together)

 LOAD  (GameTab → GameController.load, or Import button for a Generate&export file):
      1. PymolAdapter.load_session(path + ".pse")       # cmd.load "<name>.pse" (restores atoms+reps+hider atoms)
      2. StateStore.read_json(path + ".bcm") → snapshot
      3. HiderRegistry.rebuild_from(snapshot["hiders"])  # restore index→status
      4. GameController.resume(snapshot) → enable Game tab, PickWizard.activate()
```

**Note on Load fidelity:** `.pse` restores hider atoms and reps exactly. The `.bcm` restores the *found/hidden* status and timer. A loaded game is resumable because indices in a `.pse` round-trip identically (the object is serialized as-is). **Caveat (LOW confidence):** confirm in Phase 1 that `index` is stable across a save/load `.pse` cycle — if PyMOL reindexes on load, key the registry by `(chain, resi, name)` fallback identity instead of `index`. Build registry construction to accept either key.

---

## Scaling Considerations

"Scale" here = molecule size, not users (single-user desktop plugin).

| Concern | Demo PDB (~1k atoms) | Medium (4WB3, ~5k) | Large membrane (1GZM full, ~50k+ atoms) |
|---------|----------------------|--------------------|------------------------------------------|
| Backup memory (2× obj) | trivial | fine | ~2× RAM; document it, or back up protein chain only |
| `cmd.iterate` to build registry | <10ms | ~20ms | ~100ms — fine; iterate only `resn HID` (small set), not `all` |
| Picking responsiveness | instant | instant | instant (pick is O(1) lookup in registry dict) |
| Cartoon hider placement geometry | fine | fine | heaviest compute — cap hider count for large objs |
| `.pse` save size | small | small | large but acceptable; warn user before saving huge sessions |

### Scaling Priorities

1. **First bottleneck:** Cartoon hider geometry on large proteins — cap hider count as a function of object atom count (e.g. `max_hiders = min(user_value, n_atoms // 50)`), per the spec's "cap a reasonable number".
2. **Second bottleneck:** Memory for the backup on membrane proteins — mitigate by backing up only the protein selection, since hiders don't go on lipids/solvent.

---

## Anti-Patterns

### Anti-Pattern 1: Putting hiders in a SEPARATE object
**What people do:** Create `hiders_obj` and show it alongside the target. **Why it's wrong:** Defeats the core mechanic — the player just hides the `hiders_obj` object and the game is trivial. **Do this instead:** Insert into the *same* object via `pseudoatom`/`create`-merge (Pattern 6). This is a hard spec requirement.

### Anti-Pattern 2: Keying the registry by PDB `ID` or `rank`
**What people do:** Use `ID` (PDB atom id) as the registry key because it's "the atom's id". **Why it's wrong:** `ID` is not guaranteed unique; `rank` isn't either (Iterate wiki). Subtle find-the-wrong-atom bugs. **Do this instead:** Use internal `index` (unique per object); fall back to `(chain, resi, name)` tuple if `.pse` round-trip reindexes (verify in Phase 1).

### Anti-Pattern 3: Mutating the target object without a backup
**What people do:** `pseudoatom` hiders into the user's object, then on Cleanup try to remove them by index. **Why it's wrong:** Removing by index shifts indices (corrupts any live registry); if a crash happens mid-game, the user's object is permanently polluted. **Do this instead:** Always `cmd.create(backup, target)` first; Cleanup/Restart restores from backup (Pattern 6).

### Anti-Pattern 4: Calling `cmd` from GUI widgets, or calling Qt from game logic
**What people do:** A button handler does `cmd.color(...)` directly, or `GameController` calls `QMessageBox`. **Why it's wrong:** Couples layers — untestable in WSL python3.6 (no PyMOL, no Qt), and changes ripple everywhere. **Do this instead:** GUI → controller method → adapter/wizard. Controller emits to GUI via a small callback interface (`on_remaining_changed`, `on_win`) the dialog registers.

### Anti-Pattern 5: Clobbering the user's active wizard
**What people do:** `cmd.set_wizard(PickWizard())` on Start without saving the current wizard. **Why it's wrong:** If the user was mid-measurement (e.g. distance wizard), we silently destroy their state. **Do this instead:** `self._saved = cmd.get_wizard()` before activate; restore it on deactivate (Pattern 2).

### Anti-Pattern 6: Relying on `Pmw` without checking it's installed
**What people do:** Assume `Pmw.NoteBook` is available because old plugins use it. **Why it's wrong:** Pmw is unmaintained and not guaranteed in the anaconda PyMOL 2.5 env. **Do this instead:** Use `pymol.Qt.QtWidgets.QTabWidget` (recommended), or `tkinter.ttk.Notebook` if the Tk path is mandated. Verify in Phase 1.

### Anti-Pattern 7: Polling mouse buttons / reimplementing picking
**What people do:** Try to read `cmd.button` or poll the mouse to detect clicks. **Why it's wrong:** Fragile, fights PyMOL's own mouse handling. **Do this instead:** Use the Wizard `do_pick` callback — it's the supported, purpose-built mechanism.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes / Gotchas |
|---------|---------------------|-----------------|
| **PyMOL `cmd` API** | Import `from pymol import cmd`; call directly. All cmd access via `pymol_io/`. | Single-threaded; cmd calls must run on the main GUI thread. Don't spawn threads that call cmd in v1 (not needed). |
| **PyMOL Wizard system** | `from pymol.wizard import Wizard`; `cmd.set_wizard()` / `cmd.set_wizard(None)`. | Only one wizard at a time — save/restore user's wizard. |
| **PyMOL session (`.pse`)** | `cmd.save(path, state=-1)` for all states; `cmd.load(path)`. | Binary, opaque — game metadata must go in the companion `.bcm` JSON. |
| **RCSB PDB fetch** (demo) | `cmd.fetch(pdbid, async_=0)` — stdlib, no approval needed. | Network call; for demos prefer bundled files; fetch is fallback for user-entered IDs. |
| **MemProtMD / SASBDB** (large/challenge demos) | `urllib.request.urlretrieve` (stdlib) into `data/cache/`. | Large files; strip water/salt + compress before bundling per spec. **No 3rd-party lib needed — urllib is stdlib.** |
| **PyQt (whichever binding)** | `from pymol.Qt import QtWidgets, QtCore, QtGui` — the shim. | Never `import PyQt5` directly — `pymol.Qt` picks the right binding. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| GUI ↔ Controller | Method calls + callback interface (controller → gui via registered callbacks) | One-way: GUI calls controller; controller notifies GUI. No GUI imports in `game/`. |
| Controller ↔ Registry | Direct method calls | Registry is plain Python; no I/O. |
| Controller ↔ PymolAdapter / Mutator / PickWizard | Method calls | All `cmd.*` confined to `pymol_io/`. |
| Controller ↔ StateStore | Method calls | StateStore does file I/O (json) + asks adapter for `.pse`. |
| Generator ↔ Mutator | Generator computes a *spec* (coords, resn, bonds); Mutator executes it | Keeps geometry math (testable) separate from PyMOL side-effects. |
| PickWizard ↔ Controller | `wizard.controller.on_pick(index)` | Wizard holds a controller ref; controller does NOT import the wizard (avoids cycle). |

---

## Build Order (Dependencies → What to Build First)

The roadmap should phase components so each phase's components only depend on already-built ones. Below is the dependency DAG and a suggested phase mapping.

### Dependency graph

```
Phase 0 (bootstrap):
  __init_plugin__ + addmenuitemqt registration + empty PluginDialog
        │
        ▼
Phase 1 (foundation, no game yet):
  PymolAdapter (read-only cmd wrappers: get_names, get_reps, iterate)
  SetupParams dataclass + SetupTab (form + 7 buttons, but only Reset/Randomize/Save/Load Setup wired)
  DemoLoader (manifest + bundled small PDB load) + data/ layout
        │  (depends on: PymolAdapter)
        ▼
Phase 2 (mutation safety — RISKIEST, do early to de-risk):
  ObjectMutator: backup_original / restore_original / add_hider_atoms (pseudoatom path) / remove_hiders
  HiderRegistry (index → status) + a tiny test harness
  ★ Phase 1 smoke test: insert 1 pseudoatom into 1znf, read its index, delete by resn, restore from backup
        │  (depends on: PymolAdapter)
        ▼
Phase 3 (core game loop — the MVP value):
  PickWizard (do_pick → on_pick)
  GameController.start / on_pick / win
  GameTab (timer, remaining, rolling info) wired to controller
  SphereStrategy (easiest generator — "place anywhere")
  Start button end-to-end: setup → backup → generate spheres → registry → countdown → pick → find → win
  ★ This is the "core value loop works" milestone (per PROJECT.md). Ship this.
        │  (depends on: Phase 1 + 2 + PickWizard + GameController + GameTab + SphereStrategy)
        ▼
Phase 4 (remaining generators):
  LineStickStrategy (mimic connected atoms / alt positions — needs bonds via create-merge)
  CartoonStrategy (extend terminal / replicate segment as alt position — HARDEST, "L" complexity; may phase separately)
  per-rep hider counts + "lock scene" rep detection
        │  (depends on: Phase 3 + ObjectMutator create-merge path)
        ▼
Phase 5 (persistence + meta actions):
  StateStore (.pse + .bcm JSON save/load)
  Generate & export + Import buttons
  Hint button (color N atoms around a hider — cmd.expand / around)
  Reveal one / reveal all (with confirm) + reveal-count tracking
  Restart (restore from backup, regenerate)
  Cleanup model
        │  (depends on: Phase 3 + Registry + StateStore)
        ▼
Phase 6 (polish):
  found-hider visibility/color dropdown
  difficulty toggle (total-only vs per-rep remaining)
  rolling info box polish, winning message with time
  large-demo fetch + strip/compress pipeline (1GZM, 3GP6)
  source citations in data/sources.md + README
  ★ Qt-vs-Tk final validation belongs here if not settled pre-build.
```

### Build-order rationale

- **ObjectMutator (Phase 2) before any generator:** Mutation is the highest-risk, lowest-confidence area (the `create`-merge semantics are MEDIUM confidence). De-risk it with a 5-line smoke test before building generators on top of assumptions that might be wrong.
- **SphereStrategy in Phase 3, not Line/Cartoon:** Sphere is "place anywhere" (spec) — a single `pseudoatom` with no bonds. It's the fastest path to the working core loop, which is the stated MVP. Line/stick (needs bonds) and cartoon (needs C-alpha geometry) are strictly harder; build them once the loop is proven.
- **PickWizard + GameController + GameTab together in Phase 3:** These three form the inseparable click→found→refresh loop. Build them as a unit; none makes sense alone.
- **StateStore deferred to Phase 5:** Save/load is a table-stakes *feature* but not on the critical path of the core loop. The PROJECT.md says "If nothing else works, this loop must work" — prioritize the loop (Phase 3) before persistence (Phase 5).
- **Cartoon strategy may slip:** Its "L" complexity and geometry dependence (terminal extension / loop replica as alternate position) make it the most likely candidate for a Phase-4 slip into its own sub-phase. The roadmap should flag cartoon as "needs deeper research" (see Research Flags below).

### Research flags for phases

| Phase | Likely needs deeper research | Why |
|-------|------------------------------|-----|
| Phase 1 | Qt vs Tk final choice | Confirm which external GUI `setenv.bat` PyMOL launches; verify `pymol.Qt` import works. |
| Phase 2 | `cmd.create` merge-append vs replace semantics; `.pse` round-trip index stability | MEDIUM confidence; a 5-line smoke test resolves it. Also confirm chempy `get_model`/`load_model` as fallback. |
| Phase 3 | Wizard save/restore of user's pre-existing wizard; `(sele)` filtering to target object | Edge cases in picking (clicks on other objects, empty picks). |
| Phase 4 (cartoon) | How to "replicate a segment (loop) as alternate position" via C-alpha | Genuinely novel geometry; needs a dedicated research spike on cartoon representation internals (`cmd.get_fasta`, secondary structure, C-alpha chain endpoints). |
| Phase 5 | `.pse` + companion file co-location UX | Two-file share is awkward; decide whether to zip them. |

---

## Sources

**HIGH confidence (official / verified against source):**
- `pymol-open-source/modules/pymol/plugins/__init__.py` (github.com/schrodinger/pymol-open-source) — confirms `__init_plugin__(pmgapp)` entry point, `addmenuitemqt` ("Intended for plugins which open a PyQt window", raises `QtNotAvailableError`), "only available with PyQt GUI" message, plugin discovery of `.py` files and `__init__.py` packages on startup path. https://github.com/schrodinger/pymol-open-source/blob/master/modules/pymol/plugins/__init__.py
- PyMOL Wiki — Pseudoatom: "creates a molecular object with a pseudoatom **or adds a pseudoatom to a molecular object if the specified object already exists**". https://pymolwiki.org/index.php/Pseudoatom
- PyMOL Wiki — Iterate: `index` = "internal atom index (unique per object, sensitive to sorting and removing of atoms, cannot be altered)"; `ID`/`rank` not guaranteed unique. https://pymolwiki.org/index.php/Iterate
- PyMOL Wiki — Create: `cmd.create(name, selection, source_state, target_state, discrete)` merges/creates states. https://pymolwiki.org/index.php/Create
- PyMOL Wiki — Wizard: `cmd.wizard(name)` / `cmd.set_wizard()`. https://pymolwiki.org/index.php/Wizard
- Reference plugin `mtsslWizard.py` — `from pymol.wizard import Wizard`, `do_pick(self, picked_bond)`, `cmd.set_wizard(wiz)`, reads picked atom from `(sele)`, `get_panel()` for viewer menu. (in-repo: `Pymol-script-repo/plugins/mtsslWizard.py`)
- Reference plugin `emovie.py` — `.pse` + companion `.emov` (pickle) save/load pattern; `cmd.do("save %s.pse")`. (in-repo: `Pymol-script-repo/plugins/emovie.py`)
- Reference plugins `optimize.py`, `outline.py`, `vina.py`, `views.py`, `dynoplot.py`, `show_contacts.py` (Qt path) — modern `pymol.Qt` usage, `__init_plugin__` + `addmenuitemqt`, singleton `dialog = None` GC-prevention, `QTabWidget`, `QDialog`. `optimize.py` comments explicitly note the Tk→Qt migration. (in-repo: `Pymol-script-repo/plugins/`)

**MEDIUM confidence (single reference, needs Phase-1 smoke test):**
- `cmd.create(existing_obj, frag, 0, 0, 0)` merge-append semantics into an existing object's *current state* (vs replacing). Create wiki describes state-merge; in-object same-state atom-append should be confirmed with a smoke test. chempy `cmd.get_model`/`cmd.load_model` is the verified fallback.
- `index` stability across a `.pse` save/load round-trip. Mitigation: build registry to fall back to `(chain, resi, name)` identity.

**LOW confidence:**
- Whether the user's specific anaconda PyMOL 2.5.0 build (via `setenv.bat`) launches the Qt vs Tk external GUI by default — ecosystem evidence strongly says Qt, but the env is Windows/conda-specific; **validate in Phase 1**. This is the Tk-vs-Qt decision gate.

---
*Architecture research for: PyMOL 2.5.0 plugin — molecular hide-and-seek game (bioCHEMeleon)*
*Researched: 2026-08-02*
