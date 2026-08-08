# phase5_smoke.py -- Phase 5 headless smoke. Run: pymol -cq smoke/phase5_smoke.py
# Verifies line/stick + cartoon + mixed-rep hider insertion at the cmd-coupled
# runtime tier (pure pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot
# run Qt). The visual BLEND is the human-verify checkpoint (plan 05-05) -- this
# smoke proves the MECHANISM (atoms insert, reps show, sentinel set, cleanup
# restores); the human proves the BLEND.
#
# Covers 05-RESEARCH.md sec 6 Q21 smoke checks + 3 MEDIUM open risks:
#   - Open Risk 1: alter segi='GAME' on an attached residue does NOT break the
#     polymer selector (count_atoms("... and segi GAME and polymer") > 0).
#   - Open Risk 2: cmd.attach_amino_acid works with a NAMED selection (no pk1).
#   - Open Risk 3: hider C-alpha color == neighbor C-alpha color (blend).
# If a MEDIUM risk fails, iterate the fallback in mutation.py + re-run (mirrors
# the Phase 3 03-15 smoke-debug pattern). The optional iterate_state spike
# (Open Risk 6, LOW) may pass or log a deferral without failing the run.
import sys
from pymol import cmd
from biochemeleon import generators, game, mutation, registry  # noqa: F401 (registry imported for parity with phase4 smoke)

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- 1. setup: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)

# --- 2. LINE/STICK hider via insert_line_stick_hider ---
nbr_ids = cmd.identify("%s and not segi GAME and name CA" % obj, mode=0)
neighbor_id = nbr_ids[0]
offset = [0.5, 0.5, 0.5]  # fixed small offset for reproducibility
stick_id = mutation.insert_line_stick_hider(obj, offset=offset,
                                            neighbor_id=neighbor_id,
                                            handle="S001", rep="sticks")
check("stick: returns int id", isinstance(stick_id, int))
check("stick: GAME atoms in rep sticks",
      cmd.count_atoms("%s and segi GAME and rep sticks" % obj) > 0)
# sentinel: segi=GAME, b=-999 (iterate exposes segi/b lowercase; ID uppercase)
sent = []
cmd.iterate("%s and id %d" % (obj, stick_id), "stored.append((segi, b))",
            space={'stored': sent})  # hygienic space= dict (AGENTS.md; RESEARCH sec Q3)
check("stick: sentinel set",
      bool(sent) and sent[0][0] == 'GAME' and abs(sent[0][1] - (-999.0)) < 1e-6)
# bonded to neighbor: the hider is in the "neighbor of neighbor_id" set
# (neighbor sele = atoms bonded to sele; editing.py selector keyword).
# Wrapped in explicit parens so `neighbor` applies only to (obj and id
# neighbor_id) before the `and id stick_id` intersect (PyMOL selector
# precedence: `neighbor A and B` can parse as `neighbor (A and B)`, which
# would be empty -- the outer parens force the intended grouping).
nbr_of_neighbor = cmd.count_atoms("neighbor (%s and id %d)" % (obj, neighbor_id))
nbr_of_hider = cmd.count_atoms("neighbor (%s and id %d)" % (obj, stick_id))
print("diag: neighbor(neighbor_id=%d)=%r neighbor(hider_id=%d)=%r" %
      (neighbor_id, nbr_of_neighbor, stick_id, nbr_of_hider))
check("stick: hider bonded to neighbor",
      cmd.count_atoms("(neighbor (%s and id %d)) and id %d" % (obj, neighbor_id, stick_id)) > 0)
# Open Risk 3 (line/stick): color matches neighbor (insert copies neighbor color)
nbr_col = []
cmd.iterate("%s and id %d" % (obj, neighbor_id), "stored.append(color)",
            space={'stored': nbr_col})
hdr_col = []
cmd.iterate("%s and id %d" % (obj, stick_id), "stored.append(color)",
            space={'stored': hdr_col})
check("stick: color matches neighbor (Open Risk 3)",
      bool(nbr_col) and bool(hdr_col) and nbr_col[0] == hdr_col[0])
print("diag: stick_id=%r neighbor_id=%r nbr_col=%r hdr_col=%r" %
      (stick_id, neighbor_id, nbr_col, hdr_col))

# --- 3. CARTOON hider via insert_cartoon_hider ---
# find the N-terminus: longest chain's min resi (RESEARCH sec Q8 Step 1).
# MVP uses the N-terminus (NOT the C-terminus): the C-terminus carbonyl C
# carries an OXT (terminal oxygen) in 1ubq which saturates the C valence and
# makes the residue-attach primitive fail with "no target attachment vector
# found" (ObjectMolecule.cpp:3357). The N-terminus N has a free valence and
# extends cleanly with no atom removal (verified -- verify_intact passes).
# resv is the numeric residue value (int; symbol table editing.py:1444-1449) --
# NOT resi (a string that may carry insertion codes) and NOT int(resi) (the
# hygienic space= dict does not expose Python builtins, so int() would raise
# NameError; resv sidesteps that entirely).
cas_list = []
cmd.iterate("%s and polymer and name CA" % obj,
            "stored.append((chain, resv, ID))", space={'stored': cas_list})
check("cartoon: 1ubq has polymer CA", len(cas_list) > 0)
cas_by_chain = {}
for ch, ri, cid in cas_list:
    cas_by_chain.setdefault(ch, []).append((ri, cid))
chain = max(cas_by_chain, key=lambda c: len(cas_by_chain[c]))
term_resi = min(r[0] for r in cas_by_chain[chain])  # N-terminus (min resi)
ca_id = mutation.insert_cartoon_hider(obj, chain=chain, terminus_resi=term_resi,
                                       is_c_terminus=False, handle="C001")
check("cartoon: returns C-alpha int id", isinstance(ca_id, int))
# Open Risk 2: attach_amino_acid worked with a NAMED selection (no pk1 needed)
check("cartoon: attach_amino_acid worked with named sele (Open Risk 2)",
      ca_id > 0 and cmd.count_atoms("%s and segi GAME and name CA" % obj) > 0)
# Open Risk 1: alter segi='GAME' did NOT break the polymer selector
check("cartoon: GAME atoms in polymer (Open Risk 1)",
      cmd.count_atoms("%s and segi GAME and polymer" % obj) > 0)
# corrected count_atoms check (NOT the roadmap's wrong cmd.count('cartoon',...);
# mutagenesis.py:570 pattern: count_atoms("... and name CA and rep cartoon"))
check("cartoon: GAME C-alpha in rep cartoon",
      cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj) > 0)
check("cartoon: residue has N-C-C-alpha backbone",
      cmd.count_atoms("%s and segi GAME and (name N or name CA or name C)" % obj) >= 3)
# sentinel on the new residue's C-alpha
csent = []
cmd.iterate("%s and id %d" % (obj, ca_id), "stored.append((segi, b))",
            space={'stored': csent})
check("cartoon: sentinel set",
      bool(csent) and csent[0][0] == 'GAME' and abs(csent[0][1] - (-999.0)) < 1e-6)
# Open Risk 3 (cartoon): C-alpha color matches neighbor (the ORIGINAL terminal
# residue's C-alpha, NOT the new residue -- the neighbor is at resi term_resi)
nbr_ccol = []
cmd.iterate("%s and chain %s and resi %d and name CA" % (obj, chain, term_resi),
            "stored.append(color)", space={'stored': nbr_ccol})
hdr_ccol = []
cmd.iterate("%s and id %d" % (obj, ca_id), "stored.append(color)",
            space={'stored': hdr_ccol})
check("cartoon: C-alpha color matches neighbor (Open Risk 3)",
      bool(nbr_ccol) and bool(hdr_ccol) and nbr_ccol[0] == hdr_ccol[0])
print("diag: ca_id=%r chain=%r N-term_resi=%r nbr_ccol=%r hdr_ccol=%r polymer_GAME=%r" %
      (ca_id, chain, term_resi, nbr_ccol, hdr_ccol,
       cmd.count_atoms("%s and segi GAME and polymer" % obj)))

# --- 4. MIXED-REP via insert_hider_for_rep + GameController.start ---
# clean up the single-hider tests first (direct mutation, no backup/registry)
removed = mutation.cleanup_hiders(obj)
check("mixed-prep: cleanup_hiders removed single-hider tests", removed > 0)
check("mixed-prep: count back to orig", cmd.count_atoms(obj) == orig_count)
# build a mixed-rep hider_specs list directly (NOT via _on_start -- Qt-coupled;
# the smoke tests the cmd path)
extent = cmd.get_extent(obj)
sphere_pos = generators.generate_sphere_positions(extent, 1, seed=42)[0]
nbr_ids2 = cmd.identify("%s and not segi GAME and name CA" % obj, mode=0)
line_off = generators.generate_line_stick_offsets(1, seed=42)[0]
cas2 = []
cmd.iterate("%s and polymer and name CA" % obj,
            "stored.append((chain, resv, ID))", space={'stored': cas2})
cas_by2 = {}
for ch, ri, cid in cas2:
    cas_by2.setdefault(ch, []).append((ri, cid))
terminals = generators.pick_terminal_residues(cas_by2, max_chains=1)
term = terminals[0] if terminals else None
hider_specs = [(sphere_pos, "spheres"), ((line_off, nbr_ids2[0]), "sticks")]
if term:
    hider_specs.append((term, "cartoon"))
gc = game.GameController(obj)
gc.start(hider_specs)
check("mixed: start succeeded (backup returned)", gc._backup_name is not None)
check("mixed: registry len == len(hider_specs)",
      len(gc.registry.all()) == len(hider_specs))
check("mixed: counts_by_rep has each rep",
      all(gc.registry.counts_by_rep().get(rep, 0) >= 1 for _, rep in hider_specs))
check("mixed: GAME atoms in rep spheres",
      cmd.count_atoms("%s and segi GAME and rep spheres" % obj) > 0)
check("mixed: GAME atoms in rep sticks",
      cmd.count_atoms("%s and segi GAME and rep sticks" % obj) > 0)
if term:
    check("mixed: GAME atoms in rep cartoon",
          cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) > 0)

# --- 5. CLEANUP safety (sentinel remove + verify_intact + discard) ---
intact = gc.cleanup()
check("cleanup: returned True", intact is True)
check("cleanup: count back to orig", cmd.count_atoms(obj) == orig_count)
check("cleanup: no GAME atoms remain", cmd.count_atoms("%s and segi GAME" % obj) == 0)

# --- 6. (optional spike) iterate_state exposes elem/color? (Open Risk 6 LOW) ---
# insert_line_stick_hider reads (x,y,z,elem,color) via ONE iterate_state call.
# If elem/color come back None at runtime, the inserter would need to split into
# iterate_state (coords) + iterate (elem/color). Section 2 passing already
# implies iterate_state exposes elem/color; this spike confirms + documents.
# A FAIL here is acceptable (informational, not a run failure).
try:
    spike = []
    cmd.iterate_state(1, "%s and id %d" % (obj, nbr_ids2[0]),
                      "stored.append((elem, color))", space={'stored': spike})
    ok_spike = (bool(spike) and spike[0][0] is not None
                and spike[0][1] is not None)
    check("spike: iterate_state exposes elem+color (Open Risk 6)", ok_spike)
    if not ok_spike:
        print("spike: iterate_state elem/color = %r (may need split inserter)" %
              (spike,))
except Exception as exc:
    print("spike: iterate_state(elem,color) raised: %r" % (exc,))
    check("spike: iterate_state elem/color skipped (informational)", True)

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
