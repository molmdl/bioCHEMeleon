# vmd/lib/game.tcl -- Phase 15 composition root (GameController), extended in
# Phase 16 with the click-scoring controller (on_pick + set_callbacks + the
# current_state stash).
# Wires backup (viewpoint+reps) + mutation (PDB-rebuild+sentinel) + registry
# (pure) + hiders (the 2-rep found-visual layer). The ONLY module that touches
# all of them; injects the atomselect apply-lambda into registry (the only
# place atomselect touches the registry).
#
# Sources NOTHING (the entry sources the lib files in dependency order before
# this file; re-sourcing registry here would WIPE _records -- do not). For
# standalone smoke use, the smoke sources the lib files in dep order directly
# (mirrors the entry, NOT the entry itself -- avoids GUI/dialog baggage).
# game.tcl references ::biochemeleon::{registry,hiders,game_logic}::* at CALL
# time (tcl proc resolution is call-time, so source order only needs the
# namespaces to exist before the first CALL, which is always after the entry
# finishes).
#
# Owns NO mol delete/mol new directly: each reload is delegated to exactly one
# mol-bridge module (mutation::mutate owns the forward mutate-reload;
# backup::restore owns the restore-reload). game.tcl is a thin orchestrator
# like v1 game.py.
#
# Pick contract (pick_bridge.tcl, Plan 16-06): _on_event forwards exactly
# `game::on_pick <index>` -- ONE argument, the 0-based atom index. The
# game_state is NOT threaded through pick_bridge: start_game stashes it in
# the `current_state` namespace var (dict shape FROZEN per 15-05:
# {game_molid hider_count snapshot}) and cleanup clears it. The GUI (Plan
# 16-09) registers its log/remaining/win callbacks via set_callbacks.
#
# Tcl 8.5 ONLY (no 8.6 control-flow idioms; brace all expr; dict create/get).
# The apply-lambda body is the ONLY place atomselect touches the registry --
# it is INJECTED, so registry.tcl stays pure.

namespace eval ::biochemeleon::game {
    namespace export start_game cleanup restart on_pick set_callbacks

    # Phase 16: the CURRENT game_state dict {game_molid hider_count snapshot}
    # (shape FROZEN per 15-05). Stashed by start_game, cleared by cleanup --
    # on_pick reads it instead of threading game_state through pick_bridge
    # (the PickBridge contract delivers ONLY the index).
    variable current_state [dict create]

    # Callback command prefixes registered via set_callbacks (v1 game.py:94-111
    # parity). Empty list = unregistered; invocation is `catch {{*}$cb <args>}`
    # so an empty prefix fails harmlessly inside the catch (a no-op).
    #   log_cb       ONE arg   (the formatted line from game_logic::log_append)
    #   remaining_cb ZERO args  (pull model -- the GUI reads the registry itself)
    #   win_cb       TWO args  (elapsed_seconds hider_count)
    variable _cb_log [list]
    variable _cb_remaining [list]
    variable _cb_win [list]
}

# start_game {molid hider_count} -> game_state dict {game_molid hider_count snapshot}.
#
# Begin a round. Phase 15: N placeholder hiders (mutation::make_placeholder_hiders).
# Phase 16 replaces make_placeholder_hiders with real sphere placement; the
# start_game signature, the game_state shape, and the DI injection line stay
# identical.
#
# SELF-GUARDING (16-13, VERIFICATION gap 1): an active/prior round (non-empty
# current_state stash) is cleaned up FIRST -- auto-restart with the CALLER's
# new settings (this call's molid + hider_count, NOT the old round's). A stale
# stash (game molecule deleted externally) cannot corrupt the new round: the
# catch branch re-does registry::reset + the stash clear, and the target is
# remapped to the restored original by LIVENESS when the requested target was
# the old game molecule. Both the console path and dialog.tcl on_start go
# through here, so stacked hider generations are impossible at this single
# choke point.
#
# Ordering is NON-NEGOTIABLE (15-RESEARCH-registry-game.md section "Recommended
# approach 4"; 16-RESEARCH-sphere.md SS5.5 adds the hider-rep step). The 16-13
# active-game guard runs BEFORE step 1: the snapshot must capture the LIVE
# original of the NEW round, which only exists after the old round's cleanup
# restored it.
#   1. backup::snapshot BEFORE any mutation (captures original pdb_path +
#      viewpoint + reps from the LIVE original -- must run before
#      mutation::mutate mol-deletes it).
#   2. mutation::make_placeholder_hiders (pure data prep; reads coords only).
#   3. mutation::mutate (mol delete original + mol new combined + tag sentinels
#      -> NEW game_molid, monotonic > old).
#   4. backup::apply on the NEW game_molid (SC4 forward: restore reps +
#      viewpoint on the game_molid -- viewmaster-style; NO mol ops, state-only).
#   5. hiders.tcl: add the 2 hider reps AFTER backup::apply (research SS5.5 --
#      base index = numreps AFTER apply, deterministic per round, so the
#      hider reps are the LAST two: base..base+1; Pitfall 9).
#   6. registry::reconstruct_from_sentinels with the apply-lambda DI (the
#      lambda selects on the game_molid; count_hiders == N after).
# The resulting game_state is STASHED in the namespace var current_state
# (on_pick's data source) before being returned.
proc ::biochemeleon::game::start_game {molid hider_count} {
    variable current_state
    # ---- ACTIVE-GAME GUARD (16-13, VERIFICATION gap 1) --------------------
    # A Start during an in-flight round or after a won round must NOT stack
    # hider generations (the observed defect: 561-atom combined PDB from a
    # 558-atom game molecule, Segments: 3). Auto-restart semantics: clean up
    # the existing round FIRST, then start fresh with THIS call's settings
    # (NOT the old round's hider_count -- the user pressed Start with the
    # CURRENT Setup form; restart {game_state} stays Phase 19's same-count
    # Restart). Both the console path and dialog.tcl on_start go through
    # here, so stacked generations are impossible at this single choke point.
    if {[dict size $current_state] > 0} {
        set old_gs $current_state
        catch {vmdcon -info {bioCHEMeleon: active game found -- cleaning it up before the new round}}
        if {[catch {::biochemeleon::game::cleanup $old_gs} restored]} {
            # Stale stash: the game molecule is already gone (deleted
            # externally). cleanup's backup::restore errored before its
            # registry::reset + stash clear ran -- do both here so no ghost
            # state leaks into the new round.
            catch {::biochemeleon::registry::reset}
            set current_state [dict create]
            set restored {}
        }
        # Target remap by LIVENESS (molids are monotonic, never reused, so
        # the restored original never collides with the old game molid). If
        # the requested target WAS the old game molecule, cleanup just killed
        # it -- start on the restored original instead. A live different
        # target passes through unchanged.
        # hider_count is NOT re-clamped in the remap branch: pass-through
        # matches restart's own semantics (restart also reuses hider_count
        # on the restored original); validate_state in on_start already
        # clamped it against the user-selected target.
        if {[catch {molinfo $molid get numatoms} natoms]
                || ![string is integer -strict $natoms]
                || $natoms <= 0} {
            if {[catch {molinfo $restored get numatoms} rnatoms] == 0
                    && [string is integer -strict $rnatoms] && $rnatoms > 0} {
                set molid $restored
                catch {vmdcon -info {bioCHEMeleon: Start target was the previous game molecule -- starting on the restored original}}
            }
            # If restored is dead too, keep $molid: the normal body's
            # backup::snapshot errors naturally and the caller (on_start)
            # surfaces "Could not start the game" -- degraded but NOT corrupt.
        }
    }
    # ---- end guard ---------------------------------------------------------
    # 1. Snapshot BEFORE any mutation (captures original pdb_path + viewpoint + reps).
    set snapshot [::biochemeleon::backup::snapshot $molid]
    # 2. Build placeholder hider records (Phase 16 swaps this for real sphere placement).
    set hider_records [::biochemeleon::mutation::make_placeholder_hiders $molid $hider_count]
    # 3. Mutate: mol delete original + mol new combined + tag sentinels -> new game molid.
    set game_molid [::biochemeleon::mutation::mutate $molid $hider_records]
    # 4. SC4 forward: re-apply saved reps + viewpoint to the NEW game_molid (viewmaster-style).
    ::biochemeleon::backup::apply $snapshot $game_molid
    # 5. Phase 16 (research SS5.5): the 2 hider reps go AFTER backup::apply
    #    (base numreps deterministic) and before the registry reconstruct.
    ::biochemeleon::hiders::add_hider_reps $game_molid
    # 6. Reconstruct the registry from sentinels (DI: inject the atomselect apply-lambda).
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
    # Build the game_state (shape FROZEN per 15-05), STASH it for on_pick
    # (pick_bridge forwards only the index -- game.tcl owns its own state),
    # then return it.
    set gs [dict create game_molid $game_molid hider_count $hider_count snapshot $snapshot]
    set current_state $gs
    return $gs
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
    variable current_state
    set restored [::biochemeleon::backup::restore [dict get $game_state snapshot] [dict get $game_state game_molid]]
    ::biochemeleon::registry::reset
    # Phase 16: the round is over -- clear the on_pick stash so a stale pick
    # after cleanup hits the empty-state guard (no-op) instead of reading a
    # dead game_molid.
    set current_state [dict create]
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

# set_callbacks {log_cb remaining_cb win_cb} -> {}.
#
# Register the GUI callback command prefixes (v1 game.py:94-111 parity; the
# Plan 16-09 Game tab calls this in start_round):
#   log_cb       receives ONE arg -- the formatted line returned by
#                game_logic::log_append ("Miss!" / "Already found!" /
#                "Found one! N remaining" / the win line).
#   remaining_cb receives ZERO args -- PULL model: the GUI re-reads
#                registry::count_remaining / remaining_by_rep itself.
#   win_cb       receives TWO args -- elapsed_seconds (frozen by finish_win)
#                and hider_count.
# Each prefix is a command-word list (e.g. {lappend ::LOG_LOG}, or a fully
# qualified proc name). Unset prefixes are harmless: on_pick invokes them as
# `catch {{*}$cb <args>}` and an empty prefix fails inside the catch.
proc ::biochemeleon::game::set_callbacks {log_cb remaining_cb win_cb} {
    variable _cb_log
    variable _cb_remaining
    variable _cb_win
    set _cb_log $log_cb
    set _cb_remaining $remaining_cb
    set _cb_win $win_cb
    return
}

# on_pick {idx} -> {}.
#
# The click-scoring controller (v1 game.py on_pick 1:1, 04-03). Called by
# pick_bridge::_on_event with ONE argument: the 0-based atom index (the
# registry key). The game_state is NOT passed in -- this proc reads the
# current_state namespace var stashed by start_game.
#
# THREE-WAY GUARD (caller-side; registry stays the single source of truth,
# LOOP-02. registry::mark_found is a SILENT idempotent overwrite -- probe F19
# / Pitfall 5 -- so the guard MUST live here, BEFORE mark_found; is_hider is
# checked FIRST and status_of of an unregistered index is "" not an error):
#   unregistered idx -> "Miss!" log only (LOOP-01: no harm)
#   status "found"   -> "Already found!" log only (no double-count)
#   status "hidden"  -> mark_found_visual + mark_found + "Found one! N
#                       remaining" + remaining callback -> win check (LOOP-03)
#
# STATE GATE (16-RESEARCH-gametab SS6.10): scoring only in state "playing" --
# stray picks during idle/countdown/won are no-ops. This gate + finish_win's
# error-on-second-call is the double-win prevention.
#
# WIN FLOW: last find (count_remaining == 0) -> finish_win (freezes elapsed,
# errors on double) -> timer_elapsed returns the FROZEN value -> win log line
# -> win_cb (elapsed hider_count). PickBridge deactivation is the GUI's job
# (its on_win) -- game.tcl does NOT touch pick_bridge.
#
# The whole scoring body is catch-wrapped with the PickBridge handler's rule:
# an error thrown inside a pick trace/poll would be lost or half-applied, so
# errors are only REPORTED via vmdcon -err, never re-raised. `set rc [catch
# ...]` + rc == 1 (TCL_ERROR), NOT a truthy catch test -- the guard exits
# below `return`, which carries TCL_RETURN (rc == 2) that a truthy test would
# misreport (pick_bridge probe16).
proc ::biochemeleon::game::on_pick {idx} {
    variable current_state
    variable _cb_log
    variable _cb_remaining
    variable _cb_win
    # State gate FIRST (a stray pick outside playing must be a no-op).
    if {[::biochemeleon::game_logic::state] ne "playing"} {
        return
    }
    set rc [catch {
        # Stash guard: no round in flight (start_game never ran, or cleanup
        # cleared it) -> nothing to score.
        if {[dict size $current_state] == 0} {
            return
        }
        # 1. Unregistered -> miss (LOOP-01). is_hider checked FIRST.
        if {![::biochemeleon::registry::is_hider $idx]} {
            catch {{*}$_cb_log [::biochemeleon::game_logic::log_append miss ""]}
            return
        }
        # 2. Already found -> log only (no double-count; LOOP-02).
        if {[::biochemeleon::registry::status_of $idx] eq $::biochemeleon::registry::HIDER_STATUS_FOUND} {
            catch {{*}$_cb_log [::biochemeleon::game_logic::log_append already ""]}
            return
        }
        # 3. Hidden hider: visual mark (user2 flag + the modselect re-assert),
        #    registry mark, log + remaining callback.
        ::biochemeleon::hiders::mark_found_visual [dict get $current_state game_molid] $idx
        ::biochemeleon::registry::mark_found $idx
        set rem [::biochemeleon::registry::count_remaining]
        catch {{*}$_cb_log [::biochemeleon::game_logic::log_append found $rem]}
        catch {{*}$_cb_remaining}
        # Win (LOOP-03): finish_win freezes the elapsed and errors on a second
        # call; timer_elapsed AFTER finish_win returns the FROZEN value.
        if {$rem == 0} {
            ::biochemeleon::game_logic::finish_win
            set elapsed [::biochemeleon::game_logic::timer_elapsed]
            catch {{*}$_cb_log [::biochemeleon::game_logic::log_append win "You found all [::biochemeleon::registry::count_hiders] hiders in [::biochemeleon::game_logic::format_mmss $elapsed]!"]}
            catch {{*}$_cb_win $elapsed [dict get $current_state hider_count]}
        }
    } err]
    if {$rc == 1} {
        catch {vmdcon -err "bioCHEMeleon game on_pick: $err"}
    }
    return
}
