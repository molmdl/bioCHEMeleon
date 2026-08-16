# Phase 10 Research: Endgame & Debrief (DIFF-02 + DIFF-03)

**Researched:** 2026-08-17
**Domain:** PyMOL 2.5.0 plugin — endgame UX (win-screen stats + post-game teachable debrief) + Qt dialog patterns + cmd.show/highlight for per-rep hider visibility
**Confidence:** HIGH (all claims verified against `biochemeleon/` source + `tmp/pymol-src/modules/pymol/viewing.py` + existing Phase 4/6/7 runtime-verified patterns)

## Summary

Surface `_hint_count` + `_reveal_count` (already tracked on `GameController`, reset per round in `start()`) in the existing win `QMessageBox` via `setInformativeText` (rich text), and add a **second, sequential** debrief `QMessageBox` after the win dialog is dismissed. The debrief highlights all hiders in the viewer (fragment-aware `cmd.show` per rep — sphere/line/stick by atom `id`, cartoon/ribbon fragment by `segi GAME and resi rv1-rv2` using `endpoint_resvs`) and shows a per-rep summary explanation built from `registry.counts_by_rep()`. Defer `cleanup()` until AFTER the debrief dialog is dismissed (non-imported games); for imported games the hiders stay (the user clicks Cleanup explicitly, same as today). Reuse the existing `_on_win` 100 ms redraw-delay pattern a second time so the `cmd.show` calls land in the viewer before the modal debrief dialog blocks Qt. The win-stats dialog and the debrief dialog are TWO child `QMessageBox` instances (the `exec_` grep gate goes from 1 → 2 — both are child dialogs, allowed by AGENTS.md).

**Primary recommendation:** Two sequential modal `QMessageBox` children — (1) win dialog with `setText` celebration + `setInformativeText` stats (time/hints/reveals), then (2) debrief dialog with per-rep explanations + hiders shown in the viewer behind it; `cleanup()` runs after the debrief dismisses for non-imported games, deferred for imported games.

## DIFF-02: Win-Screen Stats (recommendation + rationale)

**Recommendation:** Extend the existing `_finish_win` `QMessageBox` (gui_game.py:307-312) — keep `setText` for the celebration headline (now including the hider count), add `setInformativeText` with a rich-text stats block. Do NOT use `setDetailedText` (plain-text-only, hidden behind a "Show Details…" button — wrong UX for a celebration).

### Exact dialog composition (DIFF-02)

```python
# In _finish_win, replacing the existing msg block (gui_game.py:307-312):
n_hiders = len(self._controller.registry.all())           # all are 'found' on win
hints = self._controller._hint_count                       # already tracked, reset per round (game.py:63)
reveals = self._controller._reveal_count                   # already tracked, reset per round (game.py:62)
msg = QtWidgets.QMessageBox(self.window())
msg.setIcon(QtWidgets.QMessageBox.Information)
msg.setWindowTitle("You win!")
msg.setText("You found all %d hiders in %d:%02d!" % (n_hiders, mins, secs))
msg.setInformativeText(
    "<b>Time:</b> %d:%02d<br><b>Hints used:</b> %d<br><b>Reveals used:</b> %d"
    % (mins, secs, hints, reveals))
msg.setWindowFlags(msg.windowFlags() | QtCore.Qt.WindowStaysOnTopHint)
msg.exec_()
```

### Rationale

- **`setInformativeText` (not `setDetailedText`, not `setText` alone):** `QMessageBox.setText` renders the headline (large, bold by Qt style); `setInformativeText` renders a secondary text block below the headline (smaller, supports rich text/HTML — Qt 5.x auto-detects HTML in both). `setDetailedText` is plain-text-only and hides behind a "Show Details…" button — wrong for a celebration screen where stats should be visible immediately. **Confidence: HIGH** (Qt 5.x QMessageBox docs; consistent with how `setText` already works at gui_game.py:310).
- **Show `0 hints, 0 reveals` (YES):** The objective explicitly calls this out as a flex. A player who won without help should SEE "Hints used: 0 / Reveals used: 0" — it's a skill signal. Always show all three stats; never conditional-hide a zero. This also keeps the dialog layout stable (no surprise reflow).
- **Hider count in the headline:** `"You found all N hiders in M:SS!"` is more informative than the current `"You found all hiders in M:SS!"` — `N` comes from `len(self._controller.registry.all())` (all are `found` on win, so `counts_by_rep` sums to `N`; `len(all())` is the simplest).
- **No new controller API needed:** `_hint_count` + `_reveal_count` are already public-by-convention attributes (game.py:32-33, reset in `start()` game.py:62-63). The GUI already reads `_reveal_count` at gui_game.py:227 (`start_countdown` sets the label). DIFF-02 just reads them again in `_finish_win`. **No game.py change for DIFF-02** — purely a gui_game.py edit.

### One dialog vs two (DIFF-02 + DIFF-03) — recommendation: TWO

The win-stats (DIFF-02) and the debrief (DIFF-03) should be **two sequential dialogs**, not one combined dialog.

| Approach | Pro | Con |
|---|---|---|
| **One combined dialog** (stats + debrief text + hiders shown) | Single click | Mixes the emotional beat ("you won!") with the learning beat ("here's where they were"); dialog text is long (stats + per-rep explanations) → wall of text; player reads explanations while still in celebration mode, not learning mode |
| **Two sequential dialogs** (win → dismiss → debrief + highlight) | Clean emotional separation; win dialog stays short (celebration + 3 stats); player transitions to "learning mode" for the debrief; matches the spec wording "After winning, all hiders are highlighted with an explanation" — "after winning" implies a sequence | Two clicks (minor) |

**Recommendation: TWO sequential dialogs.** The spec's "After winning, all hiders are highlighted with an explanation" frames DIFF-03 as a follow-up beat, not a merged panel. The two-click cost is negligible (the player just won — they're engaged). The win dialog is a quick 1-2 second celebration; the debrief dialog is the teachable moment the player lingers on. This also keeps each dialog's text short and scannable (spec: "simple, user-friendly, clear but sufficient in-game explanation").

## DIFF-03: Post-Game Debrief (flow design + per-rep explanations + presentation format)

### Post-win flow (step-by-step, replaces the tail of `_finish_win`)

The current `_finish_win` (gui_game.py:284-326) does: deactivate wizard → show win `QMessageBox` → `cleanup()` (non-imported) or skip (imported). The Phase 10 flow inserts the debrief BETWEEN the win dialog dismiss and `cleanup()`:

```
_on_win(elapsed)                                    [gui_game.py:267 — UNCHANGED]
  ├─ stop timer, cmd.refresh(), schedule _finish_win +100ms
_finish_win(elapsed)                                 [gui_game.py:284 — MODIFIED tail]
  ├─ deactivate wizard (existing, lines 299-302 — UNCHANGED)
  ├─ show WIN dialog (DIFF-02): setText celebration + setInformativeText stats
  │     msg.exec_()  →  player dismisses
  ├─ SHOW ALL HIDERS for debrief (NEW): cmd.show per-rep, fragment-aware
  ├─ cmd.refresh()  +  schedule _finish_debrief +100ms   [mirrors _on_win's redraw-delay pattern]
_finish_debrief()                                   [NEW method]
  ├─ show DEBRIEF dialog (DIFF-03): setText headline + setInformativeText per-rep rich text
  │     msg.exec_()  →  player dismisses
  ├─ cleanup() (NON-IMPORTED only — same gate as today: getattr(_is_imported, False))
  │     OR  hiders stay (IMPORTED — no cleanup; user clicks Cleanup explicitly, as today)
```

### Why the SECOND 100 ms redraw delay (between win-dialog-dismiss and debrief-dialog-appear)

The `cmd.show` calls in "SHOW ALL HIDERS" take effect immediately at the cmd layer, but the OpenGL viewer needs a redraw frame to paint them. If the debrief `QMessageBox.exec_()` (modal) runs immediately after `cmd.show`, it blocks the Qt event loop BEFORE the viewer redraws — the player sees the debrief dialog but the hiders behind it are still in their pre-debrief state (some hidden via the Phase 7 "Hide found" action). The existing `_on_win` (gui_game.py:279-282) already solves this exact problem for the last green hider: `cmd.refresh()` + `QTimer.singleShot(100, ...)`. The debrief reuses the same pattern: `cmd.refresh()` forces a redraw now, the 100 ms `singleShot` lets it land, then the modal debrief dialog blocks Qt — by which point the viewer has painted all shown hiders. The debrief dialog uses `WindowStaysOnTopHint` (like the win dialog) so it appears above the OpenGL window, but the dialog is small (a messagebox) so the highlighted hiders remain visible in the viewer around/beside it.

### "Highlight all hiders" implementation — RECOMMEND the fragment-aware per-record loop

**Recommendation:** Iterate `registry.all()` once and `cmd.show` each hider in its own rep, **fragment-aware** (cartoon/ribbon 4-tuple hiders shown by `segi GAME and resi rv1-rv2`, single-atom hiders shown by `id`). Do NOT use `cmd.show("everything", "<obj> and segi GAME")` (shows the WRONG rep on each hider — a sphere hider would also get lines/sticks/cartoon, defeating the "show how it blended" purpose). Do NOT use the by-id-only pattern from `_on_found_mgmt('show')` (gui_game.py:167-172 + `group_found_by_rep`) — it is NOT fragment-aware and would leave cartoon/ribbon fragment support atoms hidden (see Open Questions / Risk 2).

```python
def _show_all_hiders_for_debrief(self):
    """Show every registered hider in ITS rep for the post-win debrief.
    Fragment-aware: cartoon/ribbon 4-tuple hiders (endpoint_resvs set) are
    shown by their NEW resi range on chain H (segi GAME and resi rv1-rv2),
    so the whole fragment re-renders. Single-atom hiders (sphere/line/stick,
    or legacy 3-tuple cartoon) are shown by anchor id. rep=None (imported
    game with an unreconciled .bcm sidecar) is skipped — the hider stays in
    whatever rep it is currently in."""
    from pymol import cmd
    obj = self._controller.target_obj
    for rec in self._controller.registry.all():
        if rec.rep is None:
            continue  # defensive: imported game with corrupt/missing .bcm rep
        if rec.endpoint_resvs is not None:  # Phase 11 cartoon/ribbon fragment
            rv1, rv2 = rec.endpoint_resvs
            cmd.show(rec.rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))
        else:  # single-atom (sphere/line/stick, legacy 3-tuple cartoon)
            cmd.show(rec.rep, "%s and id %d" % (obj, rec.id))
```

**Why fragment-aware:** `_mark_found` (game.py:204-213) already colors fragment hiders by `segi GAME and resi rv1+1-rv2-1` (the middle), NOT by anchor id alone — a single-atom color would leave the rest of the displaced bump uncolored. The debrief show has the SAME structure: showing a fragment by anchor id alone would re-show the anchor CA but leave the support-residue + displaced-middle atoms hidden (if the player used "Hide found"). The debrief wants the WHOLE hider visible (so the player sees the full blend), so the show must scope the full `rv1-rv2` range (endpoints included — they're part of the blend). `endpoint_resvs` is the canonical field for this (registry.py:86-93; reconciled from .bcm by `reconcile_with_bcm` for imported games). **Confidence: HIGH** (verified: `insert_cartoon_segment_hider` mutation.py:694 shows by `chain H and resi new_start-new_end and segi GAME`; `_mark_found` game.py:206-210 colors by `segi GAME and resi rv1+1-rv2-1`; the debrief show by `segi GAME and resi rv1-rv2` is the full-range analog).

### Presentation format for the explanation — per-rep summary (NOT per-hider list)

**Recommendation:** A **per-rep summary** built from `registry.counts_by_rep()` (registry.py:250-270 — returns `{rep: count}` for every GAME_REP, zero-filled, skips `rep=None`). For each rep with `count > 0`, emit one bullet: `"N <rep> hider(s): <why hard to spot>"`. Do NOT build a per-hider table/list (QTableWidget) — the spec says "simple, user-friendly"; a per-rep summary is sufficient and far simpler. The hiders are already highlighted in the viewer (the player can SEE each one); the dialog text just explains the PATTERN per rep.

**Rationale:**
- The registry's `counts_by_rep()` already exists and is the canonical per-rep count source (used by Phase 4.1's `remaining_by_rep` sibling). DIFF-03 reuses it directly.
- A per-hider table (QTableWidget) would be ~10-50 rows of "(id, rep, explanation)" — overkill for a teachable debrief, and the explanation is the SAME for all hiders of a rep (a sphere hider blends the same way regardless of position). Per-rep summary is the right granularity.
- The spec's "explanation of why each was hard to spot" is satisfied by explaining each REP that has hiders (the player sees N hiders of rep X in the viewer + reads why rep-X hiders are hard). "Each" = "each kind of hider", not "each individual hider".

**Format:** `QMessageBox` with `setText` headline + `setInformativeText` rich-text bullets (HTML `<ul><li>…`). Rich text lets us bold the rep name + count for scannability. See the Qt Dialog Recommendation section.

### Imported-game path (no code duplication)

For imported games, `_finish_win` today does NOT call `cleanup()` (gui_game.py:325 — `if not getattr(self._controller, '_is_imported', False)`). The Phase 10 flow preserves this gate at the END of `_finish_debrief` (the debrief dialog's cleanup is deferred identically). So:

- **Non-imported:** win dialog → debrief dialog → `cleanup()` (restores original molecule from backup; hiders vanish; viewer back to pre-game state).
- **Imported:** win dialog → debrief dialog → hiders STAY (no cleanup; the user clicks Cleanup explicitly when done examining — same two-step restore + `cleanup_hiders` path as today, `__init__.py:774-782`).

The win-stats dialog (DIFF-02) and the debrief dialog (DIFF-03) are IDENTICAL for both paths — the only branch is the post-debrief cleanup gate. No code duplication: both paths share the same `_finish_win` + `_finish_debrief` methods; the `_is_imported` gate is a single `if` at the tail of `_finish_debrief` (mirroring the existing gate at gui_game.py:325).

**For imported games, `rec.rep` is reconciled:** `apply_bcm_dict` (persistence.py:192) calls `registry.reconcile_with_bcm(bcm_hiders)` which sets `rec.rep = bcm_rep` from the .bcm sidecar (registry.py:492). So `_show_all_hiders_for_debrief`'s `if rec.rep is None: continue` is a defensive no-op for valid imported games — the show runs normally. The `rep=None` skip only triggers for a corrupt/missing .bcm sidecar (an edge case the planner should smoke-test defensively but not over-engineer).

## Per-Rep "Why Hard to Spot" Explanations (domain-accurate text for each rep)

These are the exact explanation strings the planner should use (verified against the insertion mechanism in `mutation.py` — each explanation names the actual physical reason the hider blends). Keep each to ~2 sentences (student-friendly). The `<rep>: N hider(s)` prefix is built from `counts_by_rep()`; the explanation body is a fixed per-rep constant.

### spheres
> **spheres: N hider(s)** — A sphere hider is a single pseudoatom placed among the real atoms, with a matching element, color, and radius. In the sphere cloud every atom is a uniformly-sized ball, so a foreign ball looks identical to a real one — you find it by noticing an atom that has no chemical reason to be there, not by any visual difference.

**Domain basis:** `insert_hider` (mutation.py:38-90) places a `pseudoatom` with a plausible `elem` at a caller-supplied `[x,y,z]` inside the bounding volume; the dispatcher shows `spheres` by id (mutation.py:753). Spheres render any atom with a vdw radius (PITFALLS.md "Representation-specific"); a matching elem+color+radius ball is visually indistinguishable from a real atom.

### lines
> **lines: N hider(s)** — A line hider is a pseudoatom bonded to a real atom, rendered as a thin line. The lines view is a wireframe of bonds, so an extra atom with one bond looks like a real edge atom (a terminal H or a side-chain tip) — you find it by tracing bonds to an atom that doesn't belong to the chemistry.

**Domain basis:** `insert_line_stick_hider` (mutation.py:164-249) places a pseudoatom at `neighbor_coord + offset`, bonds it to the neighbor (same-object bond, mutation.py:244-246), copies the neighbor's elem+color (mutation.py:234-236), and shows `lines`/`sticks` by id. Lines render bonds (PITFALLS.md "Representation-specific"); a lone atom is invisible in lines (it needs a bond), which is why the hider is bonded.

### sticks
> **sticks: N hider(s)** — A stick hider is a pseudoatom bonded to a real atom, rendered as a thick stick. The sticks view is a thick-bond wireframe, so an extra bond looks like a real chemical bond — you find it by tracing the bond network to an atom that doesn't fit the molecular structure.

**Domain basis:** Same `insert_line_stick_hider` mechanism as lines, just `rep='sticks'` (thicker bond cylinders). Same blend logic; the thicker render makes the extra bond slightly more visible than lines but still camouflaged among the real thick bonds.

### cartoon
> **cartoon: N hider(s)** — A cartoon hider is a COPIED real backbone segment placed on a new chain, rendered as cartoon. The cartoon tube is drawn through consecutive C-alpha atoms, so a copied real backbone segment is valid backbone geometry and the tube renders as part of the existing cartoon. The segment's middle residues are slightly displaced to create a small bump, but the endpoints coincide with the real trace — you find it by spotting a kink that doesn't match the known fold.

**Domain basis:** `insert_cartoon_segment_hider` (mutation.py:518-696) copies a real 3-residue backbone segment from the CLEAN backup (`cmd.create(tmp, '<backup> and chain X and resi N-M and backbone')`, mutation.py:632-634), retags it to chain H + `segi GAME` + NEW resi (offset 10000, mutation.py:641-644), rigid-translates the MIDDLE atoms by a displacement vector (mutation.py:649-654 — the bump), merges single-state (mutation.py:665-668), and shows `cartoon` on the chain-H GAME fragment (mutation.py:694). The cartoon renderer draws through consecutive C-alphas (PITFALLS.md Pitfall 8 — a lone pseudoatom is INVISIBLE in cartoon; a real backbone segment IS visible); the copied real geometry is indistinguishable from the real trace except for the displaced middle. (For legacy 3-tuple cartoon hiders via `insert_cartoon_hider` — terminal extension — the explanation is the same idea: a real backbone extension at a terminus blends with the trace.)

### ribbon
> **ribbon: N hider(s)** — A ribbon hider is a copied real backbone segment on a new chain, rendered as ribbon. The ribbon is drawn through consecutive backbone atoms, so a copied real segment is valid backbone and renders as part of the existing ribbon. Like the cartoon hider, the middle is displaced to create a small bump — you find it by spotting a kink in the ribbon.

**Domain basis:** Same `insert_cartoon_segment_hider` mechanism as cartoon, just `rep='ribbon'` (mutation.py:694 routes `rep` through). Ribbon is also a polymer-trace rep (PITFALLS.md "Representation-specific"); the same copied-backbone-segment blend applies. The visual difference from cartoon is the flat-ribbon render vs the round tube — the blend mechanism is identical.

### Presentation in the debrief dialog

The debrief `setInformativeText` builds an HTML `<ul>` of bullets, one per rep with `count > 0` (in `GAME_REPS` order: lines, sticks, spheres, cartoon, ribbon — the `setup_state.GAME_REPS` order). A leading sentence frames it: `"All N hiders are now highlighted in the viewer. Here's why each kind was hard to spot:"`. Reps with `count == 0` are omitted (no bullet). `rep=None` records (corrupt imported .bcm) are skipped by `counts_by_rep` already (registry.py:267-268), so they don't appear in the debrief text either — the player just sees the reps that have hiders.

## Qt Dialog Recommendation (which dialog type + why)

**Recommendation:** Two `QMessageBox` children (win + debrief), both using `setText` + `setInformativeText` (rich text), both with `WindowStaysOnTopHint` + `self.window()` parent. Do NOT build a custom `QDialog` and do NOT use `QTableWidget`.

### Comparison

| Option | Fit for "simple, user-friendly, clear but sufficient" | exec_ gate impact | Verdict |
|---|---|---|---|
| **(a) QMessageBox setText + setInformativeText** (rich text) | Excellent — messagebox is the simplest Qt dialog; rich text gives bold + bullets; the player dismisses with OK/Enter | 1 → 2 (both child QMessageBox — ALLOWED per AGENTS.md) | **RECOMMENDED** |
| (b) Custom QDialog + QVBoxLayout + QLabel (rich text) + QPushButton | Fine, but more code for the same result; no UX advantage over QMessageBox for a text-only panel | +1 `.exec_()` on a child QDialog (allowed, but adds a 3rd exec_ hit) | Rejected — more code, no benefit |
| (c) QDialog + QTableWidget (per-hider rows) | Over-engineered; per-hider granularity is unnecessary (per-rep summary suffices); spec says "simple" | +1 `.exec_()` + a QTableWidget widget tree | Rejected — violates "simple" |

### Qt rules satisfied (verified against AGENTS.md)

- `from pymol.Qt import QtWidgets, QtCore` — already imported in gui_game.py:13. NO new `from PyQt5 import` (Pitfall-1 gate stays clean).
- Main plugin dialog stays MODELESS — only the two child `QMessageBox` use `.exec_()` (allowed child-dialog usage per AGENTS.md: "QFileDialog.exec_() / QMessageBox.exec_() on child dialogs ARE allowed").
- `exec_` grep gate: currently 1 (the existing `_finish_win` QMessageBox at gui_game.py:312). Phase 10 adds ONE more (`_finish_debrief`'s QMessageBox) → gate becomes 2. Both hits are on child QMessageBox — the gate's intent ("only on QFileDialog/QMessageBox, NEVER on the main PluginDialog/SetupTab") is preserved. The planner should re-run `grep -rnE "\.exec_\(\)" biochemeleon/` and assert exactly 2 hits, both QMessageBox.
- `WindowStaysOnTopHint` + `self.window()` parent — reuses the existing `_finish_win` Bug B fix (gui_game.py:306-311) so each dialog appears above the PyMOL OpenGL window. The viewer stays visible around the small messagebox, so the player sees the highlighted hiders behind the debrief dialog.
- `cmd.refresh()` + `QTimer.singleShot(100, ...)` — reuses the existing `_on_win` redraw-delay pattern (gui_game.py:281-282) for the debrief's pre-modal show flush. No new threading, no `time.sleep` (Pitfall 6 / existing gate).

## Cleanup-Flow Reconciliation (when cleanup runs, both paths)

**Recommendation:** `cleanup()` runs AFTER the debrief dialog is dismissed, gated by `_is_imported` exactly as today (gui_game.py:325). The ONLY change to the cleanup flow is that it moves from "after win dialog" to "after debrief dialog" — the gate logic is identical.

### Non-imported games (fresh Start, fresh puzzle Import with kind='puzzle' is imported — see below)

```
win dialog (DIFF-02) — dismiss
  → cmd.show all hiders (debrief highlight)
  → 100ms redraw delay
  → debrief dialog (DIFF-03) — dismiss
  → cleanup()  [restores original molecule from pre-game backup; hiders vanish;
                hint-orange real atoms restored to original colors;
                backup discarded; _started=False; registry reset]
```

The viewer returns to the pre-game state. The "show all hiders" was temporary — `cleanup()` reverts it (backup.restore is delete+create, which restores reps AND colors AND visibility state atom-for-atom from the pre-game snapshot).

### Imported games (Import button — `_is_imported=True`)

```
win dialog (DIFF-02) — dismiss
  → cmd.show all hiders (debrief highlight)
  → 100ms redraw delay
  → debrief dialog (DIFF-03) — dismiss
  → NO cleanup()  [hiders STAY shown; the user clicks Cleanup explicitly when done]
```

The hiders remain visible (highlighted + green) for the player to keep examining. When the user clicks Cleanup (Setup tab), the existing two-step `_on_cleanup` (init.py:774-782: `backup.restore` + `mutation.cleanup_hiders`) removes them. This matches today's imported-game behavior (gui_game.py:317-324 comment block) — the only change is the debrief inserted before the (skipped) cleanup.

### Why NOT auto-cleanup for imported games

The imported-game backup is the POST-IMPORT snapshot (WITH hiders), not the pre-game snapshot (game.py:364, import_state). Running `cleanup()` on an imported game would `backup.restore` (brings hiders back, since the backup has them) — which is wrong. The existing `_on_cleanup` (init.py:774-782) handles imported games with the explicit two-step `restore + cleanup_hiders`. Auto-cleanup after the debrief would either (a) run the wrong `cleanup()` (non-imported path) and leave hiders, or (b) run the imported two-step and remove hiders the player might want to keep examining. Deferring to the user's explicit Cleanup click (as today) is the safe, consistent choice.

### Why auto-cleanup IS right for non-imported games

The non-imported backup is the PRE-GAME snapshot (no hiders). `cleanup()` restores it → hiders vanish, viewer back to pre-game. The debrief highlight was temporary. If the player wants to re-examine, they can Restart (regenerates hiders) or re-Start. Auto-cleanup avoids leaving the viewer in a "hiders shown but game over" state that could confuse a new player ("are these still hiders? can I click them?"). The spec frames DIFF-03 as a temporary debrief ("After winning, all hiders are highlighted with an explanation") — implying the highlight is a moment, then the game ends. Auto-cleanup delivers that clean end state.

## Implementation Guidance (concrete steps for the planner, file-level)

### File-by-file changes

**`biochemeleon/setup_state.py`** (PURE — WSL-unit-testable, mirrors `format_remaining` precedent)
- Add `DEBRIEF_EXPLANATIONS` dict constant: `{rep: explanation_string}` for the 5 GAME_REPS (the body text from the Per-Rep section above, WITHOUT the `"N hider(s)"` prefix — the formatter adds that).
- Add `format_debrief_text(counts_by_rep)` pure function: takes a `{rep: count}` dict (from `registry.counts_by_rep()`), returns an HTML rich-text string — leading frame sentence + `<ul>` of bullets for reps with `count > 0` in `GAME_REPS` order, each `"<li><b>%s: %d hider(s)</b> — %s</li>" % (rep, count, DEBRIEF_EXPLANATIONS[rep])`. Empty dict → a graceful fallback string (`"All hiders are highlighted in the viewer."`).
- Unit tests in `tests/test_setup_state.py`: (1) empty dict → fallback; (2) single-rep dict → one bullet with the right rep+count+explanation; (3) all-reps dict → 5 bullets in GAME_REPS order; (4) zero-count reps omitted; (5) `rep=None` never appears (counts_by_rep guarantees this, but the formatter should not crash on a None key — defensive `if rep and count > 0`).

**`biochemeleon/gui_game.py`** (Qt + cmd — human-verify checkpoint)
- Modify `_finish_win(self, elapsed)` (lines 284-326):
  - Keep wizard deactivation (299-302) UNCHANGED.
  - Replace the win-dialog block (307-312) with the DIFF-02 composition above (setText with `%d hiders` + setInformativeText with time/hints/reveals rich text).
  - AFTER `msg.exec_()`, instead of the existing `if not _is_imported: cleanup()` block (325-326), call `self._show_all_hiders_for_debrief()` + `cmd.refresh()` + `QtCore.QTimer.singleShot(100, self._finish_debrief)`. REMOVE the inline cleanup gate from `_finish_win` (it moves to `_finish_debrief`).
- Add `_show_all_hiders_for_debrief(self)` (NEW method — the fragment-aware cmd.show loop from the DIFF-03 section above).
- Add `_finish_debrief(self)` (NEW method):
  - Build `counts = self._controller.registry.counts_by_rep()` (registry.py:250).
  - `text = format_debrief_text(counts)` (the new pure helper).
  - Show a second `QMessageBox(self.window())` with `setText("Debrief — where they were hiding")` + `setInformativeText(text)` + `WindowStaysOnTopHint` + `exec_()`.
  - After dismiss: `if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()` (the SAME gate as the old line 325, moved here).
- Imports: add `from .setup_state import format_debrief_text` to the existing `from .setup_state import format_remaining` line (gui_game.py:15).

**`biochemeleon/game.py`** — NO CHANGE for DIFF-02/03. The controller already exposes `_hint_count`, `_reveal_count`, `registry`, `target_obj`, `_is_imported`, `cleanup()`. (If a later Phase 10 plan needs a controller-side debrief helper, it can be added, but the research confirms the GUI can read everything it needs directly — no new controller API.)

**`biochemeleon/__init__.py`** — NO CHANGE for DIFF-02/03. The `_on_cleanup` / `_on_restart` paths are unaffected (the debrief's deferred cleanup uses `GameController.cleanup()` directly, same as today; imported games still rely on the explicit Cleanup button → `_on_cleanup` two-step).

### Headless smoke test (mirrors `smoke/phase6_smoke.py` / `smoke/phase4_1_smoke.py`)

Pure `pymol.cmd.*` script (NO Qt — headless-runnable via `cmd.exe /c run-conda-pymol.bat -cq`):
1. `format_debrief_text` is pure → unit-tested in WSL (no smoke needed for the text).
2. cmd-layer smoke: fetch 1ubq → start a mixed-rep game (2 spheres + 1 stick + 1 cartoon 4-tuple segment — mirrors phase4_1_smoke section 2) → mark all found (via `on_pick` or `_mark_found`) → assert `registry.counts_by_rep()` matches → call a `show_all_hiders_for_debrief`-equivalent cmd loop (extracted or inline) → assert `cmd.count_atoms("<obj> and segi GAME and rep spheres")` etc. reflect the shown reps per hider → assert cartoon fragment atoms (the full `rv1-rv2` range, NOT just the anchor id) are shown in cartoon. The smoke CANNOT test the Qt dialogs (win + debrief QMessageBox) — those are the human-verify checkpoint.
3. Human-verify checkpoint (real Windows PyMOL GUI): play a game to win → confirm win dialog shows time + hints + reveals (DIFF-02, including the 0/0 flex case) → dismiss → confirm debrief dialog appears + hiders shown in viewer (DIFF-03) → confirm per-rep explanations match the reps in the game → dismiss → confirm cleanup runs for a fresh game (viewer returns to pre-game) AND hiders stay for an imported game (then click Cleanup → two-step removes them).

### Grep gates (planner must re-run after the change)

- `grep -rnE "\.exec_\(\)" biochemeleon/` → expect **2** hits (both QMessageBox: `_finish_win` + `_finish_debrief`). Assert no hit on the main PluginDialog/SetupTab.
- `grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/` → expect 0 (no new violations; the new code uses only `pymol.Qt`).
- Pitfall-1 gate unchanged.

## Open Questions / Risks (the planner should watch for)

1. **`rep=None` for imported games with a corrupt/missing .bcm sidecar (LOW risk):** `counts_by_rep` skips `rep=None` records (registry.py:267-268), so the debrief text omits them; `_show_all_hiders_for_debrief` skips them (`if rec.rep is None: continue`). The hider stays in whatever rep it's currently in (the .pse preserved it). The player sees an unexplained hider — a minor degraded experience, not a crash. The planner should smoke-test the corrupt-.bcm edge case defensively but not over-engineer a fallback explanation. **Confidence: HIGH** that the skip is safe (verified: `counts_by_rep` + the show loop both guard `rep is None`).

2. **Pre-existing Phase 7 "Show found" action is NOT fragment-aware (MEDIUM risk, OUT OF SCOPE for Phase 10 but worth flagging):** `_on_found_mgmt('show')` (gui_game.py:165-172) uses `group_found_by_rep` (by-id only, registry.py:537-551) — for a cartoon/ribbon FRAGMENT hider (endpoint_resvs set), showing by anchor id alone re-shows the anchor CA but NOT the support-residue + displaced-middle atoms. If a player uses "Hide found" then "Show found" mid-game, a cartoon fragment's support atoms would stay hidden. This is a Phase 7 bug for the Phase 11 fragment path (Phase 7 shipped before Phase 11's fragments existed). **Phase 10's debrief `_show_all_hiders_for_debrief` is fragment-aware (correct) and does NOT share this bug.** The planner should NOT "fix" `_on_found_mgmt` as part of Phase 10 (scope creep) but SHOULD flag it for a future fix (or a quick-task). The debrief's fragment-aware show is the canonical reference implementation for that future fix.

3. **Two consecutive modal dialogs + the 100 ms redraw delay (MEDIUM risk — UX timing):** The win dialog dismiss → `cmd.show` + `cmd.refresh()` + 100 ms → debrief dialog appear sequence depends on the 100 ms being long enough for the viewer to paint the shown hiders. The existing `_on_win` uses 100 ms for the last green hider and it works (Phase 4 04-06 fix, gui_game.py:281-282). The debrief shows potentially MANY hiders (up to 50) — the redraw might take slightly longer. If the human-verify shows the hiders aren't painted when the debrief dialog appears, bump the second delay to 150-200 ms. **Recommendation: start at 100 ms (consistency with `_on_win`), verify in human-verify, bump if needed.** Do NOT make the debrief dialog modeless to "solve" this — a modeless debrief would need signal-connected cleanup-after-dismiss logic (more code) and breaks the "two-click sequence" UX (the player could click around the viewer mid-debrief, confusing the cleanup gate).

4. **Win dialog + debrief dialog order on Windows focus-stealing (LOW risk):** Both dialogs use `WindowStaysOnTopHint` + `self.window()` parent (the existing Bug B fix). With two sequential modals, the second must also appear above the OpenGL window. Verified pattern: the existing `_finish_win` already does this; `_finish_debrief` reuses the exact same flags. The 100 ms gap between them lets the first dialog fully close before the second opens (no z-order race). If the human-verify shows the debrief appearing BEHIND the OpenGL window, ensure `self.window()` is the PluginDialog (not the GameTab) — it is (gui_game.py:307 uses `self.window()`).

5. **`counts_by_rep` vs `len(registry.all())` for the win-dialog headline (LOW risk):** The win-dialog headline uses `len(self._controller.registry.all())` for the hider count (all are `found` on win, so this is the total). `counts_by_rep().values()` summed would give the same number for a non-degraded game. `len(all())` is simpler and matches the registry's source-of-truth iteration. The planner should use `len(all())` (not `sum(counts_by_rep().values())`) to avoid a discrepancy if `rep=None` records exist (they'd be in `all()` but skipped by `counts_by_rep` — the headline should count ALL hiders found, including degraded `rep=None` ones).

6. **`format_debrief_text` placement (LOW risk — planner's choice):** This research recommends `setup_state.py` (consolidates pure UI-facing formatters, mirrors `format_remaining`). An alternative is a new `biochemeleon/debrief.py` pure module (isolates the domain-education text). Both are WSL-unit-testable. The planner should pick one and be consistent — `setup_state.py` is the lower-friction choice (no new module, no new test file — add to `tests/test_setup_state.py`).

7. **Cartoon/ribbon 3-tuple legacy path (LOW risk):** Phase 11's 4-tuple path is the production path; the 3-tuple legacy `insert_cartoon_hider` (terminal extension) is kept for backward compat with `phase5_smoke.py` (mutation.py:769-774). A 3-tuple cartoon hider has `endpoint_resvs=None` (game.py:79-83 only sets `endpoint_resvs` for 4-tuple), so `_show_all_hiders_for_debrief` treats it as single-atom (shows by anchor id). For a 3-tuple terminal-extension hider, the support residue's atoms are NOT in the registry's `endpoint_resvs` — the by-id show re-shows the anchor CA only. This is the same gap as Risk 2 but for the legacy path. In production (Phase 11+ 4-tuple), this doesn't arise. The planner should smoke-test with a 4-tuple game (the production path) and not worry about the 3-tuple legacy show.

## Sources

### Primary (HIGH confidence)
- `biochemeleon/gui_game.py:267-326` — existing `_on_win` + `_finish_win` flow (the code Phase 10 modifies); `gui_game.py:165-172` — `_on_found_mgmt('show')` by-id pattern (the NOT-fragment-aware reference); `gui_game.py:307-312` — existing QMessageBox win dialog.
- `biochemeleon/game.py:62-63` — `_hint_count`/`_reveal_count` reset per round; `game.py:204-213` — `_mark_found` fragment-aware color pattern (the canonical fragment-aware reference); `game.py:215-228` — `win()` elapsed computation; `game.py:369-400` — `cleanup()` (non-imported restore-from-backup); `game.py:351` — `import_state` calls `apply_bcm_dict` (rep reconciliation).
- `biochemeleon/registry.py:86-93` — `endpoint_resvs` field; `registry.py:250-270` — `counts_by_rep()` (zero-filled GAME_REPS, skips rep=None); `registry.py:488-492` — `reconcile_with_bcm` sets `rec.rep` from .bcm; `registry.py:537-551` — `group_found_by_rep` (by-id, NOT fragment-aware).
- `biochemeleon/mutation.py:518-696` — `insert_cartoon_segment_hider` (Phase 11 4-tuple fragment; step 8 `cmd.show(rep, "chain H and resi new_start-new_end and segi GAME")` at mutation.py:694 — the fragment-aware show scope); `mutation.py:69-90` — `insert_hider` (sphere pseudoatom); `mutation.py:164-249` — `insert_line_stick_hider` (bonded pseudoatom + by-id show at 248).
- `biochemeleon/persistence.py:186-192` — `apply_bcm_dict` sets `_reveal_count`/`_hint_count`/`_found_color` + calls `reconcile_with_bcm` (rep reconciliation for imported games).
- `biochemeleon/setup_state.py:23` — `GAME_REPS` order (lines, sticks, spheres, cartoon, ribbon); `setup_state.py:418-447` — `format_remaining` (the pure-formatter precedent for `format_debrief_text`).
- `biochemeleon/__init__.py:758-789` — `_on_cleanup` (imported two-step `restore + cleanup_hiders`); `__init__.py:774` — `_is_imported` gate.
- `biochemeleon/wizard.py:90-92` — `deactivate()` (wizard teardown, already called in `_finish_win`).
- `tmp/pymol-src/modules/pymol/viewing.py:491-526` — `cmd.show(representation, selection)` signature (rep names include all GAME_REPS; selection is any PyMOL selection expression — verified `segi GAME and resi N-M` and `id X` both valid).
- `tmp/pymol-src/modules/pymol/viewing.py:1704-1722` — `cmd.refresh()` (triggers scene redraw; already used at gui_game.py:281).
- `.planning/research/PITFALLS.md` — Pitfall 8 (cartoon requires polymer trace — basis for the cartoon hider explanation), "Representation-specific" (lines/sticks render bonds — basis for line/stick explanations), Pitfall 6 (no threading for cmd.* — the 100 ms QTimer.singleShot pattern is the safe alternative).

### Secondary (MEDIUM confidence — Qt 5.x standard, not re-verified against PyMOL's bundled Qt)
- Qt 5.x QMessageBox API: `setText` + `setInformativeText` accept rich text (HTML, auto-detected); `setDetailedText` is plain-text-only and hidden behind "Show Details…". This is standard Qt 5.x behavior (QMessageBox inherits QDialog; setText/setInformativeText use QLabel which auto-detects rich text). PyMOL 2.5.0 ships Qt 5.x via `pymol.Qt`. Not re-verified against PyMOL's specific Qt build, but the existing `_finish_win` already uses `setText` (gui_game.py:310) and renders correctly; `setInformativeText` is the same QLabel mechanism.

## Metadata

**Confidence breakdown:**
- Standard stack (QMessageBox + cmd.show + QTimer.singleShot): HIGH — all three already used in the codebase (gui_game.py:307-312, mutation.py:248/694, gui_game.py:282), re-verified against PyMOL source.
- Architecture (two-dialog flow + fragment-aware show + deferred cleanup): HIGH — directly follows existing patterns (`_on_win` redraw delay, `_mark_found` fragment-awareness, `_is_imported` cleanup gate); no new architectural constructs.
- Pitfalls (modal-blocks-redraw, exec_ gate, rep=None skip, Phase 7 show-by-id gap): HIGH — each verified against existing code or flagged with a concrete mitigation.
- Per-rep domain explanations: HIGH — each explanation names the actual insertion mechanism from `mutation.py` (verified against the source, not invented).

**Research date:** 2026-08-17
**Valid until:** 2026-09-17 (30 days — stable; the codebase patterns cited are runtime-verified through Phase 11, no fast-moving dependencies).
