"""HiderRegistry pure data model - stdlib only, WSL-testable.

This module is the single source of truth for every inserted hider in a
game: each hider is recorded as a :class:`HiderRecord` keyed by the
stable ``(object, atom_id)`` tuple (Pitfall 4: ``id`` is stable across
add/remove; ``index`` is not). The registry lives in the PURE layer
(stdlib + ``setup_state.GAME_REPS`` only - NO ``pymol`` import, NO
``pymol.Qt`` import) so it is WSL-unit-testable, mirroring
``setup_state.py``'s convention.

Phase 3 scope (this module): the core CRUD subset -
  - :class:`HiderRecord`: data container with validation + key + to_dict
  - :class:`HiderRegistry`: ``OrderedDict``-backed register/get/all/remove

Later Phase 3 plans extend this with ``by_rep`` / ``counts_by_rep`` /
``mark_found`` (03-02), ``reconstruct_from_sentinels`` + ``to_dict`` /
``from_dict`` (03-03). The cmd-coupled insertion/cleanup lives in
``mutation.py``; the orchestrator lives in ``game.py``. The registry
stays pure by accepting an injected iterate function for sentinel
reconstruction (dependency inversion - implemented in 03-03).
"""

from collections import OrderedDict

from .setup_state import GAME_REPS


# ---- Constants ----

#: Default status for a freshly inserted hider (not yet found by player).
HIDER_STATUS_HIDDEN = 'hidden'

#: Status set when the player finds the hider (Phase 4/6 click handler).
HIDER_STATUS_FOUND = 'found'


# ---- HiderRecord ----

class HiderRecord(object):
    """One inserted hider atom - pure data container.

    Attributes:
        id (int): the stable PyMOL atom identifier (NOT the fragile
            ``index``). Cast to ``int`` on construction.
        object (str): the PyMOL object name the hider was inserted INTO.
            Atom ids are per-object; ``(object, id)`` is the future-safe
            primary key (multi-target safety).
        rep (str): one of :data:`biochemeleon.setup_state.GAME_REPS`.
            Required for per-rep counts (criterion 3).
        status (str): ``'hidden'`` (default) or ``'found'``. The field
            exists now (cheap); ``found`` is set in Phase 4/6.
        pos: optional ``(x, y, z)`` tuple for hint/reveal (Phase 6).
            Stored as-is; ``to_dict`` serializes it as a list.

    Uses ``__slots__`` to keep instances compact and to surface typos
    as ``AttributeError`` (no accidental attribute creation).
    """

    __slots__ = ('id', 'object', 'rep', 'status', 'pos')

    def __init__(self, id, object, rep, status=HIDER_STATUS_HIDDEN, pos=None):
        if rep not in GAME_REPS:
            raise ValueError("rep must be one of %r" % (GAME_REPS,))
        self.id = int(id)
        self.object = object
        self.rep = rep
        self.status = status
        self.pos = pos

    def key(self):
        """Return the registry primary key ``(object, id)``.

        ``id`` is already ``int`` (coerced in ``__init__``); this is the
        exact tuple :class:`HiderRegistry` uses to store/lookup records.
        """
        return (self.object, self.id)

    def to_dict(self):
        """Return a JSON-serializable dict representation.

        ``pos`` is included (as a list) only when it is not ``None``;
        this keeps the Phase 8 ``.bcm`` sidecar compact when pos is
        unused (Phase 3/4).
        """
        d = {'id': self.id, 'object': self.object, 'rep': self.rep,
             'status': self.status}
        if self.pos is not None:
            d['pos'] = list(self.pos)
        return d


# ---- HiderRegistry ----

class HiderRegistry(object):
    """OrderedDict-backed registry of :class:`HiderRecord` (core CRUD).

    Keyed by ``(object, id)`` (Pitfall 4: ``id`` is stable across
    add/remove; ``index`` is not). Preserves insertion order so
    ``all()`` returns records in the order they were registered - this
    matches the order hiders are inserted into the target object, which
    the click handler (Phase 4) relies on for stable iteration.

    Phase 3 core subset: ``register`` / ``get`` / ``all`` / ``remove``.
    Later plans add ``by_rep`` / ``counts_by_rep`` / ``mark_found``
    (03-02), ``reconstruct_from_sentinels`` + ``to_dict`` / ``from_dict``
    (03-03).
    """

    def __init__(self):
        # OrderedDict so all() is deterministic insertion order even on
        # Python 3.6 (where dict order is an impl detail, not guaranteed
        # by the language spec; OrderedDict makes the contract explicit).
        self._records = OrderedDict()   # key (object, id) -> HiderRecord

    def register(self, object, id, rep, status=HIDER_STATUS_HIDDEN, pos=None):
        """Create, store, and return a new :class:`HiderRecord`.

        Raises ``KeyError`` if ``(object, id)`` is already registered
        (duplicate insert - caller bug). ``id`` is coerced to ``int``
        via :class:`HiderRecord` so ``register('1ubq', '1', ...)`` and
        ``get('1ubq', 1)`` round-trip correctly.
        """
        rec = HiderRecord(id, object, rep, status, pos)
        if rec.key() in self._records:
            raise KeyError("hider %r already registered" % (rec.key(),))
        self._records[rec.key()] = rec
        return rec

    def get(self, object, id):
        """Return the :class:`HiderRecord` for ``(object, id)`` or ``None``.

        ``id`` is coerced to ``int`` so ``get('1ubq', '1')`` matches a
        record registered with ``register('1ubq', 1, ...)``.
        """
        return self._records.get((object, int(id)))

    def all(self):
        """Return a list of all records in insertion order (fresh copy)."""
        return list(self._records.values())

    def remove(self, object, id):
        """Remove the record for ``(object, id)``.

        Returns ``True`` if a record was removed, ``False`` if absent
        (idempotent-safe: removing twice returns ``False`` the second
        time, never raises). ``id`` is coerced to ``int``.
        """
        return self._records.pop((object, int(id)), None) is not None
