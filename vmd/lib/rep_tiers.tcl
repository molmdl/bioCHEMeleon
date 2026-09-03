# vmd/lib/rep_tiers.tcl
# PURE layer: rep-tier dispatch decisions (Phase 17.1 N-tier hiders).
# stdlib-only tcl 8.5. No molecular-viewer API, no GUI toolkit -- unit-testable
# via tcltest under headless VMD (vmd/tests/test_rep_tiers.test).
#
# SOURCES setup_state.tcl (same lib/ directory) for GAME_REPS and
# randomize_per_rep -- the mutation.tcl pattern; its `namespace eval` re-inits
# CONSTANTS to identical values (harmless pure re-init).
#
# THE 17.1 TIER SEAM: a tier = {name, kind, style_args}. IMPLEMENTED_TIERS is
# the GAME_REPS-ordered subset whose generators exist in Phase 17.1; Phase 17.2
# widens it with the residue-splice kinds (Cartoon/NewCartoon/Trace/Tube) --
# a one-constant change plus TIER_KINDS entries, both in this file only.
#
# STYLE ARGS (the explicit-cutoff rule): DynamicBonds' default cutoff is 3.0 A
# with a strict `<` test, which draws spurious 2.3-2.9 A bonds on hider scenes
# (17.1-RESEARCH-game-reps-viability.md sections 3/6, P-5), so the dispatch
# layer passes an explicit 1.6. Every other implemented tier is the bare
# single-word style.
#
# P9 EFFECTIVE-TOTAL RULE: an explicit per_rep REPLACES the round total (no
# top-up; v1 semantics). Callers MUST set the round's effective hider count to
# effective_total(resolve_per_rep ...) so win messages / remaining labels
# never disagree with the registry count.
#
# SENTINEL FILTER (defense-in-depth): scene_reps_to_per_rep skips any rep
# whose selection text contains "resname GAM" (the game's own hider reps).
# Detection normally runs INSIDE start_game on backup::snapshot's rep list of
# the clean restored original, where game reps are structurally absent; the
# filter covers the pathological case of a user manually loading a game PDB
# (selection read-back is byte-exact, research RQ1.3/P5).
#
# ORDER DISCIPLINE: every output dict is built by iterating GAME_REPS (never
# dict insertion order) -- the validate_state order-stability discipline
# (order-stable `eq` round-trips). The drop-overflow clamp is the one
# exception: it follows the cleaned dict's own order, validate_state's exact
# semantics (the pinned behavior: {VDW 8 Lines 8} hider_count 10 -> {VDW 8}).
#
# Tcl 8.5 ONLY: no 8.6 control-flow idioms (catch + foreach+lappend instead);
# brace every expr; one `variable` declaration per line; `lsearch -exact` for
# membership; `string first` for the sentinel check.

source [file join [file dirname [info script]] setup_state.tcl]

namespace eval ::biochemeleon::rep_tiers {
    # GAME_REPS-ordered subset with generators in Phase 17.1. Phase 17.2 widens
    # this one constant with Cartoon/NewCartoon/Trace/Tube (the extension seam).
    variable IMPLEMENTED_TIERS {Lines VDW Licorice CPK Points DynamicBonds}

    # Tier kind per implemented tier: "free" = renders a lone hider without any
    # bond partner; "bonded" = bond-style rep. Cartoon/NewCartoon/Trace/Tube
    # deliberately ABSENT (not implemented in 17.1 -> tier_kind "" / implemented 0).
    variable TIER_KINDS [dict create \
        Lines bonded \
        VDW free \
        Licorice bonded \
        CPK bonded \
        Points bonded \
        DynamicBonds bonded]

    # Export the public symbols so callers may `namespace import` them.
    # Tests and game.tcl use fully-qualified names; the export list documents
    # the public contract.
    namespace export implemented tier_kind style_args \
                     scene_reps_to_per_rep filter_per_rep_to_scene \
                     resolve_per_rep tiers_from_per_rep effective_total
}

# 1 if `rep` is an implemented tier (a generator exists in this phase), else 0.
proc ::biochemeleon::rep_tiers::implemented {rep} {
    variable IMPLEMENTED_TIERS
    if {[lsearch -exact $IMPLEMENTED_TIERS $rep] >= 0} { return 1 }
    return 0
}

# "free" | "bonded" | "" (empty for unknown/unimplemented tiers).
proc ::biochemeleon::rep_tiers::tier_kind {rep} {
    variable TIER_KINDS
    if {[dict exists $TIER_KINDS $rep]} {
        return [dict get $TIER_KINDS $rep]
    }
    return ""
}

# The modstyle ARG LIST for a tier: DynamicBonds carries the explicit 1.6
# cutoff (the spurious-bond rule); the other implemented tiers are the bare
# single-word style; unknown/unimplemented -> {} (the caller must skip).
proc ::biochemeleon::rep_tiers::style_args {rep} {
    variable IMPLEMENTED_TIERS
    if {[lsearch -exact $IMPLEMENTED_TIERS $rep] < 0} { return [list] }
    if {$rep eq "DynamicBonds"} {
        return [list DynamicBonds 1.6]
    }
    return [list $rep]
}

# Map a backup::snapshot `reps` list (records of {style sel color material},
# backup.tcl:39-50) to a GAME_REPS-ordered PRESENCE dict {rep 1}: keep a style
# only when it is a GAME_REPS name AND its selection text does NOT contain the
# hider sentinel "resname GAM". Duplicates dedup -- v1 semantics are presence
# per rep (gui_setup.py:398-408) and get_active_reps does NOT dedup (P4).
# Empty/degenerate input -> empty dict.
proc ::biochemeleon::rep_tiers::scene_reps_to_per_rep {reps_list} {
    set present [dict create]
    foreach record $reps_list {
        set style [lindex $record 0]
        set sel   [lindex $record 1]
        if {[lsearch -exact $::biochemeleon::setup_state::GAME_REPS $style] < 0} { continue }
        if {[string first {resname GAM} $sel] >= 0} { continue }
        dict set present $style 1
    }
    set result [dict create]
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        if {[dict exists $present $rep]} {
            dict set result $rep 1
        }
    }
    return $result
}

# Copy of per_rep restricted to keys present in `detected` (a presence dict
# from scene_reps_to_per_rep), GAME_REPS-ordered, counts preserved. A
# non-dict input yields the empty dict (degenerate-input guard).
proc ::biochemeleon::rep_tiers::filter_per_rep_to_scene {per_rep detected} {
    set result [dict create]
    if {[catch {dict size $per_rep}]} { return $result }
    if {[catch {dict size $detected}]} { return $result }
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        if {[dict exists $per_rep $rep] && [dict exists $detected $rep]} {
            dict set result $rep [dict get $per_rep $rep]
        }
    }
    return $result
}

# The lock-scene / randomize composition (game.tcl's per_rep resolution):
#   a. Clean per_rep: drop non-GAME_REPS keys + non-integer/<=0 counts.
#   b. allowed = lock_scene truthy ? (detected keys INTERSECT
#      IMPLEMENTED_TIERS, or IMPLEMENTED_TIERS when that set is empty)
#      : IMPLEMENTED_TIERS.
#   c. Drop per_rep keys not in allowed; then drop-overflow clamp the sum to
#      <= hider_count (validate_state semantics: keep entries that fit, DROP
#      overflow, never truncate).
#   d. Empty result -> randomize_per_rep over `allowed` (the quick-008
#      non-empty-subset guarantee; the seed is forwarded untouched -- it seeds
#      the global PRNG once when non-empty, else the sequence continues).
#   e. Return the dict rebuilt in GAME_REPS order (order-stable `eq`).
proc ::biochemeleon::rep_tiers::resolve_per_rep {hider_count per_rep detected lock_scene {seed {}}} {
    variable IMPLEMENTED_TIERS
    set game_reps $::biochemeleon::setup_state::GAME_REPS
    # (a) clean
    set clean [dict create]
    if {![catch {dict size $per_rep}]} {
        dict for {rep cnt} $per_rep {
            if {[lsearch -exact $game_reps $rep] < 0} { continue }
            if {![string is integer -strict $cnt] || $cnt <= 0} { continue }
            dict set clean $rep $cnt
        }
    }
    # (b) allowed
    if {$lock_scene} {
        set allowed [list]
        if {![catch {dict size $detected}]} {
            foreach rep $IMPLEMENTED_TIERS {
                if {[dict exists $detected $rep]} { lappend allowed $rep }
            }
        }
        if {[llength $allowed] == 0} { set allowed $IMPLEMENTED_TIERS }
    } else {
        set allowed $IMPLEMENTED_TIERS
    }
    # (c) restrict + drop-overflow clamp (validate_state semantics)
    set restricted [dict create]
    dict for {rep cnt} $clean {
        if {[lsearch -exact $allowed $rep] >= 0} {
            dict set restricted $rep $cnt
        }
    }
    if {![string is integer -strict $hider_count] || $hider_count < 0} {
        set hider_count 0
    }
    set clamped [dict create]
    set remaining $hider_count
    dict for {rep cnt} $restricted {
        if {$cnt <= $remaining} {
            dict set clamped $rep $cnt
            incr remaining -$cnt
        }
    }
    # (d) empty -> randomize over allowed
    set result $clamped
    if {[dict size $result] == 0} {
        set result [::biochemeleon::setup_state::randomize_per_rep $hider_count $allowed $seed]
    }
    # (e) rebuild GAME_REPS-ordered
    set ordered [dict create]
    foreach rep $game_reps {
        if {[dict exists $result $rep]} {
            dict set ordered $rep [dict get $result $rep]
        }
    }
    return $ordered
}

# Ordered {code style count} triples over the ACTIVE tiers only: GAME_REPS
# order, counts > 0 only, code = 1-based ordinal WITHIN the active list
# (per_rep {VDW 2 Lines 3} -> {{1 Lines 3} {2 VDW 2}}: Lines precedes VDW in
# GAME_REPS). The code is only a discriminator; the registry's rep field
# carries the GAME_REPS name. Empty/invalid input -> empty list.
proc ::biochemeleon::rep_tiers::tiers_from_per_rep {per_rep} {
    set result [list]
    if {[catch {dict size $per_rep}]} { return $result }
    set code 0
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        if {![dict exists $per_rep $rep]} { continue }
        set cnt [dict get $per_rep $rep]
        if {![string is integer -strict $cnt] || $cnt <= 0} { continue }
        incr code
        lappend result [list $code $rep $cnt]
    }
    return $result
}

# The P9 effective total: integer sum of per_rep counts (0 for empty/invalid
# input). The caller sets the round's hider_count to this so win messages and
# the Game-tab remaining label never disagree with the registry count.
proc ::biochemeleon::rep_tiers::effective_total {per_rep} {
    if {[catch {dict size $per_rep}]} { return 0 }
    set total 0
    dict for {rep cnt} $per_rep {
        if {[string is integer -strict $cnt]} {
            incr total $cnt
        }
    }
    return $total
}
