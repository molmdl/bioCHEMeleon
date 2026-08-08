---
phase: 04-mvp-core-loop-sphere
verified: 2026-08-08T15:00:00Z
status: passed
score: 27/27 must-have truths verified (2 with documented, human-verified deviations)
re_verification: false
human_verification:
  - test: "Play a complete round in real Windows PyMOL GUI (1znf 3 hiders + 4wb3 10 hiders)"
    expected: "Start -> 3-2-1 countdown; click hider -> recolor green; non-hider click = no-op; log+timer+remaining update; all found -> timer stops + modal win message with time; viewer responsive after; new game works"
    why_human: "Qt/GUI behavior (tab switch, countdown display, ticking timer, real mouse clicks, modal win dialog) cannot run from WSL per AGENTS.md"
    status: "ALREADY APPROVED by user during plan 04-06 Task 2 checkpoint (2026-08-08). All 4 ROADMAP success criteria confirmed in a real PyMOL session."
---

# Phase 4: MVP Core Loop (Sphere) Verification Report

**Phase Goal:** The player can play a complete hide-and-seek round with sphere hiders — the PROJECT.md core value. If nothing else works, this loop works.
**Verified:** 2026-08-08T15:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

The Phase 4 core value loop is delivered and runtime-verified at BOTH tiers: a
headless cmd-coupled smoke (19/19 ALL PASSED) and a real-GUI human-verify
checkpoint (APPROVED — all 4 ROADMAP success criteria). Every must-have truth in
plans 04-01..04-06 is verified against the actual codebase, with two truths
implemented via documented, human-verified deviations (win-loop ordering +
win-display path). All 8 Phase-4 requirements are satisfied.

### Observable Truths

| #   | Truth (by plan) | Status | Evidence |
| --- | --------------- | ------ | -------- |
| 04-01.1 | generate_sphere_positions returns exactly n positions for n > 0 | ✓ VERIFIED | generators.py:27-32 `for _ in range(n)` append; test_count passes |
| 04-01.2 | Every returned position lies within the bounding-box extent | ✓ VERIFIED | generators.py:29-31 `rng.uniform(xmin,xmax)` per axis; test_bounds passes |
| 04-01.3 | Same seed produces identical output (deterministic) | ✓ VERIFIED | generators.py:23 `rng = random.Random(seed)`; test_seed_determinism passes |
| 04-01.4 | n=0 returns an empty list without error | ✓ VERIFIED | range(0) → []; test_n_zero passes |
| 04-02.1 | do_pick reads picked atom via cmd.identify('pk1', mode=1) and forwards id to controller.on_pick (NEVER cmd.index) | ✓ VERIFIED | wizard.py:45 `cmd.identify("pk1", mode=1)`, :53 `self.controller.on_pick(aid)`; no `cmd.index` anywhere |
| 04-02.2 | PickWizard ignores clicks on non-target objects (no-op miss) | ✓ VERIFIED | wizard.py:50-52 `if model != self.target_object: return` |
| 04-02.3 | Saves mouse_selection_mode on activate, restores on deactivate | ✓ VERIFIED | wizard.py:39 save (in __init__, immediately before activate), :40 set 0, :79 restore. Functional behavior correct; human-verify confirmed restore |
| 04-02.4 | Saves prior wizard on activate, restores on deactivate | ✓ VERIFIED | wizard.py:74 `cmd.get_wizard()` saved, :78 `cmd.set_wizard(self._saved_wizard)` restored |
| 04-02.5 | get_panel with Done (quit game) button | ✓ VERIFIED | wizard.py:81-83 returns panel with 'Done (quit game)' |
| 04-03.1 | on_pick(non-hider) -> 'Miss!' log, no mark_found, no cmd.color | ✓ VERIFIED | game.py:74-77; test_miss asserts cmd.color not called |
| 04-03.2 | on_pick(hidden hider) -> mark_found + cmd.color green + callbacks; remaining==0 -> win() -> on_win | ✓ VERIFIED | game.py:81-87; test_found asserts all |
| 04-03.3 | on_pick(already-found) -> 'Already found!' log, no double-count | ✓ VERIFIED | game.py:78-80; test_already_found asserts no extra cmd.color |
| 04-03.4 | _remaining() returns count of registry records with status=='hidden' | ✓ VERIFIED | game.py:60-63; test_remaining passes |
| 04-03.5 | set_callbacks stores on_log/on_remaining_changed/on_win (default no-op lambdas) | ✓ VERIFIED | game.py:46-58; test_set_callbacks_defaults passes |
| 04-03.6 | win() computes elapsed from _start_time, calls on_win, deactivates _wizard if set | ✓ VERIFIED (deviation) | game.py:101-102 computes elapsed + calls _on_win. Wizard deactivation moved to GUI `_finish_win` (deviation 01c48f6 — see Deviations). Goal met: wizard IS deactivated + win shown; human-verify APPROVED. test_win_with_wizard updated to assert win() does NOT deactivate |
| 04-04.1 | Game tab shows read-only rolling info log (QTextEdit) that appends + auto-scrolls | ✓ VERIFIED | gui_game.py:22-23 QTextEdit setReadOnly; :47 `_log` appends (QTextEdit.append auto-scrolls); human-verify confirmed |
| 04-04.2 | Timer label counting up from start, M:SS, 1 Hz QTimer | ✓ VERIFIED | gui_game.py:36-38 QTimer 1000ms, :52-56 `_on_tick` formats `%d:%02d` |
| 04-04.3 | Remaining-hiders count label updated via on_remaining_changed | ✓ VERIFIED | gui_game.py:25, :49-50 `_update_remaining`, :81 callback wired, :90 initial call |
| 04-04.4 | start_countdown runs 3-2-1 via QTimer.singleShot chain (NEVER time.sleep) then _begin_play | ✓ VERIFIED | gui_game.py:66-72 singleShot chain; no time.sleep in file |
| 04-04.5 | _begin_play creates PickWizard, activates, registers callbacks, starts QTimer | ✓ VERIFIED | gui_game.py:74-90 (lazy import PickWizard :75, activate :77, set_callbacks :79, start(1000) :89) |
| 04-04.6 | _on_win stops QTimer and shows modal win message with time taken | ✓ VERIFIED (deviation) | gui_game.py:104 stops timer; modal shown via _finish_win (:132-137 QMessageBox instance + WindowStaysOnTopHint). Plan said `QMessageBox.information`; impl uses instance form for stay-on-top (deviation 01c48f6). Functionally equivalent + better; human-verify APPROVED |
| 04-05.1 | Start button in Setup actions group, exposed as self.start_btn | ✓ VERIFIED | gui_setup.py:191 `self.start_btn = QPushButton("Start")` in "Setup actions" group |
| 04-05.2 | Pressing Start resolves target, warns on failure, generates spheres, starts game, shows spheres, switches tab, starts countdown | ✓ VERIFIED | __init__.py:76-129 — resolve target (:82-104), QMessageBox.warning on failure (:87-104), generate (:106-108), start (:118-124), show spheres (:126), setCurrentWidget (:128), start_countdown (:129) |
| 04-05.3 | start_btn.clicked connected to PluginDialog._on_start | ✓ VERIFIED | __init__.py:70 `self.setup_tab.start_btn.clicked.connect(self._on_start)` |
| 04-05.4 | hider_specs are [(pos, 'spheres') for pos in positions] fed into unchanged GameController.start | ✓ VERIFIED | __init__.py:109 `hider_specs = [(pos, "spheres") for pos in positions]`; game.py start() signature unchanged |
| 04-06.1 | Headless smoke: gen + insert+register + show + recolor + remaining decrement + miss + win + cleanup all pass (exit 0) | ✓ VERIFIED | smoke/phase4_smoke.py 148 lines, 17 main checks + 2 spikes = 19 executable when spikes pass. SUMMARY claims 19/19 ALL PASSED via cmd.exe runner (cannot re-run headless PyMOL from WSL per constraints; file's checks are real and comprehensive) |
| 04-06.2 | Human-verify: player plays a complete round; 4 success criteria confirmed | ✓ VERIFIED | User APPROVED plan 04-06 Task 2 checkpoint (2026-08-08). Tested 1znf 3-hider + 4wb3 10-hider rounds in real Windows PyMOL GUI |

**Score:** 27/27 truths verified (2 via documented, human-verified deviations that meet the goal)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `biochemeleon/generators.py` | pure sphere generator | ✓ VERIFIED | 33 lines; `def generate_sphere_positions`; `import random` (0 `from pymol`); exported |
| `tests/test_generators.py` | WSL unit tests (≥50 lines) | ✓ VERIFIED | 106 lines; 8 tests pass |
| `biochemeleon/wizard.py` | PickWizard click handler (≥50 lines) | ✓ VERIFIED | 83 lines; `class PickWizard`; do_pick + do_select + activate/deactivate + get_panel |
| `biochemeleon/game.py` | GameController.on_pick/win/set_callbacks/_remaining | ✓ VERIFIED | 137 lines; `def on_pick`; all Phase-4 methods present |
| `tests/test_game_controller.py` | WSL unit tests (≥60 lines) | ✓ VERIFIED | 217 lines; 8 tests pass (incl. deviation-updated test_win_with_wizard) |
| `biochemeleon/gui_game.py` | GameTab UI (≥110 lines) | ✓ VERIFIED | 141 lines; `class GameTab`; log+timer+remaining+countdown+begin_play+on_win |
| `biochemeleon/__init__.py` | PluginDialog._on_start (≥100 lines) | ✓ VERIFIED | 129 lines; `def _on_start`; full BTN-07 fan-in |
| `biochemeleon/gui_setup.py` | Start button | ✓ VERIFIED | `start_btn` in Setup actions group |
| `smoke/phase4_smoke.py` | headless smoke (≥70 lines) | ✓ VERIFIED | 148 lines; 19 executable checks; pure `pymol.cmd.*` |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| gui_setup.start_btn.clicked | __init__.PluginDialog._on_start | signal connect | ✓ WIRED | __init__.py:70 |
| __init__._on_start | generators.generate_sphere_positions | call | ✓ WIRED | __init__.py:79 import, :108 call |
| __init__._on_start | game.GameController.start | call (snapshot→insert→register) | ✓ WIRED | __init__.py:118-120 |
| __init__._on_start | cmd.show('spheres', '...segi GAME') | call | ✓ WIRED | __init__.py:126 |
| __init__._on_start | tabs.setCurrentWidget(game_tab) | call | ✓ WIRED | __init__.py:128 |
| __init__._on_start | game_tab.start_countdown | call | ✓ WIRED | __init__.py:129 |
| gui_game.start_countdown | QTimer.singleShot chain → _begin_play | call | ✓ WIRED | gui_game.py:69 (no time.sleep) |
| gui_game._begin_play | wizard.PickWizard + activate + set_callbacks + timer.start(1000) | call | ✓ WIRED | gui_game.py:75-89 |
| wizard.do_pick | cmd.identify('pk1', mode=1) → controller.on_pick(aid) | call | ✓ WIRED | wizard.py:45,53 (NEVER cmd.index) |
| wizard.do_select | build pk1 from sele → do_pick | call | ✓ WIRED | wizard.py:56-71 (deviation c68a1a4; canonical measurement-wizard pattern) |
| game.on_pick | registry.get / registry.mark_found / cmd.color / callbacks | call | ✓ WIRED | game.py:74,81,82,84-87 |
| game.on_pick (remaining==0) | win() → _on_win(elapsed) | call | ✓ WIRED | game.py:86-87,101-102 |
| gui_game._on_win | _timer.stop + cmd.refresh + _finish_win (deferred) | call | ✓ WIRED | gui_game.py:104-107 |
| gui_game._finish_win | wizard.deactivate + QMessageBox modal + controller.cleanup | call | ✓ WIRED | gui_game.py:124-141 |
| smoke/phase4_smoke.py | headless Windows PyMOL | cmd.exe runner | ✓ WIRED | pure pymol.cmd.*; 19 checks; SUMMARY 19/19 |

### Requirements Coverage

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| LOOP-01 (click-to-find via Wizard.do_pick → registered hider → mark found) | ✓ SATISFIED | wizard.do_pick/do_select → on_pick → registry.get → mark_found + cmd.color; non-hider no-op at both wizard (:50) and controller (:75) layers |
| LOOP-02 (found-status single source of truth) | ✓ SATISFIED | registry is the sole source; on_pick reads rec.status; _remaining reads registry; win reads _remaining |
| LOOP-03 (win: all found → stop timer + winning message with time) | ✓ SATISFIED | on_pick remaining==0 → win() → on_win → _on_win stops timer + _finish_win modal "You found all hiders in M:SS!" |
| HIDER-04 (sphere hiders placed anywhere in bounding region) | ✓ SATISFIED | generate_sphere_positions uniform in extent; smoke asserts within bounds; _on_show shows `segi GAME` spheres |
| BTN-07 (Start: backup, generate, switch tab, countdown 3-2-1) | ✓ SATISFIED | _on_start: start() backs up (snapshot) → generate → show → setCurrentWidget → start_countdown(3-2-1) |
| GAME-01 (rolling info box) | ✓ SATISFIED | QTextEdit _info_log, read-only, _log appends + auto-scrolls |
| GAME-02 (timer counts up, stops on win) | ✓ SATISFIED | QTimer 1Hz _on_tick M:SS; _on_win stops timer |
| GAME-03 (remaining hiders count — total) | ✓ SATISFIED | _remaining_label via on_remaining_changed; _remaining counts HIDER_STATUS_HIDDEN. ROADMAP Phase 4 scopes "(total)"; per-rep breakdown is later-phase (sphere is the only rep here, so total==per-rep) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| game.py | 1,12,13,28 | stale docstring references "placeholder insert" / `_placeholder_hiders` | ℹ️ Info | No such method exists; `start()` uses real `hider_specs` via `mutation.insert_hider`. Leftover Phase 3 docstring. Cosmetic; recommend cleanup in a future phase. No functional impact. |
| gui_setup.py | 93 | `setPlaceholderText("e.g. 1znf")` | ℹ️ Info | Legitimate Qt QLineEdit input-hint API (not a stub). False positive. |
| __init__.py | 42 | docstring "Phase 1 ships placeholder tabs only" | ℹ️ Info | Historical evolution docstring; tabs are now populated. Cosmetic. |
| mutation.py | 93 | comment mentions "stored.xxx pattern" | ℹ️ Info | Comment explaining the avoided anti-pattern. Not a stub. |

No blocker or warning anti-patterns. No empty returns, no console.log-only handlers, no TODO/FIXME in shipped code. All "placeholder" hits are docstring/comment staleness or legitimate Qt APIs.

### Human Verification Required

The single human-verification item — playing a complete round in the real
Windows PyMOL GUI — was **ALREADY APPROVED by the user** during plan 04-06
Task 2 (2026-08-08). The user confirmed all 4 ROADMAP success criteria in a
real PyMOL session with 1znf (3 hiders) and 4wb3 (10 hiders):

1. ✓ Start → 3-2-1 countdown (C1)
2. ✓ click → recolor green + non-hider miss no-op (C2)
3. ✓ log + timer + remaining (C3)
4. ✓ win → timer stop + modal message with time (C4)

Plus wizard activation + mouse_selection_mode restore, viewer stays responsive
after win, new game works. No outstanding human verification.

### Deviations (documented, human-verified — not gaps)

Three GUI bug-fix iterations during the human-verify checkpoint, all committed
(Rule 1 bug fixes, no architectural changes). The headless smoke could not
catch these (it exercises the on_pick logic path + calls do_pick directly; it
never routes a real selection-mode click or runs the win DISPLAY path through
the Qt event loop):

1. **do_select routing (c68a1a4)** — PickWizard.set `mouse_selection_mode=0`
   but never switched the BUTTON MODE from Selecting to Picking, so real GUI
   left-clicks (default 3-Button Viewing = `cButModeSeleSet`) created `"sele"`
   + `WizardDoSelect`, not `"pk1"` + `WizardDoPick` → `do_pick` never fired.
   Fix: `do_select(name)` builds pk1 from sele, cleans up, dispatches do_pick
   (canonical measurement-wizard pattern). Verified: do_select spike in smoke
   (9c9aeea, 19/19) + human-verify.
2. **win-loop three bugs (9ec0c16)** — (1) `_begin_play` set `_start_time` on
   GameTab but `win()` reads GameController's `_start_time` (init None) → win
   time always 0:00. (2) `win()` called `_on_win` (modal blocks Qt) BEFORE
   deactivating wizard → last `cmd.color('green')` never flushed → last hider
   stayed gray. (3) No `cleanup()` after win → hiders remained, viewer frozen,
   new game broken. Fix: `_begin_play` also sets `controller._start_time`;
   `win()` reordered; `_on_win` calls `cleanup()` after modal; `_on_start`
   defensively cleans up prior controller.
3. **win-display three bugs (01c48f6)** — (A) wizard deactivation clobbered
   the pending green redraw. (B) `QMessageBox.information(self,...)` parented
   to GameTab (not top-level) → dialog hidden behind PyMOL window. (C) Viewer
   frozen (consequence of B). Fix: deactivation removed from `win()`, deferred
   to `_finish_win` via 100ms `QTimer.singleShot` (lets PyMOL render green
   first); `QMessageBox` instance with `self.window()` parent +
   `WindowStaysOnTopHint`; test_win_with_wizard updated. Human-verify APPROVED.

These deviations mean two plan truths (04-03.6 "win() deactivates _wizard" and
04-04.6 "QMessageBox.information") are implemented via a different mechanism
than the plan literally specified, but the **goal** behind each truth is met
(wizard deactivated + win shown, stays on top, viewer responsive) and was
confirmed by human-verify. WSL gates stayed green throughout (160 unit tests +
pitfall-1=0; exec_ gate=1 on the allowed QMessageBox child dialog).

### Gaps Summary

No gaps. All 27 must-have truths verified, all 9 artifacts exist + substantive
+ wired, all 14 key links wired, all 8 requirements satisfied, all 4 ROADMAP
success criteria met (3 automated + 1 human-verified APPROVED). The three
deviations are documented bug fixes that strengthened (not weakened) the
delivery, all human-verified. The only follow-up items are cosmetic docstring
cleanups (ℹ️ Info) that do not affect goal achievement.

---

_Verified: 2026-08-08T15:00:00Z_
_Verifier: OpenCode (gsd-verifier)_
