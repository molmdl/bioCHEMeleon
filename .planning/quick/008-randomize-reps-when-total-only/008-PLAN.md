---
phase: quick-008
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pymol/biochemeleon/generators.py
  - pymol/tests/test_generators.py
  - pymol/biochemeleon/__init__.py
autonomous: true
commit_prefix: "fix(quick-008):"

must_haves:
  truths:
    - "User sets only hider_count (per_rep empty) and clicks Start -> hiders span a random mix of representation types (lines/sticks/spheres/cartoon/ribbon), NOT all spheres"
    - "User explicitly sets per_rep (e.g. {spheres:3, lines:2}) and clicks Start -> behavior unchanged (hiders match the explicit per-rep counts; randomize_per_rep is NOT called)"
    - "hider_count=0 with per_rep empty -> 0 hiders, no crash (randomize_per_rep returns {} for count<=0; the per-rep loop generates nothing)"
    - "randomize_per_rep is PURE: stdlib `random` only, NO `from pymol`, NO `from .setup_state` (game_reps is a parameter) -> WSL-unit-testable"
    - "randomize_per_rep(hider_count>0, non-empty game_reps) returns a dict with at least one rep whose count > 0 (never empty, so it cannot loop back to a fallback)"
    - "every count in the returned per_rep is > 0 and the sum of counts is <= hider_count (mirrors setup_state.randomize_state's distribution; leftover is unassigned, matching the Randomize button)"
    - "pure unit tests stay green and the pitfall-1 / exec_ / syntax gates stay clean"
  artifacts:
    - path: "pymol/biochemeleon/generators.py"
      provides: "randomize_per_rep(hider_count, game_reps, seed=None) pure generator that distributes hider_count across a random non-empty subset of game_reps"
      contains: "def randomize_per_rep"
    - path: "pymol/tests/test_generators.py"
      provides: "TestRandomizePerRep class covering empty/zero inputs, non-empty guarantee, key validity, sum bound, positive values, seed determinism/difference"
      contains: "class TestRandomizePerRep"
    - path: "pymol/biochemeleon/__init__.py"
      provides: "_prepare_and_start populates per_rep via generators.randomize_per_rep when per_rep is empty; the old all-spheres fallback (was lines 477-482) is removed"
      contains: "randomize_per_rep"
  key_links:
    - from: "pymol/biochemeleon/__init__.py (_prepare_and_start)"
      to: "pymol/biochemeleon/generators.py (randomize_per_rep)"
      via: "function call when per_rep is empty"
      pattern: "generators\\.randomize_per_rep"
    - from: "pymol/biochemeleon/__init__.py (_prepare_and_start)"
      to: "pymol/biochemeleon/setup_state.py (GAME_REPS)"
      via: "import passed as game_reps arg"
      pattern: "from \\.setup_state import GAME_REPS"
---

<objective>
Randomize representation distribution when the user sets only a total hider count.

Purpose: Today, if a user sets `hider_count` (e.g. 10) but leaves `per_rep` empty
(no Randomize button, no per-rep counts) and clicks Start, ALL hiders default to
spheres. The setup comment claims `per_rep = {}` means "random" (setup_state.py:126)
but the fallback in `_prepare_and_start` (lines 477-482) hard-codes spheres. The
Randomize button (`setup_state.randomize_state`, lines 282-292) DOES distribute
across reps, so a manual total-count Start is inconsistent with Randomize.

Output: A pure, WSL-testable `randomize_per_rep(hider_count, game_reps, seed)`
generator + tests, wired into `_prepare_and_start` so an empty `per_rep`
distributes `hider_count` across a random subset of `GAME_REPS` (mixed reps)
instead of all spheres. Explicit `per_rep` is untouched.
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@pymol/biochemeleon/generators.py
@pymol/biochemeleon/setup_state.py
@pymol/biochemeleon/__init__.py
@pymol/tests/test_generators.py

# Reference (the distribution logic to mirror):
#   setup_state.py lines 282-292 (randomize_state's per_rep loop):
#     reps = rng.sample(GAME_REPS, rng.randint(0, len(GAME_REPS)))
#     per_rep = {}; remaining = hider_count
#     for rep in reps:
#         if remaining <= 0: break
#         c = rng.randint(0, remaining)
#         if c: per_rep[rep] = c; remaining -= c
# The new pure function mirrors this BUT: (1) game_reps is a parameter (DI),
# (2) guarantees >=1 rep with count>0 for hider_count>0 (caller must not loop
# back to a fallback). Do NOT touch randomize_state itself (it has existing
# tests in test_setup_state.py; the DRY refactor is explicitly out of scope).
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add randomize_per_rep pure generator + tests (RED -> GREEN)</name>
  <files>pymol/biochemeleon/generators.py, pymol/tests/test_generators.py</files>
  <action>
Add a pure function `randomize_per_rep(hider_count, game_reps, seed=None)` to
`pymol/biochemeleon/generators.py` (append after `generate_middle_displacement`).
Keep `generators.py` PURE: stdlib `random` only, NO `from pymol`, NO
`from .setup_state` (game_reps is a parameter — dependency injection, same
pattern as `registry.reconstruct_from_sentinels`'s iterate-fn param).

Logic (mirrors `setup_state.randomize_state` lines 282-292, with two changes):
```python
def randomize_per_rep(hider_count, game_reps, seed=None):
    """Distribute hider_count across a random non-empty subset of reps.

    Mirrors the per-rep distribution in setup_state.randomize_state but as
    a PURE, dependency-injected function: game_reps is passed in (not
    imported) so this module stays pure (WSL-unit-testable). Used by
    __init__._prepare_and_start when the user sets a total hider_count
    without per-rep counts (per_rep={}) -- instead of the old all-spheres
    fallback, the count is spread across a random subset of GAME_REPS so
    the game mixes representations (parity with the Randomize button).

    Guarantees at least one rep with count > 0 when hider_count > 0 (avoids
    an empty per_rep that would loop back to a fallback). The per-rep
    generation loop in _prepare_and_start already handles under-generation
    (cartoon/ribbon need mid-chain segments; sticks need neighbor atoms) with
    warnings -- a rep that cannot fulfill its count yields fewer (or zero)
    hiders, matching the Randomize button's behavior.

    Like randomize_state, the sum of returned counts may be < hider_count
    (leftover unassigned): randomize_state has the same property. This is
    intentional parity, not a bug.

    Args:
        hider_count: total hiders to distribute (int). <= 0 -> {}.
        game_reps: ordered list of valid rep names (e.g. GAME_REPS). Empty -> {}.
        seed: int for deterministic output (tests). None = entropy.

    Returns:
        dict {rep: count} with count > 0 for each key, sum(counts) <=
        hider_count, at least one key when hider_count > 0 and game_reps is
        non-empty. {} for hider_count <= 0 or empty game_reps.
    """
    if hider_count <= 0 or not game_reps:
        return {}
    rng = random.Random(seed)
    # Pick a random NON-EMPTY subset (>=1 rep). randomize_state uses
    # randint(0, ...) which can yield an empty subset; here we MUST avoid
    # empty (the caller's fallback would otherwise re-trigger).
    reps = rng.sample(game_reps, rng.randint(1, len(game_reps)))
    per_rep = {}
    remaining = hider_count
    for rep in reps:
        if remaining <= 0:
            break
        c = rng.randint(0, remaining)
        if c:
            per_rep[rep] = c
            remaining -= c
    # Guarantee non-empty: if every random draw came back 0 (possible when
    # hider_count==1 and each rep draws 0), put the full count on a random rep.
    if not per_rep:
        per_rep[rng.choice(game_reps)] = hider_count
    return per_rep
```
Also update the module docstring's "Functions:" list (lines 14-19) to add:
`  - randomize_per_rep(hider_count, game_reps, seed)  -- quick-008 (random per_rep)`.

Then add a `TestRandomizePerRep` class to `pymol/tests/test_generators.py`
(follow the existing class style; add `randomize_per_rep` to the import block
at lines 33-39). Tests (use `GAME_REPS = ['lines','sticks','spheres','cartoon','ribbon']`
as a local const in the test, NOT imported, to keep the test independent):
  - `test_zero_hider_count`: randomize_per_rep(0, GAME_REPS) == {}
  - `test_negative_hider_count`: randomize_per_rep(-5, GAME_REPS) == {}
  - `test_empty_game_reps`: randomize_per_rep(5, []) == {}
  - `test_non_empty_when_count_positive`: for seed in range(20): result =
    randomize_per_rep(10, GAME_REPS, seed=seed); assertTrue(result); assertTrue(any(v
    > 0 for v in result.values()))  # at least one rep with count > 0
  - `test_all_keys_in_game_reps`: for several seeds, every key in result is in
    GAME_REPS
  - `test_values_positive`: every value > 0 (no zero-count entries leak in)
  - `test_sum_le_hider_count`: sum(result.values()) <= hider_count for many seeds
  - `test_hider_count_one`: randomize_per_rep(1, GAME_REPS, seed=42) -> exactly one
    entry with value 1 (sum == 1)
  - `test_seed_determinism`: randomize_per_rep(10, GAME_REPS, seed=42) ==
    randomize_per_rep(10, GAME_REPS, seed=42)
  - `test_seed_difference`: randomize_per_rep(10, GAME_REPS, seed=1) !=
    randomize_per_rep(10, GAME_REPS, seed=2)

Write the tests FIRST (add the import + TestRandomizePerRep class), run to
confirm RED (the import of a non-existent `randomize_per_rep` fails —
ImportError/AttributeError is an acceptable RED state for a new function),
commit `test(quick-008): add randomize_per_rep tests`. THEN implement the
function in generators.py, run to confirm GREEN, commit
`fix(quick-008): add randomize_per_rep pure generator`.
  </action>
  <verify>
Run from the `pymol/` directory (cwd = `pymol/`):
  `python3.6 -m unittest tests.test_generators -v`  -> all green (existing +
  new TestRandomizePerRep tests).
  `python3.6 -m py_compile biochemeleon/generators.py`  -> no syntax error.
Purity check (must be ZERO matches): `grep -nE "from pymol|from \\.setup_state|import pymol" biochemeleon/generators.py`
  </verify>
  <done>
`randomize_per_rep` exists in generators.py, is pure (stdlib random only),
mirrors randomize_state's distribution, guarantees >=1 rep with count>0 for
hider_count>0, and all TestRandomizePerRep tests pass in WSL.
  </done>
</task>

<task type="auto">
  <name>Task 2: Wire randomize_per_rep into _prepare_and_start (replace all-spheres fallback)</name>
  <files>pymol/biochemeleon/__init__.py</files>
  <action>
In `pymol/biochemeleon/__init__.py`, method `_prepare_and_start`:

1. Add the GAME_REPS import. At line 362 the method does
   `from . import generators, game, demos, mutation`. Add immediately after:
   `from .setup_state import GAME_REPS`
   (setup_state.py is PURE — stdlib only, no pymol, no internal imports — so
   this import is safe with NO circular-import risk. Confirmed: setup_state.py
   imports only `random as _random` and `copy as _copy`.)

2. Populate per_rep EARLY when empty. Right after line 364
   (`per_rep = state.get("per_rep", {})  # {rep: count} (Phase 2 collect_state)`),
   insert:
   ```python
        # quick-008: if per_rep is empty (user set total hider_count without
        # per-rep counts), distribute across a random subset of GAME_REPS
        # instead of the old all-spheres fallback. randomize_per_rep
        # guarantees >=1 rep with count>0 for hider_count>0; the per-rep loop
        # below then generates mixed-rep hiders (parity with the Randomize
        # button, setup_state.randomize_state). Explicit per_rep is untouched.
        if not per_rep:
            _hider_count = int(state.get("hider_count", 0))
            per_rep = generators.randomize_per_rep(_hider_count, GAME_REPS)
   ```
   Inserting here (before `extent`/`cas_by_chain`/the cartoon pre-compute at
   lines 432-438) is CORRECT: the cartoon/ribbon pre-compute reads per_rep and
   must see the populated counts so random cartoon/ribbon hiders get their
   mid-chain segments pre-picked just like explicit ones.

3. REMOVE the old all-spheres fallback (the block at lines 477-482):
   ```python
        # Fallback: if per_rep is empty (random mode unset), default to
        # spheres (Phase 4 behavior) using the total hider_count.
        if not hider_specs:
            count = int(state.get("hider_count", 0))
            positions = generators.generate_sphere_positions(extent, count)
            hider_specs = [(pos, "spheres") for pos in positions]
   ```
   Delete those 6 lines (477-482) entirely. KEEP the under-generation warning
   block immediately after (lines 483-488, `if _gen_warnings:
   QtWidgets.QMessageBox.warning(...)`) — it still applies to cartoon/ribbon
   under-generation. For hider_count>0, per_rep is now guaranteed non-empty so
   `hider_specs` is populated by the loop (spheres always generate; other reps
   may under-generate with warnings — parity with the Randomize button). For
   hider_count=0, per_rep={} -> loop generates nothing -> 0 hiders, no crash
   (equivalent to the old fallback's `generate_sphere_positions(extent, 0)`).

Do NOT touch `setup_state.randomize_state` (it has existing tests in
test_setup_state.py; the DRY refactor is explicitly out of scope and risks
breaking those tests). Do NOT change any other caller of `_prepare_and_start`.
  </action>
  <verify>
Run from the `pymol/` directory (cwd = `pymol/`):
  `python3.6 -m py_compile biochemeleon/__init__.py`  -> no syntax error.
  Pure unit tests stay green: `python3.6 -m unittest tests.test_setup_state tests.test_generators -v`
  Pitfall-1 gate (ZERO matches): `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/`
  exec_ gate (hits must be QFileDialog/QMessageBox ONLY, never the main PluginDialog/SetupTab): `grep -rnE "\.exec_\(\)" biochemeleon/`
  Confirm the fallback is gone: `grep -nE "default to|all-spheres fallback|if not hider_specs:" biochemeleon/__init__.py` -> the old fallback comment/lines absent.
  Confirm the wiring is present: `grep -nE "randomize_per_rep|from \.setup_state import GAME_REPS" biochemeleon/__init__.py` -> both present.
  </verify>
  <done>
A user who sets only hider_count (per_rep empty) and clicks Start gets hiders
distributed across a random mix of reps (not all spheres). A user who sets
per_rep explicitly gets unchanged behavior. hider_count=0 yields 0 hiders with
no crash. The all-spheres fallback block is removed. All gates stay clean and
pure unit tests stay green.
  </done>
</task>

</tasks>

<verification>
- `python3.6 -m unittest tests.test_generators -v` passes (run from `pymol/` cwd) — new TestRandomizePerRep + existing generator tests green.
- `python3.6 -m unittest tests.test_setup_state -v` passes (run from `pymol/` cwd) — randomize_state untouched, its tests stay green.
- `python3.6 -m py_compile biochemeleon/generators.py biochemeleon/__init__.py` clean (run from `pymol/` cwd).
- Pitfall-1 gate: ZERO matches across `biochemeleon/`.
- exec_ gate: only QFileDialog/QMessageBox hits.
- `generators.py` purity: ZERO `from pymol` / `from .setup_state` / `import pymol`.
- The all-spheres fallback block is absent from `__init__.py`; `randomize_per_rep` + `from .setup_state import GAME_REPS` are present.

NOTE: Full GUI/runtime verification (actually clicking Start with a loaded
molecule and observing mixed reps) requires the Windows PyMOL session and is
NOT WSL-runnable. The pure-function correctness is covered by unit tests; the
wiring is covered by the grep gates + syntax check. A human-verify of the
mixed-rep outcome is optional and out of scope for this quick task (the logic
mirrors the already-shipped Randomize button, which is human-verified).
</verification>

<success_criteria>
- `randomize_per_rep(hider_count, game_reps, seed)` is pure, tested, and
  guarantees a non-empty per_rep for hider_count > 0.
- `_prepare_and_start` populates per_rep via `randomize_per_rep` when
  per_rep is empty (no all-spheres fallback).
- Explicit per_rep is untouched; hider_count=0 yields 0 hiders cleanly.
- All WSL-runnable gates and unit tests stay green.
</success_criteria>

<output>
After completion, create `.planning/quick/008-randomize-reps-when-total-only/008-SUMMARY.md`
</output>
