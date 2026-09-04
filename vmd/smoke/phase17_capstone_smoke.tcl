# vmd/smoke/phase17_capstone_smoke.tcl
# Phase-17.1 (17.1-13) CAPSTONE headless smoke: tiers MIXING in one round +
# the lock-scene derivation + under-generation tolerance, all through the
# real 17.1-06 dispatch. Structure copied from the 17.1-06 dispatch template
# (the per-tier smokes own Tachyon renders; the capstone owns round
# composition + bookkeeping -- no renders here, per the plan).
#
# Proves (the 17.1-13 must-haves), on demo 1znf (424 atoms):
#   ROUND A -- MIXED 3-tier round:
#     game::start_game $molid 5 [dict create VDW 2 Lines 2 Licorice 1] 0
#     1. 429-atom game molecule; hider indices {424..428}; game_state
#        hider_count == 5 (the P9 effective total: the explicit per_rep
#        sums to 5 -- no top-up, no drop on this draw).
#     2. per_rep stashed GAME_REPS-ordered: keys {Lines VDW Licorice},
#        counts 2/2/1 (resolve_per_rep's pinned 17.1-01 output contract).
#     3. Tier codes 1..3 in GAME_REPS order (the code map is DERIVED from
#        rep_tiers::tiers_from_per_rep, never hard-coded): code 1 = Lines
#        -> user3 1.0 on 424-425; code 2 = VDW -> 2.0 on 426-427; code 3 =
#        Licorice -> 3.0 on 428 (float read-back, numeric compare only,
#        P10). A real atom keeps user3 == 0.0 (P6).
#     4. numreps == pre_start + 6 (3 hidden/found pairs; hider reps LAST).
#     5. Per-pair read-back via tier_reps + mol repindex (COMBINED-BRACES
#        molinfo form ONLY -- the single-field form FAILS, Pitfall 3):
#        hidden = tier style + Element + the "user2 < 1 and user3 <code>"
#        selection; found = tier style + ColorID 7 + the "user2 > 0"
#        variant -- for ALL three tiers.
#     6. Registry: count_hiders == 5; remaining_by_rep keys {Lines VDW
#        Licorice} (first-hidden-record order == GAME_REPS tier order)
#        with counts 2/2/1. Difficulty-agnostic (remaining_by_rep groups
#        by rep regardless of the difficulty flag).
#     7. Find ONE hider per tier (425 = Lines, 426 = VDW, 428 = Licorice;
#        mark_found_visual + registry::mark_found -- the on_pick sequence):
#        count_remaining == 2; remaining_by_rep {Lines 1 VDW 1} (Licorice
#        ABSENT -- no zero-fill, registry.tcl); per-tier user2 partitions
#        exact: Lines 1 hidden / 1 found, VDW 1/1, Licorice 0/1.
#     8. cleanup: registry 0; game molid DEAD; restored original 424 atoms
#        with numreps == pre_start (no game-rep leak).
#   ROUND B -- LOCK-SCENE round (ROADMAP SC2):
#     fresh 1znf -> mol modstyle 0 $m2 Licorice (P-1 read-back BEFORE
#     start_game) -> game::start_game $m2 4 {} 1.
#     9.  Detection + restriction: per_rep keys == {Licorice} EXACTLY --
#         the scene's own rep style is the ONLY allowed tier (the
#         derivation proof: scene_reps_to_per_rep saw Licorice, resolve
#         restricted the randomize to it).
#    10.  Consistency chain (INVARIANT-BASED -- see PLAN-DETAIL below):
#         n = per_rep(Licorice) in [1, 4]; game_state hider_count ==
#         rep_tiers::effective_total(per_rep) == n (P9); atoms == 424 + n;
#         hider indices {424..423+n}; user3 == 1.0 on ALL of them
#         (Licorice is code 1); numreps == pre-styled-scene (1) + 2 == 3;
#         registry count == n; remaining_by_rep == {Licorice n}; the
#         Licorice pair's read-back style == Licorice + selections carry
#         "user3 1".
#    11.  cleanup: registry 0; game molid dead; restored original's rep-0
#         style STILL reads Licorice (snapshot fidelity -- 17.1-10 pattern).
#   ROUND C -- UNDER-GENERATION tolerance (v1 parity):
#     fresh 1znf -> game::start_game $m3 3 [dict create Cartoon 2 VDW 1] 0
#    12.  Cartoon (unimplemented in 17.1) is DROPPED with a vmdcon -warn
#         (the RUNNER greps the full log for "no generator yet" -- a
#         Warning) line, never an ERROR) line): per_rep == {VDW 1};
#         game_state hider_count == 1 (the P9 EFFECTIVE total, NOT the
#         requested 3); 425-atom molecule; hider {424} with user3 1.0;
#         numreps == pre3 + 2; registry count 1; remaining_by_rep
#         {VDW 1}; cleanup restores the original.
#
# PLAN-DETAIL NOTE (documented, not silently bent): the plan's round-B prose
# pinned "remaining_by_rep == {Licorice 4}; hider count 4" -- but resolve's
# empty-per_rep + lock_scene=1 path goes through randomize_per_rep, whose
# pinned quick-008 contract is a NON-EMPTY SUBSET with sum <= hider_count
# (NOT ==; 14-01 sum_le_total). 17.1-06's dispatch smoke hit the identical
# conflict in its step 8 ("registry count == 5" held only on full-total
# draws) and pinned the invariant form. With a SINGLE allowed tier the
# subset is FORCED to {Licorice} (the lock-scene derivation proof -- #9)
# but the drawn count is 1..4 draw-dependent. The consistency chain (#10)
# replaces the literal pins: identical proof strength for the derivation,
# robust across independent PRNG draws (the 3/3-runs methodology).
#
# Harness per 17.1-08/-06: -e'd by VMD -> [info script] is EMPTY (Pitfall 3)
# -> [pwd]-based paths (VMD cwd = staging root); VMD does NOT propagate tcl
# exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?;
# VMD -e catches top-level errors and CONTINUES (false-PASS risk) -> every
# step is catch-wrapped + the runner scans the FULL log for ERROR) /
# "bad switch" lines (the regexp -- false-PASS lesson). THIS PLAN EDITS NO
# LIB FILES (defects -> SUMMARY for a gap plan).
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently). Sources the lib files in dependency order (mirrors the entry,
# NOT the entry itself); registry sourced EXACTLY ONCE (re-sourcing would
# WIPE _records).

set failures [list]

proc _bail {tag msg} {
    global failures
    lappend failures "$tag:$msg"
}

# Float read-back compare (user2/user3 are FLOATS -- numeric only, P10).
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Assert the user3 float stamp on ONE index (numeric compare, P10).
# _bail uses `global failures`, so this is safe at any call depth.
proc _check_user3 {gm idx exp tag} {
    if {![catch {atomselect $gm "index $idx"} s]} {
        set u3 [lindex [$s get user3] 0]
        if {![_feq $u3 $exp]} {
            _bail $tag "exp=$exp got=$u3"
        }
        $s delete
    } else {
        _bail ${tag}_sel $s
    }
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
set m2 -1
set gs2 [list]
set gm2 -1
set pre2 -1
set n2 -1
set restored2 -1
set m3 -1
set gs3 [list]
set gm3 -1
set pre3 -1
set restored3 -1

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's order minus the GUI
#      files; rep_tiers after game_logic (the 17.1-06 entry order). ----
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

# =====================================================================
# ROUND A: MIXED 3-tier round -- {VDW 2 Lines 2 Licorice 1}, lock 0.
# =====================================================================
if {[catch {::biochemeleon::demos::load_demo 1znf} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    set pre_reps [molinfo $orig_molid get numreps]
    if {[catch {::biochemeleon::game::start_game $orig_molid 5 [dict create VDW 2 Lines 2 Licorice 1] 0} gs]} {
        _bail start_game_mixed $gs
    } elseif {[catch {dict get $gs game_molid} gm]} {
        _bail gs_key_game_molid "missing (gs=$gs)"
    } else {
        # ---- A1: 424 + 5 = 429 atoms; hider indices {424..428} (file
        #         order == record order; the tier split slices THIS list). ----
        set n1 [molinfo $gm get numatoms]
        if {$n1 != 429} { _bail game_atoms "exp=429 got=$n1" }
        if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hider_idxs]} {
            _bail fetch_idx $hider_idxs
            set hider_idxs [list]
        } elseif {$hider_idxs ne {424 425 426 427 428}} {
            _bail hider_idx "got=$hider_idxs"
        }
        # ---- A2: game_state hider_count == 5 (P9 effective total: the
        #         explicit per_rep sums to 5 -- no top-up, no drop). ----
        if {[catch {dict get $gs hider_count} eff]} {
            _bail gs_hider_count "missing"
        } elseif {$eff != 5} {
            _bail eff_total "exp=5 got=$eff"
        }
        # ---- A3: per_rep stashed GAME_REPS-ordered {Lines VDW Licorice}
        #         counts 2/2/1 (the 17.1-01 pinned output contract). ----
        if {![dict exists $gs per_rep]} {
            _bail gs_per_rep "missing"
        } else {
            set pr [dict get $gs per_rep]
            if {[catch {dict size $pr} psz]} {
                _bail per_rep_size $psz
            } else {
                if {$psz != 3} { _bail per_rep_size "exp=3 got=$psz" }
                foreach {rep expn} [list Lines 2 VDW 2 Licorice 1] {
                    if {[catch {dict get $pr $rep} c] || $c != $expn} {
                        _bail per_rep_$rep "exp=$expn got=$c"
                    }
                }
                if {![catch {dict keys $pr} prk]} {
                    if {$prk ne {Lines VDW Licorice}} {
                        _bail per_rep_order "got=$prk (expect GAME_REPS order: Lines VDW Licorice)"
                    }
                } else { _bail per_rep_keys $prk }
            }
        }

        # ---- A4: TIER ORDER (GAME_REPS order) + derived code map +
        #         user3 stamps. The expected code-per-index map is DERIVED
        #         from tiers_from_per_rep over the stashed per_rep, then
        #         asserted (never hard-coded blindly). ----
        if {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $pr} tiers]} {
            _bail tiers_from_per_rep $tiers
        } else {
            if {[llength $tiers] != 3} {
                _bail tier_table_len "exp=3 got=$tiers"
            } else {
                lassign [lindex $tiers 0] tc1 ts1 tk1
                lassign [lindex $tiers 1] tc2 ts2 tk2
                lassign [lindex $tiers 2] tc3 ts3 tk3
                if {$tc1 != 1 || $ts1 ne "Lines" || $tk1 != 2} {
                    _bail tier1 "got=[lindex $tiers 0] (GAME_REPS order: Lines first, code 1)"
                }
                if {$tc2 != 2 || $ts2 ne "VDW" || $tk2 != 2} {
                    _bail tier2 "got=[lindex $tiers 1] (VDW second, code 2)"
                }
                if {$tc3 != 3 || $ts3 ne "Licorice" || $tk3 != 1} {
                    _bail tier3 "got=[lindex $tiers 2] (Licorice third, code 3)"
                }
                # Derived expectation: cumulative slices of the hider index
                # list per tier's ACTUAL (== requested here) count.
                set exp_code [dict create]
                set off 0
                if {[llength $hider_idxs] != 5} {
                    _bail hider_idx_len "exp=5 got=[llength $hider_idxs]"
                }
                foreach t $tiers {
                    lassign $t cc ss kk
                    for {set i 0} {$i < $kk && $off < [llength $hider_idxs]} {incr i} {
                        dict set exp_code [lindex $hider_idxs $off] $cc
                        incr off
                    }
                }
                if {[dict size $exp_code] != 5} {
                    _bail exp_code_size "exp=5 got=[dict size $exp_code]"
                }
                foreach idx $hider_idxs {
                    if {![dict exists $exp_code $idx]} { continue }
                    _check_user3 $gm $idx [dict get $exp_code $idx] user3_$idx
                }
                # Real atoms keep user3 = 0 (P6 -- the sentinel conjunct
                # must keep excluding them).
                _check_user3 $gm 100 0.0 user3_real

                # ---- A5: numreps == pre-start numreps + 6 (3 pairs;
                #         scene reps survive apply, hider reps LAST). ----
                set nreps [molinfo $gm get numreps]
                if {$nreps != $pre_reps + 6} {
                    _bail rep_count "exp=[expr {$pre_reps + 6}] got=$nreps"
                }

                # ---- A6: PER-PAIR READ-BACK (COMBINED-BRACES form ONLY)
                #         for all three tiers, driven off the derived table. ----
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

                # ---- A7: REGISTRY: count + per-tier remaining (fresh
                #         round -- all hidden). ----
                set ch [::biochemeleon::registry::count_hiders]
                if {$ch != 5} { _bail reg_count "exp=5 got=$ch" }
                if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
                    _bail remaining_by_rep $rbr
                } else {
                    if {[dict size $rbr] != 3} {
                        _bail rbr_size "exp=3 got=$rbr"
                    }
                    if {![catch {dict keys $rbr} rbrk]} {
                        if {$rbrk ne {Lines VDW Licorice}} {
                            _bail rbr_keys "got=$rbrk (expect first-hidden-record order: Lines VDW Licorice)"
                        }
                    } else { _bail rbr_keys $rbrk }
                    foreach {rep expn} [list Lines 2 VDW 2 Licorice 1] {
                        if {[catch {dict get $rbr $rep} got] || $got != $expn} {
                            _bail rbr_$rep "exp=$expn got=$got"
                        }
                    }
                }

                # ---- A8: FIND ONE PER TIER (425 Lines, 426 VDW, 428
                #         Licorice): mark_found_visual + registry::mark_found
                #         (the on_pick sequence). Then the partition
                #         re-splits per tier EXACTLY. ----
                foreach {fidx tier_tag} [list 425 lines 426 vdw 428 licorice] {
                    if {[catch {::biochemeleon::hiders::mark_found_visual $gm $fidx} merr]} {
                        _bail mark_found_visual_$tier_tag $merr
                    } elseif {[catch {::biochemeleon::registry::mark_found $fidx} mferr]} {
                        _bail registry_mark_found_$tier_tag $mferr
                    }
                }
                set rem [::biochemeleon::registry::count_remaining]
                if {$rem != 2} { _bail remaining "exp=2 got=$rem" }
                if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
                    _bail remaining_by_rep2 $rbr2
                } else {
                    if {[dict size $rbr2] != 2} {
                        _bail rbr2_size "exp=2 got=$rbr2 (Licorice absent -- no zero-fill)"
                    }
                    foreach {rep expn} [list Lines 1 VDW 1] {
                        if {[catch {dict get $rbr2 $rep} got] || $got != $expn} {
                            _bail rbr2_$rep "exp=$expn got=$got"
                        }
                    }
                }
                # Per-tier user2 partitions exact after the three finds.
                foreach {selstr expn tag} [list \
                        {resname GAM and beta < 0 and user2 < 1 and user3 1} 1 lines_hidden \
                        {resname GAM and beta < 0 and user2 > 0 and user3 1} 1 lines_found \
                        {resname GAM and beta < 0 and user2 < 1 and user3 2} 1 vdw_hidden \
                        {resname GAM and beta < 0 and user2 > 0 and user3 2} 1 vdw_found \
                        {resname GAM and beta < 0 and user2 < 1 and user3 3} 0 licorice_hidden \
                        {resname GAM and beta < 0 and user2 > 0 and user3 3} 1 licorice_found] {
                    if {![catch {atomselect $gm $selstr} s]} {
                        if {[$s num] != $expn} {
                            _bail $tag "exp=$expn got=[$s num]"
                        }
                        $s delete
                    } else { _bail ${tag}_sel $s }
                }

                # ---- A9: CLEANUP/RESTORE: registry 0, game molid DEAD,
                #         restored original 424 atoms, numreps == the
                #         original's pre-start numreps (no game-rep leak). ----
                if {[catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
                    _bail cleanup $restored_molid
                } else {
                    set ch2 [::biochemeleon::registry::count_hiders]
                    if {$ch2 != 0} { _bail reg_after_cleanup "exp=0 got=$ch2" }
                    if {![catch {molinfo $gm get numatoms} alive]} {
                        _bail game_molid_alive "molinfo on the deleted game molid succeeded (numatoms=$alive)"
                    }
                    if {[catch {molinfo $restored_molid get numatoms} rnat]} {
                        _bail restored_atoms $rnat
                    } elseif {$rnat != 424} {
                        _bail restored_atoms "exp=424 got=$rnat"
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
}

# =====================================================================
# ROUND B: LOCK-SCENE round -- fresh 1znf, rep 0 pre-styled Licorice,
# start_game $m2 4 {} 1. ROADMAP SC2: lock-scene detects + matches;
# randomize distributes (onto the detected tier).
# =====================================================================
if {[catch {::biochemeleon::demos::load_demo 1znf} m2]} {
    _bail load_demo_b $m2
} else {
    set pre2 [molinfo $m2 get numreps]
    if {$pre2 != 1} {
        _bail pre2_reps "exp=1 got=$pre2 (the scene must have exactly its default rep)"
    }
    # Pre-style rep 0 with the tier's canonical style + P-1 read-back
    # BEFORE start_game (the 17.1-10 pre-styled-scene pattern -- a bad
    # style only console-ERRORs and no-ops, so read-back is the gate).
    if {[catch {mol modstyle 0 $m2 Licorice} me2]} {
        _bail pre_modstyle $me2
    } else {
        set st2 ""
        if {[catch {foreach {st2} [molinfo $m2 get "{rep 0}"] { break }} rb2]} {
            _bail pre_style_readback $rb2
        } elseif {$st2 ne "Licorice"} {
            _bail pre_style "exp=Licorice got=$st2"
        }
        if {[catch {::biochemeleon::game::start_game $m2 4 {} 1} gs2]} {
            _bail start_game_lock $gs2
        } elseif {[catch {dict get $gs2 game_molid} gm2]} {
            _bail gs2_game_molid "missing (gs2=$gs2)"
        } else {
            # ---- B1: per_rep keys == {Licorice} EXACTLY (the lock-scene
            #         derivation proof: detection + restriction). ----
            set pr2 [list]
            if {[dict exists $gs2 per_rep]} {
                set pr2 [dict get $gs2 per_rep]
            } else {
                _bail gs2_per_rep "missing"
            }
            if {![catch {dict size $pr2} psz2]} {
                if {$psz2 != 1} {
                    _bail lock_per_rep_size "exp=1 got=$psz2 (per_rep=$pr2)"
                }
            } else { _bail lock_per_rep_size $psz2 }
            if {![catch {dict keys $pr2} prk2]} {
                if {$prk2 ne {Licorice}} {
                    _bail lock_per_rep_keys "got=$prk2 (the lock-scene derivation must yield ONLY the detected tier)"
                }
            } else { _bail lock_per_rep_keys $prk2 }
            # ---- B2 prep: the drawn count (invariant range -- see the
            #         PLAN-DETAIL note in the header). ----
            if {[catch {dict get $pr2 Licorice} n2]} {
                _bail lock_count $n2
                set n2 -1
            } elseif {$n2 < 1 || $n2 > 4} {
                _bail lock_count_range "got=$n2 (quick-008: 1 <= sum <= 4)"
            }
            if {$n2 >= 1} {
                # ---- B2: the P9 consistency chain. ----
                if {[catch {dict get $gs2 hider_count} eff2]} {
                    _bail gs2_hider_count "missing"
                } else {
                    set eff2c [::biochemeleon::rep_tiers::effective_total $pr2]
                    if {$eff2 != $n2 || $eff2 != $eff2c} {
                        _bail lock_p9 "hider_count=$eff2 per_rep(Licorice)=$n2 effective_total=$eff2c"
                    }
                }
                # ---- B3: atoms == 424 + n; hider indices contiguous
                #         from 424 (file order == record order). ----
                set nb [molinfo $gm2 get numatoms]
                if {$nb != 424 + $n2} {
                    _bail game_atoms_b "exp=[expr {424 + $n2}] got=$nb"
                }
                if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm2} idxsB]} {
                    _bail fetch_idx_b $idxsB
                } else {
                    set expB [list]
                    for {set i 0} {$i < $n2} {incr i} {
                        lappend expB [expr {424 + $i}]
                    }
                    if {$idxsB ne $expB} {
                        _bail hider_idx_b "got=$idxsB exp=$expB"
                    }
                    # ---- B4: user3 == 1.0 on ALL hiders (Licorice is the
                    #         only tier -> code 1). ----
                    foreach idx $idxsB {
                        _check_user3 $gm2 $idx 1.0 user3_b_$idx
                    }
                }
                # ---- B5: numreps == pre-styled scene (1) + 2. ----
                set nrB [molinfo $gm2 get numreps]
                if {$nrB != $pre2 + 2} {
                    _bail rep_count_b "exp=[expr {$pre2 + 2}] got=$nrB"
                }
                # ---- B6: the Licorice pair's read-back: style Licorice,
                #         hidden Element / found ColorID 7, selections
                #         carry "user3 1". ----
                if {![dict exists $::biochemeleon::hiders::tier_reps 1]} {
                    _bail tier_reps_b_missing 1
                } else {
                    lassign [dict get $::biochemeleon::hiders::tier_reps 1] hnB fnB hsB fsB
                    foreach {rname rrep rexp_sel} [list \
                            hidden $hnB {resname GAM and beta < 0 and user2 < 1 and user3} \
                            found  $fnB {resname GAM and beta < 0 and user2 > 0 and user3}] {
                        if {[catch {mol repindex $gm2 $rrep} ridxB] || $ridxB < 0} {
                            _bail b_${rname}_repindex "name=$rrep repindex=$ridxB"
                            continue
                        }
                        set stB ""; set slB ""; set clB ""; set mtB ""
                        if {[catch {foreach {stB slB clB mtB} [molinfo $gm2 get "{rep $ridxB} {selection $ridxB} {color $ridxB} {material $ridxB}"] { break }} rbB]} {
                            _bail b_${rname}_readback $rbB
                            continue
                        }
                        if {$stB ne "Licorice"} {
                            _bail b_${rname}_style "exp=Licorice got=$stB"
                        }
                        set exp_colB "Element"
                        if {$rname eq "found"} { set exp_colB {ColorID 7} }
                        if {$clB ne $exp_colB} {
                            _bail b_${rname}_color "exp=$exp_colB got=$clB"
                        }
                        set exp_selB "$rexp_sel 1"
                        if {$slB ne $exp_selB} {
                            _bail b_${rname}_sel "exp=$exp_selB got=$slB"
                        }
                    }
                }
                # ---- B7: registry count == n; remaining_by_rep ==
                #         {Licorice n}. ----
                set chB [::biochemeleon::registry::count_hiders]
                if {$chB != $n2} { _bail reg_count_b "exp=$n2 got=$chB" }
                if {[catch {::biochemeleon::registry::remaining_by_rep} rbrB]} {
                    _bail remaining_by_rep_b $rbrB
                } else {
                    if {[dict size $rbrB] != 1} {
                        _bail rbrB_size "exp=1 got=$rbrB"
                    }
                    if {[catch {dict get $rbrB Licorice} gotB] || $gotB != $n2} {
                        _bail rbrB_licorice "exp=$n2 got=$gotB"
                    }
                }
            }
            # ---- B8: CLEANUP + SNAPSHOT FIDELITY: registry 0, game molid
            #         dead, restored original's rep-0 style STILL reads
            #         Licorice (the pre-style survives
            #         snapshot->apply->restore). ----
            if {[catch {::biochemeleon::game::cleanup $gs2} restored2]} {
                _bail cleanup_b $restored2
            } else {
                set chB2 [::biochemeleon::registry::count_hiders]
                if {$chB2 != 0} { _bail reg_after_cleanup_b "exp=0 got=$chB2" }
                if {![catch {molinfo $gm2 get numatoms} aliveB]} {
                    _bail game_molid_alive_b "molinfo on the deleted game molid succeeded (numatoms=$aliveB)"
                }
                set rstB ""
                if {[catch {foreach {rstB} [molinfo $restored2 get "{rep 0}"] { break }} rbR]} {
                    _bail restore_style_readback $rbR
                } elseif {$rstB ne "Licorice"} {
                    _bail restore_style "exp=Licorice got=$rstB (snapshot fidelity)"
                }
            }
        }
    }
}

# =====================================================================
# ROUND C: UNDER-GENERATION tolerance -- Cartoon 2 is requested but has
# NO generator in 17.1: dropped with a vmdcon -warn (v1 under-generation
# parity); only VDW 1 survives; the P9 effective total (1), NOT the
# requested 3, becomes the round's hider_count.
# =====================================================================
if {[catch {::biochemeleon::demos::load_demo 1znf} m3]} {
    _bail load_demo_c $m3
} else {
    set pre3 [molinfo $m3 get numreps]
    if {[catch {::biochemeleon::game::start_game $m3 3 [dict create Cartoon 2 VDW 1] 0} gs3]} {
        _bail start_game_undergen $gs3
    } elseif {[catch {dict get $gs3 game_molid} gm3]} {
        _bail gs3_game_molid "missing (gs3=$gs3)"
    } else {
        # ---- C1: per_rep == {VDW 1} (Cartoon dropped); hider_count == 1
        #         (the P9 EFFECTIVE total). The drop's vmdcon -warn line is
        #         asserted by the RUNNER (grep "no generator yet" -- a
        #         Warning) line, never an ERROR) line). ----
        set pr3 [list]
        if {[dict exists $gs3 per_rep]} {
            set pr3 [dict get $gs3 per_rep]
        } else {
            _bail gs3_per_rep "missing"
        }
        if {![catch {dict size $pr3} psz3]} {
            if {$psz3 != 1} {
                _bail undergen_per_rep_size "exp=1 got=$psz3 (per_rep=$pr3)"
            }
        } else { _bail undergen_per_rep_size $psz3 }
        if {![catch {dict get $pr3 VDW} c3]} {
            if {$c3 != 1} { _bail undergen_per_rep_vdw "exp=1 got=$c3" }
        } else { _bail undergen_per_rep_vdw $c3 }
        if {[catch {dict get $gs3 hider_count} eff3]} {
            _bail gs3_hider_count "missing"
        } elseif {$eff3 != 1} {
            _bail undergen_eff_total "exp=1 got=$eff3 (P9 effective total, not the requested 3)"
        }
        # ---- C2: 425 atoms; hider {424}; user3 1.0 (VDW is code 1). ----
        set n3c [molinfo $gm3 get numatoms]
        if {$n3c != 425} { _bail game_atoms_c "exp=425 got=$n3c" }
        if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm3} idxsC]} {
            _bail fetch_idx_c $idxsC
        } elseif {$idxsC ne {424}} {
            _bail hider_idx_c "got=$idxsC"
        } else {
            _check_user3 $gm3 424 1.0 user3_c_424
        }
        # ---- C3: numreps == pre3 + 2. ----
        set nrC [molinfo $gm3 get numreps]
        if {$nrC != $pre3 + 2} {
            _bail rep_count_c "exp=[expr {$pre3 + 2}] got=$nrC"
        }
        # ---- C4: registry count 1; remaining_by_rep {VDW 1}. ----
        set chC [::biochemeleon::registry::count_hiders]
        if {$chC != 1} { _bail reg_count_c "exp=1 got=$chC" }
        if {[catch {::biochemeleon::registry::remaining_by_rep} rbrC]} {
            _bail remaining_by_rep_c $rbrC
        } else {
            if {[dict size $rbrC] != 1} {
                _bail rbrC_size "exp=1 got=$rbrC"
            }
            if {[catch {dict get $rbrC VDW} gotC] || $gotC != 1} {
                _bail rbrC_vdw "exp=1 got=$gotC"
            }
        }
        # ---- C5: CLEANUP: registry 0, game molid dead, restored 424
        #         atoms. ----
        if {[catch {::biochemeleon::game::cleanup $gs3} restored3]} {
            _bail cleanup_c $restored3
        } else {
            set chC2 [::biochemeleon::registry::count_hiders]
            if {$chC2 != 0} { _bail reg_after_cleanup_c "exp=0 got=$chC2" }
            if {![catch {molinfo $gm3 get numatoms} aliveC]} {
                _bail game_molid_alive_c "molinfo on the deleted game molid succeeded (numatoms=$aliveC)"
            }
            if {[catch {molinfo $restored3 get numatoms} rnatC]} {
                _bail restored_atoms_c $rnatC
            } elseif {$rnatC != 424} {
                _bail restored_atoms_c "exp=424 got=$rnatC"
            }
        }
    }
}

# ---- Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
