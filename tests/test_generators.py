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


if __name__ == '__main__':
    unittest.main(verbosity=2)
