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

        # Layout
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.tabs)
