"""bioCHEMeleon — a hide-and-seek molecular game plugin for PyMOL 2.5.0."""

# Module-level singleton dialog reference (GC prevention — see outline.py:46).
# MUST be module scope, not inside __init_plugin__, or the dialog flashes and vanishes.
dialog = None


def __init_plugin__(app=None):
    """PyMOL plugin entry point. Registers the Plugins-menu item.

    Called by the PyMOL plugin loader once at startup (or on manual load via
    the Plugin Manager). The local import of addmenuitemqt is deliberate: if
    Qt is unavailable, the loader catches the failure cleanly instead of
    crashing the whole module load (see outline.py:29-31, optimize.py:29-31).
    """
    from pymol.plugins import addmenuitemqt
    addmenuitemqt('bioCHEMeleon', run_plugin_gui)


def run_plugin_gui():
    """Lazily create and show the plugin dialog (singleton).

    Uses dialog.show() (modeless) so the 3D viewer stays interactive while the
    dialog is open — required by the Phase-4 click-to-find loop. NEVER use the
    modal form (blocks the PyMOL event loop and the viewer).
    """
    global dialog
    if dialog is None:
        dialog = PluginDialog()
    dialog.show()
    dialog.raise_()
    dialog.activateWindow()


from pymol.Qt import QtCore, QtGui, QtWidgets
from pymol import cmd


class PluginDialog(QtWidgets.QDialog):
    """bioCHEMeleon main dialog: a tabbed window with Setup and Game status tabs.

    Phase 1 ships placeholder tabs only. Phase 2 populates Setup; Phase 4
    populates Game status.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("bioCHEMeleon")
        self.setMinimumWidth(420)

        # Tab widget (pattern from optimize.py:72-79 — QTabWidget replaces the legacy notebook widget)
        self.tabs = QtWidgets.QTabWidget(self)

        # Lazy-import the tab widget classes inside __init__ so a bug in a
        # sibling module doesn't break plugin load (only runs on first open).
        from .gui_setup import SetupTab
        from .gui_game import GameTab

        self.setup_tab = SetupTab()
        self.game_tab = GameTab()

        self.tabs.addTab(self.setup_tab, "Setup")
        self.tabs.addTab(self.game_tab, "Game status")

        # Active GameController (held across the round so cleanup/restart can
        # reach it later; Phase 4 only needs it to stay referenced).
        self._controller = None

        # Wire the Start button (BTN-07) -> _on_start (defined below).
        self.setup_tab.start_btn.clicked.connect(self._on_start)
        # Phase 7: Cleanup (Setup tab) + Restart (Game tab) button wiring.
        self.setup_tab.cleanup_btn.clicked.connect(self._on_cleanup)
        self.game_tab._restart_btn.clicked.connect(self._on_restart)
        # Phase 8: Generate & export (Setup) + Import + Save (Game) wiring.
        self.setup_tab.export_btn.clicked.connect(self._on_export)
        self.game_tab._import_btn.clicked.connect(self._on_import)
        self.game_tab._save_btn.clicked.connect(self._on_save)

        # Layout
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.tabs)

    def _on_start(self):
        """BTN-07: resolve target -> build hider_specs -> start game ->
        switch to Game tab -> 3-2-1 countdown.

        Thin wrapper over _prepare_and_start (Phase 8 refactor: _on_export
        reuses the same prepare path without the tab switch + countdown)."""
        state = self.setup_tab.collect_state()
        controller, target_obj, _ = self._prepare_and_start(state)
        if controller is None:
            return  # _prepare_and_start already showed a QMessageBox
        self.tabs.setCurrentWidget(self.game_tab)
        self.game_tab.start_countdown(self._controller)

    def _prepare_and_start(self, state):
        """Resolve target -> collapse -> build hider_specs -> free valences ->
        clean prior game -> GameController + start. Returns
        ``(controller, target_obj, _gen_warnings)`` on success, or
        ``(None, None, [])`` after a QMessageBox on failure.

        Behavior-preserving extraction of _on_start steps 1-4 (Phase 8
        refactor). _on_start + _on_export both call this; _on_start then
        switches to the Game tab + starts the countdown, _on_export saves
        the .bcmz + stays on Setup.
        """
        from . import generators, game, demos, mutation
        import random as _random
        per_rep = state.get("per_rep", {})  # {rep: count} (Phase 2 collect_state)
        # 1. Resolve target object
        mode = state.get("target_mode", "loaded")
        target_obj = None
        if mode == "loaded":
            target_obj = state.get("selected_object") or ""
            if not target_obj or target_obj not in demos.list_loaded_molecule_objects():
                QtWidgets.QMessageBox.warning(self, "No object",
                    "Please select a loaded molecule object first.")
                return None, None, []
        elif mode == "fetch":
            pdb_code = state.get("pdb_code", "")
            if not pdb_code:
                QtWidgets.QMessageBox.warning(self, "No PDB code",
                    "Please enter a PDB code first.")
                return None, None, []
            # Use the already-loaded object if the user clicked Fetch in
            # the Setup tab. cmd.fetch fails when loading mmCIF into an
            # existing object ("loading mmCIF into existing object not
            # supported" — 05-05 human-verify Issue 1).
            target_obj = pdb_code
            if target_obj not in demos.list_loaded_molecule_objects():
                target_obj = demos.fetch_pdb(pdb_code)
                if target_obj is None:
                    QtWidgets.QMessageBox.warning(self, "Fetch failed",
                        "Could not fetch PDB code %r." % pdb_code)
                    return None, None, []
        elif mode == "demo":
            demo_id = state.get("demo_id", "")
            # Use the already-loaded object if the user loaded this demo
            # before (avoids re-loading + potential multi-state append).
            target_obj = demo_id.lower() if demo_id else ""
            if not target_obj or target_obj not in demos.list_loaded_molecule_objects():
                target_obj = demos.load_demo(demo_id)
                if target_obj is None:
                    QtWidgets.QMessageBox.warning(self, "Demo failed",
                        "Could not load demo %r." % demo_id)
                    return None, None, []
        else:
            QtWidgets.QMessageBox.warning(self, "No target", "Unknown target mode.")
            return None, None, []
        # 2. Prepare target: collapse multi-state objects BEFORE data
        #    collection. Multi-state objects (e.g. NMR ensembles like 1znf
        #    with 37 models) break backup/verify_intact (mutations only
        #    affect the current state; atom counts diverge across states).
        #    Collapsing to state 1 FIRST ensures extent, neighbor_ids, and
        #    cas_list are collected from the single-state object (atom IDs
        #    are reassigned by the delete+create in collapse, so data
        #    collected before collapse would be stale — 05-05 fix).
        mutation.collapse_to_single_state(target_obj)
        # 3. Build mixed-rep hider_specs from per_rep (one (payload, rep)
        #    tuple per hider; payload is rep-specific -- the shared contract
        #    with GameController.start, which dispatches each spec per rep).
        extent = cmd.get_extent(target_obj)
        hider_specs = []
        _gen_warnings = []  # collected under-generation warnings (05-05 Issue 1)
        # Pre-fetch the data the pure generators need (cmd-coupled, here in
        # _prepare_and_start so generators.py stays pure):
        # For line/stick: pool of real neighbor CA atom ids (to bond hiders to).
        # MUST use 'name CA' (NOT all atoms) — CA atoms survive free_nterminal_valence
        # removal (which only removes H + cap residue atoms); non-CA atoms sampled as
        # neighbors could be removed before insert_line_stick_hider runs, causing
        # IndexError on nbr[0] (05-05 GUI bug, 05-07 fix).
        neighbor_ids = []
        cmd.iterate("%s and not segi GAME and name CA" % target_obj,
                    "stored.append(ID)", space={'stored': neighbor_ids})
        # For cartoon: terminal C-alpha per chain (extend-at-terminus).
        cas_list = []
        # resv (numeric residue value, already int) NOT int(resi): the hygienic
        # space= dict does not expose Python builtins, so int(resi) raises
        # NameError (symbol table editing.py:1444-1449; mirrors smoke/phase5_smoke.py).
        cmd.iterate("%s and polymer and name CA" % target_obj,
                    "stored.append((chain, resv, ID))",
                    space={'stored': cas_list})
        cas_by_chain = {}
        for chain, resi, ca_id in cas_list:
            cas_by_chain.setdefault(chain, []).append((resi, ca_id))
        _rng = _random.Random()  # neighbor sampling (non-deterministic is fine)
        for rep, count in per_rep.items():
            if rep == 'spheres':
                positions = generators.generate_sphere_positions(extent, count)
                hider_specs += [(p, 'spheres') for p in positions]
            elif rep in ('lines', 'sticks'):
                offsets = generators.generate_line_stick_offsets(count)
                n_avail = min(count, len(neighbor_ids))
                chosen = _rng.sample(neighbor_ids, n_avail) if neighbor_ids else []
                for off, nbr_id in zip(offsets, chosen):
                    hider_specs.append(((off, nbr_id), rep))
            elif rep in ('cartoon', 'ribbon'):
                # Cap: one terminal extension per chain (attaching many to
                # one terminus chains them -- 05-RESEARCH.md Open Risk 5).
                terminals = generators.pick_terminal_residues(cas_by_chain,
                                                               max_chains=count)
                for term in terminals:
                    hider_specs.append((term, rep))
                # 05-05 Issue 1: warn the user when fewer cartoon/ribbon hiders
                # were generated than requested (1ubq has 1 chain -> max 1
                # cartoon hider even if count=5). This is by-design (Open Risk 5:
                # attaching many to one terminus chains them), NOT a bug, but
                # the user needs feedback so the "remaining" counter makes
                # sense (showing 1 when 5 were requested is confusing silently).
                if len(terminals) < count:
                    n_chains = len(cas_by_chain)
                    _gen_warnings.append(
                        "Requested %d %s hider%s but only %d chain%s available; "
                        "%d hider%s generated (cartoon/ribbon hiders attach one "
                        "per chain to avoid chaining them at a terminus)." %
                        (count, rep, "" if count == 1 else "s",
                         n_chains, "" if n_chains == 1 else "s",
                         len(terminals), "" if len(terminals) == 1 else "s"))
        # Fallback: if per_rep is empty (random mode unset), default to
        # spheres (Phase 4 behavior) using the total hider_count.
        if not hider_specs:
            count = int(state.get("hider_count", 0))
            positions = generators.generate_sphere_positions(extent, count)
            hider_specs = [(pos, "spheres") for pos in positions]
        # 05-05 Issue 1: show under-generation warnings (cartoon/ribbon capped
        # at one-per-chain). Non-blocking -- the game still starts with the
        # hiders that WERE generated.
        if _gen_warnings:
            QtWidgets.QMessageBox.warning(self, "Fewer hiders generated",
                "\n\n".join(_gen_warnings))
        # 3b. Free N-terminal valences for cartoon/ribbon hiders. Removes
        #     ACE/formyl caps and H atoms bonded to the terminal N so
        #     editor.attach_amino_acid finds a free valence. MUST happen
        #     before backup.snapshot (inside gc.start) so verify_intact
        #     matches (backup and target both have caps/H removed).
        #     05-05 human-verify Issues 2+3.
        for payload, rep in hider_specs:
            if rep in ('cartoon', 'ribbon') and not payload[2]:
                mutation.free_nterminal_valence(target_obj, payload[0], payload[1])
        # 4. Start the game (snapshot -> insert -> register; Phase 3 proven)
        # Bug 3: if a previous game is still active (mid-game, or won but not
        # yet cleaned up), clean it up first so no stale hiders accumulate in
        # the object. Without this, old hiders (absent from the new registry)
        # would make every old-hider click a "Miss!" and the atom count would
        #     grow each round. cleanup() is idempotent (no-op if _started=False).
        # Wizard lifecycle fix (Phase 7): deactivate the old PickWizard before
        # cleanup. Without this, _prepare_and_start creates a new wizard in
        # _begin_play without deactivating the old one, corrupting
        # mouse_selection_mode (stays at 0) + losing the prior-wizard
        # reference. Fixes the bug for BOTH Start-mid-game AND Restart
        # (Restart calls _on_start -> _prepare_and_start).
        if self.game_tab._wizard is not None:
            self.game_tab._wizard.deactivate()
            self.game_tab._wizard = None
            if self._controller is not None:
                self._controller._wizard = None
        if self._controller is not None and self._controller._started:
            self._controller.cleanup()
        self._controller = game.GameController(target_obj)
        try:
            self._controller.start(hider_specs)
        except RuntimeError as exc:
            QtWidgets.QMessageBox.warning(self, "Game already running",
                str(exc))
            return None, None, []
        return self._controller, target_obj, _gen_warnings

    def _on_export(self):
        """BTN-05: generate hiders + save initial game state WITHOUT playing.
        Reuses _prepare_and_start (same as Start), then saves a .bcmz with
        kind='puzzle', then stays on Setup. The educator's model keeps the
        generated hiders (press Cleanup to restore the scene)."""
        from . import persistence
        from pymol import cmd
        import tempfile, os
        state = self.setup_tab.collect_state()
        controller, target_obj, _ = self._prepare_and_start(state)
        if controller is None:
            return
        # File dialog (.bcmz) — static getSaveFileName owns its own modal
        # loop (NOT the exec_ modal call from our code; the main plugin
        # dialog stays modeless).
        path, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, "Generate & export puzzle", "",
            "bioCHEMeleon Puzzle (*.bcmz);;All Files (*)")
        if not path:
            # cancelled — cleanup the generated hiders so they don't linger
            controller.cleanup()
            return
        if not path.lower().endswith('.bcmz'):
            path += '.bcmz'
        try:
            bcm_dict = persistence.build_bcm_dict(
                controller, state, kind='puzzle')
            with tempfile.NamedTemporaryFile(
                    suffix='.pse', delete=False) as tf:
                pse_path = tf.name
            cmd.save(pse_path, target_obj)  # bare name -> excludes _bchm_backup
            persistence.write_bcmz(path, bcm_dict, pse_path)
            os.unlink(pse_path)  # clean temp
        except (OSError, ValueError) as exc:
            QtWidgets.QMessageBox.warning(
                self, "Export failed", "Could not save puzzle:\n%s" % exc)
            return
        QtWidgets.QMessageBox.information(
            self, "Puzzle exported",
            "Saved puzzle to:\n%s\n\nYour model still has the generated "
            "hiders. Press Cleanup to restore your scene." % path)
        # Stay on Setup tab; controller stays _started=True so Cleanup works.

    def _on_save(self):
        """GAME-09: save the current game state as a .bcmz checkpoint.
        Pause-capture-dialog-save-resume (PITFALLS.md: timer must not
        advance during the modal file dialog)."""
        import time as _time
        from . import persistence
        from pymol import cmd
        import tempfile, os
        if (self._controller is None or not self._controller._started
                or self._controller._start_time is None):
            return  # no game or not yet begun (countdown)
        self.game_tab._timer.stop()
        elapsed = _time.time() - self._controller._start_time
        path, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, "Save bioCHEMeleon checkpoint", "",
            "bioCHEMeleon Game (*.bcmz);;All Files (*)")
        if not path:
            # cancelled — rebase to exclude dialog-wait, then resume
            self._controller._start_time = _time.time() - elapsed
            self.game_tab._timer.start(1000)
            return
        if not path.lower().endswith('.bcmz'):
            path += '.bcmz'
        try:
            setup_state = self.setup_tab.collect_state()
            bcm_dict = persistence.build_bcm_dict(
                self._controller, setup_state, kind='checkpoint',
                elapsed=elapsed)
            with tempfile.NamedTemporaryFile(
                    suffix='.pse', delete=False) as tf:
                pse_path = tf.name
            cmd.save(pse_path, self._controller.target_obj)
            persistence.write_bcmz(path, bcm_dict, pse_path)
            os.unlink(pse_path)
        except (OSError, ValueError) as exc:
            QtWidgets.QMessageBox.warning(
                self, "Save failed", "Could not save checkpoint:\n%s" % exc)
            self._controller._start_time = _time.time() - elapsed
            self.game_tab._timer.start(1000)
            return
        # Resume timer — rebase so the dialog+save time is NOT counted
        self._controller._start_time = _time.time() - elapsed
        self.game_tab._timer.start(1000)
        self.game_tab._log("Saved checkpoint to %s" % path)

    def _on_restart(self):
        """Restart (GAME-10): fresh round with new hiders.

        Deactivates the old wizard + stops the timer, then calls _on_start
        which handles: prior-game cleanup, new hider_specs from Setup tab
        state, new GameController, tab switch, countdown. The log is cleared
        in start_countdown (Phase 7 fix in gui_game.py). The wizard
        deactivation here is defensive (belt + suspenders) -- _on_start also
        deactivates the wizard (wizard-lifecycle fix), so if the wizard is
        already None, this is a no-op.
        """
        if self.game_tab._wizard is not None:
            self.game_tab._wizard.deactivate()
            self.game_tab._wizard = None
            if self._controller is not None:
                self._controller._wizard = None
        self.game_tab._timer.stop()
        self._on_start()

    def _on_cleanup(self):
        """Cleanup (BTN-06): restore original object + END round (no new hiders).

        Deactivates the wizard, stops the timer, restores the object from
        backup (via controller.cleanup), resets the Game tab UI, and releases
        the controller (_controller = None). After cleanup, the model is back
        to its pre-Start state (atom count matches, no GAME atoms). The user
        can Start a new game from the Setup tab.
        """
        if self._controller is None:
            return  # no game to clean up
        if self.game_tab._wizard is not None:
            self.game_tab._wizard.deactivate()
            self.game_tab._wizard = None
            self._controller._wizard = None
        self.game_tab._timer.stop()
        self._controller.cleanup()
        self.game_tab._info_log.clear()
        self.game_tab._timer_label.setText("0:00")
        self.game_tab._remaining_label.setText("Remaining: -")
        self.game_tab._reveal_label.setText("Reveals: 0")
        self._controller = None  # released; Start re-creates via _on_start
