# vmd/lib/registry.tcl
# PURE layer: stdlib-only tcl. No molecular-viewer API, no GUI toolkit.
# Direct port of v1 pymol/biochemeleon/registry.py (the dependency-injection pattern).
# Phase 13 scope: file + loadability + DI proc shape (full logic is a later phase).

namespace eval ::biochemeleon::registry {
    # Default status for a freshly inserted hider (not yet found by player).
    variable HIDER_STATUS_HIDDEN "hidden"

    # Status set when the player finds the hider (click handler, later phase).
    variable HIDER_STATUS_FOUND "found"

    # The registry: a dict keyed by atom `index` -> {rep status}.
    # v2 keys on `index`, NOT v1's (object, id) — VMD has no global atom id;
    # molid changes on every reload so the registry reconstructs from sentinels.
    # `rep` (Phase 16): the GAME_REPS name of the tier that owns the hider
    # ("VDW" for the Phase-16 sphere tier); "" for placeholder/unstamped
    # records — remaining_by_rep skips "" records (per-rep remaining is
    # derivable forever once the generator stamps a real rep).
    variable _records [dict create]

    # Export the public symbols (documents the public contract).
    namespace export reconstruct_from_sentinels is_hider mark_found count_hiders reset status_of count_remaining remaining_by_rep
}

# Dependency-injected sentinel reconstruction (port of v1 registry.py:420-443).
# `fetch_hider_ids` is a command prefix (a proc name OR an `apply` lambda list)
# INJECTED by the composition root (game.tcl, a later phase), so this module
# stays pure — it calls the prefix without knowing it touches any
# molecular-viewer API. The `{*}` argument expansion is the idiomatic tcl DI:
# it expands the command-prefix list into command words (works for a single
# proc name too — a 1-element list expands to itself).
# Clears existing records first (overwrite, NOT append), then records each
# sentinel index as a fresh entry with status=hidden. The optional `rep`
# (default "") stamps every record's rep field (Phase 16: game.tcl passes
# "VDW", the sphere tier's GAME_REPS name); 1-arg calls keep working unchanged
# (backward compatible with every existing caller/test).
proc ::biochemeleon::registry::reconstruct_from_sentinels {fetch_hider_ids {rep ""}} {
    variable _records
    set _records [dict create]
    foreach idx [{*}$fetch_hider_ids] {
        dict set _records $idx [dict create rep $rep status $::biochemeleon::registry::HIDER_STATUS_HIDDEN]
    }
    return
}

# Phase 13 stubs (a later phase fills in the real logic).

# Return 1 if `idx` is a registered hider, else 0.
proc ::biochemeleon::registry::is_hider {idx} {
    variable _records
    return [dict exists $_records $idx]
}

# Mark the hider at `idx` as found. Errors if `idx` is not registered
# (a clean error surfaces a caller bug rather than silently no-op-ing).
proc ::biochemeleon::registry::mark_found {idx} {
    variable _records
    if {![dict exists $_records $idx]} {
        error "hider $idx not registered"
    }
    dict set _records $idx status $::biochemeleon::registry::HIDER_STATUS_FOUND
    return
}

# Phase 15: number of registered hiders (dict size of _records).
# The capstone smoke asserts count_hiders == N post-start_game (SC3)
# and == 0 post-cleanup (proves no over/under-population).
proc ::biochemeleon::registry::count_hiders {} {
    variable _records
    return [dict size $_records]
}

# Phase 15: clear the registry (game::cleanup calls this post-restore so
# post-cleanup is_hider/count_hiders return 0 — v1 parity). Overwrites
# _records with an empty dict.
proc ::biochemeleon::registry::reset {} {
    variable _records
    set _records [dict create]
    return
}

# Phase 16: status of the hider at `idx` — "hidden", "found", or "" when the
# index is not registered. The single source of truth for found-state (LOOP-02):
# game.tcl's on_pick reads this BEFORE mark_found (the three-way
# miss/already-found/hidden guard, v1 game.py on_pick parity) because
# mark_found is a silent idempotent overwrite.
proc ::biochemeleon::registry::status_of {idx} {
    variable _records
    if {![dict exists $_records $idx]} {
        return ""
    }
    return [dict get [dict get $_records $idx] status]
}

# Phase 16: number of hiders still hidden (v1 game.py:113-116 `_remaining`
# parity). Counts ONLY status==hidden records — decrements on each mark_found,
# hits 0 on win. The Game tab pulls this for the total-remaining label (GAME-03).
proc ::biochemeleon::registry::count_remaining {} {
    variable _records
    set n 0
    dict for {k rec} $_records {
        if {[dict get $rec status] eq $::biochemeleon::registry::HIDER_STATUS_HIDDEN} {
            incr n
        }
    }
    return $n
}

# Phase 16: remaining hiders grouped by rep -> dict {rep count} over hidden
# records only (v1 registry.py:274-295 parity). Records with rep "" are
# skipped; reps absent from the records never appear (no zero-fill — the
# Game tab's format_remaining orders against GAME_REPS). Easy-mode per-rep
# remaining reads this (GAME-03).
proc ::biochemeleon::registry::remaining_by_rep {} {
    variable _records
    set out [dict create]
    dict for {k rec} $_records {
        if {[dict get $rec status] eq $::biochemeleon::registry::HIDER_STATUS_HIDDEN} {
            set r [dict get $rec rep]
            if {$r eq ""} {
                continue
            }
            if {![dict exists $out $r]} {
                dict set out $r 0
            }
            dict incr out $r
        }
    }
    return $out
}
