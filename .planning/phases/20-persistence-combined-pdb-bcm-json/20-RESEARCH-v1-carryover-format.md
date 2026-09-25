# Phase 20: Persistence — v1-Carryover Format Research (lane a of 3)

**Researched:** 2026-09-26
**Domain:** v1 (PyMOL Phase 08, SHIPPED) save/load/share persistence → v2 (VMD tcl) `.bcmz` = combined-PDB + `.bcm` JSON sidecar format spec
**Confidence:** HIGH for the v1 format (extracted verbatim from SHIPPED, human-verified code — Phase 08 closed 3/3 criteria, 78/78 smoke, 131/131 unit tests per `08-VERIFICATION.md`); HIGH for the v2 schema mapping (every field anchored to a landed v2 module or a pinned Phase 18/19 plan contract); MEDIUM for two items flagged inline (zip mechanism existence; Phase 18/19 not yet landed — schema fields are forward-compat contracts).

**Lane scope:** This document owns the **format** — what v1 did, what the v2 file must contain, the reconciliation-by-index algorithm, Generate&export vs Save semantics, the import/resume state machine, and the error taxonomy. It deliberately does NOT research the zip/JSON/reload **mechanics** (lane b) or the GUI/integration **seams** (lane c) — but it defines the format precisely enough for both to implement against.

---

## 1. Executive Summary

v1 shipped a `.bcmz` save as a stdlib zip of two fixed-name entries — `game.pse` (a PyMOL session scoped to the target object) + `game.bcm` (a hand-built JSON sidecar with `magic`/`version`/`kind`/`target_object`/`started`/`timer_elapsed`/`reveal_count`/`hint_count`/`found_color`/`found_color_rgb`/`registry`/`setup`) — and an import that loads the archive, merges the session, rebuilds the registry from sentinels, and reconciles per-hider `rep` + `status` by atom `id` (three mismatch lists: `missing_from_bcm` / `missing_from_pse` / `bad_rep`; never raises — degraded is playable). Generate&export and Save share ONE schema + ONE archive path, discriminated only by `kind` (`'puzzle'` forces `started=False`, `timer_elapsed=0.0`; `'checkpoint'` stores live values).

v2 ports the same architecture with three structural deltas and one capability inversion:

1. **No `.pse` equivalent.** The archive's geometry entry becomes the **combined PDB** (`game.pdb`, produced by the already-landed `mutation::write_combined_pdb`). The PDB carries real + hider atoms and the sentinel fields that survive `writepdb` (`resname GAM`, `beta -999` on simple hiders / residue CAs, `segid GAME`, occupancy, chain G, resid 9001 / 9001+k) — but `writepdb` **loses `user`/`user2`/`user3`** (Pitfall 7) and carries **no reps, viewpoint, materials, or colors**. Therefore everything v1's `.pse` silently carried — camera, representations, per-atom found coloring — must move INTO the `.bcm` JSON as new `viewer` + registry fields. This is the core v1→v2 format change.
2. **Reconcile by `index`, not `(object, id)`.** VMD has no global atom id; identity = `(molid, index)`, and `index` is stable across a reload of the *identical* combined PDB (deterministic writepdb atom order + hiders appended in record order). The reconcile algorithm is v1's `reconcile_with_bcm` with the key changed from `(object, id)` to `index` — same three mismatch lists, same never-raise contract — plus a v2-only `resid_block` reconciliation for the residue-sentinel family (fake-resid → CA map).
3. **Import collision check dissolves.** v1 refused import when the target object name already existed (`.pse` merge collision, C-level UNVERIFIED). v2's `mol new` creates a NEW molecule with a fresh monotonic molid — there is no name and no collision. That entire v1 error class disappears; the v2 analog is "an active round is cleaned up first" (already guaranteed by `game::start_game`'s 16-13 active-game guard).
4. **Capability inversion on viewer state.** v1's `.pse` preserved per-atom colors, custom named colors, reps, AND camera for free — v1's `.bcm` needed almost no viewer state (only the defensive `found_color_rgb` hook, which shipped always-null). v2's PDB preserves none of that: the `.bcm` gains `viewer.reps` (scene rep list {style selection color material}), `viewer.viewpoint` (the viewmaster 4-matrix list), `found_colorid` (an integer VMD ColorID — Phase 19 locked out `tk_chooseColor`, so there is **no RGB triple and no `found_color_rgb` analog**), and `found_visible` (Phase 19's hide/show-found state). Per-hider found coloring is reproduced by re-stamping `user2` (found flag) + `user3` (tier code) from the `.bcm` BEFORE any rep selection is re-applied (the hiders.tcl cached-selection ordering contract).

**Primary recommendation:** Port the v1 schema **as version 2 of the same format** — same `magic` (`BIOCHEMELEON-BCM`), same `kind` discriminator, same never-raise reconcile, same degradation ladder — with `version: 2`, `game.pse`→`game.pdb`, `target_object` **dropped** (molids are session-local; the PDB *is* the molecule), and the new fields `original_pdb`, `hider_count`, `found_colorid`, `found_visible`, `viewer.reps`, `viewer.viewpoint`, and `registry.resid_block`. A v1 file must be **refused with a version error** (its registries key on atom `id`, its geometry entry is a PyMOL pickle — cross-version load is meaningless). Build/parse the JSON in a PURE tcl layer (`dict` in, `dict` out) so the round-trip is `tcltest`-unit-testable in WSL exactly like v1's `tests/test_persistence.py` pattern.

---

## 2. v1 Format — Extracted Verbatim (SHIPPED, source of truth)

Everything in this section is read from the shipped, verified v1 code. These decisions are VALIDATED — port them unless a v2 constraint forces a delta (deltas are called out explicitly in §3/§4).

### 2.1 Constants (pymol/biochemeleon/persistence.py:35,40)

```python
BCM_MAGIC   = 'BIOCHEMELEON-BCM'
BCM_VERSION = 1
```

### 2.2 The `.bcm` top-level dict — `build_bcm_dict` (persistence.py:92-110)

Exact emission order (v1 emitted `json.dumps(bcm_dict, indent=2)` — stable, human-readable):

| # | Field | Type | Value / rule | Line |
|---|-------|------|--------------|------|
| 1 | `magic` | str | `'BIOCHEMELEON-BCM'` | :93 |
| 2 | `version` | int | `1` | :94 |
| 3 | `kind` | str | `'checkpoint'` (Save) or `'puzzle'` (Generate&export); `ValueError` on anything else | :95, :75-77 |
| 4 | `target_object` | str | `controller.target_obj` (the PyMOL object name — survives inside the `.pse`) | :96 |
| 5 | `started` | bool | `bool(controller._started)` **if kind=='checkpoint'** else **forced `False`** — the educator generated but never played a puzzle, regardless of the live controller being mid-`start()` | :97-102 |
| 6 | `timer_elapsed` | float | seconds; captured BEFORE the file dialog (pause-capture-dialog-save-resume) | :103 |
| 7 | `reveal_count` | int | | :104 |
| 8 | `hint_count` | int | | :105 |
| 9 | `found_color` | str | `'green'` default; or a custom `cmd.set_color` name | :106 |
| 10 | `found_color_rgb` | None | **forward-compat hook, always None in v1** (never populated — the `.pse` was trusted to preserve colors) | :91, :107 |
| 11 | `registry` | dict | `HiderRegistry.to_dict()` — see 2.3 | :108 |
| 12 | `setup` | dict | the raw `gui_setup.collect_state()` dict, verbatim (not a curated subset — research decision "storage is cheap; curating risks dropping a field") | :109 |

Transient fields explicitly NOT serialized (persistence.py docstring :56-58): `_backup_name`, `_wizard`, callbacks, raw `_start_time` (only the derived `timer_elapsed` crosses the file boundary).

### 2.3 The registry sub-dict (registry.py:375-385 + HiderRecord.to_dict :134-159)

```python
{'version': 1, 'hiders': [record.to_dict(), ...]}   # insertion order
```

Per-record dict (`registry.py:149-158`) — **opt-in emission** keeps sidecars compact and backward-compatible with NO version bump:

| Field | Type | Emitted when |
|-------|------|--------------|
| `id` | int | always (required) — PyMOL global atom id, the reconcile key |
| `object` | str | always (required) — the owning object name; part of the `(object, id)` key |
| `rep` | str \| None | always — one of `GAME_REPS` (`['lines','sticks','spheres','cartoon','ribbon']`), or `None` post-sentinel-rebuild |
| `status` | str | always — `'hidden'` \| `'found'` |
| `pos` | [x,y,z] | only if not None (vestigial — no runtime reader, state-reconstruction research §10.5; kept for losslessness) |
| `is_altconf` | true | only if truthy (Phase 11) |
| `endpoint_resvs` | [r1,r2] | only if not None (Phase 11; JSON list, coerced to tuple on read) |
| `alt_tag` | str | only if truthy (Phase 11) |

### 2.4 Parse + guards — `parse_bcm_dict` (persistence.py:113-145)

- `json.loads`; on failure → `ValueError("could not parse .bcm JSON: %s")`.
- `d.get('magic') != BCM_MAGIC` → `ValueError("not a bioCHEMeleon sidecar (magic=%r, expected %r)")`.
- `int(d.get('version', 1)) > BCM_VERSION` → `ValueError("unsupported .bcm version %d (expected %d). Please update bioCHEMeleon.")` — refuse-newer; older/missing version tolerated (`from_dict` tolerance pattern).

### 2.5 Apply + reconcile — `apply_bcm_dict` (persistence.py:150-192) → `reconcile_with_bcm` (registry.py:447-510)

`apply_bcm_dict` re-checks magic/version, sets `_reveal_count`/`_hint_count` (`int`, default 0) and `_found_color` (`str`, default `'green'`), then calls `controller.registry.reconcile_with_bcm(bcm_hiders)`.

`reconcile_with_bcm` — the load-bearing merge (full algorithm at registry.py:472-510):

1. Index `.bcm` hiders by `(h['object'], int(h['id']))`; malformed entries (KeyError/TypeError/ValueError) are **skipped silently**.
2. Walk the **sentinel-rebuilt records** (source of truth = loaded atoms). For each:
   - No `.bcm` match → `missing_from_bcm.append(key)`; record **stays `rep=None`, `status='hidden'`** (a real, clickable atom — playable).
   - Match → set `rec.rep = bcm_rep` (if `bcm_rep not in GAME_REPS` and not None → `bad_rep.append(...)`, **rep stays None, do NOT raise**); set `rec.status` (invalid → default `'hidden'`); restore `pos` if present; restore Phase-11 alt-conf fields with defaults.
3. Walk the `.bcm` index: any key not among sentinels → `missing_from_pse.append(key)` — **ghost entries are NOT registered** (a hider with no atom would corrupt `counts_by_rep` and make the win condition unreachable — state-reconstruction research §2.2).
4. Returns `ReconcileMismatches(missing_from_bcm, missing_from_pse, bad_rep)` — **never raises**; the caller logs warnings and proceeds (degraded is playable).

### 2.6 Archive I/O — `write_bcmz` / `read_bcmz` (persistence.py:195-248)

- **Layout:** `zipfile.ZipFile(bcmz_path, 'w', zipfile.ZIP_DEFLATED)`; entries are the **fixed names** `game.pse` (written from a temp file by the caller after a scoped `cmd.save(pse_path, target_obj)` — bare object name excludes `_bchm_backup`, PyMOL `exporting.py:973-977`) and `game.bcm` (`zf.writestr`, `json.dumps(..., indent=2)`). **No manifest** — the `.bcm` IS the manifest (magic + version + kind). Fixed inner names are a deliberate contract ("the archive is the unit of sharing; inner names are fixed; avoids basename collisions").
- **Read:** validate `game.bcm` in namelist → else `ValueError("not a bioCHEMeleon archive (missing game.bcm)")`; `game.pse` → `ValueError("archive missing game.pse (cannot reconstruct)")`; parse the `.bcm`; extract the `.pse` to `tempfile.mkdtemp(prefix='bchm_import_')/game.pse`. Returns `(pse_path, bcm_dict)`.

### 2.7 `resolve_target` (persistence.py:251-279)

Prefer `bcm_dict['target_object']` if present among loaded molecules; fallback = before/after diff of loaded molecule objects (excluding `_`-prefixed); unambiguous single new object wins; else `None` → import refuses. *(v2 delta: this entire function dissolves — `mol new` returns the molid directly; there are no object names. See §4.)*

### 2.8 `GameController.import_state` (game.py:327-367) — the 5-step reconstruction

```
1. guard: _started -> RuntimeError("game already started; call cleanup() first")
2. reconstruct_registry()            # sentinel rebuild: rep=None, all hidden
3. apply_bcm_dict(self, bcm_dict)    # reconcile + set counters/found_color
4. defensive found-color re-apply    # cmd.color per found record (idempotent;
                                     # .pse preserves color but re-apply is
                                     # future-proof) — research §4.2
5. backup.snapshot(target_obj)       # FRESH post-import backup = the "original"
   _started=True; _is_imported=True; _imported_bcm=bcm_dict
```

Step 5's ordering is deliberate (state-reconstruction research §6.4): snapshot **AFTER** reconcile + re-color, so Cleanup/Restart restore the imported state (puzzle → all-hidden initial state; checkpoint → found-status as saved). `_imported_bcm` is retained on the controller so Restart-on-imported can re-reconcile `rep` without re-reading the file (export-import research §6.2).

### 2.9 Save flow — `_on_save` (`__init__.py:745-788`)

```
guard: controller None / not _started / _start_time None  -> silent return (countdown guard)
game_tab._timer.stop()                       # PAUSE
elapsed = time.time() - _start_time          # CAPTURE (before the modal dialog)
QFileDialog.getSaveFileName(... "(*.bcmz)")  # DIALOG
  cancel -> _start_time = now - elapsed; timer.start(1000); return   # REBASE
suffix guard: append '.bcmz' if missing
build_bcm_dict(kind='checkpoint', elapsed=elapsed)
cmd.save(pse_tmp, target_obj)                # scoped: bare name excludes backup
write_bcmz(path, bcm_dict, pse_tmp); os.unlink(pse_tmp)
_start_time = time.time() - elapsed          # REBASE (dialog+save time not counted)
game_tab._timer.start(1000); log("Saved checkpoint to %s")
```

The pause-capture-dialog-save-resume order implements the PITFALLS.md timer pitfall fix (state-reconstruction research §11: capture BEFORE the dialog; rebase on cancel AND after save).

### 2.10 Generate&export flow — `_on_export` (`__init__.py:679-720`)

```
_prepare_and_start(state)                    # the "truncated Start": resolve target,
                                             # collapse, build specs, free valences,
                                             # clean prior game, controller.start()
                                             # — identical to _on_start steps 1-4
QFileDialog.getSaveFileName("Generate & export puzzle", "(*.bcmz)")
  cancel -> controller.cleanup(); return     # don't leave generated hiders dangling
build_bcm_dict(kind='puzzle')                # started forced False, timer 0.0
cmd.save(pse_tmp, target_obj); write_bcmz; unlink
QMessageBox("Puzzle exported ... Press Cleanup to restore your scene.")
# stays on Setup; controller stays _started=True so Cleanup (BTN-06) works
```

Plus the **async guard** (`_update_export_enabled`, `__init__.py:722-743`): Export is disabled for uncached fetched demos so the export can never reach the fetch continuation (which bakes in Start's tab-switch + countdown — wrong for export). *(v2 port note: this guard becomes relevant again after Phase 21.)*

### 2.11 Import flow — `_on_import` (`__init__.py:790-868`)

```
QFileDialog.getOpenFileName("(*.bcmz)")
read_bcmz(path) -> (pse_path, bcm_dict)                    # 1. unzip + parse
refuse-first collision: target_object already loaded -> warn + return   # 2.
clean prior game (wizard teardown + controller.cleanup)     # 3.
names_before = get_names(public, enabled_only)              # 4.
cmd.load(pse_path, partial=1)                               #    MERGE, not wipe
resolve_target(bcm, names_before, loaded_molecules)         # 5.
GameController(target_obj); import_state(bcm_dict)          # 6. (§2.8)
switch to Game tab; elapsed = bcm['timer_elapsed']
start_countdown(controller, elapsed=elapsed)                # 7. resume
```

`start_countdown(controller, elapsed=0)` (`gui_game.py:234`) seeds `_reveal_label` from `controller._reveal_count` (not hardcoded 0), shows the resumed time during the 3-2-1 countdown, and `_begin_play` guards `if self._controller._start_time is None` so a resumed `_start_time` set by the import is not clobbered (`08-VERIFICATION.md` GUI row).

### 2.12 kind semantics — the locked discriminator (shipped behavior, research §3.7)

| Aspect | `kind='puzzle'` (BTN-05 Generate&export) | `kind='checkpoint'` (GAME-09 Save) |
|---|---|---|
| When written | Educator generates + exports, never plays | Player presses Save mid-game |
| `started` | **forced `False`** even though the live controller is `_started=True` after `start()` | `True` |
| `timer_elapsed` | `0.0` | live elapsed, captured before the dialog |
| registry statuses | all `'hidden'` | mix of found/hidden |
| `reveal_count`/`hint_count` | `0` | live counts |
| Import UX | fresh start: countdown, timer from 0 | resume: timer continues from `timer_elapsed` |
| Everything else | identical schema, identical archive path, different dialog title | same |

Both kinds use ONE `build_bcm_dict` + ONE `write_bcmz` — the `kind` field is the only difference in the bytes.

---

## 3. v2 `.bcmz` Format Specification

### 3.1 Archive contract

| Aspect | v1 (shipped) | v2 (this spec) |
|---|---|---|
| Container | zip (`ZIP_DEFLATED`), extension `.bcmz` | same — `.bcmz`, one file, standard zip |
| Geometry entry | `game.pse` (PyMOL session pickle) | **`game.pdb`** (the combined PDB — `mutation::write_combined_pdb` output) |
| Sidecar entry | `game.bcm` (JSON, `indent=2`) | `game.bcm` (hand-rolled JSON, see §3.4) |
| Inner names | fixed contract, no manifest | same: fixed names `game.pdb` + `game.bcm`; no manifest (the `.bcm` is the manifest) |
| Temp extraction | `tempfile.mkdtemp(prefix='bchm_import_')` | same pattern — **BUT the extracted `game.pdb` must live at a STABLE path** (e.g. `$env(TEMP)/biochemeleon_import.pdb`), because the post-import backup snapshot records it and `backup::restore` re-reads `filename` at a LATER cleanup/restart. A deleted temp dir would break cleanup. *(lane b/c concern; format consequence flagged here)* |

**The `game.pse`→`game.pdb` inner-name change is load-bearing for errors:** a v1 `.bcmz` opened by v2 fails with "archive missing game.pdb (cannot reconstruct)" — a clean, self-explanatory refusal. Do not "helpfully" accept `game.pse`.

**Zip mechanism — flagged, not researched here (lane b):** Tcl 8.5.6 core has **no `zlib`** (entered core in 8.6), and no zip capability was found in `vmd-ref/scripts/` or `vmd-ref/plugins/` (checked 2026-09-26). Roadmap SC1 says "zipped into a `.bcmz`" — the *contract* is locked; the *mechanism* (some VMD-shipped capability, a hand-rolled store-only zip writer, or a fallback two-file pair) is lane b's probe. If no zip path exists, the fallback (two files `X.pdb` + `X.bcm` by naming convention, or a hand-rolled uncompressed container) **requires a planner/user checkpoint** because it deviates from SC1. The schema below is container-agnostic.

### 3.2 What lives in the PDB vs the JSON (the partition)

The combined PDB (`game.pdb`) is written by the landed `mutation::write_combined_pdb` (`vmd/lib/mutation.tcl:466-496`): `atomselect all writepdb` → strip `END`/blank lines → append hider `ATOM` records (78-col probe-pinned layout, `mutation.tcl:436-446`) → `END`. Its content after `mol new ... type pdb waitfor all`:

**Survives in the PDB (nothing about these goes in the JSON):**
- All real atoms, byte-faithful coordinates/elements/resnames/chains/resids.
- Hider sentinel fields: `resname GAM` (cols 18-20), `chain G`, `resid 9001` (simple hiders, all sharing `HID_RESSEQ`) or `9001+k` (fake residue blocks, `splice::RESID_BASE 9001`), `beta -999.0` on every simple hider atom and on **residue CAs only** (`tag_sentinels_mixed` sets N/C/O/CB to `beta 0.00` + `segid GAME`), `segid GAME`, occupancy 1.00.
- Consequence: `fetch_hider_indices` (`resname GAM and beta < 0`) works identically on the reloaded molecule, and **index layout is deterministic** (writepdb preserves index order; hiders appended in record order — simple records first, then residue records in record order, `mutation.tcl:532-540`). This determinism is what makes index-keyed reconciliation sound.

**LOST by the PDB (must live in the JSON):**
- `user` / `user2` / `user3` atom fields (Pitfall 7: `writepdb` does not persist script-modified `user*`; `user2` = found flag, `user3` = tier code, `user` = hider ordinal — `hiders.tcl:75-76`, `mutation.tcl:501-502`).
- ALL representations (the scene's base reps AND the 2N per-tier hidden/found hider reps), their colors, materials, selections.
- Viewpoint (rotate/center/scale/global matrices).
- Found color (a ColorID preference), found visibility (hide/show state).
- Everything v1's `.bcm` already carried: registry, timer, counters, kind, setup.

**v1→v2 capability loss (accepted, documented):** v1's `.pse` preserved per-rep show/hide toggles and any ad-hoc reps the user made. v2 persists **only** the rep list (style/selection/color/material — the `backup::snapshot` shape, `backup.tcl:39-49`) and the viewpoint; individual rep on/off showstate (other than found-visibility, which gets its own field) is NOT persisted. v1's `pos` per-hider field is also dropped — it was vestigial in v1 (no runtime reader) and v2 never had it.

### 3.3 Schema version + magic

```tcl
# vmd/lib/persistence.tcl (new pure module — lane b/c placement per AGENTS.md
# dependency direction: setup_state.tcl <- registry.tcl <- persistence.tcl <- game.tcl)
variable BCM_MAGIC   "BIOCHEMELEON-BCM"
variable BCM_VERSION 2
```

- `version == 2` → accept (current).
- `version > 2` → refuse: `"unsupported .bcm version %d (expected %d). Please update bioCHEMeleon."` (v1 wording, verbatim port).
- `version == 1` → refuse: `"this is a v1 (PyMOL) file; the VMD version reads v2 files only."` — v1 registries key on atom `id` and the geometry entry is a PyMOL pickle; cross-version load is meaningless. Refuse is correct, not degrade.
- `magic != "BIOCHEMELEON-BCM"` → refuse: `"not a bioCHEMeleon sidecar (magic=%s, expected BIOCHEMELEON-BCM)"` (v1 wording).
- Registry sub-dict keeps its own `"version": 1` (v1 parity — the registry shape is unchanged in spirit; the top-level `version: 2` discriminates the file).

### 3.4 The `.bcm` JSON — exact schema (version 2)

Hand-rolled emit/parse with tcl 8.5 `dict` (SC4). The schema deliberately constrains itself to a JSON subset that a ~60-line Tcl emitter and ~80-line parser can handle with zero edge cases:

**JSON subset rules (binding for the emitter/parser):**
1. **No JSON booleans** — use integers `0`/`1` (v1 used Python bools → `true`/`false`; v2 avoids a bool branch in the Tcl emitter entirely).
2. **No `null`** — optional fields are **omitted** when empty/absent (parser applies defaults; mirrors v1's opt-in emission).
3. **Strings are restricted:** no `"`, no `\`, no control characters, no newlines. Paths are stored with **forward slashes** (`C:/...` — the `to_vmd_path` convention; `backup.tcl:103-105` confirms `molinfo get filename` already returns the exact `C:/` path passed to `mol new`). The emitter STILL escapes `"` → `\"` and `\` → `\\` defensively (2-rule escaper), and the parser handles both — but well-formed writers never need it.
4. **Numbers:** integers without decimal point; floats via Tcl's default double stringification (round-trip-exact since Tcl 8.5's David Gay shortest-representation conversion — the viewpoint matrices round-trip bit-exact).
5. **Nesting depth ≤ 3** (root → `registry`/`viewer`/`setup` → hider records / rep records).
6. Emit **in schema order** (stable diffs, human-readable, mirrors v1's fixed emission order); parse order-independent.
7. UTF-8, `\n` line endings, `indent`-style pretty-printing allowed (v1 parity: `json.dumps(indent=2)`) — pretty-printing is a lane-b free choice; the parser must accept both pretty and compact.

**Top-level object (emission order):**

```json
{
  "magic": "BIOCHEMELEON-BCM",
  "version": 2,
  "kind": "checkpoint",
  "started": 1,
  "timer_elapsed": 42,
  "reveal_count": 1,
  "hint_count": 2,
  "found_colorid": 7,
  "found_visible": 1,
  "hider_count": 12,
  "original_pdb": "C:/Users/edu/puzzles/1ubq.pdb",
  "viewer": {
    "viewpoint": [0.978, -0.112, 0.176, 0.0,  ... 64 numbers total ...],
    "reps": [
      {"style": "NewCartoon", "selection": "protein", "color": "Name",  "material": "Opaque"},
      {"style": "VDW",        "selection": "resname GAM and beta < 0 and user2 < 1 and user3 1",
       "color": "Name", "material": "Translucent"}
    ]
  },
  "registry": {
    "version": 1,
    "hiders": [
      {"index": 2597, "rep": "VDW",      "status": "found"},
      {"index": 2598, "rep": "Cartoon",  "status": "hidden"}
    ],
    "resid_block": [
      {"resid": 9001, "index": 2598}
    ]
  },
  "setup": {
    "format": "biochemeleon-setup-v2",
    "target_mode": "loaded",
    "selected_object": "1ubq.pdb (0)",
    "pdb_code": "",
    "demo_id": "1znf",
    "hider_count": 10,
    "lock_scene": 0,
    "per_rep": {"VDW": 6, "Cartoon": 4},
    "difficulty_easy": 1,
    "lock_source": 0,
    "pdb_pool": []
  }
}
```

**Field-by-field spec:**

| Field | Type | Default on load | Producer (v2 source) | v1 analog / delta |
|---|---|---|---|---|
| `magic` | str const `"BIOCHEMELEON-BCM"` | — refuse if mismatch | constant | **unchanged** |
| `version` | int `2` | — refuse if >2 or ==1 | constant | v1 was `1` |
| `kind` | str `"checkpoint"` \| `"puzzle"` | — refuse other | caller of build | **unchanged** (same discriminator, same forcing rules §5) |
| `started` | int 0\|1 | `0` | `game_logic::state` mapped: `playing`/`won` → 1; forced `0` when `kind="puzzle"` | v1 bool → **v2 int** (subset rule 1) |
| `timer_elapsed` | int seconds | `0` | `game_logic::timer_elapsed` (clock-seconds delta, integer — `game_logic.tcl:163-175`) | v1 float → **v2 int** (clock seconds granularity; mm:ss display is unaffected) |
| `reveal_count` | int ≥ 0 | `0` | `game_logic::reveal_count` (Phase 19: `+=1` reveal-one, `+=len(hidden)` reveal-all — 19-RESEARCH-mechanisms §B) | **unchanged** name/semantics |
| `hint_count` | int ≥ 0 | `0` | `game_logic::hint_count` (Phase 19) | **unchanged** |
| `found_colorid` | int ColorID 0..32 | `7` (`DEFAULT_FOUND_COLOR` = green, 19-03) | `hiders::found_colorid` preference (19-04 seam) | **replaces** v1 `found_color` (name str) + `found_color_rgb`. v2 has NO custom RGB — `tk_chooseColor` is locked out (19-09 locked decision 1: palette-only); a ColorID needs no re-registration on load (VMD color table is static, 33 IDs — probe5). Emit even when 0 found hiders (it is a preference that persists across rounds — 19-10). |
| `found_visible` | int 0\|1 | `1` | Phase 19 found-mgmt state (`hiders::set_found_visible`; hide=0 after "Hide found") | **new** — no v1 analog (v1 had no hide-found feature). Restore via showrep on the per-tier FOUND reps after reload. |
| `hider_count` | int ≥ 0 | registry hider count | effective total (P9: sum of resolved per_rep — `game.tcl:69-73`) | **new** — v1 derived it. v2 emits it for (a) the sentinel-count integrity gate (§7 E9) and (b) Restart-on-imported parity (`game::restart` needs `hider_count`). |
| `original_pdb` | str (forward-slash path) or omitted/`""` | `""` | `dict get $snapshot filename` from the PRE-GAME `backup::snapshot` (i.e. `molinfo $orig_molid get filename` captured before `mutation::mutate` deleted the original) | **new** — replaces v1 `target_object`. Consumed as: provenance display; preferred Cleanup-on-imported source (`mol new $original_pdb` = the pristine educator molecule — v2 cleanup is whole-molecule reload, so the v1 restore-then-strip dance is unnecessary); fallback when `""` = strip-hiders path (`atomselect "not resname GAM" writepdb` — always available, so `""` is safe, not fatal). NOTE: `backup::snapshot` on the LIVE game molecule returns the combined-PDB temp path, NOT the original — Save must read the ORIGINAL path from the pre-mutate snapshot (`current_state`'s snapshot IS the pre-mutate one — `game.tcl:91-93`), or from `game_state.snapshot.filename`. |
| `viewer.viewpoint` | array of numbers (the flat `molinfo get {rotate_matrix center_matrix scale_matrix global_matrix}` list) | omit → leave current view | `backup::snapshot` field 3 (`backup.tcl:41`) | **new** — v1's camera lived in the `.pse`. Emit the flat list verbatim; on load pass it back positionally to `molinfo set` (same field order — `backup.tcl:85-87` probe-pinned). |
| `viewer.reps` | array of `{style, selection, color, material}` objects | omit → no scene reps beyond hider reps | `backup::snapshot` field 4 (`backup.tcl:42-48`; color/material are NAMES, not indices) | **new** — v1's reps lived in the `.pse`. See §4 step 7 for the scene-rep vs hider-rep replay split. |
| `registry.version` | int `1` | `1` | constant | **unchanged** |
| `registry.hiders[]` | array of records | `[]` | registry walk | v1 record `{id, object, rep, status, pos?, is_altconf?, endpoint_resvs?, alt_tag?}` → v2 record `{index, rep, status}` — **key change: `index` replaces `(object,id)`; `object` dropped** (single molecule); **`pos` dropped** (vestigial); **alt-conf fields dropped** (v1-Phase-11-only; v2 has no alt-conf hiders — residue records are the v2 analog and are covered by `resid_block`). `rep` = GAME_REPS name (`Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds`), or omitted when unknown (`""` sentinel-rebuild default). `status` ∈ `hidden`/`found`. Emit sorted by `index` ascending (deterministic; parse tolerates any order). |
| `registry.resid_block[]` | array of `{resid, index}` | `[]` | the registry's `_resid_block` dict (17.2) | **new** — no v1 analog (v1's dual lookup was alt-conf resv, a different mechanism). The fake-resid → CA map for the multi-atom pick fallback. Emit only when non-empty (residue rounds). Loader validates each `index` is a registered hider; invalid pairs dropped + warned. Re-derivation fallback exists (§4 step 6b) but emitting is preferred (lossless, no edge cases). |
| `setup` | object (the full validate_state dict) | `{}` (degraded) | `setup_tab::collect_state` → `validate_state` output, verbatim | **unchanged policy** (embed the whole dict, not a subset). v2 dict is 11 keys today (`setup_state.tcl:18-29`) and becomes 13 after Phase 18 lands (`material_blending 0`, `per_mat {}` appended last — 18-01). The sidecar round-trips both shapes; unknown keys are ignored on load (forward compat, v1 `from_dict` tolerance pattern). The nested `per_rep` / `per_mat` / `pdb_pool` values serialize per the subset rules (dicts → JSON objects, lists → arrays). |

**Loader tolerance rules (v1 parity, binding):** missing keys → defaults from the table; wrong-typed scalars → coerce (`string is integer/width`) or default + warn; unknown keys → ignore silently (forward compat); `rep` not in GAME_REPS → record stays `rep ""` + `bad_rep` warning (never raise); `status` not hidden/found → `hidden`; hider record missing `index` or non-integer → skip + count as malformed (v1 silently-skipped malformed entries, registry.py:477-480).

### 3.5 Where the pure build/parse lives (the v1 pattern, ported)

v1 kept ALL dict assembly/parsing in a pure module (`persistence.py` — stdlib only, WSL-testable) and left cmd-coupled steps to the orchestrator. v2 mirrors it exactly (AGENTS.md dependency direction):

```
vmd/lib/setup_state.tcl (PURE: SETUP_FORMAT, GAME_REPS, GAME_FOUND_COLORS*, GAME_MATERIALS*)
      ↑
vmd/lib/registry.tcl    (PURE: _records, _resid_block)
      ↑
vmd/lib/persistence.tcl (NEW PURE: build_bcm_dict, parse_bcm_dict, apply_bcm_dict,
      ↑                  bcm_to_json, bcm_from_json  — dict<->JSON text, stdlib file I/O only)
vmd/lib/game.tcl        (orchestrator: save_game/load_game cmd-coupled steps)
      ↑
vmd/gui/{game_tab,setup_tab,dialog}.tcl (composition root: buttons, dialogs)
```

\* Phase 18/19 constants — planned-only as of 2026-09-26 (git log shows docs commits only; `grep` finds no `GAME_MATERIALS`/`GAME_FOUND_COLORS`/`reveal_count` in `vmd/lib/`). Phase 20 depends on 16-19, so at execution time they will have landed; the schema fields `found_colorid`/`found_visible`/`reveal_count`/`hint_count`/`setup.per_mat` are contracts keyed to the pinned plan names (19-03/19-04/19-10, 18-01) and degrade to defaults if absent.

---

## 4. Reconciliation by `index` (vs v1 by `(object, id)`)

### 4.1 The algorithm (port of `reconcile_with_bcm`, registry.py:447-510, key swapped)

Precondition: `mol new $combined_pdb type pdb waitfor all` done → new molid; `registry::reconstruct_from_sentinels` already ran with the DI prefix `list ::biochemeleon::mutation::fetch_hider_indices $new_molid` → `_records` holds every sentinel index with `status=hidden` and `rep=""` (or the single-arg stamped rep — the importer should call the **1-arg form** so `rep` starts `""`, matching v1's `rep=None` semantics; `registry.tcl:44-51`).

```tcl
# PURE (registry.tcl extension — no mol/atomselect; port of registry.py:472-510)
proc ::biochemeleon::registry::reconcile_with_bcm {bcm_hiders} {
    # returns list {missing_from_bcm missing_from_pse bad_rep}  (3 lists; NEVER raises)
    # 1. index .bcm hiders: dict idx -> record; integer-coerce index ("2597" ok);
    #    malformed (missing/non-int index) -> skip silently (v1 parity)
    # 2. foreach reconstructed index:
    #      no match  -> lappend missing_from_bcm $idx          # stays rep "" + hidden
    #      match     -> rep in GAME_REPS ? set : (lappend bad_rep; rep stays "")
    #                   status in {hidden found} ? set : hidden
    # 3. foreach .bcm idx not in _records -> lappend missing_from_pse $idx
    #    (ghost — NOT registered; would corrupt remaining_by_rep + on_pick)
}
```

The v1 → v2 key mapping, line for line:

| v1 (registry.py) | v2 (this spec) |
|---|---|
| key `(h['object'], int(h['id']))` | key `int(h['index'])` |
| walk `self._records` keyed `(object, id)` | walk `_records` keyed `index` |
| `GAME_REPS` membership check → `bad_rep`, rep stays None | identical (v2 `GAME_REPS` is the 10-name list, `setup_state.tcl:10`) |
| status whitelist `(hidden, found)` → default hidden | identical (`HIDER_STATUS_HIDDEN/FOUND`, `registry.tcl:8-11`) |
| `pos` / alt-conf restore | **dropped** (§3.4) |
| returns `ReconcileMismatches` namedtuple, never raises | returns a 3-list, never raises |

**Why sentinel-first survives the port unchanged:** the loaded combined PDB is the *clickable reality* (v1 argument, state-reconstruction research §2.2 — a `.bcm`-only hider is a ghost that makes the win condition unreachable; a sentinel-only hider is a real atom that stays playable). The PDB-rebuild makes this even stronger in v2: the archive's PDB and the registry were written from the same atom walk, so a healthy file reconciles with zero mismatches.

### 4.2 The two sentinel families and the resid-block reconciliation

v2 has TWO sentinel families (v1 had one):

- **Simple hiders:** single atoms, all `resid 9001` (`HID_RESSEQ`, `mutation.tcl:50`), `beta -999`, `segid GAME`, chain G. Each is directly registered (a click on it is a direct hit, `game.tcl:513-517`).
- **Residue hiders:** fake `GAM` residues at `resid 9001+k` (`splice::RESID_BASE 9001`); only the **CA** carries `beta -999` (the registered hider index); N/C/O/CB carry `beta 0.00` + `segid GAME`. A click landing on N/C/O/CB resolves via the **resid block** (`_resid_block`: resid → registered CA index; `registry.tcl:218-244`, `game.tcl:524-526`).

Reconciliation of the resid block (in `apply`-layer code, pure where possible):

1. **Preferred:** read `.bcm` `registry.resid_block`; validate every `index` is registered (post-reconcile); drop invalid pairs with a warning; `registry::register_resid_block` the rest (wholesale-replace contract, `registry.tcl:218-231`).
2. **Fallback (block absent/corrupt):** re-derive from the molecule — for each registered index, read `{resid name}` via a narrow `atomselect index $idx`; if `resid >= 9001` **and** the GAM residue at that resid has more than one atom (`atomselect "resname GAM and segid GAME and resid $r" num > 1`), it is a residue CA → map `resid → idx`. Simple hiders share `resid 9001` with the first possible residue block — disambiguated by the atom-count check (a simple hider is a 1-atom GAM "residue"). Emitting the block in the `.bcm` avoids this edge-prone path entirely; keep the fallback as degraded-mode insurance.
3. The 9001 double-duty is safe at pick time regardless (on_pick consults `is_hider` FIRST — `registry.tcl:194-201`).

### 4.3 What reconcile alone does NOT restore (the v2-specific replay steps)

v1's `.pse` made found-hiders green, reps visible, and the camera right *for free*; v1's post-reconcile work was one defensive recolor loop. In v2 the post-reconcile replay is the load-bearing sequence (each step feeds the next; ordering is pinned by the hiders.tcl cached-selection contract — "a rep added before the user3 stamp would cache an empty selection forever", `game.tcl:130-136`):

```
6.  registry::reconcile_with_bcm            # rep + status per index (§4.1)
7a. derive tier codes: distinct reps among records, ordered by GAME_REPS position
    -> code k (1-based, same derivation as start_game's tiers_from_per_rep order);
    stamp user3 via hiders::stamp_tier_codes                # BEFORE any rep re-apply
7b. set user2 = 1.0 on found indices (float! read-back is 1.0/0.0 — hiders.tcl:228-231)
7c. replay SCENE reps from viewer.reps, FILTERED: skip any rep whose selection
    contains "resname GAM" (those are the game's 2N hider reps — re-derived, not
    replayed, so hiders::tier_reps gets built by the canonical add_hider_reps path
    and future mark_found_visual calls work; verbatim-replay of hider reps is
    REJECTED because it leaves tier_reps empty and silently kills later finds)
    -> for each kept rep: mol addrep + modstyle/modselect/modcolor/modmaterial
       (form B, isolated — backup.tcl:70-84; NEVER the global-default form)
7d. hiders::add_hider_reps with the derived tier specs      # rebuilds tier_reps +
7e. hiders::mark_found_visual re-assert per found index      # tier_styles; the
    (or the set_found_visible equivalent)                    # user2 flags are set,
7f. hiders::set_found_color $molid $found_colorid            # selections re-evaluate
7g. apply found_visible (showrep on/off on the FOUND reps per tier)
8.  molinfo set {rotate_matrix center_matrix scale_matrix global_matrix} $viewpoint
9.  registry::register_resid_block $block                    # §4.2
10. snapshot the post-import state -> the new "original" for Cleanup/Restart
    (v1 game.py:364 parity; snapshot.filename = the STABLE extracted game.pdb path)
```

Steps 7c's filter + 7d's re-derivation reproduce the save-time hider visuals exactly (the per-tier hidden/found selections are deterministic functions of the tier codes, `hiders.tcl:152,162`), and the per-hider `rep` field in the `.bcm` is precisely what makes the derivation possible — it is v2's replacement for v1's "rep lives in the `.pse` rep list".

### 4.4 Restart-on-imported (format consequence)

v1 routed Restart on imported games through the retained `_imported_bcm` (no re-generation; restore post-import backup + re-reconcile). v2 keeps the policy: the imported `.bcm` dict must be **retained** (namespace var or in `current_state`) so Restart-on-imported can re-run §4.3's steps 6-9 after `backup::restore`. The format needs no extra fields for this — the retained dict IS the state. (`game::restart`'s existing re-generation path stays for non-imported rounds.)

---

## 5. Generate&export vs Save Semantics (BTN-05 vs GAME-09)

v1's semantics port **verbatim** — they were verified in a real GUI (08-VERIFICATION criterion 2):

| Aspect | v1 (shipped) | v2 port |
|---|---|---|
| Flow | "truncated Start": `_prepare_and_start` (identical to Start's generate steps) → file dialog → save `kind='puzzle'` → stay on Setup, NO countdown/wizard | identical: run the generate path (`game::start_game` with resolved per_rep) → dialog → save `kind='puzzle'` → stay on Setup |
| `kind='puzzle'` forcing | `started` forced `False` + `timer_elapsed` `0.0` **even though the live controller is mid-`start()`** (the educator generated but never played) — persistence.py:97-102 | same forcing rule in `build_bcm_dict` (kind is the only byte difference from a checkpoint of the same state) |
| Registry in a puzzle | all `'hidden'` (fresh generation) | same (fresh `start_game`) |
| Cancel behavior | `controller.cleanup()` — don't leave generated hiders dangling | same (cleanup the just-started round) |
| Post-export state | controller stays live; educator PREVIEWS the puzzle; explicit Cleanup restores the scene (NO auto-cleanup — research §2.7) | same policy (the active-game guard makes a subsequent Start safe) |
| Save guard | silent return unless `_started` AND `_start_time` set (blocks Save during countdown) | v2 analog: `game_logic::state` must be `playing` (blocks countdown + post-win double-save; the `won` state's frozen `timer_elapsed_final` may be emitted if saving in `won` is allowed — planner's call; v1 allowed it with a UX note) |
| Timer fairness | pause-capture-dialog-save-resume with rebase on cancel AND after save (`__init__.py:745-788`) | same pattern. **v2 delta:** Tk modal dialogs run a local event loop, so the GUI's 1 Hz `after` tick keeps FIRING during `tk_getSaveFile` (unlike v1's Qt modal which froze the QTimer but not `time.time()`). The label will tick during the dialog — cosmetic; the capture-before + rebase-after pattern still fixes the MODEL. Lane c wires it. |
| Fetch-demo guard | `_update_export_enabled` disables Export for uncached fetched demos (async continuation would bake in Start's flow) | port the guard; becomes load-bearing after Phase 21 (fetched demos exist) |
| Dialog titles | "Generate & export puzzle" vs "Save bioCHEMeleon checkpoint" — same filter `(*.bcmz)`, same extension auto-append | same (Tk: `tk_getSaveFile -title ... -filetypes {{bioCHEMeleon} {.bcmz}} -defaultextension .bcmz -parent $w`) |

---

## 6. Import / Resume State Machine

v1 flow (`__init__.py:790-868` + `game.py:327-367`) mapped to v2, with state transitions in terms of v2's explicit machine (`game_logic`: `idle → countdown → playing → won`, `game_logic.tcl:60-82`):

```
[idle] Import clicked (Game tab — lane c placement)
  │
  ├─ tk_getOpenFile (.bcmz) ── cancel → [idle]
  │
  ├─ READ container → (game.pdb stable path, bcm_dict)
  │     └─ any read/parse/magic/version error → warn → [idle]        (E1-E4, §7)
  │
  ├─ GUARD: active round? → cleanup first (or rely on start_game's 16-13 guard
  │     when the resumed round re-starts; explicit cleanup is clearer for import)
  │     * v1's refuse-first NAME COLLISION check DISSOLVES: mol new creates a new
  │       molid; there are no object names and no collisions (v1 __init__.py:816-827
  │       has no v2 counterpart — do not port it)
  │
  ├─ mol new $game_pdb type pdb waitfor all  → new_molid             (E5 on failure)
  ├─ fetch_hider_indices → registry::reconstruct_from_sentinels(1-arg)
  ├─ reconcile_with_bcm + resid_block (§4.1-4.2)                     (E7-E10 → warn)
  ├─ viewer replay §4.3 steps 7a-7g                                  (ordering pinned)
  ├─ viewpoint restore (§4.3 step 8)
  ├─ post-import snapshot (the new "original"; STABLE pdb path)
  ├─ counters + timer seed:
  │     kind=puzzle    → reveal 0, hint 0, found_colorid 7, round_reset → countdown
  │     kind=checkpoint→ reveal/hint from .bcm; timer_epoch seeded at begin_play as
  │                        [clock seconds] - timer_elapsed   (resume math; the pure
  │                        module's optional `now` arg — game_logic.tcl:38-41,151-161 —
  │                        is the injection seam; begin_play must not clobber it,
  │                        v1 gui_game.py:251 guard ported)
  ├─ begin_countdown → [countdown]  (3-2-1; checkpoint shows the resumed time during
  │                                   the countdown — v1 gui_game behavior, lane c)
  └─ begin_play → [playing]         (callbacks re-attached; on_pick scoring active)
```

Degraded paths (v1 fallback ladder, state-reconstruction research §2.3 — port all three):
1. `.bcm` present + parses + version 2 → full reconcile (counters, found-status, reps, timer).
2. `.bcm` present but parse/version/magic failure → **warn + sentinel-only rebuild** (all hidden, `rep ""`, counters 0, timer fresh) — playable; per-rep remaining shows 0-count entries; found-mgmt empty.
3. `.bcm` absent from the archive → same as 2, with the explicit "no sidecar found" message.

Edge states:
- **Imported checkpoint with `remaining == 0`** (saved post-win): the game resumes "won but not cleaned up" — v1 research §12.5 recommended a log note + Cleanup guidance; port as a log line, not an error.
- **`hider_count` vs fetched-sentinel mismatch**: warn (E9) — never abort (v1 §9.5).
- **Win on an imported round**: `finish_win` freezes `timer_elapsed_final` from the resumed epoch — the reported score includes the saved elapsed (v1 parity: `win()`'s elapsed math rides the rebased `_start_time`).

---

## 7. Error Taxonomy (v1 → v2 mapping)

Refuse = hard error, import aborted, message shown, no state mutated. Warn = import proceeds degraded, message logged.

| # | Condition | v1 behavior (shipped) | v2 behavior | Level |
|---|---|---|---|---|
| E1 | Archive unreadable / not a zip | `OSError` from `ZipFile` → "Could not read game file" | container open failure → refuse | REFUSE |
| E2 | `game.bcm` missing from archive | `ValueError("not a bioCHEMeleon archive (missing game.bcm)")` | identical wording (s/#game.bcm/) | REFUSE |
| E3 | geometry entry missing | `ValueError("archive missing game.pse (cannot reconstruct)")` | `"archive missing game.pdb (cannot reconstruct)"` — also fires for a **v1 archive** (its entry is `game.pse`), which is the desired cross-version surface | REFUSE |
| E4 | magic mismatch / JSON parse failure / `version > 2` | `parse_bcm_dict` ValueErrors (§2.4) → "Import failed" | identical strings, version wording updated; `version == 1` → "v1 (PyMOL) file" refusal | REFUSE |
| E5 | `mol new` fails / PDB malformed | n/a (`.pse` load) | catch around `mol new ... waitfor all` → refuse (VMD prints its own parse errors to console) | REFUSE |
| E6 | zero sentinel atoms fetched (no `resname GAM and beta < 0`) | sentinel-rebuild yields empty registry → game with 0 hiders (degenerate but allowed — v1 §10.4) + `.bcm` hiders all flagged `missing_from_pse` | same + stronger message: "no hider sentinels found in the loaded PDB — is this a bioCHEMeleon game.pdb?" | WARN (refuse is defensible; planner's call — v1 allowed empty) |
| E7 | `.bcm` hider index ≥ numatoms or negative | impossible (ids were atom-native) | **v2-new:** out-of-range index → drop + `missing_from_pse`-style warn | WARN |
| E8 | `rep` not in GAME_REPS | `bad_rep`, rep stays None, warn | identical | WARN |
| E9 | `hider_count` ≠ fetched sentinel count | count-mismatch warning (v1 §9.5) | identical (now checkable — the field exists) | WARN |
| E10 | resid-block entry pointing at unregistered index | n/a | drop pair + warn; fallback re-derivation (§4.2) | WARN |
| E11 | status ∉ {hidden, found} | default `hidden`, warn-free (silent safe default) | identical | silent default |
| E12 | malformed hider record (missing/non-int index) | skipped silently (registry.py:477-480) | identical | silent skip |
| E13 | active round during import | explicit teardown (wizard + cleanup) before load | explicit cleanup first (16-13 guard is the backstop) | — |
| E14 | import_state on a live controller | `RuntimeError("game already started; call cleanup() first")` | v2: sequencing guard in the orchestrator (state machine makes this a caller bug) | REFUSE (programmer error) |
| E15 | save with no round / countdown not finished | silent return (guard, `__init__.py:753-755`) | `game_logic::state ne "playing"` → silent return | — |
| E16 | `.bcmz` written by a future version | "Please update bioCHEMeleon." | identical | REFUSE |
| E17 | temp extraction dir deleted before later cleanup/restart | n/a (PyMOL held the session in memory) | **v2-new:** stable-path requirement (§3.1) — the post-import snapshot's `filename` must survive; mitigation = fixed `$env(TEMP)/biochemeleon_import.pdb`, overwritten per import | design constraint |

---

## 8. Don't-Hand-Roll / Port-As-Is Checklist (for the planner)

| Problem | v1 solved it with | v2 must |
|---|---|---|
| Schema versioning + refusal | `magic` + `version` + refuse-newer | port verbatim, version 2 |
| Corrupt-sidecar resilience | never-raise reconcile + 3 mismatch lists + degradation ladder | port verbatim, index-keyed |
| Ghost-entry prevention | `.bcm`-only hiders NOT registered | port verbatim |
| Checkpoint-vs-puzzle discriminator | single `kind` field, forced puzzle zeroing | port verbatim |
| Timer fairness across the modal dialog | pause-capture-dialog-save-resume + rebase | port (note the Tk event-loop delta) |
| Post-import "original" for Cleanup/Restart | snapshot AFTER reconcile/replay | port (snapshot after §4.3 completes) |
| Retained sidecar for Restart-on-imported | `_imported_bcm` on the controller | retain the dict in namespace state |
| Pure-layer testability | pure `build_bcm_dict`/`parse_bcm_dict` + 37 unit tests | port the pattern: pure `persistence.tcl` + tcltest round-trip suite (build → serialize → parse → apply → compare) |
| Don't build | a second setup-file format, a manifest entry, a `.bcm`-inside-PDB hack, a target-name resolver | v2 needs none of these (molids, no `.pse`, `.bcm` is the manifest, `mol new` returns the target) |

---

## 9. Sources

### Primary — v1 SHIPPED code (HIGH; read directly this session)
- `pymol/biochemeleon/persistence.py` — BCM_MAGIC/VERSION (:35,40), build_bcm_dict (:45-110), parse_bcm_dict (:113-145), apply_bcm_dict (:150-192), write_bcmz/read_bcmz (:195-248), resolve_target (:251-279)
- `pymol/biochemeleon/registry.py` — HiderRecord.to_dict (:134-159), HiderRegistry.to_dict (:375-385), from_dict (:388-416), reconstruct_from_sentinels (:420-443), reconcile_with_bcm (:447-510)
- `pymol/biochemeleon/game.py` — import_state (:327-367), cleanup (:369-400)
- `pymol/biochemeleon/__init__.py` — _on_export (:679-720), _update_export_enabled (:722-743), _on_save (:745-788), _on_import (:790-868)
- `.planning/phases/08-persistence-and-shareable-puzzles/` — all three research docs + 5 plan summaries + `08-VERIFICATION.md` (3/3 criteria, 78/78 smoke, 131/131 unit tests, human-verified 2026-08-16)

### Primary — v2 landed code (HIGH; read directly this session)
- `vmd/AGENTS.md` — Tcl 8.5.6 rules, zero-dep rule, sentinel spec, save_state insufficiency (`save_state.tcl:39-46`), no-atom-id rule
- `vmd/lib/mutation.tcl` — hider constants (:46-52), _hider_record (:436-446), write_combined_pdb (:466-496), tag_sentinels (:505-520), tag_sentinels_mixed (:541-579), fetch_hider_indices (:587-593), mutate (:609+)
- `vmd/lib/backup.tcl` — snapshot/apply/restore (:39-113; viewpoint positional order, rep NAMES, filename round-trip)
- `vmd/lib/registry.tcl` — full file (index-keyed dict, _resid_block, 1-arg reconstruct stamps one rep, wholesale resid-block replace)
- `vmd/lib/game.tcl` — current_state 4-key shape (:38-43), start_game 11-step ordering (:85-146), cleanup/restart (:427-466), _resolve_pick resid fallback (:513-526)
- `vmd/lib/game_logic.tcl` — state machine + timer_epoch/timer_elapsed/finish_win (:60-200)
- `vmd/lib/hiders.tcl` — tier_reps, user2/user3 channels, mark_found_visual, cached-selection ordering (:11-231)
- `vmd/lib/setup_state.tcl` — SETUP_FORMAT v2, 11-key DEFAULTS, GAME_REPS (:10-29)
- `vmd/lib/demos.tcl` — save_setup/load_setup key-value format, LOCKED DECISION #1 (:110-181)
- `vmd/gui/setup_tab.tcl` — do_save/do_load .bcm setup precedent (:606-691)
- `vmd/lib/splice.tcl` — RESID_BASE 9001 (:71)

### Primary — Phase 18/19 pinned contracts (planned-only; MEDIUM until their code lands)
- `18-01-PLAN.md` — GAME_MATERIALS, DEFAULT_MATERIAL, DEFAULTS +material_blending/per_mat (13 keys)
- `19-RESEARCH-mechanisms.md` — reveal/hint counters, reveal-all += len(hidden), showrep found-mgmt, ColorID probe table (33 ids; 3=orange, 7=green)
- `19-03-PLAN.md` — GAME_FOUND_COLORS {green 7 red 1 yellow 4 cyan 10 pink 9 purple 11 white 8}, DEFAULT_FOUND_COLOR 7
- `19-09/19-10-PLAN.md` — palette-only color UI (tk_chooseColor LOCKED OUT), `hiders::set_found_visible/set_found_color/found_colorid` seam, handler guards

### Checks performed this session
- `git log` — Phase 18/19 have docs commits only (code not landed as of 2026-09-26); Phase 20 dir was empty.
- `grep vmd-ref/` for zip/zlib capability — none found (scripts + plugins).
- `.planning/REQUIREMENTS.md` GAME-09/GAME-04/BTN-05; `.planning/ROADMAP.md:249-263` Phase 20 SCs verbatim.

---

## 10. Open Questions (planner should resolve or route)

1. **Zip mechanism (route: lane b probe → planner/user checkpoint if infeasible).** SC1 locks "zipped into `.bcmz`", but Tcl 8.5.6 has no zlib and `vmd-ref` shows no zip tooling. If the probe finds nothing, the fallback (two-file pair, or store-only zip written by hand — a stored zip is just headers + raw bytes, ~40 lines of Tcl) deviates from SC1's letter and needs explicit user approval. The schema here is container-agnostic either way.
2. **JSON vs the LOCKED DECISION #1 key-value format.** LOCKED DECISION #1 (Phase 14) locked the *setup file* (`BTN-03/04`) to key-value lines. SC4 locks *this phase's sidecar* to hand-rolled JSON. These are different artifacts and both can stand — this research specs JSON per SC4 (nested registry records + rep lists are unreadable as flat key-value lines). If the user wants ONE format family, the alternative is a key-value game sidecar with count+entry line encodings (`hider_count N` / `hider_entry idx rep status`) — flag for the discuss step; default = JSON per SC4.
3. **Phase 18/19 code landing order.** `found_colorid`/`found_visible`/`reveal_count`/`hint_count` producers don't exist yet (docs-only commits). Phase 20 depends on 16-19 so ordering should hold; if Phase 20 executes before 18/19, the schema still works (fields emit defaults) — but the *round-trip of live counter values* can only be smoke-tested after 19 lands. Planner should sequence accordingly.
4. **Save during `won` state.** v1 allowed saving post-win (with a UX note). v2's explicit state machine makes this a clean policy choice: allow (emit `timer_elapsed_final` as `timer_elapsed`) or block (`state ne playing` → silent return). Default recommendation: block (simpler; the win box already ends the round).
5. **Non-found rep showstates not persisted.** Accepted capability loss vs v1's `.pse` (§3.2). If the user flags it, a per-rep `shown 0|1` sub-field in `viewer.reps` is the additive fix (schema has room; `mol showrep` getter reads 1/0 — 19-RESEARCH §3). Not in the base spec to keep v2 parity minimal.
6. **Viewpoint float round-trip.** HIGH confidence (Tcl 8.5 shortest round-trip double formatting; `backup.tcl` probe-verified the positional get/set), but the smoke should assert an exact-list round-trip through serialize→parse (cheap, closes the loop).

**Valid until:** ~2026-10-26 (30 days) for the v1 extraction (shipped code, stable); the Phase 18/19-contract fields should be re-checked against landed code if their execution slips past that date.
