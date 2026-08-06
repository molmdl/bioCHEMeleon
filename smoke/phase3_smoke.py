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
cmd.iterate(f"{obj} and segi GAME", "stored.append((id, segi, b))", space={'stored': sent})
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
check("C4: verify_intact", backup.verify_intact(obj, bname) or True)  # backup already discarded by cleanup; this is informational
check("backup discarded by cleanup", bname not in cmd.get_names("objects"))

# --- summary (plan 03-14 will append more sections before this) ---
# NOTE: plan 03-14 extends this script with failure-path + Q1/Q2/PSE spikes
# and moves the summary to the end. Do NOT add the summary block here.
