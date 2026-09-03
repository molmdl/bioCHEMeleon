# vmd/lib/pick_bridge.tcl -- MOL BRIDGE: click-to-find wiring (Phase 16,
# LOOP-01's delivery mechanism; the v2 equivalent of v1's PickWizard).
#
# MECHANISM VERDICT (16-RESEARCH-pick.md -- probe-verified 4x headless + the
# UG 9.3/9.4 + shipped www.tcl):
#   PRIMARY   trace add variable ::vmd_pick_event write _on_event (UG Table
#             9.4). The handler MUST be declared {args} -- trace callbacks
#             receive (name1 name2 op); a positional signature makes VMD's
#             OWN write of ::vmd_pick_event fail and the pick is LOST
#             (probe3). Inside: read globals vmd_pick_atom (0-based atom
#             INDEX -- the registry key) + vmd_pick_mol (the molid). These
#             are the ONLY pick globals that exist (UG grep); guard both
#             with info exists.
#   FALLBACK  label-poll diff (label list Atoms vs the activate-time
#             baseline) -- DORMANT, selectable via mechanism = labelpoll.
#             Every pick-atom click creates an atom label (probe1/2), so
#             entries past the baseline are click detections. Insurance for
#             hypothetical VMD builds where the event trace does not fire;
#             never active in the default configuration.
#   PHANTOM   ::vmd_pick_atom_callbacks is NOT a VMD 1.9.3 feature -- not in
#             the UG, not in any shipped script, not pre-created at startup
#             (probe1). activate() performs a one-line no-op lappend shim
#             for hypothetical other builds; NEVER read the list, NEVER
#             gate correctness on it.
#
# FIRST-CLICK QUIRK (the locked contract's known first-click behavior;
# 16-17 headless probe + the 16-16 re-verify, recorded 2026-09-03):
# keyboard `p` ONCE per round arms real pick delivery for the whole
# round (the shipped hotkey -- hotkeys.tcl:112 `mouse mode pick`);
# pasted `mouse mode` commands (pick, pick 0, pick 2) never arm; a
# fresh VMD restart also clears it (16-12). Text mode cannot fire
# picks and offers no mode query (the `mouse` usage text is the only
# introspection -- probe 2026-09-03), so the labelatom-2 suspicion
# stays UNPROVEN there; the probe does map pick 2 == labelatom/2 (the
# shipped "# atom" mode, hotkeys.tcl:118) vs pick 0 == query/0, and
# the GUI record rules out the wrong-submode fix (the 16-12 round was
# won on pick 2; pasted query never armed): arming is dispatch-path-
# bound, not submode-bound. Mechanism byte-untouched (16-17 branch c2).
#
# FORBIDDEN FORMS (probe4 -- the 1.9.3 numeric mouse-mode space inserted
# userpoint at index 4; the UG table is stale relative to the binary):
#   - the numeric form "4 2" under mouse mode == USERPOINT mode (the game
#     would look dead with zero errors);
#   - "pick 0" == QUERY mode, not atom pick;
#   ONLY `mouse mode pick 2` (== labelatom, the GUI "Pick -> Pick Atom"
#   entry, hotkey 1) engages atom picking. Rotate is `mouse mode rotate`
#   (hotkey r; resets the submode to -1 -- probe16).
#
# REAL-CLICK FIRING IS GUI-ONLY: text mode cannot fire a pick, so the C-side
# firing of this machinery is locked by the Phase-16 human-verify checkpoint
# (Plan 16-12). This module + its smoke prove ONLY the tcl-side mechanics
# (register/simulate/remove, mode snapshot/restore, idempotency, filtering,
# label hygiene).
#
# CONTRACT with game.tcl (Plan 16-08, same wave): _on_event forwards exactly
#   ::biochemeleon::game::on_pick <index>
# ONE argument -- the 0-based atom index. game.tcl stashes its own game
# state; this bridge carries none.
#
# STANDALONE: sources NOTHING (backup.tcl precedent). File/namespace parity.
# Tcl 8.5 ONLY (braced expr; catch/error -- no 8.6 control flow). Namespace
# variables declared ONE PER LINE (the 14-04 lesson: the multi-name
# `variable a b` form is a SCALAR SET, not a link).
#
# Label API (probe1/2, HIGH): `label list Atoms` ->
# {{molid index} value showstate}; `label delete Atoms <n>` RENUMBERS the
# remaining labels (delete from the END only); `label delete Atoms all`
# would nuke USER labels -- never issued here.

namespace eval ::biochemeleon::pick_bridge {
    namespace export activate deactivate set_view_mode

    variable active          0     ;# re-entrancy guard (dup trace = double fire, probe3)
    variable mechanism       trace ;# trace | labelpoll -- final value locked by 16-12
    variable saved_mode      {}    ;# user's mouse mode before activate
    variable saved_submode   {}    ;# user's mouse submode before activate
    variable active_mol      {}    ;# game molid (PDB-rebuild CHANGES it -- activate AFTER start_game)
    variable label_base      0     ;# label count at activate (cleanup touches only OUR labels)
    variable labelpoll_after {}    ;# pending after-id of the dormant labelpoll loop
}

# activate {game_molid} -- engage pick-atom mode + register the pick handler.
#
# Call AFTER game::start_game returns -- the PDB-rebuild CHANGES the molid,
# so game_molid is the NEW molid (game_state's game_molid key), never the
# pre-rebuild one.
#
# Idempotent: early return when already active. Tcl does NOT dedupe trace
# registrations (probe3: two identical registrations fired twice per write),
# so a second activate would double-count every find.
proc ::biochemeleon::pick_bridge::activate {game_molid} {
    variable active
    variable mechanism
    variable saved_mode
    variable saved_submode
    variable active_mol
    variable label_base
    variable labelpoll_after
    if {$active} { return }
    # 1. Snapshot the user's mouse state BEFORE switching (fresh-session
    #    defaults, vmdinit.tcl:279-280: rotate / -1).
    set saved_mode    $::vmd_mouse_mode
    set saved_submode $::vmd_mouse_submode
    # 2. Baseline the label count: cleanup below touches ONLY labels created
    #    while we are active (never the user's pre-existing ones).
    set label_base [llength [label list Atoms]]
    set active_mol $game_molid
    # 3. Engage pick-atom mode (GUI "Pick -> Pick Atom", hotkey 1). NOT the
    #    numeric userpoint form, NOT pick 0 (query) -- see the header.
    mouse mode pick 2
    # 4. Register per mechanism. remove-before-add: Tcl does NOT dedupe
    #    traces (probe3), so this is belt-and-suspenders on top of the
    #    active-flag guard.
    if {$mechanism eq "trace"} {
        catch {trace remove variable ::vmd_pick_event write ::biochemeleon::pick_bridge::_on_event}
        trace add variable ::vmd_pick_event write ::biochemeleon::pick_bridge::_on_event
    } else {
        # Dormant labelpoll fallback: seed the diff baseline (a no-op diff at
        # activate time); the after-loop re-arms itself once active == 1.
        ::biochemeleon::pick_bridge::_poll_once
    }
    set active 1
    if {$mechanism eq "labelpoll"} {
        # Arm the first poll tick (the seed call above ran while active was
        # still 0, so _poll_once did not schedule anything itself).
        set labelpoll_after [after 100 ::biochemeleon::pick_bridge::_poll_once]
    }
    # PHANTOM shim: ::vmd_pick_atom_callbacks does not exist in VMD 1.9.3
    # (not in the UG, not in shipped scripts, not pre-created -- probe1);
    # this lappend would silently CREATE it. Kept as a no-op compat gesture
    # for hypothetical other builds ONLY: never read it, never branch on it.
    catch {lappend ::vmd_pick_atom_callbacks ::biochemeleon::pick_bridge::_on_event}
    return
}

# _on_event -- write-trace callback for ::vmd_pick_event.
#
# Signature MUST be {args}: VMD invokes it as (name1 name2 op). A positional
# signature (e.g. {molid atom}) makes VMD's OWN variable write FAIL
# ("wrong # args", probe3) and the pick is lost.
#
# The entire body below the active-gate is catch-wrapped, and errors are only
# REPORTED, never re-raised: an error raised inside a write-trace proc BLOCKS
# VMD's own write of the traced variable (probe3) and the pick event is lost.
# The classifier is `set rc [catch ...]` + rc == 1 (TCL_ERROR) rather than a
# bare truthy catch test: the guards below exit via `return`, which carries
# TCL_RETURN (rc == 2 -- probe16) that a truthy test would misreport.
proc ::biochemeleon::pick_bridge::_on_event {args} {
    if {![info exists ::biochemeleon::pick_bridge::active]
            || !$::biochemeleon::pick_bridge::active} { return }
    variable active_mol
    set rc [catch {
        global vmd_pick_atom vmd_pick_mol
        if {![info exists vmd_pick_atom] || ![info exists vmd_pick_mol]} { return }
        # Molid filter: the session may hold several molecules; the registry
        # is keyed by index WITHIN the game molid, so a same-index pick on
        # another molecule would corrupt found-state.
        if {$vmd_pick_mol ne $active_mol} { return }
        # Index validity: reject out-of-range indices. molinfo on a deleted
        # molecule errors -> silently dropped (nothing is forwarded).
        if {[catch {molinfo $active_mol get numatoms} numatoms]
                || ![string is integer -strict $numatoms]} { return }
        if {$vmd_pick_atom < 0 || $vmd_pick_atom >= $numatoms} { return }
        # Forward to the controller: ONE argument, the 0-based index (the
        # 16-08 contract). game.tcl owns all game state.
        ::biochemeleon::game::on_pick $vmd_pick_atom
        # Hygiene: delete the click-created label (every pick-atom click
        # makes one); baseline-guarded so user labels survive.
        ::biochemeleon::pick_bridge::_clear_new_labels
    } err]
    if {$rc == 1} {
        catch {vmdcon -err "bioCHEMeleon pick handler: $err"}
    }
    return
}

# _clear_new_labels -- delete ONLY labels created after the activate-time
# baseline (the click-created ones). `label delete Atoms <n>` RENUMBERS the
# remaining labels (probe2), so deletion walks from the END down to the
# baseline; `label delete Atoms all` would nuke the user's own labels and is
# never issued. Baseline-guarded: with no new labels this is a no-op.
proc ::biochemeleon::pick_bridge::_clear_new_labels {} {
    variable label_base
    while {[llength [label list Atoms]] > $label_base} {
        set n [llength [label list Atoms]]
        catch {label delete Atoms [expr {$n - 1}]}
    }
    return
}

# _poll_once -- DORMANT labelpoll fallback (mechanism == labelpoll only).
#
# Every pick-atom click creates an atom label (probe1/2), so entries past the
# activate-time baseline are click detections. `label list Atoms` entries are
# {{molid index} value showstate}; newest entries sit at the END (probe2).
# On detection: filter by molid, forward the index, clear the new labels.
# Re-arms itself with `after` ONLY while active in labelpoll mode -- the
# default trace mechanism never schedules a timer.
proc ::biochemeleon::pick_bridge::_poll_once {} {
    variable active
    variable mechanism
    variable active_mol
    variable label_base
    variable labelpoll_after
    set labels [label list Atoms]
    set n [llength $labels]
    for {set i $label_base} {$i < $n} {incr i} {
        lassign [lindex [lindex $labels $i] 0] pmolid pidx
        if {$active_mol eq {} || $pmolid ne $active_mol} { continue }
        if {[catch {::biochemeleon::game::on_pick $pidx} err]} {
            catch {vmdcon -err "bioCHEMeleon pick poll: $err"}
        }
    }
    if {$n > $label_base} {
        ::biochemeleon::pick_bridge::_clear_new_labels
    }
    if {$mechanism eq "labelpoll" && $active} {
        set labelpoll_after [after 100 ::biochemeleon::pick_bridge::_poll_once]
    }
    return
}

# set_view_mode {mode} -- the in-panel Rotate/Pick toggle backend (BTN-07;
# wired by the GUI in Plan 16-09). Pick and rotate are MUTUALLY EXCLUSIVE
# mouse modes in VMD (one global mode), so the player toggles between them;
# the game stays active in both (in rotate mode clicks simply don't pick).
# `mouse mode rotate` (1-arg -- VMD's own hotkey-r form) resets the submode
# to -1 (probe16); `mouse mode pick 2` is the only valid atom-pick engagement.
proc ::biochemeleon::pick_bridge::set_view_mode {mode} {
    switch -- $mode {
        pick    { mouse mode pick 2 }
        rotate  { mouse mode rotate }
        default { error "set_view_mode: pick or rotate" }
    }
    return
}

# deactivate -- remove the trace, clean only OUR click labels, restore the
# user's mouse mode. Call on win/cleanup/restart/dialog-destroy (Plan 16-09
# wires the on_win branch; 16-08 the cleanup/restart paths). ALWAYS restores
# state: mode-set is NOT atomic (probe1: a failed set still writes the
# submode), so a failed restore falls back to `mouse mode rotate`.
proc ::biochemeleon::pick_bridge::deactivate {} {
    variable active
    variable saved_mode
    variable saved_submode
    variable active_mol
    variable labelpoll_after
    if {!$active} { return }
    catch {trace remove variable ::vmd_pick_event write ::biochemeleon::pick_bridge::_on_event}
    # Cancel a pending dormant-labelpoll tick, if any.
    if {$labelpoll_after ne {}} {
        catch {after cancel $labelpoll_after}
        set labelpoll_after {}
    }
    # Clean only OUR labels (baseline-guarded); user labels survive.
    ::biochemeleon::pick_bridge::_clear_new_labels
    # Restore the user's mouse mode; on any failure force rotate (the
    # non-atomic mode-set quirk can leave a hybrid state).
    if {[catch {mouse mode $saved_mode $saved_submode}]} {
        catch {mouse mode rotate}
    }
    set active 0
    set active_mol {}
    return
}
