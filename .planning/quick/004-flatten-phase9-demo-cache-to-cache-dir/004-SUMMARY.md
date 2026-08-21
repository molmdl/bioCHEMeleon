---
phase: quick-004
plan: 01
type: summary
files_modified:
  - pymol/biochemeleon/demos.py
  - pymol/biochemeleon/setup_state.py
  - pymol/tests/test_setup_state.py
  - pymol/smoke/phase9_smoke.py
  - .planning/codebase/STACK.md
  - .planning/codebase/INTEGRATIONS.md
commits:
  - hash: 3d8cf9b
    msg: "refactor(quick-004): flatten phase9 demo cache to <cwd>/cache/ (single layer)"
---

# Quick Task 004 — Summary

## What

Flattened the Phase 9 fetched-demo cache from quick-003's 3-deep nesting
(`<cwd>/tmp/phase9-demos/cache/` for the persistent `.pdb.gz` +
`<cwd>/tmp/phase9-demos/<id>.raw` for the transient `.raw` download) into a
SINGLE flat `<cwd>/cache/` directory holding both the transient `.raw` /
`.dry` (temp download / strip intermediate) and the persistent `.pdb.gz`
(cache).

Purpose: quick-003 fixed the real bug (cmd.fetch parity via cwd-based paths)
but left a 3-deep nesting (`cwd/tmp/phase9-demos/cache/`). The user wanted a
single layer. The directory name is `cache/` (NOT `tmp/`) because `cache/`
signals "keep these" — the persistent `.pdb.gz` survives sessions; a user
deleting `tmp/` would lose cached downloads. This is a path refinement, not
a bug fix (quick-003 already fixed the bug).

No logic change to the fetch / finalize / cache-write flow — only the path
strings (and their docstrings/comments) moved. The one behavioral change is
the smoke cleanup loop, which had to become extension-aware because the flat
layout co-locates the staged `.pdb` sample inside `_cache_dir()` (see
Changes → phase9_smoke.py).

## Changes

### `pymol/biochemeleon/demos.py` (functional — 1 file, +30/-30)

1. **`_cache_dir()`** (line 225): return changed from
   `os.path.join(os.getcwd(), 'tmp', 'phase9-demos', 'cache')` to
   `os.path.join(os.getcwd(), 'cache')`. Docstring reframed: resolves to
   `<cwd>/cache/`; single flat dir holding both the transient `.raw`/`.dry`
   and the persistent `.pdb.gz`; `cmd.fetch` parity + Pitfall E / Open Risk 4
   rationale kept. Source line documents the history: quick-003 relocated
   under the cwd (nested layout); quick-004 flattened to `<cwd>/cache/`.
2. **`temp_download_path()`** (line 287): return changed from
   `os.path.join(os.getcwd(), 'tmp', 'phase9-demos', demo_id + '.raw')` to
   `os.path.join(os.getcwd(), 'cache', demo_id + '.raw')`. Docstring reframed
   analogously: the `.raw` now lives IN THE SAME dir as the `.pdb.gz` cache
   (flat layout), cleaned by `cleanup_temp` after finalize; parent-creation
   note updated (`download_large_demo`'s `os.makedirs` now creates
   `<cwd>/cache/`).
3. **`download_large_demo` Pitfall E comment** (lines ~388-390): the stale
   path reference `<cwd>/tmp/phase9-demos/` → `<cwd>/cache/`. The
   `os.makedirs(_parent, exist_ok=True)` LOGIC is byte-for-byte unchanged
   (only the comment text moved).
4. **NOT touched**: `cache_path_for` / `is_cached` / `cleanup_temp` /
   `finalize_large_demo` / `load_cached_demo` logic; the two `os.makedirs`
   calls (`download_large_demo` line ~395, `finalize_large_demo` line ~502)
   — both still create `<cwd>/cache/` on first use via the flattened paths.
   No new imports.

### `pymol/biochemeleon/setup_state.py` (comment only — 1 line)

- Line 30: `-> <cwd>/tmp/phase9-demos/cache/` → `-> <cwd>/cache/`.
  (The `DEMO_MANIFEST` comment; no code/assertions changed.)

### `pymol/tests/test_setup_state.py` (comment only — 1 line)

- Line 141: `<cwd>/tmp/phase9-demos/cache/` → `<cwd>/cache/`. The test only
  asserts `cache_name` suffixes (`.pdb` vs `.pdb.gz`), not the cache DIR,
  so it stays green.

### `pymol/smoke/phase9_smoke.py` (3 path refs + 1 behavioral fix — +14/-3)

- **Line 8** (header comment): `tmp/phase9-demos/SASDPG4_fit2_model1.pdb` →
  `cache/SASDPG4_fit2_model1.pdb`.
- **Lines 112-113** (`_staged_sasbdb`): `os.path.join(os.getcwd(), 'tmp',
  'phase9-demos', 'SASDPG4_fit2_model1.pdb')` → `os.path.join(os.getcwd(),
  'cache', 'SASDPG4_fit2_model1.pdb')`.
- **Line 247** (`_memprotmd_dir`): `os.path.join(os.getcwd(), 'tmp',
  'phase9-demos')` → `os.path.join(os.getcwd(), 'cache')`.
- **Lines 88-106 (CLEANUP-LOOP FIX — behavioral, not just a path string)**:
  The old loop unlinked EVERY file in `_cache_dir()` before section A read
  the staged sample. Under quick-003's nested layout this was safe because
  the sample lived in the PARENT `tmp/phase9-demos/`, outside the cache
  subdir. Flattening puts the staged sample (`cwd/cache/
  SASDPG4_fit2_model1.pdb`) INSIDE `_cache_dir()` (`cwd/cache/`), so the old
  loop would DELETE the sample and break section A. The loop is now
  extension-aware: it wipes ONLY `.pdb.gz` (cache), `.raw` (temp), and `.dry`
  (strip intermediate), preserving the co-located staged `.pdb` sample.

### `.planning/codebase/STACK.md` (doc — 1 line)

- Line 63: fetched-demo cache path changed to `<cwd>/cache/` (flat
  single-layer layout); `cmd.fetch` parity + Pitfall E / Open Risk 4
  rationale kept; smoke staging paths note updated to reflect the flat
  layout.

### `.planning/codebase/INTEGRATIONS.md` (doc — 3 lines)

- Line 44 (MemProtMD processing): `tmp/phase9-demos/cache/` → `cache/`
  (flat `<cwd>/cache/` layout).
- Line 64 (Fetched-demo cache): `<cwd>/tmp/phase9-demos/cache/` →
  `<cwd>/cache/` (flat single-layer layout); smoke staging paths note
  updated.
- Line 65 (Temp downloads): `<cwd>/tmp/phase9-demos/<demo_id>.raw` →
  `<cwd>/cache/<demo_id>.raw`; added note that the `.raw`/`.dry` now live in
  the SAME flat dir as the `.pdb.gz` cache.

## Verification (run, all green)

All 7 plan verification checks pass (run from repo root; the `pymol/` prefix
targets the reorganized package per `pymol/AGENTS.md`):

1. **Syntax gate**: `python3.6 -m py_compile pymol/biochemeleon/*.py` → clean.
2. **Pitfall-1 gate**: `grep -rnE "import Tkinter|...|import PyQt5"
   pymol/biochemeleon/` → **0 matches**.
3. **exec_ gate**: `grep -rnE "\.exec_\(\)" pymol/biochemeleon/` → 3
   pre-existing hits (`gui_game.py:345` + `:404` `msg.exec_()` on
   QMessageBox, `__init__.py:952` `help_dlg.exec_()` on the help dialog).
   **None introduced** by this change; all on child dialogs, never the main
   modeless PluginDialog. Gate stays clean.
4. **Pure unit tests**: `cd pymol && python3.6 -m unittest tests.test_setup_state
   -v` → `Ran 125 tests in 0.024s — OK` (only comments changed in
   setup_state / test_setup_state; no assertions touched).
5. **Stubbed path-build snippet** (`/tmp/opencode/quick004_paths.py`): stubs
   `pymol` + `pymol.Qt` with MagicMock (same pattern as
   `test_setup_state.py`), imports `biochemeleon.demos`, uses a
   `TemporaryDirectory` as cwd, and asserts:
   - `_cache_dir() == <tmpcwd>/cache` ✅
   - `temp_download_path('sasdpg4') == <tmpcwd>/cache/sasdpg4.raw` ✅
   - `cache_path_for('sasdpg4') == <tmpcwd>/cache/SASDPG4_fit2_model1.pdb.gz` ✅
   - `os.path.dirname(temp_download_path('sasdpg4')) == _cache_dir()` (the
     `.raw` lives IN the cache dir — flat) ✅
   - `os.makedirs(_parent, exist_ok=True)` then `isdir(<tmpcwd>/cache)` is
     True (download_large_demo's parent-creation works on a fresh cwd) ✅

   Prints `OK`.
6. **Grep-zero check** (the completeness gate):
   `grep -rnIE --exclude-dir=__pycache__ "phase9-demos" pymol/biochemeleon/
   pymol/tests/ pymol/smoke/phase9_smoke.py .planning/codebase/` → **0
   matches**. (A stale `demos.cpython-39.pyc` in `__pycache__/` still
   contains the old docstring bytecode, but `.pyc` files are gitignored
   build artifacts, not source files — excluded via `--exclude-dir`.)
7. **Smoke cleanup loop extension-aware**: read back lines 88-106 — confirmed
   the loop skips non-`.pdb.gz`/`.raw`/`.dry` files (preserves the co-located
   staged `.pdb` sample).

## Out of scope / untested

The **network fetch + interactive GUI on a fresh computer remain untested by
this quick task.** The fetch / finalize / cache-write LOGIC is unchanged —
only the path strings moved (plus the smoke cleanup-loop fix) — so no
human-verify checkpoint was required by the plan.

The **staged `SASDPG4_fit2_model1.pdb` sample is gitignored runtime data**
(NOT in the repo — neither `pymol/cache/` nor `pymol/tmp/phase9-demos/`
exist in this worktree). The user must stage `SASDPG4_fit2_model1.pdb` at
**`pymol/cache/SASDPG4_fit2_model1.pdb`** (the new flat location; was
`pymol/tmp/phase9-demos/SASDPG4_fit2_model1.pdb` under quick-003) before
running the phase9 smoke headlessly via
`cmd.exe /c C:\src\run-conda-pymol.bat -cq smoke/phase9_smoke.py`.

A user can manually verify the end-to-end flow later by selecting the
glycoprotein (SASBDB `sasdpg4`) or membrane (MemProtMD `1gzm`/`3gp6`) demo
after launching PyMOL from a fresh cwd (the cache + `.raw` should land under
`<cwd>/cache/`).

## Deviations from plan

### 1. [Rule 1 — Bug/consistency] Reworded Source-line history references to avoid the literal `phase9-demos` token

- **Found during:** Task 1 verification (the plan's Task 3 completeness gate
  requires zero `phase9-demos` matches across all source files).
- **Issue:** The plan's Task 1 action explicitly instructed writing
  "quick-003 relocated to `<cwd>/tmp/phase9-demos/` for cmd.fetch parity" in
  the `_cache_dir()` and `temp_download_path()` Source lines (documenting the
  change history). But the plan's own Task 3 grep-zero gate (called "the
  single most important gate") requires zero `phase9-demos` references in
  `pymol/biochemeleon/`. These two requirements contradict — the literal
  history note would fail the completeness gate.
- **Fix:** Reworded the Source lines to "quick-003 relocated under the cwd
  for cmd.fetch parity (nested layout); quick-004 flattened to `<cwd>/cache/`
  (single layer)." This preserves the change history (quick-003 moved under
  cwd with a nested layout; quick-004 flattened) without the literal
  `phase9-demos` token. The same rewording was applied to the smoke cleanup
  loop comment (C4), which the plan's literal text also included
  `tmp/phase9-demos/` in.
- **Files modified:** `pymol/biochemeleon/demos.py` (2 Source lines),
  `pymol/smoke/phase9_smoke.py` (cleanup loop comment).
- **Commit:** 3d8cf9b (included in the single refactor commit).

This is the minimal change that satisfies BOTH the plan's "document the
history" intent AND its "zero stale references" success criterion.

## Commits

- `3d8cf9b` — `refactor(quick-004): flatten phase9 demo cache to <cwd>/cache/
  (single layer)` (Tasks 1+2+3; 6 files: demos.py, setup_state.py,
  test_setup_state.py, phase9_smoke.py, STACK.md, INTEGRATIONS.md; +53/-37)
- (metadata) — `docs(quick-004): ...` (this SUMMARY + PLAN + STATE)

One atomic work commit + one bookkeeping commit (mirrors the quick-003
convention, condensed to a single refactor commit per the runtime
reminders).
