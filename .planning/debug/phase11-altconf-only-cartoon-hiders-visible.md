---
status: fixing
trigger: "Phase 11 alt-conf hiders: when MULTIPLE reps configured (cartoon+ribbon+spheres+sticks), ONLY cartoon hiders render. Non-cartoon reps' hiders invisible. main branch is GOOD (all reps render). KeyError fix (ebd5086) was masking this — now exposed."
created: 2026-08-15T00:00:00Z
updated: 2026-08-15T01:30:00Z
---

## Current Focus

hypothesis: CONFIRMED — cmd.create(object, tmp, target_state=*) REPLACES the object's state coords (verified: state 1 goes from 660→12 atoms). FIX: build combined from union "(object) or (tmp)" (preserves originals + prior hiders in state 1), then replace object state 1 with combined. Single-state (disjoint alt-conf segments coexist in state 1).
test: implement union-create fix in insert_altconf_cartoon_hider; verify headless (per-state counts, smoke 63/63, PNG).
expecting: state 1 = 660 originals + GAME atoms; all reps render; smoke green.
next_action: implement fix in mutation.py + update smoke Section E (count_states==1) + regression check.

## Symptoms

expected: ALL configured reps' hiders visible in the 3D viewer (cartoon + ribbon + spheres + sticks bumps all render), exactly as on the `main` branch.
actual: ONLY cartoon hiders render. Ribbon, spheres, and sticks hiders are NOT visible (missing / not showing in their respective representations).
errors: No exception/error — silent visual regression. The PyMOL console shows no error.
reproduction: Launch the Phase 11 plugin (on exec/11) in Windows PyMOL GUI. Load the phase5 1ubq setup (which configures multiple reps). Click Start. Observe: only cartoon bumps visible; other reps' hiders missing. Compare to `main` branch where all hiders show.
started: Introduced by Phase 11 alt-conf work (the alt-conf hider insertion approach). Pre-existed the KeyError fix (ebd5086). The KeyError was masking it. `main` branch is GOOD — all hiders visible there.
additional_observation: The object shows "2 states" (likely alt A = original, alt B = hider — the alt-conf scheme). Investigate whether the "2 states" / alt-conf display behavior is why non-cartoon reps don't show their hiders (e.g., `cmd.show(rep)` may not propagate to alt B atoms for non-cartoon reps, or alt-conf atoms only render under cartoon, or the rep is applied to the wrong state/alt).

## Eliminated

(empty)

## Evidence

- timestamp: 2026-08-15T00:10:00Z
  checked: diff main..exec/11 for mutation.py hider insertion
  found: |
    main has NO insert_altconf_cartoon_hider — cartoon/ribbon use insert_cartoon_hider
    (2-residue terminal extension, NEW atom ids via editor.attach_amino_acid, object
    stays SINGLE-STATE). exec/11 added insert_altconf_cartoon_hider using
    cmd.create(object, tmp, target_state=0 for first / -1 for 2nd+) which creates
    STATES. Key difference: main=single-state, exec/11=multi-state.
  implication: The multi-state behavior introduced by alt-conf cmd.create is the regression source.

- timestamp: 2026-08-15T00:20:00Z
  checked: smoke/phase11_smoke.py Section I (mixed-rep) — count_atoms("{obj} and segi GAME and rep {rep}") for all 4 reps
  found: |
    Section I PASSES (63/63): count_atoms > 0 for spheres, sticks, cartoon, ribbon on GAME atoms.
    The rep IS applied at the cmd tier. The smoke order is sphere,stick,cartoon,ribbon
    (Pitfall 7 comment: "stick BEFORE cartoon so iterate_state runs on clean state").
  implication: The bug is VISUAL rendering, not rep application. count_atoms doesn't capture it.

- timestamp: 2026-08-15T00:40:00Z
  checked: diag_stepwise_states.py — insert hiders ONE AT A TIME, print state counts after each
  found: |
    CONFIRMED: cmd.create(object, tmp, target_state=0) REPLACES state 1:
    - after sphere only: state 1 total=661 (660 orig + 1 sphere) -- GOOD
    - after 1 cartoon alt-conf (target_state=0): state 1 total=12 GAME=12 non-GAME=0
      => the 660 original atoms are GONE from state 1. Only 12 cartoon alt-conf atoms remain.
    - after 2 cartoon alt-conf: state 1=12 GAME, state 2=12 GAME, non-GAME=0 in BOTH
    - mixed-rep: sphere(id 661) in state 1: 0, state 2: 0. stick(id 662): same.
      Original polymer in state 1: 0, state 2: 0. ALL original coords WIPED.
    - "orig cartoon" PNG = 1201 bytes = EXACTLY blank (1201) => original structure INVISIBLE.
  implication: |
    cmd.create(target_existing_obj, source) ALWAYS replaces the target state's coordinate
    set with source's atoms. The original 660 atoms + prior hiders (sphere/stick) lose
    their state-1 coords and become invisible. Only the alt-conf segment atoms (in state 1
    for the first, state 2 for the second) render. The smoke test BLIND SPOT: it checks
    count_atoms (no state filter = atom list membership), NOT per-state coords. The atoms
    still EXIST in the list (count=672) but have no coords in any renderable state.

- timestamp: 2026-08-15T00:50:00Z
  checked: diag_create_target_state.py — test target_state=0 vs 1 vs source_state=1,target_state=1
  found: |
    ALL three variants give state1 total=12 non-GAME=0. cmd.create ALWAYS replaces.
    Even TEST 5 (both alt-confs in target_state=1, same state): state1 total=12 — the
    2nd cmd.create replaced the 1st's atoms. So cmd.create can NEVER merge into a state.
  implication: |
    The fix CANNOT use cmd.create to merge alt-conf atoms into the existing object's
    state. Must use a different mechanism: build a COMBINED object (original+alt-conf)
    via a union SELECTION create, or use cmd.fuse, or restore original coords after create.

## Resolution

root_cause: |
  `insert_altconf_cartoon_hider` (Phase 11) merged the alt-conf segment into the
  existing object via `cmd.create(object, tmp, target_state=0)`. PyMOL's
  `cmd.create(target_existing_obj, source)` REPLACES the target state's entire
  coordinate set with the source's atoms (verified headless across target_state=0,
  1, and source_state=1+target_state=1 — ALL replace). The first alt-conf hider
  replaced state 1's 660 original atoms with only tmp's 12 backbone atoms, WIPING
  the original structure's state-1 coords. Sphere/stick pseudoatoms (inserted
  BEFORE the alt-conf) also lost their state-1 coords. Result: only the 12 alt-conf
  segment atoms rendered (state 1 for the first hider, state 2 for the 2nd); the
  original structure + non-alt-conf hiders were invisible. The cartoon hider
  appeared to "render" only because its 12 atoms were the sole survivors in state 1.
  The smoke test had a BLIND SPOT: it checked `count_atoms` (no state filter = atom
  LIST membership), NOT per-state coords — the wiped atoms still existed in the list
  (count=672) but had no coords in any renderable state. `main` branch was unaffected
  because it used `insert_cartoon_hider` (2-residue terminal extension via
  `editor.attach_amino_acid`, NEW atom ids, object stays SINGLE-STATE — no cmd.create
  into the existing object's state).

fix: |
  In `insert_altconf_cartoon_hider` (mutation.py step 4), replaced the direct
  `cmd.create(object, tmp, target_state=...)` with a UNION-SELECTION create:
    1. `cmd.create(combined, "(object) or (tmp)", source_state=1, target_state=1)`
       — builds a COMBINED object from the union of the current object (originals +
       any prior hiders) and tmp, all in state 1.
    2. `cmd.create(object, combined, source_state=1, target_state=1)` — replaces
       object's state 1 with combined (which HAS every existing atom, so coords
       are preserved; the 12 new GAME atoms are added).
    3. `cmd.delete(combined)`.
  This preserves all existing atoms' state-1 coords while adding the alt-conf
  segment. SINGLE-STATE (no multi-state / all_states needed): disjoint alt-conf
  segments coexist in state 1 (different residues, each <=1 alt='B' copy), so the
  Bug 4 Part B multi-state workaround (target_state=-1 for 2nd+) is obsolete. The
  `is_first_altconf` parameter is kept for signature compat but is now unused.
  game.py's all_states logic is kept (harmless no-op with 1 state) for backward
  compat with import_state + smoke checks.

verification: |
  Headless smoke phase11_smoke.py: 68/68 PASSED (was 63; +5 new regression checks:
  E: count_states==1, E: originals survive in state 1, I: single state, I: original
  polymer in state 1, I: sphere/stick hider in state 1). 0 FAILs. SystemExit: 0.
  KeyError repro phase11_keyerror_repro.py: PASS (Part 1 reproduces KeyError, Part 2
  fixed works, distinct ids [19,45], SystemExit: 0 — KeyError fix ebd5086 NOT regressed).
  Stepwise diagnostic: after 1 cartoon alt-conf, state 1 = total=672 GAME=12
  non-GAME=660 (was total=12 non-GAME=0). After mixed-rep: state 1 = total=686,
  sphere in state 1: 1 (was 0), stick in state 1: 1 (was 0), original polymer in
  state 1: 602 (was 0). orig cartoon PNG: 24784 bytes >> blank 1201 (was 1201 = blank).
  WSL gates: py_compile OK; 112 unit tests OK; Pitfall-1 grep 0 matches; exec_ only on
  QMessageBox (allowed).
  GUI visual confirmation: PENDING human-verify (a WSL agent cannot drive the Qt GUI).
files_changed:
  - biochemeleon/mutation.py (insert_altconf_cartoon_hider step 4: union create; docstrings)
  - biochemeleon/game.py (comment: all_states now harmless no-op with single-state)
  - smoke/phase11_smoke.py (Section E: count_states==1 + originals-survive check; Section I: +4 per-state regression checks)
