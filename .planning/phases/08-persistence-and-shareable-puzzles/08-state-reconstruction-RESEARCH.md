# Phase 8: Persistence & Shareable Puzzles — State Serialization + Reconstruction + Reconciliation (Dimension Research)

**Researched:** 2026-08-12
**Domain:** PyMOL 2.5.0 plugin — mid-game checkpoint serialization + post-`.pse`-reload registry reconstruction + `.bcm` sidecar reconciliation + GUI re-attachment
**Confidence:** HIGH (stack is established Phases 3-7; reconstruction primitives runtime-verified 2026-08-06; PyMOL `.pse` color-preservation verified in source `exporting.py`/`importing.py`)
**Scope:** This document owns ONE Phase 8 dimension: **WHAT state to serialize + HOW to reconstruct + reconcile it + GUI re-attachment**. It does NOT cover the `.bcm` file-format concerns (zip-vs-pair, magic number) or the export/import button-placement/workflow flow — those are sibling researchers.

---

## 1. Executive Summary

After `cmd.load(.pse)`, the sentinel atoms (`segi='GAME'` + `b=-999`) survive with their stable `id`s but the in-memory `HiderRegistry` is gone and the sentinel carries no `rep`. The reconstruction is a two-stage merge: **(1) `reconstruct_from_sentinels`** rebuilds the registry keyed by `(object, id)` with `rep=None` + `status='hidden'` for every sentinel atom (source of truth = the loaded `.pse`); **(2) `reconcile_with_bcm(bcm_hiders_list)`** mutates each rebuilt record in place, setting `rep` + `status` from the matching `.bcm` entry by `(object, id)` and flagging mismatches (source of truth = the sidecar metadata). Sentinel-first is correct because the `.pse` is the *loaded reality* — the atoms the player can actually click — and the `.bcm` is metadata describing those atoms. A `.bcm`-only hider pointing at a non-existent atom is a ghost that breaks `counts_by_rep` and `on_pick`; a sentinel-only hider (missing from `.bcm`) is a real atom the player can still find, so it stays registered with `rep=None` + `status='hidden'` and a warning is logged.

**Primary recommendation:** Implement `HiderRegistry.reconcile_with_bcm(bcm_hiders_list)` as a pure method on `registry.py` (takes a list of dicts, mutates records in place, returns a `ReconcileMismatches` namedtuple of `missing_from_bcm` + `missing_from_pse` + `bad_rep` lists — no `from pymol` import). Assemble/disassemble the full `.bcm` dict in a new `biochemeleon/persistence.py` module via two pure-assembly functions `build_bcm_dict(controller, setup_state, state_kind, elapsed=None)` and `apply_bcm_dict(controller, bcm_dict)` — `persistence.py` imports `registry` + `setup_state` only (NO `pymol`), keeping the pure-layer discipline. The GUI re-attachment extends `start_countdown(self, controller, elapsed=0)` so a checkpoint resume sets `_start_time = time.time() - elapsed` and the reveal label is seeded from `controller._reveal_count` before the countdown begins. The `_backup_name` for a reloaded game is snapshotted AFTER reconcile + (defensive) found-color re-application, so Cleanup restores the imported state (hiders in, found hiders green for a checkpoint; hiders in, none found for a puzzle).

**Per-atom `color` DOES round-trip through `.pse`** (verified: `exporting.py:424` calls `_cmd.get_session` which captures the full C-level `ObjectMolecule` state including the per-atom color property; `importing.py:130-175` `set_session` restores it; the Phase 3 smoke already confirmed `segi` + `b` + `id` survive the same round-trip path). So a found hider that was `cmd.color('green')`'d before Save will be green after Load — the registry reconcile's `status='found'` is what makes `on_pick`/`counts_by_rep`/found-mgmt behave, NOT a re-color. Re-coloring after reconcile is **redundant but defensive** — recommend doing it idempotently (cheap, defends against a future `.pse` format change that drops color).

---

## 2. Reconstruction Strategy — Sentinel-First vs .bcm-First

### 2.1 The two strategies

**Strategy A (sentinel-first — RECOMMENDED):**
```
cmd.load(.pse)
registry = HiderRegistry().reconstruct_from_sentinels(
    lambda: mutation.fetch_all_hider_ids(target_obj))   # source of truth = .pse atoms
mismatches = registry.reconcile_with_bcm(bcm_dict['registry']['hiders'])  # merge .bcm metadata
```
The `.pse` is the source of truth for *which atoms are hiders*. The `.bcm` is matched to those atoms by `(object, id)` and supplies the per-hider metadata (`rep`, `status`, `pos`) that the sentinel cannot carry.

**Strategy B (.bcm-first):**
```
cmd.load(.pse)
registry = HiderRegistry.from_dict(bcm_dict['registry'])   # source of truth = .bcm
# optionally: verify each .bcm hider exists as a sentinel in the .pse
```
The `.bcm` is the source of truth for the registry; the `.pse` is checked for consistency after.

### 2.2 Analysis — argue from correctness + robustness

| Criterion | Sentinel-first (A) | .bcm-first (B) |
|---|---|---|
| Source of truth = the atoms the player can click | YES — the `.pse` IS what's loaded; sentinel atoms are the real, clickable hiders | NO — a `.bcm`-only hider has no atom; `on_pick` can never fire for it but `counts_by_rep` counts it (ghost entry) |
| Missing `.bcm` hider (sentinel exists, `.bcm` doesn't) | Stays registered `rep=None`+`hidden`; player can still find it; warn | Not in registry; silently invisible to the game (atom exists but no count) |
| Missing `.pse` hider (`.bcm` lists it, `.pse` doesn't) | Not in registry (no atom to register); warn | Ghost entry in registry; counts wrong; `on_pick` for a real atom may collide |
| Corrupt/missing sidecar degradation | Registry still rebuilds from sentinels (degraded: all `rep=None`, all `hidden` — but the game is *playable*, just without per-rep counts or found-status) | Without `.bcm`, no registry at all (must fall back to sentinel rebuild anyway — so B always carries A as a fallback) |
| Code reuse | Uses `reconstruct_from_sentinels` (already exists, runtime-verified) + a new pure merge | Uses `from_dict` (exists) + a new verify-each-exists check |
| `rep=None` after reconcile for unmatched sentinels | Yes — documented limitation, flagged as mismatch | No — `.bcm` always has `rep` (or it's a corrupt-file edge case) |

**The decisive argument:** the `.pse` is the *loaded reality* — the atoms the player's click will hit. If the `.bcm` and `.pse` disagree, the `.pse` MUST win because that's what's on screen. Strategy B's ghost entries (`.bcm` lists a hider the `.pse` doesn't have) are *unrecoverable* — `on_pick` can never fire for a non-existent atom, but `counts_by_rep` would count it, the found-mgmt dropdown would build a selection `obj and id X` that matches nothing, and the win condition (`_remaining() == 0`) would be unreachable. Strategy A's "extra sentinel, missing from `.bcm`" case is benign — the atom is real, the player can still click it, it just has `rep=None` (so per-rep counts under-count it) and `status='hidden'` (so it counts toward `_remaining()`).

**Strategy B's fallback IS Strategy A.** When the `.bcm` is missing or fails to parse, B has no registry and must call `reconstruct_from_sentinels` — i.e., fall back to A. So B is strictly more code for a strictly weaker guarantee. Choose A.

**Robustness against sidecar loss:** A degrades gracefully (sentinel rebuild → playable game, no per-rep counts, no found-status). B degrades to "no game" unless it carries A as a fallback. Graceful degradation matters for the "player emails a `.pse` and forgets the `.bcm`" case.

### 2.3 Recommendation

**Use Strategy A (sentinel-first + `.bcm` reconcile).** It is correct (the `.pse` is loaded reality), robust (degrades to a playable game on sidecar loss), and reuses the runtime-verified `reconstruct_from_sentinels` primitive (`registry.py:249-272`, Phase 3 smoke confirmed sentinel-survives + id-stable + b=-999.0-preserved). The cost is one extra merge step (`reconcile_with_bcm`), which is a pure ~25-line dict-merge — cheap.

**Fallback ladder (implement all three):**
1. `.bcm` present + parses + version matches → full reconcile (rep + status + counts restored).
2. `.bcm` present but fails to parse / version mismatch / `kind` wrong → log warning, sentinel-only rebuild (degraded: `rep=None`, `status='hidden'` for all; game playable, per-rep counts zero, found-mgmt show-by-rep empty — see §10).
3. `.bcm` absent → same as (2); the user is told "no sidecar found; loaded atoms only, no game metadata".

---

## 3. The Reconcile Method — `HiderRegistry.reconcile_with_bcm`

### 3.1 Where it lives (the purity question)

**Live in `registry.py` as a `HiderRegistry` method.** The merge reads a list of dicts and mutates `HiderRecord` fields in place — no `from pymol import cmd`, no PyMOL call. It satisfies the same purity contract as `from_dict` (`registry.py:227-245`) and `reconstruct_from_sentinels` (`registry.py:249-272`): stdlib + `setup_state.GAME_REPS` only. Keeping the merge in `registry.py` (vs. a free function in `persistence.py`) is correct because it mutates `self._records` and validates `rep in GAME_REPS` — that's the registry's own invariant.

### 3.2 Signature + pseudo-code

```python
# In biochemeleon/registry.py (extend HiderRegistry)

from collections import namedtuple

# Returned by reconcile_with_bcm — caller (game.py / persistence.py) logs warnings
# but the registry stays usable. Empty lists = perfect match.
ReconcileMismatches = namedtuple(
    'ReconcileMismatches',
    ['missing_from_bcm',   # [(object, id)] sentinel atoms NOT in .bcm — stay rep=None, hidden
     'missing_from_pse',   # [(object, id)] .bcm hiders NOT in sentinels — ghost entries; not registered
     'bad_rep'])           # [(object, id, bad_rep)] .bcm hiders with rep not in GAME_REPS — skipped

class HiderRegistry(object):
    # ... existing methods ...

    def reconcile_with_bcm(self, bcm_hiders):
        """Reconcile sentinel-rebuilt records with .bcm sidecar metadata.

        Precondition: ``self`` was rebuilt via :meth:`reconstruct_from_sentinels`
        (records keyed by ``(object, id)``, ``rep=None``, ``status='hidden'``).
        For each ``.bcm`` hider dict, find the matching rebuilt record by
        ``(object, id)`` and set ``rep`` + ``status`` (and ``pos`` if present).
        Returns a :data:`ReconcileMismatches` naming three classes of
        disagreement; the caller decides whether to log them as warnings
        or refuse the load.

        Pure (no ``from pymol``). Takes a list of dicts (the
        ``.bcm['registry']['hiders']`` list) — no PyMOL call. Mutates
        ``self._records`` in place.

        Mismatch handling:
          - sentinel record NOT in .bcm (``missing_from_bcm``): left as
            ``rep=None`` + ``status='hidden'`` (the atom is real and
            clickable; player can still find it; per-rep counts under-count).
          - .bcm hider NOT in sentinels (``missing_from_pse``): NOT
            registered (no atom to register — a ghost entry pointing at
            a non-existent atom would corrupt ``counts_by_rep`` and
            ``on_pick``). Flagged for the caller to warn.
          - .bcm hider with ``rep`` not in :data:`GAME_REPS` (``bad_rep``):
            the record's ``rep`` is left ``None`` (do NOT raise — a
            corrupt sidecar should not kill the load). Flagged.

        Args:
            bcm_hiders (list[dict]): the ``.bcm['registry']['hiders']``
                list — each dict has ``id``, ``object``, ``rep``, ``status``
                (pos optional). Survives JSON round-trip.

        Returns:
            ReconcileMismatches: namedtuple of three mismatch lists
            (empty when the .bcm perfectly matches the sentinels).
        """
        missing_from_bcm = []
        missing_from_pse = []
        bad_rep = []
        # Index .bcm hiders by (object, int(id)) for O(N) lookup
        bcm_index = {}
        for h in bcm_hiders or []:
            try:
                key = (h['object'], int(h['id']))
            except (KeyError, TypeError, ValueError):
                continue  # malformed .bcm entry — skip
            bcm_index[key] = h
        # Walk the SENTINEL-rebuilt records (source of truth = loaded atoms)
        for key, rec in self._records.items():
            h = bcm_index.get(key)
            if h is None:
                # Sentinel atom the .bcm doesn't list — keep rep=None, hidden
                missing_from_bcm.append(key)
                continue
            # Validate rep
            bcm_rep = h.get('rep')
            if bcm_rep is not None and bcm_rep not in GAME_REPS:
                bad_rep.append((key[0], key[1], bcm_rep))
                # leave rec.rep = None (do NOT raise)
            else:
                rec.rep = bcm_rep   # may be None (vestigial; see §10.5)
            # Validate + apply status
            bcm_status = h.get('status', HIDER_STATUS_HIDDEN)
            if bcm_status not in (HIDER_STATUS_HIDDEN, HIDER_STATUS_FOUND):
                bcm_status = HIDER_STATUS_HIDDEN   # corrupt -> safe default
            rec.status = bcm_status
            # pos (vestigial — see §10.5; restore for completeness, not used at runtime)
            if 'pos' in h and h['pos'] is not None:
                rec.pos = list(h['pos'])
        # Find .bcm hiders NOT in sentinels (ghosts)
        for key, h in bcm_index.items():
            if key not in self._records:
                missing_from_pse.append(key)
        return ReconcileMismatches(
            missing_from_bcm=missing_from_bcm,
            missing_from_pse=missing_from_pse,
            bad_rep=bad_rep)
```

### 3.3 Why this shape (and not the alternatives)

- **Mutates `self._records` in place (not a classmethod returning a new registry):** the registry was already built by `reconstruct_from_sentinels` (a method on `self`); the merge is the second half of the same reconstruction. A classmethod would force a third copy of the records. In-place mutation matches `reconstruct_from_sentinels`'s own contract (`registry.py:268-272` clears + rebuilds `self._records`).
- **Returns a `namedtuple` (not raises):** a corrupt sidecar should NOT kill the load — the sentinel-rebuilt registry is already playable (degraded). The caller (the import handler in `__init__.py` or `persistence.py`) decides whether to log a warning, refuse, or proceed. This separation keeps `registry.py` policy-free.
- **Validates `rep in GAME_REPS` + `status in (hidden, found)`:** defends against a corrupt or future-version `.bcm`. Invalid values fall back to safe defaults (`rep=None`, `status='hidden'`) and are flagged — the load continues.
- **Does NOT register `missing_from_pse` ghosts:** registering a hider with no atom would make `counts_by_rep` count it (inflating totals), `build_found_selection` build a no-op selection, and the win condition unreachable (the atom can never be clicked). The caller logs the mismatch; the player is told "N hiders listed in the sidecar were not found in the session".
- **`pos` is restored but vestigial:** see §10.5 — no runtime code reads `rec.pos`. Restoring it keeps the `.bcm` round-trip lossless; skipping the restore would also be correct.

---

## 4. Found-Status Re-Application in the Viewer

### 4.1 Does `.pse` preserve per-atom custom colors? — VERIFIED YES

**Source evidence (HIGH confidence):**

- `pymol/exporting.py:782-933` — `cmd.save(filename, ...)` for `.pse` format routes to `get_session()` (`exporting.py:370-475`), which at line 423-425 calls:
  ```python
  with _self.lockcm:
      _cmd.get_session(_self._COb, session, str(names), int(partial),
                       int(quiet), binary, pse_export_version)
  ```
  `_cmd.get_session` is the C-level routine that serializes the **complete** `ObjectMolecule` state — every atom's `(resn, resi, name, chain, segi, elem, b, q, color, repVis, ...)` properties, plus all object/state settings, views, scenes, movie, wizard. The docstring at `exporting.py:784-824` says ".pse ... the complete PyMOL state is always saved to the file".
- `pymol/importing.py:823-848` — `load_pse` reads the pickle, calls `set_session` (`importing.py:130-175`), which at line 142-143 calls `_cmd.set_session(_self._COb, session, ...)` — the C-level restore of the same complete state.
- The atom-level state serialized includes the `color` property (atom index 10 in the per-atom tuple — `pymol/constants.py:255` `color = 10`; the conversion code at `exporting.py:346-348` walks `name[5][7]` (the atom list) and converts `atom[20]` (visRep bitmask) — color is a sibling per-atom field in the same struct).
- **Phase 3 smoke (2026-08-06) already confirmed** `segi='GAME'` + `b=-999.0` + atom `id` survive the same `_cmd.get_session` → pickle → `_cmd.set_session` round-trip path (`.planning/research/PITFALLS.md` "PSE — `.pse` round-trip id/sentinel stability: RESOLVED"). Color is part of the same `ObjectMolecule` atom struct — it round-trips by the same mechanism.

**Conclusion:** A found hider that was `cmd.color(self._found_color, "obj and id X")`'d before Save will display in `self._found_color` after Load. The `.pse` already shows the correct viewer state.

### 4.2 Is re-coloring after reconcile needed? — REDUNDANT but RECOMMENDED defensive

**Recommendation: DO re-apply found-color idempotently after reconcile, but treat it as defensive.**

Reasoning:
1. **The viewer is already correct** (the `.pse` preserved the green color). So `cmd.color` is redundant in the happy path.
2. **The registry must still be reconciled** (`status='found'`) regardless of viewer color, because `on_pick` reads `rec.status`, `_remaining()` reads `rec.status`, `counts_by_rep` reads `rec.rep`, and the found-mgmt dropdown reads `rec.status` + `rec.rep` (`gui_game.py:133-150` filters by `HIDER_STATUS_FOUND`, then `group_found_by_rep` skips `rep=None`). Without reconcile, a reloaded game's counts are all 0 and found-mgmt show-by-rep is broken — see §8.
3. **Defensive re-color is cheap and idempotent:** `cmd.color('green', "obj and id X")` on an atom that's already green is a no-op at the C level (the color index matches; no scene re-render triggered beyond a dirty flag). For N found hiders it's N cheap calls.
4. **Future-proofing:** if a future PyMOL version drops per-atom color from `.pse` (unlikely, but the Schrödinger build's `.pse` format may diverge), the registry still matches the viewer. Defense-in-depth.
5. **Re-color must come BEFORE the backup snapshot** (§6) so the backup has the correct colors — Cleanup restores from the backup.

**Pseudo-code (lives in the import handler, NOT in `registry.py`):**
```python
# After reconcile — re-apply found color idempotently (defensive)
from pymol import cmd
for rec in controller.registry.all():
    if rec.status == registry.HIDER_STATUS_FOUND:
        cmd.color(controller._found_color,
                  "%s and id %d" % (controller.target_obj, rec.id))
```

**Anti-pattern — trust the `.pse` and skip re-color:** works today, but couples the registry's correctness to the `.pse` color format. If a user loaded a `.pse` made by a newer/older PyMOL where colors didn't round-trip, the viewer would show found hiders in their pre-found color while the registry says found — the player sees a "found" hider that doesn't look found. The re-color is one loop; do it.

### 4.3 The found-mgmt dropdown dependency on `rep` — confirmed

The Phase 7 found-mgmt dropdown's "Show found" mode calls `group_found_by_rep(found)` (`gui_game.py:144`), which at `registry.py:299-313` SKIPS `rep=None` records:
```python
def group_found_by_rep(records):
    out = {}
    for r in records:
        if r.status == HIDER_STATUS_FOUND and r.rep is not None:
            out.setdefault(r.rep, []).append(r.id)
    return out
```
So if reconcile is NOT done (or only partially done), a reloaded game's "Show found" shows nothing (the `rep=None` records are skipped), even though found hiders exist. This makes rep reconciliation **MANDATORY** (not optional) for a playable reloaded game — see §10.6.

---

## 5. Timer Resume vs Fresh

### 5.1 The UX rule

- **Checkpoint (Save-mid-game, `state="checkpoint"`):** timer RESUMES from the saved `elapsed`. The player saved to take a break; on import the timer continues counting up. `_start_time = time.time() - elapsed` makes the running `time.time() - _start_time` produce `elapsed + (now - import_time)` — i.e., the saved elapsed plus new play time.
- **Puzzle (Generate&export, `state="puzzle"`):** timer STARTS at 0 (fresh play). The educator exported an initial state with no found hiders; the player's timer is their own solve time.

### 5.2 The signature change

`gui_game.py:188-204` currently:
```python
def start_countdown(self, controller):
    self._controller = controller
    self._reveal_label.setText("Reveals: 0")   # reset for new round (C8)
    self._info_log.clear()  # fresh round = clean log (Phase 7 fix)
    self._log("Get ready...")
    self._countdown_step(3)
```

`gui_game.py:206-224` `_begin_play` currently:
```python
def _begin_play(self):
    from .wizard import PickWizard
    self._wizard = PickWizard(self._controller, self._controller.target_obj)
    self._wizard.activate()
    self._controller._wizard = self._wizard
    self._controller.set_callbacks(
        on_log=self._log,
        on_remaining_changed=self._update_remaining,
        on_win=self._on_win,
        on_counts_changed=self._on_counts_changed,
    )
    self._start_time = time.time()
    self._controller._start_time = self._start_time
    self._timer.stop()
    self._timer.start(1000)
    self._update_remaining(self._controller._remaining())
```

**Proposed change (minimal, backward-compatible):**
```python
def start_countdown(self, controller, elapsed=0):
    """Begin the 3-2-1 countdown. On GO!, _begin_play activates the
    PickWizard, registers callbacks, and starts the timer.

    Args:
        controller (GameController): the active controller (just .start()ed
            for a fresh game, or reconstructed+reconciled for an imported
            checkpoint).
        elapsed (float): saved elapsed seconds to resume from (checkpoint
            import); 0.0 for a fresh game or puzzle import. The timer
            displays ``elapsed + (now - _begin_play_time)`` so a checkpoint
            resumes counting up from the saved time.
    """
    self._controller = controller
    self._saved_elapsed = float(elapsed)   # consumed by _begin_play
    self._reveal_label.setText("Reveals: %d" % (controller._reveal_count,))
    self._info_log.clear()
    self._log("Get ready...")
    # Show the resumed timer during the 3-2-1 countdown (fresh game: 0:00)
    if elapsed > 0:
        mins = int(elapsed) // 60
        secs = int(elapsed) % 60
        self._timer_label.setText("%d:%02d" % (mins, secs))
    self._countdown_step(3)

def _begin_play(self):
    from .wizard import PickWizard
    self._wizard = PickWizard(self._controller, self._controller.target_obj)
    self._wizard.activate()
    self._controller._wizard = self._wizard
    self._controller.set_callbacks(
        on_log=self._log,
        on_remaining_changed=self._update_remaining,
        on_win=self._on_win,
        on_counts_changed=self._on_counts_changed,
    )
    elapsed = getattr(self, '_saved_elapsed', 0.0)
    self._start_time = time.time() - elapsed   # resume from saved elapsed
    self._controller._start_time = self._start_time
    self._timer.stop()
    self._timer.start(1000)
    self._update_remaining(self._controller._remaining())
    # Reset the transient; a subsequent Restart (no elapsed arg) starts fresh
    self._saved_elapsed = 0.0
```

**Notes:**
- `start_countdown(self, controller, elapsed=0)` is backward-compatible — every existing caller (`__init__.py:244` `self.game_tab.start_countdown(self._controller)`) gets `elapsed=0` → fresh game, unchanged behavior.
- `_reveal_label` is seeded from `controller._reveal_count` (NOT hardcoded `"Reveals: 0"`) so a checkpoint import shows the saved reveal count immediately. For a fresh game, `controller._reveal_count == 0` (set in `start()` at `game.py:56`), so the label is `"Reveals: 0"` as before.
- `_saved_elapsed` is a transient attribute on the tab; it's consumed and reset in `_begin_play` so a later Restart (which calls `start_countdown(controller)` with no `elapsed`) starts at 0.
- The `_on_tick` math (`gui_game.py:182-186`) is unchanged — `int(time.time() - self._start_time)` produces `int(elapsed + play_time)`, which displays as the resumed timer.
- `win()`'s elapsed math (`game.py:131` `elapsed = time.time() - self._start_time if self._start_time else 0.0`) correctly reports the resumed-then-continued total because `controller._start_time` was set to `time.time() - elapsed`.

### 5.3 Display during the countdown

During the 3-2-1 countdown (~3 seconds), the timer label stays at its pre-countdown value (set in `start_countdown` above). For a checkpoint resume, the label shows "0:42" while "3, 2, 1, GO!" scrolls in the log. For a fresh game (elapsed=0) the label is already "0:00" from the previous `_on_cleanup` reset (`__init__.py:283`) or the initial `__init__` (`gui_game.py:24`).

---

## 6. The `_backup_name` for a Reloaded Game

### 6.1 The problem

A reloaded game's `GameController` never called `start()` (no snapshot). But `cleanup()` (`game.py:231-262`) calls `backup.restore(self.target_obj, self._backup_name)` + `backup.discard(self._backup_name)` — both need `self._backup_name` to be set (or `cleanup` raises `CmdException` on the `None` backup). The Phase 7 `_on_cleanup` (`__init__.py:265-286`) calls `controller.cleanup()` after the user dismisses the win dialog OR clicks Cleanup. So the imported controller MUST have a backup.

### 6.2 What is the "original" for a reloaded game?

- **Checkpoint (`state="checkpoint"`):** the "original" = the saved state (hiders in, found hiders green, hidden hiders in their blend colors). Cleanup should restore this state — the player imported the checkpoint, played more, then cleaned up; the model returns to the saved state, NOT the pre-game pristine state (that pristine state is gone — the educator didn't save it; only the checkpoint state was saved).
- **Puzzle (`state="puzzle"`):** the "original" = the initial puzzle state (hiders in, none found, all in blend colors). Cleanup restores this.

In both cases, the "original" is **the imported state itself**. So the backup snapshot should be taken AFTER the imported state is fully reconstructed (reconcile + found-color re-apply), so the backup is identical to the imported state.

### 6.3 Order of operations on import

```
1. cmd.load(.pse)                                    # restore atoms + colors
2. controller = GameController(target_obj)
3. controller.registry = HiderRegistry().reconstruct_from_sentinels(
        lambda: mutation.fetch_all_hider_ids(target_obj))
4. mismatches = controller.registry.reconcile_with_bcm(bcm_dict['registry']['hiders'])
5. controller._reveal_count = bcm_dict.get('reveal_count', 0)
6. controller._hint_count = bcm_dict.get('hint_count', 0)
7. controller._found_color = bcm_dict.get('found_color', 'green')
8. controller._started = True                       # the game IS started (hiders are in)
9. # Defensive found-color re-application (§4.2):
   for rec in controller.registry.all():
       if rec.status == registry.HIDER_STATUS_FOUND:
           cmd.color(controller._found_color,
                     "%s and id %d" % (controller.target_obj, rec.id))
10. # Snapshot AFTER reconcile + re-color — this is the "original" for Cleanup:
    controller._backup_name = backup.snapshot(target_obj)
11. # GUI re-attach:
    self.game_tab.start_countdown(controller, elapsed=bcm_dict.get('elapsed', 0.0))
```

**Step 10 is the key:** the snapshot captures the imported state (with found hiders green for a checkpoint). When the player later clicks Cleanup, `backup.restore` (`backup.py:54-64`) does `cmd.delete(target) + cmd.create(target, backup)` — restoring the imported state. The found hiders are green again, the hidden hiders are in their blend colors, the hint-colored real atoms (if any from a saved mid-hint state — but hint colors real neighbors, not hiders, and the `.pse` already has those colors) are restored. This is correct: "Cleanup after importing a checkpoint" = "throw away my post-import play, return to the imported state".

### 6.4 Should the snapshot happen BEFORE or AFTER the found-color re-apply? — AFTER

**After.** The snapshot must capture the found colors so Cleanup restores them. If the snapshot were taken BEFORE the re-apply (i.e., right after `cmd.load(.pse)`), the backup would have whatever colors the `.pse` had — which is also the found colors (per §4.1, the `.pse` preserves them), so in practice the two orderings converge. BUT if the `.pse` color round-trip ever fails (future format change), the after-re-apply snapshot has the correct colors and the before-snapshot doesn't. Defense-in-depth → snapshot AFTER.

### 6.5 Restart-after-import

The Phase 7 Restart (`__init__.py:246-263`) calls `_on_start`, which:
1. Deactivates the wizard + stops the timer.
2. Cleans up the prior controller (`if self._controller._started: self._controller.cleanup()` — uses the backup we just snapshotted).
3. Builds new `hider_specs` from the Setup tab state.
4. Creates a new `GameController`, calls `start()` (snapshots fresh, inserts new hiders).

So Restart-after-import works unchanged: the imported controller's backup is used by `cleanup()` to restore the imported state, then `start()` snapshots the pristine restored object + inserts fresh hiders. **No special-casing needed.**

### 6.6 What about `controller._wizard`?

`controller._wizard` is TRANSIENT (per the context). It's set by `_begin_play` (`gui_game.py:210`) on import, not serialized. The `.bcm` does NOT include it. On import, `_begin_play` creates a fresh `PickWizard(controller, target_obj)` — same as a fresh game. Confirmed: do NOT serialize `_wizard` or any callback (`_on_log`, etc.).

---

## 7. `.bcm` Assembly + Disassembly — `build_bcm_dict` / `apply_bcm_dict`

### 7.1 Where they live

**New module: `biochemeleon/persistence.py`.** Reasons:
- `game.py` is already 277 lines; adding the assembly logic would grow it further and mix the controller's runtime role with its serialization role.
- `registry.py` is the pure data model (just the registry); it shouldn't know about controller-level fields (elapsed, reveal_count, found_color, setup).
- `persistence.py` is the natural home for the top-level `.bcm` dict shape — it imports `registry` (for `registry.to_dict()`) + `setup_state` (for the setup dict shape, already JSON-serializable per `gui_setup.collect_state()` at `gui_setup.py:441-459`). It does NOT import `pymol` — it takes primitives (the controller, the setup dict) and returns/assembles a dict. Pure assembly = WSL-testable.
- The inverse (`apply_bcm_dict`) sets controller fields + calls `registry.reconcile_with_bcm`. It's also pure (no `pymol`) — the cmd-coupled steps (`cmd.load`, `cmd.color`, `backup.snapshot`) live in the import handler in `__init__.py`, not in `persistence.py`.

### 7.2 Signature + pseudo-code

```python
# biochemeleon/persistence.py — NEW module
"""Pure .bcm sidecar assembly + disassembly (Phase 8).

Imports registry + setup_state only (NO pymol, NO Qt) so it stays
WSL-unit-testable. The cmd-coupled steps (cmd.load, cmd.color,
backup.snapshot, reconstruct_from_sentinels) live in the import
handler (__init__.py) — this module just shapes the dict.
"""
import time

from .registry import HiderRegistry, HIDER_STATUS_FOUND, HIDER_STATUS_HIDDEN
from .setup_state import SETUP_FORMAT   # for setup dict version check

BCM_VERSION = 1
BCM_KIND = 'bcm-game'

# Top-level .bcm dict shape (the schema — another researcher owns the
# file-format concerns; this is the state-assembly shape):
#   {
#     "version": 1,
#     "kind": "bcm-game",
#     "state": "checkpoint" | "puzzle",
#     "target_obj": str,
#     "registry": <HiderRegistry.to_dict()>,
#     "elapsed": float,        # seconds; 0.0 for puzzle
#     "reveal_count": int,
#     "hint_count": int,
#     "found_color": str,      # 'green' or 'found_highlight'
#     "setup": <collect_state()>,
#     "saved_at": ISO 8601 str  # optional
#   }


def build_bcm_dict(controller, setup_state, state_kind, elapsed=None):
    """Assemble the full .bcm dict from a controller + setup state.

    Pure (no pymol). Captures the per-hider registry (via
    ``controller.registry.to_dict()``), the controller-level fields
    (elapsed, reveal_count, hint_count, found_color), the target object
    name, and the setup dict (so a Restart-on-imported can re-generate,
    and an exported puzzle shows the educator's configuration).

    Args:
        controller (GameController): the live controller. Reads
            ``target_obj``, ``registry``, ``_reveal_count``,
            ``_hint_count``, ``_found_color``. Does NOT read
            ``_backup_name`` (transient), ``_wizard`` (transient),
            ``_start_time`` (captured via the *elapsed* arg, not the
            raw _start_time), or callbacks (transient).
        setup_state (dict): the ``gui_setup.collect_state()`` dict. For
            a Save-mid-game, the current Setup tab state (so the player
            can see what they configured). For a Generate&export, the
            educator's configuration.
        state_kind (str): ``'checkpoint'`` (Save-mid-game) or
            ``'puzzle'`` (Generate&export).
        elapsed (float or None): for ``state_kind='checkpoint'``, the
            running elapsed ``time.time() - controller._start_time``
            captured at Save click. For ``'puzzle'``, pass 0.0 or None
            (written as 0.0). If None and state_kind='checkpoint', falls
            back to ``time.time() - controller._start_time`` (caller
            should pass it explicitly to avoid the modal-dialog pitfall — §11).

    Returns:
        dict: the full .bcm dict, JSON-serializable.
    """
    if state_kind not in ('checkpoint', 'puzzle'):
        raise ValueError("state_kind must be 'checkpoint' or 'puzzle', got %r"
                         % (state_kind,))
    if elapsed is None:
        if state_kind == 'checkpoint' and controller._start_time:
            elapsed = time.time() - controller._start_time
        else:
            elapsed = 0.0
    return {
        'version': BCM_VERSION,
        'kind': BCM_KIND,
        'state': state_kind,
        'target_obj': controller.target_obj,
        'registry': controller.registry.to_dict(),
        'elapsed': float(elapsed),
        'reveal_count': int(controller._reveal_count),
        'hint_count': int(controller._hint_count),
        'found_color': str(controller._found_color),
        'setup': setup_state,
        'saved_at': time.strftime('%Y-%m-%dT%H:%M:%S'),
    }


def apply_bcm_dict(controller, bcm_dict):
    """Set controller state fields + reconcile the registry from a .bcm dict.

    Pure (no pymol). The cmd-coupled steps (cmd.load of the .pse,
    reconstruct_from_sentinels, cmd.color re-apply, backup.snapshot)
    are the caller's responsibility — this function only sets the
    controller's serializable fields and reconciles the (already
    sentinel-rebuilt) registry with the .bcm's per-hider metadata.

    Precondition: ``controller.registry`` was already rebuilt via
    ``reconstruct_from_sentinels`` (the caller did that between
    ``cmd.load(.pse)`` and this call).

    Args:
        controller (GameController): the controller whose registry was
            sentinel-rebuilt. Sets ``_reveal_count``, ``_hint_count``,
            ``_found_color``; reconciles ``registry`` in place.
        bcm_dict (dict): the parsed .bcm sidecar.

    Returns:
        ReconcileMismatches: the namedtuple from
        ``registry.reconcile_with_bcm`` — caller logs warnings.

    Raises:
        ValueError: if the .bcm kind or version is wrong (refuse load).
    """
    if bcm_dict.get('kind') != BCM_KIND:
        raise ValueError(
            "not a bioCHEMeleon sidecar (kind=%r, expected %r)" %
            (bcm_dict.get('kind'), BCM_KIND))
    if int(bcm_dict.get('version', 1)) != BCM_VERSION:
        raise ValueError(
            "unsupported .bcm version %r (expected %r)" %
            (bcm_dict.get('version'), BCM_VERSION))
    # State fields
    controller._reveal_count = int(bcm_dict.get('reveal_count', 0))
    controller._hint_count = int(bcm_dict.get('hint_count', 0))
    controller._found_color = str(bcm_dict.get('found_color', 'green'))
    # Reconcile registry (mutates in place, returns mismatches)
    bcm_registry = bcm_dict.get('registry', {})
    bcm_hiders = bcm_registry.get('hiders', []) if isinstance(bcm_registry, dict) else []
    mismatches = controller.registry.reconcile_with_bcm(bcm_hiders)
    return mismatches
```

### 7.3 Why a module-level function (not a `GameController.to_bcm_dict` method)

- **Purity:** `persistence.py` is WSL-testable (no `pymol`); `game.py` is cmd-coupled (`from pymol import cmd` at `game.py:6`). Putting the assembly on the controller would either make it untestable in WSL or require a mock-`cmd` stub for the assembly tests (which don't need cmd at all).
- **Cohesion:** the controller's role is the runtime game loop; serialization is a separate responsibility. A `persistence.py` module is the standard separation.
- **Testability:** `tests/test_persistence.py` (new) can construct a fake controller (a small `Mock Controller` with the required attributes) + a setup dict + call `build_bcm_dict` / `apply_bcm_dict` without any PyMOL stub. Pure round-trip tests.

### 7.4 Why `apply_bcm_dict` refuses on version mismatch (vs best-effort)

A `.bcm` v2 from a future plugin version may have fields v1 doesn't understand OR may have removed fields v1 requires. Best-effort loading risks a silently-wrong game (e.g., a v2 .bcm that changed the `status` enum to include `'revealed'` would make v1's `reconcile_with_bcm` fall back to `'hidden'` for every revealed hider — the player sees a "fresh" game that's actually mid-play). Refuse with a clear error ("this .bcm was written by a newer bioCHEMeleon; upgrade your plugin") is safer. The user can still load the `.pse` and play a degraded game without the sidecar (the §2.3 fallback ladder). See §10.1.

### 7.5 Setup dict shape — already JSON-serializable

`gui_setup.collect_state()` (`gui_setup.py:441-459`) returns a dict with `"format": SETUP_FORMAT`, `"target_mode"`, `"selected_object"`, `"pdb_code"`, `"demo_id"`, `"hider_count"`, `"lock_scene"`, `"per_rep"`, `"difficulty_easy"`, `"lock_source"`, `"pdb_pool"` — all JSON-serializable primitives (str/int/bool/list/dict). Save/Load Setup (Phase 2) already round-trips this via `json.dump`/`json.load` (`gui_setup.py:546-587`). So embedding it in the `.bcm` under `"setup"` is free.

For a Save-mid-game, `setup_state` = the current Setup tab state (captured at Save click). For a Generate&export, `setup_state` = the educator's configuration. For an Import, the setup is restored to the Setup tab via `apply_state(bcm_dict['setup'])` so the player sees what was configured (and a Restart-on-imported re-generates from the same setup).

---

## 8. GUI Re-Attachment — `start_countdown` → `_begin_play` → callbacks + wizard + timer

### 8.1 The full import flow (in `__init__.py` — composition root)

The Phase 8 Import button (sibling researcher's concern — button placement is NOT this dimension) triggers an import handler in `__init__.py`. The state-serialization portion of that handler is:

```python
def _on_import(self, pse_path, bcm_path):
    """Import a saved game (checkpoint or puzzle)."""
    from . import game, mutation, backup, registry, persistence
    import json
    from pymol import cmd

    # 1. Load the .pse (restores atoms + colors + reps + scene)
    cmd.load(pse_path)   # importing.py:635 — auto-detects .pse, calls load_pse

    # 2. Read the .bcm sidecar (graceful degradation if missing/corrupt)
    bcm_dict = None
    try:
        with open(bcm_path) as f:
            bcm_dict = json.load(f)
    except (OSError, ValueError) as e:
        QtWidgets.QMessageBox.warning(
            self, "Sidecar missing or corrupt",
            "Could not read the .bcm sidecar:\n{}\n\n"
            "Loading the .pse only — the game will be playable but per-rep "
            "counts, found-status, and timer will be reset.".format(e))

    # 3. Determine target_obj — prefer .bcm, else from .pse (single object)
    if bcm_dict and 'target_obj' in bcm_dict:
        target_obj = bcm_dict['target_obj']
    else:
        # fall back: first loaded molecule object
        objs = demos.list_loaded_molecule_objects()
        if not objs:
            QtWidgets.QMessageBox.warning(self, "No object",
                "The .pse contains no molecule object.")
            return
        target_obj = objs[0]

    # 4. Build the controller + sentinel-rebuild the registry
    self._controller = game.GameController(target_obj)
    self._controller.registry = registry.HiderRegistry().reconstruct_from_sentinels(
        lambda: mutation.fetch_all_hider_ids(target_obj))

    # 5. Apply .bcm state (reconcile + controller fields) or degrade
    elapsed = 0.0
    mismatches = None
    if bcm_dict is not None:
        try:
            mismatches = persistence.apply_bcm_dict(self._controller, bcm_dict)
            elapsed = float(bcm_dict.get('elapsed', 0.0))
        except ValueError as e:
            QtWidgets.QMessageBox.warning(
                self, "Sidecar refused",
                "Refused to load the .bcm sidecar:\n{}\n\n"
                "Loading the .pse only (degraded game).".format(e))
            # registry stays sentinel-rebuilt (rep=None, hidden) — playable
    self._controller._started = True   # hiders ARE in the object

    # 6. Defensive found-color re-apply (§4.2)
    for rec in self._controller.registry.all():
        if rec.status == registry.HIDER_STATUS_FOUND:
            cmd.color(self._controller._found_color,
                      "%s and id %d" % (self._controller.target_obj, rec.id))

    # 7. Snapshot the imported state — this is the "original" for Cleanup (§6)
    self._controller._backup_name = backup.snapshot(target_obj)

    # 8. Restore the Setup tab from the .bcm (so Restart-on-imported regenerates)
    if bcm_dict and 'setup' in bcm_dict:
        self.setup_tab.apply_state(bcm_dict['setup'])

    # 9. Switch to Game tab + start countdown with resumed timer
    self.tabs.setCurrentWidget(self.game_tab)
    self.game_tab.start_countdown(self._controller, elapsed=elapsed)

    # 10. Log mismatches (warnings — not errors)
    if mismatches:
        for obj, aid in mismatches.missing_from_bcm:
            self.game_tab._log("Warning: hider id %d in %s is not in the sidecar "
                              "(playing as hidden, no per-rep count)" % (aid, obj))
        for obj, aid in mismatches.missing_from_pse:
            self.game_tab._log("Warning: sidecar lists hider id %d in %s but the "
                              ".pse doesn't have it (skipped)" % (aid, obj))
        for obj, aid, bad_rep in mismatches.bad_rep:
            self.game_tab._log("Warning: hider id %d in %s has unknown rep %r "
                              "(treating as rep=None)" % (aid, obj, bad_rep))
```

### 8.2 The `_begin_play` re-attachment — what already works

`_begin_play` (`gui_game.py:206-224`) creates a fresh `PickWizard`, activates it, registers the GUI callbacks (`_log`, `_update_remaining`, `_on_win`, `_on_counts_changed`), starts the QTimer, and updates the remaining count. For an imported game, this is EXACTLY what we want — the wizard is fresh (the saved wizard was transient and not serialized), the callbacks are re-attached (the saved callbacks were transient), the timer is started (with the resumed `_start_time` per §5.2). **No special-casing of `_begin_play` for imported games** beyond the `elapsed` parameter.

### 8.3 The `_remaining()` count after reconcile

`_begin_play` calls `self._update_remaining(self._controller._remaining())` (`gui_game.py:224`). `_remaining()` (`game.py:86-89`) counts records with `status == 'hidden'`. After reconcile, found hiders have `status='found'` and hidden hiders have `status='hidden'` — so `_remaining()` correctly returns `N - found_count`. The remaining label shows the right number on import. **No special-casing.**

### 8.4 The reveal-count label after reconcile

Per §5.2, `start_countdown` seeds `self._reveal_label` from `controller._reveal_count`. After `apply_bcm_dict` sets `controller._reveal_count = bcm_dict.get('reveal_count', 0)`, the label shows the saved reveal count. **No special-casing beyond §5.2.**

### 8.5 The found-mgmt dropdown after reconcile

The Phase 7 found-mgmt dropdown's "Hide found" / "Show found" / "Recolor found" (`gui_game.py:123-159`) reads `self._controller.registry.all()` + filters by `HIDER_STATUS_FOUND` + uses `build_found_selection` + `group_found_by_rep`. After reconcile:
- `status='found'` records are correctly filtered (reconcile set them).
- `rep` is set from `.bcm` (so `group_found_by_rep` does NOT skip them — §4.3).
- The dropdown works on an imported game exactly as on a fresh game. **No special-casing.**

### 8.6 Win on imported game

If the player imports a checkpoint that was 1 hider away from winning, finds the last hider, `on_pick` (`game.py:91-112`) calls `self.win()` which fires `self._on_win(elapsed)` (the GUI callback, re-attached by `_begin_play`). `_on_win` (`gui_game.py:226-241`) stops the timer + shows the win dialog with `elapsed` = the resumed-then-continued total. **No special-casing.**

### 8.7 The info log — do NOT serialize

The info log (`gui_game.py:22` `self._info_log`, a `QTextEdit`) is a rolling transcript of "Found one!" / "Miss!" / "Hint: ..." messages. **Do NOT serialize it in the `.bcm`.** Rationale:
1. **Bloat.** A 10-minute game can produce 50+ log lines × ~30 chars = ~1.5 KB of text. The `.bcm` without the log is ~2-5 KB (registry + setup + counts). Doubling the file size for a log the player can regenerate by playing is a bad trade.
2. **Staleness.** The log is a play-session artifact, not a game-state artifact. The player saves to resume the GAME (hiders, timer, counts), not to resume the LOG (which is a record of past events, not a state to be in).
3. **Clean resume.** `start_countdown` clears the log (`gui_game.py:194` `self._info_log.clear()`). A resumed game starts with a fresh log — the player's next "Found one!" appears as the first line. This is the right UX: the log is "what happened THIS session", not "what happened in past sessions".

---

## 9. Testability — Pure Unit Tests + Headless Smoke + GUI Checkpoint

### 9.1 Pure unit tests (WSL, no PyMOL) — `tests/test_registry.py` + `tests/test_persistence.py`

**Extend `tests/test_registry.py`** with a new `TestReconcileFromBcm` class (mirrors the existing `TestHiderRegistryReconstruct` at lines 451-532). Proposed method names:

```
class TestReconcileFromBcm(unittest.TestCase):
    """Test HiderRegistry.reconcile_with_bcm — the .bcm metadata merge.

    Pure: builds a sentinel-rebuilt registry (via reconstruct_from_sentinels
    with a fake iterate fn), then calls reconcile_with_bcm with a .bcm
    hiders list, asserts the merged records + returned mismatches.
    """

    def test_perfect_match_sets_rep_and_status(self):
        """3 sentinels + 3 .bcm entries (1 found) -> 3 records, real rep,
        1 found, 2 hidden; no mismatches."""
        # sentinel-rebuilt: 3 records, rep=None, hidden
        # .bcm: [{id:1,object:'o',rep:'spheres',status:'found'},
        #        {id:2,object:'o',rep:'sticks',status:'hidden'},
        #        {id:3,object:'o',rep:'cartoon',status:'hidden'}]
        # After reconcile: r1.rep='spheres', r1.status='found';
        #                  r2.rep='sticks', r2.status='hidden';
        #                  r3.rep='cartoon', r3.status='hidden'
        # Mismatches: all empty

    def test_missing_from_bcm_stays_rep_none_hidden(self):
        """Sentinel id=4 not in .bcm -> stays rep=None, status='hidden';
        missing_from_bcm == [('o', 4)]."""

    def test_missing_from_pse_not_registered(self):
        """ .bcm lists id=99 (not in sentinels) -> not registered;
        missing_from_pse == [('o', 99)]; registry has 3 records, not 4."""

    def test_bad_rep_skipped_with_warning(self):
        """ .bcm hider with rep='surface' (not in GAME_REPS) -> rec.rep
        stays None, bad_rep == [('o', 1, 'surface')]."""

    def test_bad_status_defaults_to_hidden(self):
        """ .bcm hider with status='revealed' (unknown) -> rec.status
        defaults to 'hidden' (no raise)."""

    def test_pos_restored_from_bcm(self):
        """ .bcm hider with pos=[1.0,2.0,3.0] -> rec.pos == [1.0,2.0,3.0]
        (list, not tuple — JSON round-trip)."""

    def test_empty_bcm_hiders_list(self):
        """reconcile_with_bcm([]) on a 3-sentinel registry -> all 3
        records stay rep=None, hidden; missing_from_bcm has 3 entries."""

    def test_none_bcm_hiders(self):
        """reconcile_with_bcm(None) -> graceful (treated as empty list);
        all records stay rep=None, hidden; 3 missing_from_bcm entries."""

    def test_mismatched_object_not_merged(self):
        """ .bcm hider (object='other', id=1) doesn't match sentinel
        ('o', 1) -> not merged; sentinel stays rep=None, hidden; .bcm
        entry flagged missing_from_pse."""
        # (multi-object future-safety; currently single-object)

    def test_id_int_coercion_in_bcm_index(self):
        """ .bcm hider with id='5' (str from JSON) matches sentinel id=5
        (int) via the int(h['id']) coercion in reconcile_with_bcm."""

    def test_round_trip_to_dict_reconstruct_reconcile(self):
        """Full round-trip: register 3 -> to_dict -> reconstruct_from_sentinels
        (fake) -> reconcile_with_bcm(to_dict['hiders']) -> records match
        original (id/object/rep/status). The .bcm round-trip preserves
        all four fields."""

    def test_counts_by_rep_after_reconcile_reflects_bcm_reps(self):
        """After reconcile, counts_by_rep reflects the .bcm reps (not all-zero
        from the rep=None sentinel-rebuild state). This is the load-bearing
        regression test for §10.6's rep=None limitation."""
```

**New file `tests/test_persistence.py`** — tests for `build_bcm_dict` + `apply_bcm_dict` + round-trip. Proposed method names:

```
class TestBuildBcmDict(unittest.TestCase):
    def test_checkpoint_dict_shape(self):
        """build_bcm_dict(controller, setup, 'checkpoint', elapsed=42.5)
        -> dict with version=1, kind='bcm-game', state='checkpoint',
        target_obj, registry=controller.registry.to_dict(), elapsed=42.5,
        reveal_count, hint_count, found_color, setup, saved_at (ISO)."""

    def test_puzzle_dict_shape(self):
        """build_bcm_dict(controller, setup, 'puzzle') -> state='puzzle',
        elapsed=0.0 (default for puzzle)."""

    def test_invalid_state_kind_raises(self):
        """build_bcm_dict(..., state_kind='frob') -> ValueError."""

    def test_elapsed_none_checkpoint_uses_start_time(self):
        """elapsed=None + state='checkpoint' + controller._start_time set
        -> elapsed = time.time() - _start_time (the fallback)."""

    def test_elapsed_none_puzzle_is_zero(self):
        """elapsed=None + state='puzzle' -> elapsed=0.0 (no _start_time
        fallback for puzzles)."""

    def test_does_not_serialize_transient_fields(self):
        """build_bcm_dict output has NO _backup_name, _wizard, _on_log,
        _start_time keys (those are transient)."""

    def test_setup_embedded_verbatim(self):
        """build_bcm_dict embeds the setup_state dict under 'setup'
        unchanged (round-trip via json.dumps/loads)."""

class TestApplyBcmDict(unittest.TestCase):
    def test_sets_controller_state_fields(self):
        """apply_bcm_dict(controller, bcm) sets _reveal_count, _hint_count,
        _found_color from the dict."""

    def test_reconciles_registry(self):
        """Pre-sentinel-rebuild the registry (3 records, rep=None);
        apply_bcm_dict with 3 .bcm hiders (1 found) -> registry records
        have real rep + 1 found."""

    def test_refuses_wrong_kind(self):
        """apply_bcm_dict with kind='other' -> ValueError."""

    def test_refuses_wrong_version(self):
        """apply_bcm_dict with version=2 -> ValueError."""

    def test_tolerates_missing_registry_key(self):
        """apply_bcm_dict with no 'registry' key -> reconcile_with_bcm([])
        -> all sentinel records stay rep=None, hidden (graceful)."""

    def test_tolerates_missing_state_fields(self):
        """apply_bcm_dict with no 'reveal_count' -> defaults to 0;
        no 'found_color' -> defaults to 'green'."""

class TestBcmRoundTrip(unittest.TestCase):
    def test_build_then_apply_preserves_state(self):
        """build_bcm_dict(controller1, setup, 'checkpoint', elapsed=42.5)
        -> bcm; sentinel-rebuild registry2 + apply_bcm_dict(controller2, bcm)
        -> controller2._reveal_count == controller1._reveal_count,
        controller2._hint_count == controller1._hint_count,
        controller2._found_color == controller1._found_color,
        registry2 records match registry1 (id/object/rep/status)."""
```

A `Mock Controller` helper (small class with the 5 attributes `build_bcm_dict` reads + the `registry` HiderRegistry) keeps these tests pure. Same `sys.modules` stub for `pymol`/`pymol.Qt` as `test_registry.py:19-21` (because `biochemeleon/__init__.py` imports `pymol.Qt` at module level — but `persistence.py` itself does NOT, so the stub is just for the package import).

### 9.2 Headless smoke (PyMOL cmd, no Qt) — `smoke/phase8_smoke.py`

Modeled on `smoke/phase7_smoke.py` (per `STATE.md` — 181 lines, 38 checks, pure `pymol.cmd.*`, no Qt). The Phase 8 smoke covers success criterion 1 (this dimension). Proposed sections:

```
smoke/phase8_smoke.py (pure pymol.cmd.*, NO Qt)
Section A — SETUP:
  fetch 1ubq, orig_count = count_atoms
Section B — START + PLAY PARTIAL:
  start(3 sphere hiders seed=42), count_atoms(target) == orig + 3
  mark 1 found (cmd.color('green', 'obj and id X'); registry.mark_found)
  reveal_one (1 more found)
  hint (1 hint used, orange neighbors)
  # State now: 3 hiders, 2 found, 1 hidden, 1 reveal, 1 hint
Section C — SAVE:
  elapsed = time.time() - controller._start_time   # capture BEFORE save
  cmd.save(tmp/game.pse)
  bcm = build_bcm_dict(controller, setup, 'checkpoint', elapsed=elapsed)
  json.dump(bcm, open(tmp/game.bcm, 'w'))
  assert bcm['registry']['hiders'] has 3 entries, 2 with status='found'
  assert bcm['reveal_count'] == 1, bcm['hint_count'] == 1
Section D — LOAD + RECONSTRUCT:
  cmd.delete(target_obj); cmd.delete('_bchm_backup')   # clear
  cmd.load(tmp/game.pse)
  # Verify sentinel survived + id stable + b=-999 + (color round-trip):
  sent = mutation.fetch_all_hider_ids(target_obj)
  assert len(sent) == 3                                  # sentinel survived
  # Verify found hider color round-tripped (§4.1):
  for rec_id in found_ids:
    cmd.iterate("obj and id %d" % rec_id, "stored.append(color)",
                space={'stored': []}) -> assert green index
Section E — RECONCILE:
  controller2 = GameController(target_obj)
  controller2.registry = HiderRegistry().reconstruct_from_sentinels(
      lambda: mutation.fetch_all_hider_ids(target_obj))
  assert all(rec.rep is None for rec in controller2.registry.all())  # pre-reconcile
  assert all(rec.status == 'hidden' for rec in controller2.registry.all())
  bcm_loaded = json.load(open(tmp/game.bcm))
  mismatches = apply_bcm_dict(controller2, bcm_loaded)
  assert mismatches.missing_from_bcm == []
  assert mismatches.missing_from_pse == []
  assert mismatches.bad_rep == []
  # Post-reconcile:
  assert all(rec.rep is not None for rec in controller2.registry.all())  # rep set
  found_recs = [r for r in controller2.registry.all() if r.status == 'found']
  assert len(found_recs) == 2                              # found-status preserved
  assert controller2._reveal_count == 1
  assert controller2._hint_count == 1
  assert controller2._found_color == 'green'
Section F — COUNTS_BY_REP RECOVERED:
  # Pre-reconcile counts (rep=None skipped):
  pre_counts = HiderRegistry().reconstruct_from_sentinels(...).counts_by_rep()
  assert all(v == 0 for v in pre_counts.values())        # rep=None invisible
  # Post-reconcile counts:
  post_counts = controller2.registry.counts_by_rep()
  assert post_counts['spheres'] == 3                     # rep recovered
Section G — FOUND-MGMT SELECTION RECOVERED:
  found = [r for r in controller2.registry.all() if r.status == 'found']
  sele = build_found_selection(found, target_obj)        # 'obj and id X+Y'
  assert cmd.count_atoms(sele) == 2                      # both found atoms selectable
  by_rep = group_found_by_rep(found)
  assert 'spheres' in by_rep and len(by_rep['spheres']) == 2  # rep non-None
Section H — BACKUP SNAPSHOT + CLEANUP RESTORE:
  controller2._started = True
  controller2._backup_name = backup.snapshot(target_obj)  # the "original" = imported state
  # Defensive found-color re-apply (idempotent — already green from .pse):
  for rec in controller2.registry.all():
    if rec.status == 'found':
      cmd.color(controller2._found_color, "%s and id %d" % (target_obj, rec.id))
  # Cleanup should restore to the imported state (3 hiders, 2 green):
  backup.restore(target_obj, controller2._backup_name)
  backup.discard(controller2._backup_name)
  assert cmd.count_atoms(target_obj) == orig + 3         # hiders back (imported state)
  assert len(mutation.fetch_all_hider_ids(target_obj)) == 3
Section I — MISMATCH SIMULATION (corrupt .bcm):
  # .bcm with a 4th hider not in the .pse:
  bad_bcm = copy.deepcopy(bcm_loaded)
  bad_bcm['registry']['hiders'].append({'id': 9999, 'object': target_obj,
                                         'rep': 'spheres', 'status': 'hidden'})
  controller3 = GameController(target_obj)
  controller3.registry = HiderRegistry().reconstruct_from_sentinels(...)
  mismatches = apply_bcm_dict(controller3, bad_bcm)
  assert (target_obj, 9999) in mismatches.missing_from_pse
  assert len(controller3.registry.all()) == 3          # ghost NOT registered
Section J — DEGRADED LOAD (no .bcm):
  cmd.delete(target_obj); cmd.load(tmp/game.pse)
  controller4 = GameController(target_obj)
  controller4.registry = HiderRegistry().reconstruct_from_sentinels(...)
  # No apply_bcm_dict — degraded mode
  assert all(rec.rep is None for rec in controller4.registry.all())
  assert all(rec.status == 'hidden' for rec in controller4.registry.all())
  counts = controller4.registry.counts_by_rep()
  assert all(v == 0 for v in counts.values())           # rep=None invisible
  # Game is still playable: 3 hiders, _remaining() == 3, on_pick works
  assert controller4._remaining() == 3
```

Smoke target: ~30-40 checks, all pure `pymol.cmd.*` (NO Qt — `start_countdown`, `_begin_play`, `QTimer`, `QFileDialog`, `QColorDialog` are GUI-only, deferred to the human-verify checkpoint). Run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase8_smoke.py` per `AGENTS.md`.

### 9.3 GUI checkpoint (human-verify, NOT WSL-runnable)

Per `AGENTS.md`, Qt GUI paths are NOT WSL-runnable (no display, no `pymol.Qt.*` at runtime). The checkpoint covers:

- **Timer resume display:** Import a checkpoint saved at 0:42 → during countdown the label shows "0:42"; after GO! it counts up (43, 44, ...). Verify the math: `_start_time = time.time() - 42` → `_on_tick` shows `int(time.time() - _start_time)` = 42 + play_time.
- **Found-mgmt dropdown after reload:** Import a checkpoint with 2 found hiders → open the dropdown → "Show found" shows both in their original rep (NOT skipped — rep was reconciled); "Recolor found" recolors both; "Hide found" hides both.
- **Restart after import:** Import a checkpoint → click Restart → verify the imported hiders are removed (cleanup ran), fresh hiders are generated, the timer resets to 0:00 (Restart is a fresh game, NOT a resume).
- **Cleanup after import:** Import a checkpoint → play more → click Cleanup → verify the model returns to the IMPORTED state (3 hiders, 2 green for a checkpoint with 2 found), NOT the pre-game pristine state.
- **Save button click:** Mid-game, click Save → file dialog appears → save `game.pse` + `game.bcm` → verify both files exist, `.bcm` is valid JSON with the right shape, `.pse` reloads with sentinels intact.
- **Import button click:** Click Import → file dialog → select a `.bcm` (or `.pse`) → verify the right `.pse` is loaded alongside it.

These six are the human-verify checkpoint for Phase 8 success criterion 1. The state-serialization correctness (does the `.bcm` capture the right fields? does reconcile restore them?) is covered by the pure unit tests + the headless smoke; the GUI checkpoint covers the human-visible UX (timer display, dropdown behavior, file dialog flow).

---

## 10. Edge Cases

### 10.1 `.bcm` version mismatch (v2 file on a v1 plugin)

**REFUSE with a clear error.** `apply_bcm_dict` raises `ValueError("unsupported .bcm version 2 (expected 1)")` (per §7.2). The import handler catches it, shows a QMessageBox ("Refused to load the .bcm sidecar ... Loading the .pse only (degraded game)"), and proceeds with the sentinel-only rebuild (the §2.3 fallback ladder). The user gets a playable game with no metadata (per-rep counts 0, found-status lost, timer fresh) — degraded but not broken.

**Rationale:** a v2 `.bcm` may have fields v1 doesn't understand, OR may have changed enum values (e.g., a new `'revealed'` status). Best-effort loading risks a silently-wrong game (the player sees a "fresh" game that's actually mid-play because v2's status enum doesn't map to v1's). Refuse + degrade is safer.

### 10.2 `.bcm` references a `target_obj` not in the loaded `.pse`

Two sub-cases:

**A. The user loaded the wrong `.pse` (object name mismatch).** The `.bcm` says `target_obj='1ubq'` but the loaded `.pse` only has `'2qbz'`. `reconstruct_from_sentinels(lambda: mutation.fetch_all_hider_ids('1ubq'))` returns `[]` (no atom matches `'1ubq and segi GAME'` — `fetch_all_hider_ids` is empty). `reconcile_with_bcm` reports ALL `.bcm` hiders as `missing_from_pse` (none were found as sentinels). The import handler should detect this (e.g., `if mismatches.missing_from_pse and not controller.registry.all():`) and show a QMessageBox ("The .bcm references object '1ubq' but the loaded .pse has no '1ubq'. Did you load the wrong .pse?"). Refuse the import.

**B. The object was renamed.** The `.pse` has the object under a different name (the user renamed it after Save, before sharing). Same detection as (A). Suggest: "Rename the object back to '1ubq' or re-save with the current name." (Future work: a "find target by sentinel" fallback that scans all loaded objects for `segi GAME` atoms and uses the one with the matching sentinel count. Out of scope for v1 — refuse + suggest is enough.)

### 10.3 `.bcm` hiders with `rep` not in `GAME_REPS`

`reconcile_with_bcm` catches this (per §3.2 pseudo-code): the record's `rep` is left `None`, the entry is added to `bad_rep`, the load continues. The caller logs a warning. The hider is still playable (it's a real sentinel atom), just without per-rep count or found-mgmt show-by-rep.

**Why not raise?** A corrupt sidecar should not kill the load. The sentinel-rebuilt registry is already playable; the bad rep is one hider's metadata. Skip + warn is the graceful path.

### 10.4 Zero hiders (empty game)

**ALLOW.** `reconcile_with_bcm([])` on an empty sentinel-rebuilt registry returns all-empty `ReconcileMismatches` (no records to mismatch). The game starts with `_remaining() == 0`, which would immediately trigger `win()` on the first `mark_found` — but there are no hiders to mark, so `on_pick`/`reveal_one`/`reveal_all` are all no-ops (`game.py:91-112`, `game.py:178-200`, `game.py:202-222` — they early-return when `hidden` is empty). The player sees "Remaining: 0" + a timer + no hiders; they can click Cleanup to end the round. Degenerate but not broken. (An educator who exports an empty puzzle gets an unwinnable-but-instantly-won game — confusing UX, but the file format should not refuse it. The Generate&export UI should warn "0 hiders generated; this puzzle has no solution" — that's the export workflow's concern, not the state-serialization dimension.)

### 10.5 The `pos` field — vestigial, restore for completeness, not used at runtime

**Confirmed vestigial.** `grep -n "\.pos\b" biochemeleon/*.py` returns only the 3 hits in `registry.py` (the slot, `__init__` assignment, `to_dict` serialization). NO runtime code reads `rec.pos`:
- `hint()` (`game.py:136-176`) uses `byres around` selection on the hider atom by id — NOT `rec.pos`.
- `reveal_one()` / `reveal_all()` (`game.py:178-222`) iterate the registry + call `_mark_found(rec.id)` — NOT `rec.pos`.
- `on_pick` (`game.py:91-112`) reads `rec.status` — NOT `rec.pos`.
- The found-mgmt dropdown (`gui_game.py:123-159`) reads `rec.status` + `rec.rep` — NOT `rec.pos`.

**Conclusion:** `pos` was a Phase 6 hint/reveal vestige — the original design intended hint/reveal to use the stored pos, but the actual implementation uses selections. `pos` is in the data model + serialized to `.bcm` for losslessness, but reconcile does NOT need to restore it for correctness. **Restore it anyway** (one line in `reconcile_with_bcm`: `if 'pos' in h and h['pos'] is not None: rec.pos = list(h['pos'])`) — keeps the `.bcm` round-trip lossless and costs nothing. Do NOT add `pos` reconciliation to the unit-test must-haves (it's not load-bearing).

### 10.6 The `rep=None` after sentinel rebuild limitation — MANDATORY reconcile

**Confirmed MANDATORY.** Two functions skip `rep=None` records:
- `counts_by_rep()` (`registry.py:178-198`): `if r.rep is None: continue` (line 195). A registry of all-`rep=None` records returns `{rep: 0 for rep in GAME_REPS}` — all zero. The Phase 4-7 GUI "Remaining: N per rep" would show all zeros. Confirmed by the existing unit test `test_reconstruct_rep_none_then_counts_by_rep` (`tests/test_registry.py:558-576`).
- `group_found_by_rep()` (`registry.py:299-313`): `if r.status == HIDER_STATUS_FOUND and r.rep is not None:` (line 311). A found hider with `rep=None` is skipped — the found-mgmt "Show found" mode (`gui_game.py:144-148`) builds no selection for it. Confirmed by the existing unit test `test_group_found_by_rep_rep_none_skipped` (`tests/test_registry.py:663-667`).

**Therefore:** without reconcile, a reloaded game's per-rep counts are all 0 (the "Remaining: 3 spheres" label says "Remaining: 0") AND found-mgmt "Show found" shows nothing for found hiders. The game is technically playable (the player can still click hiders — `on_pick` reads `rec.status`, not `rec.rep`) but the UX is broken (no per-rep counts, broken found-mgmt). **Reconcile is MANDATORY for a usable reloaded game.**

**After reconcile:** no `rep=None` records remain UNLESS a sentinel hider is missing from the `.bcm` (then it stays `None`, flagged `missing_from_bcm`). The happy path (perfect `.bcm` match) leaves zero `rep=None` records. The smoke section F (§9.2) verifies this.

### 10.7 The `_found_color` field — 'green' vs 'found_highlight'

`controller._found_color` (`game.py:40`) defaults to `'green'`; the Phase 7 color picker (`gui_game.py:161-180`) sets it to `'found_highlight'` (a custom named color via `cmd.set_color`). The `.bcm` saves the string (`'green'` or `'found_highlight'`). On import, `apply_bcm_dict` sets `controller._found_color = bcm_dict.get('found_color', 'green')`.

**Pitfall:** `'found_highlight'` is a PyMOL named color defined at runtime via `cmd.set_color('found_highlight', [r, g, b])`. The `.pse` saves custom named colors (they're part of the session state — `_cmd.get_session` captures them; verified by the same mechanism as §4.1). So on `cmd.load(.pse)`, `'found_highlight'` is re-defined with the same RGB. The defensive re-color (`cmd.color('found_highlight', ...)`) works. BUT if the user imports ONLY the `.bcm` without the `.pse` (shouldn't happen — the Import flow loads both), `'found_highlight'` is undefined and `cmd.color` raises `CmdException`. The import handler must load the `.pse` first (which defines the named color) — the order in §8.1 (step 1 load `.pse`, step 6 re-color) is correct.

**Defensive fallback in `apply_bcm_dict`:** if `found_color` is not `'green'` (a built-in) and not in `cmd.get_names('colors')` (or whatever the API is), fall back to `'green'` + log a warning. UNVERIFIED — needs runtime confirmation that `cmd.get_names('colors')` exposes named colors (or use a try/except around the first `cmd.color` call). Mark as a runtime-verification need (§12).

### 10.8 The `saved_at` timestamp — optional, display only

`saved_at` is an ISO 8601 timestamp (`time.strftime('%Y-%m-%dT%H:%M:%S')`). Not used by reconcile or any game logic — purely for the UI to display "Saved at 2026-08-12 14:32" in the Import file dialog or as a log message. Optional field; `apply_bcm_dict` does NOT read it. If a `.bcm` lacks it, no warning.

---

## 11. Save Timing — Pause-Timer-Before-Dialog

### 11.1 The pitfall (PITFALLS.md UX row)

`PITFALLS.md` UX row: "Timer keeps running while a Qt modal (file dialog) is open — Times are unfair across save/load operations. Better Approach: Pause timer on any modal dialog; resume on return."

`QFileDialog.getSaveFileName` (`gui_setup.py:548`) is a MODAL dialog — it blocks the Qt event loop (and thus the QTimer's `_on_tick`) BUT `time.time()` keeps advancing in the background. So if the user takes 10 seconds to choose a filename, the timer advances 10 seconds without the player playing. The captured `elapsed = time.time() - controller._start_time` is inflated by the dialog time.

### 11.2 The recommended capture order

**Capture `elapsed` BEFORE opening the file dialog.** Recommended implementation (pause-capture-dialog-save-resume):

```python
def _on_save(self):
    """Save-mid-game: .pse + .bcm sidecar."""
    from . import persistence
    import json
    from pymol import cmd

    if self._controller is None or not self._controller._started:
        return

    # 1. PAUSE the timer (stop the QTimer so _on_tick doesn't fire during the dialog)
    self.game_tab._timer.stop()

    # 2. CAPTURE elapsed NOW (before the modal dialog — not after)
    elapsed = time.time() - self._controller._start_time

    # 3. Open the file dialog (modal — time.time() advances but elapsed is fixed)
    pse_path, _ = QtWidgets.QFileDialog.getSaveFileName(
        self, "Save bioCHEMeleon game", "",
        "bioCHEMeleon Game (*.pse);;All Files (*)")
    if not pse_path:
        # Cancelled — rebase to exclude the dialog-wait, then resume
        self._controller._start_time = time.time() - elapsed
        self.game_tab._timer.start(1000)
        return

    # 4. Derive the .bcm path (sibling file — sibling researcher's concern)
    bcm_path = pse_path.rsplit('.', 1)[0] + '.bcm'

    # 5. Write the .pse (the heavy operation — time.time() advances but elapsed is fixed)
    cmd.save(pse_path)

    # 6. Assemble + write the .bcm
    setup_state = self.setup_tab.collect_state()
    bcm_dict = persistence.build_bcm_dict(
        self._controller, setup_state, state_kind='checkpoint', elapsed=elapsed)
    with open(bcm_path, 'w') as f:
        json.dump(bcm_dict, f, indent=2)

    # 7. RESUME the timer — adjust _start_time so the displayed elapsed
    #    continues from the captured point (the dialog + save time is
    #    NOT counted against the player).
    self._controller._start_time = time.time() - elapsed
    self.game_tab._timer.start(1000)
    self.game_tab._log("Saved to %s + %s" % (pse_path, bcm_path))
```

### 11.3 Why capture elapsed before the dialog, not after

If you capture after the dialog, the elapsed includes the dialog time → the saved `.bcm` has an inflated `elapsed` → on import, the resumed timer starts at the inflated value → unfair to the player. Capturing before fixes the saved value; adjusting `_start_time` after the save (step 7) fixes the displayed value too.

### 11.4 The cancel case

If the player cancels the file dialog, the timer must resume without the dialog-wait penalty. The rebase in the cancel branch (`self._controller._start_time = time.time() - elapsed`) handles this: on cancel, the next tick computes `time.time() - (time.time() - elapsed) == elapsed` — the timer continues from the captured value, as if the dialog never happened. Without the rebase, the cancel would penalize the player by the dialog-wait. **Both the tab's `_start_time` AND the controller's `_start_time` must be rebased** (the `Bug 1` mirror at `gui_game.py:218-221` — the controller's copy feeds `win()`'s elapsed math at `game.py:131`).

### 11.5 Order: capture elapsed → pause timer → dialog → cmd.save → write .bcm → resume timer

The order in §11.2 is critical:
1. **Pause timer** (stop QTimer) — so `_on_tick` doesn't fire during the dialog + save (it would show an advancing timer while the player is in the dialog).
2. **Capture elapsed** — `time.time() - _start_time` at this instant.
3. **Dialog** — modal; `time.time()` advances but elapsed is fixed.
4. **`cmd.save(pse_path)`** — heavy operation (writes a pickle of the full session); `time.time()` advances but elapsed is fixed.
5. **Assemble + write `.bcm`** — fast (JSON dump of a small dict).
6. **Resume timer** — `_start_time = time.time() - elapsed` makes the next `_on_tick` show `int(time.time() - _start_time) = int(elapsed)` (the same as before the dialog), then `elapsed + 1` on the next tick, etc.

---

## 12. Open Risks / Runtime-Verification Needs

### 12.1 `cmd.color('found_highlight', ...)` after import — UNVERIFIED

The defensive found-color re-apply (§4.2) calls `cmd.color(controller._found_color, ...)`. If `_found_color == 'found_highlight'` (a custom named color from the Phase 7 color picker), the color must be defined in the loaded `.pse` (the `.pse` preserves custom named colors via the same `_cmd.get_session` mechanism — HIGH confidence but UNVERIFIED for the specific case of a custom name set by `cmd.set_color` in a plugin). If the `.pse` does NOT preserve custom named colors, `cmd.color('found_highlight', ...)` raises `CmdException` (undefined color).

**Mitigation:** wrap the re-color in a try/except — if `CmdException`, fall back to `cmd.color('green', ...)` + log a warning. OR check `cmd.get_color_index('found_highlight')` (returns -1 if undefined) before the re-color.

**Verification needed:** headless smoke section D should `cmd.set_color('found_highlight', [0.1, 0.9, 0.1])` + `cmd.color('found_highlight', ...)` + `cmd.save(...)` + `cmd.delete` + `cmd.load(...)` + `cmd.color('found_highlight', ...)` — if the second `cmd.color` succeeds, custom named colors round-trip. If it raises, fall back to 'green' and document.

### 12.2 Multi-object future-safety — UNVERIFIED

The registry keys by `(object, id)` (`registry.py:89`). `reconcile_with_bcm` matches by `(object, id)`. Currently, the plugin targets a single object (`controller.target_obj` is one string). The `.bcm` saves one `target_obj` + a registry with `object` per hider (all the same). If a future phase supports multi-object games (hiders across multiple objects), the `.bcm` schema already supports it (the `object` field per hider). The reconcile already matches by `(object, id)`. NO change needed for multi-object — but UNVERIFIED that the current `GameController` constructor's `target_obj: str` doesn't break (it's a single string; multi-object would need `target_objs: list`). Out of scope for Phase 8 — single-object only.

### 12.3 `.pse` color round-trip for `cmd.set_color` named colors — UNVERIFIED

Per §4.1, per-atom color (the integer color index) round-trips through `.pse` (it's part of the `ObjectMolecule` atom struct). Custom NAMED colors (the RGB-to-name mapping set by `cmd.set_color`) are part of the session's color registry — also serialized by `_cmd.get_session`. HIGH confidence but UNVERIFIED at the runtime tier for the specific case of a plugin-defined custom color. The Phase 3 smoke confirmed `segi` + `b` + `id` (atom properties) round-trip; it did NOT test custom named colors. The Phase 8 smoke (§9.2 section D) should add a custom-named-color round-trip assertion to close this gap.

### 12.4 Concurrent Save during a Qt modal — UNVERIFIED

The save flow (§11) opens a `QFileDialog` (modal) while the QTimer is stopped. If the player clicks Save during the 3-2-1 countdown (before `_begin_play`), `controller._start_time` is `None` and `elapsed = time.time() - None` raises `TypeError`. The save button should be disabled during the countdown (a GUI concern — sibling researcher's button-placement dimension) OR the save handler should guard `if controller._start_time is None: return`. The state-serialization dimension recommends the guard (cheap, defensive) — `if self._controller is None or not self._controller._started or self._controller._start_time is None: return`.

### 12.5 Save during a win-pending state — UNVERIFIED

After `on_pick` finds the last hider, `win()` fires `_on_win(elapsed)`, which (in `_on_win` at `gui_game.py:226-241`) stops the QTimer + schedules `_finish_win` 100 ms later. If the player clicks Save during that 100 ms window, the QTimer is stopped but `_started` is still True. The save handler captures `elapsed = time.time() - _start_time` (correct — the win-time elapsed). The `.bcm` has `state='checkpoint'` with all hiders found. On import, `_remaining() == 0` → `_begin_play` → the player is in a "won but not cleaned up" state. The first click on a non-hider would log "Miss!" but `win()` doesn't re-fire (no `on_pick` triggers it). The player can click Cleanup. UNVERIFIED that this edge case is acceptable UX — recommend disabling Save during the win-pending 100 ms window (a GUI concern, sibling researcher). The state-serialization side: the `.bcm` is correct (all found, the right elapsed); the import is correct (rebuilds the won state). The only UX issue is the player confusion of "importing a won game" — recommend the Import handler detect `if controller._remaining() == 0: log("This game was saved after winning; click Cleanup to reset.")`.

---

## 13. Source Citations

### 13.1 In-repo (existing code)

| Claim | Citation |
|---|---|
| `HiderRecord` slots + `rep=None` tolerance | `biochemeleon/registry.py:44-102` |
| `HiderRegistry.to_dict()` shape | `biochemeleon/registry.py:215-225` |
| `HiderRegistry.from_dict()` round-trip | `biochemeleon/registry.py:227-245` |
| `HiderRegistry.reconstruct_from_sentinels` (DI, rep=None, status=hidden) | `biochemeleon/registry.py:249-272` |
| `HiderRegistry.mark_found` (KeyError on absent) | `biochemeleon/registry.py:200-211` |
| `HiderRegistry.register` (KeyError on duplicate) | `biochemeleon/registry.py:131-143` |
| `counts_by_rep` SKIPS `rep=None` records | `biochemeleon/registry.py:178-198` (line 195) |
| `group_found_by_rep` SKIPS `rep=None` records | `biochemeleon/registry.py:299-313` (line 311) |
| `build_found_selection` returns None for no found | `biochemeleon/registry.py:277-296` |
| `GameController.__init__` state to serialize | `biochemeleon/game.py:20-40` |
| `GameController.start` (snapshot + insert + register; resets counters) | `biochemeleon/game.py:42-63` |
| `GameController.reconstruct_registry` | `biochemeleon/game.py:224-229` |
| `GameController.cleanup` (restore from backup + discard) | `biochemeleon/game.py:231-262` |
| `GameController._mark_found` (registry + cmd.color) | `biochemeleon/game.py:114-117` |
| `GameController._remaining` (counts status='hidden') | `biochemeleon/game.py:86-89` |
| `GameController.win` (elapsed = time.time() - _start_time) | `biochemeleon/game.py:119-132` |
| `GameTab.start_countdown` (current signature, no elapsed) | `biochemeleon/gui_game.py:188-196` |
| `GameTab._begin_play` (wizard + callbacks + _start_time + QTimer) | `biochemeleon/gui_game.py:206-224` |
| `GameTab._on_tick` (timer display math) | `biochemeleon/gui_game.py:182-186` |
| `GameTab._on_counts_changed` (reveal label) | `biochemeleon/gui_game.py:93-94` |
| `GameTab._on_found_mgmt` (uses build_found_selection + group_found_by_rep) | `biochemeleon/gui_game.py:123-159` |
| `GameTab._on_pick_color` (custom named color 'found_highlight') | `biochemeleon/gui_game.py:161-180` |
| `PluginDialog._on_start` (composition root; wizard lifecycle fix) | `biochemeleon/__init__.py:79-244` |
| `PluginDialog._on_restart` (deactivate + stop + _on_start) | `biochemeleon/__init__.py:246-263` |
| `PluginDialog._on_cleanup` (deactivate + stop + cleanup + UI reset) | `biochemeleon/__init__.py:265-286` |
| `mutation.fetch_all_hider_ids` (sentinel iterate; `segi GAME and b < 0`) | `biochemeleon/mutation.py:95-126` |
| `mutation.insert_hider` (sentinel set; `b=-999.0`) | `biochemeleon/mutation.py:38-90` |
| `backup.snapshot` (delete + create fresh copy) | `biochemeleon/backup.py:39-44` |
| `backup.restore` (delete + create two-step) | `biochemeleon/backup.py:54-64` |
| `backup.discard` (idempotent delete) | `biochemeleon/backup.py:47-49` |
| `gui_setup.collect_state()` (JSON-serializable setup dict) | `biochemeleon/gui_setup.py:441-459` |
| `gui_setup.apply_state` (round-trip) | `biochemeleon/gui_setup.py:461-519` |
| `gui_setup._save_setup` (QFileDialog + json.dump — the Phase 2 pattern) | `biochemeleon/gui_setup.py:546-561` |
| Existing pure-layer unit-test pattern (sys.modules stub) | `tests/test_registry.py:19-21` |
| Existing `TestHiderRegistryReconstruct` (pattern for `TestReconcileFromBcm`) | `tests/test_registry.py:451-532` |
| Existing `test_reconstruct_rep_none_then_counts_by_rep` (rep=None invisible) | `tests/test_registry.py:558-576` |
| Existing `test_group_found_by_rep_rep_none_skipped` | `tests/test_registry.py:663-667` |
| `pos` is vestigial (no `.pos` reads in `biochemeleon/`) | `grep -n "\.pos\b" biochemeleon/*.py` → only `registry.py:81,100,101` |
| `GAME_REPS` (5 reps, no surface) | `biochemeleon/setup_state.py` (imported by `registry.py:30`) |
| `HIDER_STATUS_HIDDEN` / `HIDER_STATUS_FOUND` constants | `biochemeleon/registry.py:36-39` |

### 13.2 PyMOL source (API behavior)

| Claim | Citation |
|---|---|
| `cmd.save` for `.pse` routes to `get_session` | `pymol/exporting.py:782-933` (line 844 `if format in ('pse', 'psw',)`) |
| `get_session` calls `_cmd.get_session` (C-level full state capture) | `pymol/exporting.py:370-475` (line 423-425) |
| `cmd.load` for `.pse` routes to `load_pse` → `set_session` | `pymol/importing.py:635-821` (load dispatcher), `pymol/importing.py:823-848` (`load_pse`) |
| `set_session` calls `_cmd.set_session` (C-level full state restore) | `pymol/importing.py:130-175` (line 142-143) |
| Per-atom `color` is part of the `ObjectMolecule` atom struct (index 10) | `pymol/constants.py:255` (`color = 10`); atom list walked at `pymol/exporting.py:346-348` |
| Phase 3 smoke confirmed `segi='GAME'` + `b=-999.0` + atom `id` round-trip the same path | `.planning/research/PITFALLS.md` "PSE — `.pse` round-trip id/sentinel stability: RESOLVED" (line 447-451) |
| PyMOL Open Source has NO undo (backup is mandatory) | `.planning/research/PITFALLS.md` Pitfall 10 (line 270-298); `pymol/editor.py:25-36` (`undocontext` no-op stub) |
| `.pse` saves "complete PyMOL state" (per the official docstring) | `pymol/exporting.py:805-824` ("If the file extension is '.pse' ... the complete PyMOL state is always saved") |
| `cmd.iterate` exposes atom `id` as UPPERCASE `ID` | `.planning/research/PITFALLS.md` Phase 3 Resolved (line 457); `pymol/editing.py:1444-1449` |
| `cmd.iterate` does NOT expose `x`/`y`/`z` (use `iterate_state`) | `.planning/research/PITFALLS.md` Phase 3 Resolved (line 458) |
| b-factor selectors are COMPARISONS (`b < 0`), never exact (`b -999`) | `.planning/research/PITFALLS.md` Phase 3 Resolved (line 459); `biochemeleon/mutation.py:124` |
| `cmd.alter`/`iterate` with `space={'stored': ...}` (hygienic; never `space=None`) | `biochemeleon/mutation.py:80-84, 124-125`; `pymol/editing.py:59-60, 1490` |

### 13.3 Pitfalls + project context

| Claim | Citation |
|---|---|
| Pitfall 7 — `.pse` round-trips plugin state lossy; sidecar `.json` (here `.bcm`) is mandatory | `.planning/research/PITFALLS.md:184-218` |
| UX pitfall — "Timer keeps running while a Qt modal (file dialog) is open" | `.planning/research/PITFALLS.md:364` |
| Pitfall 4 — `id` stable across add/remove; `index` is not | `.planning/research/PITFALLS.md:110-131` |
| WSL/Windows runtime split (headless PyMOL via `run-conda-pymol.bat -cq`) | `AGENTS.md` Environment section |
| Architecture — `setup_state.py` + `registry.py` PURE (no `from pymol`); `backup`/`mutation` cmd-coupled; `game.py` orchestrator; `__init__.py` composition root | `AGENTS.md` Architecture section |
| Phase 7 found-mgmt dropdown + color picker + Restart + Cleanup | `.planning/phases/07-found-hider-management-restart-cleanup/07-02-SUMMARY.md`, `STATE.md` |
| Phase 8 success criterion 1 (this dimension) | `.planning/ROADMAP.md:174` |
| GAME-09, GAME-04, BTN-05 requirement IDs | `.planning/REQUIREMENTS.md:31, 49, 54` |

### 13.4 Unverified (flagged for runtime confirmation)

| Claim | Status |
|---|---|
| `.pse` preserves custom NAMED colors set by `cmd.set_color` (e.g., `'found_highlight'`) | HIGH confidence (same `_cmd.get_session` mechanism as per-atom color) but UNVERIFIED for the plugin-defined-custom-name case — Phase 8 smoke section D should assert |
| `cmd.color('found_highlight', ...)` succeeds after `cmd.load(.pse)` without a re-`cmd.set_color` | UNVERIFIED — depends on (above); smoke should verify |
| `cmd.get_color_index('found_highlight')` (or similar) returns -1 for undefined colors | UNVERIFIED — needs API check in `pymol/querying.py` |
| `QFileDialog` is modal (blocks QTimer but not `time.time()`) | HIGH confidence (Qt modal dialog contract); UNVERIFIED in the specific PyMOL Qt integration |

---

## 14. Summary Table — The Planner's Must-Haves

| Component | Action | Home | Pure? | Test |
|---|---|---|---|---|
| `HiderRegistry.reconcile_with_bcm(bcm_hiders)` | NEW method — merge `.bcm` metadata onto sentinel-rebuilt records | `biochemeleon/registry.py` | YES (stdlib + `GAME_REPS`) | `tests/test_registry.py::TestReconcileFromBcm` (12 methods) |
| `ReconcileMismatches` namedtuple | NEW — return type of `reconcile_with_bcm` | `biochemeleon/registry.py` | YES | covered by `TestReconcileFromBcm` |
| `build_bcm_dict(controller, setup, state_kind, elapsed=None)` | NEW function — assemble the top-level `.bcm` dict | `biochemeleon/persistence.py` (NEW module) | YES (no `pymol`) | `tests/test_persistence.py::TestBuildBcmDict` (7 methods) |
| `apply_bcm_dict(controller, bcm_dict)` | NEW function — set controller fields + call `reconcile_with_bcm`; refuses wrong kind/version | `biochemeleon/persistence.py` | YES | `tests/test_persistence.py::TestApplyBcmDict` (6 methods) + `TestBcmRoundTrip` (1 method) |
| `GameTab.start_countdown(self, controller, elapsed=0)` | MODIFY signature — add `elapsed` param for resume | `biochemeleon/gui_game.py:188` | N/A (Qt) | GUI checkpoint |
| `GameTab._begin_play` | MODIFY — read `_saved_elapsed`, set `_start_time = time.time() - elapsed` | `biochemeleon/gui_game.py:206` | N/A (Qt) | GUI checkpoint |
| `GameTab.start_countdown` seeds `_reveal_label` from `controller._reveal_count` | MODIFY — replace `"Reveals: 0"` with `"Reveals: %d" % controller._reveal_count` | `biochemeleon/gui_game.py:193` | N/A (Qt) | GUI checkpoint |
| Import handler | NEW method in `PluginDialog` — load `.pse` + read `.bcm` + reconstruct + reconcile + re-color + snapshot + `start_countdown(elapsed=...)` | `biochemeleon/__init__.py` (composition root) | N/A (Qt + cmd) | GUI checkpoint + headless smoke |
| Save handler | NEW method in `PluginDialog` — pause timer + capture elapsed + dialog + `cmd.save` + `build_bcm_dict` + write `.bcm` + resume timer | `biochemeleon/__init__.py` | N/A (Qt + cmd) | GUI checkpoint + headless smoke |
| `smoke/phase8_smoke.py` | NEW — sections A-J (§9.2); ~30-40 checks; pure `pymol.cmd.*` | `smoke/phase8_smoke.py` | N/A (cmd) | headless via `cmd.exe /c run-conda-pymol.bat -cq` |
| Defensive found-color re-apply loop | NEW — in import handler, after `apply_bcm_dict`, before `backup.snapshot` | `biochemeleon/__init__.py` (import handler) | N/A (cmd) | headless smoke section D + GUI checkpoint |

**Total new code:** ~50 lines in `registry.py` (reconcile_with_bcm + namedtuple), ~80 lines in `persistence.py` (build + apply + constants), ~10 lines modified in `gui_game.py` (start_countdown + _begin_play + _reveal_label), ~80 lines in `__init__.py` (save + import handlers), ~200 lines in `smoke/phase8_smoke.py`, ~150 lines in `tests/test_registry.py::TestReconcileFromBcm` + `tests/test_persistence.py`.

**Purity contract preserved:** `registry.py` stays pure (the merge takes a dict, no `from pymol`). `persistence.py` is pure (no `pymol`, no `Qt`). The cmd-coupled steps (`cmd.load`, `cmd.color`, `backup.snapshot`, `reconstruct_from_sentinels`'s injected `fetch_all_hider_ids`) live in the import handler (`__init__.py`), which is already cmd-coupled. The dependency direction is unchanged: `registry.py` ← `persistence.py` ← `__init__.py` (composition root); `game.py` ← `__init__.py`. No new dependencies on `pymol.Qt` from the pure layer.

---

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — uses the existing `registry.py` + `game.py` + `gui_game.py` + `backup.py` + `mutation.py` stack established in Phases 3-7; no new libraries.
- Reconstruction strategy: **HIGH** — sentinel-first is the only correct choice (the `.pse` is the loaded reality); `reconstruct_from_sentinels` is runtime-verified (Phase 3 smoke).
- Reconcile method: **HIGH** — pure dict-merge on `HiderRegistry`; the purity contract matches `from_dict` and `reconstruct_from_sentinels`.
- `.pse` color preservation: **HIGH** — verified in PyMOL source (`exporting.py:424` + `importing.py:130-143`); per-atom color is part of the `ObjectMolecule` atom struct serialized by `_cmd.get_session`. Custom NAMED colors (e.g., `'found_highlight'`) UNVERIFIED at runtime — flagged in §12.3.
- Timer resume: **HIGH** — straightforward `time.time() - elapsed` math; the signature change is backward-compatible.
- `_backup_name` for reloaded game: **HIGH** — snapshot-after-reconcile is the correct "original" for Cleanup; follows the Phase 3 backup contract.
- `.bcm` assembly: **HIGH** — pure helper functions in a new module; the shape reuses `registry.to_dict()` and `gui_setup.collect_state()`.
- GUI re-attachment: **HIGH** — extends the existing `start_countdown` + `_begin_play` flow; no new wizard or callback contracts.
- Edge cases: **HIGH** — all five edge cases have a clear policy (refuse/degrade/allow) backed by the reconcile method's mismatch reporting.
- Save timing: **HIGH** — capture-before-dialog is the documented PITFALLS.md "Better Approach"; the implementation is straightforward.

**Research date:** 2026-08-12
**Valid until:** 2026-09-12 (30 days — stable domain; the PyMOL API + the registry/backup contracts are settled. The only drift risk is a PyMOL version change affecting `.pse` color round-trip, which is unlikely in 30 days.)

