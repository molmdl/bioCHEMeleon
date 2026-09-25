# Phase 20: Persistence (Combined-PDB + .bcm JSON) — Integration + GUI Seams Research

**Researched:** 2026-09-26
**Domain:** Seam surface of Save (GAME-09) / Import (GAME-04) / Generate & export (BTN-05) against the PLANNED post-18/19 code state
**Confidence:** HIGH (all seams read from landed code or pinned PLAN must_haves; v1 workflow precedent read from shipped `pymol/biochemeleon/`)

**Scope note:** Two sibling researchers cover (a) v1 carryover / .bcm format design and (b) VMD/Tcl zip + JSON + reload mechanics. This document pins the **integration surface**: which procs/files/handlers/state the three features hook, and how the three workflows flow through the GUI. Where a design choice is forced (timer resume, generate-only path, module slot), the pinned seam facts + v1 precedent are given and the final call is flagged for the planner.

---

## Executive summary

Phase 20 hooks into a codebase whose Phase 18/19 seams are **planned but not landed**. The authoritative seam is therefore a *contract surface*, read from the pinned `must_haves`/`key_links` of 18-05/18-07/18-10 and 19-01..19-13 PLANs, plus the current `vmd/lib` + `vmd/gui` code. Three facts dominate the design:

1. **`start_game` never touches `game_logic`** — the round state machine (idle→countdown→playing→won), timer, and counters are PURE-model state driven entirely by the GUI's `start_round` chain. This makes **Generate & export without starting the game trivially clean**: call `start_game` (molecule mutated, registry populated, hiders rendered), do **not** call `game_tab::start_round` — the state machine stays `idle`, picks no-op via on_pick's state gate, and the timer never arms. v1 did exactly this (`_on_export` reused `_prepare_and_start`, stayed on Setup, kept the round live so Cleanup worked).
2. **The only missing lib seam is the timer-resume hook — and it already exists.** `game_logic::timer_start` takes an optional `now` injection argument (`game_logic.tcl:151-158`). Resuming a saved mid-game = replay the countdown (v1-parity) and, at the GO branch, rebase the epoch with `timer_start [expr {[clock seconds] - $saved_elapsed}]`. Zero game_logic changes required. The same rebase trick implements v1's pause-capture-dialog-save-resume pattern around the Save file dialog (v2's `after` timers keep ticking under modal boxes — documented 19-08/19-10 behavior — so the rebase is what actually excludes dialog time).
3. **Everything the .bcm sidecar must carry beyond the combined PDB is exactly the data `writepdb` loses**: per-index found status (user2) and per-index tier/rep (user3) are PDB-lost fields (15-02-SUMMARY:138; 15-RESEARCH-pdb-rebuild.md:23), while resname/beta/segid/coords/elements survive PDB columns. The rebuild chain on Import is a **reassembled `start_game` steps 8-13** using existing procs: `backup::apply` (viewpoint+reps from the sidecar) → `stamp_tier_codes` → `add_hider_reps` → `reconstruct_from_sentinels` (DI) → `assign_reps` → `register_resid_block` (rebuilt from CA resids) → found reconcile via `mark_found_visual`+`mark_found`.

**Primary recommendation:** Build Save/Import/Export as three dialog-scope handlers (`::biochemeleon::on_save_game` / `on_import_game` / `on_export_game`, the BTN-07 fan-in pattern), two Game-tab buttons (Import puzzle… / Save checkpoint, v1-verbatim, in a new bottom-packed row above the 19-08 Actions labelframe), one Setup-tab button (Generate & export between Load Setup and Start per spec order), a shared "prepare" extraction of `on_start` steps 1-3 for the Export path, a **pure** `lib/persistence.tcl` JSON codec (tcltest-able in WSL) + a mol-bridge export/reload path, and a phase20 headless smoke that proves the full save→cleanup→import→resume loop with the 19-05 stub-callback idiom.

---

## Seam inventory table

Status legend: **EXISTS** = in current code (file:line verified) · **P-18** = planned by Phase 18 (PLAN pinned) · **P-19** = planned by Phase 19 · **NEW** = Phase 20 must create.

### A. State capture surface — what Save reads at click time

| # | Datum | Owning module / proc | file:line | Status | Notes |
|---|-------|----------------------|-----------|--------|-------|
| A1 | Live combined molecule | `game_state.game_molid` (GUI stash `::biochemeleon::game_tab::game_state`, mirrored in `game::current_state`) | game_tab.tcl:181 (stash write), game.tcl:407-408 (stash build) | EXISTS | The atomselect-writepdb source. Same molecule `start_game` returned. |
| A2 | Combined-PDB bytes | `mutation::mutate` temp output `$::env(TEMP)/biochemeleon_game.pdb` (fallback `[pwd]/biochemeleon_game.pdb`) **or** fresh `[atomselect $game_molid all] writepdb` | mutation.tcl:609-615 | EXISTS (both paths viable) | Mechanics researcher picks; either yields the same atom order → stable indices. R5 caveat if the temp file is reused (shared path, sequential VMD runs only). |
| A3 | Original PDB path + user viewpoint + user reps | `backup::snapshot` → dict `{molid filename viewpoint reps}` stashed as `game_state.snapshot` | backup.tcl:39-50; game.tcl:194 | EXISTS | `filename` = the original PDB path (GAME-09 requirement "original PDB path"); `reps`+`viewpoint` = what Import re-applies. |
| A4 | Registry status per index | `registry::_records` (`idx → {rep status}`); readers `status_of` / `count_remaining` / `remaining_by_rep` | registry.tcl:20, 99, 110, 126 | EXISTS | Found-set = walk `_records` for `status eq found`. `found_indices` getter is **P-19-01** (19-10's on_found_mgmt consumes it) — Save may use it or walk `_records` directly. |
| A5 | Rep (tier) per index | registry record `.rep` field, bulk-written by `assign_reps` | registry.tcl:153-181 | EXISTS | Needed on Import to re-stamp user3 + rebuild rep pairs (writepdb loses user3). |
| A6 | Resid block (fake-resid → CA index) | `registry::_resid_block`; `register_resid_block` (wholesale replace) | registry.tcl:26, 218-231 | EXISTS | Import-side rebuild options: carry in .bcm **or** re-derive from the reloaded CAs (`atomselect index $idx get resid` — the game.tcl:393-402 zip is the template). Re-derivation is self-healing; simple-tier hiders share resid 9001 but `is_hider` short-circuits before the fallback (registry.tcl:194-201) so a CA-only rebuild is correct. |
| A7 | Timer elapsed (seconds) | `game_logic::timer_elapsed` (drift-free `now - timer_epoch`; frozen final in `won`) | game_logic.tcl:163-177, epoch var :69 | EXISTS | Save stores **elapsed only**, never the wall-clock epoch (meaningless on another machine). `won` saves store the frozen `timer_elapsed_final`. |
| A8 | State-machine position | `game_logic::state` (`idle/countdown/playing/won`) | game_logic.tcl:202-205 | EXISTS | Save only meaningful in `playing`/`won` (v1 guard `__init__.py:753-755` refused pre-GO saves). |
| A9 | reveal_count / hint_count | P-19-02: 0-arg getters `reveal_count`/`hint_count`, incrementers `increment_reveal {{n 1}}` / `increment_hint`, zeroed by `round_reset` | 19-02-PLAN must_haves | P-19 | **No setters planned.** Restore = `round_reset` then `increment_reveal $saved_n` / `increment_hint $saved_n` — works with the pinned seam as-is. |
| A10 | Found-color preference | `hiders::found_colorid` namespace var (default 7; persists across rounds; NOT setup form state) | P-19-04 (19-RESEARCH-mechanisms §C, :397) | P-19 | v1 carried `_found_color` in the sidecar (persistence.py:106; game.py:336 apply) — same intent. Save carries the ColorID. |
| A11 | Setup dict (11 keys, DEFAULTS order) | `setup_tab::collect_state` → `setup_state::validate_state` | setup_tab.tcl:251-285; setup_state.tcl:126-197 | EXISTS | `collect_state` post-P-18-08 also emits `material_blending` + `per_mat` (18-08). Save should store the **validated** dict (the do_save discipline, setup_tab.tcl:632). |
| A12 | Setup per_mat + material_blending | P-18-01 (DEFAULTS gains the 2 keys) + P-18-08 (collect_state emits) + P-18-05 (`.bcm` setup-file line family `per_mat_count`/`per_mat_entry`) | 18-01/18-05/18-08 PLANs | P-18 | The Setup-`.bcm` format grows before Phase 20; the game-`.bcm` sidecar embeds the same validated dict. |
| A13 | Resolved per_mat (round's actual) | `game_state.per_mat` — 5th gs key (RESOLVED dict stashed) | P-18-07 must_haves | P-18 | Mirror of 17.1-06's resolved-`per_rep` precedent. Import re-applies via `add_hider_reps`' 3rd `mat_specs` arg (P-18-02). |
| A14 | Round kind + version tags | `kind` (`checkpoint`/`puzzle`) + sidecar version line | v1 persistence.py:95-103 (kind, started, timer_elapsed); SETUP_FORMAT precedent setup_state.tcl:13 | NEW | v1 forced `started=False` for puzzles; v2's analog is "state machine stays idle" (no field needed) — but keep `kind` for the loader's expectations + future divergence. |
| A15 | GUI stash access helper | `::biochemeleon::_game_stash` (private, returns stash dict or empty) | P-19-10 Task 1 (pinned code in PLAN) | P-19 | All three Phase-20 handlers read the round through it. |

### B. Import/resume rebuild surface — the reassembled start_game steps 8-13

| # | Step | Owning proc | file:line | Status | Notes |
|---|------|-------------|-----------|--------|-------|
| B1 | `mol new` combined PDB | `mol new $path type pdb` (the backup::restore idiom) | backup.tcl:111 | EXISTS | New monotonic molid; sentinel columns survive. |
| B2 | Re-apply viewpoint + user reps | `backup::apply {snapshot molid}` — reads ONLY `reps` + `viewpoint` keys of the snapshot dict | backup.tcl:70-89 | EXISTS | A minimal snapshot dict reconstructed from the sidecar (`dict create molid - filename <combined.pdb> viewpoint … reps …`) feeds `apply` unchanged. |
| B3 | Stamp user3 tier codes | `hiders::stamp_tier_codes {molid tier_of}` | hiders.tcl:199-209 | EXISTS | **ORDERING CONTRACT: must run BEFORE add_hider_reps** (hiders.tcl:25-29) — a rep added before stamping caches an empty selection forever. |
| B4 | Rebuild hider rep pairs | `hiders::add_hider_reps {molid specs {mat_specs {}}}` (3rd arg = P-18-02) | hiders.tcl:121-185 | EXISTS / mat_specs P-18 | Tier specs derived from the sidecar's rep-per-index map: distinct reps in GAME_REPS order → codes 1..N (`rep_tiers::style_args` supplies style args, game.tcl:376-380 template). |
| B5 | Reconstruct registry from sentinels | `registry::reconstruct_from_sentinels {fetch_prefix {rep ""}}` with the DI atomselect lambda | registry.tcl:44-51; lambda template game.tcl:323-328 | EXISTS | ONE call, 1-arg (P8 — a second call clears prior records). ALL records land `hidden`. |
| B6 | Assign reps | `registry::assign_reps {idx→rep}` | registry.tcl:170-181 | EXISTS | Atomic validate-then-apply; every idx must be registered first (B5 before B6). |
| B7 | Register resid block | `registry::register_resid_block {resid→idx}` | registry.tcl:218-231 | EXISTS | See A6 for the rebuild choice. |
| B8 | Found-status reconcile | `hiders::mark_found_visual {molid idx}` + `registry::mark_found {idx}` (the `_score_found` mark pair, P-19-05) | hiders.tcl:220-253; registry.tcl:63-70 | EXISTS | Loop over the sidecar's found indices. mark_found_visual re-asserts ALL pairs' modselect (the static-molecule re-eval rule). |
| B9 | Timer resume | `game_logic::timer_start {{now {}}}` — the `now` injection hook | game_logic.tcl:151-158 | EXISTS | Rebase at GO: `timer_start [expr {[clock seconds] - $saved_elapsed}]`. **No begin_play change needed** (begin_play runs first with the real clock, then the rebase overwrites the epoch). |
| B10 | Counters restore | P-19-02 `increment_reveal $n` / `increment_hint $n` after `round_reset` | 19-02-PLAN | P-19 | Increment-from-zero is the setter-free restore. |
| B11 | State machine → playing | **NO resume transition exists** — only `round_reset → begin_countdown → countdown_tick ×4 → begin_play` | game_logic.tcl:86-147 | GAP (by design) | v1 ALSO replays the countdown (`start_countdown` → `_begin_play` with `_start_time = time.time() - elapsed`, gui_game.py:234-281). v2 replays via `game_tab::start_round` unchanged; the rebase (B9) happens in the GO branch. Channel for `$saved_elapsed` into countdown_step's GO branch: a `game_tab` namespace var (e.g. `resume_elapsed`, set by the import handler before `start_round`, consumed + cleared at GO) — zero lib changes. |
| B12 | GUI re-arm | `game_tab::set_difficulty` + `game_tab::start_round {gs}` (stop timers → reset_view_state [P-19-08] → stash → set_callbacks → round_reset → begin_countdown → log → update_remaining → countdown_step) | game_tab.tcl:153-222; set_difficulty :425-433 | EXISTS | `start_round` sets the stash itself (:181) — the import handler just calls it with the reconstructed gs. |
| B13 | Teardown of a prior live round before import | The P-19-10 `on_cleanup` flow: `stop_all_timers` + `pick_bridge::deactivate` + `game::cleanup $gs` + `end_round` + stash clear | P-19-10 Task 2 (pinned flow); game.tcl:427-436 | P-19 | Import into a live session MUST tear down first (v1 did: `__init__.py:828-835`). |

### C. Generate & export surface

| # | Step | Owning proc | file:line | Status | Notes |
|---|------|-------------|-----------|--------|-------|
| C1 | Collect + resolve target + validate | `on_start` steps 1-3 (`setup_tab::collect_state` → target resolution per mode → `validate_state` against `demos::atom_count`) | dialog.tcl:146-192 | EXISTS | v1 factored this into `_prepare_and_start` shared by Start + Export (`__init__.py:263-346`, behavior-preserving extraction, verified 08-04). v2's `on_start` is NOT yet factored — **Phase 20 should extract a shared prepare helper** (or accept duplication; extraction is the v1-proven shape). |
| C2 | 5-arg start_game call with per_mat toggle gating | P-18-10: `set pm {}; if blending → pm = per_mat`; `start_game $molid $hc $per_rep $lock_scene $pm` | 18-10-PLAN Task 1 (patches dialog.tcl:209-212) | P-18 | The shared prepare must preserve this gating verbatim. |
| C3 | Generate (no play) | `game::start_game` — mutates molecule, populates registry, adds reps, stashes `current_state` — **touches NO game_logic state** | game.tcl:147-410 (no game_logic reference anywhere in the body) | EXISTS | The load-bearing fact: skipping `start_round` leaves the model `idle`; picks no-op (state gate game.tcl:579); timer never arms. This IS the "generate only" path — no dry-run flag needed. |
| C4 | Post-export cleanup affordance | Stash the exported round's gs into `::biochemeleon::game_tab::game_state` so P-19-10's `on_cleanup` guards (`_game_stash` non-empty) admit it | P-19-10; v1 kept `controller._started=True` so Cleanup worked (`__init__.py:720`) | NEW (GUI) | Without the stash, Cleanup says "No game round to clean up." and the educator cannot restore the scene — breaking v1's promised UX ("press Cleanup to restore your scene"). |
| C5 | Export-cancel semantics | Cancel dialog → `game::cleanup $gs` + clear the stash (v1: `controller.cleanup()` on cancel, `__init__.py:697-700`) | game.tcl:427-436 | NEW (GUI) | Prevents lingering generated hiders on a cancelled export. |
| C6 | Restart-after-export note | P-19-10 `on_restart` replays the stashed round (guard passes once C4's stash exists) | P-19-10 | P-19 | Acceptable behavior (same-count replay of the exported round); document, don't block. |

---

## Three workflow state machines (proc-level call chains)

### W1 — Save checkpoint (GAME-09, Game tab)

```
[Game tab] "Save checkpoint" (ttk::button, new begin-row)
  └─> ::biochemeleon::on_save_game                (dialog.tcl, NEW, 0-arg)
       1. set gs [_game_stash]                    (P-19-10 helper)
          guard: [dict size $gs] == 0 → info box "No game round to save." + return   (NEW copy — v1 silently returned, __init__.py:753-755; v2's restart/cleanup precedent is an info box)
          guard: [game_logic::state] eq "countdown" → info box (pre-GO save refused, v1 parity) — "playing"/"won" both allowed
       2. PAUSE-CAPTURE (v1 __init__.py:756-757):
          set elapsed [game_logic::timer_elapsed]        ;# frozen final if won
       3. tk_getSaveFile  -defaultextension ".bcmz" -title "Save bioCHEMeleon checkpoint"
          -filetypes {{bioCHEMeleon game} {.bcmz}} {{All files} {*}} -parent $w
          (template: setup_tab do_save setup_tab.tcl:621-624; title v1-verbatim __init__.py:759)
          cancel ($fname eq "") → rebase timer (step 7) + return
       4. Build the sidecar (pure codec, NEW lib/persistence.tcl):
          bcm = { kind "checkpoint"
                  version <sidecar-version>
                  timer_elapsed $elapsed
                  reveal_count [game_logic::reveal_count]        (P-19-02)
                  hint_count  [game_logic::hint_count]           (P-19-02)
                  found_colorid [hiders::found_colorid]          (P-19-04)
                  registry  {idx → {rep status}} walk of registry::_records
                  setup     [setup_tab::collect_state → validate_state]  (A11/A12)
                  snapshot  {viewpoint reps filename} from [dict get $gs snapshot]  (A3) }
          + write combined PDB (A2 path chosen by mechanics research)
          + zip into .bcmz (mechanics research)
          whole build+write inside catch → warning box "Save failed: $err" + rebase + return
       5. SUCCESS box optional / log line:
          v1 logged "Saved checkpoint to %s" (game_tab._log, __init__.py:788).
          v2 note: log_append has NO generic info kind — unknown kind ERRORS
          (game_logic.tcl:244-246). Options: (a) direct
          `game_tab::on_log_line "Saved checkpoint to $fname"` (diverges the
          model/view contract slightly), (b) add an `info` log kind to
          game_logic (tiny P-19-02-class extension), (c) vmdcon -info only.
          Planner pins; (b) is the cleanest model-consistent choice.
       6. (game state unchanged — the round continues live)
       7. RESUME / rebase (ALL exit paths — v1 rebased on cancel, failure, AND
          success, __init__.py:763/782/786):
          game_logic::timer_start [expr {[clock seconds] - $elapsed}]
          (the exported optional `now` arg — game_logic.tcl:151-158; excludes
          dialog+save time from the epoch; the 1 Hz tick kept ticking under
          the modal dialog — cosmetic drift removed here)
```

### W2 — Import / resume (GAME-04, Game tab)

```
[Game tab] "Import puzzle…" (ttk::button, new begin-row)
  └─> ::biochemeleon::on_import_game               (dialog.tcl, NEW, 0-arg)
       1. tk_getOpenFile -defaultextension ".bcmz" -title "Import bioCHEMeleon game"
          -filetypes {{bioCHEMeleon game} {.bcmz}} {{All files} {*}} -parent $w
          cancel → return (true no-op)
       2. Read .bcmz → combined.pdb path + bcm dict (persistence lib, NEW;
          mechanics research owns unzip). catch → warning "Import failed: …"
          + return (v1 copy __init__.py:813-815). Version-tag mismatch →
          dedicated warning + return.
       3. TEARDOWN any live round (P-19-10 flow, B13):
          game_tab::stop_all_timers; catch {pick_bridge::deactivate};
          catch {game_tab::unregister_mode_trace};   (P-19-08, catch-guarded)
          set gs_old [_game_stash]; if non-empty { game::cleanup $gs_old }
          game_tab::end_round;  set ::biochemeleon::game_tab::game_state [dict create]
       4. set molid [mol new $combined_pdb type pdb]        (B1)
       5. Build the minimal snapshot from the sidecar and apply view/reps:
          backup::apply [dict create molid - filename $combined_pdb \
            viewpoint [bcm viewpoint] reps [bcm reps]] $molid   (B2 — apply
          reads only reps+viewpoint; backup.tcl:70-89)
       6. Registry rebuild (the reassembled start_game steps 9-11-13-14):
          registry::reconstruct_from_sentinels [list apply {{molid} {
              set sel [atomselect $molid "resname GAM and beta < 0"]
              set ids [$sel get index]; $sel delete; return $ids
          }} $molid]                                            (B5, ONE call)
          registry::assign_reps $idx_to_rep                     (B6, sidecar A5)
          registry::register_resid_block $resid_map             (B7, A6 —
          re-derived from CA resids or carried; planner pins with mechanics)
       7. Hider visuals (ORDER: stamp BEFORE reps — hiders.tcl:25-29):
          hiders::stamp_tier_codes $molid $tier_of              (B3)
          hiders::add_hider_reps $molid $specs $mat_specs       (B4; mat_specs
          from bcm per_mat, P-18-02's 3rd arg; {} = pre-18 byte-compat)
       8. Found reconcile:
          foreach idx $found_indices {
            hiders::mark_found_visual $molid $idx               (B8)
            registry::mark_found $idx }
       9. Model restore:
          game_logic::round_reset
          game_logic::increment_reveal [bcm reveal_count]       (P-19-02, B10)
          game_logic::increment_hint  [bcm hint_count]
          hiders::set_found_color $molid [bcm found_colorid]    (P-19-04; the
          preference call is legal pre-found per 19-04)
       10. Build the imported gs:
          set gs [dict create game_molid $molid \
            hider_count [registry::count_hiders] \
            snapshot  [backup::snapshot $molid]   ;# POST-import snapshot —
            ;# cleanup/restart then restore to the IMPORTED state (all-hidden
            ;# hiders present), the v1 _on_restart_imported semantics
            per_rep   [bcm per_rep]  per_mat [bcm per_mat]]
       11. Resume channel + GUI re-arm:
          set ::biochemeleon::game_tab::resume_elapsed [bcm timer_elapsed]   (NEW var)
          game_tab::set_difficulty [bcm difficulty_easy]
          game_tab::raise_tab
          game_tab::start_round $gs                              (B12 — replays
          the countdown v1-style; at the GO branch countdown_step consumes
          resume_elapsed: after begin_play, IF resume_elapsed > 0 {
            game_logic::timer_start [expr {[clock seconds] - $resume_elapsed}] }
          then clears the var). Timer RESUMES from the saved elapsed —
          v1-exact ("resume from saved elapsed", gui_game.py:277-278).
       NOTE (won-state edge): importing a save whose remaining==0 leaves the
       model `playing` with 0 remaining; the first pick immediately fires the
       win path (on_pick → _score_found never runs; actually remaining==0 +
       state playing → any hidden==none, a pick resolves miss/already → the
       win never refires — the round sits finished but unwon-flagged).
       Options: (i) refuse wins-in-sidecar saves with an info box, (ii) after
       reconcile, if count_remaining==0 → immediately finish_win + win log +
       win_cb. Planner pins; (ii) is v1-closest (import_state applied the
       state as-is and the GUI showed the finished round).
```

### W3 — Generate & export (BTN-05, Setup tab)

```
[Setup tab] "Generate & export" (ttk::button in build_actions, between
            $f.load and $f.start — spec order #5, spec.md:20; Cleanup model
            is Game-tab-ONLY per 19-08's locked comment, so spec's 7-button
            order collapses to: reset/random/save/load/EXPORT/start)
  └─> ::biochemeleon::on_export_game               (dialog.tcl, NEW, 0-arg)
       1-3. SHARED PREPARE with on_start (C1): collect_state → resolve target
       (loaded/demo/fetch error boxes identical) → validate_state vs
       atom_count. Extraction of on_start steps 1-3 into a shared helper is
       the v1-proven refactor (_prepare_and_start, __init__.py:263-346,
       "behavior-preserving extraction"); the P-18-10 5-arg + toggle gating
       (C2) rides in the shared call.
       4. catch {pick_bridge::deactivate}               (16-14 gap-1, as on_start)
       5. set gs [start_game …5-arg…]  → molecule mutated, registry live,
          hider reps rendered. NO start_round — model stays idle (C3).
          failure → warning box + return (no partial state; on_start parity).
       6. Stash for Cleanup: set ::biochemeleon::game_tab::game_state $gs   (C4)
       7. tk_getSaveFile -defaultextension ".bcmz" -title "Generate & export puzzle"
          -filetypes {{bioCHEMeleon game} {.bcmz}} {{All files} {*}} -parent $w
          cancel ($fname eq "") → game::cleanup $gs + clear the stash + return
          (C5; v1 __init__.py:697-700)
       8. Build sidecar kind="puzzle": timer_elapsed 0, counters 0, registry
          all-hidden (fresh round), found_colorid, setup dict, snapshot
          view/reps — + combined PDB + zip. catch → warning "Export failed: …"
          (v1 :713-714 copy) + KEEP the stash (retry possible; on_cleanup's
          failure-keeps-stash convention, P-19-10).
       9. SUCCESS info box (v1-verbatim-able, __init__.py:716-719):
          "Saved puzzle to:\n%s\n\nYour model still has the generated
          hiders. Press Cleanup to restore your scene."
       10. STAY on the Setup tab (no raise_tab, no start_round, no countdown).
```

---

## GUI wiring spec

### Button placement (v1 precedent + pinned v2 layout)

| Button | Tab | Where exactly | Precedent |
|--------|-----|---------------|-----------|
| **Save checkpoint** (GAME-09) | Game | New begin-row **above** the Actions labelframe | v1 `gui_game.py:87-97`: `begin_row` (Import + Save) added BEFORE `btn_row` so it renders above. v2 pack mechanics (19-08 §3.2): bottom packs stack upward — pack the new row `-side bottom -fill x` **AFTER** `pack $af -side bottom …` (19-08's Actions frame), so it lands above Actions. Widget path suggestion: `$parent.actions` exists (19-08); the new row = a `$parent.beginrow` frame packed after $af. |
| **Import puzzle…** (GAME-04) | Game | Same begin-row, left of Save | v1 `gui_game.py:88` ("Import puzzle…", tooltip "Load a puzzle prepared by 'Generate & export' and play it."). 19-RESEARCH-gui:60 already slots these two as Phase-20 Game-tab widgets. |
| **Generate & export** (BTN-05) | Setup | `build_actions` row, **between $f.load and $f.start** | v1 `gui_setup.py:279-299` order: reset, random, save, load, **export**, cleanup, start. v2 post-19 has no Setup Cleanup (19-08 locked: Game-tab only), so the row becomes reset/random/save/load/**export**/start. spec.md:20 pins export as button 5 of 7. |

Button classes: `ttk::button` (the exercised v2 class everywhere). Labels v1-verbatim: "Import puzzle…", "Save checkpoint", "Generate & export" (ellipsis char U+2026 in v1 — keep or ASCII-ize consistently with "Save Setup…"/"Load Setup..." already in setup_tab.tcl:238-239, which use ASCII "..."; **match the existing ASCII style**).

### Handler wiring (BTN-07 fan-in convention)

- All three handlers live in **`vmd/gui/dialog.tcl`** at `::biochemeleon::` scope — the on_start precedent (`setup_tab.tcl:229-232` comment: dialog scope avoids cross-tab reach-ins) and the P-19-10 fan-in pattern exactly.
- Suggested pinned names (planner must pin them in the phase-20 contract, the way 19-08/19-09/19-10 interlocked): `::biochemeleon::on_save_game`, `::biochemeleon::on_import_game`, `::biochemeleon::on_export_game` — all 0-arg.
- Button `-command` literals: `-command {::biochemeleon::on_save_game}` etc. (the 19-08 exact-literal style).
- The handlers reach the round ONLY through `_game_stash` (P-19-10) and set `::biochemeleon::game_tab::game_state` via the fully-qualified path (the parameter-shadow lesson, game_tab.tcl:177-181).
- `game_tab.tcl` needs **no new exported procs** for Phase 20 (maybe a private resume-elapsed var; handlers never call game_tab internals beyond the existing `start_round`/`raise_tab`/`set_difficulty`/`stop_all_timers`/`end_round`).

### New namespace var

- `::biochemeleon::game_tab::resume_elapsed` — set by `on_import_game` before `start_round`, consumed + cleared in `countdown_step`'s GO branch (after `begin_play`). Must be declared with `variable resume_elapsed` (one per line, the 14-04 rule) and NOT initialized at source if the load-gate asserts widget vars unset — declare it in the vars block and initialize lazily via `info exists` (or initialize to 0 at source; it is not widget-bound — planner's call, note the phase16_gametab_smoke §4 assert only checks the six listed vars).

### Dialog patterns (all verified in-repo)

| Pattern | Template | Reference |
|---------|----------|-----------|
| Save dialog | `tk_getSaveFile -defaultextension ".bcmz" -title … -filetypes [list {{bioCHEMeleon game} {.bcmz}} {{All files} {*}}] -parent $w` | setup_tab.tcl:621-624 (do_save) |
| Open dialog | `tk_getOpenFile` same shape | setup_tab.tcl:681-684 (do_load) |
| Cancel test | `if {$fname eq ""} { return }` | setup_tab.tcl:625, 685 |
| Warning box | `tk_messageBox -parent $w -icon warning -title "bioCHEMeleon" -message …` | throughout dialog.tcl / P-19-10 |
| Info box | `-icon info` | v1 export-success box; on_restart/on_cleanup guards (P-19-10) |
| Confirm box | NOT needed for any Phase-20 button (v1 had none on Save/Import/Export) | — |

---

## Error UX

| Case | Behavior | Source of the pattern |
|------|----------|----------------------|
| Save/Export/Import dialog **cancelled** | Save: rebase timer, return, round untouched. Export: cleanup the generated hiders + clear stash (v1 parity). Import: silent return. | v1 __init__.py:697-700, 761-765; setup_tab.tcl:625 |
| Save with **no round** (empty stash) | Info box "No game round to save." (NEW copy — v1 silently returned; v2's on_restart/on_cleanup precedent is an info box) | P-19-10 Task 2 |
| Save during **countdown** (pre-GO) | Refuse with info box (v1 refused via `_start_time is None`); `won` saves ARE allowed (frozen elapsed) | v1 __init__.py:753-755 |
| Save/Export **write failure** | Warning box "Save failed:/Export failed: $err"; Save additionally rebases the timer; Export keeps the stash for retry | v1 __init__.py:779-784, 712-715; P-19-10 cleanup-keeps-stash |
| Import **unreadable/corrupt** .bcmz | Warning box "Import failed: Could not read game file:\n$err" (v1-verbatim copy) | v1 __init__.py:812-815 |
| Import **version mismatch** | Sidecar `format`/version line compared at load; mismatch → dedicated warning naming the expected tag (the `format biochemeleon-setup-v2` discipline, demos.tcl:119 + setup_state.tcl:13) | demos.tcl:115 comment "lets a future loader reject mismatched versions" |
| Import **validate failure** (registry/rep mismatch vs sentinels) | Warning box "Import failed: Could not restore game state:\n$err" + leave the prior session torn down but stable (no partial game) | v1 __init__.py:859-864 |
| v1's **name-collision** refuse-first | **N/A in v2** — VMD has no named objects; molids are internal, `mol new` never collides. The v2 analog (import while a round is live) is handled by the mandatory teardown (W2 step 3). | v1 __init__.py:819-827 vs vmd/AGENTS.md molid rules |
| Export **success** | Info box (v1 copy, W3 step 9) — stays on Setup | v1 __init__.py:716-719 |
| Save **success** | Log line "Saved checkpoint to <path>" (channel decision: new `info` log kind vs direct on_log_line — see W1 step 5) | v1 __init__.py:788 |

---

## Testing seams + headless coverage plan

### Conventions (verified from phase16_gametab_smoke.tcl + 17.1-13-PLAN + 19-05-PLAN)

- Smokes are `-e`'d headless scripts: `[pwd]` staging root (NOT `[info script]`, empty under `-e`), source lib deps in dependency order, assert with failure-list accumulation, end with the `BCHM_SMOKE_RESULT PASS=1 FAIL=none` marker line. **The runner greps the marker, NEVER `$?`** (VMD drops exit codes), and always full-log-scans for `0 ERROR)` / `0 bad switch` + `Exiting normally`.
- Fresh staging copy per plan (`tmp/p20-XX/`), **VMD runs SEQUENTIAL** (R5: shared `$env(TEMP)/biochemeleon_game.pdb`).
- Pure-layer codecs → `tcltest` suites (`vmd/tests/test_persistence.test` class) runnable via plain `tclsh` in WSL — the JSON round-trip SC4 is testable WITHOUT VMD (huge win; mirrors test_registry.test).
- FULL-SUITE gate pattern (17.1-13): run EVERY suite+smoke staged, grep each log for its marker AND the two greps; record a table; reds outside file scope → defect record, not cross-file fixes.
- Stub-callback idiom for driving game flows headlessly (19-05 pinned): `game::set_callbacks` with `log → lappend ::P_LOG`, `remaining → incr ::P_REM`, `win → lappend ::P_WIN [list $elapsed $hc]`; drive the pure machine per round (`round_reset + begin_countdown + countdown_tick ×4 + begin_play`).

### What is headless-testable per workflow

| Workflow | Headless | Human-verify |
|----------|----------|--------------|
| Save | ALL lib+codec paths: capture surface reads (A1-A13), combined-PDB write, JSON encode/decode round trip, zip. Drive a real round (start_game on a bundled demo), make a find (registry::mark_found + mark_found_visual), save-side build → assert file contents. | The tk_getSaveFile dialog + button click |
| Import/resume | The whole rebuild chain (W2 steps 4-11) as lib-level calls: mol new + backup::apply + stamp/add reps + reconstruct/assign/resid + reconcile + counters + timer rebase math. Assert: registry counts/statuses, user2/user3 read-backs (FLOAT compare), numreps, timer_elapsed ≈ saved elapsed. GUI `start_round` chain is source-load-gated only. | Import dialog + resumed gameplay (a find after import scores) |
| Generate & export | start_game generate-only (assert `game_logic::state` eq "idle", numreps grown, registry populated, timer_elapsed 0) + sidecar build with kind=puzzle. | Setup-tab click + success box + Cleanup restores |

### What a phase20 smoke should prove (recommended asserts)

1. Round-trip SC2/SC4: start_game → find k hiders → save-side build (combined PDB + .bcm to tmp) → `game::cleanup` → import-side rebuild from the saved files → assert: `count_hiders` == N, per-index `status_of` matches the saved found-set, `remaining_by_rep` matches, atomselect `user2` read-back 1.0 on found CAs, `numreps` == base+2×tiers, `timer_elapsed` within ±2s of the saved value after rebase, `reveal_count`/`hint_count` restored, `molinfo … get {rotate_matrix center_matrix scale_matrix global_matrix}` equals the saved viewpoint (viewmaster exact round-trip precedent, backup.tcl:30-33).
2. Index stability: the reloaded combined PDB's sentinel index list equals the pre-save list (the reconcile-by-index premise — cheap assert via `fetch_hider_indices` on both molids).
3. Generate-only: `start_game` without `start_round` leaves `game_logic::state` == "idle" and `timer_elapsed` == 0; a forced `on_pick` (direct call) is a no-op.
4. Old-file / version-mismatch loader branch: feed a sidecar with a wrong version tag → loader errors with the pinned message.
5. JSON codec tcltest: encode → decode → `eq` on the canonical dict (order-stable discipline, demos.tcl:174-178 rebuild pattern); garbage input → clean error, no crash.

---

## Entry/source order (module slot)

Current entry chain (biochemeleon.tcl:75-118): pure block `setup_state → registry → generators → game_logic → rep_tiers` → mol bridges `demos → backup → mutation → hiders` → `game.tcl` → `pick_bridge.tcl` → `gui/dialog.tcl`.

**Recommended slot for the new persistence code (split by the AGENTS dependency rule):**

- **`vmd/lib/persistence.tcl` — PURE** (JSON encode/decode, sidecar dict canonicalization, version check; stdlib `open/puts/gets/close` + `dict` only): source in the **pure block after setup_state** (it consumes setup_state constants + validated dicts; nothing else). tclsh/tcltest-able → the SC4 round-trip test lives in WSL.
- **Combined-PDB export + reload glue (mol-touching)**: either extend `mutation.tcl` (it already owns `write_combined_pdb`, mutation.tcl:448-466) or a small `persistence_mol.tcl` bridge sourced after `mutation.tcl`/before `game.tcl`. The zip step's home follows the mechanics research (if it shells out via `exec`, it is a bridge, not pure).
- **HARD RULES:** the new module must NOT `source registry.tcl` (re-sourcing wipes `_records`, biochemeleon.tcl:109-111) — reference `registry::*` at call time like game.tcl does. Re-sourcing `setup_state.tcl`/`generators.tcl` is harmless (demos.tcl:12 and mutation.tcl:38-40 precedent: constant re-init only).
- **`vmd/pkgIndex.tcl` needs NO change** — it only maps `package ifneeded biochemeleon 2.0 → source biochemeleon.tcl`; the entry sources everything (pkgIndex.tcl:9).

---

## Risks: planned-seam drift (what to do if 18/19 land differently)

1. **18-07's 5-key gs / 18-02's 3-arg add_hider_reps / 18-05's per_mat line family** — all are pinned `must_haves` truths, but if 18 lands with a different gs arity or key names, the Save capture list (A11-A13) shifts. **Mitigation:** before writing 20-0x PLANs, diff the landed 18-* / 19-* SUMMARYs against this inventory; the planner should treat this document's P-18/P-19 rows as *hypotheses with pinned sources*, re-verified in one read pass.
2. **19-02 counters without setters** — the restore-via-increment trick (B10) depends on `increment_reveal {{n 1}}` accepting explicit N (pinned). If 19 lands with different names, adjust two call sites.
3. **19-10 `_game_stash` + handler names** — the Phase-20 handlers reuse the helper and the fan-in convention; if the helper is renamed/re-scoped, the three handlers' guards follow. The P-19-10 contract block in that PLAN is the authoritative pin.
4. **on_start not yet factored** — the shared-prepare extraction (W3 step 1-3) touches the same proc 18-10 patches (5-arg threading). Sequence Phase-20's dialog.tcl work AFTER 18-10 and diff `on_start` before extracting; keep the toggle gating verbatim.
5. **writepdb-vs-tempfile combined-PDB source (A2)** — if the mechanics research picks the `$env(TEMP)` temp file, Save gains an R5-flavored fragility (another VMD run overwrites it). The atomselect-writepdb path from the live game molecule is self-contained and is what ROADMAP SC1 literally describes ("real + hider atoms via `atomselect writepdb`"). Planner should default to writepdb-from-live and let the mechanics researcher confirm byte/identity equivalence (assert index equality, smoke assert #2 above).
6. **Cleanup/Restart semantics for imported games** — v2 has NO per-atom delete, so "cleanup" of an imported game can only reload the combined PDB (hiders persist, found-status resets). This is a deliberate, documentable divergence from v1's hider-removal cleanup (v1 needed the da8d7a8 bugfix here). The imported-gs snapshot trick (W2 step 10) makes Cleanup/Restart = "restore to imported initial state" — coherent, but the GUI copy (on_cleanup's box, 19-13's hint) may need a Phase-20 wording tweak; flag at the GUI checkpoint.
7. **Log-line channel for "Saved checkpoint"** — `log_append` errors on unknown kinds (game_logic.tcl:244-246). Adding an `info` kind is a 3-line pure-layer change but touches the P-19-02-owned file; direct `on_log_line` diverges the model/view contract. Planner pins one.
8. **resume_elapsed lifecycle** — a leaked non-zero `resume_elapsed` after an import followed by a normal Start would silently rebase a fresh round's timer. The GO-branch consume MUST clear the var unconditionally (set to 0) after reading; add it to `reset_view_state`'s charter (P-19-08's shared reset) as the belt-and-braces reset point.

---

## Sources

### Primary (HIGH confidence — read in full this session)
- `vmd/AGENTS.md` (module dependency rules, Tcl 8.5 constraints, sentinel/writepdb-loss rules, R5)
- Current code: `vmd/gui/dialog.tcl`, `vmd/gui/setup_tab.tcl`, `vmd/gui/game_tab.tcl`, `vmd/lib/game.tcl`, `vmd/lib/game_logic.tcl`, `vmd/lib/registry.tcl`, `vmd/lib/backup.tcl`, `vmd/lib/mutation.tcl` (header + mutate/write_combined_pdb regions), `vmd/lib/hiders.tcl`, `vmd/lib/setup_state.tcl`, `vmd/lib/demos.tcl`, `vmd/biochemeleon.tcl`, `vmd/pkgIndex.tcl`
- Pinned planned seams: `.planning/phases/18-materials-exploration/18-05-PLAN.md`, `18-07-PLAN.md`, `18-10-PLAN.md`; `.planning/phases/19-in-game-actions/19-02-PLAN.md`, `19-05-PLAN.md`, `19-08-PLAN.md`, `19-09-PLAN.md`, `19-10-PLAN.md`, `19-13-PLAN.md`
- v1 precedent (shipped, verified): `pymol/biochemeleon/__init__.py` (:240-346 _on_start/_prepare_and_start; :679-720 _on_export; :745-788 _on_save; :790-868 _on_import; :886-913 _on_restart_imported), `gui_game.py` (:60-115 begin_row + :229-281 timer resume), `gui_setup.py` (:260-300 button row), `persistence.py` (build_bcm_dict keys)
- Conventions: `vmd/smoke/phase16_gametab_smoke.tcl` (read in full); 17.1-13-PLAN FULL-SUITE gate; 19-12-PLAN (phase19_actions_smoke.tcl naming + staging idiom)
- `.planning/ROADMAP.md:249-263` (Phase 20 SC1-4), `.planning/REQUIREMENTS.md:33,57,62`, `spec.md:20-43` (button order)

### Secondary (MEDIUM)
- `.planning/phases/19-in-game-actions/19-RESEARCH-gui.md` (:60 Phase-20 Game-tab slotting; §2 labels), `19-RESEARCH-mechanisms.md` (:295 spec 7-button note superseded by 19-08's locked Game-tab-only Cleanup; :397 found_color sidecar note)
- `.planning/phases/08-persistence-and-shareable-puzzles/08-04-SUMMARY.md` + `08-export-import-workflow-RESEARCH.md` (v1 workflow verification record)
- `.planning/research/FEATURES.md` (early save_state-based design — superseded by ROADMAP SC1's combined-PDB decision; cited only as history)

## RESEARCH COMPLETE
