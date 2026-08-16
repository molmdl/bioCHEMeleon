# phase11_smoke.py -- Phase 11 single-state refactor headless smoke.
# Run: pymol -cq smoke/phase11_smoke.py
# Verifies the cartoon/ribbon hider at the cmd-coupled runtime tier (pure
# pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot run Qt).
#
# The Phase 11 alt-conf approach (alt='B', shared ids, multi-state all_states)
# was replaced with a SINGLE-STATE new-chain backbone-segment copy
# (insert_cartoon_segment_hider): copy a real 3-residue backbone segment from
# the clean backup, retag to a NEW chain 'H' + alt='' (NO alt-conf) + segi GAME
# + ss='L', displace the middle for a bump, union-create merge into state 1.
# NEW atom ids -> id-keyed registry like sphere/stick. No multi-state, no
# all_states, no alt-conf scoring gate. The render question (does a real
# backbone copy render as cartoon?) was verified headless separately
# (smoke/diag_render_question.py T7: png 21829 vs blank 1333, originals survive,
# single-state).
#
# GUI-only modes (connected-tube visual, auto-zoom, found-color on the bump)
# are deferred to the GUI human-verify. Headless ALL PASSED is NECESSARY but
# NOT SUFFICIENT (05-08 lesson).
#
# Sections:
#   A. SETUP: fetch 1ubq + collapse + capture orig_count + pre-capture CA coords.
#   B. SEGMENT CONSTRUCTION (single cartoon hider): backbone-only, chain H,
#      alt='', anchor middle CA, sentinel 1 atom, single-state.
#   C. CONNECTED RENDERING: GAME atoms in rep cartoon (geometry exists).
#   D. RIBBON: fresh fetch; ribbon hider renders in ribbon (NOT cartoon).
#   E. MULTI-HIDER: 2 disjoint segments; single-state; originals survive;
#      no coord corruption (1st anchor displaced, not collapsed).
#   F. SCORING (id-keyed): anchor-middle-CA scores; non-anchor middle atom
#      misses (only the anchor CA is registered, like main/legacy); endpoint
#      misses; real-trace misses.
#   G. CLEANUP: backup.restore True + count back to orig + no GAME atoms.
#   H. NEW GAME: cleanup -> re-start; no residual state.
#   I. MIXED-REP: sphere + stick + cartoon + ribbon all in registry + visible
#      + single-state + originals/sphere/stick survive in state 1.
#   J. .BCM ROUND-TRIP: endpoint_resvs survives build->write->read->import->
#      reconcile (is_altconf False, alt_tag '').
#   K. .PSE SURVIVAL: chain-H GAME fragment survives reload; alt == '' on GAME.
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


# --- A. SETUP: fetch + collapse + pre-capture orig CA coords (displacement baseline) ---
cmd.fetch(obj, async_=0)                        # AGENTS.md: async_=0 for sync load
mutation.collapse_to_single_state(obj)          # mirrors _prepare_and_start (NMR no-op for 1ubq)
orig_count = cmd.count_atoms(obj)
check("A: orig_count > 0", orig_count > 0)
# Pre-capture ALL original CA coords BEFORE any insert so the displacement check
# (Section E) has a baseline. The new single-state design does NOT corrupt
# iterate_state (no alt-conf cmd.create state-append), but the baseline is
# still needed to prove the middle atoms ARE displaced (the bump exists).
orig_ca_coords = {}
cmd.iterate_state(1, "%s and polymer and name CA" % obj,
                  "stored[(chain, resv)] = (x, y, z)",
                  space={'stored': orig_ca_coords})
check("A: pre-captured CA coords non-empty", len(orig_ca_coords) > 0)

# --- B. SEGMENT CONSTRUCTION (single cartoon hider, single-state) ---
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
# Single-state refactor: id-keyed (NOT alt-conf). is_altconf False, alt_tag ''.
check("B: rec.is_altconf False (id-keyed, no alt-conf)", rec.is_altconf is False)
_new_s_b, _new_e_b = mutation.cartoon_hider_resi_range(start_resi, end_resi)
check("B: rec.endpoint_resvs == NEW resi range (offset)",
      rec.endpoint_resvs == (_new_s_b, _new_e_b))
check("B: rec.alt_tag == '' (no alt-conf)", rec.alt_tag == '')
check("B: GAME atoms in rep cartoon",
      cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) > 0)
# backbone-only: ALL GAME atoms are backbone (N, CA, C, O -- no sidechain; user req 1)
n_game = cmd.count_atoms("%s and segi GAME" % obj)
n_game_bb = cmd.count_atoms("%s and segi GAME and backbone" % obj)
check("B: backbone-only (GAME backbone == GAME total)", n_game == n_game_bb)
# alt='' on ALL GAME atoms (NOT 'B'; no alt-conf; no leakage to originals)
alts_b = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)",
            space={'stored': alts_b})
check("B: all GAME alt == '' (no alt-conf)", bool(alts_b) and all(a == '' for a in alts_b))
# NEW chain H: the fragment is on the hider chain, NOT the real chain.
chains_b = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(chain)",
            space={'stored': chains_b})
check("B: all GAME chain == 'H' (new hider chain)",
      bool(chains_b) and all(c == 'H' for c in chains_b))
# single-state (the user's core requirement)
check("B: count_states == 1 (single-state)", cmd.count_states(obj) == 1)
# sentinel: fetch_all_hider_ids returns 1 anchor (b < 0 SELECTOR, AGENTS.md)
check("B: fetch_all_hider_ids returns 1",
      len(mutation.fetch_all_hider_ids(obj)) == 1)
# anchor is MIDDLE CA at the NEW resi (start_resi+1+offset; USER REQ 3)
_new_mid_b = _new_s_b + 1
anchor_resvs_b = []
cmd.iterate("%s and segi GAME and b < 0 and name CA" % obj,
            "stored.append(resv)", space={'stored': anchor_resvs_b})
check("B: anchor resv == NEW mid (start+1+offset)",
      bool(anchor_resvs_b) and anchor_resvs_b[0] == _new_mid_b)
# cmd.create preserves source ids (backup=snapshot) -> the anchor SHARES its id
# with the real chain-A CA at the same segment position. The copy's NEW resv
# differs from the real CA's resv -> on_pick's resv gate disambiguates.
real_ca_at_mid = []
cmd.iterate("%s and chain %s and name CA and resi %d" % (obj, chain_b, start_resi + 1),
            "stored.append(ID)", space={'stored': real_ca_at_mid})
check("B: anchor id SHARES real CA id (resv disambiguates, not id)",
      bool(real_ca_at_mid) and rec.id == real_ca_at_mid[0])
check("B: anchor resv (NEW) differs from real CA resv (orig)",
      _new_mid_b != start_resi + 1)

# --- C. CONNECTED RENDERING ---
# Headless can't assert "connected tube visual" (GUI human-verify); assert the
# GAME atoms ARE in cartoon rep so the tube has geometry to draw. The render
# itself was verified in smoke/diag_render_question.py T7 (png >> blank).
check("C: GAME cartoon CA atoms > 0 (geometry exists)",
      cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj) > 0)
# originals preserved (union-create fix): the 660 real atoms survive in state 1.
check("C: originals survive in state 1 (not wiped)",
      cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=1) > 0)
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
# The real trace has no ribbon default; ribbon is ONLY on the GAME fragment
# (rep= forwarded, not global). The real polymer is NOT shown ribbon.
check("D: ribbon ONLY on GAME (rep= forwarded, not global)",
      cmd.count_atoms("%s and segi GAME and rep ribbon" % obj) > 0 and
      cmd.count_atoms("%s and polymer and not segi GAME and rep ribbon" % obj) == 0)
check("D: single-state (ribbon)", cmd.count_states(obj) == 1)
gc2.cleanup()

# --- E. MULTI-HIDER (2 disjoint mid-chain segments; single-state) ---
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
check("E: both is_altconf False (id-keyed)",
      all(r.is_altconf is False for r in gc3.registry.all()))
# single-state (the user's core requirement; NO all_states anymore)
check("E: count_states == 1 (single-state, no all_states)",
      cmd.count_states(obj) == 1)
check("E: originals survive in state 1 (visibility regression guard)",
      cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=1) > 0)
# No coord corruption: the 1st anchor (chain H middle CA, NEW resi) is displaced
# by disp0, NOT collapsed to the original coord. Compare against the PRE-
# CAPTURED orig_ca_coords (section A baseline; the real chain-A CA at resi mid0;
# 1ubq PDB coords are deterministic). The anchor is at NEW resi (offset).
ch0, s0, e0 = segments_e[0]
mid0 = s0 + 1
_new_s0, _new_e0 = mutation.cartoon_hider_resi_range(s0, e0)
_new_mid0 = _new_s0 + 1
orig0 = orig_ca_coords[(ch0, mid0)]
game_anchor0 = []
cmd.iterate_state(1, "%s and chain H and segi GAME and name CA and resi %d" % (obj, _new_mid0),
                  "stored.append((x, y, z))", space={'stored': game_anchor0})
check("E: 1st anchor readable in state 1 (NEW resi)", len(game_anchor0) == 1)
if game_anchor0:
    gx, gy, gz = game_anchor0[0]
    disp_mag = ((gx - orig0[0]) ** 2 + (gy - orig0[1]) ** 2
                + (gz - orig0[2]) ** 2) ** 0.5
    expected_mag = (disps_e[0][0] ** 2 + disps_e[0][1] ** 2
                    + disps_e[0][2] ** 2) ** 0.5
    check("E: 1st anchor displaced ~disp0 (bump exists, not collapsed)",
          abs(disp_mag - expected_mag) < 0.5)
else:
    check("E: 1st anchor displaced ~disp0 (bump exists, not collapsed)", False)
# 2nd anchor on a DIFFERENT resi (disjoint segment) -> distinct NEW id (no KeyError)
ids_e = [r.id for r in gc3.registry.all()]
check("E: distinct anchor ids (2 disjoint chain-H fragments)",
      len(set(ids_e)) == 2)

# --- F. SCORING (id-keyed; like sphere/stick + legacy cartoon) ---
# Only the anchor middle-CA (chain H, b=-999) is registered. Clicking it scores.
# Clicking a non-anchor middle atom (N/C/O), an endpoint, or the real trace misses
# (the registry has no record for those ids; get_altconf_by_resv skips
# is_altconf=False records). This matches main/legacy cartoon hider behavior.
logs_f = []
gc3.set_callbacks(on_log=lambda msg: logs_f.append(msg))
ch0, rv0_1, rv0_2 = segments_e[0]
ch1, rv1_1, rv1_2 = segments_e[1]
mid0, mid1 = rv0_1 + 1, rv1_1 + 1
# NEW resi ranges (the copy's resv differs from the real resv -> resv gate)
_ns0, _ne0 = mutation.cartoon_hider_resi_range(rv0_1, rv0_2)
_ns1, _ne1 = mutation.cartoon_hider_resi_range(rv1_1, rv1_2)
_nmid0, _nmid1 = _ns0 + 1, _ns1 + 1
# anchor0 id (chain H, b < 0, name CA, NEW resi -- the registered clickable)
anc0 = []
cmd.iterate("%s and chain H and segi GAME and b < 0 and name CA and resi %d" % (obj, _nmid0),
            "stored.append(ID)", space={'stored': anc0})
# endpoint0 id (chain H, name CA, NEW resi _ns0 -- NOT registered, NOT the anchor)
ep0 = []
cmd.iterate("%s and chain H and segi GAME and name CA and resi %d" % (obj, _ns0),
            "stored.append(ID)", space={'stored': ep0})
# non-anchor middle atom on hider 1 (chain H, name N at NEW resi -- id NOT registered)
n1 = []
cmd.iterate("%s and chain H and segi GAME and name N and resi %d" % (obj, _nmid1),
            "stored.append(ID)", space={'stored': n1})
# real-trace CA at mid0 (chain A, ORIGINAL resi -- the original the fragment copies)
real0 = []
cmd.iterate("%s and chain %s and name CA and resi %d and not segi GAME" % (obj, ch0, mid0),
            "stored.append(ID)", space={'stored': real0})
# F1. miss_endpoint: endpoint0 id (NEW resv=_ns0, not strictly between) -> Miss
logs_f.clear()
if ep0:
    gc3.on_pick(ep0[0], alt='', resv=_ns0)
check("F1: endpoint miss (resv not strictly between, NEW range)",
      bool(logs_f) and "Miss" in logs_f[-1])
# F2. miss_real_trace: real chain-A CA id (shares anchor id; resv=orig mid0,
# NOT in the NEW range) -> Miss (resv gate disambiguates the shared id)
logs_f.clear()
if real0:
    gc3.on_pick(real0[0], alt='', resv=mid0)
check("F2: real-trace miss (shared id, resv not in NEW range)",
      bool(logs_f) and "Miss" in logs_f[-1])
# F3. score_anchor: anchor0 id (NEW resv=_nmid0, strictly between) -> Found
logs_f.clear()
if anc0:
    gc3.on_pick(anc0[0], alt='', resv=_nmid0)
check("F3: anchor middle CA scores (resv in NEW range)",
      bool(logs_f) and "Found" in logs_f[-1])
# F4. miss_non_anchor_middle: non-anchor middle atom (N) id -> Miss (only the
# anchor CA is registered; get_altconf_by_resv is dormant for is_altconf=False)
logs_f.clear()
if n1:
    gc3.on_pick(n1[0], alt='', resv=_nmid1)
check("F4: non-anchor middle atom misses (only anchor CA registered, like main)",
      bool(logs_f) and "Miss" in logs_f[-1])

# --- G. CLEANUP (backup.restore; success crit 5) ---
ok_g = gc3.cleanup()
check("G: cleanup returned True", ok_g is True)
check("G: count back to orig", cmd.count_atoms(obj) == orig_count_e)
check("G: no GAME atoms remain", cmd.count_atoms("%s and segi GAME" % obj) == 0)
# After cleanup, chain H is gone (the fragment was the only chain-H content here).
check("G: no chain H atoms remain (fragment removed)",
      cmd.count_atoms("%s and chain H" % obj) == 0)

# --- H. NEW GAME (cleanup -> re-start; no residual; success crit 6) ---
seg_h = generators.pick_segments(build_cas_by_chain(), 1)[0]
disp_h = generators.generate_middle_displacement(1, seed=7, magnitude=1.5)[0]
gc4 = game.GameController(obj)
gc4.start([((seg_h[0], seg_h[1], seg_h[2], disp_h), 'cartoon')])
check("H: new game has GAME atoms (no residual corruption)",
      cmd.count_atoms("%s and segi GAME" % obj) > 0)
check("H: new game registry len == 1", len(gc4.registry.all()) == 1)
check("H: new game single-state", cmd.count_states(obj) == 1)
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
# Order (Pitfall 7): stick (iterate_state) BEFORE cartoon so the stick's
# iterate_state runs on a clean state. (The new cartoon path is single-state
# and does not corrupt iterate_state, but the order is kept for safety.)
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
# Single-state (the user's core requirement): all 4 reps in ONE state.
check("I: single state (all 4 reps, no multi-state)", cmd.count_states(obj) == 1)
# originals preserved (union-create fix): the real polymer survives in state 1.
check("I: original polymer in state 1 (not wiped)",
      cmd.count_atoms("%s and not segi GAME and polymer" % obj, state=1) > 0)
# sphere + stick hiders survive in state 1 (not wiped by the cartoon merge)
check("I: sphere hider in state 1 (not wiped)",
      cmd.count_atoms("%s and id %d" % (obj, gc5.registry.all()[0].id), state=1) > 0)
check("I: stick hider in state 1 (not wiped)",
      cmd.count_atoms("%s and id %d" % (obj, gc5.registry.all()[1].id), state=1) > 0)
# all 4 hiders have distinct ids (id-keyed; no sharing)
ids_i = [r.id for r in gc5.registry.all()]
check("I: 4 distinct hider ids", len(set(ids_i)) == 4)
gc5.cleanup()

# --- J. .BCM ROUND-TRIP (endpoint_resvs survives; is_altconf False, alt_tag '') ---
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
# Single-state refactor: is_altconf is NOT emitted (False default); alt_tag NOT
# emitted ('' default); endpoint_resvs IS emitted (for _mark_found coloring).
check("J: bcm hider is_altconf absent/False",
      all(not h.get('is_altconf') for h in jhiders))
check("J: bcm hider endpoint_resvs present",
      all(h.get('endpoint_resvs') for h in jhiders))
check("J: bcm hider alt_tag absent/empty",
      all(not h.get('alt_tag') for h in jhiders))
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
# .pse survival BEFORE import_state: chain-H GAME fragment present, alt == ''
chains_j_pre = []
cmd.iterate("%s and segi GAME" % obj, "stored.append((chain, alt))",
            space={'stored': chains_j_pre})
check("J: .pse GAME chain H + alt '' before import_state (survival)",
      bool(chains_j_pre) and all(c == 'H' and a == '' for c, a in chains_j_pre))
# import_state + reconcile (reconstruct from sentinels + apply_bcm_dict)
gc_imp = game.GameController(target_j)
gc_imp.import_state(bcm_dict_j)
recs_imp = gc_imp.registry.all()
check("J: imported registry len == 2", len(recs_imp) == 2)
check("J: imported is_altconf False", all(r.is_altconf is False for r in recs_imp))
check("J: imported endpoint_resvs is tuple (list->tuple coercion)",
      all(isinstance(r.endpoint_resvs, tuple) for r in recs_imp))
check("J: imported alt_tag == '' (no alt-conf)", all(r.alt_tag == '' for r in recs_imp))

# --- K. .PSE SURVIVAL (post import_state): chain-H GAME fragment + alt '' ---
chains_k = []
cmd.iterate("%s and segi GAME" % obj, "stored.append((chain, alt))",
            space={'stored': chains_k})
check("K: chain H + alt == '' after import_state (survival)",
      bool(chains_k) and all(c == 'H' and a == '' for c, a in chains_k))
check("K: single-state after import", cmd.count_states(obj) == 1)
gc_imp.cleanup()

# --- M. CROSS-REP DISJOINT (cartoon+ribbon; KeyError bug fix) ---
# Regression for the Phase 11 cartoon+ribbon KeyError. _prepare_and_start
# used to call pick_segments INDEPENDENTLY per rep; for count=1 both reps
# picked the SAME deterministic centered window -> same anchor id (alt-conf
# copies shared ids) -> registry.register KeyError. The fix picks ALL
# cartoon+ribbon segments in ONE pick_segments call (globally disjoint), then
# splits across reps. With the single-state refactor, disjoint resi ranges ->
# distinct chain-H fragments -> distinct NEW anchor ids (still no KeyError).
cmd.delete(obj)
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
_orig_count_m = cmd.count_atoms(obj)
cas_m = build_cas_by_chain()
# FIXED pattern: ONE pick_segments for cartoon+ribbon combined, then split
# (cartoon first, then ribbon -- mirrors per_rep.items() order).
cartoon_total_m = 2  # cartoon=1 + ribbon=1
segs_m = generators.pick_segments(cas_m, cartoon_total_m)
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
# Invariant 1: the two hiders have DISTINCT anchor ids (the core KeyError guard).
ids_m = [r.id for r in recs_m]
check("M: distinct anchor ids (no duplicate (object,id))",
      len(set(ids_m)) == len(ids_m) and len(ids_m) == 2)
# Invariant 2: segments are globally disjoint across reps.
_ranges_m = sorted((r.endpoint_resvs[0], r.endpoint_resvs[1]) for r in recs_m)
_disjoint_m = all(_ranges_m[i][1] < _ranges_m[i + 1][0]
                  for i in range(len(_ranges_m) - 1))
check("M: segments globally disjoint across reps", _disjoint_m)
# Both hiders id-keyed (no alt-conf).
check("M: both is_altconf False (id-keyed)",
      all(r.is_altconf is False for r in recs_m))
check("M: both alt_tag == '' (no alt-conf)", all(r.alt_tag == '' for r in recs_m))
check("M: single-state (cartoon+ribbon, no multi-state)",
      cmd.count_states(obj) == 1)
gc_m.cleanup()
check("M: cleanup restores atom count",
      cmd.count_atoms(obj) == _orig_count_m)
cmd.delete(obj)

# --- N. BLANK-CHAIN REGRESSION (MemProtMD blank-chain selector bug) ---
# Regression for the Phase 11 bug where insert_cartoon_segment_hider crashed
# with `AssertionError: expected 1 anchor id, got [id, id]` on structures with
# a BLANK chain identifier (MemProtMD 1gzm/3gp6/sasdpg4 — all atoms on a single
# unnamed chain). Root cause: the unquoted `chain ` (blank, no value) PyMOL
# selector is malformed — it ignores the object scope and matches blank-chain
# atoms from EVERY object in the session (backup + live), doubling the atom
# count in cmd.create. The fix: single-quote the chain value (`chain '%s'`).
# This section retags 1ubq to a blank chain (reproducing the MemProtMD layout)
# and verifies the cartoon hider inserts cleanly. See debug session
# .planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md.
cmd.fetch(obj, async_=0)
mutation.collapse_to_single_state(obj)
# Retag ALL atoms to blank chain (mimics MemProtMD 1gzm/3gp6 single-blank-chain
# layout). alter chain='' sets the chain to the empty/blank identifier.
cmd.alter(obj, "chain=''", space={})
chains_n = []
cmd.iterate(obj, "stored.append(chain)", space={'stored': chains_n})
check("N: retag to blank chain (all atoms chain='')",
      bool(chains_n) and all(c == '' for c in chains_n))
# Build cas_by_chain on the blank-chain object + pick a mid-chain segment.
cas_n = build_cas_by_chain()
check("N: blank-chain cas_by_chain has 1 key (empty str)",
      len(cas_n) == 1 and '' in cas_n)
segs_n = generators.pick_segments(cas_n, 1)
check("N: pick_segments returns 1 segment on blank chain", len(segs_n) == 1)
# game.start with a cartoon hider — before the fix this raised
# `AssertionError: expected 1 anchor id, got [id, id]` because the segment
# selection matched atoms from both the backup and the live object.
_n_orig = cmd.count_atoms(obj)
disp_n = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)[0]
gc_n = game.GameController(obj)
_assertion_ok = True
try:
    gc_n.start([((segs_n[0][0], segs_n[0][1], segs_n[0][2], disp_n), 'cartoon')])
except AssertionError:
    _assertion_ok = False
check("N: blank-chain cartoon hider inserts without AssertionError",
      _assertion_ok)
if _assertion_ok:
    check("N: blank-chain registry len == 1", len(gc_n.registry.all()) == 1)
    if gc_n.registry.all():
        rec_n = gc_n.registry.all()[0]
        check("N: blank-chain hider id is an int", isinstance(rec_n.id, int))
        check("N: blank-chain endpoint_resvs is a 2-tuple",
              isinstance(rec_n.endpoint_resvs, tuple) and len(rec_n.endpoint_resvs) == 2)
    ok_n = gc_n.cleanup()
    check("N: blank-chain cleanup restores atom count",
          ok_n is True and cmd.count_atoms(obj) == _n_orig)
    check("N: blank-chain no GAME atoms after cleanup",
          cmd.count_atoms("%s and segi GAME" % obj) == 0)
else:
    check("N: blank-chain registry len == 1", False)
    check("N: blank-chain cleanup restores atom count", False)
    check("N: blank-chain no GAME atoms after cleanup", False)
cmd.delete(obj)

# --- L. SUMMARY ---
_n_pass = sum(1 for _, ok in RESULTS if ok)
print("\n=== Phase 11 smoke: %d/%d PASSED ===" % (_n_pass, len(RESULTS)))
sys.exit(1 if _n_pass < len(RESULTS) else 0)
