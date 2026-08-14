---
phase: 09-large-demo-fetch-source-attribution
plan: 01
subsystem: data
tags: [pymol, pdb, manifest, tdd, unit-tests, pure-python, fetch, memprotmd, sasbdb, tier-labels]

# Dependency graph
requires:
  - phase: 02-setup-tab-config
    provides: setup_state.py DEMO_MANIFEST (6 entries, 'file' key), PDB_POOL, randomize_state, validate_state — the pure layer 09-01 extends
  - phase: 09-research
    provides: 09-RESEARCH-pipeline.md (schema + TIER_LABELS + 4wb3->hard), -memprotmd.md (URLs + STRIP set), -sasbdb.md (URL + strip=False)
provides:
  - "Extended DEMO_MANIFEST: 9 entries (6 bundled + 1gzm/3gp6/sasdpg4) with the uniform fetch-source schema (source/source_id/fetch_url/cache_name/citation/strip)"
  - "TIER_LABELS display map (4 identifier-safe tiers -> Easy/Hard/Challenge/Very challenging) for DIFF-05"
  - "STRIP_RESN_MEMPROTMD = {'SOL','NA','CL'} + pure strip_resn_from_pdb(text, strip_set) PDB ATOM-line residue-name filter"
  - "Offline-safe randomize_state (non-lock 'demo' pick excludes fetched demos)"
  - "4wb3 difficulty 'mixed' -> 'hard'"
affects: [09-02 (demos.py fetch worker imports strip_resn_from_pdb + STRIP_RESN_MEMPROTMD + extended manifest), 09-03 (gui_setup.py demo_combo imports TIER_LABELS), 09-04 (DATA_SOURCES.md citations cross-ref the manifest 'citation' fields)]

# Tech tracking
tech-stack:
  added: []  # stdlib only (random, copy) — no new libraries; setup_state.py stays pure
  patterns:
    - "Uniform 9-key manifest schema with a lowercase 'source' vocabulary (bundled/memprotmd/sasbdb) driving the loader branch"
    - "Padding-agnostic PDB residue-name parsing: line[17:20].strip() (cols 18-20) so 'NA '/' NA'/'NA' all match"
    - "Pure-Python ATOM-line strip (not PyMOL solvent/inorganic selectors) so the wet ~95k-atom PDB never enters the viewer"
    - "Offline-safe randomize: random pick draws only from source=='bundled'; lock_source overrides the exclusion"

key-files:
  created: []
  modified:
    - "biochemeleon/setup_state.py — extended manifest + TIER_LABELS + STRIP_RESN_MEMPROTMD + strip_resn_from_pdb + offline-safe randomize"
    - "tests/test_setup_state.py — 8 new Phase 9 test classes (22 tests) + migrated TestDemoManifest to the new schema"

key-decisions:
  - "4wb3 'mixed' -> 'hard' (09-RESEARCH-pipeline.md:422; 4wb3 is a mid-complexity 3779-atom protein/NA hybrid, not a large-demo tier)"
  - "Lowercase 'source' vocabulary: normalized SASBDB researcher's uppercase 'SASBDB' to 'sasbdb' for pipeline-schema consistency (bundled/memprotmd/sasbdb)"
  - "Tier-ordered the ENTIRE manifest (easy->hard->challenge->very_challenging) rather than only appending the 3 new entries, so the demo combo shows a natural difficulty progression (research rec, pipeline:458-459)"
  - "SASDPG4 strip=False (glycan HETATM must survive — 09-RESEARCH-sasbdb.md:257); MemProtMD 1gzm/3gp6 strip=True (SOL/NA/CL)"
  - "citation field = short uppercase ref (1GZM/SASDPG4/...) for now; full citation strings live in DATA_SOURCES.md (09-04)"
  - "strip_resn_from_pdb filters ONLY 'ATOM' lines (HETATM/TITLE/CRYST1/MODEL/TER/ENDMDL preserved unconditionally)"

patterns-established:
  - "Manifest entry shape: {category, type, difficulty, source, source_id, fetch_url, cache_name, citation, strip} — the uniform schema every Phase 9 consumer reads"
  - "cache_name replaces 'file': bundled uses data/demos/{cache_name} (plain .pdb); fetched uses tmp/phase9-demos/cache/{cache_name} (.pdb.gz)"
  - "TIER_LABELS[meta['difficulty']] is the single mapping from identifier-safe tier to display label (gui_setup.py 09-03 uses it for the demo_combo text)"

# Metrics
duration: 25min
completed: 2026-08-14
---

# Phase 9 Plan 01: Pure-Layer Foundation Summary

**Extended DEMO_MANIFEST to 9 entries with the fetch-source schema, added TIER_LABELS + a pure strip_resn_from_pdb helper, and made randomize_state offline-safe — the stdlib-only foundation 09-02 (demos.py) and 09-03 (gui_setup.py) build on.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-14T01:05:22Z
- **Completed:** 2026-08-14T01:30:42Z
- **Tasks:** 3 (RED, GREEN, REFACTOR-skipped)
- **Files modified:** 2 (`biochemeleon/setup_state.py`, `tests/test_setup_state.py`)

## Accomplishments
- Built the Phase 9 pure-layer foundation in TDD (RED -> GREEN -> REFACTOR-skipped): 9-entry `DEMO_MANIFEST` with the uniform fetch-source schema, `TIER_LABELS`, `STRIP_RESN_MEMPROTMD`, the pure `strip_resn_from_pdb` helper, and an offline-safe `randomize_state`.
- Resolved the Phase 2 deferral: `4wb3` difficulty `mixed` -> `hard` (09-RESEARCH-pipeline.md:422).
- Added the 3 fetched demos with research-verified URLs: 1gzm + 3gp6 (MemProtMD `at.pdb`, very_challenging, strip=True) and sasdpg4 (SASBDB `SASDPG4_fit2_model1.pdb`, challenge, strip=False — glycan HETATM survives).
- 112 unit tests pass (90 existing + 22 new) in WSL with no PyMOL; the module stays pure (stdlib only — `random`, `copy`; purity gate ZERO; Pitfall-1 gate ZERO).

## Task Commits

Each TDD phase was committed atomically on `exec/09-01`:

1. **Task 1 (RED): failing tests** — `475dd9d` (`test`) — 8 new test classes / 22 tests covering manifest schema, fetch URLs, tier labels, tier assignment, 4wb3->hard, SASBDB strip=False, randomize exclusion, strip helper.
2. **Task 2 (GREEN): implementation** — `4673604` (`feat`) — extended manifest + TIER_LABELS + STRIP_RESN_MEMPROTMD + strip_resn_from_pdb + offline-safe randomize; migrated existing TestDemoManifest to the new schema; consolidated the RED import wrapper.
3. **Task 3 (REFACTOR): skipped** — no commit. The suggested refactors (a manifest docstring noting the Phase 9 schema + tier-ordering comments) were already incorporated in the GREEN commit; the only remaining nit was cosmetic brace-spacing, not worth a commit.

## Files Created/Modified
- `biochemeleon/setup_state.py` — pure layer (stdlib only). Extended `DEMO_MANIFEST` to 9 entries (renamed `file`->`cache_name` across all entries; added `source`/`source_id`/`fetch_url`/`citation`/`strip`; tier-ordered; 4wb3 `mixed`->`hard`). Added `TIER_LABELS`, `STRIP_RESN_MEMPROTMD`, `strip_resn_from_pdb`. Changed `randomize_state`'s non-lock `demo` pick to exclude fetched demos. Updated the manifest docstring (citations now repo-root `DATA_SOURCES.md`, DEMO-04).
- `tests/test_setup_state.py` — added 8 Phase 9 test classes (TestManifestSchemaPhase9, TestFetchUrls, TestTierLabels, TestTierAssignment, Test4wb3MappedToHard, TestStripFalseForSasbdb, TestRandomizeExcludesFetched, TestStripResnFromPdb); migrated the existing TestDemoManifest to the 9-entry / 9-key / `cache_name` / `4wb3=hard` schema; consolidated the import block.

## Decisions Made
- **Tier-order the whole manifest** (easy: 1znf/5e54/1k8p; hard: 1xdn/2qbz/4wb3; challenge: sasdpg4; very_challenging: 1gzm/3gp6) rather than only appending the 3 new entries — the "natural progression" rationale (and research pipeline:458-459) only holds if the entire list is tier-ordered. No test asserts order; insertion-ordered dict drives the combo.
- **Lowercase `source` vocabulary** (`bundled`/`memprotmd`/`sasbdb`) — normalized the SASBDB researcher's uppercase `SASBDB` to `sasbdb` per the pipeline schema (pipeline:411).
- **citation = short uppercase ref** (`1GZM`, `SASDPG4`, ...), matching `source_id` for now. 09-04 writes the full citation strings to `DATA_SOURCES.md`; the manifest `citation` field is the cross-ref key.
- **strip_resn_from_pdb filters only `ATOM` lines** — HETATM/TITLE/CRYST1/MODEL/TER/ENDMDL/END/REMARK preserved unconditionally (matches the research: MemProtMD records SOL/NA/CL as ATOM, so a HETATM-keyed filter would miss them; a water-residue HETATM line like HOH is NOT stripped by this helper).

## Deviations from Plan

All deviations are test-infrastructure / spec-interpretation adaptations necessary for the TDD flow to satisfy the plan's own verify criteria. None change the specified behavior; the final state matches the plan exactly.

### Test-infrastructure adaptations

**1. RED import wrapper (try/except) instead of adding names directly to the top import block**
- **Found during:** Task 1 (RED)
- **Issue:** The plan said to add `TIER_LABELS, STRIP_RESN_MEMPROTMD, strip_resn_from_pdb` to the top `from biochemeleon.setup_state import (...)` block. But at RED those names do not yet exist in `setup_state.py`, so adding them directly would make the whole test module fail to import — breaking the plan's RED verify "existing 90 tests still pass (no regression)".
- **Fix:** Imported the 3 new names via a `try/except ImportError: pass` wrapper at RED so the existing 90 tests stay importable/runnable while the new classes fail (NameError) on the unbound names. At GREEN, after the names exist, consolidated them into the single main import block and removed the wrapper — clean final state matching the plan's intent.
- **Files modified:** `tests/test_setup_state.py`
- **Verification:** RED ran 112 tests with 21 new failing/erroring and existing 90 green; GREEN ran 112 all-pass.

**2. Padding tests use column-aligned PDB lines (not the plan's literal example strings)**
- **Found during:** Task 1 (RED)
- **Issue:** The plan's example padding strings (e.g. `"ATOM  1  N   NA      3\n"`) are not PDB-column-aligned, so `line[17:20]` would not capture `"NA"` — using them literally would make the tests fail even after a correct column-based implementation (GREEN could never pass).
- **Fix:** Added a `_atom_line(resn_field)` test helper that builds a column-aligned ATOM line placing the resn exactly in PDB cols 18-20 (`line[17:20]`), with sanity assertions (`assertEqual(line[17:20], "NA ")` / `" NA"`) proving the alignment. This tests the actual specified behavior (`line[17:20].strip()` padding-agnostic) rather than the imprecise example.
- **Files modified:** `tests/test_setup_state.py`
- **Verification:** `test_padding_trailing_space` / `test_padding_leading_space` assert the exact column slice then assert the line is stripped to `"\n"`.

### Schema-migration note (not a deviation — authorized by `files_modified`)

**3. GREEN updated the existing TestDemoManifest tests to the new schema**
- **Context:** The plan's GREEN task body said `files: biochemeleon/setup_state.py`, but the schema migration the plan mandates (rename `file`->`cache_name`, 6->9 entries, 4wb3 `mixed`->`hard`) breaks the existing `TestDemoManifest` tests (they asserted the old 4-key / 6-entry / `mixed` shape). The plan's GREEN verify requires "ALL tests pass".
- **Action:** Updated the existing `TestDemoManifest` class to the new schema (9 ids, 9 keys, `cache_name`, `4wb3=hard`, bundled `<did>.pdb` / fetched `.pdb.gz` cache_name pattern) in the same GREEN commit. Both files are listed in the plan's `files_modified` frontmatter, so this is in-scope.
- **Files modified:** `tests/test_setup_state.py` (GREEN commit)

**Total deviations:** 2 test-infrastructure adaptations + 1 authorized schema-migration note. No scope creep; no behavior change beyond the plan's specified schema.

## Issues Encountered
None. (The `demos.py:128` `meta['file']` reference is now a runtime `KeyError` surface after the `file`->`cache_name` rename — this is the intended 09-02 migration surface, NOT a 09-01 issue; see Next Phase Readiness.)

## User Setup Required
None — pure-layer only, no external services, no network at test time (the fetch URLs are stored as strings; the actual fetch is 09-02's runtime concern).

## Next Phase Readiness
**Ready for 09-02 (demos.py) and 09-03 (gui_setup.py):**
- `09-02` imports `DEMO_MANIFEST`, `strip_resn_from_pdb`, `STRIP_RESN_MEMPROTMD` from `setup_state` (key_link pattern `from .setup_state import ... strip_resn_from_pdb`).
- `09-03` imports `TIER_LABELS` and maps `meta['difficulty']` -> display label for the demo_combo text (key_link pattern `TIER_LABELS.get(meta['difficulty'])`).

**Blocker / required 09-02 migration (expected, not a defect):**
- `biochemeleon/demos.py:128` still reads `meta['file']` for the bundled `load_demo` path. After 09-01's `file`->`cache_name` rename this is a runtime `KeyError` surface. `py_compile` stays green (subscript is syntactically valid) and the WSL unit tests do not exercise `demos.py` (cmd-coupled), so 09-01's WSL verification is unaffected — but **09-02 MUST migrate `meta['file']` -> `meta['cache_name']`** and add the source-based loader branching (`bundled` -> `data/demos/`; fetched -> `tmp/phase9-demos/cache/` + the fetch worker). This is the planned 09-01 -> 09-02 dependency.

**Concerns:**
- The `source` vocabulary is lowercase; any consumer comparing against uppercase (`'SASBDB'`) will silently mismatch. 09-02/09-03 should use the lowercase values (`'bundled'`/`'memprotmd'`/`'sasbdb'`) and prefer `meta.get('source', 'bundled')` for backward-compat with any unmigrated caller.
- `strip_resn_from_pdb` is padding-agnostic via `line[17:20].strip()`; it relies on PDB column alignment. Non-PDB / malformed ATOM lines shorter than 20 chars are kept (Python slicing returns the tail, stripped — not in the strip set). Acceptable for the curated MemProtMD feed; 09-02 should not feed arbitrary text into it.

---
*Phase: 09-large-demo-fetch-source-attribution*
*Completed: 2026-08-14*
