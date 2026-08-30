# vmd/smoke/phase16_gametab_smoke.tcl
# Headless LOAD-GATE smoke for Phase 16-09 (Game tab view).
#
# Tk does NOT load under -dispdev text, so the GUI is NOT built here (build /
# start_round are NEVER called; after-callbacks never fire). This script
# proves the LOADING layer only:
#   1. the pure deps the tab calls at runtime (setup_state, registry,
#      game_logic) + game_tab.tcl itself source CLEAN under text mode;
#   2. all 11 game_tab procs exist (zero widget commands ran at source --
#      a sourcing error here IS the failure);
#   3. the pure-layer round trip the tab depends on still works (game_logic
#      full countdown sequence + frozen-elapsed win, format_remaining exact
#      string, registry reconstruct + count_remaining round trip);
#   4. the four widget-bound variables are UNSET at source time (they are
#      initialized only by build -- proving no widget code ran at source);
#   5. game_tab.tcl contains no direct "mouse mode" / "vwait" / "grab set"
#      strings (the tab reaches the viewer ONLY through pick_bridge).
# Widget rendering is deferred to the 16-12 GUI human-verify checkpoint.
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here, so use [pwd]
# (VMD cwd = staging root) to locate the files (the verified Phase 13+
# pattern). VMD does NOT propagate tcl exit codes -- the WSL runner greps
# the BCHM_SMOKE_RESULT marker line, NEVER $?. ALWAYS read the FULL smoke
# output, not just the marker -- a mid-script error does NOT prevent the
# marker from printing a false PASS (14-02 lesson); the runner also scans
# for ERROR) and "bad switch".

set failures [list]
set root [pwd]

# ---------------------------------------------------------------------------
# 1. Source the pure deps the tab calls at runtime + the tab itself.
#    Sourcing must not error under -dispdev text.
# ---------------------------------------------------------------------------
foreach mod {setup_state registry game_logic} {
    set f [file join $root vmd lib $mod.tcl]
    if {![file exists $f]} {
        lappend failures "missing_lib:$mod"
    } elseif {[catch {source $f} err]} {
        lappend failures "source_error:$mod:$err"
    }
}
set tabf [file join $root vmd gui game_tab.tcl]
if {![file exists $tabf]} {
    lappend failures "missing_game_tab:$tabf"
} elseif {[catch {source $tabf} err]} {
    lappend failures "source_error:game_tab:$err"
}

# ---------------------------------------------------------------------------
# 2. Assert proc existence for all 11 game_tab procs.
# ---------------------------------------------------------------------------
if {![namespace exists ::biochemeleon::game_tab]} {
    lappend failures "no_game_tab_ns"
} else {
    set nprocs [llength [info procs ::biochemeleon::game_tab::*]]
    if {$nprocs < 11} {
        lappend failures "game_tab_proc_count_lt_11:$nprocs"
    }
    foreach p {build start_round countdown_step tick on_log_line
               update_remaining on_win set_mouse_mode set_difficulty
               stop_all_timers raise_tab} {
        if {[llength [info procs ::biochemeleon::game_tab::$p]] == 0} {
            lappend failures "no_game_tab_proc:$p"
        }
    }
}

# ---------------------------------------------------------------------------
# 3a. Pure-layer sanity: full game_logic round trip -- round_reset ->
#     begin_countdown -> the 4-tick sequence {"3" 0} {"2" 0} {"1" 0}
#     {"GO!" 1} -> begin_play -> finish_win (injected now = clock+65) ->
#     state "won" with the FROZEN elapsed 65.
# ---------------------------------------------------------------------------
if {[catch {
    ::biochemeleon::game_logic::round_reset
    ::biochemeleon::game_logic::begin_countdown
    foreach expect [list {3 0} {2 0} {1 0} {GO! 1}] {
        set t [::biochemeleon::game_logic::countdown_tick]
        if {$t ne $expect} { error "countdown_tick $t ne $expect" }
    }
    ::biochemeleon::game_logic::begin_play
    ::biochemeleon::game_logic::finish_win [expr {[clock seconds] + 65}]
    if {[::biochemeleon::game_logic::state] ne "won"} {
        error "state [::biochemeleon::game_logic::state] ne won"
    }
    if {[::biochemeleon::game_logic::timer_elapsed] != 65} {
        error "frozen elapsed [::biochemeleon::game_logic::timer_elapsed] ne 65"
    }
} err]} {
    lappend failures "game_logic_roundtrip:$err"
}

# ---------------------------------------------------------------------------
# 3b. Pure-layer sanity: format_remaining exact easy-mode string (GAME-03;
#     note the EXACTLY TWO spaces before the paren).
# ---------------------------------------------------------------------------
if {[catch {
    set fr [::biochemeleon::setup_state::format_remaining 3 [dict create VDW 3] 1]
}]} {
    lappend failures "format_remaining_error"
} else {
    if {$fr ne "Remaining: 3  (VDW: 3)"} {
        lappend failures "format_remaining_mismatch:$fr"
    }
}

# ---------------------------------------------------------------------------
# 3c. Pure-layer sanity: registry reconstruct + count_remaining round trip
#     (DI fetch prefix -> 3 hidden VDW records; the update_remaining inputs).
# ---------------------------------------------------------------------------
if {[catch {
    proc ::BCHM_GT_FETCH_IDS {} { return [list 11 12 13] }
    ::biochemeleon::registry::reconstruct_from_sentinels ::BCHM_GT_FETCH_IDS VDW
    if {[::biochemeleon::registry::count_remaining] != 3} {
        error "count_remaining [::biochemeleon::registry::count_remaining] ne 3"
    }
    set byrep [::biochemeleon::registry::remaining_by_rep]
    if {$byrep ne "VDW 3"} { error "remaining_by_rep '$byrep' ne 'VDW 3'" }
    if {![::biochemeleon::registry::is_hider 12]} { error "is_hider 12 false" }
} err]} {
    lappend failures "registry_roundtrip:$err"
}
catch {::biochemeleon::registry::reset}

# ---------------------------------------------------------------------------
# 4. The widget-bound variables initialize ONLY at build: they must be
#    UNSET at source time (proving no widget code ran at source). build is
#    never called in this smoke.
# ---------------------------------------------------------------------------
foreach v {w timer_text remain_text mode_text mouse_mode easy_mode} {
    if {[info exists ::biochemeleon::game_tab::$v]} {
        lappend failures "var_set_at_source:$v"
    }
}

# ---------------------------------------------------------------------------
# 5. game_tab.tcl must contain no direct "mouse mode" / "vwait" / "grab set"
#    strings (read the file here and string-match; case-sensitive -- the
#    labelframe TITLE "Mouse mode" is fine, the lowercase viewer-command
#    string is not). The tab reaches the viewer ONLY via pick_bridge.
# ---------------------------------------------------------------------------
if {![catch {open $tabf r} fh]} {
    set src [read $fh]
    close $fh
    foreach bad {"mouse mode" "vwait" "grab set"} {
        if {[string first $bad $src] >= 0} {
            lappend failures "forbidden_string:$bad"
        }
    }
} else {
    lappend failures "cannot_read_source:$tabf"
}

# ---------------------------------------------------------------------------
# Report. VMD does NOT propagate tcl exit codes -- use the marker line.
# ---------------------------------------------------------------------------
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
