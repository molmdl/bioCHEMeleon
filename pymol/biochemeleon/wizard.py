"""PickWizard -- click-to-find handler (pymol.wizard.Wizard subclass).

Phase 4 click-to-find loop: PyMOL routes a clicked atom to GameController.on_pick
(aid), where `aid` is the STABLE atom id (matches the registry key (object, id)
returned by mutation.insert_hider via cmd.identify(mode=0)).

Clicks arrive via ONE of two paths depending on the active BUTTON MODE (not
mouse_selection_mode -- that only sets selection granularity: atom/residue/...):

* PICKING button modes (cButModePickAtom "PkAt", cButModePickAtom1 "Pk1"):
  the C layer (SceneMouse.cpp:403-467) creates "pk1" + calls WizardDoPick ->
  do_pick(bondFlag).
* SELECTION button modes (cButModeSeleSet "Sele", ... -- the DEFAULT in
  3-Button Viewing): the C layer (SceneMouse.cpp:337-356) creates "sele" +
  calls WizardDoSelect -> do_select(name). do_pick is NEVER called.

do_select is the canonical select->pick map (pymol.wizard.measurement.do_select):
it builds pk1 from the just-created selection, cleans it up, and dispatches
through do_pick. This keeps left-drag rotation working (essential for
spin-to-find) and avoids fragile button-mode save/restore.

AGENTS.md: NEVER read pk1 through the index primitive -- index is fragile
(querying.py:1313-1317 warns "use integral atom identifiers instead of
indices"). Phase 11: do_pick reads (model, ID, alt, resv) via cmd.iterate
because alt-conf atoms share ids (cmd.identify returns (model, id) with NO
alt -- Pitfall 11); the alt+resv gate in GameController.on_pick needs alt
to distinguish a clicked alt-conf hider (alt='B') from the real-trace
original (alt='') that shares the id (Pitfall 10).
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
        # Read (model, ID, alt, resv) from pk1 via ONE iterate BEFORE unpick.
        # cmd.identify("pk1", mode=1) returns only (model, id) -- NO alt
        # (Pitfall 11); alt-conf atoms SHARE ids with originals (Pitfall 10),
        # so id alone can't distinguish a real-trace click from an alt-conf
        # hider click. iterate exposes alt + resv (editing.py:1444-1449; ID is
        # UPPERCASE -- the lowercase builtin yields NameError or a wrong value;
        # resv is the numeric residue value). Hygienic space= dict (AGENTS.md:
        # never the bare None default, which pollutes global pymol.__dict__).
        props = []
        cmd.iterate("pk1", "stored.append((model, ID, alt, resv))",
                    space={'stored': props})
        cmd.unpick()                           # clear pk1 for next pick
        if not props:
            return
        model, aid, alt, resv = props[0]
        if model != self.target_object:
            # clicked a non-target object -- miss, no-op (LOOP-01: no harm)
            return
        self.controller.on_pick(aid, alt=alt, resv=resv)
        cmd.refresh_wizard()

    def do_select(self, name):
        # Selection-mode entry point (canonical pattern: pymol.wizard.measurement
        # .do_select). In the default 3-Button Viewing preset left-click is
        # cButModeSeleSet, so the C layer (SceneMouse.cpp:337-356) creates "sele"
        # + WizardDoSelect -- NOT "pk1" + WizardDoPick. do_pick therefore never
        # fires unless the user is in a Picking button mode. Re-route selection
        # clicks by building pk1 from the just-created selection, cleaning it up
        # (the C layer recreates "sele" on the next click), and dispatching
        # through do_pick. This preserves left-drag rotation (essential for
        # spin-to-find) and works in any selection button mode without fragile
        # button-mode save/restore. mouse_selection_mode=0 (set in __init__)
        # guarantees the selection is exactly one atom -- the clicked hider.
        cmd.unpick()
        cmd.select("pk1", name)   # pk1 = the clicked atom
        cmd.delete(name)          # clean up "sele"; C layer recreates it next click
        self.do_pick(0)

    def activate(self):
        self._saved_wizard = cmd.get_wizard()   # None if no wizard active
        cmd.set_wizard(self)

    def deactivate(self):
        cmd.set_wizard(self._saved_wizard)       # restore (or clear if None)
        cmd.set("mouse_selection_mode", self._saved_selection_mode)

    def get_panel(self):
        return [[1, 'bioCHEMeleon', ''],
                [2, 'Done (quit game)', 'cmd.get_wizard().deactivate()']]
