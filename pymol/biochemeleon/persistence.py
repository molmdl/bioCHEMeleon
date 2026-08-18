"""bioCHEMeleon persistence - .bcm sidecar assembly + .bcmz archive I/O.

Phase 8 module. Pure-layer assembly (build_bcm_dict + parse_bcm_dict +
apply_bcm_dict) lives here alongside the pure file-I/O archive helpers
(write_bcmz + read_bcmz + resolve_target - added in Plan 03). All
functions in this module are PURE (stdlib only - no `pymol` import); the
cmd-coupled steps (cmd.save of the .pse before write_bcmz, cmd.load of
the .pse after read_bcmz, cmd.color re-apply, backup.snapshot) live in
the GUI handler (Plan 04) + game.py.import_state, NOT here. This keeps
persistence.py WSL-testable for the pure unit tests (same sys.modules
stub pattern as test_registry.py).

Purity: module-level imports are stdlib (json, os, tempfile, time,
zipfile) + biochemeleon.registry + biochemeleon.setup_state ONLY. NO
`pymol` import at module level OR inside any function body.

Dependency direction (strict, no cycle):
  setup_state.py (PURE) <- registry.py (PURE) <- persistence.py (THIS)
  <- game.py (orchestrator) <- __init__.py (composition root)
"""

import json
import os
import tempfile
import time
import zipfile

from .registry import HiderRegistry, ReconcileMismatches  # noqa: F401 (type refs; re-exported for callers)
from .setup_state import SETUP_FORMAT

# ---- Constants ----

#: Magic header written into every .bcm sidecar so parse_bcm_dict can
#: refuse non-bioCHEMeleon JSON with a clear error.
BCM_MAGIC = 'BIOCHEMELEON-BCM'

#: .bcm schema version. parse_bcm_dict refuses version > BCM_VERSION so a
#: newer sidecar produced by a future bioCHEMeleon surfaces a clear
#: "please update" error rather than silently mis-parsing.
BCM_VERSION = 1


# ---- Pure assembly ----

def build_bcm_dict(controller, setup_state, kind, elapsed=None):
    """Assemble the full .bcm dict from a controller + setup state.

    Pure (no pymol, no Qt). Captures the per-hider registry (via
    controller.registry.to_dict()), the controller-level fields
    (elapsed, reveal_count, hint_count, found_color), the target object
    name, and the setup dict (so Restart-on-imported can re-generate
    and an exported puzzle shows the educator's configuration).

    Args:
        controller (GameController): the live controller. Reads
            target_obj, registry, _reveal_count, _hint_count,
            _found_color, _started, _start_time. Does NOT read
            _backup_name / _wizard / callbacks (transient).
        setup_state (dict): the gui_setup.collect_state() dict.
        kind (str): 'checkpoint' (Save mid-game) or 'puzzle'
            (Generate & export).
        elapsed (float or None): for 'checkpoint', the running elapsed
            time.time() - controller._start_time captured at Save click.
            If None, falls back to time.time() - controller._start_time
            (for checkpoint) or 0.0 (for puzzle). Caller should pass it
            explicitly to avoid the modal-dialog timer pitfall (research
            section 11 - capture BEFORE the file dialog).

    Returns:
        dict: the full .bcm dict, JSON-serializable.

    Raises:
        ValueError: if kind is not 'checkpoint' or 'puzzle'.
    """
    if kind not in ('checkpoint', 'puzzle'):
        raise ValueError(
            "kind must be 'checkpoint' or 'puzzle', got %r" % (kind,))
    if elapsed is None:
        if kind == 'checkpoint' and controller._start_time is not None:
            elapsed = time.time() - controller._start_time
        else:
            elapsed = 0.0
    # found_color_rgb: FORWARD-COMPAT HOOK (Phase 8+ follow-up, NOT wired
    # in Phase 8). The .pse is HIGH confidence to preserve per-atom custom
    # colors (exporting.py:424 + importing.py:143), so the safety net is
    # deferred - Plan 04's _on_save/_on_export/_on_pick_color do NOT set
    # controller._found_color_rgb. The getattr read below is kept as a
    # forward-compat hook (returns None in Phase 8); a later phase may
    # populate _found_color_rgb via cmd.get_color when _found_color is a
    # custom cmd.set_color name. Do NOT rely on it being non-None in Phase 8.
    found_color_rgb = getattr(controller, '_found_color_rgb', None)
    return {
        'magic': BCM_MAGIC,
        'version': BCM_VERSION,
        'kind': kind,
        'target_object': controller.target_obj,
        # Force started=False for kind='puzzle': the educator did not play
        # the puzzle (they generated + exported it), so started must be
        # False regardless of controller._started (which is True after
        # gc.start() inserted the hiders). For 'checkpoint', reflect the
        # controller's actual _started state (mid-game save).
        'started': bool(controller._started) if kind == 'checkpoint' else False,
        'timer_elapsed': float(elapsed),
        'reveal_count': int(controller._reveal_count),
        'hint_count': int(controller._hint_count),
        'found_color': str(controller._found_color),
        'found_color_rgb': found_color_rgb,
        'registry': controller.registry.to_dict(),
        'setup': setup_state,
    }


def parse_bcm_dict(raw):
    """Parse + validate a .bcm JSON string (or bytes) into a dict.

    Pure (no pymol). Validates the magic header + version. Returns the
    parsed dict. Raises ValueError on magic mismatch, unsupported
    version, or JSON parse failure.

    Args:
        raw (str or bytes): the raw .bcm JSON content.

    Returns:
        dict: the parsed .bcm dict.

    Raises:
        ValueError: if magic != BCM_MAGIC, version > BCM_VERSION, or
            the content is not valid JSON.
    """
    if isinstance(raw, bytes):
        raw = raw.decode('utf-8')
    try:
        d = json.loads(raw)
    except ValueError as exc:
        raise ValueError("could not parse .bcm JSON: %s" % (exc,))
    if d.get('magic') != BCM_MAGIC:
        raise ValueError(
            "not a bioCHEMeleon sidecar (magic=%r, expected %r)" %
            (d.get('magic'), BCM_MAGIC))
    version = int(d.get('version', 1))
    if version > BCM_VERSION:
        raise ValueError(
            "unsupported .bcm version %d (expected %d). "
            "Please update bioCHEMeleon." % (version, BCM_VERSION))
    return d


# ---- apply + .bcmz archive I/O (Plan 03) ----

def apply_bcm_dict(controller, bcm_dict):
    """Set controller state fields + reconcile the registry from a .bcm dict.

    Pure (no pymol). The cmd-coupled steps (cmd.load of the .pse,
    reconstruct_from_sentinels, cmd.color re-apply, backup.snapshot)
    are the caller's responsibility - this function only sets the
    controller's serializable fields and reconciles the (already
    sentinel-rebuilt) registry with the .bcm's per-hider metadata.

    Precondition: ``controller.registry`` was already rebuilt via
    ``reconstruct_from_sentinels`` (the caller did that between
    ``cmd.load(.pse)`` and this call).

    Args:
        controller (GameController): the controller whose registry
            was sentinel-rebuilt. Sets _reveal_count, _hint_count,
            _found_color; reconciles registry in place.
        bcm_dict (dict): the parsed .bcm sidecar (from parse_bcm_dict
            or read_bcmz).

    Returns:
        ReconcileMismatches: the namedtuple from
        registry.reconcile_with_bcm - caller logs warnings.

    Raises:
        ValueError: if the .bcm magic or version is wrong (refuse load).
    """
    if bcm_dict.get('magic') != BCM_MAGIC:
        raise ValueError(
            "not a bioCHEMeleon sidecar (magic=%r, expected %r)" %
            (bcm_dict.get('magic'), BCM_MAGIC))
    version = int(bcm_dict.get('version', 1))
    if version > BCM_VERSION:
        raise ValueError(
            "unsupported .bcm version %d (expected %d)" %
            (version, BCM_VERSION))
    controller._reveal_count = int(bcm_dict.get('reveal_count', 0))
    controller._hint_count = int(bcm_dict.get('hint_count', 0))
    controller._found_color = str(bcm_dict.get('found_color', 'green'))
    bcm_registry = bcm_dict.get('registry', {})
    bcm_hiders = (bcm_registry.get('hiders', [])
                  if isinstance(bcm_registry, dict) else [])
    return controller.registry.reconcile_with_bcm(bcm_hiders)


def write_bcmz(bcmz_path, bcm_dict, pse_path):
    """Bundle a .pse + .bcm into a single .bcmz archive (stdlib zipfile).

    Pure file I/O (no pymol). The caller does cmd.save(pse_path,
    target_obj) FIRST (the scoped save that excludes _bchm_backup),
    then calls this to bundle the .pse + the .bcm JSON sidecar into
    a single .bcmz archive for sharing.

    Args:
        bcmz_path (str): path to write the .bcmz archive.
        bcm_dict (dict): the .bcm sidecar dict (from build_bcm_dict).
        pse_path (str): path to the already-written .pse file.

    Raises:
        OSError: if the .pse can't be read or the .bcmz can't be written.
    """
    with zipfile.ZipFile(bcmz_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.write(pse_path, 'game.pse')
        zf.writestr('game.bcm', json.dumps(bcm_dict, indent=2))


def read_bcmz(bcmz_path):
    """Extract a .bcmz archive -> (pse_path, bcm_dict).

    Pure file I/O (no pymol). Extracts game.pse to a temp file +
    reads + validates game.bcm. The caller does cmd.load(pse_path,
    partial=1) AFTER this (to merge the puzzle into the session).

    Args:
        bcmz_path (str): path to the .bcmz archive.

    Returns:
        tuple: (pse_path, bcm_dict). pse_path is a temp file the caller
            must clean up (or use within the temp dir's lifetime).

    Raises:
        ValueError: if the archive is missing game.pse or game.bcm,
            or the .bcm magic/version is wrong.
        OSError: if the archive can't be read.
    """
    with zipfile.ZipFile(bcmz_path, 'r') as zf:
        names = zf.namelist()
        if 'game.bcm' not in names:
            raise ValueError(
                "not a bioCHEMeleon archive (missing game.bcm)")
        if 'game.pse' not in names:
            raise ValueError(
                "archive missing game.pse (cannot reconstruct)")
        bcm_dict = parse_bcm_dict(zf.read('game.bcm'))
        tmpdir = tempfile.mkdtemp(prefix='bchm_import_')
        pse_path = os.path.join(tmpdir, 'game.pse')
        with open(pse_path, 'wb') as f:
            f.write(zf.read('game.pse'))
    return pse_path, bcm_dict


def resolve_target(bcm_dict, names_before, loaded_molecules):
    """Resolve the imported target object name.

    Pure (no pymol). Prefer bcm_dict['target_object'] (the embedded
    name - set_session restores objects with their saved names). If
    absent or renamed on collision, fall back to the before/after
    diff (loaded_molecules - names_before). Returns None if ambiguous.

    Args:
        bcm_dict (dict): the parsed .bcm sidecar.
        names_before (set): loaded molecule object names BEFORE the
            cmd.load (for collision diff).
        loaded_molecules (list): loaded molecule object names AFTER
            the cmd.load (from demos.list_loaded_molecule_objects).

    Returns:
        str or None: the target object name, or None if it can't be
            resolved.
    """
    t = bcm_dict.get('target_object')
    if t and t in loaded_molecules:
        return t
    new = [n for n in loaded_molecules if n not in names_before
           and not n.startswith('_')]
    if len(new) == 1:
        return new[0]
    if t and t in new:
        return t
    return None
