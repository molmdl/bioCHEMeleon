# verify_nucleic_fix.py -- Headless verification of the nucleic-acid hider fix.
# Run: cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\src\run-conda-pymol.bat -cq smoke\verify_nucleic_fix.py"
#
# Tests that ALL 5 GAME_REPS produce hiders on nucleic acid demos (5e54 RNA,
# 1k8p DNA, 2qbz RNA) AND that the protein path (1znf) still works (regression).
import os
import random
from pymol import cmd
from biochemeleon import generators, game, mutation, backup

DATA_DIR = os.path.join("biochemeleon", "data", "demos")
RESULTS = []

def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond)))
    status = "PASS" if cond else "FAIL"
    print("%s: %s%s" % (status, name, ("  " + detail) if detail else ""))

def build_and_start(obj, per_rep):
    """Mimic _prepare_and_start's hider-spec construction (minus the GUI/Qt parts).
    Returns (controller, hider_specs, warnings) or (None, [], [])."""
    mutation.collapse_to_single_state(obj)
    extent = cmd.get_extent(obj)
    hider_specs = []
    warnings = []

    # neighbor_ids: line/stick bond targets (FIXED selector: name CA or name P)
    neighbor_ids = []
    cmd.iterate("%s and not segi GAME and (name CA or name P)" % obj,
                "stored.append(ID)", space={'stored': neighbor_ids})

    # cas_list: cartoon/ribbon segment anchors (FIXED selector)
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
            if n_avail < count:
                warnings.append("%s: requested %d, got %d (neighbor pool=%d)" %
                                (rep, count, n_avail, len(neighbor_ids)))
        elif rep in ('cartoon', 'ribbon'):
            _take = min(count, len(_cartoon_segments) - _cartoon_idx)
            segments = _cartoon_segments[_cartoon_idx:_cartoon_idx + _take]
            disps = _cartoon_disps[_cartoon_idx:_cartoon_idx + _take]
            _cartoon_idx += _take
            for (chain, start_resi, end_resi), disp in zip(segments, disps):
                hider_specs.append(((chain, start_resi, end_resi, disp), rep))
            if _take < count:
                warnings.append("%s: requested %d, got %d (segments=%d)" %
                                (rep, count, _take, len(_cartoon_segments)))
    return hider_specs, warnings, neighbor_ids, cas_by_chain

# ---- Test each demo ----
DEMOS = [
    ("1znf", "protein", {'spheres': 1, 'lines': 1, 'sticks': 1, 'cartoon': 1, 'ribbon': 1}),
    ("5e54", "rna",     {'spheres': 1, 'lines': 1, 'sticks': 1, 'cartoon': 1, 'ribbon': 1}),
    ("1k8p", "dna",     {'spheres': 1, 'lines': 1, 'sticks': 1, 'cartoon': 1, 'ribbon': 1}),
    ("2qbz", "rna",     {'spheres': 1, 'lines': 1, 'sticks': 1, 'cartoon': 1, 'ribbon': 1}),
    ("4wb3", "mixed",   {'spheres': 1, 'lines': 1, 'sticks': 1, 'cartoon': 1, 'ribbon': 1}),
]

print("=" * 70)
print("NUCLEIC ACID HIDER FIX VERIFICATION")
print("=" * 70)

for demo_id, kind, per_rep in DEMOS:
    pdb_path = os.path.join(DATA_DIR, demo_id + ".pdb")
    obj = demo_id
    cmd.delete(obj)
    cmd.delete("_bchm_backup")
    try:
        cmd.load(pdb_path, object=obj, zoom=0)
    except Exception as e:
        print("\n[%s] LOAD FAILED: %s" % (demo_id, e))
        continue

    print("\n--- %s (%s) ---" % (demo_id, kind))
    hider_specs, warnings, neighbor_ids, cas_by_chain = build_and_start(obj, per_rep)

    print("  neighbor_ids pool: %d" % len(neighbor_ids))
    print("  cas_by_chain: %s" % dict((ch, len(v)) for ch, v in cas_by_chain.items()))
    print("  hider_specs: %d total" % len(hider_specs))
    if warnings:
        for w in warnings:
            print("  WARNING: %s" % w)

    # Count specs per rep
    rep_counts = {}
    for payload, rep in hider_specs:
        rep_counts[rep] = rep_counts.get(rep, 0) + 1
    for rep in ['spheres', 'lines', 'sticks', 'cartoon', 'ribbon']:
        print("    %s: %d spec(s)" % (rep, rep_counts.get(rep, 0)))

    # Check: each requested rep should have >=1 hider (no sphere fallback)
    all_reps_ok = all(rep_counts.get(rep, 0) >= per_rep[rep] for rep in per_rep)
    check("%s: all reps produced hiders" % demo_id, all_reps_ok,
          "expected %s, got %s" % (per_rep, rep_counts))

    # Actually start the game and verify insertion
    if hider_specs:
        gc = game.GameController(obj)
        try:
            bname = gc.start(hider_specs)
            n_hiders = len(gc.registry.all())
            check("%s: game.start succeeded" % demo_id, bname is not None)
            check("%s: registry has %d hiders" % (demo_id, len(hider_specs)),
                  n_hiders == len(hider_specs),
                  "expected %d, got %d" % (len(hider_specs), n_hiders))

            # Verify each rep has hiders in the registry
            reg_reps = {}
            for rec in gc.registry.all():
                reg_reps[rec.rep] = reg_reps.get(rec.rep, 0) + 1
            for rep in per_rep:
                check("%s: registry has %s hider(s)" % (demo_id, rep),
                      reg_reps.get(rep, 0) >= 1,
                      "got %d" % reg_reps.get(rep, 0))

            # Verify cleanup restores original atom count
            orig_count = cmd.count_atoms(bname)
            gc.cleanup()
            after_count = cmd.count_atoms(obj)
            check("%s: cleanup restores atom count" % demo_id,
                  after_count == orig_count,
                  "before=%d after=%d" % (orig_count, after_count))
        except Exception as e:
            check("%s: game.start + cleanup" % demo_id, False,
                  "EXCEPTION: %s" % e)
            import traceback
            traceback.print_exc()

print("\n" + "=" * 70)
passed = sum(1 for _, ok in RESULTS if ok)
failed = sum(1 for _, ok in RESULTS if not ok)
print("RESULTS: %d passed, %d failed" % (passed, failed))
print("=" * 70)
