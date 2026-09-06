# vmd/smoke/phase17_capstone_smoke.tcl
# Phase-17.2 (17.2-11) CAPSTONE headless smoke: the 17.1-13 composition
# capstone REWRITTEN for the widened seam (17.2-03: ALL 10 GAME_REPS
# generate -- Cartoon/NewCartoon/Trace/Tube via the shared residue splice)
# + the phase's acceptance shape: residue tiers MIXING with simple tiers in
# one round, the lock-scene derivation landing on a residue tier, and
# under-generation tolerance. All through the real start_game dispatch (the
# per-tier smokes own Tachyon renders; the capstone owns round composition
# + bookkeeping -- no renders here).
#
# Proves, on demo 1znf (424 atoms):
#   ROUND A -- MIXED 3-tier SIMPLE round (17.1-13, kept byte-identical --
#     still valid): game::start_game $molid 5 [dict create VDW 2 Lines 2
#     Licorice 1] 0 -> 429 atoms; hider {424..428}; P9 hider_count == 5;
#     per_rep {Lines VDW Licorice} 2/2/1 GAME_REPS-ordered; derived tier
#     codes -> user3 stamps 1/2/3; numreps pre+6; per-pair read-back;
#     registry 5 + remaining_by_rep {Lines VDW Licorice} 2/2/1; one find
#     per tier -> remaining 2, remaining_by_rep {Lines 1 VDW 1} (no
#     zero-fill); cleanup restores 424 atoms at pre-start numreps.
#   ROUND B -- LOCK-SCENE round (ROADMAP SC2, kept byte-identical):
#     fresh 1znf -> mol modstyle 0 $m2 Licorice -> start_game $m2 4 {} 1.
#     per_rep keys == {Licorice} EXACTLY (the derivation proof); the
#     INVARIANT chain (see PLAN-DETAIL below): n in [1, 4],
#     hider_count == effective_total == n, atoms 424+n, user3 1.0 on all,
#     numreps pre+2, registry n, remaining_by_rep {Licorice n}; cleanup
#     restores rep-0 style Licorice (snapshot fidelity).
#   ROUND C -- UNDER-GENERATION tolerance (REWRITTEN for the widened seam):
#     17.1-13's case requested {Cartoon 2 VDW 1} with Cartoon
#     unimplemented; Cartoon IMPLEMENTS since 17.2-03 (that case now
#     GENERATES -- it was asserting the pre-17.2 seam). The
#     unimplemented-style case moved to Ribbons: a VALID VMD style that is
#     NOT in GAME_REPS (viability section 5b) -- resolve_per_rep drops it
#     (non-GAME_REPS key, clean step a) and game.tcl's warning loop fires
#     (tier_kind "" -> vmdcon -warn; the RUNNER greps the warn line
#     "rep 'Ribbons' has no generator yet" -- a Warning) line, never an
#     ERROR) line).
#     fresh 1znf -> game::start_game $m3 3 [dict create Ribbons 2 VDW 1] 0
#    12.  per_rep == {VDW 1} (Ribbons dropped); game_state hider_count == 1
#         (the P9 EFFECTIVE total, NOT the requested 3); 425-atom molecule;
#         hider {424} with user3 1.0; numreps == pre3 + 2; registry count 1;
#         remaining_by_rep {VDW 1}; cleanup restores the original.
#   ROUND D -- MIXED RESIDUE round (NEW, 17.2-11): VDW 2 + Cartoon 2 in ONE
#     round -- the phase's acceptance shape (residue tiers MIX with simple
#     tiers). Explicit per_rep -> no randomize (request-side pins hold
#     unconditionally); the residue GENERATION may under-generate
#     (select_anchors' documented "May return fewer than n" contract,
#     17.2-10) -> layout asserts are OBSERVED-layout invariants (chain
#     classifier: simple records are hard-coded chain G, residue CAs carry
#     the anchor's chain) with the plan's exact pins asserted when
#     generation was full.
#     collapsed 1znf -> start_game $m4 4 [dict create VDW 2 Cartoon 2] 0
#    13.  per_rep {VDW 2 Cartoon 2} GAME_REPS-ordered + P9 hider_count == 4;
#         observed layout: 2 G sentinels {424 425} + nR residue CAs
#         (nR in [1, 2]); registry == sentinel count; resid block
#         9001+i -> the i-th CA (file order); remaining_by_rep
#         {VDW 2 Cartoon nR}; strict pins at full generation (436 atoms,
#         {424 425 427 432}, 9001->427, 9002->432).
#    14.  ONE fallback find through the PUBLIC surface: drive to playing
#         (the state gate), on_pick residue-1's C (CA+1, derived -- the C
#         is NOT registered) -> the resid-block fallback resolves the
#         registered CA: status found, user2(CA) > 0, user2(C) == 0 (the
#         CA-only design), remaining 3, remaining_by_rep {VDW 2 Cartoon 1}
#         at full generation.
#    15.  cleanup: registry 0 AND the resid block cleared; game molid DEAD;
#         restored 424 atoms at pre-start numreps.
#   ROUND E -- LOCK-SCENE CARTOON round (NEW, 17.2-11): the scene is
#     pre-styled Cartoon (a RESIDUE tier) + lock_scene 1 -- the derivation
#     must land ALL hiders on the detected residue tier (round B's
#     derivation proof, now on the residue machinery). Draw-adaptive
#     invariants per this file's own PLAN-DETAIL precedent (round B): with
#     the single allowed tier {Cartoon}, randomize_per_rep's quick-008
#     subset contract makes the drawn count n 1..3 (draw-dependent -- NOT
#     pinned); the INVARIANT chain pins the derivation, the observed
#     generation pins the layout.
#     collapsed 1znf -> mol modstyle 0 $m5 Cartoon -> start_game $m5 3 {} 1
#    16.  Derivation: per_rep keys == {Cartoon} EXACTLY; P9 chain
#         hider_count == effective_total(per_rep) == n.
#    17.  Observed residue round: registry == beta<0 count == n' in [1, n],
#         ALL sentinels CA (CA-only, no simple tier); user3 1.0 on all CAs
#         (single tier -> code 1); CA structures in the load-time-STRIDE
#         coil/turn family {T C} (recorded, never pinned); resid block
#         9001+i -> the i-th CA; numreps == pre5 + 2; the Cartoon pair's
#         read-back style Cartoon + selections "user3 1"; remaining_by_rep
#         == {Cartoon n'}.
#    18.  cleanup + snapshot fidelity: registry 0, block cleared, game
#         molid dead, restored original's rep-0 style STILL reads Cartoon,
#         restored 424 atoms.
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
set m4 -1
set gs4 [list]
set gm4 -1
set pre4 -1
set restored4 -1
set m5 -1
set gs5 [list]
set gm5 -1
set pre5 -1
set restored5 -1
# Recording-callback targets for round D's public-surface find (the same
# recorder shapes as the 17.2-09 dispatch smoke: LOG_LOG/WINS lists,
# REM_TICKS a scalar invocation counter).
set ::LOG_LOG [list]
set ::REM_TICKS 0
set ::WINS [list]

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
# ROUND C: UNDER-GENERATION tolerance -- REWRITTEN for the widened seam
# (17.2-03). The 17.1-13 case requested {Cartoon 2 VDW 1} with Cartoon
# unimplemented; Cartoon now IMPLEMENTS and GENERATES, so the
# unimplemented-style case moved to Ribbons: a VALID VMD style that is
# NOT in GAME_REPS (viability 5b) -- resolve_per_rep drops it
# (non-GAME_REPS key) and game.tcl's warning loop fires (tier_kind ""
# -> vmdcon -warn; the RUNNER greps "rep 'Ribbons' has no generator" --
# a Warning) line, never an ERROR) line). Only VDW 1 survives; the P9
# effective total (1), NOT the requested 3, becomes the round's
# hider_count.
# =====================================================================
if {[catch {::biochemeleon::demos::load_demo 1znf} m3]} {
    _bail load_demo_c $m3
} else {
    set pre3 [molinfo $m3 get numreps]
    if {[catch {::biochemeleon::game::start_game $m3 3 [dict create Ribbons 2 VDW 1] 0} gs3]} {
        _bail start_game_undergen $gs3
    } elseif {[catch {dict get $gs3 game_molid} gm3]} {
        _bail gs3_game_molid "missing (gs3=$gs3)"
    } else {
        # ---- C1: per_rep == {VDW 1} (Ribbons dropped -- a valid style
        #         excluded from GAME_REPS); hider_count == 1 (the P9
        #         EFFECTIVE total). The drop's vmdcon -warn line is
        #         asserted by the RUNNER (grep "rep 'Ribbons' has no
        #         generator" -- a Warning) line, never an ERROR) line). ----
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

# ---- Collapse loader (17.2-09 precedent): 1znf ships 2 models and the
#      residue generator (make_residue_hiders) needs deterministic
#      frame-0 geometry -> frame-0-pinned writepdb round-trip -> a
#      single-frame molecule (the same pipeline mutate uses downstream;
#      simple-only rounds A/B/C keep the plain loader). ----
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] cap172_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
}

# =====================================================================
# ROUND D: MIXED RESIDUE round -- VDW 2 + Cartoon 2 in ONE round (the
# phase's acceptance shape: residue tiers MIX with simple tiers).
# Explicit per_rep -> no randomize (request-side pins hold
# unconditionally). The residue GENERATION may under-generate
# (select_anchors' documented "May return fewer than n" contract,
# 17.2-10) -> layout asserts are OBSERVED-layout invariants (chain
# classifier: simple records are hard-coded chain G, residue CAs carry
# the anchor's chain) with the plan's exact pins asserted when
# generation was full (nR == 2 with all-CB records).
# =====================================================================
if {[catch {_load_demo_1f 1znf} m4]} {
    _bail load_demo_d $m4
} else {
    set n0d [molinfo $m4 get numatoms]
    if {$n0d != 424} { _bail orig_atoms_d "exp=424 got=$n0d" }
    set pre4 [molinfo $m4 get numreps]
    if {[catch {::biochemeleon::game::start_game $m4 4 [dict create VDW 2 Cartoon 2] 0} gs4]} {
        _bail start_game_mixed_residue $gs4
    } elseif {[catch {dict get $gs4 game_molid} gm4]} {
        _bail gs4_game_molid "missing (gs4=$gs4)"
    } else {
        # ---- D1: request-side pins (generation-independent): per_rep
        #         stashed GAME_REPS-ordered {VDW 2 Cartoon 2}; hider_count
        #         == 4 (the P9 EFFECTIVE total of the explicit per_rep --
        #         a residue hider counts 1, not 5); shape 4 keys; tier
        #         table {1 VDW 2} {2 Cartoon 2}. ----
        set prD [list]
        if {[dict exists $gs4 per_rep]} {
            set prD [dict get $gs4 per_rep]
        } else {
            _bail gs4_per_rep "missing"
        }
        if {![catch {dict keys $prD} prkD]} {
            if {$prkD ne {VDW Cartoon}} {
                _bail per_rep_order_d "got=$prkD (expect GAME_REPS order: VDW precedes Cartoon)"
            }
        } else { _bail per_rep_keys_d $prkD }
        foreach {rep expn} [list VDW 2 Cartoon 2] {
            if {[catch {dict get $prD $rep} cD] || $cD != $expn} {
                _bail per_rep_${rep}_d "exp=$expn got=$cD"
            }
        }
        if {[catch {dict get $gs4 hider_count} effD]} {
            _bail gs4_hider_count "missing"
        } elseif {$effD != 4} {
            _bail eff_total_d "exp=4 got=$effD (P9 effective total)"
        }
        if {[dict keys $gs4] ne "game_molid hider_count snapshot per_rep"} {
            _bail gs4_shape "got=[dict keys $gs4]"
        }
        if {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $prD} tiersD]} {
            _bail tiers_from_per_rep_d $tiersD
        } else {
            if {[llength $tiersD] != 2} {
                _bail tier_table_len_d "exp=2 got=$tiersD"
            } else {
                lassign [lindex $tiersD 0] tcD1 tsD1 tkD1
                lassign [lindex $tiersD 1] tcD2 tsD2 tkD2
                if {$tcD1 != 1 || $tsD1 ne "VDW" || $tkD1 != 2} {
                    _bail tier1_d "got=[lindex $tiersD 0] (VDW first, code 1)"
                }
                if {$tcD2 != 2 || $tsD2 ne "Cartoon" || $tkD2 != 2} {
                    _bail tier2_d "got=[lindex $tiersD 1] (Cartoon second, code 2)"
                }
            }
        }

        # ---- D2: OBSERVED layout (chain classifier, 17.2-10 pattern):
        #         fetch (beta<0) file order == record order, simple-first:
        #         the 2 G sentinels {424 425} (simple generation is
        #         deterministic), then nR residue CAs (nR in [1, 2] --
        #         select_anchors may under-generate). Registry == sentinel
        #         count. Atoms == 424 + 2 + 4*nR + cb, cb in [0, nR]
        #         (GLY anchors lack CB); the plan's exact pins hold at
        #         full generation (nR == 2 with all-CB records). ----
        set simpleD [list]
        set casD [list]
        if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm4} idxsD]} {
            _bail fetch_idx_d $idxsD
            set idxsD [list]
        }
        foreach xi $idxsD {
            if {![catch {atomselect $gm4 "index $xi"} sd]} {
                set chn [lindex [$sd get chain] 0]
                if {$chn eq "G"} {
                    lappend simpleD $xi
                } else {
                    lappend casD $xi
                }
                $sd delete
            } else { _bail layout_sel_d_$xi $sd }
        }
        set nR [llength $casD]
        set chD [::biochemeleon::registry::count_hiders]
        if {$chD != [llength $idxsD]} {
            _bail reg_count_d "exp=[llength $idxsD] got=$chD"
        }
        if {$simpleD ne {424 425}} {
            _bail simple_idx_d "got=$simpleD (exp the 2 VDW G sentinels, file-first)"
        }
        if {$nR < 1 || $nR > 2} {
            _bail residue_count_d "got=$nR (exp 1..2 -- select_anchors may under-generate)"
        }
        set natD [molinfo $gm4 get numatoms]
        set cbD [expr {$natD - 424 - 2 - 4 * $nR}]
        if {$cbD < 0 || $cbD > $nR} {
            _bail atoms_d "got=$natD (exp 424+2+4x$nR+cb, cb in \[0,$nR\])"
        }
        puts "CAPSTONE_D_INFO layout atoms=$natD simple=$simpleD res=$nR cb=$cbD cas=$casD idxs=$idxsD"
        if {$nR == 2 && $cbD == 2} {
            # ---- The plan's exact pins at FULL generation. ----
            if {$natD != 436} { _bail game_atoms_d "exp=436 got=$natD" }
            if {$idxsD ne {424 425 427 432}} {
                _bail hider_idx_d "got=$idxsD (exp VDW 424-425 + CAs 427/432)"
            }
            if {$casD ne {427 432}} {
                _bail ca_idx_d "got=$casD (exp CAs 427/432 at the file-layout slices)"
            }
        }
        # user3 stamps: VDW simple -> 1.0; residue CAs -> 2.0 (derived from
        # the tier table, numeric compare P10); real atoms keep 0 (P6).
        foreach xi $simpleD {
            _check_user3 $gm4 $xi 1.0 user3_d_simple_$xi
        }
        foreach xi $casD {
            _check_user3 $gm4 $xi 2.0 user3_d_ca_$xi
        }
        _check_user3 $gm4 100 0.0 user3_d_real

        # ---- D3: resid block zip (file order): 9001+i -> the i-th CA;
        #         9999 misses. At full generation: 9001->427, 9002->432.
        #         remaining_by_rep {VDW 2 Cartoon nR}. ----
        set zi 0
        foreach xi $casD {
            set rid [expr {9001 + $zi}]
            set rz [::biochemeleon::registry::hider_for_resid $rid]
            if {$rz ne $xi} {
                _bail resid_zip_d "$rid exp=$xi got=$rz"
            }
            incr zi
        }
        set rz9 [::biochemeleon::registry::hider_for_resid 9999]
        if {$rz9 ne ""} { _bail resid_9999_d "exp='' got=$rz9" }
        if {[catch {::biochemeleon::registry::remaining_by_rep} rbrD]} {
            _bail remaining_by_rep_d $rbrD
        } else {
            if {[dict size $rbrD] != 2} {
                _bail rbrD_size "exp=2 got=$rbrD"
            }
            if {[catch {dict get $rbrD VDW} gotD] || $gotD != 2} {
                _bail rbrD_vdw "exp=2 got=$gotD"
            }
            if {[catch {dict get $rbrD Cartoon} gotD2] || $gotD2 != $nR} {
                _bail rbrD_cartoon "exp=$nR got=$gotD2"
            }
        }

        # ---- D4: ONE fallback find through the PUBLIC surface: drive to
        #         playing (the state gate -- 17.2-10's drive), then
        #         on_pick residue-1's C (CA+1 -- N/CA/C/O/CB order; the C
        #         is NOT registered, the resid-block fallback resolves the
        #         registered CA). ----
        if {[catch {::biochemeleon::game::set_callbacks \
                {lappend ::LOG_LOG} {incr ::REM_TICKS} {lappend ::WINS}} cbd]} {
            _bail set_callbacks_d $cbd
        }
        if {[catch {
            ::biochemeleon::game_logic::round_reset
            ::biochemeleon::game_logic::begin_countdown
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::countdown_tick
            ::biochemeleon::game_logic::begin_play
        } driveD]} {
            _bail drive_playing_d $driveD
        } elseif {[::biochemeleon::game_logic::state] ne "playing"} {
            _bail playing_state_d "got=[::biochemeleon::game_logic::state]"
        } else {
            set ca1 [lindex $casD 0]
            set cidx [expr {$ca1 + 1}]
            if {[catch {::biochemeleon::game::on_pick $cidx} pd]} {
                _bail fb_pick_d $pd
            }
            if {[::biochemeleon::registry::status_of $ca1] ne "found"} {
                _bail fb_status_d "CA $ca1 got=[::biochemeleon::registry::status_of $ca1]"
            }
            if {![catch {atomselect $gm4 "index $ca1"} sd4]} {
                set u2a [lindex [$sd4 get user2] 0]
                if {[catch {expr {double($u2a) > 0}} okD] || !$okD} {
                    _bail fb_user2_ca "exp>0 got=$u2a"
                }
                $sd4 delete
            } else { _bail fb_sel_ca $sd4 }
            if {![catch {atomselect $gm4 "index $cidx"} sd5]} {
                set u2c [lindex [$sd5 get user2] 0]
                if {![_feq $u2c 0.0]} {
                    _bail fb_user2_c "exp=0 (CA-only design) got=$u2c"
                }
                $sd5 delete
            } else { _bail fb_sel_c $sd5 }
            set remD [::biochemeleon::registry::count_remaining]
            set expRem [expr {2 + $nR - 1}]
            if {$remD != $expRem} {
                _bail fb_remaining_d "exp=$expRem got=$remD"
            }
            if {$nR == 2} {
                # ---- The plan's exact pins at full generation. ----
                if {$remD != 3} { _bail fb_remaining_d2 "exp=3 got=$remD" }
                if {[catch {::biochemeleon::registry::remaining_by_rep} rbrD2]} {
                    _bail fb_rbr_d $rbrD2
                } else {
                    foreach {rep expn} [list VDW 2 Cartoon 1] {
                        if {[catch {dict get $rbrD2 $rep} gotD3] || $gotD3 != $expn} {
                            _bail fb_rbr_$rep "exp=$expn got=$gotD3"
                        }
                    }
                }
                if {[lindex $::LOG_LOG end] ne "Found one! 3 remaining"} {
                    _bail fb_line_d "got=[lindex $::LOG_LOG end]"
                }
            } else {
                # Under-generated draw: the found CA was Cartoon's only
                # record -> Cartoon drops from remaining_by_rep (no
                # zero-fill), VDW keeps 2.
                if {[catch {::biochemeleon::registry::remaining_by_rep} rbrD3]} {
                    _bail fb_rbr_d $rbrD3
                } else {
                    if {![catch {dict get $rbrD3 Cartoon} gD4]} {
                        _bail fb_rbr_cartoon_absent "got=$gD4 (exp absent -- no zero-fill)"
                    }
                    if {[catch {dict get $rbrD3 VDW} gD5] || $gD5 != 2} {
                        _bail fb_rbr_vdw_undergen "exp=2 got=$gD5"
                    }
                }
            }
        }

        # ---- D5: CLEANUP: registry 0 AND the resid block cleared; game
        #         molid DEAD; restored original 424 atoms at pre4 numreps. ----
        if {[catch {::biochemeleon::game::cleanup $gs4} restored4]} {
            _bail cleanup_d $restored4
        } else {
            set chD2 [::biochemeleon::registry::count_hiders]
            if {$chD2 != 0} { _bail reg_after_cleanup_d "exp=0 got=$chD2" }
            set rbD [::biochemeleon::registry::hider_for_resid 9001]
            if {$rbD ne ""} { _bail resid_block_after_cleanup_d "exp='' got=$rbD" }
            if {![catch {molinfo $gm4 get numatoms} aliveD]} {
                _bail game_molid_alive_d "molinfo on the deleted game molid succeeded (numatoms=$aliveD)"
            }
            if {[catch {molinfo $restored4 get numatoms} rnatD]} {
                _bail restored_atoms_d $rnatD
            } elseif {$rnatD != 424} {
                _bail restored_atoms_d "exp=424 got=$rnatD"
            }
            if {[catch {molinfo $restored4 get numreps} rrD]} {
                _bail restored_numreps_d $rrD
            } elseif {$rrD != $pre4} {
                _bail restored_numreps_d "exp=$pre4 got=$rrD"
            }
        }
    }
}

# =====================================================================
# ROUND E: LOCK-SCENE CARTOON round -- the scene is pre-styled Cartoon
# (a RESIDUE tier) + lock_scene 1: the lock-scene derivation must land
# ALL hiders on the detected residue tier (round B's derivation proof,
# now on the residue machinery). Draw-adaptive invariants per this
# file's own PLAN-DETAIL precedent (round B): with the single allowed
# tier {Cartoon}, randomize_per_rep's quick-008 subset contract makes
# the drawn count n 1..3 (draw-dependent -- NOT pinned); the INVARIANT
# chain pins the derivation, the observed generation pins the layout.
# =====================================================================
if {[catch {_load_demo_1f 1znf} m5]} {
    _bail load_demo_e $m5
} else {
    set pre5 [molinfo $m5 get numreps]
    if {$pre5 != 1} {
        _bail pre5_reps "exp=1 got=$pre5 (the scene must have exactly its default rep)"
    }
    # Pre-style rep 0 with the tier's canonical style + P-1 read-back
    # BEFORE start_game (the 17.1-10 pre-styled-scene pattern -- a bad
    # style only console-ERRORs and no-ops, so read-back is the gate).
    if {[catch {mol modstyle 0 $m5 Cartoon} me5]} {
        _bail pre_modstyle_e $me5
    } else {
        set st5 ""
        if {[catch {foreach {st5} [molinfo $m5 get "{rep 0}"] { break }} rb5]} {
            _bail pre_style_readback_e $rb5
        } elseif {$st5 ne "Cartoon"} {
            _bail pre_style_e "exp=Cartoon got=$st5"
        }
        if {[catch {::biochemeleon::game::start_game $m5 3 {} 1} gs5]} {
            _bail start_game_lock_cartoon $gs5
        } elseif {[catch {dict get $gs5 game_molid} gm5]} {
            _bail gs5_game_molid "missing (gs5=$gs5)"
        } else {
            # ---- E1: the derivation proof: per_rep keys == {Cartoon}
            #         EXACTLY (detection + restriction to the detected
            #         residue tier); drawn count n in [1, 3]. ----
            set pr5 [list]
            if {[dict exists $gs5 per_rep]} {
                set pr5 [dict get $gs5 per_rep]
            } else {
                _bail gs5_per_rep "missing"
            }
            if {![catch {dict size $pr5} psz5]} {
                if {$psz5 != 1} {
                    _bail lock_per_rep_size_e "exp=1 got=$psz5 (per_rep=$pr5)"
                }
            } else { _bail lock_per_rep_size_e $psz5 }
            if {![catch {dict keys $pr5} prk5]} {
                if {$prk5 ne {Cartoon}} {
                    _bail lock_per_rep_keys_e "got=$prk5 (the lock-scene derivation must yield ONLY the detected residue tier)"
                }
            } else { _bail lock_per_rep_keys_e $prk5 }
            set n5 0
            if {[catch {dict get $pr5 Cartoon} n5]} {
                _bail lock_count_e $n5
                set n5 0
            } elseif {$n5 < 1 || $n5 > 3} {
                _bail lock_count_range_e "got=$n5 (quick-008: 1 <= sum <= 3)"
            }
            # ---- E2: the P9 chain (request-side, unconditional):
            #         hider_count == effective_total(per_rep) == n. ----
            if {[catch {dict get $gs5 hider_count} eff5]} {
                _bail gs5_hider_count "missing"
            } else {
                set eff5c [::biochemeleon::rep_tiers::effective_total $pr5]
                if {$eff5 != $n5 || $eff5 != $eff5c} {
                    _bail lock_p9_e "hider_count=$eff5 per_rep(Cartoon)=$n5 effective_total=$eff5c"
                }
            }
            # ---- E3: the observed RESIDUE round: ALL sentinels are
            #         residue CAs (chain != G -- no simple tier in the
            #         draw), n' in [1, n]; registry == n'; atoms == 424 +
            #         4*n' + cb, cb in [0, n']; beta<0 names ALL CA
            #         (CA-only sentinels). ----
            set casE [list]
            set badE 0
            if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm5} idxsE]} {
                _bail fetch_idx_e $idxsE
            }
            foreach xi $idxsE {
                if {![catch {atomselect $gm5 "index $xi"} se]} {
                    set chn [lindex [$se get chain] 0]
                    set nmm [lindex [$se get name] 0]
                    if {$chn eq "G"} { incr badE }
                    if {$nmm ne "CA"} {
                        _bail beta_name_e "got=$nmm (exp CA-only sentinels)"
                    }
                    lappend casE $xi
                    $se delete
                } else { _bail layout_sel_e_$xi $se }
            }
            set nE [llength $casE]
            if {$badE != 0} {
                _bail chain_classifier_e "got=$badE G-chain sentinels (exp 0 -- residue-only draw)"
            }
            set chE [::biochemeleon::registry::count_hiders]
            if {$chE != $nE} { _bail reg_count_e "exp=$nE got=$chE" }
            if {$nE < 1 || $nE > $n5} {
                _bail residue_count_e "got=$nE (exp 1..$n5 -- at least one record, at most the drawn count)"
            }
            set natE [molinfo $gm5 get numatoms]
            set cbE [expr {$natE - 424 - 4 * $nE}]
            if {$cbE < 0 || $cbE > $nE} {
                _bail atoms_e "got=$natE (exp 424+4x$nE+cb, cb in \[0,$nE\])"
            }
            puts "CAPSTONE_E_INFO layout atoms=$natE drawn=$n5 res=$nE cb=$cbE cas=$casE"
            # user3 == 1.0 on ALL CAs (single tier -> code 1); real atoms 0.
            foreach xi $casE {
                _check_user3 $gm5 $xi 1.0 user3_e_$xi
            }
            _check_user3 $gm5 100 0.0 user3_e_real
            # CA structures: load-time STRIDE coil/turn family {T C}
            # (recorded, never pinned -- tube/trace + 17.2-09 precedent).
            if {![catch {atomselect $gm5 "resname GAM and beta < 0"} sbE]} {
                foreach st5b [$sbE get structure] {
                    if {[lsearch -exact {T C} $st5b] < 0} {
                        _bail ca_structure_e "exp T or C (load-time STRIDE) got=$st5b"
                    }
                }
                $sbE delete
            } else { _bail beta_sel_e $sbE }
            # ---- E4: resid block zip (file order): 9001+i -> the i-th
            #         CA. At the full 3-draw: resids {9001 9002 9003}. ----
            set ze 0
            foreach xi $casE {
                set ridE [expr {9001 + $ze}]
                set rze [::biochemeleon::registry::hider_for_resid $ridE]
                if {$rze ne $xi} {
                    _bail resid_zip_e "$ridE exp=$xi got=$rze"
                }
                incr ze
            }
            # ---- E5: numreps == pre5 + 2 (one tier -> one pair). ----
            set nrE [molinfo $gm5 get numreps]
            if {$nrE != $pre5 + 2} {
                _bail rep_count_e "exp=[expr {$pre5 + 2}] got=$nrE"
            }
            # ---- E6: the Cartoon pair's read-back (COMBINED-BRACES
            #         molinfo form ONLY) + remaining_by_rep == {Cartoon
            #         n'}. ----
            if {![dict exists $::biochemeleon::hiders::tier_reps 1]} {
                _bail tier_reps_e_missing 1
            } else {
                lassign [dict get $::biochemeleon::hiders::tier_reps 1] hnE fnE hsE fsE
                foreach {rname rrep rexp_sel} [list \
                        hidden $hnE {resname GAM and beta < 0 and user2 < 1 and user3} \
                        found  $fnE {resname GAM and beta < 0 and user2 > 0 and user3}] {
                    if {[catch {mol repindex $gm5 $rrep} ridxE] || $ridxE < 0} {
                        _bail e_${rname}_repindex "name=$rrep repindex=$ridxE"
                        continue
                    }
                    set stE ""; set slE ""; set clE ""; set mtE ""
                    if {[catch {foreach {stE slE clE mtE} [molinfo $gm5 get "{rep $ridxE} {selection $ridxE} {color $ridxE} {material $ridxE}"] { break }} rbE2]} {
                        _bail e_${rname}_readback $rbE2
                        continue
                    }
                    if {$stE ne "Cartoon"} {
                        _bail e_${rname}_style "exp=Cartoon got=$stE"
                    }
                    set exp_colE "Element"
                    if {$rname eq "found"} { set exp_colE {ColorID 7} }
                    if {$clE ne $exp_colE} {
                        _bail e_${rname}_color "exp=$exp_colE got=$clE"
                    }
                    set exp_selE "$rexp_sel 1"
                    if {$slE ne $exp_selE} {
                        _bail e_${rname}_sel "exp=$exp_selE got=$slE"
                    }
                }
            }
            if {[catch {::biochemeleon::registry::remaining_by_rep} rbrE]} {
                _bail remaining_by_rep_e $rbrE
            } else {
                if {[dict size $rbrE] != 1} {
                    _bail rbrE_size "exp=1 got=$rbrE"
                }
                if {[catch {dict get $rbrE Cartoon} gotE] || $gotE != $nE} {
                    _bail rbrE_cartoon "exp=$nE got=$gotE"
                }
            }
            # ---- E7: CLEANUP + SNAPSHOT FIDELITY: registry 0, block
            #         cleared, game molid dead, restored original's rep-0
            #         style STILL reads Cartoon, restored 424 atoms. ----
            if {[catch {::biochemeleon::game::cleanup $gs5} restored5]} {
                _bail cleanup_e $restored5
            } else {
                set chE2 [::biochemeleon::registry::count_hiders]
                if {$chE2 != 0} { _bail reg_after_cleanup_e "exp=0 got=$chE2" }
                set rbE3 [::biochemeleon::registry::hider_for_resid 9001]
                if {$rbE3 ne ""} { _bail resid_block_after_cleanup_e "exp='' got=$rbE3" }
                if {![catch {molinfo $gm5 get numatoms} aliveE]} {
                    _bail game_molid_alive_e "molinfo on the deleted game molid succeeded (numatoms=$aliveE)"
                }
                set rstE ""
                if {[catch {foreach {rstE} [molinfo $restored5 get "{rep 0}"] { break }} rbE4]} {
                    _bail restore_style_readback_e $rbE4
                } elseif {$rstE ne "Cartoon"} {
                    _bail restore_style_e "exp=Cartoon got=$rstE (snapshot fidelity)"
                }
                if {[catch {molinfo $restored5 get numatoms} rnatE]} {
                    _bail restored_atoms_e $rnatE
                } elseif {$rnatE != 424} {
                    _bail restored_atoms_e "exp=424 got=$rnatE"
                }
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
