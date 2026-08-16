---
status: resolved
trigger: "Fix SASBDB (sasdpg4) SSL cert verification failure on first-download from Windows conda Python (HARICA root CA absent from certifi bundle). Root cause pre-diagnosed by orchestrator; job = apply + verify fix."
created: 2026-08-16T00:00:00Z
updated: 2026-08-16T01:30:00Z
---

## Current Focus

hypothesis: (fix_spec) wrapping `urllib.request.urlopen` in a helper that retries with a permissive SSL context on `ssl.SSLError` will fix the Windows conda HARICA gap. BUT my own concern: urlopen may wrap SSLError in URLError, so `except ssl.SSLError` may never fire -> fix would be dead code.
test: empirically force a cert-verification failure from WSL (empty CA list context) and observe the exception type + MRO that urlopen raises; also check whether the SSLError is bare or nested as URLError.reason.
expecting: determine the TRUE exception type so the helper's except clause catches it correctly (either bare ssl.SSLError, or URLError with .reason being SSLError).
next_action: run the exception-type probe; then decide helper except-clause shape; then apply fix.

## Symptoms

expected: Selecting the SASBDB glycoprotein demo (sasdpg4) in the Setup tab triggers a first-download that completes and lets the user play the round.
actual: First-download of sasdpg4 fails from Windows conda PyMOL with an SSL certificate verification error; the drain shows "Fetch failed". MemProtMD fetch works.
errors: ssl.SSLError: [SSL: CERTIFICATE_VERIFY_FAILED] (per orchestrator diagnosis; cert chain HARICA RootCA 2015 -> GEANT TLS RSA 1 -> sasbdb.org verifies from WSL but not from Windows conda certifi bundle).
reproduction: Windows GUI: delete SASBDB cache, select sasdpg4, click Start -> fetch fails. (Cannot be reproduced from WSL: WSL system cert store includes HARICA -> fetch returns 200.)
started: Phase 9 SC1 SASBDB first-fetch path.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-08-16T00:00:00Z
  checked: biochemeleon/demos.py download_large_demo (lines 282-329) + __init__.py drain (lines 443-514)
  found: download_large_demo calls `urllib.request.urlopen(req, timeout=60)` with NO context= param -> default context relies on certifi bundle. Drain dispatches on kind in ('progress','done','error','canceled'); unknown kinds (e.g. 'warning') are silently dropped (no else, no return) -> safe to post a ('warning', msg) event for forward-compat.
  implication: the bug location matches the diagnosis. Posting ('warning', ...) to the queue is safe.

- timestamp: 2026-08-16T00:00:00Z
  checked: top-of-file imports in demos.py (lines 42-52): import os, threading, queue, urllib.request; from pymol import cmd; from .setup_state import ...
  found: NO `import ssl` present yet. ssl is stdlib (Pitfall 6 compliant).
  implication: need to add `import ssl` to the top imports.

## Resolution

root_cause: SASBDB cert chain uses HARICA RootCA 2015 (root) which is absent from the conda-bundled certifi CA list on Windows; urlopen with the default context fails cert verification. MemProtMD uses a more common root CA present in certifi, so it verifies.

CRITICAL CORRECTION TO FIX_SPEC: the fix_spec's helper uses `except ssl.SSLError:` to trigger the fallback. Empirical probe (WSL py3.6.9, forced cert failure via no-root SSLContext) PROVES urlopen wraps the SSLError in urllib.error.URLError: `URLError(SSLError(1, '[SSL: CERTIFICATE_VERIFY_FAILED] ...'))`. `isinstance(e, ssl.SSLError)` is False -> `except ssl.SSLError` would NEVER fire -> fix would be dead code. The SSLError is nested at `e.reason`. Corrected helper catches urllib.error.URLError and checks isinstance(e.reason, ssl.SSLError) (plus a bare ssl.SSLError safety net for builds where it might surface un-wrapped). This deviation is REQUIRED for the fix to actually work.

fix: _urlopen_with_ssl_fallback(url, timeout, progress_queue=None) -- first attempt default verifying context; on URLError whose .reason is an SSLError (or bare SSLError), retry with check_hostname=False/CERT_NONE and post a ('warning', msg) to progress_queue (drain silently drops unknown kinds -- verified safe). download_large_demo calls the helper inside its existing try; non-SSL URLErrors (404/DNS/timeout) re-raise to the outer except -> ('error', msg) unchanged.

verification: ALL GREEN.
  WSL gates: py_compile OK; 112 unit tests OK; exec_ gate = 1 (gui_game.py:303, unchanged); from pymol.Qt in demos.py = 0; Pitfall-1 package-wide = 0; Pitfall 6 static (download_large_demo + helper cmd/pymol-free) PASS.
  WSL helper: fallback context creates OK (check_hostname=False, CERT_NONE); SASBDB fetch from WSL returns 200 len 400810 (first path succeeds -- WSL has HARICA).
  GOLD-STANDARD conda probe (headless, Python 3.9.13, certifi 2023.07.22):
    T1 REPRODUCE: default-context urlopen(SASBDB) -> URLError reason=SSLCertVerificationError is_ssl=True "[SSL: CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate". Confirms (a) bug reproduces on the actual buggy Python, (b) exception is URLError wrapping SSLCertVerificationError -- validates that `except ssl.SSLError` alone would be dead code; the URLError+reason check is REQUIRED.
    T2 FIX: _urlopen_with_ssl_fallback(SASBDB) -> status=200, 65536-byte block read, fallback_warning_posted=True. Fix works; fallback triggered + succeeded.
    T3 REGRESSION: _urlopen_with_ssl_fallback(MemProtMD) -> status=200, 65536-byte block, fallback_used=False. MemProtMD still verifies on first (verifying) path -- no security weakening for hosts whose CAs are in the bundle.
  Phase9 headless smoke (staged SASBDB sample + synthetic .raw): 64/64 PASSED, 0 FAIL. Section E Pitfall 6 static still PASS.
files_changed: [biochemeleon/demos.py]
