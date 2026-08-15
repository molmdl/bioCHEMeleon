# verify_nucleic_render.py -- Verify cartoon/ribbon reps actually RENDER on
# nucleic-acid hider segments (not just that atoms are inserted).
# Run: cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\src\run-conda-pymol.bat -cq smoke\verify_nucleic_render.py"
import os
import random
from pymol import cmd
from biochemeleon import generators, game, mutation

DATA_DIR = os.path.join("biochemeleon", "data", "demos")
RESULTS = []

def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond)))
    print("%s: %s%s" % ("PASS" if cond else "FAIL", name, ("  " + detail) if detail else ""))

def build_specs(obj, per_rep):
    """Replicate _prepare_and_start hider-spec construction."""
    extent = cmd.get_extent(obj)
    hider_specs = []
    neighbor_ids = []
    cmd.iterate("%s and not segi GAME and (name CA or name P)" % obj,
                "stored.append(ID)", space={'stored': neighbor_ids})
    cas_list = []
    cmd.iterate("%s and polymer and (name CA or name P)" % obj,
                "stored.append((chain, resv, ID))",
                space={'stored': cas_list})
    cas_by_chain = {}
    for chain, resi, ca_id in cas_list:
        cas_by_chain.setdefault(chain, []).append((resi, ca_id))
    _cartoon_reps = [r for r in per_rep if r in ('cartoon', 'ribbon')]
    _cartoon_total = sum(per_rep[r] for r in _cartoon_reps)
    _cartoon_segments = (generators.pick_segments(cas_by_chain, _cartoon_total)
                         if _cartoon_total else [])
    _cartoon_disps = generators.generate_middle_displacement(len(_cartoon_segments))
    _cartoon_idx = 0
    _rng = random.Random()
    for rep, count in per_rep.items():
        if rep == 'spheres':
            positions = generators.generate_sphere_positions(extent, count)
            hider_specs += [(p, 'spheres') for p in positions]
        elif rep in ('lines', 'sticks'):
            offsets = generators.generate_line_stick_offsets(count)
            n_avail = min(count, len(neighbor_ids))
            chosen = _rng.sample(neighbor_ids, n_avail) if neighbor_ids else []
            for off, nbr_id in zip(offsets, chosen):
                hider_specs.append(((off, nbr_id), rep))
        elif rep in ('cartoon', 'ribbon'):
            _take = min(count, len(_cartoon_segments) - _cartoon_idx)
            segments = _cartoon_segments[_cartoon_idx:_cartoon_idx + _take]
            disps = _cartoon_disps[_cartoon_idx:_cartoon_idx + _take]
            _cartoon_idx += _take
            for (chain, start_resi, end_resi), disp in zip(segments, disps):
                hider_specs.append(((chain, start_resi, end_resi, disp), rep))
    return hider_specs

print("=" * 70)
print("NUCLEIC ACID CARTOON/RIBBON RENDER VERIFICATION")
print("=" * 70)

for demo_id, kind in [("1znf", "protein"), ("5e54", "rna"), ("1k8p", "dna"), ("2qbz", "rna")]:
    obj = demo_id
    cmd.delete(obj)
    cmd.delete("_bchm_backup")
    cmd.load(os.path.join(DATA_DIR, demo_id + ".pdb"), object=obj, zoom=0)
    mutation.collapse_to_single_state(obj)

    # Show the whole object as cartoon first (so the molecule has a rep context)
    cmd.show("cartoon", obj)
    cartoon_before = cmd.count_atoms("%s and rep cartoon" % obj)

    # Build specs: 1 cartoon + 1 ribbon (the critical reps)
    per_rep = {'cartoon': 1, 'ribbon': 1}
    specs = build_specs(obj, per_rep)
    print("\n--- %s (%s) ---" % (demo_id, kind))
    print("  cartoon_before (whole obj): %d atoms in rep cartoon" % cartoon_before)

    gc = game.GameController(obj)
    try:
        gc.start(specs)
        # Count GAME atoms shown in each rep
        game_cartoon = cmd.count_atoms("%s and segi GAME and rep cartoon" % obj)
        game_ribbon = cmd.count_atoms("%s and segi GAME and rep ribbon" % obj)
        game_total = cmd.count_atoms("%s and segi GAME" % obj)
        print("  GAME atoms total: %d" % game_total)
        print("  GAME atoms in rep cartoon: %d" % game_cartoon)
        print("  GAME atoms in rep ribbon: %d" % game_ribbon)

        check("%s: cartoon renders on GAME segment" % demo_id, game_cartoon > 0,
              "%d atoms" % game_cartoon)
        check("%s: ribbon renders on GAME segment" % demo_id, game_ribbon > 0,
              "%d atoms" % game_ribbon)

        # Also verify the hider atoms exist on chain H
        chain_h = cmd.count_atoms("%s and chain H and segi GAME" % obj)
        print("  chain H GAME atoms: %d" % chain_h)
        check("%s: chain-H GAME fragment exists" % demo_id, chain_h > 0)

        gc.cleanup()
    except Exception as e:
        check("%s: render test" % demo_id, False, "EXCEPTION: %s" % e)
        import traceback
        traceback.print_exc()

print("\n" + "=" * 70)
passed = sum(1 for _, ok in RESULTS if ok)
failed = sum(1 for _, ok in RESULTS if not ok)
print("RESULTS: %d passed, %d failed" % (passed, failed))
print("=" * 70)
