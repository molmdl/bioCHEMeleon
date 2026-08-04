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

#: Manifest of the 6 bundled demo PDBs (DEMO-01).
#: Each entry: {category, type, difficulty, file}.
#: Citations live in biochemeleon/data/demos/SOURCES.md (Plan 02-02).
#: Phase 9 (DIFF-05) will extend this with large fetched demos + tiers.
DEMO_MANIFEST = {
    '1znf': {'category': 'Protein',      'type': 'protein',     'difficulty': 'easy',  'file': '1znf.pdb'},
    '1xdn': {'category': 'Protein',      'type': 'protein',     'difficulty': 'hard',  'file': '1xdn.pdb'},
    '5e54': {'category': 'Nucleic acid', 'type': 'rna',         'difficulty': 'easy',  'file': '5e54.pdb'},
    '1k8p': {'category': 'Nucleic acid', 'type': 'dna',         'difficulty': 'easy',  'file': '1k8p.pdb'},
    '2qbz': {'category': 'Nucleic acid', 'type': 'rna',         'difficulty': 'hard',  'file': '2qbz.pdb'},
    '4wb3': {'category': 'Mixed',        'type': 'protein/na',  'difficulty': 'mixed', 'file': '4wb3.pdb'},
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
    """Lowercase, strip, keep only 3-5 char alphanumeric; else empty string.

    PDB IDs are 4 chars by convention, but the 3-5 range tolerates legacy
    and extended IDs. The pool helper enforces 4-char to match PDB_POOL.
    """
    if not code:
        return ""
    c = str(code).strip().lower()
    if 3 <= len(c) <= 5 and c.isalnum():
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
        demo_id = rng.choice(list(DEMO_MANIFEST.keys()))

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
