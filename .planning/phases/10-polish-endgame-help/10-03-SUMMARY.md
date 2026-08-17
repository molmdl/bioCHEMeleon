---
phase: 10-polish-endgame-help
plan: 03
subsystem: ui
tags: [qt, qdialog, qtextedit, rich-text, help, ux, pymol-controls, representations]

# Dependency graph
requires:
  - phase: 01
    provides: PluginDialog in __init__.py (modeless dialog.show(), QTabWidget with Setup + Game tabs)
  - phase: 10
    provides: 10-RESEARCH-help.md (VERIFIED PyMOL controls mapping from controlling.py:320-348 — the wheel=slab gotcha + the 6-section Help content)
provides:
  - HELP_HTML module constant (6-section rich-text reference: what is bioCHEMeleon, Setup tab, Game tab, representations explained, PyMOL controls [VERIFIED], switch-reps strategy)
  - PluginDialog.help_btn (right-aligned button row below the QTabWidget — reachable from both Setup and Game tabs)
  - PluginDialog._show_help (modal child QDialog + read-only QTextEdit + OK button + .exec_())
affects: [10-09]

# Tech tracking
tech-stack:
  added: []  # no new libs — pure Qt QDialog + QTextEdit + QPushButton (all via pymol.Qt)
  patterns:
    - Modal child QDialog opened via .exec_() for a reference panel (ALLOWED by AGENTS.md; main PluginDialog stays modeless dialog.show())
    - Read-only QTextEdit.setHtml(HELP_HTML) for scrolling rich-text help (QTextEdit natively scrolls + renders <h2>/<ul>/<ol>/<b>/<code> + supports copy-paste; chosen over QLabel-in-QScrollArea per 10-RESEARCH-help.md)
    - Module-level HELP_HTML string constant (kept in __init__.py near the dialog that shows it — single file to edit; under the ~150-line threshold per research Open Question 3)

key-files:
  created: []
  modified: [biochemeleon/__init__.py]

key-decisions:
  - "Modal child QDialog (.exec_()) for Help — ALLOWED by AGENTS.md (the main PluginDialog stays modeless dialog.show(), NEVER .exec_()). The exec_ grep gate rises 1 -> 2; BOTH hits on child dialogs (gui_game.py _finish_win QMessageBox + __init__.py _show_help QDialog). Precedent: QMessageBox.question / QInputDialog.getText / QFileDialog.getSaveFileName / QColorDialog.getColor are all modal children."
  - "QTextEdit (read-only) over QLabel-in-QScrollArea — QTextEdit natively scrolls long rich text, renders <h2>/<ul>/<table> cleanly, and supports copy-paste (a user can copy a control description). QLabel-in-scroll-area is more verbose + tables render less reliably (10-RESEARCH-help.md Help Panel Design)."
  - "HELP_HTML kept in __init__.py as a module constant (NOT a new help_text.py file) — the research's ~150-line threshold for a separate file was not exceeded; keeps the help close to the dialog that shows it (one file to edit)."
  - "Help button below the QTabWidget in a right-aligned QHBoxLayout (NOT a tab-bar corner '?') — always visible regardless of active tab, doesn't crowd the tab bar, matches the existing QVBoxLayout(self.tabs) layout (10-RESEARCH-help.md Help button placement)."
  - "PyMOL controls text is the VERIFIED text from 10-RESEARCH-help.md (controlling.py:320-348) — the plain scroll wheel adjusts the CLIPPING SLAB, NOT zoom; zoom = Right-drag or Ctrl+wheel. The Help text states this gotcha explicitly so students don't assume the wheel is broken. NOT paraphrased, NOT invented."

patterns-established:
  - "Help/reference modal child QDialog pattern: QDialog(self) + read-only QTextEdit.setHtml(MODULE_CONST) + OK button + .exec_() — the standard Qt approach for a help/manual window (10-RESEARCH-help.md)."
  - "Rich-text help content as a module-level triple-quoted HTML string constant — QTextEdit renders HTML fragments (no <html>/<body> wrapper needed); '&' escaped as &amp; for the parser."

# Metrics
duration: ~5min
completed: 2026-08-18
---

# Phase 10 Plan 03: Help Button + Modal Help Dialog (UX-01 + UX-02) Summary

**Additive UX pass: a Help button (right-aligned, below the QTabWidget) opens a modal child QDialog with a 6-section rich-text reference — the VERIFIED PyMOL controls (wheel = clipping slab, NOT zoom) + switch-reps strategy are the centerpiece.**

## Performance

- **Duration:** ~5 min (active editing; ~78 min wall including context load)
- **Started:** 2026-08-17T17:48Z
- **Completed:** 2026-08-17T19:07Z
- **Tasks:** 1
- **Files modified:** 1 (`biochemeleon/__init__.py`)

## Accomplishments
- `HELP_HTML` module-level constant added to `biochemeleon/__init__.py` (between the `dialog = None` singleton and `def __init_plugin__`). 6 sections with `<h2>` headings, `<ul><li>` bullets, `<ol><li>` numbered steps, `<b>` emphasis, `<code>` for PyMOL commands — all 7 `<h2>` tags present (1 "Help" title + 6 content sections).
- The 6 sections: (1) What is bioCHEMeleon, (2) Setup tab overview, (3) Game tab overview, (4) Representations explained (the 5 GAME_REPS), (5) PyMOL controls (default 3-Button Viewing mode — VERIFIED from `controlling.py:320-348`), (6) Tips — switch representations to spot hiders.
- The **wheel=slab gotcha** is stated explicitly: "The **plain scroll wheel adjusts the clipping plane, not zoom** — a common PyMOL surprise." + "Zoom with the wheel: hold Ctrl + scroll." This is the single most counterintuitive finding from the research and the Help text flags it prominently so students don't assume the wheel is broken.
- `self.help_btn = QtWidgets.QPushButton("Help")` added to `PluginDialog.__init__` in a right-aligned `QHBoxLayout` (addStretch(1) + button) placed AFTER `layout.addWidget(self.tabs)` — reachable from both Setup and Game tabs regardless of the active tab.
- `self.help_btn.setToolTip(...)` set (the research's recommended tooltip text: "Open the help panel: what each control does, what representations mean, and how to use the PyMOL viewer.").
- `self.help_btn.clicked.connect(self._show_help)` signal wiring.
- `PluginDialog._show_help(self)` method added at the end of the class (after `_on_cleanup`): builds a modal child `QDialog(self)` + read-only `QTextEdit.setHtml(HELP_HTML)` + OK button (`ok.clicked.connect(help_dlg.accept)`) + `help_dlg.exec_()`. `setMinimumSize(520, 600)` keeps the dialog comfortably readable.
- The main `PluginDialog` (via `run_plugin_gui`) stays MODELESS — `dialog.show()` at line 147, UNCHANGED (NEVER `.exec_()`).
- `&` escaped as `&amp;` in "Generate &amp; export" and "Import puzzle / Save checkpoint" (HTML entity — QTextEdit's rich-text parser requires this).
- No `<html>`/`<body>` wrapper tags (QTextEdit handles fragments fine).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add HELP_HTML module constant + Help button + _show_help method to __init__.py** - `dfa70f4` (feat)

## Files Created/Modified
- `biochemeleon/__init__.py` — 3 additive changes (159 insertions, 0 deletions):
  1. `HELP_HTML` module constant (lines 14-115) — 6-section rich-text HTML.
  2. Help button row in `PluginDialog.__init__` (lines 221-236) — right-aligned `QHBoxLayout` below `layout.addWidget(self.tabs)`.
  3. `_show_help` method (lines 924-948) — modal child `QDialog` + read-only `QTextEdit` + OK + `.exec_()`.
  No new imports (uses `from pymol.Qt import QtWidgets` already at module level, line 35). No new files.

## Decisions Made
- **Modal child QDialog (`.exec_()`) for Help — ALLOWED:** AGENTS.md explicitly permits `.exec_()` on child dialogs (QFileDialog/QMessageBox); the main PluginDialog must stay modeless (`dialog.show()`). The exec_ grep gate rises 1 -> 2; BOTH hits on child dialogs (`gui_game.py:312 msg.exec_()` `_finish_win` QMessageBox + `__init__.py:948 help_dlg.exec_()` `_show_help` QDialog). NO hit on the main PluginDialog. (10-RESEARCH-help.md Help Panel Design; AGENTS.md Qt rules.)
- **QTextEdit (read-only) over QLabel-in-QScrollArea:** QTextEdit natively scrolls long rich text, renders `<h2>`/`<ul>`/`<table>` cleanly, and supports copy-paste (a user can copy a control description). QLabel-in-scroll-area is more verbose + tables render less reliably. (10-RESEARCH-help.md Help Panel Design.)
- **HELP_HTML in `__init__.py` (not a new `help_text.py`):** The research's ~150-line threshold for a separate file was not exceeded (~100 lines of HTML). Keeps the help close to the dialog that shows it — one file to edit. (10-RESEARCH-help.md Open Question 3.)
- **Help button below the QTabWidget (right-aligned):** Always visible regardless of active tab, doesn't crowd the tab bar, matches the existing `QVBoxLayout(self.tabs)` layout. A `Qt.WindowFlags` "?" context-help button was rejected — it only shows a tiny per-widget tooltip on click in some Qt styles and is unreliable across platforms; a dedicated Help dialog is clearer for students. (10-RESEARCH-help.md Help button placement.)
- **PyMOL controls text is VERIFIED (not invented):** The wheel=slab gotcha comes directly from `controlling.py:320-348` (the `three_button_viewing` mode dict) — `('w','none','slab')` at line 336 defines the plain scroll wheel as `slab` (cButModeScaleSlab — adjust the clipping slab), NOT zoom. The Help text states this explicitly so students don't assume the wheel is broken. A 30-second human-verify in a real PyMOL 2.5.0 session is the recommended final check (research Open Question 1; deferred to Plan 10-09). (10-RESEARCH-help.md UX-02.)
- **`&` escaped as `&amp;`:** QTextEdit's rich-text parser requires HTML entities; "Generate & export" and "Import puzzle / Save checkpoint" use `&amp;` so the `&` renders correctly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded comments/docstrings to avoid the literal `.exec_()` token**

- **Found during:** Task 1 (verification)
- **Issue:** The plan's action block provided comment + docstring text that literally contained `.exec_()` (e.g. "opened with .exec_()", "NEVER .exec_()"). These are NOT calls — they are documentation — but the `grep -rnE "\.exec_\(\)"` gate matches literal tokens in comments/docstrings too (the AGENTS.md-warned false-positive pattern: "we hit a false positive on a docstring that said 'from PyQt5 import'"). The plan's verification requires the exec_ gate to return EXACTLY 2 hits (both real calls on child dialogs); the literal-token comments would have produced 6 hits (2 real + 4 comment/docstring), failing the "EXACTLY 2" gate.
- **Fix:** Reworded the comment (Help button row) and the docstring (`_show_help`) to avoid the literal `.exec_()` token — "opened with .exec_()" -> "opened via the modal exec call"; "NEVER .exec_()" -> "NEVER the modal exec form". The semantics are preserved (the documentation still explains the modal-child-allowed rule); only the literal token is removed so the grep gate returns exactly the 2 real calls.
- **Files modified:** `biochemeleon/__init__.py` (comment lines 223-225 + docstring lines 925-928)
- **Precedent:** Mirrors the 03-03/03-06/03-09/03-10/08-01/08-02 docstring-rewording precedent (Rule 3 blocking fix to satisfy an exact-count grep gate; AGENTS.md-warned false-positive pattern).
- **Commit:** `dfa70f4` (included in the task commit — the rewording was part of making the gate green before the commit landed)

No other deviations — the 3 additive changes (HELP_HTML + help_btn + _show_help) were applied verbatim from the plan's action block.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required. This is a Qt dialog edit; the only runtime verification is the human-verify checkpoint (open Help from both tabs, confirm modality + scrolling + all 6 sections + the wheel=slab gotcha accuracy in real PyMOL 2.5.0), which is DEFERRED to Plan 10-09's human-verify checkpoint.

## Grep-Gate State (this plan's Wave-1 worktree)
- `python3.6 -m py_compile biochemeleon/*.py` → clean (all modules syntax-clean).
- `grep -rnE "\.exec_\(\)" biochemeleon/ --include="*.py"` → exactly **2** hits, BOTH on child dialogs:
  - `biochemeleon/gui_game.py:312: msg.exec_()` — the existing `_finish_win` QMessageBox (child dialog, UNCHANGED).
  - `biochemeleon/__init__.py:948: help_dlg.exec_()` — the NEW `_show_help` QDialog (child dialog, this plan).
  - NO hit on the main `PluginDialog` / `SetupTab` / `GameTab` (those use `.show()`, never `.exec_()`).
- `grep -rnE "import Tkinter|...|import PyQt5" biochemeleon/ --include="*.py"` → **0** hits (Pitfall-1 gate clean — the new code uses `from pymol.Qt import QtWidgets` already at module level; no new import violations).
- `python3.6 -m unittest tests.test_setup_state -v` → 120 tests, all pass (no regression — `__init__.py` is Qt-coupled and not unit-tested in WSL, but the test stub confirms the import path still resolves).
- `grep -c "<h2>" biochemeleon/__init__.py` → **7** (1 "Help" title + 6 content sections — the plan's `>= 7` requirement met).
- Key links verified: `help_btn.clicked.connect(self._show_help)` (line 234), `text.setHtml(HELP_HTML)` (line 943), `layout.addWidget(self.tabs)` (line 220, followed by `addLayout(btn_row)` at line 236), `help_dlg.exec_()` (line 948), `dialog.show()` (line 147, modeless — UNCHANGED).

## Next Phase Readiness
- Help dialog is in place. The 6-section rich-text reference (including the VERIFIED wheel=slab gotcha) is the canonical controls reference for the whole plugin.
- **Handoff to Plan 10-09:** Human-verify (open Help from both tabs, scroll, dismiss with OK/Esc, verify the wheel=slab gotcha accuracy in a real PyMOL 2.5.0 session) is deferred to the Plan 10-09 human-verify checkpoint. The Help dialog's content + modality + scrolling cannot be verified headlessly from WSL (Qt needs a real display — AGENTS.md environment split); the WSL gates (py_compile + exec_ + Pitfall-1 + unit tests) confirm the code is syntactically clean + the grep invariants hold, but the rendered UX is human-verify-territory.
- **Parallel safety:** This plan modifies only `biochemeleon/__init__.py` (disjoint from Plan 10-01's `setup_state.py`+tests and Plan 10-02's `gui_setup.py` in Wave 1). The exec_ gate rises 1 -> 2 in THIS worktree; after the orchestrator merges all Wave-1 branches, the combined exec_ gate will be the union of each branch's hits (all on child dialogs — no main-dialog hit in any branch).

---
*Phase: 10-polish-endgame-help*
*Plan: 03*
*Completed: 2026-08-18*
