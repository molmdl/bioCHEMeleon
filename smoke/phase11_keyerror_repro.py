# phase11_keyerror_repro.py -- headless demonstration of the Phase 11
# cartoon+ribbon KeyError (root cause + fix verification at the cmd tier).
# Run: pymol -cq smoke/phase11_keyerror_repro.py
#
# Pure pymol.cmd.* (NO Qt) so it runs headlessly via the WSL->Windows bridge.
# _prepare_and_start itself is Qt-coupled (lives on the plugin dialog) so it
# cannot be called headlessly; this script mirrors its TWO patterns at the
# cmd tier to demonstrate the root cause and the fix:
#
#   PART 1 (buggy pattern -- the OLD _prepare_and_start): pick_segments is
#     called INDEPENDENTLY per rep (cartoon=1, ribbon=1). For count=1 it
#     picks the DETERMINISTIC centered window, so both reps pick the SAME
#     segment -> same anchor middle CA id -> registry.register KeyError on
#     the second rep. EXPECT: KeyError "hider ('1ubq', <id>) already registered".
#
#   PART 2 (fixed pattern -- the NEW _prepare_and_start): pick_segments is
#     called ONCE for the combined cartoon+ribbon count (globally disjoint),
#     then split across reps. EXPECT: game starts cleanly, 2 hiders, distinct
#     anchor ids, no KeyError.
#
# Exit 0 = both parts behaved as expected (Part 1 KeyError caught, Part 2
# success). Exit 1 = unexpected behavior in either part.
import sys

from pymol import cmd
from biochemeleon import game, mutation, generators

obj = "1ubq"


def build_cas_by_chain():
    cas = []
    cmd.iterate("%s and polymer and name CA" % obj,
                "stored.append((chain, resv, ID))", space={'stored': cas})
    d = {}
    for ch, ri, cid in cas:
        d.setdefault(ch, []).append((ri, cid))
    return d


def _fresh():
    cmd.delete(obj)
    cmd.fetch(obj, async_=0)
    mutation.collapse_to_single_state(obj)
    return build_cas_by_chain()


# ---- PART 1: buggy per-rep independent pick_segments (reproduces KeyError) ----
print("=" * 60)
print("PART 1: buggy per-rep independent pick_segments (OLD _prepare_and_start)")
print("=" * 60)
cas1 = _fresh()
cartoon_segs = generators.pick_segments(cas1, 1)   # centered window (deterministic)
ribbon_segs = generators.pick_segments(cas1, 1)    # SAME centered window
print("cartoon_segs = %r" % (cartoon_segs,))
print("ribbon_segs  = %r" % (ribbon_segs,))
print("identical segment across reps: %s" % (cartoon_segs == ribbon_segs,))
disps1 = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
hider_specs1 = [
    ((cartoon_segs[0][0], cartoon_segs[0][1], cartoon_segs[0][2], disps1[0]), 'cartoon'),
    ((ribbon_segs[0][0], ribbon_segs[0][1], ribbon_segs[0][2], disps1[1]), 'ribbon'),
]
gc1 = game.GameController(obj)
part1_ok = False
try:
    gc1.start(hider_specs1)
    print("PART 1 RESULT: NO KeyError (UNEXPECTED -- bug should reproduce)")
except KeyError as exc:
    print("PART 1 RESULT: BUG REPRODUCED KeyError: %r" % (exc,))
    part1_ok = True  # expected
    try:
        if gc1._started:
            gc1.cleanup()
    except Exception:
        pass

# ---- PART 2: fixed single global pick_segments (no KeyError) ----
print("\n" + "=" * 60)
print("PART 2: fixed single global pick_segments (NEW _prepare_and_start)")
print("=" * 60)
cas2 = _fresh()
# ONE call for combined cartoon+ribbon count, then split across reps.
segs2 = generators.pick_segments(cas2, 2)   # globally disjoint
print("global pick_segments(cas, 2) = %r" % (segs2,))
disps2 = generators.generate_middle_displacement(len(segs2), seed=42, magnitude=1.5)
hider_specs2 = [
    ((segs2[0][0], segs2[0][1], segs2[0][2], disps2[0]), 'cartoon'),
    ((segs2[1][0], segs2[1][1], segs2[1][2], disps2[1]), 'ribbon'),
]
print("hider_specs (cartoon uses seg[0], ribbon uses seg[1]) = %r" % (hider_specs2,))
gc2 = game.GameController(obj)
part2_ok = False
try:
    gc2.start(hider_specs2)
    n = len(gc2.registry.all())
    counts = gc2.registry.counts_by_rep()
    ids2 = [r.id for r in gc2.registry.all()]
    distinct = len(set(ids2)) == len(ids2)
    print("PART 2 RESULT: no KeyError. registry len=%d counts=%r ids=%r distinct=%s"
          % (n, counts, ids2, distinct))
    if n == 2 and counts.get('cartoon') == 1 and counts.get('ribbon') == 1 and distinct:
        part2_ok = True
    gc2.cleanup()
except KeyError as exc:
    print("PART 2 RESULT: KeyError (UNEXPECTED -- fix should prevent): %r" % (exc,))

# ---- SUMMARY ----
print("\n" + "=" * 60)
print("SUMMARY: Part 1 (buggy reproduces KeyError) = %s ; Part 2 (fixed works) = %s"
      % ("PASS" if part1_ok else "FAIL", "PASS" if part2_ok else "FAIL"))
print("=" * 60)
sys.exit(0 if (part1_ok and part2_ok) else 1)
