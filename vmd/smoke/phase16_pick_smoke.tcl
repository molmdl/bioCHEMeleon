# vmd/smoke/phase16_pick_smoke.tcl
# Phase-16 pick-machinery headless smoke (Plan 16-06): proves the tcl-side
# PickBridge mechanics -- mouse-mode round-trip, trace register/simulate/
# remove, activate idempotency, molid + index filters, label API/hygiene,
# phantom absence, {args} signature guard. The controller side of the 16-08
# contract is a RECORDING STUB (::biochemeleon::game::on_pick appends to
# ::PICK_LOG): this smoke validates DELIVERY, not the scoring logic (that is
# Plan 16-08 + the capstone).
#
# NOT CLAIMED HERE: real-click firing is GUI-ONLY (text mode cannot fire a
# pick) and is locked by the Phase-16 human-verify checkpoint (Plan 16-12).
# A PASS certifies tcl-side machinery exclusively.
#
# Sources the lib files it needs in dependency order (mirrors the entry minus
# the not-yet-existing 16-08 game.tcl on_pick -- the stub replaces it):
# setup_state, demos, pick_bridge. pick_bridge sources NOTHING (backup.tcl
# precedent).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root) to locate the lib files. VMD does NOT propagate
# tcl exit codes (Pitfall 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?;
# VMD -e catches top-level errors and CONTINUES (possible false-PASS) ->
# every step is wrapped in catch + _bail, and the runner scans the FULL log
# for ERROR) / bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set pre_act_mode UNKNOWN
set pre_act_sub  UNKNOWN
set label_base_obs -1
set PICK_LOG {}

# RECORDING STUB for the 16-08 contract (game.tcl is not sourced; on_pick
# does not exist yet in this wave). Defined BEFORE any activate call.
# NOTE: proc does NOT auto-create missing namespaces ("unknown namespace",
# run1) -- namespace eval must run first.
namespace eval ::biochemeleon::game {}
proc ::biochemeleon::game::on_pick {idx} { lappend ::PICK_LOG $idx }

# ---- Source the lib files in dependency order ([pwd]-relative). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    demos       [file join [pwd] vmd lib demos.tcl] \
    pick_bridge [file join [pwd] vmd lib pick_bridge.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# ---- 1. PHANTOM ABSENCE: ::vmd_pick_atom_callbacks is not pre-created by
#      VMD 1.9.3 (probe1). A user .vmdrc could create it -> log-and-continue,
#      never depend on it either way. ----
if {[info exists ::vmd_pick_atom_callbacks]} {
    puts "BCHM_SMOKE_INFO phantom_callbacks_present (a .vmdrc created it?) -- bridge never reads it"
}

# ---- 2. MOUSE-MODE ROUND-TRIP via set_view_mode (the in-panel toggle's
#      backend): snapshot -> pick -> labelatom/2 -> rotate -> rotate/-1
#      (1-arg rotate resets the submode to -1 -- probe16). ----
set snap_mode [set ::vmd_mouse_mode]
set snap_sub  [set ::vmd_mouse_submode]
if {[catch {::biochemeleon::pick_bridge::set_view_mode pick} e]} {
    _bail svm_pick $e
} elseif {[set ::vmd_mouse_mode] ne "labelatom" || [set ::vmd_mouse_submode] != 2} {
    _bail svm_pick_state "mode=[set ::vmd_mouse_mode] sub=[set ::vmd_mouse_submode] (exp labelatom/2)"
}
if {[catch {::biochemeleon::pick_bridge::set_view_mode rotate} e]} {
    _bail svm_rotate $e
} elseif {[set ::vmd_mouse_mode] ne "rotate" || [set ::vmd_mouse_submode] != -1} {
    _bail svm_rotate_state "mode=[set ::vmd_mouse_mode] sub=[set ::vmd_mouse_submode] (exp rotate/-1)"
}
# Invalid mode must error (and leave the mode alone).
if {![catch {::biochemeleon::pick_bridge::set_view_mode bogus} e]} {
    _bail svm_bogus "expected an error, got none"
} elseif {[set ::vmd_mouse_mode] ne "rotate"} {
    _bail svm_bogus_state "mode=[set ::vmd_mouse_mode] (bogus call must not change mode)"
}

# ---- 3. ACTIVATE with a real molecule: load 1k8p (555 atoms) -> activate ->
#      active flag set + mouse mode == labelatom/2. The demo molid stands in
#      for the game molid (the bridge only needs a molid; start_game is
#      15-04/16-08 territory). ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    # Snapshot BEFORE activate (the restore comparison in step 8 needs the
    # pre-activate state -- run1 bug: captured after, compared labelatom/2).
    set pre_act_mode [set ::vmd_mouse_mode]
    set pre_act_sub  [set ::vmd_mouse_submode]
    if {[catch {::biochemeleon::pick_bridge::activate $orig_molid} e]} {
        _bail activate $e
    } else {
        set label_base_obs [llength [label list Atoms]]
        if {![info exists ::biochemeleon::pick_bridge::active]
                || $::biochemeleon::pick_bridge::active != 1} {
            _bail activate_flag "active not 1"
        }
        if {[set ::vmd_mouse_mode] ne "labelatom" || [set ::vmd_mouse_submode] != 2} {
            _bail activate_mode "mode=[set ::vmd_mouse_mode] sub=[set ::vmd_mouse_submode] (exp labelatom/2)"
        }
        # ---- 4. IDEMPOTENT ACTIVATE: call activate AGAIN. Tcl does not dedupe
        #      traces (probe3: a duplicate registration fires twice) -- the one-
        #      delivery assertion in step 5 is the proof this guard worked. ----
        if {[catch {::biochemeleon::pick_bridge::activate $orig_molid} e]} {
            _bail activate_again $e
        } elseif {$::biochemeleon::pick_bridge::active != 1} {
            _bail activate_again_flag "active not 1 after re-activate"
        }
        # ---- 5. SIMULATED FIRE (probe1 mechanics: a write to ::vmd_pick_event
        #      invokes the {args} handler): atom 3, correct molid -> EXACTLY one
        #      delivery of index 3 (one for a single activate, not two). ----
        set ::vmd_pick_atom 3
        set ::vmd_pick_mol $orig_molid
        set ::vmd_pick_event 1
        if {[llength $PICK_LOG] != 1 || $PICK_LOG ne [list 3]} {
            _bail fire_delivery "PICK_LOG=<$PICK_LOG> (exp exactly {3})"
        }
        # ---- 6. MOLID FILTER: a pick on a foreign molid must be ignored. ----
        set ::vmd_pick_mol 9999
        set ::vmd_pick_event 2
        if {[llength $PICK_LOG] != 1} {
            _bail molid_filter "PICK_LOG=<$PICK_LOG> (exp unchanged {3})"
        }
        set ::vmd_pick_mol $orig_molid ;# restore for later steps
        # ---- 7. INDEX-VALIDITY FILTER: index 99999 > numatoms (1k8p = 555) with
        #      the correct molid must be rejected. ----
        set ::vmd_pick_atom 99999
        set ::vmd_pick_event 3
        if {[llength $PICK_LOG] != 1} {
            _bail index_filter "PICK_LOG=<$PICK_LOG> (exp unchanged {3})"
        }
        # ---- 8. DEACTIVATE: trace gone + mouse mode restored + only OUR labels
        #      cleaned. Also validates the label API format (probe1/2:
        #      {{molid index} value showstate}, newest at the END). ----
        if {[catch {label add Atoms $orig_molid/0} lerr]} {
            _bail label_add $lerr
        } else {
            set labels_now [label list Atoms]
            if {[llength $labels_now] != [expr {$label_base_obs + 1}]} {
                _bail label_count "count=[llength $labels_now] (exp baseline+1 = [expr {$label_base_obs + 1}])"
            }
            lassign [lindex [lindex $labels_now end] 0] lm li
            if {$lm ne $orig_molid || $li ne 0} {
                _bail label_format "newest entry=<[lindex $labels_now end]> (exp molid=$orig_molid index=0)"
            }
        }
        if {[catch {::biochemeleon::pick_bridge::deactivate} e]} {
            _bail deactivate $e
        } else {
            # 8a. trace removed: a further simulated fire delivers nothing.
            set ::vmd_pick_atom 4
            set ::vmd_pick_mol $orig_molid
            set ::vmd_pick_event 4
            if {[llength $PICK_LOG] != 1} {
                _bail trace_removed "PICK_LOG=<$PICK_LOG> (delivery after deactivate!)"
            }
            # 8b. mouse mode restored to the activate-time snapshot.
            if {[set ::vmd_mouse_mode] ne $pre_act_mode || [set ::vmd_mouse_submode] ne $pre_act_sub} {
                _bail mode_restored "mode=[set ::vmd_mouse_mode] sub=[set ::vmd_mouse_submode] (exp $pre_act_mode/$pre_act_sub)"
            }
            # 8c. baseline-guarded label cleanup: the click-label is gone, the
            # baseline (any pre-existing/user labels) untouched.
            set cnt_after [llength [label list Atoms]]
            if {$cnt_after != $label_base_obs} {
                _bail labels_cleaned "count=$cnt_after (exp baseline=$label_base_obs)"
            }
            # 8d. active flag cleared.
            if {[info exists ::biochemeleon::pick_bridge::active]
                    && $::biochemeleon::pick_bridge::active != 0} {
                _bail deactivate_flag "active not 0 after deactivate"
            }
        }
    }
}

# ---- 9. SIGNATURE GUARD: the handler MUST be declared {args} -- a positional
#      signature makes VMD's own write of the traced variable fail and the
#      pick is lost (probe3). ----
if {[info procs ::biochemeleon::pick_bridge::_on_event] eq {}} {
    _bail sig_proc "handler proc missing"
} elseif {[info args ::biochemeleon::pick_bridge::_on_event] ne "args"} {
    _bail sig_args "args=<[info args ::biochemeleon::pick_bridge::_on_event]> (exp args)"
}

# ---- Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
