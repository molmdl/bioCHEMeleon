# vmd/tests/rep_verify.tcl
# ---------------------------------------------------------------------------
# Phase 17.1 / Plan 17.1-14 -- CONSOLIDATED GUI rep-verify AUTO-DRIVER.
# EXTENDED by Plan 17.2-12 with the CARTOON round (pv_round3): the 17.2
# consolidated checkpoint round (Cartoon NewCartoon Trace Tube VDW x1 --
# 4 residue bumps + 1 VDW sphere in ONE pass).
# Drives the ONE consolidated human-verify checkpoint for the whole 17.1
# phase: 6 simple tiers (Lines VDW Licorice CPK Points DynamicBonds) behind
# the lock-scene/randomize infrastructure, exercised in a real VMD GUI in
# 3 rounds (6-tier mixed + lock-scene + cartoon).
#
# AUTO-DRIVER (standing directive from 16-16: sessions must be simpler --
# driver auto-issues commands + auto-logs to a file; the human only does
# what needs a real mouse/keyboard). Sourcing this file EXECUTES the setup
# itself and auto-logs every state dump + pick event to
# `rep_verify_log.txt` in the cwd (open-append + flush per line). The
# human's whole job:
#   1. paste ONE line:  source vmd/tests/rep_verify.tcl
#   2. press  p  once per round (arms C-side pick delivery -- the LOCKED
#      first-click quirk; pasted `mouse mode pick*` never arms)
#   3. click one hider per style (real clicks)
#   4. style the scene for round 2 (Graphics -> Representations)
#   5. paste: pv_round2      (starts the lock-scene round)
#   6. paste: pv_round3      (starts the CARTOON round on fresh 1znf:
#      press p once, find all 5 -- click the cartoon BUMP not the
#      VDW sphere for Cartoon and Tube)
#   7. paste: pv_report      (session summary)
#   8. paste: pv_cleanup     (restore; then pv_cleanup_check)
#
# ROUND 2 TARGETING (why the mirror): lock_scene detection reads the
# TARGET molecule's snapshot reps (game.tcl scene_reps_to_per_rep over the
# snapshot taken AFTER the active-game guard). The displayed molecule the
# user styled after round 1 IS the round-1 game molecule -- the guard
# DELETES it (restoring the original) before the new snapshot, so styling
# it directly can never reach the detector. pv_round2 therefore reads the
# styled style off the DISPLAYED (top) molecule's main rep and mirrors it
# onto a fresh 1k8p load, which becomes the round-2 target -- the user's
# styling choice is what drives the round-2 tier, faithfully.
#
# STRUCTURE (modeled on pick_verify.tcl, 16-12): Tk-guard if-wrap
# (`::tk_version` absent in -dispdev text -> the whole body no-ops with ONE
# warn line; an if-wrap is ONE command in both source and -e evaluation).
# Per the 17.1-04 CAUTION: only the harness patterns were copied
# (Tk-guard, path fallback, pv_cleanup/pv_cleanup_check, pv_state's
# mouse/labels/registry sections). ALL rep lookups are rebuilt on
# `hiders::tier_reps` + `mol repindex` (the removed hiders::hidden_rep /
# found_rep vars are GONE); the pv_hidden_rep/pv_hide_hidden/pv_show_hidden
# probes are NOT carried over (the hidden-rep caveat is superseded -- N-tier
# design never hides a rep). pick_verify.tcl itself stays UNREPAIRED as a
# Phase-16 historical artifact.
#
# HEADLESS PROBE KNOB: `set ::pv_probe 1` before sourcing defines all pv_*
# procs + resolves paths but SKIPS the GUI session (for a text-mode
# definition check). A real GUI session never sets it.
#
# Tcl 8.5.6: no 8.6 control-flow idioms (foreach + catch only); braced
# expr. No modal grab anywhere (the viewer must stay interactive). Re-
# sourcing resets the ::pv_finds / ::pv_rounds counters (the log FILE is
# append, so history survives) and re-registers the pick observer.
# ---------------------------------------------------------------------------

if {![info exists ::tk_version]} {
    vmdcon -warn {rep_verify.tcl is a GUI-only auto-driver (needs a real VMD GUI, Tk, and a human with a mouse) -- nothing to do in -dispdev text mode.}
} else {

# ===========================================================================
# pv_log -- ALL driver output goes through here: timestamped append to
# rep_verify_log.txt in the cwd (handle kept open, flush per line) AND a
# vmdcon -info echo (the main console stays the human's live view).
# ===========================================================================
proc pv_log {msg} {
    if {![info exists ::pv_logfh]} {
        set ::pv_logfile [file join [pwd] rep_verify_log.txt]
        set ::pv_logfh [open $::pv_logfile a]
        puts $::pv_logfh "\[[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]\] === rep_verify log opened (cwd [pwd]) ==="
    }
    puts $::pv_logfh "\[[clock format [clock seconds] -format {%H:%M:%S}]\] $msg"
    flush $::pv_logfh
    vmdcon -info $msg
    return
}

# ===========================================================================
# pv_observe -- the pick observer (16-16 exact-value format, two lines per
# click: PICK ev=... + PICK atom=... mol=... shift=...). {args} signature
# (a positional signature makes VMD's own write FAIL and lose the pick).
# Every value read is catch-guarded (prints ? instead of erroring).
# Bumps ::pv_finds when the picked index is a REGISTERED hider still in
# "hidden" status (the game's own trace marks it found moments later;
# traces fire in registration order and this one registered first).
# ===========================================================================
proc pv_observe {args} {
    global vmd_pick_atom vmd_pick_mol vmd_pick_shift_state
    set a "?"
    catch {set a $vmd_pick_atom}
    set m "?"
    catch {set m $vmd_pick_mol}
    set s "?"
    catch {set s [info exists vmd_pick_shift_state]}
    pv_log "PICK ev=$args"
    pv_log "PICK atom=$a mol=$m shift=$s"
    if {[string is integer -strict $a]} {
        set ih 0
        catch {set ih [::biochemeleon::registry::is_hider $a]}
        if {$ih} {
            set stt ""
            catch {set stt [::biochemeleon::registry::status_of $a]}
            if {$stt eq $::biochemeleon::registry::HIDER_STATUS_HIDDEN} {
                if {![info exists ::pv_finds]} { set ::pv_finds 0 }
                incr ::pv_finds
                pv_log "PICK FIND #$::pv_finds index=$a (hidden -> found)"
            }
            pv_log "PICK VERDICT index=$a is_hider=1 direct"
        } else {
            pv_observe_fallback $a $m
        }
    }
    return
}

# ===========================================================================
# pv_observe_fallback -- 17.2-12 fallback verdict for a NON-registered
# pick (READ-ONLY; no game behavior change): reads the clicked atom's
# resid + name off the picked molecule (falls back to the live game
# molecule if the pick molid is dead) and logs the registry
# hider_for_resid resolution. Captures WHICH atom delivers each bump
# click (CA vs N/C/O/CB -- the research's open pick-target question).
# ===========================================================================
proc pv_observe_fallback {idx pmol} {
    set gm $pmol
    if {![string is integer -strict $gm]
            || [catch {molinfo $gm get numatoms}]} {
        set gm [pv_game_mol]
    }
    set rid "?"
    set nm "?"
    if {[string is integer -strict $gm]
            && ![catch {set sel [atomselect $gm "index $idx"]}]} {
        catch {
            set rid [lindex [$sel get resid] 0]
            set nm [lindex [$sel get name] 0]
        }
        catch {$sel delete}
    }
    set fb "(read-failed)"
    if {$rid ne "?"} {
        set fb "(none)"
        catch {
            set r2 [::biochemeleon::registry::hider_for_resid $rid]
            if {$r2 ne {}} { set fb $r2 }
        }
    }
    pv_log "PICK VERDICT index=$idx is_hider=0 resid=$rid name=$nm fallback=$fb"
    return
}

# ===========================================================================
# pv_game_mol -- the live game molid (pick_bridge::active_mol while a round
# is live; falls back to game_tab's stashed game_state -- STALE after
# cleanup, so callers catch-guard their mol calls).
# ===========================================================================
proc pv_game_mol {} {
    if {[info exists ::biochemeleon::pick_bridge::active_mol]
            && $::biochemeleon::pick_bridge::active_mol ne {}} {
        return $::biochemeleon::pick_bridge::active_mol
    }
    if {[info exists ::biochemeleon::game_tab::game_state]} {
        if {[catch {dict get $::biochemeleon::game_tab::game_state game_molid} gm] == 0} {
            return $gm
        }
    }
    return {}
}

# ===========================================================================
# pv_state -- the 17.1 dump: mouse mode, pick_bridge vars, game_logic
# state/timer, registry count_remaining + remaining_by_rep (PER-TIER), the
# effective round per_rep, game molid atoms + hider indices + numreps, and
# EVERY tier pair (hiders::tier_reps code -> mol repindex -> style /
# selection / color / shown for hidden + found). Auto-stashes ::pv_gs for
# pv_cleanup (idempotent -- the FIRST dump after Start captures it).
# ===========================================================================
proc pv_state {} {
    if {![info exists ::pv_gs]
            && [info exists ::biochemeleon::game_tab::game_state]} {
        set ::pv_gs $::biochemeleon::game_tab::game_state
    }
    set L [list "--- bioCHEMeleon 17.1 rep-verify state dump ---"]
    if {[info exists ::vmd_mouse_mode]} {
        lappend L "mouse: mode=$::vmd_mouse_mode submode=$::vmd_mouse_submode"
    } else {
        lappend L "mouse: vmd_mouse_mode not set"
    }
    foreach v {active mechanism saved_mode saved_submode active_mol label_base} {
        if {[info exists ::biochemeleon::pick_bridge::$v]} {
            lappend L "pick_bridge $v = [set ::biochemeleon::pick_bridge::$v]"
        }
    }
    if {![catch {::biochemeleon::game_logic::state} st]} {
        lappend L "game_logic state = $st"
        if {$st eq "playing" || $st eq "won"} {
            if {[catch {::biochemeleon::game_logic::timer_elapsed} el]} {
                lappend L "timer = <error: $el>"
            } else {
                lappend L "timer elapsed = ${el}s  ([::biochemeleon::game_logic::format_mmss $el])"
            }
        } else {
            lappend L "timer = (not started; starts at GO)"
        }
    }
    if {![catch {::biochemeleon::registry::count_remaining} rem]} {
        lappend L "registry remaining = $rem"
    }
    if {![catch {::biochemeleon::registry::remaining_by_rep} byrep]} {
        lappend L "registry remaining_by_rep (per-tier) = $byrep"
    }
    if {[info exists ::pv_gs]} {
        if {![catch {dict get $::pv_gs per_rep} eff]} {
            lappend L "round per_rep (effective) = $eff"
        }
        if {![catch {dict get $::pv_gs hider_count} hc]} {
            lappend L "round hider_count = $hc"
        }
    }
    # Molecule-level state (catch-guarded: molid may be stale post-cleanup).
    set gm [pv_game_mol]
    if {$gm ne {} && ![catch {molinfo $gm get numatoms} natoms]} {
        set sel [atomselect $gm {resname GAM and beta < 0}]
        set hidx [$sel list]
        # 17.2-12: sentinel rows incl. SS letters (structure is the {T, C}
        # family for fake CAs -- anchor-dependent, NEVER hard == T).
        set srows {}
        catch {set srows [$sel get {index resid name structure}]}
        $sel delete
        set nreps [molinfo $gm get numreps]
        lappend L "game molid $gm: $natoms atoms, $nreps reps; HIDER indices: $hidx"
        if {[llength $srows] > 0} {
            lappend L "sentinels (index resid name structure): $srows"
        }
        # 17.2-12: fake resid block (hider_for_resid 9001..9005; the round
        # registers one resid per residue hider -- 9005 is the miss case).
        set fb1 {}
        catch {set fb1 [::biochemeleon::registry::hider_for_resid 9001]}
        if {$fb1 ne {}} {
            foreach rr {9001 9002 9003 9004 9005} {
                set fb {}
                catch {set fb [::biochemeleon::registry::hider_for_resid $rr]}
                if {$fb eq {}} { set fb (none) }
                lappend L "resid block: $rr -> $fb"
            }
        } else {
            lappend L {resid block: none (simple-only round)}
        }
        if {[info exists ::biochemeleon::hiders::tier_reps]} {
            dict for {code pair} $::biochemeleon::hiders::tier_reps {
                lassign $pair hname fname hself fself
                set r -1
                catch {set r [mol repindex $gm $hname]}
                if {$r < 0 || $r >= $nreps} {
                    lappend L "tier $code: hidden rep '$hname' GONE (repindex $r)"
                    continue
                }
                foreach {sty selx col mat} \
                        [molinfo $gm get "{rep $r} {selection $r} {color $r} {material $r}"] { break }
                lappend L "tier $code: hidden idx $r shown=[mol showrep $gm $r] style=$sty color=$col"
                lappend L "    hidden sel: $hself"
                set rf -1
                catch {set rf [mol repindex $gm $fname]}
                if {$rf >= 0 && $rf < $nreps} {
                    foreach {fsty fsel fcol fmat} \
                            [molinfo $gm get "{rep $rf} {selection $rf} {color $rf} {material $rf}"] { break }
                    lappend L "    found idx $rf: style=$fsty color=$fcol shown=[mol showrep $gm $rf]"
                    lappend L "    found sel: $fself"
                } else {
                    lappend L "    found rep '$fname' GONE (repindex $rf)"
                }
            }
        } else {
            lappend L "tier_reps: not present (no round started)"
        }
    } else {
        lappend L "game molid: none live ($gm)"
    }
    # Label hygiene.
    if {![catch {llength [label list Atoms]} nlab]} {
        set base 0
        if {[info exists ::biochemeleon::pick_bridge::label_base]} {
            set base $::biochemeleon::pick_bridge::label_base
        }
        lappend L "labels: count=$nlab baseline=$base ([expr {$nlab - $base}] click-created)"
    }
    foreach l $L { pv_log $l }
    return
}

# ===========================================================================
# pv_round2 -- the LOCK-SCENE round. Reads the user's styled style off the
# DISPLAYED (top) molecule's main rep (see the header ROUND 2 TARGETING
# note), mirrors it onto a fresh 1k8p load, then targets THAT molecule with
# lock_scene 1 + empty per_rep: start_game's detection must derive the
# round's tiers from the mirrored scene style alone.
# ===========================================================================
proc pv_round2 {} {
    pv_log {pv_round2: LOCK-SCENE round. Assumes you already styled the DISPLAYED molecule's main rep (Graphics -> Representations, e.g. Licorice) BEFORE pasting this.}
    # 1. Read the user's scene styling (top molecule, main rep).
    set srcmol {}
    catch {set srcmol [molinfo top]}
    set srcstyle {}
    if {$srcmol ne {} && ![catch {molinfo $srcmol get numatoms} sn] && $sn > 0} {
        foreach {sty selx col mat} \
                [molinfo $srcmol get "{rep 0} {selection 0} {color 0} {material 0}"] { break }
        set srcstyle [lindex $sty 0]
        pv_log "pv_round2: read scene style '$sty' off displayed molid $srcmol (main rep)"
    } else {
        pv_log "pv_round2: no live displayed molecule to read a style from"
    }
    # 2. Fresh 1k8p target (a NEW molecule -- never the game molecule the
    #    guard is about to delete).
    if {[catch {::biochemeleon::demos::load_demo 1k8p} m2]} {
        pv_log "pv_round2: FAILED to load fresh 1k8p target: $m2"
        return
    }
    pv_log "pv_round2: fresh 1k8p target = molid $m2"
    # 3. Mirror the user's style onto the target's main rep (only real
    #    GAME_REPS styles; anything else stays default and is logged).
    if {[lsearch -exact $::biochemeleon::setup_state::GAME_REPS $srcstyle] >= 0} {
        if {[catch {mol modstyle 0 $m2 $srcstyle} merr]} {
            pv_log "pv_round2: mirror modstyle FAILED: $merr (round-2 scene stays default)"
        } else {
            foreach {vsty vsel vcol vmat} \
                    [molinfo $m2 get "{rep 0} {selection 0} {color 0} {material 0}"] { break }
            pv_log "pv_round2: mirrored '$srcstyle' onto molid $m2 (read-back: $vsty)"
        }
    } else {
        pv_log "pv_round2: '$srcstyle' is not a GAME_REPS style -- NOT mirrored; lock_scene will detect the default (Lines)."
    }
    # 4. Build + validate the round-2 state (lock_scene 1, per_rep {},
    #    same hider_count 6), apply it to the Setup form, start via the
    #    real GUI path (on_start -> start_game detection).
    set st [dict create target_mode loaded selected_object $m2 \
                hider_count 6 per_rep [dict create] lock_scene 1 \
                difficulty_easy 1 demo_id 1k8p]
    if {[catch {::biochemeleon::setup_state::validate_state $st \
                    [::biochemeleon::demos::atom_count $m2]} stv]} {
        pv_log "pv_round2: validate_state failed: $stv"
        return
    }
    if {[catch {::biochemeleon::setup_tab::apply_state $stv} aerr]} {
        pv_log "pv_round2: apply_state failed: $aerr"
        return
    }
    pv_log {pv_round2: starting lock-scene round (lock_scene=1, per_rep={}) -- the DERIVED distribution auto-logs after GO.}
    if {[catch {::biochemeleon::on_start} oerr]} {
        pv_log "pv_round2: on_start failed: $oerr"
        return
    }
    set ::pv_rounds 2
    after 4500 pv_state
    pv_log {pv_round2: round 2 started. Press p once, find 2+ hiders (they should ALL be the styled tier), then paste: pv_round3}
    return
}

# ===========================================================================
# pv_round3 -- the 17.2 CARTOON round (Plan 17.2-12). Mirrors pv_round2's
# shape: a FRESH protein target (earlier rounds mutated/restored molecules
# -- never assume a fixed molid; 1znf has the protein CA anchors the
# residue splice needs -- 1k8p is DNA-only), then the crafted 5-hider
# state (Cartoon NewCartoon Trace Tube VDW x1 = 4 residue bumps + 1 VDW
# sphere: blend + pick + coexistence in ONE pass) via validate_state ->
# apply_state -> on_start -> after-4500 auto-dump. The dump auto-logs the
# round composition: per-tier remaining_by_rep, the fake resid block
# (hider_for_resid 9001..9005), CA sentinel indices + structure letters,
# per-tier rep read-backs, and the game atom count (orig + 21).
# ===========================================================================
proc pv_round3 {} {
    pv_log {pv_round3: CARTOON round (4 residue bumps + 1 VDW sphere).}
    # 1. Fresh 1znf protein target (a NEW molecule -- never the game
    #    molecule the guard is about to delete).
    if {[catch {::biochemeleon::demos::load_demo 1znf} m3]} {
        pv_log "pv_round3: FAILED to load fresh 1znf target: $m3"
        return
    }
    pv_log "pv_round3: fresh 1znf protein target = molid $m3"
    if {![catch {::biochemeleon::demos::atom_count $m3} nat3]} {
        pv_log "pv_round3: target has $nat3 atoms -- expect the game molecule at [expr {$nat3 + 21}] (4 residues x 5 + 1 VDW)"
    }
    # 2. Build + validate the round-3 state (5 hiders, one per tier:
    #    Cartoon NewCartoon Trace Tube VDW x1), apply, start via the real
    #    GUI path (on_start -> start_game detection).
    set st [dict create target_mode loaded selected_object $m3 \
                hider_count 5 \
                per_rep [dict create Cartoon 1 NewCartoon 1 \
                             Trace 1 Tube 1 VDW 1] \
                lock_scene 0 difficulty_easy 1 demo_id 1znf]
    if {[catch {::biochemeleon::setup_state::validate_state $st \
                    [::biochemeleon::demos::atom_count $m3]} stv]} {
        pv_log "pv_round3: validate_state failed: $stv"
        return
    }
    if {[catch {::biochemeleon::setup_tab::apply_state $stv} aerr]} {
        pv_log "pv_round3: apply_state failed: $aerr"
        return
    }
    # 3. Refresh the cleanup stash: ::pv_gs was captured by round 1's
    #    first dump and is STALE by round 3 (earlier guard restarts
    #    deleted those molids) -- pv_cleanup on it would fail. Unset so
    #    the round-3 auto-dump re-stashes the LIVE round-3 state.
    catch {unset ::pv_gs}
    pv_log {pv_round3: starting CARTOON round -- per-tier composition + resid block auto-log after GO.}
    if {[catch {::biochemeleon::on_start} oerr]} {
        pv_log "pv_round3: on_start failed: $oerr"
        return
    }
    set ::pv_rounds 3
    after 4500 pv_state
    pv_log {pv_round3: round 3 started. Press p once, find all 5 hiders --}
    pv_log {   for Cartoon and Tube click the BUMP on the cartoon geometry}
    pv_log {   (NOT the VDW sphere -- the fallback-path proof; the log records}
    pv_log {   which atom delivered each click). Bumps should read as smooth}
    pv_log {   tube detours; nearby real helices/sheets stay undistorted.}
    pv_log {   Found ones turn green. Then paste: pv_report, then pv_cleanup}
    return
}

# ===========================================================================
# pv_cleanup / pv_cleanup_check -- session teardown (console-only: the Game
# tab has NO Cleanup button until Phase 19). Order per 16-RESEARCH-pick 2.5:
# deactivate the pick bridge FIRST (idempotent), THEN game::cleanup
# (original restored, registry reset) via the ::pv_gs stash (falls back to
# the live game_tab state). pv_cleanup_check dumps the post-state.
# ===========================================================================
proc pv_cleanup {} {
    set gs {}
    if {[info exists ::pv_gs]} { set gs $::pv_gs }
    if {$gs eq {} && [info exists ::biochemeleon::game_tab::game_state]} {
        set gs $::biochemeleon::game_tab::game_state
    }
    if {$gs eq {}} {
        pv_log {pv: no game_state to clean -- no round was started.}
        return
    }
    catch {::biochemeleon::pick_bridge::deactivate}
    if {[catch {::biochemeleon::game::cleanup $gs} err]} {
        pv_log "pv: cleanup failed: $err (already cleaned? a second pv_cleanup on the same round fails harmlessly)"
        return
    }
    catch {unset ::pv_gs}
    pv_log {pv: CLEANUP done (pick bridge off, original molecule restored, registry reset). Now paste: pv_cleanup_check}
    return
}

proc pv_cleanup_check {} {
    set L [list "--- post-Cleanup check ---"]
    if {[info exists ::vmd_mouse_mode]} {
        lappend L "mouse now: mode=$::vmd_mouse_mode submode=$::vmd_mouse_submode"
    }
    if {[info exists ::biochemeleon::pick_bridge::saved_mode]} {
        lappend L "pick_bridge saved (pre-Start): $::biochemeleon::pick_bridge::saved_mode / $::biochemeleon::pick_bridge::saved_submode"
    }
    if {[info exists ::biochemeleon::pick_bridge::active]} {
        lappend L "pick_bridge active = $::biochemeleon::pick_bridge::active (expect 0)"
    }
    if {![catch {llength [label list Atoms]} nlab]} {
        set base 0
        if {[info exists ::biochemeleon::pick_bridge::label_base]} {
            set base $::biochemeleon::pick_bridge::label_base
        }
        if {$nlab == $base} {
            lappend L "labels: count=$nlab baseline=$base (CLEAN)"
        } else {
            lappend L "labels: count=$nlab baseline=$base (LEFTOVER: [expr {$nlab - $base}])"
        }
    }
    if {![catch {::biochemeleon::game_logic::state} st]} {
        lappend L "game_logic state = $st"
    }
    if {![catch {::biochemeleon::registry::count_remaining} rem]} {
        lappend L "registry remaining = $rem (expect 0 after reset)"
    }
    # 17.2-12: the restored molecule's atom count (the cleanup-restore
    # proof: back to the original demo count -- no residue remnants).
    if {![catch {molinfo top} tm] && $tm ne {}
            && ![catch {molinfo $tm get numatoms} nat]} {
        lappend L "top molecule: molid $tm, $nat atoms (expect the original demo count)"
    }
    foreach l $L { pv_log $l }
    return
}

# ===========================================================================
# pv_report -- the session summary the human pastes LAST: rounds run,
# finds registered (picked hidden hider indices), remaining (+ per-tier),
# and the log-file path to attach.
# ===========================================================================
proc pv_report {} {
    set rounds "?"
    if {[info exists ::pv_rounds]} { set rounds $::pv_rounds }
    set finds "?"
    if {[info exists ::pv_finds]} { set finds $::pv_finds }
    set rem "?"
    catch {set rem [::biochemeleon::registry::count_remaining]}
    set byrep "?"
    catch {set byrep [::biochemeleon::registry::remaining_by_rep]}
    pv_log "=== SESSION REPORT: rounds=$rounds finds=$finds remaining=$rem by_rep=$byrep"
    pv_log "=== full transcript: [file join [pwd] rep_verify_log.txt]  (attach it + your per-style verdicts)"
    return
}

# ===========================================================================
# pv_instructions -- the human's steps (printed once after round 1 starts;
# 8 short lines, everything else is auto-logged).
# ===========================================================================
proc pv_instructions {} {
    pv_log {== YOUR STEPS (everything else is auto-logged) ==}
    pv_log {0. CLICKS BEFORE ONE  p  PRESS LAND IN LABELATOM MODE (known}
    pv_log {   quirk): press  p  ONCE on the VMD display FIRST, each round.}
    pv_log {1. Round 1: click ONE hider of EACH style (6 finds): VDW/CPK/}
    pv_log {   Points spheres+dot, Licorice ball, Lines/DynBonds stubs.}
    pv_log {2. Each find turns GREEN; Game-tab remaining drops per tier.}
    pv_log {3. After the win box: style the DISPLAYED molecule's main rep}
    pv_log {   (e.g. Licorice), paste  pv_round2 , press p, find 2+.}
    pv_log {4. Paste  pv_round3  (CARTOON round: 4 bumps + 1 VDW sphere).}
    pv_log {5. Press  p  ONCE; find all 5 -- for Cartoon and Tube click the}
    pv_log {   cartoon BUMP (NOT the VDW sphere). Bumps = smooth tube}
    pv_log {   detours; real helices/sheets stay undistorted; finds green.}
    pv_log {6. Last: paste  pv_report  then  pv_cleanup.}
    return
}

# ===========================================================================
# pv_autostart -- the auto-session (runs on source): source the extension
# if absent -> load 1k8p if absent -> open_dialog -> apply the crafted
# 6-tier state -> register the pick observer -> on_start -> auto-dump.
# ===========================================================================
proc pv_autostart {} {
    pv_log "=== bioCHEMeleon 17.1 consolidated GUI rep-verify session ==="
    # 1. Source the extension if this session doesn't have it yet.
    if {![namespace exists ::biochemeleon]} {
        if {$::pv_entry_path eq {}} {
            pv_log {pv: cannot find vmd/biochemeleon.tcl -- cd to the staging root (tmp/biochemeleon-vmd) and re-source: source vmd/tests/rep_verify.tcl}
            return
        }
        pv_log "pv: sourcing the extension ($::pv_entry_path) ..."
        if {[catch {source $::pv_entry_path} err]} {
            pv_log "pv: FAILED to source biochemeleon.tcl: $err"
            return
        }
    } else {
        pv_log {pv: extension already loaded -- skipping source.}
    }
    # 2. Load demo 1k8p if the session has no 1k8p molecule; capture molid.
    set molid {}
    foreach m [molinfo list] {
        if {![catch {molinfo $m get filename} fn]
                && [string match -nocase {*1k8p*} $fn]} {
            set molid $m
        }
    }
    if {$molid eq {}} {
        if {[catch {::biochemeleon::demos::load_demo 1k8p} molid]} {
            pv_log "pv: FAILED to load demo 1k8p: $molid"
            return
        }
        pv_log "pv: loaded bundled demo 1k8p (molid $molid)"
    } else {
        pv_log "pv: demo 1k8p already loaded (molid $molid) -- skipping load."
    }
    # 3. Open the dialog (singleton re-show if already open).
    if {[catch {::biochemeleon::open_dialog} derr]} {
        pv_log "pv: open_dialog failed: $derr"
        return
    }
    # 4. Crafted 6-tier round-1 state -> validate -> apply to the form.
    if {[catch {::biochemeleon::setup_state::validate_state [dict create \
                target_mode loaded selected_object $molid hider_count 6 \
                per_rep [dict create VDW 1 Lines 1 Licorice 1 CPK 1 \
                             Points 1 DynamicBonds 1] \
                lock_scene 0 difficulty_easy 1 demo_id 1k8p] \
                [::biochemeleon::demos::atom_count $molid]} st]} {
        pv_log "pv: validate_state failed: $st"
        return
    }
    if {[catch {::biochemeleon::setup_tab::apply_state $st} aerr]} {
        pv_log "pv: apply_state failed: $aerr"
        return
    }
    pv_log {pv: Setup form applied -- 6 hiders, one per tier (VDW Lines Licorice CPK Points DynamicBonds x1).}
    # 5. Register the pick observer (idempotent: remove-then-add).
    catch {trace remove variable ::vmd_pick_event write pv_observe}
    trace add variable ::vmd_pick_event write pv_observe
    pv_log {pv: pick observer registered (every pick auto-logs to the file).}
    # 6. START round 1 through the real GUI path (the BTN-07 handler).
    if {[catch {::biochemeleon::on_start} serr]} {
        pv_log "pv: on_start failed: $serr"
        return
    }
    set ::pv_rounds 1
    pv_log {pv: ROUND 1 STARTED (6 tiers x 1 hider). State auto-dumps after the 3-2-1-GO countdown.}
    after 4500 pv_state
    pv_instructions
    return
}

# ===========================================================================
# PATH RESOLUTION -- at FILE TOP LEVEL (inside the guard) because
# [info script] is EMPTY inside procs (14-02 lesson: it is call-time
# context). Script-relative first, cwd-relative fallback.
# ===========================================================================
set ::pv_entry_path {}
set _rv_iscript [info script]
if {$_rv_iscript ne {}} {
    set _rv_cand [file normalize [file join \
            [file dirname [file normalize $_rv_iscript]] .. biochemeleon.tcl]]
    if {[file exists $_rv_cand]} { set ::pv_entry_path $_rv_cand }
}
if {$::pv_entry_path eq {}} {
    if {[catch {file normalize vmd/biochemeleon.tcl} _rv_cand] == 0
            && [file exists $_rv_cand]} {
        set ::pv_entry_path $_rv_cand
    }
}
unset -nocomplain _rv_iscript _rv_cand

# Session counters (re-source resets them; the log FILE is append-only).
set ::pv_finds 0
set ::pv_rounds 0

# ===========================================================================
# GO -- auto-start the session (skipped under the ::pv_probe knob).
# ===========================================================================
if {[info exists ::pv_probe]} {
    vmdcon -info "pv: PROBE mode -- [llength [info procs pv_*]] pv_* procs defined, autostart skipped, entry=[file tail $::pv_entry_path]"
} else {
    pv_autostart
}

}
