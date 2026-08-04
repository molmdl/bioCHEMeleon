"""Tests for biochemeleon.setup_state - pure Python, no PyMOL needed.

Run: python3.6 -m unittest tests.test_setup_state -v
Or:  python3.6 tests/test_setup_state.py
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

from biochemeleon.setup_state import (
    GAME_REPS, DEMO_MANIFEST, DEFAULTS, SETUP_FORMAT,
    hider_count_cap, randomize_state, validate_state,
)


class TestHiderCountCap(unittest.TestCase):
    """Test the hider_count_cap formula: max(1, min(50, atom_count // 50))."""

    def test_zero_atoms(self):
        self.assertEqual(hider_count_cap(0), 1)

    def test_negative_atoms(self):
        self.assertEqual(hider_count_cap(-5), 1)

    def test_small_protein(self):
        # 1znf ~212 atoms -> 212 // 50 = 4
        self.assertEqual(hider_count_cap(212), 4)

    def test_medium(self):
        # 1K8P ~555 atoms -> 555 // 50 = 11
        self.assertEqual(hider_count_cap(555), 11)

    def test_large(self):
        # 2500 // 50 = 50, capped
        self.assertEqual(hider_count_cap(2500), 50)

    def test_huge(self):
        # 100k atoms -> hard cap of 50
        self.assertEqual(hider_count_cap(100000), 50)

    def test_just_under_cap(self):
        # 2499 // 50 = 49 (just under the cap boundary)
        self.assertEqual(hider_count_cap(2499), 49)


class TestDefaults(unittest.TestCase):
    """Test the DEFAULTS dict shape and values."""

    def test_has_all_keys(self):
        self.assertEqual(
            set(DEFAULTS.keys()),
            {"format", "target_mode", "selected_object", "pdb_code",
             "demo_id", "hider_count", "lock_scene", "per_rep",
             "difficulty_easy"},
        )

    def test_format(self):
        self.assertEqual(DEFAULTS["format"], "biochemeleon-setup-v1")

    def test_target_mode(self):
        self.assertEqual(DEFAULTS["target_mode"], "loaded")

    def test_demo_id(self):
        self.assertEqual(DEFAULTS["demo_id"], "1znf")

    def test_hider_count(self):
        self.assertEqual(DEFAULTS["hider_count"], 10)

    def test_lock_scene(self):
        self.assertEqual(DEFAULTS["lock_scene"], False)

    def test_per_rep(self):
        self.assertEqual(DEFAULTS["per_rep"], {})

    def test_difficulty(self):
        self.assertEqual(DEFAULTS["difficulty_easy"], True)


class TestGameReps(unittest.TestCase):
    """Test the GAME_REPS list (the 5 in-scope representations)."""

    def test_reps(self):
        self.assertEqual(
            GAME_REPS, ['lines', 'sticks', 'spheres', 'cartoon', 'ribbon'])

    def test_no_surface(self):
        self.assertNotIn('surface', GAME_REPS)

    def test_count(self):
        self.assertEqual(len(GAME_REPS), 5)


class TestDemoManifest(unittest.TestCase):
    """Test the DEMO_MANIFEST dict (6 bundled demos)."""

    def test_count(self):
        self.assertEqual(len(DEMO_MANIFEST), 6)

    def test_ids(self):
        self.assertEqual(
            set(DEMO_MANIFEST.keys()),
            {'1znf', '1xdn', '5e54', '1k8p', '2qbz', '4wb3'})

    def test_entry_shape(self):
        for did, entry in DEMO_MANIFEST.items():
            self.assertEqual(
                set(entry.keys()),
                {'category', 'type', 'difficulty', 'file'},
                msg="Entry %r has wrong keys: %r" % (did, entry.keys()))

    def test_1znf(self):
        e = DEMO_MANIFEST['1znf']
        self.assertEqual(e['category'], 'Protein')
        self.assertEqual(e['difficulty'], 'easy')
        self.assertEqual(e['file'], '1znf.pdb')

    def test_4wb3(self):
        e = DEMO_MANIFEST['4wb3']
        self.assertEqual(e['category'], 'Mixed')
        self.assertEqual(e['difficulty'], 'mixed')

    def test_files_lowercase(self):
        for did, entry in DEMO_MANIFEST.items():
            self.assertEqual(entry['file'], "%s.pdb" % did,
                msg="file for %r should be %r.pdb, got %r"
                    % (did, did, entry['file']))


class TestRandomizeState(unittest.TestCase):
    """Test randomize_state determinism + validity."""

    def test_deterministic(self):
        self.assertEqual(randomize_state(seed=42), randomize_state(seed=42))

    def test_different_seeds_differ(self):
        # Overwhelmingly likely two distinct seeds produce distinct states.
        self.assertNotEqual(randomize_state(seed=42), randomize_state(seed=99))

    def test_has_all_keys(self):
        result = randomize_state(seed=42)
        self.assertEqual(set(result.keys()), set(DEFAULTS.keys()))

    def test_format(self):
        self.assertEqual(
            randomize_state(seed=42)["format"], "biochemeleon-setup-v1")

    def test_target_mode_valid(self):
        self.assertIn(randomize_state(seed=42)["target_mode"],
                      ["loaded", "fetch", "demo"])

    def test_demo_id_valid(self):
        self.assertIn(randomize_state(seed=42)["demo_id"], DEMO_MANIFEST)

    def test_hider_count_positive(self):
        self.assertGreaterEqual(randomize_state(seed=42)["hider_count"], 1)

    def test_hider_count_capped_no_atom_count(self):
        self.assertLessEqual(randomize_state(seed=42)["hider_count"], 50)

    def test_hider_count_capped_with_atom_count(self):
        result = randomize_state(seed=42, atom_count=212)
        self.assertLessEqual(result["hider_count"], hider_count_cap(212))

    def test_per_rep_keys_valid(self):
        per_rep = randomize_state(seed=42)["per_rep"]
        for rep in per_rep:
            self.assertIn(rep, GAME_REPS)

    def test_per_rep_values_positive(self):
        per_rep = randomize_state(seed=42)["per_rep"]
        for v in per_rep.values():
            self.assertGreater(v, 0)

    def test_per_rep_sum_within_hider_count(self):
        result = randomize_state(seed=42)
        self.assertLessEqual(
            sum(result["per_rep"].values()), result["hider_count"])

    def test_per_rep_types(self):
        per_rep = randomize_state(seed=42)["per_rep"]
        for v in per_rep.values():
            self.assertIsInstance(v, int)


class TestValidateState(unittest.TestCase):
    """Test validate_state validation + clamping."""

    def test_empty_returns_defaults(self):
        self.assertEqual(validate_state({}), {**DEFAULTS})

    def test_idempotent_on_valid(self):
        self.assertEqual(validate_state(DEFAULTS), DEFAULTS)

    def test_does_not_mutate_input(self):
        original = {"hider_count": 999}
        validate_state(original)
        self.assertEqual(original["hider_count"], 999)

    def test_clamps_hider_count_high(self):
        self.assertLessEqual(validate_state({"hider_count": 999})["hider_count"], 50)

    def test_clamps_hider_count_with_atom_count(self):
        result = validate_state({"hider_count": 999}, atom_count=212)
        self.assertLessEqual(result["hider_count"], hider_count_cap(212))

    def test_clamps_hider_count_low(self):
        self.assertEqual(validate_state({"hider_count": -5})["hider_count"], 1)

    def test_fills_missing_keys(self):
        result = validate_state({"hider_count": 5})
        self.assertIn("target_mode", result)
        self.assertEqual(result["target_mode"], "loaded")

    def test_invalid_target_mode_defaults(self):
        self.assertEqual(
            validate_state({"target_mode": "bogus"})["target_mode"], "loaded")

    def test_invalid_demo_id_defaults(self):
        self.assertEqual(
            validate_state({"demo_id": "bogus"})["demo_id"], "1znf")

    def test_drops_invalid_per_rep_keys(self):
        result = validate_state({"per_rep": {"surface": 5, "cartoon": 3}})
        self.assertNotIn("surface", result["per_rep"])
        self.assertIn("cartoon", result["per_rep"])

    def test_returns_new_dict(self):
        state = {**DEFAULTS}
        result = validate_state(state)
        self.assertIsNot(result, state)


if __name__ == '__main__':
    unittest.main(verbosity=2)
