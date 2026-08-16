# Planner Brief: Phase 10 — Polish, Endgame & Help

**Mode:** standard (not gap closure). **Depth:** comprehensive.

## Phase Goal (from ROADMAP.md)
"The game is polished with in-game explanations, PyMOL controls help, and a rich endgame experience (win-screen stats + post-game debrief) that delivers the teachable moment. The README is finalized to reflect the shipped product."

**Depends on:** Phase 4, Phase 6 (both COMPLETE). **Requirements:** UX-01, UX-02, DIFF-02, DIFF-03 (+ README SC5).

## Success Criteria (what must be TRUE)
1. (UX-01) Tooltips / a help panel explain what each button does and what each representation means.
2. (UX-02) A controls-help reference explains how to click, navigate, zoom, and rotate in PyMOL (for users new to PyMOL).
3. (DIFF-02) The winning message shows time taken, hints used, and reveals used.
4. (DIFF-03) After winning, all hiders are highlighted with an explanation of why each was hard to spot (the teachable debrief).
5. (SC5) README.md is updated to reflect the final shipped feature set, install instructions, and usage.

**Planning note (MUST honor):** The controls-help reference (SC2) and README/tooltips (SC1/SC5) should remind the user that toggling/changing the active representation in PyMOL can help spot hiders — a legitimate observation strategy, not a cheat.

## USER-SPECIFIC INSTRUCTIONS (honor exactly)
1. README.md: KEEP the top "vibe coding" warning block (README.md lines 1-2 verbatim). CHANGE "UNDER DEVELOPMENT" (line 4) to reflect that the PyMOL plugin (v1) is COMPLETE. Tone: clear, concise, engaging, professional but simple wordings understandable by students.
2. Split into more plans so each plan is focused (user explicitly wants focused plans, not compressed).
3. Do NOT use the todowrite tool (save context).
4. Tone for ALL user-facing text (tooltips, help panel, debrief, README): clear, concise, engaging, professional but simple — understandable by students. No jargon without explanation.

## RESEARCH (2 files — READ BOTH FULLY before planning)
Both are HIGH-confidence, implementation-ready:

- `.planning/phases/10-polish-endgame-help/10-RESEARCH-endgame.md` — DIFF-02 + DIFF-03. Key: extend `_finish_win` QMessageBox with setInformativeText (time/hints/reveals, no controller change); TWO sequential dialogs (win then debrief); pure `format_debrief_text(counts_by_rep)` + `DEBRIEF_EXPLANATIONS` dict in setup_state.py (mirrors format_remaining); fragment-aware `_show_all_hiders_for_debrief` (cartoon/ribbon by `segi GAME and resi rv1-rv2`, single-atom by id); defer cleanup() from after-win to after-debrief (non-imported only, same _is_imported gate); reuse the 100ms redraw-delay pattern; per-rep explanations are domain-accurate.

- `.planning/phases/10-polish-endgame-help/10-RESEARCH-help.md` — UX-01 + UX-02 + README. Key: ~30 widgets need tooltips (inventory table with draft text); Help button in PluginDialog to modal child QDialog (allowed, exec_ gate 1 to 2) with read-only QTextEdit rich HTML + 6 sections; VERIFIED PyMOL 2.5.0 controls from controlling.py — CRITICAL: plain scroll wheel = clipping slab NOT zoom (zoom = Right-drag or Ctrl+wheel); click-to-find = single left-click (PickWizard keeps left-drag rotation); switch-reps strategy text; README structure + feature inventory.

## KEY CODE FILES (read these to ground the tasks)
- `biochemeleon/setup_state.py` — PURE layer (stdlib only, WSL-unit-testable). Has GAME_REPS, format_remaining (precedent for format_debrief_text). Plan 01 adds DEBRIEF_EXPLANATIONS + format_debrief_text here.
- `biochemeleon/gui_game.py` — GameTab (Qt+cmd). `_finish_win` (line ~284) is where DIFF-02 lands; new `_show_all_hiders_for_debrief` + `_finish_debrief` for DIFF-03; ~8 widgets need tooltips. Plan 04 modifies this.
- `biochemeleon/gui_setup.py` — SetupTab (Qt). ~25 widgets need tooltips + per-rep explanations. Plan 02 modifies this.
- `biochemeleon/__init__.py` — PluginDialog (Qt). Plan 03 adds Help button + `_show_help` + HELP_HTML constant.
- `biochemeleon/game.py` — GameController. NO CHANGE needed (already has _hint_count, _reveal_count, registry, cleanup()). Read to confirm.
- `biochemeleon/registry.py` — HiderRegistry. counts_by_rep() + all() + endpoint_resvs field. Read to confirm the debrief show logic.
- `biochemeleon/wizard.py` — PickWizard. Sets mouse_selection_mode=0, keeps left-drag rotate. Read for controls accuracy.
- `README.md` — current state (2026-08-03, "UNDER DEVELOPMENT"). Plan 05 rewrites.
- `tests/test_setup_state.py` — pure-layer tests. Plan 01 adds debrief formatter tests here.
- `smoke/phase4_1_smoke.py` and `smoke/phase6_smoke.py` — headless smoke precedents. Plan 04's smoke models on these.

## PROJECT CONSTRAINTS (MUST respect in every plan)
- **WSL/Windows split:** python3.6 for syntax + pure-layer unit tests ONLY (NEVER pip install). PyMOL 2.5.0 runs in Windows conda. Headless PyMOL via `cmd.exe /c C:\src\run-conda-pymol.bat -cq <script>` from staged `tmp/bioCHEMeleon/` path (pure pymol.cmd.* only, NO Qt). Qt paths need human-verify checkpoints in real Windows PyMOL.
- **Qt rules:** `from pymol.Qt import QtWidgets, QtCore, QtGui` (NEVER `from PyQt5 import`). Main plugin dialog is MODELESS (dialog.show(), NEVER .exec_()). Child dialogs (QMessageBox, QFileDialog, QDialog) MAY use .exec_(). The exec_ grep gate is currently 1; Phase 10 raises it (all child dialogs — ALLOWED per AGENTS.md). Each plan that adds .exec_() must assert the gate hits are ONLY on child dialogs.
- **Grep gates (run after every code change):**
  - `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/` — MUST return 0.
  - `grep -rnE "\.exec_\(\)" biochemeleon/` — currently 1; rises to 2-3, ALL on child dialogs. Assert NO hit on the main PluginDialog/SetupTab.
  - `python3.6 -m py_compile biochemeleon/*.py` — syntax check all modules.
  - `python3.6 -m unittest tests.test_setup_state -v` — pure-layer tests (currently 222+ pass; Plan 01 adds more).
- **Architecture (strict dependency direction):** setup_state.py (PURE: stdlib only, no pymol, no Qt) then demos.py/game.py/backup.py/mutation.py (cmd) then gui_setup.py/gui_game.py/__init__.py (Qt+cmd). Never reverse. setup_state.py must have NO `from pymol import cmd` and NO `from pymol.Qt import`.
- **GAME_REPS** = ['lines','sticks','spheres','cartoon','ribbon']. Surface is out of scope.
- **PyMOL Open Source has NO undo.** cleanup() restores from backup.
- **Headless smoke pattern:** pure pymol.cmd.* scripts in smoke/ dir (NO Qt), run headlessly. Mirrors smoke/phase6_smoke.py / smoke/phase4_1_smoke.py.
- **Commit style:** Conventional Commits with phase-plan scope, e.g. `feat(10-01):`, `test(10-01):`, `docs(10-05):`. Planning docs committed (commit_docs: true).
- **Parallel execution:** parallelization: true in config. Wave 1 plans with disjoint filesModified run in parallel via the worktree/branch protocol (see AGENTS.md). Plans sharing a file MUST be sequential (different waves).

## RECOMMENDED PLAN STRUCTURE (5 plans, 3 waves)

I have done the dependency + file-ownership analysis. Use this structure (refine tasks within each plan, but keep this split — it maximizes focus + parallelism and avoids file conflicts):

### Plan 10-01 (Wave 1, parallel) — TDD pure debrief formatter
- type: tdd
- files_modified: biochemeleon/setup_state.py, tests/test_setup_state.py
- depends_on: []
- autonomous: true
- What: Add DEBRIEF_EXPLANATIONS dict (5 reps, domain-accurate text from endgame research) + format_debrief_text(counts_by_rep) pure function (returns HTML rich-text: frame sentence + ul of per-rep bullets for reps with count>0 in GAME_REPS order; empty dict to fallback string). TDD: RED (failing tests) then GREEN (implement) then REFACTOR. Mirrors the format_remaining precedent (Phase 4.1). Pure/WSL-unit-testable.
- Research ref: 10-RESEARCH-endgame.md sections "Per-Rep Why Hard to Spot Explanations" + "Implementation Guidance" (setup_state.py bullet).

### Plan 10-02 (Wave 1, parallel) — Setup-tab tooltips
- type: execute
- files_modified: biochemeleon/gui_setup.py
- depends_on: []
- autonomous: true
- What: Add setToolTip() to every un-tooltipped widget in gui_setup.py (~25 widgets per the help-research tooltip inventory table). Include per-rep checkbox tooltips carrying the rep explanation (5 reps — use the verified explanation text from 10-RESEARCH-help.md "Representation Explanations" table). Pure additive — no behavior change. Verify: py_compile + grep gates (Pitfall-1=0, exec_ unchanged). Human-verify deferred to Plan 10-04's checkpoint.
- Research ref: 10-RESEARCH-help.md "UX-01: Widget Tooltip Inventory" (gui_setup.py table) + "Representation Explanations" table.

### Plan 10-03 (Wave 1, parallel) — Help button + dialog
- type: execute
- files_modified: biochemeleon/__init__.py
- depends_on: []
- autonomous: true
- What: Add a HELP_HTML module constant (6 sections: what is bioCHEMeleon, Setup tab overview, Game tab overview, representations explained, PyMOL controls [VERIFIED — use the controls text from 10-RESEARCH-help.md verbatim, including the wheel=slab gotcha], switch-reps strategy) + a right-aligned "Help" QPushButton below the QTabWidget in PluginDialog + a `_show_help` method (builds a modal child QDialog + read-only QTextEdit setHtml(HELP_HTML) + OK button + exec_()). Verify: py_compile + grep gates (exec_ rises 1 to 2, both child dialogs; Pitfall-1=0). Human-verify deferred to Plan 10-04's checkpoint.
- Research ref: 10-RESEARCH-help.md "UX-01: Help Panel Design" + "UX-02: PyMOL Controls Reference" (verified mapping) + "Switch Reps to Spot Hiders Strategy".

### Plan 10-04 (Wave 2, depends 10-01) — Endgame GUI + Game-tab tooltips + headless smoke + human-verify
- type: execute
- files_modified: biochemeleon/gui_game.py, smoke/phase10_smoke.py
- depends_on: ["10-01"]
- autonomous: false (has human-verify checkpoint)
- What:
  - Task 1 (auto): Modify `_finish_win` (DIFF-02: setText with hider count + setInformativeText with time/hints/reveals rich text). Add `_show_all_hiders_for_debrief` (fragment-aware cmd.show per rec — cartoon/ribbon by `segi GAME and resi rv1-rv2`, single-atom by id; skip rep=None). Add `_finish_debrief` (build counts_by_rep then format_debrief_text then second QMessageBox with WindowStaysOnTopHint + exec_() then cleanup gate _is_imported moved here from _finish_win). Add `from .setup_state import format_debrief_text` import. Add setToolTip to the ~8 un-tooltipped gui_game.py widgets (Hint, Reveal one/all, found-mgmt combo, timer/remaining/reveal labels). Remove the inline cleanup from _finish_win (it moves to _finish_debrief).
  - Task 2 (auto): Create smoke/phase10_smoke.py (pure pymol.cmd.* — NO Qt; modeled on phase4_1_smoke.py/phase6_smoke.py). Verify: start mixed-rep game (spheres + stick + cartoon 4-tuple segment) then mark all found then assert counts_by_rep then run the fragment-aware show loop then assert cmd.count_atoms per rep reflects shown hiders then assert cartoon fragment full rv1-rv2 range shown. Run headlessly via cmd.exe /c run-conda-pymol.bat -cq.
  - Task 3 (checkpoint:human-verify): Verify in real Windows PyMOL GUI: (a) play to win then win dialog shows time + hints + reveals (incl 0/0 flex case); (b) dismiss then debrief dialog appears + all hiders shown in viewer in their reps; (c) per-rep explanations match the game's reps; (d) dismiss then cleanup runs (non-imported: viewer returns to pre-game) / hiders stay (imported: click Cleanup then two-step removes them); (e) hover tooltips render on Setup + Game widgets; (f) Help button opens modal dialog with all 6 sections, scrolls, dismisses with OK; (g) controls text accurate (esp. wheel=slab gotcha — verify in real PyMOL).
- Research ref: 10-RESEARCH-endgame.md (full flow + Implementation Guidance) + 10-RESEARCH-help.md (gui_game tooltip table).

### Plan 10-05 (Wave 3, depends 10-04) — README finalization
- type: execute
- files_modified: README.md
- depends_on: ["10-04"]
- autonomous: true
- What: Rewrite README.md per 10-RESEARCH-help.md "README: Feature Inventory + Update Guidance". KEEP lines 1-2 (vibe-coding warning) verbatim. REMOVE "UNDER DEVELOPMENT" (line 4) — v1 PyMOL plugin is COMPLETE. Update Status line. Add "Endgame & debrief" + "Help & tooltips" to What It Does. Update Usage step 6 (win screen = time + hints + reveals + debrief). Add "Tips — How to spot hiders" section (switch-reps strategy). Update Demo table to 4-tier + network column. Update last-updated date. Tone: clear, concise, engaging, student-friendly. NO phase numbers / GSD references (user-facing). Verify: no broken markdown; tone check.
- Research ref: 10-RESEARCH-help.md "README: Feature Inventory + Update Guidance" (full outline + feature inventory table).

## WAVE SUMMARY
| Wave | Plans | Parallel? | Files (disjoint?) |
|------|-------|-----------|-------------------|
| 1 | 10-01, 10-02, 10-03 | YES (3 parallel) | setup_state.py+tests / gui_setup.py / __init__.py — DISJOINT |
| 2 | 10-04 | single | gui_game.py + smoke/phase10_smoke.py |
| 3 | 10-05 | single | README.md |

## YOUR TASKS AS PLANNER
1. READ both research files fully (10-RESEARCH-endgame.md + 10-RESEARCH-help.md).
2. READ the key code files (setup_state.py, gui_game.py, gui_setup.py, __init__.py, game.py, registry.py, wizard.py, README.md, tests/test_setup_state.py) to ground the tasks.
3. For EACH of the 5 plans, derive must_haves using goal-backward methodology (truths then artifacts then key_links).
4. Write 5 PLAN.md files to `.planning/phases/10-polish-endgame-help/`:
   - `10-01-PLAN.md` (type: tdd)
   - `10-02-PLAN.md` (type: execute)
   - `10-03-PLAN.md` (type: execute)
   - `10-04-PLAN.md` (type: execute, autonomous: false)
   - `10-05-PLAN.md` (type: execute)
5. Each PLAN.md MUST have: frontmatter (phase, plan, type, wave, depends_on, files_modified, autonomous, must_haves with truths/artifacts/key_links) + objective + execution_context + context (@references) + tasks (XML: name/files/action/verify/done) + verification + success_criteria + output.
6. Update ROADMAP.md Phase 10 section: replace "Plans: TBD" / "10-01: TBD during planning" with the actual 5 plan checkboxes + objectives. Update the Plans count + the status table row.
7. Commit the plans + updated ROADMAP.md: `git add .planning/phases/10-polish-endgame-help/*.md .planning/ROADMAP.md && git commit -m "docs(10): create phase plan"` (use a multi-line body describing the 5 plans / 3 waves).

## QUALITY GATES (self-check before returning)
- [ ] 5 PLAN.md files exist in `.planning/phases/10-polish-endgame-help/`
- [ ] Each plan has valid frontmatter (phase, plan, type, wave, depends_on, files_modified, autonomous, must_haves)
- [ ] Plan 10-01 is type: tdd (RED/GREEN/REFACTOR structure)
- [ ] Plan 10-04 has a checkpoint:human-verify task (autonomous: false)
- [ ] Wave 1 plans (01, 02, 03) have DISJOINT files_modified (parallel-safe)
- [ ] Each task has: name, files, action (specific), verify (command/check), done (acceptance criteria)
- [ ] Dependencies correct (01 none; 02 none; 03 none; 04 depends 01; 05 depends 04)
- [ ] Waves assigned (1,1,1,2,3) for parallel execution
- [ ] must_haves derived goal-backward from each plan's success criteria
- [ ] exec_ grep gate impact documented per plan
- [ ] README plan 05 keeps vibe-coding warning + removes "UNDER DEVELOPMENT"
- [ ] Commit the plans + update ROADMAP.md

## RULES
- Do NOT write code or implement — only PLAN.md files + ROADMAP.md update.
- Do NOT use the todowrite tool (save context per user instruction).
- Do NOT invent PyMOL behavior — use the verified controls text from the research.
- Use the domain-accurate per-rep explanations from the endgame research (do NOT make up science).
- Tone: all user-facing text must be clear, concise, engaging, professional but simple — understandable by students.
