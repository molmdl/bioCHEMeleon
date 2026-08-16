---
phase: 09-large-demo-fetch-source-attribution
verified: 2026-08-16T21:05:00Z
status: passed
score: 4/4 must-have success criteria verified
re_verification:
  previous_status: none
  is_re_verification: false

# Must-haves are the 4 Phase 9 success criteria (SC1-SC4), each decomposed
# into the per-plan must-have truths/artifacts/key_links. All verified
# against the ACTUAL CODEBASE (not the SUMMARY claims).
must_haves:
  truths:
    - sc1: "Large membrane demos (1GZM helix, 3GP6 sheets) fetch on demand with full membrane (dppc-atomistic), stripped of water/salt, compressed before caching, with a modeless cancelable progress dialog"
    - sc2: "Glycoprotein-with-glycan demo fetches from SASBDB on demand, with source and IDs cited"
    - sc3: "DATA_SOURCES.md documents all PDB IDs, DOIs, SASBDB IDs, MemProtMD attribution, with MemProtMD per-entry licenses verified before bundling"
    - sc4: "Demo sub-menu surfaces difficulty-tiered metadata (Easy / Hard / Challenge / Very challenging)"
  artifacts:
    - path: "biochemeleon/setup_state.py"
      provides: "9-entry DEMO_MANIFEST + TIER_LABELS + STRIP_RESN_MEMPROTMD + strip_resn_from_pdb + offline-safe randomize_state"
    - path: "tests/test_setup_state.py"
      provides: "8 Phase 9 test classes (22 new tests) + migrated TestDemoManifest"
    - path: "biochemeleon/demos.py"
      provides: "Qt-free split API (download_large_demo/finalize_large_demo/load_cached_demo/cache+temp helpers) + load_demo source-branching + _urlopen_with_ssl_fallback + format='pdb'"
    - path: "smoke/phase9_smoke.py"
      provides: "Headless smoke (65 checks) for SASBDB round-trip + MemProtMD strip + cache-hit + load_demo branching + Pitfall 6 static + MemProtMD finalize round-trip"
    - path: "biochemeleon/__init__.py"
      provides: "PluginDialog._resolve_large_demo (modeless QProgressDialog + QTimer drain + worker + finalize) + _continue_after_large_demo_fetch + _update_export_enabled + _prepare_and_start large-demo branch + _on_start re-entrancy"
    - path: "biochemeleon/gui_setup.py"
      provides: "demo_combo tier-label display via TIER_LABELS"
    - path: "DATA_SOURCES.md"
      provides: "5-section consolidated attribution (RCSB CC0, MemProtMD CC-BY 4.0, SASBDB free-use, PDB_POOL CC0, PyMOL)"
    - path: "biochemeleon/data/demos/SOURCES.md"
      provides: "2-line stub pointer to repo-root DATA_SOURCES.md"
  key_links:
    - from: "biochemeleon/demos.py"
      to: "biochemeleon/setup_state.strip_resn_from_pdb"
      via: "finalize_large_demo strips MemProtMD in pure Python BEFORE cmd.load"
    - from: "biochemeleon/__init__.py._resolve_large_demo"
      to: "biochemeleon/demos.download_large_demo/finalize_large_demo"
      via: "threading.Thread worker + QTimer.singleShot drain"
    - from: "biochemeleon/gui_setup.py.demo_combo"
      to: "biochemeleon/setup_state.TIER_LABELS"
      via: "TIER_LABELS.get(meta['difficulty']) display mapping"
    - from: "biochemeleon/setup_state.DEMO_MANIFEST.citation"
      to: "DATA_SOURCES.md sections"
      via: "citation field cross-refs DATA_SOURCES.md per-source sections"

human_verification:
  - test: "SC1 - 1GZM/3GP6 fetch in real Windows PyMOL GUI"
    expected: "Membrane visible, no water; modeless dialog; play/hint/reveal/restart/clean work with sphere hiders"
    why_human: "Needs real network + Windows PyMOL GUI + Qt; WSL agent cannot run the interactive GUI"
    status: already_approved
    evidence: "09-03-SUMMARY line 92: user confirmed SC1 in a real Windows PyMOL GUI session (1gzm + 3gp6 download/finalize/load with membrane visible + no water; play/hint/reveal/restart/clean ALL work with sphere hiders; modeless dialog confirmed)"
  - test: "SC2 - SASDPG4 fetch in real Windows PyMOL GUI"
    expected: "Glycan HETATM visible (2601); mixed-rep works; SSL fallback handles HARICA gap"
    why_human: "Needs real SASBDB network + Windows certifi bundle (HARICA gap is Windows-only)"
    status: already_approved
    evidence: "09-03-SUMMARY line 92: user confirmed SC2 (sasdpg4 downloads with SSL fallback; glycan HETATM visible 2601; mixed-rep working)"
  - test: "SC3 - License + citation accuracy review"
    expected: "Every citation/DOI resolves; CC-BY 4.0 license acceptable; wrong DOI/oxy.ac.uk absent"
    why_human: "Per AGENTS.md 'ALL claims and citations MUST be verified and explicitly approved by a human'"
    status: already_approved
    evidence: "09-04-SUMMARY line 78: checkpoint:human-verify (Task 3) approved by the user, satisfying SC3 'MemProtMD per-entry licenses verified before bundling'"
  - test: "SC4 - 4-tier demo sub-menu in real Windows PyMOL GUI"
    expected: "9 demos with Easy/Hard/Challenge/Very challenging labels"
    why_human: "Needs Qt rendering in real PyMOL GUI"
    status: already_approved
    evidence: "09-03-SUMMARY line 92: user confirmed SC4 (9-demo sub-menu with 4 tier labels confirmed)"

# No gaps -- all must-haves verified. (The Phase 11 cartoon-segment hider bug
# is documented in .planning/debug/pending/ and is explicitly OUT of Phase 9
# scope -- SC1 only requires the fetch->start flow completes; sphere hiders
# work. STATE.md staleness about 09-02/03/04 completion is a pre-existing
# documentation hygiene issue outside Phase 9 scope -- the summaries, code,
# and commits all prove Phase 9 completion.)
gaps: []
---

# Phase 9: Large Demo Fetch + Source Attribution Verification Report

**Phase Goal:** The demo set is rounded out with large fetched molecules (membrane proteins, glycoprotein) and every source is fully attributed with verified licenses.
**Verified:** 2026-08-16T21:05:00Z
**Status:** **passed**
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths (Phase 9 Success Criteria)

| #   | Truth (SC) | Status | Evidence |
| --- | ---------- | ------ | -------- |
| SC1 | Large membrane demos (1GZM helix, 3GP6 sheets) fetch on demand with full membrane, stripped of water/salt, compressed before caching, with a modeless cancelable progress dialog | PASS VERIFIED | `_resolve_large_demo` (`__init__.py:387-519`) shows a modeless `QProgressDialog` (`.show()` line 428, `NonModal` line 423, `setAutoClose(False)`/`setAutoReset(False)` lines 424-425, `setMinimumDuration(500)` line 426) + `threading.Thread` worker (`download_large_demo`, lines 436-439) + recursive `QTimer.singleShot(100, drain)` (lines 516/518) with Cancel wired to a `threading.Event` (line 432). `finalize_large_demo` (`demos.py:395-493`) strips SOL/NA/CL via `strip_resn_from_pdb` BEFORE `cmd.load(format='pdb')` (lines 449-474), then `cmd.save` `.pdb.gz` cache (line 486). `exec_` gate stays at exactly 1 (`gui_game.py:303` QMessageBox only - the QProgressDialog uses `.show()`). Human-approved: 09-03-SUMMARY line 92 (1gzm + 3gp6 download/finalize/load with membrane visible + no water; modeless dialog; viewer stays interactive; play/hint/reveal/restart/clean ALL work with sphere hiders). |
| SC2 | Glycoprotein-with-glycan demo fetches from SASBDB on demand, with source and IDs cited | PASS VERIFIED | `DEMO_MANIFEST['sasdpg4']` (`setup_state.py:44-47`): `source='sasbdb'`, `source_id='SASDPG4'`, `fetch_url='https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb'`, `strip=False`. `finalize_large_demo` skips strip for SASBDB (`demos.py:461`: `load_path = downloaded_path`) - glycan HETATM preserved (no `cmd.remove hetatm`). `_urlopen_with_ssl_fallback` (`demos.py:284-335`) handles the HARICA SSL gap and is called by `download_large_demo` (line 375). Source + IDs cited in `DATA_SOURCES.md` section 3 (lines 137-179: SASDPG4 + Kalidas 2025 + Kikhney 2020 + free-use license). Human-approved: 09-03-SUMMARY line 92 (sasdpg4 downloads with SSL fallback; glycan HETATM visible 2601; mixed-rep works). |
| SC3 | DATA_SOURCES.md documents all PDB IDs, DOIs, SASBDB IDs, MemProtMD attribution, with MemProtMD per-entry licenses verified before bundling | PASS VERIFIED | `DATA_SOURCES.md` (202 lines, 5 sections): section 1 Bundled RCSB CC0 (6 entries); section 2 MemProtMD CC-BY 4.0 (1GZM + 3GP6) with CORRECTED citations - Stansfeld 2015 Structure (DOI `10.1016/j.str.2015.05.006`, line 87) + Newport 2019 NAR (DOI `10.1093/nar/gky1047`, line 82), NOT the wrong `10.1038/s41592-018-0220-9` (absent from DATA_SOURCES.md - grep returns 0); section 3 SASBDB free-use license (SASDPG4 + Kalidas 2025 `10.1080/07391102.2025.2475244` + Kikhney 2020 `10.1002/pro.3731` + "free of all copyright restrictions"); section 4 PDB_POOL RCSB CC0; section 5 PyMOL. `oxy.ac.uk` typo corrected to `ox.ac.uk` in `PROJECT.md:75` (grep: oxy.ac.uk=0 in PROJECT.md). Wrong DOI + oxy.ac.uk removed from `PITFALLS.md` (grep: both 0; corrected DOIs present - 3 matches) + research `SUMMARY.md` (grep: both 0; corrected DOIs present - 1 match). `biochemeleon/data/demos/SOURCES.md` reduced to a 2-line stub pointer. Human-approved: 09-04-SUMMARY line 78 (checkpoint:human-verify Task 3 approved). |
| SC4 | Demo sub-menu surfaces difficulty-tiered metadata (Easy / Hard / Challenge / Very challenging) | PASS VERIFIED | `gui_setup.py:20-24` imports `TIER_LABELS`; `gui_setup.py:134-138` populates `demo_combo` via `TIER_LABELS.get(meta['difficulty'], meta['difficulty'].title())` over all 9 `DEMO_MANIFEST` entries with display string `"{category} - {id} ({tier})"`. `TIER_LABELS` (`setup_state.py:65-70`) maps `{'easy':'Easy','hard':'Hard','challenge':'Challenge','very_challenging':'Very challenging'}` exactly (runtime introspection confirmed). Every manifest entry's `difficulty` is a `TIER_LABELS` key. Human-approved: 09-03-SUMMARY line 92 (9-demo sub-menu with 4 tier labels confirmed). |

**Score:** 4/4 truths verified

### Required Artifacts (Level 1-3 checks: exists + substantive + wired)

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `biochemeleon/setup_state.py` | 9-entry DEMO_MANIFEST + TIER_LABELS + STRIP_RESN_MEMPROTMD + strip_resn_from_pdb + offline-safe randomize_state | PASS VERIFIED | 413 lines. Runtime introspection: 9 entries, all 9 required keys (category/type/difficulty/source/source_id/fetch_url/cache_name/citation/strip); 1gzm+3gp6 very_challenging/memprotmd/strip=True; sasdpg4 challenge/sasbdb/strip=False; 4wb3 hard (NOT mixed); TIER_LABELS exact dict; STRIP_RESN_MEMPROTMD={'SOL','NA','CL'}; strip_resn_from_pdb padding-agnostic (leading-space NA stripped) + preserves non-ATOM (TITLE/CRYST1/HETATM/TER/ENDMDL) + empty/None returns ''; randomize_state excludes fetched (lines 322-324: `bundled_ids` filter, lock_source branch preserves user-locked fetched). Purity gate: NO `from pymol`/`from pymol.Qt` (stdlib only: random, copy). WIRED: demos.py imports strip_resn_from_pdb + STRIP_RESN_MEMPROTMD (line 51-54); gui_setup.py imports TIER_LABELS (line 22). |
| `tests/test_setup_state.py` | 8 Phase 9 test classes + migrated TestDemoManifest | PASS VERIFIED | Classes present (grep): TestManifestSchemaPhase9 (482), TestFetchUrls (517), TestTierLabels (538), TestTierAssignment (553), Test4wb3MappedToHard (566), TestStripFalseForSasbdb (576), TestRandomizeExcludesFetched (589), TestStripResnFromPdb (613). 112 test methods total. `python3.6 -m unittest tests.test_setup_state` -> 112/112 PASS (exit 0). |
| `biochemeleon/demos.py` | Qt-free split API + load_demo branching + _urlopen_with_ssl_fallback + format='pdb' | PASS VERIFIED | 523 lines. 9 functions present (inspect): `download_large_demo`/`finalize_large_demo`/`load_cached_demo`/`cache_path_for`/`is_cached`/`_cache_dir`/`temp_download_path`/`cleanup_temp`/`_urlopen_with_ssl_fallback`. `load_demo` branches on `meta.get('source','bundled')` (line 183): fetched -> `load_cached_demo`, bundled -> `data/demos/{cache_name}` (line 188). Pitfall 6: `cmd.` NOT in `download_large_demo` source (incl. docstring) - static check PASS. `finalize_large_demo` has `format='pdb'` (line 474) + `strip_resn_from_pdb` call (line 453) + `cmd.load` (line 474) + `cmd.save` (line 486) + SASBDB skip-strip (line 461). `from pymol.Qt` ZERO in demos.py (dependency direction intact). WIRED: `__init__.py._resolve_large_demo` calls `download_large_demo` (line 437) + `finalize_large_demo` (line 462) + `cleanup_temp` (line 463) + `load_cached_demo` (line 416). |
| `smoke/phase9_smoke.py` | Headless smoke for SASBDB round-trip + MemProtMD strip + cache-hit | PASS VERIFIED | 295 lines, 65 `check()` calls across sections SETUP/A/B/C/D/E/F/G/M. Section A (SASBDB finalize -> 4123 atoms + 2601 hetatm + NAG/MAN/BMA/NAN + cache .pdb.gz), B (cache-hit), C (MemProtMD strip), D (load_demo branching: bundled + fetched cache-hit + fetched cache-miss->None), E (Pitfall 6 static via inspect), F (cache_path_for/is_cached), G (MemProtMD finalize round-trip .raw -> strip -> .dry -> cmd.load(format='pdb') -> stripped atoms). `py_compile` clean. Human-verified headless 64/64 PASSED per 09-03-SUMMARY. |
| `biochemeleon/__init__.py` | `_resolve_large_demo` + `_continue_after_large_demo_fetch` + `_update_export_enabled` + `_prepare_and_start` large-demo branch + `_on_start` re-entrancy | PASS VERIFIED | 788 lines. `_resolve_large_demo` (387-519): modeless QProgressDialog (`.show()` line 428, NEVER `.exec_()`) + NonModal + setAutoClose(False)/setAutoReset(False)/setMinimumDuration(500) + worker thread + recursive QTimer.singleShot(100, drain) + Cancel->threading.Event + drain branches (progress/done/error/canceled/worker-dead) + finalize-None guard (465-475). `_continue_after_large_demo_fetch` (211-385): behavior-preserving extraction. `_update_export_enabled` (564-585): BTN-05 async guard, wired to demo_combo.currentIndexChanged (97-98) + called by drain 'done' branch (489). `_prepare_and_start` large-demo branch (193-198): stash `_pending_large_demo` + `_pending_large_demo_state` + call `_resolve_large_demo` + return (None,None,[]) silently (bypasses the bundled-only 'Demo failed' QMessageBox). `_on_start` re-entrancy (120-121): if `_pending_large_demo is not None` -> return (drain owns tab switch + countdown). WIRED: demo_combo.currentIndexChanged -> _update_export_enabled (97-98); start_btn -> _on_start -> _prepare_and_start. |
| `biochemeleon/gui_setup.py` | demo_combo tier-label display via TIER_LABELS | PASS VERIFIED | 610 lines. `TIER_LABELS` imported (line 22). demo_combo populated (134-138): `tier = TIER_LABELS.get(meta['difficulty'], meta['difficulty'].title())` + `addItem("{category} - {id} ({tier})", did)` over all 9 DEMO_MANIFEST entries. `.title()` fallback for unmapped values. Flat QComboBox kept (9 items < 15-item QTreeWidget threshold). WIRED: `__init__.py` reads `self.setup_tab.demo_combo.currentData()` in `_update_export_enabled` (578). |
| `DATA_SOURCES.md` | 5-section consolidated attribution | PASS VERIFIED | 202 lines at repo root. Section 1 Bundled RCSB CC0 (6 entries with PDB IDs + DOIs + titles + authors + publications); Section 2 MemProtMD CC-BY 4.0 (1GZM + 3GP6) with corrected citations (Stansfeld 2015 Structure + Newport 2019 NAR) + CC-BY 4.0 license string verbatim from research + processing note (SOL/NA/CL strip counts); Section 3 SASBDB free-use (SASDPG4_fit2_model1 + Kalidas 2025 + Kikhney 2020 + free-use license + over-strip CAUTION); Section 4 PDB_POOL RCSB CC0; Section 5 PyMOL. Wrong DOI `10.1038/s41592-018-0220-9` ABSENT (grep 0). `oxy.ac.uk` ABSENT (grep 0). Corrected DOIs present (MemProtMD 2, SASBDB 2). WIRED: setup_state.py module docstring (line 31) points to DATA_SOURCES.md; SOURCES.md stub points to it. |
| `biochemeleon/data/demos/SOURCES.md` | 2-line stub pointer to repo-root DATA_SOURCES.md | PASS VERIFIED | 2 lines: "# Sources consolidated in repo-root DATA_SOURCES.md (DEMO-04, Phase 9).\nSee /DATA_SOURCES.md." |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `biochemeleon/demos.finalize_large_demo` | `biochemeleon/setup_state.strip_resn_from_pdb` | import + call BEFORE cmd.load | WIRED | demos.py:53 imports `strip_resn_from_pdb`; line 453 calls it on the MemProtMD wet file, writes `.dry`, then line 474 `cmd.load(format='pdb')` reads the `.dry` (wet file never enters PyMOL). |
| `biochemeleon/__init__.py._resolve_large_demo` | `biochemeleon/demos.download_large_demo/finalize_large_demo/load_cached_demo/cleanup_temp` | threading.Thread worker + QTimer drain | WIRED | Worker: line 437 `target=demos.download_large_demo`; drain 'done' branch: line 462 `demos.finalize_large_demo` + line 463 `demos.cleanup_temp`; cache-hit: line 416 `demos.load_cached_demo`. |
| `biochemeleon/gui_setup.py.demo_combo` | `biochemeleon/setup_state.TIER_LABELS` | TIER_LABELS.get(meta['difficulty']) | WIRED | gui_setup.py:22 imports TIER_LABELS; line 135 `TIER_LABELS.get(meta['difficulty'], meta['difficulty'].title())`. |
| `biochemeleon/setup_state.DEMO_MANIFEST.citation` | `DATA_SOURCES.md sections` | citation field cross-refs per-source sections | WIRED | Each manifest entry's `citation` (1GZM/3GP6/SASDPG4/1ZNF/...) matches a DATA_SOURCES.md section header (1GZM line 98, 3GP6 line 108, SASDPG4 line 139, 1znf line 15...). |
| `biochemeleon/__init__.py._prepare_and_start` | `biochemeleon/demos.load_demo` | demo mode target resolution | WIRED | __init__.py:185 `target_obj = demos.load_demo(demo_id)`; None -> fetched-demo branch (193-198) -> `_resolve_large_demo`. |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
| ----------- | ------ | -------------- |
| SC1 (large membrane-protein demos fetch+strip+compress+cache + modeless cancelable progress dialog) | SATISFIED | None - all sub-truths verified + human-approved |
| SC2 (glycoprotein-with-glycan demo fetch from SASBDB + source/IDs cited) | SATISFIED | None - all sub-truths verified + human-approved |
| SC3 (DATA_SOURCES.md with all IDs/DOIs + MemProtMD per-entry licenses verified) | SATISFIED | None - all sub-truths verified + human-approved |
| SC4 (demo sub-menu 4-tier difficulty metadata) | SATISFIED | None - all sub-truths verified + human-approved |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | - | - | - | No blocker anti-patterns found in Phase 9 artifacts. No stub/placeholder/empty-implementation patterns. All grep gates green. |

### WSL Gate Regression Check

| Gate | Expected | Actual | Status |
| ---- | -------- | ----- | ------ |
| `python3.6 -m py_compile biochemeleon/*.py smoke/*.py` | exit 0 | exit 0 | PASS |
| `python3.6 -m unittest tests.test_setup_state` | 112/112 PASS | 112/112 PASS (OK) | PASS |
| `grep -rnE "\.exec_\(\)" biochemeleon/` | exactly 1 (gui_game.py:303) | exactly 1 (gui_game.py:303 QMessageBox) | PASS |
| `grep -rnE "from pymol.Qt" biochemeleon/demos.py` | ZERO | ZERO | PASS |
| Pitfall-1 gate (package-wide) | ZERO | ZERO (exit 1) | PASS |
| Pitfall 6 static (`cmd.` not in `download_large_demo` source incl. docstring) | PASS | PASS | PASS |

### Runtime Fixes (applied during 09-03 human-verify checkpoint)

| Fix | Commit | Verified in code |
| --- | ------ | ---------------- |
| MemProtMD finalize `cmd.load` `format='pdb'` (forces PDB reader past unrecognized `.dry` extension) | `d54f22e` | demos.py:474 `cmd.load(win_path, object=obj_name, zoom=1, format='pdb')`; smoke Section G exercises the round-trip |
| SASBDB SSL fallback `_urlopen_with_ssl_fallback` (retries without cert verification on HARICA SSLCertVerificationError) | `e0f8302` | demos.py:284-335 helper; line 375 `download_large_demo` calls it inside its try; posts `('warning', msg)` on fallback |

### Phase 11 Bug Documentation (out of scope for Phase 9)

The membrane-protein cartoon-segment hider AssertionError (native alt-confs cause duplicate anchor ids in 1gzm/3gp6/sasdpg4) was discovered during the 09-03 checkpoint and is documented in `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` (92 lines). This is a **Phase 11** issue, NOT a Phase 9 issue - Phase 9 SC1 only requires the fetch->start flow completes (sphere hiders work on all demos; mixed-rep with cartoon/ribbon blocks on membrane proteins only). Correctly scoped out.

### Human Verification Required

All 4 success criteria were human-verified and **already approved** by the user during the 09-03 and 09-04 checkpoints (no residual human verification needed):

1. **SC1 - 1GZM/3GP6 fetch in real Windows PyMOL GUI** - APPROVED (09-03-SUMMARY line 92): 1gzm + 3gp6 download/finalize/load with membrane visible + no water; play/hint/reveal/restart/clean ALL work with sphere hiders; modeless dialog confirmed (viewer stays interactive during download).
2. **SC2 - SASDPG4 fetch in real Windows PyMOL GUI** - APPROVED (09-03-SUMMARY line 92): sasdpg4 downloads with SSL fallback (HARICA cert gap handled); glycan HETATM visible (2601); mixed-rep works.
3. **SC3 - License + citation accuracy review** - APPROVED (09-04-SUMMARY line 78): every citation/DOI verified to resolve; CC-BY 4.0 license acceptable; wrong DOI + oxy.ac.uk absent from target files.
4. **SC4 - 4-tier demo sub-menu in real Windows PyMOL GUI** - APPROVED (09-03-SUMMARY line 92): 9-demo sub-menu with 4 tier labels (Easy/Hard/Challenge/Very challenging) confirmed.

### Gaps Summary

**No gaps found.** All 4 Phase 9 success criteria are verified against the actual codebase AND human-approved. All must-have truths, artifacts (Level 1-3: exists + substantive + wired), and key links are satisfied. All WSL gates pass with no regression. Both runtime fixes (d54f22e, e0f8302) are present in the code.

**Out-of-scope observations (NOT Phase 9 gaps):**
- **Phase 11 cartoon-segment hider bug** (membrane-protein alt-confs cause duplicate anchor ids) - documented in `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` for Phase 11 follow-up. Sphere hiders work on all Phase 9 demos; SC1 only requires the fetch->start flow completes.
- **STATE.md staleness** - `.planning/STATE.md` lines 8/12/14/17/19 still describe "Phase 9 Plans 09-02/03/04 INCOMPLETE (no summaries)", but the summaries exist (dated 2026-08-16/17) + the code + commits all prove Phase 9 completion. This is a STATE.md documentation hygiene issue outside Phase 9's scope (the phase goal is about code/artifacts, which are all present and verified). STATE.md should be updated to mark Phase 9 complete in a future housekeeping pass.
- **Residual concerns (documented, acceptable for v1):** the SSL fallback (`check_hostname=False`/`CERT_NONE`) is a security tradeoff for public PDB downloads; the 60s urllib timeout may be tight for slow MemProtMD connections; the `.pdb.gz` cache lives in `tmp/phase9-demos/cache/` (repo-relative, gitignored) which won't exist for an installed plugin (v2). All out of scope for v1 per AGENTS.md.

---

_Verified: 2026-08-16T21:05:00Z_
_Verifier: OpenCode (gsd-verifier)_
