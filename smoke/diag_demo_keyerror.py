# diag_demo_keyerror.py -- verify the bundled-demo KeyError: 'file' fix.
# Run headlessly via the WSL->Windows bridge (AGENTS.md):
#   bash wsl2win_cp.sh
#   mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/diag_demo_keyerror.py tmp/bioCHEMeleon/smoke/
#   cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\diag_demo_keyerror.py" 2>&1 | tail -50
#
# Reproduces the original failure surface: with the PRE-FIX load_demo
# (meta['file']), calling load_demo on ANY manifest id raised an uncaught
# KeyError because 09-01 renamed 'file'->'cache_name' in the manifest but
# 09-02 never migrated the loader. This script iterates EVERY DEMO_MANIFEST
# id through load_demo and asserts:
#   (a) NO exception for any id (the KeyError is gone);
#   (b) bundled demos load -> return lowercase obj name + atoms > 0;
#   (c) fetched demos return None gracefully (cache miss; fetch worker
#       unimplemented -- no crash);
#   (d) an unknown id returns None.
# Exit nonzero on any FAIL.
import sys
from pymol import cmd

from biochemeleon import demos
from biochemeleon.setup_state import DEMO_MANIFEST

RESULTS = []


def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)


# --- schema reality check (documents the 09-01 rename that caused the bug) ---
check("manifest has no 'file' key (09-01 renamed file->cache_name)",
      all('file' not in m for m in DEMO_MANIFEST.values()))
check("manifest has 'cache_name' key on every entry",
      all('cache_name' in m for m in DEMO_MANIFEST.values()))

bundled_ids = [d for d, m in DEMO_MANIFEST.items()
               if m.get('source', 'bundled') == 'bundled']
fetched_ids = [d for d, m in DEMO_MANIFEST.items()
               if m.get('source', 'bundled') != 'bundled']
print("bundled ids:", bundled_ids)
print("fetched ids:", fetched_ids)

# --- (a) + (b): every BUNDLED demo loads without exception ---
for did in bundled_ids:
    try:
        obj = demos.load_demo(did)
    except Exception as exc:  # the pre-fix KeyError would land here
        check("load_demo(%r) no exception" % did, False)
        print("    raised: %r" % exc)
        continue
    ok = (obj == did.lower()) and cmd.count_atoms(obj) > 0
    check("load_demo(%r) -> %r, atoms=%d" %
          (did, obj, cmd.count_atoms(obj) if obj else -1), ok)
    # clean up so the next load starts fresh (avoid multi-state append)
    try:
        cmd.delete(did.lower())
    except Exception:
        pass

# --- (a) + (c): every FETCHED demo returns None (graceful cache-miss) ---
for did in fetched_ids:
    try:
        obj = demos.load_demo(did)
    except Exception as exc:
        check("load_demo(%r) no exception" % did, False)
        print("    raised: %r" % exc)
        continue
    check("load_demo(%r) -> None (fetched cache-miss, no crash)" % did,
          obj is None)

# --- (d): unknown id returns None (None-on-failure contract) ---
try:
    obj = demos.load_demo("bogus-id")
except Exception as exc:
    check("load_demo('bogus-id') no exception", False)
    print("    raised: %r" % exc)
else:
    check("load_demo('bogus-id') -> None", obj is None)

# --- summary ---
fails = [n for n, ok in RESULTS if not ok]
print("\n==== SUMMARY: %d/%d passed ====" %
      (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILURES:")
    for n in fails:
        print("  - " + n)
    sys.exit(1)
print("ALL PASS")
