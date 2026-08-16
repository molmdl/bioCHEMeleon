# phase4_1_smoke.py -- Phase 4.1 headless smoke. Run: pymol -cq smoke/phase4_1_smoke.py
# Verifies the per-rep remaining-hiders READ path (SC3) at the cmd layer (pure
# pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot run Qt). The Qt
# label rendering (format_remaining output on the GameTab label) is the
# human-verify checkpoint (plan Task 3); this smoke tests the DATA source
# (registry.remaining_by_rep, 04.1-01) + the UNCHANGED game.py find paths
# (on_pick / reveal_one / reveal_all) to confirm per-rep HIDDEN counts
# decrement correctly (SC3) and remaining_by_rep differs from counts_by_rep
# after a find.
#
# Builds a mixed-rep game (2 spheres + 1 stick + 1 cartoon = 4 hiders across 3
# reps) the same way phase5_smoke section 4 does -- rep-specific payloads
# (spheres: [x,y,z]; sticks: (offset, neighbor_id); cartoon: (chain, terminus,
# is_c_terminus) 3-tuple routed to the legacy terminal-extension path). A
# [x,y,z] payload only works for spheres; the dispatcher (insert_hider_for_rep)
# routes each spec per rep.
import sys
from pymol import cmd
from biochemeleon import game, generators, mutation, registry  # noqa: F401 (mutation/registry imported for parity with phase4/phase5 smokes)

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- 1. SETUP: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig = cmd.count_atoms(obj)

# --- 2. START MIXED-REP: 4 hiders across 3 reps (2 spheres, 1 stick, 1 cartoon) ---
# Build rep-specific payloads the same way phase5_smoke section 4 does (the
# dispatcher routes each by rep; a [x,y,z] payload only works for spheres).
extent = cmd.get_extent(obj)
sphere_positions = generators.generate_sphere_positions(extent, 2, seed=42)
nbr_ids = cmd.identify("%s and not segi GAME and name CA" % obj, mode=0)
stick_offset = generators.generate_line_stick_offsets(1, seed=42)[0]
cas = []
cmd.iterate("%s and polymer and name CA" % obj,
            "stored.append((chain, resv, ID))", space={'stored': cas})
cas_by_chain = {}
for ch, ri, cid in cas:
    cas_by_chain.setdefault(ch, []).append((ri, cid))
terminals = generators.pick_terminal_residues(cas_by_chain, max_chains=1)
term = terminals[0] if terminals else None
check("setup: 1ubq has a cartoon N-terminus", term is not None)
hider_specs = [(sphere_positions[0], "spheres"),
               (sphere_positions[1], "spheres"),
               ((stick_offset, nbr_ids[0]), "sticks")]
if term:
    hider_specs.append((term, "cartoon"))
gc = game.GameController(obj)
gc.start(hider_specs)
gc._start_time = 1234.0   # so win()'s elapsed math works without a real timer
check("start: registry len == 4", len(gc.registry.all()) == 4)
check("start: remaining_by_rep == {lines:0, sticks:1, spheres:2, cartoon:1, ribbon:0}",
      gc.registry.remaining_by_rep() == {"lines": 0, "sticks": 1, "spheres": 2,
                                         "cartoon": 1, "ribbon": 0})
check("start: sum(remaining_by_rep) == _remaining (SC3 sum contract)",
      sum(gc.registry.remaining_by_rep().values()) == 4 == gc._remaining())
check("start: counts_by_rep == remaining_by_rep (all hidden)",
      gc.registry.counts_by_rep() == {"lines": 0, "sticks": 1, "spheres": 2,
                                     "cartoon": 1, "ribbon": 0})

# --- 3. FIND ONE SPHERE: on_pick decrements only the sphere count ---
sid = gc.registry.by_rep("spheres")[0].id
gc.on_pick(sid)
check("find sphere: remaining_by_rep[spheres] == 1 (decremented from 2)",
      gc.registry.remaining_by_rep()["spheres"] == 1)
check("find sphere: remaining_by_rep[sticks] == 1 (unchanged)",
      gc.registry.remaining_by_rep()["sticks"] == 1)
check("find sphere: remaining_by_rep[cartoon] == 1 (unchanged)",
      gc.registry.remaining_by_rep()["cartoon"] == 1)
check("find sphere: sum == 3 == _remaining",
      sum(gc.registry.remaining_by_rep().values()) == 3 == gc._remaining())
check("find sphere: counts_by_rep[spheres] == 2 (still counts the found one)",
      gc.registry.counts_by_rep()["spheres"] == 2)

# --- 4. REVEAL_ONE: exactly one rep's hidden count drops by 1 ---
before = gc.registry.remaining_by_rep()
gc.reveal_one()
after = gc.registry.remaining_by_rep()
deltas = {rep: before[rep] - after[rep]
          for rep in ("lines", "sticks", "spheres", "cartoon", "ribbon")}
check("reveal_one: sum == 2 == _remaining (one more found)",
      sum(after.values()) == 2 == gc._remaining())
check("reveal_one: exactly one rep dropped by 1 (the revealed hider's rep)",
      list(deltas.values()).count(1) == 1 and list(deltas.values()).count(0) == 4)

# --- 5. REVEAL_ALL: all hidden -> remaining_by_rep all zeros, counts_by_rep unchanged ---
gc.reveal_all()
check("reveal_all: remaining_by_rep all zeros",
      gc.registry.remaining_by_rep() == {"lines": 0, "sticks": 0, "spheres": 0,
                                         "cartoon": 0, "ribbon": 0})
check("reveal_all: sum == 0 == _remaining",
      sum(gc.registry.remaining_by_rep().values()) == 0 == gc._remaining())
check("reveal_all: counts_by_rep unchanged (counts all records regardless of status)",
      gc.registry.counts_by_rep() == {"lines": 0, "sticks": 1, "spheres": 2,
                                      "cartoon": 1, "ribbon": 0})

# --- 6. CLEANUP: restore from backup, no GAME atoms remain ---
ok = gc.cleanup()
check("cleanup: returned True (verify_intact passed)", ok is True)
check("cleanup: count back to orig", cmd.count_atoms(obj) == orig)
check("cleanup: no GAME atoms remain", cmd.count_atoms("%s and segi GAME" % obj) == 0)

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
