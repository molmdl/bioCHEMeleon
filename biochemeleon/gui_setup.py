"""Setup tab — full game configuration form (Phase 2).

Layout (research section 5.1):
  SetupTab (QVBoxLayout)
  +-- QGroupBox "Target"          (SETUP-02: 3-mode selector + QStackedWidget)
  +-- QGroupBox "Hiders"          (SETUP-03/04/05: count + lock-scene + per-rep rows)
  +-- QGroupBox "Difficulty"      (SETUP-06: easy/hard toggle)
  +-- QGroupBox "Setup actions"   (BTN-01..04 + BTN-07: Reset/Randomize/Save/Load/Start)

All Qt imports come from `pymol.Qt` (NEVER raw PyQt5); the main plugin
dialog stays modeless (QFileDialog/QMessageBox are modal children, which
is fine — research section 9.3).
"""
import json
import random

from pymol.Qt import QtCore, QtGui, QtWidgets
from pymol import cmd

from .setup_state import (
    DEFAULTS, SETUP_FORMAT, GAME_REPS, DEMO_MANIFEST,
    TIER_LABELS, PDB_POOL, _validate_pdb_code,
    hider_count_cap, randomize_state, validate_state,
)
from .demos import (
    load_demo, list_loaded_molecule_objects, fetch_pdb, get_active_reps,
)


class PyMOLObjectCombo(QtWidgets.QComboBox):
    """QComboBox that refreshes its list of loaded molecular objects every
    time the popup is shown. Editable so the user can also type a name.

    Source: vina.py:1153-1169 PyMOLComboObjectBox pattern.
    """
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
    """Full Setup configuration form.

    Captures the user's pre-game intent into a JSON-serializable state dict
    (collect_state/apply_state round-trip). Does NOT start a game or mutate
    any object — BTN-05/06/07 and hider generation are Phase 4+.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._loading = False       # guards apply_state against cascading recompute
        self.rep_rows = {}           # rep_name -> (QCheckBox, QSpinBox, QLabel)
        self._build_ui()
        self.apply_state(DEFAULTS)  # initialize to defaults on construction

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
        # page 0: loaded object (combo + refresh button)
        p0 = QtWidgets.QWidget(); p0l = QtWidgets.QHBoxLayout(p0)
        self.obj_combo = PyMOLObjectCombo()
        self.obj_refresh_btn = QtWidgets.QPushButton()
        icon = self.style().standardIcon(QtWidgets.QStyle.SP_BrowserReload)
        self.obj_refresh_btn.setIcon(icon)
        self.obj_refresh_btn.setFixedSize(25, 25)
        self.obj_refresh_btn.setToolTip("Refresh loaded objects")
        p0l.addWidget(self.obj_combo); p0l.addWidget(self.obj_refresh_btn)
        # page 1: PDB fetch (line edit + fetch button + pool editor)
        p1 = QtWidgets.QWidget(); p1l = QtWidgets.QVBoxLayout(p1)
        p1l.setContentsMargins(0, 0, 0, 0)
        fetch_row = QtWidgets.QHBoxLayout()
        self.pdb_edit = QtWidgets.QLineEdit()
        self.pdb_edit.setPlaceholderText("e.g. 1znf")
        self.fetch_btn = QtWidgets.QPushButton("Fetch")
        fetch_row.addWidget(self.pdb_edit); fetch_row.addWidget(self.fetch_btn)
        p1l.addLayout(fetch_row)
        # Issue 1 fix: QListWidget pool editor (replaces the old free-text editor).
        # Empty list -> [] (signals randomize_state to use the bundled PDB_POOL
        # default; never produces an empty pdb_code box). The label makes the
        # "use bundled pool" affordance explicit.
        pool_box = QtWidgets.QGroupBox("Pool of PDB IDs (Randomize picks fetch codes from here)")
        pool_bl = QtWidgets.QVBoxLayout(pool_box)
        self.pool_list = QtWidgets.QListWidget()
        self.pool_list.setSelectionMode(QtWidgets.QAbstractItemView.ExtendedSelection)
        pool_bl.addWidget(self.pool_list)
        # Button row: Add / Edit / Remove / Use bundled pool / Choose random
        # (no reorder — out of scope). 'Choose random' is visually associated
        # with the pool (inside the pool QGroupBox) — it picks a random pool
        # entry into the fetch field (plan 02-07), not a main Setup action.
        pool_btn_row = QtWidgets.QHBoxLayout()
        self.pool_add_btn = QtWidgets.QPushButton("+ Add")
        self.pool_edit_btn = QtWidgets.QPushButton("\u270e Edit")
        self.pool_remove_btn = QtWidgets.QPushButton("\u2212 Remove")
        self.pool_default_btn = QtWidgets.QPushButton("Use bundled pool")
        self.pool_choose_btn = QtWidgets.QPushButton("Choose random")
        for b in (self.pool_add_btn, self.pool_edit_btn,
                  self.pool_remove_btn, self.pool_default_btn,
                  self.pool_choose_btn):
            pool_btn_row.addWidget(b)
        pool_bl.addLayout(pool_btn_row)
        p1l.addWidget(pool_box)
        # page 2: bundled demo (combo populated from DEMO_MANIFEST)
        p2 = QtWidgets.QWidget(); p2l = QtWidgets.QHBoxLayout(p2)
        self.demo_combo = QtWidgets.QComboBox()
        # Phase 9 DIFF-05/SC4: surface the 4-tier difficulty label via
        # TIER_LABELS (Easy/Hard/Challenge/Very challenging). The manifest
        # stores identifier-safe keys (easy/hard/challenge/very_challenging
        # -- no spaces, grep-able); TIER_LABELS maps each to the exact display
        # string the success criterion specifies. The .title() fallback
        # handles any unmapped value defensively. The 09-01 manifest is
        # tier-ordered (easy -> hard -> challenge -> very_challenging) so the
        # combo shows a natural difficulty progression. 9 items < the 15-item
        # QTreeWidget threshold (Phase 2 research) -- keep the flat combo.
        for did, meta in DEMO_MANIFEST.items():
            tier = TIER_LABELS.get(meta['difficulty'], meta['difficulty'].title())
            self.demo_combo.addItem(
                "{category} — {id} ({tier})".format(
                    category=meta['category'], id=did, tier=tier), did)
        p2l.addWidget(self.demo_combo)
        self.target_stack.addWidget(p0)
        self.target_stack.addWidget(p1)
        self.target_stack.addWidget(p2)
        tgt_form.addRow(self.target_stack)
        # Gap 3: Lock source checkbox — when checked, Randomize preserves the
        # current target_mode + identifier and only randomizes hider composition.
        self.lock_source_cb = QtWidgets.QCheckBox(
            "Lock source (don't change target on Randomize)")
        self.lock_source_cb.setChecked(DEFAULTS["lock_source"])
        tgt_form.addRow(self.lock_source_cb)
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
        # per-rep rows: one QHBoxLayout per rep (checkbox + spinbox + label)
        self.rep_group = QtWidgets.QGroupBox(
            "Per-rep hider counts (unchecked = random)")
        rbox = QtWidgets.QVBoxLayout(self.rep_group)
        for rep in GAME_REPS:
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
            "Easy: show remaining hiders per representation "
            "(uncheck for Hard: total only)")
        dform.addRow(self.diff_easy_cb)
        outer.addWidget(diff)

        # --- Buttons group (BTN-01..04 + BTN-07 Start) ---
        btns = QtWidgets.QGroupBox("Setup actions")
        brow = QtWidgets.QHBoxLayout(btns)
        self.reset_btn = QtWidgets.QPushButton("Reset")
        self.random_btn = QtWidgets.QPushButton("Randomize")
        self.save_btn = QtWidgets.QPushButton("Save Setup…")
        self.load_btn = QtWidgets.QPushButton("Load Setup…")
        # Phase 8: Generate & export button (BTN-05) -- generate hiders and
        # save the initial game state to a .bcmz file for sharing or later
        # loading, WITHOUT starting play. Wired in __init__.py (same pattern
        # as start_btn). Stays on Setup; the educator's model keeps the
        # generated hiders (press Cleanup to restore the scene).
        self.export_btn = QtWidgets.QPushButton("Generate & export")
        self.export_btn.setToolTip(
            "Generate hiders and save the initial game state to a "
            "file for sharing or later loading. Does NOT start play — "
            "your model keeps the generated hiders (press Cleanup to "
            "restore your scene).")
        # Phase 7: Cleanup button (BTN-06) -- restore the model to its original
        # state (no hiders). Wired in __init__.py (same pattern as start_btn).
        self.cleanup_btn = QtWidgets.QPushButton("Cleanup model")
        self.cleanup_btn.setToolTip(
            "Remove all game-generated hiders and restore the model to its "
            "original state. (Does not start a new round — use Start for that.)")
        self.start_btn = QtWidgets.QPushButton("Start")
        self.start_btn.setStyleSheet("font-weight: bold;")  # primary action
        for b in (self.reset_btn, self.random_btn, self.save_btn,
                 self.load_btn, self.export_btn, self.cleanup_btn,
                 self.start_btn):
            brow.addWidget(b)
        outer.addWidget(btns)

        # --- Signal wiring ---
        self.mode_combo.currentIndexChanged.connect(self._on_mode_changed)
        self.obj_combo.currentTextChanged.connect(self._on_target_changed)
        self.obj_refresh_btn.clicked.connect(lambda: self.obj_combo.showPopup())
        self.fetch_btn.clicked.connect(self._on_fetch)
        self.demo_combo.currentIndexChanged.connect(self._on_target_changed)
        self.lock_scene_cb.toggled.connect(self._on_lock_scene_toggled)
        # Gap 2 UI: bound per-rep spinbox maxes so manual entry can't overflow
        # the total hider_count. Fires on hider_spin change + each per-rep
        # spinbox valueChanged.
        self.hider_spin.valueChanged.connect(self._recompute_per_rep_maxes)
        for rep, (cb, spin, label) in self.rep_rows.items():
            spin.valueChanged.connect(self._recompute_per_rep_maxes)
        self.reset_btn.clicked.connect(lambda: self.apply_state(DEFAULTS))
        self.random_btn.clicked.connect(self._randomize)
        self.save_btn.clicked.connect(self._save_setup)
        self.load_btn.clicked.connect(self._load_setup)
        # Issue 1: pool editor button wiring
        self.pool_add_btn.clicked.connect(self._add_pool_entry)
        self.pool_edit_btn.clicked.connect(self._edit_pool_entry)
        self.pool_remove_btn.clicked.connect(self._remove_pool_entry)
        self.pool_default_btn.clicked.connect(self._use_bundled_pool)
        # 02-07: Choose random — pick a random pool entry into the fetch field
        self.pool_choose_btn.clicked.connect(self._choose_random_from_pool)

    # ---- Slots ----
    def _on_mode_changed(self, idx):
        self.target_stack.setCurrentIndex(idx)

    def _on_target_changed(self, *_):
        """Recompute the hider-count cap from the current target object.
        If 'lock scene' is on and an object is selected, sync reps from it.
        Suppressed during apply_state (the _loading flag) so saved state is
        applied verbatim without cascading recompute. After the cap updates,
        recompute the per-rep spinbox maxes so they follow the new cap
        (Gap 2 UI).
        """
        if self._loading:
            return
        obj = self.current_target_object()
        if not obj:
            return
        try:
            cap = hider_count_cap(cmd.count_atoms(obj))
        except Exception:
            cap = 50
        self.hider_spin.setMaximum(max(1, cap))
        if self.hider_spin.value() > cap:
            self.hider_spin.setValue(cap)
        if self.lock_scene_cb.isChecked():
            self._sync_reps_from_scene(obj)
        self._recompute_per_rep_maxes()

    def _on_fetch(self):
        """Fetch the typed PDB code; show a QMessageBox on failure."""
        code = self.pdb_edit.text().strip()
        if not code:
            return
        obj = fetch_pdb(code)
        if obj is None:
            QtWidgets.QMessageBox.warning(
                self, "Fetch failed",
                "Could not fetch PDB code '{}'.\n"
                "Check the code and your network connection.\n"
                "(Bundled demos don't need the network — "
                "try one from the 'Bundled demo' mode.)".format(code))
            return
        # success — refresh the loaded-objects combo so the new object appears
        self.obj_combo.showPopup()

    def _on_lock_scene_toggled(self, checked):
        """When checked: sync reps from the scene and lock the checkboxes.
        When unchecked: unlock all checkboxes and reset labels.
        """
        if self._loading:
            return
        if checked:
            obj = self.current_target_object()
            if obj:
                self._sync_reps_from_scene(obj)
            else:
                # no object yet — lock checkboxes in their current state
                for rep, (cb, spin, label) in self.rep_rows.items():
                    cb.setEnabled(False)
        else:
            # unlock all checkboxes; re-apply per-rep enabled/label
            for rep, (cb, spin, label) in self.rep_rows.items():
                cb.setEnabled(True)
                spin.setEnabled(cb.isChecked())
                label.setText("" if cb.isChecked() else "random")

    def _on_rep_toggled(self, on, spin, label):
        """Enable/disable the spinbox and flip the 'random' label."""
        spin.setEnabled(on)
        label.setText("" if on else "random")

    def _sync_reps_from_scene(self, obj):
        """Auto-detect the object's active reps and lock the per-rep rows
        to match (SETUP-04). Uses get_active_reps (the `rep <name>` selector).
        """
        active = get_active_reps(obj)
        for rep, (cb, spin, label) in self.rep_rows.items():
            checked = rep in active
            cb.setChecked(checked)
            cb.setEnabled(False)   # locked: the scene determines which reps
            spin.setEnabled(checked)
            label.setText("" if checked else "random")

    def _recompute_per_rep_maxes(self):
        """Bound each per-rep spinbox to (hider_count - sum(other per_rep))
        so manual entry can't overflow the total (Gap 2 UI fix). Suppressed
        during apply_state (the _loading flag) so saved per_rep values are
        applied verbatim before the bounds kick in.
        """
        if self._loading:
            return
        total = self.hider_spin.value()
        current_sum = 0
        for rep, (cb, spin, label) in self.rep_rows.items():
            if cb.isChecked():
                current_sum += spin.value()
        for rep, (cb, spin, label) in self.rep_rows.items():
            if cb.isChecked():
                others = current_sum - spin.value()
                spin.setMaximum(max(0, total - others))
            else:
                spin.setMaximum(max(0, total))

    def current_target_object(self):
        """Return the PyMOL object name the form currently points at, or
        None if the target isn't a loaded object yet. In 'loaded' mode,
        returns the non-empty combo text WITHOUT re-querying the loaded
        objects list — the try/except in _on_target_changed handles a bogus
        name so the cap still recomputes on selection (Gap 1 fix:
        previously a membership re-query against the loaded-objects list
        returned None whenever the combo text didn't exactly match
        cmd.get_names output, bailing _on_target_changed before the cap
        could recompute).
        """
        mode = self.mode_combo.currentData()
        if mode == "loaded":
            name = self.obj_combo.currentText().strip()
            return name or None
        return None  # fetch/demo targets aren't loaded objects yet

    def _add_pool_entry(self):
        """Issue 1/2: prompt for a PDB ID, validate via _validate_pdb_code,
        add to the list only if valid. Invalid -> QMessageBox.warning, no add."""
        text, ok = QtWidgets.QInputDialog.getText(
            self, "Add PDB ID", "Enter PDB ID (4 chars):")
        if not ok:
            return
        code = _validate_pdb_code(text)
        if code == "":
            QtWidgets.QMessageBox.warning(
                self, "Invalid PDB ID",
                "Invalid PDB ID '{}'. PDB IDs are exactly 4 lowercase "
                "alphanumeric characters (e.g. 1ubq).".format(text))
            return
        # avoid duplicates
        existing = self._pool_list()
        if code in existing:
            QtWidgets.QMessageBox.information(
                self, "Duplicate", "'{}' is already in the pool.".format(code))
            return
        self.pool_list.addItem(QtWidgets.QListWidgetItem(code))

    def _edit_pool_entry(self):
        """Issue 1: edit the selected entry in place. Validates the new value;
        invalid -> QMessageBox.warning, no change."""
        items = self.pool_list.selectedItems()
        if not items:
            return
        item = items[0]  # edit the first selected
        old = item.text()
        text, ok = QtWidgets.QInputDialog.getText(
            self, "Edit PDB ID", "Enter PDB ID (4 chars):",
            text=old)
        if not ok:
            return
        code = _validate_pdb_code(text)
        if code == "":
            QtWidgets.QMessageBox.warning(
                self, "Invalid PDB ID",
                "Invalid PDB ID '{}'. PDB IDs are exactly 4 lowercase "
                "alphanumeric characters (e.g. 1ubq).".format(text))
            return
        # dupe check: allow if it's the same item being re-saved to the same code
        existing = [self.pool_list.item(i).text()
                    for i in range(self.pool_list.count())
                    if self.pool_list.item(i) is not item]
        if code in existing:
            QtWidgets.QMessageBox.information(
                self, "Duplicate", "'{}' is already in the pool.".format(code))
            return
        item.setText(code)

    def _remove_pool_entry(self):
        """Issue 1: remove selected row(s). List can become empty — that
        signals 'use bundled pool' at randomize time (unchanged behavior)."""
        for item in self.pool_list.selectedItems():
            self.pool_list.takeItem(self.pool_list.row(item))

    def _use_bundled_pool(self):
        """Issue 1: one-click reset to the 33-entry bundled PDB_POOL."""
        self.pool_list.clear()
        for code in PDB_POOL:
            self.pool_list.addItem(QtWidgets.QListWidgetItem(code))

    def _choose_random_from_pool(self):
        """Pick a random entry from the pool and put it in the fetch field.

        Switches source mode to 'fetch' so the field is visible. Does NOT
        change any other setup field (focused, single-purpose action).
        Uses the user's pool list if non-empty, else the bundled PDB_POOL.
        """
        pool = self._pool_list()
        if not pool:
            # empty list signals 'use bundled pool' — fall back to PDB_POOL
            pool = list(PDB_POOL)
        if not pool:
            # defensive: both empty (shouldn't happen — PDB_POOL has 33 entries)
            return
        code = random.choice(pool)
        # switch to fetch mode (0=loaded, 1=fetch, 2=demo) so the field is visible
        self.mode_combo.setCurrentIndex(1)
        self.pdb_edit.setText(code)

    def _pool_list(self):
        """Return the PDB pool as a list from the QListWidget.

        Empty list -> [] (signals randomize_state to use DEFAULTS pool).
        """
        return [self.pool_list.item(i).text()
                for i in range(self.pool_list.count())]

    # ---- collect_state / apply_state (round-trip) ----
    def collect_state(self):
        """Snapshot the current Setup form into a JSON-serializable dict."""
        per_rep = {}
        for rep, (cb, spin, label) in self.rep_rows.items():
            if cb.isChecked():
                per_rep[rep] = spin.value()
        return {
            "format": SETUP_FORMAT,
            "target_mode": self.mode_combo.currentData() or "loaded",
            "selected_object": self.obj_combo.currentText().strip(),
            "pdb_code": self.pdb_edit.text().strip().lower(),
            "demo_id": self.demo_combo.currentData() or "1znf",
            "hider_count": self.hider_spin.value(),
            "lock_scene": self.lock_scene_cb.isChecked(),
            "per_rep": per_rep,
            "difficulty_easy": self.diff_easy_cb.isChecked(),
            "lock_source": self.lock_source_cb.isChecked(),   # Gap 3
            "pdb_pool": self._pool_list(),                    # Gap 4
        }

    def apply_state(self, state):
        """Repopulate every widget from a state dict (used by Reset, Load,
        and __init__). Tolerates missing keys (forward-compat with future
        fields). The _loading flag suppresses cascading recompute/sync so
        saved per_rep values are applied verbatim.
        """
        if not isinstance(state, dict):
            state = {}
        self._loading = True
        try:
            mode = state.get("target_mode", "loaded")
            idx = {"loaded": 0, "fetch": 1, "demo": 2}.get(mode, 0)
            self.mode_combo.setCurrentIndex(idx)
            self.obj_combo.setEditText(state.get("selected_object", ""))
            self.pdb_edit.setText(state.get("pdb_code", ""))
            demo_id = state.get("demo_id", "1znf")
            for i in range(self.demo_combo.count()):
                if self.demo_combo.itemData(i) == demo_id:
                    self.demo_combo.setCurrentIndex(i)
                    break
            hc = state.get("hider_count", DEFAULTS["hider_count"])
            try:
                hc = int(hc)
            except (TypeError, ValueError):
                hc = DEFAULTS["hider_count"]
            self.hider_spin.setValue(hc)
            self.lock_scene_cb.setChecked(bool(state.get("lock_scene", False)))
            per_rep = state.get("per_rep", {})
            if not isinstance(per_rep, dict):
                per_rep = {}
            for rep, (cb, spin, label) in self.rep_rows.items():
                if rep in per_rep:
                    try:
                        c = int(per_rep[rep])
                    except (TypeError, ValueError):
                        c = 0
                    cb.setChecked(True)
                    spin.setValue(max(0, c))
                    spin.setEnabled(True)
                    label.setText("")
                else:
                    cb.setChecked(False)
                    spin.setValue(0)
                    spin.setEnabled(False)
                    label.setText("random")
            self.diff_easy_cb.setChecked(bool(state.get("difficulty_easy", True)))
            # Gap 3: lock_source checkbox
            self.lock_source_cb.setChecked(bool(state.get("lock_source", False)))
            # Issue 1: populate QListWidget (replaces the old free-text editor)
            pool = state.get("pdb_pool", [])
            self.pool_list.clear()
            if isinstance(pool, list):
                for code in pool:
                    validated = _validate_pdb_code(code)
                    if validated:
                        self.pool_list.addItem(QtWidgets.QListWidgetItem(validated))
            # (empty list = use bundled pool at randomize time — unchanged behavior)
        finally:
            self._loading = False

    # ---- Action buttons ----
    def _randomize(self):
        """Randomize setup params via randomize_state. If 'Lock source' is
        checked, preserve the current target and only randomize hider
        composition (Gap 3). PDB pool comes from the pool_edit text area
        (Gap 4); empty pool -> [] which signals randomize_state to use the
        bundled PDB_POOL default (never produces an empty pdb_code box).
        """
        obj = self.current_target_object()
        atom_count = None
        if obj:
            try:
                atom_count = cmd.count_atoms(obj)
            except Exception:
                atom_count = None
        lock_src = self.lock_source_cb.isChecked()
        locked = self.collect_state() if lock_src else None
        pool = self._pool_list()  # [] -> DEFAULTS pool in randomize_state
        result = randomize_state(
            seed=None, atom_count=atom_count,
            lock_source=lock_src, locked_state=locked,
            pdb_pool=pool,
        )
        self.apply_state(result)

    def _save_setup(self):
        """Save Setup to a .bcm.setup.json file via QFileDialog + json.dump."""
        path, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, "Save bioCHEMeleon Setup", "",
            "bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)")
        if not path:
            return
        if not path.lower().endswith('.json'):
            path += '.bcm.setup.json'
        try:
            with open(path, 'w') as f:
                json.dump(self.collect_state(), f, indent=2)
        except OSError as e:
            QtWidgets.QMessageBox.warning(
                self, "Save failed",
                "Could not write setup file:\n{}".format(e))

    def _load_setup(self):
        """Load Setup from a .bcm.setup.json file via QFileDialog + json.load,
        then validate_state (clamps/fills defaults) + apply_state.
        """
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "Load bioCHEMeleon Setup", "",
            "bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)")
        if not path:
            return
        try:
            with open(path) as f:
                state = json.load(f)
        except (OSError, ValueError) as e:
            QtWidgets.QMessageBox.warning(
                self, "Load failed",
                "Could not read setup file:\n{}".format(e))
            return
        obj = self.current_target_object()
        atom_count = None
        if obj:
            try:
                atom_count = cmd.count_atoms(obj)
            except Exception:
                atom_count = None
        validated = validate_state(state, atom_count=atom_count)
        self.apply_state(validated)
