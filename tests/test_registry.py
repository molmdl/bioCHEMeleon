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
    HiderRecord, HiderRegistry, ReconcileMismatches,
    HIDER_STATUS_HIDDEN, HIDER_STATUS_FOUND,
    build_found_selection, group_found_by_rep,
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
        """__slots__ contains exactly the 8 fields (5 Phase 3 + 3 Phase 11
        alt-conf: is_altconf, endpoint_resvs, alt_tag)."""
        self.assertEqual(HiderRecord.__slots__,
                         ('id', 'object', 'rep', 'status', 'pos',
                          'is_altconf', 'endpoint_resvs', 'alt_tag'))

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


class TestHiderRegistrySerialize(unittest.TestCase):
    """Test HiderRegistry to_dict / from_dict round-trip (Phase 8 .bcm shape).

    The serialization shape is designed NOW (Phase 3) and unit-tested for
    round-trip correctness, so Phase 8 just writes ``registry.to_dict()``
    to a ``.bcm`` JSON sidecar and reads it back via
    ``HiderRegistry.from_dict()``. Designing the shape now avoids a
    Phase 8 schema migration.

    Shape: ``{'version': 1, 'hiders': [record.to_dict() for each record
    in insertion order]}``.

    Round-trip is value-preserving for id / object / rep / status (the
    four fields the click handler + Game tab rely on). ``pos`` round-trip
    is not asserted here: ``from_dict`` stores ``pos`` as-is (a list from
    JSON) while ``HiderRecord`` accepts either a list or tuple; the
    list/tuple normalization is a Phase 8 boundary concern (RESEARCH
    serialization shape note, lines 240-241).
    """

    def test_to_dict_empty(self):
        """Fresh registry: to_dict() == {'version': 1, 'hiders': []}."""
        reg = HiderRegistry()
        self.assertEqual(reg.to_dict(), {'version': 1, 'hiders': []})

    def test_to_dict_three_hiders(self):
        """3 hiders (mixed reps, one with pos): version=1, 3 hider dicts.

        Each hider dict has keys id/object/rep/status; the one with pos
        has 'pos' key as a list.
        """
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        reg.register('1ubq', 2, 'sticks')
        reg.register('1ubq', 3, 'spheres', pos=[1.0, 2.0, 3.0])
        d = reg.to_dict()
        self.assertEqual(d['version'], 1)
        self.assertEqual(len(d['hiders']), 3)
        for h in d['hiders']:
            self.assertIn('id', h)
            self.assertIn('object', h)
            self.assertIn('rep', h)
            self.assertIn('status', h)
        # Exactly one hider has 'pos', and it's a list
        with_pos = [h for h in d['hiders'] if 'pos' in h]
        self.assertEqual(len(with_pos), 1)
        self.assertEqual(with_pos[0]['pos'], [1.0, 2.0, 3.0])
        self.assertIsInstance(with_pos[0]['pos'], list)

    def test_from_dict_round_trip(self):
        """register 3, to_dict -> d, from_dict(d) -> reg2; id/object/rep/status match."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        reg.register('1ubq', 2, 'sticks')
        reg.register('2qbz', 1, 'cartoon', pos=(4.0, 5.0, 6.0))
        d = reg.to_dict()
        reg2 = HiderRegistry.from_dict(d)
        orig = reg.all()
        new = reg2.all()
        self.assertEqual(len(new), len(orig))
        for a, b in zip(orig, new):
            self.assertEqual(b.id, a.id)
            self.assertEqual(b.object, a.object)
            self.assertEqual(b.rep, a.rep)
            self.assertEqual(b.status, a.status)

    def test_from_dict_missing_status_defaults_hidden(self):
        """from_dict with missing 'status' in a hider defaults to 'hidden'."""
        d = {'hiders': [{'id': 1, 'object': 'o', 'rep': 'spheres'}]}
        reg = HiderRegistry.from_dict(d)
        rec = reg.get('o', 1)
        self.assertIsNotNone(rec)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)

    def test_from_dict_missing_version(self):
        """from_dict with missing 'version' key still works (treats as v1).

        No KeyError on a dict that omits 'version' entirely.
        """
        d = {'hiders': []}
        reg = HiderRegistry.from_dict(d)
        self.assertEqual(reg.all(), [])

    def test_from_dict_empty_hiders(self):
        """from_dict with 'hiders': [] -> empty registry."""
        d = {'version': 1, 'hiders': []}
        reg = HiderRegistry.from_dict(d)
        self.assertEqual(reg.all(), [])


class TestHiderRegistryReconstruct(unittest.TestCase):
    """Test HiderRegistry.reconstruct_from_sentinels(iterate_hider_keys).

    The post-``.pse``-reload registry rebuild via dependency injection:
    after a session reload the in-memory registry is lost but the sentinel
    atoms (``segi='GAME'`` + ``b=-999``) survive. ``reconstruct_from_sentinels``
    rebuilds the registry from the sentinel atoms' ``(object, id)`` tuples.
    The iterate function is INJECTED as a parameter (dependency inversion)
    so ``registry.py`` stays pure - no ``from pymol import cmd``.

    After reconstruction, ``rep`` is unknown (the sentinel carries no rep -
    RESEARCH Open Risk 6) and is set to ``None``; the registry must tolerate
    ``rep=None`` ONLY in the reconstruction path (normal ``register()``
    validates against :data:`GAME_REPS`). Phase 8's ``.bcm`` sidecar recovers
    ``rep`` later.
    """

    def test_reconstruct_from_fake_iterate(self):
        """Fake fn [('1ubq',1),('1ubq',2)] -> 2 records, rep=None, status='hidden'."""
        reg = HiderRegistry()
        fake_keys = lambda: [('1ubq', 1), ('1ubq', 2)]
        reg.reconstruct_from_sentinels(fake_keys)
        all_recs = reg.all()
        self.assertEqual(len(all_recs), 2)
        # Each record: rep is None, status is 'hidden'
        for rec in all_recs:
            self.assertIsNone(rec.rep)
            self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        # Keys are ('1ubq', 1) and ('1ubq', 2)
        self.assertIsNotNone(reg.get('1ubq', 1))
        self.assertIsNotNone(reg.get('1ubq', 2))
        self.assertEqual(reg.get('1ubq', 1).id, 1)
        self.assertEqual(reg.get('1ubq', 2).id, 2)

    def test_reconstruct_clears_existing(self):
        """Reconstruct clears existing records (overwrite, NOT append).

        Register 3 hiders first, then reconstruct with a fake fn returning
        [('1ubq', 99)]; after, len(all()) == 1 (cleared + rebuilt, not 4).
        """
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        reg.register('1ubq', 2, 'sticks')
        reg.register('2qbz', 1, 'cartoon')
        self.assertEqual(len(reg.all()), 3)
        fake_keys = lambda: [('1ubq', 99)]
        reg.reconstruct_from_sentinels(fake_keys)
        self.assertEqual(len(reg.all()), 1)
        # The one record is ('1ubq', 99), rep=None
        rec = reg.get('1ubq', 99)
        self.assertIsNotNone(rec)
        self.assertIsNone(rec.rep)
        # The old records are gone
        self.assertIsNone(reg.get('1ubq', 1))
        self.assertIsNone(reg.get('1ubq', 2))
        self.assertIsNone(reg.get('2qbz', 1))

    def test_reconstruct_empty_iterate(self):
        """Reconstruct with an empty iterate fn -> empty registry."""
        reg = HiderRegistry()
        reg.register('1ubq', 1, 'spheres')
        reg.reconstruct_from_sentinels(lambda: [])
        self.assertEqual(reg.all(), [])

    def test_reconstruct_returns_self(self):
        """reconstruct_from_sentinels returns the registry instance (fluent)."""
        reg = HiderRegistry()
        result = reg.reconstruct_from_sentinels(lambda: [])
        self.assertIs(result, reg)

    def test_reconstruct_rep_none_bypasses_validation(self):
        """Reconstruct with rep=None does NOT raise (sentinel carries no rep).

        Normal register() validates rep in GAME_REPS and raises ValueError
        for invalid reps. But reconstruct_from_sentinels sets rep=None
        (the sentinel carries no rep post-.pse-reload); this must NOT raise.
        """
        reg = HiderRegistry()
        fake_keys = lambda: [('1ubq', 1), ('1ubq', 2), ('2qbz', 7)]
        # Should not raise
        reg.reconstruct_from_sentinels(fake_keys)
        self.assertEqual(len(reg.all()), 3)


class TestHiderRegistryEdgeCases(unittest.TestCase):
    """Reconfirm + new edge cases for HiderRegistry.

    - Bad rep (ValueError) - reconfirm from 03-01
    - Duplicate id (KeyError) - reconfirm from 03-01
    - rep=None reconstruction: counts_by_rep() returns only GAME_REPS keys
      (rep=None records are invisible - documented limitation Phase 8
      sidecar reconciles)
    """

    def test_register_bad_rep_raises(self):
        """register('o', 1, 'surface') raises ValueError (reconfirm 03-01)."""
        reg = HiderRegistry()
        with self.assertRaises(ValueError):
            reg.register('o', 1, 'surface')

    def test_register_dup_id_raises(self):
        """register('o', 1, 'spheres') then register('o', 1, 'sticks') raises KeyError (reconfirm)."""
        reg = HiderRegistry()
        reg.register('o', 1, 'spheres')
        with self.assertRaises(KeyError):
            reg.register('o', 1, 'sticks')

    def test_reconstruct_rep_none_then_counts_by_rep(self):
        """After reconstruct with rep=None records, counts_by_rep() returns
        only GAME_REPS keys (rep=None records are invisible - documented
        limitation Phase 8 sidecar reconciles).

        Without the rep=None guard in counts_by_rep, the 03-04 implementation
        would add a None key when records have rep=None, failing this test.
        """
        reg = HiderRegistry()
        fake_keys = lambda: [('1ubq', 1), ('1ubq', 2), ('2qbz', 7)]
        reg.reconstruct_from_sentinels(fake_keys)
        counts = reg.counts_by_rep()
        # Only GAME_REPS keys, never a None key
        self.assertEqual(set(counts.keys()), set(GAME_REPS))
        self.assertNotIn(None, counts)
        # All counts are zero (rep=None records are invisible)
        for rep in GAME_REPS:
            with self.subTest(rep=rep):
                self.assertEqual(counts[rep], 0)


class TestFoundSelectionHelpers(unittest.TestCase):
    """Test the Phase 7 pure module-level helpers build_found_selection +
    group_found_by_rep (Phase 7 Plan 01, GAME-08 dropdown foundation).

    These are MODULE-LEVEL functions in registry.py (NOT HiderRegistry
    methods) placed AFTER the HiderRegistry class. They encode the
    selection logic the Game tab dropdown (Plan 02) uses: filter the
    registry records by status==found, build a PyMOL selection string
    (or a per-rep {rep: [ids]} dict) for the found hiders. Pure (no cmd,
    no Qt) — WSL-testable like the rest of registry.py.

    Build HiderRecord instances directly: HiderRecord(id, object, rep,
    status=...). The helpers take a list of records (typically
    registry.all()) and return either a selection string or a dict.
    """

    # ---- build_found_selection ----

    def test_build_found_selection_empty(self):
        """build_found_selection([], 'obj') -> None (no records)."""
        self.assertIsNone(build_found_selection([], "obj"))

    def test_build_found_selection_no_found(self):
        """All hidden -> None (no found records to select)."""
        recs = [
            HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_HIDDEN),
            HiderRecord(101, 'obj', 'spheres', status=HIDER_STATUS_HIDDEN),
        ]
        self.assertIsNone(build_found_selection(recs, "obj"))

    def test_build_found_selection_one_found(self):
        """[found(100)] -> 'obj and id 100'."""
        recs = [HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_FOUND)]
        self.assertEqual(build_found_selection(recs, "obj"), "obj and id 100")

    def test_build_found_selection_three_found(self):
        """[found(100), found(101), found(102)] -> 'obj and id 100+101+102'."""
        recs = [
            HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_FOUND),
            HiderRecord(101, 'obj', 'sticks', status=HIDER_STATUS_FOUND),
            HiderRecord(102, 'obj', 'cartoon', status=HIDER_STATUS_FOUND),
        ]
        self.assertEqual(build_found_selection(recs, "obj"),
                         "obj and id 100+101+102")

    def test_build_found_selection_mixed(self):
        """[hidden(100), found(101), hidden(102)] -> 'obj and id 101'
        (only FOUND records are included; hidden skipped)."""
        recs = [
            HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_HIDDEN),
            HiderRecord(101, 'obj', 'sticks', status=HIDER_STATUS_FOUND),
            HiderRecord(102, 'obj', 'cartoon', status=HIDER_STATUS_HIDDEN),
        ]
        self.assertEqual(build_found_selection(recs, "obj"), "obj and id 101")

    # ---- group_found_by_rep ----

    def test_group_found_by_rep_empty(self):
        """group_found_by_rep([]) -> {} (no records)."""
        self.assertEqual(group_found_by_rep([]), {})

    def test_group_found_by_rep_no_found(self):
        """All hidden -> {} (no found records to group)."""
        recs = [
            HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_HIDDEN),
            HiderRecord(101, 'obj', 'sticks', status=HIDER_STATUS_HIDDEN),
        ]
        self.assertEqual(group_found_by_rep(recs), {})

    def test_group_found_by_rep_one_found(self):
        """[found(100, spheres)] -> {'spheres': [100]}."""
        recs = [HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_FOUND)]
        self.assertEqual(group_found_by_rep(recs), {"spheres": [100]})

    def test_group_found_by_rep_mixed_reps(self):
        """[found(100, spheres), found(101, sticks)] ->
        {'spheres': [100], 'sticks': [101]} (per-rep grouping)."""
        recs = [
            HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_FOUND),
            HiderRecord(101, 'obj', 'sticks', status=HIDER_STATUS_FOUND),
        ]
        self.assertEqual(group_found_by_rep(recs),
                         {"spheres": [100], "sticks": [101]})

    def test_group_found_by_rep_rep_none_skipped(self):
        """[found(100, None)] -> {} (rep=None records skipped — post-.pse
        reload reconstruction case; sentinel carries no rep)."""
        recs = [HiderRecord(100, 'obj', None, status=HIDER_STATUS_FOUND)]
        self.assertEqual(group_found_by_rep(recs), {})

    def test_group_found_by_rep_mixed_rep_and_none(self):
        """[found(100, spheres), found(101, None)] -> {'spheres': [100]}
        (rep=None record skipped, rep=spheres record kept)."""
        recs = [
            HiderRecord(100, 'obj', 'spheres', status=HIDER_STATUS_FOUND),
            HiderRecord(101, 'obj', None, status=HIDER_STATUS_FOUND),
        ]
        self.assertEqual(group_found_by_rep(recs), {"spheres": [100]})


class TestReconcileFromBcm(unittest.TestCase):
    """Test HiderRegistry.reconcile_with_bcm — .bcm metadata merge onto
    sentinel-rebuilt records (Phase 8 Plan 01).

    After reconstruct_from_sentinels, records have rep=None + status='hidden'.
    reconcile_with_bcm(bcm_hiders) overrides rep + status by matching
    (object, int(id)), and returns a ReconcileMismatches namedtuple of
    (missing_from_bcm, missing_from_pse, bad_rep). Pure (no pymol) —
    WSL-testable like the rest of registry.py.

    Each test builds a sentinel-rebuilt registry via
    reconstruct_from_sentinels with a fake iterate fn returning
    [('o', 1), ('o', 2), ('o', 3)] (or a subset), then calls
    reconcile_with_bcm with a .bcm hiders list and asserts the merged
    records + returned ReconcileMismatches.
    """

    def _rebuilt(self, keys=None):
        """Build a sentinel-rebuilt registry with the given (object, id) keys.

        Defaults to [('o', 1), ('o', 2), ('o', 3)] — the canonical 3-sentinel
        fixture mirroring the plan's behavior spec.
        """
        if keys is None:
            keys = [('o', 1), ('o', 2), ('o', 3)]
        reg = HiderRegistry()
        reg.reconstruct_from_sentinels(lambda: keys)
        return reg

    def test_perfect_match_sets_rep_and_status(self):
        """3 sentinels + 3 .bcm entries (1 found, reps spheres/sticks/cartoon)
        -> 3 records with real rep; 1 found, 2 hidden; mismatches all empty.
        """
        reg = self._rebuilt()
        bcm = [
            {'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'found'},
            {'id': 2, 'object': 'o', 'rep': 'sticks', 'status': 'hidden'},
            {'id': 3, 'object': 'o', 'rep': 'cartoon', 'status': 'hidden'},
        ]
        mismatches = reg.reconcile_with_bcm(bcm)
        self.assertEqual(reg.get('o', 1).rep, 'spheres')
        self.assertEqual(reg.get('o', 1).status, HIDER_STATUS_FOUND)
        self.assertEqual(reg.get('o', 2).rep, 'sticks')
        self.assertEqual(reg.get('o', 2).status, HIDER_STATUS_HIDDEN)
        self.assertEqual(reg.get('o', 3).rep, 'cartoon')
        self.assertEqual(reg.get('o', 3).status, HIDER_STATUS_HIDDEN)
        self.assertEqual(mismatches.missing_from_bcm, [])
        self.assertEqual(mismatches.missing_from_pse, [])
        self.assertEqual(mismatches.bad_rep, [])

    def test_missing_from_bcm_stays_rep_none_hidden(self):
        """Sentinel id=4 not in .bcm -> stays rep=None, status='hidden';
        missing_from_bcm == [('o', 4)].
        """
        reg = self._rebuilt([('o', 1), ('o', 4)])
        bcm = [{'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'found'}]
        mismatches = reg.reconcile_with_bcm(bcm)
        rec4 = reg.get('o', 4)
        self.assertIsNone(rec4.rep)
        self.assertEqual(rec4.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(mismatches.missing_from_bcm, [('o', 4)])

    def test_missing_from_pse_not_registered(self):
        """.bcm lists id=99 (not in sentinels) -> NOT registered (no 4th
        record); missing_from_pse == [('o', 99)]; registry has 3 records.
        """
        reg = self._rebuilt()
        bcm = [
            {'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'hidden'},
            {'id': 99, 'object': 'o', 'rep': 'sticks', 'status': 'hidden'},
        ]
        mismatches = reg.reconcile_with_bcm(bcm)
        self.assertIsNone(reg.get('o', 99))
        self.assertEqual(len(reg.all()), 3)
        self.assertEqual(mismatches.missing_from_pse, [('o', 99)])

    def test_bad_rep_skipped_with_warning(self):
        """.bcm hider with rep='surface' (not in GAME_REPS) -> rec.rep stays
        None; bad_rep == [('o', 1, 'surface')]; no raise.
        """
        reg = self._rebuilt([('o', 1)])
        bcm = [{'id': 1, 'object': 'o', 'rep': 'surface', 'status': 'found'}]
        mismatches = reg.reconcile_with_bcm(bcm)
        rec = reg.get('o', 1)
        self.assertIsNone(rec.rep)
        self.assertEqual(mismatches.bad_rep, [('o', 1, 'surface')])

    def test_bad_status_defaults_to_hidden(self):
        """.bcm hider with status='revealed' (unknown) -> rec.status='hidden';
        no raise.
        """
        reg = self._rebuilt([('o', 1)])
        bcm = [{'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'revealed'}]
        mismatches = reg.reconcile_with_bcm(bcm)
        rec = reg.get('o', 1)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(rec.rep, 'spheres')

    def test_pos_restored_from_bcm(self):
        """.bcm hider with pos=[1.0,2.0,3.0] -> rec.pos == [1.0,2.0,3.0] (list).
        """
        reg = self._rebuilt([('o', 1)])
        bcm = [{'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'hidden',
                'pos': [1.0, 2.0, 3.0]}]
        reg.reconcile_with_bcm(bcm)
        rec = reg.get('o', 1)
        self.assertEqual(rec.pos, [1.0, 2.0, 3.0])
        self.assertIsInstance(rec.pos, list)

    def test_empty_bcm_hiders_list(self):
        """reconcile_with_bcm([]) on 3-sentinel registry -> all 3 stay
        rep=None, hidden; missing_from_bcm has 3 entries.
        """
        reg = self._rebuilt()
        mismatches = reg.reconcile_with_bcm([])
        for rec in reg.all():
            self.assertIsNone(rec.rep)
            self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(len(mismatches.missing_from_bcm), 3)
        self.assertEqual(set(mismatches.missing_from_bcm),
                         {('o', 1), ('o', 2), ('o', 3)})

    def test_none_bcm_hiders(self):
        """reconcile_with_bcm(None) -> graceful (treated as empty list); 3
        missing_from_bcm entries.
        """
        reg = self._rebuilt()
        mismatches = reg.reconcile_with_bcm(None)
        for rec in reg.all():
            self.assertIsNone(rec.rep)
            self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(len(mismatches.missing_from_bcm), 3)

    def test_mismatched_object_not_merged(self):
        """.bcm hider (object='other', id=1) doesn't match sentinel ('o', 1)
        -> sentinel stays rep=None, hidden; .bcm entry flagged missing_from_pse.
        """
        reg = self._rebuilt([('o', 1)])
        bcm = [{'id': 1, 'object': 'other', 'rep': 'spheres', 'status': 'found'}]
        mismatches = reg.reconcile_with_bcm(bcm)
        rec = reg.get('o', 1)
        self.assertIsNone(rec.rep)
        self.assertEqual(rec.status, HIDER_STATUS_HIDDEN)
        self.assertEqual(mismatches.missing_from_pse, [('other', 1)])

    def test_id_int_coercion_in_bcm_index(self):
        """.bcm hider with id='5' (str from JSON) matches sentinel id=5 (int)
        via int(h['id']) coercion.
        """
        reg = self._rebuilt([('o', 5)])
        bcm = [{'id': '5', 'object': 'o', 'rep': 'spheres', 'status': 'found'}]
        mismatches = reg.reconcile_with_bcm(bcm)
        rec = reg.get('o', 5)
        self.assertEqual(rec.rep, 'spheres')
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        self.assertEqual(mismatches.missing_from_bcm, [])
        self.assertEqual(mismatches.missing_from_pse, [])

    def test_round_trip_to_dict_reconstruct_reconcile(self):
        """Full round-trip: register 3 -> to_dict -> reconstruct_from_sentinels
        (fake) -> reconcile_with_bcm(to_dict['hiders']) -> records match
        original (id/object/rep/status).
        """
        reg = HiderRegistry()
        reg.register('o', 1, 'spheres', status=HIDER_STATUS_FOUND)
        reg.register('o', 2, 'sticks', status=HIDER_STATUS_HIDDEN)
        reg.register('o', 3, 'cartoon', status=HIDER_STATUS_FOUND)
        d = reg.to_dict()
        # Simulate .pse reload: rebuild from sentinel ids, then reconcile
        reg2 = HiderRegistry()
        reg2.reconstruct_from_sentinels(
            lambda: [('o', r['id']) for r in d['hiders']])
        mismatches = reg2.reconcile_with_bcm(d['hiders'])
        self.assertEqual(mismatches.missing_from_bcm, [])
        self.assertEqual(mismatches.missing_from_pse, [])
        self.assertEqual(mismatches.bad_rep, [])
        for orig, rebuilt in zip(reg.all(), reg2.all()):
            self.assertEqual(rebuilt.id, orig.id)
            self.assertEqual(rebuilt.object, orig.object)
            self.assertEqual(rebuilt.rep, orig.rep)
            self.assertEqual(rebuilt.status, orig.status)

    def test_counts_by_rep_after_reconcile_reflects_bcm_reps(self):
        """After reconcile with 3 sphere hiders, counts_by_rep()['spheres']
        == 3 (NOT 0 — the load-bearing regression for the rep=None
        limitation that made reloaded games' per-rep counts all-zero).
        """
        reg = self._rebuilt()
        bcm = [
            {'id': 1, 'object': 'o', 'rep': 'spheres', 'status': 'hidden'},
            {'id': 2, 'object': 'o', 'rep': 'spheres', 'status': 'hidden'},
            {'id': 3, 'object': 'o', 'rep': 'spheres', 'status': 'hidden'},
        ]
        # Before reconcile: all rep=None -> counts all zero (the bug)
        self.assertEqual(reg.counts_by_rep()['spheres'], 0)
        reg.reconcile_with_bcm(bcm)
        # After reconcile: rep set from .bcm -> counts reflect it
        self.assertEqual(reg.counts_by_rep()['spheres'], 3)


class TestAltconfFields(unittest.TestCase):
    """Test the 3 Phase 11 alt-conf fields on HiderRecord + HiderRegistry
    (is_altconf, endpoint_resvs, alt_tag) + the new get_altconf_by_resv
    lookup.

    Alt-conf atoms SHARE ids with originals (research Pitfall 10), so the
    registry keyed by (object, id) cannot distinguish a real-trace click
    from an alt-conf hider click by id alone. The scoring solution (Plan
    05) reads alt + resv at pick time and gates on
    alt == rec.alt_tag AND rv1 < resv < rv2. That requires the registry
    to STORE is_altconf, endpoint_resvs, and alt_tag per record.
    get_altconf_by_resv handles non-anchor middle-atom clicks (USER
    REQUIREMENT 3: click ANY middle atom).

    Backward-compatible defaults (is_altconf=False, endpoint_resvs=None,
    alt_tag='') ensure existing Phase 3/4/5 callers passing only
    (object, id, rep, ...) are unaffected.
    """

    # ---- HiderRecord defaults + alt-conf fields ----

    def test_record_defaults(self):
        """HiderRecord(100, '1ubq', 'cartoon') -> is_altconf=False,
        endpoint_resvs=None, alt_tag='' (backward-compatible defaults)."""
        rec = HiderRecord(100, '1ubq', 'cartoon')
        self.assertFalse(rec.is_altconf)
        self.assertIsNone(rec.endpoint_resvs)
        self.assertEqual(rec.alt_tag, '')

    def test_record_altconf_fields(self):
        """HiderRecord with is_altconf=True, endpoint_resvs=(2,4), alt_tag='B'
        -> fields set as passed."""
        rec = HiderRecord(100, '1ubq', 'cartoon', is_altconf=True,
                          endpoint_resvs=(2, 4), alt_tag='B')
        self.assertTrue(rec.is_altconf)
        self.assertEqual(rec.endpoint_resvs, (2, 4))
        self.assertEqual(rec.alt_tag, 'B')

    # ---- register alt-conf fields + backward compat ----

    def test_register_altconf_fields(self):
        """register with is_altconf/endpoint_resvs/alt_tag -> returned record
        has the 3 fields; get() returns the same record with fields set."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                           endpoint_resvs=(2, 4), alt_tag='B')
        self.assertTrue(rec.is_altconf)
        self.assertEqual(rec.endpoint_resvs, (2, 4))
        self.assertEqual(rec.alt_tag, 'B')
        got = reg.get('1ubq', 100)
        self.assertIsNotNone(got)
        self.assertTrue(got.is_altconf)
        self.assertEqual(got.endpoint_resvs, (2, 4))
        self.assertEqual(got.alt_tag, 'B')

    def test_register_backward_compat(self):
        """register('1ubq', 101, 'spheres') with NO new fields ->
        rec.is_altconf is False, endpoint_resvs is None, alt_tag == ''
        (existing Phase 3/4/5 callers unaffected)."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', 101, 'spheres')
        self.assertFalse(rec.is_altconf)
        self.assertIsNone(rec.endpoint_resvs)
        self.assertEqual(rec.alt_tag, '')

    # ---- get_altconf_by_resv ----

    def test_get_altconf_by_resv_hit(self):
        """Alt-conf record (100, endpoint_resvs=(2,4));
        get_altconf_by_resv('1ubq', 3) -> returns that record (3 is strictly
        between 2 and 4)."""
        reg = HiderRegistry()
        rec = reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                           endpoint_resvs=(2, 4), alt_tag='B')
        got = reg.get_altconf_by_resv('1ubq', 3)
        self.assertIs(got, rec)

    def test_get_altconf_by_resv_endpoint_miss(self):
        """get_altconf_by_resv('1ubq', 2) -> None (endpoint, NOT strictly
        between); same for resv=4."""
        reg = HiderRegistry()
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        self.assertIsNone(reg.get_altconf_by_resv('1ubq', 2))
        self.assertIsNone(reg.get_altconf_by_resv('1ubq', 4))

    def test_get_altconf_by_resv_non_altconf_skipped(self):
        """Non-altconf record (102, 'spheres', is_altconf=False) ->
        get_altconf_by_resv('1ubq', 5) -> None (non-altconf records are
        skipped by the resv lookup)."""
        reg = HiderRegistry()
        reg.register('1ubq', 102, 'spheres')
        self.assertIsNone(reg.get_altconf_by_resv('1ubq', 5))

    def test_get_altconf_by_resv_first_match(self):
        """Two alt-conf records with disjoint ranges (2,4) and (6,8);
        get_altconf_by_resv('1ubq', 3) -> the first registered matching
        record (O(N) first-match; insertion order)."""
        reg = HiderRegistry()
        r1 = reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                          endpoint_resvs=(2, 4), alt_tag='B')
        r2 = reg.register('1ubq', 200, 'cartoon', is_altconf=True,
                          endpoint_resvs=(6, 8), alt_tag='B')
        # resv=3 is in (2,4) only -> first match is r1
        self.assertIs(reg.get_altconf_by_resv('1ubq', 3), r1)
        # resv=7 is in (6,8) only -> match is r2
        self.assertIs(reg.get_altconf_by_resv('1ubq', 7), r2)

    def test_get_altconf_by_resv_wrong_object(self):
        """get_altconf_by_resv('other', 3) -> None (object filter)."""
        reg = HiderRegistry()
        reg.register('1ubq', 100, 'cartoon', is_altconf=True,
                     endpoint_resvs=(2, 4), alt_tag='B')
        self.assertIsNone(reg.get_altconf_by_resv('other', 3))


if __name__ == '__main__':
    unittest.main(verbosity=2)
