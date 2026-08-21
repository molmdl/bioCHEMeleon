---
phase: quick-003
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pymol/biochemeleon/demos.py
  - pymol/biochemeleon/setup_state.py
  - pymol/tests/test_setup_state.py
  - .planning/codebase/STACK.md
  - .planning/codebase/INTEGRATIONS.md
autonomous: true

must_haves:
  truths:
    - "_cache_dir() returns <cwd>/tmp/phase9-demos/cache/ (NOT ~/.biochemeleon/cache/)"
    - "temp_download_path(demo_id) returns <cwd>/tmp/phase9-demos/<demo_id>.raw (NOT ~/.biochemeleon/tmp/<demo_id>.raw)"
    - "_app_dir() no longer exists (removed; no dead code)"
    - "The .raw temp parent dir is still auto-created on first download (makedirs in download_large_demo unchanged)"
    - "The cache dir is still auto-created on first finalize (makedirs in finalize_large_demo unchanged)"
    - "to_windows_path() still passes a cwd-based path through correctly (WSL cwd /mnt/c/... -> C:\\...; Windows cwd C:\\... unchanged)"
    - "Pure unit tests stay green; syntax gate, pitfall-1 gate, and exec_ gate stay clean"
  artifacts:
    - path: "pymol/biochemeleon/demos.py"
      provides: "cwd-based _cache_dir() and temp_download_path(); _app_dir() removed"
      contains: "os.path.join(os.getcwd(), 'tmp', 'phase9-demos'"
    - path: "pymol/biochemeleon/setup_state.py"
      provides: "updated DEMO_MANIFEST comment (line ~30) reflecting cwd cache location"
    - path: "pymol/tests/test_setup_state.py"
      provides: "updated test comment (line ~141) reflecting cwd cache location"
    - path: ".planning/codebase/STACK.md"
      provides: "updated fetched-demo cache description (line ~63)"
    - path: ".planning/codebase/INTEGRATIONS.md"
      provides: "updated fetched-demo cache + temp-download descriptions (lines ~64-65)"
  key_links:
    - from: "pymol/biochemeleon/demos.py:_cache_dir"
      to: "pymol/biochemeleon/demos.py:finalize_large_demo"
      via: "os.makedirs(cache_dir, exist_ok=True) before cmd.save"
      pattern: "os\\.path\\.join\\(os\\.getcwd\\(\\), 'tmp', 'phase9-demos', 'cache'\\)"
    - from: "pymol/biochemeleon/demos.py:temp_download_path"
      to: "pymol/biochemeleon/demos.py:download_large_demo"
      via: "os.makedirs(os.path.dirname(dest_path), exist_ok=True) before open(dest_path, 'wb')"
      pattern: "os\\.path\\.join\\(os\\.getcwd\\(\\), 'tmp', 'phase9-demos', demo_id \\+ '\\.raw'\\)"
    - from: "pymol/biochemeleon/demos.py:to_windows_path"
      to: "finalize_large_demo cmd.save(to_windows_path(cache_path), ...)"
      via: "WSL cwd /mnt/c/... -> C:\\... conversion must still hold for a cwd-based path"
      pattern: "to_windows_path\\(cache_path\\)"
---

<objective>
Relocate the Phase 9 fetched-demo cache + temp-download paths from the
per-user home directory (`~/.biochemeleon/`) to the current working
directory (`<cwd>/tmp/phase9-demos/`), for parity with `cmd.fetch` (which
downloads PDBs into the cwd). This also realigns the helpers with the
Phase 9 smoke test, which ALREADY stages under
`os.path.join(os.getcwd(), 'tmp', 'phase9-demos')` (smoke lines 103 + 237)
— the prior `~/.biochemeleon/` fix (commit e8ea659) had diverged from that.

Purpose: A single source of truth for "where do fetched demos land" that
matches PyMOL's own `cmd.fetch` convention (cwd), so the dev-repo smoke
test, an installed plugin, and a user running PyMOL from their project dir
all agree on the cache location.

Output: 5 files edited (1 functional in `demos.py`, 2 in-code comment
updates, 2 planning-doc updates). No new files. No logic change to the
fetch/finalize/cache-write flow — only the path BASE moves from
`~/.biochemeleon/` to `<cwd>/tmp/phase9-demos/`.
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@pymol/AGENTS.md

# The package lives at pymol/biochemeleon/ (reorganized in commit 9ff57f1).
# The repo-root AGENTS.md commands need a `pymol/` prefix to target it.
@pymol/biochemeleon/demos.py
@pymol/biochemeleon/setup_state.py
@pymol/tests/test_setup_state.py
@pymol/smoke/phase9_smoke.py
@.planning/codebase/STACK.md
@.planning/codebase/INTEGRATIONS.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Relocate cache + temp paths to cwd in demos.py (remove _app_dir)</name>
  <files>pymol/biochemeleon/demos.py, pymol/biochemeleon/setup_state.py, pymol/tests/test_setup_state.py</files>
  <action>
In `pymol/biochemeleon/demos.py`:

1. REMOVE the entire `_app_dir()` function (currently lines 203-228,
   the def + its docstring). It is no longer referenced once the two
   callers below are rewritten. Grep confirms `_app_dir` appears ONLY at
   its definition (line 203) and two call sites (lines 248, 305) — removing
   the def after rewriting the callers leaves zero dangling references.

2. REWRITE `_cache_dir()` (currently lines 231-248): replace the body
   `return os.path.join(_app_dir(), 'cache')` with
   `return os.path.join(os.getcwd(), 'tmp', 'phase9-demos', 'cache')`.
   Update the docstring to describe the cwd-based location: it resolves
   to `<cwd>/tmp/phase9-demos/cache/` (consistent with `cmd.fetch`, which
   downloads PDBs into the cwd), is created on first finalize by
   `finalize_large_demo`'s `os.makedirs(cache_dir, exist_ok=True)`, and
   persists across PyMOL sessions as long as the user launches PyMOL from
   the same dir (same limitation `cmd.fetch` has — acceptable for v1).
   Drop the now-stale `~/.biochemeleon/` and "installed-plugin" rationale
   from the docstring; keep the Pitfall E / Open Risk 4 historical note
   but reframe it as "the cwd-based layout matches the Phase 9 smoke
   test's staging paths (smoke lines 103 + 237) AND cmd.fetch's
   convention."

3. REWRITE `temp_download_path()` (currently lines 283-305): replace the
   body `return os.path.join(_app_dir(), 'tmp', demo_id + '.raw')` with
   `return os.path.join(os.getcwd(), 'tmp', 'phase9-demos', demo_id + '.raw')`.
   Update the docstring analogously: it now resolves to
   `<cwd>/tmp/phase9-demos/<demo_id>.raw`, parent dir created by
   `download_large_demo`'s `os.makedirs(os.path.dirname(dest_path),
   exist_ok=True)` (line ~417-419 — KEEP that makedirs call unchanged).
   Keep the deterministic-path + traceable-for-debugging rationale; drop
   the `~/.biochemeleon/tmp/` references.

4. DO NOT touch `download_large_demo` (the `os.makedirs(_parent,
   exist_ok=True)` block at lines ~417-419 stays — it now creates
   `<cwd>/tmp/phase9-demos/` on first download). DO NOT touch
   `finalize_large_demo` (the `os.makedirs(cache_dir, exist_ok=True)` at
   line ~526 stays — it now creates `<cwd>/tmp/phase9-demos/cache/` on
   first finalize). DO NOT touch `to_windows_path()` (line 59) — it only
   converts `/mnt/<letter>/` paths; a cwd-based path passes through
   correctly on Windows (cwd is `C:\...` → unchanged) and WSL (cwd is
   `/mnt/c/...` → converted to `C:\...`). Just VERIFY this by reading
   `to_windows_path` (lines 59-69) — no edit needed.

5. In `pymol/biochemeleon/setup_state.py`, update ONLY the comment at line
   ~30 (`-> ~/.biochemeleon/cache/`) to reflect the cwd-based location
   (e.g. `-> <cwd>/tmp/phase9-demos/cache/`). Do not rewrite the
   surrounding comment block — just fix the stale path reference.

6. In `pymol/tests/test_setup_state.py`, update ONLY the comment at line
   ~141 (`~/.biochemeleon/cache/`) to reflect the cwd-based location. Do
   not change any test assertions — the test only checks `cache_name`
   suffixes (`.pdb` vs `.pdb.gz`), not the cache DIR, so it stays green.

Do NOT add `import tempfile` or `import getcwd` separately — `os.getcwd()`
is already available via the existing `import os` at the top of demos.py
(line 42). Do NOT change `setup_state.py` imports (it must stay pure: no
pymol, no Qt). Do NOT introduce any new dependency.
  </action>
  <verify>
Run from the repo root (the `pymol/` prefix targets the reorganized
package per pymol/AGENTS.md):

```bash
# 1. Syntax gate — MUST be clean (checks syntax, NOT imports):
python3.6 -m py_compile pymol/biochemeleon/*.py

# 2. Pitfall-1 gate — MUST return ZERO matches:
grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" pymol/biochemeleon/

# 3. exec_ gate — only QFileDialog/QMessageBox hits allowed (none expected here):
grep -rnE "\.exec_\(\)" pymol/biochemeleon/

# 4. No dangling _app_dir references — MUST be empty:
grep -rn "_app_dir" pymol/biochemeleon/

# 5. cwd-based path is present in demos.py:
grep -n "os.getcwd(), 'tmp', 'phase9-demos'" pymol/biochemeleon/demos.py

# 6. Pure unit tests stay green (run from pymol/ where tests/ lives):
cd pymol && python3.6 -m unittest tests.test_setup_state -v
```

Then verify path-construction with a stubbed snippet (pymol.Qt is stubbed
because `__init__.py` imports it at module level — same pattern as
test_setup_state.py):

```bash
cd pymol && python3.6 -c "
import sys, os
from unittest.mock import MagicMock
sys.modules['pymol'] = MagicMock()
sys.modules['pymol.Qt'] = MagicMock()
sys.modules['pymol.Qt.QtWidgets'] = MagicMock()
sys.modules['pymol.Qt.QtCore'] = MagicMock()
sys.modules['pymol.Qt.QtGui'] = MagicMock()
from biochemeleon import demos
# _app_dir must NOT exist:
assert not hasattr(demos, '_app_dir'), '_app_dir should be removed'
# cwd-based cache + temp:
assert demos._cache_dir() == os.path.join(os.getcwd(), 'tmp', 'phase9-demos', 'cache'), demos._cache_dir()
assert demos.temp_download_path('3gp6') == os.path.join(os.getcwd(), 'tmp', 'phase9-demos', '3gp6.raw'), demos.temp_download_path('3gp6')
# to_windows_path still guards (cwd path on a non-/mnt system passes through):
assert demos.to_windows_path(os.path.join(os.getcwd(), 'tmp')) == os.path.join(os.getcwd(), 'tmp')
print('OK: paths are cwd-based; _app_dir removed; to_windows_path passes cwd path through')
"
```

All gates must pass; the snippet must print `OK: ...`.
  </verify>
  <done>
`_app_dir()` is gone; `_cache_dir()` returns
`<cwd>/tmp/phase9-demos/cache/`; `temp_download_path(d)` returns
`<cwd>/tmp/phase9-demos/<d>.raw`; syntax + pitfall-1 + exec_ gates clean;
no dangling `_app_dir` references; pure unit tests green; the stubbed
path-construction snippet prints OK. The makedirs calls in
`download_large_demo` and `finalize_large_demo` are untouched (they now
create the cwd-based dirs on first use). `setup_state.py` line ~30 and
`test_setup_state.py` line ~141 comments reflect the cwd location.
  </done>
</task>

<task type="auto">
  <name>Task 2: Update codebase docs (STACK.md + INTEGRATIONS.md) cache-location descriptions</name>
  <files>.planning/codebase/STACK.md, .planning/codebase/INTEGRATIONS.md</files>
  <action>
Update ONLY the lines describing the fetched-demo cache + temp-download
locations. Do not rewrite the surrounding sections.

1. In `.planning/codebase/STACK.md` (line ~63): the current text reads
   "Fetched-demo cache: `~/.biochemeleon/cache/` (per-user,
   always-writable; created on first fetch via `os.makedirs`)....".
   CHANGE to describe the cwd-based location: the cache resolves to
   `<cwd>/tmp/phase9-demos/cache/` (consistent with `cmd.fetch`, which
   downloads PDBs into the cwd), created on first finalize via
   `os.makedirs`. Keep the "persists across PyMOL sessions as long as
   the user launches PyMOL from the same dir (same limitation cmd.fetch
   has — acceptable for v1)" framing. Drop the `~/.biochemeleon/` and
   "per-user, always-writable" phrasing (cwd is not per-user; it's
   per-launch-dir). Keep the Pitfall E historical note reframed: the
   cwd-based layout matches the Phase 9 smoke staging paths AND
   `cmd.fetch`'s convention.

2. In `.planning/codebase/INTEGRATIONS.md` line ~64 ("Fetched-demo
   cache"): change `~/.biochemeleon/cache/` to
   `<cwd>/tmp/phase9-demos/cache/`. Keep the `.pdb.gz` / `cmd.save` /
   gzip-magic details (they are unaffected by the path base). Reframe
   the "per-user, always-writable" and "Persists across sessions" notes
   to the cwd-based framing (persists across sessions launched from the
   same dir).

3. In `.planning/codebase/INTEGRATIONS.md` line ~65 ("Temp downloads"):
   change `~/.biochemeleon/tmp/<demo_id>.raw` to
   `<cwd>/tmp/phase9-demos/<demo_id>.raw`. Keep the `.dry` intermediate,
   `cleanup_temp()`, and `os.makedirs(..., exist_ok=True)` details (they
   are unaffected — the makedirs now creates the cwd-based parent).

Do NOT edit any other line in these files. Do NOT touch ARCHITECTURE.md,
STRUCTURE.md, TESTING.md, or CONVENTIONS.md (none of them reference the
cache path base — verify with the grep in <verify>).
  </action>
  <verify>
```bash
# No remaining ~/.biochemeleon cache/temp references in the codebase docs:
grep -rn "~/.biochemeleon" .planning/codebase/STACK.md .planning/codebase/INTEGRATIONS.md
# (MUST return zero matches after the edit.)

# The cwd-based path IS now described in both docs:
grep -n "phase9-demos" .planning/codebase/STACK.md .planning/codebase/INTEGRATIONS.md
# (MUST show the updated lines.)

# Sanity: no other codebase doc references the old cache base:
grep -rln "~/.biochemeleon" .planning/codebase/ARCHITECTURE.md .planning/codebase/STRUCTURE.md .planning/codebase/TESTING.md .planning/codebase/CONVENTIONS.md 2>/dev/null
# (MUST be empty — confirms we did not miss a doc.)
```
All greps must match the stated expectations.
  </verify>
  <done>
STACK.md line ~63 and INTEGRATIONS.md lines ~64-65 describe the cache as
`<cwd>/tmp/phase9-demos/cache/` and temp as
`<cwd>/tmp/phase9-demos/<demo_id>.raw`; zero `~/.biochemeleon` references
remain in `.planning/codebase/STACK.md` or
`.planning/codebase/INTEGRATIONS.md`; no other codebase doc needed
editing (confirmed by the empty grep).
  </done>
</task>

</tasks>

<verification>
Overall (after both tasks):

1. `python3.6 -m py_compile pymol/biochemeleon/*.py` — clean.
2. `cd pymol && python3.6 -m unittest tests.test_setup_state -v` — green (125 tests; only comments changed in setup_state.py / test_setup_state.py, no assertions touched).
3. Pitfall-1 gate (`grep -rnE "..." pymol/biochemeleon/`) — zero matches.
4. exec_ gate (`grep -rnE "\.exec_\(\)" pymol/biochemeleon/`) — only QFileDialog/QMessageBox hits (none introduced here).
5. `grep -rn "_app_dir" pymol/biochemeleon/` — empty (helper fully removed).
6. `grep -n "os.getcwd(), 'tmp', 'phase9-demos'" pymol/biochemeleon/demos.py` — shows the two new path constructions.
7. `grep -rn "~/.biochemeleon" pymol/biochemeleon/ pymol/tests/ .planning/codebase/STACK.md .planning/codebase/INTEGRATIONS.md` — empty (all stale references updated).
8. Stubbed path-construction snippet (Task 1 <verify>) prints `OK: ...`.

The network fetch + interactive GUI are NOT part of this change (the
fetch/finalize/cache-write LOGIC is unchanged — only the path BASE moved),
so no human-verify checkpoint is required. The Phase 9 smoke test (run
headlessly on Windows via `cmd.exe /c C:\\src\\run-conda-pymol.bat`) would
be the end-to-end proof, but that is out of scope for this quick path
relocation — the smoke already stages under the same cwd paths the
helpers will now produce, so the alignment is confirmed by inspection.
</verification>

<success_criteria>
- `_cache_dir()` and `temp_download_path()` return cwd-based paths under
  `<cwd>/tmp/phase9-demos/`.
- `_app_dir()` is removed (no dead code).
- The makedirs-on-first-use invariant is preserved (download_large_demo
  creates the temp parent; finalize_large_demo creates the cache dir).
- `to_windows_path()` still handles cwd-based paths correctly (verified
  by reading + stubbed snippet).
- All WSL-runnable gates pass: syntax, pitfall-1, exec_, pure unit tests.
- Code + test + doc comments all reflect the cwd location; zero stale
  `~/.biochemeleon` references in the package, tests, or the two
  codebase docs that described the cache.
</success_criteria>

<output>
After completion, create `.planning/quick/003-relocate-phase9-demo-cache-to-cwd/003-SUMMARY.md`
</output>
