# vmd/smoke/phase13_smoke.tcl
# Headless smoke for Phase 13: source the entry, assert `biochemeleon` exists,
# call it (no-op headless), assert the pure-layer namespaces loaded.
# This script is `-e`'d by VMD -- [info script] is EMPTY here (Pitfall 3 in
# 13-RESEARCH-testing.md), so use [pwd] (VMD cwd = staging root) to locate
# the entry, then `source` it. The entry's [info script] then works correctly
# because it was `source`d (not `-e`d). This is the verified pattern; do NOT
# change it.
#
# VMD does NOT propagate tcl exit codes (Pitfall 4) -- the WSL runner greps
# the BCHM_SMOKE_RESULT marker line, NEVER $? (VMD always exits 0).

set failures [list]

# 1. Locate + source the entry. [pwd] = staging root (verified by probe;
#    13-RESEARCH-testing.md V9: VMD's [pwd] = Windows path of the WSL cwd).
set entry [file join [pwd] vmd biochemeleon.tcl]
if {![file exists $entry]} {
    lappend failures "entry_not_found:$entry"
} elseif {[catch {source $entry} err]} {
    lappend failures "source_error:$err"
}

# 2. Assert `biochemeleon` command exists (info commands).
if {[llength [info commands biochemeleon]] == 0} {
    lappend failures "no_biochemeleon_cmd"
}

# 3. Call biochemeleon headless -- MUST no-op gracefully (GUI is tk_version-guarded).
#    The global biochemeleon proc prints a vmdcon -warn and returns when tk_version
#    is absent (headless mode). catch returns 0 on clean return, 1 on error.
if {![catch {biochemeleon} err]} {
    # success (no-op headless)
} else {
    lappend failures "biochemeleon_call_error:$err"
}

# 4. Assert the pure-layer namespace loaded (entry sourced lib/setup_state.tcl).
if {![namespace exists ::biochemeleon::setup_state]} {
    lappend failures "no_setup_state_ns"
}

# 5. Assert registry namespace loaded too (entry sourced lib/registry.tcl).
if {![namespace exists ::biochemeleon::registry]} {
    lappend failures "no_registry_ns"
}

# Report. VMD does NOT propagate tcl exit codes (Pitfall 4) -- use a marker line.
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
