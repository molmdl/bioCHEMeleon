# vmd/lib/mutation.tcl -- MOL BRIDGE: PDB-rebuild + sentinel (forward mutate-reload).
# Owns the FORWARD reload ONLY (write combined PDB -> mol delete original ->
# mol new combined -> tag sentinels). The restore-reload is backup.tcl::restore.
# Tcl 8.5 only (no 8.6 control constructs; brace all expr; catch; foreach+lappend;
# $sel delete after every atomselect).
#
# Sources setup_state.tcl (same lib/ dir) -- mirrors the demos.tcl pattern; its
# `namespace eval` re-inits CONSTANTS to identical values (harmless re-init).
# Also sources generators.tcl (PURE, same lib/ dir) -- Phase 16 real sphere
# placement feeds make_placeholder_hiders; pure re-init is harmless (the entry
# sources generators too). Does NOT source registry.tcl -- the entry sources
# registry exactly ONCE; re-sourcing would WIPE _records. The DI fn
# (fetch_hider_indices) is injected INTO registry::reconstruct_from_sentinels
# by the composition root (game.tcl / the smoke), never called by mutation.tcl
# itself.
source [file join [file dirname [info script]] setup_state.tcl]
source [file join [file dirname [info script]] generators.tcl]

namespace eval ::biochemeleon::mutation {
    # Sentinel constants (mol-domain; registry.tcl stays pure with only
    # HIDER_STATUS_HIDDEN). The canonical selector is `resname GAM and beta < 0`
    # -- NEVER `beta < 0` alone (over-matches any negative-beta real atom).
    variable HID_RESNAME  "GAM"     ;# 3 chars -- fits PDB resname cols 18-20 (4-char GAME silently dropped)
    variable HID_BETA    -999       ;# value; SELECTOR is "beta < 0" (never exact `beta -999`)
    variable HID_SEGID   "GAME"     ;# 4 chars -- fits PDB segid cols 73-76
    variable HID_CHAIN   "G"        ;# hider chain (disjoint from real chains)
    variable HID_RESSEQ  9001       ;# hider residue number (disjoint from real resids)
    variable HID_ELEMENT "C"        ;# placeholder element (Phase 16 sets real blend element)
    variable HID_OCC     1.00

    # Frozen at source time. [info script] is DYNAMIC/empty under `vmd -e` once
    # source completes, so proc bodies cannot call it (Phase 14 Pitfall; mirrors
    # demos.tcl:26). Capturing here (namespace eval runs during source) freezes
    # the value for proc-body use.
    variable script_dir [file dirname [info script]]

    namespace export make_placeholder_hiders write_combined_pdb tag_sentinels \
                     fetch_hider_indices mutate
}

# make_placeholder_hiders {molid count} -> list of {name x y z} records.
# Phase 16 REAL sphere placement (HIDER-03): uniform-random points inside the
# molecule's bounding box. Bbox via `measure minmax` on "all" (returns
# {{xmin ymin zmin} {xmax ymax zmax}} -- 2 elements, each a 3-float list;
# probe-verified) fed to the PURE sampler in vmd/lib/generators.tcl (v1
# formula ported 1:1: min + rand*span per axis; NO min-distance, NO overlap
# avoidance, NO clamping/inset -- overlapping a real atom is harmless). NO
# seed passed: the call continues the global PRNG stream (same convention as
# randomize_state; reseeding per call would correlate placements with prior
# rand() consumers). Names G01..GNN (2-digit zero-padded). Signature + record
# shape FROZEN (Phase 15 contract, 15-05): only the coordinate math changed.
# No molinfo call remains, so no catch-wrapping: `measure minmax` on a bad
# molid raises naturally and game.tcl propagates (caller aborts -- 15-05).
proc ::biochemeleon::mutation::make_placeholder_hiders {molid count} {
    set all [atomselect $molid "all"]
    set mm [measure minmax $all]
    $all delete
    set pts [::biochemeleon::generators::sphere_positions $mm $count]
    set recs [list]
    set i 0
    foreach p $pts {
        incr i
        lassign $p x y z
        lappend recs [list [format "G%02d" $i] $x $y $z]
    }
    return $recs
}

# _hider_record {serial name x y z} -> 78-char ATOM string.
# CRITICAL: beta is %6.1f -> "-999.0" (6 cols, NO overflow). %6.2f -> "-999.00"
# OVERFLOWS the 6-col beta field and corrupts segid (Pitfall 1, probe2b.log).
# Use EXACTLY this format string (probe-verified, probe2b.log:53 -> len=78,
# segid GAME survives in the PDB columns).
proc ::biochemeleon::mutation::_hider_record {serial name x y z} {
    variable HID_RESNAME
    variable HID_CHAIN
    variable HID_RESSEQ
    variable HID_OCC
    variable HID_BETA
    variable HID_SEGID
    variable HID_ELEMENT
    return [format "ATOM  %5d %4s%1s%-3s %1s%4d%1s   %8.3f%8.3f%8.3f%6.2f%6.1f      %-4s%2s" \
        $serial $name " " $HID_RESNAME $HID_CHAIN $HID_RESSEQ " " \
        $x $y $z $HID_OCC $HID_BETA $HID_SEGID $HID_ELEMENT]
}

# write_combined_pdb {molid hider_records out_path} -> orig atom count.
# writepdb-then-splice (A1): writepdb preserves beta/segid/occ (NOT user --
# Pitfall 7; irrelevant here) and emits 0 TER + 1 END for 1k8p (no TER handling).
# Step (a) atomselect "all" writepdb; (b) read, drop END/blank lines;
# (c) append one hider ATOM per record via _hider_record (serial = orig_n+1+i);
# (d) write END; close. out_path MUST be Windows-visible (caller converts via
# demos::to_vmd_path; mutate computes $env(TEMP) internally).
proc ::biochemeleon::mutation::write_combined_pdb {molid hider_records out_path} {
    set all [atomselect $molid "all"]
    $all writepdb $out_path
    set orig_n [$all num]
    $all delete
    set fh [open $out_path r]
    set lines [split [read $fh] \n]
    close $fh
    set fh [open $out_path w]
    foreach l $lines {
        if {[string trim $l] eq "END" || $l eq ""} continue
        puts $fh $l
    }
    set serial [expr {$orig_n + 1}]
    foreach r $hider_records {
        foreach {nm x y z} $r { break }
        puts $fh [_hider_record $serial $nm $x $y $z]
        incr serial
    }
    puts $fh "END"
    close $fh
    return $orig_n
}

# tag_sentinels {molid} -> hider index list.
# Selects `resname $HID_RESNAME` (reliably parsed from PDB cols 18-20; A2/A5),
# then sets beta/segid IN-PLACE (rescues any PDB column misalignment -- Pitfall 2,
# proven P5/P6). Per-atom `user` = ordinal (in-session hider id; LOST on writepdb
# -- Pitfall 7 -- but set anyway for the round; the .bcm reconciles later).
# Returns the hider `index` list. ALWAYS `$sel delete` (Pitfall 3 -- atomselect
# leaks; a dangling selection on a deleted molecule returns STALE data silently).
proc ::biochemeleon::mutation::tag_sentinels {molid} {
    variable HID_RESNAME
    variable HID_BETA
    variable HID_SEGID
    set sel [atomselect $molid "resname $HID_RESNAME"]
    $sel set beta  $HID_BETA
    $sel set segid $HID_SEGID
    set idxs [$sel get index]
    # Per-atom user = ordinal (0,1,2,...) -- one list-set, same atom order.
    set ords [list]
    set u 0
    foreach i $idxs { lappend ords $u; incr u }
    $sel set user $ords
    $sel delete
    return $idxs
}

# fetch_hider_indices {molid} -> index list. THE DI FN.
# Canonical selector `resname $HID_RESNAME and beta < 0` (NEVER `beta < 0` alone
# -- over-matches negative-beta real atoms, probe.log:699). game.tcl injects
# `list ::biochemeleon::mutation::fetch_hider_indices $new_molid` as the
# fetch_hider_ids command prefix into registry::reconstruct_from_sentinels
# (matches the existing registry.tcl:34 `foreach idx [{*}$fetch_hider_ids]` shape).
proc ::biochemeleon::mutation::fetch_hider_indices {molid} {
    variable HID_RESNAME
    set sel [atomselect $molid "resname $HID_RESNAME and beta < 0"]
    set idxs [$sel get index]
    $sel delete
    return $idxs
}

# mutate {molid hider_records} -> new game molid.
# Owns the FORWARD reload: write combined PDB -> mol delete ORIGINAL -> mol new
# combined (NEW molid, monotonic > old -- Pitfall 4) -> tag sentinels -> return.
# Temp path: $env(TEMP) is already a C:/ Windows path (no to_vmd_path needed);
# fall back to [pwd] (VMD cwd is C:/ under -dispdev text). Fixed name is fine for
# Phase 15 (single game; writepdb overwrites on restart -- no `rm` needed).
# Does NOT save/restore reps/viewpoint (backup.tcl's job -- game.tcl calls
# backup::snapshot BEFORE mutate and backup::restore AFTER). NO `cleanup` proc in
# mutation.tcl (the restore-reload is backup::restore).
proc ::biochemeleon::mutation::mutate {molid hider_records} {
    if {[info exists ::env(TEMP)] && $::env(TEMP) ne ""} {
        set out [file join $::env(TEMP) biochemeleon_game.pdb]
    } else {
        set out [file join [pwd] biochemeleon_game.pdb]
    }
    write_combined_pdb $molid $hider_records $out
    mol delete $molid
    set new_m [mol new $out type pdb waitfor all]
    tag_sentinels $new_m
    return $new_m
}
