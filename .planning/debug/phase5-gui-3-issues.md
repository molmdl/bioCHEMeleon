---
status: resolved
trigger: "Debug and fix 3 distinct runtime issues discovered during Phase 5 human-verify checkpoint (plan 05-05): (1) fetch mode fails to resolve PDB code, (2) no target attachment vector found on cartoon, (3) cartoon hiders invisible"
created: 2026-08-08T19:30:00Z
updated: 2026-08-08T20:45:00Z
---

## Current Focus

hypothesis: CONFIRMED — all 3 issues root-caused and fixed
test: headless diagnostic (diag_issues.py) + e2e simulation (e2e_on_start.py) + phase5 smoke
expecting: all pass
next_action: commit fixes + stage for user GUI re-test

## Symptoms

expected: User selects fetch mode, types 1ubq, clicks Fetch (loads), clicks Start (starts game). User selects cartoon hiders on 1znf or 1ubq, clicks Start (hider inserts, visible in cartoon).
actual: (1) Start with fetch mode shows "Could not fetch PDB code '1ubq'". (2) Start with cartoon hider on 1znf/1ubq shows "no target attachment vector found". (3) Cartoon hiders invisible even with spectrum b cheat.
errors: pymol.CmdException: Error: no target attachment vector found (at mutation.py:332)
reproduction: GUI only (headless smoke passes 25/25)
started: discovered during 05-05 human-verify checkpoint

## Eliminated

- hypothesis: 1ubq N-terminus is capped/blocked (like 1znf)
  evidence: diagnostic showed 1ubq N has only 1 bond (CA) — already free. attach_amino_acid succeeds on 1ubq without any prep.
  timestamp: 2026-08-08T20:00:00Z

- hypothesis: attach_amino_acid doesn't work with named selections (needs pk1)
  evidence: diagnostic confirmed attach_amino_acid works with named selection on both 1ubq and 1znf (after prep). Smoke Open Risk 2 also confirmed.
  timestamp: 2026-08-08T20:00:00Z

## Evidence

- timestamp: 2026-08-08T19:30:00Z
  checked: __init__.py _on_start fetch branch (original committed code)
  found: _on_start ALWAYS re-fetches via demos.fetch_pdb(state.get("pdb_code")) even when the user already fetched via the Fetch button. The second cmd.fetch fails ("loading mmCIF into existing object not supported").
  implication: Issue 1 root cause = redundant re-fetch

- timestamp: 2026-08-08T19:30:00Z
  checked: 1znf.pdb structure
  found: 1znf is a multi-model NMR structure (NUMMDL 37) with hydrogens. N-terminal residue = TYR A 1. N is bonded to: CA (resi 1), H (resi 1), and C (resi 0 = ACE cap). 3 bonds = 0 free valences.
  implication: Issue 2 root cause for 1znf = multi-state + ACE cap saturating N valence

- timestamp: 2026-08-08T20:00:00Z
  checked: headless diagnostic (diag_issues.py) — fetch_pdb double-fetch
  found: first fetch_pdb("1ubq") returns "1ubq" (success). Second fetch_pdb("1ubq") returns None (mmCIF into existing object fails). "1ubq" IS in list_loaded_molecule_objects() after first fetch.
  implication: Issue 1 fix: check loaded objects before re-fetching

- timestamp: 2026-08-08T20:00:00Z
  checked: headless diagnostic — 1znf after collapse + free_nterminal_valence
  found: collapse_to_single_state reduces 37 states to 1 (424 atoms). free_nterminal_valence removes 7 atoms (ACE cap resi 0 = 6 atoms + H on N = 1). After removal, N has 1 bond (CA only) = 2 free valences. attach_amino_acid SUCCEEDS.
  implication: Issue 2 fix: collapse + free_nterminal_valence works

- timestamp: 2026-08-08T20:00:00Z
  checked: headless diagnostic — GameController.start full cartoon path on 1znf
  found: GameController.start succeeds. 7 GAME cartoon atoms. cleanup passes (verify_intact OK).
  implication: Issue 2+3 fully resolved

- timestamp: 2026-08-08T20:15:00Z
  checked: stale-data bug in _on_start (collapse AFTER data collection)
  found: Original uncommitted fix placed collapse_to_single_state AFTER extent/neighbor_ids/cas_list collection. collapse uses delete+create which reassigns atom IDs, making neighbor_ids stale (wrong atoms for line/stick hiders) and extent potentially wrong (multi-state extent vs single-state).
  implication: Moved collapse BEFORE data collection. cas_list/neighbor_ids/extent now from the collapsed single-state object.

- timestamp: 2026-08-08T20:30:00Z
  checked: e2e simulation (e2e_on_start.py) — 23 tests
  found: All 23 pass: 1ubq fetch+cartoon, 1ubq fetch+mixed, 1znf demo+cartoon, 1znf demo+mixed. GAME cartoon atoms > 0, sentinel b<0, cleanup no GAME.
  implication: All 3 issues fixed end-to-end

- timestamp: 2026-08-08T20:35:00Z
  checked: phase5 smoke regression
  found: 25/25 ALL PASSED (no regression)
  implication: Existing cmd-path tests unaffected

- timestamp: 2026-08-08T20:35:00Z
  checked: WSL gates (py_compile, 173 unittests, Pitfall-1, exec_)
  found: All green. exec_() only on QMessageBox (gui_game.py:137, allowed).
  implication: No purity/architecture violations

## Resolution

root_cause: |
  Issue 1: _on_start ALWAYS re-fetched the PDB code via demos.fetch_pdb(), even
    when the user had already clicked Fetch in the Setup tab. The second
    cmd.fetch fails because PyMOL cannot load mmCIF into an existing object
    ("loading mmCIF into existing object not supported").

  Issue 2: Two sub-causes on 1znf:
    (a) 1znf is a 37-state NMR ensemble. attach_amino_acid only operates on
        the current state, and multi-state objects break backup/verify_intact.
    (b) 1znf has an ACE cap at resi 0 whose C is bonded to the N-terminal N
        (TYR 1), plus an H atom on N. These 3 bonds (CA, cap-C, H) saturate
        the N valence, leaving 0 free valences. attach_amino_acid fails with
        "no target attachment vector found".
    Additionally, hydro=0 (original default) caused attach_amino_acid to
    remove ALL hydrogens from the entire object, breaking verify_intact.

  Issue 3: Direct consequence of Issue 2. If attach_amino_acid fails, the
    exception propagates and the hider is never inserted, so there's nothing
    to find (even with spectrum b).

fix: |
  Issue 1: _on_start now checks if the PDB code is already in
    list_loaded_molecule_objects() before re-fetching. If the user already
    clicked Fetch, the existing object is reused. Same pattern applied to
    demo mode (reuse already-loaded demo).

  Issue 2: Three changes:
    (a) mutation.collapse_to_single_state() — collapses multi-state objects
        to state 1 via create(tmp, obj, 1, 1) + delete + recreate. Called
        BEFORE data collection in _on_start so extent/neighbor_ids/cas_list
        are from the single-state object (avoids stale atom IDs).
    (b) mutation.free_nterminal_valence() — removes ACE/formyl cap residues
        (atoms bonded to N that are NOT in the terminal residue) and H atoms
        bonded to N in the terminal residue. After removal, N has 1 bond
        (CA) = 2 free valences. Called BEFORE backup.snapshot so verify_intact
        matches.
    (c) insert_cartoon_hider hydro=1 (was hydro=0) — prevents
        attach_amino_acid from stripping ALL hydrogens from the entire object.

  Issue 3: Resolved by Issue 2 fix (hiders are now actually inserted).

verification: |
  Headless:
  - diag_issues.py: all diagnostic checks pass (1ubq direct+GUI attach, 1znf
    collapse+free+attach, GameController.start on 1znf)
  - e2e_on_start.py: 23/23 pass (1ubq fetch+cartoon, 1ubq fetch+mixed,
    1znf demo+cartoon, 1znf demo+mixed — all with cleanup verification)
  - phase5_smoke.py: 25/25 ALL PASSED (no regression)
  WSL gates:
  - py_compile: OK
  - 173 unittests: OK
  - Pitfall-1 grep: 0 matches
  - exec_ grep: 1 match (QMessageBox, allowed)

files_changed:
  - biochemeleon/__init__.py (fetch reuse + collapse-before-data + free_valence)
  - biochemeleon/mutation.py (collapse_to_single_state + free_nterminal_valence + hydro=1)
