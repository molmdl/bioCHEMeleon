# diag_create_target_state.py -- Test whether target_state=1 (explicit state 1)
# MERGES tmp into state 1 (preserving existing coords) vs target_state=0
# (C-level -1) which REPLACES state 1. This is the root-cause fix test.
#
# Run: pymol -cq smoke/diag_create_target_state.py
from pymol import cmd

obj = "1ubq"
print("=== cmd.create target_state test ===")

cmd.fetch(obj, async_=0)
print("after fetch: states=%d count=%d" % (cmd.count_states(obj), cmd.count_atoms(obj)))
print("state 1 count:", cmd.count_atoms(obj, state=1))

# Make a backup to source from
cmd.create("_bak", obj)
print("backup state 1 count:", cmd.count_atoms("_bak", state=1))

# Create a tmp segment (backbone only, 3 residues mid-chain)
tmp = "_test_tmp"
cmd.delete(tmp)
cmd.create(tmp, "%s and chain A and resi 23-25 and backbone" % obj, 1, 1, zoom=0)
print("tmp count:", cmd.count_atoms(tmp), "state1:", cmd.count_atoms(tmp, state=1))
cmd.alter(tmp, "alt='B'; segi='GAME'", space={})

# --- TEST 1: target_state=0 (current Phase 11 behavior) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
print("\n--- TEST 1: target_state=0 (C-level -1) [CURRENT/BROKEN] ---")
print("before: state1 total=%d non-GAME=%d" % (
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1)))
cmd.create(obj, tmp, target_state=0, zoom=0)
print("after:  states=%d state1 total=%d non-GAME=%d GAME=%d" % (
    cmd.count_states(obj),
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1),
    cmd.count_atoms("%s and segi GAME" % obj, state=1)))

# --- TEST 2: target_state=1 (explicit state 1) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
print("\n--- TEST 2: target_state=1 (C-level 0) [PROPOSED FIX] ---")
print("before: state1 total=%d non-GAME=%d" % (
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1)))
cmd.create(obj, tmp, target_state=1, zoom=0)
print("after:  states=%d state1 total=%d non-GAME=%d GAME=%d" % (
    cmd.count_states(obj),
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1),
    cmd.count_atoms("%s and segi GAME" % obj, state=1)))

# --- TEST 3: target_state=1, source_state=1 (explicit both) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
print("\n--- TEST 3: source_state=1, target_state=1 (explicit both) ---")
print("before: state1 total=%d non-GAME=%d" % (
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1)))
cmd.create(obj, tmp, source_state=1, target_state=1, zoom=0)
print("after:  states=%d state1 total=%d non-GAME=%d GAME=%d" % (
    cmd.count_states(obj),
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1),
    cmd.count_atoms("%s and segi GAME" % obj, state=1)))

# --- TEST 4: target_state=1 for 1st, target_state=-1 for 2nd (the multi-hider pattern) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
tmp2 = "_test_tmp2"
cmd.delete(tmp2)
cmd.create(tmp2, "%s and chain A and resi 30-32 and backbone" % obj, 1, 1, zoom=0)
cmd.alter(tmp2, "alt='B'; segi='GAME'", space={})
print("\n--- TEST 4: 1st target_state=1, 2nd target_state=-1 ---")
cmd.create(obj, tmp, target_state=1, zoom=0)
print("after 1st: states=%d state1=%d GAME=%d" % (
    cmd.count_states(obj), cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and segi GAME" % obj, state=1)))
cmd.create(obj, tmp2, target_state=-1, zoom=0)
print("after 2nd: states=%d state1=%d state2=%d" % (
    cmd.count_states(obj),
    cmd.count_atoms(obj, state=1), cmd.count_atoms(obj, state=2)))
print("state1 non-GAME=%d GAME=%d" % (
    cmd.count_atoms("%s and not segi GAME" % obj, state=1),
    cmd.count_atoms("%s and segi GAME" % obj, state=1)))
print("state2 non-GAME=%d GAME=%d" % (
    cmd.count_atoms("%s and not segi GAME" % obj, state=2),
    cmd.count_atoms("%s and segi GAME" % obj, state=2)))

# --- TEST 5: BOTH alt-confs in target_state=1 (same state, disjoint segments) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
print("\n--- TEST 5: BOTH in target_state=1 (same state, disjoint) ---")
cmd.create(obj, tmp, target_state=1, zoom=0)
cmd.create(obj, tmp2, target_state=1, zoom=0)
print("after both: states=%d state1 total=%d non-GAME=%d GAME=%d" % (
    cmd.count_states(obj),
    cmd.count_atoms(obj, state=1),
    cmd.count_atoms("%s and not segi GAME" % obj, state=1),
    cmd.count_atoms("%s and segi GAME" % obj, state=1)))
# Check alt values
alts = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)", space={'stored': alts})
print("GAME alts:", sorted(set(alts)))

cmd.delete("_bak")
cmd.delete(tmp)
cmd.delete(tmp2)
print("\n=== done ===")
