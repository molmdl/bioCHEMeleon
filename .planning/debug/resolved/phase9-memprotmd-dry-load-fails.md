---
status: resolved
trigger: "MemProtMD demos (1gzm, 3gp6) download to 100% successfully, but then FAIL TO LOAD — the progress dialog reaches 'Loading…' but the object never appears in PyMOL. SASBDB demo (sasdpg4) downloads AND loads correctly with glycan visible. SC4 passes."
created: 2026-08-16T00:00:00Z
updated: 2026-08-16T00:02:00Z
---

## Current Focus

hypothesis: CONFIRMED — `.dry` extension unrecognized by cmd.load dispatch.
test: Apply fix (format='pdb' kwarg on the shared cmd.load in finalize_large_demo), then headless smoke.
expecting: finalize_large_demo returns non-None for MemProtMD; object loads with stripped atoms.
next_action: Apply the format='pdb' fix to demos.py, extend smoke, run headless.

## Symptoms

expected: MemProtMD demos (1gzm, 3gp6) download AND load — the stripped (lipid/protein-only) object appears in PyMOL after the progress dialog reaches "Loading…".
actual: Download reaches 100%, progress dialog reaches "Loading…", but the object never appears in PyMOL. finalize_large_demo returns None (caught by try/except), the drain's Rule-2 guard shows a "Fetch failed" QMessageBox.
errors: User sees a "Fetch failed" QMessageBox (the drain's Rule-2 guard for the None return). No traceback in the GUI.
reproduction: In the Windows GUI, run a MemProtMD demo (1gzm or 3gp6). Download succeeds, load fails.
started: Phase 9 (09-03). SASBDB (sasdpg4, strip=False) works; only MemProtMD (strip=True) fails.

## Eliminated

<!-- APPEND only -->

## Evidence

- timestamp: 2026-08-16T00:00:30Z
  checked: demos.py finalize_large_demo (lines 374-408)
  found: MemProtMD branch writes `dry_path = downloaded_path + '.dry'` (line 379), then `cmd.load(win_path, ...)` at line 389. The `try/except Exception: return None` (lines 388-391) swallows any load failure. cleanup_temp(load_path) at line 407 is AFTER the load — unreachable when load fails.
  implication: If cmd.load fails on the .dry file, finalize returns None and the .dry file is orphaned on disk.

- timestamp: 2026-08-16T00:00:40Z
  checked: PyMOL source importing.py filename_to_format (lines 41-101)
  found: For a `.dry` file, ext='dry' matches NONE of the elif branches (lines 56-97), falls to `else: format = ext` (line 98-99) → format='dry'. The loadfunctions dict (lines 1611-1635) has 'pdb' (line 1628) but NOT 'dry'. So cmd.load with no format kwarg: ftype=-1 → format=format_guessed='dry' → ftype=getattr(_loadable,'dry',-1)=-1 → line 756 ftype<0 and 'dry' not in loadfunctions → _cmd.find_molfile_plugin('dry') → no plugin → raise CmdException('unsupported file type: dry') (line 760).
  implication: cmd.load on a .dry file ALWAYS raises CmdException, caught by try/except → return None. ROOT CAUSE CONFIRMED.

- timestamp: 2026-08-16T00:00:50Z
  checked: PyMOL source importing.py load() signature (line 635) + format= kwarg dispatch
  found: `def load(filename, object='', state=0, format='', ...)` — format IS a kwarg. Notes (line 673-674): "The file extension is used to determine the format unless the format is provided explicitly." With format='pdb': ftype=getattr(_loadable,'pdb',-1)=0 (constants.py:10 `pdb=0`), so ftype!=-1, skips extension dispatch (line 734), skips plugin lookup (line 756 ftype<0 is False), func=loadfunctions['pdb']=read_pdbstr (line 775). Forces PDB reader regardless of extension.
  implication: format='pdb' kwarg is the canonical fix — forces read_pdbstr for .dry AND .raw files.

- timestamp: 2026-08-16T00:00:55Z
  checked: temp_download_path (demos.py:251-265) + Qt orchestration (__init__.py:435-462)
  found: temp_download_path returns `demo_id + '.raw'` for ALL fetched demos (both SASBDB and MemProtMD). The Qt drain passes tmp_path (the .raw path) to both the worker and finalize_large_demo. So the REAL GUI flow loads a `.raw` file for SASBDB (strip=False) and a `.dry` file for MemProtMD (strip=True). BOTH .raw and .dry are unrecognized extensions.
  implication: SASBDB first-fetch would ALSO fail (latent bug). SASBDB "works" in the GUI only because the 09-02 smoke pre-populated the .pdb.gz cache → GUI test was a cache hit (load_cached_demo reads .pdb.gz, a recognized extension).

- timestamp: 2026-08-16T00:01:00Z
  checked: Orphaned .dry files on disk (tmp/bioCHEMeleon/tmp/phase9-demos/)
  found: 1gzm.raw.dry (2,078,112 bytes) and 3gp6.raw.dry (1,537,847 bytes) exist — REAL stripped MemProtMD files from the failed GUI runs. They persist because cleanup_temp (line 407) is unreachable after cmd.load fails (line 389-391 returns None). Cache dir has SASDPG4_fit2_model1.pdb.gz (85KB) — confirms SASBDB was a cache hit.
  implication: Direct physical evidence: the strip ran (files exist), the load failed (files orphaned, object never appeared). Root cause 100% confirmed.

## Resolution

root_cause: finalize_large_demo writes the stripped MemProtMD file with a `.dry` extension (demos.py:379) and calls cmd.load without a format kwarg (demos.py:389). PyMOL's cmd.load dispatches by file extension via filename_to_format (importing.py:41-101); `.dry` is not a registered format (not in loadfunctions, no molfile plugin), so cmd.load raises CmdException('unsupported file type: dry') (importing.py:760). The try/except at demos.py:388-391 swallows this and returns None. The drain's Rule-2 guard shows "Fetch failed". The .dry files are orphaned because cleanup_temp (line 407) is after the failed load. SASBDB "works" only via a pre-existing .pdb.gz cache hit (the 09-02 smoke populated it); its first-fetch .raw path has the SAME latent extension bug.
fix: Add `format='pdb'` to the shared cmd.load call in finalize_large_demo (demos.py:411). This forces the PDB reader (read_pdbstr) regardless of the .dry/.raw extension — the canonical PyMOL way (importing.py:660-674: "format is provided explicitly" overrides extension dispatch). Fixes both MemProtMD .dry (reported) and SASBDB .raw (latent first-fetch). Minimal one-kwarg change; no branch logic touched.
verification: Headless smoke (smoke/phase9_smoke.py Section G) — 64/64 PASSED, 0 FAIL. Key G checks: finalize_large_demo('3gp6') returns '3gp6' (was None before fix); object loaded; SOL/NA/CL stripped (0 atoms); MET/DPP preserved; 2 states (multi-model); cache .pdb.gz written; .dry cleaned up (was orphaned before fix). Bonus: real orphaned 3gp6.raw.dry (1.5MB, from the failed GUI run) loads with format='pdb'. WSL gates: py_compile OK; 112 unit tests OK; exec_=1 (gui_game.py:303); Pitfall-1=0; demos.py Qt=0; download_large_demo cmd-free (Pitfall 6). GUI re-verify needed: the real 95k-atom MemProtMD network fetch + modeless dialog interaction can only be confirmed in the Windows GUI (headless smoke confirms the extension fix but not the full network+GUI flow).
files_changed: [biochemeleon/demos.py, smoke/phase9_smoke.py]
