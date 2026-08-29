# vmd/gui/dialog.tcl -- Phase 14 GUI layer: the dialog proc (extracted from the
# Phase 13 entry). Creates the modeless toplevel + ttk::notebook (Setup + Game
# tabs), sources the Setup-tab module, and calls setup_tab::build to populate
# the Setup tab. Tk/ttk (NOT pure). Sourced by the entry (vmd/biochemeleon.tcl).
#
# Namespace: ::biochemeleon (open_dialog lives here; it uses the namespace-
# scope `w` variable declared by the entry's `namespace eval ::biochemeleon`).
# Proc resolution is at CALL-TIME in tcl, so defining open_dialog here + calling
# it from the entry's public `biochemeleon` proc / `biochemeleon_tk_cb` works
# even though the entry no longer defines open_dialog itself.
#
# Tcl 8.5.6: uses foreach+lappend + catch (no 8.6 control-flow idioms).
#
# KEY (14-02 lesson): [info script] is DYNAMIC (call-time context, NOT
# definition-time file). The `source setup_tab.tcl` line below runs at the TOP
# LEVEL of this file (during dialog.tcl's own source), where [info script] IS
# this file's path -- so it resolves setup_tab.tcl correctly. It must NOT be
# moved inside open_dialog's proc body (there [info script] would be empty
# when called from the console/menu -> setup_tab.tcl would not be found).

# ---------------------------------------------------------------------------
# Source the Setup-tab module ONCE at load time (top-level source; [info script]
# = this file's path here). This defines ::biochemeleon::setup_tab and its
# namespace variables. Sourced once; build is called later from open_dialog.
# ---------------------------------------------------------------------------
source [file join [file dirname [info script]] setup_tab.tcl]

# ---------------------------------------------------------------------------
# open_dialog -- the dialog proc (GUI; called by the console `biochemeleon`
# command and the `biochemeleon_tk_cb` menu callback). Modeless ttk::notebook
# with Setup + Game tabs. NO modal grab on the main panel (ENTRY-01 -- a modal
# grab blocks the 3D viewer for click-to-find). Singleton re-show via
# `winfo exists` + `wm deiconify` (the 4-plugin pattern: viewmaster.tcl:66-69,
# autoionizegui.tcl:46-49, ramaplot.tcl:125-128, mergestructs.tcl:44-47).
#
# Phase 14: populates the Setup tab via setup_tab::build (replacing the Phase 13
# placeholder). NO WM_DELETE_WINDOW handler yet -- Plan 04 adds it (it calls
# collect_state + trace vdelete which reference Plan 04 callbacks).
# ---------------------------------------------------------------------------
proc ::biochemeleon::open_dialog {} {
    variable w
    if {[winfo exists .biochemeleon]} { wm deiconify $w; return }   ;# singleton re-show
    set w [toplevel .biochemeleon]
    wm title $w "bioCHEMeleon"

    set nb [ttk::notebook $w.nb]
    ttk::frame $nb.setup
    ttk::frame $nb.game
    $nb add $nb.setup -text "Setup"
    $nb add $nb.game  -text "Game"

    # Setup tab: populated by the Setup-tab module (all 4 groups + state plumbing).
    ::biochemeleon::setup_tab::build $nb.setup

    # Game tab: keep the Phase 13 placeholder (Phase 16 populates it).
    ttk::label $nb.game.placeholder -text "Game tab (Phase 16)"
    pack $nb.game.placeholder -padx 20 -pady 20

    pack $nb -fill both -expand yes
}
