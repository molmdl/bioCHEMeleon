# vmd/lib/splice.tcl
# PURE residue-splice geometry module (Phase 17.2 -- plan 17.2-01).
# Stdlib tcl 8.5 ONLY: no viewer-API calls of any kind (no scene commands,
# no selection commands, no GUI toolkit) -- every proc is pure math/string
# work, unit-testable via tcltest under the headless-VMD runner
# (vmd/tests/test_splice.test).
#
# Sources generators.tcl (same lib/ directory) for the seeded sampler:
# generators::sample drives the anchor shuffle. Pure re-init on re-source
# is harmless (the mutation.tcl pattern). Locating the sibling needs a
# fallback: under `vmd -e` [info script] is EMPTY even inside sourced
# files (verified), and VMD's own source silently skips missing files --
# so the directory is resolved explicitly and a missing sampler is a loud
# error, never a silent skip.
#
# ------------------------------------------------------------------------
# THE SS DECISION (phase Option A, recorded durably per 17.2-RESEARCH):
#   * VMD has NO ss='L' (PyMOL vocabulary). Per-atom ss = the `structure`
#     keyword, values T/C/H/G/E/B.
#   * A spliced GAM residue gets `T` (turn) from the LOAD-TIME STRIDE run
#     and renders as a smooth coil/turn tube -- the loop-tube look accepted
#     in v1 (2026-08-16). Accepted for 17.2 = **Option A**.
#   * ssrecalc is UNNECESSARY (load-time STRIDE already assigns ss) and
#     DESTRUCTIVE (wipes manual `set structure` writes) -- NEVER call it
#     in the generation flow (Pitfall C2).
#   * Manual `set structure` override exists (renderer-honored) but a
#     single-residue hider renders as a tube regardless (>= 3-residue
#     helix rule) -- the force-SS variant is OUT OF SCOPE / future polish.
#   * Trace/Tube are sibling consumers of the same splice, NOT a sidestep.
# ------------------------------------------------------------------------
#
# THE SPLICE CONTRACT: ONE fake GAM residue (N/CA/C/O/CB; CB omitted when
# the anchor lacks it) copied from a real anchor residue and rigid-
# translated 1.0 A perpendicular to the local peptide bond. Anchor's chain,
# disjoint resid block 9001+k, beta -999.0 on CA ONLY (0.00 elsewhere),
# segid GAME, element emitted per atom, NO CONECT / TER insertion /
# renumbering -- the load-time distance search bonds both junctions at
# <= 1.0 A.
#
# Governing math (probe-verified, 17.2-RESEARCH sections 4.1/10.1):
#   * Displacement envelope: the peptide junction (real 1.33 A, C-N bond
#     cutoff 1.95 A) survives a rigid perpendicular displacement d while
#     sqrt(1.33^2 + d^2) < 1.95, i.e. d < 1.43 A. SPLICE_DISPLACEMENT 1.0 A
#     is the probe-proven in-path sweet spot (1.44 A breaks the junction).
#   * Direction rule: the perpendicular is to the PEPTIDE-BOND vector
#     unit(N_next - C_anchor), NOT to the CA-CA axis (probe4 DIRPP failed
#     at 1.0 A perpendicular-to-axis while the bond-perpendicular variant
#     succeeded).

# Seeded sampler reuse: source the sibling generators module (same lib/
# directory). Primary location = [info script]'s dir (normal source
# chains); harness fallback = [pwd]/vmd/lib (the headless-VMD runner's
# cwd = staging root, the test_registry.test layout).
set ::_splice_dir [file dirname [info script]]
if {![file exists [file join $::_splice_dir generators.tcl]]} {
    set ::_splice_dir [file join [pwd] vmd lib]
}
if {![file exists [file join $::_splice_dir generators.tcl]]} {
    error "splice.tcl: cannot locate sibling generators.tcl (tried [file dirname [info script]] and [file join [pwd] vmd lib])"
}
source [file join $::_splice_dir generators.tcl]
unset ::_splice_dir

namespace eval ::biochemeleon::splice {
    # Public contract (consumed by the 17.2-04 viewer bridge).
    namespace export perp_vector displacement resid_block select_anchors \
        assemble_record atom_record

    # Phase 17.2 splice constants (probe-verified, 17.2-RESEARCH):
    variable SPLICE_DISPLACEMENT 1.0  ;# A perpendicular to the peptide bond (hard envelope 1.43)
    variable RESID_BASE 9001          ;# disjoint fake-resid block start (real demo resids <= ~500)
    variable MIN_ANCHOR_SEP 5.0       ;# A pairwise CA separation (5.0 - 2x1.0 = 3.0 > 1.95 worst-case cutoff)
    variable SPLICE_RESNAME "GAM"     ;# fake residue name (3 cols)
    variable SPLICE_SEGID "GAME"      ;# fake segment id (4 cols)
}

# ---- private 3-vector helpers (all expr braced; tcl 8.5) ----

# _cross {a b} -> cross product a x b.
proc ::biochemeleon::splice::_cross {a b} {
    lassign $a ax ay az
    lassign $b bx by bz
    return [list \
        [expr {$ay * $bz - $az * $by}] \
        [expr {$az * $bx - $ax * $bz}] \
        [expr {$ax * $by - $ay * $bx}]]
}

# _dot {a b} -> dot product.
proc ::biochemeleon::splice::_dot {a b} {
    lassign $a ax ay az
    lassign $b bx by bz
    return [expr {$ax * $bx + $ay * $by + $az * $bz}]
}

# _norm {a} -> Euclidean length.
proc ::biochemeleon::splice::_norm {a} {
    lassign $a x y z
    return [expr {sqrt($x * $x + $y * $y + $z * $z)}]
}

# _unit {a} -> a / |a| (caller guarantees |a| >= 1e-6).
proc ::biochemeleon::splice::_unit {a} {
    set n [_norm $a]
    lassign $a x y z
    return [list [expr {$x / $n}] [expr {$y / $n}] [expr {$z / $n}]]
}

# perp_vector {u {ref1 {0.0 0.0 1.0}} {ref2 {1.0 0.0 0.0}} {ref3 {}}}
#   -> {ux uy uz} UNIT vector perpendicular to u (|dot| < 1e-9),
#   deterministic (no randomness, no sign flip). Ladder: cross(u, ref1);
#   if degenerate-parallel, cross(u, ref2); then ref3 if the caller
#   supplied one; else a hard error. A zero-length u is a hard error.
proc ::biochemeleon::splice::perp_vector {u {ref1 {0.0 0.0 1.0}} {ref2 {1.0 0.0 0.0}} {ref3 {}}} {
    if {[_norm $u] < 1e-6} {
        error "splice::perp_vector: degenerate peptide-bond vector (zero length)"
    }
    foreach ref [list $ref1 $ref2] {
        if {$ref eq ""} { continue }
        set v [_cross $u $ref]
        if {[_norm $v] >= 1e-6} {
            return [_unit $v]
        }
    }
    if {$ref3 ne ""} {
        set v [_cross $u $ref3]
        if {[_norm $v] >= 1e-6} {
            return [_unit $v]
        }
    }
    error "splice::perp_vector: no non-parallel reference for the ladder"
}

# displacement {c_pt n_pt {ca_fallback {}}} -> {dx dy dz} =
# SPLICE_DISPLACEMENT x perp_vector of the peptide-bond direction
# unit(n_pt - c_pt). If the bond vector is degenerate (|n_pt - c_pt|
# < 1e-6) AND ca_fallback is a non-empty usable 3-vector, the unit CA-axis
# vector stands in as the bond direction (the research's flagged
# degenerate-parallel fallback); otherwise perp_vector's error propagates.
proc ::biochemeleon::splice::displacement {c_pt n_pt {ca_fallback {}}} {
    variable SPLICE_DISPLACEMENT
    lassign $c_pt cx cy cz
    lassign $n_pt nx ny nz
    set bond [list \
        [expr {$nx - $cx}] [expr {$ny - $cy}] [expr {$nz - $cz}]]
    if {[_norm $bond] < 1e-6 && $ca_fallback ne "" \
            && [_norm $ca_fallback] >= 1e-6} {
        set bond [_unit $ca_fallback]
    }
    lassign [perp_vector $bond] px py pz
    return [list \
        [expr {$px * $SPLICE_DISPLACEMENT}] \
        [expr {$py * $SPLICE_DISPLACEMENT}] \
        [expr {$pz * $SPLICE_DISPLACEMENT}]]
}

# resid_block {n {start {}} {real_max 0}} -> resids start..start+n-1
# (start defaults RESID_BASE). Errors when the block start is <= the
# supplied real-resid max (the disjointness guard); n <= 0 -> empty.
proc ::biochemeleon::splice::resid_block {n {start {}} {real_max 0}} {
    variable RESID_BASE
    if {$start eq ""} { set start $RESID_BASE }
    if {$start <= $real_max} {
        error "splice::resid_block: resid block not disjoint from real resids (block start $start, real max $real_max)"
    }
    if {$n <= 0} { return [list] }
    set out [list]
    for {set k 0} {$k < $n} {incr k} {
        lappend out [expr {$start + $k}]
    }
    return $out
}

# select_anchors {candidates n {seed {}}} -> accepted FULL descriptors in
# acceptance order. candidates = list of {key ok ca_x ca_y ca_z}
# descriptors (ok precomputed by the bridge: mid-chain + occupied-clear +
# valid chain). Only ok-true candidates are eligible; n is capped at the
# eligible supply (under-generation tolerance -- caller uses the actual
# count); the eligible pool is shuffled via generators::sample (seed
# convention: non-empty seed seeds the global PRNG once, empty seed keeps
# the stream); greedy acceptance in shuffled order takes a candidate iff
# its CA is >= MIN_ANCHOR_SEP from every ALREADY-ACCEPTED candidate
# (squared comparison, eps 1e-9). May return fewer than n.
proc ::biochemeleon::splice::select_anchors {candidates n {seed {}}} {
    variable MIN_ANCHOR_SEP
    set eligible [list]
    foreach cand $candidates {
        if {[lindex $cand 1]} { lappend eligible $cand }
    }
    set count [llength $eligible]
    if {$n > $count} { set n $count }
    if {$n <= 0} { return [list] }
    set shuffled [::biochemeleon::generators::sample $eligible $n $seed]
    set sep2 [expr {$MIN_ANCHOR_SEP * $MIN_ANCHOR_SEP}]
    set accepted [list]
    foreach cand $shuffled {
        lassign $cand key ok cx cy cz
        set fits 1
        foreach acc $accepted {
            lassign $acc akey aok ax ay az
            set d2 [expr {($cx - $ax) * ($cx - $ax) + ($cy - $ay) * ($cy - $ay) \
                + ($cz - $az) * ($cz - $az)}]
            if {[expr {$d2 + 1e-9}] < $sep2} { set fits 0; break }
        }
        if {$fits} { lappend accepted $cand }
    }
    return $accepted
}

# assemble_record {atoms_data chain resid displacement {max_coord 9999.0}}
#   -> {chain resid atoms_displaced}. atoms_data = list of
#   {name element x y z} in N/CA/C/O/CB order (the anchor's present
#   subset). Validates the backbone shape, rigid-translates EVERY atom by
#   the displacement (geometry preserved), and errors when any translated
#   |coord| exceeds max_coord (the %8.3f overflow guard: a coordinate
#   >= 10000 shifts the whole PDB line right and silently corrupts the
#   element field).
proc ::biochemeleon::splice::assemble_record {atoms_data chain resid displacement {max_coord 9999.0}} {
    set n0 [lindex [lindex $atoms_data 0] 0]
    set n1 [lindex [lindex $atoms_data 1] 0]
    if {$n0 ne "N" || $n1 ne "CA"} {
        error "splice::assemble_record: atom order must be N-first, CA-second (got $n0,$n1)"
    }
    set has_o 0
    foreach a $atoms_data {
        if {[lindex $a 0] eq "O"} { set has_o 1; break }
    }
    if {!$has_o} {
        error "splice::assemble_record: fake residue needs an O atom"
    }
    set k [llength $atoms_data]
    if {$k < 4} {
        error "splice::assemble_record: fake residue needs N/CA/C/O (got $k atoms)"
    }
    lassign $displacement dx dy dz
    set out [list]
    foreach a $atoms_data {
        lassign $a name element x y z
        if {![string is double -strict $x] \
                || ![string is double -strict $y] \
                || ![string is double -strict $z]} {
            error "splice::assemble_record: non-numeric coordinate for atom $name ($x $y $z)"
        }
        set tx [expr {$x + $dx}]
        set ty [expr {$y + $dy}]
        set tz [expr {$z + $dz}]
        if {abs($tx) > $max_coord || abs($ty) > $max_coord \
                || abs($tz) > $max_coord} {
            error "splice::assemble_record: coordinate overflow |$tx| > $max_coord after displacement (%8.3f corrupts)"
        }
        lappend out [list $name $element $tx $ty $tz]
    }
    return [list $chain $resid $out]
}

# atom_record {serial name element chain resid x y z} -> the 78-char ATOM
# line (probe-verified layout, research section 10.1). Columns: name 13-16,
# altloc 17 (space), resname GAM 18-20, chain 22 (the ANCHOR's chain, not
# "G"), resid 23-26, x/y/z 31-54, occupancy 1.00 55-60, beta 61-66, segid
# GAME 73-76, element 77-78 (ALWAYS emitted -- the load-bearing blend
# field).
#
# Beta policy (baked in): the CA carries the -999.0 sentinel; every other
# atom carries 0.00. The 6-char beta field is pre-rendered -- CA via
# %6.1f -> "-999.0" (the probe-pinned rule: %6.2f would render "-999.00",
# OVERFLOW the 6-col field and corrupt segid, Pitfall 1) -- and slotted
# with %6s, because one fixed spec cannot render both "-999.0" and the
# PDB-standard "  0.00" pinned by test atom_record_ca_beta. CA output is
# byte-identical to mutation.tcl::_hider_record's.
proc ::biochemeleon::splice::atom_record {serial name element chain resid x y z} {
    variable SPLICE_RESNAME
    variable SPLICE_SEGID
    if {$name eq "CA"} {
        set beta_field [format "%6.1f" -999.0]
    } else {
        set beta_field [format "%6.2f" 0.00]
    }
    # Format string: VERBATIM sibling copy of mutation.tcl::_hider_record's
    # (probe-pinned 78-col layout), with the beta slot %6.1f -> %6s to
    # receive the pre-rendered 6-char field above.
    return [format "ATOM  %5d %4s%1s%-3s %1s%4d%1s   %8.3f%8.3f%8.3f%6.2f%6s      %-4s%2s" \
        $serial $name " " $SPLICE_RESNAME $chain $resid " " \
        $x $y $z 1.00 $beta_field $SPLICE_SEGID $element]
}
