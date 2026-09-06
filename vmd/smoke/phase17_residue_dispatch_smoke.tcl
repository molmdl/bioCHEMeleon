# vmd/smoke/phase17_residue_dispatch_smoke.tcl
# Phase-17.2 (17.2-09) headless smoke: the RESIDUE-KIND dispatch routing in
# game::start_game + the on_pick resid-block fallback, driven end-to-end on
# demo 1znf (424 atoms) through the REAL pipeline (17.2-02 registry block +
# 17.2-03 residue tiers + 17.2-04 splice generator + the 17.2-09 routing).
# Proves (the plan's steps 1-8):
#   1. Mixed round start_game $m 4 {VDW 2 Cartoon 2} 0 -> 436-atom game
#      molecule (2 simple + 10 residue atoms), game_state hider_count == 4
#      (the EFFECTIVE total, P9), per_rep stashed GAME_REPS-ordered
#      {VDW 2 Cartoon 2}, dict shape UNCHANGED (4 keys).
#   2. Index layout (file order == record order, simple-first): fetch
#      indices == {424 425 427 432} (VDW simple 424-425; Cartoon residue 1
#      N/CA/C/O/CB 426-430 with CA 427; residue 2 431-435 with CA 432);
#      user3 stamps derived from rep_tiers::tiers_from_per_rep ({1 VDW 2}
#      {2 Cartoon 2}) and asserted numerically (P10); real atoms keep 0.
#   3. Resid block registered ONCE: hider_for_resid 9001 == 427,
#      9002 == 432, 9999 -> "" (miss), count_hiders == 4,
#      remaining_by_rep == {VDW 2 Cartoon 2}.
#   4. Fake-residue facts: resname GAM num == 12; the beta<0 set is exactly
#      {G01 G02 CA CA} -- the residue-zone sentinels are CA-ONLY (Pitfall
#      C6: N/C/O/CB carry beta 0.00); fake CA structure in the load-time
#      STRIDE coil/turn family {T C} (RECORDED, tube/trace precedent --
#      never pinned to T); residue-zone chains are the ANCHOR's chain
#      (never "G"); segid GAME on all 12; numreps == pre_start + 4 (2
#      tier pairs); per-pair read-back via tier_reps + repindex (VDW pair
#      style VDW + user3 1, Cartoon pair style Cartoon + user3 2).
#   5. Find-through-BOTH-paths (callbacks registered BEFORE the finds,
#      state driven to playing):
#        - on_pick 100 (real atom) -> "Miss!" (fallback consulted, real
#          resid << 9001 never in the block);
#        - on_pick 428 (residue-1's C -- NOT registered) -> the FALLBACK
#          resolves 427: user2(427) > 0, remaining 3, remaining_by_rep
#          {VDW 2 Cartoon 1}, "Found one! 3 remaining" logged;
#        - on_pick 424 / 425 (direct VDW) -> remaining 2, then 1;
#        - on_pick 433 (residue-2's C -- NOT registered) -> the FALLBACK
#          resolves 432 -> remaining 0 -> WIN: game_logic state == won,
#          finish_win fired (win_cb elapsed == the FROZEN timer_elapsed),
#          win line mentions 4 hiders.
#   6. Double-find guard through the fallback: on_pick 426 (residue-1's N;
#      its CA 427 already found) -> "Already found!", remaining still 0.
#      NOTE: this check runs BEFORE the win pick (re-ordered from the
#      plan's step list) -- post-win the STATE GATE (16-11 precedent)
#      turns every pick into a no-op, so the already-found branch can only
#      log while state == playing.
#   7. Cleanup: registry count 0 AND hider_for_resid 9001 == "" (reset
#      cleared the resid block); game molid DEAD; restored original 424
#      atoms at the pre-start numreps (no game-rep leak).
#   8. Marker + exit (BCHM_SMOKE_RESULT; the runner scans the FULL log).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the
# entry itself): setup_state, registry, generators, game_logic, rep_tiers,
# demos, backup, mutation (which sources splice for the residue
# generator), hiders, game. registry is sourced EXACTLY ONCE (re-sourcing
# would WIPE _records AND the resid block).
#
# The molecule is SINGLE-FRAME: 1znf ships 2 models, so the collapse loader
# (frame-0-pinned writepdb round-trip -- the SAME pipeline mutate uses
# downstream, tube/trace precedent) precedes start_game; every coordinate
# read/write is deterministic frame-0 geometry and make_residue_hiders'
# frame pins are no-ops.
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT propagate
# tcl exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER
# $?; VMD -e catches top-level errors and CONTINUES (possible false-PASS)
# -> every step is wrapped in catch + _bail, and the runner scans the FULL
# log for ERROR) / bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Float read-back compare (user2/user3 are FLOATS -- numeric only, P10).
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set gs [list]
set gm -1
set pre_reps -1
set hider_idxs [list]
set gs_ok 0
set playing_ok 0
set restored_molid -1

# Recording-callback targets (globals -- the callbacks write into these).
# LOG_LOG/WINS are lists (1-arg / 2-arg lappends); REM_TICKS is a scalar
# invocation counter (remaining_cb is ZERO-arg -- {incr} is the only
# zero-arg-safe recorder).
set ::LOG_LOG [list]
set ::REM_TICKS 0
set ::WINS [list]

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's source order minus
#      the GUI files. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry    [file join [pwd] vmd lib registry.tcl] \
    generators  [file join [pwd] vmd lib generators.tcl] \
    game_logic  [file join [pwd] vmd lib game_logic.tcl] \
    rep_tiers   [file join [pwd] vmd lib rep_tiers.tcl] \
    demos       [file join [pwd] vmd lib demos.tcl] \
    backup      [file join [pwd] vmd lib backup.tcl] \
    mutation    [file join [pwd] vmd lib mutation.tcl] \
    hiders      [file join [pwd] vmd lib hiders.tcl] \
    game        [file join [pwd] vmd lib game.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# Collapse loader (1znf ships 2 models): frame-0-pinned writepdb round-trip
# -> a single-frame molecule (the caller contract make_residue_hiders
# documents; the SAME pipeline mutate uses downstream).
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] resid_dispatch_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
}

if {[catch {_load_demo_1f 1znf} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    set nf [molinfo $orig_molid get numframes]
    if {$nf != 1} { _bail orig_frames "exp=1 (collapse) got=$nf" }
    set pre_reps [molinfo $orig_molid get numreps]
    puts "RESIDUEDISPATCH_INFO pre_reps=$pre_reps"
    # ---- 1. MIXED ROUND: explicit per_rep {VDW 2 Cartoon 2}, lock_scene 0.
    #         VDW is the free tier (simple records), Cartoon the residue
    #         tier (17.2-09 routing through make_residue_hiders). ----
    if {[catch {::biochemeleon::game::start_game $orig_molid 4 [dict create VDW 2 Cartoon 2] 0} gs]} {
        _bail start_game $gs
        puts "STARTFAIL_EI $errorInfo"
    } else {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            set gs_ok 1
            # 1a: 424 + 2 simple + 2x5 residue atoms = 436.
            set n1 [molinfo $gm get numatoms]
            if {$n1 != 436} { _bail game_atoms "exp=436 got=$n1" }
            # 1b: game_state hider_count == 4 (the EFFECTIVE total, P9 --
            #     a residue hider counts 1, not 5).
            if {[catch {dict get $gs hider_count} eff]} {
                _bail gs_hider_count "missing"
            } elseif {$eff != 4} {
                _bail eff_total "exp=4 got=$eff"
            }
            # 1c: per_rep stashed, GAME_REPS-ordered keys (VDW precedes
            #     Cartoon), counts 2/2.
            if {![dict exists $gs per_rep]} {
                _bail gs_per_rep "missing"
            } else {
                set pr [dict get $gs per_rep]
                if {[catch {dict keys $pr} prk]} {
                    _bail per_rep_keys $prk
                } else {
                    if {$prk ne {VDW Cartoon}} {
                        _bail per_rep_order "got=$prk (expect GAME_REPS order: VDW precedes Cartoon)"
                    }
                    foreach {rep expn} [list VDW 2 Cartoon 2] {
                        if {[catch {dict get $pr $rep} c] || $c != $expn} {
                            _bail per_rep_$rep "exp=$expn got=$c"
                        }
                    }
                }
            }
            # 1d: game_state dict shape UNCHANGED (15-05 + additive per_rep
            #     -- 4 keys total; the registry holds the resid block).
            if {[dict keys $gs] ne "game_molid hider_count snapshot per_rep"} {
                _bail gs_shape "got=[dict keys $gs]"
            }
            # 1e: the namespace stash is populated (4 keys).
            if {[dict size $::biochemeleon::game::current_state] != 4} {
                _bail stash_populated "exp=4 got=[dict size $::biochemeleon::game::current_state]"
            }

            # ---- 2. INDEX LAYOUT (file order == record order,
            #         simple-first) + user3 stamps off the DERIVED tier
            #         table. ----
            if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hider_idxs]} {
                _bail fetch_idx $hider_idxs
                set hider_idxs [list]
            } elseif {$hider_idxs ne {424 425 427 432}} {
                _bail hider_idx "got=$hider_idxs (exp VDW 424-425 + CAs 427/432)"
            }
            if {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $pr} tiers]} {
                _bail tiers_from_per_rep $tiers
            } else {
                if {[llength $tiers] != 2} {
                    _bail tier_table_len "exp=2 got=$tiers"
                } else {
                    lassign [lindex $tiers 0] tcode1 tstyle1 tcnt1
                    lassign [lindex $tiers 1] tcode2 tstyle2 tcnt2
                    if {$tcode1 != 1 || $tstyle1 ne "VDW" || $tcnt1 != 2} {
                        _bail tier1 "got=[lindex $tiers 0] (GAME_REPS order: VDW first)"
                    }
                    if {$tcode2 != 2 || $tstyle2 ne "Cartoon" || $tcnt2 != 2} {
                        _bail tier2 "got=[lindex $tiers 1] (Cartoon second, code 2)"
                    }
                    # Derived expectation: cumulative slices of the hider
                    # index list per tier's ACTUAL INDEX count (a residue
                    # tier contributes 1 per hider -- its CA).
                    set exp_code [dict create]
                    set off 0
                    if {[llength $hider_idxs] != 4} {
                        _bail hider_idx_len "exp=4 got=[llength $hider_idxs]"
                    }
                    foreach t $tiers {
                        lassign $t cc ss kk
                        for {set i 0} {$i < $kk && $off < [llength $hider_idxs]} {incr i} {
                            dict set exp_code [lindex $hider_idxs $off] $cc
                            incr off
                        }
                    }
                    if {[dict size $exp_code] != 4} {
                        _bail exp_code_size "exp=4 got=[dict size $exp_code]"
                    }
                    foreach idx $hider_idxs {
                        if {![dict exists $exp_code $idx]} { continue }
                        set e [dict get $exp_code $idx]
                        if {![catch {atomselect $gm "index $idx"} s]} {
                            set u3 [lindex [$s get user3] 0]
                            if {![_feq $u3 $e]} {
                                _bail user3_$idx "exp=$e got=$u3"
                            }
                            $s delete
                        } else { _bail user3_sel_$idx $s }
                    }
                    # Real atoms keep user3 = 0 (P6).
                    if {![catch {atomselect $gm "index 100"} s100]} {
                        set u3r [lindex [$s100 get user3] 0]
                        if {![_feq $u3r 0.0]} { _bail user3_real "exp=0.0 got=$u3r" }
                        $s100 delete
                    } else { _bail user3_sel_real $s100 }
                }
            }

            # ---- 3. RESID BLOCK (registered ONCE, after reconstruct +
            #         assign_reps). ----
            set rid9001 [::biochemeleon::registry::hider_for_resid 9001]
            if {$rid9001 != 427} { _bail resid_9001 "exp=427 got=$rid9001" }
            set rid9002 [::biochemeleon::registry::hider_for_resid 9002]
            if {$rid9002 != 432} { _bail resid_9002 "exp=432 got=$rid9002" }
            set rid9999 [::biochemeleon::registry::hider_for_resid 9999]
            if {$rid9999 ne ""} { _bail resid_9999 "exp='' got=$rid9999" }
            set ch [::biochemeleon::registry::count_hiders]
            if {$ch != 4} { _bail reg_count "exp=4 got=$ch" }
            if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
                _bail remaining_by_rep $rbr
            } else {
                if {[dict size $rbr] != 2} {
                    _bail rbr_size "exp=2 got=$rbr"
                }
                foreach {rep expn} [list VDW 2 Cartoon 2] {
                    if {[catch {dict get $rbr $rep} got] || $got != $expn} {
                        _bail rbr_$rep "exp=$expn got=$got"
                    }
                }
            }

            # ---- 4. FAKE-RESIDUE FACTS. ----
            if {![catch {atomselect $gm "resname GAM"} sg]} {
                if {[$sg num] != 12} { _bail gam_num "exp=12 got=[$sg num]" }
                set gseg [$sg get segid]
                foreach sgid $gseg {
                    if {$sgid ne "GAME"} { _bail gam_segid "got=$sgid (exp GAME on all 12)" }
                }
                $sg delete
            } else { _bail gam_sel $sg }
            # The beta<0 set: simple G-names + CA-ONLY residue sentinels
            # (Pitfall C6 -- N/C/O/CB carry beta 0.00).
            if {![catch {atomselect $gm "resname GAM and beta < 0"} sb]} {
                set bidx [$sb get index]
                set bnm [$sb get name]
                if {$bidx ne {424 425 427 432}} {
                    _bail beta_idx "got=$bidx"
                }
                if {$bnm ne {G01 G02 CA CA}} {
                    _bail beta_names "got=$bnm (exp residue-zone sentinels CA-only)"
                }
                # CA structure: load-time STRIDE coil/turn family {T C} --
                # RECORDED (tube/trace precedent), never pinned to T.
                set bstruct [$sb get structure]
                set cas [list]
                foreach st $bstruct {
                    if {[lsearch -exact {T C} $st] < 0} {
                        _bail ca_structure "exp T or C (load-time STRIDE) got=$st"
                    }
                }
                puts "RESIDUEDISPATCH_INFO beta<0 structures=$bstruct (recorded)"
                $sb delete
            } else { _bail beta_sel $sb }
            # Residue zone (426-435): chains are the ANCHOR's chain (never
            # "G" -- a mismatched chain never renders traced, Pitfall C8).
            if {![catch {atomselect $gm "index 426 427 428 429 430 431 432 433 434 435"} sz]} {
                if {[$sz num] != 10} {
                    _bail resid_zone_num "exp=10 got=[$sz num]"
                }
                set zch [$sz get chain]
                foreach zc $zch {
                    if {$zc eq "G"} { _bail resid_zone_chain "got=G (exp anchor chain)" }
                }
                $sz delete
            } else { _bail resid_zone_sel $sz }
            # numreps == pre_start + 4 (2 tier pairs; scene reps survive
            # backup::apply, hider reps land LAST).
            set nreps [molinfo $gm get numreps]
            if {$nreps != $pre_reps + 4} {
                _bail rep_count "exp=[expr {$pre_reps + 4}] got=$nreps"
            }
            # Per-pair read-back (COMBINED-BRACES molinfo form ONLY),
            # driven off the derived tier table.
            foreach t $tiers {
                lassign $t code style cnt
                if {![dict exists $::biochemeleon::hiders::tier_reps $code]} {
                    _bail tier_reps_missing $code
                    continue
                }
                lassign [dict get $::biochemeleon::hiders::tier_reps $code] hn fn hs fs
                foreach {rname rrep rexp_sel} [list \
                        hidden $hn {resname GAM and beta < 0 and user2 < 1 and user3} \
                        found  $fn {resname GAM and beta < 0 and user2 > 0 and user3}] {
                    if {[catch {mol repindex $gm $rrep} ridx] || $ridx < 0} {
                        _bail ${rname}_repindex_$code "name=$rrep repindex=$ridx"
                        continue
                    }
                    set st ""; set sl ""; set cl ""; set mt ""
                    if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep $ridx} {selection $ridx} {color $ridx} {material $ridx}"] { break }} rb]} {
                        _bail ${rname}_readback_$code $rb
                        continue
                    }
                    if {$st ne $style} {
                        _bail ${rname}_style_$code "exp=$style got=$st"
                    }
                    set exp_col "Element"
                    if {$rname eq "found"} { set exp_col {ColorID 7} }
                    if {$cl ne $exp_col} {
                        _bail ${rname}_color_$code "exp=$exp_col got=$cl"
                    }
                    set exp_sel "$rexp_sel $code"
                    if {$sl ne $exp_sel} {
                        _bail ${rname}_sel_$code "exp=$exp_sel got=$sl"
                    }
                }
            }
        }
    }
}

# ---- 5-6. FIND-THROUGH-BOTH-PATHS + the double-find guard. Callbacks
#           registered BEFORE the finds; state driven to playing (the
#           state gate). The already-found check runs BEFORE the win pick
#           (post-win the state gate no-ops every pick). ----
if {$gs_ok} {
    if {[catch {::biochemeleon::game::set_callbacks \
            {lappend ::LOG_LOG} {incr ::REM_TICKS} {lappend ::WINS}} cberr]} {
        _bail set_callbacks $cberr
    }
    if {[catch {
        ::biochemeleon::game_logic::round_reset
        ::biochemeleon::game_logic::begin_countdown
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::countdown_tick
        ::biochemeleon::game_logic::begin_play
    } driveerr]} {
        _bail drive_playing $driveerr
    } else {
        set stp [::biochemeleon::game_logic::state]
        if {$stp ne "playing"} { _bail playing_state "got=$stp" }
        if {$stp eq "playing"} { set playing_ok 1 }
    }
}

if {$gs_ok && $playing_ok} {
    # 5a. MISS through the fallback: a real atom (resid << 9001, never in
    #     the block) -> "Miss!", no harm (LOOP-01).
    if {[catch {::biochemeleon::game::on_pick 100} perr5a]} {
        _bail miss_pick_error $perr5a
    }
    if {[lindex $::LOG_LOG end] ne "Miss!"} { _bail miss_line "got=[lindex $::LOG_LOG end]" }
    set r5a [::biochemeleon::registry::count_remaining]
    if {$r5a != 4} { _bail miss_remaining "exp=4 got=$r5a" }

    # 5b. FALLBACK FIND: 428 is residue-1's C -- NOT registered; the
    #     resid-block fallback resolves it to the registered CA 427.
    if {[catch {::biochemeleon::game::on_pick 428} perr5b]} {
        _bail fb_pick_error $perr5b
    }
    if {[::biochemeleon::registry::status_of 427] ne "found"} {
        _bail fb_status "got=[::biochemeleon::registry::status_of 427]"
    }
    if {![catch {atomselect $gm "index 427"} s5b]} {
        set u2 [lindex [$s5b get user2] 0]
        if {[catch {expr {double($u2) > 0}} ok5b] || !$ok5b} {
            _bail fb_user2_427 "exp>0 got=$u2"
        }
        $s5b delete
    } else { _bail fb_sel_427 $s5b }
    set r5b [::biochemeleon::registry::count_remaining]
    if {$r5b != 3} { _bail fb_remaining "exp=3 got=$r5b" }
    if {[catch {::biochemeleon::registry::remaining_by_rep} rbr5b]} {
        _bail fb_remaining_by_rep $rbr5b
    } else {
        foreach {rep expn} [list VDW 2 Cartoon 1] {
            if {[catch {dict get $rbr5b $rep} got] || $got != $expn} {
                _bail fb_rbr_$rep "exp=$expn got=$got"
            }
        }
    }
    if {[lindex $::LOG_LOG end] ne "Found one! 3 remaining"} {
        _bail fb_line "got=[lindex $::LOG_LOG end]"
    }
    # The log contains a "found" line for the fallback find (4th line,
    # 0-based index 1 after the Miss).
    set fbfound 0
    foreach l $::LOG_LOG {
        if {[string first "Found one!" $l] == 0} { incr fbfound }
    }
    if {$fbfound < 1} { _bail fb_found_logged "got=$::LOG_LOG" }
    if {$::REM_TICKS != 1} { _bail fb_rem_cb "exp=1 got=$::REM_TICKS" }

    # 5c. DIRECT FINDS: 424 then 425 (the VDW simple hiders -- registered
    #     atoms, the Phase-16 path byte-compatible).
    if {[catch {::biochemeleon::game::on_pick 424} perr5c]} {
        _bail direct1_pick_error $perr5c
    }
    set r5c [::biochemeleon::registry::count_remaining]
    if {$r5c != 2} { _bail direct1_remaining "exp=2 got=$r5c" }
    if {[lindex $::LOG_LOG end] ne "Found one! 2 remaining"} {
        _bail direct1_line "got=[lindex $::LOG_LOG end]"
    }
    if {[catch {::biochemeleon::game::on_pick 425} perr5c2]} {
        _bail direct2_pick_error $perr5c2
    }
    set r5c2 [::biochemeleon::registry::count_remaining]
    if {$r5c2 != 1} { _bail direct2_remaining "exp=1 got=$r5c2" }
    if {[lindex $::LOG_LOG end] ne "Found one! 1 remaining"} {
        _bail direct2_line "got=[lindex $::LOG_LOG end]"
    }
    if {$::REM_TICKS != 3} { _bail direct_rem_cb "exp=3 got=$::REM_TICKS" }

    # 6. DOUBLE-FIND GUARD through the fallback (state still playing):
    #    426 is residue-1's N; its CA 427 is already found -> the fallback
    #    resolves 427, the three-way guard logs "Already found!", no
    #    double-count.
    if {[catch {::biochemeleon::game::on_pick 426} perr6]} {
        _bail already_pick_error $perr6
    }
    if {[lindex $::LOG_LOG end] ne "Already found!"} {
        _bail already_line "got=[lindex $::LOG_LOG end]"
    }
    set r6 [::biochemeleon::registry::count_remaining]
    if {$r6 != 1} { _bail already_remaining "exp=1 got=$r6" }
    if {$::REM_TICKS != 3} { _bail already_rem_cb "exp=3 got=$::REM_TICKS" }
    if {[llength $::WINS] != 0} { _bail already_no_win "got=[llength $::WINS]" }

    # 5d. FALLBACK FIND -> WIN: 433 is residue-2's C -- NOT registered;
    #     the fallback resolves 432 -> remaining 0 -> finish_win.
    if {[catch {::biochemeleon::game::on_pick 433} perr5d]} {
        _bail win_pick_error $perr5d
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
        if {$whiders != 4} { _bail win_hiders "exp=4 got=$whiders" }
        # Timer frozen: timer_elapsed AFTER finish_win returns the FROZEN
        # value == what win_cb received.
        set tel [::biochemeleon::game_logic::timer_elapsed]
        if {![_feq $tel $welapsed]} {
            _bail win_timer_frozen "cb=$welapsed timer=$tel"
        }
    }
    set wline [lindex $::LOG_LOG end]
    if {[string first "You found all 4 hiders in" $wline] < 0} {
        _bail win_line "got=$wline"
    }
    if {[lindex $::LOG_LOG end-1] ne "Found one! 0 remaining"} {
        _bail win_last_found "got=[lindex $::LOG_LOG end-1]"
    }
    if {$::REM_TICKS != 4} { _bail win_rem_cb_total "exp=4 got=$::REM_TICKS" }
    if {[::biochemeleon::registry::count_remaining] != 0} {
        _bail win_remaining "exp=0 got=[::biochemeleon::registry::count_remaining]"
    }
    # user2 read-back on BOTH fallback-resolved CAs.
    foreach cidx {427 432} {
        if {![catch {atomselect $gm "index $cidx"} sc]} {
            set u2c [lindex [$sc get user2] 0]
            if {[catch {expr {double($u2c) > 0}} okc] || !$okc} {
                _bail win_user2_$cidx "exp>0 got=$u2c"
            }
            $sc delete
        } else { _bail win_sel_$cidx $sc }
    }
}

# ---- 7. CLEANUP: restore + reset; the RESID BLOCK cleared (reset clears
#         _records AND _resid_block); game molid DEAD; the original back
#         at its pre-start numreps. ----
if {$gs_ok} {
    if {[catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
        _bail cleanup $restored_molid
    } else {
        set ch7 [::biochemeleon::registry::count_hiders]
        if {$ch7 != 0} { _bail reg_after_cleanup "exp=0 got=$ch7" }
        set rb7 [::biochemeleon::registry::hider_for_resid 9001]
        if {$rb7 ne ""} { _bail resid_block_after_cleanup "exp='' got=$rb7" }
        if {![catch {molinfo $gm get numatoms} alive]} {
            _bail game_molid_alive "molinfo on the deleted game molid succeeded (numatoms=$alive)"
        }
        if {[catch {molinfo $restored_molid get numatoms} rn7]} {
            _bail restored_atoms $rn7
        } elseif {$rn7 != 424} {
            _bail restored_atoms "exp=424 got=$rn7"
        }
        if {[catch {molinfo $restored_molid get numreps} rr7]} {
            _bail restored_numreps $rr7
        } elseif {$rr7 != $pre_reps} {
            _bail restored_numreps "exp=$pre_reps got=$rr7"
        }
        # The stash was cleared by cleanup (round over).
        if {[dict size $::biochemeleon::game::current_state] != 0} {
            _bail stash_cleared "exp=0 got=[dict size $::biochemeleon::game::current_state]"
        }
    }
}

# ---- 8. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
