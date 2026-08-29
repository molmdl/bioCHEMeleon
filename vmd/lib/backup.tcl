# vmd/lib/backup.tcl -- MOL BRIDGE: viewpoint + rep save/restore on a NEW molid.
#
# Owns the RESTORE-reload (mol delete game + mol new original + re-apply reps +
# restore viewpoint -> new molid). game.tcl calls snapshot (before mutate),
# apply (on the game_molid after mutate -- SC4 forward), restore (on cleanup).
#
# STANDALONE: sources NOTHING. Uses only mol/molinfo (scope is viewpoint + reps
# + the original PDB path; reloading the original PDB restores atom fields
# automatically, so no atom-field snapshot is needed). NOT sourcing
# demos.tcl/setup_state.tcl/registry.tcl would reverse the dependency direction
# (demos is a SIBLING mol bridge, not a dependency of backup) and, for
# registry, would wipe the live registry on re-source. See
# 15-RESEARCH-backup-restore.md §Recommended approach.
#
# Tcl 8.5 ONLY (no 8.6 control-flow idioms -- use catch + foreach+lappend;
# brace all expr). `dict create`/`dict get`/`dict exists` available. Every API
# claim below was probe-verified + cited to vmd-ref/ in
# 15-RESEARCH-backup-restore.md.

namespace eval ::biochemeleon::backup {
    namespace export snapshot apply restore
}

# snapshot {molid} -> dict {molid <int> filename <path> viewpoint <4-matrix list> reps <list of {style sel color material}>}
#
# Saves ALL reps on the molecule (NOT just GAME_REPS) -- success criterion #2
# says "same reps". A bad molid lets molinfo error naturally (propagates up so
# the caller -- game.tcl -- can abort the game); the smoke asserts this errors.
#
# Viewpoint: viewmaster 4-matrix combined get, POSITIONAL field order
# {rotate_matrix center_matrix scale_matrix global_matrix} (research PROBE1 --
# the order is positional; the set MUST match the get order; viewmaster order
# is the canonical form and was probe-verified for an EXACT round-trip).
#
# Reps: the COMBINED-BRACES molinfo form (single-field molinfo get {rep $i}
# FAILS -- v2 demos.tcl Pitfall 3; this is the SAME form demos.tcl:94 uses).
# {color $i}/{material $i} return NAMES ("Name","Opaque"), NOT indices -- pass
# straight to modcolor/modmaterial on restore.
proc ::biochemeleon::backup::snapshot {molid} {
    set filename [molinfo $molid get filename]
    set viewpoint [molinfo $molid get {rotate_matrix center_matrix scale_matrix global_matrix}]
    set reps [list]
    set n [molinfo $molid get numreps]
    for {set i 0} {$i < $n} {incr i} {
        foreach {style sel color material} \
            [molinfo $molid get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        lappend reps [list $style $sel $color $material]
    }
    return [dict create molid $molid filename $filename viewpoint $viewpoint reps $reps]
}

# apply {snapshot molid} -> {}
#
# The STATE-ONLY half of restore: re-apply reps + viewpoint to an EXISTING
# molid. NO mol delete/new (game.tcl calls this on the game_molid after
# mutation::mutate to satisfy SC4's forward path -- the forward mutate-reload
# keeps the molid; only reps/viewpoint need re-asserting). Composed by `restore`
# (DRY -- the research inlined the same logic; routing it through `apply` keeps
# ONE clear/addrep/viewpoint code path).
#
# (a) Rep clear: clonerep.tcl:94-96 pattern -- capture count ONCE, always
#     `mol delrep 0` (remaining reps renumber; save_state.tcl:121-123's
#     ascending-`delrep $i` has an off-by-one bug -- Pitfall 4, DO NOT USE).
# (b) Rep re-apply: FORM B (isolated) -- `mol addrep` then `mol modstyle/
#     modselect/modcolor/modmaterial`. NOT form A (mol representation/color/
#     selection/material + mol addrep) which mutates the GLOBAL current-default
#     rep/color/selection/material (Pitfall 5 -- a later bare mol addrep would
#     silently inherit the last rep's values).
# (c) Viewpoint restore: positional, SAME field order as the get in `snapshot`.
proc ::biochemeleon::backup::apply {snapshot molid} {
    # (a) Clear ALL existing reps (captured count + always index 0).
    set n [molinfo $molid get numreps]
    for {set i 0} {$i < $n} {incr i} { mol delrep 0 $molid }
    # (b) Re-apply each saved rep via form B (isolated).
    set idx 0
    foreach rep [dict get $snapshot reps] {
        foreach {style sel color material} $rep { break }
        mol addrep $molid
        mol modstyle   $idx $molid $style
        mol modselect  $idx $molid $sel
        mol modcolor   $idx $molid $color
        mol modmaterial $idx $molid $material
        incr idx
    }
    # (c) Restore viewpoint (positional, SAME field order as the get).
    molinfo $molid set {rotate_matrix center_matrix scale_matrix global_matrix} \
        [dict get $snapshot viewpoint]
    return
}

# restore {snapshot molid_to_delete} -> new_molid (int)
#
# The FULL cleanup cycle: mol delete $molid_to_delete + mol new original + apply
# + return new_molid. The 2-arg signature is REQUIRED for the PDB-rebuild flow:
# mutation::mutate deletes the ORIGINAL molid during start_game, so
# snapshot.molid is DEAD by cleanup time. The caller (game::cleanup) knows the
# LIVE game_molid from game_state and passes it as `molid_to_delete`. The old
# 1-arg `restore` that deleted `snapshot.molid` would either error on "no such
# molecule" or silently no-op and LEAK the 560-atom game molecule -- the
# Plan-03/04 integration blocker the plan checker flagged. The smoke's
# dead-original sub-case regression-guards this.
#
# `molinfo $m get filename` returns the EXACT path string passed to `mol new`
# (already C:/ for bundled demos -- research PROBE5); `mol new $filename type
# pdb` reloads with the identical atom count (2597==2597 in PROBE5). The
# viewpoint+reps are re-applied via `apply` (the same path game.tcl uses for
# SC4's forward mutate-reload). The new molid is strictly-higher than the old
# (monotonic, never reused -- research PROBE6).
proc ::biochemeleon::backup::restore {snapshot molid_to_delete} {
    mol delete $molid_to_delete
    set new_molid [mol new [dict get $snapshot filename] type pdb]
    apply $snapshot $new_molid
    return $new_molid
}
