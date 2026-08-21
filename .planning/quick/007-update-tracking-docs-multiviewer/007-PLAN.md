---
phase: quick-007
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - AGENTS.md
  - .planning/STATE.md
  - .planning/ROADMAP.md
  - .planning/PROJECT.md
autonomous: true

must_haves:
  truths:
    - "All file-path references in root AGENTS.md use pymol/-prefixed locations (no stale bare biochemeleon/, smoke/, tests/ path references)"
    - "The 4 documented commands (py_compile, unittest, pitfall-1 grep, exec_ grep) execute successfully with the updated paths"
    - "STATE.md mentions chimeraX as a potential viewer target alongside VMD"
    - "STATE.md notes the repo reorg (v1 code now lives under pymol/)"
    - "ROADMAP.md mentions chimeraX as a future milestone candidate"
    - "PROJECT.md mentions chimeraX as a future target"
  artifacts:
    - path: "AGENTS.md"
      provides: "Correct v1 code paths under pymol/ subdirectory"
    - path: ".planning/STATE.md"
      provides: "Multi-viewer focus + reorg note (Quick Tasks table untouched)"
    - path: ".planning/ROADMAP.md"
      provides: "chimeraX as future milestone candidate"
    - path: ".planning/PROJECT.md"
      provides: "chimeraX as future target alongside VMD"
  key_links:
    - from: "AGENTS.md Commands section"
      to: "actual file locations on disk"
      via: "py_compile / unittest / grep paths"
      pattern: "pymol/biochemeleon/"
    - from: "chimeraX mention"
      to: "STATE.md / ROADMAP.md / PROJECT.md"
      via: "consistent future-target language across all three docs"
      pattern: "chimeraX"
---

<objective>
Update tracking docs to reflect the multi-viewer repo reorg (commit 9ff57f1) that moved v1 code into `pymol/` and added `vmd/` + `chimeraX/` placeholder directories, and to record chimeraX as a future viewer target alongside VMD.

Purpose: The v1 milestone shipped, then the repo was reorganized for multi-viewer support — but AGENTS.md, STATE.md, ROADMAP.md, and PROJECT.md still reference the old flat layout (`biochemeleon/`, `smoke/`, `tests/` at repo root) and only mention VMD as the next target. Stale paths would mislead the next agent (broken commands, wrong file locations); missing chimeraX mention understates the project's scope.

Output: 4 doc files updated. No code, no tests, no behavior change.

**Critical planning insight (verified during planning):** `pymol/__init__.py` does NOT exist, so `pymol` is NOT a Python package. The naive update `python3.6 -m unittest pymol.tests.test_setup_state` FAILS with ImportError. The verified-correct repo-root command is `PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state -v` (confirmed: 125 tests OK). The problem statement's suggested `pymol/tests.test_setup_state` is broken — use the PYTHONPATH form instead. Likewise `cd pymol && python3.6 -m unittest tests.test_setup_state -v` works, but PYTHONPATH keeps all commands runnable from repo root (matching the "Commands (run from repo root)" header).
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@AGENTS.md

# Repo layout after reorg (commit 9ff57f1):
#   pymol/biochemeleon/   <- all plugin code (was biochemeleon/)
#   pymol/smoke/          <- all smoke tests (was smoke/)
#   pymol/tests/          <- all unit tests (was tests/); pymol/tests/__init__.py EXISTS
#   pymol/AGENTS.md       <- subdirectory copy, already correct (DO NOT TOUCH)
#   pymol/DATA_SOURCES.md <- subdirectory copy (DO NOT TOUCH)
#   vmd/.gitkeep          <- placeholder
#   chimeraX/.gitkeep     <- placeholder
#   wsl2win_cp.sh         <- already updated (commit 7a81dfc) to copy ./pymol/biochemeleon
#
# VERIFIED during planning (all run from repo root):
#   python3.6 -m py_compile pymol/biochemeleon/*.py            -> exit 0
#   PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state  -> 125 tests OK
#   grep -rnE "<pitfall regex>" pymol/biochemeleon/            -> 0 matches (good)
#   grep -rnE "\.exec_\(\)" pymol/biochemeleon/                -> 3 hits (QFileDialog/QMessageBox, expected)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update root AGENTS.md path references to pymol/ layout</name>
  <files>AGENTS.md</files>
  <action>
Update every stale file-PATH reference in root `AGENTS.md` to the new `pymol/`-prefixed layout. Do NOT touch `pymol/AGENTS.md` (that copy is already correct). Use the Edit tool for each change. The exact edits (old → new):

**Environment section — headless command block:**
1. Comment line: `# copies biochemeleon/ -> tmp/bioCHEMeleon/biochemeleon/` → `# copies pymol/biochemeleon/ -> tmp/bioCHEMeleon/biochemeleon/`
2. Staging line: `cp smoke/phase3_smoke.py tmp/bioCHEMeleon/smoke/` → `cp pymol/smoke/phase3_smoke.py tmp/bioCHEMeleon/smoke/`
3. Consequence paragraph: ``biochemeleon/setup_state.py`` → ``pymol/biochemeleon/setup_state.py``
4. wsl2win_cp description: ``wsl2win_cp.sh` copies `biochemeleon/` to `tmp/bioCHEMeleon/`` → ``wsl2win_cp.sh` copies `pymol/biochemeleon/` to `tmp/bioCHEMeleon/``

**Commands section (run from repo root):**
5. py_compile: `python3.6 -m py_compile biochemeleon/*.py` → `python3.6 -m py_compile pymol/biochemeleon/*.py`
6. unittest: `python3.6 -m unittest tests.test_setup_state -v` → `PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state -v`
   - Add/adjust the preceding comment to note: `# (pymol/ is the package root — no pymol/__init__.py, so use PYTHONPATH, not pymol.tests.X)`
7. pitfall-1 grep: the grep target `biochemeleon/` → `pymol/biochemeleon/` (keep the full regex pattern unchanged)
8. exec_ grep: the grep target `biochemeleon/` → `pymol/biochemeleon/`

**Architecture — module dependency diagram (the fenced code block):**
9. Prefix every module path in the diagram with `pymol/biochemeleon/`:
   - `setup_state.py  (PURE...` → `pymol/biochemeleon/setup_state.py  (PURE...`
   - `demos.py        (cmd bridge...` → `pymol/biochemeleon/demos.py        (cmd bridge...`
   - `gui_setup.py    (Qt + cmd...` → `pymol/biochemeleon/gui_setup.py    (Qt + cmd...`
   - The "Phase 3 stack" intro line: `game.py is the composition root` → `pymol/biochemeleon/game.py is the composition root`
   - `registry.py  (PURE...` → `pymol/biochemeleon/registry.py  (PURE...`
   - `backup.py    (cmd:...` → `pymol/biochemeleon/backup.py    (cmd:...`
   - `mutation.py  (cmd:...` → `pymol/biochemeleon/mutation.py  (cmd:...`
   - `game.py      (cmd orchestrator...` → `pymol/biochemeleon/game.py      (cmd orchestrator...`
   - Re-align trailing comments if the longer paths push columns out of alignment (preserve the explanatory text after each path).

**Other path references:**
10. Plugin entry point line: `Plugin entry point and dialog live in `biochemeleon/__init__.py`:` → `pymol/biochemeleon/__init__.py`
11. Tests section: ``tests/test_setup_state.py` stubs` → ``pymol/tests/test_setup_state.py` stubs` (leave the `biochemeleon.*` IMPORT name unchanged — the package name did not change, only its location)
12. Dependencies section: `Bundled demo sources are in `biochemeleon/data/demos/SOURCES.md`.` → `pymol/biochemeleon/data/demos/SOURCES.md`

**Leave unchanged (these are conceptual/import-name/prose references, not file paths):**
- Bare module names in flowing prose (e.g. "`setup_state.py` must have NO `from pymol import cmd`", "`registry.py` (Phase 3) is ALSO pure", "Pure functions → `setup_state.py` + unit tests").
- The `biochemeleon.*` import-name references (package name is unchanged).
- The `tmp/pymol-src/...` references (PyMOL open-source modules — unrelated to this reorg).
- The AGENTS.md scope header note about v2/VMD (chimeraX mentions go in the .planning docs in Task 2, not AGENTS.md).
  </action>
  <verify>
Run these from repo root and confirm the expected results:
  - `grep -nE "(^|[^/])biochemeleon/" AGENTS.md` — should return ZERO lines where `biochemeleon/` is NOT preceded by `pymol/`. (i.e. every `biochemeleon/` path must now be `pymol/biochemeleon/`). Bare prose mentions like ``biochemeleon.*`` (no slash) are fine.
  - `python3.6 -m py_compile pymol/biochemeleon/*.py` — exit 0.
  - `PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state 2>&1 | tail -3` — prints `Ran 125 tests` and `OK`.
  - `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" pymol/biochemeleon/` — zero matches.
  - `grep -rnE "\.exec_\(\)" pymol/biochemeleon/` — 3 hits, all on QFileDialog/QMessageBox dialogs (unchanged behavior, just the path moved).
  </verify>
  <done>
Root AGENTS.md has zero stale bare `biochemeleon/`, `smoke/`, or `tests/` file-path references; all 4 documented commands execute successfully against the `pymol/`-prefixed locations; the architecture diagram shows full `pymol/biochemeleon/` paths.
  </done>
</task>

<task type="auto">
  <name>Task 2: Record chimeraX as a future viewer target + note the reorg in .planning docs</name>
  <files>.planning/STATE.md, .planning/ROADMAP.md, .planning/PROJECT.md</files>
  <action>
Make targeted edits to the three .planning tracking docs so they (a) mention chimeraX as a future viewer target alongside VMD, and (b) note the repo reorg. Use the Edit tool. Do NOT touch the "Quick Tasks Completed" table in STATE.md (the orchestrator manages that separately).

**.planning/STATE.md:**
1. "Current focus" line (line 8): currently `v1 milestone COMPLETE (shipped 2026-08-18). Planning next milestone (v2 — VMD tcl script, deferred per spec.md).` → rewrite to mention the reorg and chimeraX, e.g.:
   `v1 milestone COMPLETE (shipped 2026-08-18). Repo reorganized for multi-viewer support (commit 9ff57f1): v1 PyMOL code now lives under pymol/; vmd/ and chimeraX/ are placeholder dirs. Planning next milestone (v2 — VMD tcl script, deferred per spec.md; chimeraX is a later candidate).`
2. Section header "### Open items for next milestone (v2)" (line 38) → `### Open items for next milestone` (drop the v2-only qualifier since chimeraX is now also in scope).
3. Add a chimeraX bullet to the open-items list (after the VMD bullet), e.g.:
   `- **chimeraX port** — placeholder dir chimeraX/ exists; a later milestone candidate after VMD (v2). Different viewer/extension model than PyMOL and VMD; research needed when it becomes active.`
4. Add a one-line reorg note to the open-items area, e.g.:
   `- **Repo reorg (2026-08-19, commit 9ff57f1):** v1 code moved under pymol/ (biochemeleon/, smoke/, tests/); vmd/ and chimeraX/ placeholders added. Root AGENTS.md paths updated to pymol/-prefixed layout.`
5. If the "AGENTS.md needs VMD/tcl-specific rewrite" bullet exists, leave it (still true — it's VMD-specific; a chimeraX-specific rewrite would be a separate future concern).

**.planning/ROADMAP.md:**
6. The trailing line (line 8): `*Next milestone: run `/gsd-new-milestone` (v2 — VMD tcl script, deferred per spec.md)*` → add chimeraX as a later candidate, e.g.:
   `*Next milestone: run `/gsd-new-milestone` (v2 — VMD tcl script, deferred per spec.md; chimeraX port is a later milestone candidate — placeholder dir chimeraX/ exists).*`

**.planning/PROJECT.md:**
7. Line 5: `A "hide-and-seek" game played on molecular structures inside PyMOL (v1 shipped) and VMD (v2 deferred).` → add chimeraX, e.g.:
   `A "hide-and-seek" game played on molecular structures inside PyMOL (v1 shipped), VMD (v2 deferred), and chimeraX (future candidate).`
8. "Next milestone" line (line 71): `**Next milestone:** v2 — VMD tcl script (deferred per spec.md). Run `/gsd-new-milestone`.` → append chimeraX note for consistency, e.g.:
   `**Next milestone:** v2 — VMD tcl script (deferred per spec.md); chimeraX port is a later candidate (placeholder dir chimeraX/ exists). Run `/gsd-new-milestone`.`

Do NOT add chimeraX to the "Active" requirements section (no requirements defined for it yet — it's only a candidate). Do NOT modify the v1-shipped requirements, Key Decisions table, or Constraints.
  </action>
  <verify>
  - `grep -ni "chimeraX" .planning/STATE.md .planning/ROADMAP.md .planning/PROJECT.md` — each of the 3 files returns at least one chimeraX mention.
  - `grep -ni "pymol/" .planning/STATE.md` — the reorg note references the pymol/ layout.
  - Confirm the "Quick Tasks Completed" table in STATE.md is unchanged (still exactly 2 rows: 003 and 004).
  - Read the edited sections to confirm the chimeraX language is consistent across all three docs (VMD = v2 deferred; chimeraX = later candidate).
  </verify>
  <done>
STATE.md, ROADMAP.md, and PROJECT.md each mention chimeraX as a future viewer candidate alongside VMD; STATE.md records the repo reorg (code under pymol/); the Quick Tasks Completed table in STATE.md is untouched; language is consistent across all three docs.
  </done>
</task>

</tasks>

<verification>
After both tasks:
- `grep -rnE "biochemeleon/" AGENTS.md` — every hit is `pymol/biochemeleon/` (no bare `biochemeleon/` path). Bare ``biochemeleon.*`` import-name references (no slash) are acceptable.
- The 4 AGENTS.md commands run green from repo root (py_compile exit 0; unittest 125 OK; pitfall grep 0 matches; exec_ grep 3 expected hits).
- `grep -ni "chimeraX" .planning/STATE.md .planning/ROADMAP.md .planning/PROJECT.md` — all 3 files mention chimeraX.
- STATE.md Quick Tasks Completed table unchanged (2 rows).
- Commit with: `docs(quick-007): update tracking docs for multi-viewer repo structure` (commit_docs: true).
</verification>

<success_criteria>
- Root AGENTS.md paths reflect the pymol/ layout and all 4 documented commands execute successfully.
- STATE.md, ROADMAP.md, and PROJECT.md mention chimeraX as a future viewer candidate; STATE.md notes the reorg.
- No code or test files modified; no behavior change.
- Single commit `docs(quick-007): ...`.
</success_criteria>

<output>
After completion, create `.planning/quick/007-update-tracking-docs-multiviewer/007-SUMMARY.md` following the quick-summary frontmatter convention (see `.planning/quick/004-*/004-SUMMARY.md` for the format: phase/plan/type/files_modified/commits frontmatter + What/Why/Files Changed sections).
</output>
