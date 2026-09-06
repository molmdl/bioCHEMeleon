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
# sources generators too). Also sources splice.tcl (PURE, same lib/ dir,
# Phase 17.2) -- make_residue_hiders consumes splice::select_anchors /
# displacement / assemble_record / resid_block and write_combined_pdb consumes
# splice::atom_record; pure re-init is harmless. Does NOT source registry.tcl
# -- the entry sources registry exactly ONCE; re-sourcing would WIPE _records.
# The DI fn (fetch_hider_indices) is injected INTO
# registry::reconstruct_from_sentinels by the composition root (game.tcl / the
# smoke), never called by mutation.tcl itself.
#
# Phase 17.1: bonded single-atom tier (make_bonded_hiders) -- hider name and
# element are COPIED from a distinct heavy-atom anchor (element = PDB cols
# 77-78, THE load-bearing blend field: blank degrades to element X radius
# 1.50 -- the probe-J defect class) and the position is drawn 1.2-1.6 A from
# the anchor so VMD's load-time distance search auto-bonds it. The record
# shape is now 5-field {name element x y z} EVERYWHERE (make_placeholder_hiders
# included); _hider_record's sentinel columns are unchanged.
#
# Phase 17.2: residue-splice tier (make_residue_hiders) -- ONE fake GAM
# residue (N/CA/C/O/CB) per hider, copied from a real anchor residue and
# rigid-translated 1.0 A perpendicular to the local peptide bond, serving
# Cartoon/NewCartoon/Trace/Tube alike (ONE splice, four reps). The fake
# residue gets ss `T` from the LOAD-TIME STRIDE run and renders as a smooth
# coil/turn tube (Option A; the full decision record lives in splice.tcl's
# header). NEVER call ssrecalc anywhere in the generation flow: load-time
# STRIDE already assigns ss and ssrecalc WIPES manual `set structure` writes
# (Pitfall C2). Residue rounds are tagged by tag_sentinels_mixed (CA-only
# beta, Pitfall C6), never by tag_sentinels.
source [file join [file dirname [info script]] setup_state.tcl]
source [file join [file dirname [info script]] generators.tcl]
source [file join [file dirname [info script]] splice.tcl]

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

    # Phase 17.2 residue-splice clearance: min distance from a candidate
    # anchor's residue atoms to any occupied hider position. This is a BRIDGE
    # concern (17.2-01's splice::select_anchors consumes pre-computed ok
    # descriptors and never sees occupied positions), so it lives HERE, not in
    # splice.tcl.
    variable MIN_OCC_SEP 3.0

    # Frozen at source time. [info script] is DYNAMIC/empty under `vmd -e` once
    # source completes, so proc bodies cannot call it (Phase 14 Pitfall; mirrors
    # demos.tcl:26). Capturing here (namespace eval runs during source) freezes
    # the value for proc-body use.
    variable script_dir [file dirname [info script]]

    namespace export make_placeholder_hiders make_bonded_hiders \
                     make_residue_hiders \
                     write_combined_pdb tag_sentinels tag_sentinels_mixed \
                     fetch_hider_indices mutate
}

# make_placeholder_hiders {molid count} -> list of {name element x y z}
# records (Phase 17.1 5-field shape; element = HID_ELEMENT "C" as Phase 16
# shipped -- the game's own hider reps set mol modcolor Element, so the
# placeholder element only matters for the user-rep path).
# Phase 16 REAL sphere placement (HIDER-03): uniform-random points inside the
# molecule's bounding box. Bbox via `measure minmax` on "all" (returns
# {{xmin ymin zmin} {xmax ymax zmax}} -- 2 elements, each a 3-float list;
# probe-verified) fed to the PURE sampler in vmd/lib/generators.tcl (v1
# formula ported 1:1: min + rand*span per axis; NO min-distance, NO overlap
# avoidance, NO clamping/inset -- overlapping a real atom is harmless). NO
# seed passed: the call continues the global PRNG stream (same convention as
# randomize_state; reseeding per call would correlate placements with prior
# rand() consumers). Names G01..GNN (2-digit zero-padded). Signature FROZEN
# (Phase 15 contract, 15-05): only the coordinate math (16-07) and the record
# shape (17.1: +element) changed. No molinfo call remains, so no
# catch-wrapping: `measure minmax` on a bad molid raises naturally and
# game.tcl propagates (caller aborts -- 15-05).
proc ::biochemeleon::mutation::make_placeholder_hiders {molid count} {
    variable HID_ELEMENT
    set all [atomselect $molid "all"]
    set mm [measure minmax $all]
    $all delete
    set pts [::biochemeleon::generators::sphere_positions $mm $count]
    set recs [list]
    set i 0
    foreach p $pts {
        incr i
        lassign $p x y z
        lappend recs [list [format "G%02d" $i] $HID_ELEMENT $x $y $z]
    }
    return $recs
}

# make_bonded_hiders {molid count {occupied_hiders {}}} -> list of
# {name element x y z} records (Phase 17.1 bonded single-atom tier, HIDER-04).
# Each hider MIMICS a distinct heavy-atom anchor: name + element are COPIED
# (element = PDB cols 77-78, THE load-bearing blend field -- blank degrades
# to element X radius 1.50 and Name-coloring becomes unpredictable) and the
# position is drawn 1.2-1.6 A from the anchor (generators::place_bonded_hider)
# so VMD's load-time distance search AUTO-BONDS the hider to it
# (d < 0.6*(r_i+r_j); extra bonds to nearby atoms are NORMAL -- consumers
# must assert numbonds >= 1, NEVER == 1).
#
# Anchor policy (research 3.3): heavy atoms only -- selection
# `not resname GAM and element C N O S P` (H excluded: caps the bond cutoff
# at 1.62 A and may be absent). Anchors are sampled DISTINCT via
# generators::sample; if fewer anchors exist than count, count is CAPPED at
# the anchor count (v1 under-generation parity -- the tier simply produces
# fewer hiders).
#
# Performance: anchor indices come from ONE bulk `get index`; per anchor the
# coords/name/element come from a 1-atom selection via SINGLE-KEYWORD gets
# (research Pitfall 5: multi-keyword get returns per-atom LISTS that lassign
# flat-splits wrongly) and the occupied neighborhood from ONE C-side spatial
# query `within 3.0 of index $aid and not index $aid` (3.0 = MIN_SEP_REAL
# 1.4 + D_MAX 1.6 margin) -- real atoms are never looped in tcl.
#
# Occupied list per anchor ({x y z sep} triples for reject_overlaps):
#   - the anchor's neighborhood real atoms at sep MIN_SEP_REAL (the anchor
#     itself EXCLUDED -- bonding to it is the point; anything farther than
#     3.0 A cannot come within 1.4 A of a candidate drawn <= 1.6 A out);
#   - this tier's previously-placed hider positions at sep MIN_SEP_HIDER;
#   - the occupied_hiders arg (earlier tiers this round; list of {x y z}
#     triples -- the caller extracts positions from prior records) at sep
#     MIN_SEP_HIDER (no GAM-GAM cross-bonds).
#
# NO seed anywhere: the generators calls continue the global PRNG stream
# (same convention as make_placeholder_hiders / randomize_state).
proc ::biochemeleon::mutation::make_bonded_hiders {molid count {occupied_hiders {}}} {
    # Sep constants live in the generators namespace (17.1-03) -- referenced
    # qualified so this proc cannot shadow them with same-named locals.
    set real_sep $::biochemeleon::generators::MIN_SEP_REAL
    set hider_sep $::biochemeleon::generators::MIN_SEP_HIDER
    set asel [atomselect $molid {not resname GAM and element C N O S P}]
    if {[$asel num] == 0} {
        $asel delete
        error "make_bonded_hiders: no heavy-atom anchors"
    }
    # ONE bulk get for all anchor indices (performance: never per-atom here).
    set aids [$asel get index]
    $asel delete
    if {[llength $aids] < $count} {
        set count [llength $aids]
    }
    set chosen [::biochemeleon::generators::sample $aids $count]
    set recs [list]
    set placed [list]
    foreach aid $chosen {
        # Anchor attributes: single-keyword gets, lindex the 1-element result.
        set sel [atomselect $molid "index $aid"]
        set ax [lindex [$sel get x] 0]
        set ay [lindex [$sel get y] 0]
        set az [lindex [$sel get z] 0]
        set aname [lindex [$sel get name] 0]
        set aelem [lindex [$sel get element] 0]
        $sel delete
        # Neighborhood (C-side spatial hash): every OTHER real atom within
        # 3.0 A of the anchor, at sep MIN_SEP_REAL.
        set nsel [atomselect $molid "within 3.0 of index $aid and not index $aid"]
        set nxs [$nsel get x]
        set nys [$nsel get y]
        set nzs [$nsel get z]
        $nsel delete
        set occupied [list]
        foreach nx $nxs ny $nys nz $nzs {
            lappend occupied [list $nx $ny $nz $real_sep]
        }
        # This tier's earlier hiders + earlier tiers' hiders: sep
        # MIN_SEP_HIDER (avoid GAM-GAM cross-bonds).
        foreach pp $placed {
            lappend occupied \
                [list [lindex $pp 0] [lindex $pp 1] [lindex $pp 2] $hider_sep]
        }
        foreach oh $occupied_hiders {
            lassign $oh ox oy oz
            lappend occupied [list $ox $oy $oz $hider_sep]
        }
        # Pure placement: 1.2-1.6 A bond band, rejection + relaxation, and
        # the %8.3f |coord| <= 9999 guard. No seed (global PRNG stream).
        set pos [::biochemeleon::generators::place_bonded_hider \
                     [list $ax $ay $az] $occupied]
        lappend recs [list $aname $aelem {*}$pos]
        lappend placed $pos
    }
    return $recs
}

# make_residue_hiders {molid count {occupied_hiders {}} {resid_start {}}}
#   -> list of {chain resid atoms} records (Phase 17.2 residue-splice tier).
# ONE fake GAM residue (N/CA/C/O/CB; CB omitted when the anchor lacks it) per
# hider: the anchor's present-atoms coords rigid-translated by exactly 1.0 A
# perpendicular to the local peptide-bond vector (splice::displacement of
# anchor C -> next N), the ANCHOR's chain id (NEVER "G" -- a mismatched chain
# forms a separate fragment and never renders traced, research Pitfall C8),
# and a disjoint resid from the 9001+k block (splice::resid_block; real demo
# resids <= ~500). Mid-chain anchors only (both peptide junctions present),
# pairwise CA separation >= 5.0 via splice::select_anchors, under-generation
# tolerated (count capped at eligible supply; a vmdcon -warn fires,
# non-blocking). Runs on the ORIGINAL pre-mutate molecule -- it has NO GAM
# atoms; `not resname GAM` is future-proofing.
#
# Flow (plan 17.2-04; pure geometry delegated to the probe-proven splice.tcl
# layer):
#   1. Candidates: ONE bulk CA selection with batched SINGLE-KEYWORD gets
#      (research Pitfall 5: multi-keyword get returns nested lists).
#   2. Per candidate: residue-atom presence (N/CA/C/O required, CB optional),
#      MID-CHAIN proof (prev C within 1.7 of the anchor N -- the anchor's own
#      C is ~2.4 A from its N, excluded by 1.7; next N within 1.7 of the
#      anchor C), and occupied clearance (>= MIN_OCC_SEP from every
#      occupied_hiders position) -- all folded into the ok flag of a
#      {key ok ca_x ca_y ca_z} descriptor.
#   3. splice::select_anchors picks up to $count (shuffled, greedy sep
#      rejection). NO seed anywhere: the global PRNG stream convention.
#   4. Per chosen anchor (acceptance order, ordinal k): refetch present atoms
#      in N/CA/C/O/CB order, splice::displacement of (anchor C, next N),
#      splice::resid_block 1 (resid_start + k) $real_max, splice::assemble_record
#      -> {chain resid atoms_displaced}.
proc ::biochemeleon::mutation::make_residue_hiders {molid count {occupied_hiders {}} {resid_start {}}} {
    variable MIN_OCC_SEP
    set casel [atomselect $molid {protein and not resname GAM and name CA}]
    if {[$casel num] == 0} {
        $casel delete
        error "make_residue_hiders: no protein anchors"
    }
    # ONE bulk get per keyword (batched; never a multi-keyword get here).
    set idxs [$casel get index]
    set rids [$casel get resid]
    set chns [$casel get chain]
    set xs [$casel get x]
    set ys [$casel get y]
    set zs [$casel get z]
    $casel delete
    set num [llength $idxs]
    set real_max 0
    foreach rid $rids {
        if {$rid > $real_max} { set real_max $rid }
    }
    if {$count > $num} { set count $num }
    set descriptors [list]
    set bykey [dict create]
    for {set i 0} {$i < $num} {incr i} {
        set rid [lindex $rids $i]
        set ch [lindex $chns $i]
        set cax [lindex $xs $i]
        set cay [lindex $ys $i]
        set caz [lindex $zs $i]
        # Blank chain = validated territory: a blank-chain fake residue would
        # mis-bond/mis-fragment (the chain id is THE fragment identity for the
        # trace family) -- skip the candidate entirely.
        if {[string trim $ch] eq ""} { continue }
        # Residue-atom presence in N/CA/C/O/CB order (CB optional).
        set present [list]
        set ok 1
        foreach nm {N CA C O CB} {
            set s [atomselect $molid "chain $ch and resid $rid and name $nm"]
            if {[$s num] >= 1} {
                lappend present [list $nm \
                    [lindex [$s get element] 0] \
                    [lindex [$s get x] 0] \
                    [lindex [$s get y] 0] \
                    [lindex [$s get z] 0] \
                    [lindex [$s get index] 0]]
            }
            $s delete
        }
        set names [list]
        foreach p $present { lappend names [lindex $p 0] }
        foreach req {N CA C O} {
            if {[lsearch -exact $names $req] < 0} { set ok 0 }
        }
        # MID-CHAIN proof: prev C within 1.7 A of the anchor N (the anchor's
        # own C is ~2.4 A from its N -- excluded by the 1.7 cutoff) AND next N
        # within 1.7 A of the anchor C.
        if {$ok} {
            set n_i -1
            set c_i -1
            foreach p $present {
                if {[lindex $p 0] eq "N"} { set n_i [lindex $p 5] }
                if {[lindex $p 0] eq "C"} { set c_i [lindex $p 5] }
            }
            set pcsel [atomselect $molid "name C and within 1.7 of index $n_i"]
            if {[$pcsel num] < 1} { set ok 0 }
            $pcsel delete
            set nnsel [atomselect $molid "name N and within 1.7 of index $c_i"]
            if {[$nnsel num] < 1} { set ok 0 }
            $nnsel delete
        }
        # Occupied clearance: every present-atom coord >= MIN_OCC_SEP from
        # every occupied hider position (earlier tiers this round).
        if {$ok && [llength $occupied_hiders] > 0} {
            foreach p $present {
                lassign [lrange $p 2 4] px py pz
                foreach oh $occupied_hiders {
                    lassign $oh ox oy oz
                    set d2 [expr {($px - $ox) * ($px - $ox) \
                        + ($py - $oy) * ($py - $oy) \
                        + ($pz - $oz) * ($pz - $oz)}]
                    set sep2 [expr {$MIN_OCC_SEP * $MIN_OCC_SEP}]
                    if {[expr {$d2 + 1e-9}] < $sep2} { set ok 0 }
                }
            }
        }
        lappend descriptors [list $ch:$rid $ok $cax $cay $caz]
        dict set bykey $ch:$rid [list $ch $rid]
    }
    # Pure anchor selection (shuffled, greedy >= 5.0 A CA separation). NO
    # seed: continues the global PRNG stream. May under-generate.
    set chosen [::biochemeleon::splice::select_anchors $descriptors $count]
    if {[llength $chosen] < $count} {
        catch {vmdcon -warn "make_residue_hiders: under-generated [llength $chosen] of $count hiders (anchor separation rejections)"}
    }
    set recs [list]
    set k 0
    foreach desc $chosen {
        lassign $desc key ok ax ay az
        lassign [dict get $bykey $key] ch rid
        # Refetch the anchor's present atoms in N/CA/C/O/CB order
        # ({name element x y z} -- the splice::assemble_record shape), and
        # capture the anchor C's index for the next-N spatial query below.
        set atoms_data [list]
        set c_idx -1
        foreach nm {N CA C O CB} {
            set s [atomselect $molid "chain $ch and resid $rid and name $nm"]
            if {[$s num] >= 1} {
                if {$nm eq "C"} { set c_idx [lindex [$s get index] 0] }
                lappend atoms_data [list $nm \
                    [lindex [$s get element] 0] \
                    [lindex [$s get x] 0] \
                    [lindex [$s get y] 0] \
                    [lindex [$s get z] 0]]
            }
            $s delete
        }
        # Anchor C coords + the next residue's N coords (the displacement
        # anchors: 1.0 A perpendicular to unit(next N - anchor C)).
        set c_pt [list]
        foreach a $atoms_data {
            if {[lindex $a 0] eq "C"} {
                set c_pt [list [lindex $a 2] [lindex $a 3] [lindex $a 4]]
            }
        }
        set nnsel [atomselect $molid "name N and within 1.7 of index $c_idx"]
        set n_next_pt [list \
            [lindex [$nnsel get x] 0] \
            [lindex [$nnsel get y] 0] \
            [lindex [$nnsel get z] 0]]
        $nnsel delete
        set d [::biochemeleon::splice::displacement $c_pt $n_next_pt]
        if {$resid_start eq ""} {
            set start_k [expr {$::biochemeleon::splice::RESID_BASE + $k}]
        } else {
            set start_k [expr {$resid_start + $k}]
        }
        set resid [lindex [::biochemeleon::splice::resid_block 1 $start_k $real_max] 0]
        lappend recs [::biochemeleon::splice::assemble_record $atoms_data $ch $resid $d]
        incr k
    }
    return $recs
}

# _hider_record {serial name element x y z} -> 78-char ATOM string.
# `element` is THE load-bearing blend field (PDB cols 77-78, %2s): VMD parses
# it into the atom's element -> VDW radius + Element coloring; a blank/mangled
# field silently degrades to element X radius 1.50 with unpredictable Name
# color (research probe-J defect class). Callers copy it from the anchor
# (make_bonded_hiders) or pass HID_ELEMENT (placeholder records carry it).
# CRITICAL: beta is %6.1f -> "-999.0" (6 cols, NO overflow). %6.2f -> "-999.00"
# OVERFLOWS the 6-col beta field and corrupts segid (Pitfall 1, probe2b.log).
# Use EXACTLY this format string (probe-verified, probe2b.log:53 -> len=78,
# segid GAME survives in the PDB columns).
proc ::biochemeleon::mutation::_hider_record {serial name element x y z} {
    variable HID_RESNAME
    variable HID_CHAIN
    variable HID_RESSEQ
    variable HID_OCC
    variable HID_BETA
    variable HID_SEGID
    return [format "ATOM  %5d %4s%1s%-3s %1s%4d%1s   %8.3f%8.3f%8.3f%6.2f%6.1f      %-4s%2s" \
        $serial $name " " $HID_RESNAME $HID_CHAIN $HID_RESSEQ " " \
        $x $y $z $HID_OCC $HID_BETA $HID_SEGID $element]
}

# write_combined_pdb {molid hider_records out_path {residue_records {}}}
#   -> orig atom count.
# hider_records are the 5-field {name element x y z} shape (Phase 17.1 --
# make_placeholder_hiders and make_bonded_hiders both emit it).
# residue_records (Phase 17.2, optional) are the {chain resid atoms} shape
# from make_residue_hiders/splice::assemble_record; each residue's atoms are
# appended AFTER the simple records with a continuing serial via
# splice::atom_record (the 78-col probe-pinned layout, beta -999.0 on CA
# only, segid GAME, element always emitted, NO CONECT and no TER --
# append-at-end == mid-file splice, research probe6). 3-arg behavior is
# byte-identical to the Phase 15/16 flow.
# writepdb-then-splice (A1): writepdb preserves beta/segid/occ (NOT user --
# Pitfall 7; irrelevant here) and emits 0 TER + 1 END for 1k8p (no TER handling).
# Step (a) atomselect "all" writepdb; (b) read, drop END/blank lines;
# (c) append one hider ATOM per record via _hider_record (serial = orig_n+1+i),
# then the residue records' atoms in record order (serial continues);
# (d) write END; close. out_path MUST be Windows-visible (caller converts via
# demos::to_vmd_path; mutate computes $env(TEMP) internally).
proc ::biochemeleon::mutation::write_combined_pdb {molid hider_records out_path {residue_records {}}} {
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
        foreach {nm el x y z} $r { break }
        puts $fh [_hider_record $serial $nm $el $x $y $z]
        incr serial
    }
    foreach r $residue_records {
        lassign $r chain resid atoms
        foreach a $atoms {
            lassign $a nm el x y z
            puts $fh [::biochemeleon::splice::atom_record $serial $nm $el $chain $resid $x $y $z]
            incr serial
        }
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

# tag_sentinels_mixed {molid n_simple residue_records orig_n} -> beta-set
# index list (Phase 17.2). The residue-round analog of tag_sentinels: simple
# hider atoms AND residue CAs carry beta -999 + segid GAME + per-atom user
# ordinals; residue N/C/O/CB carry beta 0.00 + segid GAME (NO beta sentinel).
#
# WHY a selector-based tag (tag_sentinels as-is) is FORBIDDEN here: it sets
# beta on ALL `resname GAM` atoms -- on a residue round that would stamp the
# fake N/C/O/CB too, so `resname GAM and beta < 0` would return 5 indices
# per hider instead of 1 (5x counts, broken bookkeeping -- Pitfall C6).
#
# WHY the index computation is SAFE: writepdb preserves index order (atoms
# land in the PDB in index order -- Phase-15 established) and
# splice::assemble_record guarantees each residue's atom order is
# N-first/CA-second, so the fake atoms occupy orig_n.. in record order:
# n_simple single-atom records first, then each residue's atoms in record
# order. The index sets are derived from orig_n + the record layout -- NEVER
# from a selector that could over-match (e.g. `resname GAM` would also hit
# nothing else today, but the index walk is layout-pinned and independent of
# any selector semantics).
proc ::biochemeleon::mutation::tag_sentinels_mixed {molid n_simple residue_records orig_n} {
    variable HID_BETA
    variable HID_SEGID
    set beta_idx [list]
    set other_idx [list]
    for {set i 0} {$i < $n_simple} {incr i} {
        lappend beta_idx [expr {$orig_n + $i}]
    }
    set cur [expr {$orig_n + $n_simple}]
    foreach r $residue_records {
        lassign $r chain resid atoms
        foreach a $atoms {
            lassign $a nm el x y z
            if {$nm eq "CA"} {
                lappend beta_idx $cur
            } else {
                lappend other_idx $cur
            }
            incr cur
        }
    }
    set sel [atomselect $molid "index $beta_idx"]
    $sel set beta  $HID_BETA
    $sel set segid $HID_SEGID
    # Per-atom user = ordinal (0,1,2,...) over the beta set in file order --
    # one list-set, same atom order.
    set ords [list]
    set u 0
    foreach i $beta_idx { lappend ords $u; incr u }
    $sel set user $ords
    $sel delete
    if {[llength $other_idx] > 0} {
        set sel2 [atomselect $molid "index $other_idx"]
        $sel2 set beta 0.00
        $sel2 set segid $HID_SEGID
        $sel2 delete
    }
    return $beta_idx
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

# mutate {molid hider_records {residue_records {}}} -> new game molid.
# Owns the FORWARD reload: write combined PDB -> mol delete ORIGINAL -> mol new
# combined (NEW molid, monotonic > old -- Pitfall 4) -> tag sentinels -> return.
# The 3rd arg (Phase 17.2, optional -- backward compatible) carries residue
# records: NON-EMPTY dispatches to tag_sentinels_mixed (CA-only beta on the
# residue CAs; NEVER tag_sentinels on a residue round -- it would beta-stamp
# all 5 fake atoms per residue and return 5 fetch indices per hider, Pitfall
# C6), EMPTY keeps tag_sentinels (the byte-unchanged simple-tier path).
# Does NOT save/restore reps/viewpoint (backup.tcl's job -- game.tcl calls
# backup::snapshot BEFORE mutate and backup::restore AFTER). NO `cleanup` proc in
# mutation.tcl (the restore-reload is backup::restore). NEVER call ssrecalc
# anywhere in this flow: the load-time STRIDE run already assigns ss (the
# spliced GAM residue gets `T`) and ssrecalc WIPES manual `set structure`
# writes (Pitfall C2).
proc ::biochemeleon::mutation::mutate {molid hider_records {residue_records {}}} {
    if {[info exists ::env(TEMP)] && $::env(TEMP) ne ""} {
        set out [file join $::env(TEMP) biochemeleon_game.pdb]
    } else {
        set out [file join [pwd] biochemeleon_game.pdb]
    }
    set orig_n [write_combined_pdb $molid $hider_records $out $residue_records]
    mol delete $molid
    set new_m [mol new $out type pdb waitfor all]
    if {[llength $residue_records] > 0} {
        tag_sentinels_mixed $new_m [llength $hider_records] $residue_records $orig_n
    } else {
        tag_sentinels $new_m
    }
    return $new_m
}
