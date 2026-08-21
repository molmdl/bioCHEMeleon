# phase9_smoke.py -- Phase 9 headless smoke. Run: pymol -cq smoke/phase9_smoke.py
# Verifies the Phase 9 fetched-demo split API (download_large_demo /
# finalize_large_demo / load_cached_demo / cache helpers) + load_demo source
# branching headlessly (pure pymol.cmd.* only, NO Qt -- AGENTS.md: the headless
# path cannot run Qt). GUI paths (the QProgressDialog + QTimer drain + real
# network fetch with progress) are deferred to the 09-03 human-verify checkpoint.
#
# Uses the STAGED SASBDB sample (cache/SASDPG4_fit2_model1.pdb) to
# simulate the worker-download output; no real network. The real fetch + progress
# dialog is verified at the 09-03 human-verify checkpoint (needs the GUI + real
# network timing).
#
# Sections (~45 checks):
#   SETUP: manifest 9 entries; 1gzm/3gp6/sasdpg4 present; TIER_LABELS 4 tiers;
#      strip helper filters synthetic SOL/NA/CL (keeps DPP/MET + non-ATOM).
#   A. SASBDB fetch round-trip: finalize_large_demo('sasdpg4', staged) -> 4123
#      atoms, 2601 hetatm glycan, NAG/MAN/BMA/NAN present, cache .pdb.gz written.
#   B. Cache-hit: delete sasdpg4 -> load_cached_demo -> 4123 atoms, 2601 hetatm.
#   C. MemProtMD strip helper: synthetic wet SOL/NA/CL removed, DPP/MET + all
#      non-ATOM records preserved (real 3gp6 wet fetch is 7.5MB -- too heavy for
#      a smoke; the pure helper test covers the strip logic).
#   D. load_demo branching: 1znf bundled -> '1znf'; sasdpg4 fetched cache-hit ->
#      'sasdpg4'; 1gzm fetched cache-miss -> None.
#   E. download_large_demo is cmd-free (Pitfall 6 static check via inspect).
#   F. cache_path_for / is_cached: 1znf None (bundled); sasdpg4 ends .pdb.gz;
#      is_cached sasdpg4 True; is_cached 1gzm False.
#   G. MemProtMD finalize round-trip (09-03 bug fix): synthetic .raw -> strip ->
#      .dry -> cmd.load(format='pdb') -> object loads with stripped atoms.
#      Verifies the .dry extension fix (format='pdb' forces the PDB reader;
#      without it cmd.load raised CmdException 'unsupported file type: dry').
#      Bonus: loads the real orphaned 3gp6.raw.dry (from the failed GUI run)
#      directly with format='pdb' to confirm the fix on real data.
#   M. SUMMARY: print pass/fail counts, sys.exit(1) on any fail.
import sys
import os
import inspect

from pymol import cmd
from biochemeleon import demos, setup_state

RESULTS = []


def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)


# --- SETUP: manifest + tier labels + strip helper ---
check("SETUP: DEMO_MANIFEST has 9 entries",
      len(setup_state.DEMO_MANIFEST) == 9)
for _did in ('1gzm', '3gp6', 'sasdpg4'):
    check("SETUP: %s in manifest" % _did, _did in setup_state.DEMO_MANIFEST)
check("SETUP: TIER_LABELS maps 4 tiers",
      len(setup_state.TIER_LABELS) == 4 and
      all(k in setup_state.TIER_LABELS
          for k in ('easy', 'hard', 'challenge', 'very_challenging')))

# Strip helper on a synthetic wet PDB (SOL/NA/CL/DPP/MET + non-ATOM records).
# PDB columns 18-20 (0-indexed 17:20) hold the residue name.
_synthetic_wet = (
    'TITLE     synthetic wet\n'
    'CRYST1   100.0  100.0  100.0  90.00  90.00  90.00 P 1\n'
    'MODEL        1\n'
    'ATOM      1  N   MET A   1      10.000  10.000  10.000  1.00 20.00           N\n'
    'ATOM      2  OW  SOL A   2      20.000  20.000  20.000  1.00 20.00           O\n'
    'ATOM      3  NA  NA  A   3      30.000  30.000  30.000  1.00 20.00          NA\n'
    'ATOM      4  CL  CL  A   4      40.000  40.000  40.000  1.00 20.00          CL\n'
    'ATOM      5  N   DPP A   5      50.000  50.000  50.000  1.00 20.00           N\n'
    'TER\n'
    'ENDMDL\n'
)
_dry_setup = setup_state.strip_resn_from_pdb(
    _synthetic_wet, setup_state.STRIP_RESN_MEMPROTMD)
_dry_setup_resn = [l[17:20].strip() for l in _dry_setup.splitlines()
                   if l.startswith('ATOM')]
check("SETUP: strip removes SOL", 'SOL' not in _dry_setup_resn)
check("SETUP: strip removes NA", 'NA' not in _dry_setup_resn)
check("SETUP: strip removes CL", 'CL' not in _dry_setup_resn)
check("SETUP: strip keeps MET (protein)", 'MET' in _dry_setup_resn)
check("SETUP: strip keeps DPP (membrane lipid)", 'DPP' in _dry_setup_resn)
check("SETUP: strip preserves TITLE", 'TITLE' in _dry_setup)
check("SETUP: strip preserves CRYST1", 'CRYST1' in _dry_setup)
check("SETUP: strip preserves MODEL", 'MODEL' in _dry_setup)
check("SETUP: strip preserves TER", 'TER' in _dry_setup)
check("SETUP: strip preserves ENDMDL", 'ENDMDL' in _dry_setup)

# Clean any stale cache+temp artifacts from prior runs so the smoke is
# deterministic. Wipe ONLY .pdb.gz (cache), .raw and .dry (temp) -- the
# flat <cwd>/cache/ layout co-locates the staged SASBDB .pdb sample in
# this same dir (smoke line 103), and it must survive the wipe so
# section A can read it. (Under quick-003's nested layout the sample
# lived in the parent dir outside the cache subdir; the flat layout
# removes that incidental separation, so the wipe must be
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

# --- A. SASBDB fetch round-trip (the small+fast demo; no strip, glycan-preserving) ---
# Stage the already-downloaded SASBDB sample as the "downloaded_path" (simulating
# the worker download -- no real network in the smoke; the staged file IS the
# real fetched content per 09-RESEARCH-sasbdb.md:382).
_staged_sasbdb = os.path.abspath(os.path.join(
    os.getcwd(), 'cache', 'SASDPG4_fit2_model1.pdb'))
check("A: staged SASBDB sample exists", os.path.exists(_staged_sasbdb))
_obj_a = demos.finalize_large_demo('sasdpg4', _staged_sasbdb)
check("A: finalize_large_demo returns 'sasdpg4'", _obj_a == 'sasdpg4')
check("A: sasdpg4 in loaded objects", 'sasdpg4' in cmd.get_names('objects'))
check("A: count_atoms == 4123 (1522 protein + 2601 glycan)",
      cmd.count_atoms('sasdpg4') == 4123)
check("A: hetatm count == 2601 (glycan HETATM -- DEMO-03)",
      cmd.count_atoms('sasdpg4 and hetatm') == 2601)
check("A: NAG/MAN/BMA/NAN present (standard wwPDB glycan codes)",
      cmd.count_atoms('sasdpg4 and resn NAG,MAN,BMA,NAN') > 0)
_cache_a = demos.cache_path_for('sasdpg4')
check("A: cache .pdb.gz file exists",
      _cache_a is not None and os.path.exists(_cache_a))
check("A: is_cached('sasdpg4') == True", demos.is_cached('sasdpg4') is True)

# --- B. cache-hit path (load_cached_demo) ---
cmd.delete('sasdpg4')
check("B: sasdpg4 deleted", 'sasdpg4' not in cmd.get_names('objects'))
_obj_b = demos.load_cached_demo('sasdpg4')
check("B: load_cached_demo returns 'sasdpg4'", _obj_b == 'sasdpg4')
check("B: count_atoms == 4123 (cache round-trips; .pdb.gz read natively)",
      cmd.count_atoms('sasdpg4') == 4123)
check("B: hetatm == 2601 (glycan preserved through cache)",
      cmd.count_atoms('sasdpg4 and hetatm') == 2601)

# --- C. MemProtMD strip helper (pure, no network) ---
# Real 3gp6 wet fetch is 7.5MB -- too slow/heavy for a smoke; the pure helper
# test covers the strip logic. The 09-03 human-verify covers the real fetch.
_dry_c = setup_state.strip_resn_from_pdb(
    _synthetic_wet, setup_state.STRIP_RESN_MEMPROTMD)
_c_resn = [l[17:20].strip() for l in _dry_c.splitlines()
           if l.startswith('ATOM')]
check("C: SOL removed (water)", 'SOL' not in _c_resn)
check("C: NA removed (sodium ion)", 'NA' not in _c_resn)
check("C: CL removed (chloride ion)", 'CL' not in _c_resn)
check("C: DPP preserved (DPPC membrane lipid)", 'DPP' in _c_resn)
check("C: MET preserved (protein residue)", 'MET' in _c_resn)
check("C: TITLE preserved (non-ATOM record)", 'TITLE' in _dry_c)
check("C: CRYST1 preserved (non-ATOM record)", 'CRYST1' in _dry_c)
check("C: MODEL preserved (non-ATOM record)", 'MODEL' in _dry_c)
check("C: TER preserved (non-ATOM record)", 'TER' in _dry_c)
check("C: ENDMDL preserved (non-ATOM record)", 'ENDMDL' in _dry_c)

# --- D. load_demo branching ---
# D.1: bundled path unchanged (cache_name field works after 09-01 rename)
if '1znf' in cmd.get_names('objects'):
    cmd.delete('1znf')
_d1 = demos.load_demo('1znf')
check("D: load_demo('1znf') bundled -> '1znf'", _d1 == '1znf')
check("D: 1znf loaded (count > 0)", cmd.count_atoms('1znf') > 0)
# D.2: fetched path -> load_cached_demo -> cache hit (from Section A)
cmd.delete('sasdpg4')
_d2 = demos.load_demo('sasdpg4')
check("D: load_demo('sasdpg4') fetched cache-hit -> 'sasdpg4'", _d2 == 'sasdpg4')
check("D: sasdpg4 count == 4123 via load_demo",
      cmd.count_atoms('sasdpg4') == 4123)
# D.3: fetched cache-miss -> None (signals caller to fetch)
if '1gzm' in cmd.get_names('objects'):
    cmd.delete('1gzm')
# Ensure 1gzm is a genuine cache miss (no stale cache from a prior run).
_1gzm_cache = demos.cache_path_for('1gzm')
if _1gzm_cache and os.path.exists(_1gzm_cache):
    try:
        os.unlink(_1gzm_cache)
    except OSError:
        pass
_d3 = demos.load_demo('1gzm')
check("D: load_demo('1gzm') fetched cache-miss -> None", _d3 is None)

# --- E. download_large_demo is cmd-free (Pitfall 6 static check) ---
_dl_src = inspect.getsource(demos.download_large_demo)
check("E: no 'cmd.' in download_large_demo source (Pitfall 6)", 'cmd.' not in _dl_src)
check("E: no 'from pymol' in download_large_demo source",
      'from pymol' not in _dl_src)
check("E: urllib present in download_large_demo source", 'urllib' in _dl_src)

# --- F. cache_path_for / is_cached ---
check("F: cache_path_for('1znf') is None (bundled)",
      demos.cache_path_for('1znf') is None)
_f_sas = demos.cache_path_for('sasdpg4')
check("F: cache_path_for('sasdpg4') endswith SASDPG4_fit2_model1.pdb.gz",
      _f_sas is not None and _f_sas.endswith('SASDPG4_fit2_model1.pdb.gz'))
check("F: is_cached('sasdpg4') == True", demos.is_cached('sasdpg4') is True)
check("F: is_cached('1gzm') == False (not fetched)", demos.is_cached('1gzm') is False)

# --- G. MemProtMD finalize round-trip (.raw -> strip -> .dry -> cmd.load) ---
# 09-03 bug fix: the MemProtMD strip writes a .dry intermediate whose extension
# is NOT a registered PyMOL file type (importing.py filename_to_format: .dry is
# not in loadfunctions, no molfile plugin). Without format='pdb', cmd.load
# raises CmdException('unsupported file type: dry') and finalize returns None.
# The fix adds format='pdb' to force the PDB reader regardless of extension.
# This section exercises the FULL MemProtMD path: synthetic .raw -> strip ->
# .dry -> cmd.load(format='pdb') -> object appears with stripped atoms.
# Also covers the latent .raw extension bug (SASBDB first-fetch would hit the
# same dispatch failure; format='pdb' on the shared cmd.load fixes both paths).

# Clean any stale 3gp6 object + cache so the test is deterministic.
if '3gp6' in cmd.get_names('objects'):
    cmd.delete('3gp6')
_3gp6_cache = demos.cache_path_for('3gp6')
if _3gp6_cache and os.path.exists(_3gp6_cache):
    try:
        os.unlink(_3gp6_cache)
    except OSError:
        pass

# Synthetic wet MemProtMD PDB: 2 MODELs, each with MET (protein), SOL (water),
# NA (sodium), CL (chloride), DPP (DPPC lipid). After strip, SOL/NA/CL gone,
# MET+DPP remain in each MODEL. PDB columns 18-20 (0-indexed 17:20) = resn.
# Two models also verify multi-MODEL (MD trajectory) handling survives strip.
_synthetic_memprotmd = (
    'TITLE     synthetic MemProtMD wet\n'
    'CRYST1   100.0  100.0  100.0  90.00  90.00  90.00 P 1\n'
    'MODEL        1\n'
    'ATOM      1  N   MET A   1      10.000  10.000  10.000  1.00 20.00           N\n'
    'ATOM      2  OW  SOL A   2      20.000  20.000  20.000  1.00 20.00           O\n'
    'ATOM      3  NA  NA  A   3      30.000  30.000  30.000  1.00 20.00          NA\n'
    'ATOM      4  CL  CL  A   4      40.000  40.000  40.000  1.00 20.00          CL\n'
    'ATOM      5  N   DPP A   5      50.000  50.000  50.000  1.00 20.00           N\n'
    'TER\n'
    'ENDMDL\n'
    'MODEL        2\n'
    'ATOM      6  N   MET A   1      11.000  11.000  11.000  1.00 20.00           N\n'
    'ATOM      7  OW  SOL A   2      21.000  21.000  21.000  1.00 20.00           O\n'
    'ATOM      8  NA  NA  A   3      31.000  31.000  31.000  1.00 20.00          NA\n'
    'ATOM      9  CL  CL  A   4      41.000  41.000  41.000  1.00 20.00          CL\n'
    'ATOM     10  N   DPP A   5      51.000  51.000  51.000  1.00 20.00           N\n'
    'TER\n'
    'ENDMDL\n'
    'END\n'
)

# Stage the synthetic .raw file (simulating the worker download output).
_memprotmd_dir = os.path.abspath(os.path.join(os.getcwd(), 'cache'))
try:
    os.makedirs(_memprotmd_dir, exist_ok=True)
except OSError:
    pass
_synthetic_raw = os.path.join(_memprotmd_dir, '3gp6_synthetic.raw')
with open(_synthetic_raw, 'w') as _f:
    _f.write(_synthetic_memprotmd)
check("G: staged synthetic MemProtMD .raw file", os.path.exists(_synthetic_raw))

# THE BUG: before the fix, finalize returned None (cmd.load failed on .dry).
_obj_g = demos.finalize_large_demo('3gp6', _synthetic_raw)
check("G: finalize_large_demo('3gp6') returns '3gp6' (not None)", _obj_g == '3gp6')
check("G: 3gp6 in loaded objects", '3gp6' in cmd.get_names('objects'))
check("G: 3gp6 count_atoms > 0 (loaded)", cmd.count_atoms('3gp6') > 0)
# SOL/NA/CL stripped (0 atoms for each stripped resn).
check("G: SOL stripped (0 atoms)", cmd.count_atoms('3gp6 and resn SOL') == 0)
check("G: NA stripped (0 atoms)", cmd.count_atoms('3gp6 and resn NA') == 0)
check("G: CL stripped (0 atoms)", cmd.count_atoms('3gp6 and resn CL') == 0)
# MET/DPP preserved (> 0 atoms).
check("G: MET preserved (> 0 atoms)", cmd.count_atoms('3gp6 and resn MET') > 0)
check("G: DPP preserved (> 0 atoms)", cmd.count_atoms('3gp6 and resn DPP') > 0)
# Per-state: 2 atoms (MET + DPP) per model; 2 states (one per MODEL).
check("G: state 1 has 2 atoms (MET+DPP)", cmd.count_atoms('3gp6', state=1) == 2)
check("G: state 2 has 2 atoms (MET+DPP)", cmd.count_atoms('3gp6', state=2) == 2)
# Cache .pdb.gz written.
_g_cache = demos.cache_path_for('3gp6')
check("G: cache .pdb.gz written", _g_cache is not None and os.path.exists(_g_cache))
check("G: is_cached('3gp6') == True", demos.is_cached('3gp6') is True)
# The .dry intermediate was cleaned up (cleanup_temp reached because load
# succeeded -- before the fix, load failed and the .dry was orphaned).
check("G: .dry intermediate cleaned up", not os.path.exists(_synthetic_raw + '.dry'))
# Clean the synthetic .raw temp (the drain cleans .raw in the GUI; we do it
# here for determinism).
demos.cleanup_temp(_synthetic_raw)

# Bonus: if the REAL 3gp6.raw.dry (orphaned from the failed GUI run) is staged,
# load it directly with format='pdb' to confirm the fix works on real data.
_real_dry = os.path.join(_memprotmd_dir, '3gp6.raw.dry')
if os.path.exists(_real_dry):
    if '3gp6_realdry' in cmd.get_names('objects'):
        cmd.delete('3gp6_realdry')
    try:
        cmd.load(demos.to_windows_path(_real_dry), object='3gp6_realdry',
                 format='pdb')
        check("G: real 3gp6.raw.dry loads with format='pdb' (real data)",
              cmd.count_atoms('3gp6_realdry') > 0)
        cmd.delete('3gp6_realdry')
    except Exception as _e:
        check("G: real 3gp6.raw.dry loads with format='pdb' (exc: %s)" % _e,
              False)
else:
    check("G: real 3gp6.raw.dry not staged (skipped)", True)

# --- M. SUMMARY ---
_n_pass = sum(1 for _, ok in RESULTS if ok)
print("\n=== PHASE9 SMOKE: %d/%d PASSED, %d FAIL ===" %
      (_n_pass, len(RESULTS), len(RESULTS) - _n_pass))
sys.exit(1 if _n_pass < len(RESULTS) else 0)
