# vmd/lib/demos.tcl
# MOL BRIDGE: sources the pure layer (setup_state.tcl) for constants, then wraps
# the VMD mol/molinfo command surface. Mirrors pymol/biochemeleon/demos.py.
# The GUI (Plan 03/04) sources BOTH setup_state.tcl AND this file.
# Tcl 8.5: catch for errors, foreach+lappend for list builds, brace all expr.
# Pure-layer access uses fully-qualified `variable ::biochemeleon::setup_state::*`
# (verified -- research uses this form).

# Source the pure layer for constants (setup_state.tcl is in the same lib/ dir).
# demos.tcl is always `source`d (never `-e`d directly), so [info script] is set
# correctly here (verified -- Pattern 1; Phase 13 Pitfall 3 only affects `-e`).
source [file join [file dirname [info script]] setup_state.tcl]

namespace eval ::biochemeleon::demos {
    # GAME_REPS / DEMO_MANIFEST / SETUP_FORMAT / DEFAULTS live in
    # ::biochemeleon::setup_state (the pure layer). Procs access them via the
    # fully-qualified `variable ::biochemeleon::setup_state::*` form.
    #
    # script_dir: this file's directory, captured at SOURCE TIME. [info script]
    # is DYNAMIC -- it returns the CALL-TIME sourcing context, NOT the
    # definition-time file, so proc bodies (e.g. load_demo) CANNOT call
    # [info script] directly (it returns "" once source completes, especially
    # under `vmd -e`). Capturing it here (namespace eval runs during source,
    # so [info script] = this file's path) freezes the value for proc-body use.
    # Standard tcl "where am I defined" pattern (cf. the entry's top-level _dir).
    variable script_dir [file dirname [info script]]
    namespace export \
        to_vmd_path list_loaded_molecules load_demo get_active_reps \
        fetch_pdb save_setup load_setup atom_count
}

# WSL -> VMD path guard: /mnt/c/... -> C:/... (FORWARD slashes, NOT backslashes
# -- vmd/AGENTS.md). No-op for other paths. Bundled-demo paths are script-relative
# (always C:/ inside VMD) so this is a defensive guard for any externally-supplied
# /mnt/c paths (e.g. a user-supplied PDB).
proc ::biochemeleon::demos::to_vmd_path {path} {
    if {[regexp {^/mnt/([a-zA-Z])/(.*)$} $path -> drive rest]} {
        return "[string toupper $drive]:/$rest"
    }
    return $path
}

# SETUP-01: enumerate loaded molecules for the dropdown. Returns a list of
# display strings "<name> (<molid>)" for every loaded molecule. The name is the
# FILENAME basename (read-only -- Pitfall 1; you cannot rename a molecule).
proc ::biochemeleon::demos::list_loaded_molecules {} {
    set out [list]
    foreach m [molinfo list] {
        lappend out "[molinfo $m get name] ($m)"
    }
    return $out
}

# SETUP-01 / DEMO-01: load a bundled demo PDB by manifest id. Returns the new
# molid. Errors (via -code error) on unknown id / non-bundled source / missing
# file / mol-new failure; the GUI catches and shows a dialog. Paths are
# script-relative (C:/) so no /mnt/c conversion is needed.
proc ::biochemeleon::demos::load_demo {demo_id} {
    variable ::biochemeleon::setup_state::DEMO_MANIFEST
    variable script_dir  ;# frozen at source time (proc body can't use [info script])
    if {![dict exists $DEMO_MANIFEST $demo_id]} {
        return -code error "unknown demo: $demo_id"
    }
    set meta [dict get $DEMO_MANIFEST $demo_id]
    # Phase 14 manifest has ONLY bundled demos. If a later phase adds fetched
    # demos, branch on [dict get $meta source] here (v1 demos.py:183). For now:
    # reject any non-bundled source entry.
    if {[dict get $meta source] ne "bundled"} {
        return -code error "non-bundled demo not supported in Phase 14: $demo_id"
    }
    set cache_name [dict get $meta cache_name]
    # demos.tcl is at <root>/vmd/lib/demos.tcl; data at <root>/vmd/data/demos/.
    # Use the source-time-frozen script_dir (NOT [info script], which is empty
    # at call time under `vmd -e`).
    set path [file normalize [file join $script_dir .. data demos $cache_name]]
    set path [::biochemeleon::demos::to_vmd_path $path]  ;# defensive (no-op for C:/)
    if {![file exists $path]} { return -code error "demo file not found: $path" }
    if {[catch {mol new $path type pdb} molid]} {
        return -code error "mol new failed: $molid"
    }
    return $molid
}

# SETUP-03: detect the active reps on a molecule (lock-scene). Returns the subset
# of GAME_REPS whose style matches a currently-displayed rep, in rep-index order.
# Uses the verified COMBINED-BRACES molinfo form (single-field molinfo get {rep $i}
# FAILS -- Pitfall 3). Skips reps whose style is not in GAME_REPS (Surface/etc).
# Wraps numreps in catch so a bad molid returns an empty list.
proc ::biochemeleon::demos::get_active_reps {mol} {
    variable ::biochemeleon::setup_state::GAME_REPS
    set active [list]
    if {[catch {molinfo $mol get numreps} n]} { return $active }  ;# bad molid -> empty
    for {set i 0} {$i < $n} {incr i} {
        foreach {style sel col mat} [molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        if {[lsearch -exact $GAME_REPS $style] >= 0} {
            lappend active $style
        }
    }
    return $active
}

# SETUP-01 fetch: STUB for Phase 14. VMD 1.9.3 has http (v2.7.2) but NO tls ->
# HTTPS (RCSB) is impossible (Pitfall 6). The robust fetch (network + tls) is
# Phase 21 (large demos). The GUI shows the option but catches the error and
# points to bundled demos. Signature mirrors v1 demos.fetch_pdb (code -> obj).
proc ::biochemeleon::demos::fetch_pdb {code} {
    return -code error "fetch_pdb not implemented in Phase 14 (VMD 1.9.3 lacks tls for HTTPS); use a bundled demo"
}

# BTN-03: Save setup parameters to a key-value line file (LOCKED DECISION #1 --
# NOT [list]+source). Writes the `format` tag first, then iterates the state
# dict: scalar keys as `$key $value`, per_rep as `per_rep_count N` +
# `per_rep_entry $rep $cnt` lines, pdb_pool as `pdb_pool_count N` +
# `pdb_pool_entry $code` lines. stdlib only (open/puts/close). The format line
# lets a future loader reject mismatched versions.
proc ::biochemeleon::demos::save_setup {state filepath} {
    variable ::biochemeleon::setup_state::SETUP_FORMAT
    set fh [open $filepath w]
    puts $fh "format $SETUP_FORMAT"
    dict for {k v} $state {
        if {$k eq "format"} continue  ;# already written above
        if {$k eq "per_rep"} {
            puts $fh "per_rep_count [dict size $v]"
            dict for {rep cnt} $v { puts $fh "per_rep_entry $rep $cnt" }
        } elseif {$k eq "pdb_pool"} {
            puts $fh "pdb_pool_count [llength $v]"
            foreach code $v { puts $fh "pdb_pool_entry $code" }
        } else {
            puts $fh "$k $v"
        }
    }
    close $fh
}

# BTN-04: Load setup parameters from a key-value line file. Returns the loaded
# + validated state dict. Errors (via -code error) on missing file. Parses each
# line as `key value...` with `gets`. CRITICAL: rebuilds the loaded dict in
# DEFAULTS key order (Pitfall 5 -- tcl dict eq is ORDER-SENSITIVE; without this
# rebuild, round-trip eq=0 even with identical content). Then calls
# validate_state (Plan 01) to canonicalize/clamp hand-edited values (defense in
# depth). stdlib only (open/gets/close).
proc ::biochemeleon::demos::load_setup {filepath} {
    variable ::biochemeleon::setup_state::DEFAULTS
    if {![file exists $filepath]} { return -code error "setup file not found: $filepath" }
    set fh [open $filepath r]
    set tmp [dict create]
    set per_rep [dict create]
    set pdb_pool [list]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq ""} continue
        # key = first whitespace-delimited token; val = REST of line (preserves
        # spaces in multi-token scalar values, e.g. selected_object "1k8p.pdb (0)").
        if {![regexp {^(\S+)\s+(.*)$} $line -> key val]} {
            set key $line
            set val ""
        }
        switch -- $key {
            "format"         { dict set tmp format $val }
            "per_rep_count"  { }
            "per_rep_entry"  {
                # val = "<rep> <count>" -- two whitespace-delimited tokens.
                set rv [split $val " "]
                dict set per_rep [lindex $rv 0] [lindex $rv 1]
            }
            "pdb_pool_count" { }
            "pdb_pool_entry" { lappend pdb_pool $val }
            default          { dict set tmp $key $val }
        }
    }
    close $fh
    dict set tmp per_rep $per_rep
    dict set tmp pdb_pool $pdb_pool
    # REBUILD in DEFAULTS key order for order-stable dict eq round-trip (Pitfall 5).
    set loaded [dict create]
    foreach k {format target_mode selected_object pdb_code demo_id hider_count lock_scene per_rep difficulty_easy lock_source pdb_pool} {
        if {[dict exists $tmp $k]} { dict set loaded $k [dict get $tmp $k] }
    }
    # Validate through the pure layer (canonicalizes + clamps) before returning.
    return [::biochemeleon::setup_state::validate_state $loaded]
}

# atom_count: returns molinfo $molid get numatoms, or 0 on error (bad molid /
# no molecule loaded). Wrapped in catch. The GUI (Plan 04) resolves the current
# molid from the target mode and calls this for the hider_count_cap computation.
proc ::biochemeleon::demos::atom_count {molid} {
    if {[catch {molinfo $molid get numatoms} n]} { return 0 }
    return $n
}
