# diag_nucleic_hiders.py -- Headless diagnostic for nucleic-acid hider support.
# Run: cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\src\run-conda-pymol.bat -cq smoke\diag_nucleic_hiders.py"
#
# Confirms the root cause: `name CA` selectors in _prepare_and_start are empty
# for nucleic acids, and tests nucleic-appropriate alternatives (name P, etc.).
import os
from pymol import cmd

# Load bundled demos from the package data dir (relative to the staged cwd).
DATA_DIR = os.path.join("biochemeleon", "data", "demos")

DEMOS = [
    ("1znf", "protein"),   # control: has CA
    ("5e54", "rna"),       # pure nucleic
    ("1k8p", "dna"),       # pure nucleic
    ("2qbz", "rna"),       # pure nucleic
    ("4wb3", "mixed"),     # protein + nucleic
]

def count(sele):
    """Safe count_atoms; returns -1 on error."""
    try:
        return cmd.count_atoms(sele)
    except Exception as e:
        return "ERR: %s" % e

print("=" * 70)
print("NUCLEIC ACID HIDER DIAGNOSTIC")
print("=" * 70)

for demo_id, kind in DEMOS:
    pdb_path = os.path.join(DATA_DIR, demo_id + ".pdb")
    obj = demo_id
    cmd.delete(obj)
    try:
        cmd.load(pdb_path, object=obj, zoom=0)
    except Exception as e:
        print("\n[%s] LOAD FAILED: %s" % (demo_id, e))
        continue

    total = count(obj)
    print("\n[%s] (%s) total atoms: %d" % (demo_id, kind, total))

    # --- The CURRENT selectors used in _prepare_and_start ---
    ca_all = count("%s and not segi GAME and name CA" % obj)
    ca_poly = count("%s and polymer and name CA" % obj)
    print("  CURRENT 'name CA' (neighbor_ids pool):  %s" % ca_all)
    print("  CURRENT 'polymer and name CA' (cas):    %s" % ca_poly)

    # --- Nucleic-appropriate selectors ---
    p_all = count("%s and name P" % obj)
    p_poly = count("%s and polymer and name P" % obj)
    c1p = count("%s and name C1'" % obj)
    c4p = count("%s and name C4'" % obj)
    print("  'name P' (phosphate):                   %s" % p_all)
    print("  'polymer and name P':                   %s" % p_poly)
    print("  'name C1'' (sugar):                     %s" % c1p)
    print("  'name C4'' (sugar):                     %s" % c4p)

    # --- Combined protein+nucleic anchor ---
    combined = count("%s and polymer and (name CA or name P)" % obj)
    print("  'polymer and (name CA or name P)':      %s" % combined)

    # --- backbone selector (should match BOTH protein + nucleic) ---
    bb = count("%s and backbone" % obj)
    bb_poly = count("%s and polymer and backbone" % obj)
    print("  'backbone':                             %s" % bb)
    print("  'polymer and backbone':                 %s" % bb_poly)

    # --- polymer selector (should match nucleic acids) ---
    poly = count("%s and polymer" % obj)
    print("  'polymer':                              %s" % poly)

    # --- extent (for spheres; should be non-empty) ---
    ext = cmd.get_extent(obj)
    print("  extent: %s" % (ext[:2],))

    # --- Per-chain breakdown of CA vs P ---
    ca_chain_list = []
    cmd.iterate("%s and polymer and name CA" % obj,
                "stored.append(chain)", space={'stored': ca_chain_list})
    p_chain_list = []
    cmd.iterate("%s and polymer and name P" % obj,
                "stored.append(chain)", space={'stored': p_chain_list})
    from collections import Counter
    ca_cnt = Counter(ca_chain_list)
    p_cnt = Counter(p_chain_list)
    all_chains = sorted(set(list(ca_cnt.keys()) + list(p_cnt.keys())))
    for ch in all_chains:
        print("    chain %s: CA=%d  P=%d" % (ch, ca_cnt.get(ch, 0), p_cnt.get(ch, 0)))

print("\n" + "=" * 70)
print("DIAGNOSTIC COMPLETE")
print("=" * 70)
