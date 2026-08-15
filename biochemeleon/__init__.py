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
        # For line/stick: pool of real neighbor backbone-anchor atom ids (to
        # bond hiders to). Uses 'name CA or name P' so BOTH protein (CA =
        # C-alpha) and nucleic acid (P = phosphate) backbones are covered —
        # nucleic acids have NO 'name CA' atoms (headless-verified 2026-08-16:
        # 5e54/1k8p/2qbz all return 0 for 'name CA'). P is the nucleic-acid
        # equivalent of CA: a stable one-per-residue backbone atom and a valid
        # bond target. (05-07 fix note: the original 'name CA' rationale was
        # that non-CA atoms could be removed by a terminal-valence step; Phase
        # 11 single-state path no longer runs that step, so the pool just needs
        # stable one-per-residue backbone atoms — CA for protein, P for NA.)
        neighbor_ids = []
        cmd.iterate("%s and not segi GAME and (name CA or name P)" % target_obj,
                    "stored.append(ID)", space={'stored': neighbor_ids})
        # For cartoon/ribbon: per-chain backbone-anchor (resi, id) list. Phase
        # 11 pick_segments consumes this for mid-chain segments (replacing the
        # Phase 5 terminal-extension path). 'polymer and (name CA or name P)'
        # covers protein (CA trace) + nucleic acid (P trace); PyMOL's cartoon
        # renderer draws the trace through CA (protein) or P (nucleic), so a
        # copied backbone segment renders in either case. Variable name
        # 'cas_list'/'cas_by_chain' is retained for continuity — entries are
        # (resi, anchor_id) where anchor is CA (protein) or P (nucleic).
        cas_list = []
        # resv (numeric residue value, already int) NOT int(resi): the hygienic
        # space= dict does not expose Python builtins, so int(resi) raises
        # NameError (symbol table editing.py:1444-1449; mirrors smoke/phase5_smoke.py).
        # Bug 2: captured BEFORE any insert (alt-conf construction reads from
        # the backup temp, not the live object).
        cmd.iterate("%s and polymer and (name CA or name P)" % target_obj,
                    "stored.append((chain, resv, ID))",
                    space={'stored': cas_list})
        cas_by_chain = {}
        for chain, resi, ca_id in cas_list:
            cas_by_chain.setdefault(chain, []).append((resi, ca_id))
        # Phase 11 fix (cartoon+ribbon KeyError): pick_segments is called ONCE
        # for the COMBINED cartoon+ribbon count so the returned segments are
        # GLOBALLY DISJOINT across reps. Previously pick_segments was called
        # per rep independently; for count=1 it picks the DETERMINISTIC
        # centered window (generators.py:159-160, no RNG), so cartoon and
        # ribbon both picked the SAME segment. With the single-state refactor,
        # each hider copies its segment to a NEW chain-H fragment, so two
        # hiders on the SAME resi range would both create chain-H GAME atoms
        # at those resi -> the 2nd union-create merge would overwrite the 1st
        # (same chain+resi+name+alt='') -> same anchor id -> registry.register
        # KeyError on the duplicate (object, id). A single global pick is
        # semantically correct (cartoon+ribbon both need a mid-chain backbone
        # segment; rep only controls cmd.show) AND guarantees disjoint resi
        # ranges -> distinct chain-H fragments -> distinct NEW anchor ids.
        # Mirrors the smoke-test Section I/M pattern (pick_segments(..., 2)
        # once, split across reps). Segments are consumed in per_rep.items()
        # order so hider_specs order is unchanged.
        _cartoon_reps = [r for r in per_rep if r in ('cartoon', 'ribbon')]
        _cartoon_total = sum(per_rep[r] for r in _cartoon_reps)
        _cartoon_segments = (generators.pick_segments(cas_by_chain, _cartoon_total)
                             if _cartoon_total else [])
        _cartoon_disps = generators.generate_middle_displacement(
            len(_cartoon_segments))
        _cartoon_idx = 0  # consumed across reps in per_rep.items() order
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
                # Phase 11 single-state: mid-chain backbone segment (replaces
                # terminal extension AND the prior alt-conf approach). Segments
                # come from the SINGLE global pick above (globally disjoint
                # across cartoon+ribbon -> distinct chain-H fragments -> distinct
                # NEW anchor ids -> no KeyError; see the pre-loop comment).
                # generate_middle_displacement produces one rigid [dx,dy,dz] per
                # segment (USER REQ 2: endpoints fixed, middle displaced -> a
                # visible bump). The 4-tuple payload routes to
                # insert_cartoon_segment_hider via the dispatcher (arity check);
                # game.start registers endpoint_resvs (for _mark_found fragment
                # coloring; is_altconf stays False -> id-keyed like sphere/stick).
                _take = min(count, len(_cartoon_segments) - _cartoon_idx)
                segments = _cartoon_segments[_cartoon_idx:_cartoon_idx + _take]
                disps = _cartoon_disps[_cartoon_idx:_cartoon_idx + _take]
                _cartoon_idx += _take
                for (chain, start_resi, end_resi), disp in zip(segments, disps):
                    hider_specs.append(
                        ((chain, start_resi, end_resi, disp), rep))
                if _take < count:
                    _gen_warnings.append(
                        "Requested %d %s hider%s but only %d disjoint mid-chain "
                        "segment%s available; %d hider%s generated (cartoon/ribbon "
                        "hiders need a >=3-residue mid-chain segment per hider)." %
                        (count, rep, "" if count == 1 else "s",
                         _take, "" if _take == 1 else "s",
                         _take, "" if _take == 1 else "s"))
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
        # Phase 11 single-state: cartoon/ribbon hiders copy a backbone segment
        # from the clean backup to a NEW chain-H fragment (insert_cartoon_segment_hider)
        # — they do NOT attach at a terminus, so the N-terminal valence does NOT
        # need freeing (the legacy terminal-extension path that needed it is no
        # longer used by _prepare_and_start). ACE caps + H atoms stay in the
        # object; backup.snapshot (inside gc.start) captures them and
        # backup.restore (cleanup) restores them.
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

    def _on_import(self):
        """GAME-04: load a previously-exported game and let the player play it.
        Unzip .bcmz -> refuse-first collision check -> cmd.load(partial=1,
        MERGE) -> resolve_target -> GameController.import_state -> switch
        to Game tab -> start_countdown(elapsed). NO re-generation.

        Discrepancy 1 resolution: cmd.load(pse_path, partial=1) MERGES the
        .pse into the current session (preserves the player's scene). A
        refuse-first collision check defends against the unverified C-level
        collision: if the .bcm's target_object is already loaded, refuse
        BEFORE the load with a clear message.
        """
        from . import game, persistence, demos
        from pymol import cmd
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "Import bioCHEMeleon game", "",
            "bioCHEMeleon Game (*.bcmz);;All Files (*)")
        if not path:
            return
        # 1. Unzip + read .bcm (read_bcmz returns (pse_path, bcm_dict))
        try:
            pse_path, bcm_dict = persistence.read_bcmz(path)
        except (OSError, ValueError) as exc:
            QtWidgets.QMessageBox.warning(
                self, "Import failed", "Could not read game file:\n%s" % exc)
            return
        # 2. Refuse-first collision check (Discrepancy 1 resolution):
        #    if the .bcm's target_object is already loaded, refuse BEFORE
        #    the load -- defends against the unverified C-level collision.
        target_in_bcm = bcm_dict.get('target_object')
        if (target_in_bcm and
                target_in_bcm in demos.list_loaded_molecule_objects()):
            QtWidgets.QMessageBox.warning(
                self, "Name collision",
                "An object named '%s' is already loaded. Please rename or "
                "delete it before importing this game (or re-export with a "
                "unique object name)." % target_in_bcm)
            return
        # 3. Clean any prior game (mirror _prepare_and_start wizard teardown)
        if self.game_tab._wizard is not None:
            self.game_tab._wizard.deactivate()
            self.game_tab._wizard = None
            if self._controller is not None:
                self._controller._wizard = None
        if self._controller is not None and self._controller._started:
            self._controller.cleanup()
        # 4. Record names, then MERGE the .pse (partial=1 preserves scene)
        names_before = set(cmd.get_names('public_objects', enabled_only=True))
        try:
            cmd.load(pse_path, partial=1)
        except Exception as exc:
            QtWidgets.QMessageBox.warning(
                self, "Import failed",
                "Could not load the game session:\n%s" % exc)
            return
        # 5. Resolve target (Fact 2: name comes from the .pse, not filename)
        target_obj = persistence.resolve_target(
            bcm_dict, names_before,
            demos.list_loaded_molecule_objects())
        if target_obj is None:
            QtWidgets.QMessageBox.warning(
                self, "Import failed",
                "Could not identify the game's target object. Please ensure "
                "the game file is valid.")
            return
        # 6. Build controller + import state (reconstruct + apply + backup)
        self._controller = game.GameController(target_obj)
        try:
            self._controller.import_state(bcm_dict)
        except (RuntimeError, ValueError) as exc:
            QtWidgets.QMessageBox.warning(
                self, "Import failed",
                "Could not restore game state:\n%s" % exc)
            self._controller = None
            return
        # 7. Switch to Game tab + start countdown with resumed timer
        self.tabs.setCurrentWidget(self.game_tab)
        elapsed = float(bcm_dict.get('timer_elapsed', 0.0))
        self.game_tab.start_countdown(self._controller, elapsed=elapsed)

    def _on_restart(self):
        """Restart: fresh round. Routes on _is_imported -- imported games
        restore from the post-import backup (no re-generation); non-imported
        games re-generate from the Setup tab via _on_start."""
        if self.game_tab._wizard is not None:
            self.game_tab._wizard.deactivate()
            self.game_tab._wizard = None
            if self._controller is not None:
                self._controller._wizard = None
        self.game_tab._timer.stop()
        if (self._controller is not None
                and getattr(self._controller, '_is_imported', False)):
            self._on_restart_imported()
        else:
            self._on_start()

    def _on_restart_imported(self):
        """Restart an imported game: restore from the post-import backup
        (re-hides all hiders, resets found-status to the imported state,
        clears hint colors), reset runtime counters, re-snapshot, restart
        countdown. NO re-generation.

        Restore brings the object back to the post-import snapshot (hiders
        present, found-status as imported). Re-reconcile rep from the saved
        _imported_bcm (rep is lost on restore -- sentinels carry no rep).
        Fresh backup.snapshot so the NEXT Restart/Cleanup restores to the
        same imported initial state.
        """
        from . import backup, registry, persistence
        c = self._controller
        if c is None:
            return
        backup.restore(c.target_obj, c._backup_name)
        backup.discard(c._backup_name)
        c.reconstruct_registry()  # sentinel rebuild (rep=None, all hidden)
        # Re-reconcile rep from the saved .bcm (rep is lost on restore)
        if c._imported_bcm is not None:
            persistence.apply_bcm_dict(c, c._imported_bcm)
        c._reveal_count = 0
        c._hint_count = 0
        c._start_time = None  # _begin_play sets it fresh
        c._backup_name = backup.snapshot(c.target_obj)  # fresh backup
        c._started = True
        self.game_tab.start_countdown(c)

    def _on_cleanup(self):
        """Cleanup: restore original object + END round. For non-imported
        games, the backup is the pre-game snapshot (no hiders) so restore
        gives a clean molecule. For imported games, the backup is the
        post-import snapshot (WITH hiders), so restore brings hiders back
        -- two-step: restore (fixes hint-orange real atoms) THEN
        mutation.cleanup_hiders (removes the restored hiders)."""
        from . import backup, mutation, registry
        if self._controller is None:
            return
        if self.game_tab._wizard is not None:
            self.game_tab._wizard.deactivate()
            self.game_tab._wizard = None
            self._controller._wizard = None
        self.game_tab._timer.stop()
        c = self._controller
        if getattr(c, '_is_imported', False):
            # Imported: two-step (restore real-atom colors, then remove hiders)
            backup.restore(c.target_obj, c._backup_name)
            backup.discard(c._backup_name)
            mutation.cleanup_hiders(c.target_obj)
            c._started = False
            c.registry = registry.HiderRegistry()
            c._reveal_count = 0
            c._hint_count = 0
        else:
            c.cleanup()  # existing path: backup is pre-game, restore removes hiders
        self.game_tab._info_log.clear()
        self.game_tab._timer_label.setText("0:00")
        self.game_tab._remaining_label.setText("Remaining: -")
        self.game_tab._reveal_label.setText("Reveals: 0")
        self._controller = None
