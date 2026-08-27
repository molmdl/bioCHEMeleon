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
    variable _records [dict create]

    # Export the public symbols (documents the public contract).
    namespace export reconstruct_from_sentinels is_hider mark_found
}

# Dependency-injected sentinel reconstruction (port of v1 registry.py:420-443).
# `fetch_hider_ids` is a proc reference or `apply` lambda INJECTED by the
# composition root (game.tcl, a later phase), so this module stays pure — it
# calls $fetch_hider_ids without knowing it touches any molecular-viewer API.
# Clears existing records first (overwrite, NOT append), then records each
# sentinel index as a fresh entry with status=hidden.
proc ::biochemeleon::registry::reconstruct_from_sentinels {fetch_hider_ids} {
    variable _records
    set _records [dict create]
    foreach idx [$fetch_hider_ids] {
        dict set _records $idx [dict create rep "" status $::biochemeleon::registry::HIDER_STATUS_HIDDEN]
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
