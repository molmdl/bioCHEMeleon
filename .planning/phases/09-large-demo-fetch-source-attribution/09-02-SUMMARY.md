---
phase: 09-large-demo-fetch-source-attribution
plan: 02
subsystem: cmd-layer
tags: [pymol, cmd, urllib, fetch, cache, pdb-gz, strip, memprotmd, sasbdb, headless-smoke, pitfall-6]

# Dependency graph
requires:
  - phase: 09-large-demo-fetch-source-attribution
    plan: 01
    provides: "Extended DEMO_MANIFEST (9 entries, cache_name field), STRIP_RESN_MEMPROTMD, strip_resn_from_pdb pure helper, TIER_LABELS -- the pure-layer foundation 09-02 imports + branches on"
  - phase: 09-research
    provides: "09-RESEARCH-pipeline.md (split API design, .pdb.gz cache, Pitfall 6 worker pattern), -memprotmd.md (pure-Python strip BEFORE cmd.load), -sasbdb.md (strip=False, glycan preserved)"
provides:
  - "demos.py split API: download_large_demo (worker, urllib-only, Pitfall 6), finalize_large_demo (main, cmd.load + pure strip for MemProtMD + cmd.save .pdb.gz cache), load_cached_demo (main cache hit), cache_path_for/is_cached/_cache_dir, temp_download_path/cleanup_temp"
  - "load_demo source-branching: bundled -> data/demos (cache_name field); fetched -> load_cached_demo (hit) or None (miss signals caller to fetch)"
  - "smoke/phase9_smoke.py: 49-check headless verification of the full fetch+strip+compress+cache round-trip"
affects: [09-03 (gui_setup.py demo_combo + __init__.py _resolve_large_demo orchestrate download_large_demo via QTimer drain + finalize_large_demo on main thread + QProgressDialog), 09-04 (DATA_SOURCES.md citations cross-ref the cache_name/source fields)]

# Tech tracking
tech-stack:
  added: []  # stdlib only (os, threading, queue, urllib.request) -- no new libraries; demos.py stays Qt-free
  patterns:
    - "Split API: Qt-free cmd-layer primitives (demos.py) + Qt orchestration (__init__.py 09-03). Worker (urllib only, NO cmd.*) posts to a queue; main-thread QTimer drain calls finalize (cmd.*). Pitfall 6 compliant."
    - "Pure-Python strip BEFORE cmd.load for MemProtMD: the 09-01 strip_resn_from_pdb helper filters SOL/NA/CL ATOM lines so the ~95k-atom wet file never enters PyMOL (avoids Pitfall 12). The dry ~19k-atom result is what cmd.load sees."
    - ".pdb.gz cache via cmd.save (native gzip -- exporting.py:912). cmd.load reads .pdb.gz natively (internal.py:278-308 gzip magic detection). No stdlib gzip step needed."
    - "Cache-miss-as-None signaling: load_demo returns None for a fetched cache miss so the Qt caller (__init__._resolve_large_demo) can trigger the fetch. Bundled demos + cache hits return the obj name."

key-files:
  created:
    - "smoke/phase9_smoke.py -- 49-check headless smoke (pure pymol.cmd.*, NO Qt); sections SETUP/A-F + summary"
  modified:
    - "biochemeleon/demos.py -- added 8 functions (download_large_demo, finalize_large_demo, load_cached_demo, cache_path_for, is_cached, _cache_dir, temp_download_path, cleanup_temp) + branched load_demo on meta['source']; migrated meta['file'] -> meta['cache_name'] (09-01 rename); module docstring updated"

key-decisions:
  - "Pure-Python strip BEFORE cmd.load for MemProtMD (09-RESEARCH-memprotmd.md:247-282 PRIMARY recommendation) over the pipeline research's cmd.remove(solvent)+cmd.remove(inorganic) after-load approach. The pure helper avoids loading the 95k-atom wet file into PyMOL entirely (Pitfall 12), is deterministic (resn line-filter, not selector classification faith), and is flag-independent (MemProtMD records SOL/NA/CL as ATOM not HETATM)."
  - "SASBDB strip=False skips the strip entirely -- glycan HETATM preserved (09-RESEARCH-sasbdb.md:257-259 CAUTION: a blanket hetatm removal would nuke the 2601 glycan atoms). finalize_large_demo gates the strip on BOTH meta['strip'] AND meta['source']=='memprotmd'."
  - "temp_download_path uses a deterministic tmp/phase9-demos/<id>.raw path (not tempfile.mkstemp) for traceability -- a .raw file survives an interrupted fetch for inspection."
  - "Cache write failure is non-fatal in finalize_large_demo (the object is already loaded; the next fetch re-downloads). os.makedirs(cache_dir, exist_ok=True) is wrapped in try/except -- if the cache dir is unavailable, the object still loads (success)."
  - "download_large_demo docstring reworded to avoid literal 'cmd.*' token (AGENTS.md false-positive pattern; mirrors 03-02/03-06/03-09/03-10 + 06-01 precedent) so the Pitfall 6 grep check is unambiguous."

patterns-established:
  - "Worker/main split for fetched demos: download_large_demo (worker, stdlib only) -> queue -> finalize_large_demo (main, cmd.*) -> cache. The Qt layer's QTimer drain (09-03) is the bridge."
  - "finalize_large_demo strip dispatch: if meta['strip'] and source=='memprotmd' -> pure strip_resn_from_pdb to a .dry temp -> cmd.load(.dry) -> cleanup_temp(.dry); else -> cmd.load(downloaded_path) as-is."

# Metrics
duration: 7min
completed: 2026-08-16
---

# Phase 9 Plan 02: Demos Split API + Headless Smoke Summary

**Built the Qt-free cmd-layer split API in `demos.py` (download/finalize/load_cached/cache helpers) + branched `load_demo` on the manifest source, verified by a 49-check headless smoke that exercises the full SASBDB fetch+strip+compress+cache round-trip + the MemProtMD pure strip helper.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-08-16T09:46:01Z
- **Completed:** 2026-08-16T09:52:34Z
- **Tasks:** 2 (both `type="auto"`)
- **Files modified:** 1 (`biochemeleon/demos.py`); **Files created:** 1 (`smoke/phase9_smoke.py`)

## Accomplishments
- Extended `biochemeleon/demos.py` with the 8-function split API the 09-03 Qt orchestration will drive: `download_large_demo` (worker thread, urllib-only, Pitfall 6 compliant -- NO `cmd.*`, NO `from pymol`), `finalize_large_demo` (main thread, `cmd.load` + pure `strip_resn_from_pdb` for MemProtMD BEFORE load + `cmd.save` `.pdb.gz` cache), `load_cached_demo` (main cache hit), `cache_path_for`/`is_cached`/`_cache_dir` (pure path helpers), `temp_download_path`/`cleanup_temp` (temp-file management).
- Branched the existing `load_demo` on `meta.get('source', 'bundled')`: bundled -> `data/demos/{cache_name}` (the existing Phase 2 path, migrated `meta['file']` -> `meta['cache_name']` per the 09-01 rename); fetched -> `load_cached_demo` (cache hit returns obj; cache miss returns None -- signals the Qt caller to trigger the fetch). This closes the 09-01 handoff (`demos.py:128` `meta['file']` KeyError surface is now migrated).
- The MemProtMD strip uses the 09-01 pure `strip_resn_from_pdb` helper BEFORE `cmd.load` (the MemProtMD researcher's PRIMARY recommendation), so the ~95k-atom wet file never enters PyMOL (avoids Pitfall 12). SASBDB (`strip=False`) skips the strip entirely -- the 2601 glycan HETATM atoms survive (DEMO-03).
- Wrote `smoke/phase9_smoke.py` (49 checks, pure `pymol.cmd.*` -- NO Qt; modeled on `phase8_smoke.py`). Verified the full SASBDB round-trip (4123 atoms, 2601 glycan HETATM, NAG/MAN/BMA/NAN present, `.pdb.gz` cache written + read natively), the cache-hit path, the MemProtMD pure strip helper, `load_demo` branching (bundled + fetched cache-hit + cache-miss-None), the Pitfall 6 static check (`inspect.getsource(download_large_demo)` has no `cmd.` / `from pymol`), and the cache helpers. Headless run via `cmd.exe /c run-conda-pymol.bat -cq`: 49/49 PASSED, exit 0, first run clean.
- All WSL gates green: `py_compile` both files + 112 existing unit tests (no regression) + Pitfall-1 gate ZERO package-wide + `exec_` gate unchanged at exactly 1 (`gui_game.py:303` QMessageBox -- demos.py adds NO `.exec_()`) + `from pymol.Qt` ZERO in demos.py (dependency direction intact) + `cmd.` ZERO in `download_large_demo` body (Pitfall 6).

## Task Commits

Each task was committed atomically on `main` (single-plan wave -- no worktree per AGENTS.md):

1. **Task 1 (split API + load_demo branching):** `826ddae` (`feat`) -- 8 new functions in demos.py + load_demo source-branching + `meta['file']`->`meta['cache_name']` migration + module docstring updated. 299 insertions, 27 deletions.
2. **Task 2 (headless smoke):** `e193f13` (`test`) -- smoke/phase9_smoke.py (187 lines, 49 checks). 49/49 PASSED on first headless run (no runtime bugs -- no `fix(09-02)` commits needed).

## Files Created/Modified
- `biochemeleon/demos.py` (166 -> 465 lines) -- added `import threading/queue/urllib.request`; extended the setup_state import to include `STRIP_RESN_MEMPROTMD, strip_resn_from_pdb`; added the 8 Phase 9 functions under a new `# ---- Phase 9: fetched-large-demo split API ----` section; modified `load_demo` to branch on `meta.get('source', 'bundled')` and use `meta['cache_name']` (was `meta['file']`); updated the module docstring to describe the fetched-demo API (written in PROSE to avoid grep false-positives per AGENTS.md).
- `smoke/phase9_smoke.py` (NEW, 187 lines) -- 49-check headless smoke. Sections: SETUP (manifest 9 entries + TIER_LABELS 4 tiers + strip helper on synthetic wet), A (SASBDB fetch round-trip via staged sample), B (cache-hit round-trip), C (MemProtMD strip helper), D (load_demo branching), E (download_large_demo cmd-free static check), F (cache_path_for/is_cached). Uses the staged `tmp/phase9-demos/SASDPG4_fit2_model1.pdb` sample to simulate the worker download (no real network); cleans the cache dir at the start for deterministic results.

## Decisions Made
- **Pure-Python strip BEFORE cmd.load for MemProtMD** (over the pipeline research's `cmd.remove(solvent)`+`cmd.remove(inorganic)` after-load approach). The MemProtMD researcher's PRIMARY recommendation (09-RESEARCH-memprotmd.md:247-282) is deterministic, avoids Pitfall 12 (the 95k-atom wet file never enters PyMOL), and is flag-independent (MemProtMD records SOL/NA/CL as ATOM, not HETATM, so a hetatm-keyed selector would miss them). The 09-01 `strip_resn_from_pdb` helper does the line-filter; `finalize_large_demo` writes the dry result to a `.dry` temp, loads that, then cleans it up.
- **SASBDB strip=False skips the strip entirely.** The 2601 glycan HETATM atoms must survive (DEMO-03). `finalize_large_demo` gates the strip on `meta.get('strip', False) and meta.get('source') == 'memprotmd'` -- SASBDB (strip=False, source=sasbdb) loads the downloaded file as-is. This avoids the 09-RESEARCH-sasbdb.md:257-259 CAUTION (a blanket hetatm removal would nuke glycans).
- **Cache write failure is non-fatal.** If `os.makedirs(cache_dir)` or `cmd.save(cache_path)` fails, the object is already loaded (the `cmd.load` succeeded) -- `finalize_large_demo` returns the obj name (success). The next fetch re-downloads. The cache is a performance optimization, not a correctness requirement.
- **`temp_download_path` is deterministic** (`tmp/phase9-demos/<id>.raw`, not `tempfile.mkstemp`) so an interrupted fetch leaves a traceable `.raw` file for debugging. `cleanup_temp` is idempotent (silently ignores a missing file).
- **download_large_demo docstring reworded** to avoid the literal `cmd.*` token (AGENTS.md false-positive pattern). "does NOT call cmd.*" -> "makes NO PyMOL cmd API calls". This makes the Pitfall 6 grep check (`cmd.` not in the function body) unambiguous.

## Deviations from Plan

All deviations are docstring-rewording adaptations for the grep gates (the AGENTS.md-documented false-positive pattern). None change the specified behavior; the final state matches the plan exactly.

### Docstring rewording (Rule 3 -- blocking grep-gate adaptations)

**1. Reworded `download_large_demo` docstring + module docstring to avoid literal `cmd.*` / `cmd.` tokens**
- **Found during:** Task 1 (verification)
- **Issue:** The plan's verbatim docstring text "does NOT call cmd.*" (in `download_large_demo`) and "NO cmd.* (Pitfall 6)" (in the module docstring's `download_large_demo` description) contain the literal `cmd.` token. The plan's own verify step requires `grep -n "cmd\." biochemeleon/demos.py` to show `cmd.` present ONLY in `finalize_large_demo`/`load_cached_demo`/`load_demo`/`fetch_pdb`/`get_active_reps` (NOT in `download_large_demo` -- Pitfall 6). The docstring mentions would trip this check.
- **Fix:** Reworded to "makes NO PyMOL cmd API calls" (in `download_large_demo` docstring) and "makes NO PyMOL cmd calls" (in the module docstring). The `download_large_demo` function body now has ZERO `cmd.` occurrences (verified programmatically: regex extraction of the function body, `body.count('cmd.') == 0`). Mirrors the 03-02/03-06/03-09/03-10 + 06-01 precedent.
- **Files modified:** `biochemeleon/demos.py`
- **Verification:** `python3.6 -c "import re; src=open('biochemeleon/demos.py').read(); m=re.search(r'(\ndef download_large_demo\(.*?)(?=\ndef \w)', src, re.DOTALL); print(m.group(1).count('cmd.'))"` -> `0`.

**Total deviations:** 1 docstring-rewording adaptation. No scope creep; no behavior change; no architectural changes.

## Issues Encountered
None. The headless smoke passed 49/49 on the first run (no runtime bugs -- no `fix(09-02)` commits needed). The staged SASBDB sample atom counts (4123 total, 2601 HETATM glycan) matched the research exactly; the `.pdb.gz` cache was written + read natively by `cmd.save`/`cmd.load` as the pipeline research predicted.

## User Setup Required
None for 09-02 (cmd-layer only, no external services, no real network at smoke time -- the staged SASBDB sample simulates the worker download). The real network fetch + QProgressDialog is the 09-03 human-verify checkpoint.

## Next Phase Readiness
**Ready for 09-03 (gui_setup.py demo_combo + __init__.py _resolve_large_demo):**
- `09-03` imports `demos.download_large_demo` / `finalize_large_demo` / `load_cached_demo` / `is_cached` / `temp_download_path` / `cleanup_temp` (the key_link pattern `demos.download_large_demo`).
- The Qt orchestration: `_resolve_large_demo(demo_id)` calls `load_cached_demo` (cache hit -> done); on cache miss, shows a modeless `QProgressDialog` + spawns `download_large_demo` on a daemon thread + drains the queue via `QTimer.singleShot(100, drain)`; on `('done',)` calls `finalize_large_demo` (main thread, cmd.*) + `cleanup_temp`; on `('error',)`/`('canceled',)` shows a QMessageBox / closes. See 09-RESEARCH-pipeline.md Pattern 1 for the full skeleton.
- `09-03` also imports `TIER_LABELS` from `setup_state` (09-01) for the demo_combo display text (DIFF-05).
- `load_demo` now returns None for a fetched cache miss, so `_prepare_and_start`'s existing `if target_obj is None` guard catches it -- 09-03 adds the `_resolve_large_demo` call BEFORE that guard (or replaces the `load_demo` call with a cache-check + fetch orchestration).

**Blocker / required 09-03 work (expected, not a defect):**
- The `__init__.py _prepare_and_start` flow (the Start button handler) currently calls `demos.load_demo(demo_id)` synchronously. For a fetched cache miss, this returns None -> the GUI shows "Could not load demo". 09-03 must intercept the fetched-demo case BEFORE the `load_demo` call (or catch the None + check `demos.cache_path_for`) and orchestrate the fetch via `_resolve_large_demo` (async -- the worker thread + QTimer drain). The re-entrancy after the async fetch (option (a) return early + re-enter on 'done' vs option (b) spin a QTimer drain that resumes `_prepare_and_start`) is a 09-03 planner decision (09-RESEARCH-pipeline.md Open Risk 3 recommends (b) for v1 simplicity).

**Concerns:**
- `download_large_demo` uses a 60s urllib timeout. For a slow connection to MemProtMD (7.5-9.3MB wet files), this may be tight. 09-03 could make the timeout configurable or catch the timeout error gracefully (the `('error', msg)` queue event already handles it -- shows a QMessageBox).
- The `.pdb.gz` cache is written to `tmp/phase9-demos/cache/` (repo-relative). For an installed plugin (v2), this path won't exist -- Pitfall E (09-RESEARCH-pipeline.md:215-219). Out of scope for v1 (run-from-repo per AGENTS.md).
- The smoke cleans the cache dir at the start for deterministic results. 09-03's human-verify (real fetch) will populate the cache for the first time -- the cache persists across sessions (tmp/ is a real on-disk dir, just gitignored).

---
*Phase: 09-large-demo-fetch-source-attribution*
*Completed: 2026-08-16*
