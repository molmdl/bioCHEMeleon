---
phase: quick-006
plan: 01
subsystem: gameplay
tags: [pymol, hider-neighbor-pool, stick-hider, sidechain, selector, headless-smoke]

# Dependency graph
requires:
  - phase: 05 (line/stick hider insertion)
    provides: insert_line_stick_hider(neighbor_id=...) — bonds to an arbitrary atom id, copies elem/color via iterate_state for blend
  - phase: 11 (single-state new-chain copy refactor)
    provides: elimination of the legacy terminal-valence step that forced the backbone-only neighbor pool
provides:
  - Line/stick hider neighbor pool widened from backbone-only (name CA or name P) to ALL heavy atoms (not elem H), so stick hiders can land on side-chain atoms where cartoon/ribbon don't obscure them
  - phase5_smoke.py section 7 — headless regression guard proving a CB (side-chain) heavy atom works as a stick-hider neighbor end-to-end
affects: [gameplay-tuning, stick-hider-placement, future-quick-tasks]

# Tech tracking
tech-stack:
  added: []  # no new libs — pure selector change
  patterns:
    - "Two DISTINCT neighbor pools in __init__.py: line/stick (not elem H, all heavy atoms) vs cartoon/ribbon (polymer and (name CA or name P), backbone trace only) — kept separate because cartoon/ribbon render through the CA/P trace"

key-files:
  created: []
  modified:
    - pymol/biochemeleon/__init__.py  # line/stick neighbor pool selector + rationale comment (line ~382-397); cartoon/ribbon pool at line ~412 UNCHANGED
    - pymol/smoke/phase5_smoke.py     # new section 7 (side-chain CB neighbor) + re-fetch, insert, sentinel, bond, blend, cleanup checks

key-decisions:
  - "Selector 'not elem H' (not a positive side-chain list): minimal, complete, representationally-correct superset of the old 'name CA or name P' pool for both protein and nucleic acid; needs no maintenance as residue side-chain atom sets vary"
  - "No 'polymer' filter on the line/stick pool (mirrors the old pool — ligand heavy atoms are valid stick bond targets too)"
  - "Cartoon/ribbon pool left UNCHANGED (polymer and (name CA or name P)) — cartoon/ribbon draw through the backbone CA/P trace, so copied segments must come from CA/P"
  - "No mutation.py functional change — insert_line_stick_hider already handles arbitrary neighbor_id (reads elem/color via iterate_state, copies for blend)"

patterns-established:
  - "Quick-task verification = headless smoke (cmd-coupled tier) is authoritative; pure unit tests guard the import surface; py_compile + pitfall-1 + exec_ gates guard syntax/hygiene"

# Metrics
duration: ~20min
completed: 2026-08-22
---

# Quick Task 006: Stick Hider Side-Chain Neighbors Summary

**Widened the line/stick hider neighbor pool from backbone-only (name CA or name P) to all heavy atoms (not elem H), so stick hiders land on side-chain atoms where cartoon/ribbon don't obscure them — headless smoke 48/48 ALL PASSED with a new CB-neighbor section.**

## Performance

- **Duration:** ~20 min (resumed session)
- **Completed:** 2026-08-22
- **Tasks:** 2 (shipped as a single atomic code commit per the plan — the smoke IS the verification for the code change)
- **Files modified:** 2

## Accomplishments
- Line/stick neighbor pool selector changed from `"%s and not segi GAME and (name CA or name P)"` to `"%s and not segi GAME and not elem H"` in `__init__.py`, with a rewritten rationale comment documenting the quick-006 fix (Phase 11 removed the terminal-valence step that forced backbone-only; side-chain heavy atoms are stable bond targets).
- Cartoon/ribbon pool at `__init__.py` line ~412 (`polymer and (name CA or name P)`) verified UNCHANGED — cartoon/ribbon render through the backbone CA/P trace.
- Added `phase5_smoke.py` section 7: re-fetches 1ubq, picks a CB (side-chain, non-backbone) heavy atom as the stick-hider neighbor, and proves insert returns an int id; sentinel (segi=GAME, b=-999) is set; the hider is bonded to the side-chain neighbor; color blends (hider color == neighbor color); cleanup restores the original count and leaves no GAME atoms.
- Headless smoke via the Windows PyMOL bridge: **48/48 passed, ALL PASSED, exit 0**. Diag confirmed `sc_neighbor_id=5 (CB)` (NOT the backbone CA id=2 from section 2) and `sc_nbr_col=[10] sc_hdr_col=[10]` (blend confirmed).
- All six verification gates green: py_compile (3 files), pitfall-1 gate (ZERO matches), exec_ gate (only child-dialog hits, baseline), pure unit tests (125 OK), both pools distinct (line/stick widened / cartoon/ribbon untouched), headless smoke (ALL PASSED).

## Task Commits

Per the plan's `<verification>` section, the two tasks shipped as a **single atomic commit** (the smoke IS the verification for the code change, so they ship together):

1. **Task 1 + Task 2: widen line/stick pool + add side-chain smoke section** - `b8fb430` (fix)

**Plan metadata:** `docs(quick-006): complete stick-sidechain-neighbors plan` (this commit — plan + summary; STATE.md intentionally NOT updated per quick-task constraint; the orchestrator handles STATE.md after merge)

## Files Created/Modified
- `pymol/biochemeleon/__init__.py` - Line/stick neighbor pool selector widened to `not elem H` (all heavy atoms) + rewritten rationale comment. Cartoon/ribbon pool (`polymer and (name CA or name P)`) untouched.
- `pymol/smoke/phase5_smoke.py` - New section 7 (SIDE-CHAIN NEIGHBOR POOL): re-fetch 1ubq, pick a CB side-chain heavy atom, prove insert + sentinel + bond + blend + cleanup. Section 2 (backbone-CA neighbor) kept as a regression guard.

## Decisions Made
- **Selector `not elem H` (not a positive side-chain list):** a positive list (e.g. `name CB or name CG or ...`) would be incomplete (different residue types have different side-chain atoms) and would need maintenance. `not elem H` is the minimal, complete, representationally-correct selector for "all heavy atoms" and is a strict superset of the old `name CA or name P` pool for both protein and nucleic acid.
- **No `polymer` filter on the line/stick pool:** mirrors the old pool (which also had none) — ligand heavy atoms are valid stick bond targets too.
- **Cartoon/ribbon pool left UNCHANGED:** cartoon/ribbon render through the backbone CA/P trace, so a copied backbone segment must come from CA/P. Two DISTINCT pools are intentional.
- **No `mutation.py` change:** `insert_line_stick_hider` already bonds to any `neighbor_id` and copies the neighbor's elem/color for blending (lines 212-249). The stale `free_nterminal_valence` reference in its ValueError message (line ~224) is out of scope for this quick task — candidate for a future quick task (see Next Phase Readiness).

## Deviations from Plan

None - plan executed exactly as written.

Minor note (not a deviation): the plan's success criteria said "6 new PASS checks" but section 7 actually contains 7 `check()` calls (the `sidechain: 1ubq has CB atoms (side-chain pool non-empty)` guard is a 7th). All 7 pass. The section 7 code block was inserted verbatim from the plan.

## Issues Encountered
None. The headless smoke ran clean on the first attempt (48/48, exit 0). The `wsl2win_cp.sh` dest-dir edge case (cp creates the package contents at top level instead of a `biochemeleon/` subdir when the dest doesn't exist) was handled by `mkdir -p tmp/bioCHEMeleon` before running the script — staging laid out correctly (`tmp/bioCHEMeleon/biochemeleon/` + `tmp/bioCHEMeleon/smoke/phase5_smoke.py`).

## User Setup Required
None - no external service configuration required. This is a pure in-process selector change verified headlessly via the existing Windows PyMOL bridge.

## Next Phase Readiness
- Quick-006 complete; the widened pool is live for the line/stick rep. Cartoon/ribbon backbone pool intentionally unchanged.
- **Known tech debt (candidate for a future quick task):** the stale `free_nterminal_valence` reference in `mutation.py` line ~224's ValueError message ("ensure neighbor_ids are sampled from 'name CA' atoms that survive free_nterminal_valence") is now misleading — Phase 11 eliminated that step and quick-006 widened the pool beyond `name CA`. The message text is out of scope here (no functional impact — it's an error-path string only), but should be updated in a future quick task to reflect the current `not elem H` pool and the absence of the terminal-valence step.
- The visual BLEND on a side-chain neighbor under cartoon remains a human-verify checkpoint (the headless smoke proves the MECHANISM — atoms insert, sentinel set, bond formed, color copied, cleanup restores; a human confirms the blend is visually convincing). Not blocking; the mechanism is identical to the backbone-neighbor path already human-verified in Phase 5.

---
*Phase: quick-006*
*Completed: 2026-08-22*
