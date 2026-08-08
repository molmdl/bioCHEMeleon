"""Pure hider generators - geometry + selection (stdlib random only, WSL-testable).

NO ``pymol`` import, NO ``pymol.Qt`` import, NO ``numpy``. The
cmd-coupled caller (``__init__.py``) feeds data (bounding box,
neighbor pool, C-alpha list) IN and gets pure geometry/selection
decisions OUT; the cmd-coupled insertion (``cmd.pseudoatom``,
``cmd.bond``, ``cmd.attach_amino_acid``) lives in ``mutation.py``
(plan 05-02).

This module mirrors the purity convention of ``registry.py`` and
``setup_state.py`` (AGENTS.md: pure layer <- cmd-coupled layer; never
reversed) so it is WSL-unit-testable.

Functions:
  - generate_sphere_positions(extent, n, seed)  -- Phase 4 (bounding-box RNG)
  - generate_line_stick_offsets(n, seed)        -- Phase 5 (small [-1,1] offsets)
  - pick_terminal_residues(cas_by_chain, max_chains)  -- Phase 5 (C-term pick)
"""

import random


def generate_sphere_positions(extent, n, seed=None):
    """Generate ``n`` random ``[x,y,z]`` positions within the bounding box.

    extent: ``[[xmin,ymin,zmin],[xmax,ymax,zmax]]`` from ``cmd.get_extent``.
    n: number of positions. seed: int for deterministic output (tests).
    Returns: list of ``[x,y,z]`` lists (empty list when ``n <= 0``).
    """
    rng = random.Random(seed)
    (xmin, ymin, zmin) = extent[0]
    (xmax, ymax, zmax) = extent[1]
    positions = []
    for _ in range(n):
        positions.append([
            rng.uniform(xmin, xmax),
            rng.uniform(ymin, ymax),
            rng.uniform(zmin, zmax),
        ])
    return positions


def generate_line_stick_offsets(n, seed=None):
    """Generate ``n`` small ``[dx, dy, dz]`` offset vectors for line/stick hiders.

    Each component is drawn uniform-random in ``[-1.0, 1.0]`` Angstrom so
    the hider sits near a real neighbor (short bond, blends with real
    bonds - 05-RESEARCH.md Sec2 Q3: "0.5-1.0 A so the bond is visible but
    short"). The caller adds the offset to a neighbor's coords (read via
    ``cmd.iterate_state``) and bonds the hider to that neighbor.

    Args:
        n: number of offset vectors.
        seed: int for deterministic output (tests). ``None`` = entropy.

    Returns:
        list of ``[dx, dy, dz]`` lists (empty when ``n <= 0``).
    """
    rng = random.Random(seed)
    return [[rng.uniform(-1.0, 1.0) for _ in range(3)] for _ in range(n)]


def pick_terminal_residues(cas_by_chain, max_chains=None):
    """Pick terminal residues for cartoon hiders (extend-at-terminal, MVP).

    ``cas_by_chain`` is ``{chain: [(resi, ca_id), ...]}`` from the
    caller's ``cmd.iterate`` over polymer C-alpha atoms
    (05-RESEARCH.md Sec3 Q8 Step 1). Returns a list of
    ``(chain, terminal_resi, is_c_terminus)`` tuples, one per chain,
    longest chain first (most C-alpha entries), each at the N-terminus
    (min resi, ``is_c_terminus=False``). Capped at ``max_chains`` if not
    ``None``. Returns ``[]`` for an empty dict.

    MVP caps cartoon hiders at one per chain (attaching many to one
    terminus chains them - 05-RESEARCH.md Sec7 Open Risk 5). MVP uses the
    N-terminus (NOT the C-terminus): the C-terminus carbonyl C carries an
    OXT (terminal oxygen) in most structures (e.g. 1ubq), which saturates
    the C valence and makes the residue-attach primitive fail with "no
    target attachment vector found" (ObjectMolecule.cpp:3357). The N-terminus
    N has a free valence for attachment, so it extends cleanly with NO atom
    removal -- the happy-path sentinel cleanup (``segi GAME``) restores the
    structure exactly and ``verify_intact`` passes (verified in the Phase 5
    headless smoke). C-terminus extension is supported by
    ``insert_cartoon_hider`` (``is_c_terminus=True``) but not exercised by
    the MVP generator.

    Args:
        cas_by_chain: ``{chain: [(resi, ca_id), ...]}``.
        max_chains: int or ``None``; if set, return at most this many
            chains (longest first).

    Returns:
        list of ``(chain, terminal_resi, is_c_terminus)`` tuples
        (``is_c_terminus`` is always ``False`` in the MVP -- N-terminus).
    """
    if not cas_by_chain:
        return []
    chains = sorted(cas_by_chain.keys(),
                    key=lambda c: len(cas_by_chain[c]), reverse=True)
    if max_chains is not None:
        chains = chains[:max_chains]
    out = []
    for ch in chains:
        resis = [r[0] for r in cas_by_chain[ch]]
        out.append((ch, min(resis), False))  # N-terminus (min resi)
    return out
