# vmd/smoke/phase16_onpick_smoke.tcl
# Phase-16 (16-08) headless smoke: the on_pick scoring controller in game.tcl,
# driven through the REAL Phase-15/16 pipeline (game::start_game -> add the 2
# hider reps -> registry reconstruct) with RECORDING callbacks registered via
# game::set_callbacks ({lappend ::LOG_LOG} etc -- prove invocation, not just
# absence of error). Real picks cannot fire in text mode (vmd_pick_* globals
# absent -- STACK.md), so on_pick is CALLED DIRECTLY with known indices; the
# real-click path is the Phase-16 human-verify checkpoint (Plan 16-12).
#
# Proves the plan's 10 steps:
#   1.  start_game on 1k8p (555 atoms) + 5 hiders -> 560 atoms, 5 sentinels at
#       555-559, numreps grew by EXACTLY 2 over the pre-start value (the new
#       hider-rep step, research SS5.5), registry reconstructed (count 5),
#       game_state dict shape FROZEN {game_molid hider_count snapshot
#       per_rep} (the additive 17.1-06 4th key), and the namespace stash
#       (current_state) populated.
#   2.  Recording callbacks registered (log_cb ONE arg / remaining_cb ZERO
#       args / win_cb TWO args). remaining_cb is zero-arg, so its recorder is
#       an INCREMENT counter ({incr ::REM_TICKS} -- a zero-arg lappend would
#       never grow the list); log_cb/win_cb lappend into lists (win_cb's two
#       args land as TWO list elements per win).
#   3.  STATE GATE: with game_logic idle, on_pick 555 is a no-op -- nothing
#       logged, registry untouched (gametab SS6.10).
#   4.  Drive to playing: round_reset -> begin_countdown -> 4x countdown_tick
#       -> begin_play (timer uses the real clock -- fine).
#   5.  Miss: on_pick 0 (a real atom) -> "Miss!" logged, remaining still 5.
#   6.  Hit: on_pick 555 -> status "found", remaining 4, user2 > 0 (read-back,
#       FLOAT values -- numeric compare only, Pitfall 7), log "Found one! 4
#       remaining", remaining_cb fired once.
#   7.  Already-found: on_pick 555 again -> "Already found!", remaining still
#       4 (the caller-side registry guard, Pitfall 5), no extra remaining_cb.
#   8.  Win: pick 556..559 -> state "won", WINS has exactly ONE entry of TWO
#       elements (elapsed >= 0, hider_count 5), win log line "You found all 5
#       hiders in ...", remaining_cb fired 5 times total.
#   9.  Double-win prevention: on_pick 0 after win -> no new log, WINS still
#       one entry (state gate + finish_win's error-on-double).
#   10. cleanup -> registry 0, the stash CLEARED (dict size 0), the live
#       game_molid deleted (leak guard), a stale pick after cleanup is a
#       no-op with no error; 10b proves the stash guard directly: state
#       driven back to playing with the stash empty -> on_pick is STILL a
#       no-op (nothing logged) -- the empty-stash guard, independent of the
#       state gate.
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself -- avoids GUI/dialog baggage): setup_state, registry, generators,
# game_logic, rep_tiers (17.1-06 entry order -- game.tcl calls rep_tiers::*
# at CALL time), demos, backup, mutation, hiders, game. registry is sourced
# EXACTLY ONCE (re-sourcing would WIPE _records); demos + mutation re-source
# setup_state themselves (harmless constant re-init). pick_bridge is NOT
# sourced (on_pick is called directly; the bridge only forwards to it).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT propagate tcl
# exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD
# -e catches top-level errors and CONTINUES (possible false-PASS) -> every
# step is wrapped in catch + _bail, and the runner also scans the FULL log for
# ERROR) / bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set gs [list]
set gm -1
set pre_reps -1
set gs_ok 0
set playing_ok 0

# Recording-callback targets (globals -- the callbacks write into these).
# LOG_LOG/WINS are lists (1-arg / 2-arg lappends); REM_TICKS is a scalar
# invocation counter (remaining_cb is ZERO-arg -- {incr} is the only
# zero-arg-safe recorder).
set ::LOG_LOG [list]
set ::REM_TICKS 0
set ::WINS [list]

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's source order minus the
#      GUI files. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    generators   [file join [pwd] vmd lib generators.tcl] \
    game_logic   [file join [pwd] vmd lib game_logic.tcl] \
    rep_tiers    [file join [pwd] vmd lib rep_tiers.tcl] \
    demos        [file join [pwd] vmd lib demos.tcl] \
    backup       [file join [pwd] vmd lib backup.tcl] \
    mutation     [file join [pwd] vmd lib mutation.tcl] \
    hiders       [file join [pwd] vmd lib hiders.tcl] \
    game         [file join [pwd] vmd lib game.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# ---- 1. SETUP + START: load 1k8p (555 atoms), game::start_game with 5
#         hiders. The hider-rep step now runs INSIDE start_game (research
#         SS5.5) -- assert numreps grew by exactly 2 over the pre-start
#         value. 17.1-07: explicit VDW-only per_rep (the regression
#         baseline -- the 2-arg form now randomizes across implemented
#         tiers). ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }
    set pre_reps [molinfo $orig_molid get numreps]
    if {![catch {::biochemeleon::game::start_game $orig_molid 5 [dict create VDW 5] 0} gs]} {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            set gs_ok 1
            # 1a: 555 + 5 = 560 atoms on the combined molecule.
            set n1 [molinfo $gm get numatoms]
            if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
            # 1b: exactly 5 sentinels at 555-559 (canonical selector).
            if {![catch {atomselect $gm "resname GAM and beta < 0"} sel]} {
                if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
                if {[$sel get index] ne {555 556 557 558 559}} {
                    _bail sentinel_idx "got=[$sel get index]"
                }
                $sel delete
            } else { _bail sentinel_sel $sel }
            # 1c: numreps grew by EXACTLY 2 over the pre-start value (the
            #     hider-rep step added hidden+found after backup::apply) and
            #     is at least 2.
            set post_reps [molinfo $gm get numreps]
            if {$post_reps != $pre_reps + 2} {
                _bail hider_reps_added "exp=[expr {$pre_reps + 2}] got=$post_reps"
            }
            if {$post_reps < 2} { _bail reps_min2 "got=$post_reps" }
            # 1d: registry reconstructed from the sentinels (count 5).
            set ch [::biochemeleon::registry::count_hiders]
            if {$ch != 5} { _bail registry_count "exp=5 got=$ch" }
            # 1e: game_state dict shape FROZEN (keys in insertion order;
            #     17.1-06 added the per_rep key -- 4 keys total).
            if {[dict keys $gs] ne "game_molid hider_count snapshot per_rep"} {
                _bail gs_shape "got=[dict keys $gs]"
            }
            # 1f: the namespace stash is populated (4 keys, same shape).
            if {[dict size $::biochemeleon::game::current_state] != 4} {
                _bail stash_populated "exp=4 got=[dict size $::biochemeleon::game::current_state]"
            }
        }
    } else {
        _bail start_game $gs
    }
}

# ---- 2. Register the RECORDING callbacks (prove invocation, not just
#         absence of error). remaining_cb is a ZERO-arg prefix --
#         {incr ::REM_TICKS} counts each fire (a zero-arg lappend would
#         never grow the list). win_cb receives TWO args, so each win
#         appends BOTH to ::WINS. ----
if {$gs_ok} {
    if {[catch {::biochemeleon::game::set_callbacks \
            {lappend ::LOG_LOG} {incr ::REM_TICKS} {lappend ::WINS}} cberr]} {
        _bail set_callbacks $cberr
    }
}

# ---- 3. STATE GATE: game_logic starts idle -- on_pick 555 must be a no-op. ----
if {$gs_ok} {
    set st0 [::biochemeleon::game_logic::state]
    if {$st0 ne "idle"} { _bail initial_state "exp=idle got=$st0" }
    if {[catch {::biochemeleon::game::on_pick 555} perr3]} {
        _bail state_gate_pick_error $perr3
    }
    if {[llength $::LOG_LOG] != 0} { _bail state_gate_logged "got=[llength $::LOG_LOG]" }
    if {$::REM_TICKS != 0} { _bail state_gate_rem_cb "got=$::REM_TICKS" }
    if {[llength $::WINS] != 0} { _bail state_gate_wins "got=[llength $::WINS]" }
    if {[::biochemeleon::registry::status_of 555] ne "hidden"} {
        _bail state_gate_registry "got=[::biochemeleon::registry::status_of 555]"
    }

    # ---- 4. Drive to playing: round_reset -> begin_countdown -> 4 ticks
    #         (3/2/1/GO) -> begin_play (real-clock timer -- fine). ----
    if {[catch {
        ::biochemeleon::game_logic::round_reset
        ::biochemeleon::game_logic::begin_countdown
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::begin_play
    } driveerr4]} {
        _bail drive_playing $driveerr4
    } else {
        set stp [::biochemeleon::game_logic::state]
        if {$stp ne "playing"} { _bail playing_state "got=$stp" }
        if {$stp eq "playing"} { set playing_ok 1 }
    }
}

# ---- 5-9: the scoring flow (only meaningful with a game + playing state). ----
if {$gs_ok && $playing_ok} {

    # ---- 5. MISS: index 0 is a real atom (N1), not a hider -> "Miss!" log
    #         only, no harm (LOOP-01). ----
    if {[catch {::biochemeleon::game::on_pick 0} perr5]} {
        _bail miss_pick_error $perr5
    }
    if {[llength $::LOG_LOG] != 1} { _bail miss_log_count "exp=1 got=[llength $::LOG_LOG]" }
    if {[lindex $::LOG_LOG end] ne "Miss!"} { _bail miss_line "got=[lindex $::LOG_LOG end]" }
    set r5 [::biochemeleon::registry::count_remaining]
    if {$r5 != 5} { _bail miss_remaining "exp=5 got=$r5" }

    # ---- 6. HIT: 555 is hidden -> mark_found_visual (user2 flag) +
    #         mark_found + "Found one! 4 remaining" + remaining_cb once. ----
    if {[catch {::biochemeleon::game::on_pick 555} perr6]} {
        _bail hit_pick_error $perr6
    }
    if {[::biochemeleon::registry::status_of 555] ne "found"} {
        _bail hit_status "got=[::biochemeleon::registry::status_of 555]"
    }
    set r6 [::biochemeleon::registry::count_remaining]
    if {$r6 != 4} { _bail hit_remaining "exp=4 got=$r6" }
    if {![catch {atomselect $gm "index 555"} s6]} {
        set u6 [lindex [$s6 get user2] 0]
        if {[catch {expr {double($u6) > 0}} ok6] || !$ok6} {
            _bail hit_user2 "exp>0 got=$u6"
        }
        $s6 delete
    } else { _bail hit_sel $s6 }
    if {[lindex $::LOG_LOG end] ne "Found one! 4 remaining"} {
        _bail hit_line "got=[lindex $::LOG_LOG end]"
    }
    if {$::REM_TICKS != 1} { _bail hit_rem_cb "exp=1 got=$::REM_TICKS" }
    if {[llength $::WINS] != 0} { _bail hit_no_win "got=[llength $::WINS]" }

    # ---- 7. ALREADY-FOUND: pick 555 again -> "Already found!" only, no
    #         double-count (the caller-side registry guard), no extra
    #         remaining_cb. ----
    if {[catch {::biochemeleon::game::on_pick 555} perr7]} {
        _bail already_pick_error $perr7
    }
    if {[lindex $::LOG_LOG end] ne "Already found!"} {
        _bail already_line "got=[lindex $::LOG_LOG end]"
    }
    set r7 [::biochemeleon::registry::count_remaining]
    if {$r7 != 4} { _bail already_remaining "exp=4 got=$r7" }
    if {$::REM_TICKS != 1} { _bail already_rem_cb "exp=1 got=$::REM_TICKS" }
    if {[llength $::WINS] != 0} { _bail already_no_win "got=[llength $::WINS]" }

    # ---- 8. WIN: pick 556..559. The last find (remaining 0) triggers
    #         finish_win exactly once and fires win_cb (elapsed hider_count). ----
    foreach idx {556 557 558 559} {
        if {[catch {::biochemeleon::game::on_pick $idx} perr8]} {
            _bail "win_pick_error_$idx" $perr8
        }
    }
    set stw [::biochemeleon::game_logic::state]
    if {$stw ne "won"} { _bail win_state "exp=won got=$stw" }
    if {[llength $::WINS] != 2} {
        _bail win_cb_shape "exp=2 (one win, 2 elements) got=[llength $::WINS]"
    } else {
        set welapsed [lindex $::WINS 0]
        set whiders [lindex $::WINS 1]
        if {[catch {expr {double($welapsed) >= 0}} okw] || !$okw} {
            _bail win_elapsed "exp>=0 got=$welapsed"
        }
        if {$whiders != 5} { _bail win_hiders "exp=5 got=$whiders" }
    }
    set wline [lindex $::LOG_LOG end]
    if {[string first "You found all 5 hiders in" $wline] < 0} {
        _bail win_line "got=$wline"
    }
    if {[lindex $::LOG_LOG end-1] ne "Found one! 0 remaining"} {
        _bail win_last_found "got=[lindex $::LOG_LOG end-1]"
    }
    if {$::REM_TICKS != 5} { _bail win_rem_cb_total "exp=5 got=$::REM_TICKS" }
    if {[::biochemeleon::registry::count_remaining] != 0} {
        _bail win_remaining "exp=0 got=[::biochemeleon::registry::count_remaining]"
    }

    # ---- 9. DOUBLE-WIN PREVENTION: on_pick 0 after the win -> the state
    #         gate (won) is a no-op; finish_win's error-on-double would fire
    #         only if the gate failed. Nothing new logged, WINS unchanged. ----
    set pre_log9 [llength $::LOG_LOG]
    if {[catch {::biochemeleon::game::on_pick 0} perr9]} {
        _bail dw_pick_error $perr9
    }
    if {[llength $::LOG_LOG] != $pre_log9} {
        _bail dw_logged "exp=$pre_log9 got=[llength $::LOG_LOG]"
    }
    if {[llength $::WINS] != 2} {
        _bail dw_single_win "exp=2 got=[llength $::WINS]"
    }
}

# ---- 10. CLEANUP: restore + reset; the stash cleared; stale pick inert. ----
if {$gs_ok} {
    if {[catch {::biochemeleon::game::cleanup $gs} restored10]} {
        _bail cleanup $restored10
    } else {
        set ch10 [::biochemeleon::registry::count_hiders]
        if {$ch10 != 0} { _bail registry_after_cleanup "exp=0 got=$ch10" }
        # The stash was cleared by cleanup (round over).
        if {[dict size $::biochemeleon::game::current_state] != 0} {
            _bail stash_cleared "exp=0 got=[dict size $::biochemeleon::game::current_state]"
        }
        # Leak guard (15-05 parity): the live game_molid was deleted.
        if {![catch {molinfo $gm get numatoms} ghost]} {
            _bail game_molid_leaked "game_molid $gm still alive (numatoms=$ghost)"
        }
        # Stale pick after cleanup: state is won -> the state gate is a no-op,
        # no error, nothing logged.
        set pre_log10 [llength $::LOG_LOG]
        if {[catch {::biochemeleon::game::on_pick 555} perr10]} {
            _bail stale_pick_error $perr10
        }
        if {[llength $::LOG_LOG] != $pre_log10} {
            _bail stale_pick_logged "exp=$pre_log10 got=[llength $::LOG_LOG]"
        }
        # 10b: STASH-GUARD direct proof. Drive the state machine back to
        # playing while the registry AND the stash are empty (post-cleanup):
        # the state gate now passes, so ONLY the empty-stash guard can keep
        # the pick inert. If the guard were missing, is_hider 555 would be
        # false (registry reset) and a "Miss!" line would appear.
        if {[catch {
            ::biochemeleon::game_logic::round_reset
            ::biochemeleon::game_logic::begin_countdown
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::begin_play
        } driveerr10]} {
            _bail drive_playing_10b $driveerr10
        } else {
            set st10b [::biochemeleon::game_logic::state]
            if {$st10b ne "playing"} { _bail stash_guard_state "got=$st10b" }
            set pre_log10b [llength $::LOG_LOG]
            set pre_wins10b [llength $::WINS]
            if {[catch {::biochemeleon::game::on_pick 555} perr10b]} {
                _bail stash_guard_error $perr10b
            }
            if {[llength $::LOG_LOG] != $pre_log10b} {
                _bail stash_guard_logged "exp=$pre_log10b got=[llength $::LOG_LOG]"
            }
            if {[llength $::WINS] != $pre_wins10b} {
                _bail stash_guard_wins "exp=$pre_wins10b got=[llength $::WINS]"
            }
        }
    }
}

# ---- 11. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
