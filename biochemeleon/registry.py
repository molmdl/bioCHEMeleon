"""HiderRegistry pure data model - stdlib only, WSL-testable.

This module is the single source of truth for every inserted hider in a
game: each hider is recorded as a :class:`HiderRecord` keyed by the
stable ``(object, atom_id)`` tuple (Pitfall 4: ``id`` is stable across
add/remove; ``index`` is not). The registry lives in the PURE layer
(stdlib + ``setup_state.GAME_REPS`` only - NO ``pymol`` import, NO
``pymol.Qt`` import) so it is WSL-unit-testable, mirroring
``setup_state.py``'s convention.

Phase 3 scope (this module):
  - :class:`HiderRecord`: data container with validation + key + to_dict
  - :class:`HiderRegistry`: ``OrderedDict``-backed core CRUD
    (register/get/all/remove) + queries (by_rep/counts_by_rep) +
    status update (mark_found) + serialization (to_dict/from_dict) +
    sentinel reconstruction (reconstruct_from_sentinels, dependency
    injection - rep=None tolerance for post-``.pse``-reload rebuild)

The cmd-coupled insertion/cleanup lives in ``mutation.py``; the
orchestrator lives in ``game.py``. The registry stays pure by accepting
an injected iterate function for sentinel reconstruction (dependency
inversion - ``reconstruct_from_sentinels`` takes the iterate callable
as a parameter, so ``game.py`` injects ``lambda: mutation.fetch_all_hider_ids(obj)``
and this module never imports ``pymol``; ``to_dict`` / ``from_dict`` let
Phase 8 just write the dict to a ``.bcm`` JSON sidecar and read it back).
"""

from collections import OrderedDict, namedtuple

from .setup_state import GAME_REPS


# ---- Constants ----

#: Default status for a freshly inserted hider (not yet found by player).
HIDER_STATUS_HIDDEN = 'hidden'

#: Status set when the player finds the hider (Phase 4/6 click handler).
HIDER_STATUS_FOUND = 'found'


#: Returned by :meth:`HiderRegistry.reconcile_with_bcm` — three classes
#: of disagreement between the sentinel-rebuilt registry and the .bcm
#: sidecar. Empty lists = perfect match. The caller (game.py /
#: __init__.py) decides whether to log warnings or refuse the load;
#: the registry stays usable regardless (degraded = playable).
ReconcileMismatches = namedtuple(
    'ReconcileMismatches',
    ['missing_from_bcm',   # [(object, id)] sentinel atoms NOT in .bcm
     'missing_from_pse',   # [(object, id)] .bcm hiders NOT in sentinels
     'bad_rep'])           # [(object, id, bad_rep)] .bcm reps not in GAME_REPS


# ---- HiderRecord ----

class HiderRecord(object):
    """One inserted hider atom - pure data container.

    Attributes:
        id (int): the stable PyMOL atom identifier (NOT the fragile
            ``index``). Cast to ``int`` on construction.
        object (str): the PyMOL object name the hider was inserted INTO.
            Atom ids are per-object; ``(object, id)`` is the future-safe
            primary key (multi-target safety).
        rep (str or None): one of :data:`biochemeleon.setup_state.GAME_REPS`,
            or ``None``. A valid rep is required for per-rep counts
            (criterion 3) on the normal insert path (``register()`` always
            passes a valid rep). ``rep=None`` is allowed ONLY for the
            post-``.pse``-reload reconstruction path
            (:meth:`HiderRegistry.reconstruct_from_sentinels`): the
            sentinel carries no rep, so the rebuilt record stores ``None``
            pending Phase 8 ``.bcm`` sidecar reconciliation.
        status (str): ``'hidden'`` (default) or ``'found'``. The field
            exists now (cheap); ``found`` is set in Phase 4/6.
        pos: optional ``(x, y, z)`` tuple for hint/reveal (Phase 6).
            Stored as-is; ``to_dict`` serializes it as a list.

    Uses ``__slots__`` to keep instances compact and to surface typos
    as ``AttributeError`` (no accidental attribute creation).
    """

    __slots__ = ('id', 'object', 'rep', 'status', 'pos')

    def __init__(self, id, object, rep, status=HIDER_STATUS_HIDDEN, pos=None):
        # rep=None is allowed (post-reload reconstruction; the sentinel
        # carries no rep). Normal register() always passes a valid rep.
        if rep is not None and rep not in GAME_REPS:
            raise ValueError("rep must be one of %r (or None)" % (GAME_REPS,))
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

    Phase 3 methods: ``register`` / ``get`` / ``all`` / ``remove``
    (core CRUD) plus ``by_rep`` / ``counts_by_rep`` / ``mark_found``
    (queries + status) plus ``to_dict`` / ``from_dict`` (serialization
    for the Phase 8 ``.bcm`` sidecar) plus ``reconstruct_from_sentinels``
    (dependency-injected sentinel rebuild after ``.pse`` reload;
    ``rep=None`` tolerance - the sentinel carries no rep). registry.py
    is functionally complete for Phase 3 (10 methods).
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

    # ---- queries + status ----

    def by_rep(self, rep):
        """Return all records matching ``rep`` in insertion order.

        Pure filter over the stored records; returns a fresh list. Reps
        with no hiders return ``[]`` (not ``None``) so callers can
        iterate without a None-check. Used by the Phase 4 Game tab to
        show remaining hiders per representation.
        """
        return [r for r in self._records.values() if r.rep == rep]

    def counts_by_rep(self):
        """Return ``{rep: count}`` for EVERY rep in :data:`GAME_REPS`.

        Zero-fills reps with no hiders so the Game tab can render
        ``"cartoon: 0"`` even when no cartoon hiders exist (criterion 3:
        per-rep counts). The returned dict's key order matches
        :data:`GAME_REPS`; counts reflect insertion-order records.

        Records with ``rep=None`` (from
        :meth:`reconstruct_from_sentinels`) are SKIPPED: the returned
        dict has only :data:`GAME_REPS` keys, never a ``None`` key. This
        is a documented limitation - Phase 8's ``.bcm`` sidecar reconciles
        ``rep`` for reloaded games, after which ``counts_by_rep``
        reflects the rebuilt records normally.
        """
        out = {rep: 0 for rep in GAME_REPS}
        for r in self._records.values():
            if r.rep is None:
                continue
            out[r.rep] = out.get(r.rep, 0) + 1
        return out

    def mark_found(self, object, id):
        """Set the record at ``(object, id)`` status to ``'found'``.

        Raises ``KeyError`` if ``(object, id)`` is not registered - this
        is the desired behavior for the Phase 4 click handler: clicking
        an atom that isn't a registered hider is a caller bug, and a
        clean ``KeyError`` surfaces it immediately rather than silently
        no-op-ing. ``id`` is coerced to ``int`` (matches register/get/
        remove).
        """
        rec = self._records[(object, int(id))]
        rec.status = HIDER_STATUS_FOUND

    # ---- serialization (Phase 8 .bcm sidecar shape) ----

    def to_dict(self):
        """Return the JSON-serializable registry shape for the ``.bcm`` sidecar.

        Returns ``{'version': 1, 'hiders': [record.to_dict() for each
        record in insertion order]}``. The shape is designed in Phase 3
        and unit-tested for round-trip correctness so Phase 8 just writes
        this dict to a JSON file and reads it back via
        :meth:`from_dict` - no schema migration at Phase 8.
        """
        return {'version': 1,
                'hiders': [r.to_dict() for r in self._records.values()]}

    @classmethod
    def from_dict(cls, d):
        """Reconstruct a :class:`HiderRegistry` from a ``to_dict`` payload.

        Tolerant: a missing ``'version'`` key is accepted (treated as
        v1); a missing ``'status'`` on a hider defaults to
        :data:`HIDER_STATUS_HIDDEN`; a missing ``'pos'`` stays ``None``.
        ``pos`` is stored as-is (a list from JSON); list/tuple
        normalization is a Phase 8 boundary concern.

        Raises ``KeyError`` if a hider dict is missing ``'object'`` /
        ``'id'`` / ``'rep'`` (required fields). ``id`` is coerced to
        ``int`` via :meth:`register` (matches the rest of the registry).
        """
        reg = cls()
        for h in d.get('hiders', []):
            reg.register(h['object'], h['id'], h['rep'],
                          h.get('status', HIDER_STATUS_HIDDEN), h.get('pos'))
        return reg

    # ---- sentinel reconstruction (dependency injection) ----

    def reconstruct_from_sentinels(self, iterate_hider_keys):
        """Rebuild the registry from sentinel atoms after a ``.pse`` reload.

        ``iterate_hider_keys`` is a callable returning an iterable of
        ``(object, id)`` tuples for ``segi='GAME'`` + ``b=-999`` atoms
        (the sentinel). It is INJECTED by ``game.py`` (typically
        ``lambda: mutation.fetch_all_hider_ids(obj)``) so this module
        stays pure - NO ``pymol`` import (dependency inversion).

        The sentinel carries no ``rep`` (RESEARCH Open Risk 6), so the
        rebuilt records store ``rep=None`` pending Phase 8 ``.bcm``
        sidecar reconciliation. ``rep=None`` is tolerated here (and ONLY
        here - normal :meth:`register` always passes a valid rep).

        Clears existing records first (overwrite, NOT append), then
        registers each sentinel as a fresh :class:`HiderRecord` with
        ``status=HIDER_STATUS_HIDDEN`` (a reloaded game treats all
        sentinel survivors as unfound). Returns ``self`` (fluent).
        """
        self._records.clear()
        for (obj, aid) in iterate_hider_keys():
            self._records[(obj, int(aid))] = HiderRecord(aid, obj, rep=None,
                                                         status=HIDER_STATUS_HIDDEN)
        return self

    # ---- .bcm sidecar reconciliation (Phase 8) ----

    def reconcile_with_bcm(self, bcm_hiders):
        """Reconcile sentinel-rebuilt records with .bcm sidecar metadata.

        Precondition: ``self`` was rebuilt via
        :meth:`reconstruct_from_sentinels` (records keyed by
        ``(object, id)``, ``rep=None``, ``status='hidden'``). For each
        ``.bcm`` hider dict, find the matching rebuilt record by
        ``(object, id)`` and set ``rep`` + ``status`` (and ``pos`` if
        present). Returns a :data:`ReconcileMismatches` namedtuple of
        three mismatch lists; the caller decides whether to log warnings
        or refuse the load.

        Pure (no ``pymol`` import). Takes a list of dicts (the
        ``.bcm['registry']['hiders']`` list). Mutates ``self._records``
        in place.

        Mismatch handling (never raises — degraded is playable):
          - sentinel NOT in .bcm (``missing_from_bcm``): left as
            ``rep=None`` + ``status='hidden'`` (real atom, still clickable).
          - .bcm hider NOT in sentinels (``missing_from_pse``): NOT
            registered (ghost entry would corrupt counts_by_rep + on_pick).
          - .bcm rep not in :data:`GAME_REPS` (``bad_rep``): rec.rep stays
            ``None`` (do NOT raise — corrupt sidecar should not kill load).
          - .bcm status not in (hidden, found): defaults to ``'hidden'``.
        """
        missing_from_bcm = []
        missing_from_pse = []
        bad_rep = []
        bcm_index = {}
        for h in bcm_hiders or []:
            try:
                key = (h['object'], int(h['id']))
            except (KeyError, TypeError, ValueError):
                continue  # malformed .bcm entry — skip
            bcm_index[key] = h
        for key, rec in self._records.items():
            h = bcm_index.get(key)
            if h is None:
                missing_from_bcm.append(key)
                continue
            bcm_rep = h.get('rep')
            if bcm_rep is not None and bcm_rep not in GAME_REPS:
                bad_rep.append((key[0], key[1], bcm_rep))
                # leave rec.rep = None
            else:
                rec.rep = bcm_rep
            bcm_status = h.get('status', HIDER_STATUS_HIDDEN)
            if bcm_status not in (HIDER_STATUS_HIDDEN, HIDER_STATUS_FOUND):
                bcm_status = HIDER_STATUS_HIDDEN
            rec.status = bcm_status
            if 'pos' in h and h['pos'] is not None:
                rec.pos = list(h['pos'])
        for key, h in bcm_index.items():
            if key not in self._records:
                missing_from_pse.append(key)
        return ReconcileMismatches(
            missing_from_bcm=missing_from_bcm,
            missing_from_pse=missing_from_pse,
            bad_rep=bad_rep)


# ---- Phase 7 found-hider selection helpers ----

def build_found_selection(records, object_name):
    """Build a PyMOL selection string for all FOUND hiders.

    Pure (no cmd, no Qt). Returns ``'<object_name> and id X+Y+Z'`` for
    records with ``status == HIDER_STATUS_FOUND``, or ``None`` if no
    records are found. Used by the Game tab dropdown (GAME-08) to select
    found hiders for hide/show/recolor.

    ``records`` is a list of :class:`HiderRecord` (typically
    ``registry.all()``). The selection uses atom ``id`` (stable across
    add/remove; Pitfall 4) joined with ``+`` — PyMOL's ``id`` selector
    accepts the ``id 1+2+3`` form. ``None`` (not an empty string) signals
    "no found hiders" so the caller can early-return without issuing a
    malformed selection.
    """
    found_ids = [r.id for r in records if r.status == HIDER_STATUS_FOUND]
    if not found_ids:
        return None
    return "%s and id %s" % (object_name,
                             "+".join(str(i) for i in found_ids))


def group_found_by_rep(records):
    """Return ``{rep: [ids]}`` for all FOUND records with ``rep is not None``.

    Pure dict building. Skips ``rep=None`` records (the post-``.pse``
    reload reconstruction case — the sentinel carries no rep; Phase 8
    ``.bcm`` sidecar reconciles). Used by the Game tab dropdown 'show'
    mode: iterate the dict and ``cmd.show(rep, '<obj> and id X+Y')`` per
    rep so each found hider is re-shown in its ORIGINAL rep (not a single
    uniform rep for all).
    """
    out = {}
    for r in records:
        if r.status == HIDER_STATUS_FOUND and r.rep is not None:
            out.setdefault(r.rep, []).append(r.id)
    return out
