# vmd/lib/game_logic.tcl
# PURE layer: the game-loop decision core — an explicit round state machine
# (idle -> countdown -> playing -> won), a drift-free timer, and the
# rolling-log model. Stdlib tcl ONLY: no molecular-viewer API, no GUI
# toolkit, no event-loop scheduling. Unit-testable headlessly
# (vmd/tests/test_game_logic.test).
#
# WHY AN EXPLICIT STATE MACHINE (v1 lesson): v1 gated play with an implicit
# `_started` flag. VMD pick callbacks fire asynchronously and can arrive
# before GO or following a win, so every scoring call must be gated by an
# explicit `state == "playing"` check (16-RESEARCH-gametab SS1 row 1,
# SS6.10). Illegal transitions raise an error to surface caller bugs
# (registry::mark_found precedent).
#
# SCHEDULING IS NOT HERE: the countdown delay-chain and the 1 Hz tick loop
# live in the GUI (Plan 16-09, tracked-id timer idiom). This module is the
# pure decision layer the GUI calls once per step — which is exactly what
# makes it tcltest-able.
#
# COUNTDOWN CONTRACT: `countdown_tick` returns a 2-element list {label done}:
#   {"3" 0} {"2" 0} {"1" 0} then {"GO!" 1} on the 4th tick.
# Ticking past GO raises an error. State stays "countdown" until
# `begin_play` (the GUI calls begin_play in the done branch), so the timer
# cannot start before GO. Encoding: `countdown_steps` counts the ticks
# remaining in this countdown INCLUDING the pending GO tick —
# begin_countdown arms it to 4 (three number labels + GO); each tick
# decrements it and the post-decrement value is the label ("3"/"2"/"1"),
# with 0 meaning GO. Once GO has fired the counter is 0 — precisely what
# begin_play requires — and any further tick fails the `> 0` guard.
#
# TIMER MATH (v1 Q11 lesson): drift-free ABSOLUTE-time delta, never a tick
# counter. `timer_start` captures a clock-seconds epoch; every read
# computes `now - epoch`. `clock` is stdlib tcl — allowed in a pure
# module. `timer_start` is called ONLY from `begin_play` (the 04-04
# lesson: the timer measures play time, not countdown time).
#
# TEST INJECTION: `clock seconds` cannot be stubbed, so `timer_start`,
# `timer_elapsed` and `finish_win` each accept an OPTIONAL trailing `now`
# argument (empty means "use [clock seconds]"). Tests inject fixed values
# (e.g. epoch 1000, now 1065 -> elapsed 65). Production callers never pass
# it — note begin_play calls timer_start with no argument.
#
# LOG MODEL: `log_append {kind msg}` formats per kind, appends (newest
# last) and RETURNS the line; `log_lines` returns the accumulated list.
# The GUI text widget (Plan 16-09) is a VIEW — this list is the
# authoritative model. Formats (v1 game.py:170/173/187 + gui countdown):
#
#   kind         line
#   -----------  -------------------------------------------
#   countdown    msg verbatim ("Get ready...", "3", "2", "1", "GO!")
#   miss         Miss!
#   already      Already found!
#   found        Found one! <msg> remaining   (msg = remaining count)
#   win          msg verbatim (caller pre-formats with format_mmss)
#
# RE-SOURCE NOTE: the `namespace eval` below re-initializes the state vars
# on re-source (state resets to idle, log clears). Acceptable — the entry
# sources this file exactly once (same contract as registry.tcl).

namespace eval ::biochemeleon::game_logic {
    # idle -> countdown -> playing -> won.
    variable state "idle"

    # Ticks remaining in the current countdown, including the pending GO
    # tick (see COUNTDOWN CONTRACT above). 0 once GO has fired.
    variable countdown_steps 0

    # clock-seconds epoch captured at GO; 0 until timer_start runs.
    variable timer_epoch 0

    # Elapsed seconds frozen by finish_win — the authoritative final score.
    variable timer_elapsed_final 0

    # Formatted rolling-log lines, newest last.
    variable log_lines [list]

    # Export the public surface (the contract consumed by the Plan 16-08
    # pick handler and the Plan 16-09 game tab).
    namespace export round_reset begin_countdown countdown_tick begin_play \
                     timer_start timer_elapsed timer_stop finish_win \
                     state format_mmss log_reset log_append log_lines
}

# Reset the whole round model: state idle, countdown cleared, timer
# cleared, log cleared. Called by the GUI's start_round (Plan 16-09).
proc ::biochemeleon::game_logic::round_reset {} {
    variable state
    variable countdown_steps
    variable timer_epoch
    variable timer_elapsed_final
    variable log_lines
    set state "idle"
    set countdown_steps 0
    set timer_epoch 0
    set timer_elapsed_final 0
    set log_lines [list]
    return
}

# idle -> countdown. Arms the tick counter (three number labels + GO).
# Errors unless state is idle (a second begin is a caller bug).
proc ::biochemeleon::game_logic::begin_countdown {} {
    variable state
    variable countdown_steps
    if {$state ne "idle"} {
        error "begin_countdown requires state idle (got '$state')"
    }
    set state "countdown"
    set countdown_steps 4
    return
}

# Advance the countdown one step; returns {label done}:
#   {"3" 0} {"2" 0} {"1" 0} then {"GO!" 1} (see COUNTDOWN CONTRACT above).
# The label is the post-decrement counter value; 0 means GO. Errors unless
# counting (wrong state) or ticked past GO. State stays "countdown" — only
# begin_play moves it to playing.
proc ::biochemeleon::game_logic::countdown_tick {} {
    variable state
    variable countdown_steps
    if {$state ne "countdown"} {
        error "countdown_tick requires state countdown (got '$state')"
    }
    if {$countdown_steps <= 0} {
        error "countdown_tick ticked past GO (countdown already done)"
    }
    incr countdown_steps -1
    if {$countdown_steps > 0} {
        return [list $countdown_steps 0]
    }
    return [list "GO!" 1]
}

# countdown -> playing; arms the timer (GO moment — the epoch is captured
# HERE, never at begin_countdown, so the countdown is not billed).
# Errors unless the countdown ran to GO (state countdown, counter 0);
# calling it from idle or mid-countdown is a caller bug.
proc ::biochemeleon::game_logic::begin_play {} {
    variable state
    variable countdown_steps
    if {$state ne "countdown" || $countdown_steps != 0} {
        error "begin_play requires the countdown finished at GO (state '$state', countdown_steps $countdown_steps)"
    }
    set state "playing"
    timer_start
    return
}

# Capture the drift-free epoch. `now` is a test-injection hook (empty =
# real clock); production callers (begin_play) pass nothing.
proc ::biochemeleon::game_logic::timer_start {{now {}}} {
    variable timer_epoch
    if {$now eq ""} {
        set now [clock seconds]
    }
    set timer_epoch $now
    return
}

# Elapsed seconds. playing: absolute delta now - epoch (drift-free — a
# delayed GUI tick cannot lose time). won: the frozen final. Idle or
# countdown: 0 (the timer has not begun).
proc ::biochemeleon::game_logic::timer_elapsed {{now {}}} {
    variable state
    variable timer_epoch
    variable timer_elapsed_final
    if {$state eq "playing"} {
        if {$now eq ""} {
            set now [clock seconds]
        }
        return [expr {$now - $timer_epoch}]
    }
    if {$state eq "won"} {
        return $timer_elapsed_final
    }
    return 0
}

# Documented no-op in the model: the GUI owns (and cancels) its own
# scheduled callbacks — the model holds nothing to stop. Exported for API
# symmetry with v1's GameTab timer stop so call sites read the same.
proc ::biochemeleon::game_logic::timer_stop {} {
    return
}

# playing -> won; freezes the final elapsed. Errors unless playing — this
# is the double-win guard: duplicate pick callbacks (16-RESEARCH SS6.10)
# must not re-score or re-freeze.
proc ::biochemeleon::game_logic::finish_win {{now {}}} {
    variable state
    variable timer_elapsed_final
    if {$state ne "playing"} {
        error "finish_win requires state playing (got '$state')"
    }
    set timer_elapsed_final [timer_elapsed $now]
    set state "won"
    return
}

# Getter the pick handler (Plan 16-08 on_pick) gates scoring on: only
# state "playing" may score.
proc ::biochemeleon::game_logic::state {} {
    variable state
    return $state
}

# Format seconds as M:SS (0 -> "0:00", 65 -> "1:05", 600 -> "10:00").
# int() guards against float input; all exprs braced (8.5 rule).
proc ::biochemeleon::game_logic::format_mmss {secs} {
    set secs [expr {int($secs)}]
    set m [expr {$secs / 60}]
    set s [expr {$secs % 60}]
    return [format "%d:%02d" $m $s]
}

# Clear the rolling log (start of round).
proc ::biochemeleon::game_logic::log_reset {} {
    variable log_lines
    set log_lines [list]
    return
}

# Format one event per the LOG MODEL table, append it (newest last) and
# return the formatted line — the caller (Plan 16-08 pick handler) both
# displays and stores it from this single call.
proc ::biochemeleon::game_logic::log_append {kind msg} {
    variable log_lines
    switch -- $kind {
        countdown {
            set line $msg
        }
        miss {
            set line "Miss!"
        }
        already {
            set line "Already found!"
        }
        found {
            set line "Found one! $msg remaining"
        }
        win {
            set line $msg
        }
        default {
            error "unknown log kind '$kind'"
        }
    }
    lappend log_lines $line
    return $line
}

# The authoritative log model (newest last). The GUI text widget renders
# this; it never parses widget contents back.
proc ::biochemeleon::game_logic::log_lines {} {
    variable log_lines
    return $log_lines
}
