"""Tests for biochemeleon.generators - pure sphere-hider generator.

Pure-layer tests (no PyMOL needed). generators.py imports only stdlib
``random`` (NO ``from pymol``), but biochemeleon/__init__.py does
``from pymol.Qt import ...`` at module level, so we stub pymol/pymol.Qt
via sys.modules (same pattern as tests/test_registry.py lines 19-21
and tests/test_setup_state.py lines 13-15) before importing
biochemeleon.*.

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

from biochemeleon.generators import generate_sphere_positions


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


if __name__ == '__main__':
    unittest.main(verbosity=2)
