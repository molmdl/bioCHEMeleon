# vmd/smoke/phase15_mutation_smoke.tcl
# Headless smoke for Phase 15 Plan 02: the mutation.tcl mol bridge (PDB-rebuild
# engine). Proves the FORWARD mutate-reload + sentinel + registry DI:
#   SC1        : combined molecule has 555+5=560 atoms; exactly 5 sentinels via
#                the canonical selector 'resname GAM and beta < 0'; indices
#                555-559; segid GAME; original atom0 (N1) intact.
#   SC3-DI     : registry reconstruct_from_sentinels via the injected
#                fetch_hider_indices command prefix -> is_hider true for
#                555-559, false for 0.
#   SC2-mech   : raw mol delete + mol new original -> 0 sentinels (backup::restore
#                wraps this in Plan 03; this smoke tests mutation.tcl ALONE).
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here (Phase 13 Pitfall
# 3), so use [pwd] (VMD cwd = staging root) to locate the lib files, then `source`
# them. Each lib's own [info script] then works correctly because it was
# `source`d (not `-e`d). This is the verified Phase 13+ pattern; do NOT change.
#
# VMD does NOT propagate tcl exit codes (Phase 13 Pitfall 4) -- the WSL runner
# greps the BCHM_SMOKE_RESULT marker line, NEVER $? (VMD always exits 0). VMD -e
# catches top-level errors and continues, so a mid-script error does NOT prevent
# a false-PASS marker -- the runner greps the FAIL= list AND scans for ERROR).
#
# Tcl 8.5 only. Every atomselect is $sel delete'd (Pitfall 3 -- atomselect leaks;
# a dangling selection on a deleted molecule returns STALE data silently).
# Sources setup_state + registry + demos + mutation. Does NOT source backup.tcl
# (Plan 03, not in this worktree) and does NOT call registry::count_hiders
# (Plan 01's addition, not in this worktree) -- uses only is_hider (Phase 13).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# ---- Source the lib files ([pwd]-relative; [info script] is empty under -e). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    demos        [file join [pwd] vmd lib demos.tcl] \
    mutation     [file join [pwd] vmd lib mutation.tcl]] {
    if {![file exists $path]} {
        lappend failures "${nm}_not_found:$path"
    } elseif {[catch {source $path} err]} {
        lappend failures "${nm}_source_error:$err"
    }
}

set pdb [::biochemeleon::demos::to_vmd_path "[pwd]/vmd/data/demos/1k8p.pdb"]
file mkdir "[pwd]/tmpout"
set outpdb [::biochemeleon::demos::to_vmd_path "[pwd]/tmpout/comb15.pdb"]

# ---- 1. Load 1k8p (555) + make 5 placeholder hiders. ----
set m0 [mol new $pdb type pdb waitfor all]
set orig_n [molinfo $m0 get numatoms]
if {$orig_n != 555} { _bail orig_atoms "exp=555 got=$orig_n" }

set hiders [::biochemeleon::mutation::make_placeholder_hiders $m0 5]
if {[llength $hiders] != 5} { _bail hider_count "[llength $hiders]" }
# Sanity: each record is {name x y z} (4 elements).
set bad_rec 0
foreach r $hiders { if {[llength $r] != 4} { incr bad_rec } }
if {$bad_rec != 0} { _bail hider_rec_shape "$bad_rec records not {name x y z}" }

# ---- 2. write_combined_pdb DIRECT call -> verify PDB content (mutate's internal
#         path is separate; this call verifies the file). Returns orig_n (555). ----
set ret_n [::biochemeleon::mutation::write_combined_pdb $m0 $hiders $outpdb]
if {$ret_n != 555} { _bail wcp_return "exp=555 got=$ret_n" }
# 2a. File has 560 atom records (428 ATOM + 127 HETATM originals + 5 hider ATOM).
if {![file exists $outpdb]} {
    _bail wcp_file "not found: $outpdb"
} else {
    set fh [open $outpdb r]
    set alllines [split [read $fh] \n]
    close $fh
    set nrec 0
    set nhider 0
    set hider_bad 0
    foreach l $alllines {
        if {[regexp {^(ATOM|HETATM)} $l]} { incr nrec }
        # Hider records carry chain+resseq "G9001" (disjoint from real resids).
        if {[regexp {G9001} $l]} {
            incr nhider
            if {![regexp {GAM} $l] || ![regexp -- {-999\.0} $l] || ![regexp {GAME} $l]} {
                incr hider_bad
            }
        }
    }
    if {$nrec != 560} { _bail wcp_records "exp=560 got=$nrec" }
    if {$nhider != 5} { _bail wcp_hider_lines "exp=5 got=$nhider" }
    if {$hider_bad != 0} { _bail wcp_hider_fmt "$hider_bad hider lines missing GAM/-999.0/GAME" }
}

# ---- 3. mutate path: re-load 1k8p (m0 was NOT deleted by write_combined_pdb --
#         it only wrote a file), then mutate (2-arg; deletes m0b + mol new +
#         tags sentinels). m0 is no longer needed -> delete for a clean mol list. ----
mol delete $m0
set m0b [mol new $pdb type pdb waitfor all]
set m1 [::biochemeleon::mutation::mutate $m0b $hiders]
# 3a. new molid is monotonic (Pitfall 4 -- molids never reused).
if {$m1 <= $m0b} { _bail new_molid "m1=$m1 <= m0b=$m0b" }
# 3b. atom count = orig + 5.
set n1 [molinfo $m1 get numatoms]
if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
# 3c. canonical sentinel selector == 5 (NEVER 'beta < 0' alone).
set sel [atomselect $m1 "resname GAM and beta < 0"]
if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
# 3d. indices are the last 5 (555..559).
set want_idxs [list 555 556 557 558 559]
if {[$sel get index] ne $want_idxs} { _bail sentinel_idx "got=[$sel get index]" }
# 3e. in-place segid sticks (beta/segid set after mol new -- rescues column bugs).
if {[$sel get segid] ne "GAME GAME GAME GAME GAME"} { _bail sentinel_segid "got=[$sel get segid]" }
$sel delete
# 3f. original atoms intact (index 0 still the real N1).
set s0 [atomselect $m1 "index 0"]
if {[$s0 get name] ne "N1"} { _bail orig_intact "index0 name=[$s0 get name] want N1" }
$s0 delete

# ---- 4. Registry DI (proc-prefix style): reconstruct_from_sentinels via the
#         injected fetch_hider_indices command prefix. is_hider correct.
#         (count_hiders is Plan 01's addition -- NOT called here; this worktree
#         may not have it. Use only is_hider, which exists from Phase 13.) ----
::biochemeleon::registry::reconstruct_from_sentinels \
    [list ::biochemeleon::mutation::fetch_hider_indices $m1]
if {![::biochemeleon::registry::is_hider 555]} { _bail reg_555 "not registered" }
if {![::biochemeleon::registry::is_hider 559]} { _bail reg_559 "not registered" }
if {[::biochemeleon::registry::is_hider 0]}   { _bail reg_0 "real atom 0 wrongly registered" }

# ---- 5. Cleanup MECHANISM: raw mol delete + mol new original -> no hider
#         residue. (In the real game, backup.tcl::restore owns this reload +
#         re-applies reps/viewpoint; this smoke proves the underlying mechanism
#         since it tests mutation.tcl ALONE.) ----
mol delete $m1
set m2 [mol new $pdb type pdb waitfor all]
if {$m2 <= $m1} { _bail cleanup_molid "m2=$m2 <= m1=$m1" }
if {[molinfo $m2 get numatoms] != 555} { _bail cleanup_atoms "exp=555 got=[molinfo $m2 get numatoms]" }
set left [atomselect $m2 "resname GAM and beta < 0"]
if {[$left num] != 0} { _bail cleanup_leftover "exp=0 got=[$left num]" }
$left delete

# ---- Report. VMD does NOT propagate tcl exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
