"""PickWizard -- click-to-find handler (pymol.wizard.Wizard subclass).

Phase 4 click-to-find loop: PyMOL routes atom picks to do_pick, which reads
the picked atom's STABLE id from pk1 via cmd.identify("pk1", mode=1) and
forwards it to GameController.on_pick(aid). The id matches the registry key
(object, id) returned by mutation.insert_hider via cmd.identify(mode=0).

AGENTS.md: NEVER read pk1 through the index primitive -- index is fragile
(querying.py:1313-1317 warns "use integral atom identifiers instead of
indices"). Use cmd.identify("pk1", mode=1) -> [(model, id)].
"""
from pymol import cmd
from pymol.wizard import Wizard


class PickWizard(Wizard):
    """Atom-pick wizard for the hide-and-seek click-to-find loop."""

    def __init__(self, controller, target_object, _self=cmd):
        Wizard.__init__(self, _self)
        self.controller = controller          # duck-typed: needs on_pick(aid) + target_obj
        self.target_object = target_object
        self._saved_wizard = None
        # Canonical pattern (measurement.py:96-97): save + set mouse mode
        self._saved_selection_mode = cmd.get_setting_int("mouse_selection_mode")
        cmd.set("mouse_selection_mode", 0)   # 0 = atomic (single-atom pick)
        cmd.deselect()

    def do_pick(self, bondFlag):
        # Read picked atom (model, id) from pk1 -- id is the STABLE identifier
        pairs = cmd.identify("pk1", mode=1)   # [(model, id)]
        cmd.unpick()                           # clear pk1 for next pick
        if not pairs:
            return
        model, aid = pairs[0]
        if model != self.target_object:
            # clicked a non-target object -- miss, no-op (LOOP-01: no harm)
            return
        self.controller.on_pick(aid)
        cmd.refresh_wizard()

    def activate(self):
        self._saved_wizard = cmd.get_wizard()   # None if no wizard active
        cmd.set_wizard(self)

    def deactivate(self):
        cmd.set_wizard(self._saved_wizard)       # restore (or clear if None)
        cmd.set("mouse_selection_mode", self._saved_selection_mode)

    def get_panel(self):
        return [[1, 'bioCHEMeleon', ''],
                [2, 'Done (quit game)', 'cmd.get_wizard().deactivate()']]
