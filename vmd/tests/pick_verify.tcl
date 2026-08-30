# vmd/tests/pick_verify.tcl
# ---------------------------------------------------------------------------
# Phase 16 / Plan 16-12 -- GUI pick-contract verification driver.
# Implements steps 1-9 of the GUI human-verify checkpoint spec
# (.planning/phases/16-mvp-core-loop-sphere/16-RESEARCH-pick.md SS3), whose
# verdict locks the VMD pick-callback contract (keep-vs-delete table, SS3
# "After the lock").
#
# WHAT THIS IS: a SOURCE-ONCE checklist for a REAL VMD GUI session. Sourcing
# it prints step prompts (vmdcon -info) + the exact one-liners to paste into
# the Tk console, and defines small pv_* helper procs for state dumps.
# IT EXECUTES NO STEPS ITSELF -- every step needs a human with a real mouse.
#
# HEADLESS SAFETY: the WHOLE body lives inside `if {[info exists
# ::tk_version]}`. A top-level `return` guard is NOT sufficient: under
# `vmd -e` VMD evaluates each top-level command independently, so `return`
# ends only that one command and the rest of the file STILL RUNS (observed
# 16-12: the step guide printed in -dispdev text mode). An if-wrap is one
# single command in both evaluation modes (source and -e), so it is a clean
# no-op headless. (::tk_version is absent in text mode -- Tk loads only in
# GUI mode; use the global qualifier per the 13-02 lesson.)
#
# PATHS: [info script] is EMPTY under `vmd -e` (14-02 lesson), so entry
# resolution tries the script-relative path first and falls back to
# cwd-relative `vmd/biochemeleon.tcl` (both the staged headless run and the
# GUI flow cd to the staging root first).
#
# HOW TO RUN (human, ~10 min):
#   1. Open a real VMD GUI on Windows (vmd.exe). In VMD: Extensions ->
#      Tk Console.
#   2. cd to the staging root (tmp/biochemeleon-vmd), then in the Tk console:
#          source vmd/tests/pick_verify.tcl
#      (Step 1's automated half -- sourcing the extension + loading demo
#      1k8p -- runs immediately; see the printed transcript.)
#   3. Follow the printed STEP 1..9 prompts IN ORDER. After each step record
#      the answer + pasted console output into
#      .planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md
#
# Expected observations are kept as EXPECTED comments next to every step.
# ---------------------------------------------------------------------------

if {![info exists ::tk_version]} {
    vmdcon -warn {pick_verify.tcl is a GUI-only verification driver (needs a real VMD GUI, Tk, and a human with a mouse) -- nothing to do in -dispdev text mode.}
} else {

# ===========================================================================
# HELPER PROCS (one-paste console commands for the human)
# ===========================================================================

# pv_say -- print each line through vmdcon -info (the main VMD console is
# always visible; the human copies from its scrollback into VERIFICATION.md).
proc pv_say {lines} {
    foreach l $lines { vmdcon -info $l }
    return
}

# pv_game_mol -- the live game molid (pick_bridge::active_mol while a round
# is live; falls back to game_tab's stashed game_state -- which is STALE
# after cleanup, so callers must catch-guard mol calls).
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

# pv_state -- the all-purpose dump (STEP 1 post-Start and STEP 9 pre-cleanup):
# mouse globals, pick_bridge vars, game_logic state/timer, registry remaining,
# hider indices, and the two hider reps (shown-state + selection + color).
proc pv_state {} {
    set L [list "--- bioCHEMeleon pick-verify state dump ---"]
    # Mouse globals + pick bridge.
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
    # Pure game model: state machine + timer + remaining.
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
    # Molecule-level state (catch-guarded: the molid may be stale post-cleanup).
    set gm [pv_game_mol]
    if {$gm ne {} && ![catch {molinfo $gm get numatoms} natoms]} {
        set sel [atomselect $gm "resname GAM and beta < 0"]
        set hidx [$sel list]
        $sel delete
        lappend L "game molid $gm: $natoms atoms; HIDER indices: $hidx"
        # The two hider reps are the last two added (hiders::hidden_rep /
        # found_rep track them). COMBINED-braces molinfo form only (Pitfall 3).
        foreach {rname r} [list hidden $::biochemeleon::hiders::hidden_rep \
                                found  $::biochemeleon::hiders::found_rep] {
            if {$r < 0 || $r >= [molinfo $gm get numreps]} { continue }
            foreach {style seltext col mat} \
                    [molinfo $gm get "{rep $r} {selection $r} {color $r} {material $r}"] { break }
            set shown [mol showrep $gm $r]
            lappend L "hider rep $rname (idx $r): shown=$shown style=$style color=$col"
            lappend L "    selection: $seltext"
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
    pv_say $L
    return
}

# pv_cleanup_check -- STEP 9 post-Cleanup dump: mouse mode restored? trace
# gone? labels back to baseline?
proc pv_cleanup_check {} {
    set L [list "--- post-Cleanup check ---"]
    if {[info exists ::vmd_mouse_mode]} {
        lappend L "mouse now: mode=$::vmd_mouse_mode submode=$::vmd_mouse_submode"
    }
    if {[info exists ::biochemeleon::pick_bridge::saved_mode]} {
        lappend L "pick_bridge saved (pre-Start): $::biochemeleon::pick_bridge::saved_mode / $::biochemeleon::pick_bridge::saved_submode"
    }
    lappend L "pick_bridge active = $::biochemeleon::pick_bridge::active (expect 0)"
    if {![catch {llength [label list Atoms]} nlab]} {
        set base $::biochemeleon::pick_bridge::label_base
        if {$nlab == $base} {
            lappend L "labels: count=$nlab baseline=$base (CLEAN)"
        } else {
            lappend L "labels: count=$nlab baseline=$base (LEFTOVER: $nlab minus $base)"
        }
    }
    if {![catch {::biochemeleon::game_logic::state} st]} {
        lappend L "game_logic state = $st"
    }
    pv_say $L
    return
}

# pv_hold_labels / pv_release_labels -- STEP 6 fallback-viability probe.
# Raising pick_bridge's label baseline to the current count makes the NEXT
# click's label SURVIVE the game's auto-clean, so the human can inspect it
# with `label list Atoms` (proves a click-created label is a detectable
# event -- the labelpoll fallback's premise). Releasing restores the old
# baseline so the held label is cleaned by the next processed pick/deactivate.
proc pv_hold_labels {} {
    set ::pv_saved_base $::biochemeleon::pick_bridge::label_base
    set ::biochemeleon::pick_bridge::label_base [llength [label list Atoms]]
    vmdcon -info {pv: baseline raised -- the NEXT click's label will SURVIVE auto-clean. Click ONE atom now, then paste: label list Atoms   (expect a {{molid index} value show} entry). Afterwards paste: pv_release_labels}
    return
}

proc pv_release_labels {} {
    if {![info exists ::pv_saved_base]} {
        vmdcon -warn "pv: pv_hold_labels was never called"
        return
    }
    set ::biochemeleon::pick_bridge::label_base $::pv_saved_base
    vmdcon -info "pv: baseline restored to $::pv_saved_base -- the held label will be auto-cleaned on the next processed pick or at Cleanup."
    return
}

# pv_hidden_rep / pv_hide_hidden / pv_show_hidden -- STEP 8 hidden-rep caveat
# probe (UG node140: "Hidden reps cannot be picked and do not show any
# graphics"). Hides the UNFOUND-hider rep (hiders::hidden_rep) without the
# human having to compute rep indices. Clicking where a hider sphere was
# must NOT find.
proc pv_hidden_rep {} {
    set gm [pv_game_mol]
    if {$gm eq {}} { return {} }
    set r $::biochemeleon::hiders::hidden_rep
    if {$r < 0 || $r >= [molinfo $gm get numreps]} { return {} }
    return $r
}

proc pv_hide_hidden {} {
    set gm [pv_game_mol]
    set r [pv_hidden_rep]
    if {$gm eq {} || $r eq {}} {
        vmdcon -warn "pv: no live game / hider rep to hide"
        return
    }
    mol showrep $gm $r off
    vmdcon -info "pv: HID rep $r of molid $gm (the unfound-hider rep; found-rep is [expr {$r + 1}]). Click where a hider sphere was -- EXPECT: no find (hidden reps cannot be picked). Restore with: pv_show_hidden"
    return
}

proc pv_show_hidden {} {
    set gm [pv_game_mol]
    set r [pv_hidden_rep]
    if {$gm eq {} || $r eq {}} {
        vmdcon -warn "pv: no live game / hider rep"
        return
    }
    mol showrep $gm $r on
    vmdcon -info "pv: re-SHOWED rep $r of molid $gm. Click the hider again -- EXPECT: find works again."
    return
}

# ===========================================================================
# PATH RESOLUTION (the entry to auto-source in STEP 1)
# ===========================================================================
# [info script] is empty under `vmd -e` -- only trust it when non-empty;
# otherwise fall back to cwd-relative vmd/biochemeleon.tcl (the staged
# headless run and the GUI flow both cd to the staging root first).
set pv_entry {}
set pv_iscript [info script]
if {$pv_iscript ne {}} {
    set pv_cand [file normalize [file join \
            [file dirname [file normalize $pv_iscript]] .. biochemeleon.tcl]]
    if {[file exists $pv_cand]} { set pv_entry $pv_cand }
}
if {$pv_entry eq {}} {
    if {[catch {file normalize vmd/biochemeleon.tcl} pv_cand] == 0
            && [file exists $pv_cand]} {
        set pv_entry $pv_cand
    }
}

# ===========================================================================
# SESSION SETUP -- the automated half of STEP 1 (idempotent, messages on)
# ===========================================================================

vmdcon -info {=================================================================}
vmdcon -info {== bioCHEMeleon Phase-16 GUI pick-contract verification (16-12) ==}
vmdcon -info {== Record every answer into .planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md}
vmdcon -info {=================================================================}

# 1. Source the extension if this session doesn't have it yet.
if {![namespace exists ::biochemeleon]} {
    if {$pv_entry eq {}} {
        vmdcon -err {pv: cannot find vmd/biochemeleon.tcl -- cd to the staging root (tmp/biochemeleon-vmd) and re-source: source vmd/tests/pick_verify.tcl}
        return
    }
    vmdcon -info "pv: sourcing the extension ($pv_entry) ..."
    if {[catch {source $pv_entry} err]} {
        vmdcon -err "pv: FAILED to source biochemeleon.tcl: $err -- fix this, then re-run: source vmd/tests/pick_verify.tcl"
        return
    }
} else {
    vmdcon -info "pv: extension already loaded -- skipping source."
}

# 2. Load demo 1k8p if the session has no 1k8p molecule.
set pv_have_1k8p 0
foreach m [molinfo list] {
    if {[string match -nocase {*1k8p*} [molinfo $m get filename]]} {
        set pv_have_1k8p 1
    }
}
if {!$pv_have_1k8p} {
    if {[catch {::biochemeleon::demos::load_demo 1k8p} err]} {
        vmdcon -err "pv: FAILED to load demo 1k8p: $err"
    } else {
        vmdcon -info "pv: loaded bundled demo 1k8p (molid list now: [molinfo list])"
    }
} else {
    vmdcon -info "pv: demo 1k8p already loaded -- skipping load."
}

# ===========================================================================
# THE 9 STEPS (printed; the human performs them in order)
# ===========================================================================

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 1 of 9 -- play setup: Start the game}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {The extension is loaded and demo 1k8p is loaded (above). Now:}
vmdcon -info {  a. Open the dialog: menu Extensions -> bioCHEMeleon}
vmdcon -info {     (or paste:  ::BCM::biochemeleon_tk_cb)}
vmdcon -info {  b. On the Setup tab: set Hider count to 3, then press Start.}
vmdcon -info {  c. WATCH during Start: the 3-2-1 countdown in the Game tab log,}
vmdcon -info {     then GO -- and check the VMD menu Mouse: it should now show}
vmdcon -info {     Pick -> Pick Atom selected (clicking an atom creates a label).}
vmdcon -info {  d. After GO, paste:  pv_state}
vmdcon -info {Record: did the mouse switch to pick mode? Did the Game tab activate}
vmdcon -info {and the timer start at GO? Paste the pv_state dump into VERIFICATION.md.}
# EXPECTED: Mouse menu shows Pick -> Pick Atom; Game tab active with
# 3-2-1-GO in the log; timer ticking from GO; pv_state shows
# mouse mode=labelatom submode=2, pick_bridge active=1 mechanism=trace,
# game_logic state=playing, registry remaining=3, hider indices = the
# 3 highest atom indices (1k8p has 555 real atoms -> expect 555 556 557),
# both hider reps shown=1 (hidden: VDW/Element, found: VDW/'ColorID 7').

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 2 of 9 -- THE LOCK: does a real click fire the trace?}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {Paste this ONE line into the Tk console (an observer trace that}
vmdcon -info {coexists with the game's own; leave it registered for steps 3-9):}
vmdcon -info {trace add variable ::vmd_pick_event write {apply {{args} {global vmd_pick_atom vmd_pick_mol vmd_pick_shift_state; vmdcon -info "PICK ev=$args atom=$vmd_pick_atom mol=$vmd_pick_mol shift=[info exists vmd_pick_shift_state]"}}}}
vmdcon -info {Then click a hider VDW sphere (see the HIDER indices in your pv_state}
vmdcon -info {dump; if a sphere is hard to spot, click ANY atom -- the trace fires}
vmdcon -info {for any pick, and the Game tab log tells you hit vs miss).}
vmdcon -info {Record: did a line 'PICK ev=...' appear? Copy it EXACTLY: the ev=}
vmdcon -info {args triple, atom=<index> (expect a 0-based index; a hider hit is}
vmdcon -info {one of the HIDER indices), mol=<molid> (expect the game molid),}
vmdcon -info {shift=1/0 (press+hold Shift for one of the clicks to see shift=1).}
# EXPECTED (this single step locks Mechanism A -- trace ::vmd_pick_event):
# one 'PICK ev=::vmd_pick_event {} write' line per click; vmd_pick_atom =
# 0-based atom index; vmd_pick_mol = the game molid; shift present (0, or 1
# with Shift held). A hider click ALSO logs 'Found one! N remaining'.

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 3 of 9 -- submode check: query mode (pick 0)}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {Paste:  mouse mode pick 0}
vmdcon -info {Click an atom. Record: did PICK still fire? Did a label get created?}
vmdcon -info {Then restore pick-atom mode:  mouse mode pick 2}
vmdcon -info {(or click the Pick radio on the Game tab panel).}
# EXPECTED: pick 0 is QUERY mode. Research prediction: the event may fire
# but labels are NOT created in query mode (the labelpoll fallback would
# be dead there). Either answer is fine -- record what you saw.

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 4 of 9 -- mouse callback independence}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {Paste:  mouse callback off}
vmdcon -info {(This is VMD's default state; this step proves it stays default.)}
vmdcon -info {Click an atom again. Record: did PICK still fire? Did the find work?}
# EXPECTED: still fires -- www.tcl (VMD's own pick consumer) never enables
# mouse callback, and UG 9.3.23 says callback gates only the HOVER
# (_silent) variables. If a click only fired WITH callback on, PickBridge
# must add `mouse callback on` at activate (Task 3 decision table).

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 5 of 9 -- Rotate/Pick toggle (hotkey + panel)}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {a. Press  r  (or paste: mouse mode rotate). Drag to rotate the view,}
vmdcon -info {   then click an atom. Record: view rotates? PICK fired?}
vmdcon -info {b. Toggle picking back ON via the Game tab panel (the Rotate/Pick}
vmdcon -info {   radios -- or paste: ::biochemeleon::pick_bridge::set_view_mode pick)}
vmdcon -info {   Click an atom. Record: does finding work again?}
# EXPECTED: in rotate mode clicks do NOT pick (no PICK line, no find) and
# the view rotates; after toggling back to Pick, clicks find again. The
# panel label should read Mouse: Rotate / Mouse: Pick accordingly.

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 6 of 9 -- label side-effects + fallback viability}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {a. After a few finds so far: did labels pile up on the clicked}
vmdcon -info {   atoms in the viewer? (The game auto-deletes each click's label.)}
vmdcon -info {b. To prove a click-created label is DETECTABLE (the labelpoll}
vmdcon -info {   fallback's premise), paste:  pv_hold_labels}
vmdcon -info {   Click ONE atom, then paste:  label list Atoms}
vmdcon -info {   Record the new entry (format {{molid index} value showstate}).}
vmdcon -info {   Then paste:  pv_release_labels}
# EXPECTED: (a) view stays clean -- no accumulating labels; (b) the held
# click DOES appear in label list Atoms (that is what VMD's Pick Atom mode
# does on click), proving the labelpoll fallback could detect clicks.

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 7 of 9 -- phantom callbacks-list falsification}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {Paste these TWO lines into the Tk console:}
vmdcon -info {proc phantom_cb {args} { vmdcon -info "PHANTOM FIRED" }}
vmdcon -info {catch {lappend ::vmd_pick_atom_callbacks phantom_cb}}
vmdcon -info {Click several atoms. Record: does 'PHANTOM FIRED' EVER appear?}
# EXPECTED: never -- ::vmd_pick_atom_callbacks is a phantom (not in the
# UG, not in shipped scripts, not pre-created; lappend merely creates the
# variable). Confirms the compat shim must stay a no-op.

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 8 of 9 -- hidden-rep caveat (UG node140)}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {Paste:  pv_hide_hidden      (hides the rep holding UNFOUND hiders)}
vmdcon -info {Click where a hider sphere was. Record: any PICK line? Any find?}
vmdcon -info {Then paste:  pv_show_hidden   and click the hider again: find works?}
# EXPECTED: with the rep hidden, clicking where the hider was finds
# NOTHING (hidden reps cannot be picked). After re-showing, the find
# works. Confirms: found-marking must never hide a rep containing
# unfound hiders (the game's two-rep design already guarantees this --
# pv_state showed both hider reps shown=1).

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== STEP 9 of 9 -- finish the round: win, then Cleanup}
vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {a. Find ALL 3 hiders (click each VDW sphere; r toggles rotate to}
vmdcon -info {   look around, the panel radios toggle back to Pick).}
vmdcon -info {   Record: found spheres turn GREEN? Remaining counter hits 0?}
vmdcon -info {   Timer stops? Does the 'You win!' box appear WITH the time?}
vmdcon -info {b. After the win box, paste:  pv_state    (record timer frozen at}
vmdcon -info {   the win time, remaining=0, state=won).}
vmdcon -info {c. Press Cleanup (Game tab), then paste:  pv_cleanup_check}
vmdcon -info {   Record: mouse mode restored to what you had before Start}
vmdcon -info {   (fresh session: rotate / -1)? Labels back to baseline?}
# EXPECTED: green found spheres (ColorID 7 rep), remaining 0, timer stops
# at the win moment, win message box shows the elapsed time; after
# Cleanup the user's mouse mode is restored and labels are clean.

vmdcon -info {-----------------------------------------------------------------}
vmdcon -info {== END -- paste this console transcript + your 9 answers into}
vmdcon -info {== .planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md}
vmdcon -info {== (OpenCode reads that file to lock the pick contract -- Task 3.)}
vmdcon -info {-----------------------------------------------------------------}

}
