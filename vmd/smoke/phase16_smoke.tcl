# vmd/smoke/phase16_smoke.tcl
# Phase-16 CAPSTONE headless smoke: ONE run drives the COMPLETE game loop
# end-to-end through the public composition surface:
#   game::start_game (real sphere placement) -> hider reps added -> countdown
#   ticks -> begin_play -> pick_bridge::activate -> SIMULATED picks delivered
#   through pick_bridge's REAL _on_event (miss / hit / already-found /
#   winning hit) -> win state + frozen timer + win callback -> deactivate
#   (mouse restored, trace gone) -> game::cleanup (registry 0, game_molid
#   deleted, original restored).
#
# THE PICK CHAIN GOES THROUGH THE REAL _on_event (research pick SS4 item 3):
# with the bridge active, `set ::vmd_pick_atom <idx>; set ::vmd_pick_mol $gm;
# set ::vmd_pick_event <n>` fires the registered write-trace -> _on_event ->
# game::on_pick. game::on_pick is NEVER called directly here. This validates
# the tcl mechanics ONLY -- it NEVER claims VMD's C-side firing, which is
# exactly what the Phase-16 human-verify session locks (Plan 16-12).
#
# All Phase-16 phase criteria reachable headlessly are asserted:
#   SC1 logic layer (generate): 560 atoms; 5 sentinels at 555-559 segid GAME;
#     hider coords inside the ORIGINAL bbox (+/- a PDB %8.3f-rounding
#     epsilon); numreps == pre-start + 2; hidden rep read-back (VDW / Element
#     / exact sentinel selection) + found rep read-back (VDW / ColorID 7 /
#     exact sentinel selection) via the COMBINED-BRACES molinfo form.
#   SC3 logic layer (loop): countdown sequence {3 0}{2 0}{1 0}{GO! 1} ->
#     begin_play -> playing with a 0-ish timer; miss (log only, registry
#     untouched); hit (status found, remaining 4, user2 flag read-back,
#     "Found one! 4 remaining"); already-found guard ("Already found!",
#     remaining still 4); win (state won, the win callback delivered EXACTLY
#     once as {elapsed hider_count==5}, timer_elapsed frozen -- two reads
#     identical and equal to the delivered elapsed, win log line "You found
#     all 5 hiders in").
#   SC2's delivery machinery: pick armed (mouse labelatom/2 + active flag);
#     deactivate (a further simulated fire delivers NOTHING -- re-driving the
#     state machine to playing first, since the "won" state gate would
#     otherwise swallow the fire even with a live trace; mouse mode restored
#     to the pre-activate snapshot; click labels cleaned to the baseline).
#   SC4 through the loop's exit: game::cleanup restores 555 atoms /
#     pre-start numreps / registry 0, and the LIVE game_molid is DELETED
#     (leak guard -- catch {molinfo ...} must fail).
# The GUI-only remainder (real click -> event firing, found-marker visuals,
# the wall-clock pacing of the countdown) is EXPLICITLY deferred to 16-12.
#
# Timer note: game_logic::timer_start uses the REAL clock -- sleeping is
# forbidden (and pointless at 1-second resolution). Elapsed is asserted
# range-wise (>= 0) and FROZEN (two post-win reads identical), never exact.
#
# Sources the lib files in dependency order directly (mirrors the entry, NOT
# the entry itself -- avoids GUI/dialog baggage): setup_state, registry,
# generators, game_logic, demos, backup, mutation, hiders, game, pick_bridge.
# registry is sourced EXACTLY ONCE (re-sourcing would WIPE _records); demos +
# mutation re-source setup_state/generators themselves (harmless constant
# re-init).
#
# Run (repo root, against fresh staging):
#   echo exit | timeout 300 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase16_smoke.tcl -eofexit' 2>&1
# then grep the FULL output for the marker AND for ERROR) / bad switch lines
# (VMD -e catches top-level errors and CONTINUES -- a false PASS is possible;
# every step below is wrapped in catch + _bail to surface failures in the
# marker itself).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> [pwd] (the
# staging root) locates the lib files. VMD does NOT propagate tcl exit codes
# (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# ---- Simulated-pick protocol (the REAL trace fires): set the pick globals
#      and WRITE ::vmd_pick_event -> the registered write-trace invokes
#      _on_event (name1 name2 op) synchronously -> game::on_pick. Distinct
#      event values per fire (belt-and-suspenders for value-change
#      semantics -- a Tcl write fires the trace regardless). ----
set ::PICK_EV 0
proc _sim_pick {idx mol} {
    incr ::PICK_EV
    set ::vmd_pick_atom  $idx
    set ::vmd_pick_mol   $mol
    set ::vmd_pick_event $::PICK_EV
    return
}

# Recording-callback targets (globals -- the callbacks write into these).
# log_cb ONE arg (lappend); remaining_cb ZERO args (an incr counter -- a
# zero-arg lappend would never grow); win_cb TWO args (both land as list
# elements -- one win == 2 elements).
set ::LOG_LOG [list]
set ::REM_TICKS 0
set ::WINS [list]

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set gs [list]
set gm -1
set pre_reps -1
set snap_mode UNKNOWN
set snap_sub UNKNOWN
set label_base_obs -1
set EPS 0.001
set gs_ok 0
set playing_ok 0
set armed_ok 0
set ::BX0 0.0; set ::BY0 0.0; set ::BZ0 0.0
set ::BX1 0.0; set ::BY1 0.0; set ::BZ1 0.0

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry, NOT the entry itself. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    generators   [file join [pwd] vmd lib generators.tcl] \
    game_logic   [file join [pwd] vmd lib game_logic.tcl] \
    demos        [file join [pwd] vmd lib demos.tcl] \
    backup       [file join [pwd] vmd lib backup.tcl] \
    mutation     [file join [pwd] vmd lib mutation.tcl] \
    hiders       [file join [pwd] vmd lib hiders.tcl] \
    game         [file join [pwd] vmd lib game.tcl] \
    pick_bridge  [file join [pwd] vmd lib pick_bridge.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# ---- 1. SETUP: load 1k8p (555 atoms); add a VDW rep on the original so
#         backup::apply carries a rep forward (mirrors real usage); record
#         pre-start numreps; snapshot the mouse-mode globals; capture the
#         ORIGINAL bbox (start_game mol-deletes the original -- capture
#         NOW); register the recording callbacks via game::set_callbacks. ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }
    catch {mol representation VDW}
    if {[catch {mol addrep $orig_molid} adderr]} { _bail addrep $adderr }
    set pre_reps [molinfo $orig_molid get numreps]
    if {$pre_reps != 2} { _bail pre_reps "exp=2 got=$pre_reps" }
    # Mouse-mode snapshot (fresh-session defaults: rotate/-1, vmdinit.tcl:279).
    set snap_mode [set ::vmd_mouse_mode]
    set snap_sub  [set ::vmd_mouse_submode]
    # ORIGINAL bbox: measure minmax -> {{x0 y0 z0} {x1 y1 z1}}.
    if {![catch {atomselect $orig_molid "all"} bsel]} {
        if {[catch {measure minmax $bsel} bbox]} {
            _bail bbox $bbox
        } else {
            lassign $bbox bbmin bbmax
            lassign $bbmin ::BX0 ::BY0 ::BZ0
            lassign $bbmax ::BX1 ::BY1 ::BZ1
        }
        $bsel delete
    } else { _bail bbox_sel $bsel }
    # Recording callbacks (log ONE arg / remaining ZERO args / win TWO args).
    if {[catch {::biochemeleon::game::set_callbacks \
            {lappend ::LOG_LOG} {incr ::REM_TICKS} {lappend ::WINS}} cberr]} {
        _bail set_callbacks $cberr
    }
}

# ---- 2. GENERATE (SC1 logic layer): game::start_game with REAL sphere
#         placement (mutation::make_placeholder_hiders -> generators::
#         sphere_positions, uniform-random inside the ORIGINAL bbox). ----
if {$orig_molid != -1} {
    if {![catch {::biochemeleon::game::start_game $orig_molid 5} gs]} {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            set gs_ok 1
            # 2a: 555 + 5 = 560 atoms on the combined molecule.
            set n1 [molinfo $gm get numatoms]
            if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
            # 2b: exactly 5 sentinels at 555-559, segid GAME (canonical
            #     selector; tagged in-place post-load).
            if {![catch {atomselect $gm "resname GAM and beta < 0"} sel]} {
                if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
                if {[$sel get index] ne {555 556 557 558 559}} {
                    _bail sentinel_idx "got=[$sel get index]"
                }
                if {[$sel get segid] ne "GAME GAME GAME GAME GAME"} {
                    _bail sentinel_segid "got=[$sel get segid]"
                }
                $sel delete
            } else { _bail sentinel_sel $sel }
            # 2c: every hider coord inside the ORIGINAL bbox (+/- eps; the
            #     PDB write rounds to 3 decimals -> max 0.0005 drift).
            foreach idx {555 556 557 558 559} {
                if {![catch {atomselect $gm "index $idx"} sh]} {
                    lassign [lindex [$sh get {x y z}] 0] hx hy hz
                    $sh delete
                    if {[catch {expr {($hx >= $::BX0 - $EPS) && ($hx <= $::BX1 + $EPS)
                                        && ($hy >= $::BY0 - $EPS) && ($hy <= $::BY1 + $EPS)
                                        && ($hz >= $::BZ0 - $EPS) && ($hz <= $::BZ1 + $EPS)}} inb] || !$inb} {
                        _bail "hider_bbox_$idx" "coord=($hx $hy $hz) bbox=($::BX0 $::BY0 $::BZ0)-($::BX1 $::BY1 $::BZ1) eps=$EPS"
                    }
                } else { _bail "hider_sel_$idx" $sh }
            }
            # 2d: numreps == pre-start + 2 (backup::apply restored the saved
            #     reps, then hiders::add_hider_reps appended hidden+found
            #     LAST); the hider-rep indices are recorded at base..base+1.
            set post_reps [molinfo $gm get numreps]
            if {$post_reps != $pre_reps + 2} {
                _bail game_numreps "exp=[expr {$pre_reps + 2}] got=$post_reps"
            }
            set rh $::biochemeleon::hiders::hidden_rep
            set rf $::biochemeleon::hiders::found_rep
            if {$rh != $pre_reps || $rf != [expr {$pre_reps + 1}]} {
                _bail hider_rep_idx "hidden=$rh found=$rf (exp $pre_reps/[expr {$pre_reps + 1}])"
            }
            # 2e: hidden rep read-back (COMBINED-BRACES molinfo form ONLY --
            #     the single-field form FAILS; Pitfall 3 in the phase docs).
            if {[catch {foreach {hstyle hsel hcol hmat} [molinfo $gm get "{rep $rh} {selection $rh} {color $rh} {material $rh}"] { break }} rb1]} {
                _bail hidden_readback $rb1
            } else {
                if {$hstyle ne "VDW"} { _bail hidden_style "exp=VDW got=$hstyle" }
                if {$hsel ne {resname GAM and beta < 0 and user2 < 1}} {
                    _bail hidden_sel "got=$hsel"
                }
                if {$hcol ne "Element"} { _bail hidden_color "exp=Element got=$hcol" }
            }
            # 2f: found rep read-back.
            if {[catch {foreach {fstyle fsel fcol fmat} [molinfo $gm get "{rep $rf} {selection $rf} {color $rf} {material $rf}"] { break }} rb2]} {
                _bail found_readback $rb2
            } else {
                if {$fstyle ne "VDW"} { _bail found_style "exp=VDW got=$fstyle" }
                if {$fsel ne {resname GAM and beta < 0 and user2 > 0}} {
                    _bail found_sel "got=$fsel"
                }
                if {$fcol ne {ColorID 7}} { _bail found_color "exp=ColorID 7 got=$fcol" }
            }
        }
    } else {
        _bail start_game $gs
    }
}

# ---- 3. COUNTDOWN -> PLAY (SC3 loop layer): round_reset -> begin_countdown
#         -> 4 ticks asserting the {3 0}{2 0}{1 0}{GO! 1} sequence ->
#         begin_play -> playing with a 0-ish timer (real clock; range check,
#         never an exact value). ----
if {$gs_ok} {
    if {[catch {
        ::biochemeleon::game_logic::round_reset
        ::biochemeleon::game_logic::begin_countdown
    } d3]} {
        _bail begin_countdown $d3
    } else {
        set seq_ok 1
        foreach want {{3 0} {2 0} {1 0} {GO! 1}} {
            if {[catch {::biochemeleon::game_logic::countdown_tick} tick]} {
                _bail countdown_tick $tick
                set seq_ok 0
                break
            }
            if {$tick ne $want} {
                _bail countdown_seq "got=$tick want=$want"
                set seq_ok 0
                break
            }
        }
        if {$seq_ok} {
            if {[catch {::biochemeleon::game_logic::begin_play} bp]} {
                _bail begin_play $bp
            } else {
                set stp [::biochemeleon::game_logic::state]
                if {$stp ne "playing"} { _bail playing_state "got=$stp" }
                set el0 [::biochemeleon::game_logic::timer_elapsed]
                if {[catch {expr {($el0 >= 0) && ($el0 <= 5)}} ok0] || !$ok0} {
                    _bail play_timer_start "exp 0-ish (>=0, <=5) got=$el0"
                }
                if {$stp eq "playing"} { set playing_ok 1 }
            }
        }
    }
}

# ---- 4. PICK ARMED: pick_bridge::activate on the game molid (AFTER
#         start_game -- the PDB-rebuild CHANGED the molid). ----
if {$gs_ok} {
    if {[catch {::biochemeleon::pick_bridge::activate $gm} aerr]} {
        _bail activate $aerr
    } else {
        if {[set ::vmd_mouse_mode] ne "labelatom" || [set ::vmd_mouse_submode] != 2} {
            _bail armed_mode "mode=[set ::vmd_mouse_mode] sub=[set ::vmd_mouse_submode] (exp labelatom/2)"
        }
        if {![info exists ::biochemeleon::pick_bridge::active]
                || $::biochemeleon::pick_bridge::active != 1} {
            _bail armed_flag "active not 1"
        }
        set label_base_obs [llength [label list Atoms]]
        if {$label_base_obs != 0} {
            puts "BCHM_SMOKE_INFO pre-existing labels (count=$label_base_obs); hygiene asserts use the observed baseline"
        }
        set armed_ok 1
    }
}

# ---- 5-8. THE SCORING LOOP THROUGH THE REAL _on_event (never game::on_pick
#           directly): every fire below goes set-globals -> write
#           ::vmd_pick_event -> trace -> _on_event -> game::on_pick. ----
if {$gs_ok && $playing_ok && $armed_ok} {

    # ---- 5. MISS (LOOP-01): index 0 is a real atom (N1). ----
    if {[catch {_sim_pick 0 $gm} ferr]} {
        _bail miss_sim $ferr
    }
    if {[llength $::LOG_LOG] != 1} {
        _bail miss_log_count "exp=1 got=[llength $::LOG_LOG]"
    }
    if {[lindex $::LOG_LOG end] ne "Miss!"} {
        _bail miss_line "got=[lindex $::LOG_LOG end]"
    }
    set r5 [::biochemeleon::registry::count_remaining]
    if {$r5 != 5} { _bail miss_remaining "exp=5 got=$r5" }
    if {[::biochemeleon::registry::count_hiders] != 5} {
        _bail miss_registry "count_hiders changed on a miss"
    }
    if {[::biochemeleon::registry::status_of 555] ne "hidden"} {
        _bail miss_status "got=[::biochemeleon::registry::status_of 555]"
    }
    # Mimic the C-side click label (pick-atom mode creates one per click);
    # the NEXT processed pick must clean it (baseline-guarded hygiene).
    if {[catch {label add Atoms $gm/0} lerr]} {
        _bail label_add $lerr
    } elseif {[llength [label list Atoms]] != [expr {$label_base_obs + 1}]} {
        _bail label_added "count=[llength [label list Atoms]] (exp [expr {$label_base_obs + 1}])"
    }

    # ---- 6. HIT + ALREADY-FOUND (LOOP-02): 555 hidden -> found. ----
    if {[catch {_sim_pick 555 $gm} ferr6]} {
        _bail hit_sim $ferr6
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
    # The processed pick cleaned the click label (baseline-guarded hygiene).
    if {[llength [label list Atoms]] != $label_base_obs} {
        _bail label_cleaned "count=[llength [label list Atoms]] (exp baseline $label_base_obs)"
    }
    # Already-found: pick 555 again -> log only, no double-count.
    if {[catch {_sim_pick 555 $gm} ferr7]} {
        _bail already_sim $ferr7
    }
    if {[lindex $::LOG_LOG end] ne "Already found!"} {
        _bail already_line "got=[lindex $::LOG_LOG end]"
    }
    set r7 [::biochemeleon::registry::count_remaining]
    if {$r7 != 4} { _bail already_remaining "exp=4 got=$r7" }
    if {$::REM_TICKS != 1} { _bail already_rem_cb "exp=1 got=$::REM_TICKS" }

    # ---- 7. WIN (LOOP-03/GAME-02): pick 556..559; the last find wins. ----
    foreach idx {556 557 558 559} {
        if {[catch {_sim_pick $idx $gm} ferr8]} {
            _bail "win_sim_$idx" $ferr8
        }
    }
    set stw [::biochemeleon::game_logic::state]
    if {$stw ne "won"} { _bail win_state "exp=won got=$stw" }
    if {[llength $::WINS] != 2} {
        _bail win_cb "exp=2 (ONE win delivery, 2 elements) got=[llength $::WINS]"
    } else {
        set welapsed [lindex $::WINS 0]
        set whiders [lindex $::WINS 1]
        if {[catch {expr {double($welapsed) >= 0}} okw] || !$okw} {
            _bail win_elapsed "exp>=0 got=$welapsed"
        }
        if {$whiders != 5} { _bail win_hiders "exp=5 got=$whiders" }
        # Timer FROZEN: two post-win reads identical AND equal to the
        # delivered elapsed (finish_win froze the value; no sleeping).
        set e1 [::biochemeleon::game_logic::timer_elapsed]
        set e2 [::biochemeleon::game_logic::timer_elapsed]
        if {[catch {expr {($e1 == $e2) && ($e1 == $welapsed) && ($e1 >= 0)}} okf] || !$okf} {
            _bail timer_frozen "reads=($e1 $e2) win_elapsed=$welapsed"
        }
    }
    set wline [lindex $::LOG_LOG end]
    if {[string first "You found all 5 hiders in" $wline] < 0} {
        _bail win_line "got=$wline"
    }
    if {$::REM_TICKS != 5} { _bail win_rem_cb_total "exp=5 got=$::REM_TICKS" }
    if {[::biochemeleon::registry::count_remaining] != 0} {
        _bail win_remaining "exp=0 got=[::biochemeleon::registry::count_remaining]"
    }

    # ---- 8. INERT AFTER WIN: the state gate + finish_win's error-on-double.
    #         Fire a real atom AND the found hider: nothing new logged, the
    #         win delivery count unchanged. ----
    set pre_log8 [llength $::LOG_LOG]
    if {[catch {_sim_pick 0 $gm} ferr9]} { _bail inert_sim0 $ferr9 }
    if {[catch {_sim_pick 555 $gm} ferr10]} { _bail inert_sim555 $ferr10 }
    if {[llength $::LOG_LOG] != $pre_log8} {
        _bail inert_logged "exp=$pre_log8 got=[llength $::LOG_LOG]"
    }
    if {[llength $::WINS] != 2} {
        _bail inert_single_win "exp=2 got=[llength $::WINS]"
    }
}

# ---- 9. DEACTIVATE: trace gone (a further simulated fire delivers
#         NOTHING), mouse mode restored to the pre-activate snapshot, click
#         labels cleaned. ----
if {$armed_ok} {
    if {[catch {::biochemeleon::pick_bridge::deactivate} derr]} {
        _bail deactivate $derr
    } else {
        # 9a. mouse mode restored to the activate-time snapshot.
        if {[set ::vmd_mouse_mode] ne $snap_mode
                || [set ::vmd_mouse_submode] ne $snap_sub} {
            _bail mode_restored "mode=[set ::vmd_mouse_mode] sub=[set ::vmd_mouse_submode] (exp $snap_mode/$snap_sub)"
        }
        # 9b. labels at the baseline (user's view clean).
        if {[llength [label list Atoms]] != $label_base_obs} {
            _bail labels_cleaned "count=[llength [label list Atoms]] (exp baseline $label_base_obs)"
        }
        # 9c. active flag cleared.
        if {[info exists ::biochemeleon::pick_bridge::active]
                && $::biochemeleon::pick_bridge::active != 0} {
            _bail deactivate_flag "active not 0 after deactivate"
        }
        # 9d. trace gone -- DIRECT introspection (catch-guarded; the
        #     behavioral proof below is authoritative if this form differs).
        if {![catch {trace info variable ::vmd_pick_event} trinfo]} {
            if {[lsearch -glob $trinfo "*_on_event*"] >= 0} {
                _bail trace_still_registered "trace info=[concat $trinfo]"
            }
        }
        # 9e. trace gone -- BEHAVIORAL proof. A bare fire would be swallowed
        #     by the "won" state gate even with a LIVE trace, so re-drive the
        #     state machine to playing first (the stash still holds the
        #     round, the game mol is still alive): a live trace would now
        #     deliver index 0 -> a "Miss!" line. No delivery => trace gone.
        if {[catch {
            ::biochemeleon::game_logic::round_reset
            ::biochemeleon::game_logic::begin_countdown
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::begin_play
        } drive9]} {
            _bail drive_playing_9 $drive9
        } else {
            set pre_log9 [llength $::LOG_LOG]
            set pre_wins9 [llength $::WINS]
            if {[catch {_sim_pick 0 $gm} f9]} { _bail inert_fire9 $f9 }
            if {[llength $::LOG_LOG] != $pre_log9} {
                _bail trace_removed "delivery AFTER deactivate (log grew [expr {[llength $::LOG_LOG] - $pre_log9}])"
            }
            if {[llength $::WINS] != $pre_wins9} {
                _bail trace_removed_wins "WINS grew after deactivate"
            }
        }
    }
}

# ---- 10. CLEANUP (Phase-15 regression through the loop's exit): restore the
#          original + reset the registry; the LIVE game_molid DELETED. ----
if {$gs_ok} {
    if {[catch {::biochemeleon::game::cleanup $gs} restored]} {
        _bail cleanup $restored
    } else {
        set n2 [molinfo $restored get numatoms]
        if {$n2 != 555} { _bail restored_atoms "exp=555 got=$n2" }
        set ch2 [::biochemeleon::registry::count_hiders]
        if {$ch2 != 0} { _bail registry_after_cleanup "exp=0 got=$ch2" }
        # Leak guard: restore deleted the PASSED LIVE game_molid (NOT the
        # dead snapshot.molid -- the 15-03 contract). Still alive => leak.
        if {![catch {molinfo $gm get numatoms} ghost]} {
            _bail game_molid_leaked "game_molid $gm still alive (numatoms=$ghost)"
        }
        set rn [molinfo $restored get numreps]
        if {$rn != $pre_reps} {
            _bail restored_numreps "exp=$pre_reps got=$rn"
        }
    }
}

# ---- 11. GATES (belt-and-suspenders, inside the smoke): no lib file may
#          contain the numeric userpoint trap, and the pick handler MUST
#          keep its {args} signature (a positional signature makes VMD's own
#          write of the traced variable FAIL -- probe3 -- and the pick is
#          LOST). Complements the runner's shell-level greps. ----
set libdir [file join [pwd] vmd lib]
if {![file isdirectory $libdir]} {
    _bail gate_libdir "$libdir missing"
} else {
    if {![file exists [file join $libdir pick_bridge.tcl]]} {
        _bail gate_pickbridge "pick_bridge.tcl not found"
    }
    foreach f [glob -nocomplain [file join $libdir *.tcl]] {
        if {[catch {open $f r} fh]} {
            _bail gate_open "$f: $fh"
            continue
        }
        set txt [read $fh]
        close $fh
        if {[string first "mouse mode 4" $txt] >= 0} {
            _bail gate_mode4 "literal 'mouse mode 4' in [file tail $f] (userpoint trap)"
        }
        if {[file tail $f] eq "pick_bridge.tcl"
                && [string first "_on_event {args}" $txt] < 0} {
            _bail gate_handler_sig "_on_event {args} signature missing (a positional signature blocks the pick write)"
        }
    }
}

# ---- 12. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
