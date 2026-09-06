# vmd/smoke/phase17_e2e_smoke.tcl
# Phase-17.2 (17.2-10) headless smoke -- the phase's SC3 acceptance: a
# cartoon-blend round is PLAYABLE end-to-end through the PUBLIC surface
# (game::start_game -> game::on_pick -> win -> game::cleanup), driven
# headlessly on demo 1znf (424 atoms). Direct on_pick calls with atom
# indices are the 16-11 capstone precedent (text mode cannot fire real
# picks; the C-side pick path is 17.2-12's GUI checkpoint).
#
# Proves:
#   A. CARTOON ROUND (per_rep {Cartoon 2 Trace 1}, 4-arg start_game):
#      1. The REQUEST is pinned: hider_count 3 (the EFFECTIVE total,
#         P9), per_rep stashed verbatim GAME_REPS-ordered {Cartoon 2
#         Trace 1}, dict shape UNCHANGED (4 keys), stash populated.
#         The LAYOUT is draw-adaptive (splice::select_anchors samples
#         exactly n candidates then greedy-accepts at 5.0 A, so a
#         residue tier may under-generate -- documented "May return
#         fewer than n"): the observed sentinel set (chain-classified:
#         simple hiders are hard-coded chain G, residue records the
#         anchor's chain) pins registry == sentinel count, C in
#         1..3, the FIRST residue block opening at 424 (CA 425 --
#         no simple records in this round), 4-5 atom strides between
#         consecutive CAs (CB omitted only for CB-less anchors), the
#         last block running to end-of-file, and the idealized
#         424 + 3x5 = 439 pin asserted whenever the draw generated in
#         full.
#      2. Resid block (registry read procs): hider_for_resid
#         9001+k == the k-th CA in file order; 9999 -> "".
#      3. State driven to playing (round_reset -> begin_countdown ->
#         4x countdown_tick -> begin_play -- the exact game_logic
#         transition the Game tab's GO button drives; on_pick is a
#         NO-OP unless state == playing), state asserted playing.
#      4. Find ALL generated hiders through on_pick ONLY:
#           - the FIRST CA picked DIRECT (registered -- the Phase-16
#             path) -> remaining C-1, "Found one! C-1 remaining",
#             user2(CA) > 0;
#           - every LATER CA via a FALLBACK click on its N (index-1,
#             never registered) -> the resid-block fallback resolves
#             the CA: status_of(CA) found, user2(CA) > 0, user2(N)
#             == 0 (the FALLBACK marks the CA, never the clicked
#             atom);
#           - the LAST find -> remaining 0 -> WIN: state == won,
#             timer FROZEN (two timer_elapsed reads equal and == the
#             win_cb elapsed), win line "You found all C hiders in
#             ..." logged, win_cb fired exactly once with
#             {elapsed C}. With a full 3-record draw this is exactly
#             425 direct / 429 N / 436 C.
#      5. Post-win pick guard: on_pick 424 (residue-1's N; unfound --
#         the state gate fires FIRST) -> NO state change, NO extra log,
#         NO extra win.
#      6. Cleanup (game::cleanup $gs) -- the no-leak contract: registry
#         count 0 AND hider_for_resid 9001 == "" (block cleared); game
#         molid DEAD; restored original 424 atoms; numreps == pre-start;
#         the on_pick stash cleared.
#   B. RANDOMIZE INVARIANT ROUND (2-arg start_game, hider_count 5):
#      7. P9 + quick-008 invariants on the OBSERVED draw (the 17.1-06
#         step-8 precedent): hider_count == effective_total(per_rep),
#         1 <= sum <= 5 (randomize_per_rep DRAWS the counts -- it may
#         underspend, never hard == 5), every per_rep /
#         remaining_by_rep key a GAME_REPS name. THE EXACT ATOM-COUNT
#         INVARIANT from the OBSERVED generation through the public
#         sentinel selector: simple hiders (free OR bonded) are ONE
#         atom each, residue blocks are contiguous AFTER all simple
#         records (simple-first file layout) with CA at block start + 1
#         and 4-5 atoms per block (CB omitted when the anchor lacks
#         it), every generated hider registered (registry == sentinel
#         count), the round total never exceeds the requested sum
#         (under-generation tolerance: 28-residue 1znf can reject
#         anchors), and the idealized orig + simple x 1 + residue x 5
#         formula asserted EXACTLY whenever the draw generated in full
#         with every anchor carrying CB.
#      8. One find through whichever path applies (derived at runtime
#         from the sentinel layout: a chain!=G sentinel is a residue
#         record's CA -> pick its N (index-1) -> fallback; else every
#         sentinel is a chain-G simple hider -> the first is registered
#         -> direct): remaining R -> R-1, the CA (fallback) or the
#         hider (direct) marked found.
#      9. Cleanup gs2: registry 0, block cleared, restored 424 atoms.
#  10. Marker + exit (BCHM_SMOKE_RESULT; the runner scans the FULL log).
#
# NO TEST HOOKS: the finds drive ONLY game::start_game / game::on_pick /
# game::cleanup (+ game::set_callbacks, the public callback registration)
# and registry READ procs (is_hider/status_of/count_hiders/
# count_remaining/remaining_by_rep/hider_for_resid). NO calls into the
# lib's hider-generation/stamp/rep internals (the mutation generator and
# hiders stamp/rep procs are banned -- the runner greps this file for
# their names and must find ZERO).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the
# entry itself): setup_state, registry, generators, game_logic, rep_tiers,
# demos, backup, mutation, hiders, game. registry is sourced EXACTLY ONCE
# (re-sourcing would WIPE _records AND the resid block).
#
# The molecule is SINGLE-FRAME: 1znf ships 2 models, so the collapse
# loader (frame-0-pinned writepdb round-trip -- the same PDB-rebuild
# pipeline the game's mutation step uses downstream) precedes each round;
# every coordinate read/write is deterministic frame-0 geometry.
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT
# propagate tcl exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT
# marker, NEVER $?; VMD -e catches top-level errors and CONTINUES
# (possible false-PASS) -> every step is wrapped in catch + _bail, and
# the runner scans the FULL log for ERROR) / bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE
# data silently).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Float read-back compare (user2 is a FLOAT -- numeric only).
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set gs [list]
set gm -1
set pre_reps -1
set gs_ok 0
set playing_ok 0
set restored_molid -1

# Recording-callback targets (globals -- the callbacks write into these).
# LOG_LOG/WINS are lists (1-arg / 2-arg lappends); REM_TICKS is a scalar
# invocation counter (remaining_cb is ZERO-arg -- {incr} is the only
# zero-arg-safe recorder).
set ::LOG_LOG [list]
set ::REM_TICKS 0
set ::WINS [list]

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). Mirrors the entry's source order minus
#      the GUI files. ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry    [file join [pwd] vmd lib registry.tcl] \
    generators  [file join [pwd] vmd lib generators.tcl] \
    game_logic  [file join [pwd] vmd lib game_logic.tcl] \
    rep_tiers   [file join [pwd] vmd lib rep_tiers.tcl] \
    demos       [file join [pwd] vmd lib demos.tcl] \
    backup      [file join [pwd] vmd lib backup.tcl] \
    mutation    [file join [pwd] vmd lib mutation.tcl] \
    hiders      [file join [pwd] vmd lib hiders.tcl] \
    game        [file join [pwd] vmd lib game.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# Collapse loader (1znf ships 2 models): frame-0-pinned writepdb
# round-trip -> a single-frame molecule.
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] e2e_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
}

# Register the list-appending callbacks BEFORE any round (the Game tab's
# set_callbacks call in start_round).
if {[catch {::biochemeleon::game::set_callbacks \
        {lappend ::LOG_LOG} {incr ::REM_TICKS} {lappend ::WINS}} cberr]} {
    _bail set_callbacks $cberr
}

# =====================================================================
# A. CARTOON ROUND (the SC3 story): Cartoon 2 + Trace 1, 4-arg
#    start_game, lock_scene 0. Both tiers are RESIDUE kind, so the
#    round has NO simple records -- pure residue layout 424..438.
# =====================================================================
if {[catch {_load_demo_1f 1znf} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    set nf0 [molinfo $orig_molid get numframes]
    if {$nf0 != 1} { _bail orig_frames "exp=1 (collapse) got=$nf0" }
    set pre_reps [molinfo $orig_molid get numreps]
    puts "E2E_INFO pre_reps=$pre_reps"
    if {[catch {::biochemeleon::game::start_game $orig_molid 3 \
            [dict create Cartoon 2 Trace 1] 0} gs]} {
        _bail start_game $gs
        puts "STARTFAIL_EI $errorInfo"
    } else {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
        } else {
            set gs_ok 1
            # A1a: the round requests 3 residue hiders (Cartoon 2 +
            #      Trace 1). The LAYOUT is draw-adaptive (the 17.2-04
            #      generator under-generation tolerance is BY DESIGN:
            #      splice::select_anchors samples exactly n candidates
            #      then greedy-accepts at 5.0 A -- two close sampled
            #      CAs reject, documented "May return fewer than n"),
            #      so the exact atom count comes from the OBSERVED
            #      sentinel layout: S one-atom simple records (none
            #      here -- both tiers are residue kind) then C residue
            #      blocks, CA at block start + 1, 4-5 atoms per block
            #      (CB omitted when the anchor lacks it).
            set n1 [molinfo $gm get numatoms]
            # A1b: hider_count == 3 (the EFFECTIVE total, P9 -- the
            #      REQUEST sum; under-generation never changes it).
            if {[catch {dict get $gs hider_count} eff]} {
                _bail gs_hider_count "missing"
            } elseif {$eff != 3} {
                _bail eff_total "exp=3 got=$eff"
            }
            # A1c: per_rep stashed VERBATIM (explicit per_rep replaces
            #      the round total, lock_scene 0), GAME_REPS-ordered
            #      keys (Cartoon precedes Trace), counts 2/1.
            if {![dict exists $gs per_rep]} {
                _bail gs_per_rep "missing"
            } else {
                set pr [dict get $gs per_rep]
                if {[catch {dict keys $pr} prk]} {
                    _bail per_rep_keys $prk
                } else {
                    if {$prk ne {Cartoon Trace}} {
                        _bail per_rep_order "got=$prk (expect GAME_REPS order: Cartoon precedes Trace)"
                    }
                    foreach {rep expn} [list Cartoon 2 Trace 1] {
                        if {[catch {dict get $pr $rep} c] || $c != $expn} {
                            _bail per_rep_$rep "exp=$expn got=$c"
                        }
                    }
                }
            }
            # A1d: game_state dict shape UNCHANGED (15-05 + additive
            #      per_rep -- 4 keys; the registry holds the resid block).
            if {[dict keys $gs] ne "game_molid hider_count snapshot per_rep"} {
                _bail gs_shape "got=[dict keys $gs]"
            }
            # A1e: the namespace stash is populated (4 keys) -- on_pick's
            #      data source (pick_bridge delivers ONLY the index).
            if {[dict size $::biochemeleon::game::current_state] != 4} {
                _bail stash_populated "exp=4 got=[dict size $::biochemeleon::game::current_state]"
            }
            # A1f: the OBSERVED sentinel layout (chain classifier --
            #      simple hiders are hard-coded chain G, residue records
            #      the anchor's chain; here BOTH tiers are residue kind,
            #      so every sentinel must be chain != G).
            set a_idx [list]
            set a_nm [list]
            set a_ch [list]
            if {[catch {atomselect $gm "resname GAM and beta < 0"} sb]} {
                _bail sentinel_sel $sb
            } else {
                set a_idx [$sb get index]
                set a_nm [$sb get name]
                set a_ch [$sb get chain]
                $sb delete
            }
            set a_c [llength $a_idx]
            foreach ac $a_ch {
                if {$ac eq "G"} {
                    _bail sentinel_chain "chain G in a cartoon-only round (residue records carry the anchor chain)"
                }
            }
            # Every generated hider registered; the round total never
            # exceeds the 3 requested and never drops to 0.
            set a_ch_regs [::biochemeleon::registry::count_hiders]
            if {$a_ch_regs != $a_c} {
                _bail reg_count "exp=$a_c (sentinels) got=$a_ch_regs"
            }
            if {$a_c > 3} { _bail reg_over "sentinels=$a_c requested=3" }
            if {$a_c < 1} { _bail reg_empty "sentinels=$a_c (round unplayable)" }
            # remaining_by_rep keys subset of {Cartoon Trace}, sum == C.
            if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
                _bail remaining_by_rep $rbr
            } else {
                set rbr_sum 0
                foreach rep [dict keys $rbr] {
                    if {[lsearch -exact {Cartoon Trace} $rep] < 0} {
                        _bail rbr_key "unexpected rep $rep"
                    }
                    incr rbr_sum [dict get $rbr $rep]
                }
                if {$rbr_sum != $a_c} {
                    _bail rbr_sum "exp=$a_c got=$rbr_sum"
                }
            }
            # Layout: fake atoms 424.. (no simple records in this
            # round); the first residue block starts AT 424, its CA at
            # 425 -- pinning the round's opening index REGARDLESS of
            # how many records generated; later CAs stride 4-5 (CB
            # omitted only for CB-less anchors); the last block runs to
            # the end of the file.
            set a_cas [list]
            set a_prev -1
            foreach ai $a_idx ac $a_ch {
                if {$ac eq "G"} { continue }
                lappend a_cas $ai
                if {$a_prev < 0} {
                    if {$ai != 425} {
                        _bail layout_first_ca "exp=425 got=$ai (cartoon-only round: block 1 opens at 424)"
                    }
                } else {
                    set alen [expr {$ai - $a_prev}]
                    if {$alen != 4 && $alen != 5} {
                        _bail layout_stride "exp 4|5 got=$alen (ca $a_prev -> $ai)"
                    }
                }
                set a_prev $ai
            }
            if {$a_c > 0} {
                set alast [expr {$n1 - $a_prev + 1}]
                if {$alast != 4 && $alast != 5} {
                    _bail layout_last "exp 4|5 got=$alast (ca=$a_prev n1=$n1)"
                }
            }
            set a_cb [expr {$n1 - 424 - 4 * $a_c}]
            if {$a_cb < 0 || $a_cb > $a_c} {
                _bail layout_atoms "n1=$n1 c=$a_c cb=$a_cb (need 0 <= cb <= $a_c)"
            }
            puts "E2E_INFO round_a_layout n1=$n1 c=$a_c cas=$a_cas cb=$a_cb (per_rep=$pr)"
            # The idealized 424 + 3x5 = 439 pin asserted whenever the
            # draw generated in full.
            if {$a_c == 3 && $a_cb == 3 && $n1 != 439} {
                _bail game_atoms "exp=439 (full generation) got=$n1"
            }
            # A2: the resid block zips 9001+k -> the k-th CA in file
            #     order (registry read procs); a miss stays "".
            set a_k 0
            foreach ai $a_cas {
                set g [::biochemeleon::registry::hider_for_resid [expr {9001 + $a_k}]]
                if {$g ne $ai} {
                    _bail resid_[expr {9001 + $a_k}] "exp=$ai got=$g"
                }
                incr a_k
            }
            if {[::biochemeleon::registry::hider_for_resid 9999] ne ""} {
                _bail resid_9999 "exp='' got=[::biochemeleon::registry::hider_for_resid 9999]"
            }

            # A3: state -> playing (round_reset -> begin_countdown ->
            #     4x countdown_tick -> begin_play -- the Game tab's GO
            #     transition; on_pick is a no-op unless playing).
            if {[catch {
                ::biochemeleon::game_logic::round_reset
                ::biochemeleon::game_logic::begin_countdown
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::begin_play
            } driveerr]} {
                _bail drive_playing $driveerr
            } else {
                set stp [::biochemeleon::game_logic::state]
                if {$stp ne "playing"} { _bail playing_state "got=$stp" }
                if {$stp eq "playing"} { set playing_ok 1 }
            }
        }
    }
}

# A4: find ALL generated hiders through on_pick ONLY -- the FIRST CA
#     clicked DIRECT (the is_hider path), every LATER CA via a FALLBACK
#     click on its N (index-1, never registered -- the resid-block
#     fallback resolves it) -- ending in the win. The find plan is
#     derived from the observed $a_cas (draw-adaptive); with a full
#     3-record draw it is exactly the plan's 425 direct / 429 N /
#     436 C sequence.
if {$gs_ok && $playing_ok} {
    set a_first [lindex $a_cas 0]
    # A4a. DIRECT CA find: the first CA IS registered (the CA-only
    #      sentinel) -- the Phase-16 direct path.
    if {[catch {::biochemeleon::game::on_pick $a_first} pa4a]} {
        _bail direct_pick_error $pa4a
    }
    set exp_r [expr {$a_c - 1}]
    set r4a [::biochemeleon::registry::count_remaining]
    if {$r4a != $exp_r} { _bail direct_remaining "exp=$exp_r got=$r4a" }
    if {[lindex $::LOG_LOG end] ne "Found one! $exp_r remaining"} {
        _bail direct_line "got=[lindex $::LOG_LOG end]"
    }
    if {[::biochemeleon::registry::status_of $a_first] ne "found"} {
        _bail direct_status "got=[::biochemeleon::registry::status_of $a_first]"
    }
    if {![catch {atomselect $gm "index $a_first"} s4a]} {
        set u2a [lindex [$s4a get user2] 0]
        if {[catch {expr {double($u2a) > 0}} oka] || !$oka} {
            _bail direct_user2 "exp>0 got=$u2a"
        }
        $s4a delete
    } else { _bail direct_sel $s4a }
    if {$::REM_TICKS != 1} { _bail direct_rem_cb "exp=1 got=$::REM_TICKS" }
    if {[llength $::WINS] != 0} { _bail direct_no_win "got=[llength $::WINS]" }

    # A4b. FALLBACK finds for every LATER residue record: click its N
    #      (ca - 1 -- NOT registered); the resid-block fallback
    #      resolves it to the registered CA. The FALLBACK marks the CA,
    #      never the clicked atom.
    set a_n 1
    foreach a_ca [lrange $a_cas 1 end] {
        set a_nidx [expr {$a_ca - 1}]
        if {[catch {::biochemeleon::game::on_pick $a_nidx} pafb]} {
            _bail fb_pick_error_$a_n $pafb
        }
        set exp_r [expr {$a_c - 1 - $a_n}]
        set rfb [::biochemeleon::registry::count_remaining]
        if {$rfb != $exp_r} { _bail fb${a_n}_remaining "exp=$exp_r got=$rfb" }
        # The line assert only applies to NON-final finds: the last
        # find's found line sits at log end-1 (the win line follows
        # it) and is checked by the win block below.
        if {$exp_r > 0
                && [lindex $::LOG_LOG end] ne "Found one! $exp_r remaining"} {
            _bail fb${a_n}_line "got=[lindex $::LOG_LOG end]"
        }
        if {[::biochemeleon::registry::status_of $a_ca] ne "found"} {
            _bail fb${a_n}_status "got=[::biochemeleon::registry::status_of $a_ca]"
        }
        if {![catch {atomselect $gm "index $a_nidx $a_ca"} sfb]} {
            lassign [$sfb get user2] u2n u2ca
            if {[catch {expr {double($u2ca) > 0}} okb] || !$okb} {
                _bail fb${a_n}_user2_ca "exp>0 got=$u2ca"
            }
            if {![_feq $u2n 0.0]} {
                _bail fb${a_n}_user2_n "exp=0 (CA-only marking) got=$u2n"
            }
            $sfb delete
        } else { _bail fb${a_n}_sel $sfb }
        if {[::biochemeleon::registry::is_hider $a_nidx]} {
            _bail fb${a_n}_n_registered "$a_nidx must NOT be registered (CA-only design)"
        }
        incr a_n
    }
    if {$::REM_TICKS != $a_c} { _bail fb_rem_cb_total "exp=$a_c got=$::REM_TICKS" }

    # A4c. THE WIN: the last find emptied the registry -- state won,
    #      timer frozen, win line with the observed total, win_cb
    #      {elapsed $a_c}.
    set stw [::biochemeleon::game_logic::state]
    if {$stw ne "won"} { _bail win_state "exp=won got=$stw" }
    set r4c [::biochemeleon::registry::count_remaining]
    if {$r4c != 0} { _bail win_remaining "exp=0 got=$r4c" }
    if {[llength $::WINS] != 2} {
        _bail win_cb_shape "exp=2 (one win, 2 elements) got=[llength $::WINS]"
    } else {
        set welapsed [lindex $::WINS 0]
        set whiders [lindex $::WINS 1]
        if {[catch {expr {double($welapsed) >= 0}} okw] || !$okw} {
            _bail win_elapsed "exp>=0 got=$welapsed"
        }
        if {$whiders != $a_c} { _bail win_hiders "exp=$a_c got=$whiders" }
        # Timer frozen: timer_elapsed AFTER finish_win returns the
        # FROZEN value -- constant across two reads and == win_cb's.
        set t1 [::biochemeleon::game_logic::timer_elapsed]
        set t2 [::biochemeleon::game_logic::timer_elapsed]
        if {![_feq $t1 $t2]} {
            _bail win_timer_two_reads "t1=$t1 t2=$t2"
        }
        if {![_feq $t1 $welapsed]} {
            _bail win_timer_frozen "cb=$welapsed timer=$t1"
        }
    }
    if {[lindex $::LOG_LOG end-1] ne "Found one! 0 remaining"} {
        _bail win_last_found "got=[lindex $::LOG_LOG end-1]"
    }
    set wline [lindex $::LOG_LOG end]
    if {[string first "You found all $a_c hiders in" $wline] < 0} {
        _bail win_line "got=$wline"
    }
    # The win mark landed on the LAST CA (the CA-only design).
    set a_last_ca [lindex $a_cas end]
    if {![catch {atomselect $gm "index $a_last_ca"} s4c]} {
        set u2c [lindex [$s4c get user2] 0]
        if {[catch {expr {double($u2c) > 0}} okc] || !$okc} {
            _bail win_user2 "exp>0 got=$u2c"
        }
        $s4c delete
    } else { _bail win_sel $s4c }

    # A5. POST-WIN PICK GUARD: on_pick 424 (residue-1's N -- its resid
    #     9001 IS in the block, so a state-gate failure would log
    #     "Already found!"). The state gate must no-op every pick:
    #     no state change, no extra log, no extra win.
    set log_len [llength $::LOG_LOG]
    if {[catch {::biochemeleon::game::on_pick 424} pa5]} {
        _bail postwin_pick_error $pa5
    }
    if {[::biochemeleon::game_logic::state] ne "won"} {
        _bail postwin_state "got=[::biochemeleon::game_logic::state]"
    }
    if {[llength $::LOG_LOG] != $log_len} {
        _bail postwin_log "exp=$log_len got=[llength $::LOG_LOG]"
    }
    if {[llength $::WINS] != 2} {
        _bail postwin_win "exp=2 got=[llength $::WINS]"
    }
    if {[::biochemeleon::registry::count_remaining] != 0} {
        _bail postwin_remaining "exp=0 got=[::biochemeleon::registry::count_remaining]"
    }
}

# A6. CLEANUP -- the no-leak contract (registry 0, resid block cleared,
#     game molid dead, restored original 424 atoms, numreps ==
#     pre-start, stash cleared).
if {$gs_ok} {
    if {[catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
        _bail cleanup $restored_molid
    } else {
        set ch6 [::biochemeleon::registry::count_hiders]
        if {$ch6 != 0} { _bail reg_after_cleanup "exp=0 got=$ch6" }
        set rb6 [::biochemeleon::registry::hider_for_resid 9001]
        if {$rb6 ne ""} { _bail resid_block_after_cleanup "exp='' got=$rb6" }
        if {![catch {molinfo $gm get numatoms} alive]} {
            _bail game_molid_alive "molinfo on the deleted game molid succeeded (numatoms=$alive)"
        }
        if {[catch {molinfo $restored_molid get numatoms} rn6]} {
            _bail restored_atoms $rn6
        } elseif {$rn6 != 424} {
            _bail restored_atoms "exp=424 got=$rn6"
        }
        if {[catch {molinfo $restored_molid get numreps} rr6]} {
            _bail restored_numreps $rr6
        } elseif {$rr6 != $pre_reps} {
            _bail restored_numreps "exp=$pre_reps got=$rr6"
        }
        if {[dict size $::biochemeleon::game::current_state] != 0} {
            _bail stash_cleared "exp=0 got=[dict size $::biochemeleon::game::current_state]"
        }
    }
}

# =====================================================================
# B. RANDOMIZE INVARIANT ROUND: 2-arg start_game (hider_count 5) --
#    randomizes across IMPLEMENTED_TIERS. The atom count is
#    deterministic GIVEN the draw: orig + simple x 1 + residue x 5.
#    Assert the invariant against the OBSERVED draw (17.1-06
#    quick-008 precedent).
# =====================================================================
set m2 -1
set gs2 [list]
set gm2 -1
set gs2_ok 0
if {[catch {_load_demo_1f 1znf} m2]} {
    _bail load_demo2 $m2
} else {
    set n02 [molinfo $m2 get numatoms]
    if {$n02 != 424} { _bail orig2_atoms "exp=424 got=$n02" }
    if {[catch {::biochemeleon::game::start_game $m2 5} gs2]} {
        _bail start_game2 $gs2
        puts "START2FAIL_EI $errorInfo"
    } else {
        if {[catch {dict get $gs2 game_molid} gm2]} {
            _bail gs2_key_game_molid "missing (gs2=$gs2)"
        } else {
            set gs2_ok 1
            set pr2 [dict get $gs2 per_rep]
            set eff2 [dict get $gs2 hider_count]
            puts "E2E_INFO randomize_per_rep=$pr2"
            # B7a: P9 + quick-008 invariants (the 17.1-06 step-8
            #      precedent, brief-corrected for 1znf: randomize_per_rep
            #      DRAWS the counts, so the sum can underspend -- 1 <=
            #      sum <= 5, never hard == 5).
            if {$eff2 != [::biochemeleon::rep_tiers::effective_total $pr2]} {
                _bail eff2_p9 "hider_count=$eff2 effective_total=[::biochemeleon::rep_tiers::effective_total $pr2]"
            }
            if {$eff2 < 1 || $eff2 > 5} {
                _bail eff2_range "got=$eff2 (quick-008: 1 <= sum <= 5)"
            }
            # B7b: every per_rep key is a GAME_REPS name (implemented).
            foreach rep [dict keys $pr2] {
                if {[lsearch -exact $::biochemeleon::setup_state::GAME_REPS $rep] < 0} {
                    _bail per_rep2_key "not a GAME_REPS name: $rep"
                }
            }
            # B7c: THE EXACT ATOM-COUNT INVARIANT, computed from the
            #      OBSERVED generation (the 17.1-06 quick-008 precedent:
            #      assert against the draw OBSERVED, not a blind
            #      per_rep-weighted guess -- on 1znf a residue record
            #      OMITS CB when its anchor lacks it (GLY -> a 4-atom
            #      record) and a residue tier can UNDER-GENERATE (28
            #      residues, 5.0 A separation rejections), so the ideal
            #      orig + simple x 1 + residue x 5 formula is the
            #      all-CB/no-under-gen SPECIAL CASE, asserted when it
            #      applies). The deterministic record layout, read
            #      through the public sentinel selector:
            #        - simple hiders (free placeholder OR bonded
            #          anchor-mimic) are ONE atom each;
            #        - residue records are contiguous blocks AFTER all
            #          simple records (simple-first file layout), CA at
            #          block start + 1, 4 or 5 atoms per block.
            set n2 [molinfo $gm2 get numatoms]
            set sent2_idx [list]
            set sent2_nm [list]
            set sent2_ch [list]
            if {[catch {atomselect $gm2 "resname GAM and beta < 0"} sb2]} {
                _bail sentinel2_sel $sb2
            } else {
                set sent2_idx [$sb2 get index]
                set sent2_nm [$sb2 get name]
                set sent2_ch [$sb2 get chain]
                $sb2 delete
            }
            # Classify by CHAIN, never by name: simple hiders (free
            # placeholder OR bonded anchor-mimic) are hard-coded chain G
            # (mutation.tcl HID_CHAIN); residue records carry the
            # ANCHOR's chain (G and blank anchors are rejected). A bonded
            # hider MIMICS its anchor's name, so a simple hider can be
            # named "CA" (run-5 discovery) -- the name is NOT a residue
            # discriminator, the chain is.
            set s_simple 0
            set c_res 0
            foreach sc $sent2_ch {
                if {$sc ne "G"} { incr c_res } else { incr s_simple }
            }
            set r_tot [llength $sent2_idx]
            # Every generated hider is registered: registry == sentinels.
            set ch2 [::biochemeleon::registry::count_hiders]
            if {$ch2 != $r_tot} {
                _bail reg_count2 "exp=$r_tot (sentinels) got=$ch2"
            }
            # Under-generation tolerance: the observed round total never
            # EXCEEDS the requested sum (it may be smaller).
            if {$r_tot > $eff2} {
                _bail reg2_overflow "sentinels=$r_tot requested=$eff2"
            }
            if {$r_tot < 1} { _bail reg2_empty "sentinels=$r_tot" }
            set cb_extra [expr {$n2 - 424 - $s_simple - 4 * $c_res}]
            if {$cb_extra < 0 || $cb_extra > $c_res} {
                _bail layout_atoms "n2=$n2 simple=$s_simple res=$c_res cb_extra=$cb_extra (need 0 <= cb_extra <= $c_res)"
            }
            set lens2 [list]
            # strict_ok = the draw generated IN FULL (no under-gen) and
            # every residue block carries its CB (cb_extra == C -- the
            # idealized x5 formula's precondition). c_res == 0 needs
            # cb_extra == 0, which the layout bound already enforces.
            set strict_ok [expr {($r_tot == $eff2) && ($cb_extra == $c_res)}]
            if {$c_res > 0} {
                # Simple-first layout: the first residue block starts
                # right after the S one-atom simple records; its CA is
                # block start + 1. Residue CAs are the chain!=G sentinels.
                set seen_ca 0
                foreach si $sent2_idx sc $sent2_ch {
                    if {$sc eq "G"} { continue }
                    if {!$seen_ca} {
                        set first_ca $si
                        set seen_ca 1
                        if {$si != 424 + $s_simple + 1} {
                            _bail layout_first_ca "exp=[expr {424 + $s_simple + 1}] got=$si (simple=$s_simple)"
                        }
                    } else {
                        set len [expr {$si - $prev_ca}]
                        if {$len != 4 && $len != 5} {
                            _bail layout_stride "exp 4|5 got=$len (ca $prev_ca -> $si)"
                        }
                        if {$len != 5} { set strict_ok 0 }
                        lappend lens2 $len
                    }
                    set prev_ca $si
                }
                # The last block runs to the END of the file (residue
                # records are always last).
                set len_last [expr {$n2 - $prev_ca + 1}]
                if {$len_last != 4 && $len_last != 5} {
                    _bail layout_last "exp 4|5 got=$len_last (ca=$prev_ca n2=$n2)"
                }
                if {$len_last != 5} { set strict_ok 0 }
                lappend lens2 $len_last
            }
            # The idealized formula (orig + simple x 1 + residue x 5)
            # asserted EXACTLY whenever the draw generated in full with
            # every anchor carrying CB.
            if {$strict_ok} {
                set predicted $n02
                dict for {rep cnt} $pr2 {
                    set kd [::biochemeleon::rep_tiers::tier_kind $rep]
                    if {$kd eq "residue"} {
                        set predicted [expr {$predicted + 5 * $cnt}]
                    } else {
                        set predicted [expr {$predicted + 1 * $cnt}]
                    }
                }
                if {$n2 != $predicted} {
                    _bail randomize_atoms "predicted=$predicted actual=$n2"
                }
            }
            puts "E2E_INFO randomize_layout n2=$n2 simple=$s_simple res=$c_res cb_extra=$cb_extra lens=$lens2 strict_ok=$strict_ok (per_rep=$pr2)"
            # B7d: remaining_by_rep keys subset of GAME_REPS.
            if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
                _bail remaining_by_rep2 $rbr2
            } else {
                foreach rep [dict keys $rbr2] {
                    if {[lsearch -exact $::biochemeleon::setup_state::GAME_REPS $rep] < 0} {
                        _bail rbr2_key "not a GAME_REPS name: $rep"
                    }
                }
            }

            # B7e: state -> playing AGAIN (round A ended "won"; on_pick
            #      is a no-op outside playing -- the same Game-tab GO
            #      transition the first round drove).
            if {[catch {
                ::biochemeleon::game_logic::round_reset
                ::biochemeleon::game_logic::begin_countdown
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::countdown_tick
                ::biochemeleon::game_logic::begin_play
            } driveerr2]} {
                _bail drive_playing2 $driveerr2
            } else {
                set stp2 [::biochemeleon::game_logic::state]
                if {$stp2 ne "playing"} { _bail playing_state2 "got=$stp2" }
            }

            # B8: ONE find through whichever path applies -- derived at
            #     runtime from the sentinel layout (NO hard-coded index):
            #     a chain!=G sentinel is a residue record's CA -> pick
            #     its N (index-1) -> the fallback; else every sentinel is
            #     a simple hider (chain G, whatever its name) -> the
            #     first is registered -> direct.
            set pick_idx ""
            set pick_ca ""
            set is_fb 0
            foreach si $sent2_idx sc $sent2_ch {
                if {$sc ne "G"} {
                    set pick_idx [expr {$si - 1}]
                    set pick_ca $si
                    set is_fb 1
                    break
                }
            }
            if {!$is_fb} { set pick_idx [lindex $sent2_idx 0] }
            puts "E2E_INFO randomize_pick idx=$pick_idx fallback=$is_fb (ca=$pick_ca) sentinels=$sent2_idx/$sent2_nm/$sent2_ch"
            set log_len2 [llength $::LOG_LOG]
            if {[::biochemeleon::game_logic::state] ne "playing"} {
                _bail rand_state_not_playing "got=[::biochemeleon::game_logic::state]"
            }
            if {[catch {::biochemeleon::game::on_pick $pick_idx} pb8]} {
                _bail rand_pick_error $pb8
            } else {
                set exp_rem [expr {$ch2 - 1}]
                set r8 [::biochemeleon::registry::count_remaining]
                if {$r8 != $exp_rem} { _bail rand_remaining "exp=$exp_rem got=$r8" }
                if {[llength $::LOG_LOG] != $log_len2 + 1} {
                    _bail rand_log_len "exp=$log_len2+1 got=[llength $::LOG_LOG]"
                } elseif {[lindex $::LOG_LOG end] ne "Found one! $exp_rem remaining"} {
                    _bail rand_line "got=[lindex $::LOG_LOG end]"
                }
                if {$is_fb} {
                    # Fallback path: the CA got marked, the clicked N did not.
                    if {[::biochemeleon::registry::status_of $pick_ca] ne "found"} {
                        _bail rand_fb_status "got=[::biochemeleon::registry::status_of $pick_ca]"
                    }
                    if {![catch {atomselect $gm2 "index $pick_idx $pick_ca"} s8]} {
                        lassign [$s8 get user2] u2n8 u2ca8
                        if {[catch {expr {double($u2ca8) > 0}} ok8] || !$ok8} {
                            _bail rand_fb_user2_ca "exp>0 got=$u2ca8"
                        }
                        if {![_feq $u2n8 0.0]} {
                            _bail rand_fb_user2_n "exp=0 got=$u2n8"
                        }
                        $s8 delete
                    } else { _bail rand_fb_sel $s8 }
                } else {
                    # Direct path: the registered simple hider itself.
                    if {[::biochemeleon::registry::status_of $pick_idx] ne "found"} {
                        _bail rand_direct_status "got=[::biochemeleon::registry::status_of $pick_idx]"
                    }
                }
            }

            # B9: cleanup gs2 -- no-leak contract again.
            if {[catch {::biochemeleon::game::cleanup $gs2} restored2]} {
                _bail cleanup2 $restored2
            } else {
                set ch9 [::biochemeleon::registry::count_hiders]
                if {$ch9 != 0} { _bail reg_after_cleanup2 "exp=0 got=$ch9" }
                set rb9 [::biochemeleon::registry::hider_for_resid 9001]
                if {$rb9 ne ""} { _bail resid_block_after_cleanup2 "exp='' got=$rb9" }
                if {![catch {molinfo $gm2 get numatoms} alive2]} {
                    _bail game2_molid_alive "molinfo on the deleted game molid succeeded (numatoms=$alive2)"
                }
                if {[catch {molinfo $restored2 get numatoms} rn9]} {
                    _bail restored2_atoms $rn9
                } elseif {$rn9 != 424} {
                    _bail restored2_atoms "exp=424 got=$rn9"
                }
            }
        }
    }
}

# ---- 10. Report. VMD does NOT propagate exit codes -- use a marker. ----
# Evidence echo: the captured public-surface callbacks (the log lines the
# round produced, the win_cb pairs, the remaining-callback ticks) and the
# final state machine position.
puts "E2E_INFO log_log=$::LOG_LOG"
puts "E2E_INFO wins=$::WINS rem_ticks=$::REM_TICKS state=[::biochemeleon::game_logic::state]"
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
