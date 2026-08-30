# 16-VERIFICATION.md — GUI pick-contract verification (Plan 16-12)

**Date:** 2026-08-30
**Plan:** 16-12 (Phase 16 — MVP Core Loop — Sphere)
**Session:** real VMD 1.9.3 GUI on Windows, Tk console, bundled demo 1k8p (555 real atoms), hiders = 3, via `vmd/tests/pick_verify.tcl` (staged `tmp/biochemeleon-vmd`).
**Verdict: LOCKED-WITH-CAVEATS** — the trace mechanism is RETAINED as primary (a complete round was WON through it in this session), but C-side firing reliability is UNRESOLVED (mode-desync flakiness + one freeze) pending one targeted re-verify session.

---

## 1. Verdict table (all 9 steps; 9a/9b/9c split)

| Step | What it tests | Verdict | Observed (decisive values) |
|---|---|---|---|
| 1 | setup / countdown / pick-mode engagement | **PASS** | Human: "step 1 working". 3-2-1-GO countdown, Game tab active, Mouse menu switched to pick mode. |
| 2 | THE LOCK — observer trace fires; exact PICK values | **INCONCLUSIVE (capture artifact — NOT a disproof)** | Labels were created on every click, but NO `PICK ev=...` lines ever printed. Root cause: the script-printed one-liner contains `[info exists` + NEWLINE + `vmd_pick_shift_state]` (the human's terminal wrapped it during copy); a newline inside the bracketed substitution parses as a command separator → the `apply` body ERRORED on every fire → output swallowed. The game's own finds (steps 5-9) prove the game's trace delivered; the exact atom/molid/shift values were NOT captured. **RE-TEST with a paste-safe two-paste observer.** |
| 3 | submode check: query mode (`mouse mode pick 0`) | **PARTIAL / WEIRD** | Per human: steps 3-5 "is weird, in the following case not working (need to use keyboard shortcut p every time i click a new hider, otherwise only show label)". Interleaved with the flakiness — no clean signal. |
| 4 | `mouse callback` independence | **INCONCLUSIVE — LEANING IMPORTANT (leading hypothesis)** | Finds worked exactly when `User Pick: mol1 atom:555`-style lines printed (VMD's user-pick-callback output ⇒ `mouse callback` was ON during those picks). Early clicks printed only `picked atom:` dumps + labels (no find). `ERROR) Illegal mouse mode: 0 -1` appeared twice immediately before working picks (after the human pressed keyboard `p`). After a fresh VMD restart, picks worked WITHOUT `p`. Hypothesis (UNCONFIRMED): VMD 1.9.3's C-side pick-event delivery depends on `mouse callback` being on / interactive-mode re-arm; the text-command `mouse mode pick 2` alone can leave a desync where labelatom clicks create labels but never write `::vmd_pick_event`. **RE-TEST explicitly (callback off → click → find?; callback on → click → find?).** |
| 5 | Rotate/Pick toggle (hotkey + panel) | **PARTIAL** | `r` rotates (no find — correct) but the Game-tab checkbox stays "Pick" (checkbox desync — pick_bridge does not observe hotkey-driven mode changes). Panel Rotate→Pick restored label-mode but finds required `p` again; only keyboard `p` allowed selecting hiders again. |
| 6 | labels + labelpoll fallback viability | **PASS** | Every pick-atom click created a detectable label: repeated `Added new Atoms label GAM9001:G01` / `:G02` / `:G03` (labelpoll premise CONFIRMED). Auto-clean worked — final labels count=0. |
| 7 | phantom callbacks-list falsification | **PASS** | `catch {lappend ::vmd_pick_atom_callbacks phantom_cb}` returned `0`; multiple clicks afterward — `PHANTOM FIRED` NEVER appeared. Phantom falsified in-GUI; compat shim stays a no-op. |
| 8 | hidden-rep caveat (UG node140) | **PASS** | With `pv_hide_hidden`: click at the hider position picked REAL atom 322 with NO find. After `pv_show_hidden`: click found hider 557. Hidden reps cannot be picked — GUI-confirmed. |
| 9a | win condition | **PASS** | Round won end-to-end through the game's own delivery: win box appeared WITH the time. |
| 9b | frozen state after win (`pv_state`) | **PASS** | `game_logic state = won`; `timer elapsed = 314s (5:14)` (frozen); `registry remaining = 0`; mouse restored to saved `rotate` / `-1`; `pick_bridge active = 0`; `mechanism = trace`; `labels: count=0` (auto-clean); hider reps: hidden rep idx 1 (VDW / Element / user2<1) + found rep idx 2 (VDW / ColorID 7 / user2>0); HIDER indices 555-557. |
| 9c | cleanup restore | **BLOCKED (script over-reach)** | No Cleanup button exists on the Game tab (cleanup/restart = Phase 19 scope; the verify script over-reached). Mouse-mode restore MACHINERY exists and is evidenced (saved rotate/-1 in the 9b pv_state) but was not exercised via the intended path. Fixed in this pass: step 9c now uses the console helper `pv_cleanup` (see Task B). |
| **OVERALL** | pick-contract lock | **LOCKED-WITH-CAVEATS** | Trace mechanism RETAINED as primary (a complete round was won through it; labelpoll premise confirmed as fallback). Contract locked with caveats — C-side firing reliability UNRESOLVED (callback hypothesis + mode desync + `p` re-arm + one freeze) pending one targeted re-verify session. |

## 2. Human's verbatim feedback (checkpoint response, 2026-08-30)

> "step 1 working
> step 2 see the label, not shure
> step 3-5 is weird, in the following case not working (need to use keyboard shortcut p every time i click a new hider, otherwise only show label), but after a restart pick working without iterativ p. for 5, r when mouse mode is pick switch rotate without labelling higder but not changing the checkbox from pick to rotate, checkbox click rotate then pick go back to label mode, only keyboard p allow selecting hider again
> after a succeful gameplay, reset does not clear hider, and the game is very problematic
> step 6-8 pass
> step 9 ab pass, c no such button exists. and vmd forze afterwards (ending standard gameplay no freeze, maybe due to force end due to freeze)"

## 3. Decisive log excerpts (from the human's pasted VMD console transcripts)

1. **Label creation (labelpoll premise):** repeated `Added new Atoms label GAM9001:G01` / `GAM9001:G02` / `GAM9001:G03` on pick-atom clicks.
2. **Win-state `pv_state` dump (step 9b):**
   ```
   game_logic state = won
   timer elapsed = 314s  (5:14)
   registry remaining = 0
   pick_bridge active = 0
   mechanism = trace
   labels: count=0 baseline=0
   mouse: mode=rotate submode=-1   (saved_mode=rotate saved_submode=-1)
   game molid ...: HIDER indices: 555 556 557
   hider rep hidden (idx 1): shown=1 style=VDW color=Element   (user2 < 1)
   hider rep found  (idx 2): shown=1 style=VDW color=ColorID 7 (user2 > 0)
   ```
3. **`mouse callback` correlation (flakiness):** working finds preceded by `User Pick: mol1 atom:555`-style lines; non-finding clicks printed only `picked atom:` dumps + label adds (no find). `ERROR) Illegal mouse mode: 0 -1` printed twice immediately before working picks (after keyboard `p`).
4. **Hidden-rep test (step 8):** click at the hidden hider's position → `picked atom:` real atom **322**, no find; after `pv_show_hidden` → click found **557**.
5. **Phantom (step 7):** `catch {lappend ::vmd_pick_atom_callbacks phantom_cb}` → `0`; multiple clicks; **no** `PHANTOM FIRED` line ever.
6. **Double-start (registered defect, out of plan scope):** after the won round, with NO Cleanup button available, Start was pressed again: `start_game` ran on the still-loaded GAME molecule (558 atoms) producing a **561-atom** combined PDB with stacked sentinels (`Segments: 3`; HIDER indices now 555-559 across two generations).
7. **Session-1 observer snippet (why step 2 was INCONCLUSIVE):** the pasted one-liner
   `trace add variable ::vmd_pick_event write {apply {{args} {global vmd_pick_atom vmd_pick_mol vmd_pick_shift_state; vmdcon -info "PICK ev=$args atom=$vmd_pick_atom mol=$vmd_pick_mol shift=[info exists vmd_pick_shift_state]"}}}}`
   arrived with a newline inside `[info exists` (terminal wrap during copy) — a newline inside a bracketed substitution is a command separator → the apply body errored on every fire → output swallowed. Capture artifact, NOT a disproof of the trace.
8. **Hotkey fact:** keyboard `p` is bound to `mouse mode pick` (1-arg form — `vmd-ref/scripts/hotkeys.tcl:112`); pressing it re-armed finds during the flaky stretch. Submode resolution of the 1-arg form is part of open question (b).

## 4. Open questions for the re-verify session

The re-verify driver is `vmd/tests/pick_verify.tcl` (fixed in plan 16-12 Task B: two-paste paste-safe observer, callback A/B test, `pv_cleanup` console helper).

- **(a) `mouse callback` on/off ↔ `::vmd_pick_event` delivery (THE leading hypothesis — 2-click A/B test, new STEP 4):** `mouse callback off` → click an unfound hider → find or not? Then `mouse callback on` → click another unfound hider → find or not? If finds require callback on, PickBridge must add `mouse callback on` at activate / `off` at deactivate. UG §9.3.23 documents only `callback on/off` (no query form) — the test SETS the state explicitly before each click, so validity does not depend on querying.
- **(b) Exact PICK event values with a paste-safe observer (new STEP 2):** two-paste form (`proc pv_observe {args}` block + short `trace add variable ::vmd_pick_event write pv_observe` line) — every printed line kept short so terminal wrapping cannot split a bracketed substitution. Capture: ev args triple, atom (0-based index), mol, shift present. Also: what submode does the hotkey `p` 1-arg form (`mouse mode pick`) actually resolve to, and does a query-mode click fire the event (old step 3)?
- **(c) Freeze reproduction:** VMD froze at the very end of the problematic session (after the won round + `pv_state` + several labelatom clicks with the bridge inactive); a clean standard-gameplay session exited fine. Candidates: the broken observer erroring per-fire, labelatom clicking with an inactive bridge, or VMD 1.9.3 flakiness. Do not speculate as fact — flag for re-verify.
- **(d) Mouse-mode restore via an actual cleanup path:** the restore machinery is evidenced (saved rotate/-1 in the 9b pv_state) but step 9c's intended path never existed. Re-verify exercises `pv_cleanup` (console) and records whether the mode is restored and labels return to baseline.

## 5. Defects registered (for the phase verifier / gap-closure planning)

1. **Double-start stacking (real bug — out of this plan's file scope):** `start_game` has no active-game guard. After a won round with no Cleanup available, pressing Start again ran on the still-loaded GAME molecule (558 atoms) → 561-atom combined PDB with stacked sentinels (`Segments: 3`, HIDER indices 555-559 across two generations).
2. **No active-game guard missing in `start_game` / `on_start`** (same defect, stated as the gap to close).
3. **Setup-tab "Reset" expectation mismatch:** Reset clears the setup FIELDS only — it does not clear hiders ("after a succeful gameplay, reset does not clear hider"). Expectation mismatch to address in gap closure (cleanup/restart = Phase 19 scope).
4. **Step-9c script over-reach (FIXED in this pass):** the verify script told the human to "Press Cleanup (Game tab)" — no such button exists in the MVP. Replaced with the `pv_cleanup` console helper (game::cleanup + pick_bridge::deactivate, using the game_state stashed by `pv_state` right after Start); the Game-tab Cleanup button arrives in Phase 19.
5. **Checkbox desync (minor UX):** pressing hotkey `r` switches VMD to rotate but the Game-tab checkbox stays "Pick" — pick_bridge does not observe hotkey-driven mode changes. Documented as known behavior.
6. **End-of-session freeze (unresolved):** see open question (c).

## 6. Keep-vs-delete decisions applied (per 16-RESEARCH-pick.md SS3)

| Research SS3 item | Decision | Rationale |
|---|---|---|
| Trace mechanism (A) primary | **KEEP** (primary) | A complete round was WON through it in this session; the step-2 capture failure was a paste artifact, not a mechanism failure. |
| Labelpoll fallback (D) | **KEEP** (dormant, ~20 lines) | Premise CONFIRMED in-GUI — every pick-atom click created a detectable label and auto-clean worked. Cheap insurance for other users' VMD builds. |
| Mechanism flip to labelpoll | **NO** | Evidence insufficient — the trace demonstrably delivered finds during the round. |
| `mouse callback on` in activate/deactivate | **NOT ADDED YET** | Hypothesis unconfirmed; UG says callback gates only the HOVER (`_silent`) variables and www.tcl never enables it, but session-1 correlation contradicts that. Re-verify A/B test (new STEP 4) decides FIRST, then the mechanism is touched. |
| Phantom callbacks-list (B) | **DELETE-confirmed** (stays a no-op shim) | Falsified in-GUI (step 7) — never fires. |
| Args-parsing branches assuming positional `(molid atom)` | **DELETE** (already absent from pick_bridge) | Step-2 evidence (game's own trace delivered with `{args}` signature) + UG. |
| `vmd_pick_molecule` / `vmd_pick_state` / `vmd_pick_selection` reads | **DELETE** (already absent) | Session evidence consistent with UG names (`vmd_pick_atom` / `vmd_pick_mol` only). |
| Hidden-rep found-marking rule | **KEEP** (never hide a rep with unfound hiders) | GUI-confirmed: hidden hider unfindable (real atom 322 picked instead); find works after re-show. |

---

*Recorded by plan 16-12 (Task A) from the human checkpoint response + pasted console transcripts. Re-verify driver fixes: vmd/tests/pick_verify.tcl (Task B, same plan).*

---

# Phase-16 goal verification (automated, 2026-08-30)

status: gaps_found
score: 5/7 must-haves verified
re_verification: no (initial automated goal verification; the section above is the authoritative 16-12 human checkpoint record and is preserved verbatim)

**Phase Goal:** "The player can play a complete hide-and-seek round with sphere hiders — the PROJECT.md core value. If nothing else works, this loop works. The VMD pick-callback contract is locked here via a GUI human-verify checkpoint."
**Verified:** 2026-08-30T22:02:59Z
**Method:** All 12 plan must_haves checked against the actual code (3-level: exists / substantive / wired), 4 tcltest suites + 7 Phase-16 smokes re-run under fresh headless staging (`tmp/verify16`), full logs scanned for false-PASS (`ERROR)` / `bad switch`); the GUI verdict is taken from the human record above (no GUI re-run by the verifier).

## Goal Achievement

### Observable Truths (must-haves, mapped to the ROADMAP SCs)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | SC1 — Start generates sphere hiders per setup, switches to Game tab, counts down 3-2-1, starts the timer | ✓ VERIFIED | `generators.tcl` (pure, 8/8 tests) + `mutation.tcl:56-58` (`measure minmax` → `sphere_positions`) + `game.tcl:78-109` (ordering incl. hider-rep step after `backup::apply`) + `dialog.tcl:134-202` `on_start` BTN-07 fan-in + `game_tab.tcl` (one-shot countdown `after 1000` with ID tracking, timer re-arms only while `playing`, epoch at `begin_play`). Placement/entry/gametab smokes PASS=1; capstone steps 2-3. GUI step 1 PASS (human record). |
| 2 | SC2-mechanism — a click correctly identifies a registered hider and marks it found (recolor via user2 two-rep split) | ✓ VERIFIED | `pick_bridge.tcl` trace `{args}` handler → `game::on_pick` (line 152) with molid filter + index validity; `game.tcl:204-249` three-way guard + state gate; `hiders.tcl` user2 flag + mandatory modselect re-assert. Capstone drives miss/hit/already-found/winning-hit through the REAL `_on_event` (simulated `::vmd_pick_event` write) — PASS=1. A complete round was WON through this path in the GUI session (record above, steps 5-9a). |
| 3 | SC2-lock — the pick contract is LOCKED (reliable C-side firing in a real GUI) | ✗ FAILED | Record above: **LOCKED-WITH-CAVEATS**. A round was won, labelpoll premise confirmed, phantom falsified — but C-side firing reliability is UNRESOLVED (mode-desync flakiness, `p` re-arm, finds correlated with `mouse callback` on, `Illegal mouse mode: 0 -1`, one freeze). Exact PICK values uncaptured (paste artifact). The A/B test (driver `vmd/tests/pick_verify.tcl` STEP 4, verified present) decides whether `mouse callback on/off` enters `activate`/`deactivate` — NOT yet added to `pick_bridge.tcl` (correctly, hypothesis unconfirmed). |
| 4 | SC3 — rolling info box logs clicks/found; remaining count (total + per-rep in easy) decrements | ✓ VERIFIED | `game_logic.tcl` log model (15/15 tests: Miss!/Already found!/Found one! N remaining); `registry.tcl:88-131` `status_of`/`count_remaining`/`remaining_by_rep` (18/18); `setup_state.tcl:307` `format_remaining` (47/47); `game_tab.tcl` `on_log_line`/`update_remaining` pull model (lines 288-316). Capstone asserts decrement through the scoring loop. |
| 5 | SC4 — all found → timer stops, winning message shows time taken | ✓ VERIFIED | `game_logic.tcl` `finish_win` (freezes elapsed, errors on double call); `game.tcl:238-243` win flow (finish_win → frozen elapsed → win log → win_cb); `game_tab.tcl:336-371` on_win → deactivate exactly once → delayed parented `tk_messageBox` with `format_mmss`. GUI steps 9a/9b PASS (win box with time; `state=won`, timer frozen 5:14, remaining=0). |
| 6 | SC5 — pick-vs-rotate control so the player can rotate between picks | ✓ VERIFIED | `game_tab.tcl:131-134` Rotate/Pick ttk::radiobuttons → `set_mouse_mode` → `pick_bridge::set_view_mode` (`pick_bridge.tcl:215-222`: `mouse mode pick 2` / `mouse mode rotate`); the tab never issues `mouse mode` directly. GUI step 5: panel toggle works (label mode restored via panel). Known minor: checkbox does not track hotkey `r` (documented behavior, does not defeat the control). |
| 7 | Loop integrity — the core loop is robust in a normal session ("if nothing else works, this loop works") | ✗ FAILED | **No active-game guard.** `game::start_game` (game.tcl:78-109) runs snapshot→mutate→reps→registry unconditionally; `on_start` (dialog.tcl:134-202) has no guard either. Confirmed live in the GUI session: Start after a won round (no Cleanup available) ran on the still-loaded GAME molecule → 561-atom combined PDB, Segments: 3, stacked sentinel generations (HIDER 555-559). A second Start during an in-flight round hits the same path — loop state is corrupted rather than aborted/restarted. |

**Score:** 5/7 truths verified

### Required Artifacts (all 12 plans; level 1-3 summary)

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `vmd/lib/generators.tcl` | pure sphere sampler | ✓ VERIFIED | 45 lines, pure (no mol/tk), exported; 8/8 tests |
| `vmd/lib/registry.tcl` (ext) | status_of / count_remaining / remaining_by_rep + rep arg | ✓ VERIFIED | exports line 23; 18/18 tests; backward compat green |
| `vmd/lib/game_logic.tcl` | pure state machine + drift-free timer + log model | ✓ VERIFIED | 257 lines; 15/15 tests; double-win prevention present |
| `vmd/lib/setup_state.tcl` (ext) | `format_remaining` | ✓ VERIFIED | line 307, exported, pure; 47/47 tests |
| `vmd/lib/hiders.tcl` | 2-rep found-visual layer | ✓ VERIFIED | hidden VDW/Element/user2<1 + found VDW/ColorID 7/user2>0; no showrep off; beta never written; re-assert present |
| `vmd/lib/pick_bridge.tcl` | trace primary + dormant labelpoll + phantom shim | ✓ VERIFIED | matches 16-06 contract exactly (mouse mode pick 2, idempotent activate, snapshot/restore, baseline-guarded label hygiene); `mouse callback` correctly NOT yet added |
| `vmd/lib/mutation.tcl` (ext) | real bbox placement body-swap | ✓ VERIFIED | `measure minmax` → `generators::sphere_positions` (lines 56-58); frozen signature/record shape |
| `vmd/lib/game.tcl` (ext) | hider-rep step + on_pick + callbacks + stash | ✓ VERIFIED (⚠ gap) | all 16-08 must_haves hold; **no active-game guard in start_game** (the registered defect) |
| `vmd/gui/game_tab.tcl` | countdown/timer/log/remaining/win + radios | ✓ VERIFIED | 446 lines; after-ID tracking + winfo/catch guards; never calls `mouse mode` directly |
| `vmd/gui/dialog.tcl` (ext) | Game tab build + on_start + on_close | ✓ VERIFIED (⚠ gap) | game_tab sourced top-level + built eagerly; on_start fan-in complete; on_close stops timers + deactivates bridge before destroy; **no active-game guard in on_start** |
| `vmd/gui/setup_tab.tcl` (ext) | Start button (BTN-07) | ✓ VERIFIED | line 240 `-command {::biochemeleon::on_start}` |
| `vmd/biochemeleon.tcl` (ext) | extended source order | ✓ VERIFIED | pure block (generators, game_logic) then mol block (hiders, pick_bridge); registry sourced EXACTLY ONCE |
| `vmd/smoke/phase16_*.tcl` (7) | headless proof | ✓ VERIFIED | all 7 PASS=1, zero `ERROR)`/`bad switch` on fresh staging (re-run this session) |
| `vmd/tests/pick_verify.tcl` | re-verify driver | ✓ VERIFIED | two-paste `pv_observe`, STEP 4 `mouse callback` A/B, `pv_cleanup` + `pv_cleanup_check` all present |
| `vmd/lib/game.tcl` + `vmd/gui/dialog.tcl` | active-game guard | ✗ MISSING | double-Start stacks generations (see Truth 7) |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| mutation.tcl | generators.tcl | `sphere_positions $mm $count` | ✓ WIRED |
| game.tcl start_game | hiders.tcl | `add_hider_reps` after `backup::apply` | ✓ WIRED |
| game.tcl on_pick | registry + hiders + game_logic | status_of guard → mark_found_visual + mark_found → count_remaining → finish_win | ✓ WIRED |
| pick_bridge._on_event | game.tcl | `game::on_pick $vmd_pick_atom` (single arg) | ✓ WIRED |
| game_tab radios | pick_bridge | `set_view_mode` | ✓ WIRED |
| game_tab GO branch | pick_bridge | `activate` at `begin_play`; `deactivate` in on_win | ✓ WIRED |
| setup_tab Start | dialog.on_start | `-command {::biochemeleon::on_start}` | ✓ WIRED |
| dialog.on_start | game + game_tab | start_game → set_difficulty → raise_tab → start_round | ✓ WIRED |
| dialog.on_close | pick_bridge + game_tab | deactivate + stop_all_timers before destroy | ✓ WIRED |
| entry | all modules | source order, registry once | ✓ WIRED |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|---|---|---|
| HIDER-03 (sphere/VDW hiders in bbox) | ✓ SATISFIED | — |
| LOOP-01 (click-to-find) | ✓ SATISFIED (caveat) | mechanism proven; C-side firing reliability unresolved (re-verify pending) |
| LOOP-02 (single found-state truth) | ✓ SATISFIED | — |
| LOOP-03 (win condition) | ✓ SATISFIED | — |
| BTN-07 (Start flow) | ✓ SATISFIED | double-Start guard missing (loop-integrity defect) |
| GAME-01 (rolling info box) | ✓ SATISFIED | — |
| GAME-02 (timer) | ✓ SATISFIED | — |
| GAME-03 (remaining count) | ✓ SATISFIED | — |

### Dynamic Verification (re-run this session, fresh staging `tmp/verify16`)

| Suite | Result | `ERROR)`/`bad switch` scan |
|---|---|---|
| test_generators (16-01) | Total=8 Passed=8 Failed=0 | clean |
| test_registry (16-02) | Total=18 Passed=18 Failed=0 | clean |
| test_game_logic (16-03) | Total=15 Passed=15 Failed=0 | clean |
| test_setup_state (16-04) | Total=47 Passed=47 Failed=0 | clean |
| phase16_hiders_smoke (16-05) | PASS=1 FAIL=none | clean |
| phase16_pick_smoke (16-06) | PASS=1 FAIL=none | clean |
| phase16_placement_smoke (16-07) | PASS=1 FAIL=none | clean |
| phase16_onpick_smoke (16-08) | PASS=1 FAIL=none | clean |
| phase16_gametab_smoke (16-09) | PASS=1 FAIL=none | clean |
| phase16_entry_smoke (16-10) | PASS=1 FAIL=none | clean |
| phase16_smoke capstone (16-11) | PASS=1 FAIL=none | clean; verified REAL failure-list mechanism (`$failures`; PASS=1 only when empty) and REAL `_on_event`-driven scoring (steps 5-8), deactivate no-delivery (step 9), cleanup (step 10), purity/8.6 gates (step 11) |

88/88 tcltest cases + 7/7 smokes green. Capstone is NOT a false-PASS: assertions accumulate into `$failures` and the marker reports `PASS=0 FAIL=...` when non-empty; full log exits normally.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| vmd/lib/game.tcl | 78-109 | missing active-game guard in start_game | 🛑 Blocker (loop integrity) | double-Start stacks generations (observed live) |
| vmd/gui/dialog.tcl | 134-202 | missing active-game guard in on_start | 🛑 Blocker (loop integrity) | same defect reachable from the UI |
| vmd/lib/pick_bridge.tcl | (whole) | `mouse callback` gating hypothesis unaddressed | ⚠️ Warning | pending A/B verdict — deliberately NOT added (correct per record §6) |
| vmd/lib/registry.tcl / mutation.tcl / game.tcl / game_tab.tcl | comments | "placeholder" wording | ℹ️ Info | historical comments about the 16-07 body-swap / Phase-13 placeholder removal — not stubs |

No TODO/FIXME/stub bodies anywhere in the Phase-16 surface.

### Human Verification Required (the re-verify checklist — driver ready: `vmd/tests/pick_verify.tcl`)

1. **STEP 4 — `mouse callback` A/B (THE decisive test).** Set `mouse callback off`, click an unfound hider → find or not; then `mouse callback on`, click another → find or not. Expected: a clean on/off verdict deciding whether PickBridge adds `mouse callback on/off` to activate/deactivate. Why human: real C-side pick delivery is GUI-only (text mode cannot fire a pick).
2. **STEP 2 — exact PICK event values via the paste-safe two-paste observer (`pv_observe`).** Expected: `PICK ev=... atom=<0-based idx> mol=<game molid>` captured without the session-1 paste artifact. Why human: requires a real mouse click in the GUI.
3. **Freeze reproduction (open question c).** Repeat the end-of-session sequence (won round + `pv_state` + labelatom clicks with bridge inactive). Expected: either repro (→ register against VMD 1.9.3 / the observer) or clean exit. Why human: GUI-session stability.
4. **`pv_cleanup` restore check (STEP 9c).** Expected: mouse mode restored to saved rotate/-1, labels back to baseline, trace removed. Why human: GUI session.
5. **Double-Start guard re-check (after the code fix lands).** Press Start during a round and after a won round. Expected: guarded (message or auto-restart), NO stacked generations (atom count = original + N, Segments: 2). Why human: GUI click path; headless assert accompanies the fix.

### Gaps Summary

Two gaps block a clean phase-16 bill:

1. **No active-game guard** (Truth 7) — `start_game` and `on_start` both run unconditionally, so Start during/after a round corrupts the loop (stacked generations, observed live: 561-atom PDB, Segments: 3). This directly violates the goal's "if nothing else works, this loop works" robustness bar. Fixable in code (`game.tcl` + `dialog.tcl`), verifiable headlessly (regression assert in a smoke) + one GUI re-check.
2. **Pick-contract reliability** (Truth 3) — the contract is locked-with-caveats: the trace mechanism demonstrably delivered a won round, but C-side firing flakiness (mode-desync, `p` re-arm, `mouse callback` correlation, one freeze) is unresolved. The fixed driver is ready; one human re-verify session (items 1-4 above) closes or confirms the `mouse callback` hypothesis, after which `pick_bridge.tcl` is either left as-is or gains the on/off pairing, and the contract is cleanly locked.

Minor registered defects (do NOT block the phase SCs; carried in the record): Setup-tab Reset clears fields only (hiders remain — expectation mismatch; cleanup/restart is Phase 19 scope), Game-tab checkbox desync on hotkey `r` (documented behavior).

**Recommendation:** run `/gsd-plan-phase --gaps` for gap 1 (code) and schedule the re-verify session for gap 2 (human); gap 2's code consequence (if any) should be planned together with its A/B outcome.

---

_Automated goal verification by OpenCode (gsd-verifier), 2026-08-30T22:02:59Z. Human checkpoint record above (plan 16-12) preserved verbatim. Not committed — orchestrator bundles._
