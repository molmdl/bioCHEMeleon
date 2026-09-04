# vmd/smoke/phase16_restart_smoke.tcl
# GAP-CLOSURE regression gate for the 16-13 active-game guard (VERIFICATION
# gap 1, headless half): repeated DIRECT start_game invocation through the
# PUBLIC composition surface (never on_pick, never pick_bridge). Makes the
# observed stacking defect a TESTED-IMPOSSIBLE state: pre-guard, a second
# Start on the still-loaded game molecule stacked hider generations (observed
# in the 16-12 GUI session: 561-atom combined PDB from a 558-atom game
# molecule, "Segments: 3", sentinel generations 555-559 + freshly appended).
#
# IMPORTANT SIMULATION NOTE: the game.tcl layer CANNOT distinguish a won
# round from a mid-round one -- both keep the current_state stash (the state
# machine is GUI-side game_logic, which this smoke deliberately does NOT
# source). The faithful after-win simulation is therefore registry-side ONLY:
# every record marked found so registry::count_remaining == 0 -- exactly the
# controller's won-state precondition. mark_found is the same call on_pick
# makes.
#
# 17.1-07 NOTE: every start_game call below passes an EXPLICIT VDW-only
# per_rep ([dict create VDW <n>] 0) -- the 2-arg form now randomizes across
# implemented tiers (17.1-06), and the per-round numreps == base + 2
# invariant asserted by _assert_round holds only for single-tier rounds.
#
# Stages (every round asserted with the SAME single-generation invariants:
# atom count = original + N, EXACTLY N sentinels at the top indices via the
# canonical selector, registry::count_hiders == N (rebuilt per round, never
# accumulated across generations), numreps == saved_numreps + 2, viewpoint
# maxdiff < 1e-4):
#   STAGE 0  setup: 1k8p (555 atoms) + one VDW rep + mutated viewpoint ->
#            saved_numreps + vp_orig recorded with backup::snapshot's EXACT
#            positional combined-braces get form (non-vacuous SC4 asserts).
#   STAGE A1 fresh-session start: gs1 = start_game(orig1 3) -- the guard must
#            NOT fire (stash empty); game_state shape frozen {game_molid
#            hider_count snapshot}; 555+3=558 atoms; sentinels {555 556 557}.
#   STAGE A2 double-start MID-ROUND, NEW-count semantics: gs2 = start_game on
#            gs1's GAME MOLECULE with count 2 -- the exact observed defect
#            path (Start while the game molecule is still loaded). The guard
#            cleans the old round, restores the 555-atom original, remaps the
#            now-dead target by LIVENESS, and starts fresh with THIS call's
#            settings: 555+2=557 atoms, sentinels {555 556}, registry 2 (NEVER
#            5 stacked); gs1's game molid DELETED (leak guard).
#   STAGE B  double-start AFTER WIN (the exact GUI defect): gs2's hiders all
#            marked found -> count_remaining == 0 (see the simulation note).
#            gs3 = start_game on gs2's game molecule, count 3: 555+3=558
#            atoms, sentinels {555 556 557}, registry 3; gs2's game molid
#            DELETED.
#   STAGE C  different-target restart (the guard's live-target pass-through):
#            load 1znf (424 atoms, LIVE) with gs3 still active, then
#            gs4 = start_game(1znf 2): the guard cleaned round 3 (gs3's game
#            molid DELETED; the round-3 restored 1k8p original SURVIVES
#            loaded -- scanned as a 555-atom 0-sentinel molecule in
#            [molinfo list]) and mutate consumed only 1znf (gs4: 424+2=426
#            atoms, sentinels {424 425}, registry 2; the 1znf original itself
#            is consumed by the mutate).
#
# VIEWPOINT MODEL NOTE (probe-verified in this plan's Task 2, probe_vp.tcl /
# probe_vp2.tcl / probe_vp3.tcl, all gitignored throwaways): VMD 1.9.3's
# molinfo 4-matrix get reads the CURRENT SCENE VIEW for any molid (a second
# mol new makes even the FIRST molecule's own get return the fresh default),
# and the scene view RESETS on every `mol new`. Consequence for stage C: the
# guard's cleanup restores the old round's original via `mol new` (view ->
# that molecule's fresh-load default) and re-applies the old round's view
# (backup::apply) BEFORE the new round's snapshot captures the view -- in the
# different-target corner flow the snapshot therefore carries the restored
# original's fresh-load view, measuring 0.7602817 vs the vp_orig lineage
# (probe3: EXACTLY maxd(1k8p-fresh-default, vp_orig); the inter-molecule
# scale is 35.525988). This is VMD view-reset-on-mol-new semantics
# intersecting the guard's cleanup ordering -- NOT a stacking defect and NOT
# a guard defect (every atom/sentinel/registry/leak/survivor invariant is
# view-independent and passes). Stage C therefore asserts the
# model-independent SC4-forward fidelity: gs4's applied view == gs4's OWN
# snapshot viewpoint (< 1e-4) -- the round applied exactly the viewpoint its
# snapshot captured. Stages A/B keep the stronger vp_orig-lineage assert
# (0.0 there: each cleanup's mol new runs on an otherwise-empty molecule set
# and its apply re-sets the view before the next snapshot reads it).
# numreps is per-molecule (unambiguous): stage C's round is built on 1znf's
# OWN rep state (1 default rep -> 1+2=3 total), NOT the 1k8p setup's saved
# rep count -- the round honors the NEW target's own snapshot.
#
# Expected atom narrative across the run: 555 -> 558 -> 557 -> 558 -> 426 on
# the game molecules (plus the intermediate 555 restores and the 424 1znf
# load); "Segments: 2" on every combined reload in the load log (never 3).
# Segments is a load-log observation EYEBALLED by the runner, NOT parsed as
# an assertion: the in-smoke AUTHORITATIVE stacking proof is atom count +
# exact sentinel index set + registry count (a stacked generation would show
# 2N sentinels / +N atoms).
#
# Harness (the 16-11 / 15-05 capstone pattern): assertions accumulate into
# the failures list; the closing marker prints BCHM_SMOKE_RESULT PASS=1
# FAIL=none ONLY when the list is empty; every stage is catch-wrapped and
# funnels into _bail so a mid-script error cannot silently skip asserts (VMD
# -e catches top-level errors and CONTINUES -- a bare marker is the
# false-PASS anti-pattern). _bail appends to ::failures DIRECTLY (not upvar
# 1): it is also called from inside _assert_round, one frame deeper, where an
# upvar link would silently create a LOCAL list and LOSE the tag.
#
# LIFTED VERBATIM from vmd/smoke/phase15_smoke.tcl: the recursive
# _flat/_vp_maxdiff viewpoint flattener (the viewpoint is NESTED 4x4
# matrices; naive abs() errors; string-eq drifts) and the 4-matrix combined
# capture form {rotate_matrix center_matrix scale_matrix global_matrix}
# (backup::snapshot's EXACT positional order -- apples-to-apples).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself -- avoids GUI/dialog baggage): setup_state -> registry -> generators
# -> rep_tiers (17.1-06 entry order -- game.tcl calls rep_tiers::* at CALL
# time) -> demos -> backup -> mutation -> hiders -> game. registry is sourced
# EXACTLY ONCE (re-sourcing would WIPE _records). generators IS required
# (start_game -> mutation::make_placeholder_hiders -> generators::
# sphere_positions since 16-07; mutation.tcl also sources it itself --
# harmless pure re-init). hiders IS required (start_game ->
# hiders::add_hider_reps since 16-08). pick_bridge + game_logic are NOT
# sourced: the guard path never touches them.
#
# Sentinel selector is ALWAYS "resname GAM and beta < 0" (never an exact
# beta-value selector); every atomselect gets $sel delete.
#
# Run (repo root, against fresh staging):
#   mkdir -p tmp/restart16 && cp -r vmd tmp/restart16/
#   timeout 300 bash -ic 'cd tmp/restart16 && vmd -dispdev text -e
#   vmd/smoke/phase16_restart_smoke.tcl -eofexit < /dev/null' > out 2>&1
# then grep the FULL output for the marker AND for ERROR) / bad switch lines
# (switch-parse errors lack the ERROR) prefix -- false-PASS detection).
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> [pwd] (the
# staging root) locates the lib files. VMD does NOT propagate tcl exit codes
# (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?.
# Tcl 8.5 only (no 8.6 idioms; brace all expr).

set failures [list]

proc _bail {tag msg} {
    # Appends to the GLOBAL failures list (identical to the phase16_smoke
    # upvar form at top level, where this smoke's stages run; robust from
    # inside _assert_round, where upvar 1 would lose the tag -- see header).
    lappend ::failures "$tag:$msg"
}

# ---- Recursive viewpoint flattener + maxdiff (lifted verbatim from
#      phase15_smoke.tcl). molinfo's 4-matrix combined get returns NESTED
#      matrices; naive abs($a-$b) on the unflattened list errors. ----
proc _flat {lst outvar} {
    upvar 1 $outvar out
    foreach x $lst {
        if {[llength $x] > 1} { _flat $x out } else { lappend out $x }
    }
}
proc _vp_maxdiff {a b} {
    set fa [list]; set fb [list]
    _flat $a fa; _flat $b fb
    set maxd 0.0
    foreach x $fa y $fb {
        if {[catch {expr {abs($x - $y)}} d]} continue ;# skip non-numeric (none expected)
        if {$d > $maxd} { set maxd $d }
    }
    return $maxd
}

# ---- Shared single-generation invariant block for a freshly started round
#      (tag-prefixed asserts; returns 1 if all green, 0 otherwise):
#        atoms == n_exp; sentinels via the canonical selector exactly
#        sent_exp (count + sorted index list); registry::count_hiders ==
#        [llength sent_exp] (REBUILT per round, never accumulated);
#        numreps == base_reps + 2 (the round's OWN snapshot target reps,
#        then hiders::add_hider_reps appended hidden+found LAST); viewpoint
#        maxdiff(vp_ref) < 1e-4 (recursive flattener -- see the VIEWPOINT
#        MODEL NOTE in the header for the stage-C reference choice). ----
proc _assert_round {gm n_exp sent_exp vp_ref base_reps tag} {
    set ok 1
    if {[catch {molinfo $gm get numatoms} nn]} {
        _bail "${tag}_atoms" $nn
        return 0
    }
    if {$nn != $n_exp} { _bail "${tag}_atoms" "exp=$n_exp got=$nn"; set ok 0 }
    if {[catch {atomselect $gm "resname GAM and beta < 0"} sel]} {
        _bail "${tag}_sentinel_sel" $sel
        set ok 0
    } else {
        if {[$sel num] != [llength $sent_exp]} {
            _bail "${tag}_sentinel_num" "exp=[llength $sent_exp] got=[$sel num]"
            set ok 0
        }
        set got [lsort -integer [$sel get index]]
        if {$got ne $sent_exp} {
            _bail "${tag}_sentinel_idx" "got=$got exp=$sent_exp"
            set ok 0
        }
        $sel delete
    }
    set ch [::biochemeleon::registry::count_hiders]
    if {$ch != [llength $sent_exp]} {
        _bail "${tag}_registry" "exp=[llength $sent_exp] got=$ch"
        set ok 0
    }
    if {[catch {molinfo $gm get numreps} gn]} {
        _bail "${tag}_numreps" $gn
        set ok 0
    } elseif {$gn != $base_reps + 2} {
        _bail "${tag}_numreps" "exp=[expr {$base_reps + 2}] got=$gn"
        set ok 0
    }
    if {[catch {molinfo $gm get {rotate_matrix center_matrix scale_matrix global_matrix}} vpg]} {
        _bail "${tag}_vp_get" $vpg
        set ok 0
    } else {
        set vd [_vp_maxdiff $vp_ref $vpg]
        if {$vd >= 1e-4} {
            _bail "${tag}_vp" "maxdiff=$vd (exp < 1e-4)"
            set ok 0
        }
    }
    return $ok
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig1 -1
set orig2 -1
set saved_numreps -1
set vp_orig [list]
set gs1 [list]
set gs2 [list]
set gs3 [list]
set gs4 [list]
set gm1 -1
set gm2 -1
set gm3 -1
set gm4 -1
set setup_ok 0
set ok_a1 0
set ok_a2 0
set ok_b 0

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry, NOT the entry itself. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    generators   [file join [pwd] vmd lib generators.tcl] \
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

# ---- STAGE 0. SETUP: load 1k8p (555 atoms) + VDW rep + mutated viewpoint;
#      record saved_numreps + vp_orig (backup::snapshot's EXACT positional
#      combined-braces get form) so the SC4-forward/restore asserts are
#      non-vacuous (15-05 stage pattern). ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig1]} {
    _bail load_demo $orig1
} elseif {[catch {
    set n0 [molinfo $orig1 get numatoms]
    if {$n0 != 555} { _bail orig1_atoms "exp=555 got=$n0" }
    catch {mol representation VDW}
    if {[catch {mol addrep $orig1} adderr]} { _bail addrep $adderr }
    # Mutate the viewpoint (rotate/scale/translate act on the TOP molecule --
    # load_demo just made the original the top molecule).
    rotate x by 30
    rotate y by 45
    scale to 0.8
    translate by 0.5 0.5 0.5
    set saved_numreps [molinfo $orig1 get numreps]
    if {$saved_numreps != 2} { _bail saved_numreps "exp=2 got=$saved_numreps" }
    set vp_orig [molinfo $orig1 get {rotate_matrix center_matrix scale_matrix global_matrix}]
} setuperr]} {
    _bail setup $setuperr
} else {
    set setup_ok 1
    puts "BCHM_SMOKE_INFO stage0 ok (orig1=$orig1 saved_numreps=$saved_numreps)"
}

# ---- STAGE A1. FRESH-SESSION START (guard must NOT fire: stash empty). ----
if {$setup_ok} {
    if {![catch {::biochemeleon::game::start_game $orig1 3 [dict create VDW 3] 0} gs1]} {
        if {[catch {dict get $gs1 game_molid} gm1]} {
            _bail gs1_key "missing (gs=$gs1)"
        } else {
            # Shape frozen per 15-05: exactly these three keys.
            foreach k {game_molid hider_count snapshot} {
                if {[catch {dict exists $gs1 $k} ex] || !$ex} {
                    _bail gs1_shape "key $k missing (gs=$gs1)"
                }
            }
            if {[catch {dict get $gs1 hider_count} hc1] || $hc1 != 3} {
                _bail a1_hider_count "exp=3 got=$hc1"
            }
            set ok_a1 [_assert_round $gm1 558 {555 556 557} $vp_orig $saved_numreps a1]
            puts "BCHM_SMOKE_INFO stageA1 gm1=$gm1 ok=$ok_a1"
        }
    } else {
        _bail start_a1 $gs1
    }
}

# ---- STAGE A2. DOUBLE-START MID-ROUND, NEW-COUNT SEMANTICS: target = the
#      OLD GAME MOLECULE (the exact observed defect path), NEW count 2. The
#      guard must clean round 1, restore the 555-atom original, remap the
#      dead target by LIVENESS, and start fresh with THIS call's count. ----
if {$ok_a1} {
    if {![catch {::biochemeleon::game::start_game $gm1 2 [dict create VDW 2] 0} gs2]} {
        if {[catch {dict get $gs2 game_molid} gm2]} {
            _bail gs2_key "missing (gs=$gs2)"
        } else {
            if {$gm2 == $gm1} {
                _bail a2_molid "gs2.game_molid == gs1.game_molid ($gm2)"
            }
            if {[catch {dict get $gs2 hider_count} hc2] || $hc2 != 2} {
                _bail a2_hider_count "exp=2 (NEW count) got=$hc2"
            }
            set ok_a2 [_assert_round $gm2 557 {555 556} $vp_orig $saved_numreps a2]
            # Leak guard: gs1's game molecule DELETED by the guard's cleanup
            # (15-05 catch-molinfo-nonzero pattern).
            if {![catch {molinfo $gm1 get numatoms} ghost1]} {
                _bail a2_old_leaked "gs1 game_molid $gm1 alive (numatoms=$ghost1)"
            }
            puts "BCHM_SMOKE_INFO stageA2 gm2=$gm2 ok=$ok_a2"
        }
    } else {
        _bail start_a2 $gs2
    }
}

# ---- STAGE B. DOUBLE-START AFTER WIN (the exact GUI defect): mark gs2's
#      hiders found -> count_remaining == 0 (the controller's won-state
#      precondition). game_logic is NOT sourced -- the game.tcl layer cannot
#      distinguish won vs mid-round (both keep current_state; the state
#      machine is GUI-side), so registry-side remaining==0 with every record
#      found IS the won state as far as the guard can see; mark_found is the
#      same call on_pick makes. ----
if {$ok_a2} {
    set b_pre 1
    foreach idx {555 556} {
        if {[catch {::biochemeleon::registry::mark_found $idx} merr]} {
            _bail b_mark "$idx: $merr"
            set b_pre 0
        } elseif {[::biochemeleon::registry::status_of $idx] ne "found"} {
            _bail b_status "idx $idx got=[::biochemeleon::registry::status_of $idx] exp=found"
            set b_pre 0
        }
    }
    if {$b_pre} {
        set rem0 [::biochemeleon::registry::count_remaining]
        if {$rem0 != 0} { _bail b_remaining_pre "exp=0 got=$rem0"; set b_pre 0 }
    }
    if {$b_pre} {
        if {![catch {::biochemeleon::game::start_game $gm2 3 [dict create VDW 3] 0} gs3]} {
            if {[catch {dict get $gs3 game_molid} gm3]} {
                _bail gs3_key "missing (gs=$gs3)"
            } else {
                if {$gm3 == $gm2} {
                    _bail b_molid "gs3.game_molid == gs2.game_molid ($gm3)"
                }
                if {[catch {dict get $gs3 hider_count} hc3] || $hc3 != 3} {
                    _bail b_hider_count "exp=3 got=$hc3"
                }
                set ok_b [_assert_round $gm3 558 {555 556 557} $vp_orig $saved_numreps b]
                # Leak guard: gs2's game molecule DELETED by the guard.
                if {![catch {molinfo $gm2 get numatoms} ghost2]} {
                    _bail b_old_leaked "gs2 game_molid $gm2 alive (numatoms=$ghost2)"
                }
                puts "BCHM_SMOKE_INFO stageB gm3=$gm3 ok=$ok_b"
            }
        } else {
            _bail start_b $gs3
        }
    }
}

# ---- STAGE C. DIFFERENT-TARGET RESTART (the guard's live-target branch):
#      load 1znf (424 atoms, LIVE) with gs3 still active, then start on it.
#      The guard cleans round 3 (whose cleanup restores the 1k8p original --
#      which must SURVIVE loaded) and starts fresh on 1znf, which the mutate
#      consumes. ----
if {$ok_b} {
    if {[catch {::biochemeleon::demos::load_demo 1znf} orig2]} {
        _bail c_load_demo $orig2
    } else {
        if {[catch {molinfo $orig2 get numatoms} n2c]} {
            _bail c_orig2_dead "1znf not LIVE after load: $n2c"
        } else {
            if {$n2c != 424} { _bail c_orig2_atoms "exp=424 got=$n2c" }
            # 1znf's OWN rep count (1 default rep) -- the round-4 invariant
            # is base_reps + 2 on the NEW target's own snapshot, not the 1k8p
            # setup's saved_numreps.
            set n2reps [molinfo $orig2 get numreps]
            # Round-3's game molecule must be ALIVE here: stage C proves the
            # LIVE-TARGET pass-through branch specifically (an active round
            # superseded by a different-target start).
            if {[catch {molinfo $gm3 get numatoms} n3pre]} {
                _bail c_pre_active "gs3 game_molid $gm3 not alive pre-start: $n3pre"
            } else {
                if {![catch {::biochemeleon::game::start_game $orig2 2 [dict create VDW 2] 0} gs4]} {
                    if {[catch {dict get $gs4 game_molid} gm4]} {
                        _bail gs4_key "missing (gs=$gs4)"
                    } else {
                        if {$gm4 == $gm3} {
                            _bail c_molid "gs4.game_molid == gs3.game_molid ($gm4)"
                        }
                        if {[catch {dict get $gs4 hider_count} hc4] || $hc4 != 2} {
                            _bail c_hider_count "exp=2 got=$hc4"
                        }
                        # vp_ref = gs4's OWN snapshot viewpoint (SC4-forward
                        # fidelity; see the VIEWPOINT MODEL NOTE -- the
                        # guard's cleanup legitimately resets the scene view
                        # via its restore's mol new before this round's
                        # snapshot, so the lineage view is not the right
                        # reference in the different-target flow).
                        set vp_snap4 [dict get $gs4 snapshot viewpoint]
                        if {[_assert_round $gm4 426 {424 425} $vp_snap4 $n2reps c]} {
                            puts "BCHM_SMOKE_INFO stageC gm4=$gm4 ok=1"
                        }
                        # Leak guard: gs3's game molecule DELETED by the guard.
                        if {![catch {molinfo $gm3 get numatoms} ghost3]} {
                            _bail c_old_leaked "gs3 game_molid $gm3 alive (numatoms=$ghost3)"
                        }
                        # The start consumed ONLY 1znf: the mutate deleted the
                        # 1znf original when building gs4's round.
                        if {![catch {molinfo $orig2 get numatoms} ghost4]} {
                            _bail c_target_consumed "orig2 $orig2 alive (numatoms=$ghost4)"
                        }
                        # Survivor guard: the round-3 cleanup RESTORED the 1k8p
                        # original and it SURVIVES loaded -- scan [molinfo list]
                        # for a 555-atom molecule with ZERO sentinels (a clean
                        # original, never a stacked game molecule). At least one
                        # must exist.
                        set survivors 0
                        foreach m [molinfo list] {
                            if {[catch {molinfo $m get numatoms} nm]} { continue }
                            if {$nm != 555} { continue }
                            if {[catch {atomselect $m "resname GAM and beta < 0"} sv]} { continue }
                            if {[$sv num] == 0} { incr survivors }
                            $sv delete
                        }
                        if {$survivors < 1} {
                            _bail c_survivor "no 555-atom 0-sentinel 1k8p original survives loaded"
                        }
                    }
                } else {
                    _bail start_c $gs4
                }
            }
        }
    }
}

# ---- Report. VMD does NOT propagate exit codes -- use a marker line. The
#      marker derives from the REAL failures list (PASS=1 ONLY when empty). ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
