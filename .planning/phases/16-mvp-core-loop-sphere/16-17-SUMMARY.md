---
phase: 16
plan: 17
subsystem: vmd-picking
tags: [vmd, tcl, tcl85, mouse-mode, pick-contract, pick_bridge, headless-probe, hotkeys]

# Dependency graph
requires:
  - phase: 16
    provides: "pick_bridge.tcl trace mechanism (16-06), GUI-locked pick contract (16-12), 16-16 re-verify record with the BRANCH (c) DISPOSITION"
provides:
  - "Closed pick contract: the first-click quirk is recorded as the LOCKED contract's known behavior (dated header comment + AGENTS.md block); NO open hypotheses remain"
  - "Probe-verified VMD 1.9.3 mouse-mode table: pick 2 = labelatom/2, pick 0 = query/0, 1-arg pick = pick/-1; NO mode-query form exists (usage text is the only introspection)"
  - "Disproof of the wrong-submode story: shipped hotkeys.tcl:112/118 (p = mouse mode pick; 1 = pick 2 '# atom') + the 16-12 won-round GUI record"
  - "Stale AGENTS.md Phase-19 guard sentence corrected (start_game auto-restarts via the 16-13 guard)"
affects: [17.1-rep-generators, 17.2-cartoon-generators, 19-game-tab, future-GUI-verify-sessions]

# Tech tracking
tech-stack:
  added: []
  patterns: ["evidence-gated branch disposition: probe FIRST, touch the mechanism ONLY on proof; arming quirk documented as dispatch-path-bound, not submode-bound"]

key-files:
  created: []
  modified: [vmd/lib/pick_bridge.tcl, vmd/AGENTS.md, .planning/STATE.md]

key-decisions:
  - "16-17 branch (c2) applied: mechanism BYTE-UNTOUCHED; the first-click quirk is the locked contract's known behavior — keyboard p once per round arms delivery, pasted mouse mode commands never arm, labelatom-2 suspicion unproven in text mode"
  - "c1 (engagement-submode change) REFUTED on evidence: the probe + hotkeys.tcl prove pick 2 IS the shipped '# atom' mode; pasted query mode never armed; the 16-12 round was won on pick 2 — arming is dispatch-path-bound, not submode-bound"
  - "mouse callback A/B stays non-blocking per the 16-16 DISPOSITION: zero mouse callback commands added anywhere"

patterns-established:
  - "Probe-first gap closure: headless text-mode probe with catch-wrapped command sweep records rc + output INCLUDING error/usage text as evidence"
  - "Quirk recording pattern: dated header comment in the mechanism file + closed-caveat wording in AGENTS.md + dated STATE.md decision entry"

# Metrics
duration: 11 min
completed: 2026-09-03
---

# Phase 16 Plan 17: Gap Closure — Pick-Contract Caveat (Branch c) Summary

**Pick contract closed with the mechanism byte-untouched (branch c2): the 16-17 headless probe + shipped hotkeys.tcl disproved the wrong-submode story — keyboard `p` once per round arms delivery (dispatch-path-bound), recorded as the LOCKED contract's known first-click behavior.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-09-03T03:21:32Z
- **Completed:** 2026-09-03T03:32:51Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- **Headless probe executed FIRST (mandated by the disposition):** staged `tmp/gap17probe`, text-mode VMD 1.9.3, log clean (0 `ERROR)`, 0 `bad switch`, Exiting normally). Captured the full mouse-mode table via the `::vmd_mouse_mode`/`::vmd_mouse_submode` globals: `pick 2` → `labelatom/2`, `pick 0` → `query/0`, `labelatom 2` → `labelatom/2`, 1-arg `mouse mode pick` (the hotkey-p form) → `pick/-1`. Proved NO mode-query form exists: `mouse mode`/`mouse`/`mouse location` all error rc=1 with the usage text (the binary's only introspection; it lists all 19 mode names); `menu mouse` returns menu-only usage.
- **Branch (c) consequence applied exactly once, as c2:** `pick_bridge.tcl` gained ONE dated FIRST-CLICK QUIRK header comment; activate/deactivate/set_view_mode, the `{args}` signature, molid/index filters, label hygiene, rc==1 classifier, and the phantom shim are all byte-identical (diff vs HEAD = 14 comment insertions only). Smoke untouched.
- **c1 refuted on evidence (no speculation):** `vmd-ref/scripts/hotkeys.tcl:112/114/118` proves `p` = `mouse mode pick`, `0` = `pick 0` "# query", `1` = `pick 2` "# atom" — the bridge's engagement IS the documented atom-pick mode. With the GUI record (16-12 round WON on pick 2 + fresh-restart picks worked with no `p`; 16-16 pasted query/1-arg forms never armed), the wrong-submode story is disproven: arming is dispatch-path-bound (user-key binding vs pasted text command), not submode-bound. Text mode cannot fire picks, so delivery is unprobeable headlessly.
- **Docs close-out:** `vmd/AGENTS.md` picking section retitled LOCKED (from LOCKED-WITH-CAVEATS); the UNRESOLVED/pending-re-verify + callback-hypothesis bullets replaced with the verified FIRST-CLICK QUIRK block (player guidance: press `p` or `1` once on the display); CONFIRMED facts, panel-checkbox desync, and the text-mode-smoke warning kept. The stale Phase-19 sentence ("no active-game guard… 561-atom… Segments: 3") rewritten to the true post-16-13 state (auto-restart guard, headless-proven 16-15, GUI-confirmed 16-16); no-Cleanup/Restart-buttons + Setup-Reset fields-only facts kept.
- **Regression green on fresh staging:** `tmp/gap17` — phase16_pick_smoke.tcl and phase16_smoke.tcl (capstone) both `BCHM_SMOKE_RESULT PASS=1 FAIL=none`, full-log scan 0 `ERROR)` / 0 `bad switch`, both "Exiting normally".
- **STATE.md:** one dated decision entry (line 72) closing the 16-17 outcome with the probe evidence.

## Task Commits

Each task was committed atomically:

1. **Task 1: Probe + apply the branch-(c) verdict to pick_bridge.tcl (c2 record)** - `3187e2e` (docs)
2. **Task 2: Docs close-out + regression sweep** - `e8f3ef5` (docs)

## Files Created/Modified
- `vmd/lib/pick_bridge.tcl` - ONE dated FIRST-CLICK QUIRK header comment (mechanism byte-untouched)
- `vmd/AGENTS.md` - picking section caveat CLOSED (LOCKED; first-click-quirk known-behavior block); Phase-19 guard sentence corrected
- `.planning/STATE.md` - dated 16-17 decision entry (probe evidence, c2 verdict, regression green)

Probe/regression artifacts (gitignored, for reproducibility): `tmp/gap17probe/probe_mouse_table.tcl`, `tmp/gap17probe_out.txt`, `tmp/gap17/` staging, `tmp/gap17_pick.txt`, `tmp/gap17_cap.txt`.

## Decisions Made
- **Branch c2 selected by evidence, not by the "inconclusive" shortcut:** the probe DID distinguish the mode names, but the c1 gate ("probe proves the wrong-submode story") is not met — the story is disproven by hotkeys.tcl + the GUI record, and text mode cannot probe delivery. The c2 consequence (mechanism byte-untouched + dated quirk comment) is applied; the stronger rationale is recorded in the header/AGENTS/STATE.
- **Zero `mouse callback` commands anywhere** — the A/B is downgraded non-blocking per the 16-16 DISPOSITION; no `mouse callback` probe commands were issued either.
- **No smoke or mechanism edits** — the pick smoke's existing labelatom/2 assertions remain correct (they match the probe's measured mapping).

## Deviations from Plan

**Interpretation note (branch-selection wording, outcome identical):** the plan's c2 parenthetical reads "probe INCONCLUSIVE — no query form works in text mode", while the actual probe found the mode table IS name-distinguishable (globals move) but offers no query form and cannot probe delivery — and the c1 gate is refuted by the shipped hotkey table + GUI record. The applied consequence is exactly c2's (mechanism byte-untouched, ONE dated header comment, docs closed with that wording); no code behavior changed. Selection followed the DISPOSITION's decision rule ("c1 … if a headless probe proves the wrong-submode story") — the story is disproven, not proven.

Otherwise: none - plan executed exactly as written.

## Issues Encountered
None. The probe ran clean first try; both regression smokes passed first try.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 16 plans 16-01..16-17 all complete; the pick contract is LOCKED with no open hypotheses: trace mechanism primary (round won through it, exact PICK values on record), labelpoll dormant fallback, phantom shim no-op, first-click quirk documented with player guidance (`p`/`1` once per round if finds don't register).
- No deferred GUI obligations from this plan (c2 requires none; c1's one-click confirm would only have applied to a submode fix). A future GUI session may optionally sanity-check the recorded quirk behavior.
- The phase verifier owns the STATE.md Current Position roll-up (untouched here per the plan).

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-09-03*
