# vmd/smoke/phase17_tiers_smoke.tcl
# Phase-17.1 (17.1-04) headless smoke: the N-tier hider rep management on a
# REAL demo through the REAL Phase-15 pipeline. Driven through
# game::start_game (composition root -- the mutated 560-atom molecule) but
# with hiders.tcl driven DIRECTLY (2 explicit tiers), NOT via start_game's
# own rep wiring (the current Phase-16 game.tcl adds its default single VDW
# pair internally; this smoke deliberately layers its own 2-tier pairs on
# top and asserts only its OWN 4 reps). Proves (probe3's flow, bug-fixed):
#   1. stamp_tier_codes writes NUMERIC user3 tier codes (read-back is FLOAT:
#      numeric compare only, P10); untouched real atoms stay 0.
#   2. add_hider_reps {{1 VDW} {2 Lines}} adds EXACTLY 4 reps (2 pairs) and
#      returns the tier_reps dict with codes 1 and 2, 4-element values
#      {hidden_name found_name hidden_sel found_sel}, non-empty names that
#      resolve via mol repindex in range.
#   3. COMBINED-BRACES read-back per rep (single-field molinfo get FAILS --
#      Pitfall 2):
#        pair-1 hidden = VDW / Element / {resname GAM and beta < 0 and
#                                        user2 < 1 and user3 1}
#        pair-1 found  = VDW / ColorID 7 / {... user2 > 0 and user3 1}
#        pair-2 hidden/found = Lines with the user3 2 selections.
#   4. Per-tier partition BEFORE any find: tier-1 hidden == 3, tier-2
#      hidden == 2 (of the 5 hiders on 1k8p+5).
#   5. mark_found_visual on a TIER-2 hider: its user2 > 0, tier-1 hiders
#      stay <= 0, and the partition re-splits per tier: tier-1 hidden still
#      3; tier-2 found == 1, tier-2 hidden == 1.
#   6. Name resolution + delrep guard: deleting one tracked game rep makes
#      mark_found_visual error with the "gone (repindex" message (the -1
#      guard proof -- names resolve at USE time, never cached indices).
#   7. tier_styles: code 1 -> VDW, code 2 -> Lines.
#
# Sources the lib files in dependency order (mirrors the entry, NOT the
# entry itself): setup_state, registry, rep_tiers, generators, game_logic,
# demos, backup, mutation, hiders, game. registry is sourced EXACTLY ONCE
# (re-sourcing would WIPE _records). rep_tiers IS sourced as of 17.1-06:
# game.tcl's start_game now calls rep_tiers::* internally, so the namespace
# must exist before that call (this header previously deferred the source
# line to "later smokes (17.1-06+)" -- this is that update). This smoke
# still passes tier_specs literally and calls zero rep_tiers:: procs.
#
# 17.1-06 SETUP NOTE: the 2-arg start_game call now RANDOMIZES across
# IMPLEMENTED_TIERS, so the setup round passes an EXPLICIT per_rep
# {VDW 5} to keep the molecule deterministic -- 5 VDW hiders, 560 atoms,
# sentinels 555-559, exactly the pre-17.1-06 shape the assertions below
# assume.
#
# NO game::cleanup: step 6 intentionally delreps a tracked game rep (the
# round is broken by design); the smoke ends there.
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
set tr [list]

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's source order minus
#      the GUI files; game.tcl added (step 1 calls game::start_game). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    rep_tiers    [file join [pwd] vmd lib rep_tiers.tcl] \
    generators   [file join [pwd] vmd lib generators.tcl] \
    game_logic   [file join [pwd] vmd lib game_logic.tcl] \
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

# ---- 1. SETUP: load 1k8p (555 atoms) and start a round through the real
#         composition root (2-arg call -- backward compatible; produces the
#         mutated molecule this smoke needs). ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }

    # 17.1-06: the EXPLICIT per_rep keeps the setup round deterministic
    # (the 2-arg form now randomizes across IMPLEMENTED_TIERS): 5 VDW
    # hiders -> 560 atoms, sentinels 555-559, the pre-17.1-06 shape.
    if {![catch {::biochemeleon::game::start_game $orig_molid 5 [dict create VDW 5] 0} gs]} {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            # 1a: 555 + 5 = 560 atoms on the combined molecule.
            set n1 [molinfo $gm get numatoms]
            if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
            # 1b: exactly 5 hiders via the canonical sentinel selector,
            #     indices 555-559.
            if {![catch {atomselect $gm "resname GAM and beta < 0"} sel]} {
                if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
                if {[$sel get index] ne {555 556 557 558 559}} {
                    _bail sentinel_idx "got=[$sel get index]"
                }
                $sel delete
            } else { _bail sentinel_sel $sel }

            # ---- 2. STAMP tier codes (user3): tier 1 = {555 556 557},
            #         tier 2 = {558 559}. Read-back is FLOAT -> numeric
            #         compare (P10). ----
            if {[catch {::biochemeleon::hiders::stamp_tier_codes $gm [dict create 1 {555 556 557} 2 {558 559}]} serr]} {
                _bail stamp_tier_codes $serr
            } else {
                foreach {idx expcode} [list 555 1.0 556 1.0 557 1.0 558 2.0 559 2.0] {
                    if {![catch {atomselect $gm "index $idx"} s]} {
                        set u3 [lindex [$s get user3] 0]
                        if {![_feq $u3 $expcode]} {
                            _bail stamp_user3_$idx "exp=$expcode got=$u3"
                        }
                        $s delete
                    } else { _bail stamp_sel_$idx $s }
                }
                # Real atoms keep user3 = 0 (P6 -- the sentinel conjunct
                # must keep excluding them).
                if {![catch {atomselect $gm "index 100"} s100]} {
                    set u3r [lindex [$s100 get user3] 0]
                    if {![_feq $u3r 0.0]} { _bail stamp_real_atom "exp=0.0 got=$u3r" }
                    $s100 delete
                } else { _bail stamp_sel_real $s100 }

                # ---- 3. ADD the 2-tier pairs: EXACTLY 4 more reps, with
                #         name-keyed tracking returned. ----
                set pre_reps [molinfo $gm get numreps]
                if {[catch {::biochemeleon::hiders::add_hider_reps $gm {{1 VDW} {2 Lines}}} tr]} {
                    _bail add_hider_reps $tr
                } else {
                    set post_reps [molinfo $gm get numreps]
                    if {$post_reps != $pre_reps + 4} {
                        _bail rep_count "exp=[expr {$pre_reps + 4}] got=$post_reps"
                    }
                    # tr has codes 1 and 2, each a 4-element value.
                    foreach c [list 1 2] {
                        if {![dict exists $tr $c]} {
                            _bail tr_code_missing "code $c not in tr"
                        } elseif {[llength [dict get $tr $c]] != 4} {
                            _bail tr_shape "code $c value not 4 elements: [dict get $tr $c]"
                        }
                    }
                    # Every name non-empty; repindex resolves in range.
                    set nreps_now [molinfo $gm get numreps]
                    foreach c [list 1 2] {
                        if {[dict exists $tr $c]} {
                            lassign [dict get $tr $c] hn fn hs fs
                            foreach nm [list $hn $fn] {
                                if {$nm eq ""} { _bail tr_empty_name "code $c" }
                                if {[catch {mol repindex $gm $nm} ridx]} {
                                    _bail tr_repindex_err "code $c name $nm: $ridx"
                                } elseif {$ridx < 0 || $ridx >= $nreps_now} {
                                    _bail tr_repindex_range "code $c name $nm repindex=$ridx numreps=$nreps_now"
                                }
                            }
                        }
                    }

                    # ---- 4. READ-BACK per rep (COMBINED-BRACES molinfo
                    #         form ONLY -- the single-field form FAILS). ----
                    # 4a: pair-1 hidden (style VDW / color Element / sel
                    #     with the user3 1 conjunct).
                    lassign [dict get $tr 1] h1n f1n h1s f1s
                    set st ""; set sl ""; set cl ""; set mt ""
                    if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep [mol repindex $gm $h1n]} {selection [mol repindex $gm $h1n]} {color [mol repindex $gm $h1n]} {material [mol repindex $gm $h1n]}"] { break }} rb1]} {
                        _bail p1_hidden_readback $rb1
                    } else {
                        if {$st ne "VDW"} { _bail p1_hidden_style "exp=VDW got=$st" }
                        if {$cl ne "Element"} { _bail p1_hidden_color "exp=Element got=$cl" }
                        if {$sl ne {resname GAM and beta < 0 and user2 < 1 and user3 1}} {
                            _bail p1_hidden_sel "got=$sl"
                        }
                    }
                    # 4b: pair-1 found (VDW / ColorID 7 / user2 > 0 + user3 1).
                    set st ""; set sl ""; set cl ""; set mt ""
                    if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep [mol repindex $gm $f1n]} {selection [mol repindex $gm $f1n]} {color [mol repindex $gm $f1n]} {material [mol repindex $gm $f1n]}"] { break }} rb2]} {
                        _bail p1_found_readback $rb2
                    } else {
                        if {$st ne "VDW"} { _bail p1_found_style "exp=VDW got=$st" }
                        if {$cl ne {ColorID 7}} { _bail p1_found_color "exp=ColorID 7 got=$cl" }
                        if {$sl ne {resname GAM and beta < 0 and user2 > 0 and user3 1}} {
                            _bail p1_found_sel "got=$sl"
                        }
                    }
                    # 4c: pair-2 hidden/found (Lines / user3 2 selections).
                    lassign [dict get $tr 2] h2n f2n h2s f2s
                    set st ""; set sl ""; set cl ""; set mt ""
                    if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep [mol repindex $gm $h2n]} {selection [mol repindex $gm $h2n]} {color [mol repindex $gm $h2n]} {material [mol repindex $gm $h2n]}"] { break }} rb3]} {
                        _bail p2_hidden_readback $rb3
                    } else {
                        if {$st ne "Lines"} { _bail p2_hidden_style "exp=Lines got=$st" }
                        if {$cl ne "Element"} { _bail p2_hidden_color "exp=Element got=$cl" }
                        if {$sl ne {resname GAM and beta < 0 and user2 < 1 and user3 2}} {
                            _bail p2_hidden_sel "got=$sl"
                        }
                    }
                    set st ""; set sl ""; set cl ""; set mt ""
                    if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep [mol repindex $gm $f2n]} {selection [mol repindex $gm $f2n]} {color [mol repindex $gm $f2n]} {material [mol repindex $gm $f2n]}"] { break }} rb4]} {
                        _bail p2_found_readback $rb4
                    } else {
                        if {$st ne "Lines"} { _bail p2_found_style "exp=Lines got=$st" }
                        if {$cl ne {ColorID 7}} { _bail p2_found_color "exp=ColorID 7 got=$cl" }
                        if {$sl ne {resname GAM and beta < 0 and user2 > 0 and user3 2}} {
                            _bail p2_found_sel "got=$sl"
                        }
                    }

                    # ---- 5. Per-tier partition BEFORE any find (fresh
                    #         atomselects evaluate the current fields). ----
                    if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 1}} s1]} {
                        if {[$s1 num] != 3} { _bail pre_part_t1_hidden "exp=3 got=[$s1 num]" }
                        $s1 delete
                    } else { _bail pre_part_t1_sel $s1 }
                    if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 2}} s2]} {
                        if {[$s2 num] != 2} { _bail pre_part_t2_hidden "exp=2 got=[$s2 num]" }
                        $s2 delete
                    } else { _bail pre_part_t2_sel $s2 }

                    # ---- 6. FOUND-MARK a TIER-2 hider (558) -- the re-
                    #         assert re-splits ONLY tier 2. ----
                    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 558} merr]} {
                        _bail mark_found_visual $merr
                    } else {
                        # Marked atom reads 1.0 (float) -> numeric > 0.
                        if {![catch {atomselect $gm "index 558"} s558]} {
                            set u2 [lindex [$s558 get user2] 0]
                            if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                                _bail found_user2 "exp>0 got=$u2"
                            }
                            $s558 delete
                        } else { _bail sel_558 $s558 }
                        # Tier-1 hider 555 untouched -> user2 <= 0.
                        if {![catch {atomselect $gm "index 555"} s555]} {
                            set u2b [lindex [$s555 get user2] 0]
                            if {[catch {expr {double($u2b) <= 0}} ok2] || !$ok2} {
                                _bail t1_untouched_user2 "exp<=0 got=$u2b"
                            }
                            $s555 delete
                        } else { _bail sel_555 $s555 }
                        # Partition after the find: tier-1 hidden still 3;
                        # tier-2 found == 1, tier-2 hidden == 1.
                        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 1}} p1]} {
                            if {[$p1 num] != 3} { _bail post_part_t1_hidden "exp=3 got=[$p1 num]" }
                            $p1 delete
                        } else { _bail post_part_t1_sel $p1 }
                        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 > 0 and user3 2}} p2]} {
                            if {[$p2 num] != 1} { _bail post_part_t2_found "exp=1 got=[$p2 num]" }
                            $p2 delete
                        } else { _bail post_part_t2_found_sel $p2 }
                        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 2}} p3]} {
                            if {[$p3 num] != 1} { _bail post_part_t2_hidden "exp=1 got=[$p3 num]" }
                            $p3 delete
                        } else { _bail post_part_t2_hidden_sel $p3 }
                    }

                    # ---- 7. NAME RESOLUTION + delrep guard: delete one
                    #         tracked game rep (tier-2 hidden) by NAME ->
                    #         mark_found_visual must error with the "gone
                    #         (repindex" message (-1 guard proof). ----
                    set h2idx_now [mol repindex $gm $h2n]
                    if {$h2idx_now < 0} {
                        _bail delrep_prereq "tier-2 hidden rep already gone"
                    } else {
                        mol delrep $h2idx_now $gm
                        set gone_err ""
                        if {![catch {::biochemeleon::hiders::mark_found_visual $gm 555} gone_err]} {
                            _bail delrep_guard "mark_found_visual did NOT error after delrep of a tracked rep"
                        } elseif {[string first {gone (repindex} $gone_err] < 0} {
                            _bail delrep_guard_msg "unexpected error: $gone_err"
                        }
                    }

                    # ---- 8. tier_styles: code 1 -> VDW, code 2 -> Lines. ----
                    if {![dict exists $::biochemeleon::hiders::tier_styles 1]
                            || [dict get $::biochemeleon::hiders::tier_styles 1] ne "VDW"} {
                        _bail tier_styles_1 "exp=VDW got=[dict get $::biochemeleon::hiders::tier_styles 1]"
                    }
                    if {![dict exists $::biochemeleon::hiders::tier_styles 2]
                            || [dict get $::biochemeleon::hiders::tier_styles 2] ne "Lines"} {
                        _bail tier_styles_2 "exp=Lines got=[dict get $::biochemeleon::hiders::tier_styles 2]"
                    }
                }
            }
        }
    } else {
        _bail start_game $gs
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
