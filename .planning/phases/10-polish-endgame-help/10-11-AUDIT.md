# Phase 10 Post-Implementation Audit: README + Docs vs Shipped Code

**Audited:** 2026-08-18
**Auditor:** Plan 10-11 (read-only)
**Purpose:** Verify the README + planning docs accurately reflect the SHIPPED code after all Phase 10 plans. Catch any drift introduced during implementation (e.g. a README claim that doesn't match the actual shipped behavior, a doc that references a feature that didn't land, a grep gate that drifted). This is the bookend to Plan 10-04's pre-implementation audit: 10-04 verified the research claims before implementation; 10-11 verifies the shipped docs after implementation.

**Method:** For each claim, read the shipped code, confirm the claim matches, record PASS or FAIL with the shipped file:line as evidence. READ-ONLY — no source or doc file was modified (`git status` shows only this audit file added).

## Summary

| # | Claim | Verdict |
|---|-------|---------|
| 1 | README "Endgame & debrief" matches shipped code | PASS |
| 2 | README "Help & tooltips" matches shipped code | PASS |
| 3 | README "Controls" claim matches HELP_HTML | PASS |
| 4 | README Demo table matches setup_state.py DEMO_MANIFEST + TIER_LABELS | PASS |
| 5 | README Usage step 6 matches the actual win-then-debrief flow | PASS |
| 6 | README "Tips — How to spot hiders" section is present + framed as legitimate | PASS |
| 7 | exec_ grep gate = 3, all child dialogs | PASS |
| 8 | Pitfall-1 grep gate = 0 | PASS |
| 9 | Full pure-layer test suite passes (incl TestFormatDebrief) | PASS |
| 10 | 10-04 pre-implementation audit's findings addressed | PASS |

**Total:** 10/10 PASS, 0 FAIL.

## Grep Gates

- exec_ gate: **3** hits (expected 3, all child dialogs) —
  - `biochemeleon/gui_game.py:345: msg.exec_()` — `_finish_win` QMessageBox (child)
  - `biochemeleon/gui_game.py:404: msg.exec_()` — `_finish_debrief` QMessageBox (child)
  - `biochemeleon/__init__.py:952: help_dlg.exec_()` — `_show_help` QDialog (child)
  - NO hit on the main `PluginDialog` (which uses `dialog.show()` at `__init__.py:151`, never `.exec_()`).
- Pitfall-1 gate: **0** hits (expected 0).
- Test suite: **125** tests, **125** passed (expected all pass, incl 5 `TestFormatDebrief`).
- `python3.6 -m py_compile biochemeleon/*.py` → clean (exit 0; audit changed no source).
- `python3.6 -m py_compile smoke/phase10_smoke.py` → clean (exit 0; smoke unchanged).

## Detail

### Claim 1: README "Endgame & debrief" matches shipped code
- **README claim:** (README.md:21) "the win screen shows your time, hints used, and reveals used, then a debrief highlights each hider and explains why it was hard to spot (the teachable moment)."
- **Shipped code evidence:**
  - `biochemeleon/gui_game.py:306` — `def _finish_win(self, elapsed):` (Plan 10-05 win-stats).
  - `biochemeleon/gui_game.py:341-343` — `msg.setInformativeText("<b>Time:</b> %d:%02d<br><b>Hints used:</b> %d<br><b>Reveals used:</b> %d" % (mins, secs, hints, reveals))` — the win screen shows time + hints + reveals.
  - `biochemeleon/gui_game.py:384` — `def _finish_debrief(self):` (Plan 10-06 debrief).
  - `biochemeleon/gui_game.py:397` — `text = format_debrief_text(counts)` (the per-rep "why hard to spot" explanations).
  - `biochemeleon/gui_game.py:398-404` — a second `QMessageBox(self.window())` with `setInformativeText(text)` + `msg.exec_()` — the debrief dialog.
- **Verdict:** PASS
- **Notes:** Exact match. `_finish_win` builds the time/hints/reveals stats block (DIFF-02); `_finish_debrief` builds the per-rep explanations via `format_debrief_text` (DIFF-03) and shows a second modal `QMessageBox`. Both are child dialogs (`.exec_()` allowed by AGENTS.md; see Claim 7). Human-verified in 10-09 (checks 1 + 2 PASS).

### Claim 2: README "Help & tooltips" matches shipped code
- **README claim:** (README.md:22) "every control has a tooltip; a Help button opens a panel explaining each representation, the PyMOL controls (rotate/pan/zoom/click), and a tip on switching representations to spot hiders."
- **Shipped code evidence:**
  - `biochemeleon/__init__.py:14` — `HELP_HTML = """<h2>bioCHEMeleon — Help</h2>...` (the 7-section rich-text reference; Plan 10-03).
  - `biochemeleon/__init__.py:234` — `self.help_btn = QtWidgets.QPushButton("Help")` (the Help button).
  - `biochemeleon/__init__.py:238` — `self.help_btn.clicked.connect(self._show_help)`.
  - `biochemeleon/__init__.py:928` — `def _show_help(self):` (opens the modal Help QDialog; Plan 10-03).
  - `biochemeleon/__init__.py:952` — `help_dlg.exec_()` (the modal child QDialog).
  - `setToolTip` call counts: `biochemeleon/gui_game.py` = **12** calls, `biochemeleon/gui_setup.py` = **25** calls, `biochemeleon/__init__.py` = **1** call (the Help button itself). Total = 38 tooltips across the three GUI files (Plans 10-02 + 10-07).
- **Verdict:** PASS
- **Notes:** Exact match. `HELP_HTML` covers each representation (lines 61-76 "Representations explained"), the PyMOL controls (lines 78-104 "PyMOL controls"), and a switch-reps tip (lines 106-125 "Tips — switch representations"). Every interactive widget in `gui_setup.py` (25 tooltips) + `gui_game.py` (12 tooltips) has a `setToolTip`. Human-verified in 10-09 (checks 5 + 6 PASS).

### Claim 3: README "Controls" claim matches HELP_HTML
- **README claim:** (implicit via README.md:22 Help bullet) the PyMOL controls are documented (rotate/pan/zoom/click).
- **Shipped code evidence:** `biochemeleon/__init__.py` `HELP_HTML` contains the verified controls text:
  - `__init__.py:81` — `<li><b>Rotate</b> — Left-drag</li>` ("Left-drag" = rotate).
  - `__init__.py:84` — `<li><b>Zoom</b> — Right-drag (or Shift + Left-drag to box-zoom a region)</li>` ("Right-drag" = zoom).
  - `__init__.py:86` — `<li><b>Zoom with the wheel</b> — hold Ctrl + scroll.` ("Ctrl + scroll" = zoom).
  - `__init__.py:86-88` — `The <b>plain scroll wheel adjusts the clipping plane, not zoom</b> — a common PyMOL surprise.` (the wheel=slab gotcha; the gotcha phrase is at line 87: "scroll wheel adjusts the clipping plane, not zoom").
  - `__init__.py:95` — `<li><b>Click an atom</b> (single Left-click) to check if it's a hider.` ("Left-click" = pick).
- **Verdict:** PASS
- **Notes:** All 5 required phrases present. The wheel=slab gotcha (the critical counterintuitive claim verified in 10-04 Claim 10 against `controlling.py:336`) is at `__init__.py:86-88`. The 10-09 human-verify Issue 1 fix added "Ctrl + Left-drag = Move" at `__init__.py:82` (verified against `controlling.py:327`). Human-verified in 10-09 (check 7 PASS — wheel=slab gotcha confirmed by the user).

### Claim 4: README Demo table matches setup_state.py DEMO_MANIFEST + TIER_LABELS
- **README claim:** (README.md:63-73) the 9 demos in the 4-tier table (Easy/Hard/Challenge/Very challenging + network column).
- **Shipped code evidence:**
  - `biochemeleon/setup_state.py:34-57` — `DEMO_MANIFEST` dict with exactly 9 entries: `1znf`, `5e54`, `1k8p`, `1xdn`, `2qbz`, `4wb3`, `sasdpg4`, `1gzm`, `3gp6`.
  - `biochemeleon/setup_state.py:65-70` — `TIER_LABELS` dict with exactly 4 keys: `easy`→`Easy`, `hard`→`Hard`, `challenge`→`Challenge`, `very_challenging`→`Very challenging`.
  - Cross-check (README row → manifest entry):
    | README row | Tier | ID | Source/Network | manifest difficulty | manifest source | Match |
    |---|---|---|---|---|---|---|
    | 65 | Easy | 1znf | RCSB PDB / no (bundled) | easy | bundled | ✓ |
    | 66 | Easy | 5e54 | RCSB PDB / no (bundled) | easy | bundled | ✓ |
    | 67 | Easy | 1k8p | RCSB PDB / no (bundled) | easy | bundled | ✓ |
    | 68 | Hard | 1xdn | RCSB PDB / no (bundled) | hard | bundled | ✓ |
    | 69 | Hard | 2qbz | RCSB PDB / no (bundled) | hard | bundled | ✓ |
    | 70 | Hard | 4wb3 | RCSB PDB / no (bundled) | hard | bundled | ✓ |
    | 71 | Challenge | sasdpg4 | SASBDB / yes (fetched) | challenge | sasbdb | ✓ |
    | 72 | Very challenging | 1gzm | MemProtMD / yes (fetched) | very_challenging | memprotmd | ✓ |
    | 73 | Very challenging | 3gp6 | MemProtMD / yes (fetched) | very_challenging | memprotmd | ✓ |
  - All 9 README IDs are keys in `DEMO_MANIFEST`. All 4 tier labels map through `TIER_LABELS`. All network flags match (`bundled`→no, `sasbdb`/`memprotmd`→yes).
  - README.md:75 references `DATA_SOURCES.md` for full attribution — file exists (10114 bytes).
- **Verdict:** PASS
- **Notes:** Minor presentation observation (NOT a FAIL): the README's "Category" column uses the manifest's `type` field for the 3 nucleic-acid demos (5e54→"RNA", 1k8p→"DNA", 2qbz→"RNA") rather than the manifest's `category` field ("Nucleic acid"). The in-app `demo_combo` (`gui_setup.py:172-176`) displays `meta['category']` = "Nucleic acid" for these 3, so a user comparing the README to the dropdown sees "RNA"/"DNA" vs "Nucleic acid". The README is accurate and more specific (RNA vs DNA is a meaningful distinction); this is a defensible user-facing simplification, not drift. The plan's Claim 4 explicit criteria (IDs match `DEMO_MANIFEST` keys, tiers match `TIER_LABELS`, network matches `source`) are all satisfied.

### Claim 5: README Usage step 6 matches the actual win-then-debrief flow
- **README claim:** (README.md:51) "Find all hiders to win — the timer stops and a win screen shows your time, hints used, and reveals used, followed by a debrief highlighting each hider and why it was hard to spot."
- **Shipped code evidence:** the win-then-debrief flow in `biochemeleon/gui_game.py`:
  - `gui_game.py:289` — `def _on_win(self, elapsed):` (win callback).
  - `gui_game.py:301` — `self._timer.stop()` (the timer stops).
  - `gui_game.py:304` — `QtCore.QTimer.singleShot(100, lambda: self._finish_win(elapsed))` (schedules the win dialog after a redraw frame).
  - `gui_game.py:306` — `def _finish_win(self, elapsed):` (the win screen).
  - `gui_game.py:341-343` — `msg.setInformativeText(...Time...Hints used...Reveals used...)` (win screen shows time + hints + reveals).
  - `gui_game.py:354` — `self._show_all_hiders_for_debrief()` (highlights each hider in its rep).
  - `gui_game.py:357` — `QtCore.QTimer.singleShot(100, self._finish_debrief)` (schedules the debrief dialog).
  - `gui_game.py:359` — `def _show_all_hiders_for_debrief(self):` (shows every registered hider in ITS rep; fragment-aware).
  - `gui_game.py:384` — `def _finish_debrief(self):` (the debrief dialog with per-rep explanations).
- **Verdict:** PASS
- **Notes:** Exact sequence match: win → timer stops → win screen (time/hints/reveals) → show all hiders → debrief dialog (why each was hard to spot). The flow `_on_win → _finish_win → _show_all_hiders_for_debrief → _finish_debrief` matches the README's "the timer stops and a win screen shows your time, hints used, and reveals used, followed by a debrief highlighting each hider and why it was hard to spot" word-for-word. Human-verified in 10-09 (checks 1 + 2 PASS).

### Claim 6: README "Tips — How to spot hiders" section is present + framed as legitimate
- **README claim:** (README.md:56-59) the Tips section says "switch reps to make an impostor stand out" + "legitimate observation strategy, not a cheat."
- **Shipped code evidence:**
  - `README.md:56` — `## Tips — How to spot hiders` (the section heading).
  - `README.md:58` — "Hiders blend into one representation. Switch reps to make an impostor stand out (e.g. hide cartoon, show spheres — a cartoon hider will stick out as an extra sphere). See the in-app Help panel for details." (the "switch reps to make an impostor stand out" phrase is present).
  - `README.md:59` — "This is a legitimate observation strategy, not a cheat." (the "legitimate observation strategy, not a cheat" phrase is present).
- **Verdict:** PASS
- **Notes:** Both required phrases present at the exact lines. The framing matches the ROADMAP SC2 note + the research's UX-02 strategy section (the switch-reps strategy is framed as fair play, not cheating). The in-app `HELP_HTML` (`__init__.py:106-125`) carries the same framing ("This is fair play... It is NOT cheating").

### Claim 7: exec_ grep gate = 3, all child dialogs
- **Expected:** 3 hits after all Phase 10 plans execute — `gui_game.py` `_finish_win` QMessageBox, `gui_game.py` `_finish_debrief` QMessageBox, `__init__.py` `_show_help` QDialog. NO hit on the main PluginDialog/SetupTab/GameTab.
- **Shipped code evidence:** `grep -rnE "\.exec_\(\)" biochemeleon/` returns exactly 3 hits:
  - `biochemeleon/gui_game.py:345: msg.exec_()` — inside `_finish_win` (line 306); `msg = QtWidgets.QMessageBox(self.window())` at line 337. Child QMessageBox.
  - `biochemeleon/gui_game.py:404: msg.exec_()` — inside `_finish_debrief` (line 384); `msg = QtWidgets.QMessageBox(self.window())` at line 398. Child QMessageBox.
  - `biochemeleon/__init__.py:952: help_dlg.exec_()` — inside `_show_help` (line 928); `help_dlg = QtWidgets.QDialog(self)` at line 941. Child QDialog.
  - The main `PluginDialog` uses `dialog.show()` at `__init__.py:151` (in `run_plugin_gui`), NEVER `.exec_()`. Confirmed modeless.
- **Verdict:** PASS
- **Notes:** Count is exactly 3, all on child dialogs (QMessageBox × 2 + QDialog × 1), NONE on the main PluginDialog. This matches the 10-04 pre-impl audit's prediction (10-04 Claim 2: gate=1 baseline; 10-03 raises to 2; 10-06 raises to 3). The 10-09 human-verify Issue 2 explicitly preserved `help_dlg.exec_()` (did NOT switch to `show()`) to keep the gate at 3 and the Help dialog modal. AGENTS.md rule satisfied: "QFileDialog.exec_() / QMessageBox.exec_() on child dialogs ARE allowed."

### Claim 8: Pitfall-1 grep gate = 0
- **Expected:** 0 hits.
- **Shipped code evidence:** `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/` returns 0 hits (exit code 1 = no match).
- **Verdict:** PASS
- **Notes:** Zero matches. All Qt imports come through `from pymol.Qt import ...` (auto-selects PyQt5/PySide2), never raw `from PyQt5 import`. No legacy Tkinter/Pmw tokens. AGENTS.md Pitfall-1 gate satisfied.

### Claim 9: Full pure-layer test suite passes (incl TestFormatDebrief)
- **Expected:** all tests pass, incl the 5 `TestFormatDebrief` tests from Plan 10-01; no regression to the existing tests.
- **Shipped code evidence:** `python3.6 -m unittest tests.test_setup_state -v` → "Ran 125 tests in 0.021s / OK". The `TestFormatDebrief` class is at `tests/test_setup_state.py:743` with 5 test methods:
  - `test_format_debrief_empty_dict` (line 754)
  - `test_format_debrief_all_zero` (line 760)
  - `test_format_debrief_single_rep` (line 768)
  - `test_format_debrief_game_reps_order` (line 786)
  - `test_format_debrief_rep_none_defensive` (line 799)
  - All 5 pass (part of the 125 OK).
- **Verdict:** PASS
- **Notes:** 125 tests, all pass. `TestFormatDebrief` (5 tests, Plan 10-01) is present + green. No regression. The 10-09-VERIFY.md post-fix run also recorded 125 tests (so the count is stable across the 10-09 fix + 10-10 README finalization; 10-10 was docs-only).

### Claim 10: The 10-04 pre-implementation audit's findings (if any FAIL) were addressed
- **Expected:** if 10-04 recorded any FAIL claims, confirm the dependent implementation plan addressed them. If 10-04 was all PASS, this claim is PASS trivially.
- **Shipped code evidence:** `.planning/phases/10-polish-endgame-help/10-04-AUDIT.md` records **10/10 PASS, 0 FAIL** (Summary table lines 10-22; "Total: 10/10 PASS, 0 FAIL" at line 23). The 10-04 audit verified the research citations against the pre-implementation codebase and found no stale claims, no drifted file:line references, no incorrect API assumptions. The Blockers table (lines 99-101) is empty.
- **Verdict:** PASS
- **Notes:** Trivially PASS — 10-04 recorded 0 FAIL claims, so there are no outstanding FAIL findings to address. The post-implementation state confirms the 10-04 predictions held: the exec_ gate rose from 1 (10-04 baseline) to 3 (10-03 added the Help QDialog, 10-06 added the debrief QMessageBox), all on child dialogs as predicted. The 10-09 human-verify (8/8 checks PASS) is the runtime confirmation that the implementation landed correctly.

## Gaps (if any FAIL)

| Failed claim | Drift description | Recommended follow-up |
|---|---|---|
| (none) | | |

No FAIL claims. One minor non-blocking observation recorded under Claim 4 Notes: the README's "Category" column uses the manifest's `type` field (RNA/DNA) for the 3 nucleic-acid demos while the in-app `demo_combo` displays the manifest's `category` field ("Nucleic acid"). This is a defensible user-facing simplification (more specific), not drift; no follow-up required (optional: align the README Category column to "Nucleic acid" if exact dropdown parity is desired, but the current text is accurate).

## Conclusion

All 10 claims PASS — the README + planning docs accurately reflect the SHIPPED code after all Phase 10 plans. No doc drift: every user-facing claim in the README is backed by shipped code (verified by reading each shipped file + recording file:line evidence), the grep gates are at their expected final state (exec_ = 3 all child dialogs, Pitfall-1 = 0), the test suite is green (125 tests, incl 5 TestFormatDebrief), and the 10-04 pre-implementation audit's all-PASS findings held through implementation. The 10-09 human-verify (8/8 checks PASS, APPROVED) is the runtime confirmation.

**Phase 10 post-implementation audit complete; README + docs match shipped code (all PASS, 0 gaps flagged for follow-up). Phase 10 is COMPLETE.**

No source code or doc file was modified (read-only audit). `git status` shows only this audit file added. `python3.6 -m py_compile biochemeleon/*.py` passes (unchanged codebase). `python3.6 -m py_compile smoke/phase10_smoke.py` passes (smoke unchanged).
