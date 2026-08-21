---
phase: quick-005
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pymol/biochemeleon/generators.py
  - pymol/tests/test_generators.py
autonomous: true

must_haves:
  truths:
    - "Two cartoon/ribbon segments on a 76-residue chain have a large interior gap (NOT back-to-back near the N-term)"
    - "Three segments on a 60-residue chain land one per third of the chain"
    - "A single segment (count=1) is still the centered mid-chain window (unchanged)"
    - "Segments remain disjoint (non-overlapping resi ranges) for all counts"
    - "All existing pick_segments tests still pass (no regression: empty, 3-res, 5-res centered, 7-res disjoint, skip-short, longest-first, count-cap)"
  artifacts:
    - path: pymol/biochemeleon/generators.py
      provides: "even-spaced multi-pick branch in pick_segments + _even_starts helper"
      contains: "_even_starts"
    - path: pymol/tests/test_generators.py
      provides: "spread regression tests (RED on old greedy, GREEN on even spacing)"
      contains: "test_two_segments_spread_across_long_chain"
  key_links:
    - from: pymol/biochemeleon/__init__.py
      to: pymol/biochemeleon/generators.py
      via: "pick_segments(cas_by_chain, _cartoon_total) -> consumes (chain, start_resi, end_resi) tuples; return SHAPE unchanged (only positions change)"
      pattern: "generators\\.pick_segments\\(cas_by_chain"
---

<objective>
Spread cartoon/ribbon hider segments across the whole chain instead of clustering them back-to-back near the N-terminus.

Purpose: When 2+ cartoon/ribbon hiders are requested, the current `pick_segments` multi-pick branch advances by only `segment_size` (3) after each pick, so the segments are adjacent (e.g. 1ubq 76 residues, count=2 -> resi 2-4 and 5-7, zero gap). Adjacent hiders are too easy to find. Even spacing (one segment per region of the chain) makes each hider individually harder to find — the actual gameplay tuning goal.

Output: A rewritten multi-pick branch in `generators.py` (even spacing via a pure `_even_starts` helper) plus regression tests in `test_generators.py` that fail on the old greedy advance and pass on the new even spacing.
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@pymol/biochemeleon/generators.py
@pymol/tests/test_generators.py
@pymol/biochemeleon/__init__.py
</context>

<tasks>

<task type="auto">
  <name>Task 1 (RED): Add spread regression tests that fail on the current greedy multi-pick</name>
  <files>pymol/tests/test_generators.py</files>
  <action>
Add two new test methods to the existing `TestPickSegments` class in `pymol/tests/test_generators.py` (append them after `test_count_cap`, before the next class `TestGenerateMiddleDisplacement`). Do NOT modify any existing test. Match the file's existing style (no f-strings; plain `self.assertX(..., "msg")` messages; `unittest` TestCase methods).

Add exactly these two methods:

```python
    def test_two_segments_spread_across_long_chain(self):
        """76-residue chain (1ubq-like), count=2 -> large interior gap (quick-005).

        The OLD greedy advance (i += segment_size) placed the two segments
        back-to-back near the N-term (resi 2-4 and 5-7, gap == 0). Even spacing
        spreads them across the chain so the two hiders are far apart and
        individually harder to find. With 76 residues the even-spaced interior
        gap is ~23; assert >= 15 (robust lower bound, well above the old 0).
        """
        cas = {'A': [(i, i + 1000) for i in range(1, 77)]}  # 76 residues
        result = pick_segments(cas, count=2, segment_size=3)
        self.assertEqual(len(result), 2)
        segs = sorted(result, key=lambda t: t[1])
        # Disjoint (no shared resi)
        self.assertLess(segs[0][2], segs[1][1], "two segments must be disjoint")
        # Spread: a large interior gap (NOT back-to-back). Old bug: gap == 0.
        gap = segs[1][1] - segs[0][2] - 1  # residues strictly between segments
        self.assertGreaterEqual(gap, 15,
            "76-residue chain count=2 must spread (gap >= 15), not "
            "back-to-back (old greedy placed resi 2-4 and 5-7, gap 0)")
        # First segment is mid-chain (not the pure N-term window)
        self.assertNotEqual((segs[0][1], segs[0][2]), (1, 3),
                            "first segment must not be the pure N-term window")

    def test_three_segments_one_per_third(self):
        """60-residue chain, count=3 -> one segment start in each third (quick-005).

        The OLD greedy advance clustered all three near the N-term (resi
        2-4, 5-7, 8-10 -- all in the first third 1-20). Even spacing places
        one segment start in each third of the chain (1-20, 21-40, 41-60).
        """
        cas = {'A': [(i, i) for i in range(1, 61)]}  # 60 residues
        result = pick_segments(cas, count=3, segment_size=3)
        self.assertEqual(len(result), 3)
        segs = sorted(result, key=lambda t: t[1])
        # All disjoint
        for i in range(len(segs) - 1):
            self.assertLess(segs[i][2], segs[i + 1][1], "segments must be disjoint")
        starts = [seg[1] for seg in segs]
        # One start in each third of the 60-residue chain
        self.assertGreaterEqual(starts[0], 1)
        self.assertLessEqual(starts[0], 20, "first start in first third (1-20)")
        self.assertGreaterEqual(starts[1], 21, "second start in second third (21-40)")
        self.assertLessEqual(starts[1], 40)
        self.assertGreaterEqual(starts[2], 41, "third start in last third (41-60)")
        self.assertLessEqual(starts[2], 60)
```

Why these specific cases: 76 residues is 1ubq (the canonical demo, 76 C-alphas), count=2 is the exact reported bug; the old greedy yields resi 2-4 and 5-7 (gap 0 < 15 -> FAIL = RED). 60 residues count=3 is a stronger spread assertion (old greedy yields starts 2,5,8 — all in the first third -> `starts[1] >= 21` FAILs = RED). Both are pure-Python (no PyMOL), WSL-runnable.

Do NOT add a `__main__` block or change imports (the two tests use `pick_segments` already imported at line 37).
  </action>
  <verify>
From the `pymol/` directory run:
`python3.6 -m unittest tests.test_generators -v 2>&1 | tail -20`

Expected RED state: the test run reports FAILURES (nonzero exit), the 2 NEW tests fail by name (`test_two_segments_spread_across_long_chain`, `test_three_segments_one_per_third`), and the 35 EXISTING tests still pass. Confirm the failures are ONLY the 2 new tests (proves the bug is captured without breaking anything else). The baseline before this task is 35 tests OK.
  </verify>
  <done>
`pymol/tests/test_generators.py` contains the 2 new spread tests; running the suite shows exactly the 2 new tests failing (RED) and all 35 existing tests passing. Committed as `test(quick-005): add spread regression tests for pick_segments multi-pick`.
  </done>
</task>

<task type="auto">
  <name>Task 2 (GREEN): Rewrite the pick_segments multi-pick branch with even spacing</name>
  <files>pymol/biochemeleon/generators.py</files>
  <action>
Edit ONLY the multi-pick branch of `pick_segments` in `pymol/biochemeleon/generators.py` (the `else:` block currently at lines 161-177, after the `if need == 1:` centered single-pick branch at lines 155-160). Add one private pure helper. Keep the function signature `pick_segments(cas_by_chain, count, segment_size=3)` and the return shape `[(chain, start_resi, end_resi), ...]` UNCHANGED.

1. Add a module-level private helper immediately BEFORE `def pick_segments(...)`:

```python
def _even_starts(n_res, count, segment_size):
    """Evenly-spaced DISJOINT window start indices (0-indexed into resis).

    Distributes ``count`` non-overlapping windows of ``segment_size``
    residues across ``n_res`` residues by splitting the slack
    (``n_res - count*segment_size``) into ``count + 1`` gaps (leading,
    between, trailing) as evenly as integer division allows (remainder
    spread to the leading gaps). The leading gap is >= 1 whenever there
    is any slack, so the first window avoids the pure N-terminus when
    the chain has room (mirrors the single-pick "mid-chain" intent).

    Precondition: ``count >= 2`` and ``count * segment_size <= n_res``
    (the caller caps via ``min(need, n_res // segment_size)``).

    Returns: list of ``count`` 0-indexed start positions into ``resis``.
    """
    footprint = count * segment_size
    slack = n_res - footprint
    n_gaps = count + 1
    base = slack // n_gaps
    rem = slack % n_gaps
    gaps = [base + (1 if k < rem else 0) for k in range(n_gaps)]
    starts = []
    pos = gaps[0]  # leading gap
    for k in range(count):
        starts.append(pos)
        pos += segment_size + gaps[k + 1]
    return starts
```

2. Replace the ENTIRE current `else:` multi-pick block (lines 161-177):
```python
        else:
            start = 1 if len(windows) > need else 0
            last_end = None
            picked = 0
            i = start
            while i < len(windows) and picked < need:
                s, e = windows[i]
                if last_end is None or s > last_end:
                    out.append((ch, s, e))
                    last_end = e
                    picked += 1
                    i += segment_size  # skip overlapping windows
                else:
                    i += 1
```
with this even-spacing block:
```python
        else:
            # Multiple segments: EVEN SPACING across the chain (quick-005).
            # The old greedy advance (i += segment_size) clustered segments
            # back-to-back near the N-term (e.g. 76-res count=2 -> resi 2-4
            # and 5-7, gap 0). Even spacing splits the slack into count+1
            # gaps (leading/between/trailing) so hiders spread across the
            # whole chain. Cap at the max disjoint windows that fit; if only
            # one fits, fall through to the centered single-pick above.
            max_fit = n_res // segment_size
            actual = min(need, max_fit)
            if actual <= 1:
                # Only one fits: centered mid-chain window (same as need==1).
                mid = (len(windows) - 1) // 2
                out.append((ch, windows[mid][0], windows[mid][1]))
            else:
                for s in _even_starts(n_res, actual, segment_size):
                    out.append((ch, resis[s], resis[s + segment_size - 1]))
```

3. Update the docstring sentence in `pick_segments` that currently says multi-pick is "greedy spread" (around line 127: "centered windows for single picks, greedy spread for multi-picks") to: "centered window for a single pick, even spacing across the chain for multi-picks (quick-005)".

Preserve EXACTLY (do NOT change):
- The `if need == 1:` centered single-pick branch (lines 155-160) — the count=1 path is correct and must stay byte-identical.
- Longer-chains-first ordering (`chains = sorted(..., reverse=True)`).
- Skip-chains-shorter-than-segment_size (`if n_res < segment_size: continue`).
- `segment_size=3` default; the function signature; the `out[:count]` final trim.
- Module purity: NO `from pymol`, NO `numpy` (stdlib `random` only). `_even_starts` is pure (no imports).
- `windows = [(resis[i], resis[i + segment_size - 1]) for i in range(...)]` is still built (the single-pick / actual<=1 path uses it; keep it).

Why this is backward-compatible: the caller `__init__.py:434,466` consumes `(chain, start_resi, end_resi)` tuples and does NOT depend on specific resi values (it takes whatever disjoint segments come back). Only the return SHAPE matters, which is unchanged. The even-spacing leading gap is >= 1 whenever there is slack, so it inherently avoids the pure N-term window whenever alternatives exist (same intent as the old `start = 1 if len(windows) > need` guard, but generalized). When slack is 0 (chain exactly fits `count*segment_size`), the leading gap is 0 and the N-term window may be used — that is the only way to fit `count` disjoint windows, so it is correct.
  </action>
  <verify>
From the `pymol/` directory:
1. Syntax: `python3.6 -m py_compile pymol/biochemeleon/generators.py` (must exit 0).
2. Purity gate (must return ZERO matches — confirms no pymol/Qt/numpy crept in):
   `grep -rnE "from pymol|import pymol|import numpy|from numpy" pymol/biochemeleon/generators.py` (expect no output).
3. GREEN — full suite passes (existing 35 + new 2 = 37 tests):
   `python3.6 -m unittest tests.test_generators -v 2>&1 | tail -20` (expect "OK" / "Ran 37 tests", exit 0).
4. Spot-check the spread by running a one-liner (optional, fast) from `pymol/`:
   `python3.6 -c "import sys,os; sys.path.insert(0,'.'); import unittest.mock as m; sys.modules.setdefault('pymol',m.MagicMock()); sys.modules.setdefault('pymol.Qt',m.MagicMock()); from biochemeleon.generators import pick_segments; print(pick_segments({'A':[(i,i) for i in range(1,77)]},2)); print(pick_segments({'A':[(i,i) for i in range(1,61)]},3))"`
   Expect 76-res count=2 -> two segments far apart (e.g. (A,25,27),(A,51,53)); 60-res count=3 -> one per third (e.g. (A,14,16),(A,30,32),(A,46,48)). NOT (2,4)/(5,7).
  </verify>
  <done>
All 37 `test_generators` tests pass (GREEN). The multi-pick branch uses `_even_starts` (even spacing); the count=1 centered path is unchanged; segments are disjoint and spread across the chain; signature/return shape/purity preserved. Committed as `fix(quick-005): spread multi-pick segments evenly across the chain`.
  </done>
</task>

</tasks>

<verification>
- `python3.6 -m unittest tests.test_generators -v` (from `pymol/`) -> 37 tests, OK (exit 0).
- `python3.6 -m py_compile pymol/biochemeleon/generators.py` -> exit 0 (syntax clean).
- Purity: `grep -rnE "from pymol|import pymol|import numpy|from numpy" pymol/biochemeleon/generators.py` -> no output (module stays pure, WSL-testable).
- Regression: the 7-residue count=2 case (`test_disjoint_segments_multi_count`) still yields disjoint, non-N-term segments (slack=1 forces near-adjacent placement, which is correct — there is no room to spread). The count=1 centered path is byte-identical.

Optional integration guard (only if context budget allows; NOT required for "done"): stage and run the headless Phase 11 smoke which calls `pick_segments(build_cas_by_chain(), 2)` on 1ubq (76 residues) and asserts 2 disjoint mid-chain hiders + single-state + registry. Per AGENTS.md:
```
bash wsl2win_cp.sh && mkdir -p tmp/bioCHEMeleon/smoke && cp pymol/smoke/phase11_smoke.py tmp/bioCHEMeleon/smoke/ 2>/dev/null
cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase11_smoke.py" 2>&1 | tail -50
```
This proves no integration regression on a real 76-residue chain (the smoke's Section E reads pre-captured coords for ANY middle resi via the full-chain `orig_ca_coords` dict, so the new spread positions are covered).
</verification>

<success_criteria>
- 2+ cartoon/ribbon hider segments on a long chain are spread across the chain (large interior gap), not clustered back-to-back near the N-term.
- A single hider (count=1) is still the centered mid-chain window.
- All 37 `test_generators` unit tests pass in WSL (no PyMOL needed).
- `generators.py` remains pure (no `pymol`/`numpy` import); signature and return shape unchanged.
- Two commits: `test(quick-005):` (RED tests) then `fix(quick-005):` (GREEN fix).
</success_criteria>

<output>
After completion, create `.planning/quick/005-spread-cartoon-segments/005-SUMMARY.md`.
</output>
