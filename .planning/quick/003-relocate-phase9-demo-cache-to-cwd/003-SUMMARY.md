---
phase: quick-003
plan: 01
type: summary
files_modified:
  - pymol/biochemeleon/demos.py
  - pymol/biochemeleon/setup_state.py
  - pymol/tests/test_setup_state.py
  - .planning/codebase/STACK.md
  - .planning/codebase/INTEGRATIONS.md
commits:
  - hash: 5041541
    msg: "fix(quick-003): relocate fetched-demo cache + temp paths to cwd"
  - hash: 882de84
    msg: "docs(quick-003): update codebase docs for cwd-based demo cache"
---

# Quick Task 003 — Summary

## What

Relocated the Phase 9 fetched-demo cache + temp-download path BASE from the
per-user home directory (`~/.biochemeleon/`) to the current working directory
(`<cwd>/tmp/phase9-demos/`), for parity with `cmd.fetch` (which downloads PDBs
into the cwd) and with the Phase 9 smoke test, which already stages under
`os.path.join(os.getcwd(), 'tmp', 'phase9-demos')` (smoke lines 103 + 237).
The prior `~/.biochemeleon/` fix (commit e8ea659) had diverged from that smoke
layout. This realigns the helpers to a single source of truth: the dev-repo
smoke, an installed plugin, and a user running PyMOL from their project dir
all now agree on the cache location.

No logic change to the fetch / finalize / cache-write flow — only the path
BASE moved. `_app_dir()` (the `~/.biochemeleon` resolver) was removed entirely;
its two callers were rewritten to build paths from `os.getcwd()`.

## Changes

### `pymol/biochemeleon/demos.py` (functional — 1 file, +32/-56)

1. **Removed `_app_dir()`** (was lines 203-228). It returned
   `os.path.join(os.path.expanduser('~'), '.biochemeleon')` and was the sole
   source of the `~/.biochemeleon/` base. After rewriting its two callers
   there are zero dangling references.
2. **Rewrote `_cache_dir()`**: `return os.path.join(_app_dir(), 'cache')` →
   `return os.path.join(os.getcwd(), 'tmp', 'phase9-demos', 'cache')`.
   Docstring reframed: resolves to `<cwd>/tmp/phase9-demos/cache/`
   (consistent with `cmd.fetch`); persists across sessions launched from the
   same dir (the same limitation `cmd.fetch` has — acceptable for v1); created
   on first finalize by `finalize_large_demo`'s `os.makedirs(cache_dir,
   exist_ok=True)`. The Pitfall E / Open Risk 4 note is reframed to the
   cwd / smoke / fetch framing (the stale `~/.biochemeleon/` references were
   dropped).
3. **Rewrote `temp_download_path()`**: `return os.path.join(_app_dir(), 'tmp',
   demo_id + '.raw')` → `return os.path.join(os.getcwd(), 'tmp',
   'phase9-demos', demo_id + '.raw')`. Docstring reframed analogously (same
   cwd-based base as `_cache_dir()`).
4. **`download_large_demo`** and **`finalize_large_demo`** makedirs LOGIC
   untouched — only the stale path comment inside `download_large_demo` was
   updated (see Deviations). `to_windows_path()` (lines 59-78) was read and
   verified, not edited (see Verification).

### `pymol/biochemeleon/setup_state.py` (comment only — 1 line)

- Line ~30: `-> ~/.biochemeleon/cache/` → `-> <cwd>/tmp/phase9-demos/cache/`.
  (The `DEMO_MANIFEST` comment; no code/assertions changed.)

### `pymol/tests/test_setup_state.py` (comment only — 1 line)

- Line ~141: `~/.biochemeleon/cache/` → `<cwd>/tmp/phase9-demos/cache/`. The
  test only asserts `cache_name` suffixes (`.pdb` vs `.pdb.gz`), not the cache
  DIR, so it stays green.

### `.planning/codebase/STACK.md` (doc — 1 line)

- Line 63: fetched-demo cache description changed to `<cwd>/tmp/phase9-demos/
  cache/` (consistent with `cmd.fetch`; created on first finalize via
  `os.makedirs`); persistence reframed to "sessions launched from the same
  dir"; Pitfall E note reframed to the cwd / smoke / fetch framing.

### `.planning/codebase/INTEGRATIONS.md` (doc — 2 lines)

- Line 64 (Fetched-demo cache): `~/.biochemeleon/cache/` → `<cwd>/tmp/
  phase9-demos/cache/`; `.pdb.gz` / `cmd.save` / gzip-magic details kept;
  persistence reframed.
- Line 65 (Temp downloads): `~/.biochemeleon/tmp/<demo_id>.raw` → `<cwd>/tmp/
  phase9-demos/<demo_id>.raw`; `.dry` / `cleanup_temp()` / `os.makedirs(...
  exist_ok=True)` details kept.

## Verification (run, all green)

All 8 plan gates pass (run from repo root; the `pymol/` prefix targets the
reorganized package per `pymol/AGENTS.md`):

1. **Syntax gate**: `python3.6 -m py_compile pymol/biochemeleon/*.py` → `PY_COMPILE_OK`.
2. **Pure unit tests**: `cd pymol && python3.6 -m unittest tests.test_setup_state -v`
   → `Ran 125 tests ... OK` (only comments changed in setup_state / test_setup_state;
   no assertions touched).
3. **Pitfall-1 gate**: `grep -rnE "import Tkinter|...|import PyQt5" pymol/biochemeleon/`
   → **0 matches** (exit 1).
4. **exec_ gate**: `grep -rnE "\.exec_\(\)" pymol/biochemeleon/` → 3 pre-existing
   hits (`gui_game.py:345` + `:404` `msg.exec_()` on QMessageBox, `__init__.py:952`
   `help_dlg.exec_()` on the help dialog). **None introduced** by this change; all
   on child dialogs, never the main modeless PluginDialog. Gate stays clean.
5. **No dangling `_app_dir`**: `grep -rn "_app_dir" pymol/biochemeleon/` → empty
   (exit 1).
6. **cwd-based path present**: `grep -n "os.getcwd(), 'tmp', 'phase9-demos'"
   pymol/biochemeleon/demos.py` → 2 hits (line 222 `_cache_dir`, line 280
   `temp_download_path`).
7. **Zero `~/.biochemeleon`**: `grep -rn "~/.biochemeleon" pymol/biochemeleon/
   pymol/tests/ .planning/codebase/STACK.md .planning/codebase/INTEGRATIONS.md`
   → empty (exit 1) — all stale references updated.
8. **Stubbed path-construction snippet** (pymol.Qt stubbed, same pattern as
   `test_setup_state.py`): `_app_dir` removed; `_cache_dir()` ==
   `<cwd>/tmp/phase9-demos/cache/`; `temp_download_path('3gp6')` ==
   `<cwd>/tmp/phase9-demos/3gp6.raw`; `to_windows_path` converts a WSL
   `/mnt/c/...` cwd to `C:\...` and passes non-`/mnt` / already-Windows paths
   through unchanged. Prints `OK: ...` (see Deviations for the one env-specific
   assertion note).

`must_have` truth-by-truth: `_cache_dir()` cwd-based ✅; `temp_download_path()`
cwd-based ✅; `_app_dir()` gone ✅; `.raw` temp parent still auto-created
(download_large_demo makedirs unchanged, confirmed via diff) ✅; cache dir still
auto-created (finalize_large_demo makedirs unchanged, confirmed via diff) ✅;
`to_windows_path` handles cwd-based paths correctly ✅; syntax / pitfall-1 /
exec_ / pure unit tests all clean ✅.

## Out of scope / untested

The **network fetch + interactive GUI on a fresh computer remain untested by
this quick task.** The fetch / finalize / cache-write LOGIC is unchanged — only
the path BASE moved — so no human-verify checkpoint was required by the plan.
A user can manually verify the end-to-end flow later by selecting the
glycoprotein (SASBDB `sasdpg4`) or membrane (MemProtMD `1gzm`/`3gp6`) demo after
launching PyMOL from a fresh cwd (the cache + `.raw` should land under
`<cwd>/tmp/phase9-demos/`). The Phase 9 smoke test (run headlessly on Windows
via `cmd.exe /c C:\src\run-conda-pymol.bat -cq`) would be the full end-to-end
proof, but that is out of scope here — the smoke already stages under the same
cwd paths the helpers now produce, so the alignment is confirmed by inspection.

## Deviations from plan

### 1. [Rule 3 — Blocking] Updated the stale path comment inside `download_large_demo`

- **Found during:** Task 1 verification (the plan's overall verification item 7
  requires `grep -rn "~/.biochemeleon" ...` to be empty).
- **Issue:** The plan's Task 1 action said "DO NOT touch `download_large_demo`"
  (to protect the `os.makedirs(_parent, exist_ok=True)` LOGIC). But the COMMENT
  above that makedirs block referenced the old `~/.biochemeleon/tmp/` path
  ("Pitfall E fix: on a fresh install the ~/.biochemeleon/tmp/ dir does not
  exist yet..."). With the path base moved, that comment is factually wrong,
  and leaving it would fail the plan's own verification item 7 (zero
  `~/.biochemeleon` references).
- **Fix:** Updated ONLY the comment text to reference `<cwd>/tmp/phase9-demos/`
  ("on a fresh launch the <cwd>/tmp/phase9-demos/ dir does not exist yet...").
  The makedirs LOGIC (`_parent = os.path.dirname(dest_path); if _parent:
  os.makedirs(_parent, exist_ok=True)`) is byte-for-byte unchanged (confirmed
  via `git diff` — the logic lines are absent from the diff).
- **Files modified:** `pymol/biochemeleon/demos.py` (comment only, lines ~392-395).
- **Commit:** 5041541 (included in the Task 1 commit).

This is the minimal, logic-preserving change that satisfies BOTH the plan's
"don't change the makedirs logic" intent AND its "zero stale references"
success criterion.

### 2. [Verification nuance — not a code deviation] The plan's stubbed snippet assertion was environment-specific

The plan's `<verify>` snippet asserted:
`demos.to_windows_path(os.path.join(os.getcwd(), 'tmp')) == os.path.join(os.getcwd(), 'tmp')`
with the comment "cwd path on a non-/mnt system passes through". That assertion
assumes a non-`/mnt` cwd, but the WSL dev shell's cwd IS `/mnt/c/...`, so
`to_windows_path` correctly converts it to `C:\...` (that is its job — WSL→
Windows path conversion for Windows PyMOL). The literal assertion can never
hold in WSL.

I ran an **environment-aware** version that proves the actual `must_have`
invariant ("WSL cwd `/mnt/c/...` → `C:\...`; Windows cwd `C:\...` unchanged"):
- WSL `/mnt/c/.../pymol/tmp` → `C:\Users\nglok\...\pymol\tmp` ✅ (converted —
  exactly what Windows PyMOL needs)
- non-`/mnt` path `/var/tmp/foo` → unchanged ✅
- already-Windows path `C:\Users\foo\tmp` → unchanged ✅

The CODE is correct; only the plan's snippet assertion was environment-specific.
No code change was needed for this.

## Commits

- `5041541` — `fix(quick-003): relocate fetched-demo cache + temp paths to cwd`
  (Task 1; 3 files: demos.py, setup_state.py, test_setup_state.py; +32/-56)
- `882de84` — `docs(quick-003): update codebase docs for cwd-based demo cache`
  (Task 2; 2 files: STACK.md, INTEGRATIONS.md; +3/-3)
- (metadata) — `docs(quick-003): complete ...` (this SUMMARY + PLAN + STATE)

Two atomic per-task work commits + one bookkeeping commit (mirrors the
quick-001/quick-002 convention).
