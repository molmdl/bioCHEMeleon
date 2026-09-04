# vmd/smoke/phase17_dispatch_smoke.tcl
# Phase-17.1 (17.1-06) headless smoke: the per-tier DISPATCH composition root
# -- game::start_game {molid hider_count {per_rep {}} {lock_scene 0}} driven
# end-to-end on real demos through the REAL pipeline (waves 1-2 integrated:
# rep_tiers resolution + per-tier generators + N-tier hiders + multi-tier
# registry). Proves (the 17.1-06 must-haves):
#   1. EXPLICIT per_rep {VDW 2 Lines 2} on 1znf (424 atoms) -> 428-atom game
#      molecule, hider indices {424 425 426 427}, game_state hider_count == 4
#      (the EFFECTIVE total, P9), per_rep stashed with the GAME_REPS-ordered
#      keys {Lines VDW} and counts 2/2 (resolve_per_rep's pinned 17.1-01
#      output contract: rebuilt GAME_REPS-ordered on BOTH paths).
#   2. Tier ordering is GAME_REPS order: Lines precedes VDW -> code 1 = Lines
#      (indices 424-425), code 2 = VDW (426-427). The expected code-per-index
#      map is DERIVED from rep_tiers::tiers_from_per_rep (not hard-coded) and
#      asserted against the user3 stamps (numeric compare -- float read-back,
#      P10).
#   3. numreps == the ORIGINAL molecule's pre-start numreps + 4 (2N pairs;
#      the scene reps survive backup::apply, hider reps land LAST).
#   4. Per-pair read-back (COMBINED-BRACES molinfo form) driven off the
#      derived tier table: hidden = tier style + Element + {... user2 < 1 and
#      user3 <code>}, found = tier style + ColorID 7 + {... user2 > 0 and
#      user3 <code>}; names resolve via mol repindex (name-keyed tracking).
#   5. Registry: count_hiders == 4; remaining_by_rep == {Lines 2 VDW 2}
#      (order-insensitive key compare).
#   6. A VDW find (426): mark_found_visual + registry::mark_found (the
#      on_pick sequence) -> VDW hidden 1 / found 1, Lines untouched 2/0;
#      remaining_by_rep -> Lines 2, VDW 1.
#   7. cleanup: registry 0, game molid DEAD, restored molecule numreps ==
#      the original's pre-start numreps (no game-rep leak).
#   8. Backward-compat containment: 2-ARG start_game on 1k8p randomizes
#      across IMPLEMENTED_TIERS (quick-008). Assertions are INVARIANT-BASED
#      (randomize_per_rep guarantees a non-empty subset with sum <= total --
#      the 14-01 sum_le_total pin -- NOT the full total, so no hard-coded
#      count): game_state hider_count == effective_total(per_rep); 1 <=
#      hider_count <= 5; per_rep keys subset of IMPLEMENTED_TIERS;
#      count_hiders == hider_count (no under-generation on 1k8p: heavy-atom
#      anchors >> 5); numreps == pre2 + 2*(#active tiers); user3 stamps match
#      the derived table (the split proof generalizes to N tiers).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the
# entry itself): setup_state, registry, rep_tiers (17.1-01, NOW in the
# order), generators, game_logic, demos, backup, mutation, hiders, game.
# registry is sourced EXACTLY ONCE (re-sourcing would WIPE _records).
#
# PLAN-DETAIL NOTES (documented, not silently bent): the plan's step-1
# detail asserted per_rep == {VDW 2 Lines 2} (the INPUT argument order);
# the pinned 17.1-01 resolve_per_rep contract is GAME_REPS-ordered OUTPUT
# ({Lines 2 VDW 2}) and wins -- asserted via keys-order + per-key counts.
# Same for step 8: the plan's "registry count == 5" holds only on draws
# that distribute the full total; randomize_per_rep's pinned contract is
# sum <= total (non-empty), so the invariants above are asserted instead.
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT propagate
# tcl exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER
# $?; VMD -e catches top-level errors and CONTINUES (possible false-PASS)
# -> every step is wrapped in catch + _bail, and the runner scans the FULL
# log for ERROR) / bad switch lines (the regexp -- false-PASS lesson).
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
set tiers [list]
set pr [list]
set restored_molid -1

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's order minus the GUI
#      files; rep_tiers added after game_logic (the 17.1-06 entry order). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry    [file join [pwd] vmd lib registry.tcl] \
    rep_tiers   [file join [pwd] vmd lib rep_tiers.tcl] \
    generators  [file join [pwd] vmd lib generators.tcl] \
    game_logic  [file join [pwd] vmd lib game_logic.tcl] \
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

# ---- 1. SETUP: load 1znf (424 atoms), capture pre-start numreps, start an
#         EXPLICIT 2-tier round: {VDW 2 Lines 2}, lock_scene 0. ----
if {[catch {::biochemeleon::demos::load_demo 1znf} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    set pre_reps [molinfo $orig_molid get numreps]
    if {![catch {::biochemeleon::game::start_game $orig_molid 4 [dict create VDW 2 Lines 2] 0} gs]} {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            # 1a: 424 + 4 = 428 atoms on the combined molecule.
            set n1 [molinfo $gm get numatoms]
            if {$n1 != 428} { _bail game_atoms "exp=428 got=$n1" }
            # 1b: hider indices == {424 425 426 427} (file order == record
            #     order; the tier split below slices THIS list).
            if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hider_idxs]} {
                _bail fetch_idx $hider_idxs
                set hider_idxs [list]
            } elseif {$hider_idxs ne {424 425 426 427}} {
                _bail hider_idx "got=$hider_idxs"
            }
            # 1c: game_state hider_count == 4 (the EFFECTIVE total, P9).
            if {[catch {dict get $gs hider_count} eff]} {
                _bail gs_hider_count "missing"
            } elseif {$eff != 4} {
                _bail eff_total "exp=4 got=$eff"
            }
            # 1d: per_rep stashed, 2 keys, Lines 2 / VDW 2, GAME_REPS-ordered
            #     keys (resolve_per_rep's pinned 17.1-01 output contract).
            if {![dict exists $gs per_rep]} {
                _bail gs_per_rep "missing"
            } else {
                set pr [dict get $gs per_rep]
                if {[catch {dict size $pr} psz]} {
                    _bail per_rep_size $psz
                } else {
                    if {$psz != 2} { _bail per_rep_size "exp=2 got=$psz" }
                    if {[catch {dict get $pr Lines} lines_cnt] || $lines_cnt != 2} {
                        _bail per_rep_lines "exp=2 got=$lines_cnt"
                    }
                    if {[catch {dict get $pr VDW} vdw_cnt] || $vdw_cnt != 2} {
                        _bail per_rep_vdw "exp=2 got=$vdw_cnt"
                    }
                    if {![catch {dict keys $pr} prk]} {
                        if {$prk ne {Lines VDW}} {
                            _bail per_rep_order "got=$prk (expect GAME_REPS order: Lines precedes VDW)"
                        }
                    } else { _bail per_rep_keys $prk }
                }
            }

            # ---- 2. TIER ORDER (GAME_REPS order: Lines precedes VDW) +
            #         user3 stamps. The expected code-per-index map is
            #         DERIVED from tiers_from_per_rep over the stashed
            #         per_rep, then asserted (never hard-coded blindly). ----
            if {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $pr} tiers]} {
                _bail tiers_from_per_rep $tiers
            } else {
                if {[llength $tiers] != 2} {
                    _bail tier_table_len "exp=2 got=$tiers"
                } else {
                    lassign [lindex $tiers 0] tcode1 tstyle1 tcnt1
                    lassign [lindex $tiers 1] tcode2 tstyle2 tcnt2
                    if {$tcode1 != 1 || $tstyle1 ne "Lines" || $tcnt1 != 2} {
                        _bail tier1 "got=[lindex $tiers 0] (GAME_REPS order: Lines first)"
                    }
                    if {$tcode2 != 2 || $tstyle2 ne "VDW" || $tcnt2 != 2} {
                        _bail tier2 "got=[lindex $tiers 1] (VDW second, code 2)"
                    }
                    # Derived expectation: cumulative slices of the hider
                    # index list per tier's ACTUAL (== requested here) count.
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
                    # Real atoms keep user3 = 0 (P6 -- the sentinel conjunct
                    # must keep excluding them).
                    if {![catch {atomselect $gm "index 100"} s100]} {
                        set u3r [lindex [$s100 get user3] 0]
                        if {![_feq $u3r 0.0]} { _bail user3_real "exp=0.0 got=$u3r" }
                        $s100 delete
                    } else { _bail user3_sel_real $s100 }

                    # ---- 3. numreps == pre-start numreps + 4 (2N pairs;
                    #         scene reps survive apply, hider reps LAST). ----
                    set nreps [molinfo $gm get numreps]
                    if {$nreps != $pre_reps + 4} {
                        _bail rep_count "exp=[expr {$pre_reps + 4}] got=$nreps"
                    }

                    # ---- 4. PER-PAIR READ-BACK (COMBINED-BRACES form ONLY
                    #         -- the single-field form FAILS), driven off the
                    #         derived tier table. ----
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

                    # ---- 5. REGISTRY: count + per-tier remaining (fresh
                    #         round -- all hidden). ----
                    set ch [::biochemeleon::registry::count_hiders]
                    if {$ch != 4} { _bail reg_count "exp=4 got=$ch" }
                    if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
                        _bail remaining_by_rep $rbr
                    } else {
                        if {[dict size $rbr] != 2} {
                            _bail rbr_size "exp=2 got=$rbr"
                        }
                        foreach {rep expn} [list Lines 2 VDW 2] {
                            if {[catch {dict get $rbr $rep} got] || $got != $expn} {
                                _bail rbr_$rep "exp=$expn got=$got"
                            }
                        }
                    }

                    # ---- 6. A VDW FIND (426): mark_found_visual +
                    #         registry::mark_found (the on_pick sequence) ->
                    #         the partition re-splits ONLY the VDW tier. ----
                    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 426} merr]} {
                        _bail mark_found_visual $merr
                    } else {
                        if {[catch {::biochemeleon::registry::mark_found 426} mferr]} {
                            _bail registry_mark_found $mferr
                        }
                        foreach {selstr expn tag} [list \
                                {resname GAM and beta < 0 and user2 < 1 and user3 2} 1 vdw_hidden \
                                {resname GAM and beta < 0 and user2 > 0 and user3 2} 1 vdw_found \
                                {resname GAM and beta < 0 and user2 < 1 and user3 1} 2 lines_hidden \
                                {resname GAM and beta < 0 and user2 > 0 and user3 1} 0 lines_found] {
                            if {![catch {atomselect $gm $selstr} s]} {
                                if {[$s num] != $expn} {
                                    _bail $tag "exp=$expn got=[$s num]"
                                }
                                $s delete
                            } else { _bail ${tag}_sel $s }
                        }
                        if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
                            _bail remaining_by_rep2 $rbr2
                        } else {
                            foreach {rep expn} [list Lines 2 VDW 1] {
                                if {[catch {dict get $rbr2 $rep} got] || $got != $expn} {
                                    _bail rbr2_$rep "exp=$expn got=$got"
                                }
                            }
                        }
                    }

                    # ---- 7. CLEANUP/RESTORE: registry 0, game molid DEAD,
                    #         restored molecule numreps == the original's
                    #         pre-start numreps (no game-rep leak). ----
                    if {[catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
                        _bail cleanup $restored_molid
                    } else {
                        set ch2 [::biochemeleon::registry::count_hiders]
                        if {$ch2 != 0} { _bail reg_after_cleanup "exp=0 got=$ch2" }
                        if {![catch {molinfo $gm get numatoms} alive]} {
                            _bail game_molid_alive "molinfo on the deleted game molid succeeded (numatoms=$alive)"
                        }
                        if {[catch {molinfo $restored_molid get numreps} rn]} {
                            _bail restored_numreps $rn
                        } elseif {$rn != $pre_reps} {
                            _bail restored_numreps "exp=$pre_reps got=$rn"
                        }
                    }
                }
            }
        }
    } else {
        _bail start_game $gs
    }
}

# ---- 8. BACKWARD-COMPAT CONTAINMENT: 2-ARG start_game on 1k8p randomizes
#         across IMPLEMENTED_TIERS (quick-008). INVARIANT-based assertions
#         (randomize_per_rep's pinned contract: non-empty subset, sum <=
#         total -- NOT the full total), so no hard-coded counts. ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} m2]} {
    _bail load_1k8p $m2
} else {
    set pre2 [molinfo $m2 get numreps]
    if {![catch {::biochemeleon::game::start_game $m2 5} gs2]} {
        if {[catch {dict get $gs2 game_molid} gm2]} {
            _bail gs2_game_molid "missing (gs2=$gs2)"
        } else {
            if {[catch {dict get $gs2 per_rep} pr2]} {
                _bail gs2_per_rep "missing"
                set pr2 [list]
            }
            set eff2 -1
            if {[catch {dict get $gs2 hider_count} eff2]} {
                _bail gs2_hider_count "missing"
                set eff2 -1
            }
            if {$eff2 >= 0} {
                # P9: hider_count == effective_total(per_rep).
                set eff2c [::biochemeleon::rep_tiers::effective_total $pr2]
                if {$eff2 != $eff2c} {
                    _bail eff2_p9 "hider_count=$eff2 effective_total=$eff2c"
                }
                # quick-008 guarantees: non-empty subset, sum <= total.
                if {$eff2 < 1 || $eff2 > 5} {
                    _bail eff2_range "got=$eff2 (quick-008: 1 <= sum <= 5)"
                }
                # per_rep keys subset of IMPLEMENTED_TIERS.
                if {![catch {dict keys $pr2} prk2]} {
                    foreach k $prk2 {
                        if {[lsearch -exact $::biochemeleon::rep_tiers::IMPLEMENTED_TIERS $k] < 0} {
                            _bail per_rep2_containment "key '$k' not in IMPLEMENTED_TIERS"
                        }
                    }
                } else { _bail per_rep2_keys $prk2 }
                # Actual == effective on 1k8p (no under-generation: heavy-atom
                # anchors >> 5, so make_bonded_hiders' cap never bites).
                set ch3 [::biochemeleon::registry::count_hiders]
                if {$ch3 != $eff2} {
                    _bail reg2_count "exp=$eff2 got=$ch3"
                }
                # remaining_by_rep: keys in IMPLEMENTED_TIERS, sum == count.
                if {[catch {::biochemeleon::registry::remaining_by_rep} rbr3]} {
                    _bail remaining_by_rep3 $rbr3
                } else {
                    set sum2 0
                    foreach {rep cnt} $rbr3 {
                        if {[lsearch -exact $::biochemeleon::rep_tiers::IMPLEMENTED_TIERS $rep] < 0} {
                            _bail rbr3_containment "key '$rep' not in IMPLEMENTED_TIERS"
                        }
                        incr sum2 $cnt
                    }
                    if {$sum2 != $eff2} {
                        _bail rbr3_sum "exp=$eff2 got=$sum2"
                    }
                }
                # Structural: numreps == pre2 + 2*(#active tiers).
                if {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $pr2} tiers2]} {
                    _bail tiers_from_per_rep2 $tiers2
                    set tiers2 [list]
                }
                set nreps2 [molinfo $gm2 get numreps]
                set exp_nreps2 [expr {$pre2 + 2 * [llength $tiers2]}]
                if {$nreps2 != $exp_nreps2} {
                    _bail rep_count2 "exp=$exp_nreps2 got=$nreps2"
                }
                # user3 stamps match the DERIVED table (the split proof
                # generalizes to any N-tier draw). Exact only because 1k8p
                # cannot under-generate at these counts (asserted above).
                if {![catch {::biochemeleon::mutation::fetch_hider_indices $gm2} idxs2]} {
                    if {[llength $idxs2] != $eff2} {
                        _bail idxs2_count "exp=$eff2 got=[llength $idxs2]"
                    } else {
                        set exp2 [dict create]
                        set off2 0
                        foreach t $tiers2 {
                            lassign $t cc ss kk
                            for {set i 0} {$i < $kk && $off2 < [llength $idxs2]} {incr i} {
                                dict set exp2 [lindex $idxs2 $off2] $cc
                                incr off2
                            }
                        }
                        foreach idx $idxs2 {
                            if {![dict exists $exp2 $idx]} { continue }
                            set e [dict get $exp2 $idx]
                            if {![catch {atomselect $gm2 "index $idx"} s]} {
                                set u3 [lindex [$s get user3] 0]
                                if {![_feq $u3 $e]} {
                                    _bail user3_2_$idx "exp=$e got=$u3"
                                }
                                $s delete
                            } else { _bail user3_2_sel_$idx $s }
                        }
                    }
                } else { _bail fetch_idx2 $idxs2 }
                # cleanup gs2 (round over; registry back to 0).
                if {[catch {::biochemeleon::game::cleanup $gs2} r2]} {
                    _bail cleanup2 $r2
                } else {
                    set ch4 [::biochemeleon::registry::count_hiders]
                    if {$ch4 != 0} { _bail reg_after_cleanup2 "exp=0 got=$ch4" }
                }
            }
        }
    } else {
        _bail start_game2 $gs2
    }
}

# ---- 9. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
