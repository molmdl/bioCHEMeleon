# diag_fix_approaches.py -- Test fix approaches for the cmd.create-replaces-state bug.
# Root cause: cmd.create(object, tmp) REPLACES the object's state coords.
# Need a way to add alt-conf atoms WITHOUT destroying original state coords.
#
# Run: pymol -cq smoke/diag_fix_approaches.py
from pymol import cmd
import os

obj = "1ubq"
OUT = "diag_out"
if not os.path.exists(OUT):
    os.makedirs(OUT)
cmd.set("bg_rgb", "white")
cmd.set("ray_shadows", 0)

print("=== Fix approaches test ===")

cmd.fetch(obj, async_=0)
orig_count = cmd.count_atoms(obj)
print("orig: count=%d state1=%d" % (orig_count, cmd.count_atoms(obj, state=1)))

# Backup + tmp segment (mirror insert_altconf_cartoon_hider steps 1-3)
cmd.create("_bak", obj)
tmp = "_alt_tmp"
cmd.delete(tmp)
cmd.create(tmp, "%s and chain A and resi 23-25 and backbone" % obj, 1, 1, zoom=0)
cmd.alter(tmp, "alt='B'; segi='GAME'; ss='L'", space={})
# Displace middle (resi 24)
cmd.alter_state(1, "%s and resi 24" % tmp, "x=x+2.0; y=y+1.0; z=z+0.5", space={})
print("tmp: count=%d state1=%d" % (cmd.count_atoms(tmp), cmd.count_atoms(tmp, state=1)))

# Check tmp atom ids
tmp_ids = []
cmd.iterate(tmp, "stored.append(ID)", space={'stored': tmp_ids})
print("tmp ids:", tmp_ids)

# --- APPROACH A: union-selection create (build combined, then swap) ---
print("\n--- APPROACH A: union create 'obj or tmp' ---")
cmd.delete(obj)
cmd.fetch(obj, async_=0)
combined = "_combined"
cmd.delete(combined)
# Union selection: all atoms from obj + all atoms from tmp, into state 1
cmd.create(combined, "(%s) or (%s)" % (obj, tmp), source_state=1, target_state=1, zoom=0)
print("combined: count=%d state1=%d non-GAME=%d GAME=%d" % (
    cmd.count_atoms(combined),
    cmd.count_atoms(combined, state=1),
    cmd.count_atoms("%s and not segi GAME" % combined, state=1),
    cmd.count_atoms("%s and segi GAME" % combined, state=1)))
# Check ids: are original ids preserved?
comb_ids = []
cmd.iterate("%s and not segi GAME" % combined, "stored.append(ID)", space={'stored': comb_ids})
print("combined non-GAME id range: %d..%d (orig was 1..660)" % (
    min(comb_ids), max(comb_ids)))
comb_game_ids = []
cmd.iterate("%s and segi GAME" % combined, "stored.append(ID)", space={'stored': comb_game_ids})
print("combined GAME ids:", comb_game_ids)
# Check alt
comb_alts = []
cmd.iterate("%s and segi GAME" % combined, "stored.append(alt)", space={'stored': comb_alts})
print("combined GAME alts:", sorted(set(comb_alts)))

# --- APPROACH B: union create with source_state=0 (all states) ---
print("\n--- APPROACH B: union create source_state=0 ---")
cmd.delete(combined)
cmd.create(combined, "(%s) or (%s)" % (obj, tmp), source_state=0, target_state=1, zoom=0)
print("combined: count=%d state1=%d non-GAME=%d GAME=%d" % (
    cmd.count_atoms(combined),
    cmd.count_atoms(combined, state=1),
    cmd.count_atoms("%s and not segi GAME" % combined, state=1),
    cmd.count_atoms("%s and segi GAME" % combined, state=1)))

# --- APPROACH C: create combined from obj, then add tmp to a new state, collapse ---
print("\n--- APPROACH C: obj -> combined, tmp as state 2, collapse all to state 1 ---")
cmd.delete(combined)
cmd.create(combined, obj, 1, 1, zoom=0)  # combined = copy of obj (state 1)
print("after copy obj: state1=%d" % cmd.count_atoms(combined, state=1))
cmd.create(combined, tmp, source_state=1, target_state=-1, zoom=0)  # state 2 = tmp
print("after add tmp state2: states=%d state1=%d state2=%d" % (
    cmd.count_states(combined),
    cmd.count_atoms(combined, state=1), cmd.count_atoms(combined, state=2)))
# Collapse: create final from all states of combined into state 1
final = "_final"
cmd.delete(final)
cmd.create(final, combined, source_state=0, target_state=1, zoom=0)
print("after collapse: states=%d state1=%d non-GAME=%d GAME=%d" % (
    cmd.count_states(final),
    cmd.count_atoms(final, state=1),
    cmd.count_atoms("%s and not segi GAME" % final, state=1),
    cmd.count_atoms("%s and segi GAME" % final, state=1)))
final_ids = []
cmd.iterate("%s and not segi GAME" % final, "stored.append(ID)", space={'stored': final_ids})
print("final non-GAME id range: %d..%d" % (min(final_ids), max(final_ids)))
final_game_ids = []
cmd.iterate("%s and segi GAME" % final, "stored.append(ID)", space={'stored': final_game_ids})
print("final GAME ids:", final_game_ids)

# --- APPROACH D: the TWO-STATE approach but keep originals in BOTH states ---
# Create combined from obj (state 1), tmp into state 1 via union, tmp2 into state 2
print("\n--- APPROACH D: union create per alt-conf, multi-state with originals ---")
cmd.delete(obj)
cmd.fetch(obj, async_=0)
# tmp2 = second segment
tmp2 = "_alt_tmp2"
cmd.delete(tmp2)
cmd.create(tmp2, "%s and chain A and resi 40-42 and backbone" % obj, 1, 1, zoom=0)
cmd.alter(tmp2, "alt='B'; segi='GAME'; ss='L'", space={})
cmd.alter_state(1, "%s and resi 41" % tmp2, "x=x-1.5; y=y+2.0; z=z+1.0", space={})
# Build combined: obj + tmp in state 1 (union)
cmd.delete(combined)
cmd.create(combined, "(%s) or (%s)" % (obj, tmp), source_state=1, target_state=1, zoom=0)
# Add tmp2 to state 2 (union with current combined)
cmd.create(combined, "(%s) or (%s)" % (obj, tmp2), source_state=1, target_state=-1, zoom=0)
print("combined: states=%d state1=%d non-GAME=%d GAME=%d | state2=%d non-GAME2=%d GAME2=%d" % (
    cmd.count_states(combined),
    cmd.count_atoms(combined, state=1),
    cmd.count_atoms("%s and not segi GAME" % combined, state=1),
    cmd.count_atoms("%s and segi GAME" % combined, state=1),
    cmd.count_atoms(combined, state=2),
    cmd.count_atoms("%s and not segi GAME" % combined, state=2),
    cmd.count_atoms("%s and segi GAME" % combined, state=2)))

# --- VISUAL CHECK for Approach A: render to confirm both original + GAME render ---
print("\n--- APPROACH A visual check ---")
cmd.delete(obj)
cmd.fetch(obj, async_=0)
cmd.delete(combined)
cmd.create(combined, "(%s) or (%s)" % (obj, tmp), source_state=1, target_state=1, zoom=0)
cmd.show("cartoon", "%s and polymer" % combined)
cmd.show("cartoon", "%s and segi GAME" % combined)
cmd.zoom("%s and segi GAME and resi 24 and name CA" % combined, buffer=8)
cmd.ray(400, 300)
cmd.png(os.path.join(OUT, "approachA_game.png"))
print("approachA GAME PNG: %d bytes" % os.path.getsize(
    os.path.join(OUT, "approachA_game.png")))
cmd.zoom("%s and polymer" % combined, buffer=5)
cmd.ray(400, 300)
cmd.png(os.path.join(OUT, "approachA_full.png"))
print("approachA full PNG: %d bytes" % os.path.getsize(
    os.path.join(OUT, "approachA_full.png")))
# blank
cmd.hide("everything", "all")
cmd.ray(400, 300)
cmd.png(os.path.join(OUT, "approachA_blank.png"))
print("approachA blank PNG: %d bytes" % os.path.getsize(
    os.path.join(OUT, "approachA_blank.png")))

# Cleanup
cmd.delete("_bak")
cmd.delete(tmp)
cmd.delete(tmp2)
cmd.delete(combined)
cmd.delete(final)
print("\n=== done ===")
