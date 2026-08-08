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

        # Layout
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.tabs)

    def _on_start(self):
        """BTN-07: resolve target -> generate sphere hiders -> start game ->
        show spheres -> switch to Game tab -> 3-2-1 countdown."""
        from . import generators, game, demos
        state = self.setup_tab.collect_state()
        # 1. Resolve target object
        mode = state.get("target_mode", "loaded")
        target_obj = None
        if mode == "loaded":
            target_obj = state.get("selected_object") or ""
            if not target_obj or target_obj not in demos.list_loaded_molecule_objects():
                QtWidgets.QMessageBox.warning(self, "No object",
                    "Please select a loaded molecule object first.")
                return
        elif mode == "fetch":
            target_obj = demos.fetch_pdb(state.get("pdb_code", ""))
            if target_obj is None:
                QtWidgets.QMessageBox.warning(self, "Fetch failed",
                    "Could not fetch PDB code %r." % state.get("pdb_code", ""))
                return
        elif mode == "demo":
            target_obj = demos.load_demo(state.get("demo_id", ""))
            if target_obj is None:
                QtWidgets.QMessageBox.warning(self, "Demo failed",
                    "Could not load demo %r." % state.get("demo_id", ""))
                return
        else:
            QtWidgets.QMessageBox.warning(self, "No target", "Unknown target mode.")
            return
        # 2. Generate sphere hider positions
        extent = cmd.get_extent(target_obj)
        count = int(state.get("hider_count", 0))
        positions = generators.generate_sphere_positions(extent, count)
        hider_specs = [(pos, "spheres") for pos in positions]
        # 3. Start the game (snapshot -> insert -> register; Phase 3 proven)
        self._controller = game.GameController(target_obj)
        try:
            self._controller.start(hider_specs)
        except RuntimeError as exc:
            QtWidgets.QMessageBox.warning(self, "Game already running",
                str(exc))
            return
        # 4. Show hiders as spheres (mutation.insert_hider uses elem='PS')
        cmd.show("spheres", "%s and segi GAME" % target_obj)
        # 5. Switch to Game tab + start the 3-2-1 countdown
        self.tabs.setCurrentWidget(self.game_tab)
        self.game_tab.start_countdown(self._controller)
