# vmd/gui/dialog.tcl -- Phase 14 GUI layer: the dialog proc (extracted from the
# Phase 13 entry). Creates the modeless toplevel + ttk::notebook (Setup + Game
# tabs), sources BOTH tab modules, and calls their build procs to populate the
# tabs. Tk/ttk (NOT pure). Sourced by the entry (vmd/biochemeleon.tcl).
#
# Namespace: ::biochemeleon (open_dialog + the BTN-07 Start handler on_start
# + the WM_DELETE_WINDOW handler on_close live here; they use the namespace-
# scope `w` variable declared by the entry's `namespace eval ::biochemeleon`).
# Proc resolution is at CALL-TIME in tcl, so defining open_dialog here + calling
# it from the entry's public `biochemeleon` proc / `biochemeleon_tk_cb` works
# even though the entry no longer defines open_dialog itself.
#
# Tcl 8.5.6: uses foreach+lappend + catch (no 8.6 control-flow idioms).
#
# KEY (14-02 lesson): [info script] is DYNAMIC (call-time context, NOT
# definition-time file). The `source setup_tab.tcl` / `source game_tab.tcl`
# lines below run at the TOP LEVEL of this file (during dialog.tcl's own
# source), where [info script] IS this file's path -- so they resolve the tab
# modules correctly. They must NOT be moved inside open_dialog's proc body
# (there [info script] would be empty when called from the console/menu ->
# the tab modules would not be found).

# ---------------------------------------------------------------------------
# Source the tab modules ONCE each at load time (top-level sources; [info
# script] = this file's path here). These define ::biochemeleon::setup_tab and
# ::biochemeleon::game_tab and their namespace variables. Sourced once; the
# builds are called later from open_dialog (Phase 16-10 wires the real Game
# tab, replacing the Phase 13 placeholder).
# ---------------------------------------------------------------------------
source [file join [file dirname [info script]] setup_tab.tcl]
source [file join [file dirname [info script]] game_tab.tcl]

# ---------------------------------------------------------------------------
# open_dialog -- the dialog proc (GUI; called by the console `biochemeleon`
# command and the `biochemeleon_tk_cb` menu callback). Modeless ttk::notebook
# with Setup + Game tabs. NO modal grab on the main panel (ENTRY-01 -- a modal
# grab blocks the 3D viewer for click-to-find). Singleton re-show via
# `winfo exists` + `wm deiconify` (the 4-plugin pattern: viewmaster.tcl:66-69,
# autoionizegui.tcl:46-49, ramaplot.tcl:125-128, mergestructs.tcl:44-47).
#
# Phase 16: populates the Setup tab via setup_tab::build AND the Game tab via
# game_tab::build (eager -- the Phase 13 placeholder is gone; 16-RESEARCH-gametab
# SS2.1: the tab is cheap to build and no after-chain exists until Start). The
# WM_DELETE_WINDOW handler (::biochemeleon::on_close, defined below) preserves
# in-progress edits + cleans up the refresh trace, the Game-tab timers, and the
# pick bridge on close. The BTN-07 Start handler (::biochemeleon::on_start,
# defined below) fans the Setup form into the game controller + Game tab.
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

    # Game tab: populated by the Game-tab module (Phase 16-10 wiring; the
    # Phase 13 placeholder label is gone). Eager build -- see the header note.
    ::biochemeleon::game_tab::build $nb.game

    pack $nb -fill both -expand yes

    # Wire the window-manager close (X button) to ::biochemeleon::on_close so
    # in-progress edits are preserved and the refresh trace is cleaned up.
    wm protocol $w WM_DELETE_WINDOW ::biochemeleon::on_close
}

# ---------------------------------------------------------------------------
# on_close -- the WM_DELETE_WINDOW handler (Plan 04; extended by Plan 16-10).
# Preserves any in-progress (un-applied) edits by snapshotting the widgets via
# collect_state + persisting the result to ::biochemeleon::state setup, so
# close+reopen keeps the user's form. (collect_state itself only RETURNS the
# dict; apply_state is what persists on action buttons, so on_close persists
# explicitly here.) Cleans up the molecule-menu refresh trace -- a leaked trace
# fires on later mol add/delete and touches a destroyed widget. Phase 16-10:
# BEFORE destroying the dialog, stop every Game-tab timer (after-ids outlive
# widgets -- a leaked tick/countdown/win-box callback would touch a destroyed
# widget path or re-arm forever) and deactivate the pick bridge (a leaked pick
# trace keeps scoring picks on a closed dialog, and the user's mouse mode must
# be restored -- research pick Pitfall 13). All steps are catch-guarded so a
# half-built form, an already-absent trace, or a never-started game can't
# error. Then destroys the toplevel. NO blocking grab anywhere -- the viewer
# stays interactive.
# ---------------------------------------------------------------------------
proc ::biochemeleon::on_close {} {
    variable w
    # Preserve in-progress edits (collect_state returns the widget snapshot;
    # persist it to the entry's state dict so close+reopen keeps them).
    if {![catch {::biochemeleon::setup_tab::collect_state} snapshot]} {
        catch {dict set ::biochemeleon::state setup $snapshot}
    }
    # Clean up the refresh trace (no-op if absent). vmd_molecule is a VMD global;
    # `global` resolves it so the delete targets the same trace build registered.
    global vmd_molecule
    catch {trace vdelete vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu}
    # Phase 16-10: stop all Game-tab timers (tick + countdown + delayed win box)
    # and tear down the pick bridge (trace removal + user mouse-mode restore +
    # click-label cleanup) BEFORE the destroy. Both are no-ops when no round
    # was ever started; catch-guarded so an absent namespace state can't abort
    # the close.
    catch {::biochemeleon::game_tab::stop_all_timers}
    catch {::biochemeleon::pick_bridge::deactivate}
    destroy $w
}
