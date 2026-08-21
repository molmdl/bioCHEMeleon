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
    _validate_pdb_code,
    hider_count_cap, randomize_state, validate_state,
    TIER_LABELS, STRIP_RESN_MEMPROTMD, strip_resn_from_pdb,
    format_remaining,
    format_debrief_text,
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
    """Test the DEMO_MANIFEST dict (9 demos: 6 bundled + 3 fetched)."""

    def test_count(self):
        self.assertEqual(len(DEMO_MANIFEST), 9)

    def test_ids(self):
        self.assertEqual(
            set(DEMO_MANIFEST.keys()),
            {'1znf', '1xdn', '5e54', '1k8p', '2qbz', '4wb3',
             '1gzm', '3gp6', 'sasdpg4'})

    def test_entry_shape(self):
        expected = {'category', 'type', 'difficulty', 'source',
                    'source_id', 'fetch_url', 'cache_name', 'citation',
                    'strip'}
        for did, entry in DEMO_MANIFEST.items():
            self.assertEqual(set(entry.keys()), expected,
                msg="Entry %r has wrong keys: %r" % (did, set(entry.keys())))

    def test_1znf(self):
        e = DEMO_MANIFEST['1znf']
        self.assertEqual(e['category'], 'Protein')
        self.assertEqual(e['difficulty'], 'easy')
        self.assertEqual(e['cache_name'], '1znf.pdb')
        self.assertEqual(e['source'], 'bundled')

    def test_4wb3(self):
        e = DEMO_MANIFEST['4wb3']
        self.assertEqual(e['category'], 'Mixed')
        self.assertEqual(e['difficulty'], 'hard')

    def test_bundled_cache_name_pattern(self):
        # Bundled demos cache as plain <did>.pdb in data/demos/; fetched
        # demos cache as compressed <name>.pdb.gz in <cwd>/cache/.
        bundled = {'1znf', '1xdn', '5e54', '1k8p', '2qbz', '4wb3'}
        for did in bundled:
            self.assertEqual(DEMO_MANIFEST[did]['cache_name'], "%s.pdb" % did,
                msg="bundled cache_name for %r should be %r.pdb, got %r"
                    % (did, did, DEMO_MANIFEST[did]['cache_name']))
        for did in ('1gzm', '3gp6', 'sasdpg4'):
            self.assertTrue(DEMO_MANIFEST[did]['cache_name'].endswith('.pdb.gz'),
                msg="fetched cache_name for %r should end with .pdb.gz, got %r"
                    % (did, DEMO_MANIFEST[did]['cache_name']))


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


class TestValidatePdbCode(unittest.TestCase):
    """Test _validate_pdb_code enforces exactly 4-char lowercase alnum."""

    def test_accepts_4char_alnum(self):
        self.assertEqual(_validate_pdb_code("1ubq"), "1ubq")

    def test_accepts_4char_all_letters(self):
        # format-valid even if not a real PDB — we don't verify against RCSB
        self.assertEqual(_validate_pdb_code("zzzz"), "zzzz")

    def test_rejects_5char(self):
        self.assertEqual(_validate_pdb_code("12345"), "")

    def test_rejects_3char(self):
        self.assertEqual(_validate_pdb_code("123"), "")

    def test_rejects_2char(self):
        self.assertEqual(_validate_pdb_code("12"), "")

    def test_rejects_non_alnum(self):
        self.assertEqual(_validate_pdb_code("ab!"), "")

    def test_lowercases(self):
        self.assertEqual(_validate_pdb_code("1UBQ"), "1ubq")

    def test_strips_whitespace(self):
        self.assertEqual(_validate_pdb_code(" 1ubq "), "1ubq")

    def test_rejects_empty(self):
        self.assertEqual(_validate_pdb_code(""), "")

    def test_rejects_none(self):
        self.assertEqual(_validate_pdb_code(None), "")


class TestValidateStateNewFields(unittest.TestCase):
    """Test lock_source + pdb_pool validation in validate_state."""

    def test_lock_source_bool_coercion(self):
        self.assertEqual(validate_state({"lock_source": 1})["lock_source"], True)

    def test_lock_source_default_false(self):
        self.assertEqual(validate_state({})["lock_source"], False)

    def test_pdb_pool_default(self):
        self.assertEqual(validate_state({})["pdb_pool"], PDB_POOL)

    def test_pdb_pool_filters_invalid(self):
        # 12345 (5-char) now rejected by _validate_pdb_code itself (Issue 2);
        # INVALID (non-alnum), 12 (2-char) rejected; 1UBQ lowercased to 1ubq dupes out
        result = validate_state({"pdb_pool": ["1ubq", "12345", "INVALID", "1UBQ", "1bna"]})
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


# ---- Phase 9: manifest schema, tier labels, fetch URLs, strip helper ----


class TestManifestSchemaPhase9(unittest.TestCase):
    """Phase 9: 9-entry manifest with the uniform fetch-source schema.

    Every entry carries 9 keys: category, type, difficulty, source,
    source_id, fetch_url, cache_name, citation, strip. The 6 bundled
    demos keep working offline; 3 fetched demos (1gzm/3gp6/sasdpg4)
    carry the network metadata the 09-02 loader uses.
    """

    def test_count(self):
        self.assertEqual(len(DEMO_MANIFEST), 9)

    def test_entry_keys(self):
        expected = {'category', 'type', 'difficulty', 'source', 'source_id',
                    'fetch_url', 'cache_name', 'citation', 'strip'}
        for did, entry in DEMO_MANIFEST.items():
            self.assertEqual(set(entry.keys()), expected,
                msg="Entry %r has wrong keys: %r" % (did, set(entry.keys())))

    def test_bundled_entries(self):
        bundled = {'1znf', '1xdn', '5e54', '1k8p', '2qbz', '4wb3'}
        for did in bundled:
            e = DEMO_MANIFEST[did]
            self.assertEqual(e['source'], 'bundled', msg="%r source" % did)
            self.assertIsNone(e['fetch_url'], msg="%r fetch_url" % did)
            self.assertFalse(e['strip'], msg="%r strip" % did)
            self.assertEqual(e['cache_name'], "%s.pdb" % did,
                msg="%r cache_name" % did)

    def test_new_ids_present(self):
        self.assertIn('1gzm', DEMO_MANIFEST)
        self.assertIn('3gp6', DEMO_MANIFEST)
        self.assertIn('sasdpg4', DEMO_MANIFEST)


class TestFetchUrls(unittest.TestCase):
    """Phase 9: research-verified fetch URLs for the 3 fetched demos."""

    def test_1gzm_url(self):
        self.assertEqual(
            DEMO_MANIFEST['1gzm']['fetch_url'],
            'https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/'
            '1gzm_default_dppc/files/structures/at.pdb')

    def test_3gp6_url(self):
        self.assertEqual(
            DEMO_MANIFEST['3gp6']['fetch_url'],
            'https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/'
            '3gp6_default_dppc/files/structures/at.pdb')

    def test_sasdpg4_url(self):
        self.assertEqual(
            DEMO_MANIFEST['sasdpg4']['fetch_url'],
            'https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb')


class TestTierLabels(unittest.TestCase):
    """Phase 9 DIFF-05: TIER_LABELS maps 4 identifier-safe tiers to display labels."""

    def test_map(self):
        self.assertEqual(TIER_LABELS, {
            'easy': 'Easy', 'hard': 'Hard',
            'challenge': 'Challenge', 'very_challenging': 'Very challenging'})

    def test_every_manifest_difficulty_is_a_tier_key(self):
        for did, meta in DEMO_MANIFEST.items():
            self.assertIn(meta['difficulty'], TIER_LABELS,
                msg="%r difficulty %r not in TIER_LABELS"
                    % (did, meta['difficulty']))


class TestTierAssignment(unittest.TestCase):
    """Phase 9: fetched demos mapped to the correct tiers."""

    def test_1gzm_very_challenging(self):
        self.assertEqual(DEMO_MANIFEST['1gzm']['difficulty'], 'very_challenging')

    def test_3gp6_very_challenging(self):
        self.assertEqual(DEMO_MANIFEST['3gp6']['difficulty'], 'very_challenging')

    def test_sasdpg4_challenge(self):
        self.assertEqual(DEMO_MANIFEST['sasdpg4']['difficulty'], 'challenge')


class Test4wb3MappedToHard(unittest.TestCase):
    """Phase 9: 4wb3 difficulty 'mixed' -> 'hard' (09-RESEARCH-pipeline.md:422)."""

    def test_4wb3_hard(self):
        self.assertEqual(DEMO_MANIFEST['4wb3']['difficulty'], 'hard')

    def test_4wb3_not_mixed(self):
        self.assertNotEqual(DEMO_MANIFEST['4wb3']['difficulty'], 'mixed')


class TestStripFalseForSasbdb(unittest.TestCase):
    """Phase 9: SASDPG4 strip=False (glycan HETATM must survive).

    A naive solvent/inorganic strip is a no-op here (0 waters/ions), but
    strip=False documents the entry's actual content and avoids a
    misleading 'stripped N waters' log line. Stripping would also risk
    the glycans if a future edit used a broad hetatm selector.
    """

    def test_sasdpg4_strip_false(self):
        self.assertFalse(DEMO_MANIFEST['sasdpg4']['strip'])


class TestRandomizeExcludesFetched(unittest.TestCase):
    """Phase 9: randomize_state never picks a fetched demo (offline-safe).

    The non-lock random pick draws ONLY from bundled demos so a random
    'demo' target always works offline. The lock_source path still
    preserves a user-locked fetched demo_id (explicit user choice).
    """

    def test_random_pick_never_fetched(self):
        for seed in range(50):
            s = randomize_state(seed=seed)
            if s['target_mode'] == 'demo':
                self.assertEqual(
                    DEMO_MANIFEST[s['demo_id']].get('source', 'bundled'),
                    'bundled',
                    msg="seed %d: randomize picked fetched demo %r"
                        % (seed, s['demo_id']))

    def test_lock_source_preserves_fetched_demo(self):
        locked = {'target_mode': 'demo', 'demo_id': '1gzm'}
        s = randomize_state(seed=7, lock_source=True, locked_state=locked)
        self.assertEqual(s['demo_id'], '1gzm')


class TestStripResnFromPdb(unittest.TestCase):
    """Phase 9: pure PDB-line strip helper (SOL/NA/CL removal).

    Filters ATOM lines whose residue name (PDB cols 18-20, 0-indexed
    line[17:20], .strip() for padding agnosticism) is in the strip set.
    All non-ATOM lines (TITLE/CRYST1/MODEL/TER/ENDMDL/HETATM/...) are
    preserved unconditionally. Deterministic pure-Python strip (NOT
    PyMOL solvent/inorganic selectors) so the wet file never enters PyMOL.
    """

    # A column-aligned ATOM line whose residue name occupies cols 18-20
    # (0-indexed 17:20). PREFIX is cols 1-17, SUFFIX is cols 21+.
    _PREFIX = "ATOM      1  N   "  # 17 chars: "ATOM" + serial + name + altLoc
    _SUFFIX = "     1"             # resi tail

    @classmethod
    def _atom_line(cls, resn_field):
        # resn_field is EXACTLY 3 chars -> lands in cols 18-20 (line[17:20])
        return cls._PREFIX + resn_field + cls._SUFFIX + "\n"

    def test_strips_sol_na_cl_keeps_protein_lipid(self):
        synthetic = (
            "TITLE test\n"
            "CRYST1\n"
            + self._atom_line("MET")
            + self._atom_line("SOL")
            + self._atom_line("NA ")
            + self._atom_line("CL ")
            + self._atom_line("DPP")
            + "TER\n"
            + "ENDMDL\n"
        )
        result = strip_resn_from_pdb(synthetic, STRIP_RESN_MEMPROTMD)
        # non-ATOM lines preserved
        self.assertIn("TITLE test", result)
        self.assertIn("CRYST1", result)
        self.assertIn("TER", result)
        self.assertIn("ENDMDL", result)
        # protein/lipid ATOM lines kept
        atom_lines = [l for l in result.splitlines() if l.startswith("ATOM")]
        self.assertEqual(len(atom_lines), 2,
            msg="expected MET+DPP only, got %r" % atom_lines)
        resns = sorted(l[17:20].strip() for l in atom_lines)
        self.assertEqual(resns, ['DPP', 'MET'])

    def test_padding_trailing_space(self):
        # resn field cols 18-20 = 'NA ' (2-char ion + trailing space)
        line = self._atom_line("NA ")
        self.assertEqual(line[17:20], "NA ")  # sanity: column-aligned
        self.assertEqual(strip_resn_from_pdb(line, STRIP_RESN_MEMPROTMD), "\n")

    def test_padding_leading_space(self):
        # resn field cols 18-20 = ' NA' (leading space + 2-char ion)
        line = self._atom_line(" NA")
        self.assertEqual(line[17:20], " NA")  # sanity: column-aligned
        self.assertEqual(strip_resn_from_pdb(line, STRIP_RESN_MEMPROTMD), "\n")

    def test_empty_input(self):
        self.assertEqual(strip_resn_from_pdb('', STRIP_RESN_MEMPROTMD), '')

    def test_non_atom_preserved(self):
        # HETATM is NOT filtered (only ATOM lines are) -> HOH survives even
        # though HOH is a water residue name (09-RESEARCH-memprotmd.md:267-274).
        text = "HETATM    1  O   HOH     1\n"
        result = strip_resn_from_pdb(text, STRIP_RESN_MEMPROTMD)
        self.assertIn("HOH", result)


class TestFormatRemaining(unittest.TestCase):
    """Phase 4.1 GAME-03: pure remaining-hiders label formatter.

    Hard mode shows the total only (unchanged from Phase 4, SC2). Easy
    mode appends a per-rep breakdown in GAME_REPS order, keeping only
    reps whose count is greater than zero, separated by two spaces
    before the opening paren (SC1). A None or empty counts dict, or
    an all-zero win state, collapses to the total-only form so the
    label never shows an empty parenthetical.
    """

    def test_format_remaining_hard_mode(self):
        # Hard mode: total only, no parenthetical (SC2, Phase 4 unchanged).
        self.assertEqual(
            format_remaining(7, {'spheres': 3, 'sticks': 3, 'cartoon': 2}, False),
            "Remaining: 7")

    def test_format_remaining_easy_mode_mixed(self):
        # Easy mode: per-rep breakdown in GAME_REPS order (sticks before
        # spheres before cartoon), two spaces before the paren (SC1).
        self.assertEqual(
            format_remaining(7, {'spheres': 2, 'sticks': 3, 'cartoon': 2}, True),
            "Remaining: 7  (sticks: 3, spheres: 2, cartoon: 2)")

    def test_format_remaining_easy_mode_filters_zero(self):
        # Easy mode: reps whose count is zero are omitted from the paren.
        self.assertEqual(
            format_remaining(4, {'spheres': 2, 'sticks': 0, 'cartoon': 2}, True),
            "Remaining: 4  (spheres: 2, cartoon: 2)")

    def test_format_remaining_easy_mode_all_zero(self):
        # Win state: every count is zero -> total-only, no empty paren.
        self.assertEqual(
            format_remaining(0, {'spheres': 0, 'sticks': 0}, True),
            "Remaining: 0")

    def test_format_remaining_none_counts(self):
        # None counts -> safe total-only default.
        self.assertEqual(format_remaining(7, None, True), "Remaining: 7")

    def test_format_remaining_empty_dict(self):
        # Empty counts dict -> safe total-only default.
        self.assertEqual(format_remaining(7, {}, True), "Remaining: 7")

    def test_format_remaining_two_space_separator(self):
        # Exactly two spaces separate the total and the opening paren;
        # no extra space before, and the substring is present.
        out = format_remaining(7, {'spheres': 2}, True)
        self.assertIn("  (", out)
        self.assertEqual(out, "Remaining: 7  (spheres: 2)")

    def test_format_remaining_game_reps_order(self):
        # Insertion order is anti-GAME_REPS (cartoon before spheres);
        # output must follow GAME_REPS order (spheres before cartoon),
        # not the dict's insertion order.
        self.assertEqual(
            format_remaining(3, {'cartoon': 2, 'spheres': 1}, True),
            "Remaining: 3  (spheres: 1, cartoon: 2)")


class TestFormatDebrief(unittest.TestCase):
    """Phase 10 DIFF-03: pure post-game debrief rich-text formatter.

    Mirrors the format_remaining precedent (same module, same pure-layer
    pattern). format_debrief_text(counts_by_rep) returns an HTML rich-text
    string usable in QMessageBox.setInformativeText: a frame sentence plus
    a <ul> of per-rep bullets (one per rep with count > 0, in GAME_REPS
    order). An empty dict, a None input, or an all-zero dict collapses to
    the graceful fallback string so the dialog never shows an empty <ul>.
    """

    def test_format_debrief_empty_dict(self):
        # Empty dict -> graceful fallback (no <ul>, no bullets).
        self.assertEqual(
            format_debrief_text({}),
            "All hiders are highlighted in the viewer.")

    def test_format_debrief_all_zero(self):
        # A zero-filled counts_by_rep dict must collapse to the SAME
        # fallback string, NOT emit an empty <ul>.
        self.assertEqual(
            format_debrief_text({'lines': 0, 'sticks': 0, 'spheres': 0,
                                 'cartoon': 0, 'ribbon': 0}),
            "All hiders are highlighted in the viewer.")

    def test_format_debrief_single_rep(self):
        out = format_debrief_text({'lines': 0, 'sticks': 0, 'spheres': 3,
                                   'cartoon': 0, 'ribbon': 0})
        # Frame sentence (exact wording from the research).
        self.assertTrue(
            out.startswith("All 3 hiders are now highlighted in the "
                           "viewer. Here's why each kind was hard to spot:"),
            msg="frame sentence prefix mismatch: %r" % out)
        # Exactly ONE <li> bullet (spheres is the only rep with count > 0).
        self.assertEqual(out.count("<li>"), 1)
        # Bullet carries the rep + count bold header.
        self.assertIn("<b>spheres: 3 hider(s)</b>", out)
        # Bullet carries the opening of the sphere explanation.
        self.assertIn("A sphere hider is a single pseudoatom", out)
        # Bullets are wrapped in <ul>...</ul>.
        self.assertIn("<ul>", out)
        self.assertIn("</ul>", out)

    def test_format_debrief_game_reps_order(self):
        # Insertion order is anti-GAME_REPS (cartoon before spheres);
        # output bullets must follow GAME_REPS order (spheres before
        # cartoon), not the dict's insertion order.
        out = format_debrief_text({'cartoon': 2, 'spheres': 1})
        # Split on '<li>' and verify spheres appears before cartoon in
        # the joined bullet order (mirrors test_format_remaining_game_reps_order).
        bullets = out.split("<li>")
        # bullets[0] is the frame sentence; bullets[1:] are the bullets.
        joined = "<li>".join(bullets[1:])
        self.assertLess(joined.index("spheres"), joined.index("cartoon"),
                        msg="spheres bullet must precede cartoon: %r" % out)

    def test_format_debrief_rep_none_defensive(self):
        # A None key in the input dict must NOT crash (defensive skip).
        # The real counts_by_rep never emits a None key, but the formatter
        # must guard a corrupt input. Assert exactly ONE bullet for spheres
        # and no 'None' substring in the output.
        out = format_debrief_text({'spheres': 2, None: 1})
        self.assertEqual(out.count("<li>"), 1)
        self.assertNotIn("None", out)


if __name__ == '__main__':
    unittest.main(verbosity=2)
