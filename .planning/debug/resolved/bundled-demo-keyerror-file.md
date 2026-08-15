---
status: resolved
trigger: "Bundled demo mode raises KeyError: 'file' when clicking Start in the bioCHEMeleon Setup tab with target_mode=demo. Observed during Phase 11 GUI human-verify but CONFIRMED PRE-EXISTING on main (introduced by an earlier phase, not Phase 11). User asked to write a debug file for another agent to investigate."
created: 2026-08-16T00:00:00Z
updated: 2026-08-16T02:00:00Z
---

## Current Focus

hypothesis: CONFIRMED. Half-completed Phase 9 migration. Plan 09-01 (merged) renamed the manifest key `file` -> `cache_name` and added a `source` field (`bundled`/`memprotmd`/`sasbdb`) to `DEMO_MANIFEST`. Plan 09-02 (which was supposed to migrate `demos.load_demo` to read `meta['cache_name']` + add source-based fetched-demo fetching) was NEVER EXECUTED (only `09-02-PLAN.md` exists; no `09-02-SUMMARY.md`). So `load_demo` (demos.py:128) still reads the old `meta['file']` key, which no longer exists in any manifest entry -> `KeyError: 'file'` for EVERY demo Start (bundled AND fetched). The 09-01-SUMMARY explicitly documents this as "the intended 09-02 migration surface" (lines 120, 131).
test: Apply the minimal 09-02 migration to `load_demo`: (1) `meta['file']` -> `meta.get('cache_name')` with a None guard; (2) branch on `meta.get('source','bundled')` so fetched demos return None gracefully (the full fetch worker is unimplemented 09-02 scope); (3) keep the bundled path (`data/demos/{cache_name}` -> cmd.load) unchanged. Then verify headlessly: iterate ALL 9 DEMO_MANIFEST ids, assert no exception, bundled demos load (return obj name + atoms>0), fetched demos return None (graceful cache-miss).
expecting: Bundled demos (1znf/5e54/1k8p/1xdn/2qbz/4wb3) load successfully; fetched demos (1gzm/3gp6/sasdpg4) return None (no crash). No KeyError for any id. Unit tests stay green (no schema change -- cache_name is already the tested canonical schema). GUI final check (demo Start loads PDB + starts game) is a human-verify checkpoint.
next_action: Edit `biochemeleon/demos.py` load_demo (lines 114-137). Then: py_compile, unit tests, pitfall-1 + exec_ grep gates, headless smoke via WSL->Windows bridge. Commit with `fix(demo):` scope (NOT phase 11).

## Symptoms

expected: Selecting a bundled demo (target_mode=demo) in the bioCHEMeleon Setup tab and clicking Start loads the demo PDB into PyMOL and starts the game (no exception).
actual: Clicking Start with target_mode=demo raises an uncaught `KeyError: 'file'` traceback in the PyMOL console. The game does not start. The error fires 8+ times in the observed session (user clicked Start repeatedly / retried).
errors: VERBATIM traceback from the PyMOL console (Windows PyMOL 2.5.0 GUI, plugin loaded from `tmp/bioCHEMeleon/biochemeleon/`):

```
Traceback (most recent call last):
  File "C:\Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/tmp/bioCHEMeleon\biochemeleon\__init__.py", line 90, in _on_start
    controller, target_obj, _ = self._prepare_and_start(state)
  File "C:\Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon\tmp\bioCHEMeleon\biochemeleon\__init__.py", line 142, in _prepare_and_start
    target_obj = demos.load_demo(demo_id)
  File "C:\Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon\tmp\bioCHEMeleon\biochemeleon\demos.py", line 128, in load_demo
    path = os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])
KeyError: 'file'
```

(Repeated 8 times across the session — each Start click re-triggered it.)

reproduction:
1. Launch Windows PyMOL (`setenv.bat` -> `pymol`).
2. Load the bioCHEMeleon plugin (Plugin Manager -> point at the biochemeleon/ path).
3. In the Setup tab, set target_mode = **demo** (bundled demo mode), pick any demo id from the combo.
4. Click **Start**.
5. Observe: `KeyError: 'file'` traceback in the PyMOL console; game does not start.
started: Pre-existing on `main` (user confirmed: "main also has this issue"). Introduced by an earlier phase (NOT Phase 11). Phase 11 work is on branch `exec/11` (worktree `tmp/exec-11`); this bug reproduces on BOTH `main` and `exec/11`, so it is independent of the Phase 11 cartoon/ribbon refactor.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-08-16T00:00:00Z
  checked: `biochemeleon/demos.py:114-137` (load_demo) on `exec/11` worktree
  found: |
    `load_demo(demo_id)` does:
      meta = DEMO_MANIFEST.get(demo_id)         # line 125 -- returns None if id missing
      if meta is None: return None              # line 126-127 -- handles missing id
      path = os.path.join(..., 'data', 'demos', meta['file'])  # line 128 -- <-- KeyError HERE
      if not os.path.exists(path): return None  # line 129-130
      win_path = to_windows_path(path)          # line 131
      ...
      try: cmd.load(win_path, object=obj_name, zoom=1)  # line 133-134
      except Exception: return None                      # line 135-136
    The `try/except` wraps ONLY `cmd.load`. The `meta['file']` access at line 128 is OUTSIDE the try block, so a missing 'file' key raises an UNCAUGHT KeyError that propagates to `_prepare_and_start` (line 142) -> `_on_start` (line 90).
  implication: The bug is a schema mismatch between `DEMO_MANIFEST` entries and `load_demo`'s `meta['file']` access. The defensive `try/except` does not cover this line. Two fix angles: (a) fix the schema (make manifest entries have 'file'), or (b) widen the guard (but the real bug is the schema).

- timestamp: 2026-08-16T00:00:00Z
  checked: `biochemeleon/__init__.py:136-146` (the demo-mode branch of `_prepare_and_start`) on `exec/11`
  found: |
    elif mode == "demo":
        demo_id = state.get("demo_id", "")
        target_obj = demo_id.lower() if demo_id else ""
        if not target_obj or target_obj not in demos.list_loaded_molecule_objects():
            target_obj = demos.load_demo(demo_id)   # line 142 -- calls the buggy fn
            if target_obj is None:                   # line 143 -- expects None on failure
                QtWidgets.QMessageBox.warning(...)   # line 144-145
                return None, None, []
    `_prepare_and_start` EXPECTS `load_demo` to return None on failure (line 143 checks `if target_obj is None`). But `load_demo` RAISES KeyError instead of returning None when 'file' is missing — so the None-check never fires and the traceback propagates. This confirms the contract violation: `load_demo`'s docstring says "Returns ... None on failure" but it raises on a schema gap.
  implication: The fix should restore the documented contract — either the manifest has 'file' (so the happy path works) AND/OR the loader catches the KeyError (so the None-on-failure contract holds even for malformed entries).

- timestamp: 2026-08-16T01:25:00Z
  checked: `biochemeleon/setup_state.py:34-57` (DEMO_MANIFEST) on `main`
  found: |
    Every manifest entry uses the Phase 9 uniform schema with keys:
      {category, type, difficulty, source, source_id, fetch_url,
       cache_name, citation, strip}
    There is NO `'file'` key in ANY entry. The on-disk filename is `'cache_name'`
    (e.g. '1znf.pdb' bundled, '1gzm.pdb.gz' fetched). The `'source'` field
    ('bundled'/'memprotmd'/'sasbdb') drives the loader branch (comment lines
    29-30: bundled -> data/demos/, fetched -> tmp/phase9-demos/cache/). 6 bundled
    + 3 fetched = 9 entries. `tests/test_setup_state.py` TestManifestSchemaPhase9
    (lines 494-499) and TestDemoManifest (lines 117-123) ASSERT this 9-key schema
    with `cache_name` -- so `cache_name` is the canonical, tested schema.
  implication: Hypothesis #1 (SCHEMA DRIFT) CONFIRMED, but more precisely: it is a
    half-completed migration. The manifest was migrated to `cache_name` (Plan 09-01)
    but `load_demo` was never migrated (Plan 09-02 never ran). The fix is in the
    LOADER (`demos.py`), not the manifest (the manifest is correct + tested).

- timestamp: 2026-08-16T01:26:00Z
  checked: `biochemeleon/gui_setup.py:122-128` (demo combo population) on `main`
  found: |
    The combo reads `meta['category']` and `meta['difficulty']` -- both EXIST in
    the Phase 9 schema. So the combo populates correctly for all 9 demos (no drift
    there). Only `demos.load_demo` reads the non-existent `meta['file']`.
  implication: The drift is isolated to `load_demo`. `gui_setup.py` needs no change.

- timestamp: 2026-08-16T01:27:00Z
  checked: `biochemeleon/data/demos/` + `tmp/phase9-demos/` + grep for a fetched-demo loader across `biochemeleon/`
  found: |
    - `data/demos/` contains the 6 bundled demos as `<did>.pdb` (1k8p/1xdn/1znf/
      2qbz/4wb3/5e54) + SOURCES.md. So the bundled happy-path files EXIST and match
      `cache_name` exactly.
    - `tmp/phase9-demos/` has NO `cache/` subdir and NO `1gzm.pdb.gz`/`3gp6.pdb.gz`.
      Only raw SASDPG4 `.pdb` files (not `.pdb.gz`, not in `cache/`). The fetched
      cache is incomplete/absent.
    - grep `cache_name|fetch_url|phase9|cache/|load_cached|fetch_demo` across
      `biochemeleon/` found matches ONLY in `setup_state.py` (the manifest def).
      NO function reads `cache_name`, branches on `source`, reads
      `tmp/phase9-demos/cache/`, decompresses `.gz`, or strips residues. The Phase 9
      fetched-demo loader (download_large_demo/finalize_large_demo/load_cached_demo)
      was NEVER implemented.
  implication: The full fetched-demo loading (network fetch + .pdb.gz cache +
    decompress + strip + Qt progress dialog) is a large UNIMPLEMENTED feature
    (Plans 09-02 + 09-03). Out of scope for this KeyError bug fix. The scoped fix
    migrates `load_demo`'s bundled path to `cache_name` (the 09-02 mandate for the
    bundled path) + makes fetched demos return None gracefully (cache miss) instead
    of crashing. Fetched demos become a known limitation (graceful "Could not load
    demo" message) until 09-02/09-03 are executed.

- timestamp: 2026-08-16T01:28:00Z
  checked: `.planning/phases/09-large-demo-fetch-source-attribution/09-01-SUMMARY.md` + `09-02-PLAN.md`
  found: |
    09-01-SUMMARY.md lines 120+131 explicitly document the `meta['file']` -> `meta['cache_name']`
    migration as "the intended 09-02 migration surface, NOT a 09-01 issue" and state
    "09-02 MUST migrate `meta['file']` -> `meta['cache_name']` and add the source-based
    loader branching". 09-02-PLAN.md Task 1 step 9 prescribes the exact `load_demo`
    change: branch on `meta.get('source','bundled')`; bundled -> data/demos/{cache_name};
    fetched -> load_cached_demo (cache hit) or None (cache miss). NO `09-02-SUMMARY.md`
    exists -- 09-02 was never executed. 09-03-PLAN.md depends_on 09-02 (also unrun).
  implication: This bug is a known, documented deferred migration that was never
    completed. The scoped fix implements exactly the 09-02 `load_demo` migration for
    the bundled path (the part that fixes the reported crash) and stubs the fetched
    branch to None (since load_cached_demo + the fetch worker don't exist yet).

## Resolution

root_cause: Half-completed Phase 9 migration. Plan 09-01 (merged to main) renamed the `DEMO_MANIFEST` key `file` -> `cache_name` and added a `source` field, but Plan 09-02 (which was supposed to migrate `demos.load_demo` to use `cache_name` + add source-based fetched-demo fetching) was never executed. `load_demo` (demos.py:128) still reads `meta['file']`, which no longer exists in any manifest entry, so it raises an UNCAUGHT `KeyError: 'file'` for every demo Start. The KeyError propagates through `_prepare_and_start` (line 142) -> `_on_start` (line 90) because `load_demo`'s try/except wraps only `cmd.load`, not the `meta['file']` subscript. The 09-01-SUMMARY explicitly flagged this as "the intended 09-02 migration surface".
fix: Migrate `demos.load_demo` per 09-02-PLAN Task 1 step 9 (bundled path only; fetched branch stubbed to None since the fetch worker is unimplemented): (1) `meta['file']` -> `meta.get('cache_name')` with a None guard; (2) branch on `meta.get('source','bundled')` -- fetched demos return None (graceful cache-miss, no crash); (3) keep the bundled path (`data/demos/{cache_name}` -> cmd.load) unchanged; (4) update the docstring to document the source branching + the unimplemented fetched-demo fetch worker. No manifest change (cache_name is already the canonical tested schema). No gui_setup change (combo reads category/difficulty, both correct).
verification: |
  Headless smoke (smoke/diag_demo_keyerror.py) via the WSL->Windows PyMOL 2.5.0
  bridge, run TWICE (stability), 12/12 PASS, exit 0 both times:
    - Schema reality confirmed: no 'file' key on any entry; 'cache_name' on all.
    - All 6 BUNDLED demos load (return lowercase obj name + atoms>0):
      1znf=424, 5e54=2844, 1k8p=555, 1xdn=2597, 2qbz=3408, 4wb3=3779 atoms.
      [Pre-fix, the very first call load_demo('1znf') raised KeyError: 'file'.]
    - All 3 FETCHED demos return None gracefully (no crash; fetch worker unimplemented).
    - Unknown id 'bogus-id' returns None (None-on-failure contract honored).
  Regression: python3.6 -m unittest tests.test_setup_state -v -> 112/112 OK (no
    schema change; cache_name was already the canonical tested schema). py_compile
    all modules OK. Pitfall-1 gate 0 matches. exec_ gate: only gui_game.py:303
  QMessageBox.exec_() (pre-existing, unrelated). GUI human-verify (demo Start
  loads PDB + starts game in a real Windows PyMOL session) remains a checkpoint.
files_changed: [biochemeleon/demos.py, smoke/diag_demo_keyerror.py]

## Context for the next agent

**Where to work:** This bug is PRE-EXISTING on `main` and independent of Phase 11. The user has NOT specified a worktree. Recommend investigating on `main` directly (read-only investigation) and applying the fix on `main` (or a fresh branch off `main`) since this is not Phase 11 work. If you prefer isolation, create a new worktree: `git worktree add tmp/debug-demo-keyerror -b fix/demo-keyerror` from the main repo. DO NOT work in `tmp/exec-11` — that worktree is for Phase 11 and is about to be merged; mixing this unrelated fix there would entangle the branches.

**Key files to read (on main, same paths as exec/11 since this bug is shared):**
- `biochemeleon/setup_state.py:34` — `DEMO_MANIFEST` definition (CONFIRM the actual key schema of each entry; this is the #1 unknown).
- `biochemeleon/demos.py:114-137` — `load_demo` (the buggy `meta['file']` access + the too-narrow `try/except`).
- `biochemeleon/gui_setup.py:122-125` — the Setup-tab combo population (`for did, meta in DEMO_MANIFEST.items()` — see which keys the combo reads; if it reads a different key than 'file', that's the drift smoking gun).
- `biochemeleon/__init__.py:90,136-146` — `_on_start` and the demo branch of `_prepare_and_start` (the call site + the None-on-failure contract).

**AGENTS.md rules that apply:**
- `setup_state.py` is the PURE layer (stdlib only, no `from pymol import cmd`, no Qt). If the fix touches `DEMO_MANIFEST`, keep it pure. `demos.py` is the cmd bridge (imports from setup_state, uses pymol.cmd).
- Pure-layer unit tests: `python3.6 -m unittest tests.test_setup_state -v` must stay green. There may be existing tests asserting the DEMO_MANIFEST schema — check `tests/test_setup_state.py` for `DEMO_MANIFEST` references and update them if the schema changes.
- Pitfall-1 grep gate: 0 matches. exec_ gate: only on QFileDialog/QMessageBox.
- Headless verification IS possible for this bug: the `load_demo` path is pure `pymol.cmd` + `os.path` (no Qt). A headless script can iterate `DEMO_MANIFEST` ids, call `demos.load_demo(did)` for each, and assert (a) no KeyError, (b) returns a valid obj name or None. Run via the WSL->Windows bridge:
  ```bash
  bash wsl2win_cp.sh
  mkdir -p tmp/bioCHEMeleon/smoke && cp <your_diag_script>.py tmp/bioCHEMeleon/smoke/
  cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\<your_diag_script>.py" 2>&1 | tail -50
  ```
  GUI final check (does the demo actually LOAD and the game START) is a human-verify checkpoint.

**Hypothesis ranking (investigate in this order):**
1. SCHEMA DRIFT (most likely): `DEMO_MANIFEST` entries use a key other than `'file'` (e.g. `'path'`, `'pdb'`, `'filename'`) and `load_demo` was not updated when the schema changed. Fix: align the key (prefer renaming in the loader to match the manifest, OR rename the manifest key to `'file'` — pick whichever minimizes test churn). Cross-check `gui_setup.py:125` to see which key the combo population reads — if it reads the SAME wrong key as `load_demo`, then the manifest was renamed and BOTH call sites drifted; if it reads a DIFFERENT key, only `load_demo` drifted.
2. NESTED/PARTIAL ENTRY: one specific demo id (e.g. a placeholder added for a not-yet-bundled PDB) has an entry without 'file'. Fix: complete the entry OR have `load_demo` skip entries without 'file' (return None).
3. NONE-CONTRACT GAP (defensive, layer on top of the real fix): `load_demo`'s `try/except` should cover the `meta['file']` access (and the `os.path.exists` check) so a malformed entry returns None per the docstring instead of raising. This is defense-in-depth, NOT the primary fix.

**Deliverable:** A minimal fix that makes `load_demo` honor its "Returns None on failure" contract for ALL manifest entries AND resolves the schema mismatch so the happy path works. Headless test iterating all `DEMO_MANIFEST` ids passing. Smoke green. GUI human-verify: demo mode Start loads the PDB and starts the game.
