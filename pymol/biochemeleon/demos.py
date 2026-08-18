"""Demo loader + PyMOL cmd-coupled utilities for the Setup tab (Phase 2/9).

This module bridges the pure state model (setup_state.py) to the PyMOL
cmd API. It is cmd-coupled (imports pymol.cmd) but stays Qt-free -- the
QProgressDialog + QTimer drain that orchestrates the large-demo fetch
lives in the Qt layer (__init__.py), not here (dependency direction:
setup_state <- demos <- gui_setup/__init__; Qt lives only in the GUI
layer; Pitfall 6 keeps the worker thread cmd-free).

Bundled-demo + general utilities (Phase 2):
  - to_windows_path(): WSL->Windows path conversion (Pitfall 11 fix)
  - list_loaded_molecule_objects(): enumerate enabled molecular objects
  - fetch_pdb(): fetch a structure from RCSB by PDB code
  - get_active_reps(): detect which reps are displayed on an object
  - load_demo(): load a demo PDB into PyMOL -- branches on the manifest
    entry's 'source' field (Phase 9): 'bundled' loads from data/demos/;
    fetched (memprotmd/sasbdb) delegates to load_cached_demo (cache hit)
    or returns None (cache miss -- the caller, the Qt layer's
    _resolve_large_demo, then triggers the fetch).

Fetched-large-demo split API (Phase 9 -- the Qt orchestration in
__init__.py drives these; demos.py provides the Qt-free primitives):
  - download_large_demo(): WORKER thread -- urllib download only, makes
    NO PyMOL cmd calls (Pitfall 6). Posts progress/done/error/canceled
    to a queue.
  - finalize_large_demo(): MAIN thread -- cmd.load the downloaded file,
    strip MemProtMD water/salt via the pure setup_state helper BEFORE
    cmd.load (the wet ~95k-atom file never enters PyMOL), then cmd.save
    a .pdb.gz cache. SASBDB (strip=False) skips the strip -- glycan
    HETATM is preserved.
  - load_cached_demo(): MAIN thread cache hit -- cmd.load a cached
    .pdb.gz (PyMOL reads .pdb.gz natively).
  - cache_path_for()/is_cached()/_cache_dir(): pure path helpers.
  - temp_download_path()/cleanup_temp(): temp-file management.

All cmd.* calls happen on the GUI main thread (PyMOL Qt builds run the
cmd interpreter on the Qt event loop -- safe to call directly from Qt
signal handlers; see research section 9.2). The worker download_large_demo
is the ONLY function that runs off the main thread, and it uses ONLY
stdlib (urllib/queue/os/threading) -- never pymol.cmd (Pitfall 6).
"""
import os
import threading
import queue
import ssl
import urllib.request
import urllib.error

from pymol import cmd

from .setup_state import (
    GAME_REPS, DEMO_MANIFEST,
    STRIP_RESN_MEMPROTMD, strip_resn_from_pdb,
)


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
    """Load a demo PDB into PyMOL by its manifest id (e.g. '1znf').

    Returns the object name on success, None on failure. Paths pass
    through to_windows_path() so Windows PyMOL (which cannot resolve
    /mnt/c/... WSL paths) can open them.

    Branches on the manifest entry's 'source' field (Phase 9 schema):
      - 'bundled'  -> load data/demos/{cache_name} (offline; always
        available; the existing Phase 2 path, unchanged except the
        field rename file -> cache_name from 09-01).
      - fetched (memprotmd/sasbdb) -> delegate to load_cached_demo
        (cache hit returns the loaded object name; cache miss returns
        None -- the caller, the Qt layer's _resolve_large_demo, then
        triggers the fetch via download_large_demo + finalize_large_demo).

    Honors the "Returns None on failure" contract for EVERY manifest
    entry: an unknown id, a missing 'cache_name' key, a missing file, or
    a cmd.load failure all return None (never raise). This is the
    contract _prepare_and_start relies on (it checks
    ``if target_obj is None`` and shows a QMessageBox, rather than
    catching a KeyError).

    Source: research section 4.4, 6; Phase 9 manifest schema (09-01);
    09-02-PLAN Task 1 step 9 (source branching); 09-RESEARCH-pipeline
    load_demo branching section.
    """
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None:
        return None
    # Phase 9 source branching. Bundled demos resolve under data/demos/;
    # fetched demos (memprotmd/sasbdb) go through the cache path (cache
    # hit loads the stripped .pdb.gz; cache miss returns None so the Qt
    # layer can trigger download_large_demo + finalize_large_demo).
    if meta.get('source', 'bundled') != 'bundled':
        return load_cached_demo(demo_id)
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


# ---- Phase 9: fetched-large-demo split API (Qt-free; the QProgressDialog ----
# ---- + QTimer drain that drives these lives in __init__.py, the Qt layer) ----

def _cache_dir():
    """Return the absolute path to the fetched-demo cache directory.

    Resolves to <repo>/tmp/phase9-demos/cache/, mirroring load_demo's
    os.path.dirname(__file__)/data/demos pattern (demos.py module file
    lives in biochemeleon/, so '..' reaches the repo root). The dir is
    git-ignored (git check-ignore tmp/phase9-demos returns exit 0); it
    persists across PyMOL sessions so a fetched demo is downloaded only
    once. v1 runs from the repo (AGENTS.md); an installed plugin would
    need a configurable cache dir (Open Risk 4 / Pitfall E -- v2).

    Source: 09-RESEARCH-pipeline.md:296-299 (cache location + path
    resolution); 09-RESEARCH-sasbdb.md:230 (gitignore verified).
    """
    return os.path.abspath(
        os.path.join(os.path.dirname(__file__), '..', 'tmp', 'phase9-demos', 'cache'))


def cache_path_for(demo_id):
    """Return the absolute path to the cached .pdb.gz for a demo.

    Returns None for bundled demos or unknown ids (bundled demos resolve
    under data/demos/ via load_demo; they have no cache entry). For
    fetched demos (memprotmd/sasbdb) returns
    <cache_dir>/<meta['cache_name']> -- the .pdb.gz written by
    finalize_large_demo's cmd.save and read by load_cached_demo's
    cmd.load (PyMOL reads .pdb.gz natively -- internal.py file_read
    detects the gzip magic and decompresses transparently).

    Source: 09-RESEARCH-pipeline.md:301-306.
    """
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None or meta.get('source') == 'bundled':
        return None
    return os.path.join(_cache_dir(), meta['cache_name'])


def is_cached(demo_id):
    """Return True if a cached .pdb.gz exists for the demo (cache hit).

    False for bundled demos (no cache entry) and for fetched demos whose
    first fetch has not yet completed (cache miss -- the caller then
    triggers download_large_demo + finalize_large_demo).

    Source: 09-RESEARCH-pipeline.md:308-310.
    """
    p = cache_path_for(demo_id)
    return bool(p and os.path.exists(p))


def temp_download_path(demo_id):
    """Return a temp path for the raw (pre-strip, pre-cache) download.

    Uses tmp/phase9-demos/<demo_id>.raw (repo-local, git-ignored) rather
    than tempfile.mkstemp so the path is deterministic + traceable for
    debugging (a tempfile would be cleaned by the OS on restart; the
    .raw file survives an interrupted fetch for inspection). The caller
    (the Qt layer's _resolve_large_demo) converts via to_windows_path
    before handing the path to the worker + finalize_large_demo, and
    calls cleanup_temp when done.

    Source: 09-RESEARCH-pipeline.md:482 (temp-file management).
    """
    return os.path.join(
        os.path.dirname(__file__), '..', 'tmp', 'phase9-demos', demo_id + '.raw')


def cleanup_temp(path):
    """Idempotently delete a temp file (the .raw download or the .dry
    stripped intermediate). Silently ignores a missing file or an
    OSError (the cache write is the load-bearing step; temp cleanup is
    best-effort).

    Source: 09-RESEARCH-pipeline.md:482.
    """
    try:
        os.unlink(path)
    except OSError:
        pass


def _urlopen_with_ssl_fallback(url, timeout, progress_queue=None):
    """Open a URL, retrying without certificate verification if SSL fails.

    Some academic hosts (e.g. SASBDB) use root CAs that may not be in the
    bundled certificate list on all Python builds (notably Windows conda,
    whose CA list can lack the HARICA root that signs sasbdb.org). The
    first attempt uses the default verifying context; if an SSL error
    occurs, the retry uses a non-verifying context. This is acceptable for
    downloading public molecular structure files from known academic
    repositories -- the content is public, not sensitive.

    NOTE on exception shape: ``urllib.request.urlopen`` does NOT raise a
    bare ``ssl.SSLError`` for a certificate-verification failure; it wraps
    the SSL error as ``urllib.error.URLError(reason=SSLError(...))``
    (verified empirically: do_open catches the OSError-family SSL error
    during the TLS handshake and re-raises it as URLError). So the SSL
    case is detected via ``isinstance(e.reason, ssl.SSLError)``. A bare
    ``except ssl.SSLError`` is also kept as a defensive safety net for any
    build where the SSL error surfaces un-wrapped. Non-SSL URL errors
    (HTTP 404, DNS, connection refused, timeout) have a non-SSL ``.reason``
    and are re-raised unchanged for the caller's outer handler to report.

    When *progress_queue* is given, a ``('warning', msg)`` event is posted
    on the fallback so the caller's drain can optionally surface it (the
    current drain silently ignores unknown event kinds, which is safe).

    Returns an HTTPResponse (the caller uses it as a context manager).
    Raises if BOTH attempts fail (caught by the caller's outer except).
    """
    req = urllib.request.Request(
        url, headers={'User-Agent': 'bioCHEMeleon/1.0'})
    try:
        return urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.URLError as e:
        # Retry only on a genuine SSL failure (cert verify / handshake).
        # A 404 / DNS / timeout URLError has a non-SSL reason -> re-raise.
        if not isinstance(getattr(e, 'reason', None), ssl.SSLError):
            raise
    except ssl.SSLError:
        # Defensive: bare SSL error (un-wrapped) -> fall through to retry.
        pass
    # SSL failure -- retry with a non-verifying context (the host's root
    # CA may be absent from the bundled certificate list on some builds).
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    if progress_queue is not None:
        progress_queue.put((
            'warning',
            'Certificate verification unavailable for this host; '
            'retrying without verification (public structure file).'))
    return urllib.request.urlopen(req, timeout=timeout, context=ctx)


def download_large_demo(demo_id, dest_path, progress_queue, cancel_event):
    """Download a large demo's raw file to dest_path via urllib.

    WORKER THREAD (Pitfall 6 compliant -- this function uses ONLY
    stdlib: urllib/queue/os/threading/ssl; it does NOT import pymol,
    makes NO PyMOL cmd API calls, does NOT touch Qt widgets). The Qt
    layer (__init__.py _resolve_large_demo) spawns this on a daemon
    thread and drains progress_queue on the main thread via a QTimer.

    Reads the manifest's fetch_url in 64KB blocks. Between blocks it
    checks cancel_event.is_set() (the QProgressDialog Cancel button sets
    the event) and posts one of:
      - ('progress', pct) -- received*100//total if Content-Length known
      - ('done',)         -- the full file is written to dest_path
      - ('canceled',)     -- cancel_event was set between blocks
      - ('error', msg)    -- any exception (URLError, HTTPError, timeout,
                             disk write failure, ...)

    SSL fallback: the fetch is performed via _urlopen_with_ssl_fallback,
    which retries without certificate verification if the default
    verifying context encounters an SSL error, for academic hosts whose
    root CA may not be in the bundled certificate list (notably SASBDB's
    HARICA root on Windows conda). This is acceptable for public
    molecular structure files; a warning event is posted on the fallback
    so the drain can optionally surface it. Non-SSL errors propagate to
    the outer handler below.

    Returns None (the result goes via the queue, not the return value --
    the main-thread drain reads it). A User-Agent header is set because
    some hosts (notably SASBDB) may block the bare default urllib UA.

    Source: 09-RESEARCH-pipeline.md:231-258 (worker implementation);
    09-RESEARCH-sasbdb.md:214 (User-Agent defensive).
    """
    meta = DEMO_MANIFEST[demo_id]
    url = meta['fetch_url']
    try:
        with _urlopen_with_ssl_fallback(url, 60, progress_queue) as resp:
            total = int(resp.headers.get('Content-Length', 0))  # 0 = unknown
            received = 0
            with open(dest_path, 'wb') as f:
                while True:
                    if cancel_event.is_set():
                        progress_queue.put(('canceled',))
                        return
                    block = resp.read(65536)  # 64KB blocks
                    if not block:
                        break
                    f.write(block)
                    received += len(block)
                    if total > 0:
                        progress_queue.put(('progress', received * 100 // total))
        progress_queue.put(('done',))
    except Exception as exc:
        progress_queue.put(('error', str(exc)))


def finalize_large_demo(demo_id, downloaded_path):
    """Load the downloaded file, strip MemProtMD water/salt, save the
    .pdb.gz cache. Runs on the MAIN thread (cmd.*). Returns the object
    name on success, None on failure.

    STRIP DISTINCTION (Pitfall C -- 09-RESEARCH-pipeline.md:206): this
    is the deliberate pre-game DEMO-02 strip of water and salt from a
    fetched MemProtMD membrane entry, NOT the cleanup-time segi-GAME
    sentinel filter (Pitfall 9 uses `segi GAME` only). The DPPC membrane
    lipids are organic (resn DPP), NOT water/salt, so they survive the
    strip by construction (the pure helper filters by residue name and
    DPP is not in the strip set).

    MemProtMD strip approach (09-RESEARCH-memprotmd.md:247-282 -- the
    researcher's PRIMARY recommendation): strip SOL/NA/CL by explicit
    residue-name line-filtering in PURE PYTHON (the 09-01
    strip_resn_from_pdb helper) BEFORE cmd.load, so the ~95k-atom wet
    file never enters PyMOL (avoids Pitfall 12 -- large wet load). The
    dry ~19k-atom result is what cmd.load sees. This is deterministic
    and flag-independent (MemProtMD records SOL/NA/CL as ATOM, not
    HETATM, so a hetatm-keyed filter would miss them).

    SASBDB (strip=False) skips the strip entirely -- the glycan HETATM
    must survive (DEMO-03; 09-RESEARCH-sasbdb.md:257-259 CAUTION: a
    blanket hetatm removal would nuke the 2601 glycan atoms; we do NOT
    do that). The downloaded file is handed to cmd.load as-is.

    LOAD FORMAT: cmd.load is called with format='pdb' because the
    on-disk extensions are not registered PyMOL file types. The
    MemProtMD strip writes a .dry intermediate and the worker downloads
    to a .raw temp; PyMOL's filename_to_format (importing.py) dispatches
    by extension and neither .dry nor .raw is in the loadfunctions map
    (nor has a molfile plugin), so without an explicit format cmd.load
    raises CmdException('unsupported file type') and finalize returns
    None. format='pdb' forces the PDB reader (read_pdbstr) regardless of
    extension -- both .dry and .raw hold plain PDB content. The cache
    .pdb.gz path (load_cached_demo) is unaffected: .pdb.gz is a
    recognized extension (gzipped pdb) and needs no format kwarg.

    The cache is written by cmd.save to <cache_dir>/<cache_name> as a
    .pdb.gz (exporting.py:912 -- cmd.save opens gzip.open when the
    filename ends in .gz; one call writes the gzipped PDB). A cache
    write failure is non-fatal (the object is already loaded; the next
    fetch will just re-download).

    Source: 09-RESEARCH-pipeline.md:264-292 (finalize skeleton, adapted
    to use the 09-01 pure strip helper for MemProtMD);
    09-RESEARCH-memprotmd.md:247-282 (pure-Python strip recommendation);
    09-RESEARCH-sasbdb.md:257-259 (strip=False preserves glycan).
    """
    meta = DEMO_MANIFEST[demo_id]
    obj_name = demo_id.lower()
    # MemProtMD: pure-Python strip BEFORE cmd.load (wet file never enters
    # PyMOL). SASBDB (strip=False) or bundled -- load as-is.
    if meta.get('strip', False) and meta.get('source') == 'memprotmd':
        try:
            with open(downloaded_path, 'r') as f:
                raw = f.read()
            dry = strip_resn_from_pdb(raw, STRIP_RESN_MEMPROTMD)  # 09-01 pure helper
            dry_path = downloaded_path + '.dry'
            with open(dry_path, 'w') as f:
                f.write(dry)
            load_path = dry_path
        except Exception:
            return None
    else:
        load_path = downloaded_path  # SASBDB (strip=False) -- load as-is
    win_path = to_windows_path(load_path)
    try:
        # format='pdb' forces the PDB reader regardless of the on-disk
        # extension: the MemProtMD strip writes a .dry intermediate and the
        # worker downloads to a .raw temp, neither of which is a registered
        # PyMOL file extension (importing.py filename_to_format dispatches by
        # extension; .dry/.raw are not in loadfunctions and have no molfile
        # plugin, so cmd.load would raise CmdException 'unsupported file
        # type' and finalize would return None). Explicit format= overrides
        # the extension dispatch (importing.py load() docstring: "The file
        # extension is used to determine the format unless the format is
        # provided explicitly"). Both .dry and .raw hold plain PDB content.
        cmd.load(win_path, object=obj_name, zoom=1, format='pdb')
    except Exception:
        return None
    # Cache the loaded object as .pdb.gz (cmd.save writes gzip in one step
    # -- exporting.py:912). Cache write failure is non-fatal.
    cache_dir = _cache_dir()
    try:
        os.makedirs(cache_dir, exist_ok=True)
    except OSError:
        return obj_name  # object loaded but cache unavailable -- still a success
    cache_path = os.path.join(cache_dir, meta['cache_name'])
    try:
        cmd.save(to_windows_path(cache_path), obj_name)
    except Exception:
        pass  # cache write failure is non-fatal (object already loaded)
    # Clean the .dry intermediate (keep the .raw for debugging? no --
    # cleanup_temp both; the .pdb.gz cache is the persistent artifact).
    if meta.get('strip', False):
        cleanup_temp(load_path)  # the .dry path (downloaded_path + '.dry')
    return obj_name


def load_cached_demo(demo_id):
    """Cache-hit path: cmd.load the cached .pdb.gz (already stripped
    for MemProtMD). Runs on the MAIN thread (cmd.*). Returns the object
    name on success, None on cache miss / bundled demo / load failure.

    None means "the caller must fetch" -- the Qt layer's
    _resolve_large_demo then shows the QProgressDialog + spawns the
    urllib worker. A cache hit is synchronous (no dialog) and offline
    (the .pdb.gz persists across sessions).

    PyMOL reads .pdb.gz natively (internal.py:278-308 file_read detects
    the gzip magic \\x1f\\x8b and decompresses transparently), so
    cmd.load(cache_path) works without a manual gzip step.

    Source: 09-RESEARCH-pipeline.md:312-327.
    """
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None or meta.get('source') == 'bundled':
        return None  # bundled demos use load_demo()
    p = cache_path_for(demo_id)
    if not os.path.exists(p):
        return None  # cache miss -- caller must download
    obj_name = demo_id.lower()
    try:
        cmd.load(to_windows_path(p), object=obj_name, zoom=1)  # reads .pdb.gz natively
        return obj_name
    except Exception:
        return None
