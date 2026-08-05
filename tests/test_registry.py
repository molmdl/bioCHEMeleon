"""Tests for biochemeleon.registry - HiderRecord + HiderRegistry core CRUD.

Pure-layer tests (no PyMOL needed). The registry module imports only
stdlib + setup_state.GAME_REPS, but biochemeleon/__init__.py does
`from pymol.Qt import ...` at module level, so we stub pymol/pymol.Qt
via sys.modules (same pattern as tests/test_setup_state.py lines 13-15)
before importing biochemeleon.*.

Run: python3.6 -m unittest tests.test_registry -v
Or:  python3.6 tests/test_registry.py
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

from biochemeleon.registry import (
    HiderRecord, HiderRegistry,
    HIDER_STATUS_HIDDEN, HIDER_STATUS_FOUND,
)
from biochemeleon.setup_state import GAME_REPS


class TestHiderRecord(unittest.TestCase):
    """Test HiderRecord construction, validation, key, to_dict, __slots__."""

    def test_construction_defaults(self):
        """HiderRecord(id, object, rep) defaults status='hidden', pos=None."""
        rec = HiderRecord(1, '1ubq', 'spheres')
        self.assertEqual(rec.id, 1)
        self.assertEqual(rec.object, '1ubq')
        self.assertEqual(rec.rep, 'spheres')
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        self.assertIsNone(rec.pos)

    def test_construction_explicit_status_and_pos(self):
        """HiderRecord accepts explicit status and pos."""
        rec = HiderRecord(2, '1ubq', 'sticks', status=HIDER_STATUS_FOUND,
                          pos=(1.5, 2.5, 3.5))
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        self.assertEqual(rec.pos, (1.5, 2.5, 3.5))

    def test_id_coerced_to_int(self):
        """id is cast to int (str '1' -> 1)."""
        rec = HiderRecord('1', '1ubq', 'spheres')
        self.assertEqual(rec.id, 1)
        self.assertIsInstance(rec.id, int)

    def test_invalid_rep_raises_value_error(self):
        """rep not in GAME_REPS raises ValueError."""
        # 'surface' is explicitly OUT OF SCOPE (PROJECT.md)
        with self.assertRaises(ValueError):
            HiderRecord(1, '1ubq', 'surface')

    def test_invalid_rep_other_values(self):
        """Any rep not in GAME_REPS raises ValueError."""
        for bad in ('', 'surface', 'mesh', 'dots', 'Spheres', 'LINES'):
            with self.subTest(rep=bad):
                with self.assertRaises(ValueError):
                    HiderRecord(1, '1ubq', bad)

    def test_all_game_reps_accepted(self):
        """Every rep in GAME_REPS is accepted."""
        for rep in GAME_REPS:
            with self.subTest(rep=rep):
                rec = HiderRecord(1, '1ubq', rep)
                self.assertEqual(rec.rep, rep)

    def test_key_returns_object_id_tuple(self):
        """key() returns (object, int(id))."""
        rec = HiderRecord(1, '1ubq', 'spheres')
        self.assertEqual(rec.key(), ('1ubq', 1))

    def test_key_with_str_id_coerced(self):
        """key() returns int id even if id was passed as str."""
        rec = HiderRecord('7', '2qbz', 'cartoon')
        self.assertEqual(rec.key(), ('2qbz', 7))
        self.assertIsInstance(rec.key()[1], int)

    def test_to_dict_omits_pos_when_none(self):
        """to_dict() omits 'pos' when pos is None."""
        rec = HiderRecord(1, '1ubq', 'spheres')
        d = rec.to_dict()
        self.assertEqual(d, {'id': 1, 'object': '1ubq', 'rep': 'spheres',
                             'status': HIDER_STATUS_HIDDEN})
        self.assertNotIn('pos', d)

    def test_to_dict_includes_pos_as_list_when_set(self):
        """to_dict() includes 'pos' as a list (not tuple) when set."""
        rec = HiderRecord(1, '1ubq', 'spheres', pos=(1.0, 2.0, 3.0))
        d = rec.to_dict()
        self.assertIn('pos', d)
        self.assertEqual(d['pos'], [1.0, 2.0, 3.0])
        self.assertIsInstance(d['pos'], list)
        # Other fields present and correct
        self.assertEqual(d['id'], 1)
        self.assertEqual(d['object'], '1ubq')
        self.assertEqual(d['rep'], 'spheres')
        self.assertEqual(d['status'], HIDER_STATUS_HIDDEN)

    def test_to_dict_with_found_status(self):
        """to_dict() reflects found status."""
        rec = HiderRecord(1, '1ubq', 'spheres', status=HIDER_STATUS_FOUND)
        self.assertEqual(rec.to_dict()['status'], HIDER_STATUS_FOUND)

    def test_slots_no_dict(self):
        """HiderRecord uses __slots__ -> no __dict__ attribute."""
        rec = HiderRecord(1, '1ubq', 'spheres')
        self.assertFalse(hasattr(rec, '__dict__'))

    def test_slots_defined(self):
        """__slots__ contains exactly the 5 fields."""
        self.assertEqual(HiderRecord.__slots__,
                         ('id', 'object', 'rep', 'status', 'pos'))

    def test_cannot_set_unknown_attribute(self):
        """With __slots__, setting an unknown attribute raises AttributeError."""
        rec = HiderRecord(1, '1ubq', 'spheres')
        with self.assertRaises(AttributeError):
            rec.unknown_field = 42


class TestHiderRegistryCore(unittest.TestCase):
    """Test HiderRegistry register/get/all/remove core CRUD."""

    def test_register_returns_hider_record(self):
        """register() returns the created HiderRecord."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', 1, 'spheres')
        self.assertIsInstance(rec, HiderRecord)
        self.assertEqual(rec.id, 1)
        self.assertEqual(rec.object, '1ubq')
        self.assertEqual(rec.rep, 'spheres')

    def test_register_defaults_status_hidden(self):
        """register() defaults status to 'hidden'."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', 1, 'spheres')
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)

    def test_register_with_explicit_status_and_pos(self):
        """register() passes status and pos through to the record."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', 1, 'spheres', status=HIDER_STATUS_FOUND,
                           pos=(1.0, 2.0, 3.0))
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        self.assertEqual(rec.pos, (1.0, 2.0, 3.0))

    def test_get_returns_registered_record(self):
        """get(object, id) returns the registered record."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        rec = reg.get('1ubq', 1)
        self.assertIsNotNone(rec)
        self.assertEqual(rec.id, 1)
        self.assertEqual(rec.rep, 'spheres')

    def test_get_returns_none_for_absent(self):
        """get(object, id) returns None when no record matches."""
        reg = HiderRegistry()
        self.assertIsNone(reg.get('1ubq', 1))
        reg.register('1ubq', 1, 'spheres')
        self.assertIsNone(reg.get('1ubq', 2))
        self.assertIsNone(reg.get('2qbz', 1))

    def test_get_int_coercion(self):
        """get() coerces id to int (str '1' matches int 1 registration)."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        self.assertIsNotNone(reg.get('1ubq', '1'))
        rec = reg.get('1ubq', '1')
        self.assertEqual(rec.id, 1)

    def test_all_empty_returns_empty_list(self):
        """all() returns [] for a fresh registry."""
        reg = HiderRegistry()
        self.assertEqual(reg.all(), [])

    def test_all_returns_insertion_order(self):
        """all() returns records in insertion order."""
        reg = HiderRegistry()
        r1 = reg.register('1ubq', 1, 'spheres')
        r2 = reg.register('1ubq', 2, 'sticks')
        r3 = reg.register('2qbz', 1, 'cartoon')
        self.assertEqual(reg.all(), [r1, r2, r3])

    def test_all_returns_list_copy(self):
        """all() returns a fresh list (mutating it doesn't affect registry)."""
        reg = HiderRegistry()
        r1 = reg.register('1ubq', 1, 'spheres')
        out = reg.all()
        out.append('garbage')
        # Registry's internal state unaffected
        self.assertEqual(reg.all(), [r1])

    def test_remove_returns_true_when_present(self):
        """remove(object, id) returns True when a record was removed."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        self.assertTrue(reg.remove('1ubq', 1))

    def test_remove_returns_false_when_absent(self):
        """remove(object, id) returns False when no record matches."""
        reg = HiderRegistry()
        self.assertFalse(reg.remove('1ubq', 1))
        reg.register('1ubq', 1, 'spheres')
        self.assertFalse(reg.remove('1ubq', 2))
        self.assertFalse(reg.remove('2qbz', 1))

    def test_remove_then_get_returns_none(self):
        """After remove, get() returns None."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        reg.remove('1ubq', 1)
        self.assertIsNone(reg.get('1ubq', 1))
        self.assertEqual(reg.all(), [])

    def test_remove_twice_second_returns_false(self):
        """remove() twice: first True, second False (already gone)."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        self.assertTrue(reg.remove('1ubq', 1))
        self.assertFalse(reg.remove('1ubq', 1))

    def test_remove_int_coercion(self):
        """remove() coerces id to int (str '1' matches int 1)."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        self.assertTrue(reg.remove('1ubq', '1'))
        self.assertIsNone(reg.get('1ubq', 1))

    def test_duplicate_key_raises_key_error(self):
        """register() with an existing (object, id) raises KeyError."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        with self.assertRaises(KeyError):
            reg.register('1ubq', 1, 'spheres')
        # Same (object, id) with a different rep is still a duplicate
        with self.assertRaises(KeyError):
            reg.register('1ubq', 1, 'sticks')

    def test_different_objects_same_id_ok(self):
        """Same id under different objects are distinct keys."""
        reg = HiderRegistry()
        r1 = reg.register('1ubq', 1, 'spheres')
        r2 = reg.register('2qbz', 1, 'sticks')
        self.assertEqual(reg.all(), [r1, r2])
        self.assertIsNotNone(reg.get('1ubq', 1))
        self.assertIsNotNone(reg.get('2qbz', 1))

    def test_register_int_coercion_then_get_with_int(self):
        """register with id as str '1'; get with int 1 works (int coercion)."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', '1', 'spheres')
        self.assertEqual(rec.id, 1)
        self.assertIsInstance(rec.id, int)
        # get with int 1 finds the record
        got = reg.get('1ubq', 1)
        self.assertIsNotNone(got)
        self.assertEqual(got.id, 1)

    def test_register_rejects_invalid_rep(self):
        """register() propagates HiderRecord's ValueError for bad rep."""
        reg = HiderRegistry()
        with self.assertRaises(ValueError):
            reg.register('1ubq', 1, 'surface')

    def test_independent_instances(self):
        """Two HiderRegistry instances have independent state."""
        r1 = HiderRegistry()
        r2 = HiderRegistry()
        r1.register('1ubq', 1, 'spheres')
        self.assertEqual(r1.all(), [r1.get('1ubq', 1)])
        self.assertEqual(r2.all(), [])
        self.assertIsNone(r2.get('1ubq', 1))


class TestHiderRegistryQueries(unittest.TestCase):
    """Test HiderRegistry by_rep / counts_by_rep / mark_found queries.

    These are the per-rep counting + status-update methods needed for
    success criterion 3 (per-rep counts) and Phase 4's click-to-find
    handler (mark_found). Pure functions over the registry's in-memory
    records.
    """

    def setUp(self):
        """Build a registry with 3 hiders across 2 reps.

        Fixture: ('1ubq', 1, 'spheres'), ('1ubq', 2, 'sticks'),
                 ('1ubq', 3, 'spheres')
        Keep direct references for insertion-order + status assertions.
        """
        self.reg = HiderRegistry()
        self.r1 = self.reg.register('1ubq', 1, 'spheres')
        self.r2 = self.reg.register('1ubq', 2, 'sticks')
        self.r3 = self.reg.register('1ubq', 3, 'spheres')

    # ---- by_rep ----

    def test_by_rep_returns_matching(self):
        """by_rep('spheres') returns [r1, r3] in insertion order."""
        out = self.reg.by_rep('spheres')
        self.assertEqual(out, [self.r1, self.r3])

    def test_by_rep_empty_returns_empty_list(self):
        """by_rep for a rep with no hiders returns [] (not None)."""
        out = self.reg.by_rep('cartoon')
        self.assertEqual(out, [])
        self.assertIsNotNone(out)

    # ---- counts_by_rep ----

    def test_counts_by_rep_all_reps_present(self):
        """counts_by_rep() returns ALL 5 GAME_REPS keys, zero-filled."""
        counts = self.reg.counts_by_rep()
        # Every GAME_REP is a key (zero-filled for reps with no hiders)
        self.assertEqual(set(counts.keys()), set(GAME_REPS))
        # Specific values for the setUp fixture
        self.assertEqual(counts, {'lines': 0, 'sticks': 1, 'spheres': 2,
                                  'cartoon': 0, 'ribbon': 0})

    def test_counts_by_rep_empty_registry(self):
        """counts_by_rep() on a fresh registry zero-fills all 5 reps."""
        reg = HiderRegistry()
        counts = reg.counts_by_rep()
        self.assertEqual(set(counts.keys()), set(GAME_REPS))
        for rep in GAME_REPS:
            with self.subTest(rep=rep):
                self.assertEqual(counts[rep], 0)

    # ---- mark_found ----

    def test_mark_found_sets_status(self):
        """mark_found('1ubq', 2) sets r2.status to 'found'."""
        self.reg.mark_found('1ubq', 2)
        self.assertEqual(self.r2.status, HIDER_STATUS_FOUND)

    def test_mark_found_only_affects_target(self):
        """mark_found('1ubq', 2) leaves r1 (and r3) as 'hidden'."""
        self.reg.mark_found('1ubq', 2)
        self.assertEqual(self.r1.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(self.r3.status, HIDER_STATUS_HIDDEN)

    def test_mark_found_not_registered_raises(self):
        """mark_found on an unregistered (object, id) raises KeyError."""
        with self.assertRaises(KeyError):
            self.reg.mark_found('1ubq', 999)


if __name__ == '__main__':
    unittest.main(verbosity=2)
