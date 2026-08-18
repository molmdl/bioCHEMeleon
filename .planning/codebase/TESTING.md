# Testing Patterns

**Analysis Date:** 2026-08-18

## Test Framework

**Runner:**
- Python stdlib `unittest` (NO pytest, NO external test deps — `spec.md` forbids unapproved libs; `unittest` ships with Python 3.6.9).
- No config file (`unittest` uses CLI args + the `tests/` package layout).

**Assertion Library:**
- `unittest.TestCase` methods (`assertEqual`, `assertNotEqual`, `assertIn`, `assertIsNone`, `assertIsNotNone`, `assertRaises`, `assertGreater`, `assertGreaterEqual`, `assertLess`, `assertLessEqual`, `assertIsInstance`, `assertAlmostEqual`, `assertTrue`, `assertFalse`, `assertNotIsInstance`).
- `unittest.mock.MagicMock` (stdlib) for the `pymol`/`pymol.Qt` stub + callback verification.

**Run Commands (from repo root):**
```bash
# All tests (discovers tests/test_*.py):
python3.6 -m unittest discover -s tests -v          # 334 tests, ~0.06s

# Single module (the AGENTS.md-cited command + one per module):
python3.6 -m unittest tests.test_setup_state -v     # 125 tests
python3.6 -m unittest tests.test_registry -v        # 102 tests
python3.6 -m unittest tests.test_persistence -v     # 37 tests
python3.6 -m unittest tests.test_generators -v      # 35 tests
python3.6 -m unittest tests.test_game_controller -v # 35 tests

# As a script (each test file ends with):
#   if __name__ == '__main__':
#       unittest.main(verbosity=2)
python3.6 tests/test_setup_state.py

# Syntax check (NOT imports — py_compile passes for cmd-coupled modules
# even in WSL where `from pymol import cmd` would fail at import time):
python3.6 -m py_compile biochemeleon/*.py
```

**Test count note:** `AGENTS.md` says "48 tests, currently green" — that count predates Phases 3–11. The current suite is **334 tests across 5 modules** (verified 2026-08-18: `Ran 334 tests in 0.063s OK`). Per-module: `test_setup_state.py`=125, `test_registry.py`=102, `test_persistence.py`=37, `test_generators.py`=35, `test_game_controller.py`=35.

## Test File Organization

**Location:**
- Separate `tests/` directory at repo root (NOT co-located with source). Layout:
  ```
  tests/
  ├── __init__.py                  # empty (makes tests/ a package)
  ├── test_setup_state.py          # ↔ biochemeleon/setup_state.py (pure)
  ├── test_registry.py             # ↔ biochemeleon/registry.py (pure)
  ├── test_generators.py           # ↔ biochemeleon/generators.py (pure)
  ├── test_persistence.py          # ↔ biochemeleon/persistence.py (pure)
  └── test_game_controller.py      # ↔ biochemeleon/game.py (cmd-coupled, logic-only)
  ```

**Naming:**
- `test_<module_under_test>.py` — mirrors the module. One test file per source module.
- Test classes: `Test<Feature>` (e.g. `TestHiderRecord`, `TestHiderRegistryCore`, `TestBuildBcmDict`, `TestOnPickFragment`).
- Test methods: `test_<behavior>` (e.g. `test_zero_atoms`, `test_idempotent_on_valid`, `test_reconstruct_clears_existing`, `test_fragment_real_trace_miss`).

**Structure:**
- Each test file opens with a module docstring stating: what it tests, the purity tier, the stub-pattern pointer (lines referencing `test_setup_state.py:13-15` / `test_registry.py:19-21`), and the run command. See `tests/test_registry.py:1-11`, `tests/test_generators.py:1-17`, `tests/test_persistence.py:1-11`.
- Each file ends with `if __name__ == '__main__': unittest.main(verbosity=2)`.

## The MagicMock Stub Pattern (CRITICAL — required for every WSL-runnable test file)

`biochemeleon/__init__.py` does `from pymol.Qt import QtCore, QtGui, QtWidgets` and `from pymol import cmd` at MODULE LEVEL (line 156-157). So importing ANY `biochemeleon.*` module triggers `__init__.py`, which fails in WSL (no PyMOL installed). The fix: stub `pymol` + `pymol.Qt` via `sys.modules` BEFORE importing `biochemeleon.*`.

**The canonical pattern (copy verbatim into every new WSL test file):**
```python
import os
import sys
import unittest
from unittest.mock import MagicMock

# Stub pymol so importing biochemeleon.* (whose __init__.py does
# `from pymol.Qt import ...`) doesn't fail in WSL without PyMOL.
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()

# Ensure repo root is on sys.path when run as a script
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from biochemeleon.<module> import <names>
```

**Where it appears:** `tests/test_setup_state.py:13-15` (the origin, cited by AGENTS.md), `tests/test_registry.py:19-21`, `tests/test_generators.py:26-28`, `tests/test_persistence.py:24-26`, `tests/test_game_controller.py:24-26`.

**Why:** PyMOL is not importable in WSL `python3.6` (it lives in the Windows conda env). The stub puts a `MagicMock` in `sys.modules['pymol']` and `sys.modules['pymol.Qt']` so `from pymol.Qt import ...` resolves to mock objects (attribute access returns more mocks — no `ImportError`). The `if 'pymol' not in sys.modules` guard is defensive: if a real PyMOL is present (Windows), don't clobber it.

**Keep this stub pattern when adding WSL-runnable tests.** It is the load-bearing trick that makes the pure layer + game.py-logic testable from WSL.

## What's WSL-Testable vs. What's NOT

This split is the central testing constraint. It follows the purity tiers in `CONVENTIONS.md`.

**WSL-runnable unit tests (pure layer — NO `from pymol`):**
- `biochemeleon/setup_state.py` → `tests/test_setup_state.py` (125 tests).
- `biochemeleon/registry.py` → `tests/test_registry.py` (102 tests).
- `biochemeleon/generators.py` → `tests/test_generators.py` (35 tests).
- `biochemeleon/persistence.py` → `tests/test_persistence.py` (37 tests).
- `biochemeleon/game.py` → `tests/test_game_controller.py` (35 tests) — see "Testing cmd-coupled logic via mocked cmd" below.

**NOT WSL-runnable (cmd-coupled at runtime OR Qt — verified by smoke tests / human checkpoints):**
- `biochemeleon/demos.py`, `biochemeleon/backup.py`, `biochemeleon/mutation.py`, `biochemeleon/wizard.py` — `from pymol import cmd` at runtime; `py_compile` passes (syntax only) but importing runs PyMOL code.
- `biochemeleon/__init__.py`, `biochemeleon/gui_setup.py`, `biochemeleon/gui_game.py` — `from pymol.Qt import ...`; need a real display.
- Verified instead by headless smoke tests (`smoke/phase<N>_smoke.py`) run via Windows PyMOL, or human-verify checkpoints for GUI/Qt paths.

## Testing cmd-Coupled Logic via Mocked cmd (`test_game_controller.py`)

`biochemeleon/game.py` has `from pymol import cmd` at module top, but the sys.modules stub makes `cmd` a `MagicMock`. The tests exercise the play-loop LOGIC (on_pick / win / hint / reveal / _remaining / _mark_found) WITHOUT calling `start()` (which needs real `cmd.identify` returning a real id list).

**The pattern:**
```python
from biochemeleon import game
from biochemeleon.game import GameController
from biochemeleon.registry import HIDER_STATUS_HIDDEN, HIDER_STATUS_FOUND

class TestGameControllerOnPick(unittest.TestCase):
    def setUp(self):
        """Build a fresh GameController with a clean mock cmd history."""
        self.gc = GameController('1ubq')
        # Reset mock cmd call history (shared via sys.modules) so call_count
        # assertions are isolated per test.
        game.cmd.reset_mock()

    def test_found(self):
        self.gc.registry.register('1ubq', 100, 'spheres')   # MANUALLY populate
        log = MagicMock(); rem = MagicMock(); win_cb = MagicMock()
        self.gc.set_callbacks(log, rem, win_cb)
        self.gc._start_time = 1000.0

        self.gc.on_pick(100)                                  # exercise logic

        rec = self.gc.registry.get('1ubq', 100)
        self.assertEqual(rec.status, HIDER_STATUS_FOUND)
        game.cmd.color.assert_called_once_with('green', "1ubq and id 100")
        rem.assert_called_once_with(0)
        win_cb.assert_called_once()
```

**Key rules (from `tests/test_game_controller.py:1-16` docstring):**
- Construct `GameController('1ubq')` WITHOUT calling `start()` — `start()` needs real `cmd.identify` (the mock returns a `MagicMock` that fails `assert len(ids) == 1` in `mutation`).
- MANUALLY populate the registry via `self.gc.registry.register(obj, id, rep, ...)`.
- `game.cmd.reset_mock()` in `setUp` isolates `call_count` assertions per test (the mock is shared via `sys.modules`).
- `game.cmd.count_atoms.return_value = 5` when a test needs the `> 0` gate to pass (a `MagicMock` default returns `NotImplemented` for `>`, breaking the gate). See `tests/test_game_controller.py:514`.
- Inspect `game.cmd.color.call_args[0][0]` / `[0][1]` to assert the color + selection string (NOT just `assert_called_once`).

## Test Structure

**Suite Organization (real pattern from `tests/test_registry.py`):**
```python
class TestHiderRegistryQueries(unittest.TestCase):
    """Test HiderRegistry by_rep / counts_by_rep / mark_found queries.

    These are the per-rep counting + status-update methods needed for
    success criterion 3 (per-rep counts) and Phase 4's click-to-find
    handler (mark_found). Pure functions over the registry's in-memory
    records.
    """

    def setUp(self):
        """Build a registry with 3 hiders across 2 reps.

        Fixture: ('1ubq', 1, 'spheres'), ('1ubq', 2, 'sticks'),
                 ('1ubq', 3, 'spheres')
        Keep direct references for insertion-order + status assertions.
        """
        self.reg = HiderRegistry()
        self.r1 = self.reg.register('1ubq', 1, 'spheres')
        self.r2 = self.reg.register('1ubq', 2, 'sticks')
        self.r3 = self.reg.register('1ubq', 3, 'spheres')

    def test_by_rep_returns_matching(self):
        """by_rep('spheres') returns [r1, r3] in insertion order."""
        out = self.reg.by_rep('spheres')
        self.assertEqual(out, [self.r1, self.r3])
```

**Patterns:**
- **Setup:** `setUp` builds a fresh `HiderRegistry()` / `GameController('1ubq')` per test; no shared state. Class docstring states the fixture; `setUp` docstring lists the exact records. See `tests/test_registry.py:299-310`, `tests/test_game_controller.py:45-51`.
- **Teardown:** Rare — `addCleanup(shutil.rmtree, tmpdir, True)` in the `.bcmz` tempfile tests (`tests/test_persistence.py:368, 378`). No `tearDown` otherwise.
- **subTest for parametric cases:** `for bad in ('', 'surface', 'mesh', 'dots', 'Spheres', 'LINES'): with self.subTest(rep=bad): with self.assertRaises(ValueError): HiderRecord(1, '1ubq', bad)` — see `tests/test_registry.py:66-70`. Also `for rep in GAME_REPS: with self.subTest(rep=rep): ...` (`tests/test_registry.py:74-77`, `:340-342`).
- **Assertion messages:** `msg=` kwarg for non-obvious assertions — `self.assertEqual(..., msg="Entry %r has wrong keys: %r" % (did, set(entry.keys())))` (`tests/test_setup_state.py:124-125`). Critical for debugging the 100-seed loops.
- **Seed-based determinism:** pure generators take a `seed` param; tests assert `seed=42` equals `seed=42` and differs from `seed=99` (`tests/test_generators.py:67-79`). `randomize_state(seed=...)` is deterministic; tests use `for seed in range(100):` to probe distribution (`tests/test_setup_state.py:450-478`).

## Mocking

**Framework:** `unittest.mock.MagicMock` (stdlib). No `unittest.mock.patch` decorator usage — stubs are set up imperatively at module load (the `sys.modules` pattern) and in `setUp`.

**Patterns:**

```python
# (1) Module-level pymol stub (the load-bearing pattern — see above):
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()

# (2) Callback mocks per-test:
log = MagicMock()
rem = MagicMock()
win_cb = MagicMock()
self.gc.set_callbacks(log, rem, win_cb)
self.gc.on_pick(100)
log.assert_called_once_with("Found one!")
rem.assert_called_once_with(0)
win_cb.assert_called_once()

# (3) Mocked cmd return value + call-arg inspection:
game.cmd.count_atoms.return_value = 5            # gate `> 0` passes
game.cmd.color.assert_called_once_with('green', "1ubq and id 100")
sele = game.cmd.color.call_args[0][1]
self.assertIn('segi GAME and resi 3-3', sele)
self.assertNotIn('id 100', sele)

# (4) MockController stand-in for persistence tests (avoids real GameController):
class MockController(object):
    def __init__(self, target_obj='1ubq', started=True, reveal_count=1,
                 hint_count=2, found_color='green', start_time=None):
        self.target_obj = target_obj
        self.registry = HiderRegistry()
        self._started = started
        self._reveal_count = reveal_count
        # ... only the attrs build_bcm_dict reads
```

**What to Mock:**
- `pymol` + `pymol.Qt` (always, in every test file — via `sys.modules`).
- GUI callbacks (`on_log`, `on_remaining_changed`, `on_win`, `on_counts_changed`) — pass `MagicMock()` and assert call args.
- `cmd.color`, `cmd.count_atoms`, `cmd.delete`, `cmd.create` — inspected via `game.cmd.<method>.call_args` / `.assert_called_once_with(...)`. Set `return_value` when the code reads a return (e.g. `count_atoms`).

**What NOT to Mock:**
- `HiderRegistry` / `HiderRecord` — these are the pure unit under test; instantiate them for real and assert their state.
- `setup_state` constants (`GAME_REPS`, `DEMO_MANIFEST`, `DEFAULTS`) — import and assert against the real values (these ARE the contracts).
- `persistence` functions (`build_bcm_dict`, `parse_bcm_dict`, `apply_bcm_dict`, `write_bcmz`, `read_bcmz`) — exercise them for real with a `MockController` + tempfile.

## Fixtures and Factories

**Test Data:**
- No shared fixtures file. Each test class builds state inline in `setUp` or per-method. Fixtures are small and explicit (e.g. 3 records across 2 reps).
- Helper methods for repeated construction:
  ```python
  # tests/test_registry.py: TestReconcileFromBcm._rebuilt
  def _rebuilt(self, keys=None):
      """Build a sentinel-rebuilt registry with the given (object, id) keys.
      Defaults to [('o', 1), ('o', 2), ('o', 3)] — the canonical 3-sentinel
      fixture mirroring the plan's behavior spec."""
      if keys is None:
          keys = [('o', 1), ('o', 2), ('o', 3)]
      reg = HiderRegistry()
      reg.reconstruct_from_sentinels(lambda: keys)
      return reg

  # tests/test_game_controller.py: TestOnPickFragment._register_fragment
  def _register_fragment(self, hider_id=100, endpoint_resvs=(...), ...):
      return self.gc.registry.register(obj, hider_id, rep, status=status,
                                       endpoint_resvs=endpoint_resvs)
  ```
- The `MockController` class (`tests/test_persistence.py:43-60`) is the closest thing to a factory — a minimal stand-in for `GameController` with only the attrs `build_bcm_dict` reads. Lives in the test file (not a separate `conftest`/`fixtures` module).
- `_sample_setup()` (`tests/test_persistence.py:63-71`) returns a representative `gui_setup.collect_state()` dict.

**Location:**
- All fixtures/helpers live IN the test files (no `tests/conftest.py`, no `tests/fixtures/`). Keeps each test file self-contained.

## Coverage

**Requirements:** None enforced numerically (no `coverage.py`, no CI threshold). Coverage is STRUCTURAL by module tier:
- Pure layer (`setup_state`, `registry`, `generators`, `persistence`): high unit-test coverage — every public function + class has tests; edge cases (empty/None/zero/bounds) are explicitly probed.
- `game.py` logic (on_pick / win / hint / reveal / _remaining / _mark_found / counters / cleanup-reset): covered by `test_game_controller.py` via mocked cmd.
- `game.py` cmd paths (`start`, `import_state`), `backup.py`, `mutation.py`, `demos.py`, `wizard.py`: covered by headless smoke tests (Windows), NOT WSL unit tests.
- GUI (`__init__.py`, `gui_setup.py`, `gui_game.py`): human-verify checkpoints (the Qt paths can't run in WSL).

**View Coverage:**
```bash
# (Not configured — no coverage.py in the stack. If added later:)
python3.6 -m coverage run -m unittest discover -s tests
python3.6 -m coverage report -m
```

## Test Types

**Unit Tests:**
- The 334-test WSL suite. Scope: one pure function / class method at a time. Examples: `test_zero_atoms` (one `hider_count_cap` call), `test_reconstruct_clears_existing` (one `reconstruct_from_sentinels` call). Fast (0.06s total).

**Integration Tests (WSL-tier):**
- Round-trip tests that chain multiple units WITHOUT PyMOL:
  - `tests/test_persistence.py::TestBcmRoundTrip` — `build_bcm_dict` → JSON dumps → `parse_bcm_dict` → assert scalars preserved.
  - `tests/test_persistence.py::TestBuildApplyRoundTrip` — `build_bcm_dict` (ctrl1) → `reconstruct_from_sentinels` (ctrl2) → `apply_bcm_dict` (ctrl2) → assert ctrl2 state + registry records match ctrl1.
  - `tests/test_registry.py::TestReconcileFromBcm::test_round_trip_to_dict_reconstruct_reconcile` — register → `to_dict` → `reconstruct_from_sentinels` (fake) → `reconcile_with_bcm(to_dict['hiders'])` → records match.
  - `tests/test_game_controller.py` — `GameController` + `HiderRegistry` + mocked `cmd` exercising the play loop end-to-end (miss / found / already-found / win / hint / reveal).

**Smoke Tests (NOT in `tests/` — in `smoke/`):**
- Headless PyMOL scripts run via Windows PyMOL: `smoke/phase<N>_smoke.py` (phase3, phase4, phase4_1, phase5, phase6, phase7, phase8, phase9, phase10, phase11) + `smoke/diag_<topic>.py` diagnostics + `smoke/verify_<topic>.py` verification.
- Run pattern (from `AGENTS.md` Environment):
  ```bash
  bash wsl2win_cp.sh                          # stage biochemeleon/ -> tmp/bioCHEMeleon/
  mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/phase3_smoke.py tmp/bioCHEMeleon/smoke/
  cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py" 2>&1 | tail -50
  # exit 0 = clean; nonzero = crash.
  ```
- These verify the cmd-coupled layer at the real PyMOL 2.5.0 runtime tier (the WSL unit tests cannot). The Phase 3 smoke (`smoke/phase3_smoke.py`) is the canonical "ALL PASSED, exit 0" reference and resolved the research UNVERIFIED flags (see `.planning/research/PITFALLS.md` "Phase 3 — Resolved Research Flags").

**E2E / GUI Tests:**
- Not automated. GUI/Qt paths (`pymol.Qt.*` at runtime) need a real display — a WSL agent cannot run them. They are human-verify checkpoints (the developer opens the plugin via `setenv.bat` → `pymol` and walks the Setup/Game tabs).

## Common Patterns

**Async Testing (N/A):**
- No async/await in the codebase. The async large-demo fetch (`_resolve_large_demo` in `__init__.py`) uses a `threading.Thread` worker + `QTimer.singleShot` drain — tested only via the human-verify / smoke path, NOT WSL unit tests (it's Qt+cmd-coupled).

**Error Testing:**
```python
# ValueError for invalid rep (caller bug):
with self.assertRaises(ValueError):
    HiderRecord(1, '1ubq', 'surface')

# KeyError for duplicate (object, id):
with self.assertRaises(KeyError):
    reg.register('1ubq', 1, 'spheres')
    reg.register('1ubq', 1, 'sticks')

# AttributeError from __slots__ (unknown attribute):
with self.assertRaises(AttributeError):
    rec.unknown_field = 42

# ValueError from persistence parse (wrong magic / unsupported version):
with self.assertRaises(ValueError):
    parse_bcm_dict(json.dumps({'magic': 'OTHER', 'version': 1}))
with self.assertRaises(ValueError):
    parse_bcm_dict('not json')
```

**Backward-Compat Testing (a recurring theme — Phase 11 added alt-conf fields):**
```python
# A Phase 8 sidecar (no alt-conf fields) loads on Phase 11 code with defaults:
d = {'version': 1, 'hiders': [
    {'id': 100, 'object': '1ubq', 'rep': 'spheres', 'status': 'hidden'}]}
reg = HiderRegistry.from_dict(d)
rec = reg.get('1ubq', 100)
self.assertFalse(rec.is_altconf)        # default
self.assertIsNone(rec.endpoint_resvs)   # default
self.assertEqual(rec.alt_tag, '')       # default

# to_dict omits defaults (compact sidecar; backward-compatible):
rec = HiderRecord(100, '1ubq', 'spheres')
d = rec.to_dict()
self.assertNotIn('is_altconf', d)
self.assertNotIn('endpoint_resvs', d)
self.assertNotIn('alt_tag', d)
```

**No-version-bump contract (Phase 11):**
```python
# build_bcm_dict always emits version == 1 for BOTH alt-conf and non-alt-conf:
mc_alt = MockController()
mc_alt.registry.register('1ubq', 100, 'cartoon', is_altconf=True,
                         endpoint_resvs=(2, 4), alt_tag='B')
d_alt = build_bcm_dict(mc_alt, _sample_setup(), 'checkpoint')
self.assertEqual(d_alt['version'], 1)   # NO version bump (research §8)
```

**List ↔ Tuple Coercion (JSON has no tuples):**
```python
# endpoint_resvs serializes as a list; reconcile coerces back to a tuple
# so `rv1 < resv < rv2` works (lists fail `<` in py3):
d2 = parse_bcm_dict(json.dumps(d))
self.assertEqual(d2['registry']['hiders'][0]['endpoint_resvs'], [2, 4])  # list
self.assertIsInstance(d2['registry']['hiders'][0]['endpoint_resvs'], list)
apply_bcm_dict(mc2, d2)
rec = mc2.registry.get('1ubq', 100)
self.assertIsInstance(rec.endpoint_resvs, tuple)   # coerced
self.assertEqual(rec.endpoint_resvs, (2, 4))
```

**When adding a new test file:**
1. Copy the MagicMock stub block (the 3-line `sys.modules['pymol']` / `['pymol.Qt']` guard + `sys.path.insert`).
2. Add a module docstring stating the purity tier, the stub-pattern pointer (cite the line numbers in `test_setup_state.py` / `test_registry.py`), and the run command.
3. One `Test<Feature>` class per logical group; `setUp` for shared fixture; `test_<behavior>` methods with behavior-stating docstrings.
4. End with `if __name__ == '__main__': unittest.main(verbosity=2)`.
5. Add the file to the "per-module" run commands list above.

---

*Testing analysis: 2026-08-18*
