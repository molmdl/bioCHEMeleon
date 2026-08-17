"""biochemeleon setup state model - pure data + pure functions.

This module is the single source of truth for the setup-configuration
data schema, the game's representation set, the demo manifest, and the
pure validation/randomization logic. It has NO Qt and NO pymol.cmd
dependencies so it can be unit-tested in WSL without PyMOL installed.

Other Phase-2 modules import FROM this module:
  - demos.py imports GAME_REPS, DEMO_MANIFEST (for load_demo, get_active_reps)
  - gui_setup.py imports DEFAULTS, SETUP_FORMAT, hider_count_cap,
    randomize_state, validate_state, GAME_REPS, DEMO_MANIFEST
"""

import random as _random
import copy as _copy


# ---- Constants ----

#: The 5 in-scope PyMOL representations for the game.
#: 'surface' is explicitly OUT OF SCOPE (PROJECT.md).
#: Source: research section 3.6 - verified from outline.py REP_LIST + PyMOL wiki.
GAME_REPS = ['lines', 'sticks', 'spheres', 'cartoon', 'ribbon']

#: Manifest of the 9 demo PDBs: 6 bundled (offline) + 3 fetched (network).
#: Each entry carries the Phase 9 fetch-source schema:
#:   {category, type, difficulty, source, source_id, fetch_url,
#:    cache_name, citation, strip}
#: 'source' drives the loader branch ('bundled' -> data/demos/, fetched
#: -> tmp/phase9-demos/cache/); 'cache_name' is the on-disk filename.
#: Citations live in repo-root DATA_SOURCES.md (DEMO-04, Phase 9).
#: Tier-ordered (easy -> hard -> challenge -> very_challenging) so the
#: demo combo shows a natural difficulty progression (DIFF-05).
DEMO_MANIFEST = {
    # ---- easy ----
    '1znf':  {'category': 'Protein',       'type': 'protein',    'difficulty': 'easy',  'source': 'bundled',  'source_id': '1ZNF', 'fetch_url': None, 'cache_name': '1znf.pdb', 'citation': '1ZNF', 'strip': False},
    '5e54':  {'category': 'Nucleic acid',  'type': 'rna',        'difficulty': 'easy',  'source': 'bundled',  'source_id': '5E54', 'fetch_url': None, 'cache_name': '5e54.pdb', 'citation': '5E54', 'strip': False},
    '1k8p':  {'category': 'Nucleic acid',  'type': 'dna',        'difficulty': 'easy',  'source': 'bundled',  'source_id': '1K8P', 'fetch_url': None, 'cache_name': '1k8p.pdb', 'citation': '1K8P', 'strip': False},
    # ---- hard ----
    '1xdn':  {'category': 'Protein',       'type': 'protein',    'difficulty': 'hard',  'source': 'bundled',  'source_id': '1XDN', 'fetch_url': None, 'cache_name': '1xdn.pdb', 'citation': '1XDN', 'strip': False},
    '2qbz':  {'category': 'Nucleic acid',  'type': 'rna',        'difficulty': 'hard',  'source': 'bundled',  'source_id': '2QBZ', 'fetch_url': None, 'cache_name': '2qbz.pdb', 'citation': '2QBZ', 'strip': False},
    '4wb3':  {'category': 'Mixed',         'type': 'protein/na', 'difficulty': 'hard',  'source': 'bundled',  'source_id': '4WB3', 'fetch_url': None, 'cache_name': '4wb3.pdb', 'citation': '4WB3', 'strip': False},
    # ---- challenge (fetched: SASBDB glycoprotein; strip=False so glycan HETATM survives) ----
    'sasdpg4': {'category': 'Glycoprotein',    'type': 'protein',  'difficulty': 'challenge',
                'source': 'sasbdb',   'source_id': 'SASDPG4',
                'fetch_url': 'https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb',
                'cache_name': 'SASDPG4_fit2_model1.pdb.gz', 'citation': 'SASDPG4', 'strip': False},
    # ---- very_challenging (fetched: MemProtMD membrane proteins; strip=True for SOL/NA/CL) ----
    '1gzm':  {'category': 'Membrane protein', 'type': 'protein',  'difficulty': 'very_challenging',
              'source': 'memprotmd', 'source_id': '1GZM',
              'fetch_url': 'https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/1gzm_default_dppc/files/structures/at.pdb',
              'cache_name': '1gzm.pdb.gz', 'citation': '1GZM', 'strip': True},
    '3gp6':  {'category': 'Membrane protein', 'type': 'protein',  'difficulty': 'very_challenging',
              'source': 'memprotmd', 'source_id': '3GP6',
              'fetch_url': 'https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/3gp6_default_dppc/files/structures/at.pdb',
              'cache_name': '3gp6.pdb.gz', 'citation': '3GP6', 'strip': True},
}

#: Phase 9 DIFF-05 display map: identifier-safe tier value -> the
#: human-readable label the success criterion literally specifies
#: ("Easy / Hard / Challenge / Very challenging"). The manifest stores
#: the identifier-safe keys (no spaces: easy/hard/challenge/
#: very_challenging); the GUI demo_combo maps each entry's difficulty
#: through this table to render the tier in the dropdown.
TIER_LABELS = {
    'easy': 'Easy',
    'hard': 'Hard',
    'challenge': 'Challenge',
    'very_challenging': 'Very challenging',
}

#: Curated pool of 34 mixed PDB codes for Randomize fetch mode (Gap 4).
#: Every entry was VERIFIED against RCSB on 2026-08-05 (each returned a
#: valid PDB with HEADER + ATOM records, all <6000 atoms). Mixed categories:
#: 6 bundled demos + 14 proteins + 3 DNA + 4 RNA + 6 hybrid (protein-NA and
#: DNA-oligosaccharide drug). Do NOT add unverified entries.
#: See .planning/phases/02-.../02-05-PLAN.md for the verification log.
PDB_POOL = [
    # Bundled demos (verified in Plan 02-02, already downloaded):
    '1znf', '1xdn', '5e54', '1k8p', '2qbz', '4wb3',
    # Proteins (verified, <6000 atoms, from RCSB titles):
    '1ubq',  # ubiquitin (660 atoms)
    '1crn',  # crambin (327 atoms)
    '6pti',  # BPTI (536 atoms)
    '1pgb',  # protein G B1 (460 atoms)
    '1fyn',  # Fyn SH3 domain (592 atoms)
    '1shg',  # SH3 domain (472 atoms)
    '1pht',  # PI3K p85 SH3 domain (988 atoms)
    '1bba',  # designed mini-protein (582 atoms)
    '1vii',  # villin headpiece (596 atoms)
    '1p9g',  # antifungal protein (657 atoms)
    '1mkg',  # VEGF mutant (3170 atoms)
    '1gtb',  # schistosome drug target (1889 atoms)
    '1cqw',  # haloalkane dehalogenase + NAI (2754 atoms)
    '1ciy',  # insecticidal toxin (4693 atoms)
    # DNA (verified):
    '1bna',  # B-DNA dodecamer (566 atoms)
    '1d98',  # oligo(dA).oligo(dT) (513 atoms)
    '1ana',  # A-DNA tetramer (246 atoms)
    # RNA (verified):
    '1ehz',  # yeast phenylalanine tRNA (1821 atoms)
    '4tra',  # yeast aspartyl tRNA (1779 atoms)
    '1u8d',  # guanine riboswitch + hypoxanthine (1867 atoms)
    '2gcs',  # pre-cleavage ribozyme (3284 atoms)
    # Hybrid (protein-NA, or NA + oligosaccharide drug — verified from titles):
    '1a34',  # satellite tobacco mosaic virus + RNA (3474 atoms)
    '1dfu',  # E. coli L25 + 5S rRNA (1819 atoms)
    '1dgc',  # GCN4-bZIP + ATF/CREB DNA (842 atoms)
    '1aay',  # Zif268 zinc finger + DNA (1330 atoms)
    '1fjl',  # Drosophila paired homeodomain + DNA (2739 atoms)
    '1ekh',  # DNA d(TTGGCCAA)2 + chromomycin A3 oligosaccharide drug + Co(II) (5010 atoms)
]

#: JSON schema version tag for setup files.
SETUP_FORMAT = "biochemeleon-setup-v1"

#: Default setup state (used by Reset button BTN-01 and initial form state).
DEFAULTS = {
    "format": SETUP_FORMAT,
    "target_mode": "loaded",      # "loaded" | "fetch" | "demo"
    "selected_object": "",        # name of loaded object (mode='loaded')
    "pdb_code": "",               # PDB code string (mode='fetch')
    "demo_id": "1znf",            # manifest id (mode='demo')
    "hider_count": 10,
    "lock_scene": False,
    "per_rep": {},                # {rep: count} - empty/missing = random
    "difficulty_easy": True,      # True=easy (show per-rep), False=hard
    "lock_source": False,         # NEW: when True, Randomize preserves target (Gap 3)
    "pdb_pool": PDB_POOL,         # NEW: pool for Randomize fetch mode (Gap 4)
}

#: Valid target modes for validation.
_VALID_MODES = {"loaded", "fetch", "demo"}


# ---- PDB code/pool helpers (pure) ----

def _validate_pdb_code(code):
    """Validate a PDB ID: exactly 4 lowercase alphanumeric chars.

    Returns the normalized code or '' if invalid. PDB IDs are 4 chars
    (e.g. '1ubq'); we don't verify against RCSB — the UI's Add/Edit
    dialogs call this and show a QMessageBox on '' (Issue 2 fix).

    Previously accepted 3-5 chars for legacy/extended IDs, but that let
    5-char entries like '12345' pass the code validator only to be
    silently dropped by _validate_pdb_pool. Tightened to exactly 4 so
    invalid IDs never enter the pool editor (no silent loss).
    """
    if not code:
        return ""
    c = str(code).strip().lower()
    if len(c) == 4 and c.isalnum():
        return c
    return ""


def _validate_pdb_pool(pool):
    """Validate a PDB pool: lowercase, 4-char alnum, dedupe, bound to 100.

    Returns a list. Non-list/empty -> PDB_POOL default (Gap 4: never
    produce an empty pool — the randomize fetch re-roll relies on a
    non-empty pool here, and an empty user input signals "use defaults").
    """
    if not isinstance(pool, list):
        return list(PDB_POOL)
    seen = []
    seen_set = set()
    for code in pool:
        c = _validate_pdb_code(code)
        # PDB_POOL convention is 4-char; accept 3-5 in _validate_pdb_code
        # for general code validation, but enforce 4-char here to match
        # the curated PDB_POOL shape (test_pdb_pool_filters_invalid).
        if c and len(c) == 4 and c not in seen_set:
            seen.append(c)
            seen_set.add(c)
            if len(seen) >= 100:
                break
    if not seen:
        return list(PDB_POOL)
    return seen


# ---- Phase 9: PDB residue-name strip helper (pure) ----

#: Verified MemProtMD strip set: GROMACS solvent (SOL = water) plus the
#: NA sodium and CL chloride counter-ions that neutralize the
#: simulation box. Empirically verified by wet-vs-dry diff + atom-count
#: math (3gp6: 76,018 stripped = 75,789 SOL + 116 NA + 113 CL; 1gzm
#: carries the same three residue names). MemProtMD records these as
#: ATOM (0 HETATM), so the strip is a pure residue-name line-filter
#: rather than a solvent/inorganic selector (09-RESEARCH-memprotmd).
STRIP_RESN_MEMPROTMD = {'SOL', 'NA', 'CL'}


def strip_resn_from_pdb(text, strip_set):
    """Remove ATOM lines whose residue name is in *strip_set* (pure).

    Iterates the PDB *text* line by line. For lines beginning with the
    ATOM record, the residue name is read from PDB columns 18-20
    (0-indexed ``line[17:20]``) and ``.strip()``-ed so 2-char ion names
    are matched padding-agnostically ('NA ', ' NA', 'NA' all strip).
    Lines whose residue name is in *strip_set* are dropped; every other
    line (all non-ATOM records: TITLE, CRYST1, MODEL, TER, ENDMDL, END,
    REMARK, HETATM, ...) is preserved unconditionally.

    Empty/None *text* returns ''. The wet file is stripped in a single
    Python pass before it ever reaches the molecular viewer, so the
    ~95k-atom wet PDB never needs to be loaded into it. This is the
    deterministic pure-Python strip used by the Phase 9 MemProtMD fetch
    worker; it avoids relying on selector classification of solvent or
    inorganic ions and preserves DPPC lipids / protein residues by
    construction (filtering by residue name can never drop a DPP lipid
    or a protein residue).

    Returns the kept lines joined by newlines with a trailing newline
    (or '' for empty input).
    """
    if not text:
        return ""
    kept = []
    for line in text.splitlines():
        if line.startswith("ATOM"):
            resn = line[17:20].strip()
            if resn in strip_set:
                continue
        kept.append(line)
    return "\n".join(kept) + "\n"


# ---- Pure functions ----

def hider_count_cap(atom_count):
    """Sane max hider count for an object with *atom_count* atoms.

    Heuristic: 1 hider per ~50 atoms, capped to [1, 50].
    Small demos (1znf ~212 atoms -> cap 4) stay findable; large
    objects (4WB3 ~3779 -> cap 50) don't overwhelm the spinbox.

    Source: research section 3.7.
    """
    if atom_count is None or atom_count <= 0:
        return 1
    return max(1, min(50, atom_count // 50))


def randomize_state(seed=None, atom_count=None, lock_source=False,
                    locked_state=None, pdb_pool=None):
    """Return a random valid setup state dict.

    If *seed* is given, the result is deterministic (same seed -> same
    dict). If *atom_count* is given, hider_count is capped to
    hider_count_cap(atom_count); otherwise capped at 50.

    If *lock_source* is True and *locked_state* is a dict, the target
    (target_mode + selected_object/pdb_code/demo_id) is preserved from
    *locked_state* and only the hider composition is randomized (Gap 3).
    If *lock_source* is True but *locked_state* is None, behavior falls
    back to lock_source=False (defensive — the UI always passes a dict
    when the checkbox is checked).

    *pdb_pool* (Gap 4): when the chosen mode is "fetch", a random code is
    drawn from the pool. If *pdb_pool* is None, DEFAULTS["pdb_pool"] is
    used. If *pdb_pool* is an empty list, "fetch" mode is re-rolled to
    "demo" (never produce an empty pdb_code box).

    Phase 9: a non-lock "demo" target is drawn ONLY from bundled demos
    (source == 'bundled') so a random target always works offline --
    fetched demos need the network (Open Risk 3 rec (a)). The lock_source
    path still preserves a user-locked fetched demo_id (explicit user
    choice overrides the exclusion).

    The returned dict is a complete state (all DEFAULTS keys) suitable
    for passing to SetupTab.apply_state().

    Source: research section 7.5 (adapted to a pure function - the SetupTab
    method calls this and then applies the result).
    """
    rng = _random.Random(seed)
    cap = hider_count_cap(atom_count) if atom_count else 50
    hider_count = rng.randint(1, max(1, cap))
    # Pick a random non-empty subset of reps with counts summing to <= hider_count
    reps = rng.sample(GAME_REPS, rng.randint(0, len(GAME_REPS)))
    per_rep = {}
    remaining = hider_count
    for rep in reps:
        if remaining <= 0:
            break
        c = rng.randint(0, remaining)
        if c:
            per_rep[rep] = c
            remaining -= c

    # Resolve the fetch pool (raw param, or DEFAULTS if None).
    # Empty pool -> fetch re-rolls to demo (Gap 4).
    pool_for_fetch = pdb_pool if pdb_pool is not None else DEFAULTS["pdb_pool"]

    if lock_source and isinstance(locked_state, dict):
        # Preserve target; only randomize hider composition (Gap 3).
        mode = locked_state.get("target_mode", "loaded")
        if mode not in _VALID_MODES:
            mode = "loaded"
        selected_object = str(locked_state.get("selected_object", ""))
        pdb_code = str(locked_state.get("pdb_code", "")).strip().lower()
        did = locked_state.get("demo_id", "1znf")
        demo_id = did if did in DEMO_MANIFEST else "1znf"
    else:
        # Pick a random mode (weighted toward demo).
        mode = rng.choice(["loaded", "fetch", "demo", "demo"])
        if mode == "fetch" and not pool_for_fetch:
            mode = "demo"  # re-roll: empty pool -> never fetch (Gap 4)
        selected_object = ""
        if mode == "fetch":
            pdb_code = rng.choice(pool_for_fetch)
        else:
            pdb_code = ""
        # Phase 9: a non-lock "demo" target is drawn ONLY from bundled
        # demos (source == 'bundled') so a random target always works
        # offline -- fetched demos need the network (Open Risk 3 rec
        # (a)). lock_source above still preserves a user-locked fetched
        # demo_id (explicit user choice overrides the exclusion).
        bundled_ids = [did for did, m in DEMO_MANIFEST.items()
                       if m.get('source', 'bundled') == 'bundled']
        demo_id = rng.choice(bundled_ids)

    return {
        "format": SETUP_FORMAT,
        "target_mode": mode,
        "selected_object": selected_object,
        "pdb_code": pdb_code,
        "demo_id": demo_id,
        "hider_count": hider_count,
        "lock_scene": rng.choice([True, False]),
        "per_rep": per_rep,
        "difficulty_easy": rng.choice([True, False]),
        "lock_source": bool(lock_source),
        "pdb_pool": _validate_pdb_pool(pdb_pool),
    }


def validate_state(state, atom_count=None):
    """Validate and clamp a setup state dict.

    Returns a NEW dict (does not mutate *state*). Fills missing keys
    from DEFAULTS, clamps hider_count to [1, cap], falls back invalid
    enum values to their defaults, drops invalid per_rep keys, and
    clamps the per_rep sum to <= hider_count (Gap 2 pure).

    *atom_count* (optional) controls the hider_count cap: if given,
    cap = hider_count_cap(atom_count); else cap = 50. The per_rep-sum
    clamp runs AFTER the hider_count clamp so it uses the final value.

    Source: research section 7.1 (schema) + 7.3 (apply_state tolerances).
    """
    result = _copy.deepcopy(DEFAULTS)
    if not isinstance(state, dict):
        return result

    # target_mode
    mode = state.get("target_mode", "loaded")
    result["target_mode"] = mode if mode in _VALID_MODES else "loaded"

    # selected_object / pdb_code
    result["selected_object"] = str(state.get("selected_object", ""))
    result["pdb_code"] = str(state.get("pdb_code", "")).strip().lower()

    # demo_id
    did = state.get("demo_id", "1znf")
    result["demo_id"] = did if did in DEMO_MANIFEST else "1znf"

    # hider_count (clamped)
    cap = hider_count_cap(atom_count) if atom_count else 50
    try:
        hc = int(state.get("hider_count", DEFAULTS["hider_count"]))
    except (TypeError, ValueError):
        hc = DEFAULTS["hider_count"]
    result["hider_count"] = max(1, min(cap, hc))

    # lock_scene / difficulty_easy (bool coercion)
    result["lock_scene"] = bool(state.get("lock_scene", False))
    result["difficulty_easy"] = bool(state.get("difficulty_easy", True))

    # per_rep (drop invalid keys, clamp values)
    per_rep = state.get("per_rep", {})
    clean = {}
    if isinstance(per_rep, dict):
        for rep, count in per_rep.items():
            if rep in GAME_REPS:
                try:
                    c = int(count)
                except (TypeError, ValueError):
                    continue
                if c > 0:  # drop zero/negative counts (means "random")
                    clean[rep] = c

    # per_rep-sum clamp: sum(per_rep) <= hider_count (Gap 2 pure).
    # Iterate in insertion order; keep entries that fit the remaining
    # budget; drop entries that would overflow. Runs AFTER the
    # hider_count clamp so it uses the final hider_count.
    clamped = {}
    remaining = result["hider_count"]
    for rep, c in clean.items():
        if c <= remaining:
            clamped[rep] = c
            remaining -= c
        # else: skip (drop overflow entry)
    result["per_rep"] = clamped

    # New fields (Gap 3 + Gap 4)
    result["lock_source"] = bool(state.get("lock_source", False))
    result["pdb_pool"] = _validate_pdb_pool(state.get("pdb_pool", PDB_POOL))

    return result


# ---- Remaining-hiders label formatter (Phase 4.1, GAME-03) ----

def format_remaining(total, counts_by_rep, easy_mode):
    """Format the remaining-hiders label (GAME-03 per-rep display).

    Pure helper: stdlib only, no Qt, no molecular viewer coupling, so it
    is unit-testable in WSL. The GameTab label setter calls this with the
    total remaining hider count and a per-rep breakdown and writes the
    returned string straight onto its label widget.

    Args:
        total (int): total remaining (hidden) hiders.
        counts_by_rep (dict|None): {rep: count} of REMAINING (hidden-only)
            hiders per rep. None or an empty dict collapses to the
            total-only display.
        easy_mode (bool): True = easy (show the per-rep breakdown); False
            = hard (total-only, byte-identical to the Phase 4 label, SC2).

    Returns:
        str: the label text. In easy mode the per-rep entries appear in
        GAME_REPS order, only reps whose count is greater than zero, and
        exactly two spaces separate the total from the opening paren
        (SC1). A None/empty counts dict, or an all-zero win state, yields
        the total-only form so the label never shows an empty parenthetical.
    """
    if not easy_mode or not counts_by_rep:
        return "Remaining: %d" % total
    parts = ["%s: %d" % (rep, counts_by_rep[rep])
            for rep in GAME_REPS if counts_by_rep.get(rep, 0) > 0]
    if not parts:
        return "Remaining: %d" % total
    return "Remaining: %d  (%s)" % (total, ", ".join(parts))


# ---- Post-game debrief formatter (Phase 10 DIFF-03) ----

#: Graceful fallback string for the debrief when there is nothing to
#: explain (empty/None/all-zero counts_by_rep). Shared by both the
#: early-empty branch and the no-bullets branch so the literal lives in
#: one place (single source of truth).
_DEBRIEF_FALLBACK = "All hiders are highlighted in the viewer."

#: Per-rep "why hard to spot" explanations for the post-game debrief.
#: Body text only (NO "<rep>:" prefix, NO "<b>" tags) — the formatter
#: adds the "<b>%s: %d hider(s)</b>" header. Verbatim from
#: 10-RESEARCH-endgame.md "Per-Rep Why Hard to Spot Explanations" (each
#: grounded in the actual mutation.py insertion mechanism — spheres =
#: matching elem/color/radius ball; lines/sticks = bonded pseudoatom
#: with copied elem/color; cartoon/ribbon = copied real backbone
#: segment on a new chain with a displaced middle).
DEBRIEF_EXPLANATIONS = {
    'spheres':
        "A sphere hider is a single pseudoatom placed among the real atoms, "
        "with a matching element, color, and radius. In the sphere cloud "
        "every atom is a uniformly-sized ball, so a foreign ball looks "
        "identical to a real one — you find it by noticing an atom that "
        "has no chemical reason to be there, not by any visual difference.",
    'lines':
        "A line hider is a pseudoatom bonded to a real atom, rendered as a "
        "thin line. The lines view is a wireframe of bonds, so an extra atom "
        "with one bond looks like a real edge atom (a terminal H or a "
        "side-chain tip) — you find it by tracing bonds to an atom that "
        "doesn't belong to the chemistry.",
    'sticks':
        "A stick hider is a pseudoatom bonded to a real atom, rendered as a "
        "thick stick. The sticks view is a thick-bond wireframe, so an extra "
        "bond looks like a real chemical bond — you find it by tracing the "
        "bond network to an atom that doesn't fit the molecular structure.",
    'cartoon':
        "A cartoon hider is a COPIED real backbone segment placed on a new "
        "chain, rendered as cartoon. The cartoon tube is drawn through "
        "consecutive C-alpha atoms, so a copied real backbone segment is "
        "valid backbone geometry and the tube renders as part of the "
        "existing cartoon. The segment's middle residues are slightly "
        "displaced to create a small bump, but the endpoints coincide with "
        "the real trace — you find it by spotting a kink that doesn't "
        "match the known fold.",
    'ribbon':
        "A ribbon hider is a copied real backbone segment on a new chain, "
        "rendered as ribbon. The ribbon is drawn through consecutive "
        "backbone atoms, so a copied real segment is valid backbone and "
        "renders as part of the existing ribbon. Like the cartoon hider, "
        "the middle is displaced to create a small bump — you find it by "
        "spotting a kink in the ribbon.",
}


def format_debrief_text(counts_by_rep):
    """Build the post-game debrief rich-text (DIFF-03) from a per-rep count
    dict. Pure helper: stdlib only, no Qt, no molecular viewer coupling, so
    it is unit-testable in WSL. The GameTab's debrief QMessageBox calls this
    with ``registry.counts_by_rep()`` and writes the returned string straight
    onto ``QMessageBox.setInformativeText``.

    Args:
        counts_by_rep (dict|None): ``{rep: count}`` from
            ``registry.counts_by_rep()`` (zero-filled GAME_REPS, skips
            rep=None). None or empty -> graceful fallback string.

    Returns:
        str: an HTML rich-text string usable in ``setInformativeText``.
        Starts with a frame sentence, then a ``<ul>`` of bullets for every
        rep with ``count > 0`` in GAME_REPS order, each bullet
        ``"<li><b>%s: %d hider(s)</b> — %s</li>" % (rep, count,
        DEBRIEF_EXPLANATIONS[rep])``. An empty dict, a None input, or an
        all-zero dict yields the fallback string
        ``"All hiders are highlighted in the viewer."`` (no empty ``<ul>``).
        A None key in the input dict is skipped defensively (the real
        counts_by_rep never emits one; the guard prevents a TypeError on
        a corrupt input).
    """
    if not counts_by_rep:
        return _DEBRIEF_FALLBACK
    total = 0
    bullets = []
    for rep in GAME_REPS:
        if not rep:  # defensive: skip a None key (counts_by_rep never emits one)
            continue
        count = counts_by_rep.get(rep, 0)
        if count > 0:
            total += count
            bullets.append(
                "<li><b>%s: %d hider(s)</b> — %s</li>" % (
                    rep, count, DEBRIEF_EXPLANATIONS[rep]))
    if not bullets:
        return _DEBRIEF_FALLBACK
    return ("All %d hiders are now highlighted in the viewer. "
            "Here's why each kind was hard to spot:<ul>%s</ul>" % (
                total, "".join(bullets)))
