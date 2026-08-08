# altconf_spike.py -- Phase 5 gap-closure (05-06) headless research spike.
# Run: pymol -cq smoke/altconf_spike.py
#
# Determines whether the alt-conf segment-replication approach can work
# for cartoon/ribbon hiders in PyMOL 2.5.0. The 05-05 human-verify found
# the terminal-extension approach renders as DISCONNECTED on 1ubq (the
# sheet arrow SHAPE on a beta-strand N-terminus; verified headless
# 05-05: the cartoon trace IS continuous -- no literal gap -- but the
# ARROW looks disconnected). The roadmap's alternative is "replicating a
# segment (loop) as an alternate position using C-alpha geometry." This
# spike tests whether that approach is viable before committing
# implementation effort in plan 05-08.
#
# Pure pymol.cmd.* only -- NO Qt (AGENTS.md: headless path cannot run Qt).
# The biochemeleon.mutation import is LATE (section 11 sentinel test) --
# mirrors phase5_smoke.py's pattern of importing project code only where
# needed.
#
# Key findings discovered during spike development (documented in diag
# output + 05-RESEARCH.md sec 12):
#   - PRIMARY (plan's hypothesis): cmd.create(obj, seg, 1, 1) same-object
#     duplication is a NO-OP -- cmd.create MERGES by identity
#     (segi,chain,resi,name), so a subset selection overwrites itself.
#   - FALLBACK (plan 12.2): cmd.create(tmp, seg) + cmd.fuse(tmp, obj,
#     mode=3) RENAMES atoms (CA->C02, N->N01, ...) to avoid collisions --
#     the duplicates have no CA, so the cartoon trace (which goes through
#     C-alpha) can't render them, and they're NOT alt-conf pairs.
#   - WORKING (this spike): cmd.create(tmp, seg) + cmd.alter(tmp,
#     "alt='B'; segi='GAME'") + cmd.create(obj, tmp) + cmd.delete(tmp).
#     The alt='B' tag makes the temp atoms' identity DIFFER from the
#     alt='' originals, so cmd.create APPENDS them as TRUE alt-conf pairs
#     (same chain/resv/name=CA, alt='B'). 25 atoms appended, 3 CAs,
#     cartoon renders them, polymer, alter_state displaces, cleanup
#     restores.
#   - CAVEAT: cmd.identify(obj, mode=0) does NOT return alt-conf atoms
#     by default -- the new atoms are found via the `segi GAME` selector
#     (cmd.iterate("obj and segi GAME", ...) and cmd.identify("obj and
#     segi GAME", mode=0) both see them). The 05-08 implementation MUST
#     use `segi GAME` selectors, NOT id-diff, to find alt-conf hiders.
#   - CAVEAT: the `id <id>` selector matches BOTH the original (alt='')
#     and the alt-conf (alt='B') versions of the same atom (they share
#     id space). To set b=-999 on ONE alt-conf CA, use `segi GAME and
#     name CA and resi <resv>` (unambiguous -- the original has
#     segi='A', so it's excluded).
#   - CAVEAT: residual alt-conf state after cmd.remove("segi GAME")
#     interferes with re-insertion (the segi GAME iterate finds 0 CAs
#     after a create+alter+create on an object that previously had
#     alt-conf atoms removed). A fresh cmd.fetch (or a backup.restore
#     via delete+create) is needed between rounds. Plan 05-08 should
#     ensure GameController.cleanup does a backup.restore (not just a
#     sentinel remove) for alt-conf hiders, OR reload the object.
#
# Questions the spike answers (in order, each builds on the prior):
#   Q1: can the alt-conf duplication mechanism append atoms to the same
#       object? (working approach: create+alter+create)
#   Q2: are the duplicates TRUE alt-conf pairs (same chain/resv/name=CA,
#       alt='B')?
#   Q3: do the cartoon/ribbon renderers show alt-conf (alt='B') atoms?
#   Q4: is all_states required for cartoon to render alt-conf?
#   Q5: are alt-conf atoms classified as polymer (cartoon trace member)?
#   Q6: can cmd.alter_state displace the copies for visibility?
#   Q7: does cleanup by segi GAME restore the original atom count?
#   Q8: does the existing sentinel design (segi GAME + b=-999 on ONE
#       clickable CA, read by segi GAME and b < 0) work UNCHANGED for
#       alt-conf hiders (fetch_all_hider_ids returns exactly 1)?
import sys
from pymol import cmd

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)


# --- 1. setup: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)  # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)
# Mid-chain segment: chain A, resi 30-32 (3 residues -- NOT terminal).
segment_sele = "%s and chain A and resi 30-32" % obj
print("diag: orig_count=%d segment_sele=%r seg_atoms=%d" %
      (orig_count, segment_sele, cmd.count_atoms(segment_sele)))

# --- 2. Can the alt-conf duplication mechanism append atoms? ---
# PRIMARY (plan's hypothesis) -- cmd.create(obj, seg, 1, 1) same-name:
# NO-OP (merge by identity). Documented as a diag (NOT a check -- the
# primary fails, and the spike uses the WORKING approach below).
ids_before_primary = set(cmd.identify(obj, mode=0))  # querying.py:1269
cmd.create(obj, segment_sele, 1, 1)
new_ids_primary = set(cmd.identify(obj, mode=0)) - ids_before_primary
print("diag: PRIMARY cmd.create(obj,seg,1,1) new_ids = %d "
      "(0 = NO-OP merge-by-identity, NOT append -- plan hypothesis "
      "DISPROVED)" % (len(new_ids_primary),))

# FALLBACK (plan 12.2) -- cmd.fuse(tmp, obj, mode=3): RENAMES atoms
# (CA->C02/C03, N->N01, ...) to avoid collisions. Documented as a diag
# (NOT a check -- the fallback fails: no CA among the renamed atoms, and
# they're NOT alt-conf pairs since names differ from the originals).
ids_before_fuse = set(cmd.identify(obj, mode=0))
tmp = "_bchm_alt_tmp"
cmd.delete(tmp)  # idempotent -- clear any stale temp
cmd.create(tmp, segment_sele, 1, 1)  # copy segment to temp (25 atoms)
cmd.fuse(tmp, obj, mode=3)  # editing.py:937; mode=3 = combine only (no bond)
cmd.delete(tmp)
fuse_new_ids = set(cmd.identify(obj, mode=0)) - ids_before_fuse
fuse_cas = []
if fuse_new_ids:
    cmd.iterate("id " + "+".join(str(i) for i in fuse_new_ids) + " and name CA",
                "stored.append(ID)", space={'stored': fuse_cas})
print("diag: FALLBACK fuse(tmp,obj,mode=3) new_ids=%d new_CAs=%d "
      "(renames atoms -- no CA -> cartoon trace can't render; plan 12.2 "
      "fallback DISPROVED)" % (len(fuse_new_ids), len(fuse_cas)))
# Reload 1ubq to guarantee a clean state for the working approach (the
# fuse fallback's 25 renamed atoms are hard to remove selectively; a
# fresh fetch is simpler and more robust).
cmd.delete(obj)
cmd.fetch("1ubq", async_=0)
print("diag: reloaded 1ubq after fuse fallback (count=%d)" %
      (cmd.count_atoms(obj),))

# WORKING (this spike) -- cmd.create(tmp, seg) + cmd.alter(tmp,
# "alt='B'; segi='GAME'") + cmd.create(obj, tmp) + cmd.delete(tmp). The
# alt='B' tag makes the temp atoms' identity DIFFER from the alt=''
# originals, so cmd.create APPENDS them (creating.py:960 -- cross-object
# create with different identity = append, NOT replace).
ids_before = set(cmd.identify(obj, mode=0))
tmp = "_bchm_alt_tmp"
cmd.delete(tmp)
cmd.create(tmp, segment_sele, 1, 1)  # copy segment to temp (25 atoms)
cmd.alter(tmp, "alt='B'; segi='GAME'", space={})  # editing.py:1424; hygienic space=
cmd.create(obj, tmp)  # APPEND alt='B' atoms to obj (different identity)
cmd.delete(tmp)
# Find the new atoms via the segi GAME selector (NOT id-diff --
# cmd.identify(obj, mode=0) does NOT return alt-conf atoms by default;
# cmd.identify("obj and segi GAME", mode=0) does).
game_ids = set(cmd.identify("%s and segi GAME" % obj, mode=0))
new_ids = game_ids  # all segi GAME atoms are the new alt-conf duplicates
check("create: alt-conf duplicates appended (create+alter+create)",
      len(new_ids) > 0)
print("diag: WORKING create+alter+create new_ids = %d (expect 25); "
      "count_after=%d (expect %d)" %
      (len(new_ids), cmd.count_atoms(obj), orig_count + len(new_ids)))

# --- 3. Are duplicates TRUE alt-conf pairs (same chain/resv/name=CA)? ---
# resv is the numeric residue value (int; symbol table editing.py:1444-
# 1449) -- NOT resi (a string that may carry insertion codes) and NOT
# int(resi) (the hygienic space= dict does not expose Python builtins,
# so int() would raise NameError; mirrors the 05-05 fix 9c49a22).
# NOTE: segment_sele matches BOTH originals (alt='', segi='A') AND
# duplicates (alt='B', segi='GAME') since they share chain/resi. Must
# exclude segi GAME from the orig query to get only the 3 original CAs.
orig_props = []
cmd.iterate(segment_sele + " and name CA and not segi GAME",
            "stored.append((chain, resv, name, alt))",
            space={'stored': orig_props})  # editing.py:1490; hygienic space=
new_props = []
cmd.iterate("%s and segi GAME and name CA" % obj,
            "stored.append((chain, resv, name, alt))",
            space={'stored': new_props})
check("create: duplicates are alt-conf pairs (same chain/resv/name, alt='B')",
      bool(new_props) and len(new_props) == len(orig_props)
      and all(o[0] == n[0] and o[1] == n[1] and o[2] == n[2] for o, n in
              zip(sorted(orig_props), sorted(new_props)))
      and all(n[3] == 'B' for n in new_props))
print("diag: orig_props=%r new_props=%r" % (orig_props, new_props))

# --- 4. Set b=-999 on ONE clickable CA (clean sentinel design) ---
# Mirrors insert_cartoon_hider step 9: b=-999 on the CLICKABLE C-alpha
# ONLY, so fetch_all_hider_ids (segi GAME and b < 0) returns exactly 1
# atom per alt-conf hider -> 1 registry entry on .pse reload. segi='GAME'
# is ALREADY set on ALL duplicates (step 2's alter); cleanup removes all
# via segi GAME.
# CRITICAL: use `segi GAME and name CA and resi <resv>` to select ONE CA,
# NOT `id <id>` -- the `id` selector in PyMOL matches BOTH the original
# (alt='') and the alt-conf (alt='B') versions of the same atom (they
# share id space in alt-conf pairs), so `alter("id <id>", "b=-999")`
# would set b=-999 on the ORIGINAL too, and may not reliably set it on
# the alt-conf copy. The `segi GAME and resi <resv>` selector is
# unambiguous: it matches ONLY the alt-conf CA (the original has
# segi='A'). resv is read via iterate (int; editing.py:1444-1449).
new_ca_info = []
cmd.iterate("%s and segi GAME and name CA" % obj, "stored.append((ID, resv))",
            space={'stored': new_ca_info})  # ID uppercase (AGENTS.md Pitfall 4)
clickable_id = new_ca_info[0][0] if new_ca_info else None
clickable_resv = new_ca_info[0][1] if new_ca_info else None
if clickable_resv is not None:
    cmd.alter("%s and segi GAME and name CA and resi %d" % (obj, clickable_resv),
              "b=-999.0", space={})
    cmd.sort(obj)  # defensive -- editing.py:1457 alter warning: sort after altering
b_neg_count = cmd.count_atoms("%s and segi GAME and b < 0" % obj)
print("diag: clickable_id=%r clickable_resv=%r (one CA gets b=-999 fetch "
      "sentinel; total new GAME CAs=%d; segi GAME b<0 count=%d)" %
      (clickable_id, clickable_resv, len(new_ca_info), b_neg_count))

# --- 5. Does cartoon render the alt-conf atoms? (KEY QUESTION) ---
# viewing.py:491 -- newly-created atoms do NOT inherit shown reps; must
# explicitly show (mutagenesis.py:660-667 precedent). Show on segi GAME
# (NOT id-sele -- identify doesn't see alt-conf atoms; segi GAME does).
cmd.show('cartoon', "%s and segi GAME" % obj)
game_cartoon_ca = cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj)
check("cartoon: alt-conf GAME CA in rep cartoon (default settings)",
      game_cartoon_ca > 0)
print("diag: game_cartoon_ca = %d (expect 3)" % (game_cartoon_ca,))

# --- 6. Is all_states needed? ---
# menu.py:762 references the all_states setting for alt-conf rendering.
cmd.set("all_states", "on")
game_cartoon_ca_all = cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj)
check("cartoon: alt-conf GAME CA in rep cartoon (all_states=on)",
      game_cartoon_ca_all > 0)
all_states_needed = (game_cartoon_ca == 0 and game_cartoon_ca_all > 0)
print("diag: game_cartoon_ca_all = %d (default=%d; all_states_needed=%s; "
      "if both >0 all_states NOT needed; if only all_states one >0, "
      "all_states IS required)" %
      (game_cartoon_ca_all, game_cartoon_ca, all_states_needed))
cmd.set("all_states", "off")  # reset

# --- 7. Are alt-conf atoms classified as polymer? ---
# The polymer selector is C-side, connectivity-based (cmd.py:363). If 0,
# the duplicates are NOT polymer and the cartoon trace won't include
# them -- document as a BLOCKER for the alt-conf approach.
game_polymer = cmd.count_atoms("%s and segi GAME and polymer" % obj)
check("cartoon: alt-conf GAME atoms in polymer", game_polymer > 0)
print("diag: game_polymer = %d (expect 25; if 0, alt-conf duplicates are "
      "NOT polymer -> cartoon trace excludes them -> BLOCKER)" %
      (game_polymer,))

# --- 8. Does ribbon render the alt-conf atoms? ---
cmd.show('ribbon', "%s and segi GAME" % obj)
game_ribbon_ca = cmd.count_atoms("%s and segi GAME and name CA and rep ribbon" % obj)
check("ribbon: alt-conf GAME CA in rep ribbon", game_ribbon_ca > 0)
print("diag: game_ribbon_ca = %d (expect 3)" % (game_ribbon_ca,))

# --- 9. Can cmd.alter_state displace alt-conf atoms for visibility? ---
# editing.py:1535 -- alter_state can modify x/y/z; example: alter_state
# 1, all, x=x+5. Displace ALL GAME atoms by 2.0 A in x.
orig_coords = []
cmd.iterate_state(1, segment_sele + " and name CA",
                  "stored.append((x, y, z))",
                  space={'stored': orig_coords})  # iterate_state exposes x/y/z
cmd.alter_state(1, "%s and segi GAME" % obj, "x=x+2.0", space={})
new_coords = []
cmd.iterate_state(1, "%s and segi GAME and name CA" % obj,
                  "stored.append((x, y, z))",
                  space={'stored': new_coords})
displaced_ok = (len(orig_coords) > 0 and len(new_coords) > 0
                and abs(new_coords[0][0] - orig_coords[0][0] - 2.0) < 0.01)
check("displace: alter_state moved alt-conf atoms", displaced_ok)
print("diag: orig_coords[0]=%r new_coords[0]=%r" %
      (orig_coords[0] if orig_coords else None,
       new_coords[0] if new_coords else None))

# --- 10. Does cleanup by segi GAME restore the original? ---
# editing.py:800 -- remove atoms FROM object (NOT delete the object).
# remove with segi GAME selector DOES see alt-conf atoms (verified).
cmd.remove("%s and segi GAME" % obj)
after_count = cmd.count_atoms(obj)
check("cleanup: count back to orig after segi GAME remove",
      after_count == orig_count)
print("diag: after_count=%d orig_count=%d" % (after_count, orig_count))

# --- 11. Sentinel: does fetch_all_hider_ids return exactly 1 atom? ---
# Re-insert for this test (mirrors the section 2 working-approach flow,
# then reads via the existing Phase 3 mutation.fetch_all_hider_ids /
# cleanup_hiders -- confirms the sentinel design works UNCHANGED for
# alt-conf hiders).
# Reload 1ubq to start from a clean state (sections 2-10 left residual
# alt-conf state records that interfere with re-insertion -- a fresh
# fetch guarantees the create+alter+create flow works identically to
# section 2).
cmd.delete(obj)
cmd.fetch("1ubq", async_=0)
print("diag sec11: reloaded 1ubq (count=%d)" % (cmd.count_atoms(obj),))
tmp = "_bchm_alt_tmp"
cmd.delete(tmp)
cmd.create(tmp, segment_sele, 1, 1)
cmd.alter(tmp, "alt='B'; segi='GAME'", space={})
cmd.create(obj, tmp)
cmd.delete(tmp)
cmd.sort(obj)  # defensive -- editing.py:1457
# Use segi GAME + resi selector (NOT id -- id matches both alt='' and
# alt='B' versions; see section 4 note).
new_ca_info2 = []
cmd.iterate("%s and segi GAME and name CA" % obj, "stored.append((ID, resv))",
            space={'stored': new_ca_info2})
print("diag sec11: segi GAME count=%d; GAME CAs=%r" %
      (cmd.count_atoms("%s and segi GAME" % obj), new_ca_info2))
if new_ca_info2:
    first_resv = new_ca_info2[0][1]
    cmd.alter("%s and segi GAME and name CA and resi %d" % (obj, first_resv),
              "b=-999.0", space={})
    cmd.sort(obj)
print("diag sec11: segi GAME b<0 count=%d" %
      (cmd.count_atoms("%s and segi GAME and b < 0" % obj),))
# LATE import of project code -- mirrors phase5_smoke.py's pattern. Only
# needed here to test the existing sentinel read/cleanup path against the
# alt-conf duplicates.
from biochemeleon import mutation  # noqa: E402 (late import, post-core tests)
fetch_ids = mutation.fetch_all_hider_ids(obj)  # mutation.py:95 -- segi GAME and b < 0
check("sentinel: fetch_all_hider_ids returns 1 atom (clean sentinel)",
      len(fetch_ids) == 1)
print("diag: fetch_ids = %r" % (fetch_ids,))
mutation.cleanup_hiders(obj)  # mutation.py:131 -- selector segi GAME
check("sentinel: cleanup_hiders restores count",
      cmd.count_atoms(obj) == orig_count)

# --- SPIKE SUMMARY ---
print("\n=== SPIKE SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails))
    sys.exit(1)
print("ALL PASSED")
