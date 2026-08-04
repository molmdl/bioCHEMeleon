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
}

#: Valid target modes for validation.
_VALID_MODES = {"loaded", "fetch", "demo"}


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


def randomize_state(seed=None, atom_count=None):
    """Return a random valid setup state dict.

    If *seed* is given, the result is deterministic (same seed -> same
    dict). If *atom_count* is given, hider_count is capped to
    hider_count_cap(atom_count); otherwise capped at 50.

    The returned dict is a complete state (all DEFAULTS keys) suitable
    for passing to SetupTab.apply_state().

    Source: research section 7.5 (adapted to a pure function - the SetupTab
    method calls this and then applies the result).
    """
    rng = _random.Random(seed)
    mode = rng.choice(["loaded", "fetch", "demo", "demo"])  # weight toward demo
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
    return {
        "format": SETUP_FORMAT,
        "target_mode": mode,
        "selected_object": "",
        "pdb_code": "",
        "demo_id": rng.choice(list(DEMO_MANIFEST.keys())),
        "hider_count": hider_count,
        "lock_scene": rng.choice([True, False]),
        "per_rep": per_rep,
        "difficulty_easy": rng.choice([True, False]),
    }


def validate_state(state, atom_count=None):
    """Validate and clamp a setup state dict.

    Returns a NEW dict (does not mutate *state*). Fills missing keys
    from DEFAULTS, clamps hider_count to [1, cap], falls back invalid
    enum values to their defaults, and drops invalid per_rep keys.

    *atom_count* (optional) controls the hider_count cap: if given,
    cap = hider_count_cap(atom_count); else cap = 50.

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
    result["per_rep"] = clean

    return result
