# vmd/gui/game_tab.tcl -- Phase 16 Game tab (GUI layer / VIEW).
# Tk/ttk. NOT pure -- but it owns NO game decisions: the round state machine,
# timer math and log model live in lib/game_logic.tcl (16-03), found-state in
# lib/registry.tcl, the controller in lib/game.tcl (16-08), and ALL viewer
# mouse switching in lib/pick_bridge.tcl (16-06). This module is only Tk
# widgets, the `after` scheduling of the countdown chain + 1 Hz timer tick,
# and callback registration (16-08 set_callbacks contract: log_cb gets 1 arg,
# remaining_cb 0 args, win_cb 2 args).
#
# VIEW-ONLY STATEMENT: every decision flows through the pure/controller
# layers -- countdown sequence (game_logic::countdown_tick), timer epoch at
# GO (game_logic::begin_play), scoring (game.tcl::on_pick via the pick
# bridge's trace), remaining counts (registry pull in update_remaining).
# The text widget is a VIEW of game_logic::log_lines; nothing parses widget
# contents back.
#
# AFTER-DISCIPLINE (16-RESEARCH-gametab SS4 -- all 7 rules):
#   1. every scheduled id is tracked (after_tick / after_countdown /
#      after_winbox); every re-arm is preceded by catch-cancel;
#   2. cancel points: start_round entry (defensive, v1 gui_game.py:285
#      "Restart mid-game" parity), on_win, and the dialog close handler via
#      stop_all_timers (16-10 extends ::biochemeleon::on_close);
#   3. every callback FIRST guards `winfo exists` and wraps widget writes in
#      catch -- a closed dialog must never raise "bad window path name" on a
#      stray tick (after ids outlive widgets; v1's QTimer died with its
#      widget, this does not);
#   4. conditional re-arm: the tick re-arms ONLY while
#      [game_logic::state] eq "playing"; countdown_step re-arms ONLY while
#      the countdown is not done;
#   5. schedule by VALUE with fully-qualified literal command names
#      (viewmaster.tcl:202-207 idiom) -- never variable-interpolated strings;
#   6. the tick re-schedules at the END of its body so a slow display update
#      cannot pile up callbacks;
#   7. the countdown is a chained ONE-SHOT after 1000, the timer a
#      SELF-RESCHEDULING after 1000; `update` is never called and the event
#      loop is never re-entered (no blocking waits of any kind).
#
# HEADLESS-SAFE AT SOURCE: the file contains ONLY `namespace eval` + proc
# definitions -- zero widget commands execute at source time, so sourcing
# under `vmd -dispdev text` is safe (same contract as setup_tab.tcl; no
# ::tk_version guard is needed at source). Widget rendering is verified at
# the 16-12 GUI human-verify checkpoint (Tk does not load in text mode).
#
# Tcl 8.5.6 constraints (vmd/AGENTS.md): foreach + catch (no 8.6 control-
# flow idioms); brace ALL expr; `variable` declarations ONE PER LINE (the
# multi-name form is a name-VALUE scalar set, not a link -- the 14-04
# lesson); ::tk_version (global qualifier) for any Tk guard.

namespace eval ::biochemeleon::game_tab {
    # Widget-bound state. The four widget-bound vars below are deliberately
    # NOT initialized here: build sets them (so `info exists` is 0 at source
    # time -- the load-gate smoke asserts no widget state exists pre-build).
    variable w                       ;# dialog toplevel handle (set by build)
    variable timer_text              ;# "0:00"           (timer label -textvariable)
    variable remain_text             ;# "Remaining: -"   (remaining label -textvariable)
    variable mode_text               ;# "Mouse: Rotate"  (mouse-mode label -textvariable)
    variable mouse_mode              ;# "rotate" | "pick" (radiobuttons -variable)

    # Round configuration + the tab's own round-state stash (NOT game.tcl's
    # current_state -- this copy feeds the GO branch's pick_bridge::activate).
    variable easy_mode               ;# 1/0 -- set by set_difficulty (default 1)
    variable game_state              ;# dict from start_round (game_molid key)

    # Tracked after ids (empty at source; catch-cancel before every re-arm;
    # stop_all_timers cancels all three).
    variable after_tick       {}
    variable after_countdown  {}
    variable after_winbox     {}

    namespace export build start_round stop_all_timers raise_tab set_difficulty
}

# ---------------------------------------------------------------------------
# build {parent} -- populate the Game tab into $parent (the $nb.game frame).
# Called EAGERLY from open_dialog (16-10 wiring): the tab is cheap to build,
# no after chain exists until Start. Initializes the four widget-bound
# variables BEFORE creating the widgets bound to them. Layout: status row
# (timer / remaining / mouse-mode labels) top fill-x, "Info log:" caption,
# log frame (core-Tk read-only text + PLAIN scrollbar) top fill-both-expand,
# "Mouse mode" labelframe bottom anchor-w.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::build {parent} {
    variable w
    variable timer_text
    variable remain_text
    variable mode_text
    variable mouse_mode

    set w [winfo toplevel $parent]

    # Initialize the widget-bound vars first (labels/radios bind to these;
    # the load-gate smoke asserts they are UNSET until this call).
    set timer_text  "0:00"
    set remain_text "Remaining: -"
    set mode_text   "Mouse: Rotate"
    set mouse_mode  "rotate"

    # -- status row (GAME-02 timer, GAME-03 remaining, mouse-mode label) ----
    set status [ttk::frame $parent.status]
    ttk::label $status.timer  -textvariable ::biochemeleon::game_tab::timer_text
    ttk::label $status.remain -textvariable ::biochemeleon::game_tab::remain_text
    ttk::label $status.mode   -textvariable ::biochemeleon::game_tab::mode_text
    pack $status.timer  -side left -padx 4
    pack $status.remain -side left -padx 12
    pack $status.mode   -side left -padx 12
    pack $status -side top -fill x -padx 8 -pady 4

    # -- "Info log:" caption -------------------------------------------------
    ttk::label $parent.loglab -text "Info log:"
    pack $parent.loglab -side top -anchor w -padx 8

    # -- log frame: CORE-Tk read-only text + PLAIN scrollbar -----------------
    # Plain `scrollbar`, NOT ttk::scrollbar: ttk::scrollbar is listed in
    # STACK.md but was never exercised in VMD's Tk (research SS0.3) -- plain
    # core Tk is the ecosystem-verified idiom (all 5 reference plugins).
    # The text stays DISABLED; every insert goes through on_log_line's
    # state-normal -> insert -> state-disabled -> see-end cycle (Pitfall 6.8).
    set logf [ttk::frame $parent.logf]
    text $logf.log -state disabled -wrap word -height 10 \
        -yscrollcommand [list $logf.sb set]
    scrollbar $logf.sb -command [list $logf.log yview]
    pack $logf.sb -side right -fill y
    pack $logf.log -side left -fill both -expand yes
    pack $logf -side top -fill both -expand yes -padx 8 -pady 4

    # -- "Mouse mode" labelframe: Rotate / Pick atoms radios (LOOP-01 UI) ----
    # Radiobuttons (not a checkbutton): pick and rotate are mutually
    # exclusive viewer states, so the control mirrors reality. -command
    # passes NO arguments -- set_mouse_mode reads the shared variable.
    set mf [ttk::labelframe $parent.mouse -text "Mouse mode" -padding 6]
    ttk::radiobutton $mf.rotate -text "Rotate" -value rotate \
        -variable ::biochemeleon::game_tab::mouse_mode \
        -command {::biochemeleon::game_tab::set_mouse_mode}
    ttk::radiobutton $mf.pick -text "Pick atoms" -value pick \
        -variable ::biochemeleon::game_tab::mouse_mode \
        -command {::biochemeleon::game_tab::set_mouse_mode}
    pack $mf.rotate -side top -anchor w
    pack $mf.pick -side top -anchor w
    pack $mf -side bottom -anchor w -pady 4
    return
}

# ---------------------------------------------------------------------------
# start_round {game_state} -- entry from the Start handler (Plan 16-10).
# Sequence: stop_all_timers FIRST (defensive restart parity) -> reset the
# PREVIOUS round's stale view state (16-14: the frozen timer and the pick
# mouse-mode indicators cannot leak into the new countdown window) -> stash
# the round state -> register the controller callbacks -> reset the pure
# model + arm the countdown -> clear the log view + log "Get ready..." ->
# pull the remaining count ONCE (GAME-03 initial display) -> fire the first
# countdown step DIRECTLY (no delay for "3" -- v1 parity).
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::start_round {game_state} {
    variable w
    variable timer_text
    variable mode_text
    variable mouse_mode

    # 1. Defensive first: cancel any pending timers (Restart mid-game /
    #    repeated Start; v1 gui_game.py:285 "stop any prior timer").
    stop_all_timers

    # 1.5 (16-14, gap-1 GUI half): reset the PREVIOUS round's view state so
    # it cannot leak into the new round's countdown window: the frozen timer
    # and the pick mouse-mode indicators (the bridge is DOWN until GO --
    # on_start deactivated it; the panel must reflect reality). The observed
    # double-Start session left the frozen "5:14" timer and "Mouse: Pick"
    # panel showing during the new countdown while the bridge was down.
    # remain_text needs no reset (update_remaining runs in step 6) and the
    # log is already cleared in step 5. Programmatic variable sets do NOT
    # fire -command (no viewer call happens -- see the countdown_step
    # GO-branch note).
    set timer_text "0:00"
    set mode_text "Mouse: Rotate"
    set mouse_mode "rotate"

    # 2. Stash the round state. NOTE: the parameter shadows the namespace var
    #    of the same name (the setup_tab::select_demo lesson, Pitfall 7 --
    #    a `variable` link cannot override a compiled parameter), so the
    #    stash is written via the fully-qualified path.
    set ::biochemeleon::game_tab::game_state $game_state

    # 3. Register the controller callbacks (16-08 contract: log_cb gets 1
    #    arg, remaining_cb 0 args, win_cb 2 args). Command-prefix VALUES
    #    built with [list] -- never string interpolation.
    ::biochemeleon::game::set_callbacks \
        [list ::biochemeleon::game_tab::on_log_line] \
        [list ::biochemeleon::game_tab::update_remaining] \
        [list ::biochemeleon::game_tab::on_win]

    # 4. Reset the pure model + arm the countdown (3 number labels + GO).
    ::biochemeleon::game_logic::round_reset
    ::biochemeleon::game_logic::begin_countdown

    # 5. Clear the log VIEW (the model was cleared by round_reset), then log
    #    the opener through the model so view and model stay in sync.
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { set wok 0 } else { set wok 1 }
    if {$wok} {
        set log $w.nb.game.logf.log
        if {[winfo exists $log]} {
            catch {
                $log configure -state normal
                $log delete 1.0 end
                $log configure -state disabled
            }
        }
    }
    ::biochemeleon::game_tab::on_log_line \
        [::biochemeleon::game_logic::log_append countdown "Get ready..."]

    # 6. GAME-03 initial display: pull the remaining count once NOW (after
    #    set_callbacks) so the label reads "Remaining: N" from round start.
    #    The remaining callback alone fires only after the first find --
    #    without this the label would show the build-time placeholder all
    #    through the countdown.
    update_remaining

    # 7. Fire the first countdown step DIRECTLY (v1 logs "3" immediately,
    #    then chains the one-shot afters).
    countdown_step
    return
}

# ---------------------------------------------------------------------------
# countdown_step {} -- one step of the 3-2-1-GO chain. The pure sequence
# lives in game_logic::countdown_tick (returns {label done}); THIS proc only
# logs and schedules. The chained ONE-SHOT after 1000 carries the delay
# between steps (id tracked in after_countdown; catch-cancel before every
# re-arm). The tick label is logged ONLY in the not-done branch and "GO!"
# ONLY in the done branch -- the 4th tick's label IS "GO!" (the 16-03
# contract {"3" 0} {"2" 0} {"1" 0} {"GO!" 1}), so logging the label
# unconditionally AND a done-branch "GO!" would emit a duplicate GO! line.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::countdown_step {} {
    variable w
    variable after_tick
    variable after_countdown
    variable game_state
    variable mode_text
    variable mouse_mode

    # Guard FIRST: the dialog may have closed since the previous step
    # scheduled this one (after ids outlive widgets).
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { return }

    lassign [::biochemeleon::game_logic::countdown_tick] label done
    if {!$done} {
        ::biochemeleon::game_tab::on_log_line \
            [::biochemeleon::game_logic::log_append countdown $label]
        catch {after cancel $after_countdown}
        set after_countdown [after 1000 ::biochemeleon::game_tab::countdown_step]
    } else {
        # GO: log "GO!" (the done label), start play -- the drift-free timer
        # epoch is captured HERE (begin_play), never at Start-button press --
        # engage the pick bridge on the game molecule, mirror Pick in the
        # label + radios (a programmatic var set does not fire -command),
        # then start the 1 Hz tick loop.
        ::biochemeleon::game_tab::on_log_line \
            [::biochemeleon::game_logic::log_append countdown "GO!"]
        ::biochemeleon::game_logic::begin_play
        if {[info exists game_state] && [dict exists $game_state game_molid]} {
            ::biochemeleon::pick_bridge::activate [dict get $game_state game_molid]
        }
        set mode_text "Mouse: Pick"
        set mouse_mode "pick"
        catch {after cancel $after_tick}
        set after_tick [after 1000 ::biochemeleon::game_tab::tick]
    }
    return
}

# ---------------------------------------------------------------------------
# tick {} -- the SELF-RESCHEDULING 1 Hz timer tick. Reads the drift-free
# elapsed (absolute epoch delta from game_logic, never a tick counter --
# v1 Q11 lesson) and re-arms at the END of the body ONLY while the model
# state is "playing": an unconditional re-arm would leak a timer forever,
# a missing one would freeze the label.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::tick {} {
    variable w
    variable after_tick
    variable timer_text

    # Guard FIRST (a stray tick after dialog close must die silently).
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { return }

    set elapsed [::biochemeleon::game_logic::timer_elapsed]
    set timer_text [::biochemeleon::game_logic::format_mmss $elapsed]

    # Re-arm ONLY while playing; reschedule at the END of the body so a slow
    # display update cannot pile up callbacks.
    if {[::biochemeleon::game_logic::state] eq "playing"} {
        catch {after cancel $after_tick}
        set after_tick [after 1000 ::biochemeleon::game_tab::tick]
    }
    return
}

# ---------------------------------------------------------------------------
# on_log_line {line} -- THE ONLY proc that inserts into the log text widget
# (Pitfall 6.8: every insert follows the state-normal -> insert ->
# state-disabled -> see-end cycle so the widget is never left editable).
# Invoked as the registered log callback (1 arg) and directly by
# start_round / countdown_step. Guarded + catch-wrapped: a stray call after
# the dialog closed must die silently, never raise a window-path error.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::on_log_line {line} {
    variable w
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { return }
    set log $w.nb.game.logf.log
    if {![winfo exists $log]} { return }
    catch {
        $log configure -state normal
        $log insert end "$line\n"
        $log configure -state disabled
        $log see end
    }
    return
}

# ---------------------------------------------------------------------------
# update_remaining {} -- PULL model (v1 gui_game.py:122-130 parity): read
# the registry counts + format via the PURE formatter, write the label
# variable. Registered as the remaining callback (0 args) and called once
# at the end of start_round (GAME-03 initial display). easy_mode defaults
# to 1 if set_difficulty has not run yet (the SETUP-05 default).
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::update_remaining {} {
    variable easy_mode
    variable remain_text
    if {![info exists easy_mode]} { set easy_mode 1 }
    set total [::biochemeleon::registry::count_remaining]
    set byrep [::biochemeleon::registry::remaining_by_rep]
    set remain_text \
        [::biochemeleon::setup_state::format_remaining $total $byrep $easy_mode]
    return
}

# ---------------------------------------------------------------------------
# on_win {elapsed n_hiders} -- the win callback (2 args: elapsed seconds,
# hider count). Sequence (16-RESEARCH SS1.3 + SS4):
#   1. stop every pending timer (the tick loop must not outlive the round);
#   2. deactivate the pick bridge EXACTLY ONCE (it restores the user's prior
#      viewer mouse state; internally idempotent, but this is its only
#      game-flow call site);
#   3. mode label + radios back to Rotate;
#   4. the win LOG line is ALREADY in the log -- game.tcl (16-08) logs it
#      via the log callback BEFORE invoking this win callback. No second
#      line is added here;
#   5. after a 100 ms render delay (v1 Bug A: let the last visual change
#      land before the modal appears) show the "You win!" box PARENTED TO
#      THE DIALOG (v1 Bug B: parent = the top level). The delayed box is a
#      tracked one-shot with its own winfo guard (_show_win_box).
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::on_win {elapsed n_hiders} {
    variable w
    variable after_winbox
    variable mode_text
    variable mouse_mode

    # 1. Cancel every pending timer (tick + countdown + a stale win box).
    stop_all_timers

    # 2. Pick bridge down exactly once (restores the user's mouse state).
    ::biochemeleon::pick_bridge::deactivate

    # 3. Mode label + radios back to Rotate.
    set mode_text "Mouse: Rotate"
    set mouse_mode "rotate"

    # 5. Delayed + guarded modal win box (parented to the dialog).
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { return }
    catch {after cancel $after_winbox}
    set after_winbox \
        [after 100 [list ::biochemeleon::game_tab::_show_win_box $elapsed $n_hiders]]
    return
}

# ---------------------------------------------------------------------------
# _show_win_box {elapsed n_hiders} -- PRIVATE: the delayed modal win message
# scheduled by on_win. Guarded: the dialog may have closed during the
# 100 ms window. Parent = the dialog toplevel (v1 Bug B).
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::_show_win_box {elapsed n_hiders} {
    variable w
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { return }
    catch {
        tk_messageBox -parent $w -icon info -title "You win!" \
            -message "You found all $n_hiders hiders in [::biochemeleon::game_logic::format_mmss $elapsed]!"
    }
    return
}

# ---------------------------------------------------------------------------
# set_mouse_mode {} -- the radiobuttons' -command handler. NO-ARG canonical
# signature: the widget wiring is
# `-command {::biochemeleon::game_tab::set_mouse_mode}` which passes NO
# arguments -- a 1-arg signature would raise "wrong # args" on the first
# radio click. The radiobutton updates the shared `mouse_mode` variable
# BEFORE firing -command, so the proc reads it. ALL viewer mouse switching
# goes through pick_bridge::set_view_mode -- this tab never issues viewer
# mouse commands directly (save/restore semantics belong to the bridge).
# catch-wrapped: the bridge's viewer call may legitimately fail outside a
# live interactive session.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::set_mouse_mode {} {
    variable mouse_mode
    variable mode_text
    if {![info exists mouse_mode]} { return }
    if {$mouse_mode eq "pick"} {
        set mode_text "Mouse: Pick"
    } else {
        set mode_text "Mouse: Rotate"
    }
    catch {::biochemeleon::pick_bridge::set_view_mode $mouse_mode}
    return
}

# ---------------------------------------------------------------------------
# set_difficulty {easy} -- store the easy-mode flag used by update_remaining
# (GAME-03 easy per-rep breakdown vs hard total-only). Called by the Start
# handler (Plan 16-10) BEFORE start_round. Anything but integer 0 maps to 1
# (easy) -- the SETUP-05 default.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::set_difficulty {easy} {
    variable easy_mode
    if {[string is integer -strict $easy] && $easy == 0} {
        set easy_mode 0
    } else {
        set easy_mode 1
    }
    return
}

# ---------------------------------------------------------------------------
# stop_all_timers {} -- cancel every tracked pending timer id. Called from
# start_round (defensive restart parity), on_win, and the dialog close
# handler (Plan 16-10 extends ::biochemeleon::on_close with this call).
# catch-cancel: cancelling an already-fired id is harmless, and an unset
# variable must never abort the caller.
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::stop_all_timers {} {
    variable after_tick
    variable after_countdown
    variable after_winbox
    catch {after cancel $after_tick}
    set after_tick {}
    catch {after cancel $after_countdown}
    set after_countdown {}
    catch {after cancel $after_winbox}
    set after_winbox {}
    return
}

# ---------------------------------------------------------------------------
# raise_tab {} -- bring the Game tab to the front. ttk::notebook SELECT --
# NEVER `raise` on the child frame (raise does not update the notebook's
# tab state). Called by the Start handler (Plan 16-10).
# ---------------------------------------------------------------------------
proc ::biochemeleon::game_tab::raise_tab {} {
    variable w
    if {![info exists w] || $w eq "" || ![winfo exists $w]} { return }
    catch {$w.nb select $w.nb.game}
    return
}
