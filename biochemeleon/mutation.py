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
    if not nbr:
        raise ValueError(
            "neighbor_id %d not found in state 1 of %s — the atom may have been "
            "removed after the id was captured (ensure neighbor_ids are sampled "
            "from 'name CA' atoms that survive free_nterminal_valence; 05-07 fix)"
            % (neighbor_id, object))
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
    """Attach TWO residues at a terminus (cartoon/ribbon hider) and return
    the clickable residue's C-alpha stable id.

    Cartoon and ribbon are POLYMER-TRACE representations -- a lone
    pseudoatom is invisible (Pitfall 8; research sec Q5). PyMOL's cartoon
    renderer draws a tube/arrow segment BETWEEN consecutive C-alpha atoms,
    so a SINGLE isolated residue at a polymer terminus produces NO visible
    geometry (verified headless 05-05: ss S/L/H all render identical to a
    blank control -- the tube has no "next" C-alpha to draw toward).

    **2-residue approach (05-05 fix, replacing the sphere fallback):** This
    function attaches TWO glycine residues at the terminus. The cartoon tube
    then renders BETWEEN the two new C-alphas (and between the first new
    C-alpha and the original terminal C-alpha), producing a short tube/loop
    extension that BLENDs with the existing cartoon (same color + ss copied
    from the neighbor) -- NOT a glaring sphere. The first new residue
    (closest to the original chain) is the CLICKABLE hider (its C-alpha id
    is registered + returned); the second new residue (the new terminus) is
    "support geometry" that gives the cartoon a segment to draw -- it is
    NOT a separate hider.

    **Clean sentinel design (so the registry has ONE entry per cartoon
    hider, even after a ``.pse`` reload):** ``segi='GAME'`` is set on ALL
    atoms of BOTH residues (cleanup_hiders removes all of them via
    ``segi GAME``), but ``b=-999`` (the fetch sentinel) is set on the
    CLICKABLE C-alpha ONLY. ``fetch_all_hider_ids`` selects
    ``segi GAME and b < 0`` (AGENTS.md), so it returns exactly ONE atom per
    cartoon hider (the clickable CA) -- not the whole residue -- and
    ``reconstruct_from_sentinels`` creates ONE registry entry per cartoon
    hider. All other GAME atoms carry ``b=0`` (not a fetch sentinel) but
    are still removed on cleanup (``segi GAME``). This is more consistent
    than the old 1-residue design, which set ``b=-999`` on the whole residue
    (so fetch returned ~7 atoms -> ~7 registry entries on reload).

    **id-diff selection (NOT resi):** the second N-terminal residue gets
    ``resi = terminus_resi - 2``, which is often NEGATIVE (e.g. -1 for 1ubq).
    The PyMOL ``resi`` SELECTOR parses a leading hyphen as a RANGE
    operator (``resi -1`` matches residues 0..1, not residue -1; verified
    headless 05-05), so newly-attached residues are NEVER selected by
    ``resi`` here. Instead, the atom-id set is diffed before/after each
    ``attach_amino_acid`` call (ids are STABLE across add/remove/sort --
    AGENTS.md Pitfall 4), and the new atoms are selected by ``id a+b+c``.
    This is robust for any resi (negative, zero, or positive).

    **2nd-attach valence:** after the first attach, the new residue's
    terminal atom (N for N-term, C for C-term) carries hydrogens (hydro=1)
    that saturate its valence, so the second attach would fail. Before the
    second attach, the first new residue's terminal valence is freed: N-term
    removes H atoms bonded to the new N (mirrors ``free_nterminal_valence``
    step 3 but for the newly-attached residue); C-term removes the OXT
    terminal oxygen on the new C. The removed H/OXT atoms are part of the
    GAME residue (removed on cleanup), so verify_intact still passes.

    Coloring (research sec Q15 option c): the neighbor C-alpha's color is
    copied onto BOTH new residues via alter so the cartoon tube segment
    blends (research sec Q16: cartoon color follows the C-alpha by default).
    No sphere fallback -- the tube itself is the visible, blending hider.

    **Secondary structure = 'L' (loop), NOT the neighbor's ss (05-05 fix):**
    The display ss is set to loop ('L') on BOTH new residues, NOT copied from
    the neighbor. A 2-residue segment with the neighbor's ss (e.g. 'S' sheet
    on a beta-strand terminus like 1ubq) renders as a small flat sheet ARROW
    that looks visually "disconnected" from the main chain tube (05-05
    human-verify: "disconnected arrow cartoon"). Verified headless: the
    cartoon trace IS continuous across the segi=GAME boundary (no literal
    gap; CA-CA ~3.8A normal; pixel counts identical across ss=S/L), so the
    "disconnected" look is the ARROW SHAPE, not a rendering gap. A loop ('L')
    renders as a smooth round TUBE that visually connects as a continuous
    extension. This also aligns the display ss with the geometry ss (the
    ``ss=4`` parameter = flat/loop dihedrals, already loop-like).

    The residue-attach primitive lives in the ``pymol.editor`` module
    (``editor.attach_amino_acid``) and is NOT exposed as
    ``cmd.attach_amino_acid`` in PyMOL 2.5.0 open-source (``cmd.py`` imports
    ``editor`` lazily inside a function, so ``cmd.editor`` is not a stable
    attribute). It is imported lazily inside this function (``from pymol
    import editor``) so the module-level import stays minimal and WSL unit
    tests (which stub ``pymol`` as ``MagicMock``) never trigger this path.
    It is called with a NAMED selection (NOT ``pk1`` -- research Open Risk 2:
    the general path accepts any sele; the Phase 5 smoke confirms).
    ``ss=4`` (flat/loop) controls the DIHEDRAL angles during attach (the
    geometry). The DISPLAY ss is set to 'L' (loop) in step 8 -- see the
    "Secondary structure = 'L'" note above (05-05 fix). ``aa='gly'`` (glycine
    -- smallest side chain; research sec Q6).

    MVP uses the N-terminus (``is_c_terminus=False`` -> attach at ``name N``,
    first new resi = ``terminus_resi - 1``, second = ``terminus_resi - 2``);
    the C-terminus path (``is_c_terminus=True``) is supported but NOT
    exercised by the generators because the C-terminus carbonyl C carries an
    OXT (terminal oxygen) in most structures (e.g. 1ubq), which saturates
    the C valence and makes the FIRST residue-attach fail with "no target
    attachment vector found" (ObjectMolecule.cpp:3357). The N-terminus N has
    a free valence (after ``free_nterminal_valence``) and extends cleanly,
    so the happy-path sentinel cleanup (``segi GAME``) restores the
    structure exactly and ``verify_intact`` passes (verified Phase 5 smoke).

    **Known MVP limitation:** only the clickable C-alpha is registered, so
    clicking any OTHER atom of either GAME residue (the support residue's
    atoms, or the clickable residue's N/C/O/H) registers as a "Miss!" in
    ``on_pick``. The player is guided to click the cartoon tube; the
    representative atom is the clickable residue's C-alpha. A future phase
    could register all GAME atoms of the hider or resolve by residue.

    Args:
        object (str): existing PyMOL object to attach INTO.
        chain (str): chain identifier of the terminal residue.
        terminus_resi (int): residue number of the terminal residue.
        is_c_terminus (bool): True for C-terminus extension (forward); False
            for N-terminus (backward, the MVP path).
        handle (str): throwaway atom *name* (unused here -- new atoms are
            selected by id-diff, not name -- but kept for signature symmetry
            with insert_hider).
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
        b (float): sentinel b-factor set on the clickable C-alpha only
            (default -999.0). Other GAME atoms get b=0.

    Returns:
        int: the clickable residue's C-alpha stable id (the first new
        residue's CA -- closest to the original chain; this is the atom the
        player clicks and the registry registers).

    Raises:
        AssertionError: if the id-diff does not yield exactly one clickable
        C-alpha (the attach or alter did not produce the expected atoms).
    """
    residue_sele = "%s and chain %s and resi %d" % (object, chain, terminus_resi)
    # 1. Read neighbor (terminal residue) C-alpha color for blending
    #    (research sec Q13: iterate exposes color lowercase). ss is NOT
    #    copied -- the display ss is hardcoded to 'L' (loop) in step 8 so the
    #    2-residue extension renders as a smooth tube (not a sheet arrow);
    #    see the "Secondary structure = 'L'" docstring note (05-05 fix).
    nbr = []
    cmd.iterate("%s and name CA" % residue_sele,
                "stored.append(color)",
                space={'stored': nbr})  # editing.py:1490; hygienic space= dict (RESEARCH sec Q3)
    n_color = nbr[0]
    # 2. Build the attach selection (single N or C atom -- editor.py:125)
    term_atom_name = "C" if is_c_terminus else "N"
    attach_sele = "%s and name %s" % (residue_sele, term_atom_name)
    # 3. attach_amino_acid lives in the pymol.editor module (editor.py:85) and
    #    is NOT exposed as cmd.attach_amino_acid in PyMOL 2.5.0 open-source
    #    (cmd.py imports editor lazily inside a function, so cmd.editor is not
    #    a stable attribute). Imported lazily here so the module-level import
    #    stays minimal and WSL unit tests (which stub pymol as MagicMock) never
    #    trigger this path.
    from pymol import editor  # editor.py:85; not exposed as cmd.attach_amino_acid

    def _id_sele(ids):
        # Build a PyMOL `id a+b+c` selection from an iterable of stable atom
        # ids (AGENTS.md Pitfall 4: id is stable across add/remove/sort).
        return "id " + "+".join(str(i) for i in ids)

    # 4. Attach FIRST glycine (CLICKABLE -- bonds to the original terminus).
    #    id-diff (NOT resi) finds the new atoms: the 2nd N-term residue gets
    #    a NEGATIVE resi (terminus_resi-2), and `resi -N` parses as a RANGE
    #    in the PyMOL selector (verified 05-05), so resi is NEVER used to
    #    select newly-attached residues here.
    ids_before_1 = set(cmd.identify(object, mode=0))  # querying.py:1269
    editor.attach_amino_acid(attach_sele, aa, ss=ss, hydro=hydro)
    first_new_ids = set(cmd.identify(object, mode=0)) - ids_before_1
    assert first_new_ids, "1st attach produced no new atoms"
    # 5. Find the first new residue's terminal atom (N or C) by id -- the
    #    second attach bonds to it.
    first_term_ids = []
    cmd.iterate(_id_sele(first_new_ids) + " and name %s" % term_atom_name,
                "stored.append(ID)", space={'stored': first_term_ids})
    assert len(first_term_ids) == 1, \
        "expected 1 terminal %s in 1st residue, got %r" % (term_atom_name,
                                                           first_term_ids)
    first_term_sele = "%s and id %d" % (object, first_term_ids[0])
    # 6. Free the first new residue's terminal valence so the 2nd attach can
    #    bond to it (N-term: remove H bonded to N -- mirrors
    #    free_nterminal_valence step 3 for the new terminus; C-term: remove
    #    OXT on C). The removed atoms are part of the GAME residue (removed
    #    on cleanup), so verify_intact still passes.
    if is_c_terminus:
        cmd.remove("%s and name OXT" % first_term_sele)  # C-term OXT
    else:
        cmd.remove("(neighbor (%s)) and (elem H)" % first_term_sele)  # N-term H
    # 7. Recompute first_new_ids (the H/OXT removal may have dropped atoms)
    #    and attach the SECOND glycine (SUPPORT -- the new terminus). The
    #    cartoon tube renders BETWEEN the two new C-alphas.
    ids_before_2 = set(cmd.identify(object, mode=0))
    first_new_ids = ids_before_2 - ids_before_1  # 1st residue (post-removal)
    editor.attach_amino_acid(first_term_sele, aa, ss=ss, hydro=hydro)
    second_new_ids = set(cmd.identify(object, mode=0)) - ids_before_2
    assert second_new_ids, "2nd attach produced no new atoms"
    all_game_ids = first_new_ids | second_new_ids
    # 8. Sentinel + blend on ALL game atoms: segi='GAME' (cleanup tag),
    #    color (blend), b=0.0 (default; NOT a fetch sentinel), ss='L' (loop
    #    display -- NOT the neighbor's ss; a 2-residue sheet segment renders
    #    as a flat arrow that looks disconnected; a loop renders as a smooth
    #    tube that connects to the main chain; 05-05 fix). Single hygienic
    #    alter (research sec Q14).
    cmd.alter(_id_sele(all_game_ids),
              "segi='GAME'; b=0.0; color=stored_c; ss='L'",
              space={'stored_c': n_color})  # editing.py:1424
    # 9. Set the b=-999 fetch sentinel on the CLICKABLE C-alpha ONLY (the
    #    first new residue's CA -- closest to the original chain; the atom
    #    the player clicks). fetch_all_hider_ids (segi GAME and b < 0) then
    #    returns exactly ONE atom per cartoon hider -> ONE registry entry.
    ca_ids = []
    cmd.iterate(_id_sele(first_new_ids) + " and name CA",
                "stored.append(ID)", space={'stored': ca_ids})
    assert len(ca_ids) == 1, "expected 1 clickable C-alpha, got %r" % (ca_ids,)
    clickable_id = ca_ids[0]
    cmd.alter("%s and id %d" % (object, clickable_id), "b=-999.0", space={})
    cmd.sort(object)  # defensive -- editing.py:1457; research sec Q23
    # 10. Show cartoon on BOTH residues (the tube renders BETWEEN consecutive
    #     C-alphas; the 2nd residue provides the "next" C-alpha so the
    #     segment is visible). NO sphere fallback -- the tube itself blends
    #     (neighbor color + ss copied in step 8). Same atoms render in ribbon
    #     too (research sec Q10).
    cmd.show('cartoon', _id_sele(all_game_ids))  # viewing.py:491
    return clickable_id


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
