"""Game status tab — populated with timer/remaining/info/buttons in Phase 4."""
from pymol.Qt import QtWidgets


class GameTab(QtWidgets.QWidget):
    """Placeholder Game status tab. Phase 4 adds the rolling info box, timer,
    remaining counter, and hint/reveal/save/restart buttons.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(QtWidgets.QLabel("Game status — coming in Phase 4"))
