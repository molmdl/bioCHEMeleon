---
phase: 16-mvp-core-loop-sphere
plan: 03
subsystem: game
tags: [tcl, vmd-1.9.3, state-machine, countdown, timer, tcltest, pure-layer, game-loop]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: pure-layer namespace + tcltest-under-headless-VMD harness pattern (test_registry.test BCHM_TEST_RESULT marker, [pwd]-based source path)
  - phase: 15-mutation-safety-hider-registry
    provides: registry.tcl pure-module precedent (error-on-illegal-op via `error`, purity gate grep pattern, re-source contract); game.tcl composition root that 16-08's on_pick will extend with game_logic calls
provides:
  - "::biochemeleon::game_logic — PURE game-loop decision layer: explicit idle -> countdown -> playing -> won state machine with error-guarded transitions"
  - "countdown_tick {label done} contract: {\"3\" 0} {\"2\" 0} {\"1\" 0} then {\"GO!\" 1}, error ticked past GO, state stays countdown until begin_play"
  - "Drift-free clock-seconds epoch timer started ONLY at begin_play; optional trailing `now` arg on timer_start/timer_elapsed/finish_win for deterministic tests"
  - "finish_win double-win guard (errors unless playing) + frozen timer_elapsed_final"
  - "format_mmss M:SS + log model (log_append formats/appends/returns; kinds countdown/miss/already/found/win)"
  - "15-case tcltest suite green under headless VMD (vmd/tests/test_game_logic.test)"
affects: [16-08 (on_pick consumes state gate + log_append + finish_win + timer_elapsed), 16-09 (game_tab consumes round_reset/begin_countdown/countdown_tick/begin_play + after-chains + text-widget log VIEW), entry source-order wiring (pure-lib source line for game_logic.tcl)]

# Tech tracking
tech-stack:
  added: []  # stdlib tcl only (clock, dict-free plain lists, switch, format)
  patterns: [explicit-state-machine-with-error-guards (v1 implicit _started flag -> explicit machine, pick callbacks gate on state==playing), optional-trailing-now-arg (clock-seconds injection for tcltest determinism), ticks-remaining-including-GO countdown encoding, log-model-returns-formatted-line (text widget is a VIEW)]

key-files:
  created:
    - vmd/lib/game_logic.tcl
    - vmd/tests/test_game_logic.test
  modified: []

key-decisions:
  - "countdown_steps encodes TICKS REMAINING INCLUDING the GO tick (begin_countdown arms 4; label = post-decrement value, 0 means GO) — the only encoding self-consistent with the binding 4-tick test contract + tick-5 error + begin_play's countdown_steps==0 GO guard, using exactly the 5 planned state vars"
  - "Optional trailing `now` argument on timer_start/timer_elapsed/finish_win (empty = [clock seconds]) — production callers never pass it; tests inject fixed epochs (1000/1065 -> 65)"
  - "timer_start is called ONLY from begin_play (04-04 lesson: timer measures play time, not countdown time); timer_elapsed returns 0 in idle/countdown"
  - "timer_stop is a documented no-op in the model (GUI owns and cancels its own scheduled callback ids); exported for API symmetry with v1's GameTab timer stop"
  - "log_append errors on unknown kind (registry mark_found precedent — surface caller bugs); countdown/win kinds pass msg verbatim, found embeds the remaining count, miss/already are fixed strings"
  - "Round isolation in tests: EVERY test body starts with round_reset — as a side effect the RED phase failed all 15 cases cleanly (no spurious passes from catch-based tests hitting unknown commands)"

patterns-established:
  - "Explicit state machine + error-guarded transitions as the pure decision layer beneath asynchronous pick callbacks"
  - "Injectable-clock pattern: optional trailing now arg instead of stubbing clock seconds (8.5 tcl has no test doubles)"
  - "Headless VMD invocation fix: pipe `exit` into vmd's stdin (echo exit | vmd ...) with an outer timeout guard — the documented `< /dev/null` pattern leaves Windows vmd.exe blocked at its `vmd >` prompt (WSL /dev/null EOF is invisible to the Windows process) after the script completes"

# Metrics
duration: 25min
completed: 2026-08-30
---

# Phase 16 Plan 03: Pure Game-Loop Logic (State Machine + Timer + Log) Summary

**Explicit idle->countdown->playing->won state machine + drift-free injectable-clock timer + rolling-log model as a PURE tcl namespace, 15/15 tcltest green under headless VMD — the decision layer Plans 16-08 (pick gating/win) and 16-09 (after-chains/log VIEW) consume unchanged**

## Performance

- **Duration:** 25 min
- **Started:** 2026-08-30T09:05:01Z
- **Completed:** 2026-08-30T09:30:17Z
- **Tasks:** 3 (RED suite, GREEN module, gates)
- **Files modified:** 2 created, 0 modified

## Accomplishments
- `vmd/lib/game_logic.tcl`: 12-proc `::biochemeleon::game_logic` pure namespace — round_reset/begin_countdown/countdown_tick/begin_play state machine, timer_start/timer_elapsed/timer_stop/finish_win drift-free timer, state getter, format_mmss, log_reset/log_append/log_lines model
- All illegal transitions raise errors (double begin_countdown, tick past GO, begin_play from idle/mid-countdown, finish_win twice) — the machine enforces idle -> countdown -> playing -> won by construction
- Timer is drift-free (absolute clock-seconds epoch delta, never a tick counter), starts ONLY at begin_play (GO), freezes on finish_win, and is deterministic in tests via the optional trailing `now` argument
- 15/15 tcltest cases green under headless VMD: RED Total=15 Failed=15 -> GREEN Total=15 Passed=15 Failed=0; zero `ERROR)` / `bad switch` false-PASS signals in full output
- Purity gate zero matches (no viewer API, no GUI toolkit, no event-loop calls — `clock` is stdlib); Tcl 8.6 gate zero matches on both files; every `expr` braced

## Task Commits

Each task was committed atomically (TDD RED/GREEN/REFACTOR):

1. **Task 1: RED — failing game_logic suite** - `3716e79` (test)
2. **Task 2: GREEN — implement game_logic.tcl pure layer** - `cdf1013` (feat)
3. **Task 3: REFACTOR + gates** - no commit (code review found no cleanup-worthy issues; gates clean, suite re-verified green)

## Files Created/Modified
- `vmd/lib/game_logic.tcl` - PURE game-loop decision layer: state machine + timer + log model (257 lines incl. contract documentation header)
- `vmd/tests/test_game_logic.test` - 15-case tcltest suite with BCHM_TEST_RESULT marker (registry harness pattern; every body starts with round_reset)

## Decisions Made
- **countdown_steps = ticks-remaining-including-GO (begin arms 4, not 3):** the plan text said "sets countdown_steps 3", but that is arithmetically incompatible with the binding test contract (4 successful ticks {3 0}{2 0}{1 0}{GO! 1}, 5th tick errors, begin_play requires countdown_steps==0) with one decrement per tick, no separate done flag among the 5 planned state vars, and a `> 0` error guard. GO fires as the counter reaches 0; the counter then sits at exactly 0, which begin_play's guard reads as "GO fired". countdown_steps is internal (no getter, no test, no consumer reads it) — all observable contracts verbatim. Consumer plans 16-08/16-09 confirmed agnostic (begin_countdown takes no args; 4 ticks).
- **Optional trailing `now` arg for clock injection:** `clock seconds` cannot be stubbed in tcl 8.5, so timer_start/timer_elapsed/finish_win accept an optional now (empty = real clock). Tests inject fixed values; production (begin_play's internal timer_start call, GUI tick) never passes it.
- **timer_stop = documented no-op:** the model holds no scheduled callbacks (scheduling is the GUI's job, Plan 16-09); exported only for API symmetry with v1's GameTab timer stop.
- **log_append errors on unknown kind:** registry mark_found precedent — a typo'd kind should surface loudly, not silently log garbage.
- **round_reset at the top of EVERY test body:** total isolation between cases; side benefit observed in RED — all 15 cases failed cleanly (catch-based tests never reached their catch because round_reset itself was an unknown command), leaving zero doubt about the RED state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] countdown_steps initial encoding (plan-text off-by-one)**
- **Found during:** Task 1 (writing the RED suite made the contract concrete)
- **Issue:** Plan behavior table said begin_countdown "sets countdown_steps 3", but 3 one-decrement ticks cannot produce the binding 4-tick sequence {"3" 0}{"2" 0}{"1" 0}{"GO!" 1} followed by a 5th-tick error and begin_play's `countdown_steps == 0` GO guard — without an extra done flag that the plan's 5-var state list doesn't include. The plan was internally inconsistent; the tests are the contract.
- **Fix:** countdown_steps counts ticks remaining INCLUDING the GO tick: begin_countdown arms 4; each tick decrements and returns the post-decrement value as the label (0 = GO); tick past 0 fails the `> 0` guard with an error. Encoded in the header COUNTDOWN CONTRACT comment.
- **Files modified:** vmd/lib/game_logic.tcl (begin_countdown/countdown_tick only)
- **Verification:** countdown_sequence + countdown_tick_after_done_errors + begin_play_after_go all green (15/15)
- **Committed in:** cdf1013 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 plan-text inconsistency resolved toward the binding tests)
**Impact on plan:** Internal-encoding only — unobservable through the exported surface; every consumer-facing contract (tick sequence, error behavior, begin_play guard, exported proc list) matches the plan verbatim.

## Issues Encountered
- **Headless VMD invocation hang (environment, not code):** the established `bash -ic '... vmd -dispdev text -e <file> -eofexit < /dev/null'` pattern left Windows vmd.exe blocked at its `vmd >` prompt after the script completed — the Windows process cannot see EOF on WSL's /dev/null. The script itself always ran to completion (marker printed; first RED run proved it), but the bash call hung until timeout. Fix: pipe `exit` into VMD's stdin (`echo exit | timeout 200 bash -ic '... -eofexit'`) so the prompt reads `exit` and VMD terminates cleanly; outer `timeout` guards pathological cases. Works identically for future headless runs.
- **tclsh confirmed absent in this WSL** (plan key facts said so; root AGENTS.md's tclsh mention does not hold in this environment) — headless VMD staging is the only runner, as the plan prescribed. Staged `tmp/biochemeleon-vmd/vmd/` inside the worktree (full vmd/ tree copy, synced before each run).

## User Setup Required
None — no external service configuration required. Pure stdlib tcl; verified entirely under headless VMD in WSL.

## Next Phase Readiness
- **Ready for Plan 16-08 (pick wiring):** on_pick gates scoring on `game_logic::state` == playing, logs via `log_append` (returns the formatted line for the callback), wins via `finish_win` (double-win guarded) and reads `timer_elapsed` for the win line; `format_mmss` pre-formats the win message.
- **Ready for Plan 16-09 (game tab):** start_round calls round_reset + begin_countdown then drives countdown_tick per delayed step (labels logged verbatim as countdown kind); begin_play in the done branch arms the timer; tick loop reads timer_elapsed + format_mmss; the text widget renders log_lines (VIEW, model authoritative).
- **Entry wiring note:** the entry must gain `source [file join $_dir lib game_logic.tcl]` in the pure block (research SS2.1 places it after registry.tcl) — owned by the wiring plan, not this one (files_modified respected).
- **No blockers.** Module is standalone (sources nothing), re-source-safe-enough (documented namespace-eval re-init contract), and passes both language gates.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
