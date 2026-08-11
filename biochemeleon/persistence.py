"""bioCHEMeleon persistence - .bcm sidecar assembly + .bcmz archive I/O.

Phase 8 module. Pure-layer assembly (build_bcm_dict + parse_bcm_dict +
apply_bcm_dict) lives here alongside the cmd-coupled file I/O
(write_bcmz + read_bcmz + resolve_target - added in Plan 03).

Purity: module-level imports are stdlib + biochemeleon.registry +
biochemeleon.setup_state ONLY. NO `pymol` import at module level - the
cmd-coupled functions (Plan 03) import cmd lazily inside the function
body so this module stays WSL-importable for the pure unit tests (same
sys.modules stub pattern as test_registry.py).

Dependency direction (strict, no cycle):
  setup_state.py (PURE) <- registry.py (PURE) <- persistence.py (THIS)
  <- game.py (orchestrator) <- __init__.py (composition root)
"""

import json
import time

from .registry import HiderRegistry  # noqa: F401 (type ref; not strictly needed)
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
