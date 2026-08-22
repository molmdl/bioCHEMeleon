# diag_4wb3_anchor.py -- Headless diagnostic for the 4wb3 anchor-duplicate-id bug.
# Run: cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\src\run-conda-pymol.bat -cq smoke\diag_4wb3_anchor.py"
#
# Bug: insert_cartoon_segment_hider asserts len(ids)==1 but gets [256, 257]
# (two alt-conf CA atoms of ASN 710 on chain A, altloc A and B).
#
# This script verifies the full mechanism:
# 1. cas_by_chain composition (does iterate match both alt-confs?)
# 2. pick_segments output (which segments include the alt-conf residue?)
# 3. Segment copy atom count (does backbone match both alt-confs?)
# 4. Post-retag anchor selector match count (1 or 2?)
import os
import random
from pymol import cmd

# --- Pure functions copied from generators.py (to avoid pymol.Qt import) ---

def _even_starts(n_res, count, segment_size):
    footprint = count * segment_size
    slack = n_res - footprint
    n_gaps = count + 1
    base = slack // n_gaps
    rem = slack % n_gaps
    gaps = [base + (1 if k < rem else 0) for k in range(n_gaps)]
    starts = []
    pos = gaps[0]
    for k in range(count):
        starts.append(pos)
        pos += segment_size + gaps[k + 1]
    return starts


def pick_segments(cas_by_chain, count, segment_size=3):
    if not cas_by_chain:
        return []
    chains = sorted(cas_by_chain.keys(),
                    key=lambda c: len(cas_by_chain[c]), reverse=True)
    out = []
    for ch in chains:
        if len(out) >= count:
            break
        resis = [r[0] for r in cas_by_chain[ch]]
        n_res = len(resis)
        if n_res < segment_size:
            continue
        windows = [(resis[i], resis[i + segment_size - 1])
                   for i in range(n_res - segment_size + 1)]
        need = count - len(out)
        if need == 1:
            mid = (len(windows) - 1) // 2
            out.append((ch, windows[mid][0], windows[mid][1]))
        else:
            max_fit = n_res // segment_size
            actual = min(need, max_fit)
            if actual <= 1:
                mid = (len(windows) - 1) // 2
                out.append((ch, windows[mid][0], windows[mid][1]))
            else:
                for s in _even_starts(n_res, actual, segment_size):
                    out.append((ch, resis[s], resis[s + segment_size - 1]))
    return out[:count]


CARTOON_RESI_OFFSET = 10000

DATA_DIR = os.path.join("biochemeleon", "data", "demos")
PDB_PATH = os.path.join(DATA_DIR, "4wb3.pdb")

print("=" * 70)
print("4WB3 ANCHOR DUPLICATE ID DIAGNOSTIC")
print("=" * 70)

# 1. Load 4wb3
cmd.reinitialize()
cmd.load(PDB_PATH, "4wb3")
n_total = cmd.count_atoms("4wb3")
print("\n[1] Loaded 4wb3: %d total atoms" % n_total)

# 2. Check alt-conf atoms
print("\n[2] Alt-conf atoms in 4wb3:")
stored_altconfs = []
cmd.iterate("4wb3", "stored_altconfs.append((ID, chain, resv, name, alt, segi))",
            space={'stored_altconfs': stored_altconfs})
alt_atoms = [(a[0], a[1], a[2], a[3], a[4]) for a in stored_altconfs if a[4] != '']
print("  Total atoms with non-blank alt: %d" % len(alt_atoms))
# Group by (chain, resv) to find alt-conf residues
from collections import defaultdict
alt_residues = defaultdict(list)
for aid, chain, resv, name, alt in alt_atoms:
    alt_residues[(chain, resv)].append((aid, name, alt))
for key in sorted(alt_residues.keys()):
    chain, resv = key
    atoms = alt_residues[key]
    ca_atoms = [a for a in atoms if a[1].strip() == 'CA']
    print("  Chain %s resv %d: %d alt-conf atoms, %d CA atoms: %s" % (
        chain, resv, len(atoms), len(ca_atoms),
        [(a[0], a[2]) for a in ca_atoms]))

# 3. Build cas_by_chain exactly as __init__.py does
print("\n[3] Building cas_by_chain (polymer and (name CA or name P)):")
cas_list = []
cmd.iterate("4wb3 and polymer and (name CA or name P)",
            "stored.append((chain, resv, ID))",
            space={'stored': cas_list})
cas_by_chain = {}
for chain, resi, ca_id in cas_list:
    cas_by_chain.setdefault(chain, []).append((resi, ca_id))

print("  Chains found: %s" % sorted(cas_by_chain.keys()))
for ch in sorted(cas_by_chain.keys()):
    entries = cas_by_chain[ch]
    resis = [r[0] for r in entries]
    # Check for duplicate resv values
    from collections import Counter
    res_counts = Counter(resis)
    duplicates = {r: c for r, c in res_counts.items() if c > 1}
    print("  Chain '%s': %d entries, resv range %d-%d, %d unique resv" % (
        ch, len(entries), min(resis), max(resis), len(set(resis))))
    if duplicates:
        print("    ** DUPLICATE resv values (alt-conf!): %s" % duplicates)
        for dup_resv, dup_count in sorted(duplicates.items()):
            dup_ids = [r[1] for r in entries if r[0] == dup_resv]
            print("      resv %d: %d entries, IDs=%s" % (dup_resv, dup_count, dup_ids))

# 4. Check: does 'polymer' match the nucleic chains (D, E)?
print("\n[4] Polymer classification of nucleic chains:")
for ch in ['D', 'E']:
    n_polymer = cmd.count_atoms("4wb3 and chain '%s' and polymer" % ch)
    n_total_ch = cmd.count_atoms("4wb3 and chain '%s'" % ch)
    n_p = cmd.count_atoms("4wb3 and chain '%s' and name P" % ch)
    n_ca = cmd.count_atoms("4wb3 and chain '%s' and name CA" % ch)
    print("  Chain '%s': %d total, %d polymer, %d P atoms, %d CA atoms" % (
        ch, n_total_ch, n_polymer, n_p, n_ca))

# 5. Call pick_segments for various counts
print("\n[5] pick_segments results:")
for count in [1, 2, 3, 4]:
    segs = pick_segments(cas_by_chain, count)
    print("  count=%d: %s" % (count, segs))
    for (ch, start, end) in segs:
        mid_resv = start + 1  # for segment_size=3
        # Check if the middle residue has alt-conf
        mid_alts = [a for a in alt_atoms if a[1] == ch and a[2] == mid_resv]
        has_altconf = len(mid_alts) > 0
        print("    -> chain=%s resi %d-%d, middle=%d, alt-conf=%s" % (
            ch, start, end, mid_resv, has_altconf))

# 6. Simulate the segment copy + retag for segments that include alt-conf
print("\n[6] Simulating segment copy + retag (the actual bug path):")

# Test ALL possible 3-residue segments on chain A to find which ones trigger
chain_a_resis = sorted(set(r[0] for r in cas_by_chain.get('A', [])))
print("  Chain A unique resv values: %d (range %d-%d)" % (
    len(chain_a_resis, ), min(chain_a_resis), max(chain_a_resis)))

# Find segments whose middle residue has alt-conf
altconf_resvs = set(r[2] for r in alt_atoms)  # resv values with alt-conf
print("  Alt-conf resv values: %s" % sorted(altconf_resvs))

# Test each possible 3-res window on chain A
for i in range(len(chain_a_resis) - 2):
    start = chain_a_resis[i]
    mid = chain_a_resis[i + 1]
    end = chain_a_resis[i + 2]
    if mid not in altconf_resvs:
        continue  # skip non-alt-conf middle residues

    print("\n  --- Segment chain A resi %d-%d (middle=%d, HAS ALT-CONF) ---" % (
        start, end, mid))

    # Simulate: copy backbone segment
    tmp = "_bchm_diag_tmp"
    cmd.delete(tmp)
    seg_sele = "4wb3 and chain 'A' and resi %d-%d and backbone" % (start, end)
    n_copy = cmd.count_atoms(seg_sele)
    cmd.create(tmp, seg_sele, 1, 1, zoom=0)
    n_created = cmd.count_atoms(tmp)
    print("  Segment copy: %d atoms in selection, %d atoms created" % (
        n_copy, n_created))

    # Check how many CA atoms the middle residue has in the copy
    mid_ca_count = cmd.count_atoms("%s and resi %d and name CA" % (tmp, mid))
    mid_p_count = cmd.count_atoms("%s and resi %d and name P" % (tmp, mid))
    print("  Middle residue %d in copy: %d CA atoms, %d P atoms" % (
        mid, mid_ca_count, mid_p_count))

    # List all atoms at the middle residue in the copy
    mid_atoms = []
    cmd.iterate("%s and resi %d" % (tmp, mid),
                "stored.append((ID, name, alt, resv))",
                space={'stored': mid_atoms})
    print("  Middle residue %d atoms in copy:" % mid)
    for a in mid_atoms:
        print("    ID=%d name=%s alt='%s' resv=%d" % (a[0], a[1], a[2], a[3]))

    # Simulate retag: chain='H', segi='GAME', alt='', resi=resv+10000
    cmd.alter(tmp,
              "chain='H'; segi='GAME'; alt=''; ss='L'; resi=resv+%d" % CARTOON_RESI_OFFSET,
              space={})

    # Check the anchor selector
    new_mid = mid + CARTOON_RESI_OFFSET
    anchor_sele = "%s and chain H and resi %d and (name CA or name P) and segi GAME" % (
        tmp, new_mid)
    n_anchor = cmd.count_atoms(anchor_sele)
    ids = cmd.identify(anchor_sele + " and b < 0", mode=0)
    # Set b=-999 first (as the code does)
    cmd.alter(anchor_sele, "b=-999.0", space={})
    ids_after_b = cmd.identify(anchor_sele + " and b < 0", mode=0)
    print("  After retag: anchor selector matches %d atoms" % n_anchor)
    print("  After retag + b=-999: identify returns %s" % ids_after_b)
    if len(ids_after_b) != 1:
        print("  *** ASSERTION WOULD FAIL: expected 1, got %d ***" % len(ids_after_b))
    else:
        print("  -> OK (1 anchor id)")

    cmd.delete(tmp)

# 7. Summary: test the actual pick_segments output
print("\n[7] Testing actual pick_segments picks (count=1..4):")
for count in [1, 2, 3, 4]:
    segs = pick_segments(cas_by_chain, count)
    for (ch, start, end) in segs:
        mid_resv = start + 1
        is_altconf = mid_resv in altconf_resvs
        print("  count=%d: chain=%s resi %d-%d, mid=%d, alt-conf=%s" % (
            count, ch, start, end, mid_resv, is_altconf))
        if is_altconf:
            # Simulate the full path
            tmp = "_bchm_diag_pick"
            cmd.delete(tmp)
            seg_sele = "4wb3 and chain '%s' and resi %d-%d and backbone" % (
                ch, start, end)
            cmd.create(tmp, seg_sele, 1, 1, zoom=0)
            cmd.alter(tmp,
                      "chain='H'; segi='GAME'; alt=''; ss='L'; resi=resv+%d" % CARTOON_RESI_OFFSET,
                      space={})
            new_mid = mid_resv + CARTOON_RESI_OFFSET
            anchor_sele = ("%s and chain H and resi %d and (name CA or name P) and segi GAME"
                           % (tmp, new_mid))
            cmd.alter(anchor_sele, "b=-999.0", space={})
            ids = cmd.identify(anchor_sele + " and b < 0", mode=0)
            print("    -> identify returns %s (len=%d) %s" % (
                ids, len(ids), "*** FAIL ***" if len(ids) != 1 else "OK"))
            cmd.delete(tmp)

# 8. Check what the OLD (pre-quick-005) adjacent placement would pick
print("\n[8] Simulating OLD adjacent placement (greedy from N-term):")
for ch in sorted(cas_by_chain.keys(), key=lambda c: len(cas_by_chain[c]), reverse=True):
    resis = sorted(set(r[0] for r in cas_by_chain[ch]))
    n_res = len(resis)
    if n_res < 3:
        continue
    # Old code: pick adjacent windows starting from index 0
    for count in [1, 2, 3, 4]:
        old_segs = []
        idx = 0
        for _ in range(count):
            if idx + 2 < n_res:
                old_segs.append((ch, resis[idx], resis[idx + 2]))
                idx += 3  # greedy advance
        for (och, ostart, oend) in old_segs:
            omid = ostart + 1
            is_altconf = omid in altconf_resvs
            if is_altconf:
                print("  OLD count=%d: chain=%s resi %d-%d, mid=%d *** ALT-CONF ***" % (
                    count, och, ostart, oend, omid))
    break  # only check the longest chain

print("\n" + "=" * 70)
print("DIAGNOSTIC COMPLETE")
print("=" * 70)
