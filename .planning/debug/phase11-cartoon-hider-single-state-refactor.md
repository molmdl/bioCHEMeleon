---
status: resolved
trigger: "the multiple state is also an issue and may tell sth, main does not have this. plus i think standard alt conf or adding atom like e.g. sphere/stick dont have this. can u just let it like a way to put atom as other rep just different criteria + show representation?"
created: 2026-08-15T02:00:00Z
updated: 2026-08-16T00:00:00Z
resolution: "User-verified in Windows PyMOL GUI: single-state refactor WORKING — cartoon/ribbon hiders render in a single-state object alongside sphere/stick; click-to-find loop works (chain H hider -> Found; real trace -> Miss). KeyError gone. Two caveats noted by user: (1) SS copy NOT done (no secondary-structure inheritance for the hider fragment) — accepted for now, future visual polish (consistent with reverted 2715df5). (2) Bundled demo KeyError ('file') observed during GUI test but CONFIRMED PRE-EXISTING on main (introduced by an earlier phase, not Phase 11) — out of scope for this debug session; Phase 11 checkpoint considered PASSED with that caveat."
---

## Current Focus

hypothesis: CONFIRMED (render question). Cartoon/ribbon NEEDS real backbone atoms — a pseudoatom (or pseudoatom-built fragment on a NEW chain) does NOT render as cartoon (T2/T3/T4/T8 all BLANK). The single-state design: copy a real 3-residue backbone segment from the CLEAN backup, retag to a NEW hider chain ('H') + alt='' (NO alt-conf) + segi='GAME' + ss='L', displace the middle atoms for a visible bump, merge into state 1 via the verified union-create (preserves originals, single-state). The copies get NEW atom ids (new chain) -> id-keyed registry like sphere/stick (no alt-conf scoring gate, no KeyError from shared ids). endpoint_resvs kept on the record ONLY for _mark_found fragment coloring (is_altconf=False).
test: implement the rewrite (mutation.py 4-tuple path -> new-chain single-state; game.py drop all_states/is_first_altconf; __init__.py simplify payload wiring; smoke rewrite), then verify headless: single-state, all reps render, originals preserved, new ids distinct, KeyError fix intact, smoke green, unit tests green, grep gates clean.
expecting: count_states==1 after all hiders; count_atoms(segi GAME and rep R)>0 for all 4 reps; originals (non-GAME) preserved; distinct anchor ids; smoke pass; no regressions.
next_action: implement mutation.py rewrite + game.py + __init__.py + smoke; run headless verification.

## Symptoms

expected: Cartoon AND ribbon hiders render in the 3D viewer alongside sphere/stick hiders, all in a SINGLE-STATE object, exactly like the `main` branch. No "2 states" shown. No KeyError. No visibility regression.
actual: (pre-refactor) Phase 11 alt-conf approach creates multi-state objects, wipes coords on merge (patched by d445b88 but fragile), only cartoon renders. `main` (single-state) has none of these issues.
errors: KeyError (fixed by ebd5086 — DO NOT revert) + visibility regression (patched by d445b88 but the underlying multi-state approach is the root cause the user wants eliminated).
reproduction: GUI setup with multiple reps (cartoon+ribbon+spheres+sticks) -> only cartoon visible; object shows "2 states". `main` branch -> all visible, single state.
started: Root cause is the Phase 11 alt-conf design (insert_altconf_cartoon_hider). The user wants it replaced with the single-state pattern used by sphere/stick.
additional: Prior debug session (.planning/debug/phase11-altconf-only-cartoon-hiders-visible.md) already confirmed cmd.create REPLACES state coords and patched it with union-create. The user now wants the ENTIRE multi-state/alt-conf approach eliminated in favor of single-state, matching sphere/stick.

## Eliminated

(empty)

## Evidence

- timestamp: 2026-08-15T02:00:00Z
  checked: prior debug session phase11-altconf-only-cartoon-hiders-visible.md
  found: |
    Root cause already confirmed: insert_altconf_cartoon_hider's cmd.create(target_existing_obj, source)
    REPLACES the target state's coord set. Patched by d445b88 (union-create). main uses
    insert_cartoon_hider (2-residue terminal extension via editor.attach_amino_acid, NEW atom ids,
    SINGLE-STATE). exec/11 smoke currently 68/68 green after the union-create patch.
  implication: The coord-wiping is solved, but the multi-state/alt-conf scaffolding remains. User wants it gone.

- timestamp: 2026-08-15T02:15:00Z
  checked: diff main..exec/11 footprint
  found: |
    main: NO insert_altconf_cartoon_hider; game.py has NO altconf/all_states/is_first; __init__.py
    cartoon uses 3-tuple terminal extension + free_nterminal_valence. exec/11 added the 4-tuple
    alt-conf path + all_states + is_first_altconf + alt_tag/is_altconf/endpoint_resvs registry
    fields + on_pick alt gate + _mark_found alt branch + import_state alt/all_states re-apply.
  implication: The alt-conf machinery is concentrated in mutation.py (insert), game.py (start/on_pick/_mark_found/import/cleanup), __init__.py (payload), smoke. registry.py + persistence.py hold the alt-conf FIELDS (kept dormant to avoid touching pure layer + persistence).

- timestamp: 2026-08-15T02:30:00Z
  checked: headless render-question diagnostic (smoke/diag_render_question.py) — does a pseudoatom / pseudoatom-fragment / real-backbone-copy render as cartoon?
  found: |
    T1 single CA pseudoatom (isolated, zoomed): png=2174 vs blank=1333 -> marginal/unreliable (matches
      docstring "single residue invisible").
    T2 2 CA pseudoatoms no-bond: BLANK (1653). T3 2 CA +bond: BLANK (1430). T4 3 CA +bonds: BLANK (1437).
      -> pseudoatom CAs alone NEVER render cartoon, even bonded.
    T5 pseudoatom full backbone (N/CA/C/O x3, peptide-bonded) on EXISTING chain A: RENDERS (11782) but
      pollutes real chain / draws a connector through space -> fragile, unusable.
    T8 pseudoatom full backbone on NEW chain H: BLANK (1333) -> pseudoatoms are NOT recognized as
      polymer on a new chain; cartoon does NOT render.
    T6 real 3-residue backbone copied to a NEW temp object: RENDERS strongly (19325, polymer=12).
    T7 real backbone copied, retagged chain='H' + alt='' + segi GAME, union-create merged into live
      1ubq state 1: RENDERS strongly (21829, polymer=12), originals survive (non-GAME state1=660),
      single-state (count_states==1). <- THE DESIGN.
  implication: |
    Cartoon/ribbon REQUIRES real backbone atoms (cmd.create copies preserve polymer recognition;
    pseudoatoms do not on a new chain). A pure "pseudoatom + show" approach is IMPOSSIBLE for cartoon.
    The faithful single-state design: copy a real backbone segment from the CLEAN backup, retag to a
    NEW hider chain ('H', the existing hider-chain convention) + alt='' (NO alt-conf) + segi GAME +
    ss='L', displace the middle atoms (visible bump), union-create merge into state 1 (preserves
    originals, single-state). New chain -> NEW atom ids -> id-keyed registry (like sphere/stick):
    no alt-conf scoring gate, no id-sharing KeyError. endpoint_resvs kept on the record ONLY for
    _mark_found fragment coloring (is_altconf=False, alt_tag=''). cmd.create (union-merge) is
    UNAVOIDABLE for placing real backbone into an existing single-state object; the union-create is
    the verified safe merge (d445b88). This honors the user's intent: single-state, no alt-conf,
    no multi-state, id-keyed, mid-chain segment placement (pick_segments), show rep.

## Resolution

root_cause: |
  The Phase 11 cartoon/ribbon 4-tuple path (insert_altconf_cartoon_hider) used an alt-conf design
  (alt='B', shared ids with originals, multi-state all_states scaffolding) that is fundamentally
  unnecessary and caused the user's complaints (multi-state object, visibility regression). The
  deeper truth (verified headless): cartoon/ribbon REQUIRES real backbone atoms to render — a
  pseudoatom or pseudoatom-built fragment on a NEW chain does NOT render (T2/T3/T4/T8 BLANK). The
  correct single-state approach copies a REAL backbone segment from the clean backup as NEW atoms
  (new chain 'H', alt='', NOT alt-conf copies sharing ids), displaces the middle for a bump, and
  merges single-state via union-create. This gives new atom ids -> id-keyed registry (like
  sphere/stick), eliminating the alt-conf scoring gate, the id-sharing KeyError risk, and the
  multi-state all_states machinery — while keeping the mid-chain segment placement (pick_segments).

fix: |
  FINAL DESIGN (single-state, NEW-resi disambiguation):
  1. mutation.py: insert_altconf_cartoon_hider -> insert_cartoon_segment_hider.
     Copy real 3-residue backbone from CLEAN backup to temp; alter temp to
     chain='H' + segi='GAME' + alt='' (NO alt-conf) + ss='L' + **NEW resi**
     (resv + CARTOON_RESI_OFFSET=10000, via cartoon_hider_resi_range helper) so
     the copy's resv differs from the real CA's resv; rigid-displace the middle
     (NEW resi range); UNION-CREATE merge into state 1 (preserves originals,
     single-state); set b=-999 on the middle CA (anchor, NEW resi); fetch the
     anchor id; show rep on the chain-H GAME fragment (NEW resi). The copy
     SHARES its id with the real CA (cmd.create preserves source ids; backup is
     a snapshot) -- alter id is a NO-OP (verified), so ids CANNOT be reassigned;
     resv is the disambiguator. New helper cartoon_hider_resi_range +
     CARTOON_RESI_OFFSET (single source of truth shared by insert + game.start).
     insert_hider_for_rep: 4-tuple -> new fn, dropped is_first_altconf param.
  2. game.py: start() drops _first_altconf/altconf_count/all_states/
     _all_states_was_set; cartoon/ribbon 4-tuple `extra` = {endpoint_resvs:
     cartoon_hider_resi_range(start,end)} (the NEW resi range; is_altconf=False,
     alt_tag='' defaults). on_pick: the alt-conf alt-gate (alt==alt_tag AND
     rv1<resv<rv2) is REPLACED by the resv-range gate (endpoint_resvs is not
     None AND rv1<resv<rv2) -- disambiguates the shared id by resv (NO alt
     check, NO alt-conf). get_altconf_by_resv stays dormant (is_altconf=False
     -> returns None; only the anchor CA scores, like main/legacy). _mark_found:
     endpoint_resvs-based fragment coloring (rv1+1-rv2-1 = NEW middle resi).
     cleanup()/abort_on_error(): all_states reset blocks REMOVED. import_state():
     the alt re-apply block REMOVED; the all_states re-apply block REMOVED (no
     new game produces is_altconf records; old alt-conf .bcmz are obsolete).
  3. __init__.py: payload (chain,start,end,disp) unchanged; updated commentary
     (new-chain fragment, NEW resi, resv-gate); KEEP the single-global
     pick_segments (KeyError fix ebd5086 -- disjoint segments -> distinct real
     CA ids -> distinct anchor ids, AND disjoint NEW resi ranges -> distinct
     fragments).
  4. smoke/phase11_smoke.py: rewritten for single-state + NEW resi (77 checks:
     is_altconf False, alt_tag '', alt '' on GAME, chain H, endpoint_resvs =
     NEW range, anchor SHARES real id + resv disambiguates, single-state,
     originals survive, all 4 reps render, resv-gate scoring truth table,
     .bcm/.pse round-trip, cross-rep disjoint KeyError regression).
  5. tests/test_game_controller.py: TestOnPickAltconf -> TestOnPickFragment
     (resv-gate truth table: anchor scores, non-anchor misses, endpoint miss,
     real-trace miss via resv, no-resv miss, already-found, sphere compat).
  registry.py + persistence.py UNTOUCHED (alt-conf fields stay; is_altconf=False
  for new hiders -> dormant). generators.py untouched. wizard.py UNTOUCHED
  (resv already passed; no chain needed).
verification: |
  Headless smoke phase11_smoke.py: 77/77 PASSED (was 68; rewritten for the
  single-state design + NEW-resi disambiguation). SystemExit: 0 (clean).
  Unit tests: 313/313 OK (tests.test_setup_state + test_registry +
  test_generators + test_game_controller + test_persistence); the 1 failing
  old alt-gate test (test_altconf_real_trace_miss) was rewritten to the resv
  gate (TestOnPickFragment).
  Render question verified headless (smoke/diag_render_question.py): lone
  pseudoatom / pseudoatom-fragment on a NEW chain do NOT render cartoon (T2/T3/
  T4/T8 BLANK); a REAL backbone copy retagged chain H + alt='' + union-create
  merge DOES render (T7 png 21829 vs blank 1333), single-state, originals
  survive. NEW-resi disambiguation verified (smoke/diag_new_resi.py): alter
  resi works, copy renders, anchor SHARES real CA id but resv=10011 differs
  from real resv=11, single-state, originals survive, cleanup restores.
  WSL gates: py_compile OK (all biochemeleon/*.py); Pitfall-1 grep 0 matches;
  exec_ gate only on QMessageBox (gui_game.py:303, allowed); no leftover
  alt-conf CODE in biochemeleon/ (only "NO all_states" explanatory comments +
  gitignored .pyc). KeyError fix (single-global pick_segments, ebd5086)
  preserved: M section cartoon+ribbon no KeyError, distinct anchor ids,
  disjoint segments.
  GUI visual confirmation: PENDING human-verify (WSL cannot drive Qt).
commits:
  - d65fb2c refactor(11): single-state cartoon/ribbon hider (new-chain copy, no alt-conf)
  - 8f3e274 test(11): single-state + NEW-resi smoke, on_pick fragment tests, render diagnostics
  - 548050c docs(11): debug session for single-state cartoon/ribbon hider refactor
gui_checkpoint:
  The headless proxy (count_atoms rep + render PNG diag) confirms all 4 reps'
  GAME atoms are present + the cartoon/ribbon fragment renders + single-state.
  The final "I can SEE all 4 reps' bumps in a single-state object" is a
  human-verify checkpoint (WSL cannot drive the Qt GUI). Steps:
    1. Activate the Windows chemtools-win10 conda env (setenv.bat) and launch PyMOL.
    2. Load the phase5 1ubq setup (or fetch 1ubq) and configure multiple reps in
       the bioCHEMeleon Setup tab (e.g. spheres=1, sticks=1, cartoon=1, ribbon=1).
    3. Click Start. Expect: ALL 4 reps' bumps visible (sphere + stick + cartoon
       + ribbon) and the object shows a SINGLE state (no "2 states"). Before the
       refactor only cartoon was visible + the object showed 2 states.
    4. Click each bump: the cartoon/ribbon bump (displaced middle on chain H)
       scores Found (turns green in the middle); clicking the real trace Misses.
    5. Cleanup restores the original scene (no hiders, single state, original
       colors).
files_changed:
  - biochemeleon/mutation.py (insert_altconf_cartoon_hider -> insert_cartoon_segment_hider; CARTOON_RESI_OFFSET + cartoon_hider_resi_range helper; insert_hider_for_rep dispatch)
  - biochemeleon/game.py (start: drop multi-state/all_states; on_pick: resv gate; _mark_found: endpoint_resvs coloring; cleanup/abort/import_state: drop all_states + alt re-apply)
  - biochemeleon/__init__.py (_prepare_and_start: updated commentary; payload unchanged)
  - smoke/phase11_smoke.py (rewritten: 77 single-state + NEW-resi checks)
  - tests/test_game_controller.py (TestOnPickAltconf -> TestOnPickFragment)
  - smoke/diag_render_question.py (render-question evidence)
  - smoke/diag_new_resi.py (NEW-resi disambiguation evidence)
