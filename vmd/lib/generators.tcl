# vmd/lib/generators.tcl
# PURE layer: stdlib-only tcl. No molecular-viewer API, no GUI toolkit.
# Unit-testable via tcltest (under headless VMD or a standalone tclsh).
# Port of v1 pymol/biochemeleon/generators.py::generate_sphere_positions
# (Python -> tcl 8.5).
#
# Purpose: HIDER-03 ("sphere/VDW hiders -- place anywhere in the bounding
# region") -- uniform-random points inside a bounding box. This is the
# geometry core Plan 16-07 body-swaps into mutation::make_placeholder_hiders.
#
# Input shape: minmax is the probe-verified `measure minmax` return --
#   {{xmin ymin zmin} {xmax ymax zmax}}   (2 elements, each a 3-float list)
# The sampler receives that list; it NEVER calls `measure` itself (fetching
# the box is the caller's viewer-bridge job).
#
# Seed rule: rand() is the GLOBAL PRNG (setup_state Pitfall 4). When the
# optional seed argument is non-empty, srand() seeds ONCE at the top of the
# proc -- never reseed per point. Production callers pass NO seed
# (continuous global stream, same convention as randomize_state).

namespace eval ::biochemeleon::generators {
    # Export the public symbols so callers may `namespace import` them.
    # Tests and the composition root use fully-qualified names; the export
    # list documents the public contract.
    namespace export sphere_positions sample unit_vector bonded_offset \
        reject_overlaps place_bonded_hider

    # Phase 17.1 bonded-placement geometry constants (17.1-RESEARCH,
    # probe-verified on VMD 1.9.3), one per line:
    variable D_MIN 1.2        ;# bond distance band low end (A)
    variable D_MAX 1.6        ;# bond distance band high end (A)
    variable MIN_SEP_REAL 1.4 ;# min sep from any REAL atom other than the anchor
    variable MIN_SEP_HIDER 4.0 ;# min hider-to-hider sep (no GAM-GAM cross-bonds)
    variable MAX_COORD 9999.0 ;# %8.3f overflow guard (|coord| ceiling)
    variable MAX_TRIES 25     ;# rejection-sampling draws per relaxation round
    variable RELAX_ROUNDS 2   ;# sep-halving rounds after retry exhaustion
}

# sphere_positions {minmax n {seed {}}} -> list of {x y z} triples,
# uniform-random inside the box (v1 formula ported 1:1: min + rand*span
# per axis). n <= 0 -> empty list. A degenerate box (min == max) yields n
# identical points (rand()*0 == 0 -- no error, no NaN).
proc ::biochemeleon::generators::sphere_positions {minmax n {seed {}}} {
    if {$seed ne ""} { expr {srand($seed)} }
    lassign $minmax lo hi
    lassign $lo xmin ymin zmin
    lassign $hi xmax ymax zmax
    set pts [list]
    for {set i 0} {$i < $n} {incr i} {
        lappend pts [list \
            [expr {$xmin + rand() * ($xmax - $xmin)}] \
            [expr {$ymin + rand() * ($ymax - $ymin)}] \
            [expr {$zmin + rand() * ($zmax - $zmin)}]]
    }
    return $pts
}

# ---- Phase 17.1: bonded single-atom hider placement ----
#
# Simple-rep hider chemistry (17.1-RESEARCH, probe-verified on VMD 1.9.3):
# on `mol new`, VMD's load-time distance search bonds two atoms iff
#   distance < 0.6 * (r_i + r_j)
# (radii C 1.70 / N 1.55 / O 1.52 / S 1.80 / P 1.55 / H 1.00 / unknown 1.50).
# A GAM hider atom placed 1.2-1.6 A from a real anchor therefore auto-bonds
# to it under EVERY heavy-anchor cutoff with >= 0.33 A margin -- the bonded
# pseudoatom analogue of HIDER-04. This layer is the PURE geometry for that
# placement; fetching anchors/neighborhoods is the caller's (mol-bridge,
# plan 17.1-05) job.
#
# The two sep constants mean different things and ride together in ONE
# occupied-entry shape ({x y z sep}, per-entry seps):
#   MIN_SEP_REAL  -- min separation from any REAL atom OTHER than the anchor
#                    (a coincident hider draws a zero-length bond / buried
#                    sphere).
#   MIN_SEP_HIDER -- min hider-to-hider separation (avoids unintended
#                    GAM-GAM cross-bonds; cross-bonding verified at <= 2.0 A).
#
# Relaxation contract: up to MAX_TRIES rejection draws at full seps, then
# ALL seps are halved and MAX_TRIES more draws are taken, RELAX_ROUNDS
# times. After the last relaxation the FINAL drawn candidate is accepted
# with each coordinate clamped to [-MAX_COORD, MAX_COORD] -- termination is
# guaranteed and a slightly-clashing hider is better than an infinite loop
# on a crowded 3GP6 neighborhood.
#
# Extra bonds are NORMAL and blend-positive: the distance search bonds the
# hider to EVERYTHING within its cutoff (a crowded hider may bond 3-5
# neighbors). Consumers must assert numbonds >= 1, NEVER == 1 -- that check
# belongs to the bridge/smoke layer, not here.
#
# Seed rule: same convention as sphere_positions -- when the optional seed
# argument is non-empty, srand() seeds ONCE at the top of the proc; internal
# procs are always called with NO seed so the global PRNG stream continues.
# Production callers pass NO seed.

# _dist2 {a b} -> squared distance between two {x y z} points (private
# helper; keeps sqrt out of the rejection hot path; d2 < sep2 is equivalent
# to d < sep for non-negative values).
proc ::biochemeleon::generators::_dist2 {a b} {
    lassign $a ax ay az
    lassign $b bx by bz
    set dx [expr {$ax - $bx}]
    set dy [expr {$ay - $by}]
    set dz [expr {$az - $bz}]
    return [expr {$dx*$dx + $dy*$dy + $dz*$dz}]
}

# sample {lst n {seed {}}} -> n DISTINCT elements of lst (partial Fisher-
# Yates shuffle; port of setup_state::_sample made public). n <= 0 -> empty
# list; n > llength -> all of lst (shuffled). Deterministic under a seed.
proc ::biochemeleon::generators::sample {lst n {seed {}}} {
    if {$seed ne ""} { expr {srand($seed)} }
    set copy $lst
    set len [llength $copy]
    if {$n > $len} { set n $len }
    if {$n <= 0} { return [list] }
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {$i + int(rand() * ($len - $i))}]
        set tmp [lindex $copy $i]
        lset copy $i [lindex $copy $j]
        lset copy $j $tmp
    }
    return [lrange $copy 0 [expr {$n - 1}]]
}

# unit_vector {{seed {}}} -> {ux uy uz} with norm ~= 1.0 (within 1e-9).
# Draws 3 uniforms in [-1, 1] and renormalizes; redraws when the draw lands
# within 1e-6 of the origin (bounded to 10 tries), then falls back to
# {0 0 1} so the proc ALWAYS returns a usable direction.
proc ::biochemeleon::generators::unit_vector {{seed {}}} {
    if {$seed ne ""} { expr {srand($seed)} }
    for {set attempt 0} {$attempt < 10} {incr attempt} {
        set x [expr {2.0 * rand() - 1.0}]
        set y [expr {2.0 * rand() - 1.0}]
        set z [expr {2.0 * rand() - 1.0}]
        set norm [expr {sqrt($x*$x + $y*$y + $z*$z)}]
        if {$norm >= 1e-6} {
            return [list \
                [expr {$x / $norm}] [expr {$y / $norm}] [expr {$z / $norm}]]
        }
    }
    return [list 0.0 0.0 1.0]
}

# bonded_offset {{seed {}}} -> {dx dy dz} = unit_vector * d with d drawn
# uniformly in [D_MIN, D_MAX]. The displacement's length is in the bond
# band, so anchor + offset always lands inside VMD's load-time bond cutoff
# (d < 0.6*(r_i+r_j)) for every heavy anchor.
proc ::biochemeleon::generators::bonded_offset {{seed {}}} {
    variable D_MIN
    variable D_MAX
    if {$seed ne ""} { expr {srand($seed)} }
    lassign [unit_vector] ux uy uz
    set d [expr {$D_MIN + rand() * ($D_MAX - $D_MIN)}]
    return [list [expr {$ux * $d}] [expr {$uy * $d}] [expr {$uz * $d}]]
}

# reject_overlaps {candidate occupied} -> 1/0. occupied is a list of
# {x y z sep} entries, each carrying its OWN minimum separation (one proc
# enforces both MIN_SEP_REAL vs real atoms and MIN_SEP_HIDER vs other
# hiders). Rejects (1) iff ANY entry is STRICTLY closer to the candidate
# than its sep; a candidate at exactly sep passes (strict-< matches the
# bond law's boundary). Empty occupied never rejects.
proc ::biochemeleon::generators::reject_overlaps {candidate occupied} {
    foreach entry $occupied {
        lassign $entry x y z sep
        if {[_dist2 $candidate [list $x $y $z]] < $sep * $sep} { return 1 }
    }
    return 0
}

# place_bonded_hider {anchor occupied {seed {}}} -> {x y z} for a single-
# atom hider bonded to anchor. Rejection-samples anchor + bonded_offset
# until the candidate clears every occupied entry's sep AND stays within
# |MAX_COORD| (the %8.3f overflow guard: a coordinate >= 10000 shifts the
# whole PDB line right and silently corrupts the element field). On retry
# exhaustion the relaxation contract above kicks in; the proc ALWAYS
# terminates and ALWAYS returns a coordinate inside the %8.3f field.
proc ::biochemeleon::generators::place_bonded_hider {anchor occupied {seed {}}} {
    variable MAX_COORD
    variable MAX_TRIES
    variable RELAX_ROUNDS
    if {$seed ne ""} { expr {srand($seed)} }
    lassign $anchor ax ay az
    # private copy of the occupied list -- the caller's list is never mutated
    set seps [list]
    foreach entry $occupied {
        lassign $entry x y z sep
        lappend seps [list $x $y $z $sep]
    }
    set cand [list $ax $ay $az]
    set halvings 0
    while {1} {
        set accepted 0
        for {set t 0} {$t < $MAX_TRIES} {incr t} {
            lassign [bonded_offset] dx dy dz
            set cx [expr {$ax + $dx}]
            set cy [expr {$ay + $dy}]
            set cz [expr {$az + $dz}]
            set cand [list $cx $cy $cz]
            if {[reject_overlaps $cand $seps]} { continue }
            if {abs($cx) > $MAX_COORD || abs($cy) > $MAX_COORD \
                    || abs($cz) > $MAX_COORD} { continue }
            set accepted 1
            break
        }
        if {$accepted} { return $cand }
        if {$halvings >= $RELAX_ROUNDS} {
            # termination guarantee: accept the FINAL drawn candidate,
            # clamped into the %8.3f-safe range
            lassign $cand cx cy cz
            if {$cx > $MAX_COORD} { set cx $MAX_COORD }
            if {$cx < -$MAX_COORD} { set cx -$MAX_COORD }
            if {$cy > $MAX_COORD} { set cy $MAX_COORD }
            if {$cy < -$MAX_COORD} { set cy -$MAX_COORD }
            if {$cz > $MAX_COORD} { set cz $MAX_COORD }
            if {$cz < -$MAX_COORD} { set cz -$MAX_COORD }
            return [list $cx $cy $cz]
        }
        set relaxed [list]
        foreach entry $seps {
            lassign $entry x y z sep
            lappend relaxed [list $x $y $z [expr {$sep / 2.0}]]
        }
        set seps $relaxed
        incr halvings
    }
}
