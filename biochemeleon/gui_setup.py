"""Setup tab — full game configuration form (Phase 2).

Layout (research section 5.1):
  SetupTab (QVBoxLayout)
  +-- QGroupBox "Target"          (SETUP-02: 3-mode selector + QStackedWidget)
  +-- QGroupBox "Hiders"          (SETUP-03/04/05: count + lock-scene + per-rep rows)
  +-- QGroupBox "Difficulty"      (SETUP-06: easy/hard toggle)
  +-- QGroupBox "Setup actions"   (BTN-01..04: Reset/Randomize/Save/Load)

All Qt imports come from `pymol.Qt` (NEVER raw PyQt5); the main plugin
dialog stays modeless (QFileDialog/QMessageBox are modal children, which
is fine — research section 9.3).
"""
import json

from pymol.Qt import QtCore, QtGui, QtWidgets
from pymol import cmd

from .setup_state import (
    DEFAULTS, SETUP_FORMAT, GAME_REPS, DEMO_MANIFEST,
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
        # page 1: PDB fetch (line edit + fetch button)
        p1 = QtWidgets.QWidget(); p1l = QtWidgets.QHBoxLayout(p1)
        self.pdb_edit = QtWidgets.QLineEdit()
        self.pdb_edit.setPlaceholderText("e.g. 1znf")
        self.fetch_btn = QtWidgets.QPushButton("Fetch")
        p1l.addWidget(self.pdb_edit); p1l.addWidget(self.fetch_btn)
        # page 2: bundled demo (combo populated from DEMO_MANIFEST)
        p2 = QtWidgets.QWidget(); p2l = QtWidgets.QHBoxLayout(p2)
        self.demo_combo = QtWidgets.QComboBox()
        for did, meta in DEMO_MANIFEST.items():
            self.demo_combo.addItem(
                "{} — {} ({})".format(meta['category'], did, meta['difficulty']),
                did)
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
        self.lock_scene_cb.toggled.connect(self._on_lock_scene_toggled)
        self.reset_btn.clicked.connect(lambda: self.apply_state(DEFAULTS))
        self.random_btn.clicked.connect(self._randomize)
        self.save_btn.clicked.connect(self._save_setup)
        self.load_btn.clicked.connect(self._load_setup)

    # ---- Slots ----
    def _on_mode_changed(self, idx):
        self.target_stack.setCurrentIndex(idx)

    def _on_target_changed(self, *_):
        """Recompute the hider-count cap from the current target object.
        If 'lock scene' is on and an object is selected, sync reps from it.
        Suppressed during apply_state (the _loading flag) so saved state is
        applied verbatim without cascading recompute.
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

    def current_target_object(self):
        """Return the PyMOL object name the form currently points at, or
        None if the target isn't a loaded object yet (fetch/demo modes are
        not loaded until the user clicks Fetch / Start). Used by
        _on_target_changed to recompute the hider-count cap.
        """
        mode = self.mode_combo.currentData()
        if mode == "loaded":
            name = self.obj_combo.currentText().strip()
            if name and name in list_loaded_molecule_objects():
                return name
            return None
        return None  # fetch/demo targets aren't loaded objects yet

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
        finally:
            self._loading = False

    # ---- Action buttons ----
    def _randomize(self):
        """Randomize setup params via the pure randomize_state, then apply.
        Uses the current target's atom count to cap the hider count.
        """
        obj = self.current_target_object()
        atom_count = None
        if obj:
            try:
                atom_count = cmd.count_atoms(obj)
            except Exception:
                atom_count = None
        result = randomize_state(seed=None, atom_count=atom_count)
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
