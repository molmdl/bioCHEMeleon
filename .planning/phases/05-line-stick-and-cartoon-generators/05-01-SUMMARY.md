---
phase: 05-line-stick-and-cartoon-generators
plan: 01
subsystem: generators
tags: [random, rng, pure-functions, tdd, wsl-tests, geometry, selection, pymol-plugin]

# Dependency graph
requires:
  - phase: 04-sphere-generator
    provides: generate_sphere_positions purity pattern (stdlib random, WSL-testable) extended here
provides:
  - "generate_line_stick_offsets(n, seed) — pure small [-1.0,1.0] [dx,dy,dz] offset vectors for line/stick hiders near real neighbors"
  - "pick_terminal_residues(cas_by_chain, max_chains) — pure longest-chain-first C-terminus (max resi) tuples for cartoon extend-at-terminal hiders"
affects: [05-02-mutation-insert-functions, 05-03-on-start-wiring, 05-04-smoke, 05-05-verification]

# Tech tracking
tech-stack:
  added: []  # stdlib random only — no new deps (purity preserved)
  patterns:
    - "Pure/cmd split: geometry + selection decisions stay PURE in generators.py (WSL-unit-testable); cmd-coupled insertion (cmd.bond/cmd.attach_amino_acid) deferred to mutation.py (plan 05-02)"
    - "TDD RED-GREEN-REFACTOR: failing tests committed first (RED), minimal pure implementation second (GREEN), refactor skipped (code already minimal)"

key-files:
  created: []
  modified:
    - "biochemeleon/generators.py — added generate_line_stick_offsets + pick_terminal_residues (33 -> 97 lines, still pure)"
    - "tests/test_generators.py — added TestGenerateLineStickOffsets + TestPickTerminalResidues (106 -> 227 lines)"

key-decisions:
  - "C-terminus only for MVP (is_c_terminus always True); N-terminus is a future option (05-RESEARCH.md Sec3 Q8)"
  - "One cartoon hider per chain cap (max_chains) — attaching many to one terminus chains them (05-RESEARCH.md Sec7 Open Risk 5)"
  - "[-1.0, 1.0] Angstrom offset bounds for line/stick (short bond, blends with real bonds — 05-RESEARCH.md Sec2 Q3)"
  - "Module stays flat: import random only, NO from pymol, NO numpy (mirrors registry.py/setup_state.py purity)"

patterns-established:
  - "Pure generator extends existing pure module (generators.py) without breaking Phase 4 generate_sphere_positions"
  - "Module-level import in test file triggers ImportError-as-RED (vs AttributeError-per-method) when functions are absent — valid TDD RED state for module-level imports"

# Metrics
duration: ~7 min
completed: 2026-08-08
---

# Phase 5 Plan 1: Line/Stick & Cartoon Pure Generators Summary

**Two pure stdlib-random functions for Phase 5 hider geometry: `generate_line_stick_offsets` (small [-1,1] offsets for bonded line/stick hiders) and `pick_terminal_residues` (longest-chain-first C-terminus tuples for cartoon extend-at-terminal hiders), both WSL-unit-tested via TDD.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-08-08T07:15:00Z
- **Completed:** 2026-08-08T07:22:01Z
- **Tasks:** 3 (RED, GREEN, REFACTOR-skipped)
- **Files modified:** 2

## Accomplishments
- `generate_line_stick_offsets(n, seed)` — pure RNG offset generator: returns `n` `[dx,dy,dz]` lists, each component uniform in `[-1.0, 1.0]` A, deterministic with seed, `[]` for `n=0`. Feeds line/stick hider placement (offset added to a neighbor's coords, then `cmd.bond`).
- `pick_terminal_residues(cas_by_chain, max_chains)` — pure selection: returns `(chain, terminal_resi, is_c_terminus)` tuples, longest-chain-first, C-terminus (max resi), capped at `max_chains`, `[]` for empty dict. Feeds cartoon hider placement (one terminal extension per chain).
- Both functions are PURE (stdlib `random` only — NO `from pymol`, NO `numpy`), mirroring the Phase 4 `generate_sphere_positions` / `registry.py` purity convention, so they are WSL-unit-testable.
- TDD discipline: 13 new test methods committed RED first (ImportError for absent functions), then minimal pure implementation committed GREEN (all 21 generator tests pass).
- No regression: 152 prior tests (setup_state + registry + game_controller) still green; purity gate 0; Pitfall-1 gate 0 (one pre-existing false-positive comment in gui_setup.py, untouched).

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — add failing tests** - `26b0dc3` (test)
2. **Task 2: GREEN — implement pure functions** - `ddef76f` (feat)
3. **Task 3: REFACTOR — skipped (no changes needed)** - no commit (code intentionally minimal per plan)

**Plan metadata:** `pending` (docs: complete plan — SUMMARY only; STATE.md/ROADMAP.md handled by orchestrator post-merge)

_Note: TDD task 3 (REFACTOR) produced no commit — the implementation was already minimal and clean; per plan "REFACTOR is optional."_

## Files Created/Modified
- `biochemeleon/generators.py` - Extended with `generate_line_stick_offsets` + `pick_terminal_residues` (33 -> 97 lines). Module stays pure (import random only). Updated module docstring to list all three generators + keep NO pymol/NO numpy purity statement.
- `tests/test_generators.py` - Extended with `TestGenerateLineStickOffsets` (7 tests) + `TestPickTerminalResidues` (6 tests) (106 -> 227 lines). Existing `TestGenerateSpherePositions` (8 tests) intact. Module docstring updated to cover Phase 5 functions.

## Decisions Made
- **C-terminus only (MVP):** `pick_terminal_residues` always returns `is_c_terminus=True`. N-terminus extension is a future option (05-RESEARCH.md Sec3 Q8 says C-terminus is the MVP path). No N-terminus selection added (plan explicitly forbids: "do NOT add features").
- **One-per-chain cap via `max_chains`:** Attaching many residues to one terminus chains them (the 2nd attaches to the 1st's new terminus, shifting the chain — 05-RESEARCH.md Sec7 Open Risk 5). The `max_chains` parameter lets the caller cap at one per chain.
- **[-1.0, 1.0] offset bounds:** Per 05-RESEARCH.md Sec2 Q3 ("0.5-1.0 A so the bond is visible but short"). The full [-1,1] range gives the caller flexibility; the caller adds the offset to a real neighbor's coords.
- **No refactor commit:** The implementation matches the plan's `<implementation>` block exactly; docstrings are accurate; no dead code. Per plan: "If no changes needed, skip the commit (REFACTOR is optional)."
- **Kept `generate_sphere_positions` intact:** Per plan ("do NOT rewrite — keep the existing function intact"). Did not reformat its docstring to match the new Args/Returns style (scope creep beyond plan).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required. The module uses only stdlib `random` (no new dependencies, no environment changes).

## Next Phase Readiness
- **Ready for plan 05-02 (mutation.py cmd-coupled insert functions):** `generate_line_stick_offsets` and `pick_terminal_residues` are the pure inputs the cmd-coupled `insert_line_stick_hider` / `insert_cartoon_hider` (plan 05-02) and the `__init__._on_start` wiring (plan 05-03) will call:
  - `generators.generate_line_stick_offsets(count, seed)` -> offsets zipped with sampled neighbor ids -> `(offset, neighbor_id)` payloads for line/stick `hider_specs`.
  - `generators.pick_terminal_residues(cas_by_chain, max_chains=count)` -> `(chain, terminus_resi, is_c_terminus)` payloads for cartoon `hider_specs`.
- **No blockers.** Purity holds (0 pymol/numpy imports in generators.py); all WSL gates green.
- **Known limitation (caroon, deferred to smoke):** `rep` is NOT recoverable from sentinels after `.pse` reload (Phase 8 `.bcm` sidecar reconciles). This plan does not touch that — it's a registry/Phase-8 concern.

---
*Phase: 05-line-stick-and-cartoon-generators*
*Completed: 2026-08-08*
