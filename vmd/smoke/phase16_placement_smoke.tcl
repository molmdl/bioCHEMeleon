# vmd/smoke/phase16_placement_smoke.tcl
# Phase-16 (16-07) headless smoke: proves make_placeholder_hiders' REAL sphere
# placement end-to-end through the unchanged game.tcl call site. The Phase-15
# body-swap target now places hiders at uniform-random points inside the
# molecule's bounding box (`measure minmax` -> the pure 16-01 sampler) instead
# of center+jitter. Proves:
#   1. REAL placement geometry: every hider coordinate on the game molecule
#      lies within the ORIGINAL's real-atom bbox (+/- 0.001 epsilon -- hider
#      coords are written %8.3f then re-parsed, so a value just under max can
#      round up by <= 0.0005). The original's real-atom extents == the game
#      molecule's real-atom extents (hiders are APPENDED by the PDB-rebuild;
#      real atoms untouched), so the pre-game bbox is the right reference.
#   2. The 5 points are NOT all identical (uniform-random smoke -- a broken
#      sampler that returns a constant point would fail this).
#   3. Frozen Phase-15 contract intact: exactly 5 sentinels via the canonical
#      selector "resname GAM and beta < 0" at indices 555-559 (555+5=560
#      atoms), names G01..G05 (2-digit zero-padded) -- {molid count}
#      signature and {name x y z} record shape unchanged.
#   4. Registry + sentinel regression (Phase-15 behavior holds): count_hiders
#      == 5 after start (is_hider 555 true, is_hider 0 false); cleanup
#      restores 555 atoms, resets the registry to 0, and DELETES the live
#      game_molid (leak guard -- catch {molinfo ...} must fail).
# The blending VISUAL is 16-12's GUI human-verify; this smoke proves geometry.
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself -- avoids GUI/dialog baggage): setup_state, registry, demos, backup,
# mutation, game. registry is sourced EXACTLY ONCE (re-sourcing would WIPE
# _records); demos + mutation re-source setup_state themselves (harmless
# constant re-init). mutation.tcl sources generators.tcl itself (the 16-07
# source line -- exercising it here IS part of the test).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT propagate
# exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD
# -e catches top-level errors and CONTINUES (possible false-PASS) -> every
# step is wrapped in catch + _bail, and the runner scans the FULL log for
# ERROR) / bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set game_molid -1
set gs [list]
set xmin 0.0; set ymin 0.0; set zmin 0.0
set xmax 0.0; set ymax 0.0; set zmax 0.0
set have_bbox 0

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's source order minus the
#      GUI files. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry     [file join [pwd] vmd lib registry.tcl] \
    demos        [file join [pwd] vmd lib demos.tcl] \
    backup       [file join [pwd] vmd lib backup.tcl] \
    mutation     [file join [pwd] vmd lib mutation.tcl] \
    game         [file join [pwd] vmd lib game.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# ---- 1. SETUP: load 1k8p (555 atoms) + compute the ORIGINAL bbox BEFORE
#      start_game (probe-verified minmax shape: {{xmin ymin zmin}
#      {xmax ymax zmax}} -- 2 elements, each a 3-float list). ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }
    if {[catch {
        set all [atomselect $orig_molid "all"]
        set mm [measure minmax $all]
        $all delete
    } merr]} {
        _bail minmax $merr
    } else {
        lassign $mm lo hi
        lassign $lo xmin ymin zmin
        lassign $hi xmax ymax zmax
        set have_bbox 1
        # Sanity: the box is well-formed (min <= max per axis) so the
        # containment asserts below mean something.
        if {$xmin > $xmax || $ymin > $ymax || $zmin > $zmax} {
            _bail bbox_shape "min>max (lo=$lo hi=$hi)"
            set have_bbox 0
        }
    }
}

# ---- 2. START: game::start_game on 1k8p + 5 hiders -> game_state. The
#      orchestrator call site is UNCHANGED from Phase 15 (snapshot ->
#      make_placeholder_hiders -> mutate -> backup::apply -> registry DI) --
#      zero downstream edits is part of this plan's contract. ----
if {![catch {::biochemeleon::game::start_game $orig_molid 5} gs]} {
    if {[catch {dict get $gs game_molid} game_molid]} {
        _bail gs_key_game_molid "missing (gs=$gs)"
    } else {
        # game_molid monotonic > original (molids never reused).
        if {$game_molid <= $orig_molid} {
            _bail game_molid_monotonic "game_molid=$game_molid <= orig=$orig_molid"
        }
        # 3a: 555 + 5 = 560 atoms on the combined molecule.
        set n1 [molinfo $game_molid get numatoms]
        if {$n1 != 560} { _bail game_atoms "exp=560 got=$n1" }
        # 3b + 5 + 7: one sentinel selection serves count/indices/coords/names.
        # Canonical selector (NEVER 'beta < 0' alone / never exact 'beta -999').
        if {![catch {atomselect $game_molid "resname GAM and beta < 0"} sel]} {
            if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
            if {[$sel get index] ne {555 556 557 558 559}} {
                _bail sentinel_idx "got=[$sel get index]"
            }
            # 5 hiders -> small list: $sel get {x y z} is safe here (the
            # AGENTS perf rule only bars this on 100k+ atom molecules).
            set coords [$sel get {x y z}]
            if {[llength $coords] != 5} {
                _bail hider_coords "exp=5 got=[llength $coords]"
            } else {
                # 5. REAL placement: EVERY hider coordinate within
                #    [min-0.001, max+0.001] per axis (epsilon covers the
                #    %8.3f write round-trip: values < max can round up by
                #    <= 0.0005).
                if {!$have_bbox} {
                    _bail hider_bounds "skipped (no valid bbox)"
                } else {
                    set k 0
                    foreach c $coords {
                        incr k
                        lassign $c hx hy hz
                        if {$hx < [expr {$xmin - 0.001}] || $hx > [expr {$xmax + 0.001}]} {
                            _bail hider_x_bounds "hider $k x=$hx outside \[$xmin .. $xmax\]"
                        }
                        if {$hy < [expr {$ymin - 0.001}] || $hy > [expr {$ymax + 0.001}]} {
                            _bail hider_y_bounds "hider $k y=$hy outside \[$ymin .. $ymax\]"
                        }
                        if {$hz < [expr {$zmin - 0.001}] || $hz > [expr {$zmax + 0.001}]} {
                            _bail hider_z_bounds "hider $k z=$hz outside \[$zmin .. $zmax\]"
                        }
                    }
                    # 6. NOT all identical (a constant-point sampler would
                    #    fail; numeric compare, 1e-9 tolerance).
                    lassign [lindex $coords 0] x0 y0 z0
                    set differs 0
                    foreach c $coords {
                        lassign $c hx hy hz
                        if {[expr {abs($hx - $x0) > 1e-9}] || \
                            [expr {abs($hy - $y0) > 1e-9}] || \
                            [expr {abs($hz - $z0) > 1e-9}]} {
                            set differs 1
                            break
                        }
                    }
                    if {!$differs} {
                        _bail degenerate_points "all 5 hider points identical"
                    }
                }
            }
            # 7. Frozen record shape: names G01..G05 (2-digit zero-padded).
            if {[$sel get name] ne {G01 G02 G03 G04 G05}} {
                _bail hider_names "got=[$sel get name]"
            }
            $sel delete
        } else { _bail sentinel_sel $sel }
        # 8. Registry regression (Phase-15 behavior holds): reconstructed
        #    from sentinels via the DI; count == 5; membership correct.
        set ch [::biochemeleon::registry::count_hiders]
        if {$ch != 5} { _bail registry_count "exp=5 got=$ch" }
        if {![::biochemeleon::registry::is_hider 555]} { _bail is_hider_true 555 }
        if {[::biochemeleon::registry::is_hider 0]} { _bail is_hider_false "idx 0" }

        # ---- 9. CLEANUP: game::cleanup -> restore original + registry reset
        #      (backup::restore $snapshot $game_molid + registry::reset). ----
        if {![catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
            set n2 [molinfo $restored_molid get numatoms]
            if {$n2 != 555} { _bail restored_atoms "exp=555 got=$n2" }
            set ch2 [::biochemeleon::registry::count_hiders]
            if {$ch2 != 0} { _bail registry_after_cleanup "exp=0 got=$ch2" }
            # Leak guard: the LIVE game_molid must be DELETED (if it is
            # still alive, restore deleted the WRONG molid -> the 560-atom
            # game molecule leaked).
            if {![catch {molinfo $game_molid get numatoms} ghost]} {
                _bail game_molid_leaked "game_molid $game_molid still alive (numatoms=$ghost)"
            }
        } else {
            _bail cleanup $restored_molid
        }
    }
} else {
    _bail start_game $gs
}

# ---- 10. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
