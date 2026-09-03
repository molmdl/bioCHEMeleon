---
phase: 16-mvp-core-loop-sphere
verified: 2026-09-03T12:40:00Z
status: passed
score: 7/7 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 5/7
  gaps_closed:
    - "Truth 7 (loop integrity) — active-game guard in game.tcl (16-13) + GUI teardown/reset halves (16-14) + headless regression gate phase16_restart_smoke.tcl (16-15) + GUI re-check PASS both paths both sessions (16-16)"
    - "Truth 3 (pick-contract lock) — exact PICK values captured closing the session-1 capture artifact (16-16); callback A/B downgraded non-blocking per DISPOSITION (16-16); first-click quirk root-caused by headless probe + hotkeys.tcl, recorded as the locked contract's known behavior with the mechanism byte-untouched (16-17 branch c2); vmd/AGENTS.md picking section retitled LOCKED with zero pending-caveat wordings"
  gaps_remaining: []
  regressions: []
gaps: []
human_verification:
  - test: "pv_cleanup restore path (driver STEP 9c) — never reached in either GUI session"
    expected: "Mouse mode restored to saved rotate/-1, labels back to baseline, trace removed"
    why_human: "Real GUI session; restore machinery is evidenced (session-1 9b pv_state saved rotate/-1) but the intended path was never exercised. NOT a phase-16 SC — cleanup is Phase-19 scope; recorded as an open (non-blocking) session item."
  - test: "Optional future GUI sanity-check of the recorded first-click quirk (driver-automated per the standing 16-16 process directive)"
    expected: "Clicks before a keyboard `p` press add labels only; after ONE `p` press, finds register for the whole round"
    why_human: "C-side pick delivery cannot fire in text mode. The quirk is LOCKED as known behavior (16-12 round WON through the trace; 16-16 exact values captured; 16-17 probe + hotkeys.tcl disprove the wrong-submode story) — this is confirmation, not lock evidence."
---

# Phase 16: MVP Core Loop (Sphere) — Re-Verification Report (2)

**Phase Goal:** "The player can play a complete hide-and-seek round with sphere hiders — the PROJECT.md core value. If nothing else works, this loop works. The VMD pick-callback contract is locked here via a GUI human-verify checkpoint."
**Verified:** 2026-09-03T12:40:00Z
**Status:** **passed**
**Re-verification:** Yes — after gap closure (16-13..16-17). Previous: 16-VERIFICATION.md 2026-08-30 gaps_found 5/7 (Truth 3 pick-contract caveats open; Truth 7 loop-integrity guard missing). The 16-12 human checkpoint record and the 16-16 partial re-verify record in 16-VERIFICATION.md remain authoritative for all GUI evidence and are not duplicated here.

**Method:** All 7 must-haves re-checked against the code on disk (guard block position, DI line, 16-14 GUI halves, restart-smoke harness, AGENTS.md caveat wording, c2 zero-`mouse callback` claim). All 8 Phase-16 smokes (7 original + phase16_restart_smoke.tcl) re-run by this verifier on FRESH staging (`tmp/verify16`, `cp -r vmd` — no rm; marker parsed, never `$?`; full logs scanned for BOTH `ERROR)` and `bad switch`). GUI verdicts taken strictly from the recorded human sessions (16-12 + 16-16); no GUI re-run by the verifier.

## Goal Achievement

### Observable Truths (must-haves → ROADMAP SCs + the 2 gap truths)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | **SC1** — Start generates sphere hiders per setup, switches to Game tab, counts down 3-2-1, starts the timer | ✓ VERIFIED | On disk: `mutation.tcl:55-58` real body-swap (`measure minmax` → `generators::sphere_positions` — placeholder-era comments in game.tcl are historical); `game.tcl:138-159` snapshot→mutate→apply→hider-reps→DI-reconstruct ordering; `dialog.tcl` on_start fan-in → `game_tab::start_round`; `game_tab.tcl` one-shot countdown with after-ID tracking. Headless (this session, fresh staging): placement + entry + gametab smokes PASS=1; capstone steps 2-3. GUI: session-1 step 1 "working" (countdown, tab switch, mouse menu switch). |
| 2 | **SC2-mechanism** — a click correctly identifies a registered hider and marks it found | ✓ VERIFIED | On disk: `pick_bridge.tcl:166,210` → `game::on_pick $vmd_pick_atom` (single arg, molid filter + index validity); `game.tcl` on_pick three-way guard + state gate; hiders.tcl user2 two-rep split. Headless: pick smoke + onpick smoke + capstone (REAL `_on_event`-driven scoring incl. miss/hit/already-found/winning-hit) all PASS=1 this session. GUI: a complete round WON through this path (16-12 steps 5-9a); exact `PICK atom=557 mol=1 shift=1` values captured (16-16). |
| 3 | **SC2-lock** — the pick contract is LOCKED (GUI checkpoint closed; no open hypotheses) | ✓ VERIFIED (was ✗ in the 2026-08-30 verification) | 16-12: LOCKED-WITH-CAVEATS — round WON through the trace, labelpoll premise confirmed, phantom callbacks-list falsified in-GUI. 16-16: exact PICK values CAPTURED (session-1 capture artifact CLOSED); callback A/B DOWNGRADED non-blocking (clean-control finds fired in the untouched default callback state; `User Pick:` echo is callback-state-independent); first-click-quirk facts established. 16-17: headless mouse-mode probe (pick 2 = labelatom/2 = the shipped hotkey-`1` "# atom" mode; NO mode-query form; c1 wrong-submode story REFUTED on evidence) → branch c2 applied: ONE dated FIRST-CLICK QUIRK header in `pick_bridge.tcl:26-45`, mechanism byte-untouched (verified this session: diff-scope = comment insertions only; ZERO `mouse callback` commands in lib/gui/smoke — grep count 0). `vmd/AGENTS.md` picking section retitled **LOCKED** with the FIRST-CLICK QUIRK known-behavior block; **zero pending-caveat wordings** (grep for UNRESOLVED / pending / LOCKED-WITH-CAVEATS / hypothesis → 0 matches). No open hypotheses remain. |
| 4 | **SC3** — rolling info box logs clicks/found; remaining count (total + per-rep in easy) decrements | ✓ VERIFIED | On disk: game_logic log model (15/15 tcltest), registry status_of/count_remaining/remaining_by_rep (18/18), setup_state format_remaining (47/47), game_tab on_log_line/update_remaining pull model. Headless: capstone asserts the decrement through the scoring loop (PASS=1 this session). GUI: 16-12 steps 5-9 (count decrements logged during the won round; final `remaining = 0`). |
| 5 | **SC4** — all found → timer stops, winning message shows time taken | ✓ VERIFIED | On disk: game_logic finish_win (freezes elapsed; double-call error), game.tcl win flow, game_tab on_win → deactivate once → delayed parented tk_messageBox with format_mmss. GUI: session-1 step 9a/9b — win box WITH the time; `state=won`, timer frozen 5:14, remaining=0. |
| 6 | **SC5** — pick-vs-rotate control so the player can rotate between picks | ✓ VERIFIED | On disk: `game_tab.tcl:131-137` Rotate/Pick radios → `set_mouse_mode` → `pick_bridge::set_view_mode` (`pick_bridge.tcl:110` `mouse mode pick 2`; :223 rotate) — the tab never issues `mouse mode` directly. GUI: session-1 step 5 panel toggle works (label mode restored via panel). Known minor (documented, accepted): checkbox desync on hotkey `r`. |
| 7 | **Loop integrity** — "if nothing else works, this loop works" (the 2 gap truths: active-game guard + restart regression gate) | ✓ VERIFIED (was ✗) | **Code:** `game.tcl:93-136` ACTIVE-GAME GUARD sits BEFORE `backup::snapshot` (line 138) — cleanup-then-fresh-start with liveness-based target remap + stale-stash catch repair; DI line `game.tcl:154` present and byte-shaped per contract (2 `list apply` occurrences = CRITICAL comment + code, as documented in 16-13). **GUI half (16-14):** `dialog.tcl:203` catch-guarded `pick_bridge::deactivate` (step 3.5) AFTER validate_state (:187) BEFORE `game::start_game` (:207); `game_tab.tcl:163-175` step 1.5 resets timer_text/mode_text/mouse_mode after stop_all_timers. **Headless gate (16-15, re-proven fresh this session):** `vmd/smoke/phase16_restart_smoke.tcl` exists (451 lines), follows the `$failures` capstone pattern (line 121 `set failures [list]`; `_bail` → `::failures`; marker PASS=1 ONLY when empty — tail gate verified), narrative re-proven: Atoms 555→558→557→558→426 with three 555 restores + one 424 load, sentinel sets {555 556 557}/{555 556}/{555 556 557}/{424 425}, `Segments: 2` on every combined reload (NEVER 3), guard INFO 3× with 2 remaps, all 5 stages ok=1, leak guards + survivor scan present. **GUI (16-16, both sessions):** after-win same-target Start (the exact session-1 defect) → original reloaded 555 → fresh 558-atom round, Segments: 2; mid-round different-target Start (1znf) → clean restart then won. Truth 7 human-verified. |

**Score:** 7/7 truths verified (previous verification: 5/7)

### Required Artifacts (gap-closure delta; 16-01..16-12 artifacts carried green from the prior verification + this session's re-runs)

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `vmd/lib/game.tcl` | active-game guard at the single choke point | ✓ VERIFIED | Guard lines 93-136 before snapshot 138; DI line intact; sources nothing; exports unchanged; 8.5-idiom gate 0 |
| `vmd/gui/dialog.tcl` | on_start bridge teardown (step 3.5) | ✓ VERIFIED | Line 203, catch-guarded, after validate_state, before start_game; header flow updated |
| `vmd/gui/game_tab.tcl` | start_round view reset (step 1.5) | ✓ VERIFIED | Lines 163-175: timer 0:00 / Mouse: Rotate / rotate, after stop_all_timers, before stash |
| `vmd/lib/pick_bridge.tcl` | quirk recorded, mechanism byte-untouched | ✓ VERIFIED | Dated FIRST-CLICK QUIRK header lines 26-45; ZERO `mouse callback` commands anywhere; activate/deactivate/set_view_mode logic untouched |
| `vmd/smoke/phase16_restart_smoke.tcl` | gap-1 headless gate, $failures pattern | ✓ VERIFIED | 451 lines; real failures list + conditional marker (false-PASS-proof); 4 public-surface stages; narrative + sentinel + Segments assertions |
| `vmd/AGENTS.md` | caveat CLOSED, no pending wordings | ✓ VERIFIED | Picking section LOCKED; FIRST-CLICK QUIRK block with player guidance; stale Phase-19 guard sentence corrected (auto-restart, headless+GUI proven) |
| `vmd/tests/pick_verify.tcl` | 10-step driver + conditional 4C | ✓ VERIFIED (existence) | Extended per 16-16 (STEP 10 + 4C); future sessions driver-automated per the standing directive |
| 8× `vmd/smoke/phase16_*.tcl` | headless proof | ✓ VERIFIED | ALL PASS=1 FAIL=none on fresh staging this session; 0 `ERROR)`, 0 `bad switch`, all "Exiting normally" |

### Key Link Verification (re-checked this session)

| From | To | Via | Status |
|---|---|---|---|
| pick_bridge._on_event | game.tcl | `game::on_pick $vmd_pick_atom` (pick_bridge.tcl:166,210) | ✓ WIRED |
| setup_tab Start | dialog.on_start | `-command {::biochemeleon::on_start}` (setup_tab.tcl:240) | ✓ WIRED |
| dialog.on_start | pick_bridge → game → game_tab | deactivate (203) → start_game (207) → start_round | ✓ WIRED |
| game_tab radios | pick_bridge | set_view_mode → `mouse mode pick 2`/`rotate` (110/223) | ✓ WIRED |
| guard | cleanup + liveness remap | `cleanup $old_gs` in-catch → `molinfo numatoms` remap → restored-original start | ✓ WIRED |
| mutation.tcl | generators.tcl | `measure minmax` → `sphere_positions` (mutation.tcl:55-58) | ✓ WIRED |
| entry | modules | source order; registry sourced exactly once (carried green; entry smoke PASS=1) | ✓ WIRED |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|---|---|---|
| HIDER-03 (sphere/VDW hiders in bbox) | ✓ SATISFIED | Real bbox placement (16-07 body-swap on disk); placement smoke green; GUI round won with sphere hiders |
| LOOP-01 (click-to-find via VMD pick) | ✓ SATISFIED | GUI-locked: round WON through the trace (16-12); exact PICK values captured (16-16); first-click quirk = documented known behavior, player guidance recorded |
| LOOP-02 (single found-state truth) | ✓ SATISFIED | Registry reconstructed from sentinels per round; capstone + restart smoke per-round registry invariants |
| LOOP-03 (win condition) | ✓ SATISFIED | GUI-verified win box with time; timer frozen; finish_win double-call guarded |
| BTN-07 (Start flow) | ✓ SATISFIED | Full fan-in on disk + wired; double-Start guarded (headless + GUI both paths) |
| GAME-01 (rolling info box) | ✓ SATISFIED | Log model 15/15; capstone; GUI log lines during won round |
| GAME-02 (timer) | ✓ SATISFIED | Drift-free timer; stops on win (GUI 5:14 frozen) |
| GAME-03 (remaining count) | ✓ SATISFIED | total + per-rep easy (remaining_by_rep 18/18; format_remaining 47/47); GUI decrement |

### Dynamic Verification (this verifier, FRESH staging `tmp/verify16`, 2026-09-03)

| Suite | Result | `ERROR)` scan | `bad switch` scan | Exiting normally |
|---|---|---|---|---|
| phase16_restart_smoke (gap-1 gate) | **PASS=1 FAIL=none** | 0 | 0 | yes |
| phase16_smoke (capstone) | **PASS=1 FAIL=none** | 0 | 0 | yes |
| phase16_pick_smoke | **PASS=1 FAIL=none** | 0 | 0 | yes |
| phase16_hiders_smoke | PASS=1 FAIL=none | 0 | 0 | yes |
| phase16_placement_smoke | PASS=1 FAIL=none | 0 | 0 | yes |
| phase16_onpick_smoke | PASS=1 FAIL=none | 0 | 0 | yes |
| phase16_gametab_smoke | PASS=1 FAIL=none | 0 | 0 | yes |
| phase16_entry_smoke | PASS=1 FAIL=none | 0 | 0 | yes |

Restart-smoke narrative re-proven from the log: `Atoms: 555 → 558 → (restore 555) → 557 → (restore 555) → 558 → (1znf 424) → (restore 555) → 426`; `Segments: 2` on all 4 combined reloads (never 3); guard INFO 3×, 2 remap lines; all 5 stage markers ok=1. Marker verified false-PASS-proof: `PASS=1` prints only when `llength $failures == 0` (`PASS=0 FAIL=<list>` otherwise); `_bail` appends to the GLOBAL list. 8.5-idiom gate over lib+gui: 0 matches. GUI-only vs headless-proven split: pick DELIVERY, win box, countdown display, panel behavior, and the guard's real-click paths are GUI-only evidence (16-12 + 16-16 sessions, cited above); all loop mechanics, guard semantics, scoring, single-generation invariants, and wiring are headless-proven this session.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| vmd/lib/game.tcl | 56-57, 139-140 | "placeholder" wording in comments | ℹ️ Info | Historical 16-07 body-swap references — the body IS swapped (mutation.tcl:55-58 real `measure minmax` → sphere_positions); not stubs |
| vmd/smoke/phase16_restart_smoke.tcl | 77 | "Segments … EYEBALLED by the runner, NOT parsed" | ℹ️ Info | Honest self-limitation in the smoke header; the structural invariants (atoms/sentinels/registry/numreps/vp) ARE parsed; the GUI log independently showed Segments: 2 |
| — | — | TODO/FIXME/stub bodies; `mouse callback` commands; 8.6 idioms | none | 0 matches across the entire Phase-16 surface |

### Human Verification Required (non-blocking, recorded for completeness)

1. **pv_cleanup restore path** — never reached in either GUI session (16-16 NOT REACHED). Expected: mouse restored to saved rotate/-1, labels to baseline, trace removed. Why human: real GUI. Not a phase-16 SC (cleanup button = Phase 19); restore machinery evidenced by session-1's 9b pv_state.
2. **Optional quirk confirmation** — a future driver-automated session may sanity-check the recorded first-click behavior. Why human: C-side delivery unprobeable in text mode. The contract is already LOCKED on existing session evidence.

### Gaps Summary

None. Both gaps from the 2026-08-30 verification are closed with layered evidence:

1. **Truth 7 (loop integrity)** — closed in code (16-13 guard at the single choke point, before snapshot), at the GUI layer (16-14 teardown + view reset), headlessly (16-15 regression gate re-proven fresh this session with the exact observed-defect path), and in the GUI (16-16: both paths, both sessions, Segments: 2 never 3).
2. **Truth 3 (pick contract)** — closed per the recorded session chain: session-1 won-round + labelpoll premise + phantom falsification (16-12); exact PICK values + guard GUI pass + quirk root-cause facts (16-16); headless probe + hotkeys.tcl disproof + c2 byte-untouched record + docs close-out (16-17). No open hypotheses remain; the first-click quirk is documented known behavior with player guidance (`p` or `1` once per round).

Accepted caveats (NOT gaps, per phase scope): first-click quirk (locked, documented); Setup-Reset fields-only mismatch and missing Cleanup/Restart button (Phase 19); restored-original molecules accumulating in the dropdown (cosmetic, Phase 19); the one unresolved freeze observation (recorded, not reproducible in the clean control session — zero freezes there under the identical guard flow).

**Recommendation:** Phase 16 goal achieved. Proceed to Phase 17.1; carry the Phase-19 notes already recorded (Cleanup/Restart buttons, view-reset-on-`mol new` wart, dropdown accumulation, driver-automated human-verify directive).

---

_Re-verification by OpenCode (gsd-verifier), 2026-09-03T12:40:00Z. Prior records (16-12 GUI checkpoint, 2026-08-30 automated verification, 16-16 partial re-verify) preserved verbatim in 16-VERIFICATION.md. Not committed — orchestrator bundles._
