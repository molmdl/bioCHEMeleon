---
phase: 02-setup-tab-configuration-bundled-demos
plan: 04
subsystem: verification
tags: [smoke-test, windows-pymol, human-verify, checkpoint, phase-complete]

# Dependency graph
requires:
  - phase: 02-setup-tab-configuration-bundled-demos
    provides: Plans 02-01 (pure state model), 02-02 (6 bundled PDBs + SOURCES.md), 02-03 (demos.py + gui_setup.py full SetupTab). Gap closures 02-05 (cap + per-rep sum + lock-source + PDB-pool editor), 02-06 (QListWidget pool editor + 4-char validation), 02-07 (Choose random button) applied after initial smoke test failure.
provides:
  - "Human approval of all 4 Phase-2 success criteria in Windows PyMOL (Test 2 cap=8 OK for the tested object size)"
  - "Phase 2 marked COMPLETE in ROADMAP.md (7/7 plans, 4 original + 3 gap closures)"
affects: [03-mutation-safety-hider-registry-foundation (Phase 3 — next; builds on the Setup state contract)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Windows PyMOL smoke test as the ONLY end-to-end verification gate for PyMOL plugin work (WSL can only verify syntax + grep gates; cmd.* + Qt rendering require the Windows runtime)"
    - "Gap-closure loop: smoke test fails -> gap closure plan -> re-test -> repeat until approved (3 gap closures: 02-05, 02-06, 02-07)"

key-files:
  created:
    - .planning/phases/02-setup-tab-configuration-bundled-demos/02-04-SUMMARY.md
  modified:
    - .planning/ROADMAP.md   # Phase 2 marked complete (7/7, [x], 2026-08-05)

key-decisions:
  - "Test 2 item 2 (hider-count cap) initially FAILED because current_target_object did a list_loaded_molecule_objects() membership re-query that returned None for valid selections; fixed in 02-05 by returning non-empty combo text directly"
  - "Test 2 cap landed at 8, not 4 — confirmed correct: cap formula is max(1, min(50, atom_count // 50)); the tested object had ~400-449 atoms (400//50=8). 1znf (~212 atoms) gives cap=4. Both are correct behavior."
  - "Pool editor went through 3 iterations: QPlainTextEdit (02-05) -> QListWidget + 4-char validation (02-06) -> + Choose random button (02-07). The final QListWidget with Add/Edit/Remove/Use-bundled-pool/Choose-random is the shipped UX."
  - "PDB_POOL (33 entries) verified against RCSB on 2026-08-05 — all curled, all returned valid PDB files, all <6000 atoms. Includes 6 bundled demos + 14 proteins + 3 DNA + 4 RNA + 6 hybrid (protein-NA + DNA-oligosaccharide drug)."

patterns-established:
  - "Pattern: Smoke test checkpoint -> gap closure plans -> re-test loop. The 02-04 checkpoint failed, spawned 02-05/02-06/02-07 gap closures, then re-approved. This is the GSD verify -> plan-gaps -> execute -> re-verify loop in action."

# Metrics
duration: ~1min (final approval pass; the full smoke-test cycle across 4 attempts spanned the session)
completed: 2026-08-05
---

# Phase 2 Plan 4: Windows PyMOL Smoke Test Summary

**Human-verified all 4 Phase-2 success criteria in Windows PyMOL after 3 gap closures (02-05, 02-06, 02-07). Phase 2 marked COMPLETE.**

## Performance

- **Duration:** ~1 min (final approval pass)
- **Completed:** 2026-08-05
- **Tasks:** 2 (checkpoint:human-verify → approved; Task 2 ROADMAP update → done)
- **Smoke test attempts:** 4 total (1 initial fail → 3 gap closures → final pass)

## Accomplishments
- Human confirmed all 4 Phase-2 success criteria PASS in Windows PyMOL:
  1. **Object selector** — 3 modes (loaded/fetch/demo) all render widgets; demo combo lists all 6 bundled demos; fetch loads a structure from RCSB (network worked).
  2. **Hider config** — cap enforced (landed at 8 for the tested object — correct per `atom_count // 50`); lock-scene auto-detects reps; per-rep sums bounded; difficulty toggles.
  3. **Reset / Randomize / Save / Load** — Reset→defaults; Randomize respects Lock source + populates fetch from pool; Save→valid JSON (11 fields); Load→repopulates; pool QListWidget with Add/Edit/Remove/Use-bundled-pool/Choose-random buttons; invalid PDB IDs rejected with QMessageBox.
  4. **Bundled demos + sources** — all 6 PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) load and render; SOURCES.md complete; dialog stays modeless (3D viewer interactive).
- Phase 2 marked COMPLETE in ROADMAP.md: 7/7 plans (4 original + 3 gap closures), top-level checkbox flipped to `[x]`, progress table row updated to "✓ Complete | 2026-08-05".

## Task Commits

1. **Task 2 (ROADMAP.md update)** — committed after this SUMMARY: `docs(02): mark Phase 2 complete in ROADMAP.md`

## Files Created/Modified
- `.planning/ROADMAP.md` — Phase 2 section: 4 plan checkboxes → 7 (added 02-05/06/07 gap closures); all flipped to `[x]`; "Plans: 4 plans" → "Plans: 7 plans (4 original + 3 gap closures)"; progress table row "3/4 | In progress" → "7/7 | ✓ Complete | 2026-08-05"; top-level Phase 2 checkbox `[ ]` → `[x]`.
- `.planning/phases/02-setup-tab-configuration-bundled-demos/02-04-SUMMARY.md` — this file.

## Decisions Made
- **Marked Phase 2 complete after 3 gap closures.** The original 4-plan phase grew to 7 plans as the smoke test surfaced real UX issues (cap not enforced, per-rep overflow, randomize changing source, empty fetch box, confusing pool editor, invalid IDs silently lost, no quick-pick button). Each gap closure was a focused plan (02-05, 02-06, 02-07) that fixed the issue + re-tested. The final approved state includes all gap closures.
- **Cap=8 is correct.** The user reported "Test 2 cap at 8 but is actually ok" — confirmed: the cap formula `max(1, min(50, atom_count // 50))` gives 8 for an object with ~400-449 atoms (8×50=400). 1znf (~212 atoms) gives cap=4 (212//50=4). Both are the intended behavior; the cap scales with object size.
- **Pool editor final design: QListWidget + 5 buttons.** After 3 iterations (QPlainTextEdit → QListWidget+4 buttons → +Choose random), the shipped design has clear list semantics, Add/Edit/Remove/Use-bundled-pool/Choose-random buttons, 4-char validation at entry, and a QMessageBox on invalid input. The 33-entry bundled PDB_POOL (verified against RCSB) is the default.

## Deviations from Plan
None for the smoke test itself. The plan was a checkpoint; the gap closures (02-05, 02-06, 02-07) were NOT part of the original 02-04 plan — they were created in response to smoke test failures/follow-ups, which is the expected GSD gap-closure loop.

## Issues Encountered
- **Initial smoke test FAILED on Test 2 item 2 (cap not enforced).** Root cause: `current_target_object()` did a `list_loaded_molecule_objects()` membership re-query that returned None for valid combo text, bailing `_on_target_changed` before `cmd.count_atoms` could recompute the cap. Fixed in 02-05.
- **3 follow-up UX issues raised after the initial fail:** (1) per-rep sum can exceed total; (2) randomize changes source + can produce empty boxes; (3) empty fetch box on randomize. All fixed in 02-05.
- **2 more UX issues raised after 02-05 re-test:** (1) pool editor (QPlainTextEdit) looks like a dropdown but is edit-only text; (2) invalid IDs (5-char, garbage) silently accepted then lost. Fixed in 02-06 (QListWidget + 4-char validation + QMessageBox feedback).
- **1 enhancement raised after 02-06 re-test:** user wanted direct "pick a random pool entry into fetch field" access (Randomize only lands on fetch mode ~25% of the time). Fixed in 02-07 (Choose random button).

## User Setup Required
None — no external service configuration. The 6 bundled demos are CC0-licensed RCSB data. The 33-entry PDB_POOL is verified against RCSB (public).

## Next Phase Readiness
- **Ready for Phase 3** (Mutation Safety & Hider Registry Foundation): The Setup state contract (DEFAULTS 11 keys, validate_state with per_rep-sum clamp, randomize_state with lock_source/pdb_pool, GAME_REPS, DEMO_MANIFEST, PDB_POOL) is stable and unit-tested (90 tests). The cmd-coupled bridge (demos.py: to_windows_path, list_loaded_molecule_objects, fetch_pdb, get_active_reps, load_demo) is in place. Phase 3 builds the hider insertion + registry on top of this foundation — it does NOT depend on the Setup tab UI, so it could have run in parallel with Phase 2 (per the roadmap's parallelization note), but is now next in sequence.
- **No blockers or concerns.** Phase 2 shipped the complete pre-game configuration experience.

---
*Phase: 02-setup-tab-configuration-bundled-demos*
*Completed: 2026-08-05*
