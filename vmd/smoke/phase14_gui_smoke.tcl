# vmd/smoke/phase14_gui_smoke.tcl
# Headless smoke for Phase 14-03: source the entry (which now sources
# setup_state + registry + demos + gui/dialog + gui/setup_tab) and assert the
# LOADING layer is intact -- all GUI namespaces + key procs exist. Tk does NOT
# load in -dispdev text, so the GUI is NOT built here (open_dialog / build are
# NOT called); widget rendering is verified in Plan 04's GUI human-verify
# checkpoint.
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here (Pitfall 3 in
# 13-RESEARCH-testing.md), so use [pwd] (VMD cwd = staging root) to locate the
# entry, then `source` it. The entry's [info script] then works correctly
# because it was `source`d (not `-e`d). This is the verified Phase 13+ pattern.
#
# VMD does NOT propagate tcl exit codes (Pitfall 4) -- the WSL runner greps the
# BCHM_SMOKE_RESULT marker line, NEVER $? (VMD always exits 0). Always read the
# FULL smoke output, not just the marker -- a mid-script error does NOT
# prevent the marker from printing a false PASS (14-02 lesson).

set failures [list]

# 1. Locate + source the entry. [pwd] = staging root.
set entry [file join [pwd] vmd biochemeleon.tcl]
if {![file exists $entry]} {
    lappend failures "entry_not_found:$entry"
} elseif {[catch {source $entry} err]} {
    lappend failures "source_error:$err"
}

# 2. Assert `biochemeleon` command exists (info commands) -- the public proc
#    defined in the entry.
if {[llength [info commands biochemeleon]] == 0} {
    lappend failures "no_biochemeleon_cmd"
}

# 3. Assert `::biochemeleon::open_dialog` proc exists -- extracted to
#    gui/dialog.tcl (Plan 14-03) and sourced by the entry.
if {[llength [info procs ::biochemeleon::open_dialog]] == 0} {
    lappend failures "no_open_dialog_proc"
}

# 4. Assert the pure-layer namespace loaded (entry sourced lib/setup_state.tcl).
if {![namespace exists ::biochemeleon::setup_state]} {
    lappend failures "no_setup_state_ns"
}

# 5. Assert the registry namespace loaded (entry sourced lib/registry.tcl).
if {![namespace exists ::biochemeleon::registry]} {
    lappend failures "no_registry_ns"
}

# 6. Assert the mol-bridge namespace loaded (entry sourced lib/demos.tcl, Plan 02).
if {![namespace exists ::biochemeleon::demos]} {
    lappend failures "no_demos_ns"
}

# 7. Assert the Setup-tab namespace loaded (dialog.tcl sourced setup_tab.tcl).
if {![namespace exists ::biochemeleon::setup_tab]} {
    lappend failures "no_setup_tab_ns"
}

# 8/9/10. Assert the key setup_tab procs exist (build / collect_state / apply_state).
foreach p {build collect_state apply_state switch_page} {
    if {[llength [info procs ::biochemeleon::setup_tab::$p]] == 0} {
        lappend failures "no_setup_tab_proc:$p"
    }
}

# 11. Pure-layer spot-check (Plan 01 logic intact): validate_state on an empty
#    dict returns a dict with the `format` key (DEFAULTS filled). Guards against
#    an accidental regression in the pure layer sourced by the entry.
if {![catch {
    set v [::biochemeleon::setup_state::validate_state [dict create]]
}]} {
    if {![dict exists $v format]} {
        lappend failures "validate_state_no_format_key"
    }
} else {
    lappend failures "validate_state_error"
}

# Report. VMD does NOT propagate tcl exit codes (Pitfall 4) -- use a marker line.
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
