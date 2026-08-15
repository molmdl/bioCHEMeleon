# diag_render_question.py -- Phase 11 refactor: settle the cartoon/ribbon
# insertion mechanism. The user wants cartoon/ribbon hiders to follow the
# sphere/stick single-state pattern (cmd.pseudoatom + cmd.show), differing
# ONLY in placement criteria. The docstring of insert_cartoon_hider claims a
# lone pseudoatom is INVISIBLE for cartoon (needs >=2 consecutive C-alphas).
# This probe VERIFY that headlessly and test candidate single-state designs:
#   T1: 1 CA pseudoatom shown as cartoon -> render?
#   T2: 2 CA pseudoatoms (consecutive resi, same chain, NO bond) -> render?
#   T3: 2 CA pseudoatoms + CA-CA bond -> render?
#   T4: 3 CA pseudoatoms (consecutive resi, same chain) -> render?
#   T5: full backbone fragment via pseudoatoms (N,CA,C,O x3, bonded) -> render?
#   T6: copy real 3-residue backbone from 1ubq to NEW temp object (single-state)
#       + show cartoon -> render? (real-geometry baseline)
#   T7: union-create merge of a NEW-chain fragment (alt='', chain H, segi GAME)
#       into the live 1ubq state 1 -> originals preserved + single-state +
#       cartoon renders on the GAME fragment? (candidate design B)
#   T8: pseudoatom fragment as a NEW CHAIN (chain H, resi 9001-9003, N/CA/C/O)
#       bonded as peptide, shown as cartoon -> render? (candidate design A)
# Pure pymol.cmd.* (no Qt, no biochemeleon import) -- WSL headless runnable.
import os
import sys
from pymol import cmd

obj = "1ubq"
PNG = "diag_render.png"
results = []


def png_size():
    cmd.png(PNG)
    sz = os.path.getsize(PNG) if os.path.exists(PNG) else 0
    return sz


def note(name, **kw):
    kw["name"] = name
    results.append(kw)
    print("[%(name)s] states=%(states)s polymer=%(polymer)s rep_cartoon=%(rep)s "
          "png=%(png)s (blank=%(blank)s full=%(full)s rendered=%(rendered)s)" % kw)


def fresh(label):
    """Fresh fetch + collapse + hide everything; return blank+full baseline."""
    cmd.delete(obj)
    cmd.fetch(obj, async_=0)
    # collapse multi-state (1ubq is single-state; no-op)
    if cmd.count_states(obj) > 1:
        tmp = "_d_single"
        cmd.delete(tmp)
        cmd.create(tmp, obj, 1, 1)
        cmd.delete(obj)
        cmd.create(obj, tmp)
        cmd.delete(tmp)
    cmd.hide("everything", obj)
    blank = png_size()
    cmd.show("cartoon", obj)
    full = png_size()
    cmd.hide("everything", obj)
    print("=== %s : blank=%d full=%d ===" % (label, blank, full))
    return blank, full


def rendered(png, blank, full):
    # Rendered if PNG meaningfully larger than blank (cartoon tube draws pixels).
    # Use a 30% margin over blank to avoid anti-alias noise. Full is the ceiling.
    return png > int(blank * 1.3) + 50


# ---- T1: single CA pseudoatom ----
blank, full = fresh("T1")
cmd.pseudoatom(obj, pos=[10.0, 10.0, 10.0], name="CA", chain="A", resi="999",
                resn="GLY", segi="TST", hetatm=1)
cmd.show("cartoon", "%s and segi TST" % obj)  # ONLY the pseudoatom, NOT real CAs
cmd.zoom("%s and segi TST" % obj)
poly = cmd.count_atoms("%s and polymer and segi TST" % obj)
rep = cmd.count_atoms("%s and segi TST and rep cartoon" % obj)
png = png_size()
note("T1 1CA pseudoatom(iso)", states=cmd.count_states(obj), polymer=poly, rep=rep,
     png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

# ---- T2: 2 CA pseudoatoms, consecutive resi, same chain, NO bond ----
blank, full = fresh("T2")
cmd.pseudoatom(obj, pos=[10.0, 10.0, 10.0], name="CA", chain="A", resi="998",
                resn="GLY", segi="TST", hetatm=1)
cmd.pseudoatom(obj, pos=[11.0, 10.0, 10.0], name="CA", chain="A", resi="999",
                resn="GLY", segi="TST", hetatm=1)
cmd.show("cartoon", "%s and segi TST" % obj)
poly = cmd.count_atoms("%s and polymer" % obj)
rep = cmd.count_atoms("%s and segi TST and rep cartoon" % obj)
png = png_size()
note("T2 2CA no-bond", states=cmd.count_states(obj), polymer=poly, rep=rep,
     png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

# ---- T3: 2 CA pseudoatoms + CA-CA bond ----
blank, full = fresh("T3")
cmd.pseudoatom(obj, pos=[10.0, 10.0, 10.0], name="CA", chain="A", resi="998",
                resn="GLY", segi="TST", hetatm=1)
cmd.pseudoatom(obj, pos=[11.0, 10.0, 10.0], name="CA", chain="A", resi="999",
                resn="GLY", segi="TST", hetatm=1)
ids = cmd.identify("%s and segi TST" % obj, mode=0)
if len(ids) == 2:
    cmd.bond("%s and id %d" % (obj, ids[0]), "%s and id %d" % (obj, ids[1]))
cmd.show("cartoon", "%s and segi TST" % obj)
poly = cmd.count_atoms("%s and polymer" % obj)
rep = cmd.count_atoms("%s and segi TST and rep cartoon" % obj)
png = png_size()
note("T3 2CA +bond", states=cmd.count_states(obj), polymer=poly, rep=rep,
     png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

# ---- T4: 3 CA pseudoatoms consecutive resi ----
blank, full = fresh("T4")
for i, x in enumerate([10.0, 11.0, 12.0]):
    cmd.pseudoatom(obj, pos=[x, 10.0, 10.0], name="CA", chain="A",
                   resi=str(998 + i), resn="GLY", segi="TST", hetatm=1)
ids = cmd.identify("%s and segi TST" % obj, mode=0)
# bond consecutive CAs
for a, b in zip(ids, ids[1:]):
    cmd.bond("%s and id %d" % (obj, a), "%s and id %d" % (obj, b))
cmd.show("cartoon", "%s and segi TST" % obj)
poly = cmd.count_atoms("%s and polymer" % obj)
rep = cmd.count_atoms("%s and segi TST and rep cartoon" % obj)
png = png_size()
note("T4 3CA +bonds", states=cmd.count_states(obj), polymer=poly, rep=rep,
     png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

# ---- T5: full backbone fragment via pseudoatoms (N,CA,C,O x3, bonded) ----
blank, full = fresh("T5")
# 3 residues, each N/CA/C/O at plausible coords (rough peptide geometry)
frag = [
    # resi 998
    ("N",  [10.0, 10.0, 10.0]),
    ("CA", [10.8, 10.8, 10.0]),
    ("C",  [11.6, 10.3, 10.0]),
    ("O",  [11.5,  9.2, 10.0]),
    # resi 999
    ("N",  [12.4, 11.0, 10.0]),
    ("CA", [13.2, 10.5, 10.0]),
    ("C",  [14.0, 11.3, 10.0]),
    ("O",  [13.9, 12.4, 10.0]),
    # resi 1000
    ("N",  [14.8, 10.8, 10.0]),
    ("CA", [15.6, 11.6, 10.0]),
    ("C",  [16.4, 11.1, 10.0]),
    ("O",  [16.3, 10.0, 10.0]),
]
for i, (nm, pos) in enumerate(frag):
    resi = 998 + i // 4
    cmd.pseudoatom(obj, pos=pos, name=nm, chain="A", resi=str(resi),
                   resn="GLY", segi="TST", hetatm=1, elem=nm)
# bond within residue + peptide
ids = cmd.identify("%s and segi TST" % obj, mode=0)
# ids in insertion order = frag order. Map (resi,name)->id
lookup = {}
for nid, (nm, _) in zip(ids, frag):
    resi = 998 + (ids.index(nid)) // 4
    lookup[(resi, nm)] = nid
for resi in (998, 999, 1000):
    for a, b in (("N", "CA"), ("CA", "C"), ("C", "O")):
        if (resi, a) in lookup and (resi, b) in lookup:
            cmd.bond("%s and id %d" % (obj, lookup[(resi, a)]),
                     "%s and id %d" % (obj, lookup[(resi, b)]))
# peptide C-N between residues
for resi in (998, 999):
    if (resi, "C") in lookup and (resi + 1, "N") in lookup:
        cmd.bond("%s and id %d" % (obj, lookup[(resi, "C")]),
                 "%s and id %d" % (obj, lookup[(resi + 1, "N")]))
cmd.show("cartoon", "%s and segi TST" % obj)
cmd.zoom("%s and segi TST" % obj)
poly = cmd.count_atoms("%s and polymer" % obj)
rep = cmd.count_atoms("%s and segi TST and rep cartoon" % obj)
png = png_size()
note("T5 pseudo-backbone x3", states=cmd.count_states(obj), polymer=poly, rep=rep,
     png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

# ---- T6: real 3-residue backbone copied to NEW temp object (single-state) ----
# Baseline: real backbone geometry renders cartoon (sanity check).
blank, full = fresh("T6")
tmp = "_d_seg"
cmd.delete(tmp)
# 1ubq chain A resi 10-12 backbone (real geometry)
cmd.create(tmp, "%s and chain A and resi 10-12 and backbone" % obj, 1, 1, zoom=0)
cmd.hide("everything", tmp)
cmd.show("cartoon", tmp)
poly = cmd.count_atoms("%s and polymer" % tmp)
rep = cmd.count_atoms("%s and rep cartoon" % tmp)
# render the temp object alone (zoom to it)
cmd.zoom(tmp)
png = png_size()
note("T6 real-backbone temp obj", states=cmd.count_states(tmp), polymer=poly,
     rep=rep, png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

# ---- T7: union-create merge of NEW-chain fragment (alt='', chain H) into live obj ----
blank, full = fresh("T7")
orig = cmd.count_atoms(obj)
# copy a real 3-residue backbone to temp, retag as NEW chain H, alt='', segi GAME
cmd.delete(tmp)
cmd.create(tmp, "%s and chain A and resi 10-12 and backbone" % obj, 1, 1, zoom=0)
cmd.alter(tmp, "chain='H'; segi='GAME'; alt=''; ss='L'", space={})
# union merge into state 1 (the d445b88 approach, but alt='' + new chain)
comb = "_d_comb"
cmd.delete(comb)
cmd.create(comb, "(%s) or (%s)" % (obj, tmp), 1, 1, zoom=0)
cmd.create(obj, comb, 1, 1, zoom=0)
cmd.delete(comb)
cmd.delete(tmp)
cmd.sort(obj)
# show cartoon ONLY on the GAME fragment
cmd.hide("everything", obj)
cmd.show("cartoon", "%s and segi GAME" % obj)
cmd.zoom("%s and segi GAME" % obj)
poly = cmd.count_atoms("%s and polymer and segi GAME" % obj)
rep = cmd.count_atoms("%s and segi GAME and rep cartoon" % obj)
png = png_size()
# also check originals preserved + single-state
orig_survive = cmd.count_atoms("%s and not segi GAME" % obj, state=1)
note("T7 union-create new-chain", states=cmd.count_states(obj), polymer=poly,
     rep=rep, png=png, blank=blank, full=full, rendered=rendered(png, blank, full))
print("    T7 orig=%d survive(non-GAME state1)=%d single-state=%s" % (
    orig, orig_survive, cmd.count_states(obj) == 1))

# ---- T8: pseudoatom fragment as NEW chain (chain H), peptide-bonded, show cartoon ----
blank, full = fresh("T8")
frag = [
    ("N",  [10.0, 10.0, 10.0]), ("CA", [10.8, 10.8, 10.0]),
    ("C",  [11.6, 10.3, 10.0]), ("O",  [11.5,  9.2, 10.0]),
    ("N",  [12.4, 11.0, 10.0]), ("CA", [13.2, 10.5, 10.0]),
    ("C",  [14.0, 11.3, 10.0]), ("O",  [13.9, 12.4, 10.0]),
    ("N",  [14.8, 10.8, 10.0]), ("CA", [15.6, 11.6, 10.0]),
    ("C",  [16.4, 11.1, 10.0]), ("O",  [16.3, 10.0, 10.0]),
]
for i, (nm, pos) in enumerate(frag):
    resi = 9001 + i // 4
    cmd.pseudoatom(obj, pos=pos, name=nm, chain="H", resi=str(resi),
                   resn="HID", segi="GAME", hetatm=1, elem=nm)
ids = cmd.identify("%s and segi GAME" % obj, mode=0)
lookup = {}
for nid, (nm, _) in zip(ids, frag):
    resi = 9001 + ids.index(nid) // 4
    lookup[(resi, nm)] = nid
for resi in (9001, 9002, 9003):
    for a, b in (("N", "CA"), ("CA", "C"), ("C", "O")):
        if (resi, a) in lookup and (resi, b) in lookup:
            cmd.bond("%s and id %d" % (obj, lookup[(resi, a)]),
                     "%s and id %d" % (obj, lookup[(resi, b)]))
for resi in (9001, 9002):
    if (resi, "C") in lookup and (resi + 1, "N") in lookup:
        cmd.bond("%s and id %d" % (obj, lookup[(resi, "C")]),
                 "%s and id %d" % (obj, lookup[(resi + 1, "N")]))
cmd.hide("everything", obj)
cmd.show("cartoon", "%s and segi GAME" % obj)
cmd.zoom("%s and segi GAME" % obj)
poly = cmd.count_atoms("%s and polymer and segi GAME" % obj)
rep = cmd.count_atoms("%s and segi GAME and rep cartoon" % obj)
png = png_size()
note("T8 pseudo-frag new-chain", states=cmd.count_states(obj), polymer=poly,
     rep=rep, png=png, blank=blank, full=full, rendered=rendered(png, blank, full))

print("\n=== SUMMARY ===")
for r in results:
    flag = "RENDERS" if r["rendered"] else "BLANK"
    print("%-28s polymer=%s rep=%s png=%d -> %s" % (
        r["name"], r["polymer"], r["rep"], r["png"], flag))
sys.exit(0)
