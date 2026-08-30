# vmd/lib/hiders.tcl -- MOL BRIDGE: hider rendering + found-marking visuals.
#
# Purpose: the VISUAL half of the sphere-hider mechanic (HIDER-03 + LOOP-01).
# add_hider_reps adds exactly 2 reps to the GAME molid -- a hidden rep (VDW +
# Element + user2<1 selection) and a found rep (VDW + ColorID 7 + user2>0
# selection); mark_found_visual flags one atom found (user2=1) and forces both
# rep selections to re-evaluate. game.tcl (Plan 16-08) calls add_hider_reps in
# start_game (AFTER backup::apply, so the hider reps are the LAST two) and
# mark_found_visual from on_pick.
#
# STANDALONE: sources NOTHING (sibling mol bridge, like backup.tcl -- uses only
# mol/molinfo/atomselect; re-sourcing registry would WIPE _records, and proc
# bodies cannot re-locate lib files via [info script] anyway).
#
# THE TWO-REP SPLIT: VMD colors per-REP, not per-atom (FEATURES.md:77) -- there
# is NO per-atom color override (v1's per-atom recolor command has no VMD
# analog). Recoloring "just the found atom" inside one rep is impossible, so
# found-state is a per-atom user2 flag and TWO reps select the two partitions:
#   hidden rep: VDW + Element coloring + {resname GAM and beta < 0 and user2 < 1}
#   found rep : VDW + ColorID 7 (green) + {resname GAM and beta < 0 and user2 > 0}
# Both selector strings are SENTINELS -- verbatim, never alter (together they
# must keep partitioning ALL hiders).
#
# Blending rationale: hiders carry element C (Phase-15 PDB cols 77-78), so VDW
# radius 1.7 == real carbons and Element coloring gives the same cyan as real
# carbons under default Name coloring (research SS4; probes F6/F7).
#
# NEVER HIDE A REP: UG node140 -- "Hidden reps cannot be picked and do not show
# any graphics." Pickability is per-REP; hiding either hider rep would make its
# hiders unclickable. NEITHER hider rep is EVER hidden during play (the
# whole-rep off toggle is Phase 19's found-hider dropdown, not ours). Found
# hiders stay visible (green) -> still pickable -> double-count prevention is
# the CALLER's registry-status guard (registry::mark_found is idempotent).
#
# NEVER WRITE BETA: the sentinel selector "resname GAM and beta < 0" must keep
# matching ALL hiders (registry reconstruct + cleanup both depend on it).
# Found flags live ONLY in user2 (a free per-atom channel; "user" is taken --
# tag_sentinels stores ordinals there). beta stays -999 forever.
#
# MANDATORY modselect RE-ASSERT: rep selections re-evaluate per TIMESTEP only
# (UG node140 selupdate semantics). A static single-frame molecule NEVER
# re-evaluates its reps' cached selections when an atom field changes -- so
# after EVERY user2 write, BOTH hider reps get their (unchanged) selection
# strings re-issued via mol modselect to force re-evaluation (probe F17). This
# is REQUIRED for correct found-marking, not insurance; idempotent and ~free
# at <=50 hiders.
#
# REP INDICES: rep indices renumber on delrep (Pitfall 9). Hider reps are added
# LAST (base = numreps AFTER backup::apply -- deterministic per round, since
# apply always ends with exactly the snapshot's reps) and recorded in the
# namespace vars below; mark_found_visual re-checks them against numreps
# before use (never trusts a cached index blindly).
#
# Tcl 8.5 ONLY (no 8.6 control-flow idioms; brace all expr). Sentinel selector
# strings are braced literals. Every atomselect is $sel delete'd.

namespace eval ::biochemeleon::hiders {
    namespace export add_hider_reps mark_found_visual
    # Rep indices this module created (one variable per line -- the Tcl 8.5
    # multi-name `variable a b` form is a name-VALUE pair, not a link; 14-04).
    # -1 = "no hider reps added yet on any molecule".
    variable hidden_rep -1
    variable found_rep -1
}

# add_hider_reps {molid} -> {}
#
# Adds the 2 hider reps to the game molid and records their indices. Call
# AFTER backup::apply in start_game (hider reps land LAST: base..base+1).
# NO showrep calls anywhere -- both reps stay SHOWN (UG node140: a hidden rep
# cannot be picked; see header).
proc ::biochemeleon::hiders::add_hider_reps {molid} {
    variable hidden_rep
    variable found_rep
    # Base index = numreps AFTER backup::apply (deterministic per round).
    set base [molinfo $molid get numreps]
    # Hidden rep: hiders whose user2 flag is still < 1 (unfound). Bare VDW =
    # defaults (res 8.0 scale 1.0 -- a 3rd param ERRORS, probe C3); Element
    # coloring auto-tracks the hider element (C -> cyan, matches real carbons).
    mol addrep $molid
    set hidden_rep $base
    mol modstyle $hidden_rep $molid VDW
    mol modcolor $hidden_rep $molid Element
    mol modselect $hidden_rep $molid {resname GAM and beta < 0 and user2 < 1}
    # Found rep: hiders whose user2 flag is > 0 (marked found). ColorID 7 =
    # green (the id is a 4th arg to modcolor; read-back is "ColorID 7").
    mol addrep $molid
    set found_rep [expr {$base + 1}]
    mol modstyle $found_rep $molid VDW
    mol modcolor $found_rep $molid ColorID 7
    mol modselect $found_rep $molid {resname GAM and beta < 0 and user2 > 0}
    return
}

# mark_found_visual {molid idx} -> {}
#
# Visual half of a found event: set user2=1 on the picked index, then re-issue
# BOTH modselects with the UNCHANGED sentinel strings (the mandatory
# re-evaluation re-assert -- see header). The atom migrates hidden-rep ->
# found-rep (green sphere). Errors with a clear message if the hider reps
# were never added (or are out of range for THIS molid).
proc ::biochemeleon::hiders::mark_found_visual {molid idx} {
    variable hidden_rep
    variable found_rep
    # Guard: hider reps must exist and be in range (rep indices renumber on
    # delrep -- re-check against numreps, never trust a cached index blindly).
    set nreps [molinfo $molid get numreps]
    if {$hidden_rep < 0 || $found_rep < 0
        || $hidden_rep >= $nreps || $found_rep >= $nreps} {
        error "hiders::mark_found_visual: hider reps not added -- call add_hider_reps first (hidden_rep=$hidden_rep found_rep=$found_rep numreps=$nreps)"
    }
    # 1. Flag the atom. user2 values are FLOATS (read-back 1.0/0.0) -- always
    #    compare numerically, never string-eq to "1" (Pitfall 7).
    set sel [atomselect $molid "index $idx"]
    $sel set user2 1
    $sel delete
    # 2. MANDATORY re-evaluation re-assert (Pitfall 3): re-issue BOTH
    #    modselects with the UNCHANGED literal strings -- a static molecule
    #    never re-evaluates cached rep selections on atom-field change
    #    (timestep-based re-eval only). Hidden rep first, then found rep.
    mol modselect $hidden_rep $molid {resname GAM and beta < 0 and user2 < 1}
    mol modselect $found_rep $molid {resname GAM and beta < 0 and user2 > 0}
    return
}
