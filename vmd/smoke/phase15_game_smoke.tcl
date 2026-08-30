# vmd/smoke/phase15_game_smoke.tcl
# Headless smoke for Phase 15 Plan 04: game.tcl composition root (orchestration).
# Proves the full start_game -> cleanup -> restart round-trip + game_state shape:
#   start_game : game_state dict {game_molid hider_count snapshot}; game_molid has
#                424+2=426 atoms; exactly 2 sentinels via the canonical selector;
#                count_hiders==2 (registry reconstructed via the apply-lambda DI);
#                reps restored on game_molid (SC4 forward -- backup::apply after
#                mutate).
#   cleanup    : restored molid has 424 atoms; 0 sentinels; count_hiders==0
#                (registry reset); reps restored (SC2); the LIVE game_molid is
#                DELETED (backup::restore $snapshot $game_molid -- proves restore
#                deleted the live game_molid, NOT the dead snapshot.molid that
#                mutation::mutate already deleted during start_game).
#   restart    : cleanup + start_game with the same hider_count -> fresh
#                game_state with 426 atoms + 2 sentinels + count_hiders==2.
#
# Uses 1znf (424 atoms, small + fast) with 2 hiders. Sources lib files in dep
# order directly (mirrors the entry's source order, NOT the entry itself --
# avoids GUI/dialog baggage): setup_state, registry, demos, backup, mutation,
# game. (registry is Plan 01; backup is Plan 03; mutation is Plan 02; all merged
# in Wave 1 before this Wave-2 plan.)
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd] (VMD
# cwd = staging root) to locate the lib files, then `source` them. Each lib's
# own [info script] then works correctly because it was `source`d (not `-e`d).
# This is the verified Phase 13+ pattern; do NOT change.
#
# VMD does NOT propagate tcl exit codes (Phase 13 Pitfall 4) -> the WSL runner
# greps the BCHM_SMOKE_RESULT marker line, NEVER $? (VMD always exits 0). VMD -e
# catches top-level errors and continues, so a mid-script error does NOT prevent
# a false-PASS marker -- this smoke wraps each op in catch to record FAIL=
# entries, AND the runner scans for ERROR) lines.
#
# Tcl 8.5 only. Every atomselect is $sel delete'd (Pitfall 3 -- atomselect leaks;
# a dangling selection on a deleted molecule returns STALE data silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Defensive init of cross-step vars so a failed earlier step never causes a
# top-level "no such variable" substitution error that would mask the real FAIL.
set m -1
set saved_numreps -1
set game_molid -1

# ---- Source the lib files in dependency order ([pwd]-relative; [info script]
#      is empty under -e). Mirrors the entry's source order minus dialog.tcl.
#      demos.tcl + mutation.tcl each re-source setup_state.tcl themselves
#      (harmless constant re-init); backup.tcl + game.tcl source nothing;
#      registry.tcl is sourced ONCE (re-sourcing would WIPE _records).
#      Phase 16 (16-08): hiders.tcl is sourced too -- start_game now calls
#      hiders::add_hider_reps (call-time resolution needs the namespace). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    demos        [file join [pwd] vmd lib demos.tcl] \
    backup       [file join [pwd] vmd lib backup.tcl] \
    mutation     [file join [pwd] vmd lib mutation.tcl] \
    hiders       [file join [pwd] vmd lib hiders.tcl] \
    game         [file join [pwd] vmd lib game.tcl]] {
    if {![file exists $path]} {
        lappend failures "${nm}_not_found:$path"
    } elseif {[catch {source $path} err]} {
        lappend failures "${nm}_source_error:$err"
    }
}

# ---- 1. Load 1znf (424 atoms) + add a VDW rep so numreps > 1 is restorable. ----
if {[catch {::biochemeleon::demos::load_demo 1znf} m]} {
    _bail load_demo $m
} else {
    set n0 [molinfo $m get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    # Add a VDW rep (default load is Lines only -> 1 rep; addrep -> 2 reps).
    catch {mol representation VDW}
    if {[catch {mol addrep $m} adderr]} { _bail addrep $adderr }
    set saved_numreps [molinfo $m get numreps]
    if {$saved_numreps != 2} { _bail saved_numreps "exp=2 got=$saved_numreps" }
}

# ---- 2. start_game: 2 placeholder hiders -> game_state dict. ----
if {![catch {::biochemeleon::game::start_game $m 2} gs]} {
    # game_state shape: 3 keys.
    if {![dict exists $gs game_molid]} { _bail gs_key_game_molid "missing" }
    if {![dict exists $gs hider_count]} { _bail gs_key_hider_count "missing" }
    if {![dict exists $gs snapshot]} { _bail gs_key_snapshot "missing" }
    if {[dict get $gs hider_count] != 2} {
        _bail gs_hider_count "exp=2 got=[dict get $gs hider_count]"
    }
    set game_molid [dict get $gs game_molid]
    # game_molid monotonic > original m (Pitfall 4 -- molids never reused).
    if {$game_molid <= $m} { _bail game_molid_monotonic "game_molid=$game_molid <= m=$m" }
    # 424 + 2 = 426 atoms on the combined molecule.
    set n1 [molinfo $game_molid get numatoms]
    if {$n1 != 426} { _bail game_atoms "exp=426 got=$n1" }
    # Exactly 2 sentinels via the canonical selector (NEVER 'beta < 0' alone).
    if {![catch {atomselect $game_molid "resname GAM and beta < 0"} sel]} {
        if {[$sel num] != 2} { _bail sentinel_count "exp=2 got=[$sel num]" }
        $sel delete
    } else { _bail sentinel_sel $sel }
    # SC3: registry reconstructed from sentinels via the apply-lambda DI ->
    # count_hiders == 2 (Plan 01 merged in Wave 1).
    set ch [::biochemeleon::registry::count_hiders]
    if {$ch != 2} { _bail registry_count "exp=2 got=$ch" }
    # SC4 forward: backup::apply restored the saved reps on the game_molid.
    # Phase 16 (16-08): start_game now ALSO adds the 2 hider reps
    # (hiders::add_hider_reps after apply -- research SS5.5), so the game
    # molid carries saved_numreps + 2. The restored molid below still has
    # EXACTLY the saved reps (cleanup restores the original, no hider reps).
    set gn [molinfo $game_molid get numreps]
    if {$gn != $saved_numreps + 2} {
        _bail game_numreps "exp=$saved_numreps + 2 got=$gn"
    }
} else {
    _bail start_game $gs
}

# ---- 3. cleanup: restore the original + clear the registry. ----
if {![catch {::biochemeleon::game::cleanup $gs} restored]} {
    # restored molid monotonic > game_molid.
    if {$restored <= $game_molid} {
        _bail restored_monotonic "restored=$restored <= game_molid=$game_molid"
    }
    # 424 atoms (no hiders).
    set n2 [molinfo $restored get numatoms]
    if {$n2 != 424} { _bail restored_atoms "exp=424 got=$n2" }
    # 0 sentinels remain.
    if {![catch {atomselect $restored "resname GAM and beta < 0"} sel2]} {
        if {[$sel2 num] != 0} { _bail restored_sentinels "exp=0 got=[$sel2 num]" }
        $sel2 delete
    } else { _bail restored_sentinel_sel $sel2 }
    # SC3: registry cleared after cleanup (reset).
    set ch2 [::biochemeleon::registry::count_hiders]
    if {$ch2 != 0} { _bail registry_after_cleanup "exp=0 got=$ch2" }
    # SC2: reps restored on the restored molid.
    set rn [molinfo $restored get numreps]
    if {$rn != $saved_numreps} { _bail restored_numreps "exp=$saved_numreps got=$rn" }
    # CRITICAL: the LIVE game_molid was DELETED by cleanup's
    # backup::restore $snapshot $game_molid (NOT the dead snapshot.molid). If it
    # is still alive, restore deleted the wrong molid -> leak (false-pass guard).
    if {![catch {molinfo $game_molid get numatoms} ghost]} {
        _bail game_molid_leaked "game_molid $game_molid still alive (numatoms=$ghost)"
    }
} else {
    _bail cleanup $restored
}

# ---- 4. restart round-trip: fresh load -> start_game -> restart -> assert. ----
# restart = cleanup + start_game with the SAME hider_count on the restored molid.
if {[catch {::biochemeleon::demos::load_demo 1znf} m2b]} {
    _bail load_demo2 $m2b
} elseif {[catch {::biochemeleon::game::start_game $m2b 2} gs2]} {
    _bail start_game2 $gs2
} elseif {[catch {::biochemeleon::game::restart $gs2} gs3]} {
    _bail restart $gs3
} else {
    if {![dict exists $gs3 game_molid]} { _bail gs3_key_game_molid "missing" }
    set gm3 [dict get $gs3 game_molid]
    set n3 [molinfo $gm3 get numatoms]
    if {$n3 != 426} { _bail restart_atoms "exp=426 got=$n3" }
    if {![catch {atomselect $gm3 "resname GAM and beta < 0"} sel3]} {
        if {[$sel3 num] != 2} { _bail restart_sentinels "exp=2 got=[$sel3 num]" }
        $sel3 delete
    } else { _bail restart_sentinel_sel $sel3 }
    set ch3 [::biochemeleon::registry::count_hiders]
    if {$ch3 != 2} { _bail restart_registry_count "exp=2 got=$ch3" }
}

# ---- Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
