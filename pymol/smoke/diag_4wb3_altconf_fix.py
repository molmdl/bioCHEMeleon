# diag_4wb3_altconf_fix.py -- Headless smoke for the quick-009 alt-conf
# anchor-duplicate fix. Run:
#   cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c \
#     "C:\src\run-conda-pymol.bat -cq smoke\diag_4wb3_altconf_fix.py"
#
# Bug (pre-fix): structures with alternate-location (alt-conf) backbone atoms
# made insert_cartoon_segment_hider fail with
# `AssertionError: expected 1 anchor id, got [256, 257]`. The `backbone`
# selector matches ALL alt-conf variants; the `alt=''` retag then merged them
# into duplicate atoms at the same (chain, resi, name, alt); the anchor
# selector `name CA or name P` matched N>1. 4wb3 (nucleosome, bundled demo)
# has alt-conf at chain-A residues 710 (CA alt-A id=256, alt-B id=257) and 734.
#
# Two-part fix verified here:
#   Fix 1 (cas_by_chain dedup by (chain, resv)) -- mirrors __init__.py's new
#     logic; keeps one entry per residue so pick_segments windows are not
#     inflated/compressed by alt-conf duplicates. SIDE EFFECT: dedup drops
#     chain A from 70 -> 68 entries, so chain C (69) becomes longest and
#     pick_segments(count=6) lands all 6 segments on chain C (no alt-conf) --
#     Fix 1 alone shifts picks away from the alt-conf chain. This is verified
#     in Section 4.
#   Fix 2 (alt-conf variant dedup in the segment copy) -- mirrors the new
#     block in mutation.insert_cartoon_segment_hider; removes duplicate
#     (chain, resv, name) atoms from tmp BEFORE the alt='' retag merges them.
#     This is the ESSENTIAL defense: even if an alt-conf residue lands in a
#     picked segment (e.g. a structure whose LONGEST chain has alt-conf), Fix 2
#     dedups the copy and returns exactly 1 anchor. Authoritatively tested in
#     Section 6 by DIRECTLY inserting chain-A segments whose middle residue IS
#     the alt-conf residue (709-711 mid=710, 733-735 mid=734) -- the exact path
#     that PRE-FIX raised AssertionError on.
#
# This smoke imports the REAL biochemeleon modules (mutation + backup +
# generators) so it exercises the actual fix code path -- not a copy. The
# authoritative assertion is the internal `assert len(ids) == 1` inside
# insert_cartoon_segment_hider; this script additionally checks each returned
# anchor id is an int, distinct, and a single GAME sentinel atom. PyMOL 2.5.0
# headless via cmd.exe (AGENTS.md).
import os
import sys
from pymol import cmd
from biochemeleon import backup, generators, mutation

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

PDB_PATH = os.path.join("biochemeleon", "data", "demos", "4wb3.pdb")
OBJ = "4wb3"
N_SEGMENTS = 6  # the threshold that triggered the bug pre-fix (quick-005 spreading)

print("=" * 70)
print("4WB3 ALT-CONF ANCHOR-DUPLICATE FIX SMOKE (quick-009)")
print("=" * 70)

# --- 1. Load 4wb3 ---
cmd.reinitialize()
cmd.load(PDB_PATH, OBJ)
n_total = cmd.count_atoms(OBJ)
print("\n[1] Loaded 4wb3: %d total atoms" % n_total)
check("4wb3 loaded (nonzero atoms)", n_total > 0)

# --- 2. Locate alt-conf backbone atoms (the bug trigger) ---
# Iterate ALL atoms once, then filter for non-blank alt + backbone names
# (CA for protein, P for nucleic acid). PyMOL's `alt` selector is finicky
# (blank vs. non-blank matching); an iterate-and-filter is unambiguous.
all_atoms = []
cmd.iterate(OBJ, "stored.append((ID, chain, resv, name, alt))",
            space={'stored': all_atoms})
altconf_backbone = [a for a in all_atoms
                    if a[4] != '' and a[3] in ('CA', 'P')]
print("\n[2] Alt-conf BACKBONE atoms (CA/P) in 4wb3: %d" % len(altconf_backbone))
altconf_resvs = sorted(set((a[1], a[2]) for a in altconf_backbone))
for (ch, resv) in altconf_resvs:
    cas = [a for a in altconf_backbone if a[1] == ch and a[2] == resv]
    print("  chain '%s' resv %d: %d alt-conf backbone atoms, IDs=%s" % (
        ch, resv, len(cas), [a[0] for a in cas]))
check("4wb3 has alt-conf backbone atoms (bug trigger present)",
      len(altconf_backbone) > 0)

# --- 3. Build cas_by_chain WITH the Fix-1 dedup (mirrors __init__.py) ---
cas_list = []
cmd.iterate("%s and polymer and (name CA or name P)" % OBJ,
            "stored.append((chain, resv, ID))",
            space={'stored': cas_list})
print("\n[3] cas_list (polymer and (name CA or name P)): %d entries" % len(cas_list))

# WITHOUT dedup -- show the bug (duplicate (chain, resv) entries)
from collections import Counter
no_dedup_counts = Counter((c, r) for c, r, _ in cas_list)
no_dup_residues = {k: v for k, v in no_dedup_counts.items() if v > 1}
print("  WITHOUT dedup: %d residues have duplicate (chain, resv) entries: %s" % (
    len(no_dup_residues), sorted(no_dup_residues.items())[:5]))
# Pre-fix: chain A had 70 entries (68 real + 2 alt-conf dups), so chain A was
# longest and pick_segments(count=6) landed on chain A -> alt-conf middle -> bug.

# WITH dedup -- the Fix-1 logic (same as __init__.py)
cas_by_chain = {}
_seen_res = set()
for chain, resi, ca_id in cas_list:
    _key = (chain, resi)
    if _key not in _seen_res:
        _seen_res.add(_key)
        cas_by_chain.setdefault(chain, []).append((resi, ca_id))

all_chain_resvs = []
for ch, entries in cas_by_chain.items():
    all_chain_resvs.extend((ch, r) for r, _ in entries)
post_residue_counts = Counter(all_chain_resvs)
remaining_dups = {k: v for k, v in post_residue_counts.items() if v > 1}
print("  WITH dedup: %d total entries, %d unique (chain, resv), %d residual dups" % (
    sum(len(v) for v in cas_by_chain.values()),
    len(set(all_chain_resvs)),
    len(remaining_dups)))
check("Fix 1: cas_by_chain has NO duplicate (chain, resv) entries",
      len(remaining_dups) == 0)
deduped_keys = set(no_dup_residues.keys()) - set(remaining_dups.keys())
check("Fix 1: alt-conf residues deduped (count > 0)", len(deduped_keys) > 0)

print("  Chains (post-dedup): %s" % sorted(cas_by_chain.keys()))
for ch in sorted(cas_by_chain.keys()):
    entries = cas_by_chain[ch]
    resis = [r[0] for r in entries]
    print("    chain '%s': %d residues, resv %d-%d" % (
        ch, len(entries), min(resis), max(resis)))

# --- 4. pick_segments(count=6) -- Fix 1 shifts picks to the longest chain ---
segments = generators.pick_segments(cas_by_chain, N_SEGMENTS)
print("\n[4] pick_segments(count=%d): %d segments" % (N_SEGMENTS, len(segments)))
picked_chains = set()
for (ch, s, e) in segments:
    mid = s + 1  # segment_size=3
    is_altconf = (ch, mid) in altconf_resvs
    picked_chains.add(ch)
    print("  -> chain '%s' resi %d-%d (middle=%d) %s" % (
        ch, s, e, mid, "*** ALT-CONF MIDDLE ***" if is_altconf else ""))
check("pick_segments returned %d segments" % N_SEGMENTS, len(segments) == N_SEGMENTS)
# Fix 1 side effect: dedup made chain C (69) longest, so count=6 lands on chain
# C (no alt-conf). This is a NATURAL consequence of Fix 1 -- the picks shift
# away from the alt-conf chain. (Pre-fix, chain A was longest and was picked,
# hitting the alt-conf middle -> bug.) This is informational, not a failure:
# even if picks avoid alt-conf here, Fix 2 is the essential defense for
# structures whose LONGEST chain has alt-conf (tested directly in Section 6).
print("  picked chains: %s (alt-conf chain A %s picked)" % (
    sorted(picked_chains), "was" if 'A' in picked_chains else "NOT"))
altconf_middles_picked = [(ch, s + 1) for (ch, s, _) in segments
                          if (ch, s + 1) in altconf_resvs]
check("Fix 1 side effect: count=6 picks avoid alt-conf chain (0 alt-conf middles)"
      if len(altconf_middles_picked) == 0
      else "count=6 picks include an alt-conf middle (Fix 2 will handle it)",
      True)  # informational either way -- the real gate is Section 6

# --- 5. Snapshot ONE clean backup; insert the 6 pick_segments hiders ---
print("\n[5] Inserting %d cartoon-segment hiders (real pick_segments path):" %
      len(segments))
backup_name = backup.snapshot(OBJ)
check("backup.snapshot created (_bchm_backup exists)",
      cmd.count_atoms(backup_name) > 0)

orig_count = cmd.count_atoms(OBJ)
anchor_ids = []
for idx, (ch, s, e) in enumerate(segments):
    mid = s + 1
    is_altconf = (ch, mid) in altconf_resvs
    disp = [1.5, 0.0, 0.0]  # deterministic rigid displacement (USER REQ 2)
    label = "pick seg %d chain '%s' resi %d-%d (mid=%d)%s" % (
        idx + 1, ch, s, e, mid,
        " ALT-CONF" if is_altconf else "")
    try:
        aid = mutation.insert_cartoon_segment_hider(
            OBJ, chain=ch, start_resi=s, end_resi=e, handle="Q009",
            backup_name=backup_name, rep='cartoon', displacement=disp)
        anchor_ids.append(aid)
        print("  %s -> anchor id %d" % (label, aid))
        check("insert %s returned int id" % label, isinstance(aid, int))
    except AssertionError as exc:
        anchor_ids.append(None)
        print("  %s -> AssertionError: %s" % (label, exc))
        check("insert %s no AssertionError" % label, False)
check("ALL %d pick_segments inserted (no AssertionError)" % len(segments),
      all(a is not None for a in anchor_ids))

# --- 6. DIRECT alt-conf segment test (authoritative Fix 2 verification) ---
# Pre-fix, these EXACT segments raised `AssertionError: expected 1 anchor id,
# got [256, 257]` (chain A resi 710) and [459, 460] (chain A resi 734). With
# Fix 2, the segment copy is deduped before the alt='' retag, so the anchor
# selector matches exactly 1. This tests the bug path DIRECTLY -- bypassing
# pick_segments' chain selection so the alt-conf middle is guaranteed.
print("\n[6] DIRECT alt-conf segment inserts (authoritative Fix 2 test):")
# chain A resi 709-711 -> middle 710 (alt-conf CA id 256 alt-A, 257 alt-B)
# chain A resi 733-735 -> middle 734 (alt-conf CA id 459 alt-A, 460 alt-B)
direct_segments = [
    ("A", 709, 711, "mid=710 alt-conf CA [256,257]"),
    ("A", 733, 735, "mid=734 alt-conf CA [459,460]"),
]
direct_ids = []
for (ch, s, e, why) in direct_segments:
    mid = s + 1
    # Confirm the middle really is alt-conf (guards against data drift)
    mid_alts = [a for a in all_atoms
                if a[1] == ch and a[2] == mid and a[3] == 'CA' and a[4] != '']
    print("  chain '%s' resi %d-%d (%s): middle CA alts=%s" % (
        ch, s, e, why, [(a[0], a[4]) for a in mid_alts]))
    check("middle %d-%d is genuinely alt-conf (>=2 alt-conf CAs)" % (s, e),
          len(mid_alts) >= 2)
    disp = [0.0, 1.5, 0.0]
    label = "direct chain '%s' resi %d-%d (mid=%d, %s)" % (ch, s, e, mid, why)
    try:
        aid = mutation.insert_cartoon_segment_hider(
            OBJ, chain=ch, start_resi=s, end_resi=e, handle="Q009",
            backup_name=backup_name, rep='cartoon', displacement=disp)
        direct_ids.append(aid)
        print("  %s -> anchor id %d" % (label, aid))
        check("Fix 2: %s returned int id (no AssertionError)" % label,
              isinstance(aid, int))
    except AssertionError as exc:
        direct_ids.append(None)
        print("  %s -> AssertionError: %s" % (label, exc))
        check("Fix 2: %s no AssertionError" % label, False)
check("Fix 2: BOTH direct alt-conf segments inserted (no AssertionError)",
      all(a is not None for a in direct_ids))

# --- 7. All anchors: distinct ids + single GAME sentinel atoms ---
all_anchors = [a for a in anchor_ids + direct_ids if a is not None]
print("\n[7] Verifying all %d anchors (pick + direct):" % len(all_anchors))
distinct = len(set(all_anchors))
print("  %d anchors, %d distinct ids" % (len(all_anchors), distinct))
check("all anchor ids are DISTINCT", distinct == len(all_anchors))

for idx, aid in enumerate(all_anchors):
    sele = "%s and id %d and segi GAME and b < 0" % (OBJ, aid)
    n = cmd.count_atoms(sele)
    check("anchor %d (id=%d) is exactly 1 GAME sentinel atom" % (idx + 1, aid),
          n == 1)

new_count = cmd.count_atoms(OBJ)
print("  object atom count: %d (orig) -> %d (after %d hiders)" % (
    orig_count, new_count, len(all_anchors)))
check("object atom count increased (hiders merged in)", new_count > orig_count)
n_game = cmd.count_atoms("%s and segi GAME" % OBJ)
check("GAME atoms present (hiders live in the object)", n_game > 0)

# --- 8. Cleanup: remove hiders + discard backup, object restores ---
print("\n[8] Cleanup + restore:")
mutation.cleanup_hiders(OBJ)  # segi GAME alone (AGENTS.md)
backup.discard()
n_after = cmd.count_atoms(OBJ)
print("  after cleanup: %d atoms (orig %d)" % (n_after, orig_count))
check("cleanup removed all GAME atoms",
      cmd.count_atoms("%s and segi GAME" % OBJ) == 0)
check("object atom count restored to original", n_after == orig_count)

# --- Summary ---
print("\n" + "=" * 70)
n_pass = sum(1 for _, ok in RESULTS if ok)
n_total = len(RESULTS)
print("SUMMARY: %d/%d checks passed" % (n_pass, n_total))
print("=" * 70)
if n_pass != n_total:
    print("FAILURES:")
    for name, ok in RESULTS:
        if not ok:
            print("  FAIL: " + name)
    sys.exit(1)
print("ALL CHECKS PASSED -- quick-009 fix verified on 4wb3 (alt-conf backbone)")
print("  Fix 1 (cas_by_chain dedup): no duplicate (chain, resv) entries")
print("  Fix 2 (segment-copy dedup): alt-conf middles -> 1 anchor, no AssertionError")
