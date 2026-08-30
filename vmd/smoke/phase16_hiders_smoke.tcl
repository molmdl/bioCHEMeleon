# vmd/smoke/phase16_hiders_smoke.tcl
# Phase-16 (16-05) headless smoke: the hiders mol bridge end-to-end through the
# REAL Phase-15 pipeline. Driven through game::start_game (composition root) ->
# hiders::add_hider_reps -> COMBINED-BRACES read-back asserts ->
# hiders::mark_found_visual -> user2 asserts -> game::cleanup. Proves:
#   1. add_hider_reps adds EXACTLY 2 reps to the game molid, at base..base+1
#      (base = numreps AFTER backup::apply -- deterministic per round).
#   2. Rep read-backs via the COMBINED-BRACES molinfo form (single-field
#      molinfo get {rep $i} FAILS -- Pitfall 2):
#        hidden rep = VDW / {resname GAM and beta < 0 and user2 < 1} / Element
#        found rep  = VDW / {resname GAM and beta < 0 and user2 > 0} / ColorID 7
#   3. mark_found_visual sets user2=1 on the picked index (user2 values are
#      FLOATS: compare numerically, NEVER string-eq "1" -- Pitfall 7), leaves
#      untouched hiders at 0.0, and re-issues BOTH modselects (the mandatory
#      re-evaluation re-assert -- Pitfall 3; proven by the found selection
#      actually re-splitting below).
#   4. The user2 flag SPLITS the sentinel population: found sel num 1, hidden
#      sel num 4 (of 5 hiders on 1k8p+5).
#   5. Sentinel integrity: "resname GAM and beta < 0" still matches ALL 5
#      (beta is NEVER written -- found flags live only in user2).
#   6. Idempotency: re-marking the same index is a no-op (no error, found sel
#      still 1) -- matches the caller-side registry-guard contract (Pitfall 5).
#   7. Cleanup parity (15-05): registry reset to 0 hiders; the LIVE game_molid
#      is DELETED (leak guard -- catch {molinfo ...} must FAIL).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself -- avoids GUI/dialog baggage): setup_state, registry, demos, backup,
# mutation, game, hiders. registry is sourced EXACTLY ONCE (re-sourcing would
# WIPE _records); demos + mutation re-source setup_state themselves (harmless
# constant re-init).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT propagate tcl
# exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD
# -e catches top-level errors and CONTINUES (possible false-PASS) -> every
# step is wrapped in catch + _bail, and the runner scans the FULL log for
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
set base_reps -1
set rh -1
set rf -1

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's source order minus the
#      GUI files. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    demos        [file join [pwd] vmd lib demos.tcl] \
    backup       [file join [pwd] vmd lib backup.tcl] \
    mutation     [file join [pwd] vmd lib mutation.tcl] \
    game         [file join [pwd] vmd lib game.tcl] \
    hiders       [file join [pwd] vmd lib hiders.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# ---- 1. SETUP: load 1k8p (555 atoms). ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }

    # ---- 2. START: the real Phase-15 pipeline (composition root only --
    #         backup/mutation/registry are never called directly here). ----
    if {![catch {::biochemeleon::game::start_game $orig_molid 5} gs]} {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            # 2a: 555 + 5 = 560 atoms on the combined molecule.
            set n1 [molinfo $gm get numatoms]
            if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
            # 2b: exactly 5 hiders via the canonical sentinel selector,
            #     indices 555-559.
            if {![catch {atomselect $gm "resname GAM and beta < 0"} sel]} {
                if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
                if {[$sel get index] ne {555 556 557 558 559}} {
                    _bail sentinel_idx "got=[$sel get index]"
                }
                $sel delete
            } else { _bail sentinel_sel $sel }

            # ---- 3. ADD HIDER REPS: exactly 2 more, at base..base+1. ----
            set base_reps [molinfo $gm get numreps]
            if {[catch {::biochemeleon::hiders::add_hider_reps $gm} aerr]} {
                _bail add_hider_reps $aerr
            } else {
                set after_reps [molinfo $gm get numreps]
                if {$after_reps != $base_reps + 2} {
                    _bail rep_count "exp=[expr {$base_reps + 2}] got=$after_reps"
                }
                set rh $base_reps
                set rf [expr {$base_reps + 1}]

                # ---- 4. READ-BACK hidden rep (COMBINED-BRACES molinfo form
                #         ONLY -- the single-field form FAILS, Pitfall 2). ----
                set hstyle ""; set hsel ""; set hcol ""; set hmat ""
                if {[catch {foreach {hstyle hsel hcol hmat} [molinfo $gm get "{rep $rh} {selection $rh} {color $rh} {material $rh}"] { break }} rberr]} {
                    _bail hidden_readback $rberr
                } else {
                    if {$hstyle ne "VDW"} { _bail hidden_style "exp=VDW got=$hstyle" }
                    if {$hsel ne {resname GAM and beta < 0 and user2 < 1}} {
                        _bail hidden_sel "got=$hsel"
                    }
                    if {$hcol ne "Element"} { _bail hidden_color "exp=Element got=$hcol" }
                }
                # ---- 5. READ-BACK found rep. ----
                set fstyle ""; set fsel ""; set fcol ""; set fmat ""
                if {[catch {foreach {fstyle fsel fcol fmat} [molinfo $gm get "{rep $rf} {selection $rf} {color $rf} {material $rf}"] { break }} rberr2]} {
                    _bail found_readback $rberr2
                } else {
                    if {$fstyle ne "VDW"} { _bail found_style "exp=VDW got=$fstyle" }
                    if {$fsel ne {resname GAM and beta < 0 and user2 > 0}} {
                        _bail found_sel "got=$fsel"
                    }
                    if {$fcol ne {ColorID 7}} { _bail found_color "exp=ColorID 7 got=$fcol" }
                }

                # ---- 6. FOUND-MARK index 555 (numeric user2 compare only). ----
                if {[catch {::biochemeleon::hiders::mark_found_visual $gm 555} merr]} {
                    _bail mark_found_visual $merr
                } else {
                    # Marked atom reads 1.0 (float) -> numeric > 0.
                    if {![catch {atomselect $gm "index 555"} s555]} {
                        set u2 [lindex [$s555 get user2] 0]
                        if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                            _bail found_user2 "exp>0 got=$u2"
                        }
                        $s555 delete
                    } else { _bail sel_555 $s555 }
                    # Untouched hider 556 stays at 0.0 (numeric <= 0).
                    if {![catch {atomselect $gm "index 556"} s556]} {
                        set u2b [lindex [$s556 get user2] 0]
                        if {[catch {expr {double($u2b) <= 0}} ok2] || !$ok2} {
                            _bail untouched_user2 "exp<=0 got=$u2b"
                        }
                        $s556 delete
                    } else { _bail sel_556 $s556 }

                    # ---- 7. The flag SPLITS the sentinel population. ----
                    if {![catch {atomselect $gm "resname GAM and beta < 0 and user2 > 0"} sf]} {
                        if {[$sf num] != 1} { _bail found_split "exp=1 got=[$sf num]" }
                        $sf delete
                    } else { _bail found_split_sel $sf }
                    if {![catch {atomselect $gm "resname GAM and beta < 0 and user2 < 1"} sh]} {
                        if {[$sh num] != 4} { _bail hidden_split "exp=4 got=[$sh num]" }
                        $sh delete
                    } else { _bail hidden_split_sel $sh }

                    # ---- 8. Sentinel integrity: beta untouched -> all 5. ----
                    if {![catch {atomselect $gm "resname GAM and beta < 0"} sg]} {
                        if {[$sg num] != 5} { _bail sentinel_integrity "exp=5 got=[$sg num]" }
                        $sg delete
                    } else { _bail sentinel_integrity_sel $sg }

                    # ---- 9. Idempotency: re-mark 555 -- no error, no dup. ----
                    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 555} merr2]} {
                        _bail remark_error $merr2
                    } else {
                        if {![catch {atomselect $gm "index 555"} s555b]} {
                            set u2c [lindex [$s555b get user2] 0]
                            if {[catch {expr {double($u2c) > 0}} ok3] || !$ok3} {
                                _bail remark_user2 "exp>0 got=$u2c"
                            }
                            $s555b delete
                        } else { _bail remark_sel_555 $s555b }
                        if {![catch {atomselect $gm "resname GAM and beta < 0 and user2 > 0"} sf2]} {
                            if {[$sf2 num] != 1} { _bail remark_split "exp=1 got=[$sf2 num]" }
                            $sf2 delete
                        } else { _bail remark_split_sel $sf2 }
                    }
                }
            }

            # ---- 10. CLEANUP: restore original + reset registry (15-05
            #          parity: registry 0 hiders; live game_molid DELETED --
            #          leak guard, catch must FAIL). ----
            if {![catch {::biochemeleon::game::cleanup $gs} restored]} {
                set ch2 [::biochemeleon::registry::count_hiders]
                if {$ch2 != 0} { _bail registry_after_cleanup "exp=0 got=$ch2" }
                if {![catch {molinfo $gm get numatoms} ghost]} {
                    _bail game_molid_leaked "game_molid $gm still alive (numatoms=$ghost)"
                }
            } else {
                _bail cleanup $restored
            }
        }
    } else {
        _bail start_game $gs
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
