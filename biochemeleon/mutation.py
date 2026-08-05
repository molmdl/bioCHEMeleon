"""Hider insertion + sentinel + cleanup -- cmd-coupled. insert_hider inserts
a pseudoatom INTO an existing object, tags the GAME sentinel, and returns
the new atom's stable id (fetched via the identify call, never the pseudoatom
return value). fetch_all_hider_ids reads back every sentinel atom's
``(object, id)`` tuple via the iterate primitive with an explicit dict
(hygienic -- no global namespace pollution), for registry reconstruction
and the smoke-test id-stability spike.

This module is the cmd-coupled mutation primitive for Phase 3. It lives in
the cmd layer (imports the pymol cmd module) alongside demos.py and
backup.py, and is NOT WSL-runnable at runtime -- only syntax-checked
(``python3.6 -m py_compile``) and runtime-verified by the Phase 3 Windows
PyMOL smoke test. The pure data model (HiderRegistry) lives in registry.py.

Source: .planning/phases/03-mutation-safety-hider-registry-foundation/
        03-RESEARCH.md, sections Q1 (pseudoatom return value), Q3 (alter
        sentinel + space= idiom), Q4 (id vs index).
"""
from pymol import cmd


# ---- Hider insertion (HIDER-01 + HIDER-02) ----

def insert_hider(object, pos, rep, handle, segi='GAME', b=-999.0):
    """Insert one hider pseudoatom INTO object. Returns the new atom's id
    (fetched via identify). The pseudoatom return value is an unverified C
    status code (RESEARCH sec Q1) -- NEVER rely on it.

    HIDER-01: the pseudoatom is inserted INTO *object* (object=existing,
    NOT a new object -- a separate object via load/create would let the
    player toggle one object to win). The public object list is
    therefore unchanged by this call.

    HIDER-02: the sentinel ``segi='GAME'`` + ``b=-999`` is set via alter
    with a single semicolon-joined expression (the canonical editor.py:354
    idiom). Cleanup and session reload identify hiders by
    this sentinel ONLY -- never by resi/chain/per-object index (unstable
    across deletions).

    The atom's stable ``id`` is fetched via identify (mode=0)
    (querying.py:1269; mode=0 returns the integral id list, NOT the
    fragile index). ``cmd.sort`` is called after the alter as a defensive
    habit (editing.py:1457 warns to sort after altering segi/chain; sort
    reassigns index but preserves id -- safe for the id-keyed registry).

    ``rep`` is accepted as a parameter (the registry needs it for
    per-rep counts) but insert_hider itself does NOT use rep for placement
    logic -- placement is Phase 4/5 generator work. Phase 3's insert_hider
    places at the caller-supplied *pos*; this proves the insertion
    mechanism, not the generator.

    Args:
        object (str): existing PyMOL object to insert INTO.
        pos (sequence of 3 floats): insertion coordinates.
        rep (str): one of GAME_REPS (validated by the registry, not here).
        handle (str): throwaway atom *name* used to re-select the new
            atom for the alter + identify calls (e.g. 'H001').
        segi (str): sentinel segment id (default 'GAME').
        b (float): sentinel b-factor (default -999.0).

    Returns:
        int: the new atom's stable id.

    Raises:
        AssertionError: if identify does not return exactly one id (the
            pseudoatom insert or alter did not produce a unique atom).
    """
    cmd.pseudoatom(object=object, pos=list(pos), name=handle,  # creating.py:1082
                   segi=segi, b=b, hetatm=1, elem='PS',
                   resn='HIDER', chain='H', resi='9001')
    cmd.alter(f"{object} and name {handle}", "segi='GAME'; b=-999.0",
              space={})  # editing.py:1424; editor.py:354 multi-`;` idiom; space={} avoids global namespace pollution (RESEARCH sec Q3)
    cmd.sort(object)  # defensive -- editing.py:1457 alter warning: sort after altering segi/chain
    ids = cmd.identify(f"{object} and name {handle} and segi GAME", mode=0)  # querying.py:1269; mode=0 returns id list, NOT index
    assert len(ids) == 1, "expected 1 new hider id, got %r" % (ids,)
    return ids[0]


# ---- Hider id reader (sentinel-based) ----

def fetch_all_hider_ids(object):
    """Read back every hider sentinel atom in *object* and return its
    ``(object_name, id)`` tuple. Used by the registry's
    ``reconstruct_from_sentinels`` (the iterate primitive is injected by
    game.py as dependency injection, keeping the registry pure) and by the
    Phase 3 smoke test's id-stability spike.

    The iterate call uses an explicit ``space=`` dict (NOT ``space=None``,
    which runs the expression against the global ``pymol.__dict__`` -- the
    legacy ``stored.xxx`` pattern that pollutes the global namespace;
    RESEARCH sec Q3). The explicit dict is the hygienic pattern
    (editor.py:156).

    The selector is the sentinel (``segi='GAME'`` + ``b=-999``). ``model``
    and ``id`` are read-only symbols exposed by the iterate primitive
    (editing.py:1446-1449). ``id`` is the STABLE integral identifier (NOT
    ``index`` -- RESEARCH sec Q4; the index primitive's own docstring warns
    indices are fragile across add/delete). Returning ``(model, id)``
    tuples (model = the object name) lets the registry key by
    ``(object, id)`` even in future multi-object scenarios.

    Args:
        object (str): the PyMOL object to scan for hider sentinels.

    Returns:
        list of (str, int): ``(object_name, id)`` tuples, one per sentinel
        atom found in *object* (empty list if none).
    """
    out = []
    cmd.iterate(f"{object} and segi GAME and b -999", "stored.append((model, id))",
                space={'stored': out})  # editing.py:1490; explicit dict avoids global namespace pollution (RESEARCH sec Q3); id = stable integral id, NOT index (RESEARCH sec Q4)
    return out  # list of (object_name, id)
