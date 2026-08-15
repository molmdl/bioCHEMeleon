---
phase: 11-alt-conf-cartoon-hider
plan: 06
subsystem: gui-composition-root
tags: [pymol, alt-conf, cartoon, ribbon, gui, init, prepare-and-start, 4-tuple, composition-root]

# Dependency graph
requires:
  - phase: 11-alt-conf-cartoon-hider-01
    provides: pick_segments (disjoint mid-chain segment picker) + generate_middle_displacement (rigid unit-vector RNG) from generators.py (Wave 1, pure layer)
  - phase: 11-alt-conf-cartoon-hider-04
    provides: insert_altconf_cartoon_hider (4-call construction) + insert_hider_for_rep arity-based dispatcher (4-tuple -> alt-conf; 3-tuple -> legacy)
  - phase: 11-alt-conf-cartoon-hider-05
    provides: GameController.start accepts 4-tuple payloads + passes backup_name/is_first_altconf to the dispatcher + registers is_altconf/endpoint_resvs/alt_tag + object-scoped all_states
  - phase: 04-gui-game-loop
    provides: _prepare_and_start skeleton (resolve target -> collapse -> build hider_specs -> start) + per_rep loop + cas_by_chain construction
  - phase: 05-cartoon-hider
    provides: legacy pick_terminal_residues 3-tuple cartoon/ribbon branch (now replaced) + free_nterminal_valence (now dropped from the call site)
provides:
  - _prepare_and_start builds 4-tuple (chain, start_resi, end_resi, displacement_vec) cartoon/ribbon payloads via pick_segments + generate_middle_displacement (replaces the Phase 5 terminal-extension 3-tuple path)
  - Under-generation warning reflects disjoint mid-chain segment availability (Bug 1 fix context), not one-per-chain terminal cap
  - cas_list capture-before-insert Bug 2 comment (alt-conf construction reads from the backup temp, not the live object)
  - free_nterminal_valence no longer called by _prepare_and_start (alt-conf copies a backbone segment from the backup, does not attach at a terminus)
affects: [11-07 (headless smoke exercises the full alt-conf lifecycle), 11-08 (GUI human-verify for the Start button producing alt-conf hiders)]

# Tech tracking
tech-stack:
  added: []  # no new libraries -- pure pymol.cmd.* + existing pure layer
  patterns:
    - "Composition-root wiring: pure generators (pick_segments + generate_middle_displacement) -> 4-tuple payloads -> dispatcher (11-04) -> start (11-05). The GUI _prepare_and_start is the thin adapter that converts per_rep counts into rep-specific payloads."
    - "cas_by_chain shape reuse: pick_segments consumes the SAME {chain: [(resi, ca_id), ...]} dict that pick_terminal_residues consumed -- zero change to the cas_by_chain construction (only the cartoon/ribbon branch body changed)."
    - "Bug 2 pre-capture: cas_list iterate runs BEFORE gc.start (the insert loop) so alt-conf construction reads from the clean backup temp, not the live object (documented inline)."

key-files:
  created: []
  modified:
    - biochemeleon/__init__.py

key-decisions:
  - "4-tuple payload shape ((chain, start_resi, end_resi, displacement_vec), rep) verified against the 11-04 dispatcher (mutation.py:648: chain, start_resi, end_resi, displacement_vec = payload) AND 11-05 start (game.py:79: _chain, start_resi, end_resi, _disp = payload) BEFORE editing -- exact match, zero ambiguity."
  - "Kept cas_by_chain construction unchanged (pick_segments consumes the same {chain: [(resi, ca_id), ...]} shape as pick_terminal_residues) -- only the cartoon/ribbon branch body + the header comment changed."
  - "Under-generation warning rewritten for disjoint mid-chain segment availability (Bug 1 fix context) -- the old one-per-chain terminal-cap warning was Phase 5 Open Risk 5 specific, no longer applicable."
  - "Removed free_nterminal_valence from the call site (alt-conf copies a backbone segment from the backup, does not attach at a terminus, so no N-terminal valence needs freeing). Kept collapse_to_single_state (NMR ensembles still need it) + the mutation import + free_nterminal_valence in mutation.py (utility kept per the plan)."
  - "Updated the stale '# For cartoon: terminal C-alpha per chain (extend-at-terminus)' header comment to reflect Phase 11 mid-chain segments (the plan said keep the construction unchanged; the comment was factually wrong after Phase 11 -- Rule 1 doc-correctness fix) AND added the Bug 2 pre-capture one-line comment per the plan."

patterns-established:
  - "_prepare_and_start cartoon/ribbon branch: pick_segments(cas_by_chain, count) -> segments; generate_middle_displacement(len(segments)) -> disps; zip -> 4-tuple payloads. The canonical Phase 11 GUI payload construction consumed by the 11-04 dispatcher + 11-05 start."
  - "free_nterminal_valence is NOT called by _prepare_and_start (Phase 11); it remains in mutation.py as a utility. The N-terminal valence is freed by alt-conf copying a backbone segment from the backup (no terminus attachment)."

# Metrics
duration: 5 min
completed: 2026-08-15
---

# Phase 11 Plan 06: Init Prepare-and-start Alt-conf Wiring Summary

**_prepare_and_start builds 4-tuple alt-conf cartoon/ribbon payloads via pick_segments + generate_middle_displacement (replacing the Phase 5 terminal-extension 3-tuple path) and drops the free_nterminal_valence call (alt-conf copies a backbone segment from the backup, no terminus attachment)**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-08-15T09:26:03Z
- **Completed:** 2026-08-15T09:31:39Z
- **Tasks:** 2
- **Files modified:** 1 (biochemeleon/__init__.py)

## Accomplishments

- `_prepare_and_start` cartoon/ribbon branch now builds 4-tuple `(chain, start_resi, end_resi, displacement_vec)` payloads via `pick_segments` (disjoint mid-chain segments, Bug 1 fix) + `generate_middle_displacement` (rigid unit-vector displacement). The 4-tuple routes to `insert_altconf_cartoon_hider` via the 11-04 dispatcher (`len(payload) == 4`) and `start` (11-05) registers `is_altconf`/`endpoint_resvs`/`alt_tag`.
- Under-generation warning rewritten for disjoint mid-chain segment availability (e.g. "Requested 5 cartoon hiders but only 2 disjoint mid-chain segments available; 2 hiders generated (cartoon/ribbon hiders need a >=3-residue mid-chain segment per hider).") -- replaces the Phase 5 one-per-chain terminal-cap warning.
- `cas_list` capture-before-insert Bug 2 comment added above the `cmd.iterate` (alt-conf construction reads from the backup temp, not the live object).
- `free_nterminal_valence` call loop REMOVED (alt-conf hiders copy a backbone segment from the clean backup via `insert_altconf_cartoon_hider`, they do NOT attach at a terminus, so the N-terminal valence does NOT need freeing). `collapse_to_single_state` + the `mutation` import + `free_nterminal_valence` in `mutation.py` all kept.
- All WSL gates green: `py_compile` all modules; 313 pure-layer tests (5 modules) pass (no regression); Pitfall-1=0; exec_ gate intact (1 existing QMessageBox child dialog in `gui_game.py`; main dialog stays modeless via `dialog.show()`).

## Task Commits

Each task was committed atomically:

1. **Task 1: _prepare_and_start builds alt-conf 4-tuple cartoon/ribbon payloads** -- `04e50e9` (feat)
2. **Task 2: drop free_nterminal_valence for alt-conf cartoon/ribbon** -- `b7fea72` (refactor)

**Plan metadata:** (pending -- created by this commit)

## Files Created/Modified

- `biochemeleon/__init__.py` -- `_prepare_and_start` cartoon/ribbon branch replaced (`pick_terminal_residues` 3-tuple -> `pick_segments` + `generate_middle_displacement` 4-tuple); under-generation warning rewritten for disjoint mid-chain segments; `cas_list` Bug 2 pre-capture comment added; `free_nterminal_valence` call loop removed (replaced with a Phase 11 explanatory comment); 2 comments reworded to clear the `free_nterminal_valence` grep gate (Rule 3 blocking); the stale "# For cartoon: terminal C-alpha per chain (extend-at-terminus)" header comment updated to reflect Phase 11 mid-chain segments (Rule 1 doc-correctness).

## Decisions Made

- **4-tuple payload shape verified against consumers BEFORE editing:** `(chain, start_resi, end_resi, displacement_vec)` matches the 11-04 dispatcher (`mutation.py:648`: `chain, start_resi, end_resi, displacement_vec = payload`) and 11-05 start (`game.py:79`: `_chain, start_resi, end_resi, _disp = payload`) exactly. Zero ambiguity -- the GUI builds the exact shape the dispatcher + orchestrator consume.
- **Kept `cas_by_chain` construction unchanged:** `pick_segments` consumes the same `{chain: [(resi, ca_id), ...]}` shape as `pick_terminal_residues` (11-01 SUMMARY contract). Only the cartoon/ribbon branch body + the header comment changed; the `cmd.iterate` + the `for chain, resi, ca_id in cas_list` loop are untouched.
- **Updated the stale "# For cartoon: terminal C-alpha per chain (extend-at-terminus)" header comment:** The plan said keep the construction unchanged, but the comment was factually wrong after Phase 11 replaced terminal-extension with mid-chain segments. Updated to "For cartoon/ribbon: per-chain C-alpha (resi, id) list. Phase 11 pick_segments consumes this for mid-chain segments (replacing the Phase 5 terminal-extension path)." (Rule 1 doc-correctness.)
- **Removed `free_nterminal_valence` from the call site but kept it in `mutation.py` as a utility:** Per the plan: "Do NOT remove free_nterminal_valence from mutation.py -- it stays as a utility; just not called here." `collapse_to_single_state` (line 158) + the `mutation` import (line 107) both retained (collapse is still needed for NMR ensembles; mutation is still used for collapse).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded 2 comments to remove the literal `free_nterminal_valence` token (the plan's own Task 2 verification gate expects grep=0)**
- **Found during:** Task 2 (verification gate)
- **Issue:** The plan's Task 2 verification requires `grep -nE "free_nterminal_valence" biochemeleon/__init__.py (0 -- removed from call site)`. But TWO comments in `__init__.py` contained the literal `free_nterminal_valence` token (neither is a call site): (a) the plan's OWN replacement comment ("so free_nterminal_valence is NOT needed") at line 238, and (b) a pre-existing comment in the `neighbor_ids` block ("CA atoms survive free_nterminal_valence removal") at line 168. `grep -nE` counts literal occurrences regardless of context (the AGENTS.md-documented false-positive pattern: "literal tokens in comments/docstrings trip this grep too"), so the gate would return 2 matches instead of 0.
- **Fix:** Reworded both comments to preserve the semantics without the literal token:
  - Line 238 (plan's replacement comment): "so free_nterminal_valence is NOT needed" -> "so the N-terminal valence does NOT need freeing"
  - Line 168 (pre-existing `neighbor_ids` comment): "CA atoms survive free_nterminal_valence removal (which only removes H + cap residue atoms)" -> "CA atoms are stable backbone atoms and valid bond targets for insert_line_stick_hider (05-07 fix: non-CA atoms could be removed by a terminal-valence step before insert, causing IndexError on nbr[0]; Phase 11 alt-conf path no longer runs that step, but 'name CA' remains the correct pool.)" -- the pre-existing rationale was also stale (Phase 11 no longer calls the terminal-valence step), so this is a combined Rule 3 + Rule 1 fix.
- **Files modified:** biochemeleon/__init__.py
- **Verification:** `grep -nE "free_nterminal_valence" biochemeleon/__init__.py` -> exit 1 (0 matches = PASS). `collapse_to_single_state` + `mutation` import + `free_nterminal_valence` in `mutation.py` (line 695) all still present.
- **Committed in:** `b7fea72` (Task 2 commit)

**2. [Rule 1 - Bug] Updated the stale "# For cartoon: terminal C-alpha per chain (extend-at-terminus)" header comment**
- **Found during:** Task 1 (cas_list comment block)
- **Issue:** The plan said "Keep the cas_by_chain construction UNCHANGED" and "Add a one-line comment above the cas_list iterate". The header comment "# For cartoon: terminal C-alpha per chain (extend-at-terminus)." was factually wrong after Phase 11 replaced terminal-extension with mid-chain segments -- leaving it would mislead future readers. (The plan's "UNCHANGED" referred to the code logic, not the now-false descriptive comment.)
- **Fix:** Updated to "# For cartoon/ribbon: per-chain C-alpha (resi, id) list. Phase 11 pick_segments consumes this for mid-chain segments (replacing the Phase 5 terminal-extension path)." + added the Bug 2 pre-capture comment per the plan.
- **Files modified:** biochemeleon/__init__.py
- **Verification:** py_compile clean; the comment now accurately describes Phase 11 mid-chain usage; the Bug 2 comment is present (line 183).
- **Committed in:** `04e50e9` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking -- grep gate literal-token rewording; 1 bug -- stale doc-correctness)
**Impact on plan:** Minimal -- both fixes preserve the original semantics. The grep-gate rewording mirrors the established repo precedent (03-02/03-06/03-09/03-10/04-04/11-04/11-05 all reworded docstrings/comments to clear grep gates; AGENTS.md documents this pattern). The stale-comment update keeps the code honest per the repo's "Code must be efficient, traceable, clean" standard. No code-behavior change; no scope creep.

## Issues Encountered

None -- both tasks went smoothly. The one subtle point (the plan's own replacement comment containing the literal `free_nterminal_valence` token that the plan's verification gate expected to be 0) was resolved by rewording the comment (Rule 3 blocking; mirrors 11-04/11-05 precedent). No debugging iterations needed.

## User Setup Required

None -- no external service configuration required. Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + existing pure layer. No `pip install` (opencode.json denies `pip*`/`apt*`/`conda*`).

## Next Phase Readiness

- **Ready for 11-07** (headless smoke): `_prepare_and_start` now produces 4-tuple alt-conf payloads. The smoke can exercise the full GUI payload-construction path (resolve target -> `pick_segments` + `generate_middle_displacement` -> `start` -> `insert_altconf_cartoon_hider`) OR call `start` directly with 4-tuple specs. The `cas_list` Bug 2 pre-capture is documented inline.
- **Ready for 11-08** (GUI human-verify): the Start button now produces alt-conf cartoon/ribbon hiders (4-tuple payloads -> `insert_altconf_cartoon_hider` -> connected bulge visual). The human-verify checkpoint validates the connected cartoon/ribbon tube, displaced middle bump, endpoint blend, multi-state display (>=2 alt-conf hiders via 11-05 `all_states=on`), no auto-zoom (11-04 `zoom=0`), and no retroactive coord corruption (11-04 `target_state=-1` for 2nd+ alt-conf).
- **No blockers.** Qt+cmd-coupled (the Start button is Qt; `_prepare_and_start` uses `cmd.iterate` for `cas_list`) -- runtime deferred to 11-07 (headless smoke for the cmd path) + 11-08 (GUI human-verify for the Start button visual). This plan only ran `py_compile` + grep gates per the plan. All WSL gates green: 313 tests (35 game-controller + 94 registry + 90 setup_state + 21 generators + 50 persistence + 23 other), py_compile all, Pitfall-1=0, exec_ gate intact (1 existing QMessageBox child dialog; main dialog modeless via `dialog.show()`).

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
