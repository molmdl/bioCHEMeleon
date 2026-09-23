# Phase 19: In-game Actions — Codebase-Integration Research

**Researched:** 2026-09-24
**Domain:** v2 bioCHEMeleon (VMD 1.9.3 tcl) codebase integration layer — GAME-05/06/07/08/10, BTN-06, DIFF-01, DIFF-04
**Confidence:** HIGH (every codebase claim cites file + proc + line, read from the physical repo at `/mnt/c/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon` on 2026-09-24; two VMD-behavior questions settled by a fresh headless probe, `tmp/p19-probe/probe2.tcl`, same date)

**Scope note:** Phase 19 executes AFTER 17.2 (BUILT, GUI checkpoint pending) and Phase 18 (FULLY PLANNED, 15 plans, not executed). All attachment points below are given in **today's line numbers** with the post-18 shift flagged — Phase 19 plans must anchor on proc names + code shapes (grep anchors), never raw line numbers, because 18-07 inserts lines into `game.tcl` step 12/15 and `restart`.

---

## 1. Current-code proc inventory (exact signatures, pre-18)

### 1.1 `vmd/lib/game.tcl` (622 lines) — the composition root

| Proc | Signature | Lines | Notes |
|------|-----------|-------|-------|
| `start_game` | `{molid hider_count {per_rep {}} {lock_scene 0}}` | 147–410 | 4-arg today → 5-arg post-18. 16-13 ACTIVE-GAME GUARD at 149–191 (cleanup-then-start, liveness remap, stale-stash catch branch). Ordering steps 1–14 documented in header 56–146. |
| `cleanup` | `{game_state}` → restored molid | 427–436 | `backup::restore [dict get $gs snapshot] [dict get $gs game_molid]` + `registry::reset` + `set current_state [dict create]`. **It does NOT touch pick_bridge, game_logic state, GUI timers, or hint reps — the Game-tab/lib surface around cleanup is the Phase-19 surface.** |
| `restart` | `{game_state}` → new game_state | 452–466 | `cleanup` + `start_game $molid $hider_count $per_rep $lock_scene` — defensive `dict exists` reads of `per_rep` (454–458) and `lock_scene` (459–463); post-18 gains the same defensive read for `per_mat` (18-07 task 1.4). Same-count, same-tier-distribution semantics (positions re-randomize — generators re-run). |
| `set_callbacks` | `{log_cb remaining_cb win_cb}` | 482–490 | log_cb 1 arg / remaining_cb 0 args (PULL) / win_cb 2 args (elapsed hider_count). Callback prefixes invoked as `catch {{*}$cb <args>}`. |
| `_resolve_pick` | `{idx}` → index or "" (PRIVATE) | 513–531 | Direct `is_hider` hit, else resid read on the game molecule → `registry::hider_for_resid` (the 17.2-09 CA fallback). |
| `on_pick` | `{idx}` | 573–622 | State gate FIRST (`game_logic::state` ne "playing" → return), stash guard, three-way miss/already/hidden guard, `mark_found_visual` + `mark_found` + log + remaining_cb + win check (`finish_win` → frozen elapsed → win log → win_cb). Whole body `set rc [catch {...}]` + `rc == 1` reporting. |

Namespace vars: `current_state` (the stashed game_state dict, cleared by cleanup — 43, 434), `_cb_log/_cb_remaining/_cb_win` (51–53).

**game_state shape today (4 keys):** `{game_molid hider_count snapshot per_rep}` (built at 407; `hider_count` = the P9 EFFECTIVE total). Post-18: 5 keys (§2).

### 1.2 `vmd/lib/game_logic.tcl` (257 lines) — PURE round model

Vars (60–75): `state` ("idle"/"countdown"/"playing"/"won"), `countdown_steps`, `timer_epoch`, `timer_elapsed_final`, `log_lines`.

| Proc | Signature | Lines |
|------|-----------|-------|
| `round_reset` | `{}` | 86–98 (resets ALL five vars; **the natural zeroing point for Phase-19 counters**) |
| `begin_countdown` | `{}` (errors unless idle) | 102–111 |
| `countdown_tick` | `{}` → `{label done}` | 118–132 |
| `begin_play` | `{}` (errors unless countdown finished) → `timer_start` | 138–147 |
| `timer_start` / `timer_elapsed` / `finish_win` | `{{now {}}}` test-injection hook | 151–158 / 163–177 / 189–198 (`finish_win` errors unless playing — the double-win guard) |
| `timer_stop` | `{}` (documented no-op) | 182–184 |
| `state` | `{}` | 202–205 |
| `format_mmss` | `{secs}` | 209–214 |
| `log_reset` / `log_append {kind msg}` / `log_lines` | | 217–221 / 226–250 / 254–257 |

LOG MODEL kinds today (229–247): `countdown` (msg verbatim), `miss` ("Miss!"), `already` ("Already found!"), `found` ("Found one! $msg remaining"), `win` (msg verbatim). Unknown kind → `error`. **Phase 19 adds kinds** (§4.2).

### 1.3 `vmd/lib/registry.tcl` (244 lines) — PURE scoring model

Vars: `HIDER_STATUS_HIDDEN`/"hidden", `HIDER_STATUS_FOUND`/"found" (8, 11), `_records` (idx → `{rep status}` dict, 20), `_resid_block` (resid → idx, 26).

| Proc | Signature | Lines |
|------|-----------|-------|
| `reconstruct_from_sentinels` | `{fetch_hider_ids {rep ""}}` (DI `{*}` prefix) | 44–51 |
| `is_hider` | `{idx}` → 0/1 | 56–59 |
| `mark_found` | `{idx}` (errors if unregistered; SILENT idempotent overwrite) | 63–70 |
| `count_hiders` | `{}` | 75–78 |
| `reset` | `{}` (clears `_records` AND `_resid_block`) | 86–92 |
| `status_of` | `{idx}` → "hidden"/"found"/"" | 99–105 |
| `count_remaining` | `{}` (counts status==hidden only) | 110–119 |
| `remaining_by_rep` | `{}` → dict {rep count}, skips rep=="" | 126–142 |
| `set_rep` / `assign_reps` | `{idx rep}` / `{mapping}` (atomic validate-then-apply) | 153–162 / 170–181 |
| `register_resid_block` / `hider_for_resid` | `{mapping}` (wholesale replace) / `{resid}` → idx or "" | 218–231 / 238–244 |

**GAP (Phase 19 needs, question D):** there is NO proc that ENUMERATES indices by status. `count_remaining` counts; nothing returns the hidden index list (needed for reveal-one's random pick + hint's candidate filtering) or the found index list (needed for found-mgmt counts/logs). Pure, trivially TDD-able (§4.1).

### 1.4 `vmd/lib/hiders.tcl` (253 lines) — MOL BRIDGE, the visual half

Vars: `tier_reps` (code → `{hidden_name found_name hidden_sel found_sel}`, 97), `tier_styles` (code → style string, 99). Both RESET at the top of every `add_hider_reps` call.

| Proc | Signature | Lines |
|------|-----------|-------|
| `add_hider_reps` | `{molid {tier_specs {{1 VDW}}}}` → tier_reps | 121–185 (post-18: optional 3rd arg `mat_specs`, 18-02; gains `tier_materials` var) |
| `stamp_tier_codes` | `{molid tier_of}` (user3 numeric stamps; MUST run BEFORE add_hider_reps — ordering contract) | 199–209 |
| `mark_found_visual` | `{molid idx}` — `user2=1` then re-asserts ALL pairs' STORED literal selection strings, resolving indices via `mol repindex` at USE time with −1/≥numreps hard errors | 220–253 |

Load-bearing invariants a Phase-19 implementer must not break (header 1–90):
- **NEVER HIDE A REP** (66–71): UG node140 — hidden reps cannot be picked. This rule exists so the HIDDEN rep stays pickable. **GAME-08's hide/show of the FOUND rep is a new, deliberate exception**: the found rep contains only `user2 > 0` hiders (already scored — unpickable is harmless). The header comment must be amended with this exception; the hidden rep stays never-hidden.
- **NEVER WRITE BETA** (73–76): found flags live only in user2.
- Rep tracking is NAME-keyed (`mol repname` captured at add time; `mol repindex` resolved at use time with −1 guard) — **GAME-08/DIFF-04 reuse exactly this machinery** (walk `tier_reps`, resolve found names via repindex, issue `mol showrep`/`mol modcolor`).
- Selection strings are stored at add time and re-issued UNCHANGED (the re-assert contract, 79–85).

### 1.5 `vmd/lib/backup.tcl` (114 lines) — snapshot/apply/restore contract

- `snapshot {molid}` → dict `{molid filename viewpoint reps}` (39–50). Reps = ALL reps as `{style sel color material}` 4-tuples via combined-braces molinfo.
- `apply {snapshot molid}` (70–89): clear-all-reps (`mol delrep 0` loop) + form-B re-apply + viewpoint set. STATE-ONLY.
- `restore {snapshot molid_to_delete}` → new_molid (109–114): **2-arg REQUIRED** — `mol delete` of the LIVE game molid (NOT the dead snapshot.molid), `mol new <original filename> type pdb`, then `apply`. Reload restores atom fields automatically (hint-orange/user flags do not survive a reload — there is no per-atom-color state to clean on the restored original).

### 1.6 `vmd/lib/mutation.tcl` (624 lines) — sentinel machinery (BTN-06 maps onto this)

- `fetch_hider_indices {molid}` (587–593): THE canonical selector `resname $HID_RESNAME and beta < 0` (NEVER `beta < 0` alone).
- `tag_sentinels` (505–520) / `tag_sentinels_mixed` (541–579): in-place GAM/−999/GAME stamping + user ordinals; mixed = CA-only beta on residue rounds.
- `mutate {molid hider_records {residue_records {}}}` (609–624): forward reload (combined PDB → mol delete original → mol new → tag).
- **BTN-06 interpretation (verified against the requirement text):** in v2, every game-generated atom lives on the game molecule, and cleanup's `mol delete` + `mol new original` removes ALL of them whole — there is no per-atom deletion in VMD (AGENTS.md domain rules). The requirement's "via `resname GAM and beta < 0` sentinel, never generic filters" is therefore a CONSTRAINT on any Phase-19 code that ever SELECTS game atoms (hint's `not resname GAM` exclusion, any smoke assert, any future import-flow cleanup) — never a new removal mechanism. `game::cleanup` already satisfies BTN-06's model-removal semantics; BTN-06's Phase-19 work is GUI wiring + the cleanup surface list (§3.5).

### 1.7 `vmd/lib/pick_bridge.tcl` (266 lines) — part of the cleanup surface

- `activate {game_molid}` (91–134) — idempotent via `active` flag; saves user mouse mode; `mouse mode pick 2`.
- `_on_event {args}` (148–175) — **molid filter at 158: `if {$vmd_pick_mol ne $active_mol} { return }`** — picks on any OTHER molecule (including a leftover restored original) are silently dropped. The 17.1-14 "restored-original-intercepts-picks" defect is a UX confusion defect (player clicks what looks like the game scene, nothing scores), NOT a scoring-corruption defect.
- `deactivate {}` (243–266) — trace removal, labelpoll cancel, baseline-guarded label cleanup, mouse-mode restore (fallback `mouse mode rotate`), `active 0`. Idempotent no-op when inactive.

### 1.8 GUI layer

- `vmd/gui/dialog.tcl` (226 lines): `open_dialog` (49–73, eager game_tab build, WM_DELETE wired), `on_close` (92–111 — collect_state persist + trace vdelete + catch-guarded `game_tab::stop_all_timers` + `pick_bridge::deactivate` + destroy; **deliberately NO game::cleanup — 16-14 deferred that to Phase 19**), `on_start` (143–226 — the 7-step BTN-07 fan-in; step 3.5 catch-guarded `pick_bridge::deactivate`; step 4 `start_game` catch → tk_messageBox abort; steps 5–7 set_difficulty/raise_tab/start_round).
- `vmd/gui/game_tab.tcl` (465 lines): namespace vars 49–70 (`w timer_text remain_text mode_text mouse_mode easy_mode game_state after_tick after_countdown after_winbox`); `build {parent}` (82–141) — layout: status row (timer/remain/mode labels, pack -side left) top → "Info log:" caption → log frame (fill both expand) → "Mouse mode" labelframe (pack -side bottom); `start_round {game_state}` (153–222) — stop_all_timers → view-state reset (timer/mode/mouse) → stash gs → set_callbacks → round_reset + begin_countdown → clear log view + "Get ready..." → update_remaining → countdown_step; `countdown_step` (234–270, GO branch: begin_play + `pick_bridge::activate [dict get $game_state game_molid]` + Pick label/radios + tick loop); `tick` (279–297); `on_log_line {line}` (307–319 — THE only log inserter); `update_remaining` (328–337 — pull model); `on_win {elapsed n_hiders}` (355–377 — stop timers + bridge down + Rotate + delayed win box); `set_mouse_mode` (406–417); `set_difficulty {easy}` (425–433); `stop_all_timers` (442–453); `raise_tab` (460–465).
- `vmd/gui/setup_tab.tcl` (691 lines): `_dget` (56–59, the dict-get-with-default helper), `build_actions` (234–240 — buttons with `-command {::biochemeleon::setup_tab::do_*}`, Start uses `-command {::biochemeleon::on_start}` → dialog scope), `collect_state` (251–284), `apply_state` (297+, `_loading` guard + catch-always-reset), `do_reset` (586–588 = `apply_state DEFAULTS` — the Setup-tab Reset that clears fields only).

### 1.9 `vmd/tests/rep_verify.tcl` (637 lines) — the GUI auto-driver pattern

Tk-guard if-wrap → `pv_log` (open-append+flush+vmdcon echo) → `pv_observe`/`pv_observe_fallback` (pick trace with `{args}` sig) → `pv_state` (mega-dump: per-tier rep read-backs via `tier_reps` + `mol repindex`, registry, resid block, mouse/labels) → `pv_round2`/`pv_round3` (fresh `demos::load_demo` target → crafted state via `validate_state` → `apply_state` → `catch {unset ::pv_gs}` → `on_start` → `after 4500 pv_state`) → `pv_cleanup` (bridge deactivate FIRST, then `game::cleanup $::pv_gs`, unset stash) → `pv_cleanup_check` (post-state dump incl. restored atom count) → `pv_report` → `pv_instructions` (LEADS with the p-press quirk) → `pv_autostart`. Post-18 it also gains `pv_round4` (18-13). Phase 19 extends this file LAST (§6).

---

## 2. Post-18 seam contract (what Phase 19 must assume DONE)

Source: `18-07-PLAN.md` (game.tcl seam), `18-02-PLAN.md` (hiders mat_specs), `18-08/18-10-PLAN.md` (GUI wiring), `18-RESEARCH-codebase-integration.md` §1–3, `18-01/18-03/18-04/18-05/18-09` plans. The 18-07 pattern — planning against a not-yet-executed prior seam — is exactly what Phase 19 repeats.

| Contract | Post-18 state | Evidence |
|----------|--------------|----------|
| `start_game` signature | `{molid hider_count {per_rep {}} {lock_scene 0} {per_mat {}}}` — additive 5th arg, `{}` = blending OFF | 18-07 task 1.1 |
| `game_state` shape | **5 keys** `{game_molid hider_count snapshot per_rep per_mat}` (per_mat = the RESOLVED dict) | 18-07 task 1.3; `phase16_onpick_smoke.tcl` gs-shape assert updated 4→5 (currently 4-key at lines 148/152) |
| `restart` | defensive `dict exists` pass-through of `per_mat` as 5th arg | 18-07 task 1.4 |
| `add_hider_reps` | 3-arg `{molid {tier_specs} {mat_specs {}}}`; `mol modmaterial` on BOTH reps of a carrying tier; P-1 read-back extended to material; new `tier_materials` var (code → material) reset per call | 18-02 truths |
| `hiders.tcl` | gains `tier_materials` parallel to `tier_styles` | 18-02 |
| `setup_state.tcl` | `GAME_MATERIALS {GameBlend Translucent Glass2 EdgyGlass Glass3}` + `DEFAULT_MATERIAL` + DEFAULTS keys `material_blending 0` / `per_mat {}` appended at END (order-stable eq discipline); validate_state cleans per_mat; randomize_state returns the new keys | 18-01/18-03 (curated set gated on 18-15's pick-through verdict) |
| `materials.tcl` (NEW lib) | `ensure_gameblend` (idempotent, the ONLY material add/change in 18) + `resolve_per_mat` (pure, GAME_REPS-ordered) + `valid_mat_value`; sources NOTHING | 18-04 |
| entry `biochemeleon.tcl` | sources `materials.tcl` after `hiders.tcl` before `game.tcl`; one catch-guarded `ensure_gameblend` call | 18-09 |
| `demos.tcl` save/load | `per_mat_count`/`per_mat_entry` lines + rebuild-list append `material_blending per_mat`; old-.bcm backward compat | 18-05 |
| `setup_tab.tcl` | material toggle + per-rep menubuttons + collect/apply threading | 18-06/18-08 |
| `dialog.tcl on_start` | 5-arg call: `set pm {}; if blending on → pm = per_mat` | 18-10 |
| smokes | `phase18_materials_smoke.tcl` + `phase18_multimat_smoke.tcl` NEW; `phase17_capstone_smoke.tcl` gains rounds F (blending) / G-off / G-lock; `phase16_onpick_smoke.tcl` 5-key; `phase14_mol_smoke.tcl` save/load keys | 18-08..18-12 |
| `rep_verify.tcl` | gains `pv_round4` + material read-back logging (execution gated on 17.2-12 closing) | 18-13 |

**Files Phase 18 touches (full list):** `vmd/lib/setup_state.tcl`, `vmd/lib/hiders.tcl`, `vmd/lib/materials.tcl` (new), `vmd/lib/demos.tcl`, `vmd/lib/game.tcl`, `vmd/gui/setup_tab.tcl`, `vmd/gui/dialog.tcl`, `vmd/biochemeleon.tcl`, `vmd/tests/test_setup_state.test`, `vmd/tests/test_materials.test` (new), `vmd/smoke/phase14_mol_smoke.tcl`, `vmd/smoke/phase16_onpick_smoke.tcl`, `vmd/smoke/phase17_capstone_smoke.tcl`, `vmd/smoke/phase18_materials_smoke.tcl` (new), `vmd/smoke/phase18_multimat_smoke.tcl` (new), `vmd/tests/rep_verify.tcl`.

**Files Phase 18 does NOT touch — Phase-19-exclusive:** `vmd/lib/game_logic.tcl`, `vmd/lib/registry.tcl`, `vmd/lib/pick_bridge.tcl`, `vmd/lib/mutation.tcl`, `vmd/lib/backup.tcl`, `vmd/gui/game_tab.tcl`, `vmd/tests/test_game_logic.test`, `vmd/tests/test_registry.test`, `vmd/smoke/phase16_restart_smoke.tcl`, `vmd/smoke/phase16_gametab_smoke.tcl`, `vmd/smoke/phase16_entry_smoke.tcl`. **`game_tab.tcl` is Phase 19's primary GUI file with zero Phase-18 overlap** — the same file-disjoint trick 18 used against 17.2.

**Byte-frozen game.tcl invariants 18 preserved and 19 must preserve unless deliberately unfrozen (§6):** 16-13 guard (149–191), ONE mutate, ONE 1-arg `reconstruct_from_sentinels`, `stamp_tier_codes` BEFORE `add_hider_reps`, hider reps land LAST (base..base+2N−1), scene-rep application = `backup::apply`.

---

## 3. Per-action attachment map (files + procs + patterns)

### 3.0 Shared pattern: the BTN-07 fan-in (16-10) is the template for every new button

```
Setup/Game tab widget  -command {::biochemeleon::on_<action>}   (setup_tab/game_tab build)
        ↓
dialog.tcl handler ::biochemeleon::on_<action>  (DIALOG scope — needs game_tab + game.tcl;
        guards + confirm boxes (tk_messageBox) + catch → tk_messageBox abort + return)
        ↓
lib call (::biochemeleon::game::<action> $gs)  (gs read from ::biochemeleon::game_tab::game_state)
        ↓
game_tab re-render (update_remaining / on_log_line / label vars)
```
- Handlers live at dialog scope (`::biochemeleon::on_start` precedent, dialog.tcl:114–141 comment SS7.5 rationale: needs setup_tab/game_tab/game.tcl, avoids cross-tab reach-ins).
- Error paths: `tk_messageBox -parent $::biochemeleon::w -icon warning -title "bioCHEMeleon"` + return (v1 parity).
- v1 button semantics to port (verified in `pymol/biochemeleon/gui_game.py:139–236` + `game.py:232–320`): handlers early-return when no controller/round or `remaining == 0`; confirms live in the GUI, NEVER in the lib procs.

### 3.1 GAME-05 Hint

**v1 semantics (port target):** `game.py:232–273` — pick a random HIDDEN hider that HAS neighbors within `HINT_RADIUS 5.0` (game.py:11); color the NEIGHBORS (`byres around`, excluding GAME atoms and the hider itself) `HINT_COLOR 'orange'` (game.py:12); do NOT mark_found; increment `_hint_count`; log "Hint: highlighted neighbors of one hider."; no confirm; no-op (uncounted) when no hider has neighbors.

**v2 attachment:**
| Concern | File | Pattern |
|---------|------|---------|
| Neighbor enumeration + random pick | `vmd/lib/game.tcl` NEW proc `hint {game_state}` | state gate (`game_logic::state` ne "playing" → return, mirror on_pick:579) + stash/gs guard; `registry::hidden_indices` (§4.1) → candidate filtering → `generators::sample $candidates 1` (the 17.1-03-tested helper; seedless in production per 14-01, explicit-seed in tests; the 1-candidate determinism trick in §7 makes headless asserts PRNG-independent) |
| The hint rep itself | `vmd/lib/hiders.tcl` NEW proc `add_hint_rep {molid idx {radius 5} {colorid 3}}` | `mol addrep` + `mol modselect` **`(exwithin 5 of index $idx) and not resname GAM`** + `mol modcolor ... ColorID 3` + read-back validation (P-1 discipline — modstyle/modselect never raise on garbage). Probe-verified 2026-09-24 (tmp/p19-probe/probe2.tcl): `exwithin` EXISTS and excludes the anchor (N=35 around a 1znf CA); the parenthesized form is REQUIRED — the unparenthesized `within 5 of index $i and not index $i` returned **N=0** (the 17.2-10 trailing-swallow gotcha reproduced); `not resname GAM` excludes fake atoms. game.tcl delegates ALL rep manipulation to mol bridges (game.tcl header 18–21) — the rep add belongs in hiders.tcl, NOT inline in game.tcl. |
| Counter | `vmd/lib/game_logic.tcl` NEW `hint_count` var + `increment_hint`/getter | round_reset zeroes it (§4.2) |
| Log line | `game_logic::log_append` NEW kind `hint` → "Hint: highlighted neighbors of one hider." | v1 line parity |
| GUI | `vmd/gui/game_tab.tcl` build: a button row with `Hint` (ttk::button); `vmd/gui/dialog.tcl` NEW `on_hint` | guard (no round / remaining==0 → return, v1 `_on_hint_clicked` parity) → `game::hint $gs` catch → message box |

**Design notes:**
- Hint targets the REGISTERED index (simple tiers: the hider atom; residue tiers: the CA — registry keys are CA-only by the 17.2-09 design), so neighbor radius is measured from the CA. v1's hint also anchored on the hider id. Acceptable; note in the plan.
- Hint reps accumulate on the game molecule (one per hint press, v1-accumulation parity — orange stays until cleanup). They die with the molecule on cleanup/restart (whole-molecule reload) — no cleanup code needed. Alternative (single re-used rep re-pointed via modselect) erases earlier hints — rejected as a v1 semantics change unless the planner wants a bounded rep count.
- Candidate filtering cost: v1 counts atoms per hidden hider (N atomselect calls). v2 equivalent: `atomselect $molid "(exwithin 5 of index $idx) and not resname GAM"` num check per candidate — at the ≤50-hider cap this is fine (<200 ms budget, AGENTS performance rules); optionally stop at the first candidate with neighbors.
- The `and not resname GAM` conjunct keeps hint reps from highlighting fake atoms; the rep itself is a REAL-atom rep — no sentinel conjunct needed INSIDE its selection, but the selection must never match GAM (BTN-06's sentinel rule respected in spirit: game atoms are identified only via resname GAM).

### 3.2 GAME-06 Reveal-one + DIFF-01 counter

**v1 semantics:** `game.py:274–296` — random hidden hider → `_mark_found` → `_reveal_count += 1` → log "Revealed one! %d remaining" → remaining callback → if remaining==0 → win(). Confirm lives in the GUI (`gui_game.py:149–157`, "Give up on one random hider? This counts as a reveal use."). GUI also early-returns when remaining==0 BEFORE confirming.

**v2 attachment:**
| Concern | File | Pattern |
|---------|------|---------|
| Reveal core | `vmd/lib/game.tcl` NEW proc `reveal_one {game_state}` | state gate + gs guard; `set hidden [registry::hidden_indices]`; empty → return; pick = `lindex [generators::sample $hidden 1] 0`; then EXACTLY the on_pick hidden-branch body (604–608): `hiders::mark_found_visual [dict get $gs game_molid] $idx` + `registry::mark_found` + `log_append revealed $rem` + remaining_cb + win check identical to 611–616 (`finish_win` → frozen elapsed → win log → win_cb). Recommend factoring the shared tail (mark+log+win-check) into a PRIVATE `game::_score_found {gs idx}` helper both on_pick and the reveal procs call — one win-flow, three callers. |
| Found-visual | `hiders::mark_found_visual` UNCHANGED | the rep-pair design means "mark found" IS the visual transition (user2 flag + re-assert) — no new visual code |
| Counter | `game_logic.tcl` NEW `reveal_count` var + increment/getter; round_reset zeroes | DIFF-01 |
| Log | `log_append` NEW kind `revealed` → "Revealed one! $msg remaining" (v1 wording differs from `found`'s "Found one!...") | |
| GUI | game_tab: `Reveal one` button; dialog: `on_reveal_one` with `tk_messageBox -type yesno -icon question -title "Reveal one hider?" -message "..."` (Tk 8.5 core, returns yes/no; GUI-only — never headless-tested) | v1 confirm parity |
| Label | game_tab build: status-row or button-row label `Reveals: N` bound to a new `reveal_text` textvariable, updated from `game_logic::reveal_count` | v1 `_reveal_label` parity (gui_game.py:61–66) |

### 3.3 GAME-07 Reveal-all

**v1 semantics:** `game.py:298–320` — mark ALL hidden found; `_reveal_count += len(hidden)` (NOT +1); remaining→0; log "Revealed all %d hiders. Game over."; win(). Confirm in GUI ("Give up and reveal ALL remaining hiders? This ends the game.").

**v2 attachment:** `game.tcl` NEW `reveal_all {game_state}` — same gates; loop `foreach idx [registry::hidden_indices]` { mark_found_visual + mark_found }; `reveal_count += n`; log kind `revealed_all`; remaining_cb; **then the win flow** (`finish_win` + win log + win_cb) — reuse the same shared `_score_found`-style tail or call finish_win directly after the loop (all found ⇒ remaining 0 ⇒ win is unconditional). GUI: `Reveal all` button + yesno confirm (`on_reveal_all`). Counter/label per §3.2.

### 3.4 GAME-08 Found-hider management dropdown + DIFF-04 color picker

**v1 semantics:** `gui_game.py:169–236` — dropdown {placeholder, Hide found, Show found, Recolor found} filtered by FOUND STATUS (not color); `_on_pick_color` (DIFF-04) sets a named color + auto-recolors existing found hiders + future finds use it.

**v2 architectural translation (the big simplification):** VMD colors per-REP, and the found visual IS a rep (the found half of each tier pair, currently `mol modcolor ... ColorID 7` hardcoded at hiders.tcl:161). Therefore:
- **Recolor found** = re-issue `mol modcolor $fidx $molid ColorID <n>` on every tracked found rep (walk `tier_reps`, resolve via `mol repindex` with the −1 guard — the mark_found_visual walk pattern, 239–251). New finds AUTOMATICALLY inherit the new color (they render through the same rep). No per-atom anything.
- **Hide found / Show found** = `mol showrep $molid $fidx off|on` per tracked found rep. SAFE against the NEVER-HIDE-A-REP rule: only the found reps are toggled; the hidden (unfound) reps stay shown and pickable. The hiders.tcl header rule (66–71) must be amended to document this deliberate exception.
- No registry selection-building needed (v1's `build_found_selection`/`group_found_by_rep` have no v2 analog — the pair design already partitions by status).

**v2 attachment:**
| Concern | File | Pattern |
|---------|------|---------|
| `set_found_color` | `vmd/lib/hiders.tcl` NEW `set_found_color {molid colorid}` | walk tier_reps → repindex resolve + guard → `mol modcolor $fidx $molid ColorID $colorid` → read-back validate (P-1). Also store the chosen color in a NEW namespace var `found_colorid` (default 7) that **`add_hider_reps` reads instead of the hardcoded 7** (line 161) so new rounds use the preference; the var is NOT reset by add_hider_reps (user preference persists across rounds — contrast tier_reps/tier_styles which ARE reset). |
| `set_found_visible` | `vmd/lib/hiders.tcl` NEW `set_found_visible {molid flag}` | same walk → `mol showrep $fidx $molid` off/on. Probe-verified 2026-09-24: `mol showrep $m $i` GET returns 0/1 and REFLECTS off/on sets in `-dispdev text` (probe2: rep0=1 → off→0 → on→1) — **headless-assertable**. (The 17.x smokes' "showrep is IGNORED in text mode" pins refer to the visual rendering in Tachyon-export workflows, not the state readback.) |
| GUI dropdown | `game_tab.tcl` build: `menubutton + menu` (the PROVEN Tk 8.5.6 idiom — setup_tab.tcl:137–162, 18-06 ban on ttk::combobox applies here too) with entries Hide found / Show found (+ optionally a found-count suffix); menu items fire dialog-scope handlers | v1 combo parity; reset-style selection is unnecessary with menu entries (v1 needed index-reset because QComboBox holds a selection) |
| GUI color picker | DIFF-04: recommended a **curated ColorID palette menubutton** (same idiom) rather than `tk_chooseColor` (§8.1 — the RGB→VMD mapping problem). `set_found_color` doubles as the handler; auto-recolor existing found comes free. | |
| State reset on new round | `start_round` (game_tab) must reset the found-visibility UI state (and the lib's round-scoped bits die with tier_reps' reset); `found_colorid` persists | |

### 3.5 GAME-10 Restart + BTN-06 Cleanup (the end-of-round pair)

**Restart (GAME-10):** ROADMAP SC4 = "reload original molecule + reps from backup and reset the game". The 16-13 decision PINS the semantics: "`restart` same-count semantics deliberately deferred to Phase 19's Restart button" — i.e. the button is a **thin wrapper over `game::restart {game_state}`** (cleanup → start_game SAME hider_count + SAME per_rep [+ per_mat post-18]; generator positions re-randomize, tier mix replays). v1's non-imported Restart re-read the Setup form (`__init__.py:870–884` routes to `_on_start`) — that is the 16-13 GUARD's job in v2 (Start-during-round = caller's-settings auto-restart); the BUTTON uses the stashed-state variant. Recommended flow (dialog scope `on_restart`):
1. Guard: a stashed round must exist (`game_tab::game_state` non-empty) else message box.
2. `catch {pick_bridge::deactivate}` (16-14 step-3.5 precedent — the new round re-arms at GO).
3. `set gs2 [game::restart $gs]` (catch → message box; game::restart's own cleanup+start are the "mol delete + reload original + re-apply saved reps" of the requirement, and `backup::restore` IS that reload).
4. `game_tab::start_round $gs2` — which already does stop_all_timers + view-state reset + `round_reset` (counters zeroed) + fresh countdown + GO-branch re-activation on the NEW game_molid. NO other GUI code needed.

**Cleanup (BTN-06):** `game::cleanup {gs}` already performs the model-removal semantics (§1.6); Phase 19 wires it. Recommended flow (dialog scope `on_cleanup`):
1. Guard as in restart.
2. `game_tab::stop_all_timers` + `pick_bridge::deactivate` (the on_close order: timers and bridge down BEFORE state teardown).
3. `set restored [game::cleanup $gs]` (catch → message box).
4. NEW `game_tab::end_round` (or extend start_round's reset block into a reusable proc): reset timer/mode/mouse/remain labels, clear the log view, reset the reveal label to "Reveals: 0", reset mouse radios to rotate. (game_logic::state stays "won"/"playing" — round_reset is start_round's job; end_round should NOT call round_reset or the next Start's countdown still works — it calls begin_countdown from idle. **Decision needed: end_round calls `game_logic::round_reset` too** — it is the documented whole-model reset and leaves state idle; safe.)
5. Viewpoint wart: cleanup's restore applies the SNAPSHOT viewpoint (backup::apply step c), so the restored original shows its pre-round view — EXCEPT the 16-15 probe finding that the scene view resets on every `mol new`; the net effect is the restored original shows its snapshot view (stage-C asserts rely on it). No extra view code required for the button path; the 16-15 "fresh-load view" wart is specific to the guard's different-target path (§8.6).

**Cleanup-on-close (16-14 deferred decision):** option (a) keep the current contract (on_close does NOT cleanup; the surviving stash is consumed by the next Start's 16-13 guard — verified behavior) or option (b) on_close also runs the cleanup flow when a stash exists. Recommendation: **(b) is now cheap** — with `on_cleanup` factored, on_close can call it catch-guarded before destroy; it removes the "game molecule lingers loaded after close" wart and matches user expectations of a Cleanup button existing at all. Keep the 16-13 guard untouched either way (it still consumes stale stashes when cleanup-on-close itself failed).

**The 16-12/17.1-14 defect fixes attach here:**
- *Restored-original-intercepts-picks* (17.1-14 finding 2): after the 16-13 guard's cleanup restores the old original and the new round targets a DIFFERENT live molecule, the restored original stays loaded/visible and looks like a playable scene. Fix candidates: `mol off $restored` (molecule-level display toggle — probe-verified round-trip via `molinfo get displayed` 0/1; ramaplot.tcl:523/viewmaster.tcl:235 precedents) or leave visible. NOTE this MODIFIES the byte-frozen guard branch — see §6 risk R1.
- *Setup-tab Reset clears fields only* (16-12): options — leave (v1 parity), or make `do_reset` offer/perform cleanup when a round is live. Planner decision (§8.7).
- *Panel checkbox does not track hotkey `r`* (16-12): pick_bridge doesn't observe hotkey-driven mode changes. Candidate: a 1 Hz `after` poll of `::vmd_mouse_mode`/`::vmd_mouse_submode` while a round is live, updating the game_tab radios (programmatic sets fire no -command — the established fact from start_round step 1.5). Cheap but adds a poller; planner decision (§8.8).

---

## 4. Registry / game_state / game_logic gap list

### 4.1 registry.tcl (pure, TDD-able) — 2 new procs recommended

| Gap | Consumer | Proposed shape |
|-----|----------|----------------|
| `hidden_indices {}` → list of registered idx with status==hidden, file/insertion order | reveal-one random pool + hint candidate filtering | `dict for` over `_records`, `lappend` when status eq HIDER_STATUS_HIDDEN. Order-stable (dict iteration order = insertion). |
| `found_indices {}` → list with status==found | found-mgmt count/log lines, smoke asserts | same shape |

NOT needed: per-rep index grouping (the found visual is per-TIER via tier_reps, not per-atom); resid-block changes (untouched).

### 4.2 game_logic.tcl (pure, TDD-able) — counters + log kinds

| Gap | Detail |
|-----|--------|
| `variable reveal_count 0` + `variable hint_count 0` | DIFF-01 (+DIFF-02 forward-compat: the win screen wants BOTH hints used and reveals used — Phase 22). |
| Getters `reveal_count {}` / `hint_count {}` + `increment_reveal {}` / `increment_hint {}` (or a combined `counts {}` getter) | name-VALUE trap: one `variable` per line (14-04 lesson). |
| `round_reset` (86–98) zeroes both | restart→start_round→round_reset gives the "across the game" reset for free; cleanup-button path should also land in round_reset via `end_round` (§3.5). |
| NEW log kinds | `revealed` → "Revealed one! $msg remaining"; `revealed_all` → "Revealed all $msg hiders. Game over." (msg = count); `hint` → "Hint: highlighted neighbors of one hider." — v1 line parity (game.py:269/289/309). Unknown-kind error stays. |

### 4.3 hiders.tcl (mol bridge) — 3 additions (post-18 base!)

`set_found_color {molid colorid}`, `set_found_visible {molid flag}`, `add_hint_rep {molid idx {radius 5} {colorid 3}}`, plus `found_colorid` var (default 7, NOT reset per call) consumed by add_hider_reps line 161. All walk tier_reps via `mol repindex` with the −1/≥numreps guard (the 239–251 pattern). All keep `$sel delete` discipline if they atomselect at all (add_hint_rep does one selection for read-back/num checks — or none: the rep selection string IS the proof; P-1 read-back on style/selection/color suffices).

### 4.4 game_state — recommendation: STAYS 5-KEY post-19

Reveal/hint counters live in game_logic (round-scoped pure model — same layer as the timer/log); found-color preference lives in hiders (the visual half, mirroring 18's "material is visual state owned by hiders" rationale — 18-research §1.5). Nothing Phase 19 needs per-round is missing from the 5-key dict. **Consequence: `phase16_onpick_smoke.tcl` needs NO further gs-shape churn after 18-07's 4→5 update.** If the planner instead stashes found-color in game_state, budget another onpick-shape update — recommend against.

### 4.5 game.tcl — new public procs

`hint {game_state}`, `reveal_one {game_state}`, `reveal_all {game_state}` (+ private `_score_found` refactor candidate). **Explicit-gs signatures** (not current_state readers) so headless smokes can drive them directly through the public surface (on_pick's stash-read exists only because pick_bridge delivers a bare index). Namespace export list (line 36) + header contract updated. `restart`/`cleanup` UNCHANGED (post-18 restart already threads per_mat).

---

## 5. File-ownership matrix (planning waves)

| File | 18 touched? | Phase-19 concerns | Suggested wave |
|------|-------------|-------------------|----------------|
| `vmd/lib/game_logic.tcl` | no | counters, log kinds, round_reset | W1 (pure, parallel) |
| `vmd/tests/test_game_logic.test` | no | counter/kind/reset cases | W1 |
| `vmd/lib/registry.tcl` | no | hidden_indices/found_indices | W1 (parallel) |
| `vmd/tests/test_registry.test` | no | enumeration cases | W1 |
| `vmd/lib/hiders.tcl` | **yes (18-02)** | set_found_color/visible, add_hint_rep, found_colorid, header NEVER-HIDE amendment | W1 (after 18 lands — plans authored against post-18 content) |
| `vmd/lib/game.tcl` | **yes (18-07)** | hint/reveal_one/reveal_all + _score_found refactor + export/header; (optional guard fix) | W2 (depends on W1 all) |
| `vmd/gui/game_tab.tcl` | **no** | buttons, reveals label, dropdowns, end_round, (checkbox-desync poll) | W3 |
| `vmd/gui/dialog.tcl` | **yes (18-10)** | on_hint/on_reveal_one/on_reveal_all/on_restart/on_cleanup (+on_close decision) | W3 (same plan as game_tab or sequential — both files are GUI fan-in) |
| `vmd/gui/setup_tab.tcl` | **yes (18-06/18-08)** | only if the Reset-defect fix is chosen (§8.7) | W3+ (optional) |
| `vmd/lib/pick_bridge.tcl` | no | only if the checkbox-desync fix polls here (bridge is the mode owner) — prefer game_tab-side polling, bridge untouched | W3+ (optional) |
| `vmd/smoke/phase19_actions_smoke.tcl` (new) | — | the headless action proof (§7) | W4 |
| `vmd/smoke/phase16_restart_smoke.tcl` | no | keep green; extend ONLY if restart semantics change (they don't — thin wrapper) | untouched |
| `vmd/smoke/phase16_onpick_smoke.tcl` | yes (18-07, 5-key) | untouched by 19 (game_state stays 5-key) | untouched |
| `vmd/smoke/phase16_gametab_smoke.tcl` / `phase16_entry_smoke.tcl` | no | load-gate extensions (new procs exist) | W3/W4 |
| `vmd/smoke/phase17_capstone_smoke.tcl` | yes (18-12) | untouched by 19 (composition unchanged) | untouched |
| `vmd/tests/rep_verify.tcl` | **yes (18-13: pv_round4)** | pv_round5 (actions round: hint → reveal → restart → cleanup driver steps + reveal-counter logging) | W5, HARD-GATED on 18-13 landed |
| gate plan (docs) | — | full-suite gate (17.1-13/17.2-11/18-14 pattern) | W6 |
| GUI checkpoint (docs, autonomous:false) | — | human verify: confirms, dropdowns, color palette, found hide/show visuals, reveal label, restart/cleanup end-to-end, first-click quirk instructions | W7 LAST |

Wave-1 parallelism: game_logic ∥ registry ∥ hiders are three disjoint files (hiders needs no W1 dependency — its new procs don't call registry/game_logic). W2 (game.tcl) consumes all three. W3 GUI consumes W2. This mirrors 18's wave shape (18-01∥18-03 then 18-07).

---

## 6. Sequencing rules + risks

**Assume DONE at Phase-19 execution time (do not re-prove):**
1. 17.2 complete: residue-kind routing (`tier_kind` "residue" → make_residue_hiders), CA-only sentinels, resid-block fallback in `_resolve_pick`, 17.2-11 capstone rewrite, rep_verify pv_round3.
2. Phase 18 complete INCLUDING its 15-18 checkpoint: 5-arg start_game, 5-key game_state, 3-arg add_hider_reps + tier_materials, materials.tcl + entry wiring, GAME_MATERIALS curated set (final membership set by the 18-15 pick-through verdict — Phase 19 must not assume Glass1/Ghost exist), on_start 5-arg threading, capstone rounds F/G, pv_round4 in rep_verify.
3. Gate numbers move: 205/205 suites → 205+N (test_materials added by 18); 33 smokes at 18-14 (31 + 2 new). Phase 19's gate plan must re-count, not copy stale numbers.

**Must NOT do:**
1. Do NOT touch the two pre-existing stale-pin red smokes (`phase17_dispatch_smoke.tcl` step-8 supply-0 degrade red on 1k8p DNA — recorded fix = drop-ungeneratable-tiers policy; `phase17_licorice_smoke.tcl` P pins — recorded fix = the 17.1-11 corrections {P radius 1.80, tan {0.5 0.5 0.2}}) unless a dedicated gap plan claims them (17.2-11 recipes; STATE.md line 154).
2. Do NOT re-diagnose pick mechanics: the contract is LOCKED (trace primary, `mouse mode pick 2`, first-click p-press quirk is known behavior — vmd/AGENTS.md). Phase 19 adds NO `mouse` commands and NO `mouse callback` usage.
3. Do NOT run/repair `vmd/tests/pick_verify.tcl` (dead hidden_rep/found_rep reads; superseded by rep_verify.tcl).
4. Do NOT introduce ttk::combobox (unverified in this Tk build — 18-06 ban carries to GAME-08's dropdown; use menubutton+menu).
5. Do NOT `grab set` anywhere on the main panel (modeless gate); confirms are `tk_messageBox` (allowed, GUI-only).
6. Do NOT write beta / hide the HIDDEN reps / relax sentinel selectors (`resname GAM and beta < 0` verbatim in any new selection that must identify game atoms; hint's neighbor selection must carry `not resname GAM`).
7. Tcl 8.5 only (no lmap/try/dict-get-default; one `variable` per line; brace expr; `::tk_version` qualifier); 8.6-idiom gate greps COMMENTS too.

**Risks:**
- **R1 — the byte-frozen 16-13 guard vs the restored-original fix.** The guard (game.tcl 149–191) is pinned byte-frozen by 17.x/18. The 17.1-14 Phase-19 candidate fix (hide/deselect the restored original after the guard's cleanup) and the 16-15 view-re-assert candidate BOTH edit the guard branch. Phase 19 must treat this as a DELIBERATE unfreeze: minimal insertion inside the guard's post-cleanup block, with `phase16_restart_smoke.tcl` (stages A1/A2/B/C — including stage C's "restored original SURVIVES loaded" assert, which a `mol off` must not break: assert `displayed` separately, keep the survival assert) + a new headless probe as the regression net. If the planner prefers zero guard risk, scope the fix to a post-guard helper call (one catch-guarded `mol off` line) or defer to a gap plan.
- **R2 — reveal-all's win flow vs state gate.** `finish_win` errors unless playing (game_logic:189–198). Reveal-all during "won" must be blocked by the SAME state gate on_pick uses — put the gate in the lib procs (not only the GUI) so console/accidental calls degrade to no-ops, matching on_pick's defense posture.
- **R3 — confirm dialogs are GUI-only.** `tk_messageBox -type yesno` cannot be exercised headless; the lib procs must be callable WITHOUT confirms (v1 split: GUI confirms, lib acts) so headless smokes drive `game::reveal_one/reveal_all` directly.
- **R4 — PRNG discipline (14-01).** Random reveal/hint picks use the global stream seedless in production; tests must either seed explicitly or use the N=1-pool determinism trick (§7). Never interleave assertions that depend on stream position.
- **R5 — shared `$env(TEMP)/biochemeleon_game.pdb`** forbids parallel VMD runs — all smoke steps sequential (mutation.tcl:610–613).
- **R6 — rep_verify is read by live GUI sessions** — Phase 19 driver edits land only after 18-13's pv_round4 (and after 17.2-12/18-15 sessions close).
- **R7 — mark_found_visual re-assert vs a hidden found rep.** If found reps are currently hidden (GAME-08), a new find still re-asserts modselect on them (fine), but the newly found hider visually disappears into the hidden found rep — acceptable UX (the user hid found hiders), but the plan must note the behavior and the GUI dropdown state must persist across finds. NEEDS-PROBE (tiny): whether `mol modselect` on an off rep flips its showrep state — one line in the phase19 smoke (`mol showrep off` → modselect → read back).

---

## 7. Test strategy per action

Runner rules (inherited): suites under headless VMD with the `BCHM_TEST_RESULT` marker (`bash -ic '... vmd -dispdev text -e vmd/tests/<f> -eofexit < /dev/null'`), parsed from logs never `$?`; smokes PASS=1 ×3 sequential, full-log scan 0 `ERROR)` AND 0 `bad switch`, `Exiting normally`; static gates (8.6-idiom, grab-set) zero; full-suite gate uses the suite_driver.tcl wrapper (17.2-11 carry-forward).

| Action | Pure tcltest | Headless smoke | GUI-only (human-verify) |
|--------|--------------|----------------|--------------------------|
| GAME-05 Hint | — (game_logic `hint` kind + hint_count increment/reset cases) | `game::hint` on a deterministic round (all-but-one-found trick: mark every hider found except one → the random pick is FORCED → PRNG-independent assert): hint rep added (numreps +1), read-back selection == the parenthesized exwithin shape, `not resname GAM` respected (rep num counts only real atoms), hider NOT marked found (status_of unchanged), hint_count incremented; no-neighbor no-op case (isolated hider → no rep, no count) | The orange highlight is visible around (not on) the hider; multiple hints accumulate |
| GAME-06 Reveal-one | game_logic: reveal_count increment, `revealed` log line, round_reset zeroing; registry: hidden_indices shrinks | `game::reveal_one` public-surface: N=1-pool determinism → exact index found; user2 flag set; rep read-back (found rep selection unchanged); remaining decremented; last-hider reveal → finish_win + win flow (frozen elapsed, win_cb fired via a stub callback — the restart_smoke's callback-free registry-side pattern extended) | Confirm dialog wording; counter label updates |
| GAME-07 Reveal-all | same counter/kind cases | `game::reveal_all`: all remaining marked (user2 partition all-found), reveal_count += N, remaining 0, win fired; idempotent second call = no-op (state gate) | Confirm dialog; "Game over." line |
| GAME-08 + DIFF-04 | registry found_indices | `set_found_visible` showrep get roundtrip off/on (probe-proven assertable); `set_found_color` read-back (`molinfo get {color $fidx}` == new ColorID); add_hider_reps uses found_colorid for a non-default value in a fresh round; found_colorid persists across a restart | Dropdown interactions; the color actually renders; hide/show visibly toggles found hiders only |
| GAME-10 Restart | — | `game::restart` via the button's exact call chain: same hider_count + same per_rep stash (keys), NEW game_molid (monotonic), old molid deleted, registry rebuilt, counters zeroed after start_round (GUI path — or assert round_reset effect directly), phase16_restart_smoke stays green | Button → fresh countdown → playable |
| BTN-06 Cleanup | — | `game::cleanup` public surface already covered (15-05/17.x); NEW: post-hint cleanup proves the hint reps die with the molecule (restored numreps == pre-start), restored atom count == original (the pv_cleanup_check proof class) | Button restores the original view/molecule; mouse mode restored |
| DIFF-01 | counter cases (above) | reveal counter survives finds+reveals within a round; resets on restart | Label "Reveals: N" renders + updates |
| Defect fixes | — | `mol off` on the guard-restored original: `molinfo get displayed` == 0, restart_smoke stage-C survival assert adapted (survives + off), new round unaffected | The restored original no longer invites clicks |

**Smoke determinism tricks (established + reused):** (1) all-but-one-found makes random reveal/hint deterministic; (2) explicit `per_rep` rounds fix the tier mix; (3) invariant-based asserts for any residual randomness (never literal draws — 17.1-06/17.2-10/17.2-11 discipline); (4) fresh VMD process per run — pinned PRNG numbers hold only for identical call sequences (17.2-09 carry-forward x).

---

## 8. Open questions for the planner

1. **DIFF-04 color-picker design.** VMD has no per-atom color and no safe "add a color" API in 1.9.3 (`color change rgb <name|id> r g b` mutates a definition GLOBALLY — viewmaster.tcl:411/save_state.tcl:362 precedents; blast radius: every rep using that id changes). Probe-verified: `colorinfo num` = 33 (ids 0–32), ColorID 3 = orange {1.0 0.5 0.0}, 7 = green. **Recommendation: a curated ColorID palette menubutton** (e.g. green 7, red 1, orange 3, yellow 4, cyan 10, pink 9, purple 11, white 8 — exact membership = planner's call, mirroring the GAME_MATERIALS curation pattern + a `GAME_FOUND_COLORS` constant in setup_state if the 18-01 pattern is followed). `tk_chooseColor` (core Tk, exists in 8.5) + `color change rgb` on a RESERVED id is the alternative — rejected as default for the blast radius. NEEDS-PROBE only if the planner wants the RGB path (probe `color change rgb` persistence across `mol delete`).
2. **Restart semantics.** Thin `game::restart` wrapper (16-13-pinned same-count/same-distribution, positions re-randomize) vs v1's form-re-reading restart. Recommendation: the wrapper — it is already built and headless-proven; the guard covers the form-driven variant. ROADMAP SC4's "reset the game" is satisfied by start_round's round_reset.
3. **Cleanup button placement.** Game tab (the 16-12 defect wording: "Game tab has no Cleanup/Restart button") vs Setup Actions row (v1 parity, gui_setup.py:287). Recommendation: Game tab for both Restart and Cleanup (the defect is the authoritative v2 signal); optional Setup-tab Cleanup duplicate is scope creep.
4. **Cleanup-on-close.** 16-14 deferred it to Phase 19. Recommendation: adopt it via the factored `on_cleanup` (cheap, kills the lingering-game-molecule wart) while keeping the 16-13 guard untouched as the safety net.
5. **Hint rep accumulation.** One rep per hint (v1 parity, unbounded but tiny) vs one re-used rep (modselect re-point, bounded, erases earlier hints). Recommendation: per-hint accumulation.
6. **Restored-original fix + view re-assert (R1).** `mol off` the guard-restored original when the new target is a different live molecule (probe-verified mechanism); the 16-15 view wart is arguably FIXED by the same change (an off molecule shows nothing). If the planner defers, record both as deferred warts. Guard-unfreeze risk mitigation in §6-R1.
7. **Setup-Reset expectation mismatch.** Leave as v1 parity (Reset = fields only, documented) vs confirm-dialog vs "Reset also cleans up". Recommendation: minimal — update the button tooltip/label semantics OR a message-box note; any auto-cleanup coupling changes BTN-01's meaning.
8. **Checkbox hotkey-desync fix.** Poll `::vmd_mouse_mode` while a round is live (game_tab-side; pick_bridge untouched) vs defer. Cheap but adds a poller; the defect is cosmetic. Planner's call; not a requirement (not in the Phase-19 req list — it is a 16-12 registered defect).
9. **end_round vs start_round refactor.** Extract the view-state-reset block (start_round steps 1.5 + log clear) into `game_tab::reset_view_state` reused by start_round and end_round (cleanup button) — DRY, low risk. Recommended.
10. **DIFF-02 forward-compat.** Keep `win_cb` 2-arg (elapsed, hider_count) — Phase 22's win-screen stats read `game_logic::hint_count/reveal_count` getters directly from `_show_win_box` instead of widening set_callbacks. Recorded so Phase 19 doesn't prematurely widen the callback contract.
11. **`mol modselect` on a hidden (showrep off) found rep** — NEEDS-PROBE (one line in the phase19 smoke): does the re-assert flip showrep state? Expected no; verify once.

---

## Sources

### Primary (HIGH confidence — read from the repo, cited by file:line)
- `vmd/lib/game.tcl` (full) — start_game 147–410, guard 149–191, cleanup 427–436, restart 452–466, set_callbacks 482–490, _resolve_pick 513–531, on_pick 573–622
- `vmd/lib/game_logic.tcl` (full) — vars 60–75, round_reset 86–98, finish_win 189–198, log model 226–257
- `vmd/lib/registry.tcl` (full) — all 12 procs cited in §1.3
- `vmd/lib/hiders.tcl` (full) — header invariants 1–90, add_hider_reps 121–185 (ColorID 7 at 161), mark_found_visual 220–253
- `vmd/lib/backup.tcl` (full) — snapshot 39–50, apply 70–89, restore 109–114
- `vmd/lib/mutation.tcl` 466–624 — tag_sentinels/_mixed, fetch_hider_indices, mutate
- `vmd/lib/pick_bridge.tcl` (full) — activate 91–134, molid filter 158, deactivate 243–266
- `vmd/gui/dialog.tcl` (full), `vmd/gui/game_tab.tcl` (full), `vmd/gui/setup_tab.tcl` (_dget 56–59, build_actions 234–240, collect_state 251–284, do_reset 586–588)
- `vmd/biochemeleon.tcl` source order 76–118; `vmd/tests/rep_verify.tcl` (driver procs 370–510 + 18-research §6 map)
- `vmd/smoke/phase16_restart_smoke.tcl` (stages 1–60), `vmd/smoke/phase16_onpick_smoke.tcl` (gs-shape asserts 148/152)
- `.planning/STATE.md` (full — 16-12/13/14/15/16/17, 17.1-14, 17.2-09/10/11 decisions), `.planning/REQUIREMENTS.md` (GAME-05..08/10, BTN-06, DIFF-01/04 lines 58–93 + phase map 139–148), `.planning/ROADMAP.md` (Phase 19, lines 215–229), `.planning/config.json` (parallelization true, commit_docs true)
- Phase-18 plans 18-01..18-15 (frontmatter + tasks; 18-07 read in full), `18-RESEARCH-codebase-integration.md` (full)
- `pymol/biochemeleon/game.py` 180–430 (hint/reveal/cleanup), `gui_game.py` 55–240 (buttons/dropdown/color), `__init__.py` 870–920 (restart/cleanup routing), `gui_setup.py` 278–297 (v1 Cleanup button on Setup)

### Probe-verified (HIGH — headless VMD 1.9.3, 2026-09-24, tmp/p19-probe/probe2.tcl, gitignored)
- `exwithin` exists and excludes the anchor; unparenthesized `within ... and not ...` = N=0 (17.2-10 gotcha reproduced), parenthesized = N=39
- `mol showrep <m> <i>` GET = 0/1 and reflects off/on sets in text mode (rep0=1 → off→0 → on→1)
- `mol off/on` round-trip via `molinfo get displayed` (0/1)
- ColorID 3 = orange {1.0 0.5 0.0}, 7 = green {0.0 1.0 0.0}, `colorinfo num` = 33
- `mol new atoms N` molecules have NO timestep — within-family selections error; smokes must use real demo loads for hint-selection asserts

### Shipped-code precedents (MEDIUM-HIGH — vmd-ref, gitignored)
- `mol showrep`: clonerep.tcl:106/150, viewmaster.tcl:259/322, save_state.tcl:88/232
- `mol off/on`: ramaplot.tcl:523/656, viewmaster.tcl:235 (`displayed`)
- `color change rgb`: viewmaster.tcl:411 (name form), save_state.tcl:362 (id form)
- No `exwithin`/`tk_chooseColor` usage anywhere in vmd-ref (probe settled exwithin anyway; tk_chooseColor remains a Tk-core assumption — GUI-only)

## Metadata

**Confidence breakdown:**
- Proc inventory + seam contract: HIGH — full-file reads, all cited; post-18 contract read from the 18 plans themselves (not inferred)
- Attachment map: HIGH for lib/GUI structure; MEDIUM for exact widget placement inside game_tab build (planner's layout call)
- VMD behavior claims: HIGH where probed (exwithin/showrep/mol off/ColorIDs), MEDIUM where only shipped-code precedent (color change rgb blast radius)
- Sequencing/waves: MEDIUM-HIGH — follows the verified 17.x/18 wave precedent; orchestrator may re-cut

**Research date:** 2026-09-24
**Valid until:** ~2026-10-24 (stable domain; re-verify only if Phase 18 execution changes the game.tcl/hiders.tcl shapes beyond the planned seams)

## RESEARCH COMPLETE
