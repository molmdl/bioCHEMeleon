"""Tests for biochemeleon.generators - pure hider generators.

Pure-layer tests (no PyMOL needed). generators.py imports only stdlib
``random`` (NO ``from pymol``), but biochemeleon/__init__.py does
``from pymol.Qt import ...`` at module level, so we stub pymol/pymol.Qt
via sys.modules (same pattern as tests/test_registry.py lines 19-21
and tests/test_setup_state.py lines 13-15) before importing
biochemeleon.*.

Covers (Phase 4): ``generate_sphere_positions`` (bounding-box RNG).
Covers (Phase 5): ``generate_line_stick_offsets`` (small [-1,1] offsets
for line/stick hiders near real neighbors) + ``pick_terminal_residues``
(C-terminus selection for cartoon "extend-at-terminal" hiders).

Run: python3.6 -m unittest tests.test_generators -v
Or:  python3.6 tests/test_generators.py
"""
import os
import sys
import math
import unittest
from unittest.mock import MagicMock

# Stub pymol so importing biochemeleon.* (whose __init__.py does
# `from pymol.Qt import ...`) doesn't fail in WSL without PyMOL.
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()

# Ensure repo root is on sys.path when run as a script
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from biochemeleon.generators import (
    generate_sphere_positions,
    generate_line_stick_offsets,
    pick_terminal_residues,
    pick_segments,
    generate_middle_displacement,
    randomize_per_rep,
)


class TestGenerateSpherePositions(unittest.TestCase):
    """Test generate_sphere_positions(extent, n, seed).

    Pure geometry: given ``extent`` (the ``[[xmin,ymin,zmin],
    [xmax,ymax,zmax]]`` list returned by ``cmd.get_extent``) and ``n``,
    return a list of ``n`` distinct ``[x,y,z]`` lists drawn
    uniform-random inside the bounding box. A ``seed`` makes output
    deterministic (testability).
    """

    def test_count(self):
        """n=5 -> len==5 (returns exactly n positions for n > 0)."""
        positions = generate_sphere_positions([[0, 0, 0], [10, 10, 10]], 5)
        self.assertEqual(len(positions), 5)

    def test_bounds(self):
        """extent [[0,0,0],[10,10,10]], n=10 -> every coord in [0,10]."""
        extent = [[0, 0, 0], [10, 10, 10]]
        positions = generate_sphere_positions(extent, 10)
        self.assertEqual(len(positions), 10)
        for pos in positions:
            for coord in pos:
                self.assertGreaterEqual(coord, 0)
                self.assertLessEqual(coord, 10)

    def test_seed_determinism(self):
        """Two calls with seed=42 -> equal (element-for-element)."""
        extent = [[0, 0, 0], [10, 10, 10]]
        first = generate_sphere_positions(extent, 5, seed=42)
        second = generate_sphere_positions(extent, 5, seed=42)
        self.assertEqual(first, second)

    def test_seed_difference(self):
        """seed=1 vs seed=2 -> not equal (different seeds differ)."""
        extent = [[0, 0, 0], [10, 10, 10]]
        first = generate_sphere_positions(extent, 5, seed=1)
        second = generate_sphere_positions(extent, 5, seed=2)
        self.assertNotEqual(first, second)

    def test_n_zero(self):
        """n=0 -> == [] (no error, empty list)."""
        positions = generate_sphere_positions([[0, 0, 0], [10, 10, 10]], 0)
        self.assertEqual(positions, [])

    def test_n_one(self):
        """n=1 -> len==1 (single position)."""
        positions = generate_sphere_positions([[0, 0, 0], [10, 10, 10]], 1)
        self.assertEqual(len(positions), 1)

    def test_negative_extent(self):
        """extent [[10,10,10],[0,0,0]], n=3 -> len==3, no crash.

        rng.uniform handles min>max by drawing in [max,min]; the
        function must not crash on a reversed bounding box, and coords
        land in [0,10] since uniform handles reversed bounds.
        """
        extent = [[10, 10, 10], [0, 0, 0]]
        positions = generate_sphere_positions(extent, 3)
        self.assertEqual(len(positions), 3)
        # Coords land in [0, 10] since uniform handles reversed bounds
        for pos in positions:
            for coord in pos:
                self.assertGreaterEqual(coord, 0)
                self.assertLessEqual(coord, 10)

    def test_returns_lists(self):
        """Each position is a 3-element list of floats (not tuple, not nested)."""
        positions = generate_sphere_positions([[0, 0, 0], [10, 10, 10]], 4)
        for pos in positions:
            self.assertIsInstance(pos, list)
            self.assertEqual(len(pos), 3)
            for coord in pos:
                self.assertIsInstance(coord, float)


class TestGenerateLineStickOffsets(unittest.TestCase):
    """Test generate_line_stick_offsets(n, seed).

    Pure geometry: returns a list of ``n`` small ``[dx, dy, dz]`` offset
    vectors, each component drawn uniform-random in ``[-1.0, 1.0]``
    Angstrom, so a line/stick hider sits near a real neighbor (short
    bond, blends with real bonds - 05-RESEARCH.md Sec2 Q3: "0.5-1.0 A so
    the bond is visible but short"). A ``seed`` makes output
    deterministic (testability). Mirrors TestGenerateSpherePositions.
    """

    def test_count(self):
        """n=5 -> len==5 (returns exactly n offsets for n > 0)."""
        offsets = generate_line_stick_offsets(5)
        self.assertEqual(len(offsets), 5)

    def test_bounds(self):
        """n=10, seed=1 -> every component of every offset in [-1.0, 1.0]."""
        offsets = generate_line_stick_offsets(10, seed=1)
        self.assertEqual(len(offsets), 10)
        for off in offsets:
            for comp in off:
                self.assertGreaterEqual(comp, -1.0)
                self.assertLessEqual(comp, 1.0)

    def test_seed_determinism(self):
        """Two calls with seed=42 -> equal (element-for-element)."""
        first = generate_line_stick_offsets(5, seed=42)
        second = generate_line_stick_offsets(5, seed=42)
        self.assertEqual(first, second)

    def test_seed_difference(self):
        """seed=1 vs seed=2 -> not equal (different seeds differ)."""
        first = generate_line_stick_offsets(5, seed=1)
        second = generate_line_stick_offsets(5, seed=2)
        self.assertNotEqual(first, second)

    def test_n_zero(self):
        """n=0 -> == [] (no error, empty list)."""
        offsets = generate_line_stick_offsets(0)
        self.assertEqual(offsets, [])

    def test_n_one(self):
        """n=1 -> len==1 (single offset)."""
        offsets = generate_line_stick_offsets(1)
        self.assertEqual(len(offsets), 1)

    def test_returns_lists(self):
        """Each offset is a 3-element list of floats (not tuple, not nested)."""
        offsets = generate_line_stick_offsets(4, seed=7)
        for off in offsets:
            self.assertIsInstance(off, list)
            self.assertEqual(len(off), 3)
            for comp in off:
                self.assertIsInstance(comp, float)


class TestPickTerminalResidues(unittest.TestCase):
    """Test pick_terminal_residues(cas_by_chain, max_chains).

    Pure selection: ``cas_by_chain`` is ``{chain: [(resi, ca_id), ...]}``
    (produced by the caller's ``cmd.iterate`` over polymer C-alpha atoms
    - 05-RESEARCH.md Sec3 Q8 Step 1). Returns a list of
    ``(chain, terminal_resi, is_c_terminus)`` tuples, one per chain,
    sorted longest-chain-first (most C-alpha entries), each at the
    N-terminus (min resi, ``is_c_terminus=False``). Capped at ``max_chains``
    if not None. Used by ``__init__._on_start`` to build cartoon hider
    payloads (one terminal extension per chain - 05-RESEARCH.md Sec7
    Open Risk 5: attaching many to one terminus chains them, so cap at
    one per chain). MVP uses the N-terminus (NOT the C-terminus): the
    C-terminus C carries an OXT that blocks the residue-attach primitive
    at runtime (verified in the Phase 5 headless smoke -- see
    ``biochemeleon/generators.py`` docstring for the OXT rationale).
    """

    def test_empty(self):
        """pick_terminal_residues({}) -> [] (no error on empty dict)."""
        self.assertEqual(pick_terminal_residues({}), [])

    def test_single_chain(self):
        """Single chain -> [(chain, min_resi, False)] (N-terminus = min resi)."""
        cas = {'A': [(1, 'id1'), (2, 'id2'), (76, 'id76')]}
        self.assertEqual(pick_terminal_residues(cas),
                         [('A', 1, False)])

    def test_multi_chain_longest_first(self):
        """Two chains, A strictly longer -> A first, both N-terminus."""
        cas = {'A': [(1, 1), (2, 2), (3, 3)], 'B': [(1, 1), (2, 2)]}
        self.assertEqual(pick_terminal_residues(cas),
                         [('A', 1, False), ('B', 1, False)])

    def test_max_chains_cap(self):
        """max_chains=1 -> only the longest chain (single-element list)."""
        cas = {'A': [(1, 1), (2, 2), (3, 3)], 'B': [(1, 1), (2, 2)]}
        self.assertEqual(pick_terminal_residues(cas, max_chains=1),
                         [('A', 1, False)])

    def test_max_chains_none(self):
        """max_chains=None -> no cap (all chains returned)."""
        cas = {'A': [(1, 1)], 'B': [(1, 1)]}
        out = pick_terminal_residues(cas, max_chains=None)
        self.assertEqual(len(out), 2)

    def test_is_c_terminus_always_false(self):
        """Every returned tuple has is_c_terminus==False (MVP = N-term only)."""
        cas = {'A': [(1, 1), (2, 2), (3, 3)], 'B': [(1, 1), (2, 2)],
               'C': [(5, 5), (10, 10)]}
        out = pick_terminal_residues(cas)
        for tup in out:
            self.assertEqual(len(tup), 3)
            self.assertFalse(tup[2], "is_c_terminus must be False (MVP N-term)")


class TestPickSegments(unittest.TestCase):
    """Test pick_segments(cas_by_chain, count, segment_size=3).

    Pure selection (Phase 11): ``cas_by_chain`` is
    ``{chain: [(resi, ca_id), ...]}`` (the SAME shape
    ``_prepare_and_start`` builds). Returns a list of
    ``(chain, start_resi, end_resi)`` 3-tuples -- DISJOINT mid-chain
    segments (Bug 1 fix: ranges non-overlapping so two alt-conf hiders
    never share a clickable middle CA id). Skips chains with fewer than
    ``segment_size`` residues. Longer chains first (determinism). Mid-chain
    (NOT terminal): the window is centered on the chain interior so the
    endpoints are not the N/C terminus when the chain is longer than
    ``segment_size`` -- this is the whole point of Phase 11 replacing the
    Phase 5 terminal-extension cartoon hider.
    """

    def test_empty_returns_empty(self):
        """pick_segments({}) -> [] (no error on empty dict)."""
        self.assertEqual(pick_segments({}, 1), [])

    def test_single_chain_three_residues(self):
        """Chain exactly segment_size -> whole chain is one mid-chain segment."""
        cas = {'A': [(1, 101), (2, 102), (3, 103)]}
        result = pick_segments(cas, count=1, segment_size=3)
        self.assertEqual(result, [('A', 1, 3)])

    def test_single_chain_five_residues_picks_mid_segment(self):
        """5 residues, count=1, size=3 -> centered window [2,4] (NOT terminal).

        start_resi == 2 and end_resi == 4: the MIDDLE 3-residue window, not
        the N-term [1,3] nor the C-term [3,5]. This is the Phase 11
        replacement of terminal-extension -- the segment is mid-chain.
        """
        cas = {'A': [(1, 101), (2, 102), (3, 103), (4, 104), (5, 105)]}
        result = pick_segments(cas, count=1, segment_size=3)
        self.assertEqual(len(result), 1)
        chain, start_resi, end_resi = result[0]
        self.assertEqual(chain, 'A')
        self.assertEqual(start_resi, 2, "mid-chain window starts at resi 2, not N-term 1")
        self.assertEqual(end_resi, 4, "mid-chain window ends at resi 4, not C-term 5")

    def test_disjoint_segments_multi_count(self):
        """7 residues, count=2, size=3 -> 2 DISJOINT mid-chain segments (Bug 1).

        Ranges must NOT overlap (no shared resi -- two alt-conf hiders must
        not share a clickable middle CA id). The first segment must NOT
        start at the N-term resi 1 (mid-chain, not terminal-extension).

        Note: with 7 residues and count=2 size-3, two disjoint windows need
        6 of 7 residues; avoiding BOTH terminals leaves only 5 (< 6), so the
        second segment necessarily reaches the C-term. The PRIMARY mid-chain
        intent (avoiding N-term extension, which is what Phase 11 replaces)
        is captured by the first segment not starting at resi 1.
        """
        cas = {'A': [(1, 101), (2, 102), (3, 103), (4, 104),
                     (5, 105), (6, 106), (7, 107)]}
        result = pick_segments(cas, count=2, segment_size=3)
        self.assertEqual(len(result), 2)
        # Sort by start_resi to check disjointness deterministically
        segs = sorted(result, key=lambda t: t[1])
        # Disjoint: end of first < start of second (no shared resi)
        self.assertLess(segs[0][2], segs[1][1],
                        "Segments must be disjoint (end_first < start_second)")
        # Mid-chain: first segment must NOT start at the N-term (resi 1)
        self.assertNotEqual(segs[0][1], 1,
                            "First segment must not start at N-term resi 1")
        # No segment may be the pure N-term window (1,3)
        for seg in segs:
            self.assertNotEqual((seg[1], seg[2]), (1, 3),
                                "No segment may be the pure N-term window [1-3]")

    def test_skips_short_chains(self):
        """Chains with < segment_size residues are skipped."""
        cas = {'A': [(1, 101), (2, 102)],               # 2 residues < 3 -> skip
               'B': [(1, 201), (2, 202), (3, 203), (4, 204)]}  # 4 residues -> ok
        result = pick_segments(cas, count=2, segment_size=3)
        # Chain A skipped; only chain B yields (at most 1 disjoint size-3 seg
        # fits in 4 residues), so len <= 2 and all from chain B.
        self.assertGreaterEqual(len(result), 1)
        for seg in result:
            self.assertEqual(seg[0], 'B', "short chain A must be skipped")
        # No segment from chain A
        self.assertFalse(any(seg[0] == 'A' for seg in result))

    def test_longest_chain_first(self):
        """Two chains of unequal length, count=2 -> longer chain's segment first."""
        cas = {'A': [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)],  # 5 residues
               'B': [(1, 1), (2, 2), (3, 3)]}                  # 3 residues
        result = pick_segments(cas, count=2, segment_size=3)
        self.assertEqual(len(result), 2)
        # Longer chain (A) comes first
        self.assertEqual(result[0][0], 'A',
                         "longer chain must come first (determinism)")
        self.assertEqual(result[1][0], 'B')

    def test_count_cap(self):
        """count > available disjoint segments -> returns only as many as fit."""
        # 4 residues -> at most 1 disjoint size-3 segment; count=5 must cap.
        cas = {'A': [(1, 1), (2, 2), (3, 3), (4, 4)]}
        result = pick_segments(cas, count=5, segment_size=3)
        self.assertLessEqual(len(result), 5)
        self.assertGreaterEqual(len(result), 1)
        # All disjoint (no overlap forced to meet count)
        segs = sorted(result, key=lambda t: t[1])
        for i in range(len(segs) - 1):
            self.assertLess(segs[i][2], segs[i + 1][1],
                            "segments must remain disjoint even when count caps")

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


class TestGenerateMiddleDisplacement(unittest.TestCase):
    """Test generate_middle_displacement(n, seed, magnitude).

    Pure RNG (Phase 11): returns a list of ``n`` ``[dx, dy, dz]`` lists --
    one random UNIT vector per hider times ``magnitude``. The SAME offset
    is applied to ALL middle atoms of one hider (rigid translation --
    Pitfall 15: displace ALL middle atoms, NOT just CA). Same seed ->
    identical vectors (deterministic, testable). Default magnitude 1.5 A
    (research: 1.5 A recommended, 2.0 A ceiling). Mirrors the
    ``random.Random(seed)`` style of ``generate_sphere_positions`` /
    ``generate_line_stick_offsets``.
    """

    def test_count(self):
        """n=5, seed=42 -> len==5, each a 3-element [dx,dy,dz] list."""
        vecs = generate_middle_displacement(5, seed=42)
        self.assertEqual(len(vecs), 5)
        for v in vecs:
            self.assertIsInstance(v, list)
            self.assertEqual(len(v), 3)

    def test_magnitude(self):
        """n=1, magnitude=1.5 -> Euclidean norm == 1.5 (unit vec x magnitude)."""
        vecs = generate_middle_displacement(1, seed=42, magnitude=1.5)
        self.assertEqual(len(vecs), 1)
        dx, dy, dz = vecs[0]
        norm = math.sqrt(dx * dx + dy * dy + dz * dz)
        self.assertAlmostEqual(norm, 1.5, places=9)

    def test_magnitude_default(self):
        """Default magnitude=1.5 -> norm == 1.5."""
        vecs = generate_middle_displacement(1, seed=42)
        self.assertEqual(len(vecs), 1)
        dx, dy, dz = vecs[0]
        norm = math.sqrt(dx * dx + dy * dy + dz * dz)
        self.assertAlmostEqual(norm, 1.5, places=9)

    def test_deterministic_seed(self):
        """Same seed -> identical vectors (reproducible displacements)."""
        first = generate_middle_displacement(3, seed=7)
        second = generate_middle_displacement(3, seed=7)
        self.assertEqual(first, second)

    def test_different_seed_differs(self):
        """Different seeds -> different vectors (almost surely)."""
        first = generate_middle_displacement(3, seed=1)
        second = generate_middle_displacement(3, seed=2)
        self.assertNotEqual(first, second)

    def test_zero_count(self):
        """n=0 -> [] (no error, empty list)."""
        self.assertEqual(generate_middle_displacement(0, seed=42), [])

    def test_rigid_per_hider(self):
        """Each returned vector is ONE [dx,dy,dz] (one unit vector per hider).

        The caller applies the SAME vector to ALL middle atoms of that one
        hider (rigid translation -- Pitfall 15). The function returns one
        vector PER HIDER (not per atom); assert each is a single 3-list.
        """
        vecs = generate_middle_displacement(4, seed=42, magnitude=1.5)
        self.assertEqual(len(vecs), 4)
        for v in vecs:
            self.assertIsInstance(v, list)
            self.assertEqual(len(v), 3)
            for comp in v:
                self.assertIsInstance(comp, float)
            # Each vector is a unit vector x magnitude (rigid translation)
            norm = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
            self.assertAlmostEqual(norm, 1.5, places=9)


class TestRandomizePerRep(unittest.TestCase):
    """Test randomize_per_rep(hider_count, game_reps, seed) -- quick-008.

    Pure, dependency-injected distribution (mirrors the per-rep loop in
    ``setup_state.randomize_state`` lines 282-292, but ``game_reps`` is a
    parameter so this module stays pure / WSL-unit-testable). Used by
    ``__init__._continue_after_large_demo_fetch`` when the user sets a
    total ``hider_count`` without per-rep counts (``per_rep={}``) -- instead
    of the old all-spheres fallback, the count is spread across a random
    subset of reps so the game mixes representations (parity with the
    Randomize button).

    Guarantees at least one rep with count > 0 when ``hider_count > 0``
    (avoids an empty per_rep that would loop back to a fallback). The sum
    of returned counts may be < hider_count (leftover unassigned) -- same
    property as ``randomize_state``.

    ``GAME_REPS`` is a LOCAL const here (NOT imported) to keep the test
    independent of the source-of-truth list.
    """

    GAME_REPS = ['lines', 'sticks', 'spheres', 'cartoon', 'ribbon']

    def test_zero_hider_count(self):
        """hider_count=0 -> {} (no hiders, no crash)."""
        self.assertEqual(randomize_per_rep(0, self.GAME_REPS), {})

    def test_negative_hider_count(self):
        """hider_count=-5 -> {} (count <= 0 short-circuits to empty)."""
        self.assertEqual(randomize_per_rep(-5, self.GAME_REPS), {})

    def test_empty_game_reps(self):
        """game_reps=[] -> {} (no reps to distribute across)."""
        self.assertEqual(randomize_per_rep(5, []), {})

    def test_non_empty_when_count_positive(self):
        """For every seed in range(20), result is non-empty with >=1 rep count > 0.

        This is the core quick-008 guarantee: the caller must NOT loop back
        to a fallback, so a positive hider_count always yields at least one
        rep with a positive count.
        """
        for seed in range(20):
            result = randomize_per_rep(10, self.GAME_REPS, seed=seed)
            self.assertTrue(result,
                            "result must be non-empty for hider_count>0 (seed=%d)" % seed)
            self.assertTrue(any(v > 0 for v in result.values()),
                            "at least one rep must have count > 0 (seed=%d)" % seed)

    def test_all_keys_in_game_reps(self):
        """Every key in result is a valid rep in GAME_REPS (no bogus keys)."""
        for seed in range(30):
            result = randomize_per_rep(10, self.GAME_REPS, seed=seed)
            for k in result:
                self.assertIn(k, self.GAME_REPS,
                              "key %r not in GAME_REPS (seed=%d)" % (k, seed))

    def test_values_positive(self):
        """Every value is > 0 (no zero-count entries leak into the dict)."""
        for seed in range(30):
            result = randomize_per_rep(10, self.GAME_REPS, seed=seed)
            for k, v in result.items():
                self.assertGreater(v, 0,
                    "count for %r must be > 0, got %d (seed=%d)" % (k, v, seed))

    def test_sum_le_hider_count(self):
        """sum(counts) <= hider_count for many seeds (leftover unassigned)."""
        for seed in range(30):
            result = randomize_per_rep(10, self.GAME_REPS, seed=seed)
            self.assertLessEqual(sum(result.values()), 10,
                "sum %d exceeds hider_count 10 (seed=%d)" % (sum(result.values()), seed))

    def test_hider_count_one(self):
        """hider_count=1, seed=42 -> exactly one entry with value 1 (sum == 1).

        With count=1 the per-rep loop can draw 0 for the first rep(s); the
        non-empty guarantee then puts the full count (1) on a random rep.
        Either way the result is a single rep with count 1.
        """
        result = randomize_per_rep(1, self.GAME_REPS, seed=42)
        self.assertEqual(len(result), 1, "hider_count=1 -> exactly one rep")
        self.assertEqual(sum(result.values()), 1, "sum must equal hider_count=1")

    def test_seed_determinism(self):
        """Same seed -> identical result (reproducible distribution)."""
        first = randomize_per_rep(10, self.GAME_REPS, seed=42)
        second = randomize_per_rep(10, self.GAME_REPS, seed=42)
        self.assertEqual(first, second)

    def test_seed_difference(self):
        """Different seeds -> (almost surely) different results."""
        first = randomize_per_rep(10, self.GAME_REPS, seed=1)
        second = randomize_per_rep(10, self.GAME_REPS, seed=2)
        self.assertNotEqual(first, second)


if __name__ == '__main__':
    unittest.main(verbosity=2)
