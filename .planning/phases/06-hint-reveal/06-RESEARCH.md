# Phase 6: Hint & Reveal - Research

**Researched:** 2026-08-10
**Domain:** PyMOL selection algebra (neighbor coloring) + Qt confirm dialogs + GameController state extension
**Confidence:** HIGH

## Summary

Phase 6 adds three Game-tab buttons (Hint, Reveal-one, Reveal-all) and a reveal counter that persists across a round. This is a **Level 1-2 research** task: the roadmap flagged Phase 6 as "standard patterns (skip deep research)", and the codebase already establishes every pattern this phase needs — `GameController` callback wiring (Phase 4), `HiderRegistry.mark_found` (Phase 3), `cmd.color('green', ...)` on found hiders (Phase 4 `on_pick`), `QMessageBox` modal child dialogs (Phase 4 `_finish_win`), and the headless smoke-test harness (Phases 3-5). The only genuinely new technical question is the **PyMOL selection operator for "neighbors of a hider"**, and that is well-trodden PyMOL ground.

Two things were verified against authoritative sources:
1. **PyMOL selection algebra** (`around`, `byres`, `neighbor`, `within`) — verified against the PyMOL 2.5.0 source (`tmp/pymol-src/modules/pymol/cmd.py:350-354`, `selecting.py:75`, `menu.py:954-968`) AND the official PyMOL Wiki "Selection Algebra" page (distance-operator comparison table). `around R` is the right operator: it returns atoms within R Å of the selection's center, **excluding the selection itself** — exactly the "color neighbors, not the hider" semantics GAME-05 requires.
2. **Qt confirm dialog** — `QMessageBox.question(parent, title, text, Yes|No) == QMessageBox.Yes` is the standard pattern, already used in PyMOL's own plugin manager (`tmp/pymol-src/modules/pymol/plugins/managergui_qt.py:22-24`) and consistent with the `_finish_win` QMessageBox pattern in `gui_game.py:132-137`.

The prior project research (`.planning/research/SUMMARY.md:148`) already locked the approach: *"Hint button (color N neighbors via `cmd.expand`/`around`); Reveal-one / Reveal-all (with confirm + reveal-count tracking)"*. This phase research confirms `around` (not `expand` — `expand` *includes* the selection; `around` *excludes* it) and fills in the integration details.

**Primary recommendation:** Add `hint()`, `reveal_one()`, `reveal_all()` methods to `GameController` (extending the established `on_pick`/`win`/`set_callbacks` pattern), a `_reveal_count` + `_hint_count` on the controller (reset in `start()`), a 4th callback `on_counts_changed` for the GUI reveal-counter label, and three buttons in `GameTab` that call the controller after showing a `QMessageBox.question` confirm dialog (for the two Reveal buttons only — Hint needs no confirm). Use `(byres (obj and id N around 5)) and not segi GAME` for the hint selection. Extract the shared mark-found-and-color logic from `on_pick` into a private `_mark_found(object, id)` helper so reveal paths reuse it.

## Standard Stack

The established libraries/APIs for this domain. **No new dependencies** — everything ships with `pymol-open-source` (PyQt5 via `pymol.Qt`) per the project constraint.

### Core

| API | Source | Purpose | Why Standard |
|-----|--------|---------|--------------|
| `sele around R` selector | `cmd.py:353`, `selecting.py:75`, [PyMOL Wiki Selection Algebra](https://pymolwiki.org/index.php/Selection_Algebra) | Atoms within R Å of `sele` center, **EXCLUDING** `sele` | The official PyMOL distance-operator table lists `around` as "includes s2: never" — i.e. it excludes the reference selection. This is exactly "color neighbors, not the hider". |
| `byres (sele)` operator | `cmd.py:350`, `menu.py:963-968` | Expand selection to whole residues | Colors full residues (not individual atoms) so the hint is a visible region. Used in PyMOL's own "residues within N A" menu entries. |
| `cmd.color(name, sele)` | Phase 4 `on_pick` (`game.py:86`) | Recolor a selection | Already used for found-hider green. Same primitive for hint-orange + reveal-green. |
| `QMessageBox.question(parent, title, text, Yes|No)` | `plugins/managergui_qt.py:22-24` | Yes/No confirm dialog | Standard Qt confirm dialog; PyMOL's own plugin manager uses this exact pattern. Returns `QMessageBox.Yes`. |
| `QMessageBox(parent)` + `exec_()` | `gui_game.py:132-137` (`_finish_win`) | Modal child dialog | Established pattern for the win dialog. AGENTS.md explicitly allows `.exec_()` on child `QMessageBox`/`QFileDialog` (only the main PluginDialog must stay modeless). |
| `HiderRegistry.all()` / `mark_found()` | `registry.py:153,200` | List/filter hiders + set status='found' | Pure, WSL-testable. `on_pick` already uses `get` + `mark_found`; reveal reuses the same. |

### Supporting

| API | Purpose | When to Use |
|-----|---------|-------------|
| `sele within R of sele2` | Atoms within R Å, **INCLUDING** `sele2` if it matches `sele` | NOT used here — `around` is the right call (excludes self). Listed only to document the rejected alternative. |
| `neighbor (sele)` | Atoms directly bonded (1-bond) to `sele`, excludes `sele` | Already used in `mutation.py:443,610` for cap/H detection. Wrong for Hint: sphere hiders have no bonds → `neighbor` returns nothing. `around` (radius-based) works for ALL rep types. |
| `sele expand R` | `sele` + atoms within R Å (always includes `sele`) | Rejected for Hint: includes the hider itself, which GAME-05 forbids. |
| `QtCore.QTimer.singleShot` | Defer a callback to the next Qt event-loop frame | Already used in `gui_game.py:107` for the win dialog. Available if a hint needs a delayed redraw, but likely unnecessary (no modal blocking). |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `around R` (radius) | `neighbor` (bonded) | `neighbor` is free (no radius guess) but returns **nothing for sphere hiders** (no bonds) and only the bonded atom for line/stick. Radius-based `around` works uniformly for all 5 reps. **Use `around`.** |
| `byres (sele around R)` (full residues) | `sele around R` (atoms only) | Atoms-only is more precise but visually scattered (a few colored atoms). Full-residue is a visible "highlight this region" blob — better UX for a hint. PyMOL's own menu offers both ("atoms within N A" vs "residues within N A"); the spec says "N atoms/residues" (either acceptable). **Recommend `byres` for visibility.** |
| Fixed radius R=5 | Configurable radius / "N nearest atoms" | PyMOL has **no "N nearest" selector** — implementing it would mean `cmd.iterate_state` + sort by distance + `id a+b+c` build (hand-rolled, O(N²)). A fixed radius is one line and works for all rep types. **Use fixed R=5 Å** (CA-CA spacing is ~3.8 Å, so 5 Å captures adjacent residues + nearby sidechains without over-highlighting). |

**Installation:** No installation — all APIs ship with PyMOL 2.5.0 open-source.

## Architecture Patterns

### Recommended additions to existing modules

```
game.py        (controller: + hint() / reveal_one() / reveal_all() / _mark_found()
                          + _reveal_count / _hint_count attrs
                          + on_counts_changed callback slot in set_callbacks)
      ↑
gui_game.py    (Qt + cmd: + Hint/Reveal-one/Reveal-all QPushButtons
                          + _reveal_count QLabel
                          + _on_counts_changed slot
                          + _confirm() helper wrapping QMessageBox.question)
      ↑
__init__.py    (composition root: NO CHANGE — buttons wire themselves
                          in GameTab.__init__; controller is duck-typed)
```

The dependency direction is unchanged: `game.py` stays the cmd-coupled orchestrator, `gui_game.py` stays Qt + lazy `pymol import cmd`, `__init__.py` wires nothing new (buttons are internal to the Game tab, like the existing timer/remaining-label).

### Pattern 1: Controller owns logic, GUI owns dialogs (established Phase 4 split)

**What:** The confirm dialog is a Qt concern → lives in `GameTab`. The coloring + mark_found + counter is logic → lives in `GameController`. The GUI calls the controller method **only after** the user confirms.

**When to use:** Every Reveal button. Hint needs no confirm (it's not a "give up" action).

**Example:**
```python
# gui_game.py — Reveal-one button slot
def _on_reveal_one_clicked(self):
    if self._controller is None or not self._controller._started:
        return  # no active game
    if self._controller._remaining() == 0:
        return  # nothing to reveal
    if not self._confirm("Reveal one hider?",
            "Give up on one random hider? This counts as a reveal use."):
        return  # user said No
    self._controller.reveal_one()
# game.py — controller method (no Qt, no dialog)
def reveal_one(self):
    hidden = [r for r in self.registry.all()
              if r.status == registry.HIDER_STATUS_HIDDEN]
    if not hidden:
        return
    import random as _r
    rec = _r.choice(hidden)
    self._mark_found(rec.id)
    self._reveal_count += 1
    self._on_counts_changed(self._hint_count, self._reveal_count)
    self._on_log("Revealed one! %d remaining" % self._remaining())
    if self._remaining() == 0:
        self.win()
```

### Pattern 2: Shared mark-found helper (refactor on_pick, not duplicate)

**What:** `on_pick` currently inlines `mark_found + cmd.color('green') + remaining + win-check`. Extract the shared part into `_mark_found(object, id)` so `reveal_one`, `reveal_all`, and `on_pick` all reuse it. The `_on_log` message differs by caller ("Found one!" vs "Revealed one!"), so the helper takes no log arg — callers log after calling it.

**When to use:** Any code path that marks a hider found + colors it green.

**Example:**
```python
# game.py
def _mark_found(self, hider_id):
    """Shared by on_pick, reveal_one, reveal_all: mark + color + rem check.
    Does NOT log (caller logs) and does NOT fire win (caller checks rem)."""
    self.registry.mark_found(self.target_obj, hider_id)
    cmd.color('green', "%s and id %s" % (self.target_obj, hider_id))

def on_pick(self, picked_id):
    rec = self.registry.get(self.target_obj, picked_id)
    if rec is None:
        self._on_log("Miss!"); return
    if rec.status == registry.HIDER_STATUS_FOUND:
        self._on_log("Already found!"); return
    self._mark_found(picked_id)
    remaining = self._remaining()
    self._on_log("Found one! %d remaining" % remaining)
    self._on_remaining_changed(remaining)
    if remaining == 0:
        self.win()
```

### Pattern 3: Counter + 4th callback (mirror set_callbacks)

**What:** Add `self._reveal_count = 0` and `self._hint_count = 0` to `GameController.__init__`, reset both in `start()`, increment in the respective methods. Add a 4th callback `on_counts_changed(hint_count, reveal_count)` to `set_callbacks` (default no-op lambda, mirroring the existing 3). The GUI connects it to a slot that updates a `QLabel("Reveals: N")`.

**When to use:** DIFF-01 (reveal counter visible across the game) + Phase 10 (win screen shows both counts).

### Anti-Patterns to Avoid

- **Calling `on_pick(hider_id)` from reveal paths to "reuse" logic.** `on_pick` logs "Found one!" and treats its arg as a *player click*. Reveal is not a click — log "Revealed one!" instead. Extract a shared helper; don't repurpose `on_pick`.
- **Putting the confirm dialog in the controller.** The controller is duck-typed to the GUI (no Qt import in `game.py`). Qt dialogs belong in `gui_game.py`. A controller that imports `pymol.Qt` breaks the architecture and the WSL unit-test stub pattern.
- **Using `cmd.color('green', "segi GAME")` for reveal-all.** Colors ALL GAME atoms green, including already-found hiders (harmless) AND support atoms (cartoon b=0 atoms — would turn the whole cartoon tube green, breaking the blend). Always color **by id**: `cmd.color('green', "%s and id %d" % (obj, rec.id))`.
- **Forgetting to reset counters in `start()`.** A second round would carry over the first round's counts. `start()` already resets `self.registry = HiderRegistry()` — add `self._reveal_count = 0; self._hint_count = 0` next to it.

## Don't Hand-Roll

Problems that look simple but already have established solutions in this codebase:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| List hidden hiders | iterate `segi GAME` + filter | `registry.all()` + `[r for r if r.status==HIDDEN]` | Registry is the single source of truth (LOOP-02). `all()` returns insertion-order records with status already tracked. |
| Mark a hider found | alter `segi`/`b` + custom flag | `registry.mark_found(obj, id)` | Sets `status='found'`; raises `KeyError` on unregistered (clean signal). Phase 3 built + tested this. |
| Color a found hider green | custom CGO / per-atom alter | `cmd.color('green', "obj and id N")` | One-liner; Phase 4 `on_pick` already uses it. |
| Yes/No confirm dialog | custom QDialog + buttons + signals | `QMessageBox.question(parent, title, text, Yes|No)` | Standard Qt; PyMOL's own plugin manager uses it (`managergui_qt.py:22`). |
| Find hider neighbors | iterate_state + sort by distance + id-list build | `(byres (obj and id N around 5)) and not segi GAME` | One selection expression; C-side neighbor search (fast); works for all rep types. PyMOL has no "N nearest" selector, so a fixed radius is the simple path — don't hand-roll distance sorting. |
| Count remaining | `cmd.count_atoms("segi GAME and not <found>")` | `self._remaining()` | Already a method (Phase 4); reads the registry, not the C-side state. |
| Detect "is a game active" | new flag + GUI sync | `self._controller._started` | Established (Phase 3); `cleanup()`/`abort_on_error()` reset it. Buttons can read it directly (duck-typed). |

**Key insight:** Every Phase 6 mechanism is a thin layer over Phase 3-4 primitives. The new code is: 3 controller methods (~30 lines), 3 button slots + 1 label + 1 confirm helper (~40 lines), 2 counter attrs + 1 callback. No new modules, no new dependencies, no architectural change.

## Common Pitfalls

### Pitfall 1: `byres` weak-priority — wrap in explicit parens

**What goes wrong:** `byres (sele around R) and not segi GAME` may parse as `byres ((sele around R) and not segi GAME)` because the PyMOL Wiki states *"All 'by'-operators have a weak priority, so `(byres S1 or S2)` is actually identical to `(byres (S1 or S2))`"*.
**Why it happens:** `byres` greedily extends its scope to the rest of the expression at the same paren level.
**How to avoid:** Wrap explicitly: **`(byres (sele around R)) and not segi GAME`**. This matches the codebase's existing defensive-paren style (`mutation.py:443` `(neighbor (%s)) and (elem H)`, `mutation.py:610` `(neighbor (%s)) and not (...)`).
**Warning signs:** Hint colors too many atoms (whole object) or the wrong atoms.

### Pitfall 2: `around` excludes the hider — but `not segi GAME` is still needed

**What goes wrong:** Assuming `around` alone suffices because it "excludes self". It excludes the *selection* (the one hider atom), but cartoon hiders have **support atoms** (the 2nd residue, `b=0`, `segi=GAME`) and there may be **other hiders** in the same object — those are NOT in the `id N` selection, so `around` *would* include them.
**Why it happens:** `around` excludes only the atoms in the selection expression, not all GAME atoms.
**How to avoid:** Always append `and not segi GAME` to exclude all GAME atoms (the hider itself + its support atoms + other hiders). Belt-and-suspenders: `around` excludes the hider atom; `not segi GAME` excludes its support atoms + other hiders.
**Warning signs:** Hint colors a neighboring hider green-orange (confusing) or colors a cartoon support residue.

### Pitfall 3: Hint colors REAL atoms permanently

**What goes wrong:** `cmd.color('orange', neighbor_sele)` colors real (non-GAME) atoms. These atoms keep the hint color for the rest of the round (and after, until recolored). `cleanup()` only removes `segi GAME` atoms — it does NOT restore real-atom colors. So a hint leaves a permanent orange stain on the structure even after the round ends.
**Why it happens:** PyMOL atom colors are persistent state; there's no auto-restore. `backup.snapshot`/`restore` copies the *geometry* — but `verify_intact` only checks count + identity (`resn,resi,name,chain,segi`), NOT color. So `restore` on failure would restore colors, but happy-path `cleanup()` (sentinel remove) does NOT.
**How to avoid:** Two options (see Open Questions): **(A) Accept-permanent-for-round** — document that hint coloring persists for the round and is reset only by starting a new round (cleanup removes hiders but real atoms keep orange). Simple, 1 line. **(B) Track + restore** — record `(id, original_color)` for each colored atom before hinting, restore on cleanup. ~15 lines, needs a list on the controller + a restore step in `cleanup()`. **Recommendation: Option A for Phase 6 MVP** (spec doesn't require restore; Phase 10 polish can add B if user testing flags it). Flag as an Open Question for the planner.
**Warning signs:** After a round with hints, the molecule has orange patches that weren't there before.

### Pitfall 4: `segi GAME` selector is case-insensitive but the sentinel value is uppercase

**What goes wrong:** Using `segi game` or `segi 'GAME'` inconsistently.
**Why it happens:** PyMOL selectors are case-insensitive but string-literal sentinels must match the stored value.
**How to avoid:** Use lowercase `segi GAME` in selections (matches `mutation.py:124,156` and `__init__.py:147` — the established style). Don't quote it.
**Warning signs:** None at runtime (case-insensitive), but consistency avoids grep-gate false positives.

### Pitfall 5: `space={'stored': ...}` hygienic dict (already established)

**What goes wrong:** Using `space=None` (default) pollutes the global `pymol.__dict__`.
**How to avoid:** Already handled in `mutation.py` — Phase 6 hint code that reads neighbor colors via `cmd.iterate` MUST use `space={'stored': lst}` (never `space=None`). AGENTS.md documents this.
**Warning signs:** State leaks between hint calls.

### Pitfall 6: Button enabled when no game / no hidden hiders

**What goes wrong:** Hint/Reveal clicked before start or after win → `registry.all()` is empty → `random.choice([])` raises `IndexError`, or `_remaining()==0` but reveal tries to mark.
**How to avoid:** Guard at the top of each controller method: `if not self._started: return` and `if self._remaining() == 0: return`. Also disable buttons in the GUI when `not _started` or `_remaining()==0`. The controller guard is the safety net (GUI can be bypassed by a fast click).
**Warning signs:** `IndexError: Cannot choose from an empty sequence` in the log.

## Code Examples

Verified patterns from official sources + the codebase:

### Hint neighbor selection (the critical new selection)

```python
# Source: PyMOL Wiki Selection Algebra (around: "includes s2: never")
#         + menu.py:963 (byres (sele around N)) + mutation.py:443 (explicit parens)
# R=5 captures adjacent residues (CA-CA ~3.8A) without over-highlighting.
HINT_RADIUS = 5.0
HINT_COLOR = 'orange'  # distinct from green=found + blend colors

def hint(self):
    """Color the residues around a random hidden hider orange (GAME-05)."""
    if not self._started:
        return
    hidden = [r for r in self.registry.all()
              if r.status == registry.HIDER_STATUS_HIDDEN]
    if not hidden:
        return
    import random as _r
    rec = _r.choice(hidden)
    # around EXCLUDES the hider atom (it's in `id N`); `not segi GAME`
    # excludes its cartoon support atoms + other hiders.
    sele = "(byres (%s and id %d around %s)) and not segi GAME" % (
        self.target_obj, rec.id, HINT_RADIUS)
    if cmd.count_atoms(sele) > 0:  # gate: skip color on empty (idempotent-safe)
        cmd.color(HINT_COLOR, sele)
    self._hint_count += 1
    self._on_counts_changed(self._hint_count, self._reveal_count)
    self._on_log("Hint: highlighted neighbors of one hider.")
```

### Reveal-one + Reveal-all (shared _mark_found helper)

```python
def _mark_found(self, hider_id):
    """Shared mark+color (no log, no win-check — callers do those)."""
    self.registry.mark_found(self.target_obj, hider_id)
    cmd.color('green', "%s and id %s" % (self.target_obj, hider_id))

def reveal_one(self):
    """Mark one random hidden hider found + green; count the reveal (GAME-06)."""
    if not self._started:
        return
    hidden = [r for r in self.registry.all()
              if r.status == registry.HIDER_STATUS_HIDDEN]
    if not hidden:
        return
    import random as _r
    rec = _r.choice(hidden)
    self._mark_found(rec.id)
    self._reveal_count += 1
    self._on_counts_changed(self._hint_count, self._reveal_count)
    remaining = self._remaining()
    self._on_log("Revealed one! %d remaining" % remaining)
    self._on_remaining_changed(remaining)
    if remaining == 0:
        self.win()

def reveal_all(self):
    """Mark all hidden hiders found + green; count reveals (GAME-07).
    Counter += number of hiders revealed (see Open Questions — recommend +N)."""
    if not self._started:
        return
    hidden = [r for r in self.registry.all()
              if r.status == registry.HIDER_STATUS_HIDDEN]
    if not hidden:
        return
    for rec in hidden:
        self._mark_found(rec.id)
    self._reveal_count += len(hidden)  # +N hiders revealed (or +1 for the action)
    self._on_counts_changed(self._hint_count, self._reveal_count)
    self._on_remaining_changed(0)
    self._on_log("Revealed all %d hiders. Game over." % len(hidden))
    self.win()  # all found -> win fires (win dialog shows)
```

### Qt confirm dialog (gui_game.py)

```python
# Source: plugins/managergui_qt.py:22-24 (PyMOL's own confirm pattern)
#         + gui_game.py:132 (self.window() top-level parent, like _finish_win)
def _confirm(self, title, text):
    """Yes/No confirm. Returns True on Yes. Uses top-level window as parent
    so the dialog appears above the PyMOL OpenGL window (same fix as
    _finish_win Bug B)."""
    btns = QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No
    return QtWidgets.QMessageBox.question(
        self.window(), title, text, btns) == QtWidgets.QMessageBox.Yes

def _on_reveal_all_clicked(self):
    if self._controller is None or not self._controller._started:
        return
    if self._controller._remaining() == 0:
        return
    if not self._confirm("Reveal all hiders?",
            "Give up and reveal ALL remaining hiders? This ends the game."):
        return
    self._controller.reveal_all()
```

### Counter callback (mirror set_callbacks)

```python
# game.py — add to set_callbacks:
def set_callbacks(self, on_log=None, on_remaining_changed=None,
                  on_win=None, on_counts_changed=None):
    self._on_log = on_log or (lambda msg: None)
    self._on_remaining_changed = on_remaining_changed or (lambda r: None)
    self._on_win = on_win or (lambda elapsed: None)
    self._on_counts_changed = on_counts_changed or (lambda h, r: None)

# gui_game.py — _begin_play registers it:
self._controller.set_callbacks(
    on_log=self._log,
    on_remaining_changed=self._update_remaining,
    on_win=self._on_win,
    on_counts_changed=self._on_counts_changed,
)

def _on_counts_changed(self, hint_count, reveal_count):
    self._reveal_label.setText("Reveals: %d" % reveal_count)
    # hint_count stored for the Phase 10 win screen; not shown in Phase 6
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `space=None` (legacy `stored.xxx`) | `space={'stored': lst}` hygienic dict | Phase 3 (2026-08) | Phase 6 hint code that reads colors via `cmd.iterate` MUST use the hygienic dict (AGENTS.md rule). |
| `mark_found` inlined in `on_pick` | Extract `_mark_found` shared helper | Phase 6 (this phase) | Reveal paths reuse it; `on_pick` calls it. No behavior change to `on_pick`. |
| 3 callbacks (`on_log/on_remaining_changed/on_win`) | 4 callbacks (+`on_counts_changed`) | Phase 6 (this phase) | Default no-op lambda preserves backward compat (existing tests/test_game_controller.py calls `set_callbacks(log,rem,win)` positionally — **WARNING: adding a 4th positional param breaks those calls**; make `on_counts_changed` keyword-only or update the tests). |

**Deprecated/outdated:**
- **`sele expand R`** for Hint: includes the hider itself → violates GAME-05. Use `around R` (excludes self).
- **`neighbor sele`** for Hint: returns nothing for sphere hiders (no bonds). Use `around R` (radius-based, works for all reps).

## Open Questions / Risks

Things the planner should decide (all LOW-MEDIUM risk; none block implementation):

1. **Hint color persistence on real atoms (MEDIUM).**
   - What we know: `cmd.color('orange', real_atom_sele)` persists; `cleanup()` removes only `segi GAME` atoms, not real-atom colors. `verify_intact` ignores color, so happy-path cleanup does NOT restore colors (failure-path `backup.restore` WOULD, via delete+create).
   - What's unclear: Should Phase 6 restore hint-colored atoms on cleanup, or accept the orange stain for the round?
   - Recommendation: **Accept-permanent-for-round (Option A)** for Phase 6 MVP. The spec doesn't require restore. Track as a Phase 10 polish item (Option B: record `(id, orig_color)` + restore step in `cleanup()`). Flag in the plan as a documented limitation.

2. **Reveal-all counter semantics (LOW).**
   - What we know: DIFF-01 says "track how many reveals were used". Reveal-one is unambiguous (+1). Reveal-all could be +1 (count the action) or +N (count the hiders revealed).
   - What's unclear: Which interpretation does the win-screen "reveals used" (Phase 10) intend?
   - Recommendation: **+N (count hiders revealed)**. Consistent with reveal-one's "+1 per hider revealed" — a reveal-all of 3 hiders is morally 3 reveals. The counter then means "total hiders revealed by give-up" regardless of button. Planner may override to +1 (action count) if the user prefers; document the choice either way.

3. **Hint radius R (LOW).**
   - What we know: CA-CA spacing ~3.8 Å; 5 Å captures adjacent residues + nearby sidechains. Too small (<3.8) misses adjacent residues; too large (>8) over-highlights.
   - What's unclear: Is 5 Å the right default? Should it scale with molecule size?
   - Recommendation: **Fixed R=5 Å** as a module constant (`HINT_RADIUS = 5.0`). Configurability is a Phase 10 polish item. The smoke test can assert the selection is non-empty + bounded.

4. **Hint target selection (LOW).**
   - What we know: Options are random hidden hider, closest-to-camera, least-recently-near, or first-registered.
   - What's unclear: Which is most useful to the player?
   - Recommendation: **Random hidden hider** (`random.choice(hidden)`). Simplest, no extra state, fair. Camera-distance would need `cmd.get_view` + iterate_state + distance math (hand-rolled, O(N)). Document as "random" in the log ("Hint: highlighted neighbors of one hider").

5. **`set_callbacks` signature change breaks existing tests (MEDIUM — planner must handle).**
   - What we know: `tests/test_game_controller.py` calls `set_callbacks(log, rem, win)` positionally (3 args). Adding a 4th positional `on_counts_changed` is fine (it defaults to None → no-op), but the existing calls won't pass it — that's OK (default no-op). The risk is if the planner makes it keyword-only or reorders.
   - Recommendation: **Append `on_counts_changed=None` as the 4th positional-or-keyword param** (after `on_win`). Existing 3-arg calls still work (4th defaults to no-op). New GUI call passes all 4. No test rewrite needed. The plan should explicitly note this backward-compat property.

6. **Hint button needs no confirm; Reveal buttons do (clarification, not a risk).**
   - Established: Hint is help (no confirm); Reveal is give-up (confirm per GAME-06/GAME-07 "asks the user to confirm"). The planner should not add a confirm to Hint.

## TDD Assessment

Which parts are testable in WSL vs headless-smoke vs human-verify:

| Component | Tier | How | Why |
|-----------|------|-----|-----|
| `GameController.hint()` logic (counter +1, callback fires, no mark_found) | **WSL unit test** | Extend `tests/test_game_controller.py`: stub `pymol`/`pymol.Qt` via `MagicMock` (existing pattern); manually populate registry; call `hint()`; assert `_hint_count==1`, `_on_counts_changed` called, `cmd.color` called with a sele containing `around`. | Pure logic + mocked cmd. Mirrors the existing `test_found`/`test_already_found` pattern. |
| `GameController.reveal_one()` logic (mark_found + counter + win-check) | **WSL unit test** | Same harness; assert `registry.get(...).status=='found'`, `_reveal_count==1`, `_on_remaining_changed` called, `win` fires when last hider. | Same as `test_found` but via `reveal_one` instead of `on_pick`. |
| `GameController.reveal_all()` logic (all marked + counter +N + win) | **WSL unit test** | Register 3 hidden; call `reveal_all()`; assert all 3 `status=='found'`, `_reveal_count==3`, `win` fires once. | Pure logic. |
| `_mark_found` shared helper (refactor of on_pick) | **WSL unit test** | Existing `test_found` still passes (behavior unchanged). Add a direct test if desired. | Refactor must not change `on_pick` behavior. |
| Counter reset in `start()` | **WSL unit test** | Set `_reveal_count=5`; call `start()` with stubbed specs (or just test the reset line); assert `_reveal_count==0`. | `start()` needs real cmd — but the reset lines can be tested by checking the attr after a mock start, OR by extracting a `_reset_counters()` helper and testing it directly. |
| Hint neighbor selection `(byres (... around 5)) and not segi GAME` | **Headless smoke** | Extend `smoke/phase4_smoke.py` (or new `phase6_smoke.py`): fetch 1ubq, start game with sphere+stick+cartoon hiders, call `gc.hint()`, assert `cmd.count_atoms("orange")` > 0 AND `cmd.count_atoms("orange and segi GAME") == 0` (no GAME atoms colored) AND the colored atoms are within 5 Å of a hider. | Needs real PyMOL selection engine — `around`/`byres` are C-side; MagicMock can't verify the selection resolves correctly. Headless via `cmd.exe /c run-conda-pymol.bat -cq` (AGENTS.md). |
| Reveal-all colors all hiders green (by id, not `segi GAME`) | **Headless smoke** | `gc.reveal_all()`; assert all hider ids are green AND no `b=0` support atoms turned green. | Verifies Pitfall-avoidance (don't color `segi GAME` en masse). |
| Confirm dialog (QMessageBox.question) | **Human-verify** | Qt dialog — cannot run headless (AGENTS.md: GUI/Qt needs real display). | Run in real Windows PyMOL; click Reveal-one/Reveal-all; confirm dialog appears, Yes proceeds, No aborts. |
| Button enable/disable (no game / no hidden) | **Human-verify** | Qt widget state. | Visual; but the controller guard (`if not _started: return`) IS unit-testable. |
| Hint color visibility (orange is distinct + visible) | **Human-verify** | Subjective visual check. | The smoke can assert "orange atoms exist"; whether it's a *good* hint is human. |

**Recommendation for the planner:**
- **WSL unit tests** (extend `tests/test_game_controller.py`): ~6-8 new tests for `hint`/`reveal_one`/`reveal_all`/`_mark_found`/counter-reset. These are the TDD RED/GREEN candidates (write failing test → implement → pass).
- **Headless smoke** (`smoke/phase6_smoke.py` or extend phase4/5): verify the `around` selection resolves + colors the right atoms + no GAME atoms colored by hint + reveal-all colors by id. ~6-8 checks. Run via `cmd.exe /c run-conda-pymol.bat -cq`.
- **Human-verify checkpoint**: confirm dialogs appear + Yes/No behavior + button enable/disable + hint orange is visible + reveal counter label updates. (Likely 1 plan task, like Phase 4 04-06.)

## Sources

### Primary (HIGH confidence)
- **PyMOL 2.5.0 source** (`tmp/pymol-src/modules/pymol/`):
  - `cmd.py:350-354` — full selector keyword list (`around`, `byres`, `neighbor`, `within`, `expand`, `near_to`, `beyond`, `gap`).
  - `selecting.py:75` — `select near142, resi 142 around 5` (canonical `around` example).
  - `menu.py:954-968` — `around` function: PyMOL's own UI uses `(sele around N)` for "atoms within N A" and `(byres (sele around N))` for "residues within N A" (confirms `byres` wrapping convention).
  - `plugins/managergui_qt.py:22-24` — `QMessageBox.question(None, 'Confirm', ..., Yes|No) == QMessageBox.Yes` (PyMOL's own confirm-dialog pattern).
- **PyMOL Wiki — Selection Algebra** (https://pymolwiki.org/index.php/Selection_Algebra):
  - Distance-operator comparison table: `around` = "includes s2: never" (excludes the reference selection); `expand` = "includes s2: always"; `within` = "includes s2: if matches s1"; `near_to` ≡ `around`.
  - "All 'by'-operators have a weak priority" → wrap `byres` in explicit parens.
- **Codebase (verified against running code)**:
  - `game.py:69-91` — `on_pick` (mark_found + cmd.color + remaining + win pattern to refactor/extend).
  - `registry.py:153,200` — `all()` + `mark_found()` (pure, reused).
  - `gui_game.py:132-137` — `_finish_win` QMessageBox pattern (top-level parent + `exec_()`).
  - `mutation.py:443,610` — `(neighbor (%s)) and not (...)` explicit-paren style (precedence defense).
  - `__init__.py:147` — `not segi GAME` exclusion pattern (established).

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md:148` — prior research locked "Hint via `cmd.expand`/`around`; Reveal with confirm + count tracking". Confirms `around` over `expand` (this research refines: `around` not `expand` because `expand` includes self).

### Tertiary (LOW confidence)
- None. All findings are primary-sourced.

## Metadata

**Confidence breakdown:**
- Standard stack (selectors + QMessageBox): **HIGH** — verified against PyMOL 2.5.0 source + official PyMOL Wiki + codebase.
- Architecture (controller methods + shared helper + counter callback): **HIGH** — direct extension of established Phase 3-4 patterns; no new architectural surface.
- Pitfalls: **HIGH** — `around`/`byres` semantics from official docs; `not segi GAME` + `space=` + lower-case-`segi` from established codebase rules; hint-color-persistence derived from `verify_intact` ignoring color (codebase fact).
- Open Questions: **LOW-MEDIUM** — design choices (color persistence, counter semantics, radius) flagged for planner; recommendations given.

**Research date:** 2026-08-10
**Valid until:** 2026-09-10 (30 days — PyMOL 2.5.0 is a fixed target; selection algebra is stable. Codebase patterns are stable unless Phase 7-8 refactor the controller, which is not planned.)
