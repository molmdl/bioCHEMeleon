# vmd/biochemeleon.tcl -- Phase 13 entry.
# Sourced form: re-source guard + namespace + package provide + source lib/*.tcl
# + open_dialog (ttk::notebook Setup+Game) + global biochemeleon proc +
# biochemeleon_tk_cb + vmd_install_extension. Mirrors pymol/biochemeleon/__init__.py.
#
# Sourcing this file DEFINES the `biochemeleon` command and registers the
# Extensions-menu item (GUI mode only); it does NOT auto-open the dialog.
# The user runs `biochemeleon` (or clicks the menu item) to open the dialog.
# This keeps headless sourcing silent and lets .vmdrc users opt in.
#
# Adapted from the verified skeleton in
# .planning/phases/13-bootstrap-sourced-entry/13-RESEARCH-entry.md (lines 80-144),
# with two plan-time corrections: (1) source BOTH lib/setup_state.tcl AND
# lib/registry.tcl (the research skeleton only sourced setup_state.tcl), and
# (2) the menu path is "Visualization/bioCHEMeleon" (NOT "Extensions/bioCHEMeleon"
# which would double-nest an Extensions submenu inside the Extensions menu).
# Namespace is ::biochemeleon::setup_state (NOT ::biochemeleon::setup) -- matches
# 13-01 and v1's setup_state.py filename.

# ---------------------------------------------------------------------------
# (1) Re-source guard -- MUST run BEFORE the namespace eval body.
# `info exists ::biochemeleon::loaded` is SAFE on a not-yet-created namespace
# (returns 0, no error). `return` at the top level of a sourced file
# terminates the source cleanly (standard tcl early-exit idiom).
# The literal PITFALLS.md pattern (variable loaded 0 INSIDE namespace eval,
# then check after) is BUGGY: `variable loaded 0` re-initializes on every
# source so the check always sees 0. The guard must precede the reset.
# ---------------------------------------------------------------------------
if {[info exists ::biochemeleon::loaded] && $::biochemeleon::loaded} {
    vmdcon -warn "bioCHEMeleon already loaded; ignoring re-source"
    return
}

# ---------------------------------------------------------------------------
# (2) Namespace + state. Variable initializers run only once thanks to the
# guard above (the guard stops re-entry before this body re-initializes).
# `w` is the toplevel handle (namespace scope = GC prevention, matching the
# viewmaster/ramaplot reference pattern). `state` holds the game state dict;
# guarded init so a re-source (if the guard were ever bypassed) doesn't reset.
# ---------------------------------------------------------------------------
namespace eval ::biochemeleon {
    variable version 2.0
    variable loaded  1            ;# set on first load; the guard above stops re-entry
    variable w                     ;# toplevel handle (namespace scope = GC prevention)
    variable state                 ;# game state -- init only if not already set
    if {![info exists state]} {
        set state [dict create timer 0 found [list] setup [dict create]]
    }
    namespace export biochemeleon
}

# ---------------------------------------------------------------------------
# (3) package provide BEFORE vmd_install_extension so its internal
# `package require biochemeleon` is a no-op (no pkgIndex.tcl needed for the
# sourced form). This keeps the door open for the optional packaged-install
# form (vmd/pkgIndex.tcl) while the sourced form works standalone.
# Matches viewmaster.tcl:26 (`package provide ViewMaster 2.6` at top level).
# ---------------------------------------------------------------------------
package provide biochemeleon $::biochemeleon::version

# ---------------------------------------------------------------------------
# (4) Source the pure layer (BOTH files -- 13-01 created both).
# `[file dirname [info script]]` works because this entry is always SOURCED
# (by the smoke, by .vmdrc, by the user), never -e'd directly in tests, so
# [info script] is correctly set inside it (Pitfall 3 in 13-RESEARCH-testing.md).
# NOTE: the 13-RESEARCH-entry.md skeleton only sourced setup_state.tcl; this
# plan ADDS the registry.tcl line (13-01 created both pure-layer files).
# Use ::biochemeleon::setup_state (NOT ::biochemeleon::setup) -- locked decision.
# ---------------------------------------------------------------------------
set _dir [file dirname [info script]]
source [file join $_dir lib setup_state.tcl]
source [file join $_dir lib registry.tcl]
unset _dir

# ---------------------------------------------------------------------------
# (5) open_dialog -- the dialog proc (GUI; called by both the console command
# and the _tk_cb callback). Modeless ttk::notebook with Setup + Game tabs.
# Singleton re-show via `winfo exists` + `wm deiconify` (the 4-plugin pattern:
# viewmaster.tcl:66-69, autoionizegui.tcl:46-49, ramaplot.tcl:125-128,
# mergestructs.tcl:44-47). NO `grab set` on the main dialog (ENTRY-01 hard
# constraint -- grab blocks the 3D viewer for click-to-find). `grab set` IS
# allowed on brief transient children (none in Phase 13). Phase 14/16
# populate the tabs; Phase 13 ships empty placeholders.
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

    # Placeholder content (Phase 13 ships empty tabs; Phase 14/16 populate them).
    ttk::label $nb.setup.placeholder -text "Setup tab (Phase 14)"
    ttk::label $nb.game.placeholder  -text "Game tab (Phase 16)"
    pack $nb.setup.placeholder -padx 20 -pady 20
    pack $nb.game.placeholder  -padx 20 -pady 20

    pack $nb -fill both -expand yes
}

# ---------------------------------------------------------------------------
# (6) Global biochemeleon proc -- the user-runnable console command (user
# types `biochemeleon` at the VMD console). tk_version-guarded: in headless
# mode (-dispdev text, no Tk) it prints a vmdcon -warn and returns cleanly
# (the graceful no-op that satisfies ROADMAP success criterion 3). In GUI
# mode it opens the dialog and returns the toplevel path. Mirrors the
# autoionize dual-proc pattern (autoionize.tcl:50) + ramaplot.tcl:109-111.
# ---------------------------------------------------------------------------
proc biochemeleon {args} {
    if {![info exists tk_version]} {
        vmdcon -warn "bioCHEMeleon: GUI requires Tk (not available in -dispdev text)."
        return
    }
    ::biochemeleon::open_dialog
    return $::biochemeleon::w
}

# ---------------------------------------------------------------------------
# (7) biochemeleon_tk_cb -- the Extensions-menu callback. Takes NO args,
# returns the toplevel widget path (VMD tracks open/close by this path --
# verified across 4 reference plugins: clonerep.tcl:237-240,
# viewmaster.tcl:1087-1090, ramaplot.tcl:663-666, mergestructs.tcl:992-995).
# ---------------------------------------------------------------------------
proc biochemeleon_tk_cb {} {
    ::biochemeleon::open_dialog
    return $::biochemeleon::w
}

# ---------------------------------------------------------------------------
# (8) Register in the Extensions menu (GUI mode only). The `if {[info exists
# tk_version]}` guard skips the call in headless mode so text-mode sourcing
# is silent (menu tk register needs Tk; without the guard it would print
# "The biochemeleon window could not be created" noise -- caught internally
# so it wouldn't crash, but the guard keeps it quiet). The inner
# `info commands vmd_install_extension` check defends against a bare tclsh
# (where the VMD command doesn't exist). Menu path = "Visualization/bioCHEMeleon"
# (locked decision #2 -- matches clonerep/viewmaster; NOT "Extensions/bioCHEMeleon"
# which double-nests). Sourcing does NOT auto-open (locked decision #3).
# ---------------------------------------------------------------------------
if {[info exists tk_version]} {
    if {[llength [info commands vmd_install_extension]]} {
        vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"
    }
}
# Sourcing does NOT auto-open the dialog -- the user runs `biochemeleon`
# or clicks the Extensions -> Visualization -> bioCHEMeleon menu item.
