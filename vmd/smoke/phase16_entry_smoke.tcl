# vmd/smoke/phase16_entry_smoke.tcl
# Headless LOAD-GATE smoke for Phase 16-10 (entry wiring -- the integration
# plan that makes the loop reachable from the GUI).
#
# Tk does NOT load under -dispdev text, so open_dialog is NEVER called and no
# widget code runs. This script proves the LOADING + INTEGRATION layer only
# (the 15-04/16-09 load-gate pattern, applied to the FULL entry):
#   0. bypass the re-source guard (loaded 0 BEFORE the source);
#   1. the ENTRY ITSELF sources clean under text mode -- every module in the
#      new Phase-16 order (generators + game_logic in the pure block; hiders +
#      pick_bridge in the mol block; registry still exactly once) loads, all
#      guards behave, and no Tk command executes at source time;
#   2. the proc surface exists across the whole stack (the Phase-16 modules,
#      the dialog-scope on_start, and all 11 game_tab procs);
#   3. the entry's source ORDER is structurally asserted (read the entry text:
#      each module's source line appears after the previous one; dialog last);
#   4. registry.tcl is sourced EXACTLY ONCE (structural: exactly one source
#      line in the entry + no lib file re-sources it; functional: reconstruct
#      -> count -> reset -> reconstruct -> count survives the full entry load);
#   5. Phase-15 regression through the PUBLIC API (now sourced BY THE ENTRY --
#      proves the new order): load 1k8p (555 atoms) -> start_game 5 -> 560
#      atoms, 5 sentinels, count_hiders 5, numreps grew by 2 -> cleanup ->
#      555 atoms, count_hiders 0, game_molid DELETED.
# The full Start -> countdown -> pick loop is verified at the 16-12 GUI
# human-verify checkpoint (Tk does not load in text mode).
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here, so use [pwd]
# (VMD cwd = staging root) to locate the entry (the verified Phase 13+
# pattern). VMD does NOT propagate tcl exit codes -- the WSL runner greps the
# BCHM_SMOKE_RESULT marker line, NEVER $?. ALWAYS read the FULL smoke output,
# not just the marker -- a mid-script error does NOT prevent the marker from
# printing a false PASS (14-02 lesson); the runner also scans for ERROR) and
# "bad switch" (the 15-05 post-verify lesson).
#
# Tcl 8.5 only. Every atomselect is $sel delete'd (Pitfall 3 -- atomselect
# leaks; a dangling selection on a deleted molecule returns STALE data
# silently).

set failures [list]
set root [pwd]

# ---------------------------------------------------------------------------
# 0. Bypass the re-source guard: the entry stops itself when ::biochemeleon::
#    loaded is already 1. Set it to 0 BEFORE sourcing so the body runs (the
#    15-04/16-09 load-gate pattern). The entry's own namespace eval then sets
#    loaded 1 -- asserted in step 2.
# ---------------------------------------------------------------------------
namespace eval ::biochemeleon { variable loaded 0 }

# ---------------------------------------------------------------------------
# 1. Source the ENTRY (the integration point under test). The entry sources,
#    in order: setup_state, registry, generators, game_logic (pure block) ->
#    demos, backup, mutation, hiders, game, pick_bridge (mol block) ->
#    gui/dialog.tcl (which sources setup_tab.tcl + game_tab.tcl at its own
#    top level). Must source clean under -dispdev text.
# ---------------------------------------------------------------------------
set entryf [file join $root vmd biochemeleon.tcl]
if {![file exists $entryf]} {
    lappend failures "missing_entry:$entryf"
} elseif {[catch {source $entryf} err]} {
    lappend failures "source_error:entry:$err"
}

# ---------------------------------------------------------------------------
# 2. The entry body ran: the loaded flag is back to 1 (the namespace eval
#    re-initialized it past the bypass).
# ---------------------------------------------------------------------------
if {![info exists ::biochemeleon::loaded] || !$::biochemeleon::loaded} {
    lappend failures "entry_loaded_flag:exp=1"
}

# ---------------------------------------------------------------------------
# 3. Proc existence across the whole sourced stack (zero widget commands ran
#    -- a sourcing error here IS the failure). Pure modules, mol bridges,
#    controller, dialog-scope handlers, setup_tab, and ALL 11 game_tab procs.
# ---------------------------------------------------------------------------
foreach p {::biochemeleon::generators::sphere_positions
           ::biochemeleon::game_logic::begin_play
           ::biochemeleon::hiders::add_hider_reps
           ::biochemeleon::pick_bridge::activate
           ::biochemeleon::pick_bridge::deactivate
           ::biochemeleon::game::start_game
           ::biochemeleon::game::on_pick
           ::biochemeleon::game::cleanup
           ::biochemeleon::on_start
           ::biochemeleon::open_dialog
           ::biochemeleon::on_close
           ::biochemeleon::setup_tab::collect_state} {
    if {[llength [info procs $p]] == 0} {
        lappend failures "no_proc:$p"
    }
}
# The entry's public wiring path (BTN-07): on_start must be non-empty.
if {[llength [info procs ::biochemeleon::on_start]] == 0} {
    lappend failures "on_start_missing"
}
if {![namespace exists ::biochemeleon::game_tab]} {
    lappend failures "no_game_tab_ns"
} else {
    foreach p {build start_round countdown_step tick on_log_line
               update_remaining on_win set_mouse_mode set_difficulty
               stop_all_timers raise_tab} {
        if {[llength [info procs ::biochemeleon::game_tab::$p]] == 0} {
            lappend failures "no_game_tab_proc:$p"
        }
    }
}

# ---------------------------------------------------------------------------
# 4a. Entry source ORDER, structurally (the order-matters truth): each module
#     source line must appear AFTER the previous one in the entry text, with
#     gui/dialog.tcl last. Search keys use the "<dir> <file>" source-join
#     form ("lib game.tcl" cannot false-match "lib game_logic.tcl").
# ---------------------------------------------------------------------------
set entry_src ""
if {![catch {open $entryf r} efh]} {
    set entry_src [read $efh]
    close $efh
} else {
    lappend failures "cannot_read_entry:$entryf"
}
if {$entry_src ne ""} {
    set prev -1
    foreach mod {setup_state registry generators game_logic demos
                 backup mutation hiders game pick_bridge} {
        set idx [string first "lib $mod.tcl" $entry_src]
        if {$idx < 0} {
            lappend failures "entry_no_source_line:$mod"
        } elseif {$idx <= $prev} {
            lappend failures "entry_order:$mod"
        } else {
            set prev $idx
        }
    }
    set didx [string first "gui dialog.tcl" $entry_src]
    if {$didx < 0 || $didx <= $prev} {
        lappend failures "entry_order:dialog_last"
    }
}

# ---------------------------------------------------------------------------
# 4b. registry.tcl sourced EXACTLY ONCE. Structural: exactly ONE source line
#     naming the registry in the entry, and NO lib module re-sources it (a
#     re-source would WIPE a populated _records dict -- line-scoped match so
#     comment mentions do not count). Functional backstop follows in 4c.
# ---------------------------------------------------------------------------
if {$entry_src ne ""} {
    set nreg 0
    foreach line [split $entry_src "\n"] {
        set t [string trim $line]
        # Trailing * -- a source line ends with the join's closing bracket.
        if {[string match "source*registry.tcl*" $t]} { incr nreg }
    }
    if {$nreg != 1} {
        lappend failures "registry_source_count:exp=1 got=$nreg"
    }
    foreach lib {demos backup mutation hiders game pick_bridge
                 generators game_logic} {
        set lf [file join $root vmd lib $lib.tcl]
        if {[catch {open $lf r} lfh]} {
            lappend failures "cannot_read_lib:$lib"
        } else {
            set lsrc [read $lfh]
            close $lfh
            foreach line [split $lsrc "\n"] {
                set t [string trim $line]
                if {[string match "source*registry.tcl*" $t]} {
                    lappend failures "lib_re_sources_registry:$lib"
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 4c. Registry functional round trip AFTER the full entry load (indirect
#     exactly-once check -- a duplicate namespace init that wiped state would
#     break this): reconstruct (DI fetch proc) -> count 3 -> reset -> count 0
#     -> reconstruct again -> count 3 -> reset.
# ---------------------------------------------------------------------------
proc ::BCHM_E_FETCH_IDS {} { return [list 7 8 9] }
if {[catch {
    ::biochemeleon::registry::reconstruct_from_sentinels ::BCHM_E_FETCH_IDS
    if {[::biochemeleon::registry::count_hiders] != 3} {
        error "count1 [::biochemeleon::registry::count_hiders] ne 3"
    }
    if {![::biochemeleon::registry::is_hider 8]} {
        error "is_hider 8 false after reconstruct"
    }
    ::biochemeleon::registry::reset
    if {[::biochemeleon::registry::count_hiders] != 0} {
        error "count2 [::biochemeleon::registry::count_hiders] ne 0"
    }
    ::biochemeleon::registry::reconstruct_from_sentinels ::BCHM_E_FETCH_IDS
    if {[::biochemeleon::registry::count_hiders] != 3} {
        error "count3 [::biochemeleon::registry::count_hiders] ne 3"
    }
    ::biochemeleon::registry::reset
} err]} {
    lappend failures "registry_roundtrip:$err"
}

# ---------------------------------------------------------------------------
# 5. Phase-15 regression through the PUBLIC API -- the lib files are now
#    sourced BY THE ENTRY in the new order, so this proves the pipeline end
#    to end: load 1k8p (555 atoms) -> start_game 5 hiders -> 560 atoms, 5
#    sentinels (canonical selector), count_hiders 5, numreps grew by exactly
#    2 (the hider-rep step, research SS5.5) -> cleanup -> 555 atoms,
#    count_hiders 0, game_molid DELETED (leak guard).
# ---------------------------------------------------------------------------
set m -1
set game_molid -1
set gs [dict create]
if {[catch {::biochemeleon::demos::load_demo 1k8p} m]} {
    lappend failures "load_demo:$m"
} else {
    set n0 [molinfo $m get numatoms]
    if {$n0 != 555} { lappend failures "orig_atoms:exp=555 got=$n0" }
    set pre_reps [molinfo $m get numreps]
    if {![catch {::biochemeleon::game::start_game $m 5} gs]} {
        if {[catch {dict get $gs game_molid} game_molid]} {
            lappend failures "gs_key_game_molid:missing (gs=$gs)"
        } else {
            # 555 + 5 = 560 atoms on the combined (PDB-rebuilt) molecule.
            set n1 [molinfo $game_molid get numatoms]
            if {$n1 != 560} { lappend failures "game_atoms:exp=560 got=$n1" }
            # Exactly 5 sentinels via the canonical selector (NEVER
            # 'beta < 0' alone -- resname GAM is the hider partition).
            if {![catch {atomselect $game_molid "resname GAM and beta < 0"} sel]} {
                if {[$sel num] != 5} {
                    lappend failures "sentinel_count:exp=5 got=[$sel num]"
                }
                $sel delete
            } else {
                lappend failures "sentinel_sel:$sel"
            }
            # Registry reconstructed from the sentinels inside start_game.
            set ch [::biochemeleon::registry::count_hiders]
            if {$ch != 5} { lappend failures "registry_count:exp=5 got=$ch" }
            # numreps grew by EXACTLY 2 (hidden + found hider reps added
            # after backup::apply).
            set post_reps [molinfo $game_molid get numreps]
            if {$post_reps != $pre_reps + 2} {
                lappend failures \
                    "hider_reps_added:exp=[expr {$pre_reps + 2}] got=$post_reps"
            }
        }
    } else {
        lappend failures "start_game:$gs"
    }
    if {$game_molid >= 0} {
        if {![catch {::biochemeleon::game::cleanup $gs} restored]} {
            set n2 [molinfo $restored get numatoms]
            if {$n2 != 555} {
                lappend failures "restored_atoms:exp=555 got=$n2"
            }
            set ch2 [::biochemeleon::registry::count_hiders]
            if {$ch2 != 0} {
                lappend failures "registry_after_cleanup:exp=0 got=$ch2"
            }
            # The LIVE game_molid was DELETED (if still alive, restore
            # deleted the wrong molid -> leak, the false-pass guard).
            if {![catch {molinfo $game_molid get numatoms} ghost]} {
                lappend failures "game_molid_leaked:numatoms=$ghost"
            }
        } else {
            lappend failures "cleanup:$restored"
        }
    }
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
