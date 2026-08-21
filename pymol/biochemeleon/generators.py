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
  - pick_segments(cas_by_chain, count, segment_size)  -- Phase 11 (mid-chain)
  - generate_middle_displacement(n, seed, magnitude)  -- Phase 11 (rigid vec)
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


def _even_starts(n_res, count, segment_size):
    """Evenly-spaced DISJOINT window start indices (0-indexed into resis).

    Distributes ``count`` non-overlapping windows of ``segment_size``
    residues across ``n_res`` residues by splitting the slack
    (``n_res - count*segment_size``) into ``count + 1`` gaps (leading,
    between, trailing) as evenly as integer division allows (remainder
    spread to the leading gaps). The leading gap is >= 1 whenever there
    is any slack, so the first window avoids the pure N-terminus when
    the chain has room (mirrors the single-pick "mid-chain" intent).

    Precondition: ``count >= 2`` and ``count * segment_size <= n_res``
    (the caller caps via ``min(need, n_res // segment_size)``).

    Returns: list of ``count`` 0-indexed start positions into ``resis``.
    """
    footprint = count * segment_size
    slack = n_res - footprint
    n_gaps = count + 1
    base = slack // n_gaps
    rem = slack % n_gaps
    gaps = [base + (1 if k < rem else 0) for k in range(n_gaps)]
    starts = []
    pos = gaps[0]  # leading gap
    for k in range(count):
        starts.append(pos)
        pos += segment_size + gaps[k + 1]
    return starts


def pick_segments(cas_by_chain, count, segment_size=3):
    """Mid-chain segment picker. Returns [(chain, start_resi, end_resi), ...].

    DISJOINT segments (Bug 1 fix -- ranges non-overlapping so two alt-conf
    hiders never share a clickable middle CA id). Skips chains with fewer
    than ``segment_size`` residues. Longer chains first (determinism).
    Mid-chain (NOT terminal): the segment window is centered on the chain
    interior so endpoints are not the N/C terminus when the chain is longer
    than ``segment_size`` -- this is the whole point of Phase 11 replacing
    the Phase 5 terminal-extension cartoon hider.

    ``cas_by_chain`` is ``{chain: [(resi, ca_id), ...]}`` (the EXISTING
    shape ``_prepare_and_start`` builds). Returns a list of
    ``(chain, start_resi, end_resi)`` 3-tuples where start_resi/end_resi
    are ints (resi values, NOT ca_ids -- alt-conf construction copies by
    ``chain and resi N-M``). Deterministic (no RNG): centered window for a
    single pick, even spacing across the chain for multi-picks (quick-005).

    Args:
        cas_by_chain: ``{chain: [(resi, ca_id), ...]}``.
        count: number of disjoint segments requested (capped at what fits).
        segment_size: residues per segment (default 3 -- keep the two ends'
            positions, slightly move the middle; USER REQ 2).

    Returns:
        list of ``(chain, start_resi, end_resi)`` tuples (``[]`` for an
        empty dict or when no chain is long enough).
    """
    if not cas_by_chain:
        return []
    chains = sorted(cas_by_chain.keys(),
                    key=lambda c: len(cas_by_chain[c]), reverse=True)
    out = []
    for ch in chains:
        if len(out) >= count:
            break
        resis = [r[0] for r in cas_by_chain[ch]]
        n_res = len(resis)
        if n_res < segment_size:
            continue  # skip chains too short for a segment
        # All candidate windows (start_resi, end_resi), consecutive residues
        windows = [(resis[i], resis[i + segment_size - 1])
                   for i in range(n_res - segment_size + 1)]
        need = count - len(out)
        if need == 1:
            # Single segment: pick the CENTERED window (mid-chain, not
            # terminal). For a chain exactly segment_size long there is only
            # one window (the whole chain) -- centered index 0.
            mid = (len(windows) - 1) // 2
            out.append((ch, windows[mid][0], windows[mid][1]))
        else:
            # Multiple segments: EVEN SPACING across the chain (quick-005).
            # The old greedy advance (i += segment_size) clustered segments
            # back-to-back near the N-term (e.g. 76-res count=2 -> resi 2-4
            # and 5-7, gap 0). Even spacing splits the slack into count+1
            # gaps (leading/between/trailing) so hiders spread across the
            # whole chain. Cap at the max disjoint windows that fit; if only
            # one fits, fall through to the centered single-pick above.
            max_fit = n_res // segment_size
            actual = min(need, max_fit)
            if actual <= 1:
                # Only one fits: centered mid-chain window (same as need==1).
                mid = (len(windows) - 1) // 2
                out.append((ch, windows[mid][0], windows[mid][1]))
            else:
                for s in _even_starts(n_res, actual, segment_size):
                    out.append((ch, resis[s], resis[s + segment_size - 1]))
    return out[:count]


def generate_middle_displacement(n, seed=None, magnitude=1.5):
    """Pure RNG. Returns [[dx, dy, dz], ...] -- one random unit vector per
    hider times magnitude. Same offset for all middle atoms of one hider
    (rigid translation -- Pitfall 15: displace ALL middle atoms, NOT just CA).

    Each vector is a random direction on the unit sphere (3 standard-normal
    components, normalized) scaled by ``magnitude``. Normalizing avoids the
    directional bias of uniform-in-cube sampling. The caller applies the
    SAME vector to every middle backbone atom of one hider (rigid shift),
    leaving the two endpoint residues at their original coords so the
    alt-conf segment blends with the real trace at the ends and bulges in
    the middle (USER REQ 2: keep the two ends, slightly move the middle).

    Args:
        n: number of hiders (one vector per hider).
        seed: int for deterministic output (tests). ``None`` = entropy.
        magnitude: Angstroms to displace middle atoms (default 1.5;
            research: 1.5 A recommended, 2.0 A ceiling).

    Returns:
        list of ``[dx, dy, dz]`` lists (empty when ``n <= 0``).
    """
    rng = random.Random(seed)
    out = []
    for _ in range(n):
        dx = rng.gauss(0.0, 1.0)
        dy = rng.gauss(0.0, 1.0)
        dz = rng.gauss(0.0, 1.0)
        norm = (dx * dx + dy * dy + dz * dz) ** 0.5
        if norm < 1e-12:
            # Vanishingly rare (3 continuous gaussians all ~0); pick a
            # deterministic fallback so we never divide by zero.
            dx, dy, dz = 1.0, 0.0, 0.0
            norm = 1.0
        out.append([dx / norm * magnitude,
                    dy / norm * magnitude,
                    dz / norm * magnitude])
    return out
