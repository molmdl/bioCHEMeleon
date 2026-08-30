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
    # Export the public symbol so callers may `namespace import` it.
    # Tests and the composition root use fully-qualified names; the export
    # list documents the public contract.
    namespace export sphere_positions
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
