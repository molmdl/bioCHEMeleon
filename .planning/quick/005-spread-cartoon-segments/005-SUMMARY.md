---
phase: quick-005
plan: 01
type: summary
subsystem: generators (cartoon/ribbon hider placement)
tags: [generators, pick_segments, even-spacing, gameplay-tuning, tdd, pure-layer]
files_modified:
  - pymol/biochemeleon/generators.py
  - pymol/tests/test_generators.py
commits:
  - hash: 5e5387d
    msg: "test(quick-005): add spread regression tests for pick_segments multi-pick"
  - hash: 00bda62
    msg: "fix(quick-005): spread multi-pick segments evenly across the chain"
---

# Quick Task 005 — Summary

## What

Rewrote the cartoon/ribbon hider multi-pick branch in `pick_segments` so
2+ segments spread **evenly across the whole chain** instead of clustering
back-to-back near the N-terminus. The old greedy advance
(`i += segment_size`) placed consecutive segments adjacent to each other
(e.g. 1ubq 76 residues, count=2 → resi 2-4 and 5-7, **interior gap 0**),
which made multi-hider games too easy: once a player finds one hider, the
next is right next to it. Even spacing splits the chain's slack into
`count + 1` gaps (leading / between / trailing) so each hider lands in its
own region of the chain and is individually harder to find — the actual
gameplay-tuning goal.

Delivered as a TDD RED→GREEN cycle: two pure-Python regression tests that
fail on the old greedy advance and pass on the new even spacing, then the
even-spacing implementation.

## Changes

### `pymol/tests/test_generators.py` (RED — 2 new tests, +47 lines)

Appended two methods to the `TestPickSegments` class (after
`test_count_cap`, before `TestGenerateMiddleDisplacement`). No existing
test modified; no imports or `__main__` block changed (`pick_segments`
already imported at line 37).

1. **`test_two_segments_spread_across_long_chain`** — 76-residue chain
   (1ubq-like), count=2: asserts the interior gap ≥ 15 (old greedy: 0),
   segments are disjoint, and the first segment is NOT the pure N-term
   window `(1,3)`.
2. **`test_three_segments_one_per_third`** — 60-residue chain, count=3:
   asserts one segment start in each third of the chain (1-20, 21-40,
   41-60). Old greedy yielded starts 2,5,8 (all in the first third → FAIL).

### `pymol/biochemeleon/generators.py` (GREEN — +48/-18)

1. **New pure helper `_even_starts(n_res, count, segment_size)`** (added
   immediately before `pick_segments`): distributes `count` disjoint
   windows of `segment_size` across `n_res` by splitting the slack
   (`n_res - count*segment_size`) into `count + 1` gaps as evenly as
   integer division allows (remainder spread to the leading gaps). The
   leading gap is ≥ 1 whenever there is any slack, so the first window
   avoids the pure N-terminus when the chain has room — generalizing the
   old `start = 1 if len(windows) > need` guard. Returns a list of
   0-indexed start positions into `resis`. Precondition:
   `count >= 2` and `count * segment_size <= n_res`.
2. **Replaced the entire `else:` multi-pick block** of `pick_segments`
   (the old greedy `while i < len(windows) ... i += segment_size` loop)
   with an even-spacing block: caps at `max_fit = n_res // segment_size`
   disjoint windows, and if only one fits falls through to the centered
   single-pick (same as `need == 1`); otherwise iterates `_even_starts`
   and emits `(ch, resis[s], resis[s + segment_size - 1])`.
3. **Updated the docstring** sentence from "centered windows for single
   picks, greedy spread for multi-picks" → "centered window for a single
   pick, even spacing across the chain for multi-picks (quick-005)".

Preserved EXACTLY (byte-identical): the `if need == 1:` centered
single-pick branch, longer-chains-first ordering, skip-chains-shorter
guard, `segment_size=3` default, the `windows = [...]` build (still used
by single-pick / `actual <= 1` paths), the `out[:count]` final trim, and
module purity (stdlib `random` only — NO `pymol`, NO `numpy`).

## Verification (run, all green)

All from the `pymol/` directory (pure-Python, no PyMOL needed):

1. **RED state (after Task 1)**: `python3.6 -m unittest tests.test_generators
   -v` → `Ran 37 tests … FAILED (failures=2)` — exactly the 2 new tests
   fail (`test_two_segments_spread_across_long_chain`: gap 0 not ≥ 15;
   `test_three_segments_one_per_third`: starts[1] 5 not ≥ 21); the 35
   existing tests pass. Bug captured without breaking anything else.
2. **GREEN state (after Task 2)**: `python3.6 -m unittest tests.test_generators
   -v` → `Ran 37 tests in 0.008s — OK` (exit 0).
3. **Syntax gate**: `python3.6 -m py_compile biochemeleon/generators.py` →
   `SYNTAX_OK` (exit 0).
4. **Purity gate**: `grep -rnE "from pymol|import pymol|import numpy|from
   numpy" pymol/biochemeleon/generators.py` → **no output** (exit 1).
   Module stays pure / WSL-testable.
5. **Spot-check spread**:
   - 76-res count=2 → `[('A', 25, 27), ('A', 51, 53)]` — interior gap 23
     (≥ 15); NOT the old `(2,4)/(5,7)`.
   - 60-res count=3 → `[('A', 14, 16), ('A', 30, 32), ('A', 46, 48)]` —
     one start per third (14 ∈ 1-20, 30 ∈ 21-40, 46 ∈ 41-60); NOT the old
     `(2,5,8)`.
6. **Regression — tight chain** (`test_disjoint_segments_multi_count`):
   7-res count=2 → `[('A', 2, 4), ('A', 5, 7)]`. Disjoint (4 < 5), first
   starts at resi 2 (not the N-term 1), no segment is the pure N-term
   window `(1,3)`. Slack = 1 is exhausted by the leading gap, so there is
   no interior gap — correct: there is no room to spread 2 size-3 windows
   in 7 residues while avoiding the N-term. Test passes (part of the 37).

## Backward compatibility

The caller `__init__.py` consumes `(chain, start_resi, end_resi)` tuples
and does NOT depend on specific resi values (it takes whatever disjoint
segments come back). Only the return SHAPE matters, which is unchanged.
The even-spacing leading gap is ≥ 1 whenever there is slack, so it
inherently avoids the pure N-term window whenever alternatives exist (same
intent as the old guard). When slack is 0 (chain exactly fits
`count*segment_size`), the leading gap is 0 and the N-term window may be
used — that is the only way to fit `count` disjoint windows, so it is
correct.

## Deviations from plan

None — plan executed exactly as written. The two-task TDD cycle (RED
tests → GREEN fix) produced exactly the two commits specified by the
success criteria.

## Out of scope / untested

The optional integration guard (headless Phase 11 smoke on a real 76-res
1ubq chain) was NOT run — the plan marks it "only if context budget
allows; NOT required for done". The unit tests (37, all green) plus the
spot-checks above fully cover the placement logic. The Phase 11 smoke
reads pre-captured coords for ANY middle resi via the full-chain
`orig_ca_coords` dict, so the new spread positions are covered by that
harness when it is next run; no integration regression is expected because
only segment POSITIONS changed (disjointness and return shape are
preserved).

## Commits

- `5e5387d` — `test(quick-005): add spread regression tests for pick_segments
  multi-pick` (Task 1 / RED; 1 file: test_generators.py; +47)
- `00bda62` — `fix(quick-005): spread multi-pick segments evenly across the
  chain` (Task 2 / GREEN; 1 file: generators.py; +48/-18)
- (metadata) — `docs(quick-005): …` (this SUMMARY + PLAN)

Two atomic TDD commits (RED then GREEN) + one bookkeeping commit, matching
the plan's success criteria ("Two commits: `test(quick-005):` (RED tests)
then `fix(quick-005):` (GREEN fix)").
