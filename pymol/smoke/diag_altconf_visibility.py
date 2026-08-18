# diag_altconf_visibility.py -- Headless diagnostic for the Phase 11
# alt-conf visibility regression (only cartoon hiders render; ribbon/spheres/
# sticks invisible). count_atoms passes (rep IS applied) but visual rendering
# fails -- so this script renders PNGs (like phase5 debug) + prints detailed
# state/rep/alt info to find WHY non-cartoon reps don't render visually.
#
# Run: pymol -cq smoke/diag_altconf_visibility.py
import sys
import os
from pymol import cmd
from biochemeleon import game, mutation, generators

OUT = "diag_out"
obj = "1ubq"

print("=== Phase 11 alt-conf visibility diagnostic ===")

# --- Setup: fetch + collapse (mirror _prepare_and_start) ---
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
orig_count = cmd.count_atoms(obj)
print("orig_count:", orig_count)
print("states after fetch+collapse:", cmd.count_states(obj))

# --- Build mixed-rep hider_specs (mirror GUI per_rep=cartoon+ribbon+spheres+sticks) ---
extent = cmd.get_extent(obj)
sphere_pos = generators.generate_sphere_positions(extent, 1, seed=42)[0]
nbr_ids = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append(ID)",
            space={'stored': nbr_ids})
line_off = generators.generate_line_stick_offsets(1, seed=42)[0]

# Build cas_by_chain for pick_segments
cas = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append((chain, resv, ID))",
            space={'stored': cas})
cas_by_chain = {}
for ch, ri, cid in cas:
    cas_by_chain.setdefault(ch, []).append((ri, cid))
segs = generators.pick_segments(cas_by_chain, 2)  # cartoon + ribbon
disps = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)

# Order: sphere, stick, cartoon, ribbon (smoke-I order -- Pitfall 7: stick
# BEFORE cartoon so iterate_state runs on a clean state; the GUI must use
# this order too since the objective reports NO error).
hider_specs = [
    (sphere_pos, 'spheres'),
    ((line_off, nbr_ids[0]), 'sticks'),
    ((segs[0][0], segs[0][1], segs[0][2], disps[0]), 'cartoon'),
    ((segs[1][0], segs[1][1], segs[1][2], disps[1]), 'ribbon'),
]
print("\nHider specs order:", [r for _, r in hider_specs])

gc = game.GameController(obj)
gc.start(hider_specs)
print("\n--- After start ---")
print("registry len:", len(gc.registry.all()))
print("registry reps:", [(r.rep, r.id, r.is_altconf) for r in gc.registry.all()])
print("count_states:", cmd.count_states(obj))
print("all_states setting:", cmd.get("all_states", obj))

# --- Detailed state/rep info ---
print("\n--- Per-state atom counts ---")
for st in range(1, cmd.count_states(obj) + 1):
    n = cmd.count_atoms(obj, state=st)
    n_game = cmd.count_atoms("%s and segi GAME" % obj, state=st)
    print("  state %d: total=%d GAME=%d" % (st, n, n_game))

print("\n--- Per-rep GAME atom counts (all states) ---")
for rep in ('spheres', 'sticks', 'cartoon', 'ribbon', 'lines'):
    n = cmd.count_atoms("%s and segi GAME and rep %s" % (obj, rep))
    print("  rep %s: GAME atoms=%d" % (rep, n))

print("\n--- Per-rep GAME atom counts PER STATE ---")
for st in range(1, cmd.count_states(obj) + 1):
    print("  state %d:" % st, end="")
    for rep in ('spheres', 'sticks', 'cartoon', 'ribbon'):
        n = cmd.count_atoms("%s and segi GAME and rep %s" % (obj, rep), state=st)
        print("  %s=%d" % (rep, n), end="")
    print()

# --- alt values on GAME atoms ---
alts = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)", space={'stored': alts})
print("\nGAME alt values:", sorted(set(alts)), "(count=%d)" % len(alts))

# --- PNG rendering (the key visual test) ---
if not os.path.exists(OUT):
    os.makedirs(OUT)
cmd.set("bg_rgb", "white")
cmd.set("ray_shadows", 0)
cmd.hide("everything", "all")
# Show the reps that are applied (mirror what the GUI would show)
cmd.show("cartoon", "%s and polymer" % obj)  # base cartoon on real trace
# Re-show GAME atom reps (hide everything wiped them)
for r in gc.registry.all():
    rep = r.rep
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        cmd.show(rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))
    else:
        cmd.show(rep, "%s and id %d" % (obj, r.id))

def render_png(name, sele_to_zoom):
    cmd.zoom(sele_to_zoom, buffer=8)
    cmd.ray(400, 300)
    path = os.path.join(OUT, name)
    cmd.png(path)
    size = os.path.getsize(path)
    print("  PNG %s: %d bytes (zoom %s)" % (name, size, sele_to_zoom))
    return size

print("\n--- PNG rendering (visual test) ---")
# Render each hider zoomed
sizes = {}
for r in gc.registry.all():
    rep = r.rep
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        zsele = "%s and segi GAME and resi %d and name CA" % (obj, (rv1+rv2)//2)
    else:
        zsele = "%s and id %d" % (obj, r.id)
    sizes[rep] = render_png("hider_%s.png" % rep, zsele)

# Render a blank control (hide everything, zoom to a hider location)
cmd.hide("everything", "all")
for r in gc.registry.all():
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        zsele = "%s and segi GAME and resi %d and name CA" % (obj, (rv1+rv2)//2)
    else:
        zsele = "%s and id %d" % (obj, r.id)
    blank = render_png("blank_%s.png" % r.rep, zsele)
    # Compare: if hider PNG == blank PNG, nothing rendered
    if r.rep in sizes:
        diff = sizes[r.rep] - blank
        visible = diff > 200  # threshold from phase5 debug
        print("  -> %s: hider=%d blank=%d diff=%d VISIBLE=%s" % (
            r.rep, sizes[r.rep], blank, diff, visible))

# --- KEY TEST: collapse to single state, do non-cartoon reps render? ---
print("\n--- KEY TEST: does collapsing to single state fix non-cartoon reps? ---")
# Re-show reps after the blank test
cmd.show("cartoon", "%s and polymer" % obj)
for r in gc.registry.all():
    rep = r.rep
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        cmd.show(rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))
    else:
        cmd.show(rep, "%s and id %d" % (obj, r.id))

# Test A: turn OFF all_states (only state 1 renders)
print("Test A: all_states=off (only state 1 renders)")
cmd.set("all_states", "off", obj)
print("  all_states now:", cmd.get("all_states", obj))
for r in gc.registry.all():
    rep = r.rep
    if r.is_altconf:
        rv1, rv2 = r.endpoint_resvs
        zsele = "%s and segi GAME and resi %d and name CA" % (obj, (rv1+rv2)//2)
    else:
        zsele = "%s and id %d" % (obj, r.id)
    render_png("allstates_off_%s.png" % rep, zsele)

# Test B: turn all_states back on, but check current_state
print("\nTest B: all_states=on, check current_state effect")
cmd.set("all_states", "on", obj)
for cs in range(1, cmd.count_states(obj) + 1):
    cmd.set("state", cs)
    print("  current_state=%d" % cs)
    for r in gc.registry.all():
        if not r.is_altconf:
            rep = r.rep
            zsele = "%s and id %d" % (obj, r.id)
            render_png("state%d_%s.png" % (cs, rep), zsele)

# Test C: the smoke-I order (sphere, stick, cartoon, ribbon) -- does order matter?
print("\n--- Test C: smoke-I order (sphere, stick, cartoon, ribbon) ---")
gc.cleanup()
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
# rebuild specs in smoke-I order
cas2 = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append((chain, resv, ID))",
            space={'stored': cas2})
cbc2 = {}
for ch, ri, cid in cas2:
    cbc2.setdefault(ch, []).append((ri, cid))
segs2 = generators.pick_segments(cbc2, 2)
disps2 = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
extent2 = cmd.get_extent(obj)
sp2 = generators.generate_sphere_positions(extent2, 1, seed=42)[0]
nb2 = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append(ID)",
            space={'stored': nb2})
lo2 = generators.generate_line_stick_offsets(1, seed=42)[0]
specs2 = [
    (sp2, 'spheres'),
    ((lo2, nb2[0]), 'sticks'),
    ((segs2[0][0], segs2[0][1], segs2[0][2], disps2[0]), 'cartoon'),
    ((segs2[1][0], segs2[1][1], segs2[1][2], disps2[1]), 'ribbon'),
]
gc2 = game.GameController(obj)
gc2.start(specs2)
print("smoke-I order states:", cmd.count_states(obj))
print("smoke-I order all_states:", cmd.get("all_states", obj))
for rep in ('spheres', 'sticks', 'cartoon', 'ribbon'):
    n = cmd.count_atoms("%s and segi GAME and rep %s" % (obj, rep))
    print("  rep %s: GAME atoms=%d" % (rep, n))
gc2.cleanup()

print("\n=== diagnostic complete ===")
