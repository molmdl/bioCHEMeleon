"""Game status tab — rolling info log, timer, remaining count, countdown, win.

Phase 4 populates the Game status tab with the player-facing game state
surface (GAME-01 log, GAME-02 timer, GAME-03 remaining) plus the 3-2-1
countdown (BTN-07) and the winning message (LOOP-03). The tab owns a 1 Hz
QTimer on the Qt main thread (PITFALLS.md Pitfall 6: NEVER threading.Thread
with cmd.*). When play begins, _begin_play creates + activates a PickWizard
(wizard.py) and registers the GameController callbacks so
the controller drives this UI.
"""
import time

from pymol.Qt import QtCore, QtWidgets


class GameTab(QtWidgets.QWidget):
    """Game status tab: rolling log + timer + remaining + countdown + win."""

    def __init__(self, parent=None):
        super().__init__(parent)
        # --- Widgets ---
        self._info_log = QtWidgets.QTextEdit()
        self._info_log.setReadOnly(True)
        self._timer_label = QtWidgets.QLabel("0:00")
        self._remaining_label = QtWidgets.QLabel("Remaining: -")
        # --- Layout ---
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(QtWidgets.QLabel("Info log:"))
        layout.addWidget(self._info_log, 1)   # stretch = log grows
        row = QtWidgets.QHBoxLayout()
        row.addWidget(self._timer_label)
        row.addStretch(1)
        row.addWidget(self._remaining_label)
        layout.addLayout(row)
        # --- Hint / Reveal buttons + reveal counter (Phase 6) ---
        self._hint_btn = QtWidgets.QPushButton("Hint")
        self._reveal_one_btn = QtWidgets.QPushButton("Reveal one")
        self._reveal_all_btn = QtWidgets.QPushButton("Reveal all")
        self._reveal_label = QtWidgets.QLabel("Reveals: 0")
        btn_row = QtWidgets.QHBoxLayout()
        btn_row.addWidget(self._hint_btn)
        btn_row.addWidget(self._reveal_one_btn)
        btn_row.addWidget(self._reveal_all_btn)
        # Phase 7: found-hider management dropdown + color picker + restart
        self._found_mgmt_combo = QtWidgets.QComboBox()
        self._found_mgmt_combo.addItem("Found hiders: (select)")
        self._found_mgmt_combo.addItem("Hide found")
        self._found_mgmt_combo.addItem("Show found")
        self._found_mgmt_combo.addItem("Recolor found")
        btn_row.addWidget(self._found_mgmt_combo)
        self._color_btn = QtWidgets.QPushButton("Color…")
        self._color_btn.setToolTip("Choose highlight color for found hiders")
        btn_row.addWidget(self._color_btn)
        self._restart_btn = QtWidgets.QPushButton("Restart")
        self._restart_btn.setToolTip("Start a fresh round with new hiders")
        btn_row.addWidget(self._restart_btn)
        btn_row.addStretch(1)
        btn_row.addWidget(self._reveal_label)
        # Phase 8: begin_row (Import + Save) -- "begin/end" actions, visually
        # separate from the in-game Hint/Reveal/Found-mgmt btn_row below.
        # Added BEFORE btn_row so it renders ABOVE it (a QHBoxLayout added
        # later still renders below).
        begin_row = QtWidgets.QHBoxLayout()
        self._import_btn = QtWidgets.QPushButton("Import puzzle…")
        self._import_btn.setToolTip(
            "Load a puzzle prepared by 'Generate & export' and play it.")
        self._save_btn = QtWidgets.QPushButton("Save checkpoint")
        self._save_btn.setToolTip(
            "Save the current game state to resume later.")
        begin_row.addWidget(self._import_btn)
        begin_row.addWidget(self._save_btn)
        begin_row.addStretch(1)
        layout.addLayout(begin_row)
        layout.addLayout(btn_row)
        self._hint_btn.clicked.connect(self._on_hint_clicked)
        self._reveal_one_btn.clicked.connect(self._on_reveal_one_clicked)
        self._reveal_all_btn.clicked.connect(self._on_reveal_all_clicked)
        # Phase 7: found-mgmt combo + color picker wiring (restart wired in
        # __init__.py — same pattern as start_btn). Use `activated` (NOT
        # currentIndexChanged) so the index-0 placeholder doesn't fire on
        # construction.
        self._found_mgmt_combo.activated.connect(self._on_found_mgmt_activated)
        self._color_btn.clicked.connect(self._on_pick_color)
        # --- 1 Hz QTimer (main thread; PITFALLS.md Pitfall 6) ---
        self._timer = QtCore.QTimer()
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self._on_tick)
        # --- Play state (set by start_countdown / _begin_play) ---
        self._controller = None
        self._wizard = None
        self._start_time = None

    # ---- play-flow (countdown -> begin_play -> callbacks -> win) ----

    def _log(self, msg):
        self._info_log.append(str(msg))

    def _update_remaining(self, remaining):
        self._remaining_label.setText("Remaining: %d" % remaining)

    def _confirm(self, title, text):
        """Yes/No confirm. Uses top-level window as parent so the dialog
        appears above the PyMOL OpenGL window (same fix as _finish_win)."""
        btns = QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No
        return QtWidgets.QMessageBox.question(
            self.window(), title, text, btns) == QtWidgets.QMessageBox.Yes

    def _on_counts_changed(self, hint_count, reveal_count):
        self._reveal_label.setText("Reveals: %d" % reveal_count)

    def _on_hint_clicked(self):
        if self._controller is None or not self._controller._started:
            return
        if self._controller._remaining() == 0:
            return
        self._controller.hint()

    def _on_reveal_one_clicked(self):
        if self._controller is None or not self._controller._started:
            return
        if self._controller._remaining() == 0:
            return
        if not self._confirm("Reveal one hider?",
                "Give up on one random hider? This counts as a reveal use."):
            return
        self._controller.reveal_one()

    def _on_reveal_all_clicked(self):
        if self._controller is None or not self._controller._started:
            return
        if self._controller._remaining() == 0:
            return
        if not self._confirm("Reveal all hiders?",
                "Give up and reveal ALL remaining hiders? This ends the game."):
            return
        self._controller.reveal_all()

    def _on_found_mgmt(self, mode):
        """Found-hider management core (GAME-08): hide/show/recolor the found
        hiders. Called by the combo handler AND _on_pick_color. Filters the
        registry by HIDER_STATUS_FOUND (NOT by color -- found hiders may be
        recolored to any color, so status is the only reliable predicate).
        """
        if self._controller is None or not self._controller._started:
            return
        from pymol import cmd
        from .registry import (HIDER_STATUS_FOUND, build_found_selection,
                               group_found_by_rep)
        found = [r for r in self._controller.registry.all()
                 if r.status == HIDER_STATUS_FOUND]
        if not found:
            return
        sele = build_found_selection(found, self._controller.target_obj)
        if sele is None:
            return  # defensive -- build_found_selection returns None for no found
        if mode == 'hide':
            cmd.hide("everything", sele)
        elif mode == 'show':
            by_rep = group_found_by_rep(found)
            for rep, ids in by_rep.items():
                cmd.show(rep, "%s and id %s" % (
                    self._controller.target_obj,
                    "+".join(str(i) for i in ids)))
        elif mode == 'recolor':
            cmd.color(self._controller._found_color, sele)

    def _on_found_mgmt_activated(self, index):
        """Combo handler. Maps combo index to mode (1=hide, 2=show, 3=recolor).
        Index 0 is the placeholder (no-op). Resets to 0 after handling so the
        user can re-select the same action."""
        mode = {1: 'hide', 2: 'show', 3: 'recolor'}.get(index)
        if mode:
            self._on_found_mgmt(mode)
        self._found_mgmt_combo.setCurrentIndex(0)  # reset for re-selection

    def _on_pick_color(self):
        """Color picker (DIFF-04): let the player choose a highlight color.
        QColorDialog.getColor() is a static method that runs its own modal
        event loop internally -- it does NOT use the exec_ modal call from our
        code, so the modeless-main rule is preserved and the exec_ grep gate
        stays at 1 (the existing _finish_win modal message only).
        Sets a PyMOL named color 'found_highlight' then assigns it to the
        controller's _found_color so new finds use it. Auto-recolors existing
        found hiders so the change is immediately visible.
        """
        if self._controller is None or not self._controller._started:
            return
        color = QtWidgets.QColorDialog.getColor()
        if not color.isValid():
            return  # cancelled
        r, g, b, _ = color.getRgbF()
        from pymol import cmd
        cmd.set_color('found_highlight', [r, g, b])
        self._controller._found_color = 'found_highlight'
        self._on_found_mgmt('recolor')  # auto-recolor existing found

    def _on_tick(self):
        elapsed = time.time() - self._start_time
        mins = int(elapsed) // 60
        secs = int(elapsed) % 60
        self._timer_label.setText("%d:%02d" % (mins, secs))

    def start_countdown(self, controller, elapsed=0):
        """Begin the 3-2-1 countdown. On GO!, _begin_play activates the
        PickWizard, registers callbacks, and starts the timer.

        Args:
            controller (GameController): the active controller (just
                .start()ed for a fresh game, or reconstructed+reconciled
                for an imported checkpoint).
            elapsed (float): saved elapsed seconds to resume from
                (checkpoint import); 0.0 for a fresh game or puzzle
                import. The timer displays ``elapsed + (now - _begin_play_time)``
                so a checkpoint resumes counting up from the saved time.
        """
        self._controller = controller
        self._saved_elapsed = float(elapsed)   # consumed by _begin_play
        self._reveal_label.setText("Reveals: %d" % (controller._reveal_count,))
        self._info_log.clear()  # fresh round = clean log (Phase 7 fix)
        self._log("Get ready...")
        if elapsed > 0:
            mins = int(elapsed) // 60
            secs = int(elapsed) % 60
            self._timer_label.setText("%d:%02d" % (mins, secs))
        self._countdown_step(3)

    def _countdown_step(self, n):
        if n > 0:
            self._log("%d" % n)
            QtCore.QTimer.singleShot(1000, lambda: self._countdown_step(n - 1))
        else:
            self._log("GO!")
            self._begin_play()

    def _begin_play(self):
        from .wizard import PickWizard   # lazy: avoid importing wizard at module load
        self._wizard = PickWizard(self._controller, self._controller.target_obj)
        self._wizard.activate()
        self._controller._wizard = self._wizard   # _finish_win deactivates on win()
        self._controller.set_callbacks(
            on_log=self._log,
            on_remaining_changed=self._update_remaining,
            on_win=self._on_win,
            on_counts_changed=self._on_counts_changed,
        )
        elapsed = getattr(self, '_saved_elapsed', 0.0)
        self._start_time = time.time() - elapsed   # resume from saved elapsed
        # Bug fix for checkpoint import: if the controller already has a
        # _start_time (set by import_state for a checkpoint resume), do NOT
        # clobber it -- the controller's copy feeds win()'s elapsed math.
        if self._controller._start_time is None:
            self._controller._start_time = self._start_time
        self._saved_elapsed = 0.0   # reset for next round
        self._timer.stop()  # defensive: stop any prior timer (Restart mid-game)
        self._timer.start(1000)
        self._update_remaining(self._controller._remaining())

    def _on_win(self, elapsed):
        """Win callback: schedule the win dialog after a short delay so
        PyMOL redraws the 3D scene (the last cmd.color('green') from
        on_pick becomes visible) BEFORE the modal dialog blocks the Qt
        event loop.

        The wizard is NOT deactivated here -- _finish_win does that in the
        delayed callback, after the redraw frame has landed. Deactivating
        in the same call as cmd.color (the previous approach) let the
        wizard-teardown WizardRefresh clobber the pending green redraw;
        separating them by 100 ms lets PyMOL render the green first.
        """
        self._timer.stop()
        from pymol import cmd
        cmd.refresh()  # trigger a scene redraw now; 100 ms lets it land
        QtCore.QTimer.singleShot(100, lambda: self._finish_win(elapsed))

    def _finish_win(self, elapsed):
        """Delayed win handler: deactivate wizard, show a stay-on-top modal
        win dialog, then cleanup after dismissal.

        Called 100 ms after _on_win so PyMOL gets a redraw frame between the
        last cmd.color('green') (in on_pick) and the modal blocking the
        event loop -- otherwise the last hider never appears green (Bug A).
        The dialog uses the top-level window as parent + WindowStaysOnTopHint
        so it appears ABOVE the PyMOL OpenGL window (Bug B). After dismissal,
        cleanup() restores the object to its pre-game state (Bug C / Phase 4
        Bug 3: hiders removed, backup discarded, viewer interactive).
        """
        # Deactivate the wizard (restores mouse_selection_mode + prior wizard).
        # Done HERE (delayed) rather than in win() so the click loop stays
        # open long enough for the green redraw to land.
        if self._wizard is not None:
            self._wizard.deactivate()
            self._wizard = None
            self._controller._wizard = None
        mins = int(elapsed) // 60
        secs = int(elapsed) % 60
        # Use the top-level PluginDialog as parent + stay-on-top so the
        # dialog appears above the PyMOL OpenGL window (not hidden behind it).
        msg = QtWidgets.QMessageBox(self.window())
        msg.setIcon(QtWidgets.QMessageBox.Information)
        msg.setWindowTitle("You win!")
        msg.setText("You found all hiders in %d:%02d!" % (mins, secs))
        msg.setWindowFlags(msg.windowFlags() | QtCore.Qt.WindowStaysOnTopHint)
        msg.exec_()
        # After the user dismisses the dialog:
        # - NON-IMPORTED game: cleanup() restores from the pre-game backup
        #   (removes hiders, restores hint-colored real atoms, discards
        #   backup) -> clean molecule ready for a new game.
        # - IMPORTED game: do NOT call cleanup() here -- it would discard
        #   the post-import backup, breaking subsequent Cleanup/Restart
        #   (which need the backup to restore the imported initial state;
        #   backup.restore with a discarded/None backup deletes the target
        #   then fails to recreate it -> empty scene). The user clicks
        #   Cleanup explicitly (imported two-step: restore + cleanup_hiders)
        #   or Restart (restore + re-reconcile from _imported_bcm). The
        #   hiders stay (all found+green) until the user acts.
        if not getattr(self._controller, '_is_imported', False):
            self._controller.cleanup()
