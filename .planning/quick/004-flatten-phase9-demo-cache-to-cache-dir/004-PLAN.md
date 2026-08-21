---
phase: quick-004
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pymol/biochemeleon/demos.py
  - pymol/biochemeleon/setup_state.py
  - pymol/tests/test_setup_state.py
  - pymol/smoke/phase9_smoke.py
  - .planning/codebase/STACK.md
  - .planning/codebase/INTEGRATIONS.md
autonomous: true
commit_prefix: "refactor(quick-004):"

must_haves:
  truths:
    - "_cache_dir() returns <cwd>/cache/ (single flat layer, not <cwd>/tmp/phase9-demos/cache/)"
    - "temp_download_path(id) returns <cwd>/cache/<id>.raw (the .raw lives IN the cache dir during fetch, cleaned after finalize)"
    - "cache_path_for('sasdpg4') returns <cwd>/cache/SASDPG4_fit2_model1.pdb.gz (derived from _cache_dir; unchanged logic, flattened base)"
    - "download_large_demo creates <cwd>/cache/ on first download via os.makedirs(os.path.dirname(dest_path), exist_ok=True)"
    - "finalize_large_demo creates <cwd>/cache/ on first finalize via os.makedirs(cache_dir, exist_ok=True)"
    - "the .dry MemProtMD strip intermediate writes to <cwd>/cache/<id>.raw.dry (downloaded_path + '.dry', naturally alongside the .raw)"
    - "the phase9 smoke cleanup loop wipes only cache+temp artifacts (.pdb.gz/.raw/.dry) from <cwd>/cache/, preserving the staged SASDPG4 .pdb sample now co-located in the same dir"
    - "zero 'phase9-demos' references remain in pymol/biochemeleon/, pymol/tests/, pymol/smoke/phase9_smoke.py, and .planning/codebase/"
    - "syntax gate, pitfall-1 gate, exec_ gate stay clean; pure unit tests stay green"
  artifacts:
    - path: "pymol/biochemeleon/demos.py"
      provides: "_cache_dir() + temp_download_path() flattened to <cwd>/cache/; docstrings + Pitfall E comment updated"
      contains: "os.path.join(os.getcwd(), 'cache'"
    - path: "pymol/smoke/phase9_smoke.py"
      provides: "staging paths read from <cwd>/cache/; cleanup loop made extension-aware to preserve staged sample"
      contains: "'cache'"
    - path: ".planning/codebase/STACK.md"
      provides: "codebase doc reflecting flat <cwd>/cache/ layout"
    - path: ".planning/codebase/INTEGRATIONS.md"
      provides: "integration doc reflecting flat <cwd>/cache/ layout"
  key_links:
    - from: "pymol/biochemeleon/demos.py:_cache_dir"
      to: "pymol/biochemeleon/demos.py:temp_download_path"
      via: "both resolve to the same <cwd>/cache/ flat dir (cache + temp co-located)"
      pattern: "os\\.path\\.join\\(os\\.getcwd\\(\\),\\s*'cache'"
    - from: "pymol/biochemeleon/demos.py:download_large_demo"
      to: "<cwd>/cache/ (parent of dest_path)"
      via: "os.makedirs(os.path.dirname(dest_path), exist_ok=True)"
      pattern: "os\\.makedirs\\(_parent, exist_ok=True\\)"
    - from: "pymol/biochemeleon/demos.py:finalize_large_demo"
      to: "<cwd>/cache/ (cache_dir)"
      via: "os.makedirs(cache_dir, exist_ok=True) + cmd.save(cache_path)"
      pattern: "os\\.makedirs\\(cache_dir, exist_ok=True\\)"
    - from: "pymol/smoke/phase9_smoke.py:cleanup loop (lines ~88-96)"
      to: "pymol/smoke/phase9_smoke.py:staged sample (line ~103)"
      via: "extension-aware wipe (.pdb.gz/.raw/.dry only) so the co-located staged .pdb sample survives"
      pattern: "endswith\\(\\.pdb\\.gz\\)|endswith\\(\\.raw\\)|endswith\\(\\.dry\\)"
---

<objective>
Flatten the Phase 9 fetched-demo cache from the 3-deep `<cwd>/tmp/phase9-demos/cache/` (persistent .pdb.gz) + `<cwd>/tmp/phase9-demos/<id>.raw` (transient .raw) layout introduced by quick-003 into a SINGLE flat `<cwd>/cache/` directory holding both the transient `.raw` (and `.dry` intermediate) and the persistent `.pdb.gz`.

Purpose: quick-003 fixed the real bug (cmd.fetch parity via cwd-based paths) but left a 3-deep nesting (`cwd/tmp/phase9-demos/cache/`). The user wants a single layer. The directory name is LOCKED as `cache/` (NOT `tmp/`) because `cache/` signals "keep these" — the persistent `.pdb.gz` survives sessions; a user deleting `tmp/` would lose cached downloads. This is a path refinement, not a bug fix (quick-003 already fixed the bug).

Output: flattened path strings in `demos.py` (+ updated docstrings/comments), updated path references in `setup_state.py`, `test_setup_state.py`, `phase9_smoke.py` (incl. one necessary behavioral fix to the cleanup loop — see Task 2), and `.planning/codebase/STACK.md` + `INTEGRATIONS.md`. All gates green; zero `phase9-demos` references remain.

Design is LOCKED by the orchestrator (pre-investigated). Directory name is `cache/`. Single flat layer under cwd. Do NOT propose alternatives.
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@pymol/AGENTS.md

# Source files to edit (read each before editing; verify line numbers — they may have shifted):
@pymol/biochemeleon/demos.py
@pymol/biochemeleon/setup_state.py
@pymol/tests/test_setup_state.py
@pymol/smoke/phase9_smoke.py
@.planning/codebase/STACK.md
@.planning/codebase/INTEGRATIONS.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Flatten the runtime cache + temp paths in demos.py</name>
  <files>pymol/biochemeleon/demos.py</files>
  <action>
This is the LOAD-BEARING change — the actual path strings the plugin uses at runtime. Read `pymol/biochemeleon/demos.py` first and confirm line numbers (they may have shifted from the citations below).

1. **`_cache_dir()` (around lines 203-222):** Change the return statement from
   `return os.path.join(os.getcwd(), 'tmp', 'phase9-demos', 'cache')`
   to
   `return os.path.join(os.getcwd(), 'cache')`.
   Rewrite the docstring to describe the flat `<cwd>/cache/` layout:
   - The opening "Resolves to" line → ``<cwd>/cache/`` (NOT `<cwd>/tmp/phase9-demos/cache/`).
   - Keep the `cmd.fetch` parity rationale and the "persists across sessions / created on first finalize by `finalize_large_demo`'s `os.makedirs(cache_dir, exist_ok=True)`" sentence.
   - Update the History paragraph: the smoke staging paths are now `os.getcwd()/cache` (smoke lines 103 + 237), and the layout is a SINGLE flat dir holding both the transient `.raw`/`.dry` and the persistent `.pdb.gz`. Note that quick-004 flattened quick-003's `<cwd>/tmp/phase9-demos/` nesting into `<cwd>/cache/` for simplicity (single layer, signals "keep these").
   - Update the Source line: keep `09-RESEARCH-pipeline.md:296-299`; change the quick-003 note to "quick-003 relocated to `<cwd>/tmp/phase9-demos/` for cmd.fetch parity; quick-004 flattened to `<cwd>/cache/` (single layer)."

2. **`temp_download_path()` (around lines 257-280):** Change the return statement from
   `return os.path.join(os.getcwd(), 'tmp', 'phase9-demos', demo_id + '.raw')`
   to
   `return os.path.join(os.getcwd(), 'cache', demo_id + '.raw')`.
   Rewrite the docstring to describe the flat layout:
   - The opening "Resolves to" line → ``<cwd>/cache/<demo_id>.raw`` (NOT `<cwd>/tmp/phase9-demos/<demo_id>.raw`).
   - Add one sentence noting the `.raw` now lives IN the SAME dir as the `.pdb.gz` cache (flat layout), and is cleaned after finalize by `cleanup_temp` (the `.pdb.gz` persists).
   - Keep the deterministic-path rationale (traceable for debugging; not `tempfile.mkstemp`), the `os.makedirs(os.path.dirname(dest_path), exist_ok=True)` parent-creation note (now creates `<cwd>/cache/`), and the `to_windows_path` + `cleanup_temp` caller notes.
   - Update the History paragraph + Source line the same way as `_cache_dir` (quick-004 flattened quick-003's nesting).

3. **`download_large_demo` Pitfall E comment (around lines 388-392):** The comment currently says "on a fresh launch the `<cwd>/tmp/phase9-demos/` dir does not exist yet". Change the path reference to `<cwd>/cache/`. Keep the rest of the Pitfall E explanation (the `os.makedirs(_parent, exist_ok=True)` at line ~395 stays — it now creates `<cwd>/cache/` on first download).

4. **Do NOT touch** the `os.makedirs(_parent, exist_ok=True)` in `download_large_demo` (line ~395) or the `cache_dir = _cache_dir()` / `os.makedirs(cache_dir, exist_ok=True)` in `finalize_large_demo` (lines ~500-502) — both still create `<cwd>/cache/` on first use via the flattened paths. Do NOT touch `cache_path_for` / `is_cached` / `cleanup_temp` / `finalize_large_demo` / `load_cached_demo` logic — only the path strings and docstrings/comments change. Do NOT add any new imports.

Constraints (pymol/AGENTS.md): `demos.py` is the cmd bridge (imports `from pymol import cmd`); keep it that way. No Tkinter/Pmw/PyQt5 imports. The `exec_` gate must only hit QFileDialog/QMessageBox (this file has none, so expect zero `\.exec_\(\)` hits here).
  </action>
  <verify>
From repo root: `python3.6 -m py_compile pymol/biochemeleon/demos.py` (clean exit). Then confirm the two return lines now read `os.path.join(os.getcwd(), 'cache', ...)` and `os.path.join(os.getcwd(), 'cache', demo_id + '.raw')` by reading lines ~222 and ~280. Then `grep -rnE "phase9-demos" pymol/biochemeleon/demos.py` — MUST return zero matches.
  </verify>
  <done>
`_cache_dir()` returns `<cwd>/cache/`; `temp_download_path(id)` returns `<cwd>/cache/<id>.raw`; the `.raw` and `.pdb.gz` coexist in the same flat dir; the Pitfall E comment references `<cwd>/cache/`; zero `phase9-demos` references in demos.py; `py_compile` clean.
  </done>
</task>

<task type="auto">
  <name>Task 2: Update smoke + test + doc references, incl. the cleanup-loop fix</name>
  <files>pymol/biochemeleon/setup_state.py, pymol/tests/test_setup_state.py, pymol/smoke/phase9_smoke.py, .planning/codebase/STACK.md, .planning/codebase/INTEGRATIONS.md</files>
  <action>
Read each file before editing; confirm line numbers (may have shifted).

**A. pymol/biochemeleon/setup_state.py line ~30 comment:** The comment currently says `# -> <cwd>/tmp/phase9-demos/cache/); 'cache_name' is the on-disk filename.` Change the path reference to `<cwd>/cache/`. Only update the stale path reference; do not alter the rest of the comment block (lines 25-33) or the DEMO_MANIFEST entries.

**B. pymol/tests/test_setup_state.py line ~141 comment:** The comment currently says `# demos cache as compressed <name>.pdb.gz in <cwd>/tmp/phase9-demos/cache/.` Change the path reference to `<cwd>/cache/`. Only update the path reference; do not alter the test logic (lines 139-149).

**C. pymol/smoke/phase9_smoke.py — three path references + ONE behavioral fix:**

   C1. Line ~8 header comment: `# Uses the STAGED SASBDB sample (tmp/phase9-demos/SASDPG4_fit2_model1.pdb) to` → change the path to `cache/SASDPG4_fit2_model1.pdb`.

   C2. Line ~103: `_staged_sasbdb = os.path.abspath(os.path.join(os.getcwd(), 'tmp', 'phase9-demos', 'SASDPG4_fit2_model1.pdb'))` → change `'tmp', 'phase9-demos'` to `'cache'` so it reads `os.path.join(os.getcwd(), 'cache', 'SASDPG4_fit2_model1.pdb')`. This is where the smoke reads the staged sample (simulating the worker download; no real network).

   C3. Line ~237: `_memprotmd_dir = os.path.abspath(os.path.join(os.getcwd(), 'tmp', 'phase9-demos'))` → change to `os.path.abspath(os.path.join(os.getcwd(), 'cache'))`. The `os.makedirs(_memprotmd_dir, exist_ok=True)` at line ~239 and the synthetic `.raw` write at lines ~242-244 now target `<cwd>/cache/3gp6_synthetic.raw` — fine.

   C4. **CLEANUP-LOOP FIX (around lines 88-96) — this is a NECESSARY behavioral change, not just a path string.** Flattening puts the staged SASBDB sample (`cwd/cache/SASDPG4_fit2_model1.pdb`) INSIDE `_cache_dir()` (`cwd/cache/`). The current loop unlinks EVERY file in `_cache_dir()` before section A reads the staged sample, which would DELETE the staged sample and break section A. (Under the old nested layout this was safe because the sample lived in the PARENT `tmp/phase9-demos/`, outside the cache subdir.) Make the loop extension-aware so it wipes only cache+temp artifacts and preserves the co-located staged `.pdb` sample. Replace the loop body (lines ~88-96) with:
   ```python
   # Clean any stale cache+temp artifacts from prior runs so the smoke is
   # deterministic. Wipe ONLY .pdb.gz (cache), .raw and .dry (temp) -- the
   # flat <cwd>/cache/ layout co-locates the staged SASBDB .pdb sample in
   # this same dir (smoke line 103), and it must survive the wipe so
   # section A can read it. (Under quick-003's nested layout the sample
   # lived in the parent tmp/phase9-demos/ outside the cache subdir; the
   # flat layout removes that incidental separation, so the wipe must be
   # extension-aware.)
   _cache_dir = demos._cache_dir()
   if os.path.isdir(_cache_dir):
       for _f in os.listdir(_cache_dir):
           if not (_f.endswith('.pdb.gz') or _f.endswith('.raw')
                  or _f.endswith('.dry')):
               continue  # leave the staged .pdb sample (and any non-artifact) alone
           _fp = os.path.join(_cache_dir, _f)
           try:
               os.unlink(_fp)
           except OSError:
               pass
   ```
   Keep the variable name `_cache_dir` (it shadows the helper name locally as before). Do NOT change the loop's position (it must still run BEFORE sections A and G).

**D. .planning/codebase/STACK.md line ~63:** The bullet currently says `Fetched-demo cache: \`<cwd>/tmp/phase9-demos/cache/\` (consistent with \`cmd.fetch\`...`. Update the path to `<cwd>/cache/` and adjust the parenthetical that references "smoke lines 103 + 237" to note the flat layout (the smoke now stages under `<cwd>/cache/`). Keep the `cmd.fetch` parity + Pitfall E / Open Risk 4 reframe rationale.

**E. .planning/codebase/INTEGRATIONS.md lines ~44, ~64, ~65:**
   - Line ~44: `...cached as \`.pdb.gz\` in \`tmp/phase9-demos/cache/\`.` → change to `...cached as \`.pdb.gz\` in \`cache/\` (flat <cwd>/cache/ layout).`
   - Line ~64: `**Fetched-demo cache:** \`<cwd>/tmp/phase9-demos/cache/\` (consistent with \`cmd.fetch\`...` → change the path to `<cwd>/cache/` and update the "matches the Phase 9 smoke test's staging paths" note to reflect the flat layout.
   - Line ~65: `**Temp downloads:** \`<cwd>/tmp/phase9-demos/<demo_id>.raw\` (raw download) + \`.dry\` (stripped intermediate, written next to the \`.raw\`).` → change the path to `<cwd>/cache/<demo_id>.raw` and note the `.raw`/`.dry` now live in the SAME flat dir as the `.pdb.gz` cache (cleaned by `cleanup_temp` after the cache write; the parent dir is created by `download_large_demo`'s `os.makedirs(..., exist_ok=True)`).

After all edits, run a repo-wide grep to confirm no other `phase9-demos` references were missed (see Task 3 verify).
  </action>
  <verify>
`python3.6 -m py_compile pymol/biochemeleon/setup_state.py pymol/tests/test_setup_state.py pymol/smoke/phase9_smoke.py` (clean exit — these are syntax checks, not import/run). Read back the edited lines to confirm: setup_state.py line ~30 says `<cwd>/cache/`; test_setup_state.py line ~141 says `<cwd>/cache/`; smoke line ~8 says `cache/SASDPG4_fit2_model1.pdb`; smoke line ~103 uses `'cache'`; smoke line ~237 uses `'cache'`; smoke lines ~88-96 now skip non-`.pdb.gz`/`.raw`/`.dry` files; STACK.md line ~63 and INTEGRATIONS.md lines ~44/64/65 reference `<cwd>/cache/`.
  </verify>
  <done>
All non-demos.py references to `tmp/phase9-demos` are updated to `cache`; the smoke cleanup loop is extension-aware (preserves the staged `.pdb` sample co-located in `<cwd>/cache/`); `py_compile` clean on the three edited Python files; the codebase docs reflect the flat layout.
  </done>
</task>

<task type="auto">
  <name>Task 3: Run all gates + stubbed path-build verification + grep-zero check</name>
  <files>(no file edits — verification only; write any throwaway script to /tmp/opencode, not the repo)</files>
  <action>
Run every gate from pymol/AGENTS.md "Commands" section, plus a stubbed path-build snippet and a repo-wide grep-zero check. All must pass. If any gate fails, fix the regression before committing.

1. **Syntax gate** (from repo root): `python3.6 -m py_compile pymol/biochemeleon/*.py` — must exit clean (checks ALL biochemeleon modules, not just the edited ones).

2. **Pitfall-1 gate:** `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" pymol/biochemeleon/` — MUST return zero matches. (Warning: literal tokens in comments/docstrings can trip this — none of this task's edits add such tokens, so expect zero. If a hit appears, it is a false positive from a docstring and must be reworded, not suppressed.)

3. **exec_ gate:** `grep -rnE "\.exec_\(\)" pymol/biochemeleon/` — any hits must be on QFileDialog/QMessageBox ONLY, never on the main PluginDialog/SetupTab. This task adds no `exec_` calls, so expect the same hit set as before (unchanged).

4. **Pure unit tests** (run from the `pymol/` dir so the `tests` package resolves): `python3.6 -m unittest tests.test_setup_state -v` — must stay GREEN (125 tests; the only edit to this file was the line ~141 comment, which does not affect test behavior). Report the final count (e.g. "Ran 125 tests in Xs — OK").

5. **Stubbed path-build snippet:** Write a throwaway script to `/tmp/opencode/quick004_paths.py` that stubs `pymol` + `pymol.Qt` (mirror the existing `pymol/tests/test_setup_state.py` sys.modules stub pattern — `demos.py` does `from pymol import cmd` at import and `biochemeleon/__init__.py` does `from pymol.Qt import ...` at module level, so both must be stubbed), inserts `pymol/` on `sys.path`, imports `biochemeleon.demos`, then asserts (using a `tempfile.TemporaryDirectory()` as cwd so `makedirs` creates a throwaway `cache/`, not a repo one):
   - `demos._cache_dir() == os.path.join(<tmpcwd>, 'cache')`
   - `demos.temp_download_path('sasdpg4') == os.path.join(<tmpcwd>, 'cache', 'sasdpg4.raw')`
   - `demos.cache_path_for('sasdpg4') == os.path.join(<tmpcwd>, 'cache', 'SASDPG4_fit2_model1.pdb.gz')` (cache_name is `SASDPG4_fit2_model1.pdb.gz` per setup_state.py line 47)
   - `os.path.dirname(demos.temp_download_path('sasdpg4')) == demos._cache_dir()` (the .raw lives IN the cache dir — flat)
   - `os.makedirs(os.path.dirname(demos.temp_download_path('sasdpg4')), exist_ok=True)` then `os.path.isdir(os.path.join(<tmpcwd>, 'cache'))` is True (download_large_demo's parent-creation works on a fresh cwd)
   Print `OK` on success. Run it: `python3.6 /tmp/opencode/quick004_paths.py`. (If the stubbed import proves fragile, fall back to reading the two return lines in demos.py and confirming they match `os.path.join(os.getcwd(), 'cache', ...)` — but prefer the stubbed snippet as it exercises the real functions.)

6. **Grep-zero check (the completeness gate):** `grep -rnE "phase9-demos" pymol/biochemeleon/ pymol/tests/ pymol/smoke/phase9_smoke.py .planning/codebase/` — MUST return zero matches. This is the single most important gate: it proves every reference was flattened. If any hit remains, edit the offending file and re-run.

7. **Do NOT run the network fetch or the interactive PyMOL GUI** — a WSL agent cannot (pymol/AGENTS.md: dev shell is WSL; the real fetch + GUI need the Windows conda env + a real display). The phase9 smoke (`pymol/smoke/phase9_smoke.py`) is a headless PyMOL cmd-only script that COULD be run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq ...` IF the staged SASBDB sample is present at `pymol/cache/SASDPG4_fit2_model1.pdb`. NOTE in the summary that the staged sample is gitignored runtime data (NOT in the repo — `pymol/tmp/phase9-demos/` and `pymol/cache/` both currently do NOT exist in this worktree); the user must stage `SASDPG4_fit2_model1.pdb` at `pymol/cache/SASDPG4_fit2_model1.pdb` (the new flat location, was `pymol/tmp/phase9-demos/SASDPG4_fit2_model1.pdb`) before running the phase9 smoke, and that the real network fetch + GUI on a fresh computer remain untested by this quick task.
  </action>
  <verify>
All six gates pass: py_compile clean; pitfall-1 zero matches; exec_ gate unchanged (QFileDialog/QMessageBox-only hits, if any); unit tests GREEN with the count reported; stubbed snippet prints `OK`; grep-zero `phase9-demos` returns nothing across `pymol/biochemeleon/`, `pymol/tests/`, `pymol/smoke/phase9_smoke.py`, `.planning/codebase/`.
  </verify>
  <done>
All gates green; the stubbed snippet confirms the three path functions resolve to the flat `<cwd>/cache/` layout (cache + temp co-located); zero `phase9-demos` references remain; the summary records that the real fetch + GUI on a fresh computer remain untested and that the user must stage the SASBDB sample at `pymol/cache/SASDPG4_fit2_model1.pdb`.
  </done>
</task>

</tasks>

<verification>
Phase-level checks (all must pass before commit):
1. `python3.6 -m py_compile pymol/biochemeleon/*.py` — clean.
2. `python3.6 -m unittest tests.test_setup_state -v` (from `pymol/`) — GREEN, count reported.
3. Pitfall-1 gate — zero matches.
4. exec_ gate — unchanged (QFileDialog/QMessageBox-only).
5. Stubbed path-build snippet — prints `OK` (cache + temp both resolve to `<cwd>/cache/`).
6. `grep -rnE "phase9-demos" pymol/biochemeleon/ pymol/tests/ pymol/smoke/phase9_smoke.py .planning/codebase/` — zero matches (the completeness gate).
7. Confirm the smoke cleanup loop (lines ~88-96) is extension-aware — read it back and confirm it skips non-`.pdb.gz`/`.raw`/`.dry` files (preserves the co-located staged sample).

Commit: `refactor(quick-004): flatten phase9 demo cache to <cwd>/cache/ (single layer)`
Then create the SUMMARY per the `<output>` section.
</verification>

<success_criteria>
- `_cache_dir()` returns `<cwd>/cache/`; `temp_download_path(id)` returns `<cwd>/cache/<id>.raw`; both co-located in one flat dir.
- `download_large_demo` + `finalize_large_demo` both create `<cwd>/cache/` on first use (makedirs unchanged, paths flattened).
- The smoke cleanup loop is extension-aware (wipes `.pdb.gz`/`.raw`/`.dry` only; preserves the staged `.pdb` sample now co-located in `<cwd>/cache/`).
- Zero `phase9-demos` references in `pymol/biochemeleon/`, `pymol/tests/`, `pymol/smoke/phase9_smoke.py`, `.planning/codebase/`.
- Syntax + pitfall-1 + exec_ gates clean; pure unit tests GREEN.
- Commit `refactor(quick-004):` created; SUMMARY written.
- Summary records: real network fetch + GUI on a fresh computer remain untested; user must stage `SASDPG4_fit2_model1.pdb` at `pymol/cache/` before running the phase9 smoke.
</success_criteria>

<output>
After completion, create `.planning/quick/004-flatten-phase9-demo-cache-to-cache-dir/004-SUMMARY.md` (mirror the quick-003 SUMMARY structure). Update `.planning/STATE.md`:
- "Last activity" line → quick-004 flatten phase9 demo cache to `<cwd>/cache/` (single layer).
- Append a row to the "Quick Tasks Completed" table for 004 (commit hash, description "Flatten Phase 9 fetched-demo cache to single `<cwd>/cache/` layer", directory `004-flatten-phase9-demo-cache-to-cache-dir`).
- Update the "Known v1 tech debt" Phase 9 parenthetical to reflect the flat `<cwd>/cache/` layout (quick-004 flattened quick-003's nesting).
Commit the SUMMARY + STATE.md update as `docs(quick-004): complete flatten-phase9-demo-cache-to-cache-dir plan`.
</output>
