---
phase: quick-002
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - AGENTS.md
autonomous: true

must_haves:
  truths:
    - "AGENTS.md documents no `rg` (ripgrep) bash commands — only `grep -rnE`"
    - "The Pitfall-1 gate command runs in the WSL shell and returns 0 matches (green)"
    - "The exec_ gate command runs in the WSL shell and returns 1 match on a QMessageBox (green)"
  artifacts:
    - path: "AGENTS.md"
      provides: "Runnable grep-based verification gates (rg unavailable in env)"
      contains: "grep -rnE"
  key_links: []
---

<objective>
Replace the `rg` (ripgrep) invocations in AGENTS.md with `grep -rnE`, because
`rg` is denied in `opencode.json` and is not installed in the WSL dev shell. The
documented verification gates must be copy-pasteable and runnable.

Purpose: AGENTS.md is the first thing an OpenCode session reads. Its "Commands"
section is meant to be run verbatim. `rg` was never available here — executors
have always substituted `grep` at runtime (see 02-01/02-02/02-03/05-03 SUMMARYs);
this makes the doc match reality.
Output: 3-line edit to AGENTS.md (two gate commands + the trailing note).
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Replace rg with grep -rnE in AGENTS.md Commands section</name>
  <files>AGENTS.md</files>
  <action>
In the "## Commands (run from repo root)" section of AGENTS.md:

1. Replace the **Pitfall-1 gate** command
   `rg -n "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/`
   with
   `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/`
   (same pattern, same path). `grep -rnE` = recursive (-r) + line numbers (-n) +
   extended regex (-E); ERE handles the `|` alternation and the `\.`/`\(`/`\)`
   escapes identically to the original `rg` patterns.

2. Replace the **exec_ gate** command
   `rg -n "\.exec_\(\)" biochemeleon/`
   with
   `grep -rnE "\.exec_\(\)" biochemeleon/`.

3. Update the **trailing note** (the paragraph after the closing ``` fence):
   change "Prefer the Grep tool over `rg` in bash (`rg *` is denied in
   `opencode.json`)." to "Prefer the Grep tool over bash `grep` for content
   searches; `rg` is denied in `opencode.json` (the `grep -rnE` commands above
   are the runnable equivalent)."

Do NOT touch the historical `rg` references in `.planning/phases/**`
(PLAN/SUMMARY/RESEARCH artifacts) — those are historical records; the project
precedent keeps them as-is and executors substituted `grep` at runtime.
Do NOT change the gate patterns themselves — only the command prefix
(`rg -n` → `grep -rnE`).
  </action>
  <verify>
- `grep -nE '^\s*rg -' AGENTS.md` → 0 matches (no `rg` command lines remain).
- `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/` → 0 matches (Pitfall-1 green).
- `grep -rnE "\.exec_\(\)" biochemeleon/` → exactly 1 match, and that match is on a QMessageBox/QFileDialog (per the existing AGENTS.md rule), NOT the main PluginDialog/SetupTab.
  </verify>
  <done>
AGENTS.md "Commands" section uses `grep -rnE` (not `rg`); both gates run and
return the documented green state (Pitfall-1 = 0 matches, exec_ = 1 hit on a
QMessageBox).
  </done>
</task>

</tasks>

<verification>
- `grep -nE '^\s*rg -' AGENTS.md` returns nothing.
- Pitfall-1 gate (`grep -rnE ... biochemeleon/`) returns 0 matches.
- exec_ gate (`grep -rnE "\.exec_\(\)" biochemeleon/`) returns 1 match, on a
  QMessageBox (allowed), not the main PluginDialog/SetupTab.
</verification>

<success_criteria>
- AGENTS.md has no `rg` bash invocations.
- Documented gate commands are runnable in the WSL env and return the green state.
- No other files changed.
</success_criteria>

<output>
After completion, create `.planning/quick/002-fix-rg-to-grep-in-agents-md/002-SUMMARY.md`
</output>
