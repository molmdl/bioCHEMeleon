# Phase 16: MVP Core Loop (Sphere) — Game-Tab GUI & Game-Loop Research

**Researched:** 2026-08-30
**Domain:** Tk 8.5 Game tab (countdown, timer, rolling log, remaining count, win message, pick-vs-rotate toggle) + v1 game-loop port map
**Confidence:** HIGH for v1 port source (read directly), widget availability (probed in Phase 14), `after` idioms (VMD-shipped scripts); MEDIUM for modal-win render behavior and pick-bridge contract (human-verify items)

Companion research: the **pick mechanism itself** (PickBridge, `mouse callback`, `vmd_pick_*` contract) is covered by a separate researcher. This doc covers the **Game-tab side**: what the pick callback calls into, and everything the player sees.

---

## 0. Scope corrections to the phase brief (read first)

1. **`ttk::spinbox` does NOT exist in VMD's Tk 8.5.6** (added in 8.5.9). The phase brief's claim "ttk::spinbox works in VMD's Tk 8.5" is wrong — already corrected in 14-RESEARCH-gui.md:13 and the shipped `setup_tab.tcl` uses plain `spinbox`. Irrelevant to the Game tab (no spinboxes there) but recorded here so the error doesn't propagate.
2. **The BTN-07 Start button does not exist yet.** `setup_tab.tcl` `build_actions` (:230-238) has only Reset/Randomize/Save/Load (BTN-01..04). There is no Start-button stub. Phase 16 must ADD the Start button + its handler. (v1 added Start in its Phase 4 too — 04-RESEARCH.md Risk 4.)
3. **`ttk::scrollbar` is listed in STACK.md:22 but was never exercised** and the probed Phase-14 widget table omits it. STACK.md's ttk list has been wrong once (ttk::spinbox). This research prescribes the **plain `scrollbar`** for the log widget (core Tk, ecosystem-verified) — see §2.

---

## 1. v1 game-loop port map (READ-SOURCE VERIFIED)

All v1 citations are to `pymol/biochemeleon/` files read in full for this research. v1's game loop was researched/verified in `.planning/phases/04-mvp-core-loop-sphere/04-RESEARCH.md` and shipped; the summaries (04-04, 04-06) record the Qt-runtime bugs that shape the port.

### 1.1 v1 architecture (who owns what)

```
v1 __init__.py (PluginDialog — orchestrator, owns tabs + controller)
  _on_start (:242-261): collect_state -> _prepare_and_start (backup+generate+insert+register)
                        -> tabs.setCurrentWidget(game_tab) -> game_tab.start_countdown(controller)
  wiring (:200-204):    setup_tab.start_btn -> _on_start ; game_tab._restart_btn -> _on_restart
v1 gui_game.py (GameTab — Qt view + QTimer + countdown chain)
v1 game.py (GameController — set_callbacks/_remaining/on_pick/win, registry single source of truth)
v1 wizard.py (PickWizard — do_pick -> controller.on_pick)   [v2: PickBridge — other researcher]
v1 setup_state.py (format_remaining :418-447, format_debrief_text :503 — PURE)
v1 registry.py (remaining_by_rep :274, counts_by_rep :250 — PURE)
```

Port principle confirmed by 04-04-SUMMARY patterns: the controller is **duck-typed** (GUI never imports game.py; controller reaches GUI only via `set_callbacks`). v2 equivalent: `game_tab` reaches game logic via namespace calls + callback procs; pure logic stays in `lib/` (tcltest-able); `game.tcl` stays the composition root.

### 1.2 Component-by-component port map

| # | v1 component | v1 implementation (file:line) | v2 equivalent | Confidence |
|---|--------------|-------------------------------|---------------|------------|
| 1 | **State machine** | IMPLICIT: `GameTab` flow `start_countdown -> _countdown_step(3..0) -> _begin_play`; `GameController._started` flag gates everything (game.py:57, :250, :385); win leaves `_started=True` until cleanup (game.py:219-225) | **EXPLICIT pure state machine** in `lib/game_logic.tcl`: `idle -> countdown -> playing -> won` (+ guards). v2 needs explicit states because VMD pick callbacks fire asynchronously and must be gated by state==playing (v1's wizard only existed during play) | HIGH (design; v1 source verified) |
| 2 | **Timer ticking** | `QtCore.QTimer` interval 1000, `timeout.connect(_on_tick)`, main thread (gui_game.py:108-111). NEVER `threading.Thread` (04-RESEARCH Q10) | Self-rescheduling `after 1000 ::biochemeleon::game_tab::tick` (PITFALLS.md Pitfall 6 prescribes exactly this). Tcl is single-threaded — no thread-safety machinery at all | HIGH |
| 3 | **Elapsed math** | `_start_time = time.time()` at GO; each tick `elapsed = time.time() - _start_time` (gui_game.py:228-232, :277-278). **Drift-free absolute-time, NOT a tick counter** (04-RESEARCH Q11: a counter drifts if ticks are delayed) | `clock seconds` epoch captured at `timer_start`; each tick computes `[expr {[clock seconds] - $epoch}]`. Optionally injectable `now` arg for tcltest | HIGH |
| 4 | **Countdown 3-2-1** | `QTimer.singleShot(1000, lambda: self._countdown_step(n-1))` chain — **never `time.sleep`** (blocks the Qt event loop; 04-RESEARCH Q21, 04-04-SUMMARY). `start_countdown` clears the log, logs "Get ready...", calls `_countdown_step(3)` (gui_game.py:234-264) | Chained one-shot `after` callbacks with **id tracking**: `set after_countdown [after 1000 ::biochemeleon::game_tab::countdown_step]`; `after cancel $after_countdown` on cleanup/restart/close. The step SEQUENCE (3→2→1→GO) is pure logic in `game_logic::countdown_tick`; the scheduling is the GUI's only job | HIGH |
| 5 | **Timer start timing** | `_start_time` set in `_begin_play` (at GO!), NOT in `start_countdown` — "timer measures play time, not countdown time" (04-04-SUMMARY lesson; gui_game.py:277-278) | `game_logic::timer_start` called from the GO branch of `countdown_tick`, never at Start-button press | HIGH |
| 6 | **Rolling info box** | `QTextEdit` read-only; `append(str)` auto-scrolls (gui_game.py:24-27, :119-120). v1 chose QTextEdit over QListWidget ("simpler + more natural", 04-RESEARCH Q23) | Core-Tk **`text` widget**: keep `-state disabled`; insert via temporary `state normal` → `insert end` → `state disabled` → `see end`. Wrapped in a frame with a plain `scrollbar` (§2.2) | HIGH |
| 7 | **Log event formats** | Controller logs: "Miss!", "Already found!", "Found one! %d remaining", "Revealed one! …", "Hint: …" (game.py:170, :173, :187, :293, :272); GUI logs countdown numbers + "GO!" | Port verbatim into the pure log model (`game_logic::log_append kind msg` → returns the formatted line; kinds: countdown/miss/found/win). Phase 16 scope: countdown + Miss/Found lines + win line | HIGH |
| 8 | **Remaining count (total)** | `GameController._remaining()` = count of status=='hidden' (game.py:113-116); GUI label via `on_remaining_changed` callback | `registry.tcl` additions: `remaining {}` (count hidden) + `remaining_by_rep {}` (ports of v1 registry.py:113-116-equivalent + :274-295). **15-RESEARCH-registry-game.md:88 explicitly deferred these to Phase 16** | HIGH |
| 9 | **Remaining count (easy per-rep)** | PULL model: `_update_remaining` reads `controller.registry.remaining_by_rep()` when `controller._easy_mode` and formats via PURE `format_remaining(remaining, counts, easy_mode)` (gui_game.py:122-130; setup_state.py:418-447). Format: `Remaining: %d` or `Remaining: %d  (Rep: n, …)` in GAME_REPS order, non-zero only, exactly two spaces before the paren | Port `format_remaining` to `lib/setup_state.tcl` (v1 keeps it in the pure layer — same home), `remaining_by_rep` to `lib/registry.tcl`. Easy flag comes from the applied setup state (`difficulty_easy`, already in the applied dict). ttk::label `-textvariable` update | HIGH |
| 10 | **Win flow** | `on_pick`: last find → `remaining == 0` → `win()` (game.py:189-190) → `elapsed = time.time() - _start_time` → `on_win(elapsed)` callback; wizard deactivation DEFERRED to the GUI (game.py:215-228) | `game_logic::finish_win` (state → won, freeze elapsed) → GUI `_on_win`: cancel tick after-id → (100 ms render delay, §1.4 Bug A) → `tk_messageBox` → deactivate pick bridge. Timer stop is GUI-side in v1 (gui_game.py:301); v2 can freeze in pure layer AND cancel the GUI tick — do both | HIGH |
| 11 | **Win message** | **Modal child dialog allowed** (v1 AGENTS rule; 04-04-SUMMARY): `QMessageBox` titled "You win!", "You found all %d hiders in %d:%02d!" (gui_game.py:337-345) | `tk_messageBox -icon info -parent $w -title "You win!" -message "You found all N hiders in M:SS!"`. Precedent already shipped: setup_tab.tcl:407,660,667,682 uses `tk_messageBox -parent $w`. Modal child is explicitly allowed (PITFALLS.md Pitfall 4: "Short error/confirm dialogs MAY use tk_messageBox") | HIGH |
| 12 | **Pick-vs-rotate control** | **v1 HAD NONE.** PyMOL wizards coexist with rotate: help text says "Left-DRAG still rotates… A quick click picks; a drag rotates" (v1 `__init__.py:97-98`; 04-RESEARCH Q8: do_pick fires on picks, not drags) | **v2-NEW UI** (PITFALLS.md:180 mandates it): two `ttk::radiobutton`s "Rotate" / "Pick atoms" sharing `-variable`, calling the PickBridge's mode proc (§5). VMD pick and rotate are mutually exclusive mouse modes (hotkeys r / 0, hotkeys.tcl:109-140) | HIGH (v1 absence verified; v2 need per PITFALLS) |
| 13 | **Restart mid-game** | `_begin_play` does `self._timer.stop()` DEFENSIVELY before `.start(1000)` — "stop any prior timer (Restart mid-game)" (gui_game.py:285) | `catch {after cancel $after_tick}` + `catch {after cancel $after_countdown}` before re-arming, everywhere a round (re)starts | HIGH |
| 14 | **Tab switch from code** | `self.tabs.setCurrentWidget(self.game_tab)` (`__init__.py:260`; async path :641, :866) | `$w.nb select $w.nb.game` — ttk::notebook's `select` subcommand (core ttk 8.5 API). `raise` on the child frame does NOT update notebook tab state — always use `select` | HIGH |
| 15 | **on_pick scoring** | `registry.get(id)` → None: log "Miss!" (no harm, LOOP-01) → status=='found': "Already found!" → else `mark_found` + recolor + log + remaining callback + win check (game.py:118-190). Registry is the single source of truth (LOOP-02) | `game.tcl::on_pick {game_state index}`: `registry::is_hider $index` → miss / `registry::hider_status` already-found / `registry::mark_found` + visual feedback + `game_logic` callbacks. v2 key is atom `index` (no global atom id), molid implicit (game molecule) | HIGH |
| 16 | **Found-hider visual** | `cmd.color('green', "obj and id N")` (game.py:211-213) | **OPEN** — VMD colors per-REP, not per-atom (FEATURES.md:77): add/modify a selection-scoped rep (`mol modcolor` with selection `index <idx>`) or `$sel set color` (UNVERIFIED). Owned by the pick-wiring plan; see §7 Open Questions | LOW (mechanism unverified) |

### 1.3 v1 runtime lessons that shape the port (04-06-SUMMARY + gui_game.py comments)

- **Bug A — modal swallows the last frame:** the final `cmd.color('green')` was invisible because the modal win dialog blocked the event loop before the redraw landed. Fix: `cmd.refresh()` + `QTimer.singleShot(100, _finish_win)` (gui_game.py:289-304). **v2 analog:** schedule the `tk_messageBox` via `after 100` after the win, and force a redraw (`display update` — VMD command, unverified in this repo, see §7) so the last visual change lands first. MEDIUM confidence that VMD's Tk modal even blocks rendering (Tk modals pump timer events) — keep the cheap 100 ms delay regardless; it is harmless.
- **Bug B — modal parented to the wrong window:** parent the message box to the TOP-LEVEL window so it appears above the viewer (gui_game.py:132-137, :337). **v2 analog:** `tk_messageBox -parent $w` (setup_tab precedent).
- **Bug C — cleanup after dismissal:** v1 Phase 4 auto-ran `cleanup()` after the win dialog dismissed (gui_game.py:346-357). **v2 decision:** DEFER auto-cleanup to the cleanup/restart phase (v2 `game::cleanup` does a whole-molecule reload — heavier; Phase 16 SC only requires timer-stop + message). Do NOT auto-cleanup in Phase 16; leave the found scene for inspection. Deviation from v1 Phase 4, deliberate.
- **Wizard deactivation on win:** v1 deactivates the wizard in the delayed `_finish_win` (gui_game.py:321-324), NOT in `_on_win` and NOT in `win()` (double-deactivate avoidance; 04-04-SUMMARY). **v2:** the win handler calls the PickBridge's deactivate/restore exactly once.
- **No `time.sleep`-style blocking anywhere** (04-04-SUMMARY: "NEVER time.sleep"). v2: no `vwait` (PITFALLS.md:212 — re-enters the event loop, hangs), no busy loops.

### 1.4 What ports 1:1 vs what must change

**Ports 1:1 (pure tcl, tcltest-able):** countdown step sequence, timer epoch/delta math, M:SS formatting, log line formats, remaining math, remaining_by_rep, format_remaining, the miss/found/already-found/win scoring decision.

**Must change:** QTimer→`after` chains with explicit id tracking (v1's QTimer died with the widget; v2 `after` ids outlive widgets — new cancel obligations, §4); QMessageBox→tk_messageBox; `time.time()`→`clock seconds`; implicit `_started` flag→explicit state machine; wizard-activates-pick→mouse-mode toggle via PickBridge; lazy Python import→tcl `source` order (call-time proc resolution makes ordering a non-issue, game.tcl:9-12).

---

## 2. Game tab build spec

### 2.1 File, namespace, sourcing

- **File:** `vmd/gui/game_tab.tcl` (mirrors setup_tab.tcl exactly).
- **Namespace:** `::biochemeleon::game_tab`.
- **Sourcing:** top level of `gui/dialog.tcl`, next to the setup_tab source line (dialog.tcl:26): `source [file join [file dirname [info script]] game_tab.tcl]`. **MUST stay top-level** (the `[info script]` lesson, dialog.tcl:14-19 — inside a proc body `[info script]` resolves to the caller's context and breaks).
- **Headless-safe:** like setup_tab.tcl, the file contains ONLY `namespace eval` + proc definitions (no widget commands execute at source time), so sourcing under `-dispdev text` is safe. No `tk_version` guard needed at source time; the dialog itself is already guarded at the entry (biochemeleon.tcl:118).
- **Build:** `::biochemeleon::game_tab::build $nb.game` called from `open_dialog` (dialog.tcl:55-57), **eager** (replacing the placeholder), same as setup_tab. Eager is correct: the tab is cheap to build, `after` chains don't exist until Start, and lazy building would need placeholder+replace churn for zero benefit.
- **Entry source order** (biochemeleon.tcl:70-93) gains one pure-lib line: `source [file join $_dir lib game_logic.tcl]` placed with the pure block (after registry.tcl, before demos.tcl). `game_tab.tcl` needs no entry edit (dialog.tcl sources it).

### 2.2 Widget tree (all verified-available in VMD's Tk 8.5.6)

```
$nb.game (ttk::frame — exists since Phase 13, dialog.tcl:48)
├── g.status (ttk::frame)
│   ├── ttk::label .timer    -textvariable ::biochemeleon::game_tab::timer_text    ;# "0:00"
│   ├── ttk::label .remain   -textvariable ::biochemeleon::game_tab::remain_text   ;# "Remaining: -"
│   └── ttk::label .mode     -textvariable ::biochemeleon::game_tab::mode_text     ;# "Mouse: Pick" | "Mouse: Rotate"
├── g.loglab (ttk::label -text "Info log:")
├── g.logf  (ttk::frame)
│   ├── text      .logf.log  -state disabled -wrap word -height 10   ;# CORE Tk (readonly via state)
│   └── scrollbar .logf.sb -command {.logf.log yview}                ;# PLAIN scrollbar (see note)
│       (text -yscrollcommand {.logf.sb set})
└── g.mouse (ttk::labelframe -text "Mouse mode")
    ├── ttk::radiobutton -text "Rotate"      -value rotate -variable ::biochemeleon::game_tab::mouse_mode
    └── ttk::radiobutton -text "Pick atoms"  -value pick   -variable ::biochemeleon::game_tab::mouse_mode
```

Widget-availability evidence: `ttk::notebook/frame/labelframe/label/radiobutton/button` all core-ttk-8.5.0, `ttk::notebook/frame/label` already proven by Phase 13 + the whole shipped setup tab (14-RESEARCH-gui.md:27-36). `text`/`scrollbar` are core Tk 8.5 (not ttk) — always present. **Plain `scrollbar` chosen over `ttk::scrollbar`** because the ecosystem-verified idiom is plain (all 5 reference plugins use plain Tk widgets; the probed Phase-14 table never exercised ttk::scrollbar; precedent for mixing is the shipped plain `spinbox`, setup_tab.tcl:20 comment).

Countdown display: v1 logs "Get ready..."/3/2/1/GO! into the log (gui_game.py:250-263). Port identically (log-only countdown — no separate big label needed; matches v1 UX exactly).

Layout: pack `status` top-fill-x, `loglab` top, `logf` top-fill-both-expand (the log stretches — v1 gave QTextEdit stretch=1, gui_game.py:38), `mouse` bottom-anchor-w.

### 2.3 game_tab proc list (thin view)

| Proc | Purpose |
|------|---------|
| `build {parent}` | Create widgets; init textvariables ("0:00", "Remaining: -", "Mouse: Rotate"); stash `$w` + widget paths in ns vars |
| `start_round {game_state}` | Entry from the Start handler: stash game_state, `game_logic::round_reset` + `begin_countdown 3`, clear log text, log "Get ready...", fire first `countdown_step` (direct call, no delay for "3" — v1 logs 3 immediately then singleShots; gui_game.py:256-261) |
| `countdown_step {}` | `game_logic::countdown_tick` → {label done?}; insert label into log; if not done: `set after_countdown [after 1000 ::biochemeleon::game_tab::countdown_step]`; if done: log "GO!", `game_logic::begin_play` (starts timer), tell PickBridge pick mode, start tick loop |
| `tick {}` | `game_logic::timer_elapsed` → `game_logic::format_mmss` → set `timer_text`; re-arm `set after_tick [after 1000 ...]` ONLY if state is playing |
| `on_log_line {line}` | Insert one line into the text widget (state-normal → insert → state-disabled → `see end`) — the callback game logic drives |
| `update_remaining {}` | Pull model (v1 gui_game.py:122-130): `registry::remaining` + `remaining_by_rep` when easy → `setup_state::format_remaining` → `remain_text` |
| `on_win {elapsed n_hiders}` | Cancel tick id; `mode_text` → Rotate + PickBridge deactivate (once); optional `after 100` → `tk_messageBox -parent $w ...` → log win line |
| `set_mouse_mode {mode}` | radiobutton -command: sets `mode_text`, calls PickBridge mode proc (§5) |
| `stop_all_timers {}` | `catch {after cancel $after_tick}; catch {after cancel $after_countdown}` — called by on_close, restart, cleanup, and defensively at the top of `start_round` (v1 gui_game.py:285 parity) |
| `raise_tab {}` | `$w.nb select $w.nb.game` |

Callbacks flow like v1: game logic (`game.tcl`/`game_logic.tcl`) reaches the GUI only through registered callbacks — `game_tab::on_log_line` / `update_remaining` / `on_win` (v1 `set_callbacks` pattern, game.py:94-111). Keep the indirection: headless tests drive the pure layer with no-op callbacks; the GUI registers real ones in `start_round`.

### 2.4 Where the Start button (BTN-07) wires

v1 keeps orchestration at the dialog level (`PluginDialog._on_start`, __init__.py:242-261). v2 equivalent — add to `gui/setup_tab.tcl` (the button lives in the Actions group) with the handler at dialog scope or a small `::biochemeleon::on_start`:

```
on_start:
  1. state    = setup_tab::collect_state
  2. resolve target molid (demo/loaded via demos bridge; fetch is later-phase)
  3. game_state = game::start_game $molid $hider_count          ;# Phase 15 signature (15-RESEARCH:155)
  4. game_tab::raise_tab
  5. game_tab::start_round $game_state
```

Steps 3-5 ordering is v1-identical (start_game is synchronous; the countdown begins only after generation completes — large-molecule blocking is mitigated later by `after 0` chunking per PITFALLS.md:205, not in Phase 16 scope). Store `game_state` in `::biochemeleon::game_tab::game_state` (ns var; the entry's `state` dict already reserves `timer`/`found` keys for a later persistence phase — biochemeleon.tcl:47).

---

## 3. Pure game-logic layer (`vmd/lib/game_logic.tcl`)

**PURE** (stdlib tcl only — no `mol`, no `tk`, no `after`): unit-testable with the exact harness pattern of `vmd/tests/test_registry.test` (tclsh standalone OR headless VMD; `source [file join [pwd] vmd lib game_logic.tcl]`). Sourced by the entry in the pure block. Purity gate greps identical to registry's (15-RESEARCH:95-96).

### 3.1 State machine (namespace singleton, guarded re-source)

```tcl
namespace eval ::biochemeleon::game_logic {
    variable state  "idle"       ;# idle | countdown | playing | won
    variable countdown_steps 0
    variable timer_epoch   0     ;# clock seconds at GO
    variable timer_elapsed_final 0 ;# frozen on win
    variable log_lines [list]    ;# formatted rolling log (newest last)
    namespace export round_reset begin_countdown countdown_tick begin_play \
                     timer_start timer_elapsed timer_stop finish_win \
                     format_mmss log_reset log_append log_lines
}
```

| Proc | Contract | Notes |
|------|----------|-------|
| `round_reset {}` | state→idle; clear countdown/timer/log | Called by `start_round` |
| `begin_countdown {}` | idle→countdown; `countdown_steps 3` | Errors if not idle (surface caller bugs — registry `mark_found` precedent, registry.tcl:50-53) |
| `countdown_tick {}` | Decrement; returns `[list $label $done]` where label ∈ {3,2,1} and done=0, or label="GO!" done=1. On done: state stays countdown until `begin_play` | The PURE part of the chain — GUI decides whether to schedule another `after` |
| `begin_play {}` | countdown→playing; calls `timer_start` | Errors if not countdown |
| `timer_start {}` | `timer_epoch [clock seconds]` | Only meaningful from begin_play |
| `timer_elapsed {}` | playing: `[expr {[clock seconds] - $timer_epoch}]`; won: `timer_elapsed_final`; idle/countdown: 0 | Optional `now` arg (defaults `[clock seconds]`) for deterministic tests — drift-free absolute delta, v1 Q11 |
| `finish_win {}` | playing→won; freezes `timer_elapsed_final` | Errors if not playing — prevents double-win from duplicate pick callbacks |
| `format_mmss {secs}` | `"M:SS"` (`expr {int(...)}` guards) | v1 gui_game.py:230-232 format, now testable |
| `log_reset` / `log_append {kind msg}` / `log_lines {}` | `log_append` formats + appends + returns the line. Formats (v1 game.py:170/173/187 + gui_game countdown): `Miss!`, `Already found!`, `Found one! <n> remaining`, `Hint: ...` (later phase), countdown numbers + `GO!` | The text widget is a VIEW; the model is authoritative for format/trim |

### 3.2 registry.tcl additions (pure, deferred-to-16 per 15-RESEARCH:88)

| Proc | Contract (v1 port) |
|------|--------------------|
| `remaining {}` | Count of records with status==hidden (v1 game.py:113-116) |
| `remaining_by_rep {}` | `{rep count}` for HIDDEN records, zero-filled over GAME_REPS order (v1 registry.py:274-295; skips `rep ""` placeholder records the same way v1 skips `rep=None`) |
| `hider_status {idx}` | "hidden"/"found"/absent — the already-found gate for `on_pick` (15-RESEARCH deferred it) |

### 3.3 setup_state.tcl addition

`format_remaining {total counts_by_rep easy_mode}` — verbatim port of v1 setup_state.py:418-447 (pure): easy+non-empty counts → `"Remaining: %d  (Rep: n, ...)"` (GAME_REPS order, >0 only, two spaces); else `"Remaining: %d"`. Add to `namespace export`.

### 3.4 Concrete tcltest cases (vmd/tests/test_game_logic.test + additions)

game_logic.test: `round_reset→idle`; `countdown sequence 3→(1,0)(1,0)(1,0)(GO!,1)`; `countdown_tick errors after done`; `begin_play errors from idle`; `timer_elapsed 0 before start`; `timer_elapsed` with injected now=epoch+65 → 65; `finish_win freezes elapsed` (inject now); `finish_win errors twice`; `format_mmss 0→"0:00", 65→"1:05", 600→"10:00"`; `log_append found` line format; `log_reset clears`.
registry.test additions: `remaining counts hidden only`; `remaining_by_rep zero-fills GAME_REPS + sums to remaining`; `hider_status hidden/found/error`.
setup_state.test additions: `format_remaining hard mode`; `easy with counts` (exact string); `easy all-zero → total-only`.

---

## 4. `after` discipline (the blocking/cancellation rules)

**No blocking anywhere.** Tcl is single-threaded; `after` callbacks run on the main event loop (PITFALLS.md Pitfall 6). Countdown = chained ONE-SHOT `after 1000` (v1 `QTimer.singleShot` chain 1:1); timer = SELF-RESCHEDULING `after 1000` tick (PITFALLS.md:204 prescribes this exact idiom). **Never `vwait`** (re-enters the event loop; hangs if the awaited var is set in the same proc — PITFALLS.md:212, AGENTS.md gotcha).

### VMD-shipped `after` idioms (evidence)

- **`viewmaster.tcl:202-207` — THE idiom for tracked, cancellable timers** (debounced save):
  ```tcl
  # viewmaster.tcl:202-207 (verbatim shape)
  if {$save_after_id != ""} { after cancel $save_after_id }
  set save_after_id [after 1000 [namespace current]::save_session]
  ```
  Id in a variable; `after cancel` before re-arm; namespace-qualified command name.
- **`mergestructs.tcl:298,312,406,495,568,668,725,771`** — `after idle "${ns}::proc"` for deferred UI updates (8 call sites — the ecosystem default for "update UI without blocking the current callback").
- VMD core scripts (`vmd-ref/scripts/*.tcl`) use NO timers — plugins are the idiom source.

### Rules for game_tab (every one is a real failure mode otherwise)

1. **Track every id**: `after_tick`, `after_countdown` ns vars. Cancel-with-catch before every re-arm (`catch {after cancel $old}` — after-cancel of an already-fired id is harmless but catch costs nothing).
2. **Cancel points** (all four): `on_close` (WM_DELETE — dialog.tcl:77 extends here), cleanup/restart (later phase, but `stop_all_timers` exists now), win (cancel tick), `start_round` entry (defensive — v1 gui_game.py:285 "Restart mid-game").
3. **`after` ids outlive widgets** (v2-specific; v1's QTimer died with its widget): every callback FIRST guards `if {![winfo exists $w]} { return }` and wraps widget writes in `catch` — a closed dialog must never raise "bad window path name" on a stray tick.
4. **Re-arm conditionally**: `tick` re-arms ONLY if `game_logic` state == playing; `countdown_step` re-arms only if not done. A forgotten re-arm kills the timer; an unconditional one leaks forever.
5. **Schedule by VALUE, not string-interp**: `set after_tick [after 1000 ::biochemeleon::game_tab::tick]` — fully-qualified literal command (viewmaster's `[namespace current]::` shape generalized). Never build command strings with variable interpolation.
6. **Reschedule at the END of tick** (PITFALLS.md:204) so a slow display update can't pile up callbacks.
7. **No `update` calls** in callbacks (re-entrancy hazard; the ecosystem never calls it).

---

## 5. Pick-vs-rotate UI spec

- **Control:** two `ttk::radiobutton`s ("Rotate" / "Pick atoms") sharing `-variable ::biochemeleon::game_tab::mouse_mode`, in a "Mouse mode" labelframe at the bottom of the Game tab (§2.2). Radiobuttons (not a checkbutton) because the underlying VMD mouse modes are mutually exclusive — the control state mirrors reality. Matches the shipped radiobutton idiom (setup_tab.tcl:110-118).
- **What it calls:** `-command {::biochemeleon::game_tab::set_mouse_mode}` reads `mouse_mode` and invokes the PickBridge's mode-switch proc. **ASSUMED contract (owned by the pick researcher — confirm before planning):** a single proc like `::biochemeleon::pick_bridge::set_mouse_mode {pick|rotate}` that internally does `mouse mode pick 0` / restore-rotate and manages `mouse callback on/off` + saved prior mode (PITFALLS.md:178). The Game tab must NOT call `mouse mode` directly — mouse-mode save/restore belongs to the bridge.
- **Default flow:** Start → countdown in whatever mode the player had; at GO → auto-switch to **Pick** (v1 activated its wizard at `_begin_play`, gui_game.py:268-269); win → restore **Rotate** (v1 deactivated the wizard in `_finish_win`, gui_game.py:321-324 — exactly once). Mid-game the player toggles freely (hotkeys r/0 keep working — hotkeys.tcl:109-140; the radios are a convenience, not a gate. Keeping the radio label in sync with hotkey changes is a polish nicety — NOT Phase 16 scope; document hotkeys in the log/help instead).
- **Tab switching mid-game:** NO special handling needed. The game continues when the player browses to the Setup tab — `after` callbacks are application-global, not tab-visibility-scoped; the pick mode is a VMD mouse mode, independent of which Tk tab is shown. v1 had the same property (QTimer kept ticking with any tab active). Do NOT pause on tab-switch (v1 didn't; out of scope).

---

## 6. Common Pitfalls (Tk 8.5 / event-loop hazards)

### 6.1 Stray `after` callbacks after dialog close (v2-NEW — v1 was immune)
**What:** close the dialog mid-countdown/mid-game → a pending `after` fires, touches destroyed widget paths → "bad window path name" spam in the VMD console (or worse, a callback that re-arms forever).
**Why:** v1's QTimer was a child QObject destroyed with the widget; v2 `after` ids live in the interpreter until fired/cancelled.
**Avoid:** `on_close` calls `game_tab::stop_all_timers` (extend dialog.tcl:77-88); every callback guards `winfo exists` + catch (§4.3).
**Detect:** close the window mid-countdown in the human-verify session; watch the console.

### 6.2 Double timer chains after Restart / repeated Start
**What:** start → restart → two tick loops interleave; the timer label jumps 2×/s or flickers.
**Avoid:** `stop_all_timers` at the top of `start_round` (v1 gui_game.py:285 "defensive: stop any prior timer").

### 6.3 Timer started at the wrong moment
**What:** countdown time leaks into the score (player billed for 3 s of "Get ready").
**Avoid:** `timer_start` only in the GO branch (`begin_play`) — v1 lesson recorded in 04-04-SUMMARY ("_start_time set in _begin_play NOT start_countdown").

### 6.4 Tick-counter drift
**What:** an `elapsed += 1` tick counter lags real time after event-loop stalls (large-molecule redraws, modal dialogs).
**Avoid:** absolute-epoch delta each tick (v1 Q11: `time.time()` delta; v2 `clock seconds` delta). Modal `tk_messageBox` is the exact stall case — Tk modals DO keep pumping timer events (standard Tk), but ticks may coalesce.

### 6.5 `vwait` for the countdown (the classic hang)
**What:** "wait 3 seconds" implemented as `vwait`/`tkwait`/a `while` loop → frozen VMD or infinite loop.
**Avoid:** chained `after` only. PITFALLS.md:212 + AGENTS.md Tcl-8.5 gotcha list.

### 6.6 `variable a b` name-value trap
**What:** `variable after_tick after_countdown` sets `after_tick` to the STRING "after_countdown" (name-VALUE pair, not two links) — probe-verified lesson, setup_tab.tcl:246-250.
**Avoid:** one `variable` declaration per line, link-only (no value) for arrays/handles. Every proc declaring ns vars follows setup_tab.tcl:251-260.

### 6.7 Unqualified `tk_version` inside procs
**What:** bare `tk_version` checks LOCAL scope only — always absent inside a proc → guard always true/false incorrectly.
**Avoid:** `::tk_version` (Phase 13 lesson; setup_tab header comment :17-18). The game tab rarely needs it (only if a proc touches Tk conditionally).

### 6.8 text-widget readonly state left enabled
**What:** insert via `state normal` and forget `state disabled` → the player's stray typing corrupts the log.
**Avoid:** wrap EVERY insert: normal → insert → disabled → `see end` (one helper proc `on_log_line`, nothing else touches the widget). Also `-wrap word` for long messages.

### 6.9 Modal win message vs. the last render frame (v1 Bug A analog)
**What:** the final found-hider visual change may not be visible when the modal appears.
**Avoid:** freeze state → cancel tick → `after 100 {show tk_messageBox}` (v1: `cmd.refresh()` + 100 ms singleShot, gui_game.py:301-304). MEDIUM confidence VMD even needs this (Tk modals pump events, unlike Qt's modal grab) — the 100 ms is cheap insurance either way.
**Warning sign (human-verify):** last hider's visual change appears only AFTER dismissing the win box.

### 6.10 Pick callback firing outside `playing`
**What:** a stray pick (label-poll fallback especially) fires after win or before GO → duplicate win, scoring during countdown.
**Avoid:** `game.tcl::on_pick` gates on `game_logic` state == playing (v1 equivalent: the wizard only existed during play). `finish_win` errors on second call (§3.1).

### 6.11 `_loading`-style cascades on the Game tab
Lower risk than setup (fewer coupled widgets), but keep the pattern: textvariable writes inside `apply_state`-like flows (none in Phase 16) would need the guard. The radiobutton `-command` only fires on USER clicks — safe.

### 6.12 Tcl 8.5 syntax gates (pre-existing, re-run after edits)
No `lmap/try/throw/tailcall/coroutine/yield/finally`; brace ALL `expr`; `dict get` has NO 3-arg default (use a `_dget`-style helper or `dict exists`); no `grab set` anywhere in `gui/` (modeless gate — vmd/AGENTS.md commands section).

---

## 7. Open Questions (carry into planning / human-verify)

1. **PickBridge contract** (other researcher): exact proc name + arg shape for mode switching and for delivering `(molid, index)` into `game::on_pick`. This doc ASSUMES `pick_bridge::set_mouse_mode {pick|rotate}` + a callback into `game::on_pick`. Reconcile before writing 16-01.
2. **Found-hider visual feedback** — how to visually mark one atom found in VMD: `mol modcolor` on a selection-scoped rep (FEATURES.md:77 hint pattern) vs `$sel set color` (UNVERIFIED in this repo) vs hide-rep. Owned by the pick/wiring plan; headless-probeable (`atomselect set color` round-trip). v1 was `cmd.color('green', ...)` (game.py:211-213).
3. **`tk_messageBox` render behavior during modal** — does VMD keep rendering during a modal Tk message box (likely yes, Tk pumps timer events) and does the 100 ms pre-delay suffice? Human-verify item (SC4 session).
4. **`display update`** (force an immediate redraw before the modal) — believed to exist in VMD 1.9.3 but not yet cited in this repo's research; verify against the UG (vmd-ref/ug.pdf) or probe before using.
5. **Where the Start handler lives** — proposed `::biochemeleon::on_start` at dialog scope (mirrors v1 PluginDialog._on_start); alternative: a `start_game` proc inside setup_tab. Planner's call; the handler needs setup_tab state + game_tab + game.tcl, so dialog scope avoids cross-tab reach-ins.
6. **Restart/Cleanup buttons** — v1 had Restart on the Game tab (wired `__init__.py:204`); v2 cleanup/restart procs EXIST (game.tcl:85-101) but the buttons are a later phase. Phase 16 ships the loop without them (win leaves the found scene for inspection — deliberate deviation from v1-Phase-4 auto-cleanup, §1.3 Bug C).

---

## 8. Sources

### Primary (HIGH — read in full this session)
- `pymol/biochemeleon/gui_game.py` (414 lines) — GameTab: QTimer :108-111, `_log` :119-120, `_update_remaining` :122-130, `_on_tick` :228-232, `start_countdown` :234-256, `_countdown_step` :258-264, `_begin_play` :266-287, `_on_win`/`_finish_win` :289-357, Bug A/B/C comments.
- `pymol/biochemeleon/game.py` (415 lines) — `set_callbacks` :94-111, `_remaining` :113-116, `on_pick` :118-190, `win` :215-228, hint/reveal :232-318, cleanup :369-400.
- `pymol/biochemeleon/__init__.py` — wiring :200-204, `_on_start` :242-261, tab switch :260, help text :97-98 (no rotate toggle in v1).
- `pymol/biochemeleon/setup_state.py` — `format_remaining` :418-447, `format_debrief_text` :503+.
- `pymol/biochemeleon/registry.py` — `counts_by_rep` :250, `remaining_by_rep` :274.
- `vmd/gui/dialog.tcl` (89 l), `vmd/gui/setup_tab.tcl` (686 l), `vmd/lib/game.tcl` (101 l), `vmd/lib/registry.tcl` (74 l), `vmd/lib/setup_state.tcl` (293 l), `vmd/biochemeleon.tcl` :55-124 (source order, state dict), `vmd/tests/test_registry.test` (harness pattern).
- `.planning/phases/04-mvp-core-loop-sphere/04-RESEARCH.md` (952 l) + `04-04-SUMMARY.md` + `04-06-SUMMARY.md` (game-loop lessons, 3 GUI bugs).
- `.planning/phases/15-mutation-safety-hider-registry/15-RESEARCH-registry-game.md` — game_state shape, Phase-16 deferrals (:88), start_game Phase-16-readiness (:155).
- `vmd-ref/plugins/viewmaster.tcl:202-207`, `vmd-ref/plugins/mergestructs.tcl` (8× `after idle`) — shipped `after` idioms.
- `.planning/research/PITFALLS.md` Pitfalls 4 (modal/grab), 5 (pick modes + toggle mandate :180), 6 (after timer, vwait).
- `.planning/research/STACK.md` (Tk/ttk, headless limits :227), `.planning/phases/14-setup-tab-bundled-demos/14-RESEARCH-gui.md` (probed widget table :25-45, ttk::spinbox correction :13, tk_messageBox precedent :41).
- `.planning/research/FEATURES.md:77` (VMD per-rep coloring constraint), `ARCHITECTURE.md:428` (recolor seam), `hotkeys.tcl:109-140` via PITFALLS (r/0 hotkeys).

### Confidence summary
| Area | Level | Why |
|------|-------|-----|
| v1 port map | HIGH | v1 files read in full, line-cited |
| Widget availability | HIGH | Phase-14-probed table + shipped setup_tab usage |
| `after` idioms | HIGH | VMD-shipped scripts + PITFALLS.md prescription |
| Pure-layer design | HIGH | mirrors proven registry/setup_state patterns |
| Modal-win render timing | MEDIUM | Tk-standard behavior, VMD unverified → human-verify |
| PickBridge contract | MEDIUM | assumed seam; other researcher owns it |
| Found-hider visual | LOW | VMD per-rep coloring constraint known, mechanism unproven |
