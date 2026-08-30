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
