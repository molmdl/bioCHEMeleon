# Codebase Concerns

**Analysis Date:** 2026-08-18

**Project state context:** v1 is COMPLETE and VERIFIED (all phases 1-11 + Phase 4.1 done; 125 unit tests green; 10 headless smoke tests green; no pending todos; no open debug sessions in `.planning/debug/pending/`). The concerns below describe the shipped v1's fragility surface, latent issues, and constraints for future maintenance / v2 work — not open blockers. Most concerns are documented in `AGENTS.md`, `.planning/research/PITFALLS.md`, and `.planning/STATE.md` "Blockers/Concerns" (lines 281-300); this file consolidates them with file paths and current mitigations.

---

## Tech Debt

**Cartoon MVP is N-terminus-only (C-terminus path unexercised at runtime):**
- Issue: The C-terminus carbonyl C carries an OXT (terminal oxygen) in 1ubq + most structures, which saturates the C valence and makes `pymol.editor.attach_amino_acid` fail with "no target attachment vector found" (`ObjectMolecule.cpp:3357`). Phase 5 (plan 05-04) switched cartoon MVP to the N-terminus (free valence, no atom removal, `verify_intact` passes). `insert_cartoon_hider(is_c_terminus=True)` still supports the C-terminus path for OXT-free structures, but NO smoke test or generator exercises it.
- Files: `biochemeleon/mutation.py` (`insert_cartoon_hider`, `pick_terminal_residues`); `biochemeleon/generators.py` (`pick_terminal_residues` returns `is_c_terminus=False`).
- Impact: A bundled demo with an N-terminal cap (ACE/formyl) or a non-standard N-terminus may fail the N-term attach at runtime. The C-term path is dead code that has never been runtime-verified against a real OXT-free structure.
- Current mitigation: Documented in `.planning/STATE.md:284` (Blockers/Concerns `[05-04]`). C-terminus path retained in code but not in the MVP generator.
- Fix approach: Add a C-terminus smoke section (e.g. a capped/OXT-free structure) AND an N-terminal-cap demo regression test before either path is relied on for a new demo set. Consider detecting N-terminal caps and falling back to C-terminus automatically.

**`biochemeleon.zip` is stale (gitignored fallback install artifact):**
- Issue: `biochemeleon.zip` (6973 bytes, Aug 3 02:26) is ~15 days older than the `biochemeleon/` package (last modified Aug 18 09:33). The zip is gitignored (per `AGENTS.md:155`) but if anyone uses it as a fallback install artifact (e.g. via PyMOL Plugin Manager "Install from file"), they get a stale package missing all Phase 6-11 work.
- Files: `biochemeleon.zip` (repo root), `biochemeleon/` (source of truth).
- Impact: Stale installs silently miss bug fixes (Phase 11 membrane blank-chain fix `0702563`, Phase 6 hint-color-restore fix `c9c2169`, post-win cleanup-on-imported fix `[08-05]`, post-game debrief `41872b1`, etc.).
- Current mitigation: Gitignored (not committed); `wsl2win_cp.sh` stages the live `biochemeleon/` to `tmp/bioCHEMeleon/` for the headless bridge.
- Fix approach: Regenerate `biochemeleon.zip` from current `biochemeleon/` at every release tag, OR delete it and document the `wsl2win_cp.sh` staging path as the only install method.

**`AGENTS.md` slightly misrepresents the `opencode.json` denylist:**
- Issue: `AGENTS.md:11` says "`opencode.json` denies `pip*`, `apt*`, `conda*`, `rm*`." The actual `opencode.json` (lines 58-66) has `rm *` and `rg *` as `deny`, but `pip *`, `pip3 *`, `apt *`, `conda *`, `wget *`, `curl *`, `python *`, `mv *`, `npm *`, and `git push/pull/merge/rebase/reset/checkout` are all `ask` (i.e. prompt for approval, not fully denied).
- Files: `AGENTS.md:11`, `opencode.json:50-69`.
- Impact: Minor — an agent reading `AGENTS.md` may believe pip/apt/conda are impossible, when they are actually approval-gated. The practical effect (autonomous agents can't run them without a human) is the same, but the framing is imprecise.
- Fix approach: Reword `AGENTS.md:11` to "`opencode.json` gates `pip*`, `apt*`, `conda*` behind approval and denies `rm*`/`rg*`."

**`__pycache__` committed alongside source in `biochemeleon/` and `smoke/`:**
- Issue: `ls -la biochemeleon/` shows a `__pycache__/` subdirectory (Aug 18 10:35) and `smoke/__pycache__/` exists. `*.pyc` is gitignored per `AGENTS.md:155`, but the directories may still accumulate stale bytecode if Python versions change.
- Files: `biochemeleon/__pycache__/`, `smoke/__pycache__/`.
- Impact: Negligible for runtime; possible confusion if a 3.6-vs-3.x bytecode mismatch causes silent import failures.
- Fix approach: Add `__pycache__/` (not just `*.pyc`) to `.gitignore`; clean directories at release tag.

---

## Known Bugs

**No open bugs.** v1 is complete and all phases are VERIFIED. The most recent bug fix was `0702563 fix(11): quote chain value in selectors to handle blank-chain structures` (2026-08-16); the next most recent was `36d5de4 fix(10-09): add Ctrl+Left-drag=Move to Help controls` (user checkpoint feedback). Recent fix commits (last 60 commits): only 4 `fix(...)` commits — `0702563` (Phase 11 membrane), `36d5de4` (help text), `fd573ad` (doc exec_ count), `ef9a154` (planning revision). No regressions are tracked.

**Recently-fixed bug worth recording as a fragility lesson (NOT a current bug):**
- **Phase 11 membrane blank-chain selector bug** (FIXED `0702563`, 2026-08-16): The unquoted chain value in PyMOL selectors with a blank chain (`chain=''`, common in MemProtMD structures `1gzm`/`3gp6`/`sasdpg4` where all atoms are on a single unnamed chain) was MALFORMED — it ignored the object scope and matched blank-chain atoms from EVERY object in the session. With the backup + live object both loaded, the segment selection in `insert_cartoon_segment_hider` matched each atom TWICE, `cmd.create` produced duplicate-id atoms, and `cmd.identify` returned `[id, id]` → `AssertionError: expected 1 anchor id, got [25, 25]`. Fix: single-quote the chain value in all 6 selectors in `biochemeleon/mutation.py`. Regression test: `smoke/phase11_smoke.py` section N (9 blank-chain tests, 86/86 PASSED) + `smoke/diag_phase11_dup_id.py` (repro). **Rule for future code: ALWAYS quote chain values in selectors** — `'%s and chain \'%s\'' % (obj, chain)`, never `'%s and chain %s' % (obj, chain)`. Source: `.planning/STATE.md:14`; `git show 0702563`.

---

## Security Considerations

**Attribution / citation verification (spec.md constraint, DEMO-04):**
- Risk: `spec.md:89` mandates "Do NOT make up anything. ALL claims and citations (DOIs, PDB IDs, sources) MUST be verified against a source and explicitly approved by a human." A future agent adding a demo PDB without a verified DOI, or shipping MemProtMD membrane coordinates without the CC-BY 4.0 attribution, would violate the spec and create a license-attribution failure.
- Files: `DATA_SOURCES.md` (repo root, 202 lines, all citations maintained); `biochemeleon/data/demos/SOURCES.md` (2-line pointer to repo-root `DATA_SOURCES.md`); `biochemeleon/data/demos/*.pdb` (6 bundled PDBs).
- Current mitigation: `DATA_SOURCES.md` lists every PDB ID + DOI + SASBDB ID + MemProtMD attribution with license (CC0 for RCSB, CC-BY 4.0 for MemProtMD, free-use for SASBDB). Verified per `.planning/research/PITFALLS.md:517-521` (MemProtMD license verified 2026-08-14 from site JS bundle). The 6 bundled RCSB PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) are all CC0.
- Recommendations: Any new demo addition MUST update `DATA_SOURCES.md` with a human-verified DOI + license. MemProtMD per-entry license MUST be re-verified before bundling any new membrane coordinates (the site was unreachable at Phase 9 research time per `.planning/STATE.md:286`; license was confirmed CC-BY 4.0 on 2026-08-14 but per-entry verification is the spec-mandated gate).

**External Python library approval (spec.md constraint):**
- Risk: `spec.md:86-87` requires that any Python library beyond what `pymol-open-source` ships (PyQt5 via `pymol.Qt`, numpy) MUST be listed to a file, explicitly user-approved, and either user-installed or vendored into `./3rd_party_lib/` (gitignored) with the library's license noted. Silent `pip install` violates the spec.
- Files: `opencode.json:60-64` (`pip *`, `pip3 *`, `apt *`, `conda *` are `ask`-gated); `3rd_party_lib/` (gitignored, currently no vendored libs).
- Current mitigation: `opencode.json` approval gate + `AGENTS.md:111` documents the constraint. v1 uses only pymol-open-source + numpy — no external libs were added.
- Recommendations: Maintain the gate for v2. If a lib is needed, state whether the user must set up a linux-like env or can keep the "calling cmd from WSL" approach (`spec.md:87`).

**Path traversal / unsanitized user-input paths (low risk):**
- Risk: `cmd.load(user_input_path)` is called for user-provided PDB files. Per `.planning/research/PITFALLS.md:351`, this is a local desktop plugin so risk is low, but path sanitization + `CmdException` handling is the defensive pattern.
- Files: `biochemeleon/demos.py` (`load_demo`, `fetch_pdb`); `biochemeleon/__init__.py` (`_on_start` target resolution).
- Current mitigation: `demos.to_windows_path()` converts `/mnt/c/...` → `C:\...` only for WSL mount paths (returns other paths unchanged). PyMOL's `cmd.load` raises `CmdException` on missing files; the plugin catches and surfaces via `QMessageBox.warning`.
- Recommendations: Validate file extension + catch `CmdException` to give a clean error (per PITFALLS.md:351).

---

## Performance Bottlenecks

**100k+ atom membrane proteins (1GZM, 3GP6 with full DPPC membrane) — Pitfall 12:**
- Problem: `cmd.get_model(target_obj)` copies the entire structure into Python — RAM spikes to multiple GB and the call takes 10+ seconds on a 100k+ atom membrane protein. Per-hider neighbor search in Python loops takes another 10+ seconds each. "Start" appears to freeze; on low-RAM machines PyMOL crashes.
- Files: `biochemeleon/generators.py`, `biochemeleon/mutation.py` (any `cmd.get_model` call would be the bug; verify it's absent), `biochemeleon/game.py` (`GameController.start` insert loop).
- Cause: `cmd.get_model` is O(total atoms) in Python; Python neighbor loops are O(hiders × atoms).
- Improvement path: Per `.planning/research/PITFALLS.md:479-493`: never `cmd.get_model` on large objects — use `cmd.iterate(obj, '...', space=...)` (streams, no copy). For neighbor search use C-side selection: `cmd.select('_tmp_nbr', 'obj within 8 of [x,y,z]')`. For hider placement sample C-side: `cmd.select('_tmp_ca', 'obj and name CA')`, then `cmd.iterate` only Cα coords into a numpy array (memory: 100k × 3 × 8B ≈ 2.4 MB). Strip water + salt before bundling. Show a modeless `QProgressDialog` during fetch + load + strip + generate. Performance budget: Generate on 3GP6 < 30 s on mid-range laptop; click latency < 200 ms.
- Current mitigation: v1 generators use `cmd.iterate` (not `cmd.get_model`) per the smoke-verified paths. The large demos (1GZM, 3GP6) are FETCHED ON DEMAND (not bundled) per Phase 9 — `demos.py` fetch path. Performance is bounded by the user's network + machine.

**`cmd.create('_bchm_backup', obj)` snapshot doubles RAM at Start:**
- Problem: Every `GameController.start` snapshots the target via `cmd.create('_bchm_backup', target_obj, zoom=0)` BEFORE any mutation (`biochemeleon/backup.py:40-46`). For a 100k+ atom object this doubles RAM. Frequent restarts compound the allocation churn.
- Files: `biochemeleon/backup.py:40-46` (`snapshot`), `biochemeleon/game.py` (`start` calls `backup.snapshot` first).
- Cause: There is NO undo in PyMOL Open Source (`undocontext` is a no-op stub, `editor.py:25-36`); the backup is the ONLY recovery mechanism. Snapshot-once-at-Start + delete-on-unload is the canonical pattern (per PITFALLS.md:344).
- Improvement path: Already optimal for the no-undo constraint — snapshot is mandatory. The only improvement is to delete the backup as soon as the game ends (cleanup/abort both call `backup.discard`). No further optimization possible without undo.

---

## Fragile Areas

**WSL/Windows runtime split (the single most common way to break things — `AGENTS.md:7`):**
- Files: `AGENTS.md:7-25` (Environment section), `wsl2win_cp.sh` (84-byte staging script), `biochemeleon/demos.py:to_windows_path` (WSL→Windows path guard).
- Why fragile: Dev shell is WSL Ubuntu (python3.6, no PyMOL, no Qt runtime). PyMOL 2.5.0 runs in a Windows conda env (`chemtools-win10` activated by `setenv.bat`). A WSL agent CANNOT run the interactive GUI and CANNOT use Qt (`pymol.Qt.*`) at runtime. Pure `pymol.cmd.*` paths CAN be run headlessly via `cmd.exe /c C:\src\run-conda-pymol.bat -cq <script>` (discovered Phase 3, 2026-08-06), but this is a discovered workaround, NOT a first-class setup. Windows PyMOL cannot resolve WSL paths — `demos.to_windows_path()` converts `/mnt/c/...` → `C:\...` only for WSL mount paths (returns other paths unchanged); a path that isn't converted is a latent failure.
- Safe modification: Always `cd` into the staged Windows path (`tmp/bioCHEMeleon/`) before invoking `cmd.exe`. Wrap in `timeout 90` + `tail -50` to avoid hangs (~30s runtime for a phase smoke). Check exit code: 0 = clean, nonzero = crash. For any Qt/GUI work, defer to a human-verify checkpoint (no display in WSL).
- Test coverage: GUI/Qt code is NOT automated (human-verify only — see "Test Coverage Gaps" below). Pure layer is unit-tested in WSL; cmd-coupled code is headless-smoke-tested via the bridge.

**Headless PyMOL bridge depends on a Windows-side file existing at a hardcoded path:**
- Files: `AGENTS.md:13-22`, `wsl2win_cp.sh`, external `/mnt/c/src/run-conda-pymol.bat` (1638 bytes, Jun 9 2022).
- Why fragile: The headless bridge command `cmd.exe /c C:\src\run-conda-pymol.bat -cq <script>` requires `C:\src\run-conda-pymol.bat` to exist on the Windows side at that exact path. If the user moves/renames/deletes that bat file, every headless smoke test in `smoke/phase*_smoke.py` (10 files) becomes unrunnable from WSL. The bridge also requires `wsl2win_cp.sh` to stage `biochemeleon/` → `tmp/bioCHEMeleon/` first; an unstaged or stale `tmp/bioCHEMeleon/` produces confusing failures.
- Safe modification: Before relying on the bridge, `ls -la /mnt/c/src/run-conda-pymol.bat` + `bash wsl2win_cp.sh` + `ls tmp/bioCHEMeleon/biochemeleon/`. Document the bridge dependency in any new smoke test's header.
- Test coverage: 10 headless smoke tests depend on this bridge; no test verifies the bridge itself exists.

**PyMOL API pitfalls (the "easy to get wrong" list — each is a latent bug source):**
- Files: `AGENTS.md:77-102` (Domain rules + Phase 3 mutation-safety rules), `.planning/research/PITFALLS.md` (545 lines, authoritative), `biochemeleon/mutation.py`, `biochemeleon/backup.py`, `biochemeleon/registry.py`.
- Why fragile: The PyMOL 2.5.0 open-source API has many silent-failure modes. Each rule below has caught a real bug during Phase 3-11 verification:
  - `cmd.pseudoatom()` returns `None` (`NoneType`) — NEVER rely on the return value for hider ids. Use `cmd.identify("obj and name <handle> and segi GAME", mode=0)` + `assert len(ids) == 1` (mode=0 returns the id list, NOT the fragile index). Source: `biochemeleon/mutation.py:88`; PITFALLS.md:429-434.
  - `cmd.iterate` exposes the atom id as UPPERCASE `ID`, NOT lowercase `id` (the Python builtin → `NameError` or wrong value; `editing.py:1444-1449`). All iterate expressions must use uppercase symbols (`ID`, `MODEL`, `RESN`, `RESI`, `NAME`, `CHAIN`, `SEGI`, `B`, `RESV`). Source: `biochemeleon/mutation.py:124`; PITFALLS.md:457.
  - `cmd.iterate` does NOT expose `x`/`y`/`z` coordinates (state-dependent; need `cmd.iterate_state`). `backup.verify_intact` uses `(resn, resi, name, chain, segi)` — count + identity multiset suffices because `cmd.create` copies coords bit-for-bit (RESEARCH §Q6 fallback). Source: `biochemeleon/backup.py:69-83`; PITFALLS.md:458.
  - `cmd.iterate`/`cmd.alter` with `space=None` pollutes the global `pymol.__dict__` (`editing.py:59-60`). ALWAYS use `space={'stored': ...}` (hygienic dict). Source: `biochemeleon/backup.py:80-83`, `biochemeleon/mutation.py:124`; PITFALLS.md:340, PITFALLS.md:501.
  - B-factor selector `b -999` is MALFORMED ("Selector-Error: Malformed selection") and SILENTLY matches nothing (no exception — returns `[]`, a dangerous failure mode). The sentinel VALUE stays `-999` (set in `insert_hider`/cleanup docstrings); only the SELECTOR uses the comparison `b < 0` (matches `-999.0`). Source: `biochemeleon/mutation.py:113` (`fetch_all_hider_ids`); PITFALLS.md:459.
  - No `cmd.get_representations()` in PyMOL 2.5.0. Detect active reps with `cmd.count_atoms("{obj} and rep {rep}") > 0`. Source: `AGENTS.md:83`.
  - `cmd.create(obj, seg, 1, 1)` is a NO-OP (Phase 5 05-06 spike). Single-call `cmd.create(existing, src)` IS a REPLACE (smoke-confirmed `n_after==n_before`), but `backup.restore` uses the explicit two-step `cmd.delete(target)` + `cmd.create(target, backup)` for an unambiguous failure path. Consult `tmp/pymol-src/modules/pymol/` (gitignored, readable from any worktree via the main-repo absolute path) when the API behaves unexpectedly. Source: `biochemeleon/backup.py:54-67`; PITFALLS.md:436-439.
  - Registry MUST key on atom `id` (stable across add/delete + `.pse` reload; smoke-confirmed `pse_sent==[saved_id]`) — NEVER on `index` (fragile, shifts on insert/remove; `querying.py:1315`). Source: `biochemeleon/registry.py`; PITFALLS.md:110-124.
  - `rep` is NOT recoverable from sentinels after `.pse` reload (the sentinel carries only `segi='GAME'` + `b=-999`; `reconstruct_from_sentinels` sets `rep=None`). Phase 8 `.bcm` sidecar reconciles `rep` via `HiderRegistry.reconcile_with_bcm` (pure, no pymol). ADDRESSED 2026-08-12 (Plan 08-01). Source: `biochemeleon/registry.py` (`reconcile_with_bcm`); `.planning/STATE.md:288`.
  - **Chain values in selectors MUST be single-quoted** (Phase 11 membrane bug `0702563`): blank chains (`chain=''`, common in MemProtMD `1gzm`/`3gp6`/`sasdpg4`) produce a malformed unquoted selector that matches blank-chain atoms from EVERY object in the session. Use `'%s and chain \'%s\'' % (obj, chain)`, never `'%s and chain %s' % (obj, chain)`. Source: `biochemeleon/mutation.py` (6 selectors); `smoke/diag_phase11_dup_id.py` (repro).
  - PyMOL rep-inheritance (Phase 5 05-09): a freshly-fetched protein has `cartoon` shown by DEFAULT on its polymer; newly-attached residues INHERIT the cartoon rep. A regression guard asserting `rep cartoon == 0` on GAME atoms is UNSOUND — cartoon comes from inheritance, not the explicit show. Assert the requested rep is on GAME atoms but NOT on the rest of the polymer. Source: `.planning/STATE.md:285`.
- Safe modification: Read `AGENTS.md:77-102` + `.planning/research/PITFALLS.md` before any `cmd.*` call. Grep-gate the package after edits: `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/` (MUST be 0) and `grep -rnE "\.exec_\(\)" biochemeleon/` (must be on QFileDialog/QMessageBox/`_show_help` QDialog only, NEVER on the main PluginDialog which uses `dialog.show()` at `biochemeleon/__init__.py:151`).
- Test coverage: 10 headless smoke tests in `smoke/phase*_smoke.py` cover the cmd-coupled paths; pure-layer pitfall rules are pinned by 125 unit tests in `tests/`.

**No undo (safety-critical invariant — PyMOL Open Source):**
- Files: `biochemeleon/backup.py` (snapshot/restore/discard/verify_intact), `biochemeleon/game.py` (`start` snapshots BEFORE mutation; `cleanup`/`abort_on_error` restore), `tmp/pymol-src/modules/pymol/editor.py:25-36` (`undocontext` no-op stub).
- Why fragile: PyMOL Open Source has NO undo/redo — `undocontext` is a no-op stub (`editor.py:25-36`). Every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure. `backup.snapshot` MUST precede any `mutation.insert_hider` — the backup is the ONLY recovery mechanism. Restore MUST be the two-step `cmd.delete(target)` + `cmd.create(target, backup)` (single-call `cmd.create(existing, backup)` is merge-vs-replace UNVERIFIED C-dispatched; smoke-confirmed REPLACE, but two-step stays for unambiguous failure path).
- Safe modification: NEVER add a destructive `cmd.*` call without a preceding `backup.snapshot`. NEVER re-call `verify_intact` on a backup AFTER `cleanup()`/`abort_on_error()` discarded it — both already run `verify_intact`/`restore` + `discard` internally; re-calling raises `CmdException` on the deleted object. Assert the orchestrator's RETURN value, not a re-derivation.
- Test coverage: `smoke/phase3_smoke.py` 24/24 ALL PASSED (criterion 4 both paths); `backup.py` lifecycle fully smoke-verified.

**Hider sentinel + cleanup rules (data-loss prevention):**
- Files: `biochemeleon/mutation.py` (`insert_hider` sets `segi='GAME'` + `b=-999`; `cleanup_hiders` removes by `segi GAME` ALONE; `fetch_all_hider_ids` reads by `segi GAME and b < 0`), `biochemeleon/registry.py` (keyed by `(object, id)` tuple).
- Why fragile: Cleanup MUST use `segi GAME` ALONE (sentinel-only; hiders are the only atoms with `segi=GAME`). NEVER use `hetatm`/`water`/`solvent`/`not polymer`/`resn PSD`/`HOH`/`DPPC`/`PC`/`OL` as the cleanup filter — these over-match and delete real ligands, ions, waters, and the entire DPPC membrane (Pitfall 9). NEVER cleanup by `resi`/`chain`/per-object `index` (unstable across deletions). The `b < 0` selector is for `fetch_all_hider_ids`/read paths; cleanup by `segi GAME` ONLY. Hiders MUST be inserted INTO the same PyMOL object (`cmd.pseudoatom(object=existing, ...)`), NEVER a separate object (else the player toggles one object to win — Pitfall 2).
- Safe modification: Sentinel is `segi='GAME'` + `b=-999`. Any new cleanup path MUST scope by `segi GAME` + the target object. `cmd.sort(obj)` after `cmd.alter` of `segi`/`chain` is defensive (editing.py:1457: stale canonical order confounds later `create`/`byres`; `sort` reassigns `index` but preserves `id` — safe for the id-keyed registry).
- Test coverage: `smoke/phase3_smoke.py` C2/C4; Pitfall 9 regression tests on membrane demos.

**Plugin entry point + modeless dialog (Pitfall 1 — Tk deprecation):**
- Files: `biochemeleon/__init__.py:5` (`dialog = None` module-level singleton — GC prevention; MUST be module scope, not inside `__init_plugin__`), `biochemeleon/__init__.py:129` (`__init_plugin__(app=None)` — NOT legacy `__init__(self)`), `biochemeleon/__init__.py:151` (`dialog.show()` — modeless, NEVER `.exec_()`), `biochemeleon/__init__.py:144` (modeless comment).
- Why fragile: PyMOL 2.x is Qt-based; Tkinter is deprecated with full expectation of removal by PyMOL 4.0 (per official PyMOL wiki). The main dialog MUST stay modeless (`dialog.show()`) so the 3D viewer stays interactive for the click-to-find loop. All Qt imports via `from pymol.Qt import QtWidgets` (auto-selects PyQt5/PySide2) — NEVER `from PyQt5 import`. `QFileDialog.exec_()` / `QMessageBox.exec_()` / `QDialog.exec_()` on child dialogs ARE allowed (3 current hits: `gui_game.py:345` `_finish_win`, `gui_game.py:404` `_finish_debrief`, `__init__.py:952` `_show_help`).
- Safe modification: After any GUI edit, run `grep -rnE "\.exec_\(\)" biochemeleon/` — every hit MUST be on a child dialog, NEVER on the main PluginDialog. Run the Pitfall-1 grep — MUST be 0 matches package-wide.
- Test coverage: Both grep gates are part of the WSL regression suite; exec_ gate currently at 3 (expected final state, all child dialogs).

**`rep <name>` selector + per-rep counts (rep-inheritance + regression-guard soundness):**
- Files: `biochemeleon/demos.py` (`get_active_reps` uses `rep <name>` selector), `biochemeleon/registry.py` (`counts_by_rep`).
- Why fragile: Per `.planning/STATE.md:285` (Blockers/Concerns `[05-09]`): a freshly-fetched protein has `cartoon` shown by DEFAULT on its polymer (~602 atoms) but NOT `ribbon`. Newly-attached polymer residues INHERIT the cartoon rep. So `count_atoms('obj and segi GAME and rep cartoon')` is nonzero for a cartoon-geometry hider REGARDLESS of which rep the explicit show call used. A regression guard asserting `rep cartoon == 0` on GAME atoms is UNSOUND. The correct way to verify a rep= forwarding fix: assert the requested rep is on GAME atoms but NOT on the rest of the polymer.
- Safe modification: When asserting on `rep <X>` counts for newly-attached polymer residues, account for the polymer's DEFAULT reps. Use `ribbon` (not a default rep) as the discriminator when testing rep forwarding.
- Test coverage: `smoke/phase5_smoke.py` section 5c (ribbon rep support); `smoke/phase4_1_smoke.py` mixed-rep counts.

---

## Scaling Limits

**Large fetched demos (1GZM helix, 3GP6 sheets with full DPPC membrane):**
- Current capacity: 1GZM ~12k atoms (helix-only MemProtMD), 3GP6 ~19k atoms (sheets + DPPC). Phase 11 smoke `3gp6 dry (19221 atoms, all blank chain) game.start succeeds headlessly` (commit `0702563`).
- Limit: Per `.planning/research/PITFALLS.md:479-493`, `cmd.get_model` on a 100k+ atom object with full solvation would OOM. The stripped/dry membrane demos (water + salt removed) stay under ~20k atoms and are tractable.
- Scaling path: Strip water + salt + compress before bundling (per `spec.md:56`). Fetch large demos on-demand (Phase 9 `demos.py` fetch path), never bundle. Show a modeless `QProgressDialog` during fetch + load + strip + generate. Performance budget: Generate on 3GP6 < 30 s; click latency < 200 ms.

**Hider count vs object size:**
- Current capacity: `hider_count_cap` in `biochemeleon/setup_state.py` caps hider count to a reasonable max per `spec.md:11`. The cap is computed from object atom count + rep complexity.
- Limit: Per `.planning/research/PITFALLS.md:366-367`, a hider count too high for a small molecule makes the game unfindable; the player quits. The cap prevents this for bundled demos.
- Scaling path: `setup_state.hider_count_cap` already adapts to object size; verify on any new demo before shipping.

---

## Dependencies at Risk

**PyMOL 2.5.0 open-source API (single hard dependency):**
- Risk: The plugin targets `pymol-open-source` 2.5.0 in conda. Several API contracts verified at the 2.5.0 runtime tier (Phase 3 smoke, 2026-08-06) may change in future PyMOL versions: `cmd.pseudoatom` returns `None`, `cmd.iterate` exposes `ID` uppercase, `cmd.iterate` has no `x/y/z`, `cmd.create(existing, src)` is REPLACE, `cmd.attach_amino_acid` lives in `pymol.editor` (not `cmd`), `undocontext` is a no-op stub.
- Impact: A PyMOL version bump (e.g. 3.0+ removing Tkinter support, or changing `cmd.iterate` symbol casing) could silently break the plugin. The grep gates would NOT catch behavioral changes — only import/`exec_` changes.
- Migration plan: Pin to PyMOL 2.5.0 for v1. For any version bump, re-run all 10 headless smoke tests + the human-verify checkpoint. Re-verify every API contract in `.planning/research/PITFALLS.md` "Phase 3 — Resolved Research Flags" against the new version. The `tmp/pymol-src/modules/pymol/` source tree is the authoritative reference for resolving surprises.

**Python 3.6 syntax constraint (dev shell):**
- Risk: The WSL dev shell runs `python3.6` (3.6.9) for syntax checks + unit tests. Any 3.7+ syntax (walrus `:=`, f-string `=`, positional-only params) breaks the WSL gate. Per `.planning/STATE.md:294` (Blockers/Concerns `[03-01]`): "walrus `:=` is Python 3.8+; python3.6 is 3.6.9 — reaffirms the AGENTS.md constraint to avoid 3.7+ syntax."
- Impact: A 3.7+ syntax edit would pass at runtime in Windows PyMOL (which uses a newer Python) but fail the WSL syntax gate, creating a false-negative test signal.
- Migration plan: Keep v1 code at 3.6-compatible syntax. If the dev shell is upgraded, update `AGENTS.md` and re-run the full test suite.

**External Python libraries (gated by spec.md):**
- Risk: Any library beyond `pymol-open-source` (PyQt5 via `pymol.Qt`, numpy) requires user approval + vendoring into `./3rd_party_lib/` (gitignored) with the library's license noted (`spec.md:86-87`). v1 uses NO external libs beyond the shipped ones.
- Impact: Adding a lib silently violates the spec. The `opencode.json` `pip *`/`apt *`/`conda *` `ask`-gate is the first line of defense.
- Migration plan: For v2, if a lib is needed, write the list to a file + seek user approval + state whether the user must set up a linux-like env or can keep the "calling cmd from WSL" approach.

---

## Missing Critical Features

**v2 VMD tcl script (deferred per `spec.md:58-61`):**
- Problem: `spec.md` requires BOTH a PyMOL plugin (v1) AND a VMD tcl script (v2). v2 is deferred — `AGENTS.md:5` notes "v1 (PyMOL 2.5.0 plugin). v2 (VMD tcl script) is deferred per `spec.md`; this file is v1-scoped; revisit it when v2 research begins. When the active milestone becomes v2, flag that AGENTS.md needs a VMD/tcl-specific rewrite."
- Blocks: The VMD half of the spec is not implemented. VMD has many more materials and representations; `spec.md:61` requires research to limit the representations this game could play on. `spec.md:60` requires seeking user approval for any additional vmd tcl lib (e.g. `tooltip.tcl`).
- Fix approach: When v2 begins, rewrite `AGENTS.md` for VMD/tcl specifics. Re-research representation limits + tcl lib needs. Do NOT reuse the PyMOL-specific pitfall rules for VMD.

**`surface` representation (explicitly out of scope):**
- Problem: `GAME_REPS = ['lines','sticks','spheres','cartoon','ribbon']` in `biochemeleon/setup_state.py` — `surface` is explicitly out of scope per `spec.md` and `AGENTS.md:82`. Per `.planning/research/PITFALLS.md:235`: "surface is a computed mesh over an object and doesn't 'blend' a foreign atom in any useful way."
- Blocks: Players cannot play the game on `surface` representation.
- Fix approach: Out of scope for v1. If v1.x/v2 adds surface, it requires a fundamentally different hider mechanism (computed mesh, not atom insertion).

---

## Test Coverage Gaps

**GUI/Qt code is NOT automated (human-verify checkpoints only):**
- What's not tested: `biochemeleon/__init__.py` (PluginDialog, `_on_start`, `_on_win`, `_show_help`, `_on_found_mgmt`), `biochemeleon/gui_setup.py` (SetupTab full UI), `biochemeleon/gui_game.py` (GameTab, `_finish_win`, `_finish_debrief`, `_show_all_hiders_for_debrief`, `_on_pick_color`), `biochemeleon/wizard.py` (PickWizard). None of these can be exercised in WSL — Qt needs a real display.
- Files: `biochemeleon/__init__.py`, `biochemeleon/gui_setup.py`, `biochemeleon/gui_game.py`, `biochemeleon/wizard.py`.
- Risk: Regressions in GUI/Qt code may not be caught until a human runs the Windows smoke test. Per `.planning/STATE.md:14` + `AGENTS.md:23`: "Qt/GUI smoke tests remain human-verify checkpoints." Several Phase 4/5/6/7/10 bugs (e.g. `c68a1a4` do_select routing, `9ec0c16` win-loop bugs, `01c48f6` win-display bugs, `c9c2169` hint color persistence + backup corruption) were caught ONLY at the human-verify checkpoint — headless smoke structurally cannot catch color-persistence / modal-timing / wizard-lifecycle / button-mode bugs.
- Priority: HIGH — but inherent to the WSL/Windows split. Mitigation: every GUI-touching plan ends with a `checkpoint:human-verify` plan (Pattern: Phase 4 04-06, Phase 5 05-05, Phase 6 06-03, Phase 7 07-03, Phase 10 10-09).

**cmd-coupled code verified only by headless smoke (manual staging required):**
- What's not tested in WSL unit tests: `biochemeleon/demos.py`, `biochemeleon/backup.py`, `biochemeleon/mutation.py`, `biochemeleon/game.py` (controller wiring), `biochemeleon/persistence.py` (cmd-paths). These are cmd-coupled — `py_compile` is syntax-only, the unit tests exercise only the pure layer.
- Files: `biochemeleon/demos.py`, `biochemeleon/backup.py`, `biochemeleon/mutation.py`, `biochemeleon/game.py`, `biochemeleon/persistence.py`.
- Risk: Regressions in cmd-coupled code may not be caught until a headless smoke is run (which requires `bash wsl2win_cp.sh` + staging to `tmp/bioCHEMeleon/` + `cmd.exe /c C:\src\run-conda-pymol.bat -cq <script>`). The smoke tests are comprehensive (10 files: phase3..phase11 + phase4_1) but must be re-run manually after any cmd-coupled edit. Per `.planning/STATE.md:48`: "headless smoke cannot catch color-persistence bugs (count-back-to-orig passes even when colors stay wrong — the human-verify checkpoint catches what the smoke structurally cannot)."
- Priority: MEDIUM — the headless bridge closes most of the gap, but color-state + modal-timing bugs remain human-only.

**Color-persistence bugs structurally missed by headless smoke:**
- What's not tested: Per `.planning/STATE.md:41` (Phase 6 06-03 bug 3): "hint orange color persists after cleanup + ROOT CAUSE backup corruption — cleanup() originally did sentinel-remove + verify + discard but did NOT restore hint()-colored real neighbor atoms to original colors. ROOT CAUSE: hint()'s `around`/`near` selection crossed object boundaries, coloring atoms in the _bchm_backup object (coordinate-identical copy) too, corrupting the backup's colors." The headless smoke's count-back-to-orig passed even though colors were wrong. The human-verify checkpoint caught it.
- Files: `biochemeleon/game.py` (`hint()`, `cleanup()`), `biochemeleon/backup.py` (`restore`).
- Risk: Any future code that colors real atoms (hint, reveal, found-recolor) + then relies on cleanup to restore colors could regress the same bug class if the selection crosses object boundaries. The fix pattern: `hint()` selection ends with `and <target_obj>` to restrict to target object only; cleanup via `backup.restore` (delete+create two-step) restores atom count AND original colors in one step.
- Priority: MEDIUM — mitigation is in place (`hint_sele` helper scopes to target; `cleanup()` calls `backup.restore`), but the structural gap remains: headless smoke cannot catch color-state regressions.

**Headless smoke coverage of post-win cleanup-on-imported paths:**
- What's not tested by early smokes: Per `.planning/STATE.md:180` (Phase 8 08-05): "The bug: cleanup() discards the post-import backup (backup.discard + _backup_name=None); subsequent Cleanup-on-imported or Restart-on-imported does `cmd.delete(target) + cmd.create(target, None)` — the create fails on a None/absent backup, leaving the target DELETED (empty scene)." The early smoke tested Restart/Cleanup-on-imported mid-game (backup intact) but NOT post-win (backup discarded), so the bug slipped to human-verify. Fix: `if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()` in `_finish_win`.
- Files: `biochemeleon/gui_game.py` (`_finish_win`, `_finish_debrief` cleanup gate).
- Risk: Any future change to the cleanup-on-imported vs non-imported branching could regress the same bug class if the smoke doesn't cover the full lifecycle (start → play → WIN → cleanup/restart).
- Priority: MEDIUM — smoke Section N now regression-tests both post-win paths (N1 win → cleanup-on-imported → count==orig; N2 win → restart-on-imported → count==orig+1). Pattern for future smokes: cover the full lifecycle, not just mid-game states.

---

*Concerns audit: 2026-08-18 (v1 complete + verified; no open bugs; concerns describe fragility surface for maintenance + v2)*
