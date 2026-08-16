# phase9_smoke.py -- Phase 9 headless smoke. Run: pymol -cq smoke/phase9_smoke.py
# Verifies the Phase 9 fetched-demo split API (download_large_demo /
# finalize_large_demo / load_cached_demo / cache helpers) + load_demo source
# branching headlessly (pure pymol.cmd.* only, NO Qt -- AGENTS.md: the headless
# path cannot run Qt). GUI paths (the QProgressDialog + QTimer drain + real
# network fetch with progress) are deferred to the 09-03 human-verify checkpoint.
#
# Uses the STAGED SASBDB sample (tmp/phase9-demos/SASDPG4_fit2_model1.pdb) to
# simulate the worker-download output; no real network. The real fetch + progress
# dialog is verified at the 09-03 human-verify checkpoint (needs the GUI + real
# network timing).
#
# Sections (~30 checks):
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

# Clean any stale cache from prior runs so the smoke is deterministic.
_cache_dir = demos._cache_dir()
if os.path.isdir(_cache_dir):
    for _f in os.listdir(_cache_dir):
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
    os.getcwd(), 'tmp', 'phase9-demos', 'SASDPG4_fit2_model1.pdb'))
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

# --- M. SUMMARY ---
_n_pass = sum(1 for _, ok in RESULTS if ok)
print("\n=== PHASE9 SMOKE: %d/%d PASSED, %d FAIL ===" %
      (_n_pass, len(RESULTS), len(RESULTS) - _n_pass))
sys.exit(1 if _n_pass < len(RESULTS) else 0)
