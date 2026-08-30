# vmd/smoke/phase15_backup_smoke.tcl
# Headless smoke for Phase 15 Plan 03: backup.tcl (viewpoint + rep save/restore
# on a NEW molid). Proves the save/restore round-trip (SC2 + SC4) and the
# PDB-rebuild-flow contract: `restore $snap $molid_to_delete` deletes the LIVE
# molid PASSED by the caller (NOT the dead snapshot.molid -- the original was
# deleted by mutation::mutate during start_game).
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here (Phase 13 Pitfall
# 3), so use [pwd] (VMD cwd = staging root) to locate backup.tcl, then `source`
# it. backup.tcl's own [info script] then works correctly because it was
# `source`d (not `-e`d). This is the verified Phase 13+ pattern; do NOT change.
#
# STANDALONE: does NOT source demos.tcl/mutation.tcl/registry.tcl -- backup.tcl
# is tested ALONE (it uses NO atomselect, NO registry). A local `_to_vmd` path
# helper mirrors demos::to_vmd_path (sourcing demos.tcl would reverse the
# dependency direction). USE 1xdn.pdb (PROTEIN, 2597 atoms) so Cartoon +
# Structure render cleanly (1k8p is nucleic -> Stride warnings -- Pitfall 8).
#
# VMD does NOT propagate tcl exit codes (Phase 13 Pitfall 4) -- the WSL runner
# greps the BCHM_SMOKE_RESULT marker line, NEVER $? (VMD always exits 0).

set failures [list]

# Helper: append a failure tag (keeps the failure list compact for the marker).
proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# ---- Source backup.tcl via [pwd] (STANDALONE -- no deps). ----
set bk [file join [pwd] vmd lib backup.tcl]
if {![file exists $bk]} {
    _bail backup_not_found $bk
} elseif {[catch {source $bk} err]} {
    _bail backup_source_error $err
}

# ---- Local _to_vmd path helper (mirror demos::to_vmd_path; do NOT source
#      demos.tcl -- reverses dependency). /mnt/c/... -> C:/... (forward slashes).
proc _to_vmd {p} {
    if {[regexp {^/mnt/([a-zA-Z])/(.*)$} $p -> drive rest]} {
        return "[string toupper $drive]:/$rest"
    }
    return $p
}
set pdb [_to_vmd "[pwd]/vmd/data/demos/1xdn.pdb"]

# ---- Recursive flatten + numeric maxdiff (Pitfall 2 -- the viewpoint is a
#      NESTED 4-element list of 4x4 matrices, NOT a flat 64-list; naive
#      abs($a-$b) errors "can't use non-numeric string"). Copy verbatim from
#      research lines 360-377 (probe2-verified).
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
        if {[catch {expr {abs($x - $y)}} d]} continue   ;# skip non-numeric (none expected)
        if {$d > $maxd} { set maxd $d }
    }
    return $maxd
}

# Helper: set up the SAME 3-rep + mutated-viewpoint state on a freshly-loaded
# 1xdn molid. form A (mol representation/color/selection/material + mol addrep)
# is fine here -- we are setting up the SAVED state, not restoring (restore uses
# form B in backup.tcl). The caller passes the molid; the mol must already be
# TOP so rotate/scale/translate target it (mol new makes the new mol top).
proc _setup_3reps_mutate_vp {m} {
    mol representation VDW;  mol selection "name CA";  mol color Name;  mol material Opaque;     mol addrep $m
    mol representation Cartoon; mol selection "protein"; mol color Structure; mol material Transparent; mol addrep $m
    rotate x by 30; rotate y by 45; scale to 0.8; translate by 0.5 0.5 0.5
}

# Helper: run the SC2 + SC4 round-trip assertions for a (snapshot, new_molid)
# pair. Asserts: atom count + numreps restored exactly, each rep {style, sel,
# color, material} matches saved (rep-index order), viewpoint maxdiff < 1e-4.
proc _assert_roundtrip {tag snap new_m atoms_before numreps_before} {
    upvar 1 failures f
    set saved_reps [dict get $snap reps]
    # atom count (SC2)
    set atoms_after [molinfo $new_m get numatoms]
    if {$atoms_after != $atoms_before} { lappend f "${tag}_atoms:exp=$atoms_before got=$atoms_after" }
    # numreps (SC2 "same reps")
    set numreps_after [molinfo $new_m get numreps]
    if {$numreps_after != $numreps_before} { lappend f "${tag}_numreps:exp=$numreps_before got=$numreps_after" }
    # each rep matches saved (rep-index order, via the combined-braces form)
    for {set i 0} {$i < $numreps_after} {incr i} {
        foreach {r s c mat} [molinfo $new_m get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        set want [lindex $saved_reps $i]
        if {$r ne [lindex $want 0] || $s ne [lindex $want 1] || $c ne [lindex $want 2] || $mat ne [lindex $want 3]} {
            lappend f "${tag}_rep_mismatch:i=$i got={$r $s $c $mat} want=$want"
        }
    }
    # viewpoint maxdiff < 1e-4 (SC4, viewmaster round-trip)
    set vp_saved    [dict get $snap viewpoint]
    set vp_restored [molinfo $new_m get {rotate_matrix center_matrix scale_matrix global_matrix}]
    set md [_vp_maxdiff $vp_saved $vp_restored]
    if {$md >= 1e-4} { lappend f "${tag}_viewpoint_maxdiff:$md" }
}

# =========================================================================
# CASE 1: live-original round-trip (SC2 + SC4 + passed-molid-deleted contract).
# =========================================================================

# 1. Load original, set up 3 reps (default Lines + VDW on "name CA" + Cartoon on
#    "protein" with Structure color + Transparent material), mutate viewpoint.
set m [mol new $pdb type pdb]
_setup_3reps_mutate_vp $m
set atoms_before [molinfo $m get numatoms]      ;# expect 2597
set numreps_before [molinfo $m get numreps]     ;# expect 3 (default Lines + VDW + Cartoon)

# 2. Snapshot -> assert dict shape (keys molid/filename/viewpoint/reps all
#    exist; reps length == numreps_before).
if {[catch {::biochemeleon::backup::snapshot $m} snap]} {
    _bail snapshot $snap
} else {
    if {![dict exists $snap molid]}    { _bail snap_shape molid }
    if {![dict exists $snap filename]} { _bail snap_shape filename }
    if {![dict exists $snap viewpoint]} { _bail snap_shape viewpoint }
    if {![dict exists $snap reps]}     { _bail snap_shape reps }
    if {[llength [dict get $snap reps]] != $numreps_before} {
        _bail snap_reps_count "[llength [dict get $snap reps]] (want $numreps_before)"
    }
}

# 3. Restore $snap $m -> new_m (2nd arg = the LIVE molid to delete). Full cycle:
#    mol delete $m + mol new original + apply + return new molid.
if {![catch {::biochemeleon::backup::restore $snap $m} new_m]} {
    # 4. NEW molid is monotonic-higher (Pitfall 1).
    if {$new_m <= $m} { _bail new_molid_monotonic "old=$m new=$new_m" }
    # 5-8. SC2 + SC4 round-trip assertions.
    _assert_roundtrip case1 $snap $new_m $atoms_before $numreps_before
    # 9. Assert the PASSED molid ($m) is deleted: catch {molinfo $m get numatoms}
    #    returns NONZERO ($m is gone -- proves `restore` deletes $molid_to_delete,
    #    not snapshot.molid). In isolation $m == snap.molid and $m was live, so
    #    this is identical to the old behavior -- but the assertion locks the
    #    contract.
    set rc [catch {molinfo $m get numatoms} msg]
    if {$rc == 0} { _bail case1_passed_molid_alive "exp=$m deleted got=numatoms=$msg" }
} else {
    _bail restore $new_m
}

# =========================================================================
# CASE 2: dead-original sub-case (REGRESSION GUARD for the PDB-rebuild flow).
# Simulates mutation::mutate deleting the original molid during start_game:
# snapshot.molid is DEAD by cleanup time. restore must delete the LIVE
# game_molid PASSED as the 2nd arg (m3), NOT the dead snapshot.molid (m2).
# This sub-case would have CAUGHT the Plan-03/04 integration blocker in
# isolation (the old 1-arg restore deleting snapshot.molid would have errored
# on the already-dead m2 OR silently leaked the live game_molid m3).
# =========================================================================

# 1. Load a SECOND copy of 1xdn -> m2, same 3-rep + mutated-viewpoint setup.
set m2 [mol new $pdb type pdb]
_setup_3reps_mutate_vp $m2
# 2. snapshot $m2 -> snap2 (snap2.molid == m2).
if {[catch {::biochemeleon::backup::snapshot $m2} snap2]} {
    _bail case2_snapshot $snap2
} else {
    # 3. Manually `mol delete $m2` -- simulates mutation::mutate deleting the
    #    original; snap2.molid (m2) is now DEAD.
    mol delete $m2
    # 4. Load a LIVE molecule to stand in for the game_molid (cleanup's
    #    molid_to_delete argument). m3 = fresh 1xdn (2597 atoms).
    set m3 [mol new $pdb type pdb]
    # 5. restore $snap2 $m3 -> new_m2. Must delete $m3 (PASSED), reload original,
    #    apply snap2's reps + viewpoint.
    if {![catch {::biochemeleon::backup::restore $snap2 $m3} new_m2]} {
        # SC2 + SC4 round-trip on new_m2 against snap2.
        _assert_roundtrip case2 $snap2 $new_m2 $atoms_before $numreps_before
        # Assert m3 (the PASSED molid_to_delete) is GONE -- restore deleted the
        # LIVE m3, NOT the dead m2.
        set rc3 [catch {molinfo $m3 get numatoms} msg3]
        if {$rc3 == 0} { _bail case2_passed_molid_alive "exp=m3=$m3 deleted got=numatoms=$msg3" }
        # Assert m2 stays DEAD -- restore did NOT error trying to re-delete the
        # already-dead original, and did NOT resurrect it.
        set rc2 [catch {molinfo $m2 get numatoms} msg2]
        if {$rc2 == 0} { _bail case2_dead_original_resurrected "exp=m2=$m2 dead got=numatoms=$msg2" }
    } else {
        _bail case2_restore $new_m2
    }
}

# =========================================================================
# CASE 3: bad-molid snapshot errors (caller -- game.tcl -- can abort the game).
# =========================================================================
if {![catch {::biochemeleon::backup::snapshot 999} bad]} {
    _bail snapshot_bad_molid "exp=error got=ok:$bad"
}

# ---- Report. VMD does NOT propagate tcl exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
