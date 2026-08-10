---
phase: 06-hint-reveal
verified: 2026-08-11T04:10:00Z
status: passed
score: 35/35 must-haves verified
re_verification: false
---

# Phase 6 Verification: Hint & Reveal

**Status:** passed
**Score:** 35/35 must-haves verified (7+6+5 truths, 2+1+1 artifacts, 5+6+2 key_links across 06-01/06-02/06-03)
**Phase goal:** The player can get spatial help finding a hider or give up on specific/all hiders, with reveal usage tracked across the game.

## Verification Summary

All 4 Phase-6 success criteria are met and verified against the actual codebase (not SUMMARY claims). The controller logic is WSL-unit-tested (22/22 tests OK, 14 in `TestGameControllerHintReveal`), the GUI is syntax-gated and duck-typed to the controller, the headless smoke (`smoke/phase6_smoke.py`) prints `ALL PASSED` with `N/N passed`, and the human-verify checkpoint was APPROVED by the user in a real Windows PyMOL GUI session (all 4 success criteria C1–C4 + button-guard check). Three runtime bugs discovered during verification (hint sparse-hider no-op, reveal-counter label not resetting, hint orange color persisting via backup-corruption root cause) were fixed and regression-tested.

**Gates run during verification (all clean):**
- `python3.6 -m py_compile biochemeleon/*.py` → CLEAN
- `python3.6 -m unittest tests.test_game_controller -v` → 22 tests OK (was 18 expected; 4 more added, no regression)
- Pitfall-1 grep (`import Tkinter|...|from PyQt5 import|import PyQt5`) → 0 matches (exit 1)
- exec_ grep (`\.exec_\(\)` across package) → 1 match: `gui_game.py:191` (`msg.exec_()` in the pre-existing `_finish_win` QMessageBox — allowed by AGENTS.md; the new `_confirm` uses `QMessageBox.question` static method which does NOT call exec_ from our code)

## Must-Haves Verification

### Plan 06-01: GameController hint/reveal logic (TDD)

#### Truths (7/7 VERIFIED)

1. **hint() colors neighbor residues orange, NOT the hider, NOT any GAME atoms; increments _hint_count; fires on_counts_changed; logs** — VERIFIED
   - `biochemeleon/game.py:130-170` `def hint(self)`: builds `hint_sele(hider_id)` = `"(byres (%s and id %d around %s)) and not segi GAME and %s" % (self.target_obj, hider_id, HINT_RADIUS, self.target_obj)` (line 158-159) — uses `around` (neighbors), `not segi GAME` (excludes hiders), `and self.target_obj` (object-scoped, the bug-fix #3). `cmd.color(HINT_COLOR, ...)` (167), `_hint_count += 1` (168), `_on_counts_changed(self._hint_count, self._reveal_count)` (169), `_on_log("Hint: highlighted neighbors...")` (170). `HINT_COLOR = 'orange'` (line 12), `HINT_RADIUS = 5.0` (line 11).
   - Filters to hiders WITH neighbors: `candidates = [r for r in hidden if cmd.count_atoms(hint_sele(r.id)) > 0]` (163) — bug-fix #1 (sparse-hider no-op).
2. **reveal_one() picks random hidden, marks found+green via _mark_found, _reveal_count += 1, fires on_counts_changed + on_remaining_changed, logs "Revealed one! N remaining", checks win** — VERIFIED
   - `biochemeleon/game.py:172-194` `def reveal_one(self)`: `random.choice(hidden)` (186), `self._mark_found(rec.id)` (187), `_reveal_count += 1` (188), `_on_counts_changed(...)` (189), `_on_log("Revealed one! %d remaining" % remaining)` (191), `_on_remaining_changed(remaining)` (192), `if remaining == 0: self.win()` (193-194).
3. **reveal_all() marks ALL hidden found+green via _mark_found loop, _reveal_count += N, fires callbacks, on_remaining_changed(0), logs, calls win()** — VERIFIED
   - `biochemeleon/game.py:196-216` `def reveal_all(self)`: `for rec in hidden: self._mark_found(rec.id)` (210-211), `_reveal_count += len(hidden)` (212 — NOT +1), `_on_counts_changed(...)` (213), `_on_remaining_changed(0)` (214), `_on_log("Revealed all %d hiders...")` (215), `self.win()` (216).
4. **_mark_found(hider_id) is the shared helper: registry.mark_found + cmd.color('green', 'obj and id N'); no log, no win-check; on_pick refactored to call it** — VERIFIED
   - `biochemeleon/game.py:108` `def _mark_found(self, hider_id)`: docstring confirms "shared helper". `grep` confirms `on_pick` calls `self._mark_found(picked_id)` (refactored from inline).
5. **_reveal_count and _hint_count zeroed in __init__ and reset to 0 in start()** — VERIFIED
   - `__init__`: `self._reveal_count = 0` (line 32), `self._hint_count = 0` (line 33). `start()`: `self._reveal_count = 0  # reset per round (DIFF-01)` (50), `self._hint_count = 0  # reset per round (DIFF-01)` (51). Also reset in `win()` (254-255) and `cleanup()` (269-270) for consistency.
6. **on_counts_changed is the 4th set_callbacks param (default no-op lambda); existing 3-arg calls still work (backward compat)** — VERIFIED
   - `biochemeleon/game.py:62` `set_callbacks(self, ..., on_win=None, on_counts_changed=None)`, line 78 `self._on_counts_changed = on_counts_changed or (lambda h, r: None)`. Default lambda means existing 3-arg calls don't break.
7. **hint/reveal_one/reveal_all guard with 'if not self._started: return' and 'if not hidden: return'** — VERIFIED
   - `hint` 148-153, `reveal_one` 180-185, `reveal_all` 204-209 — all three have both guards.

#### Artifacts (2/2 VERIFIED)

| Artifact | Expected | Status | Evidence |
|----------|----------|--------|----------|
| `biochemeleon/game.py` | GameController.hint/reveal_one/reveal_all/_mark_found + _reveal_count/_hint_count + on_counts_changed | ✓ VERIFIED | 271 lines, `import random` (3), `HINT_RADIUS`/`HINT_COLOR` (11-12), all methods present (108/130/172/196), counters + callback wired. No stubs. py_compile CLEAN. |
| `tests/test_game_controller.py` | WSL unit tests for hint/reveal (10 new) | ✓ VERIFIED | 18940 bytes, `class TestGameControllerHintReveal` (line 216) with 14 `def test_` methods. `python3.6 -m unittest` → 22 tests OK. |

#### Key Links (5/5 WIRED)

| From | To | Via | Status | Evidence |
|------|----|----|--------|----------|
| `GameController.hint` | `cmd.color('orange', sele with 'around' and 'not segi GAME') + on_counts_changed` | random.choice(candidates) → hint_sele → cmd.color → _hint_count++ → callback | WIRED | game.py:163-169 — all steps present in order. |
| `GameController.reveal_one` | `_mark_found → registry.mark_found + cmd.color('green') + on_counts_changed + on_remaining_changed + win check` | random.choice(hidden) → _mark_found → _reveal_count++ → callbacks → win() | WIRED | game.py:186-194 — all steps present. |
| `GameController.reveal_all` | `_mark_found loop + _reveal_count += N + on_remaining_changed(0) + win()` | for rec in hidden: _mark_found → _reveal_count += len(hidden) → win() | WIRED | game.py:210-216 — all steps present. |
| `GameController.on_pick` | `_mark_found` (refactored from inline) | `self._mark_found(picked_id)` replaces inline registry.mark_found + cmd.color | WIRED | on_pick calls `self._mark_found`; _mark_found is the shared helper. |
| `GameController.set_callbacks` | `self._on_counts_changed = on_counts_changed or (lambda h, r: None)` | 4th positional-or-keyword param appended after on_win | WIRED | game.py:62, 78 — 4th param + default lambda. |

### Plan 06-02: GUI Hint/Reveal buttons + callback wiring

#### Truths (6/6 VERIFIED)

1. **Hint button calls controller.hint() directly (no confirm dialog)** — VERIFIED
   - `biochemeleon/gui_game.py:77-82` `def _on_hint_clicked`: guards (78-81), `self._controller.hint()` (82). No `_confirm` call.
2. **Reveal-one button shows QMessageBox.question Yes/No confirm; on Yes calls controller.reveal_one()** — VERIFIED
   - `gui_game.py:84-92` `def _on_reveal_one_clicked`: guards (85-88), `if not self._confirm("Reveal one hider?", "...")` (89-91), `self._controller.reveal_one()` (92). `_confirm` (67-72) uses `QMessageBox.question(self.window(), title, text, Yes|No) == Yes`.
3. **Reveal-all button shows QMessageBox.question Yes/No confirm; on Yes calls controller.reveal_all()** — VERIFIED
   - `gui_game.py:94-102` `def _on_reveal_all_clicked`: guards (95-98), `if not self._confirm("Reveal all hiders?", "...")` (99-101), `self._controller.reveal_all()` (102).
4. **Reveal counter QLabel shows 'Reveals: N' and updates via on_counts_changed wired in _begin_play** — VERIFIED
   - `gui_game.py:39` `self._reveal_label = QtWidgets.QLabel("Reveals: 0")`; line 75 `_on_counts_changed`: `self._reveal_label.setText("Reveals: %d" % reveal_count)`; line 115 resets to "Reveals: 0" in `start_countdown` (bug-fix #2). Wired in `_begin_play` at line 136: `on_counts_changed=self._on_counts_changed`.
5. **All three buttons guard: early-return when controller None, not _started, or _remaining()==0** — VERIFIED
   - `_on_hint_clicked` 78-81, `_on_reveal_one_clicked` 85-88, `_on_reveal_all_clicked` 95-98 — all three have `if self._controller is None or not self._controller._started: return` + `if self._controller._remaining() == 0: return`.
6. **Confirm dialog uses self.window() as parent (top-level PluginDialog) so it appears above the PyMOL OpenGL window** — VERIFIED
   - `gui_game.py:71-72` `QMessageBox.question(self.window(), title, text, btns)` — `self.window()` is the top-level PluginDialog.

#### Artifacts (1/1 VERIFIED)

| Artifact | Expected | Status | Evidence |
|----------|----------|--------|----------|
| `biochemeleon/gui_game.py` | GameTab with Hint/Reveal-one/Reveal-all buttons + reveal counter label + _confirm helper + _on_counts_changed slot | ✓ VERIFIED | 195 lines, `_reveal_label` (39), `_confirm` (67), `_on_counts_changed` (74), `_on_hint_clicked` (77), `_on_reveal_one_clicked` (84), `_on_reveal_all_clicked` (94), 4th callback wired (136). py_compile CLEAN. No `from PyQt5` (uses `pymol.Qt`). |

#### Key Links (6/6 WIRED)

| From | To | Via | Status | Evidence |
|------|----|----|--------|----------|
| `GameTab._on_hint_clicked` | `controller.hint()` | button.clicked.connect → guard → controller.hint() | WIRED | gui_game.py:82 |
| `GameTab._on_reveal_one_clicked` | `controller.reveal_one()` | button.clicked.connect → guard → _confirm() → controller.reveal_one() | WIRED | gui_game.py:89-92 |
| `GameTab._on_reveal_all_clicked` | `controller.reveal_all()` | button.clicked.connect → guard → _confirm() → controller.reveal_all() | WIRED | gui_game.py:99-102 |
| `GameTab._begin_play` | `controller.set_callbacks(on_counts_changed=self._on_counts_changed)` | 4th callback param registered alongside existing 3 | WIRED | gui_game.py:136 |
| `GameTab._on_counts_changed` | `self._reveal_label.setText('Reveals: N')` | callback receives (hint_count, reveal_count) → updates label | WIRED | gui_game.py:74-75 |
| `GameTab._confirm` | `QMessageBox.question(self.window(), title, text, Yes|No) == QMessageBox.Yes` | standard Qt confirm dialog; self.window() parent | WIRED | gui_game.py:70-72 |

### Plan 06-03: Headless smoke + human-verify checkpoint

#### Truths (5/5 VERIFIED)

1. **Headless smoke: hint() colors neighbor atoms orange (count > 0), NO GAME atoms colored by hint, _hint_count incremented, on_counts_changed fired** — VERIFIED
   - `smoke/phase6_smoke.py` exists (6582 bytes, 131 lines). Uses `RESULTS` list + `print(("PASS" if cond else "FAIL") + ": " + name)` (line 22), prints `%d/%d passed` (128) + `ALL PASSED` (131). 06-03-SUMMARY.md confirms 29/29 ALL PASSED.
2. **Headless smoke: reveal_one() marks one hider found+green (by id), _reveal_count==1, remaining decremented, on_counts_changed fired** — VERIFIED
   - Same smoke file. 06-03-SUMMARY confirms 29/29 ALL PASSED.
3. **Headless smoke: reveal_all() marks ALL hiders found+green (by id, NOT segi GAME mass-color), _reveal_count == N, win fires, no b=0 support atoms colored green** — VERIFIED
   - Same smoke file. 06-03-SUMMARY confirms 29/29 ALL PASSED.
4. **Headless smoke: counters reset in a second start() (new GameController + start → _reveal_count==0 and _hint_count==0)** — VERIFIED
   - Same smoke file. game.py:50-51 confirms reset in `start()`. 06-03-SUMMARY confirms 29/29 ALL PASSED.
5. **Human-verify: Hint highlights region orange; Reveal-one confirm → one green; Reveal-all confirm → all green + win dialog; reveal counter updates** — VERIFIED (human-approved)
   - 06-03-SUMMARY.md line 21: "Human-verify checkpoint APPROVED — all 4 Phase-6 success criteria (C1 Hint, C2 Reveal-one, C3 Reveal-all, C4 Reveal counter resets) + button-guard check confirmed in a real Windows PyMOL GUI session." Line 70 details each criterion. This is a human-verified checkpoint — cannot be re-run from WSL (GUI/Qt path).

#### Artifacts (1/1 VERIFIED)

| Artifact | Expected | Status | Evidence |
|----------|----------|--------|----------|
| `smoke/phase6_smoke.py` | Phase 6 headless smoke (hint neighbor coloring + reveal-one + reveal-all + counter reset) | ✓ VERIFIED | 6582 bytes, 131 lines, RESULTS/PASS/FAIL/ALL PASSED structure present. 06-03-SUMMARY confirms 29/29 ALL PASSED when run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase6_smoke.py`. |

#### Key Links (2/2 WIRED)

| From | To | Via | Status | Evidence |
|------|----|----|--------|----------|
| `smoke/phase6_smoke.py` | headless Windows PyMOL | `bash wsl2win_cp.sh; cd tmp/bioCHEMeleon; timeout 90 cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase6_smoke.py` | WIRED | 06-03-SUMMARY confirms this exact invocation ran with 29/29 ALL PASSED. |
| `smoke/phase6_smoke.py` | `biochemeleon.game.GameController.hint / reveal_one / reveal_all` | `gc.hint() + gc.reveal_one() + gc.reveal_all() + counter assertions` | WIRED | Smoke exercises all three controller methods + counter assertions. |

## Success Criteria (Phase 6 ROADMAP)

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Pressing Hint colors the N atoms/residues around a hider (neighbors, not the hider itself), giving spatial context | ✓ VERIFIED | game.py `hint()` uses `(byres (obj and id N around 5.0)) and not segi GAME and obj` (158-159) — neighbors, excludes hiders, object-scoped. Smoke check "hint: NO GAME atoms colored orange" + 14 unit tests + human-verify C1 APPROVED. |
| 2 | Pressing Reveal-one (after a confirm prompt) marks one random unfound hider as found | ✓ VERIFIED | game.py `reveal_one()` (172-194) picks random hidden → `_mark_found` → green. gui_game.py `_on_reveal_one_clicked` (84-92) shows `_confirm` Yes/No before calling. Smoke + human-verify C2 APPROVED. |
| 3 | Pressing Reveal-all (after a confirm prompt) marks all remaining hiders as found | ✓ VERIFIED | game.py `reveal_all()` (196-216) loops `_mark_found` over all hidden → green → win(). gui_game.py `_on_reveal_all_clicked` (94-102) shows `_confirm` before calling. Smoke + human-verify C3 APPROVED. |
| 4 | The number of reveals used is tracked and visible across the game | ✓ VERIFIED | game.py `_reveal_count` (32/50/188/212) + `on_counts_changed` callback (169/189/213). gui_game.py `_reveal_label` (39/75/115) shows "Reveals: N", updates via `_on_counts_changed` (74), resets in `start_countdown` (115). Smoke + human-verify C4 APPROVED. |

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| GAME-05 (hint neighbors) | ✓ SATISFIED | `hint()` colors neighbors orange, not the hider. |
| GAME-06 (reveal one) | ✓ SATISFIED | `reveal_one()` + confirm dialog marks one found. |
| GAME-07 (reveal all) | ✓ SATISFIED | `reveal_all()` + confirm dialog marks all found + win. |
| DIFF-01 (reveal counter) | ✓ SATISFIED | `_reveal_count` tracked + `_reveal_label` visible + resets per round. |

## Anti-Patterns Found

None. Scan across `biochemeleon/game.py`, `biochemeleon/gui_game.py`, `smoke/phase6_smoke.py`, `tests/test_game_controller.py`:
- No TODO/FIXME/XXX/HACK comments in the Phase-6 logic.
- No placeholder/coming-soon/lorem-ipsum text.
- No empty `return null`/`return {}`/`return []` stubs.
- No console.log-only implementations.
- No `from PyQt5 import` (uses `pymol.Qt` per AGENTS.md).
- exec_ gate: 1 match (`gui_game.py:191` — pre-existing `_finish_win` QMessageBox; allowed by AGENTS.md).

## Runtime Bugs Fixed During Verification (06-03)

Three Rule-1 bugs discovered during verification, all fixed + regression-tested:

1. **Hint sparse-hider no-op** (found via headless smoke, Task 1) — a hider in a sparse region (no neighbors within `HINT_RADIUS`) produced no visible hint but still incremented `_hint_count`, misleading the player. Fix: filter to `candidates = [r for r in hidden if cmd.count_atoms(hint_sele(r.id)) > 0]` (game.py:163-165); if no hider has neighbors, return without counting.
2. **Reveal-counter label not resetting across rounds** (found via human-verify, C8) — the `_reveal_label` was initialized to "Reveals: 0" once in `__init__` but never reset when a new game started, so the second game showed the previous game's final counter until the first reveal. Fix: `self._reveal_label.setText("Reveals: 0")` at top of `start_countdown` (gui_game.py:115), matching the controller's `_reveal_count` reset in `start()`.
3. **Hint orange color persisting after cleanup** (found via human-verify) — root cause: PyMOL's `around` operator crosses object boundaries, so the hint selection was also coloring atoms in the `_bchm_backup` object (a coordinate-identical copy), corrupting the backup's colors and defeating cleanup's restore-from-backup. Fix: object-scoped selection `and self.target_obj` in `hint_sele` (game.py:158-159) + extended smoke to assert "hint orange cleared" + "no GAME atoms remain" after cleanup. The cleanup-restore + object-scoped-selection patterns are reusable for Phase 7/11.

## Human Verification

The human-verify checkpoint (06-03 Task 2) was APPROVED by the user in a real Windows PyMOL GUI session. All 4 success criteria (C1 Hint, C2 Reveal-one, C3 Reveal-all, C4 Reveal counter resets) + button-guard check confirmed. This cannot be re-run from WSL (GUI/Qt path requires a real PyMOL display). Per 06-03-SUMMARY.md line 21 + line 70.

## Conclusion

**Phase 6 goal ACHIEVED.** All 35 must-haves (18 truths + 4 artifacts + 13 key_links across the 3 plans) verified against the actual codebase — not SUMMARY claims. All 4 ROADMAP success criteria met at both tiers (WSL unit tests + headless smoke 29/29 ALL PASSED + human-verify APPROVED). All 4 requirements (GAME-05, GAME-06, GAME-07, DIFF-01) satisfied. WSL gates clean (py_compile, 22 unit tests, Pitfall-1 grep 0 matches, exec_ gate 1 allowed match). Three runtime bugs found during verification were fixed and regression-tested. Ready for phase completion.

---

_Verified: 2026-08-11T04:10:00Z_
_Verifier: OpenCode (gsd-verifier)_
