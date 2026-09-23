# Phase 19: In-game Actions — GUI/UX Layer Research

**Researched:** 2026-09-24
**Domain:** Tk 8.5/ttk widget design space for the Game-tab controls (Hint / Reveal-one / Reveal-all / Found-hider dropdown / Restart / Cleanup), confirm dialogs, the DIFF-04 color picker, the reveal-counter display, and the human-verify session pattern
**Confidence:** HIGH for everything cited from shipped code (v1 `gui_game.py`/`gui_setup.py` read in full; v2 `game_tab.tcl`/`dialog.tcl`/`setup_tab.tcl` read in full). MEDIUM/NEEDS-PROBE only where Tk behavior is not yet exercised in VMD's Tk 8.5.6 build (marked inline).

> **Companion docs (siblings, same phase):** `19-RESEARCH-mechanisms.md` (VMD mechanism layer: hint rep, showrep, color table, probed V1–V20 / NEEDS-PROBE P1–P8) and `19-RESEARCH-integration.md` (file/proc seam anchors, wave plan, test strategy). This doc owns the **GUI/UX layer**: widget choice + layout, v1 exact UX copy, confirm/picker interaction analysis, in-game explanation, the hotkey-desync question, and the human-verify session design. It deliberately does NOT re-derive lib internals (mark_found_visual, tier_reps, game::restart) — it cites the siblings where the GUI consumes them.

---

## Summary

Phase 19's GUI work is the direct Tk 8.5 port of v1's Phase 6/7 Game-tab additions, and **every widget the port needs is already exercised somewhere in the v2 codebase except two**: the `yesno` message-box type and the color-picker UI. The established v2 idioms cover the rest: `ttk::button` (setup_tab.tcl:236-240), `ttk::label` with `-textvariable` (game_tab.tcl:100-105 — the status row is exactly where DIFF-01's "Reveals: N" label belongs), plain `menubutton`+`menu` for dropdowns (setup_tab.tcl:137-162, the clonerep idiom), and `tk_messageBox -parent $w` (game_tab.tcl:388 win box, dialog.tcl:147 error boxes). `ttk::combobox` stays banned (18-06). The one real fork in the road is DIFF-04: the two sibling research docs recommend **different pickers** (mechanisms: `tk_chooseColor` → reserved ColorID 17; integration: a curated ColorID palette menubutton) — this doc resolves the fork with a UX/accessibility analysis and recommends **the curated palette menubutton** (named, color-blind-friendly swatches; zero first-exercise risk; matches the GAME-08 idiom in the same row), with `tk_chooseColor` documented as the v1-parity alternative if the user insists on a free picker.

For the confirm flow: v1's exact, user-approved copy ships in `gui_game.py:154-155/164-165` and ports verbatim (`tk_messageBox -type yesno -icon question`). The modal-over-modeless interaction class is already proven in v2 three ways (win box, error boxes, native file dialogs). For the hotkey-desync defect (16-12), the fix hinges on one unverified fact — whether VMD's C side updates `::vmd_mouse_mode` when a hotkey changes mode (`vmdinit.tcl:278-280` only *initializes* it) — so the plan should schedule a one-line GUI probe before committing to trace vs poll vs defer.

**Primary recommendation:** Build the actions as one `ttk::labelframe` "Actions" at the bottom of the Game tab (above the Mouse-mode labelframe) with two rows — help row (Hint / Reveal one / Reveal all / Found hiders menubutton / Color menubutton) and a visually separated round-end row (Restart / Cleanup model) — add "Reveals: N" to the existing status row, port v1's confirm copy verbatim with `tk_messageBox -type yesno`, use silent no-op guards (never enable/disable), and verify via a new `vmd/tests/actions_verify.tcl` auto-driver in the rep_verify.tcl shape with a **3-paste** session.

---

## 1. Widget availability matrix (question A)

Every row cites where the claim comes from. "Exercised in v2" = a live widget instance ships in `vmd/gui/` today; "ecosystem" = the 5 reference plugins in `vmd-ref/plugins/`; "Tk-doc" = official Tk 8.5 manual (per the mechanisms doc's Sources — Tk 8.5.19 pages; VMD ships 8.5.6, core commands only).

| Control | Variant | Exercised in v2? | Ecosystem / doc evidence | Verdict for Phase 19 |
|---|---|---|---|---|
| Buttons | `ttk::button` | **YES** — setup_tab.tcl:236-240 (`build_actions`), all 5 Setup actions | — | Use for Hint / Reveal one / Reveal all / Restart / Cleanup model |
| Status labels | `ttk::label -textvariable` | **YES** — game_tab.tcl:100-105 (timer/remain/mode) | — | Use for "Reveals: N" (DIFF-01) |
| Grouping | `ttk::labelframe -padding 6` | **YES** — game_tab.tcl:130 (Mouse mode), setup_tab.tcl:108/175/216 | — | Use for the "Actions" group |
| Found-hider dropdown | **plain `menubutton` + `menu`** | **YES** — setup_tab.tcl:137-144, 154-162 (loaded-mol + demo dropdowns) | clonerep.tcl:193; mergestructs.tcl:145; ramaplot.tcl:172 | **Use** (stateless menu entries; no placeholder/reset dance needed) |
| — | `ttk::menubutton` | NO (zero usage in v2) | zero in vmd-ref | Avoid — unexercised variant of an exercised idea |
| — | `ttk::combobox` | NO — **banned** (18-06; integration doc §6 rule 4 carries the ban to GAME-08) | Tk-doc-verified widget (mechanisms V16) but zero ecosystem usage | **Do not use** |
| — | `tk_optionMenu` | NO in v2 | autoionizegui.tcl:96 | Avoid — non-themed, global-var semantics don't fit fire-one-action |
| Confirm dialog | `tk_messageBox -parent $w` | **YES** — game_tab.tcl:388 (`-icon info`, win box, GUI-verified 2026-08-30); dialog.tcl:147-213 (6× `-icon warning`); setup_tab.tcl:412/665/672/687 | clonerep.tcl:183 (`-type ok`) | Use for confirms. **`-type yesno` + `-icon question` + `-detail` are NOT yet exercised** in v2 — Tk-doc-verified (mechanisms V15: returns `yes`/`no`; `-detail` available) but first-exercise → human-verify item |
| Color picker | `tk_chooseColor -parent -title -initialcolor` | NO (zero usage in v2) | **Zero usage in vmd-ref** (mechanisms grep); Tk-doc-verified (V14: returns a Tk_GetColor name — `#rrggbb` for custom picks — or `""` on cancel) | Only if the free-picker path is chosen; return-form is NEEDS-PROBE (mechanisms P1) |
| Color palette (alternative) | `menu add command` per color + `-background` swatch, or label-suffixed entries | menu idiom **YES** (setup menus); menu-entry `-background`/`-compound` swatch images NOT exercised | — | Recommended DIFF-04 UI — see §4.2; swatch rendering is a human-verify item |
| Native modal file dialogs | `tk_getSaveFile` / `tk_getOpenFile -parent $w` | **YES** — setup_tab.tcl:621-624, 681-684 (do_save/do_load, shipped since Phase 14) | — | Precedent that **native modal dialogs work over the modeless dialog** in VMD's Tk |
| Menu separators | `menu add separator` | NO in v2 | ubiquitous Tk | Optional between the two action rows if rendered as menu (not needed for the labelframe design) |

**Load-bearing precision:** the exercised dropdown idiom is the **plain core-Tk `menubutton`** (`-relief raised -bd 2 -direction flush -textvariable` + child `menu -tearoff no`), not `ttk::menubutton`. The Game tab should copy setup_tab.tcl:137-162's exact shape. Likewise the exercised scrollbar/text pairing is plain core Tk (game_tab.tcl:118-123) — not relevant to Phase 19 but it fixes the idiom convention: *plain core Tk for what ttk doesn't cover or hasn't proven; ttk for buttons/labels/frames*.

---

## 2. v1 UX reference (exact labels/copy — the port target)

All from `pymol/biochemeleon/gui_game.py` (read in full; line numbers verbatim) unless noted. **These wordings shipped and were human-verified in v1 Phases 6-7** (06-02/06-03, 07-01/07-02/07-03 summaries — the confirm copy, button labels, and counter behavior were all user-approved; 06-03's C8 bug report led to the counter-reset fix that v2 must bake in from the start).

### 2.1 Widget labels (v1 → v2 port)

| v1 widget | v1 label (exact) | gui_game.py line | v2 disposition |
|---|---|---|---|
| QPushButton | `Hint` | 45 | ttk::button "Hint" |
| QPushButton | `Reveal one` | 49 | ttk::button "Reveal one" |
| QPushButton | `Reveal all` | 53 | ttk::button "Reveal all" |
| QComboBox | `Found hiders: (select)` (placeholder), `Hide found`, `Show found`, `Recolor found` | 67-70 | menubutton "Found hiders" + menu entries `Hide found` / `Show found` / `Recolor found` (placeholder dropped — menubutton+menu is stateless, integration §3.4) |
| QPushButton | `Color…` | 75 | Color menubutton or palette entries (§4.2) |
| QPushButton | `Restart` | 78 | ttk::button "Restart" |
| QLabel | `Reveals: %d` (init `Reveals: 0`) | 57, 140, 249 | ttk::label + `reveal_text` textvariable |
| QPushButton (Setup tab) | `Cleanup model` | gui_setup.py:287 | ttk::button "Cleanup model" — v1 placed it **between Load Setup and Start** (07-02-SUMMARY:90) |
| QPushButton (Setup tab) | `Import puzzle…` / `Save checkpoint` | 88, 91 | **NOT Phase 19** — Phase 20 scope (import/checkpoint) |

### 2.2 v1 tooltips (the in-game explanation content — port their INFORMATION, not their mechanism)

v2 has no tooltip facility (deferred to Phase 22 per the zero-dep decision + AGENTS.md "write a ~30-line pure-Tk helper if tooltips are wanted"). The v1 tooltip texts (gui_game.py) are the source for log lines / confirm copy / label wording:

| v1 widget | Tooltip (exact) | line |
|---|---|---|
| Hint | "Reveal a clue: temporarily highlights atoms near one hider to point you toward it (counts as a hint used)." | 46-48 |
| Reveal one | "Give up on one random hider — it gets revealed and marked found (counts as a reveal used)." | 50-52 |
| Reveal all | "Give up and reveal every remaining hider at once. This ends the game." | 54-56 |
| Found combo | "After finding hiders, choose how to display them: Hide, Show, or Recolor the found hiders." | 71-73 |
| Color… | "Choose highlight color for found hiders" | 76 |
| Restart | "Start a fresh round with new hiders" | 79 — **v2 must REWORD** (mechanisms doc §D: v2 Restart is a same-count REPLAY of the stashed round, not a form re-derive; e.g. "Restart this round from its initial state — same hider count and reps") |
| Reveals label | "How many hiders you've revealed (via Reveal one / Reveal all). Shown on the win screen too." | 58-60 |
| Cleanup model | "Remove all game-generated hiders and restore the model to its original state. (Does not start a new round — use Start for that.)" | gui_setup.py:288-290 |

### 2.3 Confirm copy (v1 verbatim — port verbatim)

| Dialog | Title | Body | Source |
|---|---|---|---|
| Reveal one | `Reveal one hider?` | `Give up on one random hider? This counts as a reveal use.` | gui_game.py:154-155 |
| Reveal all | `Reveal all hiders?` | `Give up and reveal ALL remaining hiders? This ends the game.` | gui_game.py:164-165 |
| Hint | — none — | Hint is help, never a give-up gate (user-approved decision, 06-02-SUMMARY:32) | — |
| Restart | — none — | v1 Restart had **no confirm** (`_on_restart` = timer stop + `_on_start`) | __init__.py wiring, 07-RESEARCH.md §2 |

Guard-before-confirm (v1 pattern, port exactly): every reveal handler checks `controller is None or not _started` and `_remaining() == 0` **and returns silently BEFORE showing any dialog** (gui_game.py:142-167). A confirm must never appear for a dead action.

### 2.4 v1 log lines (game_logic kind formatting parity — mechanisms doc §B owns the kind list)

"Hint: highlighted neighbors of one hider." (game.py:272) · "Revealed one! %d remaining" (game.py:293) · "Revealed all %d hiders. Game over." (game.py:317). v1's win box: "You found all %d hiders in %d:%02d!" (gui_game.py:340) — already ported in v2 (game_tab.tcl:389); stats block is Phase 22.

### 2.5 v1 behavioral facts that constrain the v2 GUI

- **Counter reset per round (v1 C8 lesson, 06-03-SUMMARY:114-118):** the reveal label was initialized once and never reset — the user reported stale "Reveals: N" on round 2. v2 must reset `reveal_text` in `start_round` step 1.5 (the 16-14 view-state reset block, game_tab.tcl:173-175) and again in the Cleanup path.
- **Dropdown reset dance was a v1 QComboBox artifact:** `activated` signal + `setCurrentIndex(0)` after handling (gui_game.py:198-205) so the placeholder doesn't fire on construction and the same action can be re-selected. **menubutton+menu needs none of this** — each menu-entry click is one action (integration §3.4).
- **Found-mgmt filters by STATUS, never color** (07-02-SUMMARY key-decision) — in v2 the analog is "walk `tier_reps`' found reps" (mechanisms §C); the GUI never builds id-selections.
- **Silent no-op guards, not enable/disable** (07-RESEARCH.md:270 "follow the same pattern — no-op guards, not enable/disable"): buttons stay clickable in every game state; handlers early-return. Keep this in v2 for all six new controls.
- **Reveal-all counter = +N hiders, not +1 action** (06-01-SUMMARY:37) — already pinned by both siblings; the label text "Reveals: N" means "hiders revealed by give-up".

---

## 3. Recommended Game-tab layout + control design per requirement (questions B, D, E, H)

### 3.1 Current game_tab structure (the canvas)

`game_tab::build` (game_tab.tcl:82-141) packs, in order:

```
1. $parent.status   (ttk::frame, -side top -fill x)      timer | remain | mode   [pack -side left]
2. $parent.loglab   ("Info log:" caption, -side top -anchor w)
3. $parent.logf     (core text + scrollbar, -side top -fill both -expand yes)
4. $parent.mouse    (ttk::labelframe "Mouse mode", -side bottom -anchor w)   ← currently the LAST pack
```

### 3.2 Recommended layout (v2-native, v1-informed)

```
┌──────────────────────────────────────────────────────────┐
│ 5:14   Remaining: 3   Reveals: 1   Mouse: Pick           │  ← status row (DIFF-01 added)
├──────────────────────────────────────────────────────────┤
│ Info log:                                                │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Found one! 3 remaining                               │ │  ← log (fill both -expand)
│ │ Hint: highlighted neighbors of one hider.            │ │
│ └──────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────┤
│ ┌─ Actions ────────────────────────────────────────────┐ │
│ │ [Hint] [Reveal one] [Reveal all] [Found hiders ▾] [Color ▾] │  ← help row
│ │        [Restart]  [Cleanup model]                    │  ← round-end row
│ └──────────────────────────────────────────────────────┘ │
│ Mouse mode                                               │
│ (•) Rotate  ( ) Pick atoms                               │  ← stays at the bottom edge
└──────────────────────────────────────────────────────────┘
```

**Pack mechanics (get this right — pack ordering is the classic Tk mistake):** with `-side bottom`, the FIRST bottom-packed window claims the bottom edge and later ones stack ABOVE it. The Mouse labelframe is packed at line 139; the new Actions labelframe must be packed **-side bottom -fill x AFTER that line** so Actions sits directly above Mouse mode and the log keeps its `-expand yes` priority. Do NOT pack Actions `-side top` after the log — top-packing after an expanding widget starves it.

**Why the bottom (v1 parity + interaction argument):** v1 rendered its btn_row at the bottom of the Game tab (after the log); the Game tab's primary interaction surface during play is the log + viewer, and bottom-fixed controls never shift as the log grows. The Mouse-mode labelframe stays the bottom-most element (it's the control the player toggles most often mid-round; it must not move).

### 3.3 Control design per requirement

| Req | Control | Design + behavior contract |
|---|---|---|
| GAME-05 Hint | `ttk::button` "Hint" | `-command {::biochemeleon::on_hint}` (dialog-scope handler per integration §3.0). NO confirm (v1 decision). Guard: state "playing" + remaining>0 → silent no-op (v1: guards run BEFORE any dialog). Visual result: orange rep around one hidden hider's neighborhood — NOT on the hider (mechanisms §A). Repeated presses accumulate hint reps (v1 UX; integration §8.5 recommends per-press accumulation). |
| GAME-06 Reveal one | `ttk::button` "Reveal one" | `-command {::biochemeleon::on_reveal_one}`. Guard (incl. remaining==0) → **then** `tk_messageBox -type yesno -icon question -title "Reveal one hider?" -message "Give up on one random hider? This counts as a reveal use."`; "no" → return with ZERO side effects; "yes" → `game::reveal_one $gs`. |
| GAME-07 Reveal all | `ttk::button` "Reveal all" | Same shape; title "Reveal all hiders?" body "Give up and reveal ALL remaining hiders? This ends the game." → `game::reveal_all $gs` → win flow fires (win box ~100 ms later; the confirm is already destroyed by then — no modal nesting, §4.1). |
| GAME-08 dropdown | plain `menubutton` "Found hiders" + `menu` (3 command entries) | Entries `Hide found` / `Show found` / `Recolor found`, each `-command [list ::biochemeleon::on_found_mgmt hide]` etc. (dialog-scope; lib call is `hiders::set_found_visible`/`set_found_color` per mechanisms §C). No placeholder, no reset — stateless. Guards: silent no-op when no round or zero found. Entries stay enabled in all states (v1 no-op-guard parity). Optional polish: dynamic `-textvariable` "Found hiders (N)" updated by `update_remaining`'s pull via `registry::found_indices` — flag as optional, default static text (less state). |
| DIFF-04 picker | "Color" menubutton + curated palette menu (recommendation — see §4.2 for the fork) | 6-10 named ColorID entries; selection → `hiders::set_found_color` (auto-recolors existing found reps; future finds inherit via `found_colorid`). Optional: set the menubutton's `-background`/`-foreground` to the chosen color as a live swatch — plain menubutton supports `-background`; NOT exercised in v2 → optional polish, verify in the GUI session. |
| GAME-10 Restart | `ttk::button` "Restart" | `-command {::biochemeleon::on_restart}`. NO confirm (v1 parity). Handler: guard stash non-empty → `pick_bridge::deactivate` → `stop_all_timers` → `game::restart $gs` → `start_round $gs2` (which re-resets view state incl. the new `reveal_text`) — the exact flow both siblings recommend. Label text stays "Restart"; the v1 tooltip is REWORDED (same-count replay, §2.2). |
| BTN-06 Cleanup | **two buttons, one handler**: Game tab "Cleanup model" (16-12 defect resolution) + Setup tab "Cleanup model" between Load Setup and Start (spec.md:20 placement; v1 parity gui_setup.py:287) | `-command {::biochemeleon::on_cleanup}` both. Handler: guard → deactivate + stop timers → `game::cleanup $gs` → `game_logic::round_reset` → UI reset (timer 0:00, Remaining: -, Reveals: 0, Mouse: Rotate, log cleared — v1 `__init__.py:942-945` reset set verbatim) → raise the Setup tab (mechanisms Open Q5 recommendation). |
| DIFF-01 counter | `ttk::label` in the status row | `-textvariable ::biochemeleon::game_tab::reveal_text`, packed `-side left -padx 12`. Position: **between `remain` and `mode`** (counts grouped: timer, remaining, reveals, then the mode label). Init "Reveals: 0" in `build`; reset in `start_round` step 1.5 (C8 lesson) and in `on_cleanup`. Update sites: after each reveal call (pull `game_logic::reveal_count` getter — the 0-arg PULL discipline matches `update_remaining`, game_tab.tcl:328-337). No 4th callback — the v2 pull model needs no `set_callbacks` change (mechanisms §B). |
| 17.1-14 fix | (not a widget) | `mol off` the guard-restored original — mechanisms §D owns it; GUI-visible effect: the restored original stops inviting clicks (verify in the session, §6). |

**Found-hider dropdown labels (question B detail):** v1's dropdown is an **action** dropdown, not a hider list — "Hide found / Show found / Recolor found" operate on ALL found hiders globally (v1 parity; per-hider ops are impossible in v2 anyway — no per-atom channel, mechanisms §C). So there is **no per-index or per-rep-group listing to design**; the registry record shape (`{rep status}`, registry.tcl:20) never surfaces in the widget. If a per-tier breakdown is ever wanted it would be a menu submenu per tier — out of scope; the ≤5-tier found-rep walk covers all tiers at once.

### 3.4 In-game explanation (question H — spec: "clear but sufficient")

With no tooltips in Phase 19, explanation is carried by four channels (all v1-proven):

1. **Self-explanatory labels** — "Hint", "Reveal one", "Reveal all", "Found hiders", "Color", "Restart", "Cleanup model" (v1 shipped these exact labels; they were the tooltip-free surface users saw in menus anyway).
2. **The Info log explains every action after it happens** — the v1 log lines (§2.4) are self-describing ("Hint: highlighted neighbors of one hider." tells the player what a Hint DID). This is the primary explanation channel and it already exists.
3. **The confirm dialogs explain the give-up actions before they happen** — v1's confirm copy is literally the tooltip text reworded as a question. This is why Hint (help) needs no confirm but the reveals (cost) do.
4. **The status row is self-labeling** — "Remaining: 3" / "Reveals: 1" / "Mouse: Pick" read as English.

**Explicitly out of scope (record so nobody adds it here):** tooltips. The tklib `tooltip.tcl` decision is Phase 22 (root context + AGENTS.md zero-dep rule: vendor under `vmd/3rd_party_lib/` with license, or a ~30-line pure-Tk helper). Do NOT sneak a tooltip dependency into Phase 19. If the user asks for hover help at the Phase-19 checkpoint, the answer is "Phase 22".

---

## 4. Confirm / color-picker interaction analysis (questions C, D, E)

### 4.1 Modal boxes over the modeless dialog — proven class, three ways

The modeless discipline (NO `grab set` on the main panel) is untouched by Phase 19: `tk_messageBox` and `tk_chooseColor` create their OWN modal child windows with an internal local grab — they are the same class as the already-shipped, GUI-verified dialogs:

1. **The win box** — `tk_messageBox -parent $w -icon info` (game_tab.tcl:388), verified in the 2026-08-30 full-round GUI session (vmd/AGENTS.md picking section: "win box, timer frozen 5:14" observed in a real session).
2. **Six error boxes** in `on_start` + three in setup_tab — all `-parent $w`, shipped since Phase 16-10.
3. **Native modal file dialogs** — `tk_getSaveFile`/`tk_getOpenFile -parent $w` (setup_tab.tcl:621/681), shipped since Phase 14 (do_save/do_load were exercised in the Phase 14/16 sessions).

Interaction consequences to document in the plan (not bugs — expected behavior):

- **A modal confirm intentionally blocks dialog + console interaction while up.** The player answers, then resumes. v1 identical (QMessageBox modal). What it does NOT block: the VMD event loop keeps running — **Tk `after` timers fire during a modal box's internal event loop**, so the 1 Hz timer tick keeps counting while a Reveal confirm is open. That is v1 behavior too (QTimer kept running during `exec_`) and is honest UX (deliberating over a give-up costs time). The plan should state this so the human-verify session doesn't misread it as a bug.
- **No modal nesting is possible from our own flows:** every dialog-opening handler returns from the dialog before making its lib call (`set ans [tk_messageBox ...]` → then act), and Reveal-all's win box is scheduled 100 ms AFTER the confirm returns (game_tab.tcl:373-375 `after_winbox` pattern). The one sequence to keep an eye on in verification: Reveal-all Yes → confirm closes → reveal_all runs → win box appears ~100 ms later. Two boxes in sequence, never stacked.
- **State-gated buttons make "dialog during countdown" impossible:** the reveal/hint handlers gate on `game_logic::state eq "playing"` (mechanisms §E.6) — during "countdown" the handlers no-op before any dialog. The win box is the only post-win modal and it has its own tracked one-shot.
- **Cancel is a true no-op by construction:** "no" from `tk_messageBox` returns before any lib call; `""` from `tk_chooseColor` returns before any color mutation. Assert this in the session (§6 verdict table: counter unchanged, registry unchanged, log unchanged after a No).
- **grab-set gate stays zero:** the new code adds dialogs, never `grab set` (the 13-02 gate greps `vmd/gui/` — tk_messageBox's internal grab is not a `grab set` call and is already present in shipped code).

### 4.2 DIFF-04: the sibling-doc fork, resolved

The two siblings disagree on the picker and both flag it for the planner:

- **Mechanisms (§C):** `tk_chooseColor -parent $w` → parse `#rrggbb` → `color change rgb 17 <r g b>` (probed round-trip V6) → `hiders::found_colorid`. v1 parity (`QColorDialog.getColor()`). Open risks: P1 (return form from VMD's Tk 8.5.6 on Windows — zero ecosystem precedent) and P2 (slot-17 collision with any default mapping — render check).
- **Integration (§8.1):** curated ColorID palette menubutton (e.g. green 7, red 1, orange 3, yellow 4, cyan 10, pink 9, purple 11, white 8); `tk_chooseColor` "rejected as default for the blast radius".

**This doc's UX/accessibility analysis — recommendation: the curated palette menubutton.** Reasons, in weight order:

1. **Accessibility is the REQUIREMENT, and named presets beat free choice for color-blind players.** DIFF-04's own text: "player chooses how found hiders are marked (accessibility / color-blind support)". A free RGB picker asks the player to *judge a hue* — exactly what color-blind users cannot do reliably. A named palette ("green", "orange", "cyan", "magenta"…) lets them choose by LABEL. The free picker is the weaker accessibility answer despite being the v1-parity answer.
2. **Zero first-exercise risk.** `tk_chooseColor` has zero precedent in v2 AND in the 5 reference plugins; its Windows return form is NEEDS-PROBE (P1) and the slot collision is a render check (P2). The palette menu reuses the exercised `menu add command` idiom in the same widget row as GAME-08's dropdown — one idiom, one session.
3. **No global color-table mutation by default.** The palette assigns EXISTING ColorIDs via `mol modcolor` — no `color change rgb`, no blast radius, nothing to restore at cleanup. (Mechanisms' slot-17 design remains valid if the free-picker path is ever chosen.)
4. **Spec constraint "simple and user-friendly"** — a 6-10 entry menu is simpler than a system color dialog.

**Membership recommendation** (final call = planner/user; both siblings defer): default **green 7** first (unchanged behavior), then a colorblind-reasonable spread across hues AND lightness — red 1, orange 3, yellow 4, cyan 10 (light blue), pink 9, purple 11, magenta 13 — plus **named labels in the menu entries** (e.g. `add command -label "Cyan" -command [list ::biochemeleon::on_found_color 10]`). Verify white/very-light choices against VMD's default dark background in the session before shipping them; drop any entry that vanishes. Every entry needs no lib probe (ColorIDs 0-32 all exist, mechanisms V5).

**v1-parity escape hatch:** if the user wants the free picker anyway (v1 had QColorDialog), the mechanisms doc's tk_chooseColor→slot-17 flow is fully specified including mitigations. Record the hybrid option (palette + a "More…" entry opening tk_chooseColor) as available but NOT recommended for Phase 19 — it carries both risks for marginal gain.

**Where the choice persists (question D):** `hiders::found_colorid` namespace var (default 7, NOT reset per call) per mechanisms §C — the v1 `_found_color` controller-attr precedent. It is game-session state, NOT setup state (does not belong in `collect_state`/`.bcm` — Phase 20 may carry it later; v1's sidecar did, game.py:336). The GUI consequence: the Game tab needs NO persistence code — the picker writes the lib var; future rounds inherit. Reset-to-green is NOT automatic (preference persists) — document that Restart/Cleanup keep the chosen color (v1 behaved the same: `_found_color` survived cleanup; only a fresh process reset it).

---

## 5. The hotkey/mode desync (question F) — fix shape is probe-gated

**The defect (16-12, registered):** pressing VMD's hotkey `r` rotates the mouse mode away from pick, but the Game-tab Rotate/Pick radios stay on "Pick" — pick_bridge observes nothing (it has no mode watcher; `set_view_mode` is only invoked from the radios, pick_bridge.tcl:229-236).

**The load-bearing unknown:** does `::vmd_mouse_mode` actually CHANGE when the mode changes? Evidence today:
- `vmdinit.tcl:278-280` merely **initializes** the two variables (`set vmd_mouse_mode rotate` / `set vmd_mouse_submode -1`) at startup. No trace, no update hook visible in the init scripts.
- `www.tcl:71` declares them `global` in a pick handler but the visible code never reads them for mode logic — weak evidence only.
- pick_bridge **saves/restores** them as if they reflect reality (activate saves, deactivate issues `mouse mode $saved_mode $saved_submode`, pick_bridge.tcl:260) — and pv_state dumps them — but nobody has verified a hotkey-driven WRITE to the variable.

**Options for the planner (in decision order):**

1. **NEEDS-PROBE first (one console line in the Phase-19 session):** with a round live, press `r`, then `puts "$::vmd_mouse_mode $::vmd_mouse_submode"` in the VMD console. If the values changed → the variable is live-maintained.
   - **If YES:** prefer an **event-driven `trace`** over a poll: `trace add variable ::vmd_mouse_mode write <proc>` registered in `countdown_step`'s GO branch (or `start_round`), removed in `on_win`/`on_cleanup`/`on_close` (the same lifecycle discipline as the pick trace — pick_bridge owns `::vmd_pick_event`'s trace, so a game_tab-owned mode trace keeps file ownership clean: **game_tab.tcl, not pick_bridge** — integration §3.5 prefers game_tab-side). The trace proc: compare the detected mode to `mouse_mode`; if they differ, set `mouse_mode` + `mode_text` programmatically (programmatic sets fire no `-command`, game_tab.tcl:170-172 — so NO viewer call happens, which is correct: the viewer is ALREADY in that mode; do NOT call `set_view_mode` from the trace or you'll fight the user's hotkey).
   - **If NO:** the variable is a startup-only snapshot → neither trace nor poll can observe hotkey changes → **defer the defect** (it is cosmetic, registered, and not in the Phase-19 requirement list — integration §8.8 agrees). Record honestly in the plan.
2. **Poll fallback (only if the trace path is rejected for complexity):** a 1 Hz `after` poll of `::vmd_mouse_mode` while state eq "playing" — but this adds a FOURTH tracked after-id to a file that already documents a 7-rule after-discipline (game_tab.tcl:17-36) for a cosmetic fix. The trace is strictly better if the variable is live.
3. **Rejected: `user add key r` re-binding.** VMD's hotkeys.tcl owns `r`/`p` (hotkeys.tcl `user add key` table); re-binding risks breaking VMD's own bindings and brushes the locked pick contract (no `mouse`/hotkey commands from Phase 19 — integration §6 rule 2). Do not.

**Scope guidance:** this is a 16-12 registered defect, NOT a Phase-19 requirement. Fix it in Phase 19 ONLY as a small, separately-verifiable task behind the probe result; otherwise record it as deferred with the probe finding attached. Either way the probe costs one paste line in the §6 session — fold it in.

---

## 6. Human-verify session design (question G)

### 6.1 What is GUI-only in Phase 19 (the verification surface)

Inherited constraint: Tk doesn't load in `-dispdev text` (vmd/AGENTS.md), so every widget behavior below is human-verify; the lib half of each action is headless-proven (mechanisms V1-V20, integration §7). The GUI-only list, mapped to requirements:

| # | GUI-only behavior | Req |
|---|---|---|
| G1 | All six new controls render in the "Actions" labelframe + "Reveals: N" in the status row; layout doesn't crowd the log/mouse frame | all |
| G2 | Hint: orange region appears AROUND (not on) a hider; log line "Hint: highlighted neighbors of one hider."; repeated presses accumulate regions; no-op with no game / 0 remaining | GAME-05 |
| G3 | Reveal one: confirm appears with the exact v1 copy; **No = true no-op** (counter, registry, log, viewer all unchanged); Yes = one more hider green + "Revealed one! N remaining" + "Reveals" label +1 | GAME-06, DIFF-01 |
| G4 | Reveal all: confirm; Yes = all remaining turn green, "Game over." log, win box appears (no stacking with the confirm) | GAME-07 |
| G5 | Found hiders menu: Hide found → found hiders vanish (and a NEW find while hidden stays invisible — documented behavior, mechanisms §C); Show found → they return | GAME-08 |
| G6 | Color menu: choosing a named color recolors ALL found hiders immediately; a subsequent find renders in the new color | DIFF-04 |
| G7 | Restart: fresh countdown re-arms, timer restarts, same hider count, positions re-randomized, "Reveals: 0", first-click `p` quirk applies again | GAME-10 |
| G8 | Cleanup (both buttons): original molecule restored, labels/log reset, mouse mode restored to the user's prior state | BTN-06 |
| G9 | Modal boxes don't deadlock the session; the timer keeps ticking under a confirm (expected, §4.1); grab-set gate conceptually untouched | — |
| G10 | Cancel paths: confirm-No (G3), color-menu "cancel" is implicit (don't click = no change) | — |
| G11 | (if the desync fix lands) hotkey `r` flips the radios back to Rotate while a round is live | 16-12 |
| G12 | (17.1-14 fix) after a different-target Start mid-round, the restored original no longer intercepts picks | 17.1-14 |

### 6.2 Session shape — `vmd/tests/actions_verify.tcl` (new driver, rep_verify.tcl patterns, 3 pastes)

Model on `vmd/tests/rep_verify.tcl` exactly: Tk-guard if-wrap whole body (one warn line in text mode), `pv_log` (open-append + flush + vmdcon echo), crafted state via `validate_state` → `apply_state` → `on_start`, `after 4500` auto-dump, `pv_instructions` leading with the `p`-press quirk, `::pv_probe` headless knob. New for Phase 19 — two driver capabilities worth pinning:

- **Widget-state auto-dump:** the status labels are `-textvariable`-bound namespace vars, so the driver reads the ACTUAL on-screen text without touching widgets: `set ::biochemeleon::game_tab::reveal_text`, `remain_text`, `timer_text`, `mode_text` — log them each dump. Also dump `game_logic::reveal_count`/`hint_count` getters (or the game_logic counters post-merge), `registry::count_remaining`, per-tier found-rep showstate via the `mol showrep $m $idx` GETTER (headless-assertable even in a GUI session — mechanisms V8) and found-rep color read-back via combined-braces `molinfo get "{color $idx}"`. Objective verdicts, minimal human narration.
- **The driver never calls the confirm-bearing handlers.** `on_reveal_one`/`on_reveal_all` open a blocking `tk_messageBox` — a driver call would stall the script mid-paste (the human would have to answer while the console is busy). The confirms are exercised by the HUMAN clicking the real buttons; the driver reads state before/after. Non-confirm handlers (`on_hint` pops no dialog, `on_restart`/`on_cleanup` pop none) MAY be driver-invoked, but the physical buttons should be clicked by the human anyway — that IS the verification.

**Proposed 3-paste session** (standing 16-16 directive: driver auto-issues, ≤3 short pastes):

1. **Paste 1 — `source vmd/tests/actions_verify.tcl`** (staging cwd, e.g. `tmp/biochemeleon-vmd`): auto-sources the extension if absent, loads **1znf** (protein — hints need real neighbors; 1k8p is DNA-only, per rep_verify's round-3 lesson), applies a crafted round (e.g. 6 hiders, mixed simple tiers — `per_rep {VDW 2 Lines 2 Licorice 2}`, easy mode), calls `on_start`, auto-dumps after the countdown, prints instructions.
2. **Human block 1** (real clicks only): press `p` once → find **one** hider (green) → click **Hint** (orange region around a *different* hider; not on it) → click **Reveal one** → confirm appears → **No** (nothing changes — G3) → **Reveal one** again → **Yes** (hider green, "Reveals: 1") → **Found hiders → Hide found** (found vanish) → **Show found** → **Color → e.g. Red** (found recolor) → find one more hider (renders in the NEW color — G6).
3. **Paste 2 — `pv_r5b`**: driver dumps state (labels/counters/showstate/color read-backs), then calls `on_restart` (no confirm — driver-safe), waits 4500 ms, auto-dumps the fresh round (new molid, same hider_count, Reveals: 0). Instructs: press `p`, then **click Reveal all → Yes** (confirm → all green → "Game over." → win box; two boxes in sequence, never stacked — G4).
4. **Paste 3 — `pv_finish`**: final report (rounds, counters, remaining, label values, found-rep showstates/colors) + `pv_cleanup`-style teardown (bridge deactivate → `game::cleanup` → `pv_cleanup_check`-style post-dump proving the restored original + original atom count) + the log-file path to attach.
5. **(conditional pastes only if in scope):** the desync probe line (`puts $::vmd_mouse_mode` after pressing `r`) and/or a second crafted round for the 17.1-14 different-target check — fold into the same session, not extra sessions.

**Verdict format for the orchestrator:** a G1-G12 pass/fail table with the auto-log as evidence, mirroring 17.1-14-SUMMARY's (a)-(e) table. The 17.1 session proved the shape works (142-line clean auto-log, 2 rounds, user verdict mapped item-by-item).

---

## 7. Open questions for the planner

1. **DIFF-04 picker fork (the one real decision).** Siblings disagree; this doc recommends the **curated palette menubutton** (named entries, accessibility-first, zero NEEDS-PROBE surface) with tk_chooseColor→slot-17 as the documented v1-parity alternative and a "palette + More…" hybrid recorded but not recommended. Because the requirement text says "color picker", the planner may want the user's one-line confirmation of palette-vs-free — this is the single item worth a user ping if CONTEXT.md never materialized.
2. **Reveal-counter label position.** Recommended status row between `remain` and `mode`; v1 had it at the right end of the button row. Cosmetic; either is defensible — pick one and move on.
3. **Desync fix in/out of Phase 19.** Probe-gated (§5). If the probe says the variable is dead, defer with the finding recorded; do not build a poller for a dead variable.
4. **Reset-defect coupling (16-12 "Setup Reset clears fields only").** Mechanisms Open Q8 recommends the light touch (tooltip/wording note only). If the planner adopts it, the v1 Cleanup-model tooltip (gui_setup.py:288-290) is the wording template; no auto-cleanup coupling.
5. **Dynamic "Found hiders (N)" menubutton text.** Optional polish via the existing `update_remaining` pull; default static "Found hiders". Decide once; don't let it grow into state tracking.
6. **Post-win found-mgmt.** v1 disabled found-mgmt after win (its cleanup had already run). v2's molecule SURVIVES a win, so Hide/Show/Recolor/Restart/Cleanup all remain meaningful post-win — handlers should gate reveals/hints to "playing" but allow found-mgmt/restart/cleanup in "won" (mechanisms §D guards already say {playing won} for restart/cleanup; extend the same gate to found-mgmt). Flag in the plan so the session tests post-win dropdown behavior (it's a v2 behavior with no v1 analog).
7. **Cleanup raise destination.** Mechanisms Open Q5 recommends raising the Setup tab after Cleanup. Cheap and sensible; confirm so both Cleanup buttons behave identically.
8. **Color-menu optional swatch rendering** (menubutton `-background` tint) — only if trivially accepted in the GUI session; drop on any rendering weirdness. Named labels alone already satisfy the accessibility intent.

---

## Sources

### Primary (HIGH — shipped code read in full this session)
- `pymol/biochemeleon/gui_game.py` (414 lines) — ALL v1 labels, tooltips, confirm copy, guards, dropdown+picker handlers, layout order, counter reset site
- `pymol/biochemeleon/gui_setup.py:285-299` — "Cleanup model" label + tooltip + placement between Load and Start
- `vmd/gui/game_tab.tcl` (465 lines) — build/pack order, status row, start_round step-1.5 reset block, after-discipline, win box, raise_tab
- `vmd/gui/dialog.tcl` (226 lines) — on_start fan-in (handler-scope precedent), on_close, 6 tk_messageBox error paths
- `vmd/gui/setup_tab.tcl` (691 lines) — menubutton+menu idiom (137-162), ttk::button row (236-240), tk_getSaveFile/OpenFile (621/681), _loading guard, no-op-guard convention
- `vmd/lib/pick_bridge.tcl:229-236,243-266` — set_view_mode, saved_mode restore (desync context)
- `vmd/lib/registry.tcl:20` — record shape `{rep status}` (dropdown-labels question)
- `vmd/tests/rep_verify.tcl` (637 lines) — the auto-driver pattern (Tk-guard, pv_log, pv_state, pv_round*, pv_cleanup, pv_instructions)
- `vmd-ref/scripts/vmdinit.tcl:278-280`, `vmd-ref/scripts/www.tcl:71` — vmd_mouse_mode initialization-only evidence (desync probe rationale)

### Secondary (HIGH — v1 phase records)
- `.planning/phases/06-hint-reveal/06-RESEARCH.md`, `06-01/02/03-SUMMARY.md` — confirm-vs-no-confirm decision (06-02:32), +N counter semantics (06-01:37), C8 label-reset bug + fix (06-03:114-118), hint sparse-hider no-op fix
- `.planning/phases/07-found-hider-management-restart-cleanup/07-RESEARCH.md`, `07-01/02/03-SUMMARY.md` — dropdown status-filter decision, Cleanup placement/label, no-op-guard convention (07-RESEARCH:270), wizard-lifecycle resolution
- `.planning/phases/17.1-*/17.1-14-SUMMARY.md` — the approved consolidated session shape + verdict-mapping table + the standing simpler-session directive in action

### Tertiary (HIGH — sibling research, same phase)
- `19-RESEARCH-mechanisms.md` — probed VMD facts (showrep V8, color table V5-V7, tk_chooseColor/messageBox Tk-doc verification V14-V15, P1-P8 NEEDS-PROBE list), v1→v2 port-deltas table
- `19-RESEARCH-integration.md` — handler-scope fan-in pattern (§3.0), wave matrix (§5), combobox ban (§6), desync options (§8.8), DIFF-04 palette recommendation (§8.1)

### NEEDS-PROBE / NEEDS-VERIFY items owned by this doc
- `tk_messageBox -type yesno` / `-icon question` / `-detail` — Tk-doc-verified, NOT yet exercised in v2 → human-verify item (G3/G4)
- DIFF-04 palette menu rendering (named entries; optional swatch tint) → human-verify item (G6)
- `::vmd_mouse_mode` live-update on hotkey presses (the §5 probe) → one console line in the Phase-19 session
- Windows-native `tk_chooseColor` return form (mechanisms P1) — only if the free-picker path is chosen

## Metadata

**Confidence breakdown:**
- Widget availability: HIGH for every "exercised in v2" row (file:line cited); MEDIUM for the two first-exercise widgets (Tk-doc-verified, flagged)
- v1 UX reference: HIGH — shipped code + user-approved phase records
- Layout/interaction analysis: HIGH for pack mechanics and modal-over-modeless precedent (three proven dialog classes in v2); MEDIUM for cosmetic recommendations (label position, swatch tint)
- Session design: HIGH — direct extension of the approved 17.1-14 pattern
- Desync: LOW until the probe runs (honestly flagged — the fix's feasibility hinges on an unverified VMD behavior)

**Research date:** 2026-09-24
**Valid until:** post-Phase-18 execution shifts game_tab.tcl-adjacent line numbers only (proc-name anchors survive); Tk 8.5.6 facts are fixed-target stable.

---

## RESEARCH COMPLETE

**Phase:** 19 - In-game Actions (GUI/UX layer)
**Confidence:** HIGH (all widget/UX claims cite shipped v2 or shipped+user-approved v1 code; the two honest gaps — yesno-type first exercise and the desync probe — are sketched as session items, not unknowns)

### Key Findings

- **Every needed widget is already exercised in v2 except two:** ttk::button/label/labelframe, plain menubutton+menu, tk_messageBox(-parent), and native modal file dialogs all ship today; `ttk::combobox` is banned (18-06), and only `-type yesno` + the DIFF-04 picker UI are first-exercise (Tk-doc-verified, human-verify items).
- **v1's UX is fully specified and user-approved:** exact labels ("Hint", "Reveal one", "Reveal all", "Found hiders → Hide/Show/Recolor found", "Restart", "Cleanup model"), exact confirm copy, +N counter semantics, the C8 counter-reset lesson, no-op-guard convention — port verbatim except the Restart tooltip (v2 restart is a same-count REPLAY; reword).
- **DIFF-04 fork resolved with a recommendation:** curated named-color palette menubutton (accessibility-first: color-blind players choose by LABEL; zero NEEDS-PROBE surface; no color-table mutation) over tk_chooseColor→slot-17 — but the sibling disagreement is documented for the planner/user to confirm.
- **Modal-over-modeless is a proven class** (win box, error boxes, file dialogs): confirms block interaction while up, `after` timers keep ticking under them (expected, document it), no modal nesting is reachable from our flows, cancel paths are true no-ops by construction.
- **Session design:** new `vmd/tests/actions_verify.tcl` in the rep_verify.tcl shape — widget-state auto-dump via textvariable reads + showstate/color getters, driver never calls confirm-bearing handlers, **3 pastes** (source / pv_r5b / pv_finish), G1-G12 verdict table; the desync fix is probe-gated (one `puts $::vmd_mouse_mode` line decides trace vs defer).

### File Created

`.planning/phases/19-in-game-actions/19-RESEARCH-gui.md`

### Ready for Planning

GUI-layer research complete — the planner consumes this doc together with `19-RESEARCH-mechanisms.md` (VMD facts + NEEDS-PROBE P1-P8) and `19-RESEARCH-integration.md` (seam anchors + wave matrix). Open decision for the user (if no CONTEXT.md arrives): DIFF-04 palette vs free picker.
