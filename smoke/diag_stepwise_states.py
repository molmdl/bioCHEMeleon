# diag_stepwise_states.py -- Pinpoint when state membership is lost during
# alt-conf hider insertion. Inserts hiders ONE AT A TIME and prints state
# counts + discrete flag after each. Also tests the HYPOTHESIS that
# cmd.create(target_state=0) replaces state 1 (vs merging).
#
# Run: pymol -cq smoke/diag_stepwise_states.py
from pymol import cmd
from biochemeleon import game, mutation, generators

obj = "1ubq"
print("=== Stepwise state diagnostic ===")

cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
print("after fetch+collapse: states=%d count=%d" % (
    cmd.count_states(obj), cmd.count_atoms(obj)))

def snap(label):
    ns = cmd.count_states(obj)
    print("\n[%s] states=%d count(no-state)=%d" % (label, ns, cmd.count_atoms(obj)))
    try:
        disc = cmd.get("discrete", obj)
    except Exception:
        disc = "?"
    print("  discrete=%s all_states=%s" % (disc, cmd.get("all_states", obj)))
    for st in range(1, ns + 1):
        tot = cmd.count_atoms(obj, state=st)
        game_n = cmd.count_atoms("%s and segi GAME" % obj, state=st)
        nongame = cmd.count_atoms("%s and not segi GAME" % obj, state=st)
        print("  state %d: total=%d GAME=%d non-GAME=%d" % (st, tot, game_n, nongame))
    # Per-rep GAME counts (no state)
    for rep in ('spheres', 'sticks', 'cartoon', 'ribbon'):
        n = cmd.count_atoms("%s and segi GAME and rep %s" % (obj, rep))
        if n:
            print("  rep %s: GAME=%d" % (rep, n))

snap("after fetch")

# --- Step 1: insert sphere only ---
extent = cmd.get_extent(obj)
sp = generators.generate_sphere_positions(extent, 1, seed=42)[0]
gc = game.GameController(obj)
gc.start([(sp, 'spheres')])
snap("after sphere")
gc.cleanup()
snap("after sphere cleanup")

# --- Step 2: insert stick only ---
nbr = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append(ID)", space={'stored': nbr})
lo = generators.generate_line_stick_offsets(1, seed=42)[0]
gc = game.GameController(obj)
gc.start([((lo, nbr[0]), 'sticks')])
snap("after stick")
gc.cleanup()
snap("after stick cleanup")

# --- Step 3: insert ONE cartoon alt-conf only ---
cas = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append((chain, resv, ID))",
            space={'stored': cas})
cbc = {}
for ch, ri, cid in cas:
    cbc.setdefault(ch, []).append((ri, cid))
seg = generators.pick_segments(cbc, 1)[0]
disp = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)[0]
gc = game.GameController(obj)
gc.start([((seg[0], seg[1], seg[2], disp), 'cartoon')])
snap("after 1 cartoon alt-conf (target_state=0)")
gc.cleanup()
snap("after 1 cartoon cleanup")

# --- Step 4: insert TWO cartoon alt-conf (to trigger state 2 + all_states) ---
segs = generators.pick_segments(cbc, 2)
disps = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
gc = game.GameController(obj)
gc.start([((segs[0][0], segs[0][1], segs[0][2], disps[0]), 'cartoon'),
          ((segs[1][0], segs[1][1], segs[1][2], disps[1]), 'cartoon')])
snap("after 2 cartoon alt-conf (state 2 created)")
gc.cleanup()
snap("after 2 cartoon cleanup")

# --- Step 5: THE MIXED-REP CASE (sphere, stick, cartoon, ribbon) ---
# Mirror smoke-I order: sphere, stick BEFORE alt-conf (Pitfall 7)
sp5 = generators.generate_sphere_positions(extent, 1, seed=42)[0]
nbr5 = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append(ID)", space={'stored': nbr5})
lo5 = generators.generate_line_stick_offsets(1, seed=42)[0]
segs5 = generators.pick_segments(cbc, 2)
disps5 = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
gc = game.GameController(obj)
gc.start([
    (sp5, 'spheres'),
    ((lo5, nbr5[0]), 'sticks'),
    ((segs5[0][0], segs5[0][1], segs5[0][2], disps5[0]), 'cartoon'),
    ((segs5[1][0], segs5[1][1], segs5[1][2], disps5[1]), 'ribbon'),
])
snap("after mixed-rep (sphere, stick, cartoon, ribbon)")

# Check: are the original atoms in ANY state?
print("\n--- Original atom state membership ---")
for st in range(1, cmd.count_states(obj) + 1):
    n_orig = cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=st)
    print("  state %d: original polymer atoms=%d" % (st, n_orig))

# Check sphere/stick state membership
for aid_name, aid in [("sphere", gc.registry.all()[0].id), ("stick", gc.registry.all()[1].id)]:
    for st in range(1, cmd.count_states(obj) + 1):
        n = cmd.count_atoms("%s and id %d" % (obj, aid), state=st)
        print("  %s (id %d) in state %d: %d" % (aid_name, aid, st, n))

# KEY: does the original structure render? Zoom to a real CA + ray.
print("\n--- PNG: original structure visibility ---")
import os
OUT = "diag_out"
if not os.path.exists(OUT):
    os.makedirs(OUT)
cmd.set("bg_rgb", "white")
cmd.set("ray_shadows", 0)
# Show cartoon on the REAL polymer (not GAME) to see if original renders
cmd.hide("everything", "all")
cmd.show("cartoon", "%s and polymer and not segi GAME" % obj)
cmd.zoom("%s and polymer and not segi GAME" % obj, buffer=5)
cmd.ray(400, 300)
cmd.png(os.path.join(OUT, "step5_orig_cartoon.png"))
print("  orig cartoon PNG: %d bytes" % os.path.getsize(
    os.path.join(OUT, "step5_orig_cartoon.png")))
# blank
cmd.hide("everything", "all")
cmd.ray(400, 300)
cmd.png(os.path.join(OUT, "step5_blank.png"))
print("  blank PNG: %d bytes" % os.path.getsize(
    os.path.join(OUT, "step5_blank.png")))

# Now show ALL reps as the GUI would (don't re-hide; just show on top)
cmd.show("cartoon", "%s and polymer and not segi GAME" % obj)
for r in gc.registry.all():
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        cmd.show(r.rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))
    else:
        cmd.show(r.rep, "%s and id %d" % (obj, r.id))
# Zoom to each hider
for r in gc.registry.all():
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        zsele = "%s and segi GAME and resi %d and name CA" % (obj, (rv1+rv2)//2)
    else:
        zsele = "%s and id %d" % (obj, r.id)
    cmd.zoom(zsele, buffer=8)
    cmd.ray(400, 300)
    p = os.path.join(OUT, "step5_gui_%s.png" % r.rep)
    cmd.png(p)
    print("  gui-style %s PNG: %d bytes" % (r.rep, os.path.getsize(p)))

gc.cleanup()
snap("after mixed-rep cleanup")

print("\n=== done ===")
