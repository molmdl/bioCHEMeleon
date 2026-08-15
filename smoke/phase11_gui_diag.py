# phase11_gui_diag.py -- GUI-runnable diagnostic for Phase 11 alt-conf
# cartoon/ribbon hider. Run in a REAL Windows PyMOL GUI session:
#   1. Launch PyMOL (setenv.bat -> pymol) -- the GUI opens with the 3D viewer.
#   2. In the PyMOL command line (text input at the top of the GUI):
#      run smoke/phase11_gui_diag.py
#      (use the Windows-accessible path; see the Plan 08 how-to-verify steps)
#   3. Follow the printed checklist (observe the viewer + click).
#
# Pure pymol.cmd.* (NO Qt) -- it runs in the GUI process but does not open Qt
# dialogs itself; the user observes the existing viewer + clicks. The HUMAN
# is the oracle for the GUI-only failure modes headless smoke cannot see
# (05-08 lesson: 4 fix cycles each passed headless 44/44 + 49/49 but FAILED in
# the GUI -- auto-zoom, multi-state display, retroactive coord corruption,
# found-color on the displaced bump). Headless smoke (Plan 07, 54/54 PASSED)
# is NECESSARY but NOT SUFFICIENT (research Open Risk 4).
#
# The script:
#   - loads 1ubq, inserts 2 cartoon alt-conf hiders (mid-chain, ~1.5A bump)
#   - activates PickWizard so clicks route to GameController.on_pick
#     (prints "Found!"/"Miss!" to the PyMOL console + recolors the bump)
#   - exposes diag_gc / diag_wizard / new_game() for SC5 (cleanup) + SC6
#     (new game) via the PyMOL command line
#   - prints a 9-step observation checklist covering all 6 Phase 11 success
#     criteria + the 4 GUI-only failure modes
# Item 9 (ribbon + mixed reps) uses the PLUGIN Setup tab (full integration).
import sys

from pymol import cmd
from biochemeleon import game, mutation, generators
from biochemeleon.wizard import PickWizard

print("=" * 64)
print("Phase 11 GUI diagnostic -- alt-conf cartoon/ribbon hider")
print("=" * 64)

# --- SETUP: 1ubq, collapse, build CA map ---
cmd.fetch("1ubq", async_=0)                    # AGENTS.md: async_=0 for sync load
obj = "1ubq"
mutation.collapse_to_single_state(obj)          # mirrors _prepare_and_start
orig_count = cmd.count_atoms(obj)
print("Loaded 1ubq, collapsed to single state, orig_count=%d" % orig_count)

# Build {chain: [(resi, ca_id), ...]} (pick_segments input shape; ID UPPERCASE
# -- AGENTS.md: iterate exposes the atom id as UPPERCASE ID, never lowercase
# id which is the Python builtin; hygienic space= dict, never the bare None
# default which pollutes global pymol.__dict__).
cas = []
cmd.iterate("%s and polymer and name CA" % obj, "stored.append((chain, resv, ID))",
            space={'stored': cas})
cas_by = {}
for ch, ri, cid in cas:
    cas_by.setdefault(ch, []).append((ri, cid))

# --- INSERT 2 cartoon alt-conf hiders (SC1 + SC3 + all_states + Bug 4) ---
# 2 disjoint mid-chain segments in ONE pick_segments call (Bug 1 fix: disjoint
# ranges so two alt-conf hiders never share a clickable middle CA id). Each
# hider is a backbone-only alt-conf copy of a 3-residue mid-chain segment
# (user req 1); the middle residue is displaced ~1.5A (user req 2); the two
# endpoints coincide with the real trace so the cartoon tube blends at the
# ends and bulges in the middle (the connected visual -- THE Phase 11 fix).
segments = generators.pick_segments(cas_by, 2)
if len(segments) == 2:
    disps = generators.generate_middle_displacement(2, seed=42, magnitude=1.5)
    hider_specs = [((s[0], s[1], s[2], d), 'cartoon')
                   for s, d in zip(segments, disps)]
else:
    # Fallback: 1ubq is 76 residues so 2 disjoint 3-residue segments always
    # fit, but keep the fallback for unusually short chains.
    segments = generators.pick_segments(cas_by, 1)
    disps = generators.generate_middle_displacement(1, seed=42, magnitude=1.5)
    hider_specs = [((segments[0][0], segments[0][1], segments[0][2], disps[0]),
                   'cartoon')]
    print("WARN: could not pick 2 disjoint segments; using 1 hider.")

diag_gc = game.GameController(obj)
# Route "Found!"/"Miss!" log messages to the PyMOL console so the human
# sees the scoring result when clicking (default on_log is a no-op).
diag_gc.set_callbacks(on_log=lambda msg: print(msg))
diag_gc.start(hider_specs)
cmd.show("cartoon", "%s and segi GAME" % obj)   # idempotent safety (insert shows it)
n_hiders = len(diag_gc.registry.all())

# Defensive: re-apply alt='B' on GAME atoms (mirrors import_state's Open Risk
# 3 fallback; idempotent -- the insert already set alt='B'; scoped to segi
# GAME so originals (segi A) are untouched, Pitfall 12; hygienic space={} --
# AGENTS.md: never the bare None default which pollutes global pymol.__dict__).
cmd.alter("%s and segi GAME" % obj, "alt='B'", space={})

# First hider's segment (for the single-hider observations in the checklist).
chain0, start_resi, end_resi = segments[0]
mid_resi = start_resi + 1                       # the displaced middle residue
print("Inserted %d cartoon alt-conf hider(s):" % n_hiders)
for i, seg in enumerate(segments):
    print("  Hider %d: chain=%s resi %d-%d, middle CA (resi %d) displaced ~1.5A"
          % (i + 1, seg[0], seg[1], seg[2], seg[1] + 1))
if n_hiders >= 2:
    print("  all_states=on (object-scoped) so BOTH hiders are visible.")
print("orig_count=%d  game_atoms=%d  n_hiders=%d  all_states_set=%s"
      % (orig_count, cmd.count_atoms("%s and segi GAME" % obj), n_hiders,
         diag_gc._all_states_was_set))

# --- ACTIVATE PickWizard (click-to-find wired to diag_gc) ---
# Pure pymol.cmd.* (cmd.set_wizard -- NO Qt). Clicks in the viewer route to
# diag_gc.on_pick(aid, alt, resv) via PickWizard.do_pick/do_select -> the
# console prints "Found one!"/"Miss!" + the bump recolors (Pitfall 14: segi
# GAME middle only, NOT the real trace). mouse_selection_mode=0 (atomic
# pick); left-drag still rotates (do_select re-routes selection clicks).
diag_wizard = PickWizard(diag_gc, obj)
diag_wizard.activate()
print("PickWizard ACTIVE -- click atoms in the viewer to find hiders.")
print("  (mouse_selection_mode=0 atomic pick; left-drag still rotates)")


def new_game(seed=99):
    """Start a fresh cartoon hider game (SC6: New Game after cleanup).

    Call from the PyMOL command line:  new_game()   or   new_game(seed=7)
    Cleans up the current round (if still started), picks NEW disjoint
    segments (different seed for variety), inserts fresh hiders, and the
    PickWizard stays armed. Verifies no residual alt-conf corruption from
    the prior round (success criterion 6 -- the 05-08 Bug 4 + Pitfall 8
    failure mode: sentinel-remove leaves residual alt-conf state that breaks
    re-insertion; backup.restore is the canonical fix, already in cleanup).
    """
    if diag_gc._started:
        diag_gc.cleanup()
    segs = generators.pick_segments(cas_by, 2)
    if len(segs) < 2:
        segs = generators.pick_segments(cas_by, 1)
    ds = generators.generate_middle_displacement(len(segs), seed=seed,
                                                 magnitude=1.5)
    specs = [((s[0], s[1], s[2], d), 'cartoon') for s, d in zip(segs, ds)]
    diag_gc.start(specs)
    cmd.show("cartoon", "%s and segi GAME" % obj)
    cmd.alter("%s and segi GAME" % obj, "alt='B'", space={})  # defensive
    print("New game started: %d cartoon hiders. Click to find!" % len(segs))
    for i, seg in enumerate(segs):
        print("  Hider %d: chain=%s resi %d-%d" % (i + 1, seg[0], seg[1], seg[2]))


# --- OBSERVATION CHECKLIST (the human verifies each) ---
print("\n" + "=" * 64)
print("OBSERVATION CHECKLIST -- verify each in the viewer:")
print("=" * 64)
print("1. [SC1 / Risk 6] The cartoon hider renders as a CONNECTED part")
print("   of the cartoon trace (a small bulge/loop mid-chain), NOT a")
print("   disconnected segment floating away. Look for a slight bump on")
print("   the tube at resi %d-%d (hider 1)." % (start_resi, end_resi))
print("   EXPECT: connected tube with a displaced middle bump.")
print("   (05-08 failure: disconnected look -- this is THE Phase 11 fix.)")
print("")
print("2. [Pitfall 5 / Bug 3] The view did NOT auto-zoom into the inserted")
print("   segment on Start. The camera stayed at the full-molecule view.")
print("   EXPECT: no sudden zoom-in. (Headless is blind to this -- GUI only.")
print("   The fix: zoom=0 on every cmd.create inside game.start.)")
print("")
print("3. [Risk 6] The middle bump is DISPLACED (~1.5A off the real trace)")
print("   but the endpoints (resi %d, %d) connect smoothly to the real" % (start_resi, end_resi))
print("   trace (no visible seam). EXPECT: a visible bulge at resi %d," % mid_resi)
print("   ends blended, middle nudged sideways.")
print("")
print("4. [SC3 / Bug 4] %d hiders were inserted. BOTH bumps are visible" % n_hiders)
if n_hiders >= 2:
    ch1, s1, e1 = segments[1]
    print("   (all_states is on). Rotate the view -- %d separate mid-chain" % n_hiders)
    print("   bulges should be present, not just one.")
    print("   Hider 1: resi %d-%d;  Hider 2: resi %d-%d." % (start_resi, end_resi, s1, e1))
    print("   EXPECT: %d separate bulges; hider 1 NOT corrupted/collapsed by" % n_hiders)
    print("   hider 2 (05-08 Bug 4 retroactive coord corruption -- GUI only).")
else:
    print("   EXPECT: 1 bulge (multi-hider check skipped -- short chain).")
print("")
print("5. [SC4 / Pitfall 10/11/14] Click a MIDDLE atom of the bump (resi %d," % mid_resi)
print("   any atom -- CA/N/C/O). The console should print 'Found one!' and")
print("   the bump recolors (NOT the real trace). Click an ENDPOINT (resi %d" % start_resi)
print("   or %d) -- should print 'Miss!'. Click the REAL trace (alt=''," % end_resi)
print("   the original CA at resi %d, NOT the bump) -- should print 'Miss!'." % mid_resi)
print("   EXPECT: middle click = Found + recolor bump; endpoint/real = Miss.")
print("   (PickWizard is ACTIVE -- just click in the viewer. The wizard")
print("   reads (model, ID, alt, resv) from pk1 so alt='B' scores, alt='' misses.)")
print("")
print("6. [Pitfall 14 / Risk 7] When found, ONLY the bump (segi GAME middle,")
print("   resi %d) turns green -- the real trace keeps its original color." % mid_resi)
print("   EXPECT: bump recolored green, real trace unchanged. (The fix:")
print("   _mark_found colors 'segi GAME and resi <middle>', NOT the shared id.)")
print("")
print("7. [SC5] Type  diag_gc.cleanup()  in the PyMOL command line. The bump")
print("   vanishes; the molecule returns to its original state (count back to")
print("   %d). EXPECT: clean restore, no residual bulge, all_states reset off." % orig_count)
print("   (backup.restore delete+create two-step -- NOT sentinel remove;")
print("   Pitfall 8: sentinel remove leaves residual alt-conf state.)")
print("")
print("8. [SC6] Type  new_game()  in the PyMOL command line. A fresh hider")
print("   appears with NO corruption from the prior round. EXPECT: a clean")
print("   new round (then  diag_gc.cleanup()  to restore, or new_game(seed=7)")
print("   for another round).")
print("")
print("9. [SC2 + SC4] Repeat with RIBBON + MIXED REPS via the PLUGIN Setup")
print("   tab (set per_rep: ribbon=1 for SC2; cartoon=1, ribbon=1, spheres=1,")
print("   sticks=1 for SC4). Click Start in the plugin. EXPECT: hiders in")
print("   each rep, all visible + clickable. (Tests the full _prepare_and_start")
print("   integration -- the plugin builds the 4-tuple payloads, Plan 06.)")
print("")
print("=" * 64)
print("When done, type 'approved' (or describe issues) in the chat.")
print("=" * 64)
print("Helpers available in the PyMOL command line:")
print("  diag_gc.cleanup()          -- restore (SC5)")
print("  new_game()                 -- fresh cartoon game (SC6)")
print("  new_game(seed=7)           -- fresh game with a different seed")
print("  diag_wizard.deactivate()   -- stop the click-to-find mode")
print("  diag_wizard.activate()     -- resume the click-to-find mode")
print("  diag_gc.registry.all()     -- inspect the registered hiders")

# Keep the object loaded + hiders inserted + PickWizard active so the user
# can interact (click, cleanup, new_game). Do NOT cleanup here -- the user
# does it via diag_gc.cleanup() to verify SC5, then new_game() for SC6.
