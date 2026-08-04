---
phase: 02-setup-tab-configuration-bundled-demos
verified: 2026-08-05T04:00:00Z
status: passed
score: 4/4 must-haves verified
human_smoke_test: 02-04-APPROVED (2026-08-05)
verification_tier: WSL code-level (PyMOL/Qt runtime behavior covered by human smoke test 02-04)
---

# Phase 2: Setup Tab Configuration & Bundled Demos — Verification Report

**Phase Goal:** The user can fully configure every game parameter in the Setup tab and load bundled demo molecules — the entire pre-game configuration experience.
**Verified:** 2026-08-05
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (the 4 Phase-2 success criteria)

| # | Truth | Status | Evidence (code-level) |
|---|-------|--------|----------------------|
| 1 | The user can choose a target via the object selector: a loaded object, a PDB fetch, or a bundled demo (with a category sub-menu) | ✓ VERIFIED | `gui_setup.py:72-75` — `mode_combo` with 3 items (`"Loaded object"`,`"Fetch from PDB"`,`"Bundled demo"`) carrying userData `loaded`/`fetch`/`demo`. `gui_setup.py:78-133` — `target_stack` QStackedWidget with 3 pages: p0=`PyMOLObjectCombo`+refresh btn (lines 80-87), p1=`pdb_edit`+`fetch_btn`+`pool_list` QListWidget (lines 89-121), p2=`demo_combo` populated from `DEMO_MANIFEST` (lines 122-129). `demo_combo` items render `"{category} — {id} ({difficulty})"` so the category metadata is surfaced per-entry (6 entries from `DEMO_MANIFEST`). `_on_mode_changed` (line 221) swaps the stack page. `PyMOLObjectCombo.showPopup` (lines 41-47) refreshes the loaded-objects list on every popup. Human smoke test 02-04 confirmed the runtime click-through. |
| 2 | The user can set the hider count (capped to a sane max), toggle "lock current scene", assign per-rep hider counts (or leave them random), and toggle difficulty | ✓ VERIFIED | **Cap:** `gui_setup.py:145-148` `hider_spin` range [1,50]; `_on_target_changed` (lines 224-246) calls `hider_count_cap(cmd.count_atoms(obj))` (line 238) and `setMaximum(max(1,cap))` (line 241); clamps current value down if over cap (line 242-243). `current_target_object` (lines 323-338) returns the non-empty combo text WITHOUT a membership re-query (Gap-1 fix). **Lock scene:** `lock_scene_cb` (lines 149-151) + `_on_lock_scene_toggled` (lines 265-284) + `_sync_reps_from_scene` (lines 291-301) which calls `get_active_reps(obj)` and locks per-rep checkboxes to the scene's active reps. **Per-rep:** `for rep in GAME_REPS` (line 156) builds 5 rows (cb+spin+label); `_on_rep_toggled` flips enabled + 'random' label (lines 286-289); `_recompute_per_rep_maxes` (lines 303-321) bounds each per-rep max to `hider_count - sum(others)` (Gap-2 UI). `validate_state` per_rep-sum clamp at `setup_state.py:302-313` (Gap-2 pure). **Difficulty:** `diff_easy_cb` (lines 178-181). |
| 3 | The user can Reset to defaults, Randomize the params, Save Setup to a file, and Load Setup from a file | ✓ VERIFIED | **Reset:** `reset_btn` (line 187) → `lambda: self.apply_state(DEFAULTS)` (line 208). **Randomize:** `random_btn` (line 188) → `_randomize` (lines 513-535) calls `randomize_state(atom_count=cmd.count_atoms(obj), lock_source=self.lock_source_cb.isChecked(), locked_state=self.collect_state() if lock_src, pdb_pool=self._pool_list())` then `apply_state(result)`. **Save:** `save_btn` (line 189) → `_save_setup` (lines 537-552) uses `QFileDialog.getSaveFileName` + `json.dump(self.collect_state(), f, indent=2)`. **Load:** `load_btn` (line 190) → `_load_setup` (lines 554-579) uses `QFileDialog.getOpenFileName` + `json.load` + `validate_state(state, atom_count=...)` + `apply_state`. **Gap closures:** `lock_source_cb` (lines 136-139) preserves target on Randomize; `pool_list` QListWidget + 5 buttons (Add/Edit/Remove/Use bundled pool/Choose random, lines 103-120); `_choose_random_from_pool` (lines 404-421) uses `random.choice(pool)` and switches to fetch mode (line 420). Human smoke test 02-04 confirmed Save/Load round-trip and Reset/Randomize. |
| 4 | Bundled small demo PDBs (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3) load and render in the viewer with sources cited | ✓ VERIFIED | **Files:** 6 PDBs present in `biochemeleon/data/demos/` — `1znf.pdb` (HEADER=1, ATOM=15318), `1xdn.pdb` (HEADER=1, ATOM=2095), `5e54.pdb` (HEADER=1, ATOM=2826), `1k8p.pdb` (HEADER=1, ATOM=428), `2qbz.pdb` (HEADER=1, ATOM=3263), `4wb3.pdb` (HEADER=1, ATOM=1670) — all valid PDB format. **Manifest:** `setup_state.py:29-36` `DEMO_MANIFEST` has exactly these 6 IDs with `category`/`type`/`difficulty`/`file` metadata. **Loader:** `demos.py:114-137` `load_demo(demo_id)` resolves path via `os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])`, existence-checks, runs through `to_windows_path(path)`, then `cmd.load(win_path, object=obj_name, zoom=1)`. **Sources:** `biochemeleon/data/demos/SOURCES.md` (64 lines) cites all 6 with PDB ID + DOI (`https://doi.org/10.2210/pdbXXXX/pdb`) + title + authors + publication + method + notes, plus a CC0 1.0 license section. Human smoke test 02-04 confirmed all 6 demos load + render in Windows PyMOL. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `biochemeleon/setup_state.py` | Pure state model: DEFAULTS 11 keys, GAME_REPS 5, DEMO_MANIFEST 6, PDB_POOL, hider_count_cap, randomize_state (lock_source/locked_state/pdb_pool), validate_state (per_rep-sum clamp), _validate_pdb_code 4-char; NO pymol/Qt imports | ✓ VERIFIED | 319 lines (min 60). Exists, substantive, exported. Purity confirmed — only `import random as _random` and `import copy as _copy` (lines 14-15); the only "pymol" mention is in the docstring (line 5), no actual import. 11 DEFAULTS keys verified via stubbed import: `['format','target_mode','selected_object','pdb_code','demo_id','hider_count','lock_scene','per_rep','difficulty_easy','lock_source','pdb_pool']`. GAME_REPS=5, DEMO_MANIFEST=6 keys, PDB_POOL=33 unique entries. `hider_count_cap(212)=4`, `(3779)=50`, `(0)=1`, `(None)=1` — formula `max(1, min(50, atom_count // 50))`. |
| `biochemeleon/demos.py` | cmd-coupled helpers: to_windows_path, list_loaded_molecule_objects, fetch_pdb (async_=0), get_active_reps (rep selector), load_demo (cmd.load via to_windows_path) | ✓ VERIFIED | 137 lines (min 50). Exists, substantive, exported. `from pymol import cmd` (line 17) + `from .setup_state import GAME_REPS, DEMO_MANIFEST` (line 19). `fetch_pdb` uses `cmd.fetch(code, name=obj_name, async_=0)` (line 82). `get_active_reps` uses `cmd.count_atoms("{} and rep {}".format(obj, rep))` (line 105). `load_demo` uses `to_windows_path(path)` + `cmd.load(win_path, object=obj_name, zoom=1)` (lines 131-134). |
| `biochemeleon/gui_setup.py` | Full SetupTab: PyMOLObjectCombo, 3-mode QStackedWidget, hider_spin capped, lock_scene_cb, 5 per-rep rows, diff_easy_cb, 4 action buttons, lock_source_cb, pool_list QListWidget + 5 buttons, _choose_random_from_pool, collect_state/apply_state round-trip, _save_setup/_load_setup JSON | ✓ VERIFIED | 579 lines (min 150). Exists, substantive, exported (`class SetupTab` line 50, `class PyMOLObjectCombo` line 30). Imports `DEFAULTS, SETUP_FORMAT, GAME_REPS, DEMO_MANIFEST, PDB_POOL, _validate_pdb_code, hider_count_cap, randomize_state, validate_state` from `.setup_state` (lines 20-24) and `load_demo, list_loaded_molecule_objects, fetch_pdb, get_active_reps` from `.demos` (lines 25-27). All required widgets present (see truth table for line refs). |
| `biochemeleon/data/demos/*.pdb` (6 files) | 6 bundled demo PDBs, valid format | ✓ VERIFIED | 6 files, all with HEADER=1 and ATOM records (see truth #4 for counts). |
| `biochemeleon/data/demos/SOURCES.md` | Citations for all 6 demos (DEMO-01) | ✓ VERIFIED | 64 lines. Cites all 6 PDB IDs with DOI + title + authors + publication + method + notes + CC0 license. |
| `tests/test_setup_state.py` | Unit tests for pure state model (WSL-runnable) | ✓ VERIFIED | 469 lines (min 80). 13 test classes, 90 `def test_` methods. All 90 pass under `python3.6 -m unittest tests.test_setup_state -v`. |
| `biochemeleon/__init__.py` | PluginDialog, modeless .show(), 2 tabs (Setup + Game status) — UNCHANGED from Phase 1 | ✓ VERIFIED | 66 lines. `dialog = None` module-level singleton (line 5). `__init_plugin__` (line 8) registers menu via `addmenuitemqt`. `run_plugin_gui` uses `dialog.show()` (line 30, modeless — NO `.exec_()`). `PluginDialog` (line 38) builds `QTabWidget` with SetupTab + GameTab (lines 51-62). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `biochemeleon/demos.py` | `biochemeleon/setup_state.py` | `from .setup_state import GAME_REPS, DEMO_MANIFEST` | ✓ WIRED | demos.py:19 |
| `biochemeleon/gui_setup.py` | `biochemeleon/setup_state.py` | `from .setup_state import DEFAULTS, SETUP_FORMAT, GAME_REPS, DEMO_MANIFEST, PDB_POOL, _validate_pdb_code, hider_count_cap, randomize_state, validate_state` | ✓ WIRED | gui_setup.py:20-24 — all 9 names used downstream |
| `biochemeleon/gui_setup.py` | `biochemeleon/demos.py` | `from .demos import load_demo, list_loaded_molecule_objects, fetch_pdb, get_active_reps` | ✓ WIRED | gui_setup.py:25-27 — all 4 used: `fetch_pdb` in `_on_fetch`, `list_loaded_molecule_objects` in `PyMOLObjectCombo.showPopup`, `get_active_reps` in `_sync_reps_from_scene`, `load_demo` (not yet called from a UI slot — Phase 4 Start will use it; but the import is present and the symbol is referenced) |
| `demos.py:load_demo` | `cmd.load` | `to_windows_path(os.path.join(dirname(__file__), 'data', 'demos', meta['file']))` | ✓ WIRED | demos.py:128-134 |
| `demos.py:get_active_reps` | `cmd.count_atoms` | `"{} and rep {}".format(obj, rep)` selector | ✓ WIRED | demos.py:103-108 |
| `demos.py:fetch_pdb` | `cmd.fetch` | `cmd.fetch(code, name=obj_name, async_=0)` (sync) | ✓ WIRED | demos.py:82 |
| `gui_setup.py:SetupTab._on_target_changed` | `hider_count_cap` + `cmd.count_atoms` | `cap = hider_count_cap(cmd.count_atoms(obj)); self.hider_spin.setMaximum(max(1,cap))` | ✓ WIRED | gui_setup.py:238,241 |
| `gui_setup.py:SetupTab._sync_reps_from_scene` | `get_active_reps` | `active = get_active_reps(obj)` then lock per-rep rows | ✓ WIRED | gui_setup.py:295-301 |
| `gui_setup.py:SetupTab._recompute_per_rep_maxes` | per-rep sum bound (Gap-2 UI) | `spin.setMaximum(max(0, total - others))` | ✓ WIRED | gui_setup.py:303-321 |
| `gui_setup.py:SetupTab._randomize` | `randomize_state` | `randomize_state(seed=None, atom_count=..., lock_source=..., locked_state=..., pdb_pool=...)` + `apply_state(result)` | ✓ WIRED | gui_setup.py:530-535 |
| `gui_setup.py:SetupTab._save_setup` | `json.dump` | `QFileDialog.getSaveFileName` + `json.dump(self.collect_state(), f, indent=2)` | ✓ WIRED | gui_setup.py:539,548 |
| `gui_setup.py:SetupTab._load_setup` | `json.load` + `validate_state` | `QFileDialog.getOpenFileName` + `json.load` + `validate_state(state, atom_count=atom_count)` + `apply_state(validated)` | ✓ WIRED | gui_setup.py:558,565,578-579 |
| `gui_setup.py:SetupTab._choose_random_from_pool` | `random.choice` + fetch-mode switch | `code = random.choice(pool); self.mode_combo.setCurrentIndex(1); self.pdb_edit.setText(code)` | ✓ WIRED | gui_setup.py:418-421 |
| `gui_setup.py:SetupTab.collect_state` ↔ `apply_state` | JSON round-trip | both use the same 11-key dict shape (format, target_mode, selected_object, pdb_code, demo_id, hider_count, lock_scene, per_rep, difficulty_easy, lock_source, pdb_pool) | ✓ WIRED | gui_setup.py:432-450 (collect) and 452-510 (apply) |
| `biochemeleon/__init__.py` | `gui_setup.SetupTab` + `gui_game.GameTab` | `from .gui_setup import SetupTab; from .gui_game import GameTab` + `addTab` | ✓ WIRED | __init__.py:55-62 |
| `setup_state.py` purity | (no pymol/Qt) | only `import random`, `import copy` | ✓ WIRED (pure) | setup_state.py:14-15 — no `from pymol` / `import pymol` |

### Requirements Coverage

| Requirement | Status | Satisfying code | Blocking issue |
|-------------|--------|-----------------|----------------|
| SETUP-01 (Setup window opens, QTabWidget Setup+Game tabs) | ✓ SATISFIED | `__init__.py:38-66` `PluginDialog` with `QTabWidget` + SetupTab + GameTab | — |
| SETUP-02 (Object selector: loaded / fetch / demo with category sub-menu) | ✓ SATISFIED | `gui_setup.py:72-133` mode_combo (3 modes) + QStackedWidget (3 pages) + demo_combo with `"{category} — {id} ({difficulty})"` labels (category surfaced per-entry) | — |
| SETUP-03 (Hider count capped to reasonable max vs atom count) | ✓ SATISFIED | `gui_setup.py:145-148,224-246` hider_spin + `_on_target_changed` + `hider_count_cap`; `setup_state.py:152-163` cap formula | — |
| SETUP-04 (Lock current scene checkbox; detect reps from scene) | ✓ SATISFIED | `gui_setup.py:149-151,265-301` `lock_scene_cb` + `_on_lock_scene_toggled` + `_sync_reps_from_scene` + `demos.py:90-109` `get_active_reps` | — |
| SETUP-05 (Per-rep hider list with checkboxes + count setters; unchecked = random) | ✓ SATISFIED | `gui_setup.py:152-172` 5 per-rep rows via `for rep in GAME_REPS`; `_on_rep_toggled` flips spinbox enabled + 'random' label; `_recompute_per_rep_maxes` bounds sum | — |
| SETUP-06 (Difficulty toggle: easy=per-rep remaining, hard=total only) | ✓ SATISFIED | `gui_setup.py:176-182` `diff_easy_cb` ("Easy: show remaining hiders per representation (uncheck for Hard: total only)") | — |
| DEMO-01 (Bundle 6 small demo PDBs with sources cited) | ✓ SATISFIED | `biochemeleon/data/demos/{1znf,1xdn,5e54,1k8p,2qbz,4wb3}.pdb` (6 files, all HEADER+ATOM valid) + `SOURCES.md` (all 6 cited with DOI) + `setup_state.py:29-36` `DEMO_MANIFEST` | — |
| BTN-01 (Reset — restore defaults) | ✓ SATISFIED | `gui_setup.py:187,208` `reset_btn` → `apply_state(DEFAULTS)` | — |
| BTN-02 (Randomize — randomize setup params) | ✓ SATISFIED | `gui_setup.py:188,209,513-535` `random_btn` → `_randomize` → `randomize_state` + `apply_state` (with `lock_source` + `pdb_pool` params) | — |
| BTN-03 (Save Setup to file) | ✓ SATISFIED | `gui_setup.py:189,210,537-552` `save_btn` → `_save_setup` → `QFileDialog.getSaveFileName` + `json.dump` | — |
| BTN-04 (Load Setup from file) | ✓ SATISFIED | `gui_setup.py:190,211,554-579` `load_btn` → `_load_setup` → `QFileDialog.getOpenFileName` + `json.load` + `validate_state` + `apply_state` | — |

**11/11 Phase-2 requirements satisfied.**

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

**No blocker or warning anti-patterns found.** Scanned all Phase-2 modules for `TODO|FIXME|XXX|HACK|not implemented|coming soon|will be here|lorem ipsum` — zero matches. The 6 `return None` matches in `demos.py` (lines 79, 85, 127, 130, 137) and `gui_setup.py:338` are all legitimate defensive error-handling paths (fetch_pdb/load_demo return None on failure; current_target_object returns None when not in loaded mode), not stubs. `gui_setup.py:93` `pdb_edit.setPlaceholderText("e.g. 1znf")` is a real Qt API call, not a stub placeholder.

### WSL-Tier Gate Results

| Gate | Expected | Result |
|------|----------|--------|
| `python3.6 -m py_compile` (7 modules) | All compile | ✓ PASS — `__init__.py`, `setup_state.py`, `demos.py`, `gui_setup.py`, `gui_game.py`, `game.py`, `wizard.py` all compile clean |
| `python3.6 -m unittest tests.test_setup_state -v` | All tests pass | ✓ PASS — 90 tests in 0.019s, OK |
| Pitfall-1 grep (Tkinter/Pmw/PyQt5/mainloop/Toplevel/grab_set) | ZERO matches | ✓ PASS — zero matches across `biochemeleon/` |
| exec_ gate (`.exec_()` anywhere) | ZERO on main dialog (QFileDialog/QMessageBox OK) | ✓ PASS — zero `.exec_()` calls anywhere in `biochemeleon/` |
| `from PyQt5 import` / `import PyQt5` gate | ZERO matches | ✓ PASS — zero matches; all Qt imports via `from pymol.Qt import` |
| `setup_state.py` purity (no pymol/Qt) | ZERO actual imports | ✓ PASS — only `import random`, `import copy`; the word "pymol" appears only in the module docstring (line 5) |
| `PDB_POOL` uniqueness + count | 33 unique entries | ✓ PASS — `len(PDB_POOL)=33`, `len(set(PDB_POOL))=33` (no dupes) |
| `DEMO_MANIFEST` keys | exactly 6 (1znf,1xdn,5e54,1k8p,2qbz,4wb3) | ✓ PASS |
| `GAME_REPS` | exactly 5 (lines,sticks,spheres,cartoon,ribbon) | ✓ PASS |
| `DEFAULTS` keys | 11 | ✓ PASS — `['format','target_mode','selected_object','pdb_code','demo_id','hider_count','lock_scene','per_rep','difficulty_easy','lock_source','pdb_pool']` |
| PDB file validity (6 files) | Each has HEADER + ATOM records | ✓ PASS — all 6 files: HEADER=1, ATOM counts: 15318/2095/2826/428/3263/1670 |

### Human Verification Required (already completed by 02-04 smoke test)

The Phase-2 plan 02-04 was a Windows-PyMOL human-verify checkpoint. Per the execution context, the human smoke test APPROVED all 4 success criteria on 2026-08-05 after the 3 gap closures (02-05, 02-06, 02-07). The following items were human-verified at runtime (WSL cannot run PyMOL or Qt):

### 1. Object selector 3-mode click-through (SC1)
**Test:** Open the plugin dialog → switch Source between Loaded object / Fetch from PDB / Bundled demo.
**Expected:** The QStackedWidget swaps pages; PyMOLObjectCombo refreshes loaded objects on popup; Fetch button loads a PDB; demo_combo shows 6 entries with category labels.
**Why human:** Requires live PyMOL + Qt runtime; WSL agent cannot launch the dialog.
**Status:** ✓ Approved by 02-04 smoke test.

### 2. Hider config live interaction (SC2)
**Test:** Select a loaded object → verify hider_spin max recomputes to the object's atom-count cap; toggle Lock current scene → verify per-rep checkboxes lock to the scene's active reps; tick per-rep rows + set counts → verify the sum bound prevents overflow; toggle difficulty.
**Expected:** Cap follows `hider_count_cap(cmd.count_atoms(obj))`; lock-scene syncs active reps; per-rep maxes bound to remaining budget; difficulty checkbox toggles.
**Why human:** Requires a loaded PyMOL object + live Qt form + cmd.count_atoms runtime behavior.
**Status:** ✓ Approved by 02-04 smoke test.

### 3. Reset / Randomize / Save / Load round-trip (SC3)
**Test:** Click Reset → form returns to defaults; click Randomize → form fills with random valid params (with and without Lock source checked); Save Setup → write a `.bcm.setup.json`; Load Setup → reload it and verify the form repopulates.
**Expected:** Reset→DEFAULTS; Randomize→valid state via `randomize_state`; Save writes JSON; Load validates + applies. Pool editor (Add/Edit/Remove/Use bundled pool/Choose random) works.
**Why human:** Requires live Qt form + file dialogs.
**Status:** ✓ Approved by 02-04 smoke test (after gap closures 02-05/06/07 added the pool editor + lock-source + choose-random).

### 4. Demo load + render (SC4)
**Test:** Switch to Bundled demo mode → pick each of the 6 demos → verify it loads and renders in the PyMOL 3D viewer.
**Expected:** All 6 PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) load via `cmd.load` + `to_windows_path` and render visibly. SOURCES.md cites each.
**Why human:** Requires live PyMOL rendering; WSL agent cannot display OpenGL.
**Status:** ✓ Approved by 02-04 smoke test.

### Gaps Summary

**No gaps found.** All 4 success criteria verified at the code level; all 11 requirements satisfied; all 15 key links wired; all 7 required artifacts present, substantive, and wired; zero anti-patterns. The human smoke test (02-04) already approved the runtime Qt + PyMOL behavior that WSL cannot reproduce.

**Minor observations (NOT gaps — accepted by human smoke test):**
- **"Category sub-menu" interpretation:** SETUP-02 says "with a sub-menu for demo categories." The implementation uses a flat `demo_combo` with each item labelled `"{category} — {id} ({difficulty})"` rather than a hierarchical QMenu sub-menu. The category metadata IS surfaced per-entry, the human smoke test approved this form, and Phase 9 (DIFF-05) will extend the demo metadata with tiered difficulty — a hierarchical sub-menu could be introduced then if desired. Not a blocker.
- **`load_demo` not yet called from a UI slot:** `gui_setup.py` imports `load_demo` (line 25) but no SetupTab slot currently calls it — the bundled-demo page only updates the `demo_id` field in the state dict; actual loading happens in Phase 4's Start action (BTN-07). The human smoke test triggered demo loads directly. Not a Phase-2 gap (Phase 2's scope is the configuration form, not the Start action); the import + wiring is present for Phase 4 to use.

### Verification Metadata

- **Approach:** Read actual code files (not SUMMARY claims); ran WSL-tier checks (py_compile all 7 modules, 90 unit tests, Pitfall-1 grep, exec_ gate, PyQt5 import gate, setup_state purity); verified all 15 key links by grepping the call sites; cross-checked the 4 success criteria + 11 requirements against the code; confirmed the 6 PDB files have HEADER + ATOM records; confirmed SOURCES.md cites all 6.
- **WSL-runnable checks:** All green (py_compile, 90/90 unit tests, all 4 grep gates zero matches).
- **Runtime checks (PyMOL + Qt):** Covered by human smoke test 02-04 (APPROVED 2026-08-05 after gap closures 02-05/06/07).
- **Phase 2 plans:** 7/7 complete (02-01 TDD state model, 02-02 bundle demos, 02-03 populate demos.py + gui_setup.py, 02-04 Windows smoke test, 02-05 gap closure cap+per-rep+lock-source+pool, 02-06 gap closure QListWidget+4-char validate, 02-07 gap closure Choose random).
- **Files inspected:** `biochemeleon/setup_state.py` (319 lines), `biochemeleon/demos.py` (137 lines), `biochemeleon/gui_setup.py` (579 lines), `biochemeleon/__init__.py` (66 lines), `biochemeleon/data/demos/SOURCES.md` (64 lines), 6 PDB files (header scan), `tests/test_setup_state.py` (469 lines, 90 tests).

---

_Verified: 2026-08-05T04:00:00Z_
_Verifier: OpenCode (gsd-verifier)_
_Tier: WSL code-level + human smoke test 02-04 (Windows PyMOL)_
