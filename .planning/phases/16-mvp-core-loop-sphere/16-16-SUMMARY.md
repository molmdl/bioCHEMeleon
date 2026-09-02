---
phase: 16-mvp-core-loop-sphere
plan: 16
subsystem: testing
tags: [vmd, tcl, gui-verification, pick-contract, human-verify, trace-observer, active-game-guard]

# Dependency graph
requires:
  - phase: 16-12
    provides: 16-VERIFICATION.md session-1 record (LOCKED-WITH-CAVEATS) + re-verify driver vmd/tests/pick_verify.tcl (two-paste pv_observe observer, STEP 4 callback A/B, pv_cleanup helper)
  - phase: 16-13/16-14/16-15
    provides: active-game guard (game.tcl self-guarding start_game + dialog.tcl on_start deactivate) — the code under GUI re-check in this plan
provides:
  - GUI-verified active-game guard on BOTH paths (after-win same-target Start — the exact session-1 defect — and mid-round different-target Start): 558 atoms / Segments: 2, never 561/Segments 3; Truth 7 human-verified
  - Exact PICK event values captured via the paste-safe observer (PICK atom=557 mol=1 shift=1 + 556/36/555) — session-1's INCONCLUSIVE capture artifact CLOSED
  - First-click-quirk root-cause facts: clicks before a keyboard p press land in labelatom submode 2 (labels only, count never changes); ONE p press per round arms delivery for the whole round; pasted `mouse mode pick 0|pick` never arms
  - 16-17 BRANCH (c) disposition + standing user process directive (driver-automated future human-verify sessions)
affects: [16-17 pick-bridge mouse-mode probe, phase-16 verification roll-up, phase-19 cleanup/restart UX]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "paste-safe two-paste trace observer (pv_observe) — proven in-GUI, captured exact vmd_pick_* values"
    - "guard auto-restart semantics (clean up prior round, start fresh on the caller's target) — GUI-confirmed both paths"
    - "driver-automated human-verify pattern (auto-issue commands + auto-log to file) — mandated for ALL future verify sessions"

key-files:
  created:
    - .planning/phases/16-mvp-core-loop-sphere/16-16-SUMMARY.md
  modified:
    - vmd/tests/pick_verify.tcl (Task 1: STEP 10 + conditional 4C)
    - .planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md (Task 3: re-verify section appended — NOT committed by this plan; orchestrator bundles)
    - .planning/STATE.md (Task 3: one dated decision entry)

key-decisions:
  - "Callback A/B DOWNGRADED to non-blocking: clean-session finds fired in the untouched default callback state (no mouse callback command ever pasted); 'User Pick:' echo is callback-state-independent (session-1 inference weakened)"
  - "16-17 = BRANCH (c): headless-probe VMD 1.9.3's mouse-mode table (what `mouse mode pick 2` selects; whether a mode query exists), then EITHER (c1) fix the bridge's engagement submode if the wrong-submode story is proven (GUI confirm = ONE Start + ONE click) OR (c2) record the p-press as the LOCKED contract's known first-click quirk (vmd/AGENTS.md + pick_bridge header), mechanism byte-untouched"
  - "STANDING USER DIRECTIVE: future human-verify sessions MUST be simpler — driver auto-issues commands and auto-logs to a file; user pastes only what is strictly required before real clicks; everything probeable moves to headless tests"

patterns-established:
  - "Honest PARTIAL recording: untested items marked NOT COMPLETED / NOT REACHED, never guessed; freeze recorded as OBSERVATION without attribution"

# Metrics
duration: not fully recorded (Task 1 ran in a prior session; Task 3 closing session ~5 min)
completed: 2026-09-03
---

# Phase 16 Plan 16: Re-verify driver + partial GUI re-verify session Summary

**Active-game guard GUI-verified on both paths (558 atoms/Segments: 2, never stacked) and exact PICK values captured (atom=557 mol=1 shift=1); session derailed PARTIAL — callback A/B downgraded to non-blocking, first-click quirk (keyboard p per round) handed to 16-17 as BRANCH (c).**

## Performance

- **Duration:** not fully recorded (Task 1 ran in a prior session; Task 3 closing session ~5 min)
- **Started:** Task 1 prior session (timestamp not recorded); Task 3 2026-09-02T20:11:06Z
- **Completed:** 2026-09-03
- **Tasks:** 3 (Task 1 complete; Task 2 = human-verify checkpoint answered PARTIAL; Task 3 = record + close)
- **Files modified:** 3

## Accomplishments

- Re-verify driver extended: STEP 10 (double-start guard re-check + freeze probe) + conditional STEP 4C (callback restore), staged, headless-guard clean — commits c64cc37 + d60585b.
- Human re-verify session ran PARTIAL but captured DECISIVE evidence: guard re-check PASS both paths (Truth 7 human-verified), exact PICK values captured (session-1 capture artifact CLOSED), first-click-quirk root cause identified, callback hypothesis downgraded to non-blocking, freeze recorded as an unattributed observation.
- 16-VERIFICATION.md re-verify section written honestly (NOT COMPLETED items marked, never guessed) + the 16-17 BRANCH (c) disposition line; STATE.md decision entry added.

## Task Commits

1. **Task 1: Extend pick_verify.tcl (STEP 10 + conditional 4C)** - `c64cc37` (feat: retitle driver steps to of-10 + conditional STEP 4C restore) + `d60585b` (feat: add STEP 10 guard re-check + freeze probe; update END banner)
2. **Task 2: Run the re-verify session (human-verify checkpoint)** - no commits (GUI human session; answered PARTIAL — see Deviations)
3. **Task 3: Record the re-verify session** - this docs commit (16-16-SUMMARY.md + STATE.md; 16-VERIFICATION.md deliberately NOT committed — orchestrator bundles at roll-up)

## Files Created/Modified

- `vmd/tests/pick_verify.tcl` - STEP 10 (after-win + mid-round guard re-check, freeze probe) + conditional STEP 4C (restore only when the A/B actually ran)
- `.planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md` - appended "# Re-verify session (plan 16-16, 2026-09-03) -- PARTIAL" section: five verdicts, root-cause facts, guard-PASS log excerpts, verbatim PICK capture, freeze observation, cosmetic Phase-19 notes, user process directive, 16-17 disposition
- `.planning/STATE.md` - one dated decision entry (re-verify outcome + process directive + 16-17 pointer)
- `.planning/phases/16-mvp-core-loop-sphere/16-16-SUMMARY.md` - this file

## Decisions Made

- **Callback A/B downgraded to non-blocking** — the clean control session's finds fired in the untouched default callback state (`User Pick: mol4 atom:425` echoes with no `mouse callback` ever pasted), so session-1's "echo ⇒ callback on" inference is weakened to "console echo, callback-state-independent". `mouse callback on/off` pairing is NOT required for 16-17.
- **16-17 = BRANCH (c)** — the open item is the FIRST-CLICK QUIRK (keyboard `p` once per round is the only working re-arm; pasted `mouse mode pick 0|2` never arms; `pv_state` showed `mode=labelatom submode=2` after the bridge's engagement). 16-17 headless-probes VMD 1.9.3's mouse-mode table, then either fixes the engagement submode (c1, GUI confirm = ONE Start + ONE click) or documents the quirk (c2, mechanism byte-untouched).
- **Standing user process directive** — future human-verify sessions are driver-automated (auto-issue + auto-log to file); user pastes only what is strictly required; everything probeable moves to headless tests.

## Deviations from Plan

### Process deviations (documentation, not code)

**1. Task 1 executed via two micro-edits after two full-context attempts stalled**
- **Found during:** Task 1 (prior session)
- **Issue:** two full-context execution attempts stalled (long-file edit reliability)
- **Fix:** switched to two surgical micro-edits (retitle + conditional 4C in c64cc37; STEP 10 + END banner in d60585b); staged; headless guard clean
- **Committed in:** c64cc37, d60585b

**2. Task 2 checkpoint answered PARTIAL — session derailed but decisive**
- **Found during:** Task 2 (human-verify checkpoint)
- **Issue:** the user found the 10-step paste procedure too complicated, got lost at STEP 2 paste 2 of 2, and stopped; the clean control session then captured the decisive evidence instead
- **Fix:** Task 3 records the honest PARTIAL state (A/B NOT COMPLETED, pv_cleanup NOT REACHED) with the five-verdict resume signal filled truthfully; the user's process directive (simpler, driver-automated sessions) is recorded as a standing decision
- **Files modified:** 16-VERIFICATION.md, STATE.md

---

**Total deviations:** 2 process-level (1 execution-strategy change, 1 partial checkpoint) — zero code deviations.
**Impact on plan:** Guard re-check (the plan's primary GUI deliverable) PASSED on both paths; the unpicked items (A/B, pv_cleanup) are either downgraded to non-blocking (callback) or explicitly carried to 16-17. No scope creep.

## Issues Encountered

- One freeze OBSERVED in the driver session right after the post-win guard restart (log ends, no "Exiting normally"); ZERO in the clean control session running the identical guard flow. Attribution unknown (pv_observe per-fire errors vs VMD 1.9.3 flakiness) — recorded as observation, no speculation; open question (c) partially answered.
- Cosmetic Phase-19 notes from the user: hiders remain visible after a win (MVP design — no Cleanup button yet); Setup-Reset clears fields only (known); restored-original molecules accumulate in the loaded-objects dropdown after restarts; the target dropdown can go stale (driver session listed only `biochemeleon_game`, clean session showed both `1znf` and `biochemeleon_game`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **16-17 (pick-bridge mouse-mode probe) is unblocked** with a precise mandate: BRANCH (c) — headless-probe the VMD 1.9.3 mouse-mode table first; mechanism byte-untouched unless the wrong-submode story is proven.
- **Truth 7 (loop integrity) is human-verified** — the active-game guard holds in the GUI on both paths; the double-start defect observed in session 1 is confirmed fixed.
- **Truth 3 (pick contract)** remains LOCKED-WITH-CAVEATS with the caveat list SHRUNK: exact values captured, callback hypothesis downgraded; the remaining caveat is the first-click quirk (c1/c2 decision in 16-17).
- **Concern:** future human-verify sessions must follow the user's process directive (driver-automated, minimal pastes) or they will derail again.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-09-03*
