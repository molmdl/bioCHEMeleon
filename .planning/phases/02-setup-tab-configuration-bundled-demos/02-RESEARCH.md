# Phase 2: Setup Tab Configuration & Bundled Demos - Research

**Researched:** 2026-08-03
**Domain:** PyMOL 2.5.0 plugin — PyQt5 setup form + bundled demo PDB loader + WSL→Windows path helper
**Confidence:** HIGH (Qt form patterns, cmd API signatures, rep-detection selector, citations, to_windows_path), MEDIUM (Plugin Manager dir-install on Windows — inherited from Phase 1; `cmd.fetch` network availability at runtime)

---

## Summary

Phase 2 turns the placeholder `SetupTab` from Phase 1 into the full pre-game configuration experience: a 3-mode object selector (loaded object / PDB fetch / bundled demo), a hider-count spinbox capped to atom count, a "lock current scene" checkbox, a per-representation hider list with checkboxes + per-rep counts, a difficulty toggle, and four config buttons (Reset / Randomize / Save Setup / Load Setup). It also bundles six small demo PDBs into the repo with cited sources and implements the `to_windows_path()` helper that PITFALLS.md deferred from Phase 1. Phase 2 does **NOT** generate hiders, start a game, or mutate any object — BTN-05/06/07 and all HIDER-* requirements are out of scope.

The technical pattern is settled at HIGH confidence from three converging sources: (1) the project research docs (`STACK.md`, `PITFALLS.md`, `ARCHITECTURE.md`) which already verified the PyQt5-via-`pymol.Qt` stack and Pitfall 11; (2) the modern reference plugins in `Pymol-script-repo/plugins/` — **`vina.py`** contributes the exact `PyMOLComboObjectBox(QComboBox)` refresh-on-show pattern (`cmd.get_names("all", enabled_only=True)`), the `QFormLayout` + `QSpinBox.setRange/setValue` + `QCheckBox` + `QFileDialog.getOpenFileName` form pattern, and the `@widget.signal.connect` decorator syntax; **`outline.py`** contributes the QComboBox-with-refresh-button layout, `QSpinBox`, `QFileDialog.getSaveFileName`, and the canonical PyMOL rep-name list (`REP_LIST = ['surface','cartoon','mesh','dots','spheres','lines','nonbonded']`); (3) the **PyMOL 2.5.0 source** (`querying.py` at tag `v2.5.0`) which gives the exact `cmd.get_names` / `cmd.count_atoms` / `cmd.get_type` / `cmd.get_object_list` signatures, and the official wiki "Selection Algebra" page which confirms the `rep <name>` selector for detecting active representations. All six demo PDB citations were fetched directly from the RCSB REST API (`data.rcsb.org/rest/v1/core/entry/{ID}`) and the canonical download URL `https://files.rcsb.org/download/{ID}.pdb` was confirmed to resolve (1znf.pdb fetched end-to-end).

**Primary recommendation:** Populate `biochemeleon/gui_setup.py` with a `QVBoxLayout` of four `QGroupBox` sections ("Target", "Hiders", "Difficulty", "Buttons") using `QFormLayout` rows; implement the object selector as a `QComboBox` (mode) + a stacked widget that swaps between a `PyMOLObjectCombo` (subclass `QComboBox` overriding `showPopup` to refresh from `cmd.get_names('public_objects', enabled_only=True)` filtered by `cmd.get_type(name)=='object:molecule'`), a `QLineEdit` (PDB code) + fetch button, and a demo `QComboBox` populated from a `DemoLoader` manifest; implement per-rep config as a `QGroupBox` containing one row per rep (a `QCheckBox` + a `QSpinBox`); implement Save/Load via `QFileDialog.getSaveFileName/getOpenFileName` + `json` with a `.bcm.setup.json` extension; implement Reset/Randomize via a `DEFAULTS` dict and an `apply_state()`/`collect_state()` method pair. Populate `biochemeleon/demos.py` with `to_windows_path()` + a `DemoLoader` class backed by `biochemeleon/data/demos/*.pdb` + a `biochemeleon/data/demos/SOURCES.md` citation file. Do **NOT** extract `PluginDialog` to `gui_dialog.py` (Phase 2 grows `gui_setup.py`, not `__init__.py`).

---

## 1. Phase 2 Scope Summary

**IN scope (Phase 2 deliverables):**
- Populate `biochemeleon/gui_setup.py` with the full Setup form (SETUP-01..06) + the four config buttons (BTN-01..04).
- Populate `biochemeleon/demos.py` with `to_windows_path()` (PITFALLS.md Pitfall 11, deferred from Phase 1) + `DemoLoader` (manifest + `load_demo`).
- Bundle the six small demo PDBs under `biochemeleon/data/demos/` + a `SOURCES.md` citation file (DEMO-01).
- WSL syntax + Pitfall-1/11 gate; Windows-PyMOL functional smoke test of all 4 success criteria.

**Explicitly OUT of scope (do NOT build these in Phase 2):**
- BTN-05 Generate & export (Phase 8), BTN-06 Cleanup (Phase 7), BTN-07 Start (Phase 4).
- Any hider generation, object mutation, registry, wizard, picking, timer, win condition (Phases 3/4/5).
- `gui_game.py` content (Phase 4).
- Large demo fetch (MemProtMD 1GZM/3GP6, SASBDB glycoprotein) — DEMO-02/03/04 are Phase 9. Phase 2 only bundles the six SMALL demos.
- `DATA_SOURCES.md` (DEMO-04, Phase 9) — Phase 2 writes a lighter `SOURCES.md` inside `data/demos/` that Phase 9 can absorb.
- Difficulty-tiered demo sub-menu metadata "Challenge / Very challenging" (DIFF-05, Phase 9) — Phase 2's demo sub-menu only surfaces Easy/Hard (the categories given in DEMO-01).

**Phase boundary rationale:** Phase 2 delivers the entire pre-game configuration UX (the user can pick a target, set all params, save/load/reset/randomize, and load any of the 6 bundled demos) without touching any destructive PyMOL op. This keeps Phase 2 safely non-destructive (no `segi='GAME'`, no backup, no mutation) so it can ship before the Phase 3 mutation-safety de-risking. The Setup form's per-rep config feeds the Phase 3 `segi='GAME'` + `b=-999` sentinel mechanism later, but Phase 2 only captures the user's intent into a Python dict (and optionally a JSON file).

---

## 2. PyMOL Qt Form Widget Patterns (for the Setup form)

All widgets come from `from pymol.Qt import QtCore, QtGui, QtWidgets` — **NEVER `from PyQt5 import`** (breaks on PySide2 builds; established in Phase 1, re-confirmed in STACK.md "What NOT to Use"). The exact class names and signal syntax below are verified against the modern reference plugins `vina.py` and `outline.py`.

### 2.1 Widget cheat-sheet (paste-ready)

| Widget | Class | Key API | Verified source |
|--------|-------|---------|-----------------|
| Dropdown / combobox | `QtWidgets.QComboBox` | `addItems(list)`, `clear()`, `setCurrentText(s)`, `currentText()`, `setEditable(bool)`, `setInsertPolicy(QComboBox.NoInsert)`, override `showPopup()` | `vina.py:1153-1169` (`PyMOLComboObjectBox`), `outline.py:334` |
| Numeric input (capped) | `QtWidgets.QSpinBox` | `setRange(min, max)`, `setValue(v)`, `value()`, `setGroupSeparatorShown(bool)` | `outline.py:292-297`, `vina.py:718-729` |
| Checkbox | `QtWidgets.QCheckBox` | `setChecked(b)`, `isChecked()`, `stateChanged.connect(...)` | `outline.py:386`, `vina.py:734-735` |
| List-with-checkboxes | `QListWidget` + `QListWidgetItem` + `setItemWidget(item, QCheckBox)` OR a `QGroupBox` with one row per item (recommended — see §2.3) | `QListWidget.addItem(item)`, `item.setCheckState(Qt.Checked/Unchecked)` | (simplest pattern — see §2.3) |
| Button | `QtWidgets.QPushButton` | `setText(s)`, `clicked.connect(callable)`, `@btn.clicked.connect` decorator | `vina.py:740-742`, `outline.py:339` |
| File dialog (save) | `QtWidgets.QFileDialog.getSaveFileName(parent, title, dir, filter)` | returns `(path, filter)` tuple — take `[0]` | `outline.py:170-171` |
| File dialog (open) | `QtWidgets.QFileDialog.getOpenFileName(parent, title, dir, filter)` | returns `(path, filter)` tuple — take `[0]` | `vina.py:746-752` |
| Label | `QtWidgets.QLabel` | `QLabel("text")`, `setText(s)` | `outline.py:299` |
| Grouping | `QtWidgets.QGroupBox("title")` + `QFormLayout` inside | `groupBox.setLayout(formLayout)` | `optimize.py:89,165` |
| Form layout | `QtWidgets.QFormLayout` | `addRow("Label:", widget)`, `setWidget(row, SpanningRole, widget)` | `vina.py:711,777-780`, `optimize.py` |
| Line edit (text) | `QtWidgets.QLineEdit` | `QLineEdit(default)`, `setText(s)`, `text()`, `textEdited.connect(...)` | `vina.py:1214`, `optimize.py:111` |
| Message box (errors/confirm) | `QtWidgets.QMessageBox` | `setWindowTitle`, `setText`, `setStandardButtons(QMessageBox.Ok)`, `exec_()` (modal — OK for a message box, NOT for the main dialog) | `outline.py:178-182` |
| Horizontal line layout | `QtWidgets.QHBoxLayout` | `addWidget(a); addWidget(b)` | `outline.py:333-341` (combobox + refresh btn) |
| Vertical stack | `QtWidgets.QVBoxLayout` | `addWidget(group)` | Phase 1 `PluginDialog` |

### 2.2 Signal/slot connection syntax (new-style PyQt5)

PyQt5 uses the new-style `signal.connect(slot)` syntax. Two equivalent forms appear in the reference repo — both work under `pymol.Qt`:

```python
# Form 1: direct method call (most common)
self.refresh_btn.clicked.connect(self._refreshCombobox)        # outline.py:339
self.mode_combo.currentIndexChanged.connect(self._on_mode_changed)

# Form 2: @decorator with a closure (vina.py pattern)
@click_button.clicked.connect
def on_click():
    ...                                                         # vina.py:742-744

@receptor_sel.currentTextChanged.connect
def validate(text):
    validate_receptor_sel()                                     # vina.py:1193-1195
```

**Recommendation:** use Form 1 (method calls on `self`) for the Setup form — it keeps all slots as named methods on `SetupTab`, which is easier to test and to wire into `collect_state()`/`apply_state()`. Reserve the `@decorator` form for tiny inline closures.

**Confirmed:** `widget.signal.connect(slot)` is the PyQt5 new-style connection. There is no `SIGNAL()`/`connect()` old-style string syntax anywhere in the modern reference plugins. Do NOT use `pyqtSignal(...)` string-based connections.

### 2.3 Per-rep list with checkboxes (SETUP-05) — recommended simplest pattern

SETUP-05 requires "per-representation hider list with checkboxes; after ticking, a form/textbox/spinwheel sets the per-rep count (if unset, random per-rep totaling the hider count)". The simplest pattern that does NOT require a custom `QListWidget` delegate:

**Recommended: a `QGroupBox("Per-rep hider counts")` containing one row per rep, where each row is a `QHBoxLayout` of `[QCheckBox(rep_name), QSpinBox, QLabel("random")]`.** The QSpinBox is enabled only when the checkbox is checked; when unchecked, the per-rep count is "random" (the QLabel shows "random" and the spinbox is disabled). This is simpler than `QListWidget.setItemWidget` (which needs careful item/widget lifecycle) and gives a clean 1-row-per-rep mapping for `collect_state()`.

```python
# Pattern: one QHBoxLayout row per representation, stored in a dict
self.rep_rows = {}  # rep_name -> (QCheckBox, QSpinBox, QLabel)
reps_layout = QtWidgets.QVBoxLayout()
for rep in GAME_REPS:  # ['lines','sticks','spheres','cartoon','ribbon']
    row = QtWidgets.QHBoxLayout()
    cb = QtWidgets.QCheckBox(rep)
    spin = QtWidgets.QSpinBox()
    spin.setRange(0, 999)
    spin.setValue(0)
    spin.setEnabled(False)              # disabled until checkbox toggled
    label = QtWidgets.QLabel("random")  # shown when checkbox unchecked
    row.addWidget(cb)
    row.addWidget(spin)
    row.addWidget(label)
    row.addStretch()
    reps_layout.addLayout(row)
    self.rep_rows[rep] = (cb, spin, label)
    cb.toggled.connect(
        lambda checked, s=spin, l=label: self._on_rep_toggled(checked, s, l))
```

(`GAME_REPS` and the `_on_rep_toggled` slot are defined in §3.5 / §5.2.)

**Alternative (only if the row-count is dynamic):** `QListWidget` with `QListWidgetItem.setCheckState(Qt.Checked/Qt.Unchecked)` for the tick, and `QListWidget.setItemWidget(item, spinbox)` for the per-rep count. This is more code and the item/widget lifecycle is fiddly. **Don't use it in Phase 2** — the rep set is fixed at 5 entries, so the QGroupBox-of-rows pattern is strictly simpler.

### 2.4 Refreshing the loaded-objects dropdown (the canonical pattern)

`vina.py:1153-1169` defines `PyMOLComboObjectBox(QComboBox)` which **overrides `showPopup()`** to refresh from `cmd.get_names` every time the user opens the dropdown. This is the verified refresh-on-show pattern. Phase 2 should use the same approach for the "loaded object" mode of the object selector (§3.2):

```python
# Source: vina.py:1153-1169 (verbatim shape, adapted)
class PyMOLObjectCombo(QtWidgets.QComboBox):
    """QComboBox that refreshes its list of loaded molecular objects
    every time the popup is shown. Editable so the user can also type
    a selection expression."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setEditable(True)
        self.setInsertPolicy(QtWidgets.QComboBox.NoInsert)
        self.setEditText("")

    def showPopup(self):
        current = self.currentText().strip()
        self.clear()
        # Only molecular objects, only enabled ones (see §3.1 for the exact call)
        names = list_loaded_molecule_objects()
        self.addItems(names)
        if current:
            self.setCurrentText(current)
        super().showPopup()
```

**Additionally** (optional, complementary): a refresh button next to the combo, exactly as `outline.py:333-342` does (a `QPushButton` with the `SP_BrowserReload` standard icon, `clicked.connect(self._refreshCombobox)`). Phase 2 should include BOTH: the refresh-on-show gives a fresh list whenever the dropdown is opened, and the explicit refresh button gives the user a visible "refresh now" affordance. The button is cheap; include it.

```python
# Source: outline.py:333-342 (verbatim shape)
combo_row = QtWidgets.QHBoxLayout()
self.obj_combo = PyMOLObjectCombo()
self.obj_refresh_btn = QtWidgets.QPushButton()
icon = self.style().standardIcon(QtWidgets.QStyle.SP_BrowserReload)
self.obj_refresh_btn.setIcon(icon)
self.obj_refresh_btn.setFixedSize(25, 25)
self.obj_refresh_btn.setToolTip("Refresh list of loaded objects")
self.obj_refresh_btn.clicked.connect(lambda: self.obj_combo.showPopup())
combo_row.addWidget(self.obj_combo)
combo_row.addWidget(self.obj_refresh_btn)
```

---

## 3. PyMOL cmd API for Object Enumeration, Fetch, Load, and Representation Detection

All signatures below are verified against the **PyMOL 2.5.0 source** (`modules/pymol/querying.py` at tag `v2.5.0`, fetched from `raw.githubusercontent.com/schrodinger/pymol-open-source/v2.5.0/modules/pymol/querying.py`) and the official PyMOL wiki.

### 3.1 Enumerate loaded objects — `cmd.get_names`

**Exact signature** (PyMOL 2.5.0 `querying.py`):
```python
def get_names(type='public_objects', enabled_only=0, selection="", *, _self=cmd):
```
Returns a Python `list[str]` of object/selection names.

**Type argument (mode int in parens):**
| `type` value | mode | What it returns |
|--------------|------|-----------------|
| `'objects'` | 1 | all object names |
| `'selections'` | 2 | all selection names |
| `'all'` | 0 | objects + selections |
| `'public'` | 3 | public objects + selections |
| **`'public_objects'`** | 4 | **public objects (DEFAULT) — excludes selections** |
| `'public_selections'` | 5 | public selections |
| `'public_nongroup_objects'` | 6 | public non-group objects |
| `'public_group_objects'` | 7 | public group objects |
| `'nongroup_objects'` | 8 | non-group objects |
| `'group_objects'` | 9 | group objects |

**For the object selector (loaded-object mode):** use `cmd.get_names('public_objects', enabled_only=True)`. This excludes selections AND disabled objects — exactly what a "pick a loaded object" dropdown wants. (`vina.py:1164` uses `cmd.get_names("all", enabled_only=True)` — that works too but includes selections; `'public_objects'` is the more precise choice.)

**Distinguishing "molecular objects" from maps/volumes/etc.:** pair `get_names` with `cmd.get_type(name)` (next). Do NOT just dump all `public_objects` into the dropdown — the user may have maps/measurements loaded that aren't valid game targets.

### 3.2 Object type — `cmd.get_type`

**Exact signature** (`querying.py`):
```python
def get_type(name, quiet=1, *, _self=cmd):
```
Returns one of: `"object:molecule"`, `"object:map"`, `"object:mesh"`, `"object:slice"`, `"object:surface"`, `"object:measurement"`, `"object:cgo"`, `"object:group"`, `"object:volume"`, `"selection"`.

**Helper for the object selector — list only molecular objects:**
```python
from pymol import cmd

def list_loaded_molecule_objects():
    """Return names of enabled molecular objects (exclude maps, volumes,
    selections, measurements, cgo, groups). Used to populate the Setup
    object-selector dropdown."""
    out = []
    for name in cmd.get_names('public_objects', enabled_only=True):
        if cmd.get_type(name) == 'object:molecule':
            out.append(name)
    return out
```
This is the verified approach. (`cmd.get_object_list(selection)` exists too — `querying.py` `get_object_list(selection="(all)", quiet=1)` returns objects covered by a selection — but `get_names`+`get_type` is the cleaner enumeration for a dropdown.)

### 3.3 Count atoms — `cmd.count_atoms`

**Exact signature** (`querying.py`):
```python
def count_atoms(selection="(all)", quiet=1, state=ALL_STATES, domain='', *, _self=cmd):
```
Returns `int`. Used everywhere in the reference repo (`vina.py:1203`, `pytms.py`, `dssp_stride.py`).

**For SETUP-03's hider-count cap (§3.6):** `cmd.count_atoms(obj)` gives the atom count of the selected object. (There is no separate `cmd.count` for atom counting — `count_atoms` is the function. The wiki's `Count` page 404s; the function is `count_atoms`.)

### 3.4 Fetch from PDB — `cmd.fetch`

**Exact signature** (PyMOL wiki `/Fetch`, confirmed against `importing.py`):
```python
fetch codes [, name [, state [, finish [, discrete [, multiplex [, zoom [, type [, async]]]]]]]]]
# Python API kwarg: async_  (NOT async — async is a Python keyword)
```
- `codes` = str: one or more accession codes, space-separated (e.g. `"1znf"` or `"1znf 1xdn"`).
- `name` = str: new object name {default: the accession code}.
- `type` = `cif|pdb|pdb1|mmtf|...`: file type {default: negotiated, `cif` since PyMOL 1.8}.
- `async_` = 0/1: **default `0` (synchronous) in the Python API since PyMOL 2.3.0**. The wiki ChangeLog: *"Changed in PyMOL 2.3.0: Default async=0"* and the argument doc: *"{default: 0 since PyMOL 2.3, before that: !quiet, which means 1 for the PyMOL command language, and 0 for the Python API}"*. **So in the plugin (Python API) `cmd.fetch` is synchronous by default in 2.5.0** — but STACK.md recommends passing `async_=0` explicitly for safety/clarity, and this research concurs.

**For SETUP-02's PDB-fetch mode:**
```python
from pymol import cmd

def fetch_pdb(code, name=None):
    """Fetch a structure from RCSB by PDB code. Synchronous. Requires
    network. Returns the object name on success, None on failure."""
    code = code.strip().lower()
    if not (3 <= len(code) <= 5 and code.isalnum()):
        return None  # basic validation
    obj_name = name or code
    try:
        cmd.fetch(code, name=obj_name, async_=0)   # sync; wait for full load
        return obj_name
    except Exception as e:
        # network down, invalid code, etc. — show a QMessageBox (see §7)
        return None
```
**Network dependency:** `cmd.fetch` requires internet. In an offline test it raises. Wrap in try/except and surface a `QMessageBox` (§7). The bundled-demo path (§4) does NOT need network — it loads local files.

### 3.5 Load a local PDB — `cmd.load`

**Exact signature** (PyMOL wiki `/Load`, confirmed against `importing.py`):
```python
cmd.load(filename [, object [, state [, format [, finish [, discrete [, multiplex [, zoom]]]]]]])
```
- `filename` = str: **path or URL**. The file extension determines format (`.pdb` → PDB, `.cif` → mmCIF, `.pse` → session).
- `object` = str: object name {default: filename prefix}.
- Returns the number of states loaded (or raises `pymol.CmdException` on failure).

**For the bundled-demo path (§4) and the WSL→Windows path (§6):**
```python
# DemoLoader.load_demo (see §4.4 for the full class)
path = os.path.join(os.path.dirname(__file__), 'data', 'demos', f'{demo_id}.pdb')
win_path = to_windows_path(path)          # see §6 — converts /mnt/c/... to C:\...
cmd.load(win_path, object=demo_id.lower(), zoom=1)
```
**Path encoding is the WSL→Windows pitfall (Pitfall 11) — `to_windows_path()` is mandatory before any `cmd.load` of a repo-local file when running in the WSL-dev / Windows-PyMOL workflow. See §6.**

### 3.6 Detect active representations — the `rep <name>` selector (SETUP-04)

**This was the biggest open question. There is NO `cmd.get_representations()` function in PyMOL 2.5.0** — I read the full `modules/pymol/querying.py` at the v2.5.0 tag; it has `get_names`, `get_type`, `get_object_list`, `count_atoms`, `count_states`, `count_frames`, `count_discrete`, but no `get_representations`. The PyMOL wiki page `/Get_Representations` returns 404.

**The verified approach:** use the `rep <name>` selection-language selector with `cmd.count_atoms`. The official PyMOL wiki "Selection Algebra" page (`/Selection_Algebra`, which `/Single-word_Selectors` redirects to) explicitly lists, under "Style" selectors:

> `rep cartoon` — Atoms with cartoon representation
> `# select anything shown as a line` → `select rep lines`

So `cmd.count_atoms(f"{obj} and rep {rep_name}") > 0` tells you whether `rep_name` is currently displayed on the object. This is HIGH confidence (official wiki + `cmd.count_atoms` signature verified in source).

**The exact rep-name strings PyMOL uses** (confirmed from `outline.py:320-322` `REP_LIST` + the grep of `cmd.show`/`cmd.hide` across the reference repo):
```python
# All rep names that appear in the reference repo's cmd.show()/cmd.hide() calls:
# 'lines', 'sticks', 'spheres', 'cartoon', 'ribbon', 'surface', 'mesh',
# 'dots', 'labels', 'nonbonded', 'nb_spheres', 'cgo', 'dashes'
```
**The game's rep set (PROJECT.md: lines, sticks, spheres, cartoon/ribbon; surface OUT OF SCOPE):**
```python
GAME_REPS = ['lines', 'sticks', 'spheres', 'cartoon', 'ribbon']
# 'surface' is explicitly OUT OF SCOPE (PROJECT.md) — do not include it.
```

**Detect "current scene" reps for SETUP-04 "lock current scene":**
```python
from pymol import cmd

def get_active_reps(obj):
    """Return the subset of GAME_REPS currently displayed on `obj`.
    Used by SETUP-04 'lock current scene' to detect the rep list from
    the scene. Uses the verified `rep <name>` selector."""
    active = []
    for rep in GAME_REPS:
        try:
            if cmd.count_atoms(f"{obj} and rep {rep}") > 0:
                active.append(rep)
        except Exception:
            pass   # invalid selection / no such object — skip
    return active
```
**Fallback if no rep is active** (object loaded but `show` not yet called): return an empty list and let the Setup form default to showing all 5 reps as "available" (the SETUP-04 "when false, list all available reps" branch).

### 3.7 Recommended hider-count cap (SETUP-03)

SETUP-03: "Hider count input, capped to a reasonable maximum relative to the object's atom count."

**Recommendation (formula + defaults):**
```python
def hider_count_cap(atom_count):
    """Sane max hider count for an object with `atom_count` atoms.
    Heuristic: 1 hider per ~50 atoms, capped to [1, 50]. Keeps small
    demos (1znf ~212 atoms -> cap 5; 1K8P ~555 -> cap 11) findable and
    large objects (4WB3 ~3779 -> cap 50) from being overwhelming."""
    if atom_count <= 0:
        return 1
    return max(1, min(50, atom_count // 50))

DEFAULT_HIDER_COUNT = 10  # used by Reset (BTN-01) and as the initial spinbox value
```
**Rationale:** 1 hider per ~50 atoms is generous (the smallest demo, 1znf at 212 atoms, gets a cap of 4 — small enough to be findable). The hard cap of 50 prevents the spinbox from going absurd on a 100k-atom membrane protein (Phase 9's concern, but the cap protects Phase 2's spinbox now). The minimum of 1 guards the empty-object edge case.

**When to recompute the cap:** recompute on target change (when the object selector's selection changes, or after a fetch/load completes) and call `self.hider_spin.setMaximum(cap)` + clamp `self.hider_spin.setValue(min(current, cap))`. Wire this into the object-selector's `currentTextChanged` signal (§5.2).

---

## 4. Bundled Demo PDBs (DEMO-01)

### 4.1 The 6 demo IDs and their categories

| ID | Category | Type | Difficulty | Atoms (deposited) | Method | Title (short) |
|----|----------|------|-----------|-------------------|--------|---------------|
| 1znf | Protein | Protein | Easy | 212 (37 NMR models) | SOLUTION NMR | Zinc finger DNA-binding domain |
| 1xdn | Protein | Protein | Hard | 2597 | X-RAY 1.2Å | RNA editing ligase 1 (T. brucei) |
| 5e54 | Nucleic acid | RNA | Easy | 2844 | X-RAY (XFEL) 2.3Å | Adenine riboswitch aptamer (apo) |
| 1k8p | Nucleic acid | DNA | Easy | 555 | X-RAY 2.4Å | Human telomeric G-quadruplex (parallel) |
| 2qbz | Nucleic acid | RNA | Hard | 3408 | X-RAY 2.6Å | M-Box metal-sensing riboswitch |
| 4wb3 | Mixed | Protein/NA | (n/a — mixed) | 3779 | X-RAY 2.0Å | C5a + L-RNA/L-DNA aptamer NOX-D20 |

(Atom counts and metadata from the RCSB REST API `data.rcsb.org/rest/v1/core/entry/{ID}`, fetched 2026-08-03. The category/difficulty mapping is from DEMO-01 in REQUIREMENTS.md.)

### 4.2 Canonical fetch URL — VERIFIED

**`https://files.rcsb.org/download/{ID}.pdb`** — confirmed end-to-end: I fetched `https://files.rcsb.org/download/1znf.pdb` and received a valid PDB file (HEADER, TITLE, ATOM/HETATM records, JRNL citation, etc.). The URL pattern is `https://files.rcsb.org/download/{PDB_ID_UPPERCASE}.pdb`. RCSB also accepts lowercase.

**Note on file sizes:** the 1znf PDB is an NMR ensemble (37 models, NUMMDL 37) so its `.pdb` file is ~1.2 MB despite only 212 atoms/model — much larger than the others. The other 5 are single-model X-ray structures, typically 50–500 KB. Total bundle is small (a few MB), fine to commit. **Do NOT gzip** in Phase 2 (PROJECT.md mentions compression for the *large* Phase 9 membrane demos; the 6 small demos are fine uncompressed, and un-gzipped `.pdb` is easier for the user to inspect and for `cmd.load` to read without a decompression step).

### 4.3 Storage location & gitignore decision

**Recommended:** `biochemeleon/data/demos/{id}.pdb` (lowercase filenames, e.g. `1znf.pdb`, `5e54.pdb`).

**Why `biochemeleon/data/demos/` (not `biochemeleon/demos/`):** `biochemeleon/demos.py` is already a Python module (Phase 1 stub). Putting PDB files in a sibling `demos/` directory would shadow/import-collide with the module. A `data/` subdirectory keeps data separate from code. (`demos.py` is the DemoLoader code; `data/demos/` is the PDB data.)

**Why NOT `biochemeleon/demos/` as a subpackage:** same name-collision reason — Python would see `biochemeleon/demos/` as a package and `biochemeleon/demos.py` as a module, and the package wins, breaking `from .demos import DemoLoader`.

**Gitignore:** **DO NOT gitignore `biochemeleon/data/demos/`.** DEMO-01 explicitly says "Bundle the small demo PDBs **in the repo** with sources cited." They are committed. (`.gitignore` already excludes `Pymol-script-repo/` and `3rd_party_lib/` but not `biochemeleon/data/` — leave it that way.)

**Size implications:** 6 small PDBs, a few MB total — negligible for git. Commit them directly.

### 4.4 The DemoLoader design — manifest + load_demo

**Manifest:** a Python dict (in `demos.py`) — not a separate JSON file. A Python dict is simpler (no file I/O at import time), is easy for Phase 9 to extend with the large fetched demos, and keeps the citation metadata co-located with the loader code. (A JSON manifest is also fine; the dict is marginally simpler for Phase 2's small fixed set.)

```python
# biochemeleon/demos.py  (manifest — paste-ready)

# Category taxonomy for the demo sub-menu (SETUP-02 + DEMO-01).
# Phase 2 surfaces Easy/Hard; Phase 9 (DIFF-05) adds Challenge/Very challenging.
DEMO_MANIFEST = {
    # id : {category, type, difficulty, file, citation_key}
    '1znf': {'category': 'Protein',      'type': 'protein', 'difficulty': 'easy',   'file': '1znf.pdb'},
    '1xdn': {'category': 'Protein',      'type': 'protein', 'difficulty': 'hard',  'file': '1xdn.pdb'},
    '5e54': {'category': 'Nucleic acid', 'type': 'rna',     'difficulty': 'easy',   'file': '5e54.pdb'},
    '1k8p': {'category': 'Nucleic acid', 'type': 'dna',     'difficulty': 'easy',   'file': '1k8p.pdb'},
    '2qbz': {'category': 'Nucleic acid', 'type': 'rna',     'difficulty': 'hard',  'file': '2qbz.pdb'},
    '4wb3': {'category': 'Mixed',        'type': 'protein/na', 'difficulty': 'easy', 'file': '4wb3.pdb'},
}
# Citations live in biochemeleon/data/demos/SOURCES.md (§4.5).
```

**Demo sub-menu structure (SETUP-02 "sub-menu for demo categories"):** the object selector's "demo" mode should present the demos grouped by category. The simplest Qt pattern: a `QComboBox` whose items are prefixed with the category, OR a small tree. **Recommendation:** use a flat `QComboBox` with items formatted as `"{category} — {id} ({difficulty})"` (e.g. `"Protein — 1znf (easy)"`), keyed internally by `id`. A flat combo is simpler than a `QTreeWidget` and is enough for 6 items. If Phase 9 grows the set to ~15+ demos, upgrade to a `QTreeWidget` with category top-level nodes then.

```python
# Wiring the demo combo (in gui_setup.py)
self.demo_combo = QtWidgets.QComboBox()
for did, meta in DEMO_MANIFEST.items():
    self.demo_combo.addItem(
        f"{meta['category']} — {did} ({meta['difficulty']})",   # display text
        did                                                     # userData = the id
    )
# To read the selection: self.demo_combo.currentData()  -> '1znf' etc.
```

**`load_demo(demo_id)` method:**
```python
# biochemeleon/demos.py (load_demo — paste-ready)
import os
from pymol import cmd

def load_demo(demo_id):
    """Load a bundled demo PDB into PyMOL by its manifest id (e.g. '1znf').
    Returns the object name on success, None on failure. The PDB is
    resolved relative to this module's __file__ so it works identically
    whether the plugin runs from the repo or from the installed copy in
    the user plugin dir. Paths are passed through to_windows_path() so
    Windows PyMOL (which cannot resolve /mnt/c/... WSL paths) can open them.
    """
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None:
        return None
    path = os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])
    if not os.path.exists(path):
        return None
    win_path = to_windows_path(path)        # see §6
    obj_name = demo_id.lower()              # PyMOL object names are conventionally lowercase
    try:
        cmd.load(win_path, object=obj_name, zoom=1)
        return obj_name
    except Exception:
        return None
```

### 4.5 Source citation file — `biochemeleon/data/demos/SOURCES.md`

DEMO-01 says "with sources cited in documentation". DEMO-04 (a full `DATA_SOURCES.md` at the repo root) is Phase 9. **For Phase 2, write a lightweight `biochemeleon/data/demos/SOURCES.md` next to the PDBs**, with one citation entry per PDB. Phase 9's `DATA_SOURCES.md` can later absorb or link to this file.

**Citation format (per RCSB policy: PDB ID + DOI + corresponding publication + graphics program):**

```markdown
# biochemeleon/data/demos/SOURCES.md
# Sources for the bundled small demo PDBs in bioCHEMeleon.
# All PDB entries are © RCSB PDB, licensed CC0 1.0 (Public Domain Dedication).
# https://www.rcsb.org/pages/policies
# Cite: PDB ID + DOI + the corresponding publication + PyMOL (Schrödinger LLC).

## 1znf — Protein (Easy)
- PDB ID: 1ZNF
- DOI: https://doi.org/10.2210/pdb1znf/pdb
- Title: Three-dimensional solution structure of a single zinc finger DNA-binding domain.
- Authors: Lee, M.S.; Gippert, G.P.; Soman, K.V.; Case, D.A.; Wright, P.E.
- Publication: Science, vol. 245, pp. 635-637 (1989). PMID 2503871.
- Method: Solution NMR (37 models).

## 1xdn — Protein (Hard)
- PDB ID: 1XDN
- DOI: https://doi.org/10.2210/pdb1xdn/pdb
- Title: High resolution crystal structure of a key editosome enzyme from Trypanosoma brucei: RNA editing ligase 1.
- Authors: Deng, J.; Schnaufer, A.; Salavati, R.; Stuart, K.D.; Hol, W.G.
- Publication: J. Mol. Biol., vol. 343, pp. 601-613 (2004). DOI 10.1016/j.jmb.2004.08.041. PMID 15465048.
- Method: X-ray diffraction, 1.2 Å resolution.

## 5e54 — RNA (Easy)
- PDB ID: 5E54
- DOI: https://doi.org/10.2210/pdb5e54/pdb
- Title: Structures of riboswitch RNA reaction states by mix-and-inject XFEL serial crystallography.
- Authors: Stagno, J.R.; Liu, Y.; ...; Wang, Y.-X. (full list in PDB header)
- Publication: Nature, vol. 541, pp. 242-246 (2017). DOI 10.1038/nature20599. PMID 27841871.
- Method: X-ray free-electron laser (XFEL) serial crystallography, 2.3 Å.
- Notes: Adenine riboswitch aptamer domain, apo (ligand-free) state.

## 1k8p — DNA (Easy)
- PDB ID: 1K8P
- DOI: https://doi.org/10.2210/pdb1k8p/pdb
- Title: Crystal structure of parallel quadruplexes from human telomeric DNA.
- Authors: Parkinson, G.N.; Lee, M.P.; Neidle, S.
- Publication: Nature, vol. 417, pp. 876-880 (2002). DOI 10.1038/nature755. PMID 12050675.
- Method: X-ray diffraction, 2.4 Å.
- Notes: Human telomeric G-quadruplex, parallel-stranded.

## 2qbz — RNA (Hard)
- PDB ID: 2QBZ
- DOI: https://doi.org/10.2210/pdb2qbz/pdb
- Title: Structure and mechanism of a metal-sensing regulatory RNA.
- Authors: Dann III, C.E.; Wakeman, C.A.; Sieling, C.L.; Baker, S.C.; Irnov, I.; Winkler, W.C.
- Publication: Cell, vol. 130, pp. 878-892 (2007). DOI 10.1016/j.cell.2007.06.051. PMID 17803910.
- Method: X-ray diffraction, 2.6 Å.
- Notes: M-Box riboswitch aptamer domain (metal-sensing regulatory RNA).

## 4wb3 — Mixed (Protein + Nucleic acid)
- PDB ID: 4WB3
- DOI: https://doi.org/10.2210/pdb4wb3/pdb
- Title: Structural basis for the targeting of complement anaphylatoxin C5a using a mixed L-RNA/L-DNA aptamer.
- Authors: Yatime, L.; Maasch, C.; Hoehlig, K.; Klussmann, S.; Andersen, G.R.; Vater, A.
- Publication: Nat. Commun., vol. 6, p. 6481 (2015). DOI 10.1038/ncomms7481. PMID 25901944.
- Method: X-ray diffraction, 2.0 Å.
- Notes: Mirror-image L-RNA/L-DNA aptamer NOX-D20 in complex with mouse C5a-desArg complement anaphylatoxin (protein/NA hybrid).

## License
RCSB PDB data files are available under the CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
(https://www.rcsb.org/pages/policies). Attribution is requested (above) per wwPDB policy.
```
All citation fields (DOI, authors, journal, vol/pp, year, PMID, method) were fetched directly from the RCSB REST API `data.rcsb.org/rest/v1/core/entry/{ID}` on 2026-08-03 — HIGH confidence.

---

## 5. The Setup Form Layout — Mapping SETUP-01..06 + BTN-01..04 to Widgets

### 5.1 Recommended top-level structure

`SetupTab(QWidget)` holds a `QVBoxLayout` of four `QGroupBox` sections, in this order (matches the user's natural top-to-bottom config flow):

```
SetupTab (QVBoxLayout)
├── QGroupBox "Target"            (SETUP-02)
│     ├── mode selector (QComboBox: "Loaded object" / "PDB fetch" / "Bundled demo")
│     └── QStackedWidget (swaps by mode):
│           ├── page 0: PyMOLObjectCombo + refresh button   (loaded object)
│           ├── page 1: QLineEdit (PDB code) + "Fetch" QPushButton
│           └── page 2: QComboBox (demo list, from DEMO_MANIFEST)
├── QGroupBox "Hiders"            (SETUP-03, SETUP-04, SETUP-05)
│     ├── QFormLayout row: "Hider count" -> QSpinBox (capped via §3.7)
│     ├── QCheckBox "Lock current scene"  (SETUP-04)
│     └── QGroupBox "Per-rep hider counts" (SETUP-05)
│           └── one QHBoxLayout row per rep in GAME_REPS:
│                 [QCheckBox(rep), QSpinBox(count), QLabel("random")]
├── QGroupBox "Difficulty"        (SETUP-06)
│     └── QFormLayout row: "Show per-rep remaining" -> QCheckBox (easy=True / hard=False)
└── QGroupBox "Buttons"           (BTN-01..04)
      └── QHBoxLayout: [Reset, Randomize, Save Setup, Load Setup]  (4 QPushButtons)
```

Use `QGroupBox` + `QFormLayout` (verified pattern: `optimize.py:89,165` uses `QGroupBox`; `vina.py:711,777-780` uses `QFormLayout.addRow("Label:", widget)`). The `QStackedWidget` for the 3-mode object selector is the clean way to swap widgets by mode (Qt's idiomatic "show one of N" container).

### 5.2 SetupTab skeleton (paste-ready scaffold)

```python
# biochemeleon/gui_setup.py
"""Setup tab — full config form (Phase 2)."""
import json
import random

from pymol.Qt import QtCore, QtGui, QtWidgets
from pymol import cmd

from .demos import (
    DEMO_MANIFEST, load_demo, list_loaded_molecule_objects,
    fetch_pdb, get_active_reps, GAME_REPS, hider_count_cap,
)

DEFAULTS = {
    "target_mode": "loaded",      # "loaded" | "fetch" | "demo"
    "selected_object": "",        # name of loaded object (mode='loaded')
    "pdb_code": "",               # PDB code string (mode='fetch')
    "demo_id": "1znf",            # manifest id (mode='demo')
    "hider_count": 10,
    "lock_scene": False,
    "per_rep": {},                # {rep: count} — empty/missing = random
    "difficulty_easy": True,      # True=easy (show per-rep), False=hard
}


class PyMOLObjectCombo(QtWidgets.QComboBox):
    """QComboBox that refreshes from cmd.get_names on showPopup (vina.py:1153)."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setEditable(True)
        self.setInsertPolicy(QtWidgets.QComboBox.NoInsert)

    def showPopup(self):
        current = self.currentText().strip()
        self.clear()
        self.addItems(list_loaded_molecule_objects())
        if current:
            self.setCurrentText(current)
        super().showPopup()


class SetupTab(QtWidgets.QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._build_ui()
        self.apply_state(DEFAULTS)   # initialize to defaults on construction

    # ---- UI construction ----
    def _build_ui(self):
        outer = QtWidgets.QVBoxLayout(self)

        # --- Target group (SETUP-02) ---
        tgt = QtWidgets.QGroupBox("Target")
        tgt_form = QtWidgets.QFormLayout(tgt)
        self.mode_combo = QtWidgets.QComboBox()
        self.mode_combo.addItem("Loaded object", "loaded")
        self.mode_combo.addItem("Fetch from PDB", "fetch")
        self.mode_combo.addItem("Bundled demo", "demo")
        tgt_form.addRow("Source:", self.mode_combo)

        self.target_stack = QtWidgets.QStackedWidget()
        # page 0: loaded object
        p0 = QtWidgets.QWidget(); p0l = QtWidgets.QHBoxLayout(p0)
        self.obj_combo = PyMOLObjectCombo()
        self.obj_refresh_btn = QtWidgets.QPushButton()
        icon = self.style().standardIcon(QtWidgets.QStyle.SP_BrowserReload)
        self.obj_refresh_btn.setIcon(icon)
        self.obj_refresh_btn.setFixedSize(25, 25)
        self.obj_refresh_btn.setToolTip("Refresh loaded objects")
        p0l.addWidget(self.obj_combo); p0l.addWidget(self.obj_refresh_btn)
        # page 1: PDB fetch
        p1 = QtWidgets.QWidget(); p1l = QtWidgets.QHBoxLayout(p1)
        self.pdb_edit = QtWidgets.QLineEdit()
        self.pdb_edit.setPlaceholderText("e.g. 1znf")
        self.fetch_btn = QtWidgets.QPushButton("Fetch")
        p1l.addWidget(self.pdb_edit); p1l.addWidget(self.fetch_btn)
        # page 2: bundled demo
        p2 = QtWidgets.QWidget(); p2l = QtWidgets.QHBoxLayout(p2)
        self.demo_combo = QtWidgets.QComboBox()
        for did, meta in DEMO_MANIFEST.items():
            self.demo_combo.addItem(
                f"{meta['category']} — {did} ({meta['difficulty']})", did)
        p2l.addWidget(self.demo_combo)
        self.target_stack.addWidget(p0)
        self.target_stack.addWidget(p1)
        self.target_stack.addWidget(p2)
        tgt_form.addRow(self.target_stack)
        outer.addWidget(tgt)

        # --- Hiders group (SETUP-03/04/05) ---
        hiders = QtWidgets.QGroupBox("Hiders")
        hform = QtWidgets.QFormLayout(hiders)
        self.hider_spin = QtWidgets.QSpinBox()
        self.hider_spin.setRange(1, 50)
        self.hider_spin.setValue(DEFAULTS["hider_count"])
        hform.addRow("Hider count:", self.hider_spin)
        self.lock_scene_cb = QtWidgets.QCheckBox(
            "Lock current scene (use the object's current representations)")
        hform.addRow(self.lock_scene_cb)
        # per-rep rows
        self.rep_group = QtWidgets.QGroupBox("Per-rep hider counts (unchecked = random)")
        rbox = QtWidgets.QVBoxLayout(self.rep_group)
        self.rep_rows = {}
        for rep in GAME_REPS:
            row = QtWidgets.QHBoxLayout()
            cb = QtWidgets.QCheckBox(rep)
            spin = QtWidgets.QSpinBox(); spin.setRange(0, 999); spin.setValue(0)
            spin.setEnabled(False)
            label = QtWidgets.QLabel("random")
            row.addWidget(cb); row.addWidget(spin); row.addWidget(label); row.addStretch()
            rbox.addLayout(row)
            self.rep_rows[rep] = (cb, spin, label)
            cb.toggled.connect(
                lambda on, s=spin, l=label: self._on_rep_toggled(on, s, l))
        hform.addRow(self.rep_group)
        outer.addWidget(hiders)

        # --- Difficulty group (SETUP-06) ---
        diff = QtWidgets.QGroupBox("Difficulty")
        dform = QtWidgets.QFormLayout(diff)
        self.diff_easy_cb = QtWidgets.QCheckBox(
            "Easy: show remaining hiders per representation (uncheck for Hard: total only)")
        dform.addRow(self.diff_easy_cb)
        outer.addWidget(diff)

        # --- Buttons group (BTN-01..04) ---
        btns = QtWidgets.QGroupBox("Setup actions")
        brow = QtWidgets.QHBoxLayout(btns)
        self.reset_btn = QtWidgets.QPushButton("Reset")
        self.random_btn = QtWidgets.QPushButton("Randomize")
        self.save_btn = QtWidgets.QPushButton("Save Setup…")
        self.load_btn = QtWidgets.QPushButton("Load Setup…")
        for b in (self.reset_btn, self.random_btn, self.save_btn, self.load_btn):
            brow.addWidget(b)
        outer.addWidget(btns)

        # --- Signal wiring ---
        self.mode_combo.currentIndexChanged.connect(self._on_mode_changed)
        self.obj_combo.currentTextChanged.connect(self._on_target_changed)
        self.obj_refresh_btn.clicked.connect(lambda: self.obj_combo.showPopup())
        self.fetch_btn.clicked.connect(self._on_fetch)
        self.demo_combo.currentIndexChanged.connect(self._on_target_changed)
        self.reset_btn.clicked.connect(lambda: self.apply_state(DEFAULTS))
        self.random_btn.clicked.connect(self._randomize)
        self.save_btn.clicked.connect(self._save_setup)
        self.load_btn.clicked.connect(self._load_setup)

    # ---- Slots (see §5.3, §7, §8 for the bodies) ----
    def _on_mode_changed(self, idx):
        self.target_stack.setCurrentIndex(idx)

    def _on_target_changed(self, *_):
        # Recompute the hider-count cap from the newly-selected target.
        obj = self.current_target_object()
        if obj:
            cap = hider_count_cap(cmd.count_atoms(obj))
            self.hider_spin.setMaximum(max(1, cap))
            self.hider_spin.setValue(min(self.hider_spin.value(), cap))
        # If "lock scene" is checked, refresh the per-rep checkboxes from the scene.
        if self.lock_scene_cb.isChecked() and obj:
            self._sync_reps_from_scene(obj)

    def _on_fetch(self):
        # See §7 for the try/except + QMessageBox pattern.
        ...

    def _on_rep_toggled(self, on, spin, label):
        spin.setEnabled(on)
        label.setText("" if on else "random")

    def _sync_reps_from_scene(self, obj):
        active = get_active_reps(obj)  # §3.6 — uses `rep <name>` selector
        for rep, (cb, spin, label) in self.rep_rows.items():
            checked = rep in active
            cb.setChecked(checked)
            cb.setEnabled(False)   # locked: can't change which reps — scene is locked
            spin.setEnabled(checked)
            label.setText("" if checked else "random")

    def current_target_object(self):
        """Return the PyMOL object name the Setup form currently points at,
        or None if the target isn't a loaded object yet (e.g. fetch/demo not
        yet executed). Used by _on_target_changed to recompute the cap."""
        mode = self.mode_combo.currentData()
        if mode == "loaded":
            name = self.obj_combo.currentText().strip()
            return name if name and name in list_loaded_molecule_objects() else None
        return None  # fetch/demo targets aren't loaded until the user clicks Fetch/loads the demo

    # ---- collect_state / apply_state (BTN-01/03/04) ----  (see §8)
    def collect_state(self): ...
    def apply_state(self, state): ...
    def _randomize(self): ...
    def _save_setup(self): ...
    def _load_setup(self): ...
```

### 5.3 Slot bodies referenced above

- `_on_mode_changed` swaps the `QStackedWidget` page (1 line).
- `_on_target_changed` recomputes the hider-count cap (§3.7) and, if "lock scene" is on, calls `_sync_reps_from_scene` (§3.6).
- `_on_fetch` calls `fetch_pdb` (§3.4) inside a try/except; on failure shows a `QMessageBox` (§7).
- `_on_rep_toggled` enables/disables the spinbox + flips the "random" label.
- `collect_state` / `apply_state` / `_randomize` / `_save_setup` / `_load_setup` are defined in §8.

---

## 6. `to_windows_path()` Helper (Phase-2 deliverable, Pitfall 11)

**Read PITFALLS.md Pitfall 11 first.** Summary: PyMOL runs as a Windows process (launched via `setenv.bat`) and cannot resolve WSL paths (`/mnt/c/...`). Any path passed to `cmd.load`/`cmd.save` must be a Windows path (`C:\...`). The helper converts WSL mount paths to Windows paths.

### 6.1 Two runtime cases (CRITICAL distinction)

The plugin's bundled-demo files can be loaded in two situations, and the path resolution differs:

**(a) Runtime in installed Windows PyMOL (the normal case):** the plugin lives at `%APPDATA%\pymol\startup\biochemeleon\` (Windows path). `os.path.dirname(__file__)` returns a **Windows-native** path like `C:\Users\nglok\AppData\Roaming\pymol\startup\biochemeleon`. This path is **already** Windows-native — `to_windows_path()` is a no-op on it (the `/mnt/` guard returns it unchanged).

**(b) Dev-test from a WSL path (the dev case):** during development the plugin may be imported from the repo at `/mnt/c/Users/nglok/Desktop/.../biochemeleon/`. `os.path.dirname(__file__)` returns a **WSL** path like `/mnt/c/Users/nglok/Desktop/.../biochemeleon`. Windows PyMOL cannot open `/mnt/c/...` — it needs `C:\Users\nglok\Desktop\...\biochemeleon`. **This is when `to_windows_path()` does the conversion.**

**So `to_windows_path()` must be a guard, not an unconditional transform:** convert only if the path starts with `/mnt/`; otherwise return unchanged. This keeps the code portable (a genuine Linux PyMOL install would get Linux paths, which `cmd.load` handles natively — no conversion needed).

### 6.2 Paste-ready implementation

**Location:** `biochemeleon/demos.py` (per the Phase-1 TODO documented at `biochemeleon/demos.py:3`). Keeping it in `demos.py` is simplest — it's the only module that loads files in Phase 2, and the TODO already points there. Do NOT create a separate `util.py` for one function.

```python
# biochemeleon/demos.py
import os

def to_windows_path(path):
    """Convert a WSL mount path (/mnt/c/...) to a Windows path (C:\\...).

    PyMOL runs as a Windows process (launched via setenv.bat) and cannot
    resolve WSL paths. This helper is the Pitfall 11 fix (see
    .planning/research/PITFALLS.md). It is a GUARD, not an unconditional
    transform: only paths starting with /mnt/<letter>/ are converted;
    all other paths (already-Windows C:\\... paths from an installed
    plugin, or genuine Linux paths from a Linux PyMOL) are returned
    unchanged so the code is portable.

    Args:
        path: str -- a filesystem path, possibly a WSL mount path.

    Returns:
        str -- the same path expressed as a Windows backslash path if the
        input was a /mnt/<drive>/... WSL path; otherwise the input unchanged.
    """
    # Match /mnt/<single drive letter>/<rest>
    p = str(path)
    parts = p.replace('\\', '/').split('/', 3)  # normalize slashes then split
    # parts looks like ['', 'mnt', 'c', 'Users/...'] for a WSL mount path
    if len(parts) == 4 and parts[0] == '' and parts[1] == 'mnt' \
            and len(parts[2]) == 1 and parts[2].isalpha():
        drive = parts[2].upper()
        rest = parts[3]
        return '{}:\\{}'.format(drive, rest.replace('/', '\\'))
    return p   # not a WSL mount path — return as-is (already Windows or Linux)
```

**Test (in WSL, no PyMOL needed):** `to_windows_path('/mnt/c/Users/nglok/x.pdb')` → `'C:\\Users\\nglok\\x.pdb'`; `to_windows_path('C:\\Users\\nglok\\x.pdb')` → `'C:\\Users\\nglok\\x.pdb'` (unchanged); `to_windows_path('/home/lwng/x.pdb')` → `'/home/lwng/x.pdb'` (unchanged — genuine Linux path).

**Limitation (documented):** this only converts WSL mount paths (`/mnt/<drive>/...`). It does NOT handle the `\\wsl$\` UNC path form (that's for the Plugin Manager's file picker, not for `cmd.load` — Phase 1 already documents the install path). It does NOT help if PyMOL is genuinely on Linux (a real Linux install gets Linux paths, which `cmd.load` handles natively — the guard returns them unchanged, which is correct).

### 6.3 `cmd.exp_path` — NOT recommended

PyMOL has `cmd.exp_path(path)` which expands `~` and resolves paths, but it does NOT do WSL→Windows conversion (it runs inside the Windows PyMOL process where `~` is a Windows home, not a WSL home). **Do not use `cmd.exp_path` to solve Pitfall 11** — use `to_windows_path()`. (`cmd.exp_path` is fine for `~` expansion if ever needed, but it's not the WSL fix.)

---

## 7. Save/Load Setup to a File (BTN-03, BTN-04) + Reset (BTN-01) + Randomize (BTN-02)

### 7.1 The setup-parameters data model (JSON schema)

```python
# collect_state() returns this dict; apply_state(state) takes it.
# JSON-serializable (only str/int/float/bool/dict/list — pymol.plugins.pref_set
# only supports basic types, and json.dump needs the same).
{
  "format": "biochemeleon-setup-v1",
  "target_mode": "loaded",          # "loaded" | "fetch" | "demo"
  "selected_object": "1znf",        # mode='loaded' -> object name
  "pdb_code": "",                   # mode='fetch' -> PDB code (lowercased)
  "demo_id": "1znf",                # mode='demo' -> manifest id
  "hider_count": 8,
  "lock_scene": true,
  "per_rep": {                      # only reps the user explicitly assigned
    "spheres": 3,                    # rep -> count. Missing rep = "random".
    "cartoon": 5                    # (the game later distributes the remaining
  },                                 #  hider_count - sum(per_rep) randomly across
  "difficulty_easy": false           #  the unchecked reps — Phase 4's job)
}
```
**Concrete JSON example (what Save writes):**
```json
{
  "format": "biochemeleon-setup-v1",
  "target_mode": "demo",
  "selected_object": "",
  "pdb_code": "",
  "demo_id": "1xdn",
  "hider_count": 12,
  "lock_scene": false,
  "per_rep": {},
  "difficulty_easy": false
}
```

### 7.2 File-dialog filter & extension

**Recommended extension:** `*.bcm.setup.json` (NOT `.bcm` — Phase 8 uses `.bcm` for game-state sidecars; a distinct setup extension avoids confusion). The filter string: `"bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)"`.

**QFileDialog usage** (verified patterns: `outline.py:170-171` for save, `vina.py:746-752` for open):
```python
# Save Setup (BTN-03)
path, _ = QtWidgets.QFileDialog.getSaveFileName(
    self, "Save bioCHEMeleon Setup", "", "bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)")
if path:
    if not path.lower().endswith('.json'):
        path += '.bcm.setup.json'
    with open(path, 'w') as f:
        json.dump(self.collect_state(), f, indent=2)

# Load Setup (BTN-04)
path, _ = QtWidgets.QFileDialog.getOpenFileName(
    self, "Load bioCHEMeleon Setup", "", "bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)")
if path:
    with open(path) as f:
        state = json.load(f)
    self.apply_state(state)
```
**Modal file dialog is OK:** `QFileDialog.getSaveFileName`/`getOpenFileName` are modal by default — that's fine. PITFALLS.md only forbids making the **main plugin dialog** modal; a modal file dialog (or a modal `QMessageBox`) inside the modeless plugin is standard and expected. (Confirmed: `outline.py:178-182` uses `QMessageBox.exec_()`; `vina.py:688` uses `fileDialog.exec_()`.)

### 7.3 `collect_state()` / `apply_state(state)` (paste-ready)

```python
def collect_state(self):
    """Snapshot the current Setup form into a JSON-serializable dict."""
    per_rep = {}
    for rep, (cb, spin, label) in self.rep_rows.items():
        if cb.isChecked():
            per_rep[rep] = spin.value()
    return {
        "format": "biochemeleon-setup-v1",
        "target_mode": self.mode_combo.currentData() or "loaded",
        "selected_object": self.obj_combo.currentText().strip(),
        "pdb_code": self.pdb_edit.text().strip().lower(),
        "demo_id": self.demo_combo.currentData() or "1znf",
        "hider_count": self.hider_spin.value(),
        "lock_scene": self.lock_scene_cb.isChecked(),
        "per_rep": per_rep,
        "difficulty_easy": self.diff_easy_cb.isChecked(),
    }

def apply_state(self, state):
    """Repopulate every widget from a state dict (used by Reset, Load, and
    __init__). Tolerates missing keys (forward-compat with future fields)."""
    mode = state.get("target_mode", "loaded")
    idx = {"loaded": 0, "fetch": 1, "demo": 2}.get(mode, 0)
    self.mode_combo.setCurrentIndex(idx)
    self.obj_combo.setEditText(state.get("selected_object", ""))
    self.pdb_edit.setText(state.get("pdb_code", ""))
    demo_id = state.get("demo_id", "1znf")
    for i in range(self.demo_combo.count()):
        if self.demo_combo.itemData(i) == demo_id:
            self.demo_combo.setCurrentIndex(i); break
    self.hider_spin.setValue(int(state.get("hider_count", 10)))
    self.lock_scene_cb.setChecked(bool(state.get("lock_scene", False)))
    per_rep = state.get("per_rep", {})
    for rep, (cb, spin, label) in self.rep_rows.items():
        if rep in per_rep:
            cb.setChecked(True)
            spin.setValue(int(per_rep[rep]))
            spin.setEnabled(True)
            label.setText("")
        else:
            cb.setChecked(False)
            spin.setValue(0)
            spin.setEnabled(False)
            label.setText("random")
    self.diff_easy_cb.setChecked(bool(state.get("difficulty_easy", True)))
```

### 7.4 Reset (BTN-01) — restore defaults

```python
self.reset_btn.clicked.connect(lambda: self.apply_state(DEFAULTS))
```
`DEFAULTS` (defined at the top of `gui_setup.py`, §5.2) is the source of truth for defaults. Reset = `apply_state(DEFAULTS)`. One line.

### 7.5 Randomize (BTN-02) — concrete logic

```python
def _randomize(self):
    """Randomize setup params within sane bounds."""
    import random
    # pick a random target mode (weight toward 'demo' so the user sees demos)
    mode = random.choice(["loaded", "fetch", "demo", "demo"])
    state = {"target_mode": mode, "selected_object": "", "pdb_code": "",
             "demo_id": random.choice(list(DEMO_MANIFEST.keys())),
             "lock_scene": random.choice([True, False]),
             "difficulty_easy": random.choice([True, False]),
             "per_rep": {}}
    # hider count: random in [1, cap] if a target is loaded, else [1, 50]
    obj = self.current_target_object()
    cap = hider_count_cap(cmd.count_atoms(obj)) if obj else 50
    state["hider_count"] = random.randint(1, max(1, cap))
    # per-rep: pick a random non-empty subset of reps, assign random counts
    # that sum to <= hider_count (the rest are 'random' — Phase 4 distributes)
    reps = random.sample(GAME_REPS, random.randint(0, len(GAME_REPS)))
    remaining = state["hider_count"]
    for rep in reps:
        if remaining <= 0:
            break
        c = random.randint(0, remaining)
        if c:
            state["per_rep"][rep] = c
            remaining -= c
    self.apply_state(state)
```

---

## 8. Should `PluginDialog` be extracted to `gui_dialog.py`?

**Recommendation: NO — do not extract in Phase 2.** `__init__.py` stays as-is; only `gui_setup.py` and `demos.py` grow.

**Reasoning:** Phase 2 grows `gui_setup.py` (the Setup form) and `demos.py` (DemoLoader + to_windows_path). It does **not** grow `PluginDialog` — `PluginDialog` (in `__init__.py`) just constructs `SetupTab()` and `GameTab()` and adds them to the `QTabWidget`, exactly as in Phase 1. The Phase-1 `PluginDialog` is 29 lines and stays ~29 lines in Phase 2. The "may extract if it grows large" note in the Phase-1 SUMMARY was conditional on `PluginDialog` itself gaining logic; Phase 2 doesn't add any. Extraction would be churn with no benefit.

**When to revisit:** if a later phase adds cross-tab logic to `PluginDialog` (e.g. Phase 4's Start button needs to switch tabs + run a 3-2-1 countdown coordinated between Setup and Game tabs), that's the moment to consider extracting `PluginDialog` to `gui_dialog.py`. Phase 2 is not that moment.

**The only `__init__.py` change in Phase 2:** none required. (`PluginDialog` already lazy-imports `SetupTab`/`GameTab` inside `__init__`, so the populated `SetupTab` is picked up automatically when Phase 2's `gui_setup.py` is written. No `__init__.py` edit needed.)

---

## 9. Pitfalls Active in Phase 2

Re-read `PITFALLS.md` and Phase-1 RESEARCH §8. The pitfalls that bite Phase 2:

### 9.1 Pitfall 11 — WSL→Windows path (ACTIVE, addressed by §6)
The `to_windows_path()` helper (§6) is the Phase-2 deliverable that closes this. The `__file__`-relative path resolution in `load_demo` (§4.4) means the installed-plugin case gets a Windows-native path automatically; the dev-WSL case is handled by the guard. **Verification:** the bundled-demo load smoke test (Success Criterion 4) exercises this end-to-end via `setenv.bat`.

### 9.2 Qt threading — `cmd.*` calls directly from Qt slots (SAFE, but confirm)
**Can `cmd.load`/`cmd.fetch`/`cmd.get_names` be called directly from a Qt `clicked` signal handler?** In PyMOL Qt builds, the cmd interpreter runs on the **main Qt thread** (PyMOL's GUI event loop IS the Qt event loop). PITFALLS.md Pitfall 6 says: *"all `cmd.*` calls happen on the GUI main thread"* — and Qt slots connected with `Qt::DirectConnection` (the default for same-thread sender/receiver) also run on the main thread. **So `cmd.load`/`cmd.fetch`/`cmd.get_names` called directly from a `clicked` slot is safe** — no `QTimer.singleShot(0, ...)` marshalling needed. The reference repo confirms: `vina.py` calls `cmd.count_atoms` directly inside a `@currentTextChanged.connect` slot (`vina.py:1203`); `outline.py` calls `cmd.load_png`/`cmd.scene`/`cmd.set` directly inside button handlers.

**The one caveat (Pitfall 6, does NOT bite Phase 2):** do NOT spawn a `threading.Thread` or `QThread` that calls `cmd.*`. Phase 2 has no threads (no timer, no long-running work) — `cmd.fetch` is synchronous and short on small PDBs, and the bundled demos load in <1s. So Phase 2 is automatically safe. (If a future phase adds a long-running fetch with a progress dialog, THAT phase must marshal `cmd.*` back to the main thread — not Phase 2's concern.)

### 9.3 Modal dialogs (file dialog, message box) — OK inside the modeless plugin
`QFileDialog.getSaveFileName`/`getOpenFileName` are modal. `QMessageBox.exec_()` is modal. **Both are fine inside the modeless plugin dialog** — only making the **main plugin dialog** itself modal (`PluginDialog.exec_()`) is forbidden (Phase 1 §4.2). Confirmed: `outline.py:178-182` uses `QMessageBox().exec_()`; `vina.py:688` uses `fileDialog.exec_()`. The modeless plugin stays modeless; a transient modal child dialog is standard Qt.

### 9.4 `cmd.fetch` requires network — graceful error handling
`cmd.fetch` needs internet. In an offline test (or a typo'd code) it raises `pymol.CmdException`. **Pattern:** wrap in try/except and show a `QMessageBox.warning`:
```python
def _on_fetch(self):
    code = self.pdb_edit.text().strip()
    if not code:
        return
    obj = fetch_pdb(code)   # §3.4 — returns None on failure
    if obj is None:
        QtWidgets.QMessageBox.warning(
            self, "Fetch failed",
            f"Could not fetch PDB code '{code}'.\n"
            "Check the code and your network connection.\n"
            "(Bundled demos don't need the network — try one from the 'Bundled demo' mode.)")
        return
    # success — refresh the loaded-objects combo so the new object appears
    self.obj_combo.showPopup()
```

### 9.5 Refreshing the loaded-objects list — triggers
The loaded-objects list changes as the user loads/fetches. Two triggers, BOTH recommended:
1. **Refresh-on-show** (the `PyMOLObjectCombo.showPopup` override, §2.4) — the list is fresh every time the dropdown opens. This is the primary mechanism.
2. **Explicit refresh button** next to the combo (§2.4, `outline.py:333-342` pattern) — gives a visible affordance; clicking it calls `self.obj_combo.showPopup()` (which re-runs the refresh).

Do NOT refresh on a timer (wasteful). Do NOT refresh on every keystroke (the combo is editable). The two triggers above are sufficient.

### 9.6 Pitfall 1 — Tkinter/Pmw (inherited from Phase 1, still applies)
Phase 2 still must not introduce `import tkinter`/`Pmw`/`app.root`/`grab_set`/`from PyQt5 import`/`dialog.exec_()` (on the main dialog). The Phase-1 grep checks (§11.1) carry forward unchanged. Phase 2 adds new files (`data/demos/SOURCES.md` is markdown — not checked) but no new Python beyond the two existing modules, so the same greps cover it.

---

## 10. Verification Strategy for Phase 2

Phase 2 verification is **split across two environments**, exactly like Phase 1: WSL for syntax + grep gates, Windows PyMOL for the four functional success criteria. The planner must encode both tiers.

### 10.1 WSL tier — syntax + grep (runnable in WSL python3.6, no PyMOL)

```bash
# Syntax-check every modified module (py_compile checks syntax, not imports)
python3.6 -m py_compile biochemeleon/__init__.py
python3.6 -m py_compile biochemeleon/gui_setup.py
python3.6 -m py_compile biochemeleon/gui_game.py   # unchanged in Phase 2 but re-check
python3.6 -m py_compile biochemeleon/demos.py
python3.6 -m py_compile biochemeleon/wizard.py     # unchanged
python3.6 -m py_compile biochemeleon/game.py       # unchanged

# Pitfall-1 grep checks (must return ZERO matches):
rg -n "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/
# `dialog.exec_()` on the MAIN dialog is forbidden; QFileDialog.exec_()/QMessageBox.exec_() ARE allowed.
# So grep for exec_ and manually confirm any hits are on child file/message dialogs, not PluginDialog:
rg -n "\.exec_\(\)" biochemeleon/
# pymol.Qt must be used (must return matches):
rg -n "from pymol\.Qt import" biochemeleon/

# Phase-2-specific greps:
# to_windows_path must exist and handle /mnt/ guard:
rg -n "def to_windows_path" biochemeleon/demos.py
rg -n "parts\[1\] == 'mnt'" biochemeleon/demos.py        # the guard condition
# DemoLoader / load_demo must exist:
rg -n "def load_demo|DEMO_MANIFEST" biochemeleon/demos.py
# All 6 demo IDs referenced:
rg -n "1znf|1xdn|5e54|1k8p|2qbz|4wb3" biochemeleon/demos.py
# Setup form has the 4 button slots:
rg -n "reset_btn|random_btn|save_btn|load_btn" biochemeleon/gui_setup.py
# Rep-detection uses the `rep ` selector:
rg -n "rep \{" biochemeleon/demos.py        # f"{obj} and rep {rep}" — literal "rep {"

# Bundled PDBs present (6 files):
ls biochemeleon/data/demos/*.pdb | wc -l   # must be 6
# SOURCES.md present:
test -f biochemeleon/data/demos/SOURCES.md
```

**WSL-verifiable truths (artifacts):** the `to_windows_path` guard logic, the manifest listing all 6 IDs, the existence of the 6 `.pdb` files + `SOURCES.md`, the 4 button slots, the `rep <name>` selector usage, the no-Tk/no-Pmw/no-raw-PyQt5 gate. These can be checked without running PyMOL.

### 10.2 Windows tier — functional smoke test (the 4 success criteria)

Run via `cmd.exe /c "setenv.bat && pymol"` (per Phase 1 §5.1), then exercise the Setup tab. Concrete steps mapped to the 4 success criteria:

| Success criterion | Smoke-test step | PASS |
|-------------------|----------------|------|
| 1. Object selector: loaded object / PDB fetch / bundled demo | Open the Setup tab. Switch the "Source" combobox to each of the 3 modes; confirm the widget below swaps (loaded-objects combo / PDB code + Fetch button / demo combo). In "Loaded object" mode, load `1znf.pdb` via PyMOL's File→Open first, then confirm the object appears in the combo. In "PDB fetch" mode, type `1ubq` and click Fetch — confirm the structure loads (needs network). In "Bundled demo" mode, the combo lists all 6 demos grouped by category. | All 3 modes render their widget; fetch loads a structure; demo combo lists 6 entries. |
| 2. Hider count (capped), lock scene, per-rep counts, difficulty | Pick a loaded object. Confirm the hider-count spinbox max is capped (e.g. for a 212-atom object, max ~4). Set hider count to 5. Tick "Lock current scene" — confirm the per-rep checkboxes auto-populate from the object's current reps (e.g. `show cartoon` first → cartoon checkbox auto-ticks and locks). Untick "Lock current scene" — confirm all 5 reps become available (checkboxes unlock). Tick 2 reps and set per-rep counts (e.g. spheres=3, cartoon=2). Toggle the Easy/Hard difficulty checkbox. | Cap visible; lock-scene auto-detects reps; per-rep counts settable; difficulty toggles. |
| 3. Reset / Randomize / Save / Load | Click Reset — confirm all widgets return to defaults. Click Randomize — confirm params change to random valid values. Click Save Setup — pick a path, confirm a `.bcm.setup.json` file is written (open it in a text editor; confirm it's valid JSON with the §7.1 fields). Click Load Setup — pick the file; confirm the form repopulates. | All 4 buttons work; saved JSON is valid; loaded state repopulates the form. |
| 4. Bundled demos load and render with sources cited | In "Bundled demo" mode, select each of the 6 demos in turn; for each, confirm the structure loads into the viewer (the 3D view shows the molecule) and renders (zoom to it). Open `biochemeleon/data/demos/SOURCES.md` and confirm all 6 entries are cited (PDB ID + DOI + authors + journal). | All 6 demos load + render; SOURCES.md lists all 6 with citations. |

**Windows-only truths (NOT WSL-verifiable):** the actual rendering of demos in the viewer, the fetch network call, the modal file-dialog UX, the `rep <name>` selector actually returning >0 for a shown rep (this confirms the §3.6 approach on the user's build), the hider-count cap visible in the spinbox. These are the `checkpoint:human-verify` task.

### 10.3 What "done" looks like for Phase 2

- All `py_compile` + grep checks pass in WSL (§10.1).
- The user confirms all 4 Windows-tier smoke tests PASS (§10.2).
- The repo has `biochemeleon/data/demos/{1znf,1xdn,5e54,1k8p,2qbz,4wb3}.pdb` + `biochemeleon/data/demos/SOURCES.md`.
- `biochemeleon/gui_setup.py` and `biochemeleon/demos.py` are populated; `__init__.py`, `gui_game.py`, `wizard.py`, `game.py` are unchanged from Phase 1.

---

## 11. Goal-Backward Must-Haves (head start for the planner)

### 11.1 Observable truths (from the user's perspective) — propose 5-7

1. **The Setup tab opens with a populated config form** (not the Phase-1 placeholder) — 3-mode target selector, hider-count spinbox, lock-scene checkbox, per-rep rows, difficulty checkbox, 4 action buttons.
2. **The user can pick a target three ways:** a loaded object (from a dropdown of currently-loaded molecular objects), a PDB code (typed + Fetched — needs network), or a bundled demo (from a category-grouped list).
3. **The hider-count spinbox is capped** to a sane max relative to the chosen target's atom count (e.g. 212-atom 1znf → cap ~4; the spinbox physically can't exceed the cap).
4. **"Lock current scene" detects the object's current representations** (via the `rep <name>` selector) and auto-ticks + locks the matching per-rep rows; when unchecked, all 5 reps are available and unlocked.
5. **Reset / Randomize / Save Setup / Load Setup all work** — Reset restores defaults; Randomize sets valid random params; Save writes a `.bcm.setup.json`; Load reads one and repopulates the form.
6. **All 6 bundled demos load and render** in the viewer (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3), with sources cited in `biochemeleon/data/demos/SOURCES.md`.
7. **The plugin dialog stays modeless** (the 3D viewer is interactive while the Setup tab is open — inherited from Phase 1, must not regress).

### 11.2 Required artifacts (specific files)

- `biochemeleon/gui_setup.py` — populated with the full Setup form (§5).
- `biochemeleon/demos.py` — populated with `to_windows_path()` (§6), `DEMO_MANIFEST`, `load_demo`, `list_loaded_molecule_objects`, `fetch_pdb`, `get_active_reps`, `GAME_REPS`, `hider_count_cap` (§3, §4).
- `biochemeleon/data/demos/1znf.pdb`, `1xdn.pdb`, `5e54.pdb`, `1k8p.pdb`, `2qbz.pdb`, `4wb3.pdb` — the 6 bundled PDBs (downloaded from `https://files.rcsb.org/download/{ID}.pdb`, committed).
- `biochemeleon/data/demos/SOURCES.md` — the citation file (§4.5).
- `biochemeleon/__init__.py`, `gui_game.py`, `wizard.py`, `game.py` — **unchanged** from Phase 1.

### 11.3 Key links (which artifact calls which API)

- **SetupTab object-selector (loaded mode)** → `list_loaded_molecule_objects()` → `cmd.get_names('public_objects', enabled_only=True)` filtered by `cmd.get_type(name)=='object:molecule'` (§3.1, §3.2).
- **SetupTab object-selector (fetch mode)** → `fetch_pdb(code)` → `cmd.fetch(code, name=..., async_=0)` (§3.4), wrapped in try/except + `QMessageBox` (§9.4).
- **SetupTab object-selector (demo mode)** → `load_demo(demo_id)` → `cmd.load(to_windows_path(os.path.join(dirname(__file__), 'data', 'demos', f'{id}.pdb')), object=id)` (§4.4, §6).
- **SetupTab hider-count cap** → `hider_count_cap(cmd.count_atoms(obj))` → `self.hider_spin.setMaximum(cap)` (§3.7).
- **SetupTab "lock scene"** → `get_active_reps(obj)` → `cmd.count_atoms(f"{obj} and rep {rep}")` per rep in `GAME_REPS` (§3.6).
- **SetupTab Save button** → `QFileDialog.getSaveFileName` + `json.dump(self.collect_state())` to a `.bcm.setup.json` (§7.2, §7.3).
- **SetupTab Load button** → `QFileDialog.getOpenFileName` + `json.load` + `self.apply_state(state)` (§7.2, §7.3).
- **SetupTab Reset button** → `self.apply_state(DEFAULTS)` (§7.4).
- **SetupTab Randomize button** → `_randomize()` builds a random state dict + `apply_state` (§7.5).

---

## 12. Open Questions / Risks for the Planner

### 12.1 The `rep <name>` selector on the user's specific build (MEDIUM → smoke-test closes it)
**What we know (HIGH):** the official PyMOL wiki "Selection Algebra" page lists `rep cartoon` / `rep lines` as selectors; `cmd.count_atoms` is verified in the v2.5.0 source. The approach `cmd.count_atoms(f"{obj} and rep {rep_name}") > 0` is the standard idiom.
**What's unverified:** I could not run PyMOL from WSL to confirm the selector returns >0 on the user's specific `setenv.bat`-launched conda build. It's expected to work trivially (it's core PyMOL selection language, not a version-gated feature), but the Windows smoke test (§10.2 criterion 2, "Lock current scene auto-detects reps") is the formal confirmation.
**Mitigation:** the `_sync_reps_from_scene` method wraps the per-rep `count_atoms` in try/except (§3.6) so a single failed rep doesn't break the form; and the SETUP-04 "lock scene" feature degrades gracefully to "no reps detected → user can still toggle manually with lock off".

### 12.2 `cmd.fetch` network availability at runtime (MEDIUM)
**What we know:** `cmd.fetch` requires internet; the bundled-demo path does NOT. The fetch mode is one of three target modes and is optional (the user can always use a loaded object or a bundled demo).
**Risk:** in an offline test environment the fetch smoke-test step (§10.2 criterion 1) will fail. That's expected and acceptable — the try/except + `QMessageBox` (§9.4) handles it gracefully.
**Mitigation:** the planner should mark the fetch smoke-test step as "requires network — skip with a note if offline" so the user doesn't block on it. The 4 success criteria do NOT require fetch to work (criterion 1 says "the user can choose... a PDB fetch" — the mode must EXIST and render its widget; the actual network fetch is a bonus check).

### 12.3 Plugin Manager dir-install on Windows (MEDIUM — inherited from Phase 1, unchanged)
Phase 2 doesn't change the install mechanism (Phase 1's Plugin-Manager dir-install + the `biochemeleon/` package dir). The Phase-1 open question 9.1 (does the Manager cleanly accept a directory?) carries forward unchanged. Phase 2's new `data/demos/` subdirectory is just more files inside the package dir — the Manager copies the whole package, so the demos come along automatically. No new install risk.

### 12.4 `pymol.plugins.pref_set` vs JSON file for Save Setup (LOW — decided)
ARCHITECTURE.md / PITFALLS.md mention `pymol.plugins.pref_set/get` for settings (basic types only). I considered using it for Save Setup instead of a JSON file. **Decision: use a JSON file (BTN-03/04 are explicit user Save/Load to a file the user names), NOT `pref_set`.** `pref_set` is for persistent plugin preferences (auto-saved across sessions, not user-named files); BTN-03/04 are clearly "save/load to a user-chosen file" — `QFileDialog` + `json` is the right tool. `pref_set` is irrelevant to Phase 2. (If a future phase wants to remember the last-used setup across sessions, THAT could use `pref_set` — not Phase 2.)

### 12.5 `4wb3` "difficulty" labeling (LOW)
DEMO-01 lists `4wb3` under "Mixed" with no Easy/Hard tier (the other 5 have Easy/Hard). The manifest (§4.4) assigns `difficulty: 'easy'` to `4wb3` as a placeholder. The planner can keep 'easy' or use a distinct 'mixed' label — Phase 2 only surfaces the label in the demo combo display string; Phase 9 (DIFF-05) refines the tier system. Low impact either way; flag for the user if they care.

### 12.6 1znf is a 37-model NMR ensemble (LOW — file size)
The 1znf.pdb file is ~1.2 MB (37 NMR models) while the other 5 demos are <500 KB single-model structures. This is fine for bundling (a few MB total) but means `cmd.load('1znf.pdb')` creates a 37-state object by default. Phase 2 only loads and renders it (Success Criterion 4); the multi-state nature doesn't affect the Setup form. If a later phase's hider generation needs a single state, it can `cmd.load(..., state=1)` or `split_states` — not Phase 2's concern. Noted for awareness only.

---

## Sources

### Primary (HIGH confidence — PyMOL 2.5.0 source, directly read)
- **`pymol-open-source` v2.5.0 `modules/pymol/querying.py`** — fetched raw from `raw.githubusercontent.com/schrodinger/pymol-open-source/v2.5.0/modules/pymol/querying.py`. Verified exact signatures: `get_names(type='public_objects', enabled_only=0, selection="", ...)` (mode int mapping for all 10 type values), `get_type(name, quiet=1, ...)` (return values `object:molecule`/`object:map`/.../`selection`), `get_object_list(selection="(all)", quiet=1, ...)`, `count_atoms(selection="(all)", quiet=1, state=ALL_STATES, domain='', ...)`. Confirmed NO `get_representations` function exists in this module.

### Primary (HIGH confidence — official PyMOL wiki, fetched)
- **PyMOL wiki `/Fetch`** — `fetch codes [, name [, ... [, type [, async]]]]`; `async_` is the Python kwarg; "Changed in PyMOL 2.3.0: Default async=0"; "{default: 0 since PyMOL 2.3}" for the Python API. Confirms `async_=0` is the safe explicit form.
- **PyMOL wiki `/Load`** — `cmd.load(filename [,object [,state [,format [,finish [,discrete [,multiplex [,zoom]]]]]]])`; extension determines format (`.pdb`→PDB); filename may be a path or URL.
- **PyMOL wiki `/Selection_Algebra`** (redirect target of `/Single-word_Selectors`) — confirms the `rep <name>` selector under "Style" (`rep cartoon` — "Atoms with cartoon representation"; example `select rep lines`). HIGH confidence for the rep-detection approach in §3.6.
- **PyMOL wiki `/Property_Selectors`** — confirms `segi` (s.), `name` (n.), `resn` (r.), `chain` (c.) short-form selectors (relevant context for `segi='GAME'` in Phase 3, not Phase 2).

### Primary (HIGH confidence — reference plugins, directly read)
- **`Pymol-script-repo/plugins/vina.py`** — `:180-209` (Qt widget class imports via `Qt.QtWidgets`), `:682-688` (`QFileDialog()` instance + `exec_()` for save), `:706-783` (`QFormLayout` + `QSpinBox.setRange/setValue` + `QCheckBox` + `QPushButton` + `@btn.clicked.connect` + `QFileDialog.getOpenFileName(...)[0]` + `layout.addRow("Label:", widget)`), `:1153-1169` (`PyMOLComboObjectBox(QComboBox)` overriding `showPopup()` to refresh from `cmd.get_names("all", enabled_only=True)`), `:1191-1209` (receptor selection combo + `@currentTextChanged.connect` validator calling `cmd.count_atoms(f"({text}) and polymer")`).
- **`Pymol-script-repo/plugins/outline.py`** — `:160-182` (`QFileDialog.getSaveFileName(None, "Save File", dir, "PNG Files (*.png)")[0]` + `QMessageBox.exec_()`), `:211-214` (QComboBox usage), `:280-308` (`QSpinBox.setRange/setValue` + `QHBoxLayout`), `:311-390` (`QDialog` + `QVBoxLayout` + QComboBox-with-refresh-button layout using `SP_BrowserReload` icon + `clicked.connect(self._refreshCombobox)` + `QCheckBox("Save to file")`), `:320-322` (`REP_LIST = ['surface','cartoon','mesh','dots','spheres','lines','nonbonded']` — canonical PyMOL rep-name strings).
- **`Pymol-script-repo/plugins/optimize.py`** — `:89,165` (`QGroupBox("...options")` + `QFormLayout`), `:98-204` (`QComboBox` + `QLineEdit` form rows).
- **`Pymol-script-repo/plugins/show_contacts.py`** — `:310,317` (`QComboBox` for object selection — Qt path).
- (grep across the repo confirmed `cmd.count_atoms` usage in `pytms.py`, `dssp_stride.py`, `vina.py`; `cmd.get_names`/`cmd.get_object_list` in `dssp_stride.py`, `pytms.py`, `vina.py`.)

### Primary (HIGH confidence — RCSB REST API, fetched 2026-08-03)
- `data.rcsb.org/rest/v1/core/entry/1ZNF` — citation metadata (DOI 10.2210/pdb1znf/pdb, Science 245:635 1989, PMID 2503871, NMR 37 models, 212 atoms).
- `data.rcsb.org/rest/v1/core/entry/1XDN` — (DOI 10.2210/pdb1xdn/pdb, J.Mol.Biol. 343:601 2004, DOI 10.1016/j.jmb.2004.08.041, PMID 15465048, X-ray 1.2Å, 2597 atoms).
- `data.rcsb.org/rest/v1/core/entry/5E54` — (DOI 10.2210/pdb5e54/pdb, Nature 541:242 2017, DOI 10.1038/nature20599, PMID 27841871, XFEL 2.3Å, 2844 atoms, adenine riboswitch).
- `data.rcsb.org/rest/v1/core/entry/1K8P` — (DOI 10.2210/pdb1k8p/pdb, Nature 417:876 2002, DOI 10.1038/nature755, PMID 12050675, X-ray 2.4Å, 555 atoms, G-quadruplex).
- `data.rcsb.org/rest/v1/core/entry/2QBZ` — (DOI 10.2210/pdb2qbz/pdb, Cell 130:878 2007, DOI 10.1016/j.cell.2007.06.051, PMID 17803910, X-ray 2.6Å, 3408 atoms, M-Box riboswitch).
- `data.rcsb.org/rest/v1/core/entry/4WB3` — (DOI 10.2210/pdb4wb3/pdb, Nat.Commun. 6:6481 2015, DOI 10.1038/ncomms7481, PMID 25901944, X-ray 2.0Å, 3779 atoms, protein/NA hybrid).
- `https://files.rcsb.org/download/1znf.pdb` — fetched end-to-end via webfetch; confirmed the canonical download URL resolves to a valid PDB file (HEADER/TITLE/ATOM/JRNL records present).

### Primary (HIGH confidence — project research docs, already verified)
- `.planning/research/STACK.md` — PyQt5 via `pymol.Qt`; `__init_plugin__`; `addmenuitemqt`; `pymol.Qt` auto-selects PyQt5/PySide2/PyQt4/PySide; conda-forge `pymol-open-source` run-dep `pyqt`; `cmd.fetch(..., async_=0)` recommendation; "What NOT to Use" (no `from PyQt5 import`, no Tkinter/Pmw).
- `.planning/research/PITFALLS.md` — Pitfall 1 (Tkinter must-not list, modal `exec_()` forbidden on main dialog); Pitfall 11 (WSL→Windows path, `to_windows_path()` helper, `__file__`-relative path resolution, install path crosses boundary); Pitfall 6 (all `cmd.*` on main thread — confirms direct Qt-slot `cmd.*` calls are safe); RCSB CC0 license + citation policy (PDB ID + DOI + publication + graphics program).
- `.planning/research/ARCHITECTURE.md` — component responsibilities (DemoLoader manifest + fetch + cache; SetupTab params form + buttons); `GAME_REPS` set (lines/sticks/spheres/cartoon/ribbon; surface out of scope); `.pse` + companion JSON pattern (informs the `.bcm.setup.json` extension choice — distinct from Phase 8's `.bcm` game-state sidecar).
- `.planning/research/FEATURES.md` — feature scope (DEMO-01 demo set; SETUP-01..06; BTN-01..04).
- `.planning/phases/01-plugin-bootstrap-dialog-scaffold/01-RESEARCH.md` — Phase 1 patterns inherited verbatim: `from pymol.Qt import` (never `from PyQt5`), `__init_plugin__(app=None)` + `addmenuitemqt`, module-level `dialog = None` singleton, modeless `dialog.show()` (never `.exec_()` on the main dialog), lazy import of tab classes inside `PluginDialog.__init__`, the `PluginDialog`-in-`__init__.py` Option-A decision (Phase 2 §8 confirms no extraction), the `to_windows_path()` deferral note (Phase 2 §6 delivers it), the WSL/Windows verification split (Phase 2 §10 follows the same pattern).

### Primary (HIGH confidence — current source, directly read)
- `biochemeleon/__init__.py` (66 lines) — Phase-1 `PluginDialog(QDialog)` + `QTabWidget` + 2 tabs; lazy `from .gui_setup import SetupTab` / `from .gui_game import GameTab`. Phase 2 does NOT change this file.
- `biochemeleon/gui_setup.py` (13 lines) — Phase-1 placeholder `SetupTab(QWidget)`. Phase 2 replaces this with the full form (§5).
- `biochemeleon/demos.py` (8 lines) — Phase-1 stub with the `TODO (Phase 2): implement to_windows_path()` note. Phase 2 replaces this with the DemoLoader + helper (§3, §4, §6).

### Secondary (MEDIUM confidence — inherited, not re-verified)
- Plugin Manager directory-install quirks on Windows — from Phase-1 RESEARCH §9.1 (MEDIUM). Phase 2 adds no new install risk.

---

## Metadata

**Confidence breakdown:**
- Qt form widget patterns + signal syntax: **HIGH** — directly read from `vina.py`, `outline.py`, `optimize.py` (modern reference plugins using `pymol.Qt`).
- PyMOL cmd API (`get_names`, `get_type`, `get_object_list`, `count_atoms`, `fetch`, `load`): **HIGH** — signatures read from `pymol-open-source` v2.5.0 `querying.py` + official wiki `/Fetch` and `/Load`.
- Rep detection (`rep <name>` selector): **HIGH** — official wiki `/Selection_Algebra` lists it; `cmd.count_atoms` signature verified in source. (Empirical confirmation on the user's build is the Windows smoke test, not a research gap.)
- Rep-name strings (`lines`/`sticks`/`spheres`/`cartoon`/`ribbon`): **HIGH** — `outline.py:320-322` `REP_LIST` + grep of `cmd.show`/`cmd.hide` across the reference repo.
- Demo PDB URLs + citations: **HIGH** — RCSB download URL fetched end-to-end (1znf); all 6 citations fetched from the RCSB REST API.
- `to_windows_path()` approach: **HIGH** — PITFALLS.md Pitfall 11 + the `__file__`-relative resolution pattern from ARCHITECTURE.md/STACK.md.
- PluginDialog extraction decision (NO): **HIGH** — direct read of `__init__.py` shows `PluginDialog` is 29 lines and Phase 2 adds no logic to it.
- `cmd.fetch` network availability at runtime: **MEDIUM** — depends on the user's network; handled by try/except + QMessageBox (§9.4).

**Research date:** 2026-08-03
**Valid until:** 2026-09-03 (30 days — stable domain; PyMOL 2.5.0, the reference plugins, and the RCSB URLs are not fast-moving. The 6 demo PDB IDs are archived by RCSB and will not disappear.)
