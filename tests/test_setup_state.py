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
    GAME_REPS, DEMO_MANIFEST, DEFAULTS, SETUP_FORMAT, PDB_POOL,
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
             "difficulty_easy", "lock_source", "pdb_pool"},
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


class TestPdbPool(unittest.TestCase):
    """Test the PDB_POOL constant (34 verified RCSB entries)."""

    def test_is_list(self):
        self.assertIsInstance(PDB_POOL, list)

    def test_count_in_range(self):
        # 34 expected; allow 30-40 for forward-compat
        self.assertGreaterEqual(len(PDB_POOL), 30)
        self.assertLessEqual(len(PDB_POOL), 40)

    def test_all_lowercase_alnum_4char(self):
        for pid in PDB_POOL:
            self.assertEqual(len(pid), 4,
                msg="PDB id %r is not 4 chars" % pid)
            self.assertTrue(pid.isalnum(),
                msg="PDB id %r is not alphanumeric" % pid)
            self.assertTrue(pid.islower(),
                msg="PDB id %r is not lowercase" % pid)

    def test_no_duplicates(self):
        self.assertEqual(len(set(PDB_POOL)), len(PDB_POOL))

    def test_contains_bundled_demos(self):
        for did in ('1znf', '1xdn', '5e54', '1k8p', '2qbz', '4wb3'):
            self.assertIn(did, PDB_POOL, msg="bundled demo %r missing" % did)

    def test_mixed_categories(self):
        # At least one each: protein, DNA, RNA, and two different hybrid
        # classes (protein-DNA hybrid and DNA-oligosaccharide drug hybrid).
        self.assertIn('1ubq', PDB_POOL)   # protein
        self.assertIn('1bna', PDB_POOL)   # DNA
        self.assertIn('1ehz', PDB_POOL)   # RNA
        self.assertIn('1aay', PDB_POOL)   # protein-DNA hybrid
        self.assertIn('1ekh', PDB_POOL)   # DNA-oligosaccharide drug hybrid


class TestDefaultsExtended(unittest.TestCase):
    """Test the 2 new DEFAULTS keys (lock_source, pdb_pool)."""

    def test_lock_source_default(self):
        self.assertEqual(DEFAULTS["lock_source"], False)

    def test_pdb_pool_default(self):
        self.assertEqual(DEFAULTS["pdb_pool"], PDB_POOL)

    def test_has_11_keys(self):
        self.assertEqual(len(DEFAULTS), 11)

    def test_new_keys_present(self):
        self.assertIn("lock_source", DEFAULTS)
        self.assertIn("pdb_pool", DEFAULTS)


class TestValidateStatePerRepSum(unittest.TestCase):
    """Test that validate_state clamps per_rep sum to <= hider_count (Gap 2 pure)."""

    def test_sum_clamped_high(self):
        result = validate_state({"hider_count": 3, "per_rep": {"spheres": 5, "cartoon": 5}})
        self.assertLessEqual(sum(result["per_rep"].values()), 3)

    def test_sum_clamped_keeps_first(self):
        # hider_count=2, per_rep has 3 entries of 1 each: first 2 kept, 3rd dropped
        result = validate_state({"hider_count": 2, "per_rep": {"spheres": 1, "cartoon": 1, "lines": 1}})
        self.assertEqual(result["per_rep"], {"spheres": 1, "cartoon": 1})

    def test_sum_within_budget_unchanged(self):
        # sum=5 <= hider_count=5, unchanged
        result = validate_state({"hider_count": 5, "per_rep": {"spheres": 2, "cartoon": 3}})
        self.assertEqual(result["per_rep"], {"spheres": 2, "cartoon": 3})

    def test_sum_clamp_after_hider_count_clamp(self):
        # hider_count=999 clamped to cap=2 (atom_count=100), then per_rep clamped to <= 2
        result = validate_state({"hider_count": 999, "per_rep": {"spheres": 100}}, atom_count=100)
        cap = hider_count_cap(100)
        self.assertLessEqual(sum(result["per_rep"].values()), cap)

    def test_empty_per_rep_unchanged(self):
        self.assertEqual(validate_state({"hider_count": 5, "per_rep": {}})["per_rep"], {})


class TestValidateStateNewFields(unittest.TestCase):
    """Test lock_source + pdb_pool validation in validate_state."""

    def test_lock_source_bool_coercion(self):
        self.assertEqual(validate_state({"lock_source": 1})["lock_source"], True)

    def test_lock_source_default_false(self):
        self.assertEqual(validate_state({})["lock_source"], False)

    def test_pdb_pool_default(self):
        self.assertEqual(validate_state({})["pdb_pool"], PDB_POOL)

    def test_pdb_pool_filters_invalid(self):
        # lowercase, 4-char alnum, dedupe — 1UBQ lowercased to 1ubq dupes out
        result = validate_state({"pdb_pool": ["1ubq", "INVALID", "12", "1UBQ", "1bna"]})
        self.assertEqual(result["pdb_pool"], ["1ubq", "1bna"])

    def test_pdb_pool_bounds_to_100(self):
        result = validate_state({"pdb_pool": ["1ubq"] * 200})
        self.assertLessEqual(len(result["pdb_pool"]), 100)

    def test_pdb_pool_non_list_defaults(self):
        self.assertEqual(validate_state({"pdb_pool": "not a list"})["pdb_pool"], PDB_POOL)

    def test_pdb_pool_empty_defaults(self):
        # empty user input -> DEFAULTS pool (Gap 4: never produce empty pool)
        self.assertEqual(validate_state({"pdb_pool": []})["pdb_pool"], PDB_POOL)


class TestRandomizeLockSource(unittest.TestCase):
    """Test lock_source preserves target mode + identifier (Gap 3)."""

    def test_lock_source_preserves_fetch(self):
        locked = {"target_mode": "fetch", "pdb_code": "1ubq",
                  "demo_id": "1znf", "selected_object": ""}
        result = randomize_state(seed=42, lock_source=True, locked_state=locked)
        self.assertEqual(result["target_mode"], "fetch")
        self.assertEqual(result["pdb_code"], "1ubq")

    def test_lock_source_preserves_loaded(self):
        locked = {"target_mode": "loaded", "selected_object": "myobj",
                  "pdb_code": "", "demo_id": "1znf"}
        result = randomize_state(seed=42, lock_source=True, locked_state=locked)
        self.assertEqual(result["target_mode"], "loaded")
        self.assertEqual(result["selected_object"], "myobj")

    def test_lock_source_preserves_demo(self):
        locked = {"target_mode": "demo", "demo_id": "5e54",
                  "selected_object": "", "pdb_code": ""}
        result = randomize_state(seed=42, lock_source=True, locked_state=locked)
        self.assertEqual(result["target_mode"], "demo")
        self.assertEqual(result["demo_id"], "5e54")

    def test_lock_source_still_randomizes_hiders(self):
        locked = {"target_mode": "demo", "demo_id": "5e54",
                  "selected_object": "", "pdb_code": ""}
        r1 = randomize_state(seed=42, lock_source=True, locked_state=locked)
        r2 = randomize_state(seed=99, lock_source=True, locked_state=locked)
        # hider composition still randomizes (count or per_rep differs)
        self.assertTrue(r1["hider_count"] != r2["hider_count"]
                        or r1["per_rep"] != r2["per_rep"])

    def test_lock_source_without_locked_state_ignored(self):
        # must not crash; behaves like lock_source=False
        result = randomize_state(seed=42, lock_source=True, locked_state=None)
        self.assertIsInstance(result, dict)


class TestRandomizePdbPool(unittest.TestCase):
    """Test pdb_pool drives fetch mode (Gap 4)."""

    def test_fetch_picks_from_pool(self):
        result = randomize_state(seed=42, pdb_pool=["1ubq", "1znf", "5e54"])
        if result["target_mode"] == "fetch":
            self.assertIn(result["pdb_code"], ["1ubq", "1znf", "5e54"])

    def test_fetch_never_empty_with_pool(self):
        for seed in range(100):
            result = randomize_state(seed=seed, pdb_pool=["1ubq", "1bna"])
            self.assertFalse(result["target_mode"] == "fetch" and not result["pdb_code"],
                msg="seed %d: fetch mode with empty pdb_code" % seed)

    def test_empty_pool_avoids_fetch(self):
        # empty pool -> never fetch mode (re-rolls to demo)
        for seed in range(100):
            result = randomize_state(seed=seed, pdb_pool=[])
            self.assertNotEqual(result["target_mode"], "fetch",
                msg="seed %d: empty pool should not produce fetch mode" % seed)

    def test_pool_param_none_uses_defaults(self):
        result = randomize_state(seed=42, pdb_pool=None)
        if result["target_mode"] == "fetch":
            self.assertIn(result["pdb_code"], PDB_POOL)

    def test_fetch_picks_from_pool_non_empty(self):
        pool = ["1ubq", "1bna", "1ehz", "1cqw"]
        found_fetch = False
        for seed in range(200):
            result = randomize_state(seed=seed, pdb_pool=pool)
            if result["target_mode"] == "fetch":
                found_fetch = True
                self.assertIn(result["pdb_code"], pool,
                    msg="seed %d: fetch pdb_code not in pool" % seed)
        self.assertTrue(found_fetch,
            msg="fetch mode never reached with non-empty pool across 200 seeds")


if __name__ == '__main__':
    unittest.main(verbosity=2)
