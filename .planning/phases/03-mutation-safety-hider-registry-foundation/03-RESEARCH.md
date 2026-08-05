# Phase 3: Mutation Safety & Hider Registry Foundation - Research

**Researched:** 2026-08-05
**Domain:** PyMOL 2.5.0 open-source object mutation, snapshot/restore, atom-id tracking
**Confidence:** HIGH (API signatures + semantics verified from bundled PyMOL 2.5.0 source at `./tmp/pymol-src/`; 4 narrow C-dispatched behaviors flagged UNVERIFIED with smoke-test resolutions)

## Summary

Phase 3 de-risks the single highest-uncertainty area of the project: safely inserting "hider" pseudoatoms INTO an existing PyMOL object, tracking them by stable atom `id`, and proving that backup → mutate → cleanup (or restore) leaves the original structure byte-identical. I read the bundled PyMOL 2.5.0 open-source Python sources directly (creating.py, editing.py, querying.py, commanding.py, editor.py, selector.py) and verified every API signature, default, and return value this phase depends on.

The locked decisions (AGENTS.md + STATE.md) hold up against the source: `cmd.pseudoatom(object=existing, ...)` inserts INTO an existing object (no new object created — verified from the signature at creating.py:1082); the sentinel `segi='GAME'` + `b=-999` is set via `cmd.alter` with a single semicolon-joined expression (canonical pattern confirmed at editor.py:354); and `undocontext` is a no-op stub in open-source (editor.py:25-36 — confirms PyMOL has NO undo, so manual snapshot/restore is mandatory). The atom `id` (fetched via `cmd.identify(sele, mode=0)` or `cmd.iterate(sele, "stored.append(id)", space={...})`) is the STABLE identifier — `cmd.index()`'s own docstring (querying.py:1313-1317) explicitly contrasts "fragile indices" vs "integral atom identifiers," confirming `id` survives `cmd.remove` while `index` does not.

Four behaviors dispatch to C (`_cmd.*`) and could NOT be verified from Python alone: (1) whether `cmd.pseudoatom`'s return value is the new atom's id or a status code — **do not rely on it**; fetch the id via `identify` after insertion; (2) `cmd.create(existing, backup)` merge-vs-replace semantics — **sidestep with `delete` + `create`** for restore; (3) whether `cmd.create` preserves source atom `id` values — **smoke-test the id-set**; (4) `.pse` round-trip id/index stability — **smoke-test it**. Each has a concrete spike in the smoke-test plan.

**Primary recommendation:** Split the cmd-coupled work into THREE new focused modules (`registry.py` pure, `backup.py`, `mutation.py`) instead of piling everything into `game.py`, so the ~20 small plans can run in 3 parallel waves instead of one long sequential chain. `game.py` becomes a thin orchestrator wired last.

## Standard Stack

This phase adds NO new third-party dependencies. It uses only what `pymol-open-source` 2.5.0 ships + the existing pure layer.

### Core (PyMOL 2.5.0 built-in — already available)
| API | Source location | Purpose | Why standard |
|------|-----------------|---------|---------------|
| `cmd.pseudoatom` | creating.py:1082 | Insert one atom INTO an existing object (no new object) | Only built-in in-place atom insert; AGENTS.md-locked method |
| `cmd.create` | creating.py:960 | Snapshot copy + restore copy | The canonical object-copy primitive |
| `cmd.delete` | commanding.py:496 | Discard backup / remove mutated target before restore | Wildcard-capable object removal |
| `cmd.remove` | editing.py:800 | Sentinel-based hider cleanup (`obj and segi GAME`) | Removes atoms FROM an object without deleting the object |
| `cmd.alter` | editing.py:1424 | Set `segi='GAME'; b=-999.0` sentinel | Multi-field assign in one call (editor.py:354 idiom) |
| `cmd.iterate` | editing.py:1490 | Fetch `id` list + atomic tuples for verify | Read-only per-atom eval with `space=` injection |
| `cmd.identify` | querying.py:1269 | Get stable atom `id` list (mode=0) | Returns integral `id`, not fragile `index` |
| `cmd.count_atoms` | querying.py:1412 | Count assertions | Cheap structure-integrity check |
| `cmd.get_names` | querying.py:1148 | "object list unchanged" assertion (criterion 1) | `public_objects` mode hides `_bchm_backup` |
| `cmd.sort` | (C-dispatched) | Re-canonicalize atom order after alter | Defensive; optional for Phase 3 (see alter warning, editing.py:1457) |

### Supporting (existing project layer)
| Module | Purpose | When to use |
|--------|---------|-------------|
| `setup_state.GAME_REPS` | The 5 valid reps (`['lines','sticks','spheres','cartoon','ribbon']`) | Validate `rep` field in HiderRegistry |
| `demos.to_windows_path` | WSL→Windows path guard | Only if smoke test reads/writes files (it uses `/tmp` on Windows side; minor) |

### Alternatives Considered
| Instead of | Could use | Tradeoff (why we don't) |
|------------|-----------|--------------------------|
| `cmd.pseudoatom(object=existing)` | `cmd.fuse(mode=3)` (combine without bond) | `fuse` needs a 2nd temp object + single-atom selections; more moving parts. `pseudoatom` is the AGENTS.md-locked method and is simpler. `fuse` modes 1/2/3 verified at editing.py:937 for later phases. |
| `delete` + `create` to restore | single `create(existing, backup)` | Single-call merge-vs-replace is UNVERIFIED from source (C-dispatched, creating.py:1024). `delete`+`create` is unambiguous. |
| key registry by `index` | key by `id` | `index` is "fragile and will change as atoms are added or deleted" (querying.py:1315). `id` is the integral stable identifier. Locked by Pitfall 4. |

**Installation:** None. No `pip install`. (opencode.json denies `pip*`/`apt*`/`conda*`; python3.6 is WSL test-only.)

## API Verification

All citations are `pymol-open-source` 2.5.0 source at `./tmp/pymol-src/modules/pymol/`. "UNVERIFIED" = dispatches to C (`_cmd.*`) and could not be confirmed from Python.

### Q1. `cmd.pseudoatom` — signature, return value, id-fetch (creating.py:1082-1134)

**Full signature** (creating.py:1082-1084):
```python
def pseudoatom(object='', selection='', name='PS1', resn='PSD', resi='1', chain='P',
               segi='PSDO', elem='PS', vdw=-1.0, hetatm=1, b=0.0, q=0.0, color='',
               label='', pos=None, state=ALL_STATES, mode='rms', quiet=1, _self=cmd):
```

**Confirmed accepted keyword args + defaults:** `object` (target object — insert INTO this), `selection`, `name='PS1'`, `resn='PSD'`, `resi='1'`, `chain='P'`, `segi='PSDO'`, `elem='PS'`, `vdw=-1.0`, `hetatm=1`, `b=0.0`, `q=0.0`, `color=''`, `label=''`, `pos=None` (a 3-list/tuple of floats), `state`, `mode`, `quiet`. All of `elem/resn/resi/chain/segi/hetatm/vdw/b/q/name` are settable at insertion — confirming Pitfall 3's required explicit overrides.

**Return value — UNVERIFIED as atom id.** Body (creating.py:1126-1134):
```python
r = _cmd.pseudoatom(_self._COb, str(object), str(selection), ...)
...
return r
```
`r` comes from the C layer and is checked via `_self._raising(r, _self)` (error gate). No caller in the bundled source captures `cmd.pseudoatom()`'s return as an id. **Do NOT rely on the return value being the new atom's id.** Treat it as a status code.

**Does it create a new object?** No. Docstring (creating.py:1089-1090): "adds a pseudoatom to a molecular object, and will [create] the molecular object if it does not yet exist." When `object=<existing>`, the atom is inserted INTO that object → `cmd.get_names("public_objects")` is unchanged. This is criterion 1's mechanism. (UNVERIFIED-from-Python that the C path truly in-place-appends vs. shadow-creates — but the docstring + the lock semantics + AGENTS.md lock all agree; smoke test asserts it.)

**Does it reindex existing atoms' `id`?** The Python body calls only `_cmd.pseudoatom` (no `_cmd.sort`/`_cmd.alter` that would reassign ids). Existing-atom `id` stability across a pseudoatom insert is **UNVERIFIED from Python** (C-dispatched), but strongly implied by `cmd.index()`'s docstring contrast (querying.py:1313-1317, see Q4). Smoke-test the id-set before/after insert.

**Recommended id-fetch pattern (reliable, no reliance on return value):** give each hider a unique `name` handle at insertion, then fetch its `id` via `cmd.identify`:
```python
cmd.pseudoatom(object=obj, pos=[x, y, z], name=handle,    # handle e.g. "H001"
               segi='GAME', b=-999.0, hetatm=1, elem='PS',
               resn='HIDER', chain='H', resi=str(9001 + n))
ids = cmd.identify(f"{obj} and name {handle} and segi GAME", mode=0)
assert len(ids) == 1
new_id = ids[0]
```
`name` is a throwaway insertion handle; the registry keys on `id` only, leaving `name`/`elem`/`resn` free for Phase 4/5 plausibility work. Batch alternative: insert all hiders with distinct handles, then ONE `cmd.iterate(f"{obj} and segi GAME", "stored.append((name, id))", space={'stored': []})` → map `name → id`.

### Q2. `cmd.create` merge-append vs replace (MEDIUM flag) (creating.py:960-1036)

**Full signature** (creating.py:960-962):
```python
def create(name, selection, source_state=0, target_state=0, discrete=0,
           zoom=-1, quiet=1, singletons=0, extract=None, copy_properties=False, _self=cmd):
```

**Snapshot is a deep independent copy.** `cmd.create('_bchm_backup', target_obj)` makes a new object whose atom records are copies of the selection (creating.py:966 "creates a new molecule object from a selection"). Mutating `target_obj` after the snapshot does NOT affect the backup. HIGH confidence (standard PyMOL semantics; the body's `_self.lock`/`_self.unlock` around `_cmd.create` shows a real C create, creating.py:1021-1028).

**Merge-vs-replace — UNVERIFIED from Python (C-dispatched).** The body (creating.py:1024-1026) calls `_cmd.create(...)` with no Python-level merge logic; docstring (creating.py:966-967) says "creates a new molecule object from a selection. It can also be used to create states in an existing object." The peptide builder at editor.py:355 uses `create(name, "frag or ?name", ...)` to MERGE via a union selection, and join_states (creating.py:1180) uses `target_state=-1` to APPEND a state. With default `target_state=0` on an EXISTING object, `create(existing, other_obj)` is *believed* to REPLACE state 0's contents, but this is C behavior.

**Recommended restore pattern (eliminates all ambiguity):**
```python
cmd.delete(target_obj)        # remove mutated object entirely (commanding.py:496)
cmd.create(target_obj, backup)  # fresh atom-for-atom copy from backup
```
`delete` removes the whole object (including hiders); `create` makes a clean copy. No merge ambiguity. **Use this. Do NOT use single-call `cmd.create(existing, backup)` for restore** (it's the flagged MEDIUM behavior). The single-call form is fine for the *snapshot* direction (`create('_bchm_backup', target_obj)`) because `_bchm_backup` doesn't exist yet → no merge question.

**Does create preserve source atom `id` values?** UNVERIFIED from Python (C-dispatched). `create` copies atom records; the `id` field (external integral id) is *believed* preserved while `index` is reassigned contiguously. **Smoke-test**: iterate the id-set of the backup and of the restored object; assert equality. If ids are NOT preserved, the registry must be rebuilt after restore (acceptable — restore is the failure/abort path). For the happy path (cleanup by `cmd.remove`), ids ARE stable (see Q4) so registry continuity is only at risk on the restore path.

### Q3. `cmd.alter` sentinel assignment (editing.py:1424-1473)

**Signature:** `alter(selection, expression, quiet=1, space=None, _self=cmd)`.

**Multi-field assign in ONE call — CONFIRMED canonical.** editor.py:354 uses three `;`-joined assignments in a single alter string:
```python
_self.alter(tmp_obj, 'resi="""%s""";chain="""%s""";segi="""%s"""' % (resi, chain, segi))
```
So `cmd.alter(sele, "segi='GAME'; b=-999.0")` works. The outer Python string is double-quoted; the inner string value `GAME` is single-quoted; `b` is a float (no quotes). This is the sentinel-set call. HIGH confidence.

**Writable symbols** (editing.py:1446-1449): `name, resn, resi, resv, chain, segi, elem, alt, q, b, vdw, type, partial_charge, formal_charge, elec_radius, text_type, label, numeric_type, color, ss, cartoon, flags`. Read-only (`*`): `model, state, index, ID, rank`. So you can set `segi` and `b` but NOT `ID`. (The registry reads `id` via `iterate`, never writes it.)

**Works on a single-atom selection** — yes (alter iterates per-atom over whatever selection; a one-atom selection sets that one atom).

**`space=` pattern — CONFIRMED.** editing.py:47-62 (`_iterate_prepare_args`): if `space is None`, the expression runs against the GLOBAL `pymol.__dict__` (legacy `stored.xxx` pattern, pollutes global namespace). **Pass an explicit dict** to stay hygienic:
```python
stored = []
cmd.iterate(sele, "stored.append(id)", space={'stored': stored})
# stored now populated as a side effect
```
editor.py:156 confirms the variant `space={'tmp': tmp}` where the expression both reads and writes the dict. **Always pass `space={...}`; never rely on the global `stored` module.**

**`sort` warning** (editing.py:1457-1460): "issue a 'sort' command on an object after modifying any property which might affect canonical atom ordering (names, chains, etc.). Failure to do so will confound subsequent 'create' and 'byres' operations." Setting `segi`/`chain` on hiders can affect ordering. **Recommend `cmd.sort(obj)` after the sentinel alter as a defensive habit** (the fab builder implicitly relies on ordered creates). `sort` reassigns `index` but preserves `id` — safe for the id-keyed registry. It is NOT strictly required for Phase 3's happy path (we don't `create`/`byres` on the mutated object except the restore path, which `delete`s first), but cheap to include.

### Q4. `id` vs `index` stability (Pitfall 4 deep dive)

**`cmd.iterate` exposes `id`** (editing.py:1446-1449 lists `ID` read-only; the iterate docstring editing.py:1504-1509 uses `name`, and the same symbol table applies). `cmd.iterate(sele, "stored.append(id)", space={'stored': []})` returns the integral atom `id`. CONFIRMED.

**`cmd.identify(mode=0)` returns the `id` list** (querying.py:1282-1283): "mode 0: only return a list of identifiers (default)". `mode=1` returns `[(object_name, id), ...]` (querying.py:1283). So `cmd.identify("obj and segi GAME", mode=0)` → `[id1, id2, ...]`. CONFIRMED — mode=0 is the `id`, NOT the `index`.

**`cmd.index()` returns `(object, index)` tuples and WARNS indices are fragile** (querying.py:1302-1330), docstring (querying.py:1313-1317):
> "Atom indices are fragile and will change as atoms are added or deleted. Whenever possible, use integral atom identifiers instead of indices."

This is the source-level proof of Pitfall 4: **`id` (integral identifier) is stable across add/delete; `index` is not.** HIGH confidence.

**`cmd.id_atom(sele)`** (querying.py:1235-1267): returns the single `id` for a one-atom selection (raises if 0 or >1). Handy for the click handler (Phase 4) — note it now, implement later.

**Does inserting a pseudoatom change existing atoms' `id`?** UNVERIFIED from Python (C-dispatched). Strongly implied NO by the index/id contrast above. **Smoke-test**: `before = set(cmd.identify(obj, mode=0))`; insert pseudoatom; `after = set(cmd.identify(obj, mode=0))`; assert `before ⊆ after` and `after - before == {new_id}` (existing ids unchanged).

**Does `cmd.remove` reindex remaining atoms' `id`?** UNVERIFIED from Python (C-dispatched), but the index/id contrast implies `id` is stable across remove (only `index` shifts). **Smoke-test**: record id-set, `cmd.remove("obj and segi GAME")`, assert surviving id-set == original id-set.

**`.pse` save/load round-trip id stability** (MEDIUM flag): UNVERIFIED from Python. **Smoke-test spike** (see Smoke Test Plan §6): save .pse after inserting hiders, reload, iterate ids, compare. Sentinel (`segi GAME`, `b -999`) survival is the fallback detection mechanism per AGENTS.md — even if ids shift, the registry can be *reconstructed* from sentinels (with `rep` lost, recovered via Phase 8 sidecar).

## Registry Design (Q5)

### Pure-layer data model — `biochemeleon/registry.py` (NEW, PURE)

Lives in the pure layer (stdlib only, NO `pymol` import) so it is WSL-unit-testable, mirroring `setup_state.py`'s convention (setup_state.py:1-16 — `import random`/`copy` only). Imports `GAME_REPS` from `setup_state` for `rep` validation. The cmd-coupled reconstruction goes in `game.py` and injects an iterate function (dependency inversion keeps the model pure).

**Fields per hider (Phase 3 minimal set):**
| Field | Type | Phase 3? | Why |
|-------|------|----------|-----|
| `id` | int | REQUIRED | Primary key; stable atom id (Pitfall 4). |
| `object` | str | REQUIRED | PyMOL object name (ids are per-object; future multi-object safety). |
| `rep` | str | REQUIRED | One of `GAME_REPS`; needed for criterion 3 (per-rep counts). |
| `status` | str | REQUIRED (default `'hidden'`) | `'hidden'`/`'found'`. Field exists now (cheap); `found` is set in Phase 4/6. |
| `pos` | (float,float,float) | DEFERRED | For hint/reveal (Phase 6). Store now optionally; cheap. |
| `hint_count` | int | DEFERRED | Phase 6. |
| `inserted_at` | int | DEFERRED | Ordering; not needed Phase 3. |

**Key = `(object, id)` tuple** (Pitfall 4 says track by `(object, atom_id)`; for Phase 3 single-target, `id` alone would do, but `(object, id)` is future-safe and matches the locked decision).

**Recommended API surface:**
```python
# biochemeleon/registry.py — PURE (stdlib only)
from collections import OrderedDict
from .setup_state import GAME_REPS

HIDER_STATUS_HIDDEN = 'hidden'
HIDER_STATUS_FOUND = 'found'

class HiderRecord:
    __slots__ = ('id', 'object', 'rep', 'status', 'pos')
    def __init__(self, id, object, rep, status=HIDER_STATUS_HIDDEN, pos=None):
        if rep not in GAME_REPS:
            raise ValueError("rep must be one of %r" % (GAME_REPS,))
        self.id = int(id); self.object = object; self.rep = rep
        self.status = status; self.pos = pos
    def key(self):
        return (self.object, self.id)
    def to_dict(self):
        d = {'id': self.id, 'object': self.object, 'rep': self.rep, 'status': self.status}
        if self.pos is not None: d['pos'] = list(self.pos)
        return d

class HiderRegistry:
    def __init__(self):
        self._records = OrderedDict()   # key (object,id) -> HiderRecord
    def register(self, object, id, rep, status=HIDER_STATUS_HIDDEN, pos=None):
        rec = HiderRecord(id, object, rep, status, pos)
        if rec.key() in self._records:
            raise KeyError("hider %r already registered" % (rec.key(),))
        self._records[rec.key()] = rec
        return rec
    def get(self, object, id):
        return self._records.get((object, int(id)))
    def all(self):
        return list(self._records.values())
    def by_rep(self, rep):
        return [r for r in self._records.values() if r.rep == rep]
    def counts_by_rep(self):
        out = {r: 0 for r in GAME_REPS}
        for r in self._records.values():
            out[r.rep] = out.get(r.rep, 0) + 1
        return out
    def remove(self, object, id):
        return self._records.pop((object, int(id)), None) is not None
    def mark_found(self, object, id):
        rec = self._records[(object, int(id))]; rec.status = HIDER_STATUS_FOUND
    def reconstruct_from_sentinels(self, iterate_hider_keys):
        """Rebuild registry from sentinel atoms after .pse reload.
        iterate_hider_keys: callable -> iterable of (object, id) for segi-GAME b--999 atoms.
        Pure: cmd-coupled iterate is INJECTED by game.py. rep is unknown post-reload
        (set to None pending Phase 8 sidecar reconciliation)."""
        self._records.clear()
        for (obj, aid) in iterate_hider_keys():
            self._records[(obj, int(aid))] = HiderRecord(aid, obj, rep=None,
                                                         status=HIDER_STATUS_HIDDEN)
        return self
    def to_dict(self):
        return {'version': 1, 'hiders': [r.to_dict() for r in self._records.values()]}
    @classmethod
    def from_dict(cls, d):
        reg = cls()
        for h in d.get('hiders', []):
            reg.register(h['object'], h['id'], h['rep'], h.get('status', 'hidden'),
                         h.get('pos'))
        return reg
```

**Notes:**
- `rep=None` is allowed in `reconstruct_from_sentinels` (relax the `GAME_REPS` check there, or add a sentinel-reconstruction path that bypasses validation). The Phase 3 smoke test only checks in-memory `counts_by_rep` (criterion 3); post-reload rep recovery is Phase 8 (sidecar). Flag this as a known limitation (Open Risks).
- `to_dict`/`from_dict` is the Phase 8 `.bcm` sidecar shape — design now, implement in Phase 8. Phase 3 only unit-tests it round-trips.
- `reconstruct_from_sentinels` takes the iterate fn as a parameter → `registry.py` stays pure and WSL-testable (pass a fake fn in tests).

**Serialization shape (for Phase 8 `.bcm` sidecar):**
```json
{
  "version": 1,
  "target_object": "1ubq",
  "hiders": [
    {"id": 1234, "object": "1ubq", "rep": "spheres", "status": "hidden"}
  ]
}
```

## Backup/Restore Design (Q6)

### cmd-coupled helpers — `biochemeleon/backup.py` (NEW, cmd-coupled)

Lives in the cmd layer (imports `from pymol import cmd`). NOT WSL-testable at runtime — only syntax-checked (`python3.6 -m py_compile`) + Windows PyMOL smoke test.

```python
# biochemeleon/backup.py — cmd-coupled
from pymol import cmd

BACKUP_PREFIX = '_bchm_backup'   # underscore => private (hidden from public_objects)

def snapshot(target_obj):
    """Create a private independent backup copy of target_obj. Returns backup name.
    Discards any stale backup first. HIGH confidence (create = deep copy)."""
    cmd.delete(BACKUP_PREFIX)                       # commanding.py:496
    cmd.create(BACKUP_PREFIX, target_obj)           # creating.py:960 (fresh copy)
    return BACKUP_PREFIX

def restore(target_obj, backup_name=BACKUP_PREFIX):
    """FAILURE-PATH restore: target ends up atom-for-atom identical to backup.
    Uses delete+create to avoid merge-vs-replace ambiguity (UNVERIFIED single-call).
    Returns True on success, False on failure (caller aborts game)."""
    try:
        cmd.delete(target_obj)                       # remove mutated object entirely
        cmd.create(target_obj, backup_name)          # fresh copy from backup
        return True
    except Exception:
        return False

def discard(backup_name=BACKUP_PREFIX):
    """Delete the backup object. Idempotent."""
    cmd.delete(backup_name)

def verify_intact(target_obj, backup_name=BACKUP_PREFIX):
    """Return True iff target's structure matches backup: atom count + atomic tuple multiset.
    Tuple = (resn, resi, name, chain, segi, x, y, z). Coords are exact for a create-copy."""
    if cmd.count_atoms(target_obj) != cmd.count_atoms(backup_name):
        return False
    def _tuples(obj):
        out = []
        cmd.iterate(obj, "stored.append((resn, resi, name, chain, segi, x, y, z))",
                    space={'stored': out})            # editing.py:1490
        return out
    return sorted(_tuples(target_obj)) == sorted(_tuples(backup_name))
```

**`verify_intact` strategy:** count check (cheap, catches gross mismatch) + atomic-tuple multiset equality (catches any coordinate/residue/name drift). Exact float equality is safe because `create` copies coords bit-for-bit. A stronger/alternative check is id-set equality — but id-preservation across `create` is UNVERIFIED (Q2), so the tuple-multiset is the reliable primary check; the smoke test ALSO asserts id-set equality as a secondary (informational) check to resolve the flag.

**Error handling:**
- `snapshot` is infallible-ish (delete is idempotent; create of a fresh name can't merge). If `target_obj` doesn't exist, `create` errors — caller ensures target exists before Start.
- `restore` wraps `delete`+`create` in try/except and returns bool. Caller (game.py) on `False`: log, discard backup, abort the game (the target may be in a bad state — surface a QMessageBox to the user; but that's Phase 4 UI wiring, not Phase 3).
- `verify_intact` is a pure query (no mutation); returns bool. Caller asserts in smoke test; in production (Phase 4) a False triggers restore.

**Where it lives:** `backup.py` (cmd-coupled). The pure layer (`registry.py`) cannot call cmd. `game.py` orchestrates `backup.*` + `mutation.*` + `registry.HiderRegistry`.

**`cmd.remove` sentinel cleanup** lives in `mutation.py` (not backup.py) — it mutates the target, not the backup:
```python
# biochemeleon/mutation.py — cmd-coupled
from pymol import cmd
from . import registry as _reg   # pure; lazy import to avoid circulars

def insert_hider(object, pos, rep, handle, segi='GAME', b=-999.0):
    """Insert one hider pseudoatom INTO object. Returns the new atom's id (fetched via identify)."""
    cmd.pseudoatom(object=object, pos=list(pos), name=handle,     # creating.py:1082
                    segi=segi, b=b, hetatm=1, elem='PS',
                    resn='HIDER', chain='H', resi='9001')
    cmd.alter(f"{object} and name {handle}", "segi='GAME'; b=-999.0",
              space={})                                           # editing.py:1424; editor.py:354 idiom
    cmd.sort(object)                                             # defensive (editing.py:1457)
    ids = cmd.identify(f"{object} and name {handle} and segi GAME", mode=0)  # querying.py:1269
    assert len(ids) == 1, "expected 1 new hider id, got %r" % (ids,)
    return ids[0]

def fetch_all_hider_ids(object):
    """All hider ids in object (by sentinel). For registry reconstruct/verify."""
    out = []
    cmd.iterate(f"{object} and segi GAME and b -999", "stored.append((model, id))",
                space={'stored': out})                            # editing.py:1490
    return out  # list of (object_name, id)

def cleanup_hiders(object):
    """Remove all hiders from object by sentinel. Returns count removed."""
    before = cmd.count_atoms(f"{object} and segi GAME")           # querying.py:1412
    if before:
        cmd.remove(f"{object} and segi GAME")                     # editing.py:800
    return before
```
(`alter(..., space={})` passes an empty dict — explicit, avoids global namespace pollution per Q3.)

## Smoke Test Plan (Q7)

The WSL agent cannot run PyMOL. The smoke test is the formal Phase 3 verification, run by a HUMAN in Windows PyMOL. **Recommended format: a single Python script** run via `pymol -cq phase3_smoke.py` (command-line, no GUI — most automatable; one command). It imports the real `biochemeleon` modules (copied via `wsl2_win_cp.sh` to the Windows side) so it tests the actual implementation, and prints `PASS/FAIL` per assertion with a final summary and nonzero exit on any failure.

**Setup (human, one time):**
1. From WSL: `bash wsl2_win_cp.sh` (copies `biochemeleon/` to `tmp/bioCHEMeleon/`).
2. In Windows: activate env (`setenv.bat`), `cd` to the Windows `tmp/bioCHEMeleon/` path, copy `smoke/phase3_smoke.py` there.
3. Run: `pymol -cq phase3_smoke.py` (or `pymol` then `run phase3_smoke.py`).

**The script** (`smoke/phase3_smoke.py`):
```python
# phase3_smoke.py — Phase 3 verification. Run: pymol -cq phase3_smoke.py
import sys
from pymol import cmd
from biochemeleon import backup, mutation, registry

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- setup ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)
orig_ids = set(cmd.identify(obj, mode=0))
orig_pubnames = set(cmd.get_names("public_objects"))

# --- snapshot ---
bname = backup.snapshot(obj)
check("snapshot name == _bchm_backup", bname == "_bchm_backup")
check("backup private (not in public_objects)", bname not in cmd.get_names("public_objects"))
check("backup in objects", bname in cmd.get_names("objects"))
check("backup count == orig", cmd.count_atoms(bname) == orig_count)

# --- insert 3 hiders ---
reg = registry.HiderRegistry()
handles = ["H00", "H01", "H02"]
reps = ["spheres", "sticks", "lines"]
for h, rep in zip(handles, reps):
    aid = mutation.insert_hider(obj, pos=[10.0, 10.0, 10.0], rep=rep, handle=h)
    reg.register(object=obj, id=aid, rep=rep)
    check("hider %s id fetched (not None)" % h, aid is not None)

# --- criterion 1: object list unchanged ---
check("C1: public object list unchanged", set(cmd.get_names("public_objects")) == orig_pubnames)
check("C1: count += 3", cmd.count_atoms(obj) == orig_count + 3)

# --- criterion 2: sentinel on all hiders ---
sent = []
cmd.iterate(f"{obj} and segi GAME", "stored.append((id, segi, b))", space={'stored': sent})
check("C2: 3 sentinel atoms", len(sent) == 3)
check("C2: all segi=GAME and b=-999", all(s == 'GAME' and abs(b - (-999.0)) < 1e-6 for _, s, b in sent))

# --- existing ids unchanged after insert (Q4 spike) ---
new_ids = set(cmd.identify(obj, mode=0))
check("Q4: existing ids stable across insert", orig_ids.issubset(new_ids) and len(new_ids - orig_ids) == 3)

# --- criterion 3: registry queries + per-rep counts ---
check("C3: registry len == 3", len(reg.all()) == 3)
check("C3: per-rep counts", reg.counts_by_rep() == {"spheres":1, "sticks":1, "lines":1, "cartoon":0, "ribbon":0})

# --- criterion 4 happy path: cleanup by sentinel ---
removed = mutation.cleanup_hiders(obj)
check("C4: cleanup removed 3", removed == 3)
check("C4: count back to orig", cmd.count_atoms(obj) == orig_count)
check("C4: id-set matches orig (Q4 spike)", set(cmd.identify(obj, mode=0)) == orig_ids)
check("C4: verify_intact", backup.verify_intact(obj, bname))
backup.discard(bname)
check("backup discarded", bname not in cmd.get_names("objects"))

# --- failure path: restore from backup ---
bname2 = backup.snapshot(obj)
mutation.insert_hider(obj, pos=[99.0, 99.0, 99.0], rep="spheres", handle="F00")
check("pre-restore count +1", cmd.count_atoms(obj) == orig_count + 1)
ok = backup.restore(obj, bname2)
check("failure-path restore returns True", ok)
check("failure-path: count back to orig", cmd.count_atoms(obj) == orig_count)
check("failure-path: verify_intact after restore", backup.verify_intact(obj, bname2))
# Q2 spike: does create preserve ids on restore? (informational)
restored_ids = set(cmd.identify(obj, mode=0))
check("Q2: restore preserves id-set (informational)", restored_ids == orig_ids)
backup.discard(bname2)

# --- Q2 spike: single-call create(existing, backup) merge vs replace ---
cmd.create("_spike_src", obj)
n_before = cmd.count_atoms(obj)
cmd.create(obj, "_spike_src")   # the AMBIGUOUS single-call form
n_after = cmd.count_atoms(obj)
check("Q2: single-call create is REPLACE (not append/double)", n_after == n_before)
cmd.delete("_spike_src")

# --- Q1 spike: pseudoatom return value ---
ret = cmd.pseudoatom(object=obj, pos=[1.0, 1.0, 1.0], name="R00", segi="GAME", b=-999.0)
print("Q1: cmd.pseudoatom return value = %r (type %s)" % (ret, type(ret).__name__))
cmd.remove(f"{obj} and name R00")

# --- MEDIUM flag: .pse round-trip id/sentinel stability ---
bname3 = backup.snapshot(obj)
saved_id = mutation.insert_hider(obj, pos=[5.0, 5.0, 5.0], rep="spheres", handle="P00")
cmd.save("/tmp/phase3_test.pse")
cmd.delete(obj)
cmd.load("/tmp/phase3_test.pse")
pse_sent = []
cmd.iterate(f"{obj} and segi GAME", "stored.append(id)", space={'stored': pse_sent})
check("PSE: hider survives reload by sentinel", len(pse_sent) == 1)
check("PSE: hider id stable across round-trip", pse_sent == [saved_id])
reg2 = registry.HiderRegistry().reconstruct_from_sentinels(lambda: mutation.fetch_all_hider_ids(obj))
check("PSE: registry reconstructs from sentinels", len(reg2.all()) == 1)
mutation.cleanup_hiders(obj)
backup.discard(bname3)

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
```

**Expected outputs (what the human checks):**
- Every line prints `PASS:`. The three spike lines (Q1/Q2/PSE) print their value + `PASS` (or `FAIL` + the flagged behavior — which is itself a useful research result; record it in the phase SUMMARY).
- Final: `ALL PASSED` and exit 0.
- If `Q2: single-call create is REPLACE` prints `FAIL` (i.e., it appended/doubled), that CONFIRMS the recommendation to use `delete`+`create` for restore — record and proceed.
- If `PSE: hider id stable across round-trip` prints `FAIL`, the MEDIUM flag resolves to "ids are NOT stable across .pse reload" → registry must rely on sentinel reconstruction + Phase 8 sidecar for `rep` — record and proceed (the sentinel-survival check is the load-bearing one).

**Why a script not .pml:** Python gives assertions + exit codes + a single re-runnable artifact. `.pml` is line-by-line and has no assertions. The script can also be checked into `smoke/` for regression.

## Plan-Splitting Seams (Q8) — CRITICAL

The user wants aggressive atomicity (20+ small plans acceptable). The dominant constraint: **all cmd-coupled work would land in `game.py` if we don't split, forcing one long sequential chain.** The key architectural recommendation:

> **Split cmd-coupled Phase 3 work into THREE new focused modules** — `registry.py` (pure), `backup.py` (cmd), `mutation.py` (cmd) — and keep `game.py` as a thin orchestrator wired LAST. This turns 1 sequential chain into 3 parallel waves.

### Proposed module split (dependency direction preserved)
```
setup_state.py (PURE, existing) ── GAME_REPS
        ↑
registry.py (PURE, NEW) ── HiderRegistry + HiderRecord
        ↑
mutation.py (cmd, NEW) ── insert_hider / cleanup_hiders / fetch ids   (imports registry lazily)
backup.py   (cmd, NEW) ── snapshot / restore / discard / verify_intact (standalone, no registry import)
        ↑                           ↑
        └──── game.py (cmd, existing stub) ─── orchestrator ────┘
```
- `registry.py` is pure (stdlib + `from .setup_state import GAME_REPS`) → WSL unit-testable, no MagicMock needed.
- `backup.py` is standalone cmd (no import of registry/mutation) → independent file, parallel-safe.
- `mutation.py` imports `registry` only to pass records up (and can do so lazily / via the returned id) → its file is independent of `backup.py`.
- `game.py` imports all three and wires Start/Cleanup → sequential, LAST.
This respects AGENTS.md's strict dependency direction (pure ← cmd ← Qt) and the existing stub comment ("GameController + HiderRegistry — populated in Phase 3/4"): the *data model* `HiderRegistry` moves to `registry.py` (pure), and `game.py` keeps the *controller*.

### Candidate plans (~20), grouped into parallelization waves

**Wave 1 — INDEPENDENT modules (parallel across files; intra-file sequential)**

| # | Objective | Files | Deps |
|---|-----------|-------|------|
| 03-01 | `registry.py`: `HiderRecord` + `HiderRegistry` core (`register`/`get`/`all`/`remove`/`__init__`) | `biochemeleon/registry.py`, `tests/test_registry.py` | none (uses `setup_state.GAME_REPS`) — WSL unit tests |
| 03-02 | `registry.py`: `by_rep`/`counts_by_rep`/`mark_found`/summary | `tests/test_registry.py` | 03-01 — WSL unit tests |
| 03-03 | `registry.py`: `reconstruct_from_sentinels(iterate_fn)` + `to_dict`/`from_dict` (Phase 8 shape) + edge cases (dup id, bad rep) | `tests/test_registry.py` | 03-01, 03-02 — WSL unit tests |
| 03-04 | `backup.py`: `snapshot(target)` + `discard(backup)` + `BACKUP_PREFIX` | `biochemeleon/backup.py` | none — syntax check + smoke stub |
| 03-05 | `backup.py`: `restore(target, backup)` via `delete`+`create` (try/except → bool) | `biochemeleon/backup.py` | 03-04 — syntax + smoke stub |
| 03-06 | `backup.py`: `verify_intact(target, backup)` (count + tuple-multiset via iterate) | `biochemeleon/backup.py` | 03-04 — syntax + smoke stub |
| 03-07 | `mutation.py`: `insert_hider(object, pos, rep, handle)` = pseudoatom + alter sentinel + sort + identify→id | `biochemeleon/mutation.py` | soft dep on registry API (known from research) — syntax + smoke stub |
| 03-08 | `mutation.py`: `fetch_all_hider_ids(object)` (iterate `(model,id)`) + `cleanup_hiders(object)` (`remove` sentinel) | `biochemeleon/mutation.py` | 03-07 — syntax + smoke stub |

**Wave 2 — Orchestrator (sequential; depends on Wave 1)**

| # | Objective | Files | Deps |
|---|-----------|-------|------|
| 03-09 | `game.py`: `GameController.__init__(target_obj)` + `start()` = `snapshot` + `registry.reset` + (placeholder) | `biochemeleon/game.py` | 03-03, 03-04, 03-07 — syntax check |
| 03-10 | `game.py`: `cleanup()` = `cleanup_hiders` + `verify_intact` + `discard`; `abort_on_error()` = `restore`+`discard` wrapper | `biochemeleon/game.py` | 03-05, 03-06, 03-08, 03-09 — syntax check |

**Wave 3 — Verification (sequential after Wave 2; spikes parallel with each other)**

| # | Objective | Files | Deps |
|---|-----------|-------|------|
| 03-11 | Write `smoke/phase3_smoke.py` (full round-trip: criteria 1–4 happy path) | `smoke/phase3_smoke.py` | 03-10 — HUMAN runs in Windows PyMOL |
| 03-12 | Smoke test — failure-path restore section + spikes (Q1 return value, Q2 merge-vs-replace) | `smoke/phase3_smoke.py` (extend) | 03-11 — HUMAN runs |
| 03-13 | Spike — `.pse` round-trip id/sentinel stability (MEDIUM flag) section | `smoke/phase3_smoke.py` (extend) | 03-11 — HUMAN runs |
| 03-14 | Run + triage smoke test; record Q1/Q2/PSE findings into phase SUMMARY | `.planning/.../03-VERIFICATION.md`, `03-SUMMARY.md` | 03-11..03-13 |

**Wave 4 — Hardening & docs (parallel; after verification)**

| # | Objective | Files | Deps |
|---|-----------|-------|------|
| 03-15 | Add Phase 3 grep gates + AGENTS.md domain rules (e.g. "restore = delete+create, never single create"; "hider id via identify, never return value of pseudoatom") | `AGENTS.md`, CI/rgate | 03-14 |
| 03-16 | Update `STATE.md` (Phase 3 complete) + `PITFALLS.md` (resolved MEDIUM flags) | `.planning/STATE.md`, `.planning/research/PITFALLS.md` | 03-14 |
| 03-17 | Write `03-SUMMARY.md` (what shipped, smoke-test results, residual risks for Phase 4) | `.planning/.../03-SUMMARY.md` | 03-14, 03-16 |

(If the planner wants even more atomicity, split 03-03 into "reconstruct" and "serialize" and split 03-11/12/13 into one-plan-per-criterion — reaching ~22 plans. The seams above are the natural ones; sub-splitting within a file is fine but yields more sequential small plans.)

### Parallelization dependency graph
```
Wave 1 (parallel):  [03-01→02→03 registry.py]   [03-04→05→06 backup.py]   [03-07→08 mutation.py]
                         \              |              /          \         /
                          \             |             /            \       /
Wave 2 (seq):               03-09 → 03-10  (game.py orchestrator)
                                |
Wave 3 (seq + parallel spikes):  03-11 → 03-12 → 03-13 → 03-14      (03-12/13 are independent spikes, can swap order)
                                |
Wave 4 (parallel):          03-15   03-16   03-17
```
- Wave 1's three module tracks are **file-disjoint** → truly parallel (no merge conflicts). `mutation.py` has a *soft* contract dep on `registry.py`'s `register` signature, but that signature is fixed by this research, so the two can be developed concurrently.
- Wave 2 is sequential (single file `game.py`) and blocked on Wave 1.
- Wave 3's smoke sections are additive to one script → sequential-ish but each is a small checkpoint; the spikes (03-12, 03-13) are independent investigations.
- Wave 4 is parallel (different docs).

**Flag for the planner:** if even MORE parallelism is wanted, `backup.py` and `mutation.py` could each be split into two files (`backup.py` + `backup_verify.py`; `mutation_insert.py` + `mutation_cleanup.py`), but that over-fragments a small surface — not recommended unless the planner sees real bandwidth. The 3-module split is the sweet spot.

## Open Risks

1. **`cmd.pseudoatom` return value (Q1) — UNVERIFIED.** May be the new atom's id in some builds. The smoke test prints it. Mitigation: code NEVER relies on it (uses `identify` after insert) → safe regardless of outcome.
2. **`cmd.create` merge-vs-replace (Q2, MEDIUM) — UNVERIFIED.** Mitigation: restore uses `delete`+`create` (unambiguous). The smoke-test spike records the single-call behavior for documentation; if it turns out to be clean replace, a future refactor could drop the `delete`, but no need in Phase 3.
3. **`cmd.create` id-preservation (Q2) — UNVERIFIED.** Affects whether the registry survives a restore without rebuild. Mitigation: restore is the abort path (registry rebuilt on next Start anyway); the happy path (cleanup via `remove`) preserves ids (HIGH confidence per index/id contrast). Smoke test confirms.
4. **`.pse` round-trip id stability (MEDIUM) — UNVERIFIED.** If ids shift on reload, the in-memory registry can't be matched back by id. Mitigation: `reconstruct_from_sentinels` rebuilds the id list from the sentinel (HIGH confidence the sentinel survives — it's just atom properties); `rep` is lost on reload and recovered via the Phase 8 `.bcm` sidecar. Smoke test confirms which case holds.
5. **`public_objects` hides `_bchm_backup` — MEDIUM (well-established but C-side).** If underscore-prefix did NOT hide from `public_objects`, the "object list unchanged" assertion (criterion 1) would need to subtract the backup name explicitly. Mitigation: the smoke test asserts both `not in public_objects` AND `in objects`; if the first fails, the assertion code in `game.py`/smoke filters explicitly. Low risk.
6. **`rep` is NOT recoverable from sentinels alone after `.pse` reload.** The sentinel only carries `segi='GAME'`+`b=-999`; `rep` is game metadata. Phase 3's `reconstruct_from_sentinels` sets `rep=None`. Phase 8 sidecar reconciles. Flag for Phase 4/8 planners: do NOT assume `rep` survives reload without the sidecar.
7. **`cmd.sort` after alter — defensive but may reassign `index`.** Safe for the id-keyed registry. If a later phase caches `index` anywhere, that cache would break — but Phase 3 doesn't. Document in AGENTS.md.
8. **Exact-float equality in `verify_intact`.** Assumes `create` copies coords bit-for-bit. If PyMOL applies any rounding on create, the tuple-multiset compare could falsely fail. Smoke test will surface this; fallback is to compare `(resn, resi, name, chain, segi)` only + count, and treat coords as separately verified. Low risk.

## Common Pitfalls (Phase 3-scoped; builds on `.planning/research/PITFALLS.md` HIGH-confidence set — NOT re-verified)

### Pitfall: relying on `cmd.pseudoatom` return as the atom id
**What goes wrong:** code does `new_id = cmd.pseudoatom(...)` and keys the registry on it; if the return is a status code (not an id), the registry is corrupted.
**Why:** the return dispatches to C (`_cmd.pseudoatom`, creating.py:1126) and is documented only via the error gate.
**How to avoid:** ALWAYS fetch the id via `cmd.identify("obj and name <handle> and segi GAME", mode=0)` after insertion; assert exactly one id.
**Warning signs:** registry ids don't match `cmd.identify` output; counts drift.

### Pitfall: restore via single-call `cmd.create(existing, backup)` (merge ambiguity)
**What goes wrong:** if `create` appends instead of replaces, the target doubles in size; "structure match" fails.
**Why:** merge-vs-replace is C-side (creating.py:1024) and UNVERIFIED.
**How to avoid:** `cmd.delete(target); cmd.create(target, backup)` — unambiguous.
**Warning signs:** count after restore = 2× original.

### Pitfall: keying the registry by `index` instead of `id`
**What goes wrong:** after insert/remove, indices shift → registry points at wrong atoms.
**Why:** `cmd.index()` docstring (querying.py:1315) explicitly says indices are fragile across add/delete.
**How to avoid:** key on `id` (via `identify(mode=0)` or `iterate("...id...")`); never `cmd.index()`.
**Warning signs:** registry works at Start, breaks after first cleanup/insert.

### Pitfall: polluting the global `stored` namespace in iterate/alter
**What goes wrong:** `space=None` uses `pymol.__dict__`; concurrent games or tests cross-contaminate.
**Why:** `_iterate_prepare_args` (editing.py:59-60) defaults to the global dict.
**How to avoid:** ALWAYS pass `space={'stored': []}` (or `space={}` for pure alter).
**Warning signs:** flaky test failures; stale values across runs.

### Pitfall: forgetting `cmd.sort` after altering `segi`/`chain`
**What goes wrong:** canonical atom order is stale → later `create`/`byres` operations confound.
**Why:** alter docstring warning (editing.py:1457-1460).
**How to avoid:** `cmd.sort(obj)` after the sentinel alter. (Optional for Phase 3 happy path; mandatory if any create-on-mutated-object follows.)
**Warning signs:** `byres`/`create` selects wrong atoms after mutation.

### Pitfall: backup object visible to the user
**What goes wrong:** `_bchm_backup` shows in the user's object panel → confusing; "object list unchanged" assertion fails.
**Why:** depends on underscore-prefix privacy (C-side, MEDIUM).
**How to avoid:** name starts with `_` (private); smoke-test `not in public_objects`. If it leaks, filter explicitly in the assertion.
**Warning signs:** `get_names("public_objects")` contains `_bchm_backup`.

## Code Examples (verified patterns from source)

### Insert a hider and fetch its id (creating.py:1082 + querying.py:1269 + editor.py:354)
```python
from pymol import cmd
cmd.pseudoatom(object="1ubq", pos=[10.0, 10.0, 10.0], name="H001",
               segi='GAME', b=-999.0, hetatm=1, elem='PS',
               resn='HIDER', chain='H', resi='9001')            # creating.py:1082
cmd.alter("1ubq and name H001", "segi='GAME'; b=-999.0", space={})  # editing.py:1424; editor.py:354
cmd.sort("1ubq")                                                # editing.py:1457
ids = cmd.identify("1ubq and name H001 and segi GAME", mode=0)  # querying.py:1269 -> [id]
assert len(ids) == 1
```

### Snapshot + restore (creating.py:960, commanding.py:496)
```python
cmd.create("_bchm_backup", "1ubq")          # snapshot (fresh copy)
# ... mutate 1ubq ...
cmd.delete("1ubq")                          # commanding.py:496 — remove mutated
cmd.create("1ubq", "_bchm_backup")          # restore (fresh copy from backup)
cmd.delete("_bchm_backup")                 # discard
```

### Iterate ids + atomic tuples (editing.py:1490, editor.py:156)
```python
ids = []
cmd.iterate("1ubq and segi GAME", "stored.append(id)", space={'stored': ids})
tuples = []
cmd.iterate("1ubq", "stored.append((resn, resi, name, chain, segi, x, y, z))",
            space={'stored': tuples})
```

### Sentinel cleanup (editing.py:800)
```python
cmd.remove("1ubq and segi GAME")   # removes only hiders, leaves originals
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `undocontext` for safe mutation | NO undo in open-source (no-op stub) | PyMOL open-source (editor.py:25-36) | Manual `cmd.create` snapshot + `delete`+`create` restore is mandatory |
| `iterate` via global `stored` module | `iterate(..., space={...})` injection | PyMOL 2.x | Hygienic, testable, no global pollution |
| (new in 2.5) `iterate(sele, lambda atom: ...)` callback | callback form | PyMOL 2.5 (editing.py:1512-1515) | Cleaner for simple reads; but `space=` form is needed for multi-value collects — use `space=` in Phase 3 for consistency |
| Track atoms by `resi`/`chain` | Track by integral `id` | long-standing (querying.py:1315) | `id` stable across add/delete; `resi`/`chain`/`index` are not |

**Deprecated/outdated for this phase:**
- `undocontext` — no-op in open-source; do not use.
- `cmd.index()` for tracking — fragile; use `cmd.identify(mode=0)` or `iterate`'s `id`.
- Single-call `cmd.create(existing, other)` for restore — merge semantics UNVERIFIED; use `delete`+`create`.

## Open Questions

1. **`cmd.pseudoatom` return value semantics** — id or status? Resolved by smoke-test spike (Q1); code is safe either way (never relies on return).
2. **`cmd.create` id-preservation across copy** — does the restored object keep the backup's ids? Resolved by smoke test (Q2); affects only the abort path (registry rebuilt on next Start anyway).
3. **`.pse` reload id stability (MEDIUM)** — resolved by smoke-test spike; `reconstruct_from_sentinels` handles the "ids shift but sentinel survives" case.
4. **`rep` recovery after `.pse` reload** — NOT solved in Phase 3 (sentinel carries no rep). Deferred to Phase 8 `.bcm` sidecar. Phase 4/8 planners must not assume `rep` survives reload.
5. **Multi-target-object games** — Phase 3 assumes one target object; `(object, id)` key is future-safe but the backup name (`_bchm_backup`) is single. If Phase 9 supports parallel games on multiple objects, backup naming needs per-target suffixes. Out of scope for Phase 3.

## Sources

### Primary (HIGH confidence — bundled PyMOL 2.5.0 open-source source, read directly)
- `./tmp/pymol-src/modules/pymol/creating.py:960-1036` — `cmd.create` signature, body, dispatch to `_cmd.create`
- `./tmp/pymol-src/modules/pymol/creating.py:1082-1134` — `cmd.pseudoatom` full signature, defaults, body, `return r`
- `./tmp/pymol-src/modules/pymol/creating.py:1136-1199` — `join_states` (create append-state idiom, line 1180)
- `./tmp/pymol-src/modules/pymol/editing.py:47-62` — `_iterate_prepare_args` (space= semantics, callback form)
- `./tmp/pymol-src/modules/pymol/editing.py:800-834` — `cmd.remove`
- `./tmp/pymol-src/modules/pymol/editing.py:937-987` — `cmd.fuse` (modes 1/2/3, mode=3 combine-no-bond)
- `./tmp/pymol-src/modules/pymol/editing.py:1424-1473` — `cmd.alter` (symbol table, sort warning, space=)
- `./tmp/pymol-src/modules/pymol/editing.py:1490-1533` — `cmd.iterate` (callback form, space=)
- `./tmp/pymol-src/modules/pymol/querying.py:1148-1192` — `cmd.get_names` (mode map; public_objects=4)
- `./tmp/pymol-src/modules/pymol/querying.py:1235-1267` — `cmd.id_atom` (single-atom id)
- `./tmp/pymol-src/modules/pymol/querying.py:1269-1300` — `cmd.identify` (mode 0 = id list, mode 1 = (obj,id))
- `./tmp/pymol-src/modules/pymol/querying.py:1302-1330` — `cmd.index` (fragile-index warning, line 1315)
- `./tmp/pymol-src/modules/pymol/querying.py:1412-1434` — `cmd.count_atoms`
- `./tmp/pymol-src/modules/pymol/commanding.py:496-530` — `cmd.delete` (wildcards)
- `./tmp/pymol-src/modules/pymol/editor.py:25-36` — `undocontext` NO-OP stub (confirms no undo)
- `./tmp/pymol-src/modules/pymol/editor.py:156, 158, 354, 355` — canonical `space=` + multi-`;` alter + `create(union)` merge idioms
- `./tmp/pymol-src/modules/pymol/selector.py:1-7` — `process` (tuple→backtick form)

### Secondary (MEDIUM — established PyMOL behavior, C-side, flagged for smoke test)
- underscore-prefix object privacy (public_objects filter) — C-side, smoke-tested
- `create` deep-copy independence — standard semantics, body-confirmed

### Tertiary (LOW / UNVERIFIED — to resolve via smoke test)
- `cmd.pseudoatom` return value (id vs status) — C-dispatched
- `cmd.create(existing, backup)` merge-vs-replace — C-dispatched
- `cmd.create` id-preservation — C-dispatched
- `.pse` round-trip id/sentinel stability — C-dispatched

## Metadata

**Confidence breakdown:**
- API signatures & defaults: HIGH — read directly from bundled source
- `id` vs `index` stability: HIGH — `cmd.index` docstring explicitly contrasts them
- No-undo: HIGH — `undocontext` is a no-op stub in source
- alter multi-`;` + space= patterns: HIGH — canonical idioms in editor.py
- `create` snapshot = deep copy: HIGH (MEDIUM on id-preservation)
- merge-vs-replace, pseudoatom return, .pse stability: UNVERIFIED — smoke-test spikes resolve
- Registry/backup design (recommendations): HIGH — grounded in verified API behavior

**Research date:** 2026-08-05
**Valid until:** 2026-09-04 (stable — PyMOL 2.5.0 is a fixed target; no upstream drift expected)
