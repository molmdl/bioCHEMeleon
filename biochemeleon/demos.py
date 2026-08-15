"""Demo loader + PyMOL cmd-coupled utilities for the Setup tab (Phase 2).

This module bridges the pure state model (setup_state.py) to the PyMOL
cmd API. It provides:
  - to_windows_path(): WSL->Windows path conversion (Pitfall 11 fix)
  - list_loaded_molecule_objects(): enumerate enabled molecular objects
  - fetch_pdb(): fetch a structure from RCSB by PDB code
  - get_active_reps(): detect which reps are displayed on an object
  - load_demo(): load a bundled demo PDB into PyMOL

All cmd.* calls happen on the GUI main thread (PyMOL Qt builds run the
cmd interpreter on the Qt event loop -- safe to call directly from Qt
signal handlers; see research section 9.2).
"""
import os

from pymol import cmd

from .setup_state import GAME_REPS, DEMO_MANIFEST


# ---- WSL -> Windows path helper (Pitfall 11) ----

def to_windows_path(path):
    """Convert a WSL mount path (/mnt/c/...) to a Windows path (C:\\...).

    PyMOL runs as a Windows process (launched via setenv.bat) and cannot
    resolve WSL paths. This is a GUARD, not an unconditional transform:
    only paths starting with /mnt/<letter>/ are converted; all other
    paths (already-Windows C:\\... from an installed plugin, or genuine
    Linux paths) are returned unchanged.

    Source: research section 6.2.
    """
    p = str(path)
    parts = p.replace('\\', '/').split('/', 3)
    # parts looks like ['', 'mnt', 'c', 'Users/...'] for a WSL mount path
    if len(parts) == 4 and parts[0] == '' and parts[1] == 'mnt' \
            and len(parts[2]) == 1 and parts[2].isalpha():
        drive = parts[2].upper()
        rest = parts[3]
        return '{}:\\{}'.format(drive, rest.replace('/', '\\'))
    return p


# ---- Object enumeration (SETUP-02 loaded-object mode) ----

def list_loaded_molecule_objects():
    """Return names of enabled molecular objects (exclude maps, volumes,
    selections, measurements, cgo, groups).

    Uses cmd.get_names('public_objects', enabled_only=True) filtered by
    cmd.get_type(name)=='object:molecule'. This is the verified approach
    for populating the Setup object-selector dropdown.

    Source: research section 3.1, 3.2.
    """
    out = []
    for name in cmd.get_names('public_objects', enabled_only=True):
        if cmd.get_type(name) == 'object:molecule':
            out.append(name)
    return out


# ---- PDB fetch (SETUP-02 fetch mode) ----

def fetch_pdb(code, name=None):
    """Fetch a structure from RCSB by PDB code. Synchronous. Requires
    network. Returns the object name on success, None on failure.

    Wraps cmd.fetch in try/except so network errors / invalid codes
    don't crash the Setup form. The caller (gui_setup._on_fetch) shows
    a QMessageBox on None return.

    Source: research section 3.4, 9.4.
    """
    code = code.strip().lower()
    if not (3 <= len(code) <= 5 and code.isalnum()):
        return None
    obj_name = name or code
    try:
        cmd.fetch(code, name=obj_name, async_=0)  # sync; wait for full load
        return obj_name
    except Exception:
        return None


# ---- Representation detection (SETUP-04 lock-scene) ----

def get_active_reps(obj):
    """Return the subset of GAME_REPS currently displayed on *obj*.

    Uses the verified `rep <name>` selection selector:
        cmd.count_atoms("{obj} and rep {rep}") > 0
    There is NO cmd.get_representations() in PyMOL 2.5.0 (research 3.6).

    Each per-rep count_atoms is wrapped in try/except so a single failed
    rep doesn't break the form (research 12.1 mitigation).

    Source: research section 3.6.
    """
    active = []
    for rep in GAME_REPS:
        try:
            if cmd.count_atoms("{} and rep {}".format(obj, rep)) > 0:
                active.append(rep)
        except Exception:
            pass  # invalid selection / no such object -- skip
    return active


# ---- Bundled demo loader (SETUP-02 demo mode, DEMO-01) ----

def load_demo(demo_id):
    """Load a bundled demo PDB into PyMOL by its manifest id (e.g. '1znf').

    Returns the object name on success, None on failure. The PDB is
    resolved relative to this module's __file__ so it works identically
    whether the plugin runs from the repo or from the installed copy.
    Paths pass through to_windows_path() so Windows PyMOL (which cannot
    resolve /mnt/c/... WSL paths) can open them.

    Branches on the manifest entry's 'source' field (Phase 9 schema):
      - 'bundled'  -> load data/demos/{cache_name} (offline; always
        available).
      - fetched (memprotmd/sasbdb) -> return None (cache miss). The
        Phase 9 fetch worker (download_large_demo + finalize_large_demo
        + load_cached_demo, plan 09-02) is not yet implemented, so
        fetched demos (1gzm/3gp6/sasdpg4) surface as a graceful "Could
        not load demo" in the GUI rather than crashing. When 09-02
        lands, the fetched branch should delegate to
        load_cached_demo(demo_id) instead of returning None.

    Honors the "Returns None on failure" contract for EVERY manifest
    entry: an unknown id, a missing 'cache_name' key, a missing file, or
    a cmd.load failure all return None (never raise). This restores the
    contract _prepare_and_start relies on (it checks
    ``if target_obj is None`` and shows a QMessageBox, rather than
    catching a KeyError).

    Source: research section 4.4, 6; Phase 9 manifest schema (09-01);
    09-02-PLAN Task 1 step 9 (source branching).
    """
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None:
        return None
    # Phase 9 source branching. Fetched demos need the 09-02 fetch worker
    # (download_large_demo/finalize_large_demo/load_cached_demo -- not yet
    # implemented); return None so the GUI shows a graceful "Could not load
    # demo" instead of raising. When 09-02 lands, replace this with:
    #   return load_cached_demo(demo_id)
    if meta.get('source', 'bundled') != 'bundled':
        return None
    cache_name = meta.get('cache_name')
    if not cache_name:
        return None  # malformed entry (no on-disk filename) -- None-on-failure
    path = os.path.join(os.path.dirname(__file__), 'data', 'demos', cache_name)
    if not os.path.exists(path):
        return None
    win_path = to_windows_path(path)
    obj_name = demo_id.lower()  # PyMOL object names conventionally lowercase
    try:
        cmd.load(win_path, object=obj_name, zoom=1)
        return obj_name
    except Exception:
        return None
