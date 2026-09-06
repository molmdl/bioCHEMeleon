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
# game.tcl references ::biochemeleon::{registry,rep_tiers,hiders,game_logic}::*
# at CALL time (tcl proc resolution is call-time, so source order only needs the
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
# the `current_state` namespace var (dict shape 15-05 {game_molid
# hider_count snapshot} + the additive 17.1-06 per_rep key) and cleanup
# clears it. The GUI (Plan 16-09) registers its log/remaining/win callbacks
# via set_callbacks.
#
# Tcl 8.5 ONLY (no 8.6 control-flow idioms; brace all expr; dict create/get).
# The apply-lambda body is the ONLY place atomselect touches the registry --
# it is INJECTED, so registry.tcl stays pure.

namespace eval ::biochemeleon::game {
    namespace export start_game cleanup restart on_pick set_callbacks

    # Phase 16: the CURRENT game_state dict {game_molid hider_count snapshot}
    # (15-05 shape + the additive 17.1-06 per_rep key -- 4 keys total).
    # Stashed by start_game, cleared by cleanup --
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

# start_game {molid hider_count {per_rep {}} {lock_scene 0}} ->
#   game_state dict {game_molid hider_count snapshot per_rep}.
#
# Begin a round. 17.1-06: the per-tier DISPATCH composition root -- lock-scene
# derivation, per-tier placement over the N generators, multi-tier registry
# stamping. Backward compatible: 2-arg calls (the Phase-15/16 signature) keep
# working and randomize across IMPLEMENTED_TIERS (resolve_per_rep's
# empty-per_rep path -- the quick-008 non-empty-subset distribution).
#   per_rep    : validated dict {GAME_REPS name -> count} (setup_state);
#                {} = randomize.
#   lock_scene : 1 = restrict per_rep to the tiers DETECTED on the scene
#                (snapshot reps via rep_tiers::scene_reps_to_per_rep);
#                0 = per_rep as given (or randomize when empty).
# P9 EFFECTIVE-TOTAL RULE: an explicit per_rep REPLACES the round total (no
# top-up; v1 semantics) -- game_state's hider_count is the EFFECTIVE total
# (sum of the resolved per_rep), so the win message and win_cb never
# disagree with the registry count. Requested-but-unimplemented tiers are
# dropped with a non-blocking vmdcon -warn (v1 under-generation parity).
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
# approach 4"; 16-RESEARCH-sphere.md SS5.5 adds the hider-rep step; 17.1-06
# adds the tier-dispatch steps -- 17.1-RESEARCH-rep-infra.md RQ3.2/RQ4.3). The
# 16-13 active-game guard runs BEFORE step 1: the snapshot must capture the
# LIVE original of the NEW round, which only exists after the old round's
# cleanup restored it.
#   1. backup::snapshot BEFORE any mutation (captures original pdb_path +
#      viewpoint + reps from the LIVE original -- must run before
#      mutation::mutate mol-deletes it).
#   2. Lock-scene detection from THIS round's OWN snapshot reps
#      (rep_tiers::scene_reps_to_per_rep): the guard's cleanup restored the
#      original first, so the snapshot is structurally free of game reps;
#      the sentinel filter inside rep_tiers is defense-in-depth (RQ1.4/P5).
#   3. rep_tiers::resolve_per_rep (lock-scene restriction / randomize /
#      drop-overflow clamp) -> the EFFECTIVE per_rep; eff_total = its sum
#      (P9). Unimplemented-tier warning against the CALLER's keys first.
#   4. Per-tier placement loop in GAME_REPS order
#      (rep_tiers::tiers_from_per_rep): free tiers ->
#      mutation::make_placeholder_hiders; bonded tiers ->
#      mutation::make_bonded_hiders with the accumulating occupied-hider
#      position list; residue tiers (17.2-09: Cartoon/NewCartoon/Trace/Tube)
#      -> mutation::make_residue_hiders with the resid_start offset
#      (RESID_BASE + residue records placed so far -- two residue tiers in
#      one round must not collide on the 9001 block). Simple-record lists
#      and residue-record lists are accumulated SEPARATELY with per-tier
#      ACTUAL counts tracked (a tier may under-generate: make_bonded_hiders
#      caps at the anchor count, make_residue_hiders at the eligible-anchor
#      supply).
#   5. ONE mutation::mutate call with ALL records (mol delete original + mol
#      new combined + tag sentinels -> NEW game_molid, monotonic > old).
#      Residue records ride the 3rd argument (17.2-04: non-empty ->
#      tag_sentinels_mixed, CA-only beta -- NEVER tag_sentinels on a residue
#      round, Pitfall C6).
#   6. backup::apply on the NEW game_molid (SC4 forward: restore reps +
#      viewpoint on the game_molid -- viewmaster-style; NO mol ops,
#      state-only).
#   7. registry::reconstruct_from_sentinels ONCE (1-arg; the DI command
#      prefix below), then split the sentinel indices by tier:
#      fetch_hider_indices returns file order == record order and the
#      records were emitted simple-first (write_combined_pdb writes the
#      simple records before the residue records), so tier k owns the
#      sorted index slice at its cumulative ACTUAL INDEX-COUNT offsets
#      (17.2-09: a residue tier contributes 1 fetch index per hider -- its
#      CA -- not 5 per record; no extra molinfo).
#   8. hiders::stamp_tier_codes BEFORE add_hider_reps (ORDERING CONTRACT: a
#      static single-frame molecule never re-evaluates cached rep selections
#      on an atom-field change -- a rep added before the user3 stamp would
#      cache an empty selection forever).
#   9. hiders::add_hider_reps with the {code style-args} spec table (AFTER
#      backup::apply -- base numreps deterministic; the 2N hider reps land
#      LAST: base..base+2N-1; Pitfall 9).
#  10. registry::assign_reps (ONE bulk call -- P8: NEVER a per-tier
#      reconstruct loop, which would clear prior tiers).
#  11. The resid-block registration (17.2-09, ONE registry call AFTER
#      reconstruct + assign_reps -- validation needs _records populated):
#      each residue tier's record resids zip with its fetch-list index
#      slice -> the fake-resid -> CA map the on_pick fallback consults.
#      Skipped entirely for rounds with no residue tier. game_state's shape
#      is UNCHANGED (4 keys) -- the registry holds the block.
# The resulting game_state is STASHED in the namespace var current_state
# (on_pick's data source) before being returned.
proc ::biochemeleon::game::start_game {molid hider_count {per_rep {}} {lock_scene 0}} {
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
    # 2. Lock-scene detection from THIS round's own snapshot reps (ordering
    #    step 2). The guard above cleaned any prior round first, so the
    #    snapshot is structurally free of game reps; rep_tiers' sentinel
    #    filter is defense-in-depth (research RQ1.4/P5).
    set detected [::biochemeleon::rep_tiers::scene_reps_to_per_rep [dict get $snapshot reps]]
    # 3. Warn (non-blocking, v1 under-generation parity) for requested tiers
    #    with no generator -- compared against the CALLER's per_rep keys,
    #    captured BEFORE resolve (the resolved dict only holds implemented
    #    tiers). Non-dict input -> no keys (catch-guarded).
    set per_rep_in $per_rep
    if {[catch {dict keys $per_rep_in} in_keys]} {
        set in_keys [list]
    }
    foreach r $in_keys {
        if {"" eq [::biochemeleon::rep_tiers::tier_kind $r]} {
            catch {vmdcon -warn "bioCHEMeleon: rep '$r' has no generator yet -- dropped from this round"}
        }
    }
    # 4. Resolve the EFFECTIVE per_rep (lock-scene restriction / randomize /
    #    drop-overflow clamp) and its P9 effective total.
    set per_rep [::biochemeleon::rep_tiers::resolve_per_rep $hider_count $per_rep $detected $lock_scene]
    set eff_total [::biochemeleon::rep_tiers::effective_total $per_rep]
    # 5. Ordered active-tier table {code style count} (GAME_REPS order,
    #    1-based codes -- the code is only a discriminator; the registry's
    #    rep field carries the GAME_REPS name).
    set tiers [::biochemeleon::rep_tiers::tiers_from_per_rep $per_rep]
    # 6. Per-tier placement loop (GAME_REPS order). occ_hiders accumulates
    #    ALL previously-placed hider positions this round as {x y z} triples
    #    (extracted from the prior simple 5-field {name element x y z}
    #    records and from each residue record's CA -- the 17.1-05
    #    occupied_hiders contract) so a later bonded/residue tier keeps its
    #    distance from earlier hiders. tier_idx_counts tracks the ACTUAL
    #    FETCH-INDEX count per tier, parallel to $tiers (a tier may
    #    under-generate: make_bonded_hiders caps at the anchor count,
    #    make_residue_hiders at the eligible-anchor supply) -- the slicing
    #    currency is the fetch list (beta<0 atoms), and a residue tier
    #    contributes 1 index per hider (its CA), NOT 5 per record (Pitfall
    #    C6). tier_is_residue (1/0, parallel) drives the file-layout slicing
    #    walk below; residue_tiers keeps each residue tier's record list for
    #    the resid zip.
    set records [list]
    set residue_records [list]
    set residue_tiers [list]
    set tier_idx_counts [list]
    set tier_is_residue [list]
    set occ_hiders [list]
    set resid_used 0
    foreach t $tiers {
        lassign $t code style count
        set kind [::biochemeleon::rep_tiers::tier_kind $style]
        if {$kind eq "residue"} {
            # NEVER call ssrecalc in this flow (Pitfall C2): the load-time
            # STRIDE run already assigns the fake GAM residue its `T`
            # structure; ssrecalc is unnecessary and WIPES manual ss writes.
            # resid_start threads the 9001 block ACROSS residue tiers in one
            # round (two Cartoon-family tiers must not collide on 9001+k):
            # resid_used = residue records placed so far. Fully-qualified
            # call-time read -- game.tcl sources NOTHING; splice.tcl is
            # loaded because mutation sources it.
            set resid_start [expr {$::biochemeleon::splice::RESID_BASE + $resid_used}]
            set rrecs [::biochemeleon::mutation::make_residue_hiders $molid $count $occ_hiders $resid_start]
            incr resid_used [llength $rrecs]
            # occ_hiders gains each record's CA position (atoms[1] -- the
            # N/CA/C/O/CB order guarantees the CA sits at index 1).
            foreach r $rrecs {
                lassign $r fch frid fatoms
                lassign [lindex $fatoms 1] fnm fel fx fy fz
                lappend occ_hiders [list $fx $fy $fz]
            }
            lappend tier_idx_counts [llength $rrecs]
            lappend tier_is_residue 1
            if {[llength $rrecs] > 0} {
                # SEPARATE accumulation (must-have truth 1): residue records
                # ride mutate's 3rd arg, NOT the simple-records list.
                lappend residue_records {*}$rrecs
                lappend residue_tiers $rrecs
            }
        } else {
            if {$kind eq "free"} {
                set recs [::biochemeleon::mutation::make_placeholder_hiders $molid $count]
            } elseif {$kind eq "bonded"} {
                set recs [::biochemeleon::mutation::make_bonded_hiders $molid $count $occ_hiders]
            } else {
                # Defense: resolve_per_rep restricts to implemented tiers, so
                # an empty kind never reaches here -- skip with the warning.
                catch {vmdcon -warn "bioCHEMeleon: rep '$style' has no generator yet -- skipped"}
                lappend tier_idx_counts 0
                lappend tier_is_residue 0
                continue
            }
            foreach r $recs {
                lassign $r nm el x y z
                lappend occ_hiders [list $x $y $z]
            }
            lappend records {*}$recs
            lappend tier_idx_counts [llength $recs]
            lappend tier_is_residue 0
        }
    }
    # 7. ONE mutate call: mol delete original + mol new combined + tag
    #    sentinels -> new game molid (monotonic > old). The residue records
    #    ride the 3rd arg (17.2-04): non-empty -> mutate dispatches to
    #    tag_sentinels_mixed (CA-only beta on the residue CAs) -- NEVER
    #    tag_sentinels on a residue round (it would beta-stamp all 5 fake
    #    atoms per residue, Pitfall C6). Empty -> the byte-unchanged simple
    #    path.
    set game_molid [::biochemeleon::mutation::mutate $molid $records $residue_records]
    # 8. SC4 forward: re-apply saved reps + viewpoint to the NEW game_molid
    #    (viewmaster-style; state-only).
    ::biochemeleon::backup::apply $snapshot $game_molid
    # 9. Reconstruct the registry from sentinels -- ONCE, 1-arg (P8: NEVER a
    #    per-tier reconstruct loop; a second call would CLEAR prior tiers,
    #    probe1 P17D). CRITICAL: [list apply {lambda} $game_molid] is a
    #    COMMAND-PREFIX VALUE (the {expand} in reconstruct_from_sentinels
    #    invokes it). NEVER [apply {lambda} $game_molid] -- that EVALUATES
    #    immediately and returns the id-list value, which [{*}] would then
    #    run as a command -> "invalid command name <first-index>" (the 13-01
    #    DI bug, probe-verified in 15-RESEARCH-registry-game).
    ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{molid} {
        set sel [atomselect $molid "resname GAM and beta < 0"]
        set ids [$sel get index]
        $sel delete
        return $ids
    }} $game_molid]
    # 10. Split the sentinel indices by tier: fetch_hider_indices returns
    #     file order == record order (probe3) and the combined PDB was
    #     emitted SIMPLE-FIRST (write_combined_pdb writes $records before
    #     $residue_records -- residue records appended after simple records,
    #     continuing serial), so the fetch list is sliced by walking the
    #     tiers in FILE-LAYOUT order: all simple (free/bonded) tiers in
    #     GAME_REPS order, then all residue tiers in GAME_REPS order. A
    #     plain GAME_REPS-order walk would mis-slice mixed rounds where a
    #     residue tier precedes a simple tier (Cartoon < Points) -- the
    #     residue tier would steal the simple tier's leading indices. Each
    #     tier's slice is contiguous because the records were concatenated
    #     in exactly this two-block order. tier_of = {code -> index list}
    #     (empty slices skipped: stamping an empty selection would error);
    #     idx_to_rep = {index -> GAME_REPS style name}; residue_slices
    #     (parallel to residue_tiers -- same residue-tier walk order, same
    #     non-empty condition) feeds the resid zip below.
    set idxs [::biochemeleon::mutation::fetch_hider_indices $game_molid]
    set tier_of [dict create]
    set idx_to_rep [dict create]
    set residue_slices [list]
    set off 0
    foreach pass [list 0 1] {
        foreach t $tiers cnt $tier_idx_counts isr $tier_is_residue {
            if {$isr != $pass} { continue }
            lassign $t code style count
            set slice [list]
            for {set i 0} {$i < $cnt} {incr i} {
                set idx [lindex $idxs $off]
                lappend slice $idx
                dict set idx_to_rep $idx $style
                incr off
            }
            if {[llength $slice] > 0} {
                dict set tier_of $code $slice
                if {$pass == 1} {
                    lappend residue_slices $slice
                }
            }
        }
    }
    # 11. Stamp the user3 tier codes BEFORE adding the reps (ORDERING
    #     CONTRACT -- ordering step 8; see hiders.tcl's header).
    ::biochemeleon::hiders::stamp_tier_codes $game_molid $tier_of
    # 12. Add ONE hidden/found rep PAIR per tier (2N reps) AFTER backup::apply
    #     (ordering step 9 -- base numreps deterministic, hider reps land
    #     LAST). Specs carry the style args (DynamicBonds -> {DynamicBonds
    #     1.6}, the spurious-bond rule).
    set specs [list]
    foreach t $tiers {
        lassign $t code style count
        lappend specs [list $code {*}[::biochemeleon::rep_tiers::style_args $style]]
    }
    ::biochemeleon::hiders::add_hider_reps $game_molid $specs
    # 13. Multi-tier registry stamping: ONE bulk assign_reps (P8).
    ::biochemeleon::registry::assign_reps $idx_to_rep
    # 14. Resid-block registration (17.2-09, ONE call -- the multi-atom pick
    #     fallback's pure half): zip each residue tier's record resids with
    #     its fetch-list index slice, both in record/file order within the
    #     tier (residue k's resid = resid_start + k in acceptance order ==
    #     file order; slice[j] is that record's CA). AFTER reconstruct +
    #     assign_reps: the atomic validate-then-replace needs every index in
    #     _records. Rounds with no residue tier skip the call entirely; the
    #     block is wholesale-replaced per round and cleared by cleanup's
    #     registry::reset.
    set resid_map [dict create]
    foreach rrecs $residue_tiers slice $residue_slices {
        foreach r $rrecs idx $slice {
            lassign $r fch frid fatoms
            dict set resid_map $frid $idx
        }
    }
    if {[dict size $resid_map] > 0} {
        ::biochemeleon::registry::register_resid_block $resid_map
    }
    # Build the game_state (15-05 shape + the additive per_rep key;
    # hider_count = the EFFECTIVE total, P9), STASH it for on_pick
    # (pick_bridge forwards only the index -- game.tcl owns its own state),
    # then return it.
    set gs [dict create game_molid $game_molid hider_count $eff_total snapshot $snapshot per_rep $per_rep]
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
#
# 17.1-06: per_rep is passed through SYMMETRICALLY (the round replays its own
# tier distribution instead of re-randomizing). Defensive reads: game_state
# has NO lock_scene key (the 4-key shape) -- the stashed per_rep already
# encodes the resolved lock-scene restriction (resolve_per_rep keeps an
# explicit per_rep verbatim when lock_scene=0), so the defensive lock_scene
# read always yields 0, which is moot for the distribution (17.1-06
# must-haves truth).
proc ::biochemeleon::game::restart {game_state} {
    set hider_count [dict get $game_state hider_count]
    if {[dict exists $game_state per_rep]} {
        set per_rep [dict get $game_state per_rep]
    } else {
        set per_rep [list]
    }
    if {[dict exists $game_state lock_scene]} {
        set lock_scene [dict get $game_state lock_scene]
    } else {
        set lock_scene 0
    }
    set molid [::biochemeleon::game::cleanup $game_state]
    return [::biochemeleon::game::start_game $molid $hider_count $per_rep $lock_scene]
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

# _resolve_pick {idx} -> the registered hider index to score, or "".
#
# PRIVATE pick resolver (17.2-09): the single place a raw clicked index
# becomes a scoring target. Two stages, in order:
#   (a) DIRECT HIT: the clicked atom IS a registered hider -- the Phase-16
#       path, byte-compatible (simple-tier hiders are single atoms and are
#       always registered, so simple rounds resolve here and never reach
#       (b)).
#   (b) RESID-BLOCK FALLBACK (research SS7.1 -- the v2 analog of v1's
#       get_altconf_by_resv dual lookup): only the fake residue's CA carries
#       the beta sentinel, so a cartoon-bump click can deliver the
#       residue's N/C/O/CB index -- an atom that is NOT registered. The
#       clicked atom's resid is read on the game molecule (game.tcl is the
#       mol layer; the registry stays pure) and consulted against the
#       round's registered fake-resid -> CA block: a hit re-targets scoring
#       to the registered CA, a miss ("") stays a Miss!. Real demo atoms
#       have resid << 9001 and never appear in the block, so a direct click
#       on a real atom still misses. The stash guard (empty current_state)
#       returns "" before the selection is ever built.
# The selection handle is always deleted (dangling selections leak and
# return stale data silently -- AGENTS.md).
proc ::biochemeleon::game::_resolve_pick {idx} {
    variable current_state
    # (a) Direct hit: registered hider -> score it as-is.
    if {[::biochemeleon::registry::is_hider $idx]} {
        return $idx
    }
    # Stash guard: no round in flight -> nothing to resolve (and no game
    # molecule to read the resid from).
    if {[dict size $current_state] == 0} {
        return ""
    }
    # (b) Fallback: clicked atom's resid on the game molecule -> the
    # registered fake-resid -> CA block. Single-keyword get (multi-keyword
    # get returns per-atom lists -- Pitfall 5).
    set sel [atomselect [dict get $current_state game_molid] "index $idx"]
    set rid [lindex [$sel get resid] 0]
    $sel delete
    return [::biochemeleon::registry::hider_for_resid $rid]
}

# on_pick {idx} -> {}.
#
# The click-scoring controller (v1 game.py on_pick 1:1, 04-03). Called by
# pick_bridge::_on_event with ONE argument: the 0-based atom index (the
# registry key). The game_state is NOT passed in -- this proc reads the
# current_state namespace var stashed by start_game.
#
# PICK RESOLUTION (17.2-09): the raw index is resolved FIRST via
# _resolve_pick -- a direct registered hit, or the resid-block fallback
# that re-targets a cartoon-bump click on a fake residue's N/C/O/CB to the
# residue's registered CA (only the CA carries the beta sentinel, so only
# the CA is registered; the found-visual marks the CA alone -- the
# CA-only design, research SS7.2; the 5-sphere polish is explicitly NOT
# built).
#
# THREE-WAY GUARD (caller-side; registry stays the single source of truth,
# LOOP-02. registry::mark_found is a SILENT idempotent overwrite -- probe F19
# / Pitfall 5 -- so the guard MUST live here, BEFORE mark_found; status_of of
# an unregistered index is "" not an error):
#   unresolved ""     -> "Miss!" log only (LOOP-01: no harm)
#   status "found"    -> "Already found!" log only (no double-count)
#   status "hidden"   -> mark_found_visual + mark_found + "Found one! N
#                        remaining" + remaining callback -> win check (LOOP-03)
# All three run on the RESOLVED index.
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
        # 1. Resolve the pick (17.2-09): direct registered hit, or the
        #    resid-block fallback re-targeting a fake-residue N/C/O/CB
        #    click to its registered CA. Unresolved -> miss (LOOP-01).
        set hit_idx [::biochemeleon::game::_resolve_pick $idx]
        if {$hit_idx eq ""} {
            catch {{*}$_cb_log [::biochemeleon::game_logic::log_append miss ""]}
            return
        }
        # 2. Already found -> log only (no double-count; LOOP-02).
        if {[::biochemeleon::registry::status_of $hit_idx] eq $::biochemeleon::registry::HIDER_STATUS_FOUND} {
            catch {{*}$_cb_log [::biochemeleon::game_logic::log_append already ""]}
            return
        }
        # 3. Hidden hider: visual mark on the RESOLVED index (user2 flag +
        #    the modselect re-assert -- one green sphere at the CA, the
        #    CA-only design), registry mark, log + remaining callback.
        ::biochemeleon::hiders::mark_found_visual [dict get $current_state game_molid] $hit_idx
        ::biochemeleon::registry::mark_found $hit_idx
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
