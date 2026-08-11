# Phase 8: Persistence & Shareable Puzzles — File Format & Co-Location Research

**Researched:** 2026-08-12
**Domain:** `.pse` save/load mechanics + `.bcm` JSON sidecar schema + co-location UX (PyMOL 2.5.0 open-source)
**Confidence:** HIGH for `.pse` mechanics (verified against `pymol-src/modules/pymol/exporting.py` + `importing.py` source); HIGH for `.bcm` schema (built on the runtime-confirmed Phase 3 `to_dict`/`from_dict` + `reconstruct_from_sentinels`); MEDIUM for the zip co-location choice (a UX decision, not a verifiable fact — but stdlib `zipfile` is HIGH confidence).
**Scope:** FILE FORMAT + CO-LOCATION + SAVE/LOAD MECHANICS only. NOT covered here: the Generate&export/Import workflow flow (parallel researcher), the registry reconstruction-by-id merge logic (parallel researcher).

---

## 1. Executive Summary

**Recommendation:** Save the game as a **single `.bcmz` archive** (a standard zip, written via stdlib `zipfile`) containing two entries — `game.pse` (the PyMOL session, scoped to just the target object) and `game.bcm` (a JSON sidecar with the registry, timer, reveal/hint counts, found-color, setup state, target object name, a magic header, and a schema version). On Import, the plugin extracts the `.pse` to a temp file, `cmd.load`s it (REPLACE session by default — `partial=0`), reads the `.bcm` from the archive, and reconciles the rebuilt-from-sentinels registry with the `.bcm`'s per-hider found-status + rep by matching atom `id`.

The `.pse` is the "geometry save" (atoms, bonds, reps, camera, settings — the sentinel `segi='GAME'`+`b=-999` survives, runtime-confirmed Phase 3); the `.bcm` is the "game-state save" (everything PyMOL doesn't persist). The two are zipped together so the educator shares ONE file (`.bcmz`) and the player picks ONE file on Import — closing the roadmap-flagged "two-file share is awkward" question. A user who manually unzips can still open the `.pse` directly in PyMOL (hiders are real atoms); they just lose the game-state sidecar (degrades gracefully to a sentinel-rebuild with `rep=None`, all hidden, timer 0).

**Co-location decision:** **zip-together (`.bcmz`)** over "naming convention + keep both files" — single-file share is the educator workflow's primary need; the plugin auto-extracts transparently; stdlib-only; the "open .pse directly without plugin" use case survives via manual unzip.

---

## 2. `cmd.save` / `cmd.load` `.pse` Mechanics (source-verified)

### 2.1 `cmd.save(filename, selection='(all)', state=-1, format='', ...)` — signature + behavior

**Source:** `tmp/pymol-src/modules/pymol/exporting.py:782-933` (`def save`), `exporting.py:973-977` (`get_psestr`), `exporting.py:370-475` (`get_session`), `exporting.py:986-998` (`savefunctions` registry).

**Signature** (`exporting.py:782`):
```python
def save(filename, selection='(all)', state=-1, format='', ref='',
         ref_state=-1, quiet=1, partial=0, *, _self=cmd):
```

**Format dispatch** (`exporting.py:838-841`): if `format` is empty, it's guessed from the filename extension. `.pse` → `format='pse'` → dispatched to `savefunctions['pse']` = `get_psestr` (`exporting.py:997`).

**The critical quirk — `get_psestr`** (`exporting.py:973-977`):
```python
def get_psestr(selection, partial, quiet, _self):
    if '(' in selection: # ignore selections
        selection = ''
    session = _self.get_session(selection, partial, quiet)
    return cPickle.dumps(session, 1)
```

**This is the load-bearing finding for the file-format design:**

- If the selection contains `(` (e.g. the default `'(all)'`, or any `'(...)'` selection expression), `get_psestr` **forces `selection = ''`** and calls `get_session(names='', ...)`.
- `get_session(names='', ...)` (`exporting.py:370`, docstring line 374): *"names: Names of objects to export, or the empty string to export all objects."* → empty string = **ALL objects** (the entire session: every loaded molecule + the `_bchm_backup` + selections + settings + camera + movie + scenes).
- If the selection does NOT contain `(` (e.g. a bare object name like `'1ubq'`), it's passed through as `names='1ubq'` to `get_session`, which **scopes the saved objects to just `1ubq`**. Settings/camera/movie/scenes are session-wide and are saved regardless of `names` (they live in the session dict, not per-object — confirmed by the `get_session` flow at `exporting.py:423-475` which always deep-copies `_pymol.session`, runs `_session_save_tasks`, and conditionally `zlib.compress`es the whole dict).

**Implications for Phase 8 Save:**

| Call | What's saved | Backup included? | Settings/camera? |
|------|--------------|------------------|-------------------|
| `cmd.save('game.pse')` (default `selection='(all)'`) | ALL objects | YES (bloats file ~2x) | YES |
| `cmd.save('game.pse', '1ubq')` (bare name) | ONLY `1ubq` | NO (excluded by name filter) | YES |
| `cmd.save('game.pse', '1ubq and segi GAME')` (parens) | ALL objects (parens → ignored!) | YES (surprise!) | YES |

**Recommendation:** Use `cmd.save(pse_path, target_obj)` with a **bare object name** to scope to just the target and exclude `_bchm_backup`. Guard against `'(' in target_obj` (pathological — see §6).

**The official wiki claim** (cited in PITFALLS.md Pitfall 7: *"the complete PyMOL state is always saved to the file (the selection and state parameters are thus ignored)"*) is **correct for the default `'(all)'` selection** but **WRONG in general** — a bare-name selection IS honored (the `if '(' in selection` check is the gate). This is a hidden quirk; the default behavior matches the wiki, but our scoped save exploits the non-default path.

**`partial` parameter** (`exporting.py:782`, `get_session` docstring line 376): *"partial: If true, do not store selections, settings, view, movie."* We want `partial=0` (default) so settings + view + movie ARE saved (the camera should be restored on Import). Note: `get_psestr` passes `partial` through to `get_session`, so `cmd.save('game.pse', '1ubq', partial=0)` is the canonical call. **Do NOT pass `partial=1`** — that would drop the camera/view, and the imported puzzle would not show the educator's intended viewpoint.

### 2.2 `cmd.load(filename, ...)` / `cmd.load_pse(filename, ...)` — signature + behavior

**Source:** `tmp/pymol-src/modules/pymol/importing.py:635-821` (`def load`), `importing.py:823-848` (`def load_pse`), `importing.py:130-164` (`def set_session`), `importing.py:1623` (`'pse': load_pse` dispatch entry).

**`cmd.load` signature** (`importing.py:635`):
```python
def load(filename, object='', state=0, format='', finish=1,
         discrete=-1, quiet=1, multiplex=None, zoom=-1, partial=0,
         mimic=1, object_props=None, atom_props=None, *, _self=cmd):
```

**Dispatch for `.pse`** (`importing.py:1623`): `'pse': load_pse` — `cmd.load('file.pse')` routes to `load_pse`.

**`load_pse` signature** (`importing.py:823`):
```python
def load_pse(filename, partial=0, quiet=1, format='pse', *, _self=cmd):
```

**CRITICAL — `load_pse` does NOT accept an `object=` parameter.** The `cmd.load` kw-filtering loop (`importing.py:802-816`) only forwards parameters that appear in the dispatched function's signature. Because `load_pse` has no `object` parameter, **`cmd.load('file.pse', 'new_name')` silently DROPS `object='new_name'`** — the loaded objects come back with their SAVED names (whatever they were called when `cmd.save` ran). This means Import cannot rename the target object; it lands with the name it had in the educator's session (e.g. `1ubq`).

**`load_pse` behavior** (`importing.py:823-848`):
```python
def load_pse(filename, partial=0, quiet=1, format='pse', *, _self=cmd):
    try:
        contents = _self.file_read(filename)
        session = io.pkl.fromString(contents)
    except AttributeError as e:
        raise pymol.CmdException('PSE contains objects which cannot be unpickled (%s)' % str(e))
    r = _self.set_session(session, quiet=quiet, partial=partial, steal=1)
    if not partial:
        _self.set("session_file", filename.replace("\\", "/"), quiet=1)
    ...
    return r
```

**`set_session`** (`importing.py:130-164`):
```python
def set_session(session, partial=0, quiet=1, cache=1, steal=-1, *, _self=cmd):
    ...
    with _self.lockcm:
        _cmd.set_session(_self._COb, session, int(partial), int(quiet))   # C-side
    ...
```

**Session-replace vs merge** — `partial` parameter semantics:

| `partial` | Behavior on load |
|-----------|------------------|
| `0` (DEFAULT for `load_pse`) | **REPLACE** the entire current session: existing objects/settings/view are CLEARED, then the loaded session's state is installed. The loaded objects come back with their saved names. |
| `1` | **MERGE**: load the session's objects into the existing session. Existing objects are NOT cleared. Collision behavior (same-named object) is UNVERIFIED at the C level (`_cmd.set_session` is C-dispatched; not readable). |

**Recommendation for Import:** Use `cmd.load(pse_path)` with the default `partial=0` (REPLACE). This gives the player a clean session with just the puzzle target — no leftover objects from their prior work. **Must warn the user first** (confirm dialog): "Importing will replace the current PyMOL session. Save your work first." (see §9 Edge Cases — collision handling).

**`steal=1`** (`importing.py:830`, `load_pse`'s call to `set_session`): hardcoded — the loaded session dict is moved (not deep-copied) into `_pymol.session`. This is an internal optimization; not user-facing.

**Unpickling errors** (`importing.py:827-828`): if the `.pse` contains objects that can't be unpickled (e.g. a plugin callback missing `__getstate__`/`__setstate__`), `load_pse` raises `pymol.CmdException('PSE contains objects which cannot be unpickled (%s)')`. This is the failure mode PITFALLS.md Pitfall 7 warns about for the `load_callback` approach — and the reason we use the sidecar-JSON approach instead. Our `.pse` should contain NO plugin callbacks (only atoms + settings + camera), so this error should not fire.

### 2.3 Answers to the specific `.pse` questions

**Q1a — `cmd.save` signature:** `cmd.save(filename, selection='(all)', state=-1, format='', ref='', ref_state=-1, quiet=1, partial=0, *, _self=cmd)` (`exporting.py:782`).

**Q1b — Does `cmd.save(filename, selection)` save just the selection's atoms or the whole session when extension is `.pse`?** With the default `selection='(all)'` (contains `(`) → the selection is IGNORED and the WHOLE session is saved (`get_psestr` line 974: `if '(' in selection: selection = ''`). With a bare object-name selection (no parens, e.g. `'1ubq'`) → ONLY that object is saved (passed as `names=` to `get_session`). Settings/camera/movie are saved in BOTH cases (session-wide).

**Q1c — Does `.pse` save the ENTIRE session or can it be scoped?** It CAN be scoped to one object by passing a bare name: `cmd.save('game.pse', '1ubq')`. The Pitfall 7 research claim "complete PyMOL state is always saved" is true ONLY for the default `'(all)'` selection (the `(` check is the gate). This is a VERIFIED quirk; the planner should rely on it but add a guard for `(` in the target name.

**Q1d — What does `cmd.load('file.pse')` do?** It REPLACES the current session (`partial=0` default): existing objects cleared, loaded objects installed with their saved names. It does NOT load into a new object. It does NOT merge (unless `partial=1`, which is UNVERIFIED for collisions). It does NOT honor the `object=` argument (`load_pse` doesn't accept it; silently dropped).

**Q1e — Does `.pse` preserve the hidden `_bchm_backup`?** YES if saved with `(all)` (default) — `_bchm_backup` is in `all_objects` and `get_session(names='')` saves all objects. NO if saved with `cmd.save('game.pse', target_obj)` (bare name) — the name filter excludes `_bchm_backup`. The backup is hidden from `public_objects` (underscore prefix, `backup.py:34` `BACKUP_PREFIX = '_bchm_backup'`) but IS in `all_objects` — `get_session` iterates `all_objects`, not `public_objects`. See §6 for the recommended exclusion strategy.

---

## 3. `.bcm` Top-Level JSON Schema Proposal

### 3.1 Design constraints (from existing code)

- The registry portion is **already designed** in Phase 3 (`registry.py:215-245`): `HiderRegistry.to_dict()` returns `{'version': 1, 'hiders': [record.to_dict(), ...]}`; `HiderRegistry.from_dict(d)` round-trips it. The planner does NOT redesign this.
- `HiderRecord.to_dict()` (`registry.py:91-102`) returns `{'id': int, 'object': str, 'rep': str|None, 'status': 'hidden'|'found', 'pos': [x,y,z] (only if not None)}`.
- `reconstruct_from_sentinels` (`registry.py:249-272`) rebuilds with `rep=None`, `status='hidden'` for every sentinel — so the `.bcm` MUST carry the canonical `rep` + `status` per hider (matched by `id`) to override the sentinel defaults.
- The setup state shape is **already established** in Phase 2 (`gui_setup.py:441-459` `collect_state()`): a JSON-serializable dict with `format`, `target_mode`, `selected_object`, `pdb_code`, `demo_id`, `hider_count`, `lock_scene`, `per_rep`, `difficulty_easy`, `lock_source`, `pdb_pool`.
- `GameController` state to capture (`game.py:20-40`): `target_obj`, `registry`, `_backup_name` (transient — NOT serialized), `_started`, `_start_time`, `_reveal_count`, `_hint_count`, `_found_color`.

### 3.2 Proposed top-level `.bcm` schema (version 1)

```json
{
  "magic": "BIOCHEMELEON-BCM",
  "version": 1,
  "kind": "checkpoint",
  "target_object": "1ubq",
  "started": true,
  "timer_elapsed": 42.5,
  "reveal_count": 1,
  "hint_count": 2,
  "found_color": "green",
  "registry": {
    "version": 1,
    "hiders": [
      {"id": 1234, "object": "1ubq", "rep": "spheres", "status": "found", "pos": [10.0, 10.0, 10.0]},
      {"id": 1235, "object": "1ubq", "rep": "sticks", "status": "hidden"},
      {"id": 1236, "object": "1ubq", "rep": "cartoon", "status": "hidden"}
    ]
  },
  "setup": {
    "format": "biochemeleon-setup-v1",
    "target_mode": "loaded",
    "selected_object": "1ubq",
    "pdb_code": "",
    "demo_id": "1znf",
    "hider_count": 3,
    "lock_scene": false,
    "per_rep": {"spheres": 1, "sticks": 1, "cartoon": 1},
    "difficulty_easy": true,
    "lock_source": false,
    "pdb_pool": []
  }
}
```

### 3.3 Field-by-field rationale

| Field | Type | Purpose | Source |
|-------|------|---------|--------|
| `magic` | str (const `"BIOCHEMELEON-BCM"`) | File-type detection. First JSON key; lets the plugin refuse non-bioCHEMeleon files. Also visible to anyone who unzips + opens the `.bcm` in a text editor. | New (Phase 8) |
| `version` | int (1) | Schema version. `1` = current. Future v2 migrations check this. | New (Phase 8) |
| `kind` | str (`"checkpoint"` \| `"puzzle"`) | Distinguishes Save-mid-game (`"checkpoint"`) from Generate&export initial-state (`"puzzle"`). Drives Import UX: checkpoint = resume (restore timer + found-status); puzzle = fresh start (timer 0, but rep recovered from .bcm). | New (Phase 8) |
| `target_object` | str | The PyMOL object name. Import uses this to know which object the game targets (the sentinel-rebuild iterate filter). MUST match the object name in the `.pse`. | `GameController.target_obj` (`game.py:21`) |
| `started` | bool | Whether the game was in progress when saved. For checkpoint: `true`. For puzzle: `false`. Redundant with `kind` but kept for programmatic clarity (the controller's `_started` flag — `game.py:24`). | `GameController._started` (`game.py:24`) |
| `timer_elapsed` | float (seconds) | Elapsed play time at save. For checkpoint: the live elapsed value. For puzzle: `0.0`. On Import (checkpoint): timer resumes from this value. Computed as `time.time() - self._start_time` (see `game.py:131`). | `GameController._start_time` (`game.py:26`) |
| `reveal_count` | int | Number of reveals used (Phase 6 DIFF-01). Restored on Import. | `GameController._reveal_count` (`game.py:32`) |
| `hint_count` | int | Number of hints used (Phase 6 DIFF-01). Restored on Import. | `GameController._hint_count` (`game.py:33`) |
| `found_color` | str | Player-chosen highlight color (Phase 7 DIFF-04). Either a PyMOL named color (`"green"`) or a custom `cmd.set_color` name (`"found_highlight"`). For a custom color, Import must re-`cmd.set_color` it before recoloring found hiders (the color definition is NOT in the `.pse` unless we explicitly save it — UNVERIFIED; see §10 Open Risks). | `GameController._found_color` (`game.py:40`) |
| `registry` | dict | The `HiderRegistry.to_dict()` shape (Phase 3, `registry.py:215-225`). Per-hider `status` + `rep` override the sentinel-rebuild defaults by matching `id`. | `HiderRegistry.to_dict()` (`registry.py:215`) |
| `setup` | dict | The raw `gui_setup.collect_state()` dict (Phase 2). Captures the educator's intended configuration. For a checkpoint: "how this game was set up". For a puzzle: "the educator's intended config". The raw dict is already JSON-serializable (Phase 2 round-trips it). | `gui_setup.collect_state()` (`gui_setup.py:441-459`) |

### 3.4 Why `found_color` for a custom color needs runtime care

If the player chose a custom color via the Phase 7 color picker (`gui_game.py:161-180`), the color was registered as `cmd.set_color('found_highlight', [r, g, b])`. This named color is a PyMOL setting — UNVERIFIED whether custom `cmd.set_color` definitions survive `.pse` round-trip (they're stored in the `colors` session dict entry, likely yes, but not confirmed at runtime). If they DON'T survive, Import must re-`cmd.set_color('found_highlight', [r, g, b])` before any recolor. **Mitigation:** store the RGB triple alongside `found_color` in the `.bcm` so Import can re-register it:

```json
"found_color": "found_highlight",
"found_color_rgb": [0.2, 0.8, 0.3]
```

`found_color_rgb` is `null` when `found_color` is a built-in PyMOL color name (e.g. `"green"`). On Import: if `found_color_rgb is not None`, `cmd.set_color(found_color, found_color_rgb)` before use. **This is a LOW-cost safety net for an UNVERIFIED setting-survival question.** Flagged in §10.

### 3.5 Should found-status be duplicated at top level?

**No.** Found-status lives in `registry.hiders[].status` (already per-hider, already JSON-serialized by Phase 3 `to_dict`). The sentinel rebuild sets all to `'hidden'`; the `.bcm` overrides per-hider by matching `id`. A top-level found-count would be a derived value (`sum(1 for h in hiders if h.status == 'found')`) — derivable on Import, not stored. **No duplication.**

### 3.6 Should `setup` be the raw `collect_state()` dict or a curated subset?

**The raw dict.** It's already JSON-serializable, already round-trips (Phase 2 Save/Load Setup), and carries the educator's full intent. A curated subset would lose information (e.g. `pdb_pool` for a fetch-mode puzzle) and require maintenance as the setup shape evolves. The raw dict is the established pattern. The `format` key inside (`"biochemeleon-setup-v1"`) gives us forward-compat for the setup sub-shape too.

### 3.7 `kind: "checkpoint"` vs `"puzzle"` — concrete difference

| Aspect | `kind: "checkpoint"` (Save mid-game) | `kind: "puzzle"` (Generate & export) |
|--------|--------------------------------------|--------------------------------------|
| When written | Player presses Save during play | Educator presses Generate & export from Setup |
| `started` | `true` | `false` |
| `timer_elapsed` | live elapsed (e.g. `42.5`) | `0.0` |
| `registry.hiders[].status` | mix of `'found'` and `'hidden'` | ALL `'hidden'` |
| `reveal_count`, `hint_count` | live counts | `0` |
| Import UX | Resume: timer continues from `timer_elapsed`, found-status restored, wizard activates, play continues | Fresh start: timer starts at 0, all hidden (sentinel rebuild = no-op override), wizard activates, play from scratch |
| Backup on save | `_bchm_backup` exists in the live session (excluded from .pse by scoped save) | No backup yet (Generate & export snapshots + inserts + registers, then saves; the backup IS created during generation but excluded from the .pse) |

Both kinds use the SAME `.bcm` schema; `kind` is the discriminator. The Import workflow reads `kind` and decides resume-vs-fresh-start UX.

---

## 4. Co-Location UX Decision (the flagged research question)

The roadmap flagged: *".pse + companion .bcm co-location UX — two-file share is awkward; decide zip-together vs document 'keep both files'."*

### 4.1 Options evaluated

| ID | Approach | Stdlib? | Files to share | PyMOL direct-open? | Inspection |
|----|----------|---------|----------------|--------------------|-----------| 
| (a) | **Zip `.pse` + `.bcm` into one `.bcmz`** | YES (`zipfile`) | 1 | NO (must extract first; user can manually unzip) | Opaque to file explorer; `.bcm` is human-readable inside the zip |
| (b) | **Naming convention + "keep both files"** | YES | 2 | YES (`.pse` double-click) | Transparent (both files visible) |
| (c) | **Embed `.bcm` inside `.pse`** (PyMOL setting / chempy brute object) | YES | 1 | YES | Opaque (binary pickle) |
| (d) | **Auto-pair on Import** (QFileDialog accepts either; find sibling by basename) | YES | 2 | YES | Transparent |

### 4.2 Rejected options — cons

**(c) Embed `.bcm` inside `.pse`** — REJECTED (fragile).
- `.pse` is a binary pickle (`cPickle.dumps(session, 1)`, `exporting.py:977`). Embedding custom data requires either:
  - `cmd.set('bchm_metadata', json_string)` — a PyMOL string setting. UNVERIFIED whether large JSON strings survive `.pse` round-trip cleanly (settings ARE saved, but there may be length limits or escaping issues). Fragile.
  - A chempy "brute object" carrying the JSON as a property — fragile, may not survive pickling, pollutes the object list.
  - `cmd.load_callback` + `__getstate__`/`__setstate__` — PITFALLS.md Pitfall 7 explicitly calls this out as fragile (must pop non-picklable Qt/timers; "Test round-trip on every change"). REJECTED — the sidecar-JSON approach is what Phase 8 implements, per the prior research.
- This is the most fragile option. The sidecar-JSON approach is preferred and is what Phase 8 implements.

**(b) Naming convention + "keep both files"** — REJECTED as primary (kept as fallback).
- Pro: transparent; PyMOL loads `.pse` directly; "open .pse without plugin" works natively.
- Con: TWO files to share — the educator must email/upload/copy BOTH `mymol.pse` and `mymol.bcm`, keeping them paired by basename. If a student downloads just the `.pse` and forgets the `.bcm`, Import degrades (sentinel rebuild, no found-status, no rep, no timer — game still playable but not the intended experience). The pairing burden is on both educator and student.
- Con: The "keep both files" instruction is documentation debt — users WILL forget.
- Acceptable as a FALLBACK for the manual-unzip case (a user who unzips a `.bcmz` gets a `.pse` + `.bcm` pair that they can keep paired by basename).

**(d) Auto-pair on Import** — REJECTED as primary (kept as Import UX layer).
- Still two files to share (the same con as (b)).
- The auto-pair is a nice UX on the Import side (user picks either file; plugin finds the sibling by basename), but it doesn't solve the SHARE problem (educator still shares two files).
- Can be combined with (a) as an Import-side convenience: if the user picks a `.bcmz`, extract + load; if the user picks a `.pse` (manually unzipped), look for a sibling `.bcm` by basename and load it too. **Recommended as a secondary Import path.**

### 4.3 Recommended: (a) Zip-together (`.bcmz`)

**Rationale (in priority order):**

1. **Single-file share is the educator workflow's primary need.** An educator emailing a puzzle to students, uploading to an LMS, or copying to a USB stick wants ONE file. Two files named `mymol.pse` + `mymol.bcm` are awkward to keep paired in transit (email clients may rename attachments; LMS uploads may separate them; USB copies may drop one). A single `.bcmz` is one attachment, one upload, one copy.

2. **The plugin auto-extracts transparently on Import.** The user never manually unzips in the normal workflow. Save writes the `.bcmz`; Import reads it. The extraction is an implementation detail (extract `.pse` to a temp file, `cmd.load` it, read `.bcm` from the archive). No user-facing "extract" step.

3. **stdlib `zipfile` — no external dependency.** The Phase 8 constraints (AGENTS.md: "Only libraries shipped with `pymol-open-source` may be assumed — PyQt5 via `pymol.Qt`, numpy, Python stdlib") are satisfied. `zipfile` + `json` + `tempfile` + `os` are all stdlib. No `pip install`, no vendoring.

4. **The "open .pse directly in PyMOL without the plugin" use case survives via manual unzip.** A user who wants to open the puzzle in PyMOL without the bioCHEMeleon plugin can: right-click the `.bcmz` → "Extract All" (Windows) or `unzip game.bcmz` (CLI) → open `game.pse` in PyMOL. The hiders are real atoms (sentinel survives), so the molecule + hiders are visible. They lose the game state (no `.bcm` applied), but the molecule is there. This is a documented secondary use case, not the primary one.

5. **The `.bcm` JSON is human-readable inside the archive.** A curious user/educator can `unzip -p game.bcmz game.bcm` and inspect the sidecar in a text editor. The archive is a standard zip, not an opaque binary — any zip tool can open it.

6. **File-type detection via extension + magic.** `.bcmz` is unambiguous (custom extension). The `.bcm` inside has `"magic": "BIOCHEMELEON-BCM"` as a belt-and-suspenders check.

### 4.4 `.bcmz` archive layout

```
game.bcmz                          # standard zip (ZIP_DEFLATED)
├── game.pse                       # PyMOL session (scoped to target object)
├── game.bcm                       # JSON sidecar (schema §3.2)
└── (no manifest.json — the .bcm has magic + version, sufficient)
```

**Why no `manifest.json`:** the `.bcm` already carries `magic` + `version` + `kind` + `target_object`. A separate manifest would duplicate this. The `.bcm` IS the manifest.

**Why fixed names `game.pse` + `game.bcm` (not the basename):** the archive is the unit of sharing; the inner names are a fixed contract. The user-facing name is the `.bcmz` filename (e.g. `ubq-puzzle.bcmz`); inside, the entries are always `game.pse` + `game.bcm`. This simplifies the Import code (always reads `game.pse` + `game.bcm`) and avoids basename-collision issues inside the archive.

### 4.5 Save path (concrete function signature + pseudocode)

```python
# biochemeleon/persistence.py (new module — cmd-coupled; imports backup for guard)
import json, os, tempfile, zipfile
from pymol import cmd
from . import backup  # for BACKUP_PREFIX guard

def save_game(bcmz_path, controller, setup_state, kind='checkpoint'):
    """Save the game as a .bcmz archive (zip containing game.pse + game.bcm).

    Args:
        bcmz_path: path to write the .bcmz (Windows path when PyMOL runs in Windows).
        controller: GameController with target_obj, registry, _start_time,
            _reveal_count, _hint_count, _found_color.
        setup_state: the gui_setup.collect_state() dict.
        kind: 'checkpoint' (Save mid-game) or 'puzzle' (Generate & export).
    Raises:
        ValueError: if target_obj contains '(' (scoped-save guard — see §6).
    """
    target_obj = controller.target_obj
    if '(' in target_obj:
        raise ValueError(
            "Target object name %r contains '(' which breaks scoped .pse save. "
            "Please rename the object before saving." % target_obj)
    bcm = build_bcm_dict(controller, setup_state, kind)
    with tempfile.TemporaryDirectory() as tmpdir:
        pse_path = os.path.join(tmpdir, 'game.pse')
        # Scoped save: excludes _bchm_backup (§6). Settings/camera ARE saved.
        cmd.save(pse_path, target_obj)
        with zipfile.ZipFile(bcmz_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.write(pse_path, 'game.pse')
            zf.writestr('game.bcm', json.dumps(bcm, indent=2))

def build_bcm_dict(controller, setup_state, kind):
    """Build the .bcm top-level dict (pure — no cmd calls; reads controller attrs)."""
    import time
    elapsed = (time.time() - controller._start_time
               if controller._start_time is not None else 0.0)
    return {
        'magic': 'BIOCHEMELEON-BCM',
        'version': 1,
        'kind': kind,
        'target_object': controller.target_obj,
        'started': bool(controller._started),
        'timer_elapsed': elapsed if kind == 'checkpoint' else 0.0,
        'reveal_count': controller._reveal_count,
        'hint_count': controller._hint_count,
        'found_color': controller._found_color,
        'found_color_rgb': None,  # §3.4 — populated if custom color; see §10
        'registry': controller.registry.to_dict(),
        'setup': setup_state,
    }
```

### 4.6 Import path (concrete function signature + pseudocode)

```python
def import_game(bcmz_path):
    """Import a game from a .bcmz archive.

    Returns (controller, setup_state, bcm) — the caller (GUI) wires the
    controller into the Game tab + applies the kind-specific UX (resume
    vs fresh start).

    Side effect: REPLACES the current PyMOL session (cmd.load partial=0).
    Caller MUST warn the user before calling (§9.1).
    """
    with zipfile.ZipFile(bcmz_path, 'r') as zf:
        names = zf.namelist()
        if 'game.bcm' not in names:
            raise ValueError("Not a bioCHEMeleon archive (missing game.bcm)")
        if 'game.pse' not in names:
            raise ValueError("Archive missing game.pse (cannot reconstruct)")
        bcm = json.loads(zf.read('game.bcm').decode('utf-8'))
        if bcm.get('magic') != 'BIOCHEMELEON-BCM':
            raise ValueError("Not a bioCHEMeleon file (magic mismatch)")
        version = bcm.get('version', 1)
        if version > 1:
            raise ValueError(
                "File schema version %d is newer than this plugin supports (1). "
                "Please update bioCHEMeleon." % version)
        with tempfile.TemporaryDirectory() as tmpdir:
            pse_path = os.path.join(tmpdir, 'game.pse')
            with open(pse_path, 'wb') as f:
                f.write(zf.read('game.pse'))
            cmd.load(pse_path)  # partial=0 default — REPLACE session
    target_obj = bcm['target_object']
    if target_obj not in cmd.get_names('objects'):
        raise ValueError(
            "Loaded .pse does not contain expected object %r" % target_obj)
    # Reconstruct registry from sentinels (rep=None, all hidden)
    from . import game, mutation
    controller = game.GameController(target_obj)
    controller.registry = registry.HiderRegistry().reconstruct_from_sentinels(
        lambda: mutation.fetch_all_hider_ids(target_obj))
    # Apply .bcm state (found-status, rep, timer, counters, found_color)
    apply_bcm_state(controller, bcm)
    setup_state = bcm.get('setup', {})
    return controller, setup_state, bcm

def apply_bcm_state(controller, bcm):
    """Override the sentinel-rebuilt registry with .bcm per-hider state (by id).
    Pure dict/registry ops + cmd.set_color for custom found_color. This function
    is the bridge between the sentinel-rebuild (source of truth: which atoms ARE
    hiders) and the .bcm (the per-hider metadata: rep + status + counters).
    """
    # Reconcile each sentinel-rebuilt record with the .bcm's per-hider entry by id.
    bcm_by_id = {h['id']: h for h in bcm['registry']['hiders']}
    for rec in controller.registry.all():
        h = bcm_by_id.get(rec.id)
        if h is None:
            continue  # sentinel present but not in .bcm — leave as rep=None, hidden
        rec.rep = h.get('rep')           # override None with the saved rep
        rec.status = h.get('status', 'hidden')  # override 'hidden' with saved status
    # Restore counters
    controller._reveal_count = bcm.get('reveal_count', 0)
    controller._hint_count = bcm.get('hint_count', 0)
    controller._found_color = bcm.get('found_color', 'green')
    # Re-register custom found_color if needed (§3.4)
    rgb = bcm.get('found_color_rgb')
    if rgb is not None:
        cmd.set_color(controller._found_color, rgb)
    # For checkpoint: restore the timer base so it continues from elapsed
    if bcm.get('kind') == 'checkpoint':
        import time
        elapsed = bcm.get('timer_elapsed', 0.0)
        controller._start_time = time.time() - elapsed
        controller._started = True
    else:  # puzzle — fresh start
        controller._start_time = None
        controller._started = False
```

**Note:** `apply_bcm_state`'s registry-reconciliation loop is the bridge to the parallel researcher's "registry reconstruction-by-id merge logic" — the planner should coordinate with that researcher to ensure `apply_bcm_state` aligns with their recommended merge semantics. The sketch above is a minimum-viable version; the merge researcher may refine it.

---

## 5. File-Dialog UX for Save / Generate & export / Import

### 5.1 The established QFileDialog pattern (Phase 2)

**Source:** `biochemeleon/gui_setup.py:546-562` (`_save_setup`), `gui_setup.py:563-588` (`_load_setup`).

```python
# Save (Phase 2):
path, _ = QtWidgets.QFileDialog.getSaveFileName(
    self, "Save bioCHEMeleon Setup", "",
    "bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)")
if not path:
    return
if not path.lower().endswith('.json'):
    path += '.bcm.setup.json'
# ... json.dump ...

# Load (Phase 2):
path, _ = QtWidgets.QFileDialog.getOpenFileName(
    self, "Load bioCHEMeleon Setup", "",
    "bioCHEMeleon Setup (*.bcm.setup.json);;All Files (*)")
```

`QFileDialog.getSaveFileName(parent, title, default_dir, filter)` returns a tuple `(path, selected_filter)`. Phase 8 reuses this exact pattern. Confirmed via the Phase 2 code — no new Qt API to verify.

### 5.2 Save (mid-game) — `GameTab`

**One file picker, one file written (`.bcmz`).**

```python
def _on_save_game(self):
    """GAME-09: Save the current game as a .bcmz archive."""
    if self._controller is None or not self._controller._started:
        QtWidgets.QMessageBox.warning(self, "No game", "Start a game first.")
        return
    path, _ = QtWidgets.QFileDialog.getSaveFileName(
        self, "Save bioCHEMeleon Game", "",
        "bioCHEMeleon Game (*.bcmz);;All Files (*)")
    if not path:
        return
    if not path.lower().endswith('.bcmz'):
        path += '.bcmz'
    setup_state = self.window().setup_tab.collect_state()
    try:
        persistence.save_game(path, self._controller, setup_state, kind='checkpoint')
    except (OSError, ValueError) as e:
        QtWidgets.QMessageBox.warning(self, "Save failed", str(e))
```

**Default extension:** `*.bcmz`. The filter `"bioCHEMeleon Game (*.bcmz);;All Files (*)"` is the pattern. The auto-append `if not path.lower().endswith('.bcmz'): path += '.bcmz'` mirrors Phase 2's `.json` append.

### 5.3 Generate & export (Setup tab) — same dialog as Save, `kind='puzzle'`

**Same dialog, different `kind`.** The user picks a `.bcmz` path; the plugin generates hiders (without starting play) and writes a `kind='puzzle'` archive. The dialog can have a slightly different title ("Export bioCHEMeleon Puzzle") but the filter + extension are identical.

```python
def _on_generate_export(self):
    """BTN-05: Generate hiders and save the initial game state (no play)."""
    # ... resolve target + build hider_specs (same as _on_start) ...
    # ... gc.start(hider_specs) (snapshot + insert + register) ...
    path, _ = QtWidgets.QFileDialog.getSaveFileName(
        self, "Export bioCHEMeleon Puzzle", "",
        "bioCHEMeleon Puzzle (*.bcmz);;All Files (*)")
    if not path:
        # user cancelled — cleanup the generated hiders (don't leave them)
        gc.cleanup()
        return
    if not path.lower().endswith('.bcmz'):
        path += '.bcmz'
    persistence.save_game(path, gc, self.setup_tab.collect_state(), kind='puzzle')
    # After export, cleanup the live game (we generated hiders but didn't play)
    gc.cleanup()
```

**Why same dialog:** both produce a `.bcmz`; the only difference is `kind` (which the user doesn't see directly — the title communicates intent). Two dialogs would be UI clutter for the same file type. The title differs ("Save bioCHEMeleon Game" vs "Export bioCHEMeleon Puzzle") to communicate intent.

### 5.4 Import (Game tab) — one file picker (`.bcmz`)

```python
def _on_import(self):
    """GAME-04: Import a previously exported game."""
    path, _ = QtWidgets.QFileDialog.getOpenFileName(
        self, "Import bioCHEMeleon Game", "",
        "bioCHEMeleon Game (*.bcmz);;All Files (*)")
    if not path:
        return
    # Warn: Importing REPLACES the current session (§9.1)
    if not self._confirm("Import game?",
            "Importing will replace the current PyMOL session.\n"
            "Save your work first. Continue?"):
        return
    try:
        controller, setup_state, bcm = persistence.import_game(path)
    except (OSError, ValueError, KeyError) as e:
        QtWidgets.QMessageBox.warning(self, "Import failed", str(e))
        return
    # Wire the controller into the Game tab + apply kind-specific UX
    self._controller = controller
    if bcm.get('kind') == 'checkpoint':
        # Resume: start the timer from elapsed, activate the wizard, continue play
        self._begin_play_for_imported_checkpoint(controller, bcm)
    else:  # puzzle
        # Fresh start: countdown then begin_play (timer starts at 0)
        self.start_countdown(controller)
```

### 5.5 Secondary Import path (auto-pair for manually-unzipped pairs)

Optional (not required for v1): if the user picks a `.pse` (manually unzipped), the plugin looks for a sibling `.bcm` by basename:

```python
if path.lower().endswith('.pse'):
    bcm_path = path[:-4] + '.bcm'
    if os.path.exists(bcm_path):
        # load .pse + .bcm separately (naming-convention fallback)
        ...
    else:
        # .bcm missing — degrade gracefully (sentinel rebuild, rep=None, all hidden)
        ...
```

**Recommendation:** defer this secondary path to a later phase (it's a nice-to-have, not a v1 requirement). The primary path is `.bcmz` only. Documenting the `.bcmz` as the only share format keeps v1 simple.

---

## 6. `.pse` Content Control — Excluding the Backup Object

### 6.1 The problem

The `_bchm_backup` object (`backup.py:34` `BACKUP_PREFIX = '_bchm_backup'`) is a coordinate-identical copy of the target, created at `GameController.start()` (`game.py:54` `self._backup_name = backup.snapshot(self.target_obj)`). It's hidden from `public_objects` (underscore prefix) but IS in `all_objects`. `cmd.save('game.pse')` with the default `'(all)'` selection saves it (bloats the file ~2x — it's a full copy of the target). The backup is transient — a reloaded game rebuilds its own backup on first play action; it should NOT be in the shared `.pse`.

### 6.2 The recommended approach — scoped save (bare-name selection)

**Use `cmd.save(pse_path, target_obj)` with a bare object name.** Per §2.1's source verification, `get_psestr` (`exporting.py:973-977`) passes a non-paren selection through to `get_session(names=target_obj)`, which filters objects by name — excluding `_bchm_backup`. Settings/camera are saved regardless (session-wide).

**Pros:**
- The backup stays in the LIVE session (so the user can continue playing safely after Save — cleanup still has a backup to restore from).
- The `.pse` contains only the target object + settings + camera (clean for sharing).
- No temp files, no delete-then-restore dance.

**Guard (required):** if `'(' in target_obj`, the scoped save silently degenerates to save-all (the `(` check trips `get_psestr`'s `selection = ''`). Object names with `(` are pathological (PyMOL allows them but they're vanishingly rare — PDB codes, demo IDs, and user-typed names are alphanumeric). The guard:

```python
if '(' in target_obj:
    raise ValueError(
        "Target object name %r contains '(' which breaks scoped .pse save. "
        "Please rename the object before saving." % target_obj)
```

This is a HARD refuse — the user must rename the object (e.g. via PyMOL's object panel → rename). Simpler and safer than a fallback code path that's never tested in practice.

### 6.3 The rejected alternatives

**Delete backup before save + save-all + restore backup** — REJECTED (complex, fragile).
- Would require: `cmd.save('_bchm_backup_tmp.pse', '_bchm_backup')` → `cmd.delete('_bchm_backup')` → `cmd.save('game.pse')` → `cmd.load('_bchm_backup_tmp.pse', '_bchm_backup')` → cleanup temp file.
- Restoring the backup via `cmd.load` would trigger a SECOND `set_session` (REPLACE), destroying the game state we just saved. The load order is a trap.
- Could use `cmd.create('_bchm_backup', target_obj)` to re-snapshot — but the target NOW has hiders in it (mid-game), so the new backup would have hiders, defeating the backup's purpose.
- **Verdict:** too complex, too fragile, no benefit over scoped save.

**Let the backup ride along in the `.pse`** — REJECTED (bloats file, confuses direct-open).
- File is ~2x the size (the backup is a full coordinate copy).
- A user opening the `.pse` directly in PyMOL (without the plugin) would see `_bchm_backup` in the object menu (underscore-prefixed, but present). Confusing.
- The backup has NO game-relevance on Import (the Import workflow creates a fresh backup as needed).
- **Verdict:** lazy approach; the scoped save is strictly better.

### 6.4 Does the saved `.pse`'s object list confuse the player on Import?

No — with scoped save, the `.pse` contains ONLY `target_obj` (e.g. `1ubq`). On Import, `cmd.load` REPLACES the session with just `1ubq`. The player sees one object in the PyMOL object menu. No `_bchm_backup`, no other molecules. Clean.

### 6.5 Safe ordering for Save mid-game

The Save mid-game sequence (in `save_game`):
1. **Read controller state** (registry, counters, start_time) — pure reads, no mutation.
2. **Build the `.bcm` dict** (`build_bcm_dict`) — pure dict ops.
3. **Scoped `cmd.save(pse_path, target_obj)`** — writes the `.pse` to a temp file. Does NOT mutate the live session (the backup stays).
4. **Write the `.bcmz`** (`zipfile.ZipFile.write` + `writestr`) — reads the temp `.pse`, writes the archive.
5. **Temp dir cleanup** (`tempfile.TemporaryDirectory` context exit) — removes the temp `.pse`.

**No snapshot/restore needed.** The live session is untouched by Save; the user can continue playing safely.

---

## 7. Path Handling (WSL vs Windows)

### 7.1 `QFileDialog` returns Windows paths when PyMOL runs in Windows

**Confirmed by the Phase 2 pattern.** `gui_setup.py:546-562` uses `QFileDialog.getSaveFileName` and passes the returned path directly to `open(path, 'w')` + `json.dump`. This works in the Windows PyMOL runtime (Phase 2 is verified). `QFileDialog` uses the native Windows dialog (Qt auto-selects), which returns Windows-style paths (`C:\Users\...\game.bcmz`). No conversion needed when running in Windows PyMOL.

**The `demos.to_windows_path()` helper** (`demos.py:24-43`) is a GUARD for the WSL-dev case where a path might be POSIX (`/mnt/c/...`). It converts `/mnt/c/...` → `C:\...` and leaves other paths unchanged. For Phase 8, the paths come from `QFileDialog` (already Windows-style in production) or from `tempfile.TemporaryDirectory()` (Windows temp dir in the Windows PyMOL process). **`to_windows_path()` is NOT needed for Save/Import paths** — they're already Windows-native.

**Where `to_windows_path()` IS still needed:** if Phase 8 has any bundled/default paths (e.g. a default save dir relative to `__file__`). For v1, the `QFileDialog` default dir is `""` (current dir), so no conversion needed.

### 7.2 Headless smoke-test path handling

**Phase 3 smoke proven the pattern** (`smoke/phase3_smoke.py:86-88`):
```python
cmd.save("phase3_test.pse")     # relative path
cmd.delete(obj)
cmd.load("phase3_test.pse")     # relative path — resolved against cmd.exe cwd
```

This worked headlessly via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py` from a staged Windows-facing path (`tmp/bioCHEMeleon/`). The relative paths resolved against the cmd.exe cwd (the staged `/mnt/c` path mapped to a Windows `\\wsl$` or `C:\` path).

**For Phase 8 smoke:**
- `persistence.save_game('phase8_test.bcmz', ...)` — relative `.bcmz` path, resolved against cwd.
- `tempfile.TemporaryDirectory()` inside `save_game` — uses the Windows `%TEMP%` (since PyMOL runs as a Windows process). `cmd.save(pse_path, target_obj)` writes to the Windows temp path — works.
- `persistence.import_game('phase8_test.bcmz')` — reads the `.bcmz` from cwd, extracts `.pse` to a Windows temp dir, `cmd.load(pse_path)` — works.

**No `/tmp` paths** (Phase 3 smoke hit this — Windows can't resolve `/tmp`). Use relative paths or `tempfile.TemporaryDirectory()` (which yields Windows paths in the Windows process). The `cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c ...` staging pattern from AGENTS.md applies — the cwd is the staged Windows-facing path.

### 7.3 `cmd.save` / `cmd.load` path expansion

**Source:** `exporting.py:835` (`filename = _self.exp_path(filename)`), `importing.py:745` (`filename = _self.exp_path(filename)`). Both call `exp_path` which expands `~` and resolves relative paths. Relative paths are resolved against the PyMOL process cwd (the cmd.exe cwd in the headless case, the PyMOL install dir in the GUI case). This is the verified Phase 3 behavior.

---

## 8. Round-Trip Smoke-Test Design

### 8.1 Headless-verifiable (pure `cmd.*` + stdlib)

**Sequence** (extends the Phase 3 smoke pattern — `smoke/phase3_smoke.py`):

```python
# smoke/phase8_smoke.py — Phase 8 file-format round-trip.
# Run: cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase8_smoke.py
import sys, os, json, zipfile
from pymol import cmd
from biochemeleon import game, registry, mutation, persistence

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- setup ---
cmd.fetch("1ubq", async_=0)
obj = "1ubq"
orig_count = cmd.count_atoms(obj)

# --- start a game (3 sphere hiders) ---
gc = game.GameController(obj)
gc.start([([10.0, 10.0, 10.0], "spheres"),
          ([11.0, 11.0, 11.0], "spheres"),
          ([12.0, 12.0, 12.0], "spheres")])
check("started with 3 hiders", len(gc.registry.all()) == 3)

# --- mark 1 found + set counters + start_time (simulate mid-game) ---
import time
recs = gc.registry.all()
gc.registry.mark_found(obj, recs[0].id)
gc._reveal_count = 1
gc._hint_count = 2
gc._start_time = time.time() - 42.5  # 42.5s elapsed

# --- save as .bcmz (checkpoint) ---
setup_state = {
    "format": "biochemeleon-setup-v1", "target_mode": "loaded",
    "selected_object": obj, "pdb_code": "", "demo_id": "1znf",
    "hider_count": 3, "lock_scene": False,
    "per_rep": {"spheres": 3}, "difficulty_easy": True,
    "lock_source": False, "pdb_pool": [],
}
persistence.save_game("phase8_test.bcmz", gc, setup_state, kind='checkpoint')
check("save_game wrote .bcmz", os.path.exists("phase8_test.bcmz"))

# --- verify archive contents ---
with zipfile.ZipFile("phase8_test.bcmz", 'r') as zf:
    names = zf.namelist()
    check("archive contains game.pse", "game.pse" in names)
    check("archive contains game.bcm", "game.bcm" in names)
    bcm = json.loads(zf.read("game.bcm").decode("utf-8"))
check("bcm magic", bcm["magic"] == "BIOCHEMELEON-BCM")
check("bcm version 1", bcm["version"] == 1)
check("bcm kind checkpoint", bcm["kind"] == "checkpoint")
check("bcm target_object", bcm["target_object"] == "1ubq")
check("bcm registry len 3", len(bcm["registry"]["hiders"]) == 3)
statuses = [h["status"] for h in bcm["registry"]["hiders"]]
check("bcm 1 found, 2 hidden",
      statuses.count("found") == 1 and statuses.count("hidden") == 2)
check("bcm timer_elapsed ~42.5", abs(bcm["timer_elapsed"] - 42.5) < 1.0)
check("bcm reveal_count 1", bcm["reveal_count"] == 1)
check("bcm hint_count 2", bcm["hint_count"] == 2)
check("bcm setup hider_count 3", bcm["setup"]["hider_count"] == 3)

# --- verify backup NOT in the .pse (scoped save) ---
# (extract .pse to a temp dir, load into a FRESH session by deleting everything first)
cmd.delete("all")  # clear session
check("session cleared", cmd.get_names("objects") == [])
with zipfile.ZipFile("phase8_test.bcmz", 'r') as zf:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        pse_path = os.path.join(td, "game.pse")
        with open(pse_path, "wb") as f:
            f.write(zf.read("game.pse"))
        cmd.load(pse_path)
check("loaded .pse has 1ubq", obj in cmd.get_names("objects"))
check("loaded .pse has NO _bchm_backup",
      "_bchm_backup" not in cmd.get_names("all_objects"))
check("loaded 1ubq has 3 hiders (sentinels)",
      cmd.count_atoms("%s and segi GAME" % obj) == 3)

# --- reconstruct registry from sentinels ---
sent_ids = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(ID)",
            space={'stored': sent_ids})
bcm_ids = [h["id"] for h in bcm["registry"]["hiders"]]
check("sentinel ids match .bcm ids", sorted(sent_ids) == sorted(bcm_ids))

gc2 = game.GameController(obj)
gc2.reconstruct_registry()  # from sentinels — rep=None, all hidden
recs2 = gc2.registry.all()
check("sentinel rebuild: 3 hiders", len(recs2) == 3)
check("sentinel rebuild: all rep None", all(r.rep is None for r in recs2))
check("sentinel rebuild: all hidden", all(r.status == "hidden" for r in recs2))

# --- apply .bcm state (reconcile) ---
persistence.apply_bcm_state(gc2, bcm)
recs2b = gc2.registry.all()
check("after apply_bcm: 1 found",
      sum(1 for r in recs2b if r.status == "found") == 1)
check("after apply_bcm: 2 hidden",
      sum(1 for r in recs2b if r.status == "hidden") == 2)
check("after apply_bcm: rep reconciled from .bcm",
      all(r.rep == "spheres" for r in recs2b))
check("after apply_bcm: reveal_count restored", gc2._reveal_count == 1)
check("after apply_bcm: hint_count restored", gc2._hint_count == 2)
check("after apply_bcm: found_color restored", gc2._found_color == "green")
check("after apply_bcm: start_time restored (~42.5 elapsed)",
      abs((time.time() - gc2._start_time) - 42.5) < 1.0)

# --- full import_game round-trip (separate from manual reconstruct above) ---
cmd.delete("all")
gc3, setup3, bcm3 = persistence.import_game("phase8_test.bcmz")
check("import_game restored object", obj in cmd.get_names("objects"))
check("import_game target_object", gc3.target_obj == obj)
check("import_game kind checkpoint", bcm3["kind"] == "checkpoint")
recs3 = gc3.registry.all()
check("import_game: 1 found, 2 hidden",
      sum(1 for r in recs3 if r.status == "found") == 1 and
      sum(1 for r in recs3 if r.status == "hidden") == 2)
check("import_game: rep reconciled",
      all(r.rep == "spheres" for r in recs3))

# --- puzzle (Generate & export) round-trip ---
cmd.delete("all")
cmd.fetch("1ubq", async_=0)
gc4 = game.GameController(obj)
gc4.start([([20.0, 20.0, 20.0], "spheres")])
persistence.save_game("phase8_puzzle.bcmz", gc4, setup_state, kind='puzzle')
gc4.cleanup()  # clean up the live game (we generated but didn't play)
with zipfile.ZipFile("phase8_puzzle.bcmz", 'r') as zf:
    bcm_p = json.loads(zf.read("game.bcm").decode("utf-8"))
check("puzzle kind", bcm_p["kind"] == "puzzle")
check("puzzle started false", bcm_p["started"] is False)
check("puzzle timer 0", bcm_p["timer_elapsed"] == 0.0)
check("puzzle all hidden",
      all(h["status"] == "hidden" for h in bcm_p["registry"]["hiders"]))
cmd.delete("all")
gc5, setup5, bcm5 = persistence.import_game("phase8_puzzle.bcmz")
check("puzzle import: all hidden",
      all(r.status == "hidden" for r in gc5.registry.all()))
check("puzzle import: started false", gc5._started is False)
check("puzzle import: start_time None", gc5._start_time is None)

# --- cleanup ---
mutation.cleanup_hiders(obj)

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
```

### 8.2 What the headless smoke CAN verify

- `.bcmz` archive creation + structure (zip entries).
- `.bcm` JSON schema (magic, version, kind, target_object, registry, timer, counters, setup).
- Scoped `.pse` save (backup excluded) — verified by loading into a fresh session and checking `_bchm_backup not in all_objects`.
- Sentinel survival across `.bcmz` round-trip (Phase 3 confirmed; re-confirmed here).
- Registry rebuild from sentinels (Phase 3 confirmed).
- `apply_bcm_state` reconciliation (found-status, rep, timer, counters, found_color).
- `import_game` full round-trip (both checkpoint and puzzle kinds).
- Object-name collision is NOT testable headlessly (would need a pre-existing same-named object — testable, but the REPLACE behavior makes it a no-op: the loaded object replaces the existing one).

### 8.3 What needs the GUI human-verify checkpoint

- `QFileDialog` Save / Generate & export / Import buttons (Qt widget rendering, native dialog).
- The confirm dialog before Import ("Importing will replace the current PyMOL session").
- Tab-switching (Setup → Game after Generate & export; Game tab after Import).
- The full Import-to-play workflow: does the imported game PLAY correctly? (click-to-find works, timer runs, win fires, found-hider recolor visible). This requires the PickWizard + mouse + viewer — GUI-only.
- The found_color custom RGB re-registration (if `found_color_rgb` is non-null, does `cmd.set_color` + recolor produce the visually-correct color on the imported found hiders?).
- Resume-vs-fresh-start UX (checkpoint: timer continues from elapsed; puzzle: countdown then play). Headless can verify the `_start_time` math; GUI must verify the timer LABEL shows the right value.

---

## 9. Edge Cases

### 9.1 Object-name collision on Import

**Scenario:** The `.pse` has `1ubq`; the current session also has `1ubq`. `cmd.load('game.pse')` with `partial=0` (default) REPLACES the session — the existing `1ubq` is destroyed, the loaded `1ubq` takes its place.

**Behavior:** By default (no `partial=1`), the existing object is REPLACED. No collision merge is attempted. This is predictable but destructive.

**Recommendation:** Show a confirm dialog BEFORE Import:
```
"Importing will replace the current PyMOL session.
Save your work first. Continue?"
```
On confirm: `cmd.load(pse_path)` (REPLACE). This is the simplest, most predictable behavior. The user is warned; their existing work is their responsibility.

**Do NOT use `partial=1` (merge):** collision behavior for same-named objects is UNVERIFIED at the C level (`_cmd.set_session` is C-dispatched; not readable). Merge would risk silent corruption (which `1ubq` wins? do their atoms combine?). REPLACE is safe and predictable.

### 9.2 `.bcm` missing or corrupt, `.pse` fine

**Scenario:** The `.bcmz` is missing `game.bcm`, OR `json.loads` raises `ValueError` (malformed JSON), OR `magic` mismatch.

**Behavior:** `import_game` raises `ValueError` with a clear message:
- `"Not a bioCHEMeleon archive (missing game.bcm)"` — if `game.bcm` not in archive.
- `"Not a bioCHEMeleon file (magic mismatch)"` — if magic is wrong.
- The `json.loads` `ValueError` propagates as a parse error.

**Graceful degradation (alternative, for the manually-unzipped case):** if the user opens a `.pse` directly (without the plugin), the sentinel rebuild still works (registry rebuilt with `rep=None`, all hidden, timer 0). The game is playable but lacks the found-status + rep + timer metadata. This is the documented degradation for the "manual unzip + open .pse" path. For the primary `.bcmz` path, a missing/corrupt `.bcm` is a hard error (the archive is defective).

### 9.3 `.pse` missing, `.bcm` fine

**Scenario:** The `.bcmz` is missing `game.pse`.

**Behavior:** `import_game` raises `ValueError("Archive missing game.pse (cannot reconstruct)")`. Cannot reconstruct — no atoms. Hard error.

### 9.4 Versioning — future v2

**`.bcm` has `version: 1`.** On Import:
- `version == 1` → accept (current schema).
- `version > 1` → refuse: `"File schema version %d is newer than this plugin supports (1). Please update bioCHEMeleon."`
- `version < 1` (shouldn't happen — v1 is the first) → treat as v1 (the `from_dict` tolerance pattern from `registry.py:228-245` — tolerant of missing keys).

**Migration strategy for future v2:** when v2 is introduced, write a `migrate_bcm(bcm)` function that converts v1 → v2 (adds new fields with defaults). The Import path becomes: `if version < CURRENT: bcm = migrate_bcm(bcm)`. For v1, `migrate_bcm` is a no-op. The planner does NOT implement migration now (v1 only) — just the version check + refuse-newer.

### 9.5 Sentinel count mismatch (`.bcm` registry vs `.pse` atoms)

**Scenario:** The `.bcm` lists 3 hiders, but the `.pse` has 5 sentinel atoms (e.g. the educator manually added 2 atoms with `segi=GAME` after export). Or the reverse: `.bcm` lists 3, `.pse` has 2 (sentinel lost).

**Behavior:** `apply_bcm_state` iterates the SENTINEL-rebuilt records (source of truth: which atoms ARE hiders). For each, it looks up the `.bcm` entry by `id`. If a sentinel has no `.bcm` entry, it stays `rep=None`, `status='hidden'` (a "new" hider not in the sidecar — treated as a fresh hidden hider). If a `.bcm` entry has no sentinel (id missing from the `.pse`), it's silently dropped (the atom is gone — can't reconcile a non-existent atom).

**Recommendation:** after `apply_bcm_state`, log a warning if `len(sentinel_ids) != len(bcm_hiders)`:
```
"Warning: .bcm lists %d hiders but .pse has %d sentinel atoms. 
 Some hider state may be inconsistent."
```
The game is still playable; the warning surfaces the inconsistency.

---

## 10. Open Risks / Things to Verify at Runtime

These could NOT be fully verified by source-reading alone; the headless smoke + GUI checkpoint must confirm them.

### 10.1 Custom `cmd.set_color` survival across `.pse` round-trip — UNVERIFIED

**The question:** Does a custom color registered via `cmd.set_color('found_highlight', [r, g, b])` survive `cmd.save('file.pse')` + `cmd.load('file.pse')`?

**Why it matters:** If the player chose a custom found-color (Phase 7 DIFF-04, `gui_game.py:178` `cmd.set_color('found_highlight', [r, g, b])`), the found hiders are colored `'found_highlight'`. On Import, if `'found_highlight'` is not re-registered, `cmd.color('found_highlight', ...)` fails silently or colors with a fallback.

**Mitigation (already in §3.4):** store `found_color_rgb` in the `.bcm`; on Import, `cmd.set_color(found_color, found_color_rgb)` before any recolor. This is a safety net that works regardless of whether the setting survives.

**Runtime verification:** the headless smoke can test: `cmd.set_color('test_color', [0.2, 0.8, 0.3])` → `cmd.save('test.pse')` → `cmd.delete('all')` → `cmd.load('test.pse')` → check if `'test_color'` is in `cmd.get_names('colors')` (or whatever the colors API is). UNVERIFIED — needs the smoke to confirm. If it survives, the `found_color_rgb` safety net is belt-and-suspenders; if it doesn't, the safety net is load-bearing.

### 10.2 `tempfile.TemporaryDirectory()` in the Windows PyMOL process — UNVERIFIED for `cmd.save`

**The question:** Does `cmd.save(pse_path, target_obj)` work when `pse_path` is a Windows `%TEMP%` path (e.g. `C:\Users\nglok\AppData\Local\Temp\tmpXXX\game.pse`)?

**Why it matters:** `save_game` uses `tempfile.TemporaryDirectory()` to stage the `.pse` before zipping. If `cmd.save` can't write to the Windows temp dir (permissions, path issues), the save fails.

**Likely works:** `cmd.save` calls `_self.exp_path(filename)` (`exporting.py:835`) which expands paths; the Windows temp dir is a standard Windows path. Phase 3 smoke used relative paths (worked); absolute Windows paths should also work (the bundled demos use `to_windows_path`-converted absolute paths successfully — `demos.py:131-134`).

**Runtime verification:** the headless smoke (which uses `tempfile.TemporaryDirectory()` inside `save_game`) will confirm. If it fails, fall back to a relative-path temp file in the cwd.

### 10.3 Scoped save with a bare object name — UNVERIFIED at runtime (source-verified only)

**The question:** Does `cmd.save('game.pse', '1ubq')` actually exclude `_bchm_backup` at runtime?

**Source verification (HIGH confidence):** `exporting.py:973-977` (`get_psestr`) + `exporting.py:370-374` (`get_session` docstring) confirm the scoping mechanism. But the C-side `_cmd.get_session` is not readable; the `names` parameter's exact filtering semantics (single name vs space-separated list vs selection expression) are UNVERIFIED at runtime.

**Runtime verification:** the headless smoke (§8.1) explicitly checks `_bchm_backup not in cmd.get_names("all_objects")` after loading the saved `.pse` into a fresh session. This is the load-bearing assertion. If it FAILS (the backup IS in the .pse), the fallback is `cmd.delete('_bchm_backup')` before save + accept that the backup is gone from the live session (the user can't continue playing after Save — acceptable for "Save and quit" but not "Save and continue"). The scoped save is the cleaner path; the smoke confirms it.

### 10.4 `cmd.load(pse_path)` object-name collision when the user has same-named object — UNVERIFIED at runtime

**The question:** If the user has `1ubq` loaded and Imports a `.bcmz` whose `.pse` also has `1ubq`, does `cmd.load(pse_path)` cleanly REPLACE the existing `1ubq`, or does it error / merge / create a duplicate?

**Source verification (HIGH confidence):** `importing.py:823-848` (`load_pse`) + `importing.py:130-143` (`set_session` with `partial=0`) confirm REPLACE semantics. But the C-side `_cmd.set_session` behavior for same-named objects is UNVERIFIED.

**Runtime verification:** add a smoke section: load `1ubq`, then `cmd.load` a `.pse` that also has `1ubq`, then check `cmd.count_atoms('1ubq')` matches the .pse's count (not doubled, not errored). If it fails, the confirm dialog + `cmd.delete('all')` before Import is the safer path (clear everything, then load).

### 10.5 `found_color` is a PyMOL built-in name vs a custom name — runtime distinction

**The question:** `found_color` can be `"green"` (built-in) or `"found_highlight"` (custom). The `.bcm` stores both the same way (a string). The `found_color_rgb` field distinguishes: `null` for built-in, `[r, g, b]` for custom. On Import, `cmd.set_color` is only called for custom (`found_color_rgb is not None`). If a built-in color name is somehow not available in the target PyMOL (unlikely — `"green"` is universal), `cmd.color` would fail silently. Low risk; the smoke uses `"green"` (built-in) to avoid the custom-color path complexity.

---

## 11. Source Citations

### 11.1 PyMOL source (HIGH confidence — read at the absolute path)

| Claim | File:Line | Verification |
|-------|----------|--------------|
| `cmd.save` signature | `tmp/pymol-src/modules/pymol/exporting.py:782-783` | `def save(filename, selection='(all)', state=-1, format='', ref='', ref_state=-1, quiet=1, partial=0, *, _self=cmd)` |
| `get_psestr` ignores paren selections | `tmp/pymol-src/modules/pymol/exporting.py:973-977` | `if '(' in selection: selection = ''` — load-bearing for scoped save |
| `get_session(names='', ...)` — empty = all objects | `tmp/pymol-src/modules/pymol/exporting.py:370-374` | docstring: "names: Names of objects to export, or the empty string to export all objects." |
| `savefunctions['pse'] = get_psestr` | `tmp/pymol-src/modules/pymol/exporting.py:997` | dispatch entry |
| `cmd.load` signature | `tmp/pymol-src/modules/pymol/importing.py:635-637` | `def load(filename, object='', state=0, format='', finish=1, discrete=-1, quiet=1, multiplex=None, zoom=-1, partial=0, mimic=1, object_props=None, atom_props=None, *, _self=cmd)` |
| `load_pse` signature (NO `object=` param) | `tmp/pymol-src/modules/pymol/importing.py:823` | `def load_pse(filename, partial=0, quiet=1, format='pse', *, _self=cmd)` — `object` silently dropped |
| `load_pse` → `set_session(partial=0)` = REPLACE | `tmp/pymol-src/modules/pymol/importing.py:830` | `r = _self.set_session(session, quiet=quiet, partial=partial, steal=1)` |
| `set_session` C-dispatch | `tmp/pymol-src/modules/pymol/importing.py:143` | `_cmd.set_session(_self._COb, session, int(partial), int(quiet))` — C-side, not readable |
| `'pse': load_pse` dispatch | `tmp/pymol-src/modules/pymol/importing.py:1623` | format-to-function map entry |
| `load_pse` unpickling error | `tmp/pymol-src/modules/pymol/importing.py:827-828` | `CmdException('PSE contains objects which cannot be unpickled')` — Pitfall 7 |
| `cmd.delete` signature | `tmp/pymol-src/modules/pymol/commanding.py:496-522` | `def delete(name, _self=cmd)` — supports wildcards; idempotent (try/except wraps the C call) |
| `exp_path` for save/load | `exporting.py:835`, `importing.py:745` | `filename = _self.exp_path(filename)` — path expansion |

### 11.2 Existing bioCHEMeleon code (HIGH confidence — read in this session)

| Claim | File:Line |
|-------|----------|
| `HiderRegistry.to_dict()` shape | `biochemeleon/registry.py:215-225` |
| `HiderRegistry.from_dict(d)` | `biochemeleon/registry.py:227-245` |
| `HiderRecord.to_dict()` | `biochemeleon/registry.py:91-102` |
| `reconstruct_from_sentinels` (rep=None, all hidden) | `biochemeleon/registry.py:249-272` |
| `GameController.__init__` state | `biochemeleon/game.py:20-40` |
| `GameController.reconstruct_registry` | `biochemeleon/game.py:224-229` |
| `GameController.start` (snapshot + insert + register) | `biochemeleon/game.py:42-63` |
| `GameController._start_time`, `_reveal_count`, `_hint_count`, `_found_color` | `biochemeleon/game.py:26, 32, 33, 40` |
| `BACKUP_PREFIX = '_bchm_backup'` | `biochemeleon/backup.py:34` |
| `backup.snapshot` (delete + create) | `biochemeleon/backup.py:39-44` |
| `gui_setup.collect_state()` shape | `biochemeleon/gui_setup.py:441-459` |
| `gui_setup._save_setup` (QFileDialog pattern) | `biochemeleon/gui_setup.py:546-562` |
| `gui_setup._load_setup` (QFileDialog pattern) | `biochemeleon/gui_setup.py:563-588` |
| `demos.to_windows_path` | `biochemeleon/demos.py:24-43` |
| `gui_game.GameTab` structure | `biochemeleon/gui_game.py:16-77` |
| `__init__.PluginDialog._on_start` (controller lifecycle) | `biochemeleon/__init__.py:79-244` |
| `__init__._on_cleanup` (controller release) | `biochemeleon/__init__.py:265-286` |
| `SETUP_FORMAT = "biochemeleon-setup-v1"` | `biochemeleon/setup_state.py:81` |
| `DEFAULTS` dict shape | `biochemeleon/setup_state.py:84-99` |

### 11.3 Prior runtime-confirmed flags (HIGH confidence — Phase 3 smoke, 2026-08-06, NOT re-investigated)

| Claim | Source |
|-------|--------|
| `segi='GAME'` sentinel survives `.pse` save/load | `.planning/research/PITFALLS.md:447-451` (Phase 3 — Resolved Research Flags, PSE section) |
| Atom `id` stable across `.pse` round-trip | same |
| `b=-999.0` preserved exactly across `.pse` round-trip | same |
| `reconstruct_from_sentinels` rebuilds with `rep=None` | same |
| PyMOL Open Source has NO undo (`undocontext` no-op stub) | `.planning/research/PITFALLS.md:276-285` (Pitfall 10) |
| `cmd.iterate` exposes `id` as uppercase `ID` | `.planning/research/PITFALLS.md:457` (Phase 3 smoke discovery) |
| b-factor selectors are COMPARISONS (`b < 0`), never exact (`b -999`) | `.planning/research/PITFALLS.md:459` |
| Headless PyMOL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq` | `AGENTS.md` Environment section |

### 11.4 Webfetch / external sources

None used. All findings are from PyMOL source (read directly) + existing code (read directly) + prior runtime-confirmed flags (cited from PITFALLS.md).

---

## Metadata

**Confidence breakdown:**
- `.pse` save/load mechanics: **HIGH** — verified against `pymol-src/modules/pymol/exporting.py:782-977` + `importing.py:635-848` (source-read, file:line cited). The scoped-save quirk (`get_psestr` line 974 `if '(' in selection`) is the load-bearing finding; the smoke (§8) will runtime-confirm.
- `.bcm` JSON schema: **HIGH** — built on the runtime-confirmed Phase 3 `to_dict`/`from_dict`/`reconstruct_from_sentinels` (PITFALLS.md §447-451); the top-level fields map 1:1 to `GameController` attributes (`game.py:20-40`) which are read in this session.
- Co-location UX (zip vs naming): **MEDIUM** — a UX decision (not a verifiable fact); stdlib `zipfile` is HIGH confidence; the single-file-share rationale is a workflow judgment (educator sharing is the primary use case per `ROADMAP.md:170-176`).
- Path handling: **HIGH** — Phase 2 + Phase 3 smoke patterns confirmed the WSL/Windows split; `QFileDialog` returns Windows paths in Windows PyMOL (Phase 2 verified); `tempfile.TemporaryDirectory()` in the Windows process yields Windows temp paths (UNVERIFIED for `cmd.save` specifically — §10.2).
- Edge cases: **HIGH** for the schema-version + missing-file logic (designed from the source); **MEDIUM** for object-name collision (REPLACE semantics source-verified; C-side collision behavior UNVERIFIED — §10.4).

**Research date:** 2026-08-12
**Valid until:** 2026-09-12 (30 days — stable for the Phase 8 planning + execution window; the `.pse` mechanics are unlikely to change within a PyMOL 2.5.0 minor version)
