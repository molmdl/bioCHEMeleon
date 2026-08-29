# vmd/smoke/phase14_mol_smoke.tcl
# Headless smoke for Phase 14 Plan 02: the mol bridge (demos.tcl). Verifies all
# 6 bundled demos load with correct atom counts, rep detection works (and
# survives mol delrep renumbering), atom_count + fetch_pdb stub behave, and
# save/load round-trips a setup dict with dict eq=1.
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here (Phase 13 Pitfall
# 3), so use [pwd] (VMD cwd = staging root) to locate demos.tcl, then `source`
# it. demos.tcl's own [info script] then works correctly because it was
# `source`d (not `-e`d). This is the verified Phase 13+ pattern; do NOT change.
#
# VMD does NOT propagate tcl exit codes (Phase 13 Pitfall 4) -- the WSL runner
# greps the BCHM_SMOKE_RESULT marker line, NEVER $? (VMD always exits 0).

set failures [list]

# ---- Source the mol bridge (which sources setup_state.tcl for constants). ----
set demos [file join [pwd] vmd lib demos.tcl]
if {![file exists $demos]} {
    lappend failures "demos_not_found:$demos"
} elseif {[catch {source $demos} err]} {
    lappend failures "demos_source_error:$err"
}

# Helper: append a failure tag (keeps the failure list compact for the marker).
proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# ---- Check 1: to_vmd_path (WSL->VMD path guard). ----
if {![catch {::biochemeleon::demos::to_vmd_path "/mnt/c/Users/foo"} got]} {
    if {$got ne "C:/Users/foo"} { _bail to_vmd_path_mnt $got }
} else { _bail to_vmd_path_mnt_err $got }
if {![catch {::biochemeleon::demos::to_vmd_path "C:/already"} got]} {
    if {$got ne "C:/already"} { _bail to_vmd_path_win $got }
} else { _bail to_vmd_path_win_err $got }
if {![catch {::biochemeleon::demos::to_vmd_path "relative/path"} got]} {
    if {$got ne "relative/path"} { _bail to_vmd_path_rel $got }
} else { _bail to_vmd_path_rel_err $got }

# ---- Check 2: load_demo all 6 bundled demos + verified atom counts. ----
# Verified counts (research mol-logic lines 50-59): 1znf=424, 1xdn=2597,
# 5e54=2844, 1k8p=555, 2qbz=3408, 4wb3=3779.
set expected [dict create 1znf 424 1xdn 2597 5e54 2844 1k8p 555 2qbz 3408 4wb3 3779]
set last_mol -1
foreach {did exp_n} $expected {
    if {[catch {::biochemeleon::demos::load_demo $did} molid]} {
        _bail "load_demo_$did" $molid
        continue
    }
    if {[catch {molinfo $molid get numatoms} got_n]} {
        _bail "load_demo_numatoms_$did" $got_n
        continue
    }
    if {$got_n != $exp_n} { _bail "load_demo_atoms_$did" "exp=$exp_n got=$got_n" }
    set last_mol $molid
}

# ---- Check 3: list_loaded_molecules -> 6 display strings "<name> (<molid>)". ----
if {![catch {::biochemeleon::demos::list_loaded_molecules} mols]} {
    if {[llength $mols] != 6} {
        _bail list_loaded_count "[llength $mols] (want 6)"
    } else {
        foreach m $mols {
            # Must end with "(<digits>)" -- the <name> (<molid>) display form.
            if {![regexp {\((\d+)\)$} $m -> mid]} { _bail list_loaded_format $m }
        }
    }
} else { _bail list_loaded_err $mols }

# ---- Check 5: atom_count (run BEFORE check 4 mutates reps; atoms are rep-
#      independent, but this keeps the two checks cleanly decoupled). ----
if {$last_mol >= 0} {
    if {![catch {molinfo $last_mol get numatoms} direct]} {
        set via_ac [::biochemeleon::demos::atom_count $last_mol]
        if {$via_ac != $direct} { _bail atom_count_good "exp=$direct got=$via_ac" }
    } else { _bail atom_count_direct $direct }
}
# bad molid -> 0 (catch path)
if {![catch {::biochemeleon::demos::atom_count 999} bad]} {
    if {$bad != 0} { _bail atom_count_bad "exp=0 got=$bad" }
} else { _bail atom_count_bad_err $bad }

# ---- Check 4: get_active_reps (uses the LAST loaded molid; survives renumber). ----
if {$last_mol >= 0} {
    # 4a. Freshly loaded mol has 1 default rep: Lines.
    if {![catch {::biochemeleon::demos::get_active_reps $last_mol} r0]} {
        if {$r0 ne "Lines"} { _bail active_reps_fresh "exp=Lines got=$r0" }
    } else { _bail active_reps_fresh_err $r0 }

    # 4b. Add a VDW rep -> "Lines VDW".
    if {![catch {mol representation VDW}]} {
        if {[catch {mol addrep $last_mol} adderr]} { _bail active_reps_addrep $adderr }
        if {![catch {::biochemeleon::demos::get_active_reps $last_mol} r1]} {
            if {$r1 ne "Lines VDW"} { _bail active_reps_2reps "exp=Lines VDW got=$r1" }
        } else { _bail active_reps_2reps_err $r1 }
    } else { _bail active_reps_setrep $adderr }

    # 4c. Delete rep 0 -> VDW shifts to index 0 -> "VDW". Verifies style detection
    #     survives mol delrep renumbering (Pitfall 2).
    if {[catch {mol delrep 0 $last_mol} delerr]} { _bail active_reps_delrep $delerr }
    if {![catch {::biochemeleon::demos::get_active_reps $last_mol} r2]} {
        if {$r2 ne "VDW"} { _bail active_reps_postdel "exp=VDW got=$r2" }
    } else { _bail active_reps_postdel_err $r2 }
} else {
    _bail active_reps "no_mol_loaded"
}

# ---- Check 6: fetch_pdb stub -> error containing "not implemented". ----
if {![catch {::biochemeleon::demos::fetch_pdb 1CRN} fetcherr]} {
    _bail fetch_pdb_rc "exp=error got=ok:$fetcherr"
} else {
    if {![string match "*not implemented*" $fetcherr]} {
        _bail fetch_pdb_msg $fetcherr
    }
}

# ---- Check 7: save_setup/load_setup round-trip with `eq`=1. ----
# randomize_state 42 555 -> complete 11-key dict in DEFAULTS order, per_rep
# populated (quick-008 guarantee). Round-trips via the DEFAULTS-key-order
# rebuild on load (Pitfall 5). Temp file under [pwd] (staging root).
# NOTE: `eq` is the tcl string-equality OPERATOR (compares dict string reps);
# there is NO `dict eq` subcommand in tcl 8.5 (research "dict eq" is shorthand
# for `expr {$a eq $b}`). Order-sensitivity is the whole point (Pitfall 5).
if {![catch {::biochemeleon::setup_state::randomize_state 42 555} original]} {
    set tmpfile [file join [pwd] tmp_test_setup.bcm]
    if {![catch {::biochemeleon::demos::save_setup $original $tmpfile} saveerr]} {
        if {![catch {::biochemeleon::demos::load_setup $tmpfile} loaded]} {
            set same [expr {$loaded eq $original}]
            if {$same == 0} {
                _bail roundtrip_eq "0 (original != loaded)"
                puts "  DEBUG original: $original"
                puts "  DEBUG loaded:   $loaded"
            }
        } else { _bail load_setup $loaded }
    } else { _bail save_setup $saveerr }
    catch {file delete $tmpfile}  ;# cleanup (harmless if absent)
} else { _bail randomize_state $original }

# ---- Report. VMD does NOT propagate tcl exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
