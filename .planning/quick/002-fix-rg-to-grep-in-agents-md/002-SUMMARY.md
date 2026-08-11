---
phase: quick-002
plan: 01
type: summary
files_modified:
  - AGENTS.md
commits:
  - hash: f78a9b7
    msg: "docs(quick-002): replace rg with grep -rnE in AGENTS.md"
---

# Quick Task 002 — Summary

## What

Replaced the two `rg` (ripgrep) invocations in AGENTS.md's "Commands (run from
repo root)" section with `grep -rnE`, and updated the trailing note. `rg` is
denied in `opencode.json` and not installed in the WSL dev shell; the documented
gates were never runnable as-written (executors have always substituted `grep`
at runtime — see 02-01/02-02/02-03/05-03 SUMMARYs). This makes the doc match
reality.

## Changes (AGENTS.md, 3 lines)

1. **Pitfall-1 gate** —
   `rg -n "import Tkinter|...|import PyQt5" biochemeleon/`
   →
   `grep -rnE "import Tkinter|...|import PyQt5" biochemeleon/`
2. **exec_ gate** —
   `rg -n "\.exec_\(\)" biochemeleon/`
   →
   `grep -rnE "\.exec_\(\)" biochemeleon/`
3. **Trailing note** — "Prefer the Grep tool over `rg` in bash (`rg *` is denied
   in `opencode.json`)." → "Prefer the Grep tool over bash `grep` for content
   searches; `rg` is denied in `opencode.json` (the `grep -rnE` commands above
   are the runnable equivalent)."

`grep -rnE` = recursive (-r) + line numbers (-n) + extended regex (-E). ERE
handles the `|` alternation and the `\.`/`\(`/`\)` escapes identically to the
original `rg` patterns. The gate patterns themselves were NOT changed — only
the command prefix (`rg -n` → `grep -rnE`).

## Verification (run, all green)

- `grep -nE '^\s*rg -' AGENTS.md` → **0 matches** (no `rg` command lines remain
  in AGENTS.md).
- Pitfall-1 gate: `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/`
  → **0 matches** (green, exit 1).
- exec_ gate: `grep -rnE "\.exec_\(\)" biochemeleon/` → **1 match** at
  `biochemeleon/gui_game.py:271: msg.exec_()`, where
  `msg = QtWidgets.QMessageBox(...)` (line 266). This is the win-dialog
  QMessageBox — explicitly ALLOWED by the AGENTS.md rule ("any hits must be on
  QFileDialog/QMessageBox, NEVER on the main PluginDialog/SetupTab"). Gate stays
  green at 1, consistent with the long-documented `exec_=1` state.

## Out of scope (intentionally NOT changed)

- Historical `rg` references in `.planning/phases/**`
  (PLAN/SUMMARY/RESEARCH artifacts) were left untouched. These are historical
  records of what was planned/executed at the time; the project precedent
  (02-01/02-02/02-03/05-03 SUMMARYs) is that `rg` in plan docs is substituted
  with `grep` at runtime, and the docs are kept as-is. Changing them would
  rewrite history without value.
- The gate patterns themselves were not changed — only the command prefix
  (`rg -n` → `grep -rnE`).

## Deviations from plan

None. The plan was executed verbatim.

## Commit

`f78a9b7` — `docs(quick-002): replace rg with grep -rnE in AGENTS.md`
Single atomic work commit, only `AGENTS.md` staged (1 file changed, 3
insertions, 3 deletions). Planning docs + STATE row committed in a separate
bookkeeping commit (mirrors quick-001's two-commit pattern: work commit + plan
commit).
