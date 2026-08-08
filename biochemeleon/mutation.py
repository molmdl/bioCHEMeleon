"""Hider insertion + sentinel + cleanup -- cmd-coupled. insert_hider inserts
a pseudoatom INTO an existing object, tags the GAME sentinel, and returns
the new atom's stable id (fetched via the identify call, never the pseudoatom
return value). fetch_all_hider_ids reads back every sentinel atom's
``(object, id)`` tuple via the iterate primitive with an explicit dict
(hygienic -- no global namespace pollution), for registry reconstruction
and the smoke-test id-stability spike. cleanup_hiders removes all sentinel
atoms FROM an object by sentinel (happy-path cleanup -- the remove primitive
deletes atoms FROM the object, not the object itself) and returns the count
removed (idempotent; gates the remove call on a non-zero sentinel count).

Phase 5 adds three line/stick + cartoon inserters: insert_line_stick_hider
(pseudoatom + bond for lines/sticks), insert_cartoon_hider (attached
residue at a terminus for cartoon/ribbon), and insert_hider_for_rep (per-rep
dispatcher). The coloring strategy (research sec Q15 option c) keeps the
GAME sentinel UNCHANGED (so Phase 3 cleanup + read path need zero migration)
AND copies the neighbor's color/elem/ss onto the hider via alter so the
default rendering blends -- NOT the Phase 4 sphere elem, which would stand
out in line/stick/cartoon. Runtime behavior (same-object bond, named attach
selection, segi-doesn't-break-polymer, color-follows-C-alpha) is deferred to
the Phase 5 headless smoke.

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
    cmd.iterate(f"{object} and segi GAME and b < 0", "stored.append((model, ID))",
                space={'stored': out})  # editing.py:1490; explicit dict avoids global namespace pollution (RESEARCH sec Q3); id = stable integral id, NOT index (RESEARCH sec Q4)
    return out  # list of (object_name, id)


# ---- Hider cleanup (sentinel-based, happy path) ----

def cleanup_hiders(object):
    """Remove all hider sentinel atoms FROM *object* and return the count
    removed. Happy-path cleanup: the remove primitive deletes atoms FROM
    the object (NOT the object itself, unlike the delete primitive which
    removes the whole object) -- the original structure stays and only
    hiders are removed, so the object matches its pre-game state (criterion
    4). This is the happy-path counterpart to ``backup.restore`` (the
    failure path).

    Cleanup is by sentinel ONLY -- the selector is the sentinel
    (``segi='GAME'`` + ``b=-999``), never resi/chain/per-object index
    (unstable across deletions; AGENTS.md sentinel-only rule), which makes
    cleanup robust against registry loss on a ``.pse`` reload (RESEARCH
    sec Q4). The count-atoms primitive (querying.py:1412) gates the remove
    call: if the sentinel count is zero, the remove is skipped (idempotent
    -- no error on an empty selection). The returned count lets the caller
    (game.py cleanup) assert it matches the registry length.

    Args:
        object (str): the PyMOL object to remove hider sentinels from.

    Returns:
        int: the number of hider sentinel atoms removed (0 if none were
            present -- idempotent).
    """
    before = cmd.count_atoms(f"{object} and segi GAME")  # querying.py:1412; gate to skip remove on empty selection
    if before:
        cmd.remove(f"{object} and segi GAME")  # editing.py:800; remove atoms FROM object (NOT delete the object)
    return before


# ---- Line/stick + cartoon inserters (Phase 5) ----

def insert_line_stick_hider(object, offset, neighbor_id, handle,
                             rep='sticks', segi='GAME', b=-999.0,
                             bond_order=1):
    """Insert a bonded pseudoatom near *neighbor_id* (line/stick hider)
    and return the new atom's stable id.

    Lines and sticks are BOND-based representations -- a lone pseudoatom
    is invisible (RESEARCH sec Q1). This function places a pseudoatom at
    ``neighbor_coord + offset``, bonds it to the neighbor (same-object
    bond -- the bond primitive requires both atoms in one object;
    RESEARCH sec Q2/Q4), and shows the *rep* on the new atom only (by id,
    NOT all GAME atoms -- avoids cross-contamination with sphere/cartoon
    hiders; RESEARCH sec Q11: newly-inserted atoms do NOT inherit shown
    reps).

    Coloring (research sec Q15 option c): the GAME sentinel
    (``segi='GAME'`` + ``b=-999``) is KEPT UNCHANGED so Phase 3 cleanup
    (``segi GAME``) and the sentinel read path need zero migration. The
    neighbor's color and elem are copied onto the hider via a single
    alter call so the DEFAULT rendering blends (NOT the Phase 4 sphere
    elem, which would stand out in line/stick -- research sec Q12/Q17).

    The neighbor's coords are read via iterate-state (the iterate
    primitive does NOT expose x/y/z -- RESEARCH sec Q6 / Phase 3
    finding). The neighbor's elem and color are read in the same
    iterate-state call (research sec Q13 confirms color/elem are
    exposed; if iterate-state does NOT expose elem/color at runtime, the
    Phase 5 smoke will catch it -- LOW risk, research Open Risk 6).

    Args:
        object (str): existing PyMOL object to insert INTO.
        offset (sequence of 3 floats): [dx, dy, dz] offset from the
            neighbor's coords (pure RNG from generators.py).
        neighbor_id (int): stable atom id of the real neighbor to bond
            to (same object).
        handle (str): throwaway atom *name* used to re-select the new
            atom for the alter + identify calls.
        rep (str): 'lines' or 'sticks' -- shown on the new atom by id.
        segi (str): sentinel segment id (default 'GAME').
        b (float): sentinel b-factor (default -999.0).
        bond_order (int): bond order (default 1 = single bond).

    Returns:
        int: the new atom's stable id.

    Raises:
        AssertionError: if identify does not return exactly one id.
    """
    # 1. Read neighbor coords + elem + color (iterate-state exposes x/y/z;
    #    research sec Q13: color/elem exposed by iterate; combined here in
    #    one call -- LOW risk if iterate-state doesn't expose elem/color at
    #    runtime, smoke will catch it).
    nbr = []
    cmd.iterate_state(1, "%s and id %d" % (object, neighbor_id),
                      "stored.append((x, y, z, elem, color))",
                      space={'stored': nbr})  # editing.py:1490; hygienic space= dict (RESEARCH sec Q3)
    nx, ny, nz, n_elem, n_color = nbr[0]
    # 2. Insert pseudoatom at neighbor + offset, plausible elem (neighbor's)
    pos = [nx + offset[0], ny + offset[1], nz + offset[2]]
    cmd.pseudoatom(object=object, pos=pos, name=handle,  # creating.py:1082
                   segi=segi, b=b, hetatm=0, elem=n_elem,
                   resn='HIDER', chain='H', resi='9001')
    # 3. Sentinel + blend alter (single hygienic call -- research sec Q14):
    #    KEEP segi='GAME' + b=-999 sentinel (option c), ADD color=neighbor.
    cmd.alter("%s and name %s" % (object, handle),
              "segi='GAME'; b=-999.0; color=stored_c",
              space={'stored_c': n_color})  # editing.py:1424; space= hygienic (RESEARCH sec Q3)
    cmd.sort(object)  # defensive -- editing.py:1457 alter warning: sort after altering segi/chain
    # 4. Fetch the new atom's stable id (NEVER the pseudoatom return value; RESEARCH sec Q1)
    hider_ids = cmd.identify("%s and name %s and segi GAME" % (object, handle),
                             mode=0)  # querying.py:1269; mode=0 returns id list, NOT index
    assert len(hider_ids) == 1, "expected 1 new line/stick hider id, got %r" % (hider_ids,)
    hider_id = hider_ids[0]
    # 5. Bond to neighbor (same-object bond -- editing.py:717 satisfied)
    cmd.bond("%s and id %d" % (object, hider_id),
             "%s and id %d" % (object, neighbor_id),
             order=bond_order)  # editing.py:694; order=1 single bond
    # 6. Show ONLY this atom's rep (NOT all GAME -- avoids cross-contamination; Q11)
    cmd.show(rep, "%s and id %d" % (object, hider_id))  # viewing.py:491
    return hider_id


def insert_cartoon_hider(object, chain, terminus_resi, is_c_terminus,
                         handle, aa='gly', ss=4, hydro=1,
                         segi='GAME', b=-999.0):
    """Attach a residue at a terminus (cartoon/ribbon hider) and return
    the new residue's C-alpha stable id.

    Cartoon and ribbon are POLYMER-TRACE representations -- a lone
    pseudoatom is invisible (Pitfall 8; research sec Q5). This function
    attaches a real glycine residue at a chain terminus via the
    residue-attach primitive (which fuses real backbone geometry via
    mode-2 fuse internally -- research sec Q6), applies the GAME
    sentinel + neighbor blend, shows the cartoon rep on the new residue
    only, and returns the new C-alpha's stable id (the cartoon-
    representative atom the player clicks).

    Coloring (research sec Q15 option c): the GAME sentinel
    (``segi='GAME'`` + ``b=-999``) is KEPT UNCHANGED so Phase 3 cleanup
    + read path need zero migration. The neighbor C-alpha's color and
    secondary structure are copied onto the new residue via a single
    alter call so the cartoon tube segment blends (research sec Q16:
    cartoon color follows the C-alpha by default).

    The residue-attach primitive lives in the ``pymol.editor`` module
    (``editor.attach_amino_acid``) and is NOT exposed as
    ``cmd.attach_amino_acid`` in PyMOL 2.5.0 open-source (``cmd.py`` imports
    ``editor`` lazily inside a function, so ``cmd.editor`` is not a stable
    attribute). It is imported lazily inside this function (``from pymol
    import editor``) so the module-level import stays minimal and WSL unit
    tests (which stub ``pymol`` as ``MagicMock``) never trigger this path.
    It is called with a NAMED selection (NOT ``pk1`` -- research Open Risk 2:
    the general path accepts any sele; the Phase 5 smoke confirms).
    ``ss=4`` (flat/loop) gives the least conspicuous extension (no helix
    ribbon or sheet arrow). ``hydro=0`` suppresses hydrogens. ``aa='gly'``
    (glycine -- smallest side chain; research sec Q6).

    MVP uses the N-terminus (``is_c_terminus=False`` ->
    ``new_resi = terminus_resi - 1``, attach at ``name N``); the C-terminus
    path (``is_c_terminus=True``) is supported but NOT exercised by the
    generators because the C-terminus carbonyl C carries an OXT (terminal
    oxygen) in most structures (e.g. 1ubq), which saturates the C valence
    and makes the residue-attach primitive fail with "no target attachment
    vector found" (ObjectMolecule.cpp:3357). The N-terminus N has a free
    valence and extends cleanly with NO atom removal, so the happy-path
    sentinel cleanup restores the structure exactly (verified in the
    Phase 5 headless smoke).

    Args:
        object (str): existing PyMOL object to attach INTO.
        chain (str): chain identifier of the terminal residue.
        terminus_resi (int): residue number of the terminal residue.
        is_c_terminus (bool): True for C-terminus extension (forward,
            new_resi = terminus_resi + 1); False for N-terminus
            (backward, new_resi = terminus_resi - 1).
        handle (str): throwaway atom *name* (unused here but kept for
            signature symmetry with insert_hider).
        aa (str): amino acid fragment name (default 'gly').
        ss (int): secondary structure for dihedrals (default 4 = flat).
        hydro (int): hydrogen handling (default 1 = keep hydrogens).
            CRITICAL: hydro=0 causes attach_amino_acid to remove ALL
            hydrogens from the ENTIRE object (pkmol scope), not just the
            new residue. This was discovered in the 05-05 human-verify:
            1znf (which has H atoms) lost ~200 atoms on attach with
            hydro=0, causing verify_intact to fail. hydro=1 keeps
            existing H and only adds/fixes H on the new residue (which
            gets segi=GAME and is removed on cleanup).
        segi (str): sentinel segment id (default 'GAME').
        b (float): sentinel b-factor (default -999.0).

    Returns:
        int: the new residue's C-alpha stable id.

    Raises:
        AssertionError: if identify does not return exactly one C-alpha.
    """
    residue_sele = "%s and chain %s and resi %d" % (object, chain, terminus_resi)
    # 1. Read neighbor (terminal residue) C-alpha props for blending
    #    (research sec Q13: iterate exposes chain/ss/color lowercase)
    nbr = []
    cmd.iterate("%s and name CA" % residue_sele,
                "stored.append((chain, ss, color))",
                space={'stored': nbr})  # editing.py:1490; hygienic space= dict (RESEARCH sec Q3)
    n_chain, n_ss, n_color = nbr[0]
    # 2. Build the attach selection (single N or C atom -- editor.py:125)
    attach_sele = "%s and name %s" % (residue_sele,
                                     "C" if is_c_terminus else "N")
    # 3. Attach the residue (fuses real backbone geometry; mode=2 internally).
    #    attach_amino_acid lives in the pymol.editor module (editor.py:85) and is
    #    NOT exposed as cmd.attach_amino_acid in PyMOL 2.5.0 open-source (cmd.py
    #    imports editor lazily inside a function, so cmd.editor is not a stable
    #    attribute). Imported lazily here so the module-level import stays
    #    minimal and WSL unit tests (which stub pymol as MagicMock) never trigger
    #    this path.
    from pymol import editor  # editor.py:85; not exposed as cmd.attach_amino_acid
    editor.attach_amino_acid(attach_sele, aa, ss=ss, hydro=hydro)
    # 4. Compute new residue number (C-term: +1 forward; N-term: -1 backward)
    new_resi = terminus_resi + 1 if is_c_terminus else terminus_resi - 1
    new_sele = "%s and chain %s and resi %d" % (object, n_chain, new_resi)
    # 5. Sentinel + blend alter (single hygienic call -- research sec Q14):
    #    KEEP segi='GAME' + b=-999 sentinel (option c), ADD color + ss for blend
    cmd.alter(new_sele,
              "segi='GAME'; b=-999.0; color=stored_c; ss=stored_ss",
              space={'stored_c': n_color, 'stored_ss': n_ss})  # editing.py:1424
    cmd.sort(object)  # defensive -- editing.py:1457; research sec Q23
    # 6. Show cartoon on ONLY the new residue (NOT all GAME; Q11: fused atoms
    #    start with no reps; same atoms render in ribbon too -- Q10)
    cmd.show('cartoon', "%s and resi %d and segi GAME" % (object, new_resi))  # viewing.py:491
    # 7. Fetch the new C-alpha stable id (the cartoon-representative atom)
    ids = cmd.identify("%s and name CA and segi GAME and resi %d" % (object, new_resi),
                       mode=0)  # querying.py:1269; mode=0 returns id list, NOT index
    assert len(ids) == 1, "expected 1 new cartoon C-alpha, got %r" % (ids,)
    return ids[0]


def insert_hider_for_rep(object, rep, payload, handle):
    """Dispatch hider insertion per representation.

    Lets ``GameController.start`` stay a thin ``(payload, rep)`` loop --
    the dispatcher hides the rep-specific insertion signature divergence
    (research sec Q19): spheres need ``pos``, line/stick need
    ``(offset, neighbor_id)``, cartoon/ribbon need
    ``(chain, terminus_resi, is_c_terminus)``.

    For spheres: calls the UNCHANGED Phase 3 ``insert_hider`` (which does
    NOT show the rep) then shows spheres BY ID (NOT all GAME atoms -- the
    dispatcher owns the sphere show so ``_on_start`` no longer shows ALL
    GAME atoms as spheres, which would cross-contaminate stick/cartoon
    hiders).

    For lines/sticks: unpacks ``(offset, neighbor_id)`` and delegates to
    ``insert_line_stick_hider`` (which shows its own rep by id).

    For cartoon/ribbon: unpacks ``(chain, terminus_resi, is_c_terminus)``
    and delegates to ``insert_cartoon_hider`` (which shows its own rep;
    for ribbon, the same residue renders in both -- research sec Q10).

    Args:
        object (str): existing PyMOL object to insert INTO.
        rep (str): one of GAME_REPS ('spheres', 'lines', 'sticks',
            'cartoon', 'ribbon').
        payload: rep-specific -- ``pos`` (spheres), ``(offset,
            neighbor_id)`` (lines/sticks), or ``(chain, terminus_resi,
            is_c_terminus)`` (cartoon/ribbon).
        handle (str): throwaway atom *name* passed to the insert fn.

    Returns:
        int: the new hider atom's stable id.

    Raises:
        ValueError: if *rep* is not a recognized GAME_REP.
    """
    if rep == 'spheres':
        aid = insert_hider(object, pos=payload, rep=rep, handle=handle)
        # Dispatcher owns the sphere show (by id, NOT all GAME -- avoids
        # cross-contamination with stick/cartoon hiders)
        cmd.show("spheres", "%s and id %d" % (object, aid))  # viewing.py:491
        return aid
    elif rep in ('lines', 'sticks'):
        offset, neighbor_id = payload
        return insert_line_stick_hider(object, offset=offset,
                                       neighbor_id=neighbor_id,
                                       handle=handle, rep=rep)
    elif rep in ('cartoon', 'ribbon'):
        chain, terminus_resi, is_c_terminus = payload
        return insert_cartoon_hider(object, chain=chain,
                                    terminus_resi=terminus_resi,
                                    is_c_terminus=is_c_terminus,
                                    handle=handle)
    else:
        raise ValueError("unknown rep %r" % (rep,))


# ---- Target preparation (Phase 5 05-05 human-verify fixes) ----

def collapse_to_single_state(obj):
    """Collapse a multi-state object to a single state (state 1).

    Multi-state objects (e.g. NMR ensembles like 1znf with 37 models)
    break the backup/verify_intact mechanism: mutations (attach, remove,
    pseudoatom) only affect the current state, while backup.snapshot
    copies all states, causing atom-count mismatches in verify_intact.

    Replaces *obj* in-place with a single-state copy of its state 1.
    No-op if the object already has exactly 1 state.

    Args:
        obj (str): the PyMOL object to collapse.

    Returns:
        bool: True if the object was collapsed, False if it was already
            single-state (no-op).
    """
    if cmd.count_states(obj) <= 1:
        return False
    tmp = "_bchm_single"
    cmd.delete(tmp)                # idempotent — clear any stale temp
    cmd.create(tmp, obj, 1, 1)     # copy state 1 only (creating.py:960)
    cmd.delete(obj)                # remove the multi-state original
    cmd.create(obj, tmp)           # recreate as single-state
    cmd.delete(tmp)
    return True


def free_nterminal_valence(obj, chain, terminus_resi):
    """Free the N-terminal N valence for attach_amino_acid.

    editor.attach_amino_acid needs a free valence on the target N atom.
    Two things can saturate the N valence (3 bonds max):

    1. **Hydrogen atoms** on N (structures with H, or after cmd.h_add).
       The N-terminal N has bonds to CA + H (or CA + H + H for NH2),
       leaving 0-1 free valences.
    2. **N-terminal caps** (ACE/formyl groups). The cap's carbonyl C is
       bonded to N, using up a valence. E.g. 1znf has an ACE cap at
       resi 0 whose C is bonded to the TYR 1 N.

    This function removes:
    - All atoms in cap residues (residues of atoms bonded to N that are
      NOT in the terminal residue) — removes the entire ACE/formyl group.
    - H atoms bonded to N in the terminal residue — frees the H valence.

    After removal, N has 1 bond (CA only) = 2 free valences, and
    attach_amino_acid succeeds. The new residue's resi (terminus_resi - 1)
    will NOT collide with the cap's resi (the cap is gone).

    CRITICAL: must be called BEFORE backup.snapshot (inside
    GameController.start) so verify_intact matches (both backup and
    target have caps/H removed).

    Args:
        obj (str): the PyMOL object.
        chain (str): chain identifier of the N-terminal residue.
        terminus_resi (int): residue number of the N-terminal residue.
    """
    n_sele = "%s and chain %s and resi %d and name N" % (obj, chain, terminus_resi)
    # Step 1: identify cap residues (residues of atoms bonded to N that
    # are NOT in the terminal residue). Uses explicit outer parens around
    # neighbor (...) to avoid PyMOL selector precedence swallowing the
    # intersect into the neighbor argument (05-04 smoke pitfall).
    cap_resis = []
    cmd.iterate(
        "(neighbor (%s)) and not (%s and chain %s and resi %d)" %
        (n_sele, obj, chain, terminus_resi),
        "stored.append((chain, resv))",
        space={'stored': cap_resis})
    # Step 2: remove all atoms in cap residues (entire ACE/formyl group)
    for cap_chain, cap_resi in set(cap_resis):
        cmd.remove("%s and chain %s and resi %d" % (obj, cap_chain, cap_resi))
    # Step 3: remove H atoms bonded to N in the terminal residue
    cmd.remove(
        "(neighbor (%s)) and (%s and chain %s and resi %d and elem H)" %
        (n_sele, obj, chain, terminus_resi))
