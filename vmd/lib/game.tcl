# vmd/lib/game.tcl -- Phase 15 composition root (GameController).
# Wires backup (viewpoint+reps) + mutation (PDB-rebuild+sentinel) + registry
# (pure). The ONLY module that touches all three; injects the atomselect
# apply-lambda into registry (the only place atomselect touches the registry).
#
# Sources NOTHING (the entry sources backup+mutation+registry in dependency
# order before this file; re-sourcing registry here would WIPE _records -- do
# not). For standalone smoke use, the smoke sources the lib files in dep order
# directly (mirrors the entry, NOT the entry itself -- avoids GUI/dialog
# baggage). game.tcl references ::biochemeleon::registry::* at CALL time (tcl
# proc resolution is call-time, so source order only needs the namespace to
# exist before the first CALL, which is always after the entry finishes).
#
# Owns NO mol delete/mol new directly: each reload is delegated to exactly one
# mol-bridge module (mutation::mutate owns the forward mutate-reload;
# backup::restore owns the restore-reload). game.tcl is a thin orchestrator
# like v1 game.py.
#
# Tcl 8.5 ONLY (no 8.6 control-flow idioms; brace all expr; dict create/get).
# The apply-lambda body is the ONLY place atomselect touches the registry --
# it is INJECTED, so registry.tcl stays pure.

namespace eval ::biochemeleon::game {
    namespace export start_game cleanup restart
}

# start_game {molid hider_count} -> game_state dict {game_molid hider_count snapshot}.
#
# Begin a round. Phase 15: N placeholder hiders (mutation::make_placeholder_hiders).
# Phase 16 replaces make_placeholder_hiders with real sphere placement; the
# start_game signature, the game_state shape, and the DI injection line stay
# identical.
#
# Ordering is NON-NEGOTIABLE (15-RESEARCH-registry-game.md section "Recommended
# approach 4"):
#   1. backup::snapshot BEFORE any mutation (captures original pdb_path +
#      viewpoint + reps from the LIVE original -- must run before
#      mutation::mutate mol-deletes it).
#   2. mutation::make_placeholder_hiders (pure data prep; reads coords only).
#   3. mutation::mutate (mol delete original + mol new combined + tag sentinels
#      -> NEW game_molid, monotonic > old).
#   4. backup::apply on the NEW game_molid (SC4 forward: restore reps +
#      viewpoint on the game_molid -- viewmaster-style; NO mol ops, state-only).
#   5. registry::reconstruct_from_sentinels with the apply-lambda DI (the
#      lambda selects on the game_molid; count_hiders == N after).
proc ::biochemeleon::game::start_game {molid hider_count} {
    # 1. Snapshot BEFORE any mutation (captures original pdb_path + viewpoint + reps).
    set snapshot [::biochemeleon::backup::snapshot $molid]
    # 2. Build placeholder hider records (Phase 16 swaps this for real sphere placement).
    set hider_records [::biochemeleon::mutation::make_placeholder_hiders $molid $hider_count]
    # 3. Mutate: mol delete original + mol new combined + tag sentinels -> new game molid.
    set game_molid [::biochemeleon::mutation::mutate $molid $hider_records]
    # 4. SC4 forward: re-apply saved reps + viewpoint to the NEW game_molid (viewmaster-style).
    ::biochemeleon::backup::apply $snapshot $game_molid
    # 5. Reconstruct the registry from sentinels (DI: inject the atomselect apply-lambda).
    #    CRITICAL: [list apply {lambda} $game_molid] is a COMMAND-PREFIX VALUE (the {expand}
    #    in reconstruct_from_sentinels invokes it). NEVER [apply {lambda} $game_molid] --
    #    that EVALUATES immediately and returns the id-list value, which [{*}] would then
    #    run as a command -> "invalid command name <first-index>" (the 13-01 DI bug,
    #    probe-verified in 15-RESEARCH-registry-game).
    ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{molid} {
        set sel [atomselect $molid "resname GAM and beta < 0"]
        set ids [$sel get index]
        $sel delete
        return $ids
    }} $game_molid]
    return [dict create game_molid $game_molid hider_count $hider_count snapshot $snapshot]
}

# cleanup {game_state} -> restored molid.
#
# Restore the original molecule + clear the registry. backup::restore owns the
# FULL restore cycle: mol delete $molid_to_delete + mol new original + apply
# reps+viewpoint + return new_molid.
#
# CRITICAL (the PDB-rebuild integration contract): pass game_molid (the LIVE
# game molecule from game_state) as molid_to_delete -- NOT snapshot.molid. The
# original (snapshot.molid) was DELETED by mutation::mutate during start_game,
# so snapshot.molid is DEAD by cleanup time. Passing the dead snapshot.molid
# would either error on "no such molecule" or silently no-op and LEAK the
# 560-atom game molecule (the Plan-03/04 integration blocker). restore's 2nd
# arg is the LIVE game_molid to delete. Then registry::reset so post-cleanup
# is_hider/count_hiders return 0 (v1 parity: game.py cleanup re-instantiates
# the registry).
proc ::biochemeleon::game::cleanup {game_state} {
    set restored [::biochemeleon::backup::restore [dict get $game_state snapshot] [dict get $game_state game_molid]]
    ::biochemeleon::registry::reset
    return $restored
}

# restart {game_state} -> new game_state.
#
# cleanup then start_game with the SAME hider_count on the restored molid.
# The new start_game reconstructs the registry on the fresh game_molid (the
# registry is a namespace singleton with NO cross-reload persistence in
# Phase 15; rebuild-from-sentinels each round).
proc ::biochemeleon::game::restart {game_state} {
    set hider_count [dict get $game_state hider_count]
    set molid [::biochemeleon::game::cleanup $game_state]
    return [::biochemeleon::game::start_game $molid $hider_count]
}
