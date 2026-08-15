---
phase: 11-alt-conf-cartoon-hider
plan: 08
subsystem: testing (GUI human-verify checkpoint)
status: complete
date: 2026-08-16
tags: [cartoon, ribbon, single-state, new-chain-copy, gui-diagnostic, human-verify, checkpoint, user-verified, hider-03, hider-05]

# Dependency graph
requires:
  - phase: 11-alt-conf-cartoon-hider-07
    provides: smoke/phase11_smoke.py headless smoke (54/54 ALL PASSED, exit 0) -- the NECESSARY gate proving the mechanism at the cmd tier
  - phase: 11-alt-conf-cartoon-hider-01
    provides: pick_segments (disjoint mid-chain) + generate_middle_displacement (rigid unit-vector RNG)
  - phase: 11-alt-conf-cartoon-hider-04
    provides: insert_cartoon_segment_hider (single-state new-chain copy) + insert_hider_for_rep dispatcher
  - phase: 11-alt-conf-cartoon-hider-05
    provides: GameController.on_pick resv-range gate + _mark_found endpoint_resvs fragment coloring + start single-state wiring
  - phase: 11-alt-conf-cartoon-hider-06
    provides: _prepare_and_start 4-tuple payload construction (pick_segments + generate_middle_displacement -> start)
provides:
  - smoke/phase11_gui_diag.py -- GUI-runnable diagnostic + 9-step observation checklist (pure pymol.cmd.* NO Qt)
  - User verification of all 6 Phase 11 success criteria in a real Windows PyMOL GUI session on 1ubq (the SUFFICIENT gate headless smoke cannot provide)
  - Phase 11 closure: HIDER-03/HIDER-05 alt-conf gap from Phase 5 CLOSED
affects: [phase-08 (08-05 checkpoint completion incomplete), phase-09 (09-02/03/04 incomplete), phase-10 (not yet planned)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GUI-runnable diagnostic pattern: pure pymol.cmd.* script the USER runs in a real Windows PyMOL GUI session (setenv.bat -> pymol -> run smoke/phase11_gui_diag.py); the script automates SETUP + activates PickWizard + prints a human-observation checklist. The HUMAN is the oracle for GUI-only failure modes (auto-zoom, multi-state display, connected-bulge visual, found-color on displaced bump) headless smoke is blind to."
    - "Single-state new-chain copy: copy a REAL 3-residue backbone from the clean backup to a NEW chain 'H' + alt='' + segi='GAME' + NEW resi (CARTOON_RESI_OFFSET=10000), rigid-displace the middle, union-create merge into state 1 (preserves originals, single-state). New chain -> NEW atom ids -> id-keyed registry (like sphere/stick), eliminating the alt-conf scoring gate + id-sharing KeyError."
    - "resv-range gate: on_pick scoring uses endpoint_resvs (NOT alt==alt_tag) to disambiguate the shared id -- the cartoon hider's anchor CA SHARES the real CA's id (cmd.create preserves source ids; alter id is a NO-OP), so resv (NEW resi range, shifted by CARTOON_RESI_OFFSET) is the disambiguator."

key-files:
  created:
    - smoke/phase11_gui_diag.py  (227 lines; GUI-runnable diagnostic + 9-step checklist; pure pymol.cmd.* NO Qt)
  modified: []

key-decisions:
  - "Single-state refactor (d65fb2c) eliminated the alt-conf/multi-state complexity entirely: insert_altconf_cartoon_hider -> insert_cartoon_segment_hider (new-chain copy, alt='', single-state, NEW resi via CARTOON_RESI_OFFSET). This was a MAJOR mid-execution deviation from the plan's alt-conf design, triggered by 2 debug sessions (GUI-only visibility regressions: only cartoon rendered, multi-state cmd.create wiped original coords). The refactor preserves the mid-chain segment placement (pick_segments) + connected visual + the HIDER-03/HIDER-05 gap closure, while removing the all_states/is_first_altconf/alt_tag scaffolding."
  - "SS (secondary-structure) copy NOT done -- the hider fragment does NOT inherit parent secondary structure. Accepted for now as future visual polish (consistent with the reverted commit 2715df5). The fragment renders as a loop (ss='L') and is visible+clickable; the cosmetic ss-mismatch is a future enhancement, not a Phase 11 blocker."
  - "Bundled demo KeyError ('file') -- surfaced during the GUI test but CONFIRMED PRE-EXISTING on main (introduced by an earlier phase, NOT Phase 11). Out of scope for Phase 11. A separate debug file (.planning/debug/bundled-demo-keyerror-file.md, status: investigating) exists for a future fix."
  - "The plan frontmatter must_haves describe the ORIGINAL alt-conf design and are STALE. Verification was against the 6 outcome-based SUCCESS CRITERIA (from ROADMAP.md), NOT the stale alt-conf must_haves. The 4 'GUI-only failure modes' the must_haves list (auto-zoom, connected tube, displaced bump, multi-state all_states display) were checked via the diagnostic -- the single-state refactor made multi-state + coord corruption impossible by construction (no multi-state, union-create preserves originals)."

patterns-established:
  - "Phase 11 GUI checkpoint resolution: a GUI-runnable diagnostic (phase11_gui_diag.py) + a headless smoke (phase11_smoke.py) together provide NECESSARY (headless) + SUFFICIENT (GUI human-verify) verification for cmd.create-heavy code paths. The 05-08 methodology failure (4 fix cycles passed headless 44/44 + 49/49 but failed in GUI) is closed by running BOTH tiers."
  - "Mid-execution refactor documentation: when a debug session discovers the plan's design is fundamentally wrong, record the root cause + fix + verification in .planning/debug/<name>.md (frontmatter status: verifying -> resolved), then commit the resolution. The debug session IS the deviation record (more durable than a SUMMARY deviation section)."

# Metrics
duration: 2 sessions (2026-08-15 diagnostic + 2026-08-16 user-verify); this finalization SUMMARY written 2026-08-16
completed: 2026-08-16
commits:
  - 021e608 test(11-08): add phase11 GUI diagnostic + observation checklist
  - 6807dad fix(11-08): insert parent dir into sys.path for GUI run
  - a1f06c3 docs(11): debug session for alt-conf visibility regression (root cause + fix)
  - d65fb2c refactor(11): single-state cartoon/ribbon hider (new-chain copy, no alt-conf)
  - 8f3e274 test(11): single-state + NEW-resi smoke, on_pick fragment tests, render diagnostics
  - 548050c docs(11): debug session for single-state cartoon/ribbon hider refactor
  - 4c5b14b docs(11): record commit hashes + GUI human-verify checkpoint in debug session
  - 3b7d7b1 docs(11): mark single-state refactor debug session resolved (user-verified)
---

# Phase 11 Plan 08: GUI Human-Verify Checkpoint Summary

**User-verified single-state cartoon/ribbon hider in a real Windows PyMOL GUI on 1ubq -- all 6 success criteria PASS (checkpoint resolved 2026-08-16, 2 accepted caveats); closes the Phase 5 HIDER-03/HIDER-05 alt-conf gap**

## Performance

- **Duration:** 2 sessions (diagnostic written 2026-08-15; user-verify completed 2026-08-16). This finalization SUMMARY was written 2026-08-16 after merging exec/11 -> main.
- **Started:** 2026-08-15 (Task 1 diagnostic)
- **Completed:** 2026-08-16 (Task 2 user-verify checkpoint resolved)
- **Tasks:** 2 (Task 1 auto: GUI diagnostic script; Task 2 checkpoint:human-verify: user-verified)
- **Files modified:** 1 created (smoke/phase11_gui_diag.py) + 2 debug-session docs (committed during the debug sessions)

## Accomplishments

- **smoke/phase11_gui_diag.py written** (227 lines, pure `pymol.cmd.*` NO Qt): a GUI-runnable diagnostic the USER runs in a real Windows PyMOL session. It fetches 1ubq, collapses to single-state, builds 2 cartoon hiders via `game.GameController.start` (the refactored single-state path -> `insert_cartoon_segment_hider`), activates `PickWizard` so viewer clicks route to `GameController.on_pick` (prints "Found one!"/"Miss!" + recolors the bump), and prints a 9-step observation checklist covering all 6 Phase 11 success criteria + the 4 GUI-only failure modes. Exposes `diag_gc.cleanup()` (SC5) + `new_game()` (SC6) helpers for the PyMOL command line. Commit `021e608` + fix `6807dad` (insert parent dir into sys.path so `from biochemeleon import ...` resolves when run via PyMOL's `run` from the smoke/ dir).
- **Checkpoint RESOLVED -- user-verified 2026-08-16** (commit `3b7d7b1`): the user confirmed in a real Windows PyMOL GUI session on 1ubq that ALL 6 Phase 11 success criteria PASS. The single-state refactor WORKS -- cartoon/ribbon hiders render in a single-state object alongside sphere/stick; click-to-find loop works (chain H hider -> Found; real trace -> Miss). The KeyError from the prior alt-conf attempt is GONE. Two caveats were noted by the user and accepted (documented below). Debug session `.planning/debug/phase11-cartoon-hider-single-state-refactor.md` marked `status: resolved` with the full resolution text.
- **Phase 11 is COMPLETE.** The HIDER-03/HIDER-05 alt-conf gap from Phase 5 (terminal-extension cartoon rendered disconnected on 1ubq) is CLOSED by the single-state new-chain copy approach.

## Task Commits

Each task was committed atomically on the exec/11 worktree branch:

1. **Task 1: Write smoke/phase11_gui_diag.py** -- `021e608` (test) + `6807dad` (fix, sys.path for GUI run)
   - 227-line GUI-runnable diagnostic + 9-step observation checklist; pure pymol.cmd.* (NO Qt); activates PickWizard; exposes `diag_gc`/`diag_wizard`/`new_game()` helpers.
2. **Task 2: checkpoint:human-verify** -- `3b7d7b1` (docs, mark resolved)
   - User-verified 2026-08-16 in a real Windows PyMOL GUI session; all 6 success criteria PASS.

**Plan metadata:** this SUMMARY (`docs(11): complete...` commit) is written after the exec/11 -> main fast-forward merge.

## Files Created/Modified

- `smoke/phase11_gui_diag.py` (227 lines) -- Phase 11 GUI-runnable diagnostic. Loads 1ubq, collapses to single-state, builds 2 cartoon hiders via `game.GameController.start` (single-state `insert_cartoon_segment_hider` path), activates `PickWizard`, prints a 9-step observation checklist. Pure `pymol.cmd.*` (NO Qt); inserts parent dir into sys.path so `from biochemeleon import game, mutation, generators, PickWizard` resolves when run via PyMOL's `run` from the smoke/ dir.
- `.planning/debug/phase11-altconf-only-cartoon-hiders-visible.md` (commit `a1f06c3`) -- debug session for the alt-conf visibility regression (root cause: `cmd.create` REPLACES target state coords; fix: union-create; superseded by the single-state refactor).
- `.planning/debug/phase11-cartoon-hider-single-state-refactor.md` (commits `548050c` + `4c5b14b` + `3b7d7b1`) -- debug session for the single-state refactor (root cause: alt-conf design unnecessary + GUI-fragile; fix: new-chain single-state copy + NEW resi; verification: headless smoke 77/77 + unit tests 313/313 + GUI user-verify; status: resolved).

## Decisions Made

- **Single-state refactor eliminated the alt-conf/multi-state complexity.** The original Phase 11 plan (11-01 through 11-08) described an alt-conf design (alt='B', shared atom ids, multi-state `all_states` scaffolding). During execution, two debug sessions discovered this approach caused GUI-only visibility regressions (only cartoon rendered; multi-state `cmd.create` wiped original coords). The executor refactored to a single-state new-chain copy approach (`insert_cartoon_segment_hider`, `CARTOON_RESI_OFFSET=10000`, resv-range gate). This removed `all_states`/`is_first_altconf` from `game.py`, replaced the alt-gate with a resv-range gate in `on_pick`, and used `endpoint_resvs`-based fragment coloring in `_mark_found`. The 4-tuple payload in `__init__.py` is unchanged; only the commentary was updated. `registry.py` + `persistence.py` were untouched (alt-conf fields stay dormant; `is_altconf=False` for new hiders).
- **SS (secondary-structure) copy deferred.** The hider fragment does NOT inherit the parent's secondary structure (it renders as a loop, ss='L'). Accepted for now as future visual polish -- the fragment is visible + clickable; the cosmetic ss-mismatch is not a Phase 11 blocker. Consistent with the reverted commit 2715df5.
- **Bundled demo `KeyError: 'file'` out of scope.** Surfaced during the GUI test but CONFIRMED PRE-EXISTING on `main` (introduced by an earlier phase, NOT Phase 11). A separate debug file (`.planning/debug/bundled-demo-keyerror-file.md`, status: investigating) exists for a future fix. Phase 11 checkpoint considered PASSED with this caveat.
- **Verify against SUCCESS CRITERIA, not the stale must_haves.** The plan frontmatter `must_haves` describe the ORIGINAL alt-conf design (alt='B', shared ids, multi-state) and are STALE post-refactor. Verification was against the 6 outcome-based SUCCESS CRITERIA from ROADMAP.md, which are design-agnostic (connected render, ribbon, multi-hider, mixed-rep, cleanup, new-game).

## Deviations from Plan

### MAJOR mid-execution deviation: alt-conf -> single-state refactor

This is the load-bearing deviation for Plan 08 (and the whole of Phase 11). It is documented in detail in the debug session `.planning/debug/phase11-cartoon-hider-single-state-refactor.md` (status: resolved). Summary:

- **Found during:** GUI testing of the alt-conf implementation (only cartoon rendered; multi-state object; visibility regression vs main).
- **Issue:** The plan's alt-conf design (alt='B', shared atom ids, multi-state `all_states` scaffolding) caused GUI-only regressions that 4 fix cycles could not resolve (the 05-08 methodology failure). The deeper truth (verified headless via `smoke/diag_render_question.py`): cartoon/ribbon REQUIRES real backbone atoms to render -- a pseudoatom or pseudoatom-fragment on a NEW chain does NOT render (T2/T3/T4/T8 all BLANK). The alt-conf copies shared ids with originals, which the id-keyed registry cannot track without a scoring gate + KeyError risk.
- **Fix:** Refactor to a single-state new-chain copy (`insert_cartoon_segment_hider`): copy a REAL 3-residue backbone from the clean backup to a NEW chain 'H' + alt='' (NO alt-conf) + segi='GAME' + ss='L' + NEW resi (`CARTOON_RESI_OFFSET=10000` via `cartoon_hider_resi_range`), rigid-displace the middle, union-create merge into state 1 (preserves originals, single-state). New chain -> NEW atom ids -> id-keyed registry (like sphere/stick). `on_pick` uses a resv-range gate (NOT an alt gate); `_mark_found` uses `endpoint_resvs`-based fragment coloring. `game.py` dropped `all_states`/`is_first_altconf`; `registry.py` + `persistence.py` untouched (alt-conf fields dormant).
- **Files modified:** `biochemeleon/mutation.py` (insert_altconf_cartoon_hider -> insert_cartoon_segment_hider; CARTOON_RESI_OFFSET + cartoon_hider_resi_range helper; insert_hider_for_rep dispatch), `biochemeleon/game.py` (start/on_pick/_mark_found/cleanup/abort_on_error/import_state), `biochemeleon/__init__.py` (commentary), `smoke/phase11_smoke.py` (rewritten 77 checks), `tests/test_game_controller.py` (TestOnPickAltconf -> TestOnPickFragment).
- **Verification:** Headless smoke `phase11_smoke.py` 77/77 PASSED; unit tests 313/313 OK; GUI user-verified 2026-08-16 (all 6 success criteria).
- **Committed in:** `d65fb2c` (refactor), `8f3e274` (tests), `548050c`/`4c5b14b`/`3b7d7b1` (docs).

### Auto-fixed Issues

**1. [Rule 1 - Bug] phase11_gui_diag.py sys.path for GUI run**
- **Found during:** Task 1 (first GUI run of the diagnostic)
- **Issue:** When run via PyMOL's `run smoke/phase11_gui_diag.py`, the script's directory (smoke/) is added to sys.path, but `biochemeleon/` lives one level up -- `from biochemeleon import game, mutation, generators` failed.
- **Fix:** Insert the parent dir into sys.path at the top of the script (`_PARENT = os.path.dirname(_HERE); sys.path.insert(0, _PARENT)`).
- **Files modified:** smoke/phase11_gui_diag.py
- **Verification:** GUI run resolves the import; `6807dad`.

---

**Total deviations:** 1 MAJOR (alt-conf -> single-state refactor, documented in the debug session) + 1 auto-fixed (sys.path for GUI run).
**Impact on plan:** The single-state refactor is the correct design (user-verified); the plan's alt-conf must_haves are STALE and were superseded by the outcome-based SUCCESS CRITERIA. No scope creep -- the refactor closes the same HIDER-03/HIDER-05 gap the plan targeted.

## Issues Encountered

- The 05-08 methodology failure (headless smoke passing while GUI fails) was the central risk for this plan. It was resolved by the single-state refactor: by eliminating multi-state + alt-conf, the GUI-only failure modes (multi-state display, retroactive coord corruption) are IMPOSSIBLE by construction -- there is no multi-state to display and union-create preserves originals. The remaining GUI-only check (connected-bulge visual, auto-zoom, found-color on the bump) was verified by the user via the diagnostic.
- The bundled demo `KeyError: 'file'` surfaced during the GUI test but was confirmed pre-existing on `main` (out of scope; separate debug file).

## User Setup Required

None -- no external service configuration required. The GUI diagnostic runs in the user's existing Windows conda PyMOL environment (`setenv.bat` -> `pymol`). Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + the existing biochemeleon package. No `pip install`.

## Next Phase Readiness

- **Phase 11 is COMPLETE + VERIFIED.** The HIDER-03/HIDER-05 alt-conf gap from Phase 5 is CLOSED.
- **Next phases (incomplete, await user decision):**
  - **Phase 8** -- Plan 08-05 (the human-verify checkpoint for persistence/shareable puzzles) is STILL incomplete. STATE.md was stale; it claimed Phase 8 was in progress at the 08-05 checkpoint, and Phase 9/11 work proceeded afterward. Phase 8 Plan 08-05-SUMMARY.md does NOT exist (genuinely incomplete). Leave as-is -- do NOT mark Phase 8 complete.
  - **Phase 9** -- Plan 09-01 has a SUMMARY; Plans 09-02/03/04 are incomplete. Leave as-is.
  - **Phase 10** -- Not yet planned.
- **No blockers** for Phase 11. All WSL gates green (see 11-VERIFICATION.md). The single-state refactor is the shipped design; the alt-conf approach is abandoned (preserved in git history + debug sessions for reference).

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-16*
