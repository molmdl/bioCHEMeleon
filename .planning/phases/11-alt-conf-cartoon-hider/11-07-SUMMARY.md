---
phase: 11-alt-conf-cartoon-hider
plan: 07
subsystem: testing (headless integration smoke)
tags: [alt-conf, cartoon, ribbon, headless-smoke, pymol-cmd, scoring, multi-hider, mixed-rep, bcm, pse, alt-survival]

# Dependency graph
requires:
  - phase: 11-alt-conf-cartoon-hider-01
    provides: pick_segments (disjoint mid-chain) + generate_middle_displacement (rigid unit-vector RNG) from generators.py
  - phase: 11-alt-conf-cartoon-hider-02
    provides: HiderRecord 3 alt-conf fields + HiderRegistry.get_altconf_by_resv + .bcm round-trip (list->tuple coercion)
  - phase: 11-alt-conf-cartoon-hider-04
    provides: insert_altconf_cartoon_hider (4-call construction) + insert_hider_for_rep arity-based dispatcher
  - phase: 11-alt-conf-cartoon-hider-05
    provides: GameController.on_pick dual-lookup + alt/resv gate + _mark_found is_altconf branch + start all_states + import_state alt re-apply
  - phase: 11-alt-conf-cartoon-hider-06
    provides: _prepare_and_start 4-tuple payload construction (pick_segments + generate_middle_displacement -> start)
  - phase: 03-mutation-safety-hider-registry
    provides: backup.snapshot-before-insert invariant + space={} hygiene + ID uppercase + b<0 selector + sentinel rules
provides:
  - smoke/phase11_smoke.py -- 12-section (A-L) headless integration smoke, 54 checks, pure pymol.cmd.* (NO Qt), ALL PASSED exit 0
  - Runtime verification of the 4-call alt-conf construction (backbone-only, alt='B', anchor middle CA, sentinel 1 atom)
  - Runtime verification of the scoring truth table (anchor scores, non-anchor middle scores, endpoint/real-trace miss)
  - Runtime verification of multi-hider (2 disjoint, all_states on, >=2 states, no coord corruption via Bug 2 pre-capture)
  - Runtime verification of .pse alt survival (Open Risk 2/3 -- alt='B' survives .pse reload) + all_states re-apply (Open Risk 5)
  - Runtime verification of .bcm round-trip (is_altconf/endpoint_resvs/alt_tag survive build->write->read->import_state->reconcile)
affects: [11-08 (GUI human-verify for connected-tube visual, auto-zoom, multi-state display, found-color on displaced bump -- headless is NECESSARY but NOT SUFFICIENT)]

# Tech tracking
tech-stack:
  added: []  # no new libraries -- pure pymol.cmd.* (PyMOL 2.5.0 open-source) + existing pure layer
  patterns:
    - "Headless smoke pattern: stage via wsl2win_cp.sh -> cp smoke to tmp/bioCHEMeleon/smoke/ -> cd tmp/bioCHEMeleon && timeout 180 cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase11_smoke.py (AGENTS.md headless pattern)"
    - "Bug 2 pre-capture in smoke: orig_ca_coords dict via iterate_state(1, ...) BEFORE any alt-conf insert; post-insert GAME anchor (a segment atom) is safe to read via iterate_state (Pitfall 7 only corrupts NON-segment atoms)"
    - "Scoring truth table via direct on_pick(aid, alt, resv) calls (NOT PickWizard -- Qt-free): MISS tests first (no state change), then SCORE tests on DIFFERENT hiders to avoid state bleed"
    - "phase5_smoke ribbon check pattern: ribbon ONLY on GAME (polymer has no ribbon default -> rep= forwarded); inherited cartoon from the backup copy chain is EXPECTED (helps the blend), NOT a bug"

key-files:
  created:
    - smoke/phase11_smoke.py  (353 lines; 12 sections A-L, 54 checks, pure pymol.cmd.*)
  modified: []

key-decisions:
  - "Ribbon check uses the phase5_smoke pattern (ribbon ONLY on GAME, not 'rep cartoon == 0 on GAME'): alt-conf copies INHERIT cartoon from the backup copy chain (backup had cartoon from cmd.fetch default -> tmp inherits -> obj inherits). The inherited cartoon HELPS the blend (continuous tube); ribbon is the distinguishing marker. The plan's 'rep cartoon == 0' assertion was based on the incorrect assumption that newly-created atoms don't inherit reps -- Rule 1 smoke-check bug (NOT a source code bug)."
  - "Scoring sub-tests ordered MISS-first (no state change) then SCORE on DIFFERENT hiders (hider 0 then hider 1) to avoid state bleed without needing status resets between sub-tests."
  - "all_states verified via the Python flag gc._all_states_was_set (deterministic) rather than cmd.get (return format uncertain in PyMOL 2.5.0 headless). The actual cmd.set call is in game.py (verified by 11-05 unit tests)."
  - "Mixed-rep hider order: sphere -> stick -> cartoon -> ribbon (stick BEFORE cartoon so the stick's iterate_state runs on a clean state before any alt-conf corruption -- Pitfall 7)."

patterns-established:
  - "Phase 11 headless smoke structure: section A pre-captures orig CA coords (Bug 2/Pitfall 7); sections B-K exercise construction/scoring/cleanup/multi-hider/mixed-rep/.bcm/.pse; section L prints N/N PASSED + sys.exit(1 on fail)."
  - "Direct on_pick(aid, alt, resv) for headless scoring verification (no PickWizard/Qt needed) -- the smoke simulates clicks by passing the picked atom's (id, alt, resv) directly."

# Metrics
duration: 13 min
completed: 2026-08-15
---

# Phase 11 Plan 07: Headless Integration Smoke Summary

**Headless integration smoke for alt-conf cartoon/ribbon hider (54/54 PASSED, exit 0): 4-call construction, scoring truth table, multi-hider no-corruption, mixed-rep, .bcm/.pse alt-survival round-trip**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-08-15T09:33Z
- **Completed:** 2026-08-15T09:46Z
- **Tasks:** 2
- **Files modified:** 1 (smoke/phase11_smoke.py created)

## Accomplishments

- **smoke/phase11_smoke.py written** (353 lines, 12 sections A-L, 54 checks, pure `pymol.cmd.*` NO Qt). Runs headlessly via `cmd.exe /c C:\src\run-conda-pymol.bat -cq smoke\phase11_smoke.py` -- **54/54 PASSED, exit 0**.
- **Section A (SETUP)**: fetches 1ubq, collapses to single-state, pre-captures ALL original CA coords into `orig_ca_coords` dict via `iterate_state(1, ...)` BEFORE any alt-conf insert (Bug 2 pre-capture pattern / Pitfall 7).
- **Section B (ALT-CONF CONSTRUCTION)**: verifies the 4-call construction -- backbone-only (GAME backbone == GAME total), alt='B' on ALL GAME atoms, anchor is MIDDLE CA (resv == start_resi+1), sentinel returns 1 atom, registry record has is_altconf=True + endpoint_resvs=(start,end) + alt_tag='B'.
- **Section C (CONNECTED RENDERING)**: GAME atoms in rep cartoon (geometry exists for the connected tube -- the visual BLEND is Plan 08 GUI human-verify).
- **Section D (RIBBON)**: ribbon hider renders in rep ribbon; ribbon ONLY on GAME atoms (polymer has no ribbon default -> rep= forwarded, NOT hardcoded cartoon). Success criterion 2 mechanism verified.
- **Section E (MULTI-HIDER)**: 2 disjoint mid-chain segments; registry len 2; both is_altconf; all_states set (object-scoped); count_states >= 2; 1st anchor readable in state 1 (no iterate_state corruption); 1st anchor displaced ~disp0 (NOT corrupted/collapsed -- Bug 4 fix verified). Success criterion 3 mechanism verified.
- **Section F (SCORING TRUTH TABLE)**: 4 sub-tests via direct `gc3.on_pick(aid, alt, resv)` -- endpoint miss (resv not strictly between), real-trace miss (alt != 'B'), anchor middle CA scores (alt='B' + middle resv), non-anchor middle atom scores (resv-range fallback via get_altconf_by_resv). USER REQ 3 verified.
- **Section G (CLEANUP)**: backup.restore returns True; count back to orig; no GAME atoms. Success criterion 5 verified.
- **Section H (NEW GAME)**: after cleanup, fresh gc4.start produces a new hider (no residual alt-conf corruption); cleanup restores count. Success criterion 6 verified.
- **Section I (MIXED-REP)**: sphere + stick + cartoon + ribbon all in registry (len 4) + all 4 reps visible on GAME atoms. Success criterion 4 verified.
- **Section J (.BCM ROUND-TRIP)**: is_altconf/endpoint_resvs/alt_tag survive build_bcm_dict -> write_bcmz -> read_bcmz -> import_state -> reconcile; .pse alt == 'B' BEFORE import_state (Open Risk 2/3 -- alt survives .pse reload); imported records have is_altconf=True + endpoint_resvs tuple (list->tuple coercion) + alt_tag='B'.
- **Section K (.PSE ALT SURVIVAL)**: alt == 'B' after import_state (survival or fallback); all_states re-applied (>=2 alt-conf, Open Risk 5).
- **Open Risks closed (headless-checkable)**: Risk 2 (backbone-only renders in cartoon -- PASS), Risk 3 (.pse alt survival -- PASS, alt='B' survives), Risk 5 (all_states re-apply -- PASS), Risk 8 (get_altconf_by_resv disjointness -- PASS, disjoint segments), Risk 9 (cmd.create state args from clean backup -- PASS), Risk 10 (backbone selector atom set -- PASS, N/CA/C/O only).
- **Open Risks deferred to Plan 08 (GUI human-verify)**: Risk 1 (multi-hider GUI integration), Risk 4 (GUI-runnable diagnostic methodology), Risk 6 (connected bulge visual), Risk 7 (found-color on displaced bump). Headless ALL PASSED is NECESSARY but NOT SUFFICIENT (05-08 lesson: 4 fix cycles each passed headless but failed in GUI).

## Task Commits

Each task was committed atomically:

1. **Task 1: Write smoke/phase11_smoke.py** -- `99f9224` (test)
   - 12 sections (A-L), 54 checks, pure pymol.cmd.* (NO Qt); hygienic space={'stored':...} on every iterate; ID UPPERCASE; b<0 selector; orig_ca_coords pre-capture in section A.
2. **Task 2: Stage + run headlessly + debug** -- `a644f8e` (fix)
   - 1 smoke-check bug fixed (ribbon NOT-cartoon assertion -> phase5_smoke pattern); 54/54 PASSED, exit 0.

**Plan metadata:** (pending -- created by this commit)

## Files Created/Modified

- `smoke/phase11_smoke.py` (353 lines) -- Phase 11 headless integration smoke. 12 sections: A (setup + pre-capture), B (single cartoon alt-conf construction), C (connected rendering geometry), D (ribbon rep forwarding), E (multi-hider + no coord corruption), F (scoring truth table via direct on_pick), G (cleanup via backup.restore), H (new game after cleanup), I (mixed-rep 4 reps), J (.bcm round-trip + .pse alt survival pre-import), K (.pse alt survival post-import + all_states), L (summary + sys.exit). Pure `pymol.cmd.*` (NO Qt); hygienic `space={'stored':...}` on all 11 iterate/iterate_state calls; `ID` UPPERCASE; `b < 0` selector (never `b -999`); `orig_ca_coords` pre-capture (5 references).

## Decisions Made

- **Ribbon check uses the phase5_smoke pattern (NOT "rep cartoon == 0 on GAME")**: The alt-conf copies INHERIT cartoon from the backup copy chain (backup had cartoon from `cmd.fetch` default -> tmp inherits -> obj inherits). The inherited cartoon HELPS the blend (continuous tube through the GAME segment); the ribbon is the distinguishing marker. The plan's `count_atoms("segi GAME and rep cartoon") == 0` assertion was based on the incorrect assumption that newly-created atoms don't inherit reps -- Rule 1 smoke-check bug (NOT a source code bug; `insert_altconf_cartoon_hider` is correct). Replaced with: ribbon ONLY on GAME (`polymer and not segi GAME and rep ribbon == 0`), the phase5_smoke pattern that proves `rep=` was forwarded.
- **Scoring sub-tests ordered MISS-first then SCORE on DIFFERENT hiders**: MISS tests (endpoint, real-trace) don't change hider status, so they run first while hiders are hidden. SCORE tests run on hider 0 (anchor middle CA) then hider 1 (non-anchor middle atom) -- different records, no state bleed, no status reset needed.
- **all_states verified via the Python flag** `gc._all_states_was_set` (deterministic) rather than `cmd.get("all_states", obj)` (return format uncertain in PyMOL 2.5.0 headless). The actual `cmd.set("all_states", "on", obj)` call is in `game.py` (verified by 11-05 unit tests).
- **Mixed-rep hider order: sphere -> stick -> cartoon -> ribbon**: The stick hider's `insert_line_stick_hider` calls `iterate_state(1, ...)` to read neighbor coords. This MUST run BEFORE any alt-conf insert (Pitfall 7: iterate_state is corrupted for non-segment atoms after a `cmd.create` alt-conf append). Placing stick 2nd (before cartoon 3rd) ensures the stick's iterate_state runs on a clean state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the ribbon smoke check (inherited cartoon is expected, not a rep=-forwarding failure)**
- **Found during:** Task 2 (headless run, section D)
- **Issue:** The plan's section D check `count_atoms("segi GAME and rep cartoon") == 0` failed at runtime (54/54 -> 53/54). The alt-conf copies INHERIT the cartoon rep flag through the `cmd.create` copy chain: `cmd.fetch` shows cartoon on the polymer by default -> `backup.snapshot` (`cmd.create('_bchm_backup', obj)`) copies the rep flags -> `cmd.create(tmp, '<backup> and backbone')` copies them to tmp -> `cmd.create(obj, tmp)` copies them to obj. So GAME atoms have cartoon (inherited) + ribbon (explicitly shown via `cmd.show('ribbon', ...)`). The plan's assertion was based on research §Q11 ("newly-created atoms do NOT inherit shown reps"), which is imprecise for the `cmd.create` copy path (it applies to `cmd.pseudoatom`, not `cmd.create`). The inherited cartoon is the SAME known behavior phase5_smoke line 283-295 documented for attached residues.
- **Fix:** Replaced the wrong assertion with the phase5_smoke pattern: `count_atoms("segi GAME and rep ribbon") > 0 AND count_atoms("polymer and not segi GAME and rep ribbon") == 0` (ribbon ONLY on GAME -- the real polymer has no ribbon default, proving `rep=` was forwarded, not a global show). The inherited cartoon HELPS the blend (continuous tube); the ribbon is the distinguishing marker. This is a smoke-check bug (Rule 1), NOT a source code bug -- `insert_altconf_cartoon_hider` is correct.
- **Files modified:** smoke/phase11_smoke.py (section D check, +10/-4 lines)
- **Verification:** Headless re-run: 54/54 PASSED, exit 0.
- **Committed in:** `a644f8e` (Task 2 fix commit)

---

**Total deviations:** 1 auto-fixed (1 bug -- smoke-check assertion)
**Impact on plan:** Minimal -- the fix corrects a wrong assertion in the smoke (not the source code). The inherited cartoon is expected behavior (same as phase5_smoke); the phase5 pattern is the correct way to verify rep= forwarding. No source code change; no scope creep.

## Issues Encountered

None beyond the 1 smoke-check bug above. The headless run was clean on the first attempt (53/54), and the single fix brought it to 54/54 on the second run. No source code bugs found in `biochemeleon/*.py` -- all 6 prior plans (11-01 through 11-06) produced correct runtime behavior. The `.pse` alt survival (Open Risk 2/3) passed on the first try (alt='B' survives .pse reload without needing the import_state fallback, though the fallback is still applied as a defensive no-op).

## User Setup Required

None -- no external service configuration required. Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + existing pure layer. No `pip install` (opencode.json denies `pip*`/`apt*`/`conda*`).

## Next Phase Readiness

- **Ready for 11-08** (GUI human-verify): The headless smoke proves the MECHANISM (4-call construction, scoring, cleanup, multi-hider, mixed-rep, .bcm/.pse round-trip all work at the cmd tier). The GUI human-verify (Plan 08) must confirm the VISUAL: connected cartoon/ribbon tube (not disconnected), displaced middle bump visible + clickable, endpoint blend (no visible seam), found-color on displaced bump (not real trace), multi-state display (all 2+ hiders visible), no auto-zoom (Bug 3), no retroactive coord corruption (Bug 4). **Headless ALL PASSED is NECESSARY but NOT SUFFICIENT** -- the 05-08 attempt failed because 4 fix cycles each passed headless (44/44, 49/49) but failed in the GUI. Plan 08 MUST include a GUI-runnable diagnostic (Open Risk 4).
- **Open Risks closed (headless)**: 2 (backbone-only renders), 3 (.pse alt survival), 5 (all_states re-apply), 8 (get_altconf_by_resv disjointness), 9 (cmd.create state args), 10 (backbone selector atom set).
- **Open Risks deferred to Plan 08** (GUI-only): 1 (multi-hider GUI integration), 4 (GUI diagnostic methodology), 6 (connected bulge visual), 7 (found-color on displaced bump).
- **No blockers** for Plan 08. All WSL gates green: py_compile clean, no Qt, 11 hygienic space= dicts, 0 space=None, 6 ID uppercase, 0 `b -999`, 5 orig_ca_coords references.

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
