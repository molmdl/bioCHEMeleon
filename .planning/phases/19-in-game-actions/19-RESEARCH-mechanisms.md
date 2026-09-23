# Phase 19: In-game Actions — Research (VMD MECHANISM LAYER)

**Researched:** 2026-09-24
**Domain:** VMD 1.9.3 tcl mechanism layer for hint / reveal / found-mgmt / restart / cleanup — exact VMD APIs per action, v1 (PyMOL) port deltas, verified vs NEEDS-PROBE behaviors
**Confidence:** HIGH for all probed VMD APIs (read-only headless probes run today: `tmp/p19probe/p19probe{,2,3,4,5}.tcl` + outputs `molusage.txt`, `p19out4.txt`, `p19out5.txt`) and for all v1 semantics (shipped code + phase 6/7 docs read in full). MEDIUM for headless-invisible behaviors (Tk widget rendering, real pick delivery, rep-hiding visuals — established GUI-checkpoint classes). LOW only where marked NEEDS-PROBE.

> **Companion doc:** `19-RESEARCH-integration.md` (sibling) covers the codebase-integration layer (today's line-number anchors, pre/post-18 seams, smokes/tests inventory). This doc covers the VMD MECHANISM layer: what each action needs from VMD 1.9.3, what v1 did and how it ports, and which behaviors are verified vs need a probe.

---

## Method & scope

This research mines: v1's Phase 6/7 research + summaries + shipped PyMOL code (`pymol/biochemeleon/game.py`, `gui_game.py`, `__init__.py` — read with file:line), the v2 lib mechanism layer (`game.tcl`, `hiders.tcl`, `backup.tcl`, `registry.tcl`, `mutation.tcl`, `game_logic.tcl`, `pick_bridge.tcl`, `rep_tiers.tcl` — read in full), the v2 GUI surface (`dialog.tcl`, `game_tab.tcl`, `setup_tab.tcl`), prior locked contracts (STATE.md 16-12..17.2-04, `vmd/AGENTS.md` picking/sentinel sections), and **read-only headless VMD 1.9.3 probes run today** against `1znf.pdb` (424 atoms), following the established probe idiom (`bash -ic "cd tmp/p19probe && vmd -dispdev text -e <probe>.tcl -eofexit < /dev/null"`; all probes ended `Exiting normally`). Tk 8.5 widget claims are verified against the official Tk 8.5.19 manual pages (VMD ships 8.5.6 — core Tk commands only; see Sources).

**Phase 19 targets the post-Phase-18 codebase.** Per 18-07-PLAN.md:14,39,77-79, `start_game` widens to 5-arg `{molid hider_count per_rep lock_scene per_mat}` and `game_state` widens to 5-key `{game_molid hider_count snapshot per_rep per_mat}` (restart threads per_mat as the 5th arg). Every mechanism below assumes that shape.

---

## Summary

Phase 19 is a **thin mechanism layer over already-proven v2 primitives**, exactly like v1's Phases 6/7 were a thin layer over v1's Phase 3/4 primitives. The new VMD surface reduces to:

1. **Hint = an added rep** over `(within 5.0 of (index N)) and not resname GAM` — VMD has no per-atom color, coloring IS a rep (probed end-to-end today: addrep + modstyle VDW + modcolor + modselect → exact read-back + correct count).
2. **Reveal = the existing found-flow** (`hiders::mark_found_visual` + `registry::mark_found`, game.tcl:604-605) — a revealed hider is byte-identical to a click-found hider.
3. **Found-mgmt = `mol showrep $molid <found-repidx> off/on`** on the per-tier FOUND reps only (probed: getter form `mol showrep $m $idx` reads 1/0 showstate; binary usage text: `showrep <molid> <repid> [on|off] -- Turn selected rep on or off`; NO `mol hiderep`/`mol displayrep` exist).
4. **Confirm dialogs = `tk_messageBox -type yesno`** (official Tk 8.5 docs: returns `yes`/`no`); **color picker = `tk_chooseColor -parent $w`** (official Tk 8.5 docs: returns a color name — `#rrggbb` form for custom picks — or "" on cancel).
5. **Restart = the existing `game::restart`** (game.tcl:452-466, same-count + per_rep + per_mat pass-through) and **cleanup = the existing `game::cleanup`** (game.tcl:427-436) — both exist and are smoke-proven. The genuinely new work is **button wiring + guards + counter + log kinds**, plus the 17.1-14 candidate fix (`mol off` the guard-restored original when it is not the new round's target).

The single most load-bearing finding: **`within` swallows trailing expressions** — today's probe2 reproduced the 17.2-04 hazard with a discriminator: bare `within 5 of index 0 and not resname GAM` returned **41** (trailing expr ignored — identical to raw `within 5 of index 0` = 41) while parenthesized `(within 5 of index 0) and not resname GAM` returned **38** (3 tagged GAM atoms correctly excluded). Every hint selector MUST parenthesize.

**Primary recommendation:** Add `game::hint`, `game::reveal_one`, `game::reveal_all` to `vmd/lib/game.tcl` (composition root, v1 game.py controller parity), `registry::hidden_indices` (pure accessor — the missing enumeration seam), `hiders::hide_found_tier / show_found_tier / recolor_found_tier` (name-keyed via the existing `tier_reps` dict), and `game_logic::{reveal_count,hint_count}` (pure counters, reset in `round_reset`, new log kinds `hint`/`revealed_one`/`revealed_all` with v1-verbatim lines). GUI: wire Hint/Reveal-one/Reveal-all/Restart ttk::buttons + 1 found-mgmt menu (clonerep `menubutton`+`menu` idiom — setup_tab.tcl:21 precedent) + 1 "Reveals: N" label in `game_tab::build`, with handlers guarding on `game_logic::state` + `count_remaining`, confirm via `tk_messageBox -type yesno -icon question -parent $w`, picker via `tk_chooseColor -parent $w` → `color change rgb 17 <r g b>` → `mol modcolor <found-idx> $m ColorID 17`. Also: Game-tab Restart (calls `game::restart` through the 16-14 deactivate-first pattern), Cleanup buttons (Game tab per the 16-12 defect + Setup tab per spec.md:20), and the 17.1-14 `mol off` fix inside `start_game`'s guard.

---

## 1. Per-action mechanism analysis

### A. HINT (GAME-05)

#### v1 semantics (shipped, verified — `pymol/biochemeleon/game.py:11-12, 232-272` + `06-RESEARCH.md`)

| Aspect | v1 behavior | Source |
|---|---|---|
| N value | Fixed `HINT_RADIUS = 5.0` Å (module constant; CA-CA ~3.8 Å so 5 Å captures adjacent residues) | game.py:11 |
| Granularity | **Residue** (`byres` expansion) — "full-residue is a visible 'highlight this region' blob — better UX" (06-RESEARCH.md:48) | game.py:260 |
| Color | `HINT_COLOR = 'orange'` ("distinct from green=found + blend colors", 06-RESEARCH.md:219) | game.py:12 |
| Target | **Random hidden hider**, chosen AFTER pre-filtering candidates to hiders that HAVE >=1 neighbor within radius (sparse-hider silent no-op — the 06-03 f5a2b00 fix: no count, no callback, no log when nothing would highlight) | game.py:265-268 |
| Exclusion | `and not segi GAME` excludes ALL hider atoms (the hider itself + support atoms + other hiders — 06-RESEARCH.md Pitfall 2) + `and <obj>` object-scope (the around-crosses-object fix) | game.py:259-261 |
| Repeated hints | **Accumulate** (per-atom recolors persist; multiple hint regions coexist) | game.py:269 |
| Count | `_hint_count` increments per press; reserved for Phase-22 win screen | game.py:270-271 |
| Zero remaining | Guard `if not hidden: return` → silent no-op | game.py:254-255 |
| No confirm | Hint = help, never a give-up gate (06-02-SUMMARY:32) | gui_game.py:142-147 |
| Log line | "Hint: highlighted neighbors of one hider." (verbatim) | game.py:272 |

#### v2 mechanism (probed end-to-end today — probe4)

**The coloring primitive is a REP, not per-atom color.** hiders.tcl:6-8 pins it: "VMD colors/styles per-REP, not per-atom (FEATURES.md:77) — there is NO per-atom color or style override." ROADMAP criterion 1 pins the rep mechanism: `atomselect "within 5 of index N"` + an added rep. Probed today (probe4, all rc=0, exact read-back):

```tcl
# PROBED (tmp/p19probe/p19probe4.tcl, tmp/p19probe/p19out4.txt):
mol addrep $m
set hidx [expr {[molinfo $m get numreps] - 1}]
mol modstyle $hidx $m VDW
mol modcolor $hidx $m ColorID 3            ;# PROBED orange: colorinfo rgb 3 = {1.0 0.5 0.0}
set hsel "(within 5.0 of (index $idx)) and not resname GAM"
mol modselect $hidx $m $hsel
# read-back (combined-braces molinfo form): style='VDW'
#   sel='(within 5.0 of (index 50)) and not resname GAM' color='ColorID 3' mat='Opaque'
# selection atom count = 51 — the 2 tagged fake GAM atoms were excluded correctly
```

**Selector discipline (probe2 today, the load-bearing finding):**

| Form | Result on tagged 1znf (3 GAM atoms tagged near index 0) | Verdict |
|---|---|---|
| `within 5 of index 0 and not resname GAM` (bare) | **41** == raw `within 5 of index 0` (trailing expr swallowed) | BROKEN — matches hider-adjacent GAM atoms (reveals other hiders) |
| `(within 5 of index 0) and not resname GAM` | **38** (41 − 3 GAM) | **PIN THIS FORM** |
| raw `within 5 of index 0` | 41 | the within set includes hider-adjacent GAM atoms |

This reproduces the STATE.md 17.2-04 discovery ("VMD `within` swallows trailing expressions ... occupied list silently empty") with a discriminator — the unparenthesized hint selector would color the hiders near the hinted one (revealing other hiders' positions). The `not resname GAM` conjunct excludes: the hinted hider itself, its fake-residue N/C/O/CB (residue rounds — all 5 fake atoms carry `resname GAM` even though only the CA has beta<0, mutation.tcl:541-578), and ALL other hiders — the exact v1 `not segi GAME` semantics (06-RESEARCH.md Pitfall 2), because all v2 hider atoms carry `resname GAM` (mutation.tcl:46).

**Within-0 self-inclusion (probe1):** `within 0 of index 0` matched index 0 itself — VMD's `within D of X` INCLUDES X. The `not resname GAM` conjunct excludes the hider anyway (hiders are `resname GAM`).

**Residue-granularity (v1 byres analog):** the v2 `same residue as` operator works with the parenthesized within (probe1, probed): `same residue as ((within 5 of index 0) and not resname GAM) and not resname GAM` returned **119** atoms (41 neighbors expanded to whole residues). Either atom-level (51) or residue-level (119) satisfies GAME-05's "N atoms/residues". Recommendation: **residue-level** for v1 parity (visible region blob); the residue form must ALSO be parenthesized (both the `same residue as` reference and the trailing conjunct).

**Cross-molecule scoping — structurally unnecessary in v2:** v1's critical `and <obj>` object-scope fix (the `around` operator crossed object boundaries and corrupted `_bchm_backup`, 06-03 c9c2169) has **no v2 analog needed**: VMD's `atomselect $molid "<selection>"` is molid-scoped by construction — every v2 lib proc passes the molid (hiders.tcl:204, game.tcl:324, mutation.tcl:589) and selections cannot cross molecules. The v2 backup is an on-disk PDB path (backup.tcl:40 `molinfo get filename`), not a coordinate-identical loaded molecule — nothing to corrupt. **v1's hint corruption hazard does not exist in v2.**

**Hint rep lifecycle & cleanup invariants:**
- The hint rep is added AFTER `backup::apply` (it rides on top of the scene reps), so it does not alter the round's snapshot (backup.tcl:39-50 — snapshot captured pre-mutation).
- `backup::restore` (cleanup) = `mol delete` + `mol new` + `apply` (backup.tcl:109-114; apply = clear-then-addrep, backup.tcl:72-84) → **hint reps die with the whole-molecule restore. No hint-rep tracking for cleanup is needed.** Same for `start_game`'s mid-round guard cleanup (game.tcl:158-191 → cleanup → snapshot of the restored original → mutate deletes that original again).
- The v1 wart "hint colors REAL atoms persistently; sentinel cleanup alone doesn't restore colors" (06-RESEARCH.md Pitfall 3, fixed by restore-from-backup in 06-03 c9c2169) **does not exist in v2** — the hint recolors nothing; it overlays a rep. Structural v2 improvement.
- If the planner picks design (b) (one rep per press), `mol delrep` is the removal primitive — probed (probe4 step 6): delrep removed the hint rep, numreps back to base. By name: `mol repindex $m $name` resolves before delrep (hiders.tcl:31-48 name-keyed discipline; delrep renumbers — PITFALLS.md).

**Single-rep vs accumulate (planner decision — see Open Questions Q1):**
- **(a) ONE persistent hint rep + per-press `mol modselect` re-assert** (recommended): re-issuing modselect forces the rep's cached selection to re-evaluate — the exact mechanism mark_found_visual relies on (hiders.tcl:78-85 "timestep-based re-eval only; a static molecule never re-evaluates on an atom-field change — probe F17" + MANDATORY modselect RE-ASSERT header block). Probe4 probed modselect → selection read-back exact. The changed-string variant is the same API path (modselect writes the selection → re-evaluate); the mechanism smoke should assert selection read-back changes per press.
- (b) One rep per press (v1-UX accumulation parity): N presses = N extra reps in the user's rep list. Simpler bookkeeping (restore clears all reps anyway), but pollutes the rep list and grows unbounded.

**Hint with zero remaining hiders:** guard on the hidden-index list (see B for the new `registry::hidden_indices`): empty → silent no-op, no count, no log (v1 game.py:254-255 parity). Hint with remaining>0 but NO candidate has a non-empty neighborhood: pre-filter candidates (v1 game.py:265-267 parity) → silent no-op. v2 check per candidate: `[atomselect $m "(within 5.0 of (index $idx)) and not resname GAM"] num > 0` — <=50 C-side selections per press, trivial (PITFALLS.md Pitfall 11 class: narrow selects).

**Hint channel conflicts:** the hint rep uses no atom-field channel — `user` (hider ordinals, mutation.tcl:516-517), `user2` (found flag, hiders.tcl:75-76), `user3` (tier codes, hiders.tcl:15-23) are all untouched. The hint rep's selection is read-only over `index`. The hint rep is not in `tier_reps`, so mark_found_visual's all-pairs re-assert never touches it (hiders.tcl:42-48). The hidden/found pair read-back-validated selections (hiders.tcl:152,162) are never altered.

**Pick-safety:** the hint rep overlays REAL atoms — picking in the region delivers the real atom's index → `is_hider(real) = 0` → "Miss!" (game.tcl:593). No registry interference. The hint rep is left SHOWN (no showrep interaction; `mol showrep off` is ignored in text mode anyway — phase17 smokes probe F6).

**Hint color — probed color table (probe5, `p19out5.txt`):** VMD 1.9.3 ships **33 ColorIDs** (`colorinfo num` = 33). Probed RGBs: ColorID 3 = `{1.0 0.5 0.0}` = orange (the v1 hint color), ColorID 7 = `{0.0 1.0 0.0}` = green (consistent with hiders.tcl:155-156 "ColorID 7 = green" + the 17.1-08..12 render-verified smokes). Full table probed in `p19out5.txt` (ColorIDs 0-32). **Named-color-index claims from training data were WRONG in my recall (e.g. I recalled slot 7 = silver) — the probe is authoritative; use only probed values.** Hint rep = `mol modcolor $hidx $m ColorID 3` (no table mutation needed).

### B. REVEAL-ONE / REVEAL-ALL (GAME-06/GAME-07/DIFF-01)

#### v1 semantics (shipped — game.py:274-318, gui_game.py:149-167)

| Aspect | v1 behavior | Source |
|---|---|---|
| Confirm copy | Reveal-one: title "Reveal one hider?" text "Give up on one random hider? This counts as a reveal use." Reveal-all: title "Reveal all hiders?" text "Give up and reveal ALL remaining hiders? This ends the game." | gui_game.py:154-155, 164-165 |
| Confirm plumbing | `_confirm(title, text)` → QMessageBox.question == Yes; the controller method has NO dialog (GUI owns it — 06-RESEARCH.md Pattern 1: "The confirm dialog is a Qt concern → lives in GameTab") | gui_game.py:132-137 |
| Random pick | `random.choice(hidden)` over registry records filtered status==HIDDEN | game.py:288, 308 |
| Found-flow | `_mark_found(rec.id)` shared by on_pick + both reveals (06-01 REFACTOR commit 610a2e3) — mark_found + color only; caller logs + checks win | game.py:289 |
| Reveal-one counter | `+= 1` | game.py:290 |
| Reveal-all counter | `+= len(hidden)` — "+N hiders revealed, NOT +1 for the action" (06-01-SUMMARY key-decision; 06-RESEARCH.md Open Q2 resolution) | game.py:314 |
| Reveal-all win | Loop marks all, then `self.win()` fires (all found → win dialog) | game.py:312-318 |
| Reveal-one win | Fires when remaining hits 0 (a reveal can BE the last find) | game.py:295-296 |
| Log lines | "Revealed one! %d remaining" / "Revealed all %d hiders. Game over." (verbatim) | game.py:293, 317 |
| Counter reset | `_reveal_count=0` in start() AND cleanup() AND abort_on_error() (06-03 c9c2169: game-over counter consistency) | game.py:398-399, 413-414 |
| Zero remaining | Guard `if not hidden: return` → no-op (no IndexError) | game.py:286-287 |
| Identical to a click-find? | YES — both go through `_mark_found` (green coloring via the found-marking flow). Only the log line differs. | 06-RESEARCH.md Pattern 2 |

#### v2 mechanism: REUSE THE EXISTING FOUND-FLOW (game.tcl:604-616)

A revealed hider must look identical to a click-found hider. The click found-flow is (game.tcl:604-616):

```tcl
::biochemeleon::hiders::mark_found_visual [dict get $current_state game_molid] $hit_idx
::biochemeleon::registry::mark_found $hit_idx
set rem [::biochemeleon::registry::count_remaining]
catch {{*}$_cb_log [::biochemeleon::game_logic::log_append found $rem]}
catch {{*}$_cb_remaining}
if {$rem == 0} {
    ::biochemeleon::game_logic::finish_win
    set elapsed [::biochemeleon::game_logic::timer_elapsed]
    catch {{*}$_cb_log [::biochemeleon::game_logic::log_append win "You found all [::biochemeleon::registry::count_hiders] hiders in [::biochemeleon::game_logic::format_mmss $elapsed]!"]}
    catch {{*}$_cb_win $elapsed [dict get $current_state hider_count]}
}
```

**Recommended seam: extract `game::_found_flow {idx}`** (the v1 `_mark_found` precedent, 06-01 commit 610a2e3) — visual + registry only; the caller does log/remaining/win. `on_pick` calls `_found_flow` then logs "Found one!"; `reveal_one` calls `_found_flow` then logs "Revealed one!"; `reveal_all` loops `_found_flow` over hidden indices then logs "Revealed all". This keeps the three-way guard (game.tcl:548-556) as on_pick's own pre-guard (reveal paths have their own simpler guard: state playing + stash non-empty + remaining>0).

`mark_found_visual` (hiders.tcl:220-253): sets `user2=1` on the index then re-issues modselect for ALL tracked pairs with the stored literal strings — the atom migrates its tier's hidden rep → found rep (ColorID 7 green, hiders.tcl:161). A revealed hider is byte-identical to a click-found hider. (v1 06-RESEARCH.md Pattern 2 parity.) Residue-tier hiders resolve via `_resolve_pick`'s registered CA — reveal picks the CA directly from the registry list, so no fallback needed (the fallback exists only for unregistered cartoon-bump CLICKS).

**Random pick discipline (14-01 PRNG contract):** STATE.md 14-01 pins: "All randomness tests pass an explicit seed arg (Pitfall 4 mitigation — no reliance on residual global PRNG state)" and "callers wanting reproducible randomization must pass a seed and NOT interleave `rand()` calls (global PRNG)". mutation.tcl:85-87 pins the production convention: "NO seed passed: the call continues the global PRNG stream (same convention as randomize_state; reseeding per call would correlate placements with prior rand() consumers)". **Probed today (probe1):** `expr {srand(42)}` + two `expr {rand()}` draws returned the deterministic pair 0.5245871..., 0.7354235... — srand/rand work in VMD tcl. Recommendation: a PURE helper `pick_random {indices {seed {}}}` mirroring setup_state::randomize_per_rep's exact signature convention (seed non-empty → `expr {srand($seed)}` then draw; seed empty → continue the global stream); tcltest cases pass explicit seeds. Lives in registry.tcl (pure) or game.tcl — planner decides (registry placement = tcltest-able).

**The missing enumeration seam — `registry::hidden_indices`:** the registry's exported surface (registry.tcl:29) has NO hidden-record accessor: reconstruct_from_sentinels/is_hider/mark_found/count_hiders/reset/status_of/count_remaining/remaining_by_rep/set_rep/assign_reps/register_resid_block/hider_for_resid. Reveal-one and hint both need "the list of indices with status==hidden". v1 used `registry.all()` + filter (v1 registry.py:153 `all()` + 06-RESEARCH.md Pattern 1's `[r for r in registry.all() if r.status == HIDDEN]`). v2's `_records` is a namespace-private dict (registry.tcl:20) with no accessor — the composition root cannot enumerate without one. **Add a pure proc `registry::hidden_indices {}` → list of keys whose record's status eq HIDER_STATUS_HIDDEN** (the remaining_by_rep pattern, registry.tcl:126-142). tcltest cases: empty registry → {}, all-found → {}, mixed → hidden only, count_remaining == llength of the list. This is the single new pure-layer seam Phase 19 needs. (v1's 07-01 shipped the analogous pure helpers `build_found_selection`/`group_found_by_rep` as module-level functions — the precedent.)

**Reveal-all ordering:** loop `_found_flow` per hidden index. `mark_found_visual` re-asserts ALL pairs per call (2N modselects per hider — "idempotent and ~free" at the 50-hider cap, hiders.tcl:85). The LAST call leaves rem==0 → the reveal-all caller then runs the win sequence ONCE (finish_win + win log + win_cb). finish_win ERRORS unless state playing (game_logic.tcl:189-198 double-win guard) — reveal paths must be gated on `game_logic::state` eq "playing" exactly like on_pick's state gate (game.tcl:578-581). Order matters: finish_win BEFORE reading timer_elapsed (the frozen-value contract, game.tcl:611-613).

**DIFF-01 counter placement:** recommend the `game_logic` namespace (pure layer): `variable reveal_count 0` + `variable hint_count 0` (track hints too — Phase 22's DIFF-02 needs both; v1 tracked both from Phase 6), reset in `round_reset` (game_logic.tcl:86-98 — start_round calls it), increments inside the reveal/hint procs, 0-arg getters (PULL model — matches `remaining_cb` 0-args and `update_remaining`'s pull discipline, game_tab.tcl:328-337). Phase-22 forward-compat: the win_cb stays 2-arg (16-08 contract — game_tab.tcl:186-189 registers exactly 3 callbacks); DIFF-02 reads the counters via getters — no contract change. v1 diverged (its counter lived on the controller with a 4th callback `on_counts_changed`, 06-01); v2's pull model is the smaller seam. Alternative: stash the counter in game_state (game.tcl) — but game_state is round state, not pure logic, and the 5-key shape is post-18-frozen; adding a 6th key is an unnecessary seam.

**GUI reveal label:** `reveal_text` widget-bound var + `ttk::label -textvariable` in `game_tab::build`'s status row (next to remain, game_tab.tcl:99-106). Reset to "Reveals: 0" in `start_round` step 1.5 (the 16-14 view-state reset pattern, game_tab.tcl:173-175) — closes the v1 C8 bug class (label not reset per round, 06-03 c9c2169). Update after each reveal via the getter.

**Log kinds:** game_logic::log_append's switch (game_logic.tcl:228-247) gains 3 kinds with v1-verbatim lines:
- `hint` → "Hint: highlighted neighbors of one hider."
- `revealed_one` → "Revealed one! $msg remaining" (msg = remaining)
- `revealed_all` → "Revealed all $msg hiders. Game over." (msg = count revealed)
The switch's `default {error ...}` discipline (game_logic.tcl:244-246) keeps unknown kinds a caller bug. Extend `vmd/tests/test_game_logic.test` (the existing tcltest suite). Do NOT reuse kind `found` — the lines differ ("Found one!" vs "Revealed one!") and the switch formats per kind (the v1 06-RESEARCH.md anti-pattern "Calling on_pick from reveal paths to reuse logic" applies to log reuse too).

**State-machine discipline for reveal procs (on_pick's catch pattern, game.tcl:573-581):** the whole reveal body is catch-wrapped with `set rc [catch ...]` + `rc == 1` (TCL_ERROR) — never a truthy catch test (guards exit via `return`, which carries TCL_RETURN rc==2; pick_bridge probe16). Errors are only REPORTED via `vmdcon -err`, never re-raised. Reveal procs live in game.tcl and are called by game_tab handlers — GUI never calls registry/hiders directly (the architecture direction, game_tab.tcl:10-15 VIEW-ONLY statement).

### C. FOUND-HIDER MANAGEMENT (GAME-08/DIFF-04)

#### v1 semantics (shipped — gui_game.py:66-79, 169-226, __init__.py:203-205)

| Aspect | v1 behavior | Source |
|---|---|---|
| Widget | QComboBox "Found hiders: (select)" + "Hide found"/"Show found"/"Recolor found" | gui_game.py:66-70 |
| Signal | `activated` (NOT currentIndexChanged) so index-0 placeholder doesn't fire on construction; reset to 0 after handling | gui_game.py:103-106, 205 |
| Selector | Filters by HIDER_STATUS_FOUND (status, NEVER color — the color is player-chosen/mutable) | gui_game.py:171-181 |
| Hide | `cmd.hide("everything", sele)` on the found-id selection | gui_game.py:187-188 |
| Show | per-rep `cmd.show(rep, "obj and id X+Y+Z")` via `group_found_by_rep` (each found hider re-shows in its ORIGINAL rep) | gui_game.py:189-194 |
| Recolor | `cmd.color(controller._found_color, sele)` | gui_game.py:195-196 |
| Color picker | QColorDialog.getColor() static modal; invalid = cancelled; getRgbF → `cmd.set_color('found_highlight', [r g b])` → `controller._found_color = 'found_highlight'` → auto-recolor existing found | gui_game.py:207-226 |
| Future finds | `_mark_found` uses `self._found_color` (parameterized 07-01: default 'green' preserved, legacy tests pass unchanged) | 07-01-SUMMARY:39,65 |
| Global application | ALL found hiders recolored + future finds use the new color (global, not per-hider) | 07-RESEARCH.md:249-251 |
| Tooltip copy | "After finding hiders, choose how to display them: Hide, Show, or Recolor the found hiders." / "Choose highlight color for found hiders" | gui_game.py:71-76 |

#### v2 mechanism: found-mgmt operates on the PER-TIER FOUND REPS (probed)

The v2 found-visual is per-TIER, not per-hider: each tier's found rep has selection `resname GAM and beta < 0 and user2 > 0 and user3 $code` (hiders.tcl:162). Found hiders are exactly the atoms matching the found reps. So GAME-08 maps to **rep showstate toggling on the found reps only**:

```tcl
# PROBED (tmp/p19probe/p19probe3.tcl molusage.txt + p19probe5.tcl p19out5.txt):
# usage text from the 1.9.3 binary: showrep <molid> <repid> [on|off] -- Turn selected rep on or off
# NOTE ARG ORDER: <molid> FIRST (probe3's swapped form erred 'Illegal molecule specification')
mol showrep $m $found_idx off    ;# hide this tier's found rep
mol showrep $m $found_idx on     ;# show
mol showrep $m $found_idx        ;# GETTER (no on|off arg) -> 1/0 showstate (PROBED 1->0->1 round-trip)
```

- **No `mol hiderep`/`mol displayrep` exist** (probed: both return the mol usage text rc=1 — not listed in the usage text either). `mol showrep [on|off]` is THE mechanism.
- **Why rep-level hide is CORRECT here (not a violation of the NEVER-HIDE rule):** hiders.tcl:66-71 pins "NEVER HIDE A REP" because "Hidden reps cannot be picked and do not show any graphics" (UG node140, GUI-confirmed 16-12) and pickability of UNFOUND hiders is load-bearing. The found rep contains ONLY found hiders (user2 > 0) — hiding it cannot make an unfound hider unclickable: unfound hiders live in the hidden reps (`user2 < 1`, hiders.tcl:152) which stay shown. Found hiders are already registered found — the registry's three-way guard makes re-clicks "Already found!" (game.tcl:597-599); a click passing through a hidden found rep to a real atom behind it is a "Miss!" (harmless). **Phase 19 must REWRITE this header rule as a rule-narrowing: the HIDDEN rep of every pair is never hidden; the FOUND rep may be toggled by found-mgmt.** hiders.tcl:68-69 states "NO showrep call exists in this module and neither rep is EVER hidden during play" — Phase 19's found-mgmt procs live in hiders.tcl and introduce showrep; update the header comment (the 8.6-idiom gate greps comments — STATE.md constraint 9 — so comment edits must stay gate-clean). The phase17 smokes' "NEVER mol showrep (ignored in text mode)" comments (phase17_cartoon_smoke.tcl:36,79,130; phase17_cpk_smoke.tcl:35,101,437; phase17_dynbonds_smoke.tcl:47,122,530) are per-smoke rationale notes, not lib gates — they stay valid for those smokes.
- **Headless assertion discipline (probe F6 + probe5 reconciliation):** `mol showrep off` is IGNORED IN TEXT MODE for rendering (phase17 smokes pin this — the phase17_cpk_smoke.tcl:35 note: "selection because `mol showrep off` is IGNORED in text mode -- probe") but the showSTATE is tracked: the getter form read back 1→0→1 in text mode (probe5). So a mechanism smoke CAN assert `mol showrep $m $idx` == 0 after hide / == 1 after show (state-level), and visual hiding is a GUI-checkpoint item. The phase17 render-proof idiom (Tachyon .dat) CANNOT distinguish hidden reps in text mode — do not attempt render assertions for found-mgmt.
- **Hide → show round-trip semantics:** hiding the found rep of a tier makes that tier's found hiders invisible (they no longer match the hidden rep — user2 > 0 — and the found rep is off). "Show found" re-exposes them. Byte-identical round-trip at the state level. **Interaction with subsequent finds:** after hiding found reps, a NEW find in that tier (mark_found_visual) migrates the atom to the (still hidden) found rep — the new find is invisible until "Show found". Expected behavior (the user chose hide-found); document in the plan. mark_found_visual's all-pairs modselect re-assert works on hidden reps fine (modselect is showstate-independent).
- **Per-hider vs global:** GLOBAL application (v1 parity — all found hiders + future finds). Per-hider color is NOT buildable in v2 (no per-atom color channel — hiders.tcl:6-8; per-hider would need per-hider reps, unbounded). The found-mgmt menu toggles/reads ALL tracked found pairs at once (≤ 5 tiers).
- **Residue-tier found hiders:** hiding the found rep hides the CA only (the registered atom — the CA-only found-visual design, game.tcl:600-603 "the found-visual marks the CA alone — the 5-sphere polish is explicitly NOT built"). The fake residue's N/C/O/CB (beta 0.00, user2 unset) never matched either rep — unchanged.

**DIFF-04 color picker (probed color-table facts + shipped-source verification):**

- VMD 1.9.3 ships **33 ColorIDs** (probed `colorinfo num` = 33). ColorID 3 = orange `{1.0 0.5 0.0}` (probed), ColorID 7 = green `{0.0 1.0 0.0}` (probed; consistent with hiders.tcl:155-156 "ColorID 7 = green" + the 17.1-08..12 smokes' read-backs). Full table probed in `p19out5.txt`.
- **`mol modcolor $idx $m <named-color>` is INVALID** (probed probe2: `mol modcolor $idx $m red` → `ERROR) Incorrect atom color method command 'red'`, read-back empty). modcolor takes a color METHOD + optional index: `Element`, `Name`, `ColorID 17` (probed exact read-back `'ColorID 17'`). So player-chosen RGB must go through **ColorID N + table mutation**:
  ```tcl
  # SHIPPED-SOURCE VERIFICATION (official VMD tcl):
  #   save_state.tcl:362:  puts $fildes "  color change rgb $c $rgb"   (numeric ColorID)
  #   viewmaster.tcl:411:  color change rgb $name $r $g $b             (restore_colordefs)
  #   save_state.tcl:356:  set cnum [colorinfo num] / colorinfo rgb $c (table read)
  # PROBED today (probe1): color change rgb 17 0.5 0.5 0.0 -> rc=0;
  #   colorinfo rgb 17 reads back {0.5 0.5 0.0}. Round-trip VERIFIED headlessly.
  #   (Same for ColorID 22: color change rgb 22 0.1 0.9 0.2 -> rc=0.)
  ```
- **Recommended DIFF-04 flow:** reserve **ColorID 17** (a user-slot; probed initial RGB {0.8799999952316284 0.9700000286102295 0.019999999552965164} — a distinct table entry, not a duplicate of 0-16) as the game's found-highlight slot: `color change rgb 17 <r> <g> <b>` then `mol modcolor <found-idx> $m ColorID 17` for ALL tracked found pairs. This is the direct v1 `cmd.set_color('found_highlight', [r g b])` analog (07-RESEARCH.md:224-251) with the same accepted wart: **the table mutation is global/in-session** — if anything else uses ColorID 17, it changes too. v1 accepted the identical wart (07-RESEARCH.md:251 "whether re-calling set_color updates atoms already colored ... safe approach: always re-apply cmd.color explicitly"). NEEDS-PROBE (GUI/render): whether any DEFAULT rep/method mapping references slots 17-32 — sketch in section 3. Mitigation regardless: read slot 17's initial RGB at round start (`colorinfo rgb 17`), optionally restore it at cleanup (v1 did not restore its color table either).
- **Future finds after a color change:** hiders.tcl:161 hardcodes `mol modcolor $fidx $molid ColorID 7` at pair-creation. Within a round, DIFF-04's `mol modcolor ... ColorID 17` on the found pairs persists (mark_found_visual re-asserts modSELECT only, never modcolor — hiders.tcl:245,250) → future finds in the same round use ColorID 17. Across rounds, `add_hider_reps` recreates pairs with hardcoded ColorID 7 → **recommend a namespace var `hiders::found_colorid` (default 7) read at pair-creation** (default-preserving parameterization — the v1 07-01 `_found_color` precedent verbatim, 07-01-SUMMARY:39 "default-preserving parameterization: _found_color='green' default keeps legacy behavior") so DIFF-04's choice persists across restarts; OR the game.tcl layer re-applies the current color after each `add_hider_reps` (planner decision; the parameterization is the smaller seam).
- **tk_chooseColor (official Tk 8.5 docs, chooseColor.htm):** `tk_chooseColor ?option value ...?` with `-initialcolor color`, `-parent window`, `-title titleString`; "If the user selects a color, tk_chooseColor will return the name of the color in a form acceptable to Tk_GetColor. If the user cancels the operation, both commands will return the empty string." So: `set ans [tk_chooseColor -parent $w -title "Found hider highlight" -initialcolor green]`; "" → cancelled. The returned name is typically `#rrggbb` — parse via `scan`/hex arithmetic (6 hex chars → 3 ints → /255.0). NEEDS-PROBE (GUI-only): the exact return FORM from VMD's Tk 8.5.6 on Windows (native dialog) — sketch in section 3. VMD's own reference plugins contain NO tk_chooseColor usage (grep: zero hits in vmd-ref) — ecosystem evidence is absent; official Tk docs are the verification source. GUI-only rendering remains a human-verify item (Tk doesn't load headless — 13-01 lesson).
- **tk_messageBox -type yesno (official Tk 8.5 docs, messageBox.htm):** types include `yesno` ("Displays two buttons whose symbolic names are yes and no") and `-icon question` exists; "it returns the symbolic name of the selected button". So: `set ans [tk_messageBox -parent $w -type yesno -icon question -title "Reveal one hider?" -message "Give up on one random hider? This counts as a reveal use."]`; `expr {$ans eq "yes"}` gates. `-detail string` is available for the auxiliary line (the OS de-emphasized detail line). v2 already uses `tk_messageBox -parent $w -icon info -title "You win!"` (game_tab.tcl:388-390) and reference plugins use `-type ok` (clonerep.tcl:183) — the command is ecosystem-proven; the yesno TYPE is Tk-doc-verified, GUI-only rendering.

**Widget for the found-mgmt menu (three options, evidence-ranked):**

| Option | Evidence | Tradeoff |
|---|---|---|
| **(b) ttk::menubutton / plain `menubutton` + `menu` (clonerep idiom)** — RECOMMENDED | v2-exercised: setup_tab.tcl:21 "menubutton+menu for dropdowns (the clonerep idiom)"; reference plugins clonerep.tcl:193, mergestructs.tcl:145, ramaplot.tcl:172 | Stateless entries = each menu click fires one action, no placeholder-reset dance needed (v1's `setCurrentIndex(0)` becomes unnecessary). Consistent with the tab's existing dropdowns. |
| (a) ttk::combobox | Official Tk 8.5 docs verify the widget (`-state readonly`, `-values`, `current`/`get`/`set`, `<<ComboboxSelected>>` virtual event) — but ZERO usage in the 5 reference plugins and ZERO in v2 code; ttk::scrollbar's STACK.md note ("listed but never exercised in VMD's Tk") is the caution class | Closest v1-UX parity (placeholder + reset semantics) but adds a first-exercise risk in VMD's Tk for a UI state dance that (b) avoids entirely. |
| (c) plain `tk_optionMenu` | autoionizegui.tcl:96 (ecosystem-proven) | Non-themed (plain Tk) — inconsistent with the tab's ttk surface; bound-to-global-var semantics don't fit "fire one action per selection". |

### D. RESTART / CLEANUP (GAME-10/BTN-06 + the 16-12/16-13/16-14/17.1-14 assigned items)

#### What already exists (smoke-proven — genuinely new work is wiring only)

| Mechanism | Status | Source |
|---|---|---|
| `game::restart {game_state}` — cleanup + start_game SAME hider_count + per_rep + (per_mat post-18-07) pass-through on the restored molid | EXISTS, headless-proven (phase16_restart_smoke 926a2b9/69db365; 17.1-13 capstone restart symmetry; 17.1-06 "restart per_rep pass-through symmetry") | game.tcl:452-466 |
| `game::cleanup {game_state}` — `backup::restore` (mol delete LIVE game_molid + mol new recorded original + apply reps+viewpoint) + `registry::reset` + clear stash | EXISTS (15-04; dead-original leak regression-guarded) | game.tcl:427-436; backup.tcl:109-114 |
| `start_game` SELF-GUARDING active-game auto-clean at the choke point (auto-restart with CALLER's settings; liveness remap; stale-stash catch branch) | EXISTS (16-13 95a7de4; headless 16-15; GUI 16-16 both paths PASS) | game.tcl:158-191 |
| `pick_bridge::deactivate` before a new round (GUI half) — on_start already does it (step 3.5) | EXISTS in on_start; on_win deactivates too. **Phase 19's Restart/Cleanup handlers must repeat the same ordering** | dialog.tcl:203; game_tab.tcl:365 |
| GAME-10 semantics = SAME-COUNT replay (NOT v1's re-derive-from-form) | PINNED by roadmap ("restart the game from the stored initial state") + 16-13 note ("restart's same-count semantics ... Phase 19's Restart button") | game.tcl:452-456; ROADMAP.md:226; STATE.md 16-13 |
| Timer/log/mode view reset on new round | EXISTS (16-14 start_round step 1.5) — Restart reuses start_round; Cleanup adds its own UI reset | game_tab.tcl:153-222 |
| cleanup-on-dialog-close | **DEFERRED ITEM — Phase 19 scope per 16-14** ("dialog closed mid-round" path: on_close deliberately NOT given game::cleanup) | STATE.md 16-14; dialog.tcl:92-111 |
| Setup-tab Cleanup button (BTN-06 spec'd placement) | **ABSENT — setup_tab Actions group has only Reset/Randomize/Save/Load/Start (setup_tab.tcl:236-240)** | spec.md:20 |
| Game-tab Cleanup/Restart buttons | **ABSENT — the registered 16-12 defect** ("Game tab has no Cleanup/Restart button ... Phase 19 scope") | vmd/AGENTS.md Phase-19 note; STATE.md 16-12 |

#### BTN-06 sentinel-only-selector reconciliation

The requirement text (REQUIREMENTS.md:34: "remove all game-generated representations/atoms not in the original molecule (via `resname GAM and beta < 0` sentinel, never generic filters)") maps to v2 as **role-changed** (PITFALLS.md v2 Pitfall 8: "The sentinel's role changes: in v1 it was the `remove` filter; in VMD it's the **identifier** for 'which atoms were hiders' (for marking/found-tracking), while cleanup is always 'reload original PDB'"):

1. **Cleanup = whole-molecule reload** — `game::cleanup` mol-deletes the recorded LIVE game_molid (from game_state, never a deduced molid) and reloads the RECORDED original filename (from snapshot, game.tcl:429 — backup.tcl:40 recorded `molinfo get filename` at snapshot time). "Never generic filters" in v2 = **never delete a molecule deduced by scanning (`molinfo list` + sentinel probe); always the recorded handle + recorded path.** The "reload the wrong file" failure mode (PITFALLS.md Pitfall 8) is prevented by the recorded-path contract. The 16-12-observed stacking defect class is already closed at the choke point (16-13 guard).
2. **Sentinel-identification roles preserved:** registry reconstruct (mutation.tcl:587-593 `resname $HID_RESNAME and beta < 0` — NEVER `beta < 0` alone, over-match guard at mutation.tcl:44-45), cleanup VALIDATION (post-cleanup assert: `fetch_hider_indices` on the restored original == 0 — the phase15_game smoke pattern), and found-marking targeting. The canonical selector `resname GAM and beta < 0` (pinned by the BTN-06 text) is exactly mutation.tcl:589's form.
3. **"Remove all game-generated REPRESENTATIONS"** — backup::restore's `apply` clears ALL reps (backup.tcl:72-74 clear-then-addrep) then re-adds ONLY the snapshot's reps → game reps (2N hider pairs + hint rep) removed wholesale.
4. **Hint reps + found-mgmt state:** hint reps die with the molecule (whole-molecule restore — see A). Found-mgmt showstate (hidden found reps) dies too. The game_tab UI state for found-mgmt (if the plan tracks a hidden-flag for the menu) must reset on cleanup/restart. Cleanup assertions: post-restore `molinfo $restored get numreps` == pre-start numreps + `fetch_hider_indices` == 0 + registry count_hiders == 0 (the phase15_game/phase16_restart smokes already assert this shape).

#### Game-tab Restart handler flow (recommended, mirrors on_start's proven steps)

```tcl
proc ::biochemeleon::on_restart {} {   # dialog-scope handler (next to on_start, dialog.tcl:143)
    # 1. Guards: stash non-empty + game_logic::state in {playing won}
    #    (idle/countdown = silent no-op — v1's silent guard parity, 06-02-SUMMARY:35).
    # 2. pick_bridge::deactivate (16-14 step-3.5 pattern: the bridge binds active_mol
    #    to the OLD game molid; without this, activate's idempotence guard would keep
    #    it bound to the DEAD molid and every pick on the new molecule is silently
    #    dropped — the observed 16-14 defect class).
    # 3. game_tab::stop_all_timers (defensive restart parity).
    # 4. catch-wrapped game::restart $gs (the STASHED game_state — same-count
    #    same-per_rep same-per_mat replay via the 5-arg post-18 seam; NOT the
    #    Setup form). start_game's own guard no-ops (cleanup already ran inside
    #    restart — the stash was cleared, so the fresh start_game is a clean round).
    # 5. game_tab::start_round $new_gs (round_reset + countdown + bridge at GO)
    #    + raise_tab + reset reveal_text ("Reveals: 0").
}
```

**v1→v2 Restart semantics divergence (pin this in the plan):** v1's `_on_restart` called `_on_start` (re-derived from the CURRENT Setup form — "Start a fresh round with new hiders" tooltip, gui_game.py:79; if the user edited the form mid-round, Restart used the new settings). v2's GAME-10 requirement text (REQUIREMENTS.md:63 "restart the game from the stored initial state (`mol delete` + reload original PDB + re-apply saved reps)") and the roadmap criterion 4 (ROADMAP.md:226) pin the REPLAY semantics, and 16-13 deliberately reserved "restart's same-count semantics" for this button (STATE.md 16-13; game.tcl:155-156). **v2 Restart replays the stashed round config; it does NOT re-read the Setup form.** The v1 tooltip copy "Start a fresh round with new hiders" should be REWORDED for v2 (e.g. "Restart this round from its initial state — same hider count and reps") to prevent the v1-expectation mismatch.

**Wiring note:** Restart needs BOTH the game_tab stash AND the dialog-level deactivate ordering. v1 wired restart in the composition root (__init__.py:203-204 `game_tab._restart_btn.clicked.connect(self._on_restart)`). v2's analog: dialog-scope handler `::biochemeleon::on_restart` next to `on_start` (dialog.tcl:143 rationale at 114-117: "needs setup_tab state + game_tab + game.tcl — dialog scope avoids cross-tab reach-ins"). It reads game_tab's stashed game_state via the fully-qualified namespace path (`::biochemeleon::game_tab::game_state` — the 14-03 pattern for cross-namespace reads). Cleanup likewise: `::biochemeleon::on_cleanup` (dialog scope; v1's `_on_cleanup` was composition-root too, __init__.py:203, 915-946).

#### Game-tab Cleanup handler flow (16-12 defect resolution)

```tcl
proc ::biochemeleon::on_cleanup {} {
    # 1. Guard: stash non-empty (else no-op — v1 'no game to clean up', __init__.py:923-924;
    #    cleanup() itself is idempotent but the guard avoids needless UI resets, 07-RESEARCH.md:142).
    # 2. pick_bridge::deactivate + game_tab::stop_all_timers (v1 parity: __init__.py:925-929).
    # 3. catch-wrapped game::cleanup $gs (returns the restored molid; registry::reset inside).
    # 4. game_logic::round_reset (state won/playing -> idle; log model cleared).
    # 5. UI reset: timer 0:00, remaining "Remaining: -", reveals "Reveals: 0",
    #    mode Rotate, log view cleared (v1 _on_cleanup UI reset verbatim, __init__.py:942-945).
    # 6. Where next? Raise the Setup tab (round over) — planner decision, see Open Questions.
}
```

After-win Cleanup: the stash survives a win (on_win deactivates the bridge but never calls cleanup — game_tab.tcl:355-377), so post-win Cleanup works (v1 parity: "allow cleanup after win — a second cleanup is a harmless no-op", 07-RESEARCH.md:140-141). Post-win Restart likewise (the game molid is alive; `game::restart` re-rounds it). After-win Start already works via the 16-13 guard (16-16 GUI-confirmed).

#### Setup-tab Cleanup button (BTN-06 spec'd)

Spec.md:20 pins Cleanup as Setup-tab button 6 of 7 (current v2 has 5 — BTN-05 Generate&export is Phase 20's). Add `ttk::button $f.cleanup -text "Cleanup model" -command {::biochemeleon::on_cleanup}` between Load Setup and Start (the v1 placement precedent: gui_setup.py added it "between load_btn and start_btn", 07-02-SUMMARY:90; v1's tooltip distinguished Cleanup (restore original) from Restart (new round), 07-02-SUMMARY:90). Same handler as the Game-tab Cleanup — one handler, two buttons (v1 did exactly this: one `_on_cleanup`, wired from setup_tab.cleanup_btn, __init__.py:203).

#### The 17.1-14 candidate fix — hide/deselect the restored original after guard cleanup

The finding (STATE.md 17.1-14): after a guard cleanup restoring an original that is NOT the next round's target (different-target Start mid-round), the restored original SITS IN THE VIEWER and intercepts stray picks (6 picks logged on mol=3 in round 2 before the user manually hid it via VMD's molecule list). The user's manual hide STOPPED interception — in-GUI evidence that hiding the molecule removes the pick target (VMD's pick ray hits rendered graphics; no graphics = no pick).

Verified mechanism (probed probe5 + viewmaster.tcl:220,235):
- `mol off $restored` — molecule invisible. `molinfo $restored get displayed` reads 1→0→1 (probed round-trip `mol off`/`mol on`, probe5).
- viewmaster saves/restores exactly this flag (`molinfo get displayed` at :220; `if $val { mol on $molid } else { mol off $molid }` at :235) — ecosystem-proven pattern.
- NOT `mol fix`: that pins mouse MOTION ("fix <molid> -- don't apply mouse motions", probed usage text) — it prevents rotate/translate from moving the molecule, not pickability. The interception is a pick-target problem, so `mol off` is the evidenced fix.

**Where the fix applies (scope precision):** inside `start_game`'s guard, AFTER the target-remap branch (game.tcl:179-190): if `$restored` is live AND `$restored ne $molid` (the new round targets a different molecule), `mol off $restored`. If the new round targets the restored original (same-target restart / remap branch), the restored original is mol-deleted by mutate moments later — no interception window exists (synchronous tcl; no clicks can fire between restore and delete). **The Phase-19 Restart button NEVER hits the different-target branch** (restart re-targets the restored original — game.tcl:464-465) — the fix matters for the Setup-tab Start path with a different target. Risks: (a) an `mol off`'d molecule still appears in the Setup loaded-mol menu (selecting it is legal — liveness, not visibility, gates start_game; minor UX wart, document); (b) only the guard's own `$restored` is ever hidden (never the user's molecules); (c) the user re-shows via VMD's molecule list if wanted (the exact 17.1-14 user workflow).

### E. Cross-cutting

**Locked pick contract — what hint/reveal/found-mgmt must NOT disturb (vmd/AGENTS.md picking section + pick_bridge.tcl):**

1. The delivery mechanism is `trace add variable ::vmd_pick_event write _on_event` (pick_bridge.tcl:114-116) reading globals `vmd_pick_atom` + `vmd_pick_mol` (pick_bridge.tcl:153-154), filtering molid (pick_bridge.tcl:158) and forwarding ONE index (pick_bridge.tcl:166). **Forbidden forms (16-17 probe):** `mouse mode pick 0` = QUERY; numeric `4 2` = USERPOINT; only `mouse mode pick 2` engages atom picking (pick_bridge.tcl:40-47,110). `::vmd_pick_atom_callbacks` is PHANTOM (falsified in-GUI 16-12) — never read/gate on it (pick_bridge.tcl:21-24,128-132). **Phase 19's hint/reveal/found-mgmt procs issue NO mouse-mode commands and NO trace registrations** — they are controller procs called from GUI handlers while the bridge stays untouched. The first-click `p`-press quirk (locked known behavior) is orthogonal — no Phase 19 action changes mouse state.
2. **Hidden reps cannot be picked (UG node140, GUI-confirmed 16-12)** — "Found-marking must never hide a rep containing unfound hiders" (vmd/AGENTS.md). Phase 19 honors this: found-mgmt hides ONLY found reps (which contain only user2>0 atoms); the HIDDEN reps (unfound hiders) stay shown. The hiders.tcl NEVER-HIDE rule narrows, not breaks (see C).
3. **Rep-name-keyed tracking invariant:** mark_found_visual resolves names via `mol repindex` AT USE TIME and hard-errors on -1/out-of-range (hiders.tcl:239-250). Phase 19's found-mgmt showstate toggles do NOT delrep anything — rep indices never shift (delrep renumbers, Pitfall 9) — so the name-keyed resolution is untouched. **Phase 19 must NEVER delrep a hider rep mid-round** (under hint design (a) no delreps happen at all; under design (b) hint-rep delreps are safe because hider pairs are name-keyed, but they shift higher reps' indices — prefer design (a)).
4. **The modselect re-assert invariant:** after EVERY user2 write, mark_found_visual re-issues modselect for ALL pairs with stored literal strings (hiders.tcl:78-85). Phase 19's reveal paths call mark_found_visual per hider — same discipline. Phase 19 must NOT modselect a hider pair with a CHANGED string (the stored-string contract at hiders.tcl:47-48: strings are stored precisely so they are "literally unchanged at re-assert time" — changed strings would poison the all-pairs re-assert). Phase 19's changed-string modselects happen ONLY on the hint rep (design (a)), which is not in tier_reps.
5. **user2/user3 stamp invariants the smokes assert:** found-marking writes user2 ONLY (hiders.tcl:75-76 "Found flags live ONLY in user2 — `user` is taken — tag_sentinels stores ordinals there; user3 carries tier codes"; "beta stays -999 forever" — NEVER write beta, hiders.tcl:73-76). Phase 19's hint uses NO atom-field channel (A above). DIFF-04 uses NO atom-field channel (ColorID + modcolor only). The phase17 smokes assert exact user2 partitions per tier (STATE.md 17.1-13: "exact per-tier user2 partitions (1h1f, 1h1f, 0h1f)") — reveal's user2 writes go through mark_found_visual, byte-identical to click-found.
6. **State-machine gating:** all reveal/hint paths gate on `game_logic::state` eq "playing" (on_pick's state gate, game.tcl:578-581). Stray picks during countdown/won are no-ops; stray button presses likewise. The three-way guard (unresolved/already-found/hidden, game.tcl:597-599) stays on_pick's own pre-guard; reveal/hint paths pre-filter hidden indices instead (B).
7. **Tcl 8.5 gotchas (vmd/AGENTS.md, all established):** no lmap/try (catch + foreach+lappend); brace ALL expr; `variable` ONE per line; `switch -- $kind` (game_logic.tcl:228 already does); `regexp --` for dash-starting patterns (STATE.md orchestrator W1 fix); `::tk_version` global qualifier inside procs (13-02 lesson: "info exists tk_version inside a proc checks LOCAL scope only → use ::tk_version"); `dict get` has NO 3-arg default (hider_for_resid's dict-exists guard, registry.tcl:238-244).
8. **Gates to keep zero:** 8.6-idiom gate (greps lib/gui INCLUDING comments — STATE.md constraint 9), grab-set gate, `mol ssrecalc` gate (17.2 Option-A block), `ERROR)`/`bad switch` in every log (the 15-orchestrator W1 lesson: switch-parse errors lack the `ERROR)` prefix), `Exiting normally` every run, 205/205 tcltest suites, 29/31 smokes (2 pre-existing stale-pin reds from 17.2-11, documented). New code adds tcltest cases (registry::hidden_indices, game_logic counters + 3 log kinds, pick_random seed discipline) and extends a mechanism smoke (the probe evidence above IS the assertion sketch).
9. **Won-state seam (deliberate 16-13 design):** game.tcl cannot distinguish won vs mid-round ("the game.tcl layer cannot distinguish won vs mid-round" — STATE.md 16-15, "game_logic deliberately NOT sourced" in the probe). The reveal/restart/cleanup handlers read `game_logic::state` — the GUI layer CAN distinguish (won → post-win actions allowed; playing → in-game). This is why the handlers live at dialog/game_tab scope, not inside start_game.
10. **Shared $env(TEMP) staging hazard:** the combined PDB is written to `$env(TEMP)/biochemeleon_game.pdb` (mutation.tcl:610-613) — "shared $env(TEMP) combined-PDB forbids parallel runs" (STATE.md 17.1-13 gate note). Phase 19 adds no new PDB writes; the existing hazard class stays (sequential smokes only).

## 2. v1 → v2 port deltas table

| # | Concern | v1 (PyMOL) mechanism | v2 (VMD) mechanism | Delta class |
|---|---|---|---|---|
| 1 | Hint coloring | `cmd.color('orange', sele)` — per-ATOM persistent color over real atoms | `mol addrep` + `modstyle/modcolor/modselect` — an added REP over the neighborhood | REWORKED (structural): no per-atom color channel exists (hiders.tcl:6-8) |
| 2 | Hint neighborhood selector | `(byres (obj and id N around 5)) and not segi GAME and obj` | `(same residue as ((within 5.0 of (index N)) and not resname GAM)) and not resname GAM` | PORTED with 3 gotchas: parenthesize within (swallow hazard, PROBED 41 vs 38), `resname GAM` replaces `segi GAME`, object-scope `and <obj>` ELIMINATED (molid-scoped by construction) |
| 3 | Hint object-corruption hazard | REAL — `around` crossed object boundaries, corrupted `_bchm_backup` (06-03 c9c2169) | DOES NOT EXIST — atomselect is molid-scoped; backup is an on-disk PDB | ELIMINATED |
| 4 | Hint color persistence wart | REAL — per-atom recolor persists until cleanup (06-RESEARCH.md Pitfall 3) | DOES NOT EXIST — the rep is removed by whole-molecule restore | ELIMINATED |
| 5 | Reveal found-flow | `_mark_found` = `registry.mark_found` + `cmd.color('green', "obj and id N")` | `game::_found_flow` = `hiders::mark_found_visual` (user2=1 + all-pairs modselect re-assert) + `registry::mark_found` | PORTED 1:1 (same shape, v2 visual layer) |
| 6 | Reveal confirms | `QMessageBox.question(self.window(), title, text, Yes|No)` | `tk_messageBox -parent $w -type yesno -icon question -title ... -message ...` == "yes" | PORTED (different toolkit, same semantics; Tk-doc-verified) |
| 7 | Random pick | `random.choice(hidden)` (python stdlib PRNG) | `pick_random {indices {seed {}}}` (expr srand/rand; 14-01 explicit-seed test discipline; global-stream production convention — probed) | PORTED with PRNG discipline |
| 8 | Found enumeration | `registry.all()` + status filter (v1 registry.py:153 `all()` exists) | **`registry::hidden_indices` MUST BE ADDED** (no accessor exists — the one new pure seam) | NEW SEAM |
| 9 | Reveal-all counter semantics | `+= len(hidden)` (NOT +1 per action) | same (pin the same decision; 06-01-SUMMARY key-decision) | PORTED verbatim |
| 10 | Found-mgmt widget | QComboBox + `activated` + reset-to-placeholder | menubutton+menu (clonerep idiom, v2-exercised) — stateless, no reset dance | SIMPLIFIED |
| 11 | Found-mgmt hide | `cmd.hide("everything", sele)` — per-atom rep visibility | `mol showrep $m $found_idx off` — per-REP visibility on per-tier found reps | REWORKED (rep-level, tier-granular — the v2 found-visual is per-tier) |
| 12 | Found-mgmt show per-rep | `group_found_by_rep` → per-rep `cmd.show` | nothing needed — the found rep ALREADY carries the per-tier style (hiders.tcl:160-163) | SIMPLIFIED (per-tier, not per-hider) |
| 13 | DIFF-04 picker | QColorDialog.getColor() → getRgbF → `cmd.set_color('found_highlight', [r g b])` | tk_chooseColor -parent $w → parse `#rrggbb` → `color change rgb 17 <r g b>` (shipped-source form: save_state.tcl:362, viewmaster.tcl:411) | PORTED (slot 17 = v1's named-color analog; same global-mutation wart accepted) |
| 14 | DIFF-04 future finds | `_mark_found` reads `self._found_color` | recommend `hiders::found_colorid` (default 7) read at pair-creation (07-01 default-preserving precedent) | NEW SEAM (small) |
| 15 | Restart semantics | `_on_restart` → `_on_start` (re-derived from the CURRENT Setup form) | `game::restart $gs` (same-count same-per_rep same-per_mat REPLAY — pinned by roadmap GAME-10 text + 16-13) | DELIBERATE DIVERGENCE (16-13; reword the v1 tooltip) |
| 16 | Restart new-round plumbing | wizard deactivate + timer stop + `_on_start` | pick_bridge::deactivate + stop_all_timers + game::restart + start_round (16-14 pattern) | PORTED |
| 17 | Cleanup | `backup.restore` (delete+create two-step from in-memory backup) + counters reset | `game::cleanup` (backup::restore = mol delete + mol new recorded original + apply) + registry::reset + stash clear | PORTED (v2's restore is file-based) |
| 18 | Cleanup placement | Setup-tab button 6 of 7 + composition-root handler | same (setup_tab.tcl:236-240 +5 more; add between Load and Start) + Game-tab button (16-12 defect) | PORTED + ADDED |
| 19 | Confirm copy | "Give up on one random hider? This counts as a reveal use." / "Give up and reveal ALL remaining hiders? This ends the game." | same copy verbatim (tk_messageBox -message/-detail) | PORTED verbatim |
| 20 | Counter UX | "Reveals: %d" QLabel + on_counts_changed 4th callback | "Reveals: N" ttk::label + PULL (getter) — no set_callbacks contract change | SIMPLIFIED |
| 21 | Log lines | "Hint: highlighted neighbors of one hider." / "Revealed one! %d remaining" / "Revealed all %d hiders. Game over." | same verbatim via 3 new game_logic log kinds | PORTED verbatim |
| 22 | Guard copy for cleanup UI reset | log cleared + timer/remaining/reveals labels reset | same (start_round step-1.5 + on_cleanup UI reset) | PORTED |

## 3. Verified vs NEEDS-PROBE table (with probe sketches)

### VERIFIED (probed today or shipped-source-cited — planner can pin assertions)

| # | Behavior | How verified | Cite |
|---|---|---|---|
| V1 | Hint rep end-to-end: addrep + modstyle VDW + modcolor ColorID 3 + modselect `(within 5.0 of (index N)) and not resname GAM` → exact read-back, correct count (51), 2 GAM atoms excluded | probe4 rc=0 exact read-back | tmp/p19probe/p19out4.txt |
| V2 | `within` swallows trailing expressions: bare form == raw count (41); parenthesized form correctly excludes (38) | probe2 with tagged GAM discriminator | STATE.md 17.2-04 (pre-verified); probe2 reproduces |
| V3 | `within 0 of index 0` INCLUDES the reference atom | probe1 formD | tmp/p19probe (probe1) |
| V4 | `same residue as ((within 5 of index 0) and not resname GAM)` expands residues (119) | probe1 formC | probe1 |
| V5 | Color table: 33 ColorIDs; slot 3 = orange {1.0 0.5 0.0}; slot 7 = green {0.0 1.0 0.0}; full table captured | probe5 `colorinfo num` + `colorinfo rgb $c` | tmp/p19probe/p19out5.txt |
| V6 | `color change rgb 17 <r g b>` round-trips (rc=0; colorinfo rgb 17 reads back) — slots 17 and 22 both probed | probe1 | probe1 |
| V7 | `mol modcolor $idx $m red` INVALID (ERROR) Incorrect atom color method command 'red') — modcolor takes METHOD + index only | probe2 negative test | probe2 |
| V8 | `mol showrep <molid> <repid> [on|off]` exists (binary usage text); getter form (no arg) returns 1/0 showstate with round-trip | probe3 usage text + probe5 getter round-trip | tmp/p19probe/molusage.txt:52,119; p19out5.txt |
| V9 | NO `mol hiderep`/`mol displayrep` subcommands exist | probe3 (both → mol usage text rc=1) | molusage.txt:69,131 |
| V10 | `molinfo $m get displayed` + `mol off`/`mol on` round-trip (1→0→1) — the 17.1-14 fix mechanism | probe5 | p19out5.txt |
| V11 | `mol delrep` removes a rep (hint-rep cleanup analog) | probe4 step 6 | p19out4.txt |
| V12 | `expr {srand(42)}` + `expr {rand()}` deterministic draws in VMD tcl | probe1 | probe1 |
| V13 | Combined-braces molinfo read-back works for an off-state rep (`molinfo get "{rep 0}"` returned 'Lines' after showrep off) | probe3 | molusage.txt:65-68 |
| V14 | tk_chooseColor exists in core Tk 8.5 with -initialcolor/-parent/-title; returns color name or "" on cancel | official Tk 8.5.19 manual (tcl-lang.org) | Sources |
| V15 | tk_messageBox -type yesno returns yes/no; -icon question; -detail exists | official Tk 8.5.19 manual | Sources |
| V16 | ttk::combobox exists in Tk 8.5 ttk (readonly state, values, <<ComboboxSelected>>) — for the dropdown option (a) | official Tk 8.5.19 manual | Sources |
| V17 | `color change rgb <colorid> <r g b>` is the shipped VMD color-definition mutation form (numeric ColorID) | save_state.tcl:362 + viewmaster.tcl:411 | shipped sources |
| V18 | Found-flow marks found byte-identically to clicks (user2=1 + all-pairs re-assert) — reveal reuses it | code-read + smoke record (17.1-13 found-partitions) | game.tcl:604-605; hiders.tcl:220-253 |
| V19 | game::restart/cleanup exist with same-count/replay semantics + stash clearing | code-read + smokes (phase16_restart PASS; 17.1-13 restart symmetry) | game.tcl:427-466 |
| V20 | `mol fix` is a motion-level pin, not pickability ("don't apply mouse motions") | probe3 usage text | molusage.txt:23 |

### NEEDS-PROBE (headless-invisible or first-exercise — each with a sketch)

| # | Behavior | Why not headless-verified | Probe sketch |
|---|---|---|---|
| P1 | **tk_chooseColor return FORM from VMD's Tk 8.5.6 on Windows** (`#rrggbb` vs named) | Tk doesn't load in text mode (13-01); zero ecosystem usage in vmd-ref | GUI session: `puts [tk_chooseColor -title t]` from the VMD console with a custom-picked color → capture the exact string. Defensive plan code: accept any Tk_GetColor form — if it starts with `#` and llength==1, parse 6 hex; else `colorinfo rgb` lookup by name... actually simpler: defensive parse `scan $ans "#%2x%2x%2x" r g b` in catch; non-parse → fall back to the pre-change color |
| P2 | Whether any DEFAULT rep/method mapping references ColorIDs 17-32 (the DIFF-04 slot-collision risk) | requires a render visual check | Headless Tachyon idiom (17.1-08..12): fresh session, default Lines scene on 1znf, `color change rgb 17 1 0 0` → render .dat → compare FCylinder/sphere color tokens against a baseline render with slot 17 untouched; any salmon-like token shift = collision. If collision: use slot 32 (probed distinct initial {0.9599999785423279 0.7200000286102295 0.0}) and repeat |
| P3 | The changed-string `mol modselect` re-evaluation on a rep ADDED AFTER the modselect (hint design (a) per-press re-assert) | same API path as mark_found_visual's unchanged-string re-assert (probe F17), but the changed-string variant is unexercised in-repo | Headless: fresh mol, addrep + modselect sel-A → read back; modselect sel-B (different string) → read back; assert read-back == sel-B and atom count matches sel-B's C-side count. rc=0 + read-back is the assertion (selection RESOLUTION headless; visual re-render is GUI-checkpoint) |
| P4 | `mol showrep off` VISUAL hiding (pick-through behavior on hidden found reps) | text mode ignores the hide for rendering (probe F6); state tracks (V8) | GUI-checkpoint item: hide a found rep → confirm the found hiders vanish + a click where they were is a Miss/behind-atom pick. (Pick-through was GUI-confirmed for the general case 16-12: "hidden-rep unpickable GUI-confirmed") |
| P5 | tk_messageBox yesno rendering + modality inside a modeless VMD toplevel | Tk-only | GUI-checkpoint (the _show_win_box precedent covers tk_messageBox parenting; yesno is the same widget class) |
| P6 | ttk::combobox rendering in VMD's Tk (only if option (a) is chosen) | Tk-only; zero ecosystem usage | GUI-checkpoint. Recommended mitigation: pick option (b) menubutton+menu and this probe never runs |
| P7 | Whether `mol off` on the restored original removes it from the pick ray in-GUI (the 17.1-14 fix's final confirmation) | pick delivery is GUI-only (16-12) | GUI-checkpoint: different-target Start mid-round → confirm zero picks logged on the hidden original's molid (the 17.1-14 log shape: "6 picks on mol=3" should read 0) |
| P8 | Hint-rep VISUAL (VDW overlay rendering + orange visibility on a Lines scene) | text mode renders nothing | GUI-checkpoint (v1's 06-03 lesson: "headless smoke passing does NOT prove GUI correctness for color-persistence bugs"; here it's visibility/contrast) |

## 4. Open questions for the planner

1. **Hint rep design (a) single-rep-modselect vs (b) rep-per-press (A above).** What we know: (a) is bounded (one rep, per-press modselect re-assert — the mark_found_visual mechanism probed V18/P3), (b) is v1-UX accumulation parity. (a) changes repeated-hint UX vs v1 (only the latest region highlighted). Recommendation: (a) — bounded rep list, mechanism-consistent, and v1's accumulation was a per-atom-recolor artifact, not a design goal. If the user wants v1 accumulation, (b) with a name-keyed hint-rep dict (tier_reps pattern) is the port.
2. **Reveal-all counter +N (hiders) vs +1 (action)** — v1 resolved +N (06-01-SUMMARY:37, 06-RESEARCH.md Open Q2). Port verbatim; no new decision needed. DIFF-01 "track how many reveals were used across the game" is satisfied by +N hiders-revealed-by-give-up (v1's meaning).
3. **hint_count tracking in Phase 19 or deferred to Phase 22?** v1 tracked both from Phase 6. DIFF-01 requires reveals only, but Phase 22's DIFF-02 needs hints too. Recommendation: track both now (symmetric 2 counters, one round_reset reset) — avoids a Phase-22 seam change in game_logic.
4. **Found-mgmt widget: (b) menubutton+menu (recommended, v2-exercised) vs (a) ttk::combobox (v1-UX parity, Tk-doc-verified, unexercised in VMD's Tk).** Option (b) removes the placeholder-reset state dance entirely. See C table.
5. **Cleanup raise-destination.** v1's Game-tab had no cleanup; v1's Setup-tab cleanup stayed on Setup. v2's Game-tab Cleanup after use → raise Setup tab (round over) vs stay on Game. Recommendation: raise Setup (matches the round-over state; Start is there).
6. **DIFF-04 persistence across restarts.** `hiders::found_colorid` namespace var (default 7) persists across rounds until changed (simplest, default-preserving); OR re-apply per round from a game-tab state var. Recommendation: the namespace var (the v1 `_found_color` controller-attr precedent verbatim). NOT persisted to disk (Phase 20's .bcm could carry it later — v1's sidecar carried `_found_color` via apply_bcm_dict, game.py:336 — note for Phase 20).
7. **on_close cleanup-on-dialog-close (16-14 deferred).** 16-14 deliberately left cleanup-on-close to Phase 19: add `catch {::biochemeleon::game::cleanup ...}` reading the game_tab stash + `catch {game_logic::round_reset}` in on_close BEFORE destroy (after stop_all_timers + pick_bridge::deactivate, dialog.tcl:108-109). The surviving-stash path ("consumed by 16-13's guard on the next Start") becomes a clean session instead. Small scope item — flag it in the plan as an assigned 16-14 item.
8. **Setup-tab Reset expectation mismatch (16-12 registered defect).** The defect is "Setup-tab Reset clears setup fields only (hiders remain — expectation mismatch)". Is the Phase 19 resolution to make Reset ALSO call on_cleanup (when a game is active), or to reword the Reset button's copy/tooltip? Recommendation: when a game is active, Reset clears fields AND asks... v1-parity: v1's Reset never touched a game. Recommendation: keep Reset fields-only but add a tooltip "(hiders in an active game are not affected — use Cleanup)" — the light-touch resolution. Planner/user decides.
9. **Restart during countdown.** v1 flagged this (07-RESEARCH.md Risk 4: a pending countdown singleShot chain firing _begin_play on a NEW controller). v2's countdown is a tracked chained after (after_countdown, game_tab.tcl:251) — start_round's stop_all_timers cancels it (game_tab.tcl:161) BEFORE the new countdown arms. The Restart handler must call start_round (which stops timers) — the v1 Risk-4 class is structurally closed in v2 by the 16-14 tracked-after discipline. Verify in the plan's headless smoke that a restart-during-countdown shape cancels the old chain (assertable via the after-id discipline).
10. **Guard log line for the 17.1-14 fix.** The `mol off` fix should log via `vmdcon -info` (the guard's existing log-line convention, game.tcl:160,185) e.g. "bioCHEMeleon: restored original is hidden to avoid pick interception". Mirrors the guard's existing 2 INFO lines — traceable per the code-standards constraint.

## 5. Recommended approach per requirement ID

| Req | Mechanism (all probed unless noted) | New seam | Verification tier |
|---|---|---|---|
| **GAME-05 Hint** | `game::hint {}`: guard (state playing + stash + hidden>0) → pre-filter candidates (neighborhood count > 0 per hidden idx, parenthesized selector V1-V4) → pick_random → hint rep (design (a): one persistent rep + modselect; ColorID 3 orange; style VDW) → game_logic::hint_count++ → log kind `hint` | game::hint + hint-rep bookkeeping (hiders.tcl or game.tcl — planner; recommendation: game.tcl owns the rep name in a namespace var, hiders.tcl stays found-visual-only) | WSL tcltest (pick_random + counters) + headless mechanism smoke (V1 assertions: read-back style/sel/color, count>0, GAM excluded — probe4 is the literal script) + GUI checkpoint (P8 visual) |
| **GAME-06 Reveal-one** | `game::reveal_one {}`: guard → `[pick_random [registry::hidden_indices]]` → `_found_flow $idx` (mark_found_visual + mark_found) → reveal_count++ → `log_append revealed_one $rem` → remaining_cb → win sequence if rem==0 (finish_win + win log + win_cb — on_pick's exact sequence) | game::_found_flow extraction (on_pick refactor, byte-compatible) + registry::hidden_indices + game_logic reveal_count + log kind | WSL tcltest (hidden_indices, counters, log kinds, pick_random seeds) + headless smoke (reveal-one == click-found byte-identity: user2 partition + found-rep selection read-back + remaining) + GUI checkpoint (P5 confirm dialog) |
| **GAME-07 Reveal-all** | `game::reveal_all {}`: guard → foreach hidden idx `_found_flow` → reveal_count += N → `log_append revealed_all $N` → remaining_cb → win sequence once | (none — reuses the reveal-one seam) | headless smoke (loop identity: remaining 0, all user2>0, found-rep selections match, win fires once — the onpick-smoke found-partition shape) + GUI checkpoint |
| **GAME-08 Found-mgmt** | `hiders::hide_found_tiers {molid}` / `show_found_tiers {molid}` / `recolor_found_tiers {molid}`: iterate tier_reps (name-keyed → repindex resolution at use time) → `mol showrep $m $fidx off/on` or `mol modcolor $fidx $m ColorID $found_colorid` (probed V8). GUARD: tier_reps non-empty (else error, mark_found_visual's precedent). NEVER touches hidden reps | hiders.tcl showrep introduction + header rule-narrowing | headless smoke (state-level: showrep getter 0/1 round-trip V8; read-back unchanged after off/on V13) + GUI checkpoint (P4 visual + pick-through) |
| **GAME-10 Restart** | Dialog-scope `::biochemeleon::on_restart` (flow above: guard → deactivate → stop timers → catch-wrapped `game::restart $gs` → start_round + raise_tab + reveal_text reset) | dialog.tcl handler + game_tab.tcl Restart button | headless smoke (16-15's restart-smoke shape extended: restart via the STASHED state — same-count + per_rep + per_mat passthrough, post-18 5-arg) + GUI checkpoint (countdown re-arm, pick re-arm after restart — 16-16's session shape) |
| **BTN-06 Cleanup** | Dialog-scope `::biochemeleon::on_cleanup` (flow above) + Setup-tab button (spec.md:20 placement) + Game-tab button (16-12 defect) — ONE handler, TWO buttons (v1 parity). Sentinel role: identification/validation only (whole-molecule reload is the mechanism; PITFALLS v2 Pitfall 8) | dialog.tcl handler + 2 buttons | headless smoke (cleanup assertions already exist: post-restore fetch_hider_indices==0 + numreps==pre-start + registry 0 — extend with the hint-rep-dies assertion) + GUI checkpoint |
| **DIFF-01 Reveal counter** | game_logic::{reveal_count,hint_count} + round_reset + 0-arg getters + 3 log kinds. GUI: reveal_text label (textvariable) + reset in start_round step 1.5 + getter updates in handlers | game_logic.tcl counters/kinds + game_tab label | WSL tcltest (counter reset/lifecycle + kind formatting + round_reset clears) |
| **DIFF-04 Color picker** | `tk_chooseColor -parent $w -title ... -initialcolor green` → "" cancel (Tk-doc V14) → parse `#%2x%2x%2x` → `color change rgb 17 r g b` (probed V6) → `hiders::found_colorid` var → `recolor_found_tiers` auto-recolor (v1 _on_pick_color parity: picker auto-recolors existing found, gui_game.py:226) → future finds inherit (P3 same-round; cross-round via found_colorid) | hiders::found_colorid + recolor proc (GAME-08's) | headless smoke (color change round-trip V6 + modcolor read-back V7-negative/V1) + GUI checkpoint (P1 picker form, P2 slot-collision render check optional) |
| **17.1-14 fix** | `start_game` guard branch: post-remap `if {$restored ne $molid && live} { mol off $restored }` + INFO log (probed V10; viewmaster pattern :220/:235) | one branch in the guard (post-18 anchor: 18-07 inserts into step 12/15 + restart — the guard is byte-frozen, so the plan anchors the insertion point on the remap comment block) | headless probe (guard-session shape: different-target Start → `molinfo $restored get displayed` == 0; same-target restart → no-op) + GUI checkpoint (P7 zero-intercept) |
| **16-14 on_close item** | on_close gains catch-wrapped `game::cleanup` + `game_logic::round_reset` reading the game_tab stash (dialog.tcl:108-109 insertion point) | dialog.tcl:108-109 | headless (on_close is Tk-guarded — assert via a console-path cleanup) — GUI checkpoint for the close-mid-round session |

**Cross-requirement discipline (all rows):** every lib proc catch-wraps with `set rc [catch ...]` + rc==1 (never truthy); every GUI handler guards `winfo exists` + catch-wraps widget writes; every atomselect `$sel delete`'d; every new log line via game_logic::log_append (never direct puts); Tcl 8.5 only; comments stay gate-clean (8.6-idiom gate greps comments).

## Sources

### Primary (HIGH — probed today on the physical VMD 1.9.3 install)

- `tmp/p19probe/p19probe.tcl` (probe1) — colorinfo num/categories, `color change rgb` round-trip (slots 17, 22), within selector forms (formD self-inclusion), `same residue as` formC (119), srand/rand draws
- `tmp/p19probe/p19probe2.tcl` (probe2) — mol usage text (showrep form), modcolor named-color NEGATIVE, within-swallow discriminator (bare 41 vs paren 38 vs raw 41 with tagged GAM atoms)
- `tmp/p19probe/p19probe3.tcl` + `molusage.txt` (probe3) — FULL `mol` usage text from the binary (showrep `<molid> <repid> [on|off]`, no hiderep/displayrep, selupdate/colupdate/scaleminmax/drawframes/smoothrep/showperiodic listed, mol fix/free/on/off/active/inactive semantics)
- `tmp/p19probe/p19probe4.tcl` + `p19out4.txt` (probe4) — hint-rep end-to-end (addrep/modstyle VDW/modcolor ColorID 22/modselect parenthesized selector → exact read-back, count 51, GAM excluded), showrep off/on rc=0, delrep cleanup
- `tmp/p19probe/p19probe5.tcl` + `p19out5.txt` (probe5) — full ColorID table 0-32 RGBs, `molinfo get displayed` + mol off/on round-trip, `mol showrep` GETTER form 1→0→1

### Shipped VMD sources (HIGH)

- `vmd-ref/scripts/save_state.tcl:362,356` — `color change rgb $c $rgb` (numeric ColorID form) + `colorinfo rgb $c` table read
- `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:220,235,259,322,411` — `molinfo get displayed` save, `mol on/off` restore, `mol showrep $mol $i` GETTER save + `$n $val` restore, `color change rgb` in restore_colordefs
- `vmd-ref/plugins/clonerep.tcl:92-96,193` — delrep-renumbering discipline + the menubutton+menu dropdown idiom
- `vmd-ref/plugins/mergestructs.tcl:145`, `ramaplot.tcl:172`, `autoionizegui.tcl:96` — dropdown/menu ecosystem idioms

### Official Tk 8.5 docs (HIGH — TkCmd manual pages, tcl-lang.org, 8.5.19)

- chooseColor.htm — tk_chooseColor options + "" on cancel
- messageBox.htm — -type yesno → yes/no, -icon question, -detail
- ttk_combobox.htm — widget/readonly/values/<<ComboboxSelected>>

### v1 shipped code + phase docs (HIGH)

- `pymol/biochemeleon/game.py:11-12,232-318,369-415` — HINT_RADIUS/HINT_COLOR, hint (candidates pre-filter + object-scope), reveal_one/reveal_all (+N semantics), cleanup/abort counter resets
- `pymol/biochemeleon/gui_game.py:66-79,103-106,132-137,142-167,169-226` — dropdown/buttons, activated+reset, _confirm, reveal confirm copies verbatim, found-mgmt + color picker
- `pymol/biochemeleon/__init__.py:203-205,870-946` — restart/cleanup wiring + UI reset
- `.planning/phases/06-hint-reveal/06-RESEARCH.md`, `06-01/02/03-SUMMARY.md` — v1 semantics + 3 Rule-1 bugs (sparse-hider no-op, label reset C8, object-crossing around)
- `.planning/phases/07-found-hider-management-restart-cleanup/07-RESEARCH.md`, `07-01/02/03-SUMMARY.md` — v1 found-mgmt/picker/restart/cleanup + wizard-lifecycle risk resolution

### v2 codebase (HIGH — read in full today)

- `vmd/lib/game.tcl` (start_game 147-410, guard 158-191, cleanup 427-436, restart 452-466, set_callbacks 482-490, _resolve_pick 513-531, on_pick 573-622)
- `vmd/lib/hiders.tcl` (pair design 8-13, channels 15-23, ordering 25-29, name-keyed 31-48, read-back 57-64, NEVER-HIDE 66-71, NEVER-BETA 73-76, re-assert 78-85, procs 121-253)
- `vmd/lib/backup.tcl` (snapshot 39-50, apply 70-89, restore 109-114)
- `vmd/lib/registry.tcl` (244 lines — full API + resid block)
- `vmd/lib/mutation.tcl` (sentinel constants 46-52, PRNG convention 85-87, tag_sentinels 505-520, tag_sentinels_mixed 541-578, fetch_hider_indices 587-593, mutate 609-624)
- `vmd/lib/game_logic.tcl` (state machine 60-82, round_reset 86-98, finish_win 189-198, log_append 226-250)
- `vmd/lib/pick_bridge.tcl` (mechanism 4-54, activate 91-134, _on_event 148-175, set_view_mode 229-236, deactivate 243-266)
- `vmd/lib/rep_tiers.tcl` (TIER_KINDS 66-76, sentinel filter 121-137)
- `vmd/gui/dialog.tcl` (open_dialog 49-73, on_close 92-111, on_start 143-226)
- `vmd/gui/game_tab.tcl` (build 82-141, start_round 153-222, on_win 355-377, update_remaining 328-337)
- `vmd/gui/setup_tab.tcl` (button wiring 236-240, menubutton idiom 21)
- `vmd/AGENTS.md` (picking LOCKED section, sentinel rules, Tcl 8.5 gotchas, Phase-19 note)

### v2 planning records (HIGH)

- `.planning/STATE.md` — 16-12/16-13/16-14/16-15/16-16/16-17, 17.1-13/17.1-14, 17.2-04 discoveries
- `.planning/ROADMAP.md:215-231` — Phase 19 goal/criteria
- `.planning/REQUIREMENTS.md:34,58-63,90-93,139-146` — requirement texts
- `.planning/phases/18-materials-exploration/18-07-PLAN.md:14,39,77-79` — post-18 5-arg/5-key widening
- `.planning/research/FEATURES.md:66-67,77` — sentinel selector + hint-rep mechanism (pre-16 verified)
- `.planning/research/PITFALLS.md` (v2) — Pitfall 2 (no undo), Pitfall 8 (cleanup-reload role change)
- Companion: `.planning/phases/19-in-game-actions/19-RESEARCH-integration.md` — codebase-integration layer (line anchors, smokes inventory)

## Metadata

**Confidence breakdown:**
- Hint mechanism: HIGH — probed end-to-end today (V1-V4) + v1 semantics verbatim
- Reveal mechanism: HIGH — reuse of the smoke-proven found-flow (V18) + one new pure seam
- Found-mgmt/color: HIGH for probed facts (V5-V8, V17) + Tk-doc verification (V14-V16); the Tk return form (P1) and slot collision (P2) are the honest gaps
- Restart/cleanup: HIGH — existing smoke-proven procs; new work is wiring (the integration doc's seam anchors)
- Pick-contract interactions: HIGH — all tenured mechanisms (V8/V13 + UG node140 GUI-confirmed); visual checks P4/P7/P8 are GUI-checkpoint classes

**Research date:** 2026-09-24
**Valid until:** post-Phase-18 execution shifts game.tcl line numbers (the integration doc's proc-name anchors cover this); VMD API facts stable (fixed 1.9.3 target). Probes reproducible from `tmp/p19probe/`.

---

## RESEARCH COMPLETE

**Phase:** 19 - In-game Actions
**Confidence:** HIGH (all VMD mechanism claims probed today or shipped-source-cited; honest gaps P1-P8 all sketched)

### Key Findings

- **Hint = a parenthesized-rep mechanism:** `(within 5.0 of (index N)) and not resname GAM` — the swallow hazard is REPRODUCED with a discriminator (bare 41 vs paren 38); the rep mechanism probed end-to-end with exact read-back; ColorID 3 = orange (probed); v1's object-corruption + color-persistence hazards structurally ELIMINATED in v2.
- **Reveal = the existing found-flow byte-identical to a click-find** (mark_found_visual + mark_found); the ONE new pure seam is `registry::hidden_indices` (no hidden-record accessor exists today); reveal-all = +N (v1 decision ported).
- **Found-mgmt = `mol showrep $m $found_idx off/on`** on per-tier FOUND reps only (probed usage text + getter round-trip; NO hiderep/displayrep exist); the hiders.tcl NEVER-HIDE rule narrows (hidden rep never toggled); state IS trackable headlessly (showstate getter) while visuals are GUI-checkpoint.
- **DIFF-04 = `tk_chooseColor` (Tk-doc-verified) → `color change rgb 17 <r g b>` (probed round-trip; shipped-source form) → reserved ColorID slot**; modcolor named-color form is INVALID (probed negative); recommend `hiders::found_colorid` for cross-round persistence.
- **Restart/Cleanup = the existing smoke-proven `game::restart`/`game::cleanup`; the new work is dialog-scope handlers + 2+2 buttons + the 16-14 on_close item;** Restart semantics = same-count REPLAY (pinned by roadmap GAME-10 + 16-13, deliberately diverging from v1's re-derive-from-form — reword v1's tooltip). The 17.1-14 fix = `mol off $restored` in the guard's different-target branch (probed displayed-flag round-trip).

### File Created

`.planning/phases/19-in-game-actions/19-RESEARCH-mechanisms.md`

### Ready for Planning

Mechanism research complete — planner can create PLAN.md files, consuming this doc together with `19-RESEARCH-integration.md` (seam anchors) and `19-CONTEXT.md` (if present after `/gsd-discuss-phase`).



