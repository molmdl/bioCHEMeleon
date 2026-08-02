"""Setup tab — populated with the full config form in Phase 2."""
from pymol.Qt import QtWidgets


class SetupTab(QtWidgets.QWidget):
    """Placeholder Setup tab. Phase 2 adds the object selector, hider count,
    lock-scene checkbox, per-rep list, difficulty toggle, and 7 buttons.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(QtWidgets.QLabel("Setup — coming in Phase 2"))
