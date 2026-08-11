---
phase: 07-found-hider-management-restart-cleanup
verified: 2026-08-12T03:10:00Z
status: passed
score: 8/8 must-haves verified
re_verification: No — initial verification
human_verification_already_done:
  checkpoint: "07-03 Task 2 (checkpoint:human-verify) — APPROVED"
  user_signal: "approved, all passed. good job!"
  session: "real Windows PyMOL GUI (1znf) — all 4 success criteria confirmed"
  criteria_confirmed:
    - "C1 (GAME-08): Found-hider dropdown Hide/Show/Recolor + resets to placeholder"
    - "C2 (DIFF-04): QColorDialog picks new color + auto-recolors existing + new finds use new color + Cancel = no change"
    - "C3 (GAME-10): Restart restores + regenerates + fresh countdown/timer/log + left-drag rotates (wizard lifecycle OK)"
    - "C4 (BTN-06): Cleanup restores atom count + no GAME atoms + wizard deactivated + UI reset + Start works after + no-op when no game"
---

# Phase 7: Found-Hider Management, Restart & Cleanup Verification Report

**Phase Goal:** The player can manage how found hiders are displayed, restart for a fresh round, and clean the model back to its original state.
**Verified:** 2026-08-12T03:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Player can hide all found hiders via the dropdown | ✓ VERIFIED | `gui_game.py:45` QComboBox + `gui_game.py:141-142` `_on_found_mgmt('hide')` → `cmd.hide("everything", sele)` + `gui_game.py:134-135` HIDER_STATUS_FOUND filter + smoke §3 PASS + human C1 |
| 2 | Player can show all found hiders via the dropdown in their original reps | ✓ VERIFIED | `gui_game.py:143-148` `_on_found_mgmt('show')` → `group_found_by_rep` + per-rep `cmd.show(rep, ...)` + smoke §3 PASS ("found hider visible again") + human C1 |
| 3 | Player can recolor all found hiders via the dropdown using a player-chosen color | ✓ VERIFIED | `gui_game.py:149-150` `_on_found_mgmt('recolor')` → `cmd.color(self._controller._found_color, sele)` + smoke §4 PASS (color index [3]→[5388]) + human C1 |
| 4 | Player can pick a highlight color via a color picker | ✓ VERIFIED | `gui_game.py:173` `QColorDialog.getColor()` + `gui_game.py:178` `cmd.set_color('found_highlight', [r,g,b])` + human C2 (Qt-only path) |
| 5 | New finds use the player-chosen color, not hardcoded green | ✓ VERIFIED | `game.py:40` `_found_color='green'` default + `game.py:117` `cmd.color(self._found_color, ...)` (NOT hardcoded) + `gui_game.py:179` `_found_color` assign + unit test `test_found_color_threading` (asserts `cmd.color('cyan', ...)`) + smoke §5 PASS (cyan index [5387]→[5]) + human C2 |
| 6 | Player can press Restart for a fresh round (object restored, new hiders, fresh timer/log) | ✓ VERIFIED | `gui_game.py:54` `_restart_btn` + `__init__.py:246-263` `_on_restart` (deactivate wizard + stop timer + `_on_start`) + `gui_game.py:194` `start_countdown` clears log + `gui_game.py:222` `_begin_play` defensive `_timer.stop()` + smoke §6 PASS (start→cleanup→start→cleanup round-trip) + human C3 |
| 7 | Player can press Cleanup to restore the original object (no hiders, original atom count) | ✓ VERIFIED | `gui_setup.py:193` `cleanup_btn` + `__init__.py:265-286` `_on_cleanup` → `controller.cleanup()` (line 281) restores from backup + smoke §7 PASS ("count back to orig", "no GAME atoms remain", "idempotent") + human C4 |
| 8 | After Cleanup, the game state is fully reset (no dangling wizard, no running timer) | ✓ VERIFIED | `__init__.py:276-279` deactivate wizard + `__init__.py:280` `_timer.stop()` + `__init__.py:282` `_info_log.clear()` + `__init__.py:283-285` reset labels + `__init__.py:286` `_controller = None` + human C4 (left-drag rotates = no dangling wizard) |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `biochemeleon/registry.py` | `def build_found_selection` + `def group_found_by_rep` (pure, no `from pymol`) | ✓ VERIFIED | `build_found_selection` at line 277; `group_found_by_rep` at line 299; pure (only `from .setup_state import GAME_REPS` at line 30 — 0 `from pymol` matches); 313 lines (substantive); module-level functions after HiderRegistry class |
| `biochemeleon/game.py` | `_found_color` in `__init__` AND used in `_mark_found` | ✓ VERIFIED | `self._found_color = 'green'` at line 40 (init); `cmd.color(self._found_color, ...)` at line 117 (_mark_found — NOT hardcoded 'green'); 277 lines (substantive) |
| `biochemeleon/gui_game.py` | QComboBox, QColorDialog, `_on_found_mgmt`, `build_found_selection` usage, `group_found_by_rep` usage, `_found_color` usage, `_info_log.clear`, `_timer.stop`, `_restart_btn` | ✓ VERIFIED | QComboBox line 45; QColorDialog line 173; `_on_found_mgmt` line 123; `build_found_selection` line 138; `group_found_by_rep` line 144; `_found_color` lines 150+179; `_info_log.clear()` line 194; `_timer.stop()` line 222; `_restart_btn` line 54; 275 lines (substantive) |
| `biochemeleon/gui_setup.py` | `cleanup_btn` | ✓ VERIFIED | `cleanup_btn` created line 193 ("Cleanup model"); tooltip lines 194-196; added to button row line 200 (between load_btn and start_btn); NOT wired here (wired in __init__.py per pattern); 588 lines (substantive) |
| `biochemeleon/__init__.py` | `_on_restart`, `_on_cleanup`, `deactivate`, `_controller = None`, `cleanup_btn.clicked.connect`, `_restart_btn.clicked.connect` | ✓ VERIFIED | `_on_restart` line 246; `_on_cleanup` line 265; `deactivate` calls lines 229+258+277 (wizard-lifecycle fix in _on_start + _on_restart + _on_cleanup); `_controller = None` lines 67+286; `cleanup_btn.clicked.connect` line 72; `_restart_btn.clicked.connect` line 73; 286 lines (substantive) |
| `smoke/phase7_smoke.py` | exists, contains `phase7`, `GameController`, `build_found_selection` | ✓ VERIFIED | Exists (9798 bytes); `phase7` in line 1 header; `GameController` used lines 45+104+135+158; `build_found_selection` imported line 27 + used line 62; 181 lines; 38 `check()` calls; SUMMARY block + `sys.exit(1)` on fail |
| `tests/test_registry.py` | `build_found_selection` tests | ✓ VERIFIED | `TestFoundSelectionHelpers` class line 579; 5 `build_found_selection` tests (empty/no_found/one_found/three_found/mixed) + 6 `group_found_by_rep` tests (empty/no_found/one_found/mixed_reps/rep_none_skipped/mixed_rep_and_none) = 11 tests; imports at line 29 |
| `tests/test_game_controller.py` | `_found_color` tests | ✓ VERIFIED | `test_found_color_default_green` line 486 (asserts `_found_color == 'green'`); `test_found_color_threading` line 494 (registers hider, sets `_found_color='cyan'`, calls `_mark_found(100)`, asserts `cmd.color.assert_called_once_with('cyan', "1ubq and id 100")` at line 509 — substantive threading proof) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `gui_game.py _on_found_mgmt` | `HIDER_STATUS_FOUND` filter | list comprehension over `controller.registry.all()` | ✓ WIRED | `gui_game.py:134-135` `found = [r for r in self._controller.registry.all() if r.status == HIDER_STATUS_FOUND]` — filters by status (NOT color); smoke §3 confirms 1 found + 2 hidden correctly separated |
| `gui_game.py _on_pick_color` | `controller._found_color` | `QColorDialog.getColor` → `cmd.set_color` → `controller._found_color = 'found_highlight'` | ✓ WIRED | `gui_game.py:178-180` `cmd.set_color('found_highlight', [r,g,b])` + `self._controller._found_color = 'found_highlight'` + `self._on_found_mgmt('recolor')` (auto-recolor existing); smoke §5 confirms threading (cyan index 5, NOT green) |
| `__init__.py _on_restart` | deactivate wizard then `_on_start` | `deactivate()` + `_timer.stop()` + `_on_start()` | ✓ WIRED | `__init__.py:257-263`: deactivate wizard (lines 258-261) + `_timer.stop()` (line 262) + `_on_start()` (line 263); `_on_start` also deactivates wizard (belt-and-suspenders, lines 228-232) + `start_countdown` clears log; smoke §6 confirms round-trip; human C3 confirms wizard lifecycle |
| `__init__.py _on_cleanup` | `controller.cleanup()` then `_controller = None` | deactivate wizard + stop timer + cleanup + UI reset + release | ✓ WIRED | `__init__.py:276-286`: deactivate wizard (276-279) + `_timer.stop()` (280) + `controller.cleanup()` (281) + UI reset (282-285) + `_controller = None` (286); smoke §7 confirms cleanup restores count + no GAME atoms + idempotent; human C4 confirms |
| `gui_setup.py cleanup_btn.clicked` | `__init__.py _on_cleanup` | `clicked.connect(self._on_cleanup)` | ✓ WIRED | `__init__.py:72` `self.setup_tab.cleanup_btn.clicked.connect(self._on_cleanup)` — button created in gui_setup.py:193, wired in composition root (__init__.py) per the established start_btn pattern |

### Requirements Coverage

| Requirement | ID | Status | Evidence |
|-------------|----|----|----------|
| Found-hider management dropdown — hide/show/change color of hiders with a "found" status | GAME-08 | ✓ SATISFIED | QComboBox (`gui_game.py:45`) with 3 modes + `_on_found_mgmt` (line 123) filtering by `HIDER_STATUS_FOUND` (line 134-135) + `build_found_selection` + `group_found_by_rep`; smoke §3+§4 PASS; human C1 APPROVED |
| Restart button — restart the game from the stored initial state | GAME-10 | ✓ SATISFIED | `_restart_btn` (`gui_game.py:54`) + `_on_restart` (`__init__.py:246`) deactivates wizard + stops timer + calls `_on_start` (fresh round from Setup tab state); smoke §6 PASS; human C3 APPROVED (wizard lifecycle confirmed) |
| Cleanup model — remove all game-generated representations/atoms (via `segi='GAME'` sentinel only) | BTN-06 | ✓ SATISFIED | `cleanup_btn` (`gui_setup.py:193`) + `_on_cleanup` (`__init__.py:265`) → `controller.cleanup()` (`game.py:231`) restores from backup (created pre-mutation, so restore removes ALL game-generated atoms + restores original); smoke §7 PASS ("count back to orig", "no GAME atoms remain", "idempotent"); human C4 APPROVED. Note: cleanup uses backup.restore (Phase 6 deviation — hint colors real atoms, so backup.restore is needed instead of sentinel-remove alone); the backup contains the pre-game state so restore removes every game-generated atom and leaves the original exactly as it was (count matches pre-Start). |
| Color picker for found-hider highlight (accessibility / color-blind support) | DIFF-04 | ✓ SATISFIED | `QColorDialog` (`gui_game.py:173`) + `_on_pick_color` (line 161) sets `cmd.set_color('found_highlight')` + assigns `controller._found_color` (line 179) + auto-recolors existing (line 180); `_mark_found` reads `self._found_color` (`game.py:117`) so new finds use the player-chosen color; unit test `test_found_color_threading` PASS; smoke §5 PASS (cyan, NOT green); human C2 APPROVED |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | No blocker/warning anti-patterns in Phase 7 code. All "placeholder" grep matches are benign: historical Phase-3 docstrings (`game.py:1,17,18`), the intentional QComboBox index-0 placeholder ITEM description (`gui_game.py:65,154`), and Qt `setPlaceholderText` API (`gui_setup.py:93`). No empty returns in Phase 7 handlers (`_on_found_mgmt`/`_on_pick_color`/`_on_restart`/`_on_cleanup` all have real implementations). No TODO/FIXME/HACK. |

### WSL Gate Results

| Gate | Expected | Result |
|------|----------|--------|
| `python3.6 -m py_compile biochemeleon/*.py` | OK | ✓ PY_COMPILE_OK |
| `python3.6 -m unittest tests.test_setup_state tests.test_registry tests.test_game_controller tests.test_generators` | 200 tests pass | ✓ Ran 200 tests, OK (matches SUMMARY claim) |
| Pitfall-1 gate (Tkinter/Pmw/PyQt5/etc.) | 0 matches | ✓ 0 |
| exec_ gate | 1 (only `gui_game.py:271 msg.exec_()`) | ✓ 1 — confirmed only the existing `_finish_win` modal message; NO new `.exec_()` from QColorDialog (uses `getColor()` static method) |
| registry.py purity (`from pymol`) | 0 | ✓ 0 (registry.py stays pure — only `from .setup_state import GAME_REPS`) |

### Headless Smoke (Independent Runtime Confirmation)

Re-ran `smoke/phase7_smoke.py` headlessly via `cmd.exe /c C:\src\run-conda-pymol.bat -cq` from staged `tmp/bioCHEMeleon/` path for independent confirmation of the SUMMARY's cmd-path claims (verifier role: "do NOT trust SUMMARY claims").

**Result: 38/38 ALL PASSED, exit 0** — matches the 07-03-SUMMARY claim exactly.

Key runtime confirmations (independent of the SUMMARY):
- `recolor: post-color changed from pre` — color index changed [3]→[5388] (`found_highlight` differs from green) ✓
- `threading: post-color changed from pre (cyan, not green)` — color index changed [5387]→[5] (cyan, NOT default green) ✓ — runtime confirmation of the Plan 01 TDD change that was unit-tested with mocked cmd
- `restart: count back to orig after gc2 cleanup` + `no GAME atoms after gc2 cleanup` ✓
- `cleanup: count back to orig` + `no GAME atoms remain` + `idempotent (returns True when not started)` ✓ — confirms the `_on_cleanup` `if self._controller is None: return` guard at the cmd layer

### Human Verification Required

**No additional human verification needed.** The Phase 7 human-verify checkpoint (07-03 Task 2) was already APPROVED by the user ("approved, all passed. good job!") in a real Windows PyMOL GUI session (1znf). All 4 success criteria + the wizard-lifecycle fix were confirmed:

- **C1 (GAME-08):** Found-hider dropdown Hide/Show/Recolor works; dropdown resets to "(select)" placeholder after each action (re-selectable)
- **C2 (DIFF-04):** Color… button opens QColorDialog; pick non-default color → existing found hiders auto-recolor immediately; find a NEW hider → uses the NEW color (NOT green — `_found_color` threading works for future finds); Cancel → no color change
- **C3 (GAME-10):** Restart restores object (old hiders gone), regenerates new hiders, fresh 3-2-1 countdown, timer resets to 0:00, info log cleared; **CRITICAL wizard lifecycle:** left-drag ROTATES after Restart (mouse NOT stuck in atomic-pick mode) and hider clicks SUCCEED
- **C4 (BTN-06):** Cleanup restores atom count (matches pre-Start, no GAME atoms), wizard deactivated (left-drag rotates — mouse mode restored), UI reset (Remaining: -, Reveals: 0, 0:00), Start works after Cleanup (controller released via `_controller = None`), Cleanup with no game running is a no-op

The Qt/GUI paths (QColorDialog modal, QComboBox dropdown UI, button clicks, PickWizard activate/deactivate + mouse_selection_mode, timer reset, log clearing, tab switching) are headless-unreachable but were covered by the approved checkpoint. The headless smoke (re-run above: 38/38) covered the cmd-layer paths independently.

### Gaps Summary

**No gaps found.** All 8 must-have truths are verified at all 3 levels (artifacts exist + substantive + wired). All 5 key links are wired correctly. All 4 requirements (GAME-08, GAME-10, BTN-06, DIFF-04) are satisfied. All WSL gates are green. The headless smoke independently confirms the cmd-path claims (38/38 ALL PASSED). The human-verify checkpoint was already APPROVED covering the Qt/GUI paths. No blocker or warning anti-patterns.

Phase 7 goal — "The player can manage how found hiders are displayed, restart for a fresh round, and clean the model back to its original state" — is **achieved**.

---

_Verified: 2026-08-12T03:10:00Z_
_Verifier: OpenCode (gsd-verifier)_
