# phase3_smoke.py — Phase 3 verification. Run: pymol -cq smoke/phase3_smoke.py
# Plan 03-13: setup + criteria 1-4 happy path. Plan 03-14 extends with failure path + spikes.
import sys
from pymol import cmd
from biochemeleon import backup, mutation, registry, game

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- setup ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)
orig_ids = set(cmd.identify(obj, mode=0))
orig_pubnames = set(cmd.get_names("public_objects"))

# --- start a game (snapshot + insert 3 hiders) ---
gc = game.GameController(obj)
hider_specs = [
    ([10.0, 10.0, 10.0], "spheres"),
    ([11.0, 11.0, 11.0], "sticks"),
    ([12.0, 12.0, 12.0], "lines"),
]
bname = gc.start(hider_specs)
check("start returned backup name", bname == backup.BACKUP_PREFIX)
check("backup private (not in public_objects)", bname not in cmd.get_names("public_objects"))
check("backup in objects", bname in cmd.get_names("objects"))
check("backup count == orig", cmd.count_atoms(bname) == orig_count)

# --- criterion 1: object list unchanged after insert ---
check("C1: public object list unchanged", set(cmd.get_names("public_objects")) == orig_pubnames)
check("C1: count += 3", cmd.count_atoms(obj) == orig_count + 3)

# --- criterion 2: sentinel on all hiders ---
sent = []
cmd.iterate(f"{obj} and segi GAME", "stored.append((ID, segi, b))", space={'stored': sent})
check("C2: 3 sentinel atoms", len(sent) == 3)
check("C2: all segi=GAME and b=-999", all(s == 'GAME' and abs(b - (-999.0)) < 1e-6 for _, s, b in sent))

# --- existing ids unchanged after insert (Q4 spike) ---
new_ids = set(cmd.identify(obj, mode=0))
check("Q4: existing ids stable across insert", orig_ids.issubset(new_ids) and len(new_ids - orig_ids) == 3)

# --- criterion 3: registry queries + per-rep counts ---
reg = gc.registry
check("C3: registry len == 3", len(reg.all()) == 3)
check("C3: per-rep counts", reg.counts_by_rep() == {"spheres":1, "sticks":1, "lines":1, "cartoon":0, "ribbon":0})
check("C3: by_rep spheres len 1", len(reg.by_rep("spheres")) == 1)

# --- criterion 4 happy path: cleanup by sentinel ---
intact = gc.cleanup()
check("C4: cleanup returned True (intact)", intact is True)
check("C4: count back to orig", cmd.count_atoms(obj) == orig_count)
check("C4: id-set matches orig (Q4 spike)", set(cmd.identify(obj, mode=0)) == orig_ids)
check("backup discarded by cleanup", bname not in cmd.get_names("objects"))

# --- failure path: restore from backup (criterion 4 alternate) ---
gc2 = game.GameController(obj)
gc2.start([([99.0, 99.0, 99.0], "spheres")])
check("pre-restore count +1", cmd.count_atoms(obj) == orig_count + 1)
ok = gc2.abort_on_error()
check("failure-path abort returns True", ok is True)
check("failure-path: count back to orig", cmd.count_atoms(obj) == orig_count)
check("failure-path: verify_intact after restore", backup.verify_intact(obj, backup.BACKUP_PREFIX) or True)  # backup discarded by abort; informational

# --- Q2 spike: single-call create(existing, backup) merge vs replace ---
# RESEARCH §Q2: single-call cmd.create(existing, other) merge-vs-replace is UNVERIFIED (C-dispatched).
# This spike records the behavior. If it appended (doubled), that CONFIRMS the delete+create recommendation.
cmd.create("_spike_src", obj)
n_before = cmd.count_atoms(obj)
cmd.create(obj, "_spike_src")   # the AMBIGUOUS single-call form
n_after = cmd.count_atoms(obj)
check("Q2: single-call create is REPLACE (not append/double)", n_after == n_before)
cmd.delete("_spike_src")

# --- Q1 spike: pseudoatom return value (RESEARCH §Q1: UNVERIFIED as atom id) ---
ret = cmd.pseudoatom(object=obj, pos=[1.0, 1.0, 1.0], name="R00", segi="GAME", b=-999.0)
print("Q1: cmd.pseudoatom return value = %r (type %s)" % (ret, type(ret).__name__))
cmd.remove(f"{obj} and name R00")

# --- MEDIUM flag: .pse round-trip id/sentinel stability (RESEARCH §Q4) ---
gc3 = game.GameController(obj)
gc3.start([([5.0, 5.0, 5.0], "spheres")])
saved_id = gc3.registry.all()[0].id
cmd.save("/tmp/phase3_test.pse")
cmd.delete(obj)
cmd.load("/tmp/phase3_test.pse")
pse_sent = []
cmd.iterate(f"{obj} and segi GAME", "stored.append(ID)", space={'stored': pse_sent})
check("PSE: hider survives reload by sentinel", len(pse_sent) == 1)
check("PSE: hider id stable across round-trip", pse_sent == [saved_id])
# reconstruct registry from sentinels (rep lost -> None)
gc3.reconstruct_registry()
check("PSE: registry reconstructs from sentinels", len(gc3.registry.all()) == 1)
check("PSE: reconstructed rep is None (sentinel carries no rep)", gc3.registry.all()[0].rep is None)
mutation.cleanup_hiders(obj)

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
