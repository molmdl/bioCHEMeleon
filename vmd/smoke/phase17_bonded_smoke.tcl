# vmd/smoke/phase17_bonded_smoke.tcl
# Phase 17.1 Plan 05 headless CHEMISTRY smoke: proves make_bonded_hiders'
# anchor mimicry + auto-bonding through the real PDB-rebuild path. On demo
# 1znf (424 atoms; 37-model NMR ensemble -- VMD loads model 1's 424 atoms):
#   1. RECORDS  : make_bonded_hiders $m0 5 -> 5 records of the 5-field
#                 {name element x y z} shape; every name is a REAL atom name
#                 (never G%02d) and every element in {C N O S P} AND some real
#                 atom's element; coords finite and |coord| <= 9999.
#   2. PDB LAYO : write_combined_pdb DIRECT call -> the last 5 ATOM lines are
#                 exactly 78 cols with NON-BLANK element (cols 77-78, copied
#                 from the record -- the probe-J blank-element regression
#                 guard), resname GAM (18-20), segid GAME (73-76), beta field
#                 "-999.0" (61-66, %6.1f -- NEVER %6.2f).
#   3. MUTATE   : fresh 1znf -> mutate -> 424+5 = 429 atoms; hider indices
#                 {424..428} via the canonical selector 'resname GAM and
#                 beta < 0'.
#   4. BOND LAW : every hider numbonds >= 1 (never == 1 -- extra bonds are
#                 NORMAL); parsed element == written element; radius == the
#                 element's VDW radius (C 1.70 / N 1.55 / O 1.52 / S 1.80 /
#                 P 1.55, eps 1e-6 -- the blank-element->X-1.50 regression
#                 guard); name in the real names; SOME real atom within the
#                 1.2-1.6 A bond band of every hider (nearest-real-atom
#                 distance <= 1.61 -- the anchor is never in the occupied
#                 list, so the anchor-bond band holds even when the 17.1-03
#                 relaxation contract fired). Full-sep accepts additionally
#                 sit in [1.19, 1.61]; relaxed accepts (nearest < 1.19) are
#                 LOGGED and only asserted non-degenerate.
#   5. SENTINEL : betas all -999.0 (numeric), segids all GAME.
#   6. SEPARATION: min pairwise hider-hider distance >= 3.9 (sep 4.0, strict-<
#                 boundary + %8.3f rounding); if a pair dips below 3.9 the
#                 relaxation fallback fired for it -- the smoke LOGS that and
#                 then only asserts >= 1.19.
# The blending VISUAL is a later GUI human-verify; this smoke proves chemistry.
#
# This script is `-e`'d by VMD -- [info script] is EMPTY here (Phase 13 Pitfall
# 3), so use [pwd] (VMD cwd = staging root) to locate the lib files, then
# `source` them (each lib's own [info script] then works). Lib source order
# mirrors the entry: setup_state, registry, rep_tiers, generators, game_logic,
# demos, backup, mutation (registry sourced EXACTLY ONCE; mutation re-sources
# setup_state + generators itself -- harmless constant re-init).
#
# VMD does NOT propagate tcl exit codes (Pitfall 4) -- the WSL runner greps the
# BCHM_SMOKE_RESULT marker line, NEVER $?. VMD -e catches top-level errors and
# CONTINUES (false-PASS class) -- the runner also scans the FULL log for
# ERROR) / bad switch lines. Tcl 8.5 only (brace all expr; foreach+lappend).
# Every atomselect is $sel delete'd (Pitfall 3 -- stale-data silent hazard).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# VDW radii per element (research probe A, VMD 1.9.3 element table). -1 flags
# an element outside the heavy-anchor policy (would fail the radius assert).
proc _vdw_rad {el} {
    switch -- $el {
        C { return 1.70 }
        N { return 1.55 }
        O { return 1.52 }
        S { return 1.80 }
        P { return 1.55 }
        default { return -1 }
    }
}

# ---- 0. Source the lib files in dependency order ([pwd]-relative). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry    [file join [pwd] vmd lib registry.tcl] \
    rep_tiers   [file join [pwd] vmd lib rep_tiers.tcl] \
    generators  [file join [pwd] vmd lib generators.tcl] \
    game_logic  [file join [pwd] vmd lib game_logic.tcl] \
    demos       [file join [pwd] vmd lib demos.tcl] \
    backup      [file join [pwd] vmd lib backup.tcl] \
    mutation    [file join [pwd] vmd lib mutation.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

set pdb [::biochemeleon::demos::to_vmd_path "[pwd]/vmd/data/demos/1znf.pdb"]
file mkdir "[pwd]/tmpout"
set outpdb [::biochemeleon::demos::to_vmd_path "[pwd]/tmpout/comb17bonded.pdb"]

# Defensive init so a failed earlier step never masks as a substitution error.
set recs [list]
set real_names [list]
set real_elems [list]
set m0 -1
set gm -1

# ---- 1. RECORDS: load 1znf (424) + make_bonded_hiders 5. ----
set m0 [mol new $pdb type pdb waitfor all]
set orig_n [molinfo $m0 get numatoms]
if {$orig_n != 424} { _bail orig_atoms "exp=424 got=$orig_n" }

# Real name/element universes (424 atoms -- small enough for one bulk get;
# the AGENTS perf rule targets 100k+ molecules).
set allsel [atomselect $m0 "all"]
set real_names [$allsel get name]
set real_elems [$allsel get element]
$allsel delete

if {[catch {::biochemeleon::mutation::make_bonded_hiders $m0 5} mbh_err]} {
    _bail mbh_call $mbh_err
} else {
    set recs $mbh_err
    if {[llength $recs] != 5} { _bail rec_count "exp=5 got=[llength $recs]" }
    set bad_shape 0
    set bad_name 0
    set phony_name 0
    set bad_elem 0
    set bad_coord 0
    foreach r $recs {
        if {[llength $r] != 5} { incr bad_shape; continue }
        foreach {nm el x y z} $r { break }
        # Name mimicry: a real atom's name, never a placeholder G%02d.
        if {[lsearch -exact $real_names $nm] < 0} { incr bad_name }
        if {[regexp {^G[0-9][0-9]$} $nm]} { incr phony_name }
        # Element mimicry: the heavy-anchor policy AND some real atom's element.
        if {[lsearch -exact {C N O S P} $el] < 0} { incr bad_elem }
        if {[lsearch -exact $real_elems $el] < 0} { incr bad_elem }
        # Coords finite + inside the %8.3f guard (NaN makes the comparison
        # false, so !(<=) catches both overflow and NaN).
        foreach v [list $x $y $z] {
            if {[catch {expr {abs($v) <= 9999.0}} ok] || !$ok} { incr bad_coord }
        }
    }
    if {$bad_shape != 0} { _bail rec_shape "$bad_shape records not {name element x y z}" }
    if {$bad_name != 0} { _bail name_mimic "$bad_name names not real atom names" }
    if {$phony_name != 0} { _bail phony_name "$phony_name names match placeholder G%02d" }
    if {$bad_elem != 0} { _bail elem_mimic "$bad_elem elements outside {C N O S P}/real elements" }
    if {$bad_coord != 0} { _bail coord_finite "$bad_coord coords non-finite or |v|>9999" }
}

# ---- 2. PDB LAYOUT: write_combined_pdb DIRECT call -> inspect the hider
#         lines (hiders are appended LAST, before END). ----
if {[catch {::biochemeleon::mutation::write_combined_pdb $m0 $recs $outpdb} wret]} {
    _bail wcp_call $wret
} else {
    if {$wret != 424} { _bail wcp_return "exp=424 got=$wret" }
    if {![file exists $outpdb]} {
        _bail wcp_file "not found: $outpdb"
    } else {
        set fh [open $outpdb r]
        set alllines [split [read $fh] \n]
        close $fh
        set atomlines [list]
        foreach l $alllines {
            if {[string range $l 0 3] eq "ATOM" || [string range $l 0 5] eq "HETATM"} {
                lappend atomlines $l
            }
        }
        if {[llength $atomlines] != 429} {
            _bail wcp_atom_lines "exp=429 got=[llength $atomlines]"
        }
        # The last 5 ATOM records are the bonded hiders.
        set tail [lrange $atomlines end-4 end]
        set i 0
        foreach l $tail {
            incr i
            if {[string length $l] != 78} {
                _bail pdb_len "hider $i len=[string length $l] (want 78)"
            }
            # Element cols 77-78 NON-BLANK and == the record's element
            # (the probe-J blank-element regression guard + copy-through).
            set pel [string trim [string range $l 76 77]]
            if {$pel eq ""} { _bail pdb_elem_blank "hider $i cols77-78 blank" }
            if {$i <= [llength $recs]} {
                set want_el [lindex [lindex $recs [expr {$i - 1}]] 1]
                if {$pel ne $want_el} {
                    _bail pdb_elem_copy "hider $i col='$pel' want=$want_el"
                }
            }
            if {[string range $l 17 19] ne "GAM"} {
                _bail pdb_resname "hider $i got=[string range $l 17 19]"
            }
            if {[string range $l 72 75] ne "GAME"} {
                _bail pdb_segid "hider $i got=[string range $l 72 75]"
            }
            # Beta field: %6.1f -> " -999.0" (trimmed compare; %6.2f would
            # overflow into segid -- the 15-02 pitfall).
            if {[string trim [string range $l 60 65]] ne "-999.0"} {
                _bail pdb_beta "hider $i got='[string range $l 60 65]'"
            }
        }
        # chain+resseq marker identifies hider lines; exactly 5.
        set nh 0
        foreach l $atomlines { if {[string first "G9001" $l] >= 0} { incr nh } }
        if {$nh != 5} { _bail pdb_hider_lines "exp=5 got=$nh" }
    }
}

# ---- 3/4/5. MUTATE + BOND LAW + SENTINEL round-trip on the game molecule. ----
mol delete $m0
set m0b [mol new $pdb type pdb waitfor all]
if {[catch {::biochemeleon::mutation::mutate $m0b $recs} gm]} {
    _bail mutate_call $gm
} else {
    if {$gm <= $m0b} { _bail new_molid "gm=$gm <= m0b=$m0b" }
    set n1 [molinfo $gm get numatoms]
    if {$n1 != 429} { _bail game_atoms "exp=429 got=$n1" }
    if {![catch {atomselect $gm "resname GAM and beta < 0"} sel]} {
        if {[$sel num] != 5} {
            _bail sentinel_count "exp=5 got=[$sel num]"
        } else {
            if {[$sel get index] ne {424 425 426 427 428}} {
                _bail hider_idx "got=[$sel get index]"
            }
            set hidx    [$sel get index]
            set hbonds  [$sel get numbonds]
            set helems  [$sel get element]
            set hnames  [$sel get name]
            set hrads   [$sel get radius]
            set hcoords [$sel get {x y z}]
            set hbetas  [$sel get beta]
            set hsegids [$sel get segid]
            # 4. BOND LAW: numbonds >= 1 (extra bonds NORMAL -- never assert
            # == 1); parsed element == written element (record order == file
            # order == index order); radius == VDW(element); name mimicry.
            set k 0
            foreach b $hbonds e $helems n $hnames r $hrads {
                incr k
                if {![string is integer -strict $b] || $b < 1} {
                    _bail bond_law "hider $k numbonds=$b (< 1)"
                }
                set want_el [lindex [lindex $recs [expr {$k - 1}]] 1]
                if {$e ne $want_el} {
                    _bail elem_parse "hider $k parsed element=$e want=$want_el"
                }
                set want_r [_vdw_rad $e]
                if {$want_r < 0} {
                    _bail elem_policy "hider $k element=$e outside heavy policy"
                } elseif {abs($r - $want_r) > 1e-6} {
                    _bail radius_mimic "hider $k el=$e radius=$r want=$want_r"
                }
                if {[lsearch -exact $real_names $n] < 0} {
                    _bail name_mimic2 "hider $k name=$n not a real atom name"
                }
            }
            # Nearest-REAL-atom distance per hider. INVARIANT: the ANCHOR is
            # never in the occupied list, so every hider sits at a fresh
            # 1.2-1.6 A draw from its anchor (relaxation only shrinks the
            # OTHER seps) -> min distance over real atoms <= 1.61 ALWAYS
            # (with %8.3f rounding). The LOWER bound (>= 1.19) holds only for
            # full-sep accepts: on crowded anchors (H-bearing sp3 carbons --
            # each bonded H at ~1.09 A blocks a ~67-degree cone of the thin
            # 1.2-1.6 shell) the 25 full-sep tries can exhaust and the pinned
            # 17.1-03 relaxation contract accepts a candidate closer than the
            # band to a NON-anchor real atom. DISCOVERY (1znf, 5 hiders):
            # 3/5 relaxed. Per the plan's inspect-then-pin instruction:
            # <= 1.61 asserted for ALL; full-sep accepts also >= 1.19;
            # relaxed accepts LOGGED + asserted non-degenerate (> 1e-6).
            set rsel [atomselect $gm "index < 424"]
            set rcoords [$rsel get {x y z}]
            $rsel delete
            set k 0
            foreach c $hcoords {
                incr k
                lassign $c hx hy hz
                set mind2 1e30
                foreach rc $rcoords {
                    lassign $rc rx ry rz
                    set dx [expr {$hx - $rx}]
                    set dy [expr {$hy - $ry}]
                    set dz [expr {$hz - $rz}]
                    set d2 [expr {$dx*$dx + $dy*$dy + $dz*$dz}]
                    if {$d2 < $mind2} { set mind2 $d2 }
                }
                set mind [expr {sqrt($mind2)}]
                if {$mind > 1.61} {
                    _bail anchor_dist "hider $k nearest-real-dist=$mind > 1.61 (no real atom in the bond band)"
                } elseif {$mind >= 1.19} {
                    puts "BCHM_BONDED: hider $k nearest-real-dist=$mind (full-sep accept)"
                } else {
                    puts "BCHM_BONDED_RELAX: hider $k nearest-real-dist=$mind < 1.19 (MIN_SEP_REAL relaxed on a crowded anchor)"
                    if {$mind <= 1e-6} {
                        _bail anchor_degenerate "hider $k coincident with a real atom (dist=$mind)"
                    }
                }
            }
            # 5. SENTINEL round-trip: beta -999.0 numeric, segid GAME, 5 of each.
            foreach bval $hbetas {
                if {abs($bval + 999.0) > 1e-9} {
                    _bail sentinel_beta "got=$bval want=-999.0"
                }
            }
            if {$hsegids ne "GAME GAME GAME GAME GAME"} {
                _bail sentinel_segid "got=$hsegids"
            }
            # 6. SEPARATION: min pairwise hider-hider distance. Expected
            # >= 3.9 (sep 4.0; strict-< boundary passes at 4.0 and %8.3f
            # rounding can dip by <= 0.001 -- 3.9 leaves margin). A pair
            # below 3.9 means the relaxation fallback fired for it: LOG the
            # relaxation, then only assert >= 1.19 (still bond-band-adjacent).
            set minpair 1e30
            for {set a 0} {$a < 5} {incr a} {
                for {set b [expr {$a + 1}]} {$b < 5} {incr b} {
                    lassign [lindex $hcoords $a] ax ay az
                    lassign [lindex $hcoords $b] bx by bz
                    set dx [expr {$ax - $bx}]
                    set dy [expr {$ay - $by}]
                    set dz [expr {$az - $bz}]
                    set d [expr {sqrt($dx*$dx + $dy*$dy + $dz*$dz)}]
                    if {$d < $minpair} { set minpair $d }
                }
            }
            puts "BCHM_BONDED: min hider-hider dist=$minpair"
            if {$minpair < 3.9} {
                puts "BCHM_BONDED_RELAX: min hider-hider dist $minpair < 3.9 (relaxation fallback fired)"
                if {$minpair < 1.19} {
                    _bail hider_sep "min pair=$minpair < 1.19 even after relaxation"
                }
            }
        }
        $sel delete
    } else {
        _bail sentinel_sel $sel
    }
}

# ---- Report. VMD does NOT propagate tcl exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
