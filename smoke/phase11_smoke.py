# phase11_smoke.py -- Phase 11 headless smoke. Run: pymol -cq smoke/phase11_smoke.py
# Verifies the alt-conf cartoon/ribbon hider at the cmd-coupled runtime tier
# (pure pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot run Qt).
# GUI-only modes (connected-tube visual, auto-zoom, multi-state display,
# found-color on displaced bump) are deferred to the Plan 08 GUI human-verify.
# Headless ALL PASSED is NECESSARY but NOT SUFFICIENT (05-08 lesson).
#
# Covers: 4-call alt-conf construction, scoring truth table, cleanup, new-game,
# multi-hider (all_states + no coord corruption), mixed-rep, .bcm round-trip,
# .pse alt survival (Open Risks 2/3/5). Mirrors phase8_smoke structure.
#
# Sections (~40 checks):
#   A. SETUP: fetch 1ubq + collapse + capture orig_count + pre-capture CA coords.
#   B. ALT-CONF CONSTRUCTION (single cartoon hider): backbone-only, alt='B',
#      anchor middle CA, sentinel 1 atom.
#   C. CONNECTED RENDERING: GAME atoms in rep cartoon (geometry exists).
#   D. RIBBON: fresh fetch; ribbon hider renders in ribbon (NOT cartoon).
#   E. MULTI-HIDER: 2 disjoint segments; all_states on; >=2 states;
#      no coord corruption (1st anchor displaced, not collapsed).
#   F. SCORING (truth table): anchor-middle-CA scores, non-anchor-middle-atom
#      scores, endpoint misses, real-trace misses.
#   G. CLEANUP: backup.restore True + count back to orig + no GAME atoms.
#   H. NEW GAME: cleanup -> re-start; no residual alt-conf state.
#   I. MIXED-REP: sphere + stick + cartoon + ribbon all in registry + visible.
#   J. .BCM ROUND-TRIP: is_altconf/endpoint_resvs/alt_tag survive build->write->
#      read->import_state->reconcile.
#   K. .PSE ALT SURVIVAL: alt == 'B' after reload (or import_state fallback);
#      all_states re-applied.
#   M. CROSS-REP DISJOINT: cartoon+ribbon in one game via the FIXED single-
#      global-pick pattern (no KeyError, distinct anchor ids, disjoint
#      segments). Regression for the Phase 11 cartoon+ribbon KeyError.
#   L. SUMMARY: print pass/fail counts, sys.exit(1) on any fail.
import sys
import os

from pymol import cmd
from biochemeleon import game, registry, backup, mutation, persistence, generators
from biochemeleon.registry import HIDER_STATUS_FOUND, HIDER_STATUS_HIDDEN

RESULTS = []


def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)


obj = "1ubq"


def build_cas_by_chain():
    """{chain: [(resi, ca_id), ...]} from polymer C-alphas (ID UPPERCASE)."""
    cas = []
    cmd.iterate("%s and polymer and name CA" % obj,
                "stored.append((chain, resv, ID))", space={'stored': cas})
    d = {}
    for ch, ri, cid in cas:
        d.setdefault(ch, []).append((ri, cid))
    return d


# --- A. SETUP: fetch + collapse + pre-capture orig CA coords (Pitfall 7) ---
cmd.fetch(obj, async_=0)                        # AGENTS.md: async_=0 for sync load
mutation.collapse_to_single_state(obj)          # mirrors _prepare_and_start (NMR no-op for 1ubq)
orig_count = cmd.count_atoms(obj)
check("A: orig_count > 0", orig_count > 0)
# Bug 2 pre-capture: grab ALL original CA coords BEFORE any alt-conf insert
# (iterate_state is corrupted for non-segment atoms after a cmd.create alt-conf
# append; the GAME anchor IS a segment atom so reading it post-insert is safe,
# but the comparison baseline MUST exist before any mutation). Pitfall 7.
orig_ca_coords = {}
cmd.iterate_state(1, "%s and polymer and name CA" % obj,
                  "stored[(chain, resv)] = (x, y, z)",
                  space={'stored': orig_ca_coords})
check("A: pre-captured CA coords non-empty", len(orig_ca_coords) > 0)

# --- B. ALT-CONF CONSTRUCTION (single cartoon hider) ---
cas_by_chain = build_cas_by_chain()
segments = generators.pick_segments(cas_by_chain, 1)
check("B: pick_segments returned 1 segment", len(segments) == 1)
chain_b, start_resi, end_resi = segments[0]
disp_b = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)[0]
hider_specs_b = [((chain_b, start_resi, end_resi, disp_b), 'cartoon')]
gc = game.GameController(obj)
gc.start(hider_specs_b)
check("B: backup_name not None", gc._backup_name is not None)
check("B: registry len == 1", len(gc.registry.all()) == 1)
rec = gc.registry.all()[0]
check("B: rec.is_altconf True", rec.is_altconf is True)
check("B: rec.endpoint_resvs == (start, end)",
      rec.endpoint_resvs == (start_resi, end_resi))
check("B: rec.alt_tag == 'B'", rec.alt_tag == 'B')
check("B: GAME atoms in rep cartoon",
      cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) > 0)
# backbone-only: ALL GAME atoms are backbone (N, CA, C, O -- no sidechain; user req 1)
n_game = cmd.count_atoms("%s and segi GAME" % obj)
n_game_bb = cmd.count_atoms("%s and segi GAME and backbone" % obj)
check("B: backbone-only (GAME backbone == GAME total)", n_game == n_game_bb)
# alt='B' on ALL GAME atoms (Pitfall 12: no leakage to originals)
alts_b = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)",
            space={'stored': alts_b})
check("B: all GAME alt == 'B'", bool(alts_b) and all(a == 'B' for a in alts_b))
# sentinel: fetch_all_hider_ids returns 1 anchor (b < 0 SELECTOR, AGENTS.md)
check("B: fetch_all_hider_ids returns 1",
      len(mutation.fetch_all_hider_ids(obj)) == 1)
# anchor is MIDDLE CA (resv == start_resi + 1; USER REQ 3)
anchor_resvs_b = []
cmd.iterate("%s and segi GAME and b < 0 and name CA" % obj,
            "stored.append(resv)", space={'stored': anchor_resvs_b})
check("B: anchor resv == start_resi+1 (MIDDLE)",
      bool(anchor_resvs_b) and anchor_resvs_b[0] == start_resi + 1)

# --- C. CONNECTED RENDERING ---
# Headless can't assert "connected tube visual" (Plan 08 GUI); assert atoms
# ARE in cartoon rep so the tube has geometry to draw (success crit 1 mechanism).
check("C: GAME cartoon CA atoms > 0 (geometry exists)",
      cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj) > 0)
gc.cleanup()

# --- D. RIBBON (rep='ribbon', NOT hardcoded cartoon; success crit 2) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
seg_d = generators.pick_segments(build_cas_by_chain(), 1)[0]
disp_d = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)[0]
gc2 = game.GameController(obj)
gc2.start([((seg_d[0], seg_d[1], seg_d[2], disp_d), 'ribbon')])
check("D: GAME atoms in rep ribbon",
      cmd.count_atoms("%s and segi GAME and rep ribbon" % obj) > 0)
# The alt-conf copies INHERIT cartoon from the backup copy chain (backup had
# cartoon from cmd.fetch default -> tmp inherits -> obj inherits; same known
# behavior phase5_smoke line 283 documented for attached residues). The
# inherited cartoon HELPS the blend (continuous tube); the ribbon is the
# distinguishing marker. The phase5_smoke pattern proves rep= was forwarded:
# ribbon is on GAME atoms but NOT on the rest of the polymer (the real trace
# has no ribbon default). This is NOT a rep=-forwarding bug -- it's expected.
check("D: ribbon ONLY on GAME (rep= forwarded, not global)",
      cmd.count_atoms("%s and segi GAME and rep ribbon" % obj) > 0 and
      cmd.count_atoms("%s and polymer and not segi GAME and rep ribbon" % obj) == 0)
gc2.cleanup()

# --- E. MULTI-HIDER (2 disjoint mid-chain segments; success crit 3) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
orig_count_e = cmd.count_atoms(obj)
segments_e = generators.pick_segments(build_cas_by_chain(), 2)
check("E: 2 disjoint segments", len(segments_e) == 2)
r0 = (segments_e[0][1], segments_e[0][2])
r1 = (segments_e[1][1], segments_e[1][2])
check("E: segments disjoint (no resv overlap)", r0[1] < r1[0] or r1[1] < r0[0])
disps_e = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
hider_specs_e = [((segments_e[i][0], segments_e[i][1], segments_e[i][2], disps_e[i]),
                  'cartoon') for i in range(2)]
gc3 = game.GameController(obj)
gc3.start(hider_specs_e)
check("E: registry len == 2", len(gc3.registry.all()) == 2)
check("E: both is_altconf", all(r.is_altconf for r in gc3.registry.all()))
check("E: all_states set (>=2 alt-conf, object-scoped)",
      gc3._all_states_was_set is True)
# Phase 11 visibility-regression fix: the alt-conf hider merge now uses a
# union-selection create (combined = current-object OR tmp -> replace state 1)
# so the original atoms + prior hiders KEEP their state-1 coords. Pre-fix,
# cmd.create(object, tmp, target_state=0) REPLACED state 1 with only tmp's 12
# atoms, wiping the 660 originals (invisible). The fix is single-state (disjoint
# alt-conf segments coexist in state 1), so count_states == 1 (was >= 2).
check("E: count_states == 1 (single-state; union-create fix)",
      cmd.count_states(obj) == 1)
check("E: originals survive in state 1 (visibility regression fix)",
      cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=1) > 0)
# No coord corruption (Bug 4): 1st anchor (state 1) displaced by disp0, NOT
# collapsed. The GAME anchor IS a segment atom so iterate_state is safe
# (Pitfall 7 only corrupts NON-segment atoms). Compare against PRE-CAPTURED
# orig_ca_coords (section A baseline; 1ubq PDB coords are deterministic).
ch0, s0, e0 = segments_e[0]
mid0 = s0 + 1
orig0 = orig_ca_coords[(ch0, mid0)]
game_anchor0 = []
cmd.iterate_state(1, "%s and segi GAME and alt B and name CA and resi %d" % (obj, mid0),
                  "stored.append((x, y, z))", space={'stored': game_anchor0})
check("E: 1st anchor readable in state 1 (no iterate_state corruption)",
      len(game_anchor0) == 1)
if game_anchor0:
    gx, gy, gz = game_anchor0[0]
    disp_mag = ((gx - orig0[0]) ** 2 + (gy - orig0[1]) ** 2
                + (gz - orig0[2]) ** 2) ** 0.5
    expected_mag = (disps_e[0][0] ** 2 + disps_e[0][1] ** 2
                    + disps_e[0][2] ** 2) ** 0.5
    check("E: 1st anchor displaced ~disp0 (NOT corrupted/collapsed)",
          abs(disp_mag - expected_mag) < 0.5)
else:
    check("E: 1st anchor displaced ~disp0 (NOT corrupted/collapsed)", False)

# --- F. SCORING (truth table; USER REQ 3) ---
# Use gc3 (2 hiders). Run MISS tests first (no state change), then SCORE tests
# on DIFFERENT hiders (hider 0 then hider 1) to avoid state bleed. Clicks are
# simulated via gc3.on_pick(aid, alt, resv) DIRECTLY (NOT PickWizard -- Qt-free).
logs_f = []
gc3.set_callbacks(on_log=lambda msg: logs_f.append(msg))
ch0, rv0_1, rv0_2 = segments_e[0]
ch1, rv1_1, rv1_2 = segments_e[1]
mid0, mid1 = rv0_1 + 1, rv1_1 + 1
# anchor0 id (b < 0, name CA, resi mid0 -- the registered clickable)
anc0 = []
cmd.iterate("%s and segi GAME and b < 0 and name CA and resi %d" % (obj, mid0),
            "stored.append(ID)", space={'stored': anc0})
# endpoint0 id (alt B, name CA, resi rv0_1 -- NOT registered, NOT strictly between)
ep0 = []
cmd.iterate("%s and segi GAME and alt B and name CA and resi %d" % (obj, rv0_1),
            "stored.append(ID)", space={'stored': ep0})
# non-anchor middle atom on hider 1 (name N at mid1 -- id NOT registered; resv lookup)
n1 = []
cmd.iterate("%s and segi GAME and alt B and name N and resi %d" % (obj, mid1),
            "stored.append(ID)", space={'stored': n1})
# F1. miss_endpoint: endpoint resv (rv0_1) -> Miss (not strictly between)
logs_f.clear()
if ep0:
    gc3.on_pick(ep0[0], alt='B', resv=rv0_1)
check("F1: endpoint miss (resv not strictly between)",
      bool(logs_f) and "Miss" in logs_f[-1])
# F2. miss_real_trace: anchor0 id with alt='' -> Miss (alt != 'B'; Pitfall 10)
logs_f.clear()
if anc0:
    gc3.on_pick(anc0[0], alt='', resv=mid0)
check("F2: real-trace miss (alt != 'B')",
      bool(logs_f) and "Miss" in logs_f[-1])
# F3. score_anchor_middle_ca: anchor0 id, alt='B', resv=mid0 -> Found
logs_f.clear()
if anc0:
    gc3.on_pick(anc0[0], alt='B', resv=mid0)
check("F3: anchor middle CA scores (alt='B', middle resv)",
      bool(logs_f) and "Found" in logs_f[-1])
# F4. score_non_anchor_middle_atom: n1 id, alt='B', resv=mid1 -> Found (resv lookup)
logs_f.clear()
if n1:
    gc3.on_pick(n1[0], alt='B', resv=mid1)
check("F4: non-anchor middle atom scores (resv-range fallback)",
      bool(logs_f) and "Found" in logs_f[-1])

# --- G. CLEANUP (backup.restore; NOT cleanup_hiders; success crit 5) ---
ok_g = gc3.cleanup()
check("G: cleanup returned True", ok_g is True)
check("G: count back to orig", cmd.count_atoms(obj) == orig_count_e)
check("G: no GAME atoms remain", cmd.count_atoms("%s and segi GAME" % obj) == 0)

# --- H. NEW GAME (cleanup -> re-start; no residual alt-conf; success crit 6) ---
seg_h = generators.pick_segments(build_cas_by_chain(), 1)[0]
disp_h = generators.generate_middle_displacement(1, seed=7, magnitude=1.5)[0]
gc4 = game.GameController(obj)
gc4.start([((seg_h[0], seg_h[1], seg_h[2], disp_h), 'cartoon')])
check("H: new game has GAME atoms (no residual corruption)",
      cmd.count_atoms("%s and segi GAME" % obj) > 0)
check("H: new game registry len == 1", len(gc4.registry.all()) == 1)
gc4.cleanup()
check("H: new game cleanup restores count",
      cmd.count_atoms(obj) == orig_count_e)

# --- I. MIXED-REP (sphere + stick + cartoon + ribbon; success crit 4) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
extent = cmd.get_extent(obj)
sphere_pos = generators.generate_sphere_positions(extent, 1, seed=42)[0]
nbr_ids_i = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append(ID)",
            space={'stored': nbr_ids_i})
line_off = generators.generate_line_stick_offsets(1, seed=42)[0]
segs_i = generators.pick_segments(build_cas_by_chain(), 2)
disp_i = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
# Order matters (Pitfall 7): stick (iterate_state) BEFORE cartoon (alt-conf) so
# the stick's iterate_state runs on a clean state (no alt-conf corruption yet).
hider_specs_i = [
    (sphere_pos, 'spheres'),
    ((line_off, nbr_ids_i[0]), 'sticks'),
    ((segs_i[0][0], segs_i[0][1], segs_i[0][2], disp_i[0]), 'cartoon'),
    ((segs_i[1][0], segs_i[1][1], segs_i[1][2], disp_i[1]), 'ribbon'),
]
gc5 = game.GameController(obj)
gc5.start(hider_specs_i)
check("I: registry len == 4", len(gc5.registry.all()) == 4)
counts_i = gc5.registry.counts_by_rep()
check("I: counts has all 4 reps",
      counts_i.get('spheres') == 1 and counts_i.get('sticks') == 1
      and counts_i.get('cartoon') == 1 and counts_i.get('ribbon') == 1)
check("I: sphere GAME atoms visible",
      cmd.count_atoms("%s and segi GAME and rep spheres" % obj) > 0)
check("I: stick GAME atoms visible",
      cmd.count_atoms("%s and segi GAME and rep sticks" % obj) > 0)
check("I: cartoon GAME atoms visible",
      cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) > 0)
check("I: ribbon GAME atoms visible",
      cmd.count_atoms("%s and segi GAME and rep ribbon" % obj) > 0)
# Phase 11 visibility-regression fix: pre-fix, cmd.create(object, tmp) REPLACED
# state 1, wiping the original structure + sphere/stick hiders (only the 12
# cartoon alt-conf atoms remained in state 1). The union-create fix preserves
# ALL atoms in state 1. These per-state checks are the regression guard.
check("I: single state (union-create fix)", cmd.count_states(obj) == 1)
check("I: original polymer in state 1 (not wiped)",
      cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=1) > 0)
check("I: sphere hider in state 1 (not wiped)",
      cmd.count_atoms("%s and id %d" % (obj, gc5.registry.all()[0].id), state=1) > 0)
check("I: stick hider in state 1 (not wiped)",
      cmd.count_atoms("%s and id %d" % (obj, gc5.registry.all()[1].id), state=1) > 0)
gc5.cleanup()

# --- J. .BCM ROUND-TRIP (is_altconf/endpoint_resvs/alt_tag survive) ---
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
segs_j = generators.pick_segments(build_cas_by_chain(), 2)
disp_j = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
gc6 = game.GameController(obj)
gc6.start([((segs_j[i][0], segs_j[i][1], segs_j[i][2], disp_j[i]), 'cartoon')
           for i in range(2)])
setup_state_j = {
    "format": "biochemeleon-setup-v1", "target_mode": "loaded",
    "selected_object": obj, "pdb_code": "", "demo_id": "1ubq",
    "hider_count": 2, "lock_scene": False,
    "per_rep": {"cartoon": 2}, "difficulty_easy": True,
    "lock_source": False, "pdb_pool": [],
}
bcm_j = persistence.build_bcm_dict(gc6, setup_state_j, kind='checkpoint')
check("J: bcm version 1", bcm_j.get('version') == 1)
jhiders = bcm_j.get('registry', {}).get('hiders', [])
check("J: bcm has 2 hiders", len(jhiders) == 2)
check("J: bcm hider is_altconf True", all(h.get('is_altconf') for h in jhiders))
check("J: bcm hider endpoint_resvs present",
      all(h.get('endpoint_resvs') for h in jhiders))
check("J: bcm hider alt_tag == 'B'",
      all(h.get('alt_tag') == 'B' for h in jhiders))
# write .bcmz + scoped .pse (bare name excludes _bchm_backup)
pse_j = "phase11_test.pse"
bcmz_j = "phase11_test.bcmz"
cmd.save(pse_j, obj)
persistence.write_bcmz(bcmz_j, bcm_j, pse_j)
check("J: .bcmz exists", os.path.exists(bcmz_j) and os.path.getsize(bcmz_j) > 0)
# clear + load partial=1 (MERGE) + resolve_target
cmd.delete("all")
pse_path_j, bcm_dict_j = persistence.read_bcmz(bcmz_j)
names_before_j = set(cmd.get_names('public_objects', enabled_only=True))
cmd.load(pse_path_j, partial=1)
loaded_j = [n for n in cmd.get_names('public_objects', enabled_only=True)
            if cmd.get_type(n) == 'object:molecule']
target_j = persistence.resolve_target(bcm_dict_j, names_before_j, loaded_j)
check("J: resolve_target == 1ubq", target_j == obj)
# .pse alt survival BEFORE import_state (Open Risk 2/3 -- tests .pse preservation)
alts_j_pre = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)",
            space={'stored': alts_j_pre})
check("J: .pse alt == 'B' before import_state (survival, Open Risk 2/3)",
      bool(alts_j_pre) and all(a == 'B' for a in alts_j_pre))
# import_state + reconcile (reconstruct from sentinels + apply_bcm_dict + alt re-apply)
gc_imp = game.GameController(target_j)
gc_imp.import_state(bcm_dict_j)
recs_imp = gc_imp.registry.all()
check("J: imported registry len == 2", len(recs_imp) == 2)
check("J: imported is_altconf True", all(r.is_altconf for r in recs_imp))
check("J: imported endpoint_resvs is tuple (list->tuple coercion)",
      all(isinstance(r.endpoint_resvs, tuple) for r in recs_imp))
check("J: imported alt_tag == 'B'", all(r.alt_tag == 'B' for r in recs_imp))

# --- K. .PSE ALT SURVIVAL (post import_state) + all_states re-apply ---
alts_k = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)",
            space={'stored': alts_k})
check("K: alt == 'B' after import_state (survival or fallback)",
      bool(alts_k) and all(a == 'B' for a in alts_k))
check("K: all_states re-applied (>=2 alt-conf, Open Risk 5)",
      gc_imp._all_states_was_set is True)
gc_imp.cleanup()

# --- M. CROSS-REP DISJOINT (cartoon+ribbon; KeyError bug fix) ---
# Regression for the Phase 11 cartoon+ribbon KeyError. _prepare_and_start
# used to call pick_segments INDEPENDENTLY per rep; for count=1 both reps
# picked the SAME deterministic centered window -> same anchor middle CA
# id -> registry.register KeyError on the second rep. The fix picks ALL
# cartoon+ribbon segments in ONE pick_segments call (globally disjoint),
# then splits across reps (mirrors the fixed _prepare_and_start). Pure
# pymol.cmd.* (NO Qt) so this runs headlessly. GUI checklist item 9
# (phase11_gui_diag.py) covers the full _prepare_and_start integration.
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
_orig_count_m = cmd.count_atoms(obj)
cas_m = build_cas_by_chain()
# FIXED pattern: ONE pick_segments for cartoon+ribbon combined, then split
# (cartoon first, then ribbon -- mirrors per_rep.items() order).
altconf_total_m = 2  # cartoon=1 + ribbon=1
segs_m = generators.pick_segments(cas_m, altconf_total_m)
check("M: 2 disjoint segments available for cartoon+ribbon", len(segs_m) == 2)
disps_m = generators.generate_middle_displacement(len(segs_m), seed=42,
                                                   magnitude=1.5)
specs_m = [((segs_m[0][0], segs_m[0][1], segs_m[0][2], disps_m[0]), 'cartoon'),
          ((segs_m[1][0], segs_m[1][1], segs_m[1][2], disps_m[1]), 'ribbon')]
gc_m = game.GameController(obj)
gc_m.start(specs_m)  # would KeyError before the fix (same anchor id)
recs_m = gc_m.registry.all()
check("M: no KeyError; registry len == 2", len(recs_m) == 2)
counts_m = gc_m.registry.counts_by_rep()
check("M: counts cartoon==1 ribbon==1",
      counts_m.get('cartoon') == 1 and counts_m.get('ribbon') == 1)
# Invariant 1: the two alt-conf hiders have DISTINCT anchor ids (the core
# KeyError guard -- no duplicate (object, id)).
ids_m = [r.id for r in recs_m]
check("M: distinct anchor ids (no duplicate (object,id))",
      len(set(ids_m)) == len(ids_m) and len(ids_m) == 2)
# Invariant 2: segments are globally disjoint across reps (no shared
# residues -- end of one < start of the other after sorting by start).
_ranges_m = sorted((r.endpoint_resvs[0], r.endpoint_resvs[1]) for r in recs_m)
_disjoint_m = all(_ranges_m[i][1] < _ranges_m[i + 1][0]
                  for i in range(len(_ranges_m) - 1))
check("M: segments globally disjoint across reps", _disjoint_m)
# Both hiders are alt-conf with the expected endpoint_resvs/alt_tag.
check("M: both is_altconf True", all(r.is_altconf for r in recs_m))
check("M: both alt_tag == 'B'", all(r.alt_tag == 'B' for r in recs_m))
check("M: all_states set (>=2 alt-conf)", gc_m._all_states_was_set is True)
gc_m.cleanup()
check("M: cleanup restores atom count",
      cmd.count_atoms(obj) == _orig_count_m)
cmd.delete(obj)

# --- L. SUMMARY ---
_n_pass = sum(1 for _, ok in RESULTS if ok)
print("\n=== Phase 11 smoke: %d/%d PASSED ===" % (_n_pass, len(RESULTS)))
sys.exit(1 if _n_pass < len(RESULTS) else 0)
