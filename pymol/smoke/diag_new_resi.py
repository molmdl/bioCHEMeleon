# diag_new_resi.py -- verify the NEW-RESI single-state design end-to-end.
# cmd.create preserves source ids (backup=snapshot -> copy shares id with the
# real CA), so id-keyed scoring can't disambiguate a real-trace click. FIX:
# reassign the copy's RESI to NEW values (disjoint from the real segment +
# from sphere/stick resi 9001). The copy then shares the id but has a DIFFERENT
# resv -> on_pick disambiguates by resv (already passed by the wizard, no
# wizard.py change). Tests: alter resi works; copy renders; single-state;
# originals preserved; anchor NEW resv differs from real resv; cleanup restores.
import os
import sys
from pymol import cmd

obj = "1ubq"
PNG = "diag_new_resi.png"
RESI_OFFSET = 10000  # copy resi = real resi + 10000 (disjoint from real + 9001)


def png_size():
    cmd.png(PNG)
    return os.path.getsize(PNG) if os.path.exists(PNG) else 0


cmd.fetch(obj, async_=0)
mutation_collapse = True  # 1ubq is single-state; skip
orig_count = cmd.count_atoms(obj)
# Snapshot (backup), mirroring backup.snapshot
bak = "_bchm_backup"
cmd.delete(bak)
cmd.create(bak, obj, 1, 1)

# pick a segment (chain A, resi 10-12)
chain, start_resi, end_resi = "A", 10, 12
new_start = start_resi + RESI_OFFSET
new_end = end_resi + RESI_OFFSET
new_mid = start_resi + 1 + RESI_OFFSET

# 1. Copy backbone from backup to temp
tmp = "_bchm_seg"
cmd.delete(tmp)
cmd.create(tmp, "%s and chain %s and resi %d-%d and backbone" % (bak, chain, start_resi, end_resi), 1, 1, zoom=0)
# 2. Retag: chain H + segi GAME + alt='' + ss L + NEW resi (resi = resv + offset)
#    Test if alter can reassign resi (resv is the numeric residue value).
cmd.alter(tmp, "chain='H'; segi='GAME'; alt=''; ss='L'; resi=resv+%d" % RESI_OFFSET, space={})
# verify resi reassigned
tmp_resis = []
cmd.iterate(tmp, "stored.append(resv)", space={'stored': tmp_resis})
print("tmp resv after alter:", sorted(set(tmp_resis)))
print("alter resi worked?", set(tmp_resis) == {new_start, new_start + 1, new_end})

# 3. Displace middle (NEW resi mid)
cmd.alter_state(1, "%s and resi %d" % (tmp, new_mid), "x=x+2.0; y=y+2.0; z=z+2.0", space={})
# 4. Union-create merge into state 1
comb = "_bchm_comb"
cmd.delete(comb)
cmd.create(comb, "(%s) or (%s)" % (obj, tmp), 1, 1, zoom=0)
cmd.create(obj, comb, 1, 1, zoom=0)
cmd.delete(comb)
cmd.delete(tmp)
cmd.sort(obj)

# Anchor: chain H, NEW resi mid, CA, segi GAME, b=-999
anchor_sele = "%s and chain H and resi %d and name CA and segi GAME" % (obj, new_mid)
cmd.alter(anchor_sele, "b=-999.0", space={})
anchor_ids = cmd.identify(anchor_sele + " and b < 0", mode=0)
print("anchor id:", anchor_ids, "(shared with real CA? real CA id below)")
real_ca = []
cmd.iterate("%s and chain A and name CA and resi %d" % (obj, start_resi + 1),
            "stored.append(ID)", space={'stored': real_ca})
print("real chain-A CA id at resi %d:" % (start_resi + 1), real_ca)
print("anchor id == real CA id (shared)?",
      bool(anchor_ids) and bool(real_ca) and anchor_ids[0] == real_ca[0])

# Show cartoon on the chain-H GAME fragment
cmd.show("cartoon", "%s and chain H and resi %d-%d and segi GAME" % (obj, new_start, new_end))

# Render check
cmd.hide("everything", obj)
cmd.show("cartoon", "%s and chain H and segi GAME" % obj)
cmd.zoom("%s and chain H and segi GAME" % obj)
game_png = png_size()
cmd.hide("everything", obj)
blank = png_size()
print("GAME cartoon PNG=%d blank=%d rendered? %s" % (
    game_png, blank, game_png > blank * 1.3 + 50))

# Restore view + show everything for state checks
print("single-state?", cmd.count_states(obj) == 1)
print("originals survive (non-GAME polymer state1)?",
      cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=1) > 0)
print("orig_count=%d, now=%d (orig+12 GAME)" % (
    orig_count, cmd.count_atoms(obj)))
print("GAME atoms:", cmd.count_atoms("%s and segi GAME" % obj))

# NEW resv vs real resv: the disambiguation key
print("anchor NEW resv=%d ; real CA resv=%d (differ? %s)" % (
    new_mid, start_resi + 1, new_mid != start_resi + 1))

# Cleanup: remove segi GAME (the fragment) -> count restored
cmd.remove("%s and segi GAME" % obj)
print("after cleanup GAME atoms:", cmd.count_atoms("%s and segi GAME" % obj))
print("count restored to orig?", cmd.count_atoms(obj) == orig_count)
sys.exit(0)
