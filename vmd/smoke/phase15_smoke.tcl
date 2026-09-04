# vmd/smoke/phase15_smoke.tcl
# Phase-15 CAPSTONE headless smoke: the full backup -> mutate -> reconstruct ->
# cleanup -> restore pipeline, driven EXCLUSIVELY through the game.tcl
# composition-root API (game::start_game / game::cleanup -- backup/mutation/
# registry are NEVER called directly here; their isolated behavior is already
# proven by the Wave-1/2 module smokes). Proves all 4 phase success criteria:
#   SC1: start_game on 1k8p (555 atoms) + 5 hiders -> game_molid has 560 atoms;
#        exactly 5 sentinels via "resname GAM and beta < 0" at indices 555-559
#        with segid GAME; the original atom 0 (N1) is intact.
#   SC2: cleanup -> restored molid has 555 atoms + same numreps + 0 sentinels;
#        the LIVE game_molid is DELETED (catch {molinfo ...} nonzero -- proves
#        backup::restore deleted the passed game_molid, NOT the dead
#        snapshot.molid; guards the Plan-03/04 leak false-pass).
#   SC3: registry::count_hiders == 5 after start (is_hider true for 555-559,
#        false for 0); count_hiders == 0 after cleanup (registry reset).
#   SC4: reps restored on the game_molid (forward, backup::apply) + viewpoint
#        restored on the restored molid within 1e-4 (recursive flattener -- the
#        viewpoint is NESTED 4x4 matrices; naive abs() on the unflattened list
#        errors, and string-eq could drift on float formatting).
#
# 1k8p = 555 atoms, 5 placeholder hiders (the plan's chosen demo -- larger than
# 15-04's 1znf, exercising the full pipeline on a bigger body).
#
# Sources the lib files in dependency order directly (mirrors the entry, NOT
# the entry itself -- avoids GUI/dialog baggage): setup_state, registry,
# rep_tiers (17.1-06 entry order -- game.tcl calls rep_tiers::* at CALL time),
# demos, backup, mutation, game. (demos + mutation each re-source setup_state
# themselves -- harmless constant re-init; registry is sourced ONCE here --
# re-sourcing would WIPE _records.)
#
# 17.1-07 NOTE: the start_game call passes an EXPLICIT VDW-only per_rep
# ([dict create VDW 5] 0) -- the 2-arg form now randomizes across implemented
# tiers (17.1-06), and the saved_numreps + 2 invariant holds only for
# single-tier rounds.
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd] (VMD
# cwd = staging root) to locate the lib files. VMD does NOT propagate tcl exit
# codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD -e
# catches top-level errors and CONTINUES (possible false-PASS) -> every step is
# wrapped in catch + _bail, and the runner also scans the log for ERROR) lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (Pitfall 3 -- a dangling selection on a deleted molecule returns
# STALE data silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# ---- Recursive viewpoint flattener + maxdiff (15-RESEARCH-backup-restore.md,
#      probe-verified). molinfo's 4-matrix combined get returns NESTED
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

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set saved_numreps -1
set game_molid -1
set vp_orig [list]
set gs [list]

# ---- Source the lib files in dependency order ([pwd]-relative; [info script]
#      is empty under -e). Mirrors the entry's source order minus dialog.tcl.
#      Phase 16 (16-08): hiders.tcl is sourced too -- start_game now calls
#      hiders::add_hider_reps (call-time resolution needs the namespace). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
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

# ---- 1. SETUP: load 1k8p (555 atoms) + VDW rep + mutated viewpoint. ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }
    # Add a VDW rep (default load is Lines only -> 1 rep; addrep -> 2 reps) so
    # SC4's "reps restored" has something > 1 to restore.
    catch {mol representation VDW}
    if {[catch {mol addrep $orig_molid} adderr]} { _bail addrep $adderr }
    # Mutate the viewpoint (rotate/scale/translate act on the TOP molecule --
    # load_demo just made the original the top molecule).
    rotate x by 30
    rotate y by 45
    scale to 0.8
    translate by 0.5 0.5 0.5
    set saved_numreps [molinfo $orig_molid get numreps]
    if {$saved_numreps != 2} { _bail saved_numreps "exp=2 got=$saved_numreps" }
    # SC4 baseline: the 4-matrix combined get (POSITIONAL field order -- the
    # SAME form backup::snapshot uses, so the round-trip compare is
    # apples-to-apples).
    set vp_orig [molinfo $orig_molid get {rotate_matrix center_matrix scale_matrix global_matrix}]
}

# ---- 2. START: game::start_game on 1k8p + 5 placeholder hiders -> game_state.
#      This is the orchestrator (snapshot -> make_placeholder_hiders -> mutate
#      -> backup::apply -> registry DI); backup/mutation/registry are NOT
#      called directly here. ----
if {![catch {::biochemeleon::game::start_game $orig_molid 5 [dict create VDW 5] 0} gs]} {
    if {[catch {dict get $gs game_molid} game_molid]} {
        _bail gs_key_game_molid "missing (gs=$gs)"
    } else {
        # game_molid monotonic > original (Pitfall 4 -- molids never reused).
        if {$game_molid <= $orig_molid} {
            _bail game_molid_monotonic "game_molid=$game_molid <= orig=$orig_molid"
        }
        # SC1a: 555 + 5 = 560 atoms on the combined molecule.
        set n1 [molinfo $game_molid get numatoms]
        if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
        # SC1b: exactly 5 sentinels via the canonical selector (NEVER
        # 'beta < 0' alone / never exact 'beta -999'), indices 555-559, segid
        # GAME (tagged in-place post-load by mutation).
        if {![catch {atomselect $game_molid "resname GAM and beta < 0"} sel]} {
            if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
            if {[$sel get index] ne {555 556 557 558 559}} {
                _bail sentinel_idx "got=[$sel get index]"
            }
            if {[$sel get segid] ne "GAME GAME GAME GAME GAME"} {
                _bail sentinel_segid "got=[$sel get segid]"
            }
            $sel delete
        } else { _bail sentinel_sel $sel }
        # SC1c: original atom 0 intact (name N1) -- the writepdb-then-splice
        # must NOT corrupt the real atoms.
        if {![catch {atomselect $game_molid "index 0"} s0]} {
            if {[$s0 get name] ne "N1"} {
                _bail orig_intact "got=[$s0 get name] want N1"
            }
            $s0 delete
        } else { _bail orig_sel $s0 }
        # SC3a: registry reconstructed from the sentinels via the
        # [list apply {lambda} $game_molid] DI (command-prefix VALUE).
        set ch [::biochemeleon::registry::count_hiders]
        if {$ch != 5} { _bail registry_count "exp=5 got=$ch" }
        foreach idx {555 556 557 558 559} {
            if {![::biochemeleon::registry::is_hider $idx]} { _bail is_hider_true $idx }
        }
        if {[::biochemeleon::registry::is_hider 0]} { _bail is_hider_false "idx 0" }
        # SC4 forward: backup::apply restored the saved reps on the game_molid.
        # Phase 16 (16-08): start_game now ALSO adds the 2 hider reps
        # (hiders::add_hider_reps after apply -- research SS5.5), so the game
        # molid carries saved_numreps + 2. The restored molid below still has
        # EXACTLY the saved reps (cleanup restores the original, no hider reps).
        set gn [molinfo $game_molid get numreps]
        if {$gn != $saved_numreps + 2} {
            _bail game_numreps "exp=$saved_numreps + 2 got=$gn"
        }

        # ---- 3. CLEANUP: game::cleanup -> restore the original + reset the
        #      registry (backup::restore $snapshot $game_molid + registry::reset). ----
        if {![catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
            # SC2a: 555 atoms (no hiders) on the restored molid.
            set n2 [molinfo $restored_molid get numatoms]
            if {$n2 != 555} { _bail restored_atoms "exp=555 got=$n2" }
            # SC2b: same reps as the original.
            set rn [molinfo $restored_molid get numreps]
            if {$rn != $saved_numreps} {
                _bail restored_numreps "exp=$saved_numreps got=$rn"
            }
            # SC2c: no hider residue on the restored molid.
            if {![catch {atomselect $restored_molid "resname GAM and beta < 0"} sel2]} {
                if {[$sel2 num] != 0} { _bail restored_sentinels "exp=0 got=[$sel2 num]" }
                $sel2 delete
            } else { _bail restored_sentinel_sel $sel2 }
            # SC2d (false-pass guard): the LIVE game_molid was DELETED by
            # cleanup's backup::restore $snapshot $game_molid (NOT the dead
            # snapshot.molid). If it is still alive, restore deleted the WRONG
            # molid -> the 560-atom game molecule LEAKED.
            if {![catch {molinfo $game_molid get numatoms} ghost]} {
                _bail game_molid_leaked "game_molid $game_molid still alive (numatoms=$ghost)"
            }
            # SC3b: registry cleared after cleanup (reset).
            set ch2 [::biochemeleon::registry::count_hiders]
            if {$ch2 != 0} { _bail registry_after_cleanup "exp=0 got=$ch2" }
            # SC4 restore: viewpoint round-trip on the restored molid
            # (recursive flattener + 1e-4 tolerance -- NOT string eq, NOT naive
            # abs on the nested matrices).
            set vp_restored [molinfo $restored_molid get {rotate_matrix center_matrix scale_matrix global_matrix}]
            set vd [_vp_maxdiff $vp_orig $vp_restored]
            if {$vd >= 1e-4} { _bail viewpoint_maxdiff "maxdiff=$vd (exp < 1e-4)" }
        } else {
            _bail cleanup $restored_molid
        }
    }
} else {
    _bail start_game $gs
}

# ---- 4. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
