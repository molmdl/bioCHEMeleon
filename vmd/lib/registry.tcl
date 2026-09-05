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

    # Phase 17.2: the resid-block map — a dict resid -> hider index (the PURE
    # half of the multi-atom pick fallback). Mutated ONLY by reset (cleared)
    # and register_resid_block (wholesale replace); reconstruct_from_sentinels
    # never touches it.
    variable _resid_block [dict create]

    # Export the public symbols (documents the public contract).
    namespace export reconstruct_from_sentinels is_hider mark_found count_hiders reset status_of count_remaining remaining_by_rep set_rep assign_reps register_resid_block hider_for_resid
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
# _records with an empty dict. Phase 17.2: ALSO clears _resid_block — a
# stale resid block must not survive cleanup into the next round (only
# reset and register_resid_block mutate _resid_block). Observable
# _records behavior is unchanged.
proc ::biochemeleon::registry::reset {} {
    variable _records
    variable _resid_block
    set _records [dict create]
    set _resid_block [dict create]
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

# ---- Phase 17.1: per-record rep assignment ----

# Stamp ONE record's rep field — the per-record complement to the SINGLE
# reconstruct_from_sentinels call (P17D/P8: reconstruct clears + stamps one
# rep for ALL records, so a multi-tier round calls it ONCE, then assigns
# each hider's tier here — NEVER a per-tier reconstruct loop).
# Registered idx -> rep is overwritten (any prior value, including "");
# the record's status is PRESERVED. Unregistered idx -> error with the
# exact mark_found wording. Returns nothing.
proc ::biochemeleon::registry::set_rep {idx rep} {
    variable _records
    if {![dict exists $_records $idx]} {
        error "hider $idx not registered"
    }
    set rec [dict get $_records $idx]
    dict set rec rep $rep
    dict set _records $idx $rec
    return
}

# Bulk per-record rep assignment: `mapping` is a dict idx -> rep applied via
# set_rep. ATOMIC: validates EVERY key first — if ANY idx is unregistered,
# errors "hider $k not registered" BEFORE touching any record (no partial
# application). Rep values are stored as given — the registry does NOT
# validate them against GAME_REPS (that is the caller's — rep_tiers /
# game.tcl — job). Empty mapping is a no-op. Returns nothing.
proc ::biochemeleon::registry::assign_reps {mapping} {
    variable _records
    dict for {k v} $mapping {
        if {![dict exists $_records $k]} {
            error "hider $k not registered"
        }
    }
    dict for {k v} $mapping {
        ::biochemeleon::registry::set_rep $k $v
    }
    return
}

# ---- Phase 17.2: resid-block lookup (multi-atom pick fallback, pure half) ----

# The resid -> hider-index map serves the multi-atom pick fallback. A
# cartoon splice (17.2-01) registers ONE atom per hider — the fake GAM
# residue's CA (beta=-999 on the CA only) — but a real click on the cartoon
# bump can land on the residue's N/C/O/CB. The pick contract therefore needs
# a SECOND, resid-keyed lookup: clicked index -> resid (read by game.tcl
# at pick time, 17.2-09, keeping THIS module pure) -> registered
# hider index (the fake CA). The v2 analog of v1's get_altconf_by_resv dual
# lookup, keyed `resid ∈ registered block`.
#
# Harmless 9001 collision: single-atom simple-tier hiders all share resid
# 9001 (17.2-01 RESID_BASE), the same number the fake-residue block starts
# at. This is safe because on_pick consults is_hider FIRST — a single-atom
# hider click IS registered — so the fallback only fires for non-registered
# atoms, whose only resid-block members are fake-residue N/C/O/CB. Real demo
# atoms have resid ≪ 9001. Mixed rounds with two residue tiers get disjoint
# blocks via the dispatch's resid_start offset (17.2-09) — this module just
# stores whatever mapping it is given.
#
# Lifecycle (pinned by tests): register_resid_block WHOLESALE-REPLACES the
# block (one call per round, never merged with a prior block); reset CLEARS
# it; reconstruct_from_sentinels NEVER touches it (the dispatch always
# re-registers after reconstruct in residue rounds).

# Register ONE round's resid -> hider-index map. `mapping` is a dict
# resid -> hider index (the dispatch builds it: fake residue k, resid
# 9001+k, -> its registered CA index).
# ATOMIC validate-then-replace: every idx is validated as a registered hider
# FIRST (error "hider $idx not registered" — the exact mark_found wording —
# on any miss) BEFORE the block is touched (no partial state). All valid →
# the block is REPLACED WHOLESALE by $mapping (never merged with a prior
# round's block; one call per round). An empty mapping is a no-op — the
# block is left UNCHANGED (not cleared; reset is the clearer). Returns
# nothing.
proc ::biochemeleon::registry::register_resid_block {mapping} {
    variable _records
    variable _resid_block
    dict for {resid idx} $mapping {
        if {![dict exists $_records $idx]} {
            error "hider $idx not registered"
        }
    }
    if {[dict size $mapping] == 0} {
        return
    }
    set _resid_block $mapping
    return
}

# Resolve a fake-residue resid (9001+k) to its registered hider index —
# the pure half of the multi-atom pick fallback (a click on a fake GAM
# residue's N/C/O/CB resolves to the registered CA). Unknown resid -> ""
# (NEVER an error — the miss path is a normal "Miss!" pick). Tcl 8.5: dict
# get has NO 3-arg default form — use the dict exists guard + dict get.
proc ::biochemeleon::registry::hider_for_resid {resid} {
    variable _resid_block
    if {![dict exists $_resid_block $resid]} {
        return ""
    }
    return [dict get $_resid_block $resid]
}
