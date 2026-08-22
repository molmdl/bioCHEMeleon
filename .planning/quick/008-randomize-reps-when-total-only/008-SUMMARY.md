---
phase: quick-008
plan: 01
type: summary
files_modified:
  - pymol/biochemeleon/generators.py
  - pymol/tests/test_generators.py
  - pymol/biochemeleon/__init__.py
commits:
  - hash: 70025f3
    msg: "test(quick-008): add randomize_per_rep tests"
  - hash: c96ecd7
    msg: "fix(quick-008): add randomize_per_rep pure generator"
  - hash: 889fd00
    msg: "fix(quick-008): wire randomize_per_rep into start flow (replace all-spheres fallback)"
---

# Quick Task 008 — Summary

## What

Randomized the representation distribution when the user sets only a total
`hider_count` (leaves `per_rep` empty) and clicks Start. Previously this
case defaulted ALL hiders to spheres (an all-spheres fallback at
`__init__.py:477-482`), which contradicted the `per_rep = {}` comment in
`setup_state.py:126` ("empty/missing = random") and was inconsistent with
the Randomize button (`setup_state.randomize_state` lines 282-292, which
DO distribute across reps). Now an empty `per_rep` distributes
`hider_count` across a random non-empty subset of `GAME_REPS` so the game
mixes representations on Start — parity with the Randomize button.

Output: a pure, WSL-testable `randomize_per_rep(hider_count, game_reps,
seed)` generator (dependency-injected: `game_reps` is a parameter, so
`generators.py` stays stdlib-`random`-only with NO `from pymol` and NO
`from .setup_state`) + 10 unit tests, wired into
`_continue_after_large_demo_fetch` (the post-resolution body extracted
from `_prepare_and_start` in Phase 9; the plan's line refs 362/364/477-482
all land here). Explicit `per_rep` is untouched; `hider_count=0` yields 0
hiders with no crash.

## Changes

### `pymol/biochemeleon/generators.py` (new pure function — +57 lines)

- **`randomize_per_rep(hider_count, game_reps, seed=None)`** appended after
  `generate_middle_displacement`. Mirrors `setup_state.randomize_state`'s
  per-rep loop (lines 282-292) but as a PURE, dependency-injected function:
  `game_reps` is passed in (not imported) so the module stays WSL-testable
  (same DI pattern as `registry.reconstruct_from_sentinels`'s iterate-fn
  param). Two differences from `randomize_state`:
  1. **Non-empty subset**: uses `rng.randint(1, len(game_reps))` (NOT
     `randint(0, ...)`) so the sampled subset is always >=1 rep.
  2. **Non-empty guarantee**: if every per-rep draw came back 0 (possible
     when `hider_count==1` and each rep draws `randint(0, 1)==0`), puts the
     full count on `rng.choice(game_reps)`. The caller must never loop back
     to a fallback.
  Returns `{rep: count}` with every count > 0, `sum(counts) <= hider_count`
  (leftover unassigned — intentional parity with `randomize_state`), and
  >=1 key when `hider_count > 0` and `game_reps` is non-empty. `{}`
  for `hider_count <= 0` or empty `game_reps`.
- **Module docstring** "Functions:" list updated with the new entry.

### `pymol/tests/test_generators.py` (new test class — +97 lines)

- **`TestRandomizePerRep`** class (10 tests). `GAME_REPS` is a LOCAL const
  in the test (NOT imported) for independence, per the plan. Covers:
  - `test_zero_hider_count` / `test_negative_hider_count` /
    `test_empty_game_reps` → `{}` for degenerate inputs (no crash).
  - `test_non_empty_when_count_positive` → 20 seeds, result always
    non-empty with >=1 rep count > 0 (the core quick-008 guarantee).
  - `test_all_keys_in_game_reps` / `test_values_positive` → no bogus keys,
    no zero-count entries leak in.
  - `test_sum_le_hider_count` → 30 seeds, `sum <= hider_count`.
  - `test_hider_count_one` → exactly one entry with value 1 (sum == 1).
  - `test_seed_determinism` / `test_seed_difference` → seed reproducibility.
- `randomize_per_rep` added to the `generators` import block (lines 33-39).

### `pymol/biochemeleon/__init__.py` (wiring — +10/-6 lines)

In `_continue_after_large_demo_fetch` (the post-resolution body; called by
the synchronous `_prepare_and_start` path at line 346 AND the async
large-demo drain's 'done' branch):

1. **`from .setup_state import GAME_REPS`** (line 363) added immediately
   after `from . import generators, game, demos, mutation`. Safe: 
   `setup_state.py` is PURE (imports only `random as _random` +
   `copy as _copy`; no `from pymol`, no internal imports) → no
   circular-import risk. (Confirmed via grep of setup_state.py imports.)
2. **Populate `per_rep` early when empty** (lines 366-374), right after
   `per_rep = state.get("per_rep", {})`. Inserted BEFORE the
   cartoon/ribbon pre-compute (`_cartoon_reps`/`_cartoon_segments`/`
   _cartoon_disps` ~line 440) so random cartoon/ribbon hiders get their
   mid-chain segments pre-picked just like explicit ones. The
   `randomize_per_rep` guarantee (>=1 rep count > 0 for hider_count > 0)
   means the per-rep loop now always populates `hider_specs` for a positive
   count.
3. **Removed the old all-spheres fallback** (was lines 477-482:
   `if not hider_specs: ... generate_sphere_positions(extent, count)`).
   The under-generation warning block immediately after (now lines 487-492)
   is KEPT — it still applies to cartoon/ribbon under-generation. For
   `hider_count=0`, `per_rep={}` → the loop generates nothing → 0 hiders,
   no crash (equivalent to the old fallback's
   `generate_sphere_positions(extent, 0)`).

`setup_state.randomize_state` was NOT touched (it has existing tests in
`test_setup_state.py`; the DRY refactor is explicitly out of scope).

## Verification (run, all green)

All 7 plan verification checks pass (run from `pymol/` cwd):

1. **`python3.6 -m unittest tests.test_generators -v`** → `Ran 45 tests
   in 0.012s — OK` (35 existing + 10 new `TestRandomizePerRep`).
2. **`python3.6 -m unittest tests.test_setup_state -v`** → green
   (`randomize_state` untouched; its tests stay green). Combined sweep
   `tests.test_setup_state tests.test_generators` → `Ran 170 tests — OK`.
3. **`python3.6 -m py_compile biochemeleon/generators.py
   biochemeleon/__init__.py`** → clean (no syntax error).
4. **Pitfall-1 gate**: `grep -rnE "import Tkinter|...|import PyQt5"
   biochemeleon/` → **0 matches**.
5. **exec_ gate**: 3 pre-existing hits (`gui_game.py:345` + `:404`
   `msg.exec_()` on QMessageBox, `__init__.py:956` `help_dlg.exec_()` on
   the help dialog). **None introduced** by this change; all on child
   dialogs, never the main modeless PluginDialog. Gate stays clean.
6. **`generators.py` purity**: `grep -nE "from pymol|from \.setup_state|
   import pymol" biochemeleon/generators.py` → **0 matches** (pure).
7. **Fallback gone + wiring present**:
   - `grep -nE "default to|all-spheres fallback|if not hider_specs:"
     biochemeleon/__init__.py` → the `if not hider_specs:` fallback CODE is
     absent (the only "all-spheres fallback" match is the new explanatory
     comment at line 368 documenting the replacement).
   - `grep -nE "randomize_per_rep|from \.setup_state import GAME_REPS"
     biochemeleon/__init__.py` → both present (lines 363, 368, 374).

## Out of scope / untested

Full GUI/runtime verification (actually clicking Start with a loaded
molecule and observing mixed reps) requires the Windows PyMOL session
and is NOT WSL-runnable. The pure-function correctness is covered by unit
tests; the wiring is covered by the grep gates + syntax check. A
human-verify of the mixed-rep outcome is optional and out of scope for
this quick task (the logic mirrors the already-shipped Randomize button,
which is human-verified).

## Deviations from plan

None — plan executed exactly as written.

One clarification (not a deviation): the plan refers to the edits landing
in "method `_prepare_and_start`", but the post-resolution body (where
line refs 362/364/477-482 point) was extracted to
`_continue_after_large_demo_fetch` in Phase 9 (the method's own docstring
at lines 359-361 documents: "the body is verbatim from _prepare_and_start
lines 150-307 -- no logic change, just moved so the async path can share
it"). The edits went where the line references pointed; the synchronous
`_prepare_and_start` path calls `_continue_after_large_demo_fetch` at
line 346, so the wiring is correct at the flow level. The plan's line
references were authoritative and were followed exactly.

## Commits

- `70025f3` — `test(quick-008): add randomize_per_rep tests` (TDD RED —
  TestRandomizePerRep class + import; 97 insertions)
- `c96ecd7` — `fix(quick-008): add randomize_per_rep pure generator`
  (TDD GREEN — function + docstring; 57 insertions)
- `889fd00` — `fix(quick-008): wire randomize_per_rep into start flow
  (replace all-spheres fallback)` (+10/-6 in `__init__.py`)
- (metadata) — `docs(quick-008): ...` (this SUMMARY + PLAN)

TDD: RED → GREEN, no REFACTOR needed (code was clean on first GREEN).
