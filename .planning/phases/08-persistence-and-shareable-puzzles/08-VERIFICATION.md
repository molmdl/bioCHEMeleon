---
phase: 08-persistence-and-shareable-puzzles
verified: 2026-08-16T18:30:00Z
status: passed
score: 3/3 success-criteria verified
human_verification_completed: true
  prior_checkpoint: "08-05-SUMMARY.md documents human-verify PARTIAL APPROVAL (2026-08-16): 3 success criteria (Save+reload GAME-09, Generate&export BTN-05, Import+play GAME-04) + collision refuse + custom color round-trip ALL PASSED in a real Windows PyMOL GUI. 1 bug found (post-win Cleanup/Restart on imported game -> empty scene) + fixed (commit da8d7a8) + smoke Section N regression (15 checks). The fix is cmd-layer verified (78/78 headless smoke, independently re-run by this verifier). STATE.md line 15 confirms Phase 8 declared COMPLETE (5/5)."
independent_verification:
  unit_tests: "131/131 PASS (tests.test_persistence + tests.test_registry, run by verifier)"
  headless_smoke: "78/78 PASS, exit 0 (smoke/phase8_smoke.py, independently re-run by verifier via cmd.exe /c C:\\src\\run-conda-pymol.bat -cq)"
  pitfall1_gate: "CLEAN (no Tkinter/PyQt5/PySide imports in biochemeleon/)"
  exec_gate: "CLEAN (only QMessageBox.exec_() at gui_game.py:303 — allowed child dialog; main dialog stays modeless)"
  purity: "persistence.py + registry.py have NO pymol/Qt imports (pure, WSL-testable)"
---

# Phase 8: Persistence & Shareable Puzzles Verification Report

**Phase Goal:** The player can checkpoint a game in progress and reload it later, and an educator can prepare a puzzle (Generate & export) and share it for a player to Import.
**Verified:** 2026-08-16T18:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Phase Success Criteria)

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Pressing Save writes a .pse + .bcm JSON sidecar (registry, timer, reveal counts, setup); reloading both restores the full game state with the registry rebuilt from sentinels | ✓ VERIFIED | `_on_save` (__init__.py:352) calls `build_bcm_dict(kind='checkpoint', elapsed)` + `cmd.save(pse_path, target_obj)` (scoped — bare name excludes `_bchm_backup`) + `write_bcmz`. Pause-capture-dialog-save-resume (timer pitfall guarded). Reload path: `_on_import` (__init__.py:397) `read_bcmz` → `cmd.load(partial=1)` → `resolve_target` → `GameController.import_state` (game.py:327) which `reconstruct_registry()` (sentinel rebuild, rep=None) → `apply_bcm_dict` (reconcile rep+found-status from .bcm). Smoke sections C/D/E/F independently verified 78/78: scoped save excludes backup, 3 sentinels survive load, reconcile restores 1 found/2 hidden/all rep=spheres, `counts_by_rep` spheres==3 (NOT 0). Human-verified PASSED per 08-05-SUMMARY. |
| 2 | Pressing Generate & export (from Setup) generates hiders + saves initial game state to a file WITHOUT starting play | ✓ VERIFIED | `_on_export` (__init__.py:309) reuses `_prepare_and_start` (refactored from `_on_start`, behavior-preserving) → `build_bcm_dict(kind='puzzle')` (forces `started=False` + `timer_elapsed=0.0` even when `controller._started` is True) → `cmd.save(pse_path, target_obj)` → `write_bcmz` → stays on Setup tab. `export_btn` ("Generate & export") is in gui_setup.py:196, placed between `load_btn` ("Load Setup…") and `cleanup_btn` ("Cleanup model") per spec order (line 210-212). Wired: `export_btn.clicked.connect(self._on_export)` (__init__.py:75). Smoke section K independently verified: puzzle kind=='puzzle', started==False, timer_elapsed==0.0, all hiders hidden. Human-verified PASSED per 08-05-SUMMARY. |
| 3 | Pressing Import (from Game tab) loads a previously exported game + lets the player play it | ✓ VERIFIED | `_on_import` (__init__.py:397) opens `QFileDialog` → `read_bcmz` → refuse-first collision check (if `target_object` already loaded, warn + return) → `cmd.load(pse_path, partial=1)` (MERGE, preserves scene) → `resolve_target` → `GameController.import_state(bcm_dict)` → switch to Game tab → `start_countdown(controller, elapsed)`. `_import_btn` ("Import puzzle…") in gui_game.py:64 (begin_row, renders ABOVE btn_row). Wired: `_import_btn.clicked.connect(self._on_import)` (__init__.py:76). Smoke sections H/L independently verified: `resolve_target=='1ubq'`, `_is_imported==True`, `_backup_name=='_bchm_backup'`, `_imported_bcm` preserved, registry 3/1 found/2 hidden/all rep=spheres; collision detectability confirmed (1ubq in loaded molecules → refuse condition True). Human-verified PASSED per 08-05-SUMMARY (click-to-find works, win fires). |

**Score:** 3/3 success-criteria verified

### Required Artifacts (three-level check)

| Artifact | Expected | Exists | Substantive | Wired | Status |
| --- | --- | --- | --- | --- | --- |
| `biochemeleon/persistence.py` | build_bcm_dict + parse_bcm_dict + apply_bcm_dict + write_bcmz + read_bcmz + resolve_target + BCM_MAGIC/BCM_VERSION | ✓ (279 lines) | ✓ SUBSTANTIVE — all 6 functions + 2 constants implemented; pure (stdlib + .registry + .setup_state only; NO pymol/Qt) | ✓ WIRED — imported by `__init__.py` (lazy `from . import persistence`) + `game.py` (lazy) + smoke | ✓ VERIFIED |
| `biochemeleon/registry.py` | HiderRegistry.reconcile_with_bcm + ReconcileMismatches namedtuple | ✓ (515 lines) | ✓ SUBSTANTIVE — `reconcile_with_bcm` (lines 411-474) full sentinel-first merge with 3 mismatch lists; `ReconcileMismatches` namedtuple (lines 47-51); pure (no pymol) | ✓ WIRED — called by `apply_bcm_dict` (persistence.py:192); smoke exercises it | ✓ VERIFIED |
| `biochemeleon/game.py` | GameController.import_state + _is_imported + _imported_bcm fields | ✓ (415 lines) | ✓ SUBSTANTIVE — `import_state` (lines 327-367) full 5-step reconstruction (reconstruct_registry → apply_bcm_dict → defensive recolor → fresh backup.snapshot → set flags); `_is_imported=False` + `_imported_bcm=None` in `__init__` (lines 45-46) | ✓ WIRED — called by `_on_import` (__init__.py:465); `_is_imported` checked by `_on_restart` (line 488) + `_on_cleanup` (line 538) + `_finish_win` (gui_game.py:316) | ✓ VERIFIED |
| `biochemeleon/__init__.py` | _prepare_and_start + _on_export + _on_import + _on_save + _on_restart_imported + modified _on_restart + modified _on_cleanup | ✓ (553 lines) | ✓ SUBSTANTIVE — all 7 handlers implemented with real logic (file dialogs, cmd.save/load, build_bcm_dict, write_bcmz, resolve_target, import_state, backup ops) | ✓ WIRED — `export_btn.clicked.connect(_on_export)` (line 75); `_import_btn.clicked.connect(_on_import)` (line 76); `_save_btn.clicked.connect(_on_save)` (line 77); `_restart_btn` routes `_on_restart` | ✓ VERIFIED |
| `biochemeleon/gui_setup.py` | export_btn (Generate & export) in Setup actions row | ✓ (600 lines) | ✓ SUBSTANTIVE — `export_btn` (line 196) with tooltip; placed between `load_btn` and `cleanup_btn` per spec order (lines 210-212) | ✓ WIRED — connected in `__init__.py:75` | ✓ VERIFIED |
| `biochemeleon/gui_game.py` | begin_row (import_btn + save_btn) + start_countdown(elapsed=0) + _begin_play resume fix | ✓ (317 lines) | ✓ SUBSTANTIVE — `begin_row` QHBoxLayout (lines 63-73) with `_import_btn` + `_save_btn` above btn_row; `start_countdown(self, controller, elapsed=0)` (line 203) backward-compatible signature; `_begin_play` resume guard (line 251: `if self._controller._start_time is None`); `_reveal_label` seeded from `controller._reveal_count` (line 218, not hardcoded); `_finish_win` post-win fix (line 316: `if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()`) | ✓ WIRED — `_import_btn`/`_save_btn` connected in `__init__.py:76-77`; `start_countdown` called by `_on_start`/`_on_import`/`_on_restart_imported` | ✓ VERIFIED |
| `tests/test_persistence.py` | TestBuildBcmDict + TestParseBcmDict + TestApplyBcmDict + TestBcmRoundTrip + TestWriteReadBcmz + TestResolveTarget + alt-conf round-trip/backward-compat | ✓ (717 lines) | ✓ SUBSTANTIVE — 37 test methods across 9 test classes | ✓ WIRED — 131/131 PASS (independently run by verifier: `python3.6 -m unittest tests.test_persistence tests.test_registry -v`) | ✓ VERIFIED |
| `tests/test_registry.py` | TestReconcileFromBcm class (~12 unit tests) | ✓ (1121 lines) | ✓ SUBSTANTIVE — `TestReconcileFromBcm` (line 681) with 12 reconcile tests (perfect match, str-id coercion, mismatched object, missing_from_bcm/pse, none hiders, pos restore, bad_rep skip, status default, round-trip); 94 total test methods | ✓ WIRED — all pass (part of 131/131) | ✓ VERIFIED |
| `smoke/phase8_smoke.py` | Headless smoke (~78 checks, pure pymol.cmd.* — export/import round-trip) | ✓ (361 lines) | ✓ SUBSTANTIVE — 78 `check()` calls across 14 sections (A-N+M); covers scoped save, sentinel rebuild, reconcile, import round-trip, Restart/Cleanup-on-imported, puzzle round-trip, collision, post-win regression | ✓ WIRED — exercises `build_bcm_dict`/`write_bcmz`/`read_bcmz`/`resolve_target`/`import_state`/`cmd.save`/`cmd.load`/`reconcile_with_bcm`/`counts_by_rep`; **independently re-run by verifier: 78/78 PASS, exit 0** | ✓ VERIFIED |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `gui_setup.export_btn.clicked` | `PluginDialog._on_export` | `export_btn.clicked.connect(self._on_export)` in `__init__.py:75` | ✓ WIRED | Connection present; handler generates + saves .bcmz |
| `gui_game._import_btn.clicked` | `PluginDialog._on_import` | `_import_btn.clicked.connect(self._on_import)` in `__init__.py:76` | ✓ WIRED | Connection present; handler unzips + loads + imports |
| `gui_game._save_btn.clicked` | `PluginDialog._on_save` | `_save_btn.clicked.connect(self._on_save)` in `__init__.py:77` | ✓ WIRED | Connection present; handler pause-capture-save-resume |
| `_on_export` | `_prepare_and_start` + `build_bcm_dict` + `cmd.save` + `write_bcmz` | handler body `__init__.py:318,334,339,340` | ✓ WIRED | All 4 calls present; kind='puzzle' forced started=False |
| `_on_save` | `build_bcm_dict(kind='checkpoint')` + `cmd.save(target_obj)` + `write_bcmz` | handler body `__init__.py:377,383,384` | ✓ WIRED | Pause-capture-dialog-save-resume (timer pitfall guarded at lines 363-364, 370-371, 389-394) |
| `_on_import` | `read_bcmz` + `cmd.load(partial=1)` + `resolve_target` + `import_state` | handler body `__init__.py:418,446,453,465` | ✓ WIRED | All 4 calls present; refuse-first collision check at lines 426-434 |
| `_on_restart` | `_is_imported` flag → `_on_restart_imported` OR `_on_start` | handler body `__init__.py:488-491` | ✓ WIRED | Routes on `getattr(self._controller, '_is_imported', False)` |
| `_on_cleanup` | imported two-step: `backup.restore` + `mutation.cleanup_hiders` | handler body `__init__.py:538-546` | ✓ WIRED | `_is_imported` branch does restore+discard+cleanup_hiders; non-imported calls `c.cleanup()` |
| `_on_restart_imported` | `backup.restore` + `reconstruct_registry` + `apply_bcm_dict` + `backup.snapshot` | handler body `__init__.py:509,511,514,518` | ✓ WIRED | Re-reconciles rep from saved `_imported_bcm` (rep lost on restore) |
| `GameController.import_state` | `reconstruct_registry` + `apply_bcm_dict` + `backup.snapshot` | method body `game.py:351,352,364` | ✓ WIRED | Sentinel rebuild → reconcile → fresh backup; sets `_started/_is_imported/_imported_bcm` |
| `apply_bcm_dict` | `controller.registry.reconcile_with_bcm` | `persistence.py:192` | ✓ WIRED | Passes `bcm_dict['registry']['hiders']` list to pure merge |
| `build_bcm_dict` | `controller.registry.to_dict()` + controller state attrs | `persistence.py:104-108` | ✓ WIRED | Reads `_reveal_count`/`_hint_count`/`_found_color`/`_started`/`_start_time`; embeds registry + setup verbatim |
| `write_bcmz` | `zipfile.ZipFile` + `zf.write(pse,'game.pse')` + `zf.writestr('game.bcm', json)` | `persistence.py:211-213` | ✓ WIRED | Bundles .pse + .bcm into single .bcmz archive |
| `read_bcmz` | `zipfile.ZipFile` + `parse_bcm_dict` + temp file extract | `persistence.py:235-247` | ✓ WIRED | Returns `(pse_path, bcm_dict)`; validates magic+version via parse_bcm_dict |
| `_finish_win` | `_is_imported` guard → skip `cleanup()` for imported | `gui_game.py:316` | ✓ WIRED | Post-win fix: imported games preserve backup so subsequent Cleanup/Restart work; non-imported path unchanged |
| `smoke/phase8_smoke.py` | all persistence + game + registry cmd-coupled round-trip | sections A-N | ✓ WIRED | **Independently re-run: 78/78 PASS, exit 0** |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
| --- | --- | --- |
| **GAME-09** (Save button — .pse + .bcm sidecar for checkpointing) | ✓ SATISFIED | None. `_on_save` writes .bcmz (bundling .pse + .bcm JSON with registry/timer/reveal counts/setup); `import_state` rebuilds registry from sentinels + reconciles from .bcm. Human-verified PASSED + smoke 78/78. |
| **BTN-05** (Generate & export — generate rep + save initial state to file without playing) | ✓ SATISFIED | None. `_on_export` reuses `_prepare_and_start` (generates hiders) + saves .bcmz with kind='puzzle' (started=False, timer=0) + stays on Setup. Human-verified PASSED + smoke section K. |
| **GAME-04** (Import button — import a game prepared by Generate & export) | ✓ SATISFIED | None. `_on_import` loads .bcmz → merges .pse → resolves target → `import_state` → starts countdown. Human-verified PASSED (click-to-find works, win fires) + smoke section H. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `biochemeleon/game.py` | 17-18 | "placeholder insert" / "_placeholder_hiders" in docstring | ℹ️ Info | Historical narrative comment describing Phase 3 mechanism proof; NOT active code (verified: no `_placeholder_hiders` calls, no `def _placeholder`). Phase 4/5 real generators replaced it. |
| `biochemeleon/__init__.py` | 42 | "Phase 1 ships placeholder tabs only" in docstring | ℹ️ Info | Historical narrative comment; Phase 2+ populated the tabs. Not a stub. |
| `biochemeleon/gui_game.py` | 80, 169 | "index-0 placeholder" for found-mgmt combo | ℹ️ Info | Legitimate UI pattern: a "no selection" placeholder item in a QComboBox. Not a stub. |
| `biochemeleon/persistence.py` | 279 | `return None` (resolve_target ambiguous case) | ℹ️ Info | Documented behavior — returns None when target can't be resolved; caller shows "Import failed" dialog. Not a stub. |
| `biochemeleon/registry.py` | 305, 496 | `return None` (helper "no found hiders" sentinel) | ℹ️ Info | Documented behavior — `build_found_selection` returns None (not empty string) to signal "no found hiders". Not a stub. |

**No blockers, no warnings.** All "placeholder" hits are historical docstrings or legitimate UI patterns. No `TODO`/`FIXME`/`NotImplementedError`/bare-`pass` stubs in any Phase 8 file. Pitfall-1 gate (no Tkinter/PyQt5/PySide imports) CLEAN. exec_ gate CLEAN (only `QMessageBox.exec_()` at gui_game.py:303 — allowed child dialog per AGENTS.md; main dialog stays modeless via `dialog.show()`).

### Human Verification

**Human verification was ALREADY COMPLETED** per the 08-05-SUMMARY.md checkpoint (2026-08-16) and STATE.md line 15. The human-verify was a "PARTIAL APPROVAL":

**PASSED (human, real Windows PyMOL GUI):**
1. Save mid-game + reload resumes the game (timer, found-status, registry) — success criterion 1
2. Generate & export writes .bcmz + stays on Setup + Cleanup restores scene — success criterion 2
3. Import loads .bcmz + play begins + click-to-find works + win fires — success criterion 3
4. Collision refuse (target_object already loaded → clear error dialog)
5. Custom color round-trip (found hiders retain custom color after reload)

**1 bug found + fixed during human-verify:**
- **Post-win Cleanup/Restart on imported game produced empty scene** — `_finish_win` called `controller.cleanup()` after the win dialog, which discarded the post-import backup; subsequent Cleanup-on-imported/Restart-on-imported called `backup.restore(target, None)` → `cmd.delete(target)` + `cmd.create(target, None)` failed → target DELETED (empty scene).
- **Fix:** `_finish_win` now guards `if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()` (gui_game.py:316). Imported games preserve the backup; the user clicks Cleanup (two-step) or Restart explicitly.
- **Regression:** Smoke Section N (15 new checks) added — simulates import → win → cleanup-on-imported (count==orig, NOT empty) + import → win → restart-on-imported (hiders restored, NOT empty). **Verifier independently re-ran the smoke: 78/78 PASS including all 15 Section N checks, exit 0.**

**Verifier note on Qt GUI path:** The `_finish_win` fix is cmd-layer verified by smoke Section N (which mirrors `_on_cleanup` imported + `_on_restart_imported` exactly). The Qt GUI path (the actual `_finish_win` skip) is structurally identical — the only Qt-specific parts (wizard.deactivate, `msg.exec_()`) are unchanged. Per AGENTS.md, the Qt GUI cannot be run from a WSL agent, so the verifier relies on (a) the documented human-verify results, (b) the independent 78/78 smoke re-run, and (c) the structural verification of the fix.

### Gaps Summary

**No gaps found.** All 3 Phase 8 success criteria are verified:
- **Structurally:** All required artifacts exist, are substantive (real implementations, not stubs), and are wired (connections present and exercised).
- **Automated:** 131/131 unit tests pass + 78/78 headless smoke pass (both independently re-run by the verifier, not just trusting SUMMARY claims).
- **Human:** The 3 success criteria + collision refuse + custom color round-trip were human-verified PASSED in a real Windows PyMOL GUI (per 08-05-SUMMARY checkpoint, 2026-08-16). The 1 bug found during human-verify was fixed + has a smoke regression.

The phase goal — "The player can checkpoint a game in progress and reload it later, and an educator can prepare a puzzle (Generate & export) and share it for a player to Import" — is **achieved**.

---

_Verified: 2026-08-16T18:30:00Z_
_Verifier: OpenCode (gsd-verifier)_
_Independent re-runs: `python3.6 -m unittest tests.test_persistence tests.test_registry -v` (131/131 PASS) + `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase8_smoke.py` (78/78 PASS, exit 0)_
