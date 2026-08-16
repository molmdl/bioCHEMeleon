# diag_phase11_dup_id.py -- Headless diagnostic for the Phase 11 duplicate-anchor-id
# bug on MemProtMD structures (3gp6 dry, and 1gzm if available). The alt-conf
# hypothesis was DISPROVED: the trigger files have NO alt-confs. This diagnostic
# traces insert_cartoon_segment_hider step-by-step to find WHERE the duplicate
# id appears.
#
# Run headlessly:
#   bash wsl2win_cp.sh
#   mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/diag_phase11_dup_id.py tmp/bioCHEMeleon/smoke/
#   # stage the trigger PDB files into the Windows-facing path:
#   mkdir -p tmp/bioCHEMeleon/tmp && cp tmp/3gp6_default_dppc-atomistic_dry.pdb tmp/bioCHEMeleon/tmp/
#   cd tmp/bioCHEMeleon && timeout 150 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\diag_phase11_dup_id.py" 2>&1 | tail -150
import os
import sys
from collections import Counter
from pymol import cmd
from biochemeleon import game, mutation, generators, backup

CARTOON_OFFSET = mutation.CARTOON_RESI_OFFSET


def _count(sele, **kw):
    return cmd.count_atoms(sele, **kw)


def census(obj, label):
    print("\n===== %s: census %s =====" % (label, obj))
    print("  total atoms: %d  states: %d" % (_count(obj), cmd.count_states(obj)))
    chains = []
    cmd.iterate(obj, "stored.append(chain)", space={'stored': chains})
    cc = Counter(chains)
    print("  chain distribution: %r" % dict(cc))
    # polymer + name CA/P
    n_poly = _count("%s and polymer" % obj)
    n_poly_ca = _count("%s and polymer and name CA" % obj)
    n_poly_p = _count("%s and polymer and name P" % obj)
    print("  polymer=%d  polymer+name CA=%d  polymer+name P=%d" % (
        n_poly, n_poly_ca, n_poly_p))
    # all name CA (not just polymer)
    n_all_ca = _count("%s and name CA" % obj)
    n_all_p = _count("%s and name P" % obj)
    print("  ALL name CA=%d  ALL name P=%d  (incl. non-polymer)" % (
        n_all_ca, n_all_p))
    # check for duplicate ids
    ids = []
    cmd.iterate(obj, "stored.append(ID)", space={'stored': ids})
    id_counts = Counter(ids)
    dups = {k: v for k, v in id_counts.items() if v > 1}
    print("  total ids=%d  unique ids=%d  duplicate id count=%d" % (
        len(ids), len(id_counts), len(dups)))
    if dups:
        print("  DUPLICATE IDS (first 10): %r" % list(dups.items())[:10])
        # show atoms with duplicate ids
        for dup_id in list(dups.keys())[:3]:
            rows = []
            cmd.iterate("%s and id %d" % (obj, dup_id),
                        "stored.append((ID, chain, resv, name, resn, segi, alt))",
                        space={'stored': rows})
            print("    id %d: %r" % (dup_id, rows))
    return n_poly_ca


def build_cas_by_chain(obj):
    cas = []
    cmd.iterate("%s and polymer and (name CA or name P)" % obj,
                "stored.append((chain, resv, ID))", space={'stored': cas})
    d = {}
    for ch, ri, cid in cas:
        d.setdefault(ch, []).append((ri, cid))
    return d


def trace_insert(obj, chain, start_resi, end_resi, backup_name, label):
    """Step through insert_cartoon_segment_hider MANUALLY, printing at each step."""
    print("\n----- %s: trace insert_cartoon_segment_hider -----" % label)
    new_start, new_end = mutation.cartoon_hider_resi_range(start_resi, end_resi)
    new_mid = new_start + 1
    new_mid_lo, new_mid_hi = new_start + 1, new_end - 1
    print("  chain=%r start_resi=%d end_resi=%d -> new_start=%d new_end=%d new_mid=%d"
          % (chain, start_resi, end_resi, new_start, new_end, new_mid))

    # Step 1: copy backbone from backup to tmp
    tmp = cmd.get_unused_name("_bchm_seg")
    segment_sele = "%s and chain %s and resi %d-%d and backbone" % (
        backup_name, chain, start_resi, end_resi)
    print("  [step1] segment_sele = %r" % (segment_sele,))
    n_seg = _count(segment_sele)
    print("  [step1] atoms matching segment_sele in backup: %d" % n_seg)
    # also check WITHOUT the chain filter (to see if blank chain is the issue)
    seg_no_chain = "%s and resi %d-%d and backbone" % (backup_name, start_resi, end_resi)
    n_seg_nochain = _count(seg_no_chain)
    print("  [step1] same WITHOUT chain filter: %d" % n_seg_nochain)
    # check chain values of atoms matching the no-chain version
    seg_chains = []
    cmd.iterate(seg_no_chain, "stored.append(chain)",
                space={'stored': seg_chains})
    print("  [step1] chains in no-chain segment: %r" % (
        dict(Counter(seg_chains)),))
    # check atom names in the segment (with chain filter)
    seg_names = []
    cmd.iterate(segment_sele, "stored.append((name, resv, ID, chain))",
                space={'stored': seg_names})
    print("  [step1] atoms in chain-filtered segment: %d" % len(seg_names))
    for r in seg_names:
        print("         %r" % (r,))

    cmd.create(tmp, segment_sele, 1, 1, zoom=0)
    print("  [step1] tmp=%s created; tmp atom count=%d" % (tmp, _count(tmp)))
    # check tmp for duplicate ids
    tmp_ids = []
    cmd.iterate(tmp, "stored.append(ID)", space={'stored': tmp_ids})
    tmp_id_dups = {k: v for k, v in Counter(tmp_ids).items() if v > 1}
    if tmp_id_dups:
        print("  [step1] *** tmp has DUPLICATE IDS: %r" % list(tmp_id_dups.items())[:5])
    tmp_rows = []
    cmd.iterate(tmp, "stored.append((ID, chain, resv, name, resn, segi, alt))",
                space={'stored': tmp_rows})
    print("  [step1] tmp atoms (first 16):")
    for r in tmp_rows[:16]:
        print("         %r" % (r,))

    # Step 2: retag tmp
    cmd.alter(tmp,
              "chain='H'; segi='GAME'; alt=''; ss='L'; resi=resv+%d" % CARTOON_OFFSET,
              space={})
    tmp_rows2 = []
    cmd.iterate(tmp, "stored.append((ID, chain, resv, name, resn, segi, alt))",
                space={'stored': tmp_rows2})
    print("  [step2] tmp after retag (first 16):")
    for r in tmp_rows2[:16]:
        print("         %r" % (r,))
    # check for multiple CAs at new_mid
    mid_cas = [r for r in tmp_rows2 if r[1] == 'H' and r[2] == new_mid and r[3] == 'CA']
    print("  [step2] CAs at (chain H, resi %d): %d" % (new_mid, len(mid_cas)))
    for r in mid_cas:
        print("         %r" % (r,))

    # Step 3: skip displacement (not relevant to the dup-id bug)

    # Step 4: union-create
    combined = cmd.get_unused_name("_bchm_comb")
    cmd.create(combined, "(%s) or (%s)" % (obj, tmp),
               source_state=1, target_state=1, zoom=0)
    print("  [step4] combined=%s created; combined count=%d" % (
        combined, _count(combined)))
    # check combined for duplicate ids
    comb_ids = []
    cmd.iterate(combined, "stored.append(ID)", space={'stored': comb_ids})
    comb_dups = {k: v for k, v in Counter(comb_ids).items() if v > 1}
    print("  [step4] combined ids: total=%d unique=%d dup_count=%d" % (
        len(comb_ids), len(set(comb_ids)), len(comb_dups)))
    if comb_dups:
        print("  [step4] combined DUPLICATE IDS (first 5): %r" % (
            list(comb_dups.items())[:5]))
    # check chain-H GAME atoms in combined
    comb_hgame = []
    cmd.iterate("%s and chain H and segi GAME" % combined,
                "stored.append((ID, resv, name, chain, segi))",
                space={'stored': comb_hgame})
    print("  [step4] combined chain-H GAME atoms: %d" % len(comb_hgame))
    for r in comb_hgame[:20]:
        print("         %r" % (r,))

    # Step 4b: replace object state 1
    cmd.create(obj, combined, source_state=1, target_state=1, zoom=0)
    cmd.delete(combined)
    cmd.delete(tmp)
    cmd.sort(obj)
    print("  [step4b] obj after replace+sort; count=%d" % _count(obj))

    # Step 5: check chain-H GAME atoms in obj
    obj_hgame = []
    cmd.iterate("%s and chain H and segi GAME" % obj,
                "stored.append((ID, resv, name, chain, segi))",
                space={'stored': obj_hgame})
    print("  [step5] obj chain-H GAME atoms: %d" % len(obj_hgame))
    for r in obj_hgame[:20]:
        print("         %r" % (r,))

    # Step 6: set b=-999 on anchor
    anchor_sele = ("%s and chain H and resi %d and (name CA or name P) and segi GAME"
                   % (obj, new_mid))
    print("  [step6] anchor_sele = %r" % (anchor_sele,))
    n_anchor = _count(anchor_sele)
    print("  [step6] atoms matching anchor_sele BEFORE alter: %d" % n_anchor)
    anchor_rows = []
    cmd.iterate(anchor_sele,
                "stored.append((ID, resv, name, chain, segi, b))",
                space={'stored': anchor_rows})
    for r in anchor_rows:
        print("         %r" % (r,))
    cmd.alter(anchor_sele, "b=%.1f" % -999.0, space={})

    # Step 7: identify
    ids = cmd.identify(anchor_sele + " and b < 0", mode=0)
    print("  [step7] identify(anchor_sele + ' and b < 0') = %r" % (ids,))
    print("  [step7] len == 1 -> %s" % (len(ids) == 1,))
    return ids


# ===== Load 3gp6 dry (the trigger file we have) =====
print("=" * 64)
print("Loading 3gp6_default_dppc-atomistic_dry.pdb")
print("=" * 64)
DRY3GP6 = "tmp/3gp6_default_dppc-atomistic_dry.pdb"
if not os.path.exists(DRY3GP6):
    print("ERROR: %s not found" % DRY3GP6)
    sys.exit(1)
cmd.load(DRY3GP6, object="3gp6", zoom=0, format='pdb')
mutation.collapse_to_single_state("3gp6")
census("3gp6", "3gp6-load")

# Build cas_by_chain (mirrors _prepare_and_start)
cas_by = build_cas_by_chain("3gp6")
print("\n  cas_by_chain keys: %r" % (list(cas_by.keys()),))
for ch in cas_by:
    entries = cas_by[ch]
    resis = [r[0] for r in entries]
    print("  chain %r: %d entries, resi range %d-%d, first 5=%r" % (
        ch, len(entries), min(resis), max(resis), entries[:5]))
    dup_resis = {r: n for r, n in Counter(resis).items() if n > 1}
    if dup_resis:
        print("    *** duplicate resis: %r" % list(dup_resis.items())[:5])

# Run pick_segments
segs = generators.pick_segments(cas_by, 1)
print("\n  pick_segments(cas_by, 1) = %r" % (segs,))

# Take a backup (mirrors game.start)
bk = backup.snapshot("3gp6")
print("  backup=%s; backup count=%d" % (bk, _count(bk)))
census(bk, "3gp6-backup")

# Trace the insert
if segs:
    ch, s, e = segs[0]
    disp = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)[0]
    ids = trace_insert("3gp6", ch, s, e, bk, "3gp6-trace")
    print("\n  >>> 3gp6 result: identify returned %r (len=%d)" % (ids, len(ids)))
    if len(ids) != 1:
        print("  >>> BUG REPRODUCED on 3gp6!")
    else:
        print("  >>> 3gp6 does NOT reproduce (1 id). Bug may be 1gzm-specific.")
    # cleanup
    backup.restore("3gp6", bk)
    backup.discard(bk)
else:
    print("  no segment picked -- cannot trace")

# Also try game.start directly (the full flow)
print("\n" + "=" * 64)
print("Trying game.start directly on 3gp6")
print("=" * 64)
cmd.delete("3gp6")
cmd.load(DRY3GP6, object="3gp6", zoom=0, format='pdb')
mutation.collapse_to_single_state("3gp6")
cas_by2 = build_cas_by_chain("3gp6")
segs2 = generators.pick_segments(cas_by2, 1)
if segs2:
    ch, s, e = segs2[0]
    disp2 = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)[0]
    gc = game.GameController("3gp6")
    try:
        gc.start([((ch, s, e, disp2), 'cartoon')])
        print("  game.start SUCCEEDED; registry len=%d" % len(gc.registry.all()))
        for r in gc.registry.all():
            print("    id=%s rep=%s endpoint_resvs=%r" % (r.id, r.rep, r.endpoint_resvs))
        gc.cleanup()
    except AssertionError as exc:
        print("  *** AssertionError: %s" % exc)
        # inspect the object state after crash
        census("3gp6", "3gp6-after-crash")
        hgame = []
        cmd.iterate("3gp6 and chain H and segi GAME",
                    "stored.append((ID, resv, name, chain, segi, b))",
                    space={'stored': hgame})
        print("  chain-H GAME atoms after crash: %d" % len(hgame))
        for r in hgame[:30]:
            print("    %r" % (r,))
        try:
            gc.cleanup()
        except Exception:
            pass

print("\n" + "=" * 64)
print("Diagnostic complete.")
print("=" * 64)
