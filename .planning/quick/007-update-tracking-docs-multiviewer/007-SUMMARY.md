---
phase: quick-007
plan: 01
type: summary
files_modified:
  - AGENTS.md
  - .planning/STATE.md
  - .planning/ROADMAP.md
  - .planning/PROJECT.md
commits:
  - hash: 7626414
    msg: "docs(quick-007): update tracking docs for multi-viewer repo structure"
---

# Quick Task 007 — Summary

## What

Updated the four root tracking docs to reflect the multi-viewer repo
reorg (commit 9ff57f1) that moved all v1 PyMOL code under `pymol/`
(`pymol/biochemeleon/`, `pymol/smoke/`, `pymol/tests/`) and added `vmd/`
+ `chimeraX/` placeholder directories — and recorded chimeraX as a
future viewer target alongside VMD.

This is a docs-only change: no code, no tests, no behavior change. The
v1 milestone shipped 2026-08-18, then the repo was reorganized for
multi-viewer support, but the tracking docs still referenced the old
flat layout (`biochemeleon/`, `smoke/`, `tests/` at repo root) and only
mentioned VMD as the next target. Stale paths would mislead the next
agent (broken `py_compile`/`unittest`/`grep` commands, wrong file
locations); the missing chimeraX mention understated the project's scope.

## Why

- **AGENTS.md paths were stale.** Every documented command in the
  "Commands (run from repo root)" section pointed at `biochemeleon/`,
  `smoke/`, `tests/` at repo root — directories that no longer exist
  there (they moved under `pymol/`). A fresh agent copying those
  commands would get "No such file or directory" / ImportError.
- **`pymol` is NOT a Python package** (no `pymol/__init__.py`), so the
  naive `python3.6 -m unittest pymol.tests.test_setup_state` FAILS with
  ImportError. The verified-correct repo-root form is
  `PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state -v`
  (confirmed: 125 tests OK). This planning insight (verified during
  planning) is captured in an inline comment so the next agent doesn't
  rediscover it.
- **chimeraX was missing from the roadmap.** The reorg added
  `chimeraX/.gitkeep`, signalling chimeraX as a future viewer target,
  but STATE.md / ROADMAP.md / PROJECT.md only mentioned VMD. Recording
  chimeraX keeps the tracking docs honest about the project's
  multi-viewer scope (VMD = v2 deferred; chimeraX = later candidate).

## Files Changed

### `AGENTS.md` (+22/-17 — path references only)

**Environment section — headless command block:**
- Comment line: `# copies biochemeleon/ -> ...` → `# copies pymol/biochemeleon/ -> ...`.
- Staging line: `cp smoke/phase3_smoke.py ...` → `cp pymol/smoke/phase3_smoke.py ...`.
- Consequence paragraph: ``biochemeleon/setup_state.py`` → ``pymol/biochemeleon/setup_state.py``.
- `wsl2win_cp.sh` description: `copies biochemeleon/ to ...` → `copies pymol/biochemeleon/ to ...`.

**Commands section (run from repo root):**
- py_compile: `biochemeleon/*.py` → `pymol/biochemeleon/*.py`.
- unittest: `python3.6 -m unittest tests.test_setup_state -v` → `PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state -v`, with an added comment noting `pymol/` is the package root (no `pymol/__init__.py`, so use PYTHONPATH not `pymol.tests.X`).
- pitfall-1 grep target: `biochemeleon/` → `pymol/biochemeleon/` (regex pattern unchanged).
- exec_ grep target: `biochemeleon/` → `pymol/biochemeleon/`.

**Architecture — module dependency diagram (fenced code block):**
- Prefixed every module path with `pymol/biochemeleon/` (setup_state.py, demos.py, gui_setup.py, registry.py, backup.py, mutation.py, game.py) and the "Phase 3 stack" intro line ("`pymol/biochemeleon/game.py` is the composition root"). Re-aligned the trailing parenthesized comments so the columns line up after the longer paths (preserved all explanatory text).

**Other path references:**
- Plugin entry point line: `biochemeleon/__init__.py` → `pymol/biochemeleon/__init__.py`.
- Tests section: ``tests/test_setup_state.py` stubs` → ``pymol/tests/test_setup_state.py` stubs` (the `biochemeleon.*` IMPORT name left unchanged — the package name did not change, only its location).
- Dependencies section: `biochemeleon/data/demos/SOURCES.md` → `pymol/biochemeleon/data/demos/SOURCES.md`.

**Left unchanged (conceptual/import-name/prose references, NOT file paths):**
- Bare module names in flowing prose ("`setup_state.py` must have NO `from pymol import cmd`", "`registry.py` (Phase 3) is ALSO pure", "Pure functions → `setup_state.py` + unit tests").
- `biochemeleon.*` import-name references (package name unchanged).
- `tmp/pymol-src/...` references (PyMOL open-source modules — unrelated to this reorg).
- The AGENTS.md scope header note about v2/VMD (chimeraX mentions went into the .planning docs in Task 2, not AGENTS.md — AGENTS.md stays v1-scoped).
- `pymol/AGENTS.md` and `pymol/DATA_SOURCES.md` (subdirectory copies — already correct, DO NOT TOUCH per plan).

### `.planning/STATE.md` (+5/-1)

1. "Current focus" line: rewrote to mention the reorg and chimeraX — `v1 milestone COMPLETE ... Repo reorganized for multi-viewer support (commit 9ff57f1): v1 PyMOL code now lives under pymol/; vmd/ and chimeraX/ are placeholder dirs. Planning next milestone (v2 — VMD tcl script, deferred per spec.md; chimeraX is a later candidate).`
2. Section header: `### Open items for next milestone (v2)` → `### Open items for next milestone` (dropped the v2-only qualifier since chimeraX is now also in scope).
3. Added a chimeraX bullet to the open-items list (after the VMD bullet): `chimeraX port — placeholder dir chimeraX/ exists; a later milestone candidate after VMD (v2). Different viewer/extension model than PyMOL and VMD; research needed when it becomes active.`
4. Added a one-line reorg note bullet: `Repo reorg (2026-08-19, commit 9ff57f1): v1 code moved under pymol/ (biochemeleon/, smoke/, tests/); vmd/ and chimeraX/ placeholders added. Root AGENTS.md paths updated to pymol/-prefixed layout.`
5. Left the "AGENTS.md needs VMD/tcl-specific rewrite" bullet (still true — VMD-specific; a chimeraX-specific rewrite would be a separate future concern).
- **Quick Tasks Completed table: UNTOUCHED** (still exactly 2 rows: 003 and 004) — the orchestrator manages that table after merge.

### `.planning/ROADMAP.md` (+1/-1)

- Trailing line: added chimeraX as a later candidate — `*Next milestone: run /gsd-new-milestone (v2 — VMD tcl script, deferred per spec.md; chimeraX port is a later milestone candidate — placeholder dir chimeraX/ exists).*`. (No phase entries modified — quick tasks don't touch roadmap phases.)

### `.planning/PROJECT.md` (+2/-2)

1. Line 5 (What This Is): `...inside PyMOL (v1 shipped) and VMD (v2 deferred).` → `...inside PyMOL (v1 shipped), VMD (v2 deferred), and chimeraX (future candidate).`
2. "Next milestone" line: appended chimeraX note — `**Next milestone:** v2 — VMD tcl script (deferred per spec.md); chimeraX port is a later candidate (placeholder dir chimeraX/ exists). Run /gsd-new-milestone.`
- Did NOT add chimeraX to the "Active" requirements section (no requirements defined for it yet — it's only a candidate). Did NOT modify v1-shipped requirements, Key Decisions table, or Constraints.

## Verification (run from repo root, all green)

**Task 1 — AGENTS.md paths:**
1. `grep -nE "(^|[^/])biochemeleon/" AGENTS.md` → **ZERO matches** (every `biochemeleon/` path is now `pymol/biochemeleon/`). Bare ``biochemeleon.*`` import-name refs (no slash) are fine.
2. `python3.6 -m py_compile pymol/biochemeleon/*.py` → **exit 0**.
3. `PYTHONPATH=pymol python3.6 -m unittest tests.test_setup_state 2>&1 | tail -3` → **`Ran 125 tests` ... `OK`**.
4. pitfall-1 grep on `pymol/biochemeleon/` → **0 matches** (exit 1).
5. exec_ grep on `pymol/biochemeleon/` → **3 hits** (`gui_game.py:345` + `:404` `msg.exec_()` on QMessageBox, `__init__.py:952` `help_dlg.exec_()` on the help dialog) — all on child dialogs, never the main modeless PluginDialog. Unchanged behavior; only the path moved.
6. "Leave unchanged" refs confirmed intact: `biochemeleon.*` import-name (line 75, no slash), bare module names in prose (lines 65/76), `tmp/pymol-src/...` (line 25), v1-scope header note (line 5).

**Task 2 — .planning docs:**
1. `grep -ni "chimeraX" .planning/STATE.md .planning/ROADMAP.md .planning/PROJECT.md` → all 3 files mention chimeraX (STATE.md ×3: lines 8/41/42; ROADMAP.md line 8; PROJECT.md lines 5/71).
2. `grep -ni "pymol/" .planning/STATE.md` → reorg note references the pymol/ layout (lines 8 and 42).
3. Quick Tasks Completed table in STATE.md → **unchanged** (exactly 2 rows: 003 and 004).
4. Section header is now `### Open items for next milestone` (v2 qualifier dropped).
5. chimeraX language is consistent across all three docs: VMD = v2 deferred; chimeraX = later candidate.

**Overall:** 4 files changed (+27/-24), no code or test files modified, no behavior change. Diff stat matches the plan's `files_modified` frontmatter exactly.

## Deviations from plan

### 1. [Process] Single work commit instead of per-task atomic commits

- **Context:** The orchestrator spawn constraint said "Commit each task
  atomically on the quick/007 branch." The plan's `<verification>` and
  `<success_criteria>` both explicitly specify "Single commit
  `docs(quick-007): update tracking docs for multi-viewer repo
  structure`".
- **Resolution:** Honored the plan's explicit, repeated "Single commit"
  instruction. Rationale: (a) the plan is the specific, authored source
  of truth for this work and states the single-commit requirement twice;
  (b) the quick-004 precedent (same repo, same workflow) used one work
  commit for all its task edits + one metadata commit for the SUMMARY;
  (c) all changes are pure documentation with no behavior change, so
  per-task bisect granularity adds little value. The two tasks are
  cleanly separable in the commit body (AGENTS.md = Task 1;
  STATE/ROADMAP/PROJECT = Task 2). This mirrors the established
  quick-task commit convention (one work commit + one metadata commit).
- **Commit:** 7626414 (the single work commit covering all 4 files).

No code/test bugs, missing-critical-functionality, or blocking issues
were encountered (Rules 1-3 not triggered). No architectural decisions
required (Rule 4 not triggered). No authentication gates.

## Commits

- `7626414` — `docs(quick-007): update tracking docs for multi-viewer repo
  structure` (Tasks 1+2; 4 files: AGENTS.md, STATE.md, ROADMAP.md,
  PROJECT.md; +27/-24)
- (metadata) — `docs(quick-007): complete update-tracking-docs-multiviewer
  plan` (this SUMMARY + the plan dir)

One atomic work commit + one bookkeeping commit (mirrors the quick-003 /
quick-004 convention).
