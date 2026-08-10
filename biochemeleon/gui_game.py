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
        btn_row.addStretch(1)
        btn_row.addWidget(self._reveal_label)
        layout.addLayout(btn_row)
        self._hint_btn.clicked.connect(self._on_hint_clicked)
        self._reveal_one_btn.clicked.connect(self._on_reveal_one_clicked)
        self._reveal_all_btn.clicked.connect(self._on_reveal_all_clicked)
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

    def _on_tick(self):
        elapsed = time.time() - self._start_time
        mins = int(elapsed) // 60
        secs = int(elapsed) % 60
        self._timer_label.setText("%d:%02d" % (mins, secs))

    def start_countdown(self, controller):
        """Begin the 3-2-1 countdown (called by PluginDialog._on_start after
        GameController.start + tab switch). On GO!, _begin_play activates the
        PickWizard, registers callbacks, and starts the timer."""
        self._controller = controller
        self._reveal_label.setText("Reveals: 0")  # reset for new round (C8)
        self._log("Get ready...")
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
        self._start_time = time.time()
        # Bug 1: win() (game.py) reads the CONTROLLER's _start_time, not the
        # tab's. The tab's copy feeds _on_tick (timer label); the controller's
        # copy feeds win()'s elapsed math. Both must be set.
        self._controller._start_time = self._start_time
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
        # After the user dismisses the dialog, clean up the hiders (sentinel
        # remove) + discard the backup so the object is back to its pre-game
        # state. cleanup() is idempotent (no-op if already _started=False).
        self._controller.cleanup()
