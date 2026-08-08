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
        self._controller._wizard = self._wizard   # controller deactivates on win()
        self._controller.set_callbacks(
            on_log=self._log,
            on_remaining_changed=self._update_remaining,
            on_win=self._on_win,
        )
        self._start_time = time.time()
        # Bug 1: win() (game.py) reads the CONTROLLER's _start_time, not the
        # tab's. The tab's copy feeds _on_tick (timer label); the controller's
        # copy feeds win()'s elapsed math. Both must be set.
        self._controller._start_time = self._start_time
        self._timer.start(1000)
        self._update_remaining(self._controller._remaining())

    def _on_win(self, elapsed):
        self._timer.stop()
        mins = int(elapsed) // 60
        secs = int(elapsed) % 60
        # Bug 2: the last cmd.color('green', ...) from on_pick must flush to
        # the viewer BEFORE the modal QMessageBox blocks the Qt event loop,
        # or the user sees the win dialog but the last hider never turns
        # green. win() already deactivated the wizard (so the click loop is
        # closed -- no re-entrant picks during processEvents); force a scene
        # redraw + drain pending Qt paint events so the green lands.
        from pymol import cmd
        cmd.refresh()
        QtWidgets.QApplication.processEvents()
        QtWidgets.QMessageBox.information(
            self, "You win!",
            "You found all hiders in %d:%02d!" % (mins, secs))
        # Bug 3: after the user dismisses the win dialog, clean up the hiders
        # (sentinel remove) + discard the backup so the object is back to its
        # pre-game state. Without this, _started stays True, old hiders remain
        # in the object, and a new game accumulates stale hiders whose ids are
        # absent from the new registry -> every old-hider click is a "Miss!".
        # cleanup() is idempotent (no-op if already _started=False).
        self._controller.cleanup()
