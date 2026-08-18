# phase10_smoke.py -- Phase 10 headless smoke. Run: pymol -cq smoke/phase10_smoke.py
# Verifies the cmd-layer debrief show path (DIFF-03) at the cmd layer (pure
# pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot run Qt). The Qt
# dialogs (win + debrief), the 100ms redraw delay, and the cleanup gate are
# deferred to the human-verify checkpoint (Plan 10-09).
#
# Builds a mixed-rep game (2 spheres + 1 stick + 1 cartoon 4-tuple segment --
# mirrors phase4_1_smoke section 2 + phase11_smoke's 4-tuple path) the same
# way __init__._prepare_and_start does: generators.pick_segments for the
# cartoon fragment + generate_middle_displacement for the bump. Marks all
# hiders found, then runs the fragment-aware debrief show loop (the SAME
# logic gui_game._show_all_hiders_for_debrief uses: per rec, skip rep=None,
# fragment by segi GAME and resi rv1-rv2, single-atom by id). Asserts every
# hider is shown in its own rep, and the cartoon fragment's FULL rv1-rv2
# range is shown (NOT just the anchor id).
import sys
from pymol import cmd
from biochemeleon import game, generators, mutation, registry  # noqa: F401 (mutation/registry imported for parity with phase4/phase5/phase11 smokes)

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- 1. SETUP: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig = cmd.count_atoms(obj)

# --- 2. START MIXED-REP: 2 spheres + 1 stick + 1 cartoon 4-tuple segment ---
# Build rep-specific payloads the same way __init__._prepare_and_start does
# (the dispatcher routes each by rep). The cartoon 4-tuple uses
# pick_segments + generate_middle_displacement (Phase 11 single-state path).
extent = cmd.get_extent(obj)
sphere_positions = generators.generate_sphere_positions(extent, 2, seed=42)
nbr_ids = cmd.identify("%s and not segi GAME and name CA" % obj, mode=0)
stick_offset = generators.generate_line_stick_offsets(1, seed=42)[0]
# Cartoon 4-tuple: pick ONE disjoint mid-chain segment + one displacement.
cas = []
cmd.iterate("%s and polymer and name CA" % obj,
            "stored.append((chain, resv, ID))", space={'stored': cas})
cas_by_chain = {}
for ch, ri, cid in cas:
    cas_by_chain.setdefault(ch, []).append((ri, cid))
segments = generators.pick_segments(cas_by_chain, 1)  # 1 cartoon hider
check("setup: 1ubq has a mid-chain segment for cartoon", len(segments) >= 1)
disps = generators.generate_middle_displacement(len(segments))
seg = segments[0]
disp = disps[0]
hider_specs = [(sphere_positions[0], "spheres"),
               (sphere_positions[1], "spheres"),
               ((stick_offset, nbr_ids[0]), "sticks"),
               ((seg[0], seg[1], seg[2], disp), "cartoon")]  # 4-tuple
gc = game.GameController(obj)
gc.start(hider_specs)
gc._start_time = 1234.0   # so win()'s elapsed math works without a real timer
check("start: registry len == 4", len(gc.registry.all()) == 4)
check("start: counts_by_rep == {lines:0, sticks:1, spheres:2, cartoon:1, ribbon:0}",
      gc.registry.counts_by_rep() == {"lines": 0, "sticks": 1, "spheres": 2,
                                       "cartoon": 1, "ribbon": 0})

# --- 3. MARK ALL FOUND (so the debrief show applies to found hiders) ---
for rec in gc.registry.all():
    gc._mark_found(rec.id, rec)
check("mark all: all hiders found", gc._remaining() == 0)
check("mark all: all status == found",
      all(r.status == registry.HIDER_STATUS_FOUND for r in gc.registry.all()))

# --- 4. DEBRIEF SHOW: hide all GAME atoms first, then run the fragment-aware
#     show loop (the SAME logic gui_game._show_all_hiders_for_debrief uses).
cmd.hide("everything", "%s and segi GAME" % obj)
check("hide: no GAME atoms visible in any rep",
      cmd.count_atoms("%s and segi GAME and (rep lines or rep sticks or "
                      "rep spheres or rep cartoon or rep ribbon)" % obj) == 0)
# The fragment-aware debrief show loop (inline from Plan 10-06):
for rec in gc.registry.all():
    if rec.rep is None:
        continue
    if rec.endpoint_resvs is not None:  # cartoon/ribbon fragment
        rv1, rv2 = rec.endpoint_resvs
        cmd.show(rec.rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))
    else:  # single-atom
        cmd.show(rec.rep, "%s and id %d" % (obj, rec.id))

# --- 5. ASSERT per-rep shown (each rep with hiders has visible GAME atoms) ---
check("debrief show: spheres GAME atoms visible in spheres rep",
      cmd.count_atoms("%s and segi GAME and rep spheres" % obj) >= 2)
check("debrief show: sticks GAME atom visible in sticks rep",
      cmd.count_atoms("%s and segi GAME and rep sticks" % obj) >= 1)
check("debrief show: cartoon GAME atoms visible in cartoon rep",
      cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) >= 1)

# --- 6. ASSERT cartoon fragment FULL rv1-rv2 range shown (NOT just anchor id) ---
cartoon_rec = next((r for r in gc.registry.all() if r.rep == "cartoon"), None)
check("debrief show: cartoon rec has endpoint_resvs (4-tuple path)",
      cartoon_rec is not None and cartoon_rec.endpoint_resvs is not None)
if cartoon_rec and cartoon_rec.endpoint_resvs:
    rv1, rv2 = cartoon_rec.endpoint_resvs
    # The full range (endpoints included) should have visible cartoon atoms.
    full_range_shown = cmd.count_atoms(
        "%s and segi GAME and resi %d-%d and rep cartoon" % (obj, rv1, rv2))
    check("debrief show: cartoon full rv1-rv2 range shown (>=3 atoms)",
          full_range_shown >= 3)  # 3-residue segment -> >=3 CA atoms
    # The MIDDLE (rv1+1..rv2-1) specifically must be shown -- a by-id-only
    # show would leave these hidden (the support-residue + displaced bump).
    middle_shown = cmd.count_atoms(
        "%s and segi GAME and resi %d-%d and rep cartoon" % (obj, rv1 + 1, rv2 - 1))
    check("debrief show: cartoon MIDDLE (rv1+1-rv2-1) shown (fragment-aware)",
          middle_shown >= 1)

# --- 7. CLEANUP: debrief highlight was temporary; cleanup restores orig ---
ok = gc.cleanup()
check("cleanup: restore succeeded (verify_intact)", ok)
check("cleanup: atom count back to orig", cmd.count_atoms(obj) == orig)
check("cleanup: no GAME atoms remain",
      cmd.count_atoms("%s and segi GAME" % obj) == 0)

# --- SUMMARY ---
failed = [n for n, ok in RESULTS if not ok]
print("\n=== Phase 10 smoke: %d/%d passed ===" % (
    len(RESULTS) - len(failed), len(RESULTS)))
if failed:
    print("FAILED:")
    for n in failed:
        print("  - " + n)
    sys.exit(1)
print("ALL PASSED")
