---
phase: 14-setup-tab-bundled-demos
plan: 04
subsystem: gui
tags: [tcl, vmd, tk, ttk, gui, setup-tab, callbacks, trace, wm-delete, save-load, live-cap, human-verify]

# Dependency graph
requires:
  - phase: 14-setup-tab-bundled-demos (plan 03)
    provides: gui/setup_tab.tcl form (4 groups + collect_state/apply_state + switch_page + _dget) with 10 STUB callbacks (body=return); gui/dialog.tcl open_dialog extracted (modeless, no WM_DELETE handler yet); entry sources demos.tcl + gui/dialog.tcl
  - phase: 14-setup-tab-bundled-demos (plan 02)
    provides: demos.tcl mol bridge (load_demo/list_loaded_molecules/get_active_reps/save+load_setup/atom_count/fetch_pdb stub) — the backend the callbacks call
  - phase: 14-setup-tab-bundled-demos (plan 01)
    provides: validate_state (deterministic clamp) + randomize_state + randomize_per_rep (quick-008) + DEFAULTS/GAME_REPS/hider_count_cap — the pure layer do_save/do_load/do_reset/do_randomize call
  - phase: 13-bootstrap-sourced-entry
    provides: entry bootstrap + ::biochemeleon::state dict (the `setup` key on_close persists to) + tk_version-guarded public procs
provides:
  - "vmd/gui/setup_tab.tcl — 10 callbacks fully wired (refresh_mol_menu trace, select_demo, select_loaded_mol, on_rep_toggled, update_cap, recompute_per_rep_maxes, do_reset, do_randomize, do_save, do_load) + live per-rep-sum capping + validate_state-on-save with warning popup"
  - "vmd/gui/dialog.tcl — ::biochemeleon::on_close WM_DELETE_WINDOW handler (collect_state -> persist ::biochemeleon::state setup + trace vdelete vmd_molecule + destroy); wm protocol wired in open_dialog"
  - "The complete Phase 14 Setup tab — a modeless, end-to-end pre-game configuration experience (DEMO-01, SETUP-01..06, BTN-01..04) human-verified in a real VMD GUI session"
affects:
  - "Phase 16 (Start flow reads the Setup state via collect_state; Game tab populated; on_close's collect_state preserves in-progress edits across dialog destroy/recreate)"
  - "Phase 20 (.bcm Save/Load: do_save/do_load are the working Save/Load; Phase 20 wraps the combined-PDB + JSON sidecar around the same .bcm plumbing)"
  - "Phase 22 (unload cleanup reuses the on_close trace vdelete pattern for leak-free unload)"

# Tech tracking
tech-stack:
  added: []  # stdlib tcl + Tk/ttk (ships with VMD 1.9.3); no new libraries
  patterns:
    - "Tcl 8.5 `variable a b c d` is name-VALUE PAIRS (scalar `set a b; set c d`), NOT a list of name-links. To LINK multiple namespace vars in one scope, use one-per-line `variable a; variable b` (link-only, no value). The multi-name form silently does scalar assignment."
    - "Per-rep sum live-capping (dynamic spinbox -to): each checked rep's -to = hider_count - sum(other checked reps), so the per-rep SUM can NEVER exceed hider_count via normal GUI interaction. Three-pronged: on_rep_toggled clamps the newly-enabled rep to the remaining allowance; recompute_per_rep_maxes sets a dynamic -to per checked rep (unchecked reps -to 0); update_cap clamps the per-rep sum in insertion order when a smaller molecule shrinks the cap. All guarded by _loading so apply_state (which sets validated values directly) isn't fighting the clamps."
    - "validate_state-on-save + tk_messageBox warning: do_save runs collect_state through validate_state BEFORE saving; if clamping occurred, a tk_messageBox popup warns the user (human-readable diff of changed keys), apply_state updates the widgets to the validated values, and the VALIDATED state is saved. Makes save->load perfectly consistent (GUI/pure-layer round-trip)."
    - "WM_DELETE_WINDOW handler = collect_state + trace vdelete + destroy: preserves in-progress edits (collect_state -> dict set ::biochemeleon::state setup), cleans up the refresh trace (trace vdelete vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu — Pitfall 5, no leaked-callback error spam on later mol add/delete), then destroys the toplevel. wm protocol wired in open_dialog."

key-files:
  created: []
  modified:
    - "vmd/gui/setup_tab.tcl — replaced the 10 STUB callbacks (body=return from Plan 03) with full implementations; added live per-rep-sum capping (on_rep_toggled/recompute_per_rep_maxes/update_cap) + validate_state-on-save with warning popup (do_save)"
    - "vmd/gui/dialog.tcl — added ::biochemeleon::on_close (WM_DELETE_WINDOW handler: collect_state + persist + trace vdelete + destroy); wired wm protocol $w WM_DELETE_WINDOW in open_dialog"

key-decisions:
  - "Source-time script_dir from Plan 02 reused: select_demo calls ::biochemeleon::demos::load_demo (which captures script_dir at source time) so bundled demos resolve regardless of cwd — no [info script] in the callback body."
  - "refresh_mol_menu takes `args` (the trace callback signature is {name1 name2 op} — Pitfall 2); skips `graphics` filetype mols; adds a radiobutton per mol bound to ::biochemeleon::setup_tab::selected_mol with -command [list select_loaded_mol $id] (list-quoting for runtime values — Pitfall 7)."
  - "do_save/do_load use the key-value format via demos::save_setup/load_setup (LOCKED DECISION #1, NOT [list]+source). load_setup already calls validate_state internally (Plan 02), so do_load applies the returned validated dict directly."
  - "do_randomize passes collect_state as the locked_state so lock_source=1 preserves the locked target (matches randomize_state's lock_source branch from Plan 01); no seed = non-deterministic (random)."
  - "The authoritative clamp is validate_state on Save (with a user-visible warning); widget-level live-capping is defense-in-depth for a good UX (the per-rep sum can't balloon via GUI interaction, but Save is the source of truth for round-trip consistency)."
  - "on_close persists via explicit `dict set ::biochemeleon::state setup $state` (collect_state only RETURNS the dict; on_close is the one that writes it to the shared state) — wrap in catch so a half-built form doesn't error on close."

patterns-established:
  - "One-per-line `variable` for multi-var linking in tcl 8.5 (NOT the multi-name form). Required whenever a proc links >1 namespace var that may already exist as an array (the rep_sel trap)."
  - "Dynamic-spinbox -to live-capping for 'sum of parts <= total' constraints (per-rep counts vs hider_count). Reusable by any Phase 14+ GUI constraint of this shape."
  - "validate_state-on-save + warning popup pattern: GUI writes go through the pure-layer canonicalizer before persistence + tell the user what changed. The GUI/pure-layer consistency contract."
  - "WM_DELETE_WINDOW handler = collect_state + trace vdelete + destroy. The Phase 22 unload-cleanup pattern (release traces + selections + restore mouse mode) is the same shape."

# Metrics
duration: 38min
completed: 2026-08-29
---

# Phase 14 Plan 04: Setup tab callbacks + WM_DELETE handler Summary

**All 10 Setup-tab callbacks wired (refresh_mol_menu trace, demo/loaded-mol select, per-rep toggle, cap recompute, reset/randomize/save/load) + the WM_DELETE_WINDOW handler (collect_state + trace vdelete + destroy); 2 bugs fixed during the GUI human-verify checkpoint (Tcl 8.5 `variable a b` name-value-pairs trap that aborted dialog build; per-rep-sum live-cap + save warning for save->load consistency) — checkpoint APPROVED, Phase 14 complete.**

## Performance

- **Duration:** 38 min (agent execution; excludes user GUI-checkpoint time between the 2 fix rounds)
- **Started:** 2026-08-29T12:57:00Z
- **Task 1 committed:** 2026-08-29T13:18:27Z (dfeebbf)
- **Checkpoint fix 1 (rep_sel):** 2026-08-29T13:36:59Z (c3f6d3a)
- **Completed (last fix):** 2026-08-29T14:51:47Z (fec7c63)
- **Tasks:** 2 (Task 1: wire callbacks + WM_DELETE; Task 2: checkpoint:human-verify) + 2 checkpoint-driven fix rounds
- **Files modified:** 2

## Accomplishments

- Replaced all 10 STUB callbacks in `vmd/gui/setup_tab.tcl` (Plan 03 left them as `return`) with full implementations:
  - **refresh_mol_menu {args}** — trace callback (`{name1 name2 op}` signature); resolves the loaded-mol menu path; clears + repopulates from `[molinfo list]`, skipping `graphics` filetype mols; one radiobutton per mol (`-value $id -label "$id [name]" -variable ...selected_mol -command [list select_loaded_mol $id]`); "None loaded" disabled entry when empty.
  - **select_demo {demo_id}** — sets `demo_id` + `mode=demo`; calls `switch_page`; `catch {::biochemeleon::demos::load_demo $demo_id} molid`; on success sets `current_molid` + `update_cap`; on error a `tk_messageBox` warning.
  - **select_loaded_mol {molid}** — sets `selected_mol` + `current_molid` + `mode=loaded`; `switch_page` + `update_cap`.
  - **on_rep_toggled {rep}** — `_loading` guard; enables/disables the per-rep spinbox (path resolved via `lsearch $GAME_REPS $rep`); on disable sets `rep_cnt($rep) 0`; clamps the newly-enabled count to the remaining allowance (live-cap, see fixes); calls `recompute_per_rep_maxes`.
  - **update_cap {}** — `_loading` guard; atom_count via `::biochemeleon::demos::atom_count`; cap via `::biochemeleon::setup_state::hider_count_cap`; reconfigures the hider-count spinbox `-to [expr {max(1,$cap)}]`; clamps `hider_count`; on cap shrink, clamps the per-rep sum in insertion order + `recompute_per_rep_maxes`.
  - **recompute_per_rep_maxes {}** — `_loading` guard; sets each checked rep's spinbox `-to` dynamically (hider_count - sum of other checked reps); unchecked reps `-to 0`.
  - **do_reset {}** — `apply_state $::biochemeleon::setup_state::DEFAULTS`.
  - **do_randomize {}** — atom_count from `current_molid`; `lock_source` from the var; `apply_state [::biochemeleon::setup_state::randomize_state "" $atom_count $lock_source [collect_state]]` (empty seed = non-deterministic; collect_state as locked_state preserves the locked target when lock_source=1).
  - **do_save {}** — `tk_getSaveFile` (.bcm); runs `collect_state` through `validate_state` BEFORE saving; if clamping occurred, a `tk_messageBox` warning (human-readable diff) + `apply_state` the validated values + save the VALIDATED state (save->load consistency); `catch {::biochemeleon::demos::save_setup $state $fname}` with a warning on error.
  - **do_load {}** — `tk_getOpenFile` (.bcm); `catch {::biochemeleon::demos::load_setup $fname} result`; on error a warning; on success `apply_state $result` (load_setup already calls validate_state internally — Plan 02).
- Added `::biochemeleon::on_close` (WM_DELETE_WINDOW handler) to `vmd/gui/dialog.tcl`: `catch { collect_state }` -> persist to `::biochemeleon::state setup` (preserve in-progress edits); `catch { trace vdelete vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu }` (clean up the trace — Pitfall 5); `destroy $w`. Wired `wm protocol $w WM_DELETE_WINDOW ::biochemeleon::on_close` in `open_dialog`.
- **Two bugs found + fixed during the GUI checkpoint** (both user-reported in the real VMD session — see Deviations):
  1. **rep_sel array/scalar mismatch** (c3f6d3a) — Tcl 8.5 `variable a b c d` is name-VALUE pairs, not name-links; collect_state/apply_state's multi-name `variable rep_sel rep_cnt ...` silently did a scalar `set rep_sel "rep_cnt"`, but the checkbutton `-variable ...rep_sel($rep)` makes Tk auto-create `rep_sel` as an ARRAY → "can't set rep_sel: variable is array" aborted the dialog build (empty popup). Fix: one-per-line `variable` decls (link-only).
  2. **per-rep sum live-cap + save warning** (fec7c63) — (a) each per-rep spinbox had `-to = hider_count` individually so the SUM could far exceed the total; (b) typing directly into the hider-count entry bypassed the `-to` cap (which only clamps arrow clicks) so save->load showed a different value than the screen. Fix: three-pronged live-capping (on_rep_toggled/recompute_per_rep_maxes/update_cap) + do_save runs validate_state first with a warning popup + saves the validated state.
- All gates clean: modeless (no `grab set` in vmd/gui/), 8.6 idioms (zero lmap/try/throw/finally/tailcall/coroutine/yield), ttk::spinbox absence (plain spinbox), trace vdelete vmd_molecule present (the on_close handler), 7 key procs have multi-line bodies.
- All headless smokes still PASS=1 (no regression): GUI smoke, Phase 13 smoke, Phase 14 mol smoke; plus a UX-fix probe (procs exist + correct argc + validate_state clamps + eq diff detection) PASS=1.
- **GUI human-verify checkpoint APPROVED**: the full Setup tab works end-to-end in a real VMD 1.9.3 session — demos load, hider count caps to atom count, per-rep rows enable/disable + live-cap, the 4 buttons work, Save/Load round-trips to a `.bcm` file, the dialog stays modeless (viewer interactive), close+reopen preserves in-progress edits, trace cleanup works (no error spam on later mol add/delete), re-source guard works.

## Task Commits

Each task/fix was committed atomically:

1. **Task 1: Wire the 10 callbacks + add WM_DELETE handler** - `dfeebbf` (feat)
2. **(checkpoint fix) rep_sel array/scalar mismatch in variable decls** - `c3f6d3a` (fix) — Rule 1 bug found during checkpoint (dialog build aborted)
3. **(checkpoint fix) Live-cap per-rep sum + save warning on clamp** - `fec7c63` (fix) — Rule 1 bug found during checkpoint (save->load inconsistency + per-rep sum exceeding total)

Task 2 (checkpoint:human-verify) produced no code commit (it's the gate); its outcome is the 2 fix commits above + the final APPROVED.

**Plan metadata:** (this commit)

## Files Created/Modified
- `vmd/gui/setup_tab.tcl` — 10 stub callbacks replaced with full implementations; added the live per-rep-sum capping (on_rep_toggled/recompute_per_rep_maxes/update_cap) + the validate_state-on-save warning popup (do_save); one-per-line `variable` decls in collect_state/apply_state (the rep_sel fix). Net ~390 lines added over the Plan 03 stubs.
- `vmd/gui/dialog.tcl` — added `::biochemeleon::on_close` (collect_state + persist + trace vdelete + destroy); wired `wm protocol $w WM_DELETE_WINDOW ::biochemeleon::on_close` in `open_dialog`. Net +33 lines.

## Decisions Made
- **Source-time script_dir (from Plan 02) reused in the callback bodies:** `select_demo` calls `::biochemeleon::demos::load_demo`, which captures `script_dir` at source time (Plan 02's fix). No callback uses `[info script]` in its proc body — the 14-02 lesson holds across the GUI layer.
- **list-quoting for runtime values in -command scripts:** every menubutton/menu `-command` that closes over a runtime value (molid, demo_id) uses `[list ... $val]`, NOT string interpolation (Pitfall 7). e.g. `-command [list ::biochemeleon::setup_tab::select_loaded_mol $id]`.
- **do_save canonicalizes before persisting:** the GUI never writes a non-validated state to disk. validate_state is the single source of truth; the warning popup tells the user what was clamped. This is the GUI/pure-layer consistency contract.
- **Widget-level live-capping is defense-in-depth, not authoritative:** the per-rep-sum live-cap gives a good UX (counts can't balloon via interaction), but validate_state on Save is the real clamp (handles the entry-typing bypass + any programmatic apply_state). Documented this so downstream doesn't assume the widget clamps are sufficient.
- **on_close persists explicitly:** `collect_state` only RETURNS the dict; `on_close` is the one that does `dict set ::biochemeleon::state setup $state`. Wrapped in `catch` so a half-built form (e.g. closed mid-apply) doesn't error on close.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tcl 8.5 `variable a b c d` is name-VALUE pairs, NOT a list of name-links (dialog build aborted)**
- **Found during:** Task 2 checkpoint:human-verify (the user sourced the entry in a real VMD session; the dialog came up as an empty popup + VMD's "Creation of window for biochemeleon failed" wrapper).
- **Issue:** `collect_state`/`apply_state` used `variable rep_sel rep_cnt difficulty_easy lock_source` intending to link all four namespace vars into local scope. But Tcl 8.5 `variable a b c d` parses as name-VALUE PAIRS — it does a scalar `set rep_sel "rep_cnt"` (then `set difficulty_easy "lock_source"`), NOT a 4-name link. Meanwhile the checkbutton `-variable ::biochemeleon::setup_tab::rep_sel($rep)` in `build_hiders_group` causes Tk to auto-create `rep_sel` as an ARRAY (each element set to the offvalue 0). So when `build` -> `apply_state DEFAULTS` hit the scalar `set rep_sel`, it failed: "can't set rep_sel: variable is array", aborting the dialog build. `collect_state` had the same latent bug (would have errored on the first button press).
- **Fix:** Split each multi-name `variable` into one-per-line (link-only, no value): `variable rep_sel; variable rep_cnt; variable difficulty_easy; variable lock_source` — the form that just links the local name to the namespace var. Applied to both `collect_state` and `apply_state`.
- **Files modified:** `vmd/gui/setup_tab.tcl`
- **Verification:** a headless probe reproducing the exact scenario (pre-init `rep_sel` as array, then `apply_state DEFAULTS` + `collect_state`) now returns rc=0 with correct values (was rc=1). All 4 gates clean; GUI + Phase 13 smokes still PASS=1.
- **Committed in:** `c3f6d3a`

**2. [Rule 1 - Bug] Per-rep sum could exceed hider_count + save->load inconsistency (entry-typing bypass)**
- **Found during:** Task 2 checkpoint:human-verify (the user reported two UX issues in the Hiders group after the rep_sel fix got the dialog building).
- **Issue (a):** Each per-rep spinbox had `-to = hider_count` individually, so the SUM of per-rep counts could far exceed the total hider_count (e.g. 10 reps each at 10 = 100 vs hider_count 10). This doesn't match v1's behavior (per-rep counts partition the total).
- **Issue (b):** Typing directly into the hider-count spinbox entry bypassed the `-to` cap (which only clamps arrow clicks), so the on-screen value could exceed the cap; Save then clamp-on-load showed a DIFFERENT value than the screen — save->load was inconsistent.
- **Fix (three-pronged live-capping so the per-rep sum can NEVER exceed hider_count via normal GUI interaction):**
  - A) `on_rep_toggled`: when enabling a rep, clamp its count to the REMAINING allowance (hider_count - sum of all OTHER checked per-rep counts).
  - B) `recompute_per_rep_maxes`: each checked rep's `-to` is now dynamic (hider_count - sum of other checked reps), so increasing one rep shrinks the others' maxes; unchecked reps get `-to 0`.
  - C) `update_cap`: when a smaller molecule is loaded (cap shrinks), clamp the per-rep sum in insertion order (keep early reps, reduce later ones) + call `recompute_per_rep_maxes`.
  - All guarded by `_loading` so `apply_state` (which sets validated values directly) isn't fighting the clamps.
- **Fix (save->load consistency):** `do_save` now runs `collect_state` through `validate_state` BEFORE saving; if clamping occurred, a `tk_messageBox` popup warns the user (human-readable diff of changed keys), `apply_state` updates the widgets to the validated values, and the VALIDATED state is saved. The authoritative clamp is validate_state on Save; the entry-typing bypass itself is noted as a future minor UX refinement (could add `-validatecmd` to the spinbox entry).
- **Files modified:** `vmd/gui/setup_tab.tcl`
- **Verification:** a UX-fix headless probe (procs exist + correct argc + validate_state clamps + eq comparison detects diffs) PASS=1; all 4 gates clean; GUI + Phase 13 + Phase 14 mol smokes all PASS=1. Widget-level live-capping confirmed in the GUI by the user (second checkpoint round -> APPROVED).
- **Committed in:** `fec7c63`

**3. [Rule 3 - Blocking] `tclsh` not available in WSL + `rm` denied by opencode.json — headless verification adapted (same as 14-01/02/03)**
- **Found during:** Task 1 + both fix rounds' verify steps.
- **Issue:** The plan's syntax/smoke staging uses `tclsh` (not installed; AGENTS.md forbids apt) and `rm -rf` (denied by opencode.json).
- **Fix:** Reused the established pattern — headless VMD's tcl 8.5.6 for syntax/definition probes (source only DEFINES procs; no mol/tk calls at source time) + a fixed staging dir (`tmp/bchm14x-stage`) with `mkdir -p && cp -r vmd ...` (cp overwrites). `tmp/` is gitignored.
- **Files modified:** none (probes/staging live in gitignored `tmp/`)
- **Verification:** all probes + smokes ran successfully via this approach.
- **Committed in:** N/A (workflow adaptation)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs found during the GUI checkpoint + 1 Rule 3 blocking environment constraint carried forward from 14-01/02/03)
**Impact on plan:** Both Rule 1 fixes were necessary for correctness — #1 made the dialog build at all (the plan's `variable` form was a Tcl 8.5 trap the research didn't flag), #2 made save->load consistent + matched v1's per-rep-sum behavior. The Rule 3 adaptation is environment-driven (identical to prior plans). All plan objectives met; the checkpoint's purpose (catch GUI issues headless can't) was served — both fixes came directly from the user's real-VMD testing.

## Issues Encountered
- The **`variable a b` name-value-pairs trap** (deviation #1) was the subtlest and most consequential: it's a Tcl 8.5 *language* quirk, not a VMD/API issue. The research skeletons and the Plan 03 code both used the multi-name `variable` form (it looks like the natural "link several vars" idiom, and it's legal — it just doesn't DO what it looks like). It only manifested at GUI-build time (Tk auto-creates `rep_sel` as an array via the checkbutton `-variable`), so the headless smoke (no Tk) couldn't catch it — exactly the class of issue the human-verify checkpoint exists for. Lesson: in Tcl 8.5, `variable a b` is NEVER "link a and b"; it's `set a b`. To link, use one-per-line.
- The **per-rep sum exceeding hider_count** (deviation #2a) was a behavior gap vs v1 (v1's per-rep counts partition the total); the live-cap brings v2 to parity. The **entry-typing bypass** (#2b) is a Tk spinbox quirk (`-to` only clamps arrow clicks, not direct entry) — the validate_state-on-save + warning is the robust fix; a future `-validatecmd` on the entry would be a nice-to-have refinement.

## Verification Results
- **Gates (headless):** modeless (`grab set` in vmd/gui/ = 0), 8.6 idioms (0), ttk::spinbox (0), trace vdelete vmd_molecule (>=1), 7 key procs multi-line bodies. All PASS.
- **Smokes (headless):** GUI smoke PASS=1, Phase 13 smoke PASS=1, Phase 14 mol smoke PASS=1, UX-fix probe PASS=1, rep_sel-fix probe rc=0. No regression.
- **GUI human-verify (Task 2):** APPROVED — the full Setup tab works end-to-end in a real VMD 1.9.3 session (demos load, hider count caps, per-rep rows + live-cap, 4 buttons, Save/Load round-trip, modeless, close+reopen preserves state, trace cleanup, re-source guard).

## Requirements Satisfied
This plan (with 14-01/02/03) satisfies all 11 Phase 14 requirements:
- **SETUP-01:** molecule dropdown (loaded mols via `molinfo list` + bundled demos + fetch option); selecting a bundled demo loads via `mol new` (DEMO-01 set). ✓
- **SETUP-02:** hider count spinbox capped to atom count (update_cap via demos::atom_count + hider_count_cap; reconfigures `-to`). ✓
- **SETUP-03:** lock-scene checkbox (state reflected in collect_state; detection is Phase 16 START). ✓
- **SETUP-04:** per-rep rows with optional per-rep counts (on_rep_toggled enables/disables the spinbox; live-cap keeps sum <= hider_count). ✓
- **SETUP-05:** difficulty toggle (Easy/Hard radiobuttons). ✓
- **SETUP-06:** Randomize distributes across a random non-empty subset of reps (do_randomize -> randomize_state -> randomize_per_rep, quick-008 baked in from Plan 01). ✓
- **BTN-01/02/03/04:** Reset/Randomize/Save/Load each work as labeled; Save/Load round-trips to a `.bcm` file (do_save/do_load + demos::save_setup/load_setup; validate_state-on-save for consistency). ✓
- **DEMO-01:** 6 bundled demos load (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) via select_demo -> demos::load_demo. ✓
- **Dialog is modeless** (viewer interactive; no `grab set`); **close+reopen preserves state** (on_close collect_state -> ::biochemeleon::state setup); **trace cleanup works** (on_close trace vdelete — no error spam on later mol add/delete). ✓

## User Setup Required
None — no external service configuration required. The GUI uses only VMD 1.9.3's bundled Tcl/Tk 8.5.6 + ttk (already installed). The headless smokes run under the existing VMD install. The GUI human-verify was run by the user in a real VMD session (Task 2 checkpoint) and APPROVED.

## Next Phase Readiness
- **Phase 14 complete:** all 4 plans (14-01 pure layer + 14-02 mol bridge + 14-03 GUI structure + 14-04 callbacks) done. Phase 14 success criteria 1-3 met (criterion 4 — pure-layer tcltest — met in Plan 01). Ready for Phase 14 verification (if the workflow runs a phase-level verify), then Phase 15.
- **Ready for Phase 15 (Mutation Safety & Hider Registry — HIGHEST RISK):** `mol new`/`molinfo` are proven (14-02 demos), the Setup tab is a stable configuration surface, and `collect_state` is the bridge. Phase 15 de-risks PDB-rebuild before any generator builds on it.
- **Ready for Phase 16 (MVP Core Loop):** the Start flow reads the Setup state via `collect_state`; `apply_state` survives dialog destroy/recreate (on_close persists to `::biochemeleon::state setup`); `randomize_state`/`randomize_per_rep` carry the quick-008 guarantee.
- **Ready for Phase 20 (Persistence):** do_save/do_load are the working Save/Load to `.bcm`; Phase 20 wraps the combined-PDB + JSON sidecar around the same plumbing.
- **Ready for Phase 22 (unload cleanup):** the on_close `trace vdelete` pattern is the template for leak-free unload (release traces + selections + restore mouse mode).
- **No blockers.** The complete pre-game configuration experience is verified end-to-end.
- **Notes for downstream:**
  - Reuse the one-per-line `variable` form in any Phase 14+ GUI proc that links >1 namespace var that may already exist as an array (the rep_sel trap).
  - The dynamic-spinbox `-to` live-cap pattern is reusable for any "sum of parts <= total" GUI constraint.
  - The validate_state-on-save + warning popup is the GUI/pure-layer consistency contract — Phase 20's full Save should follow the same shape (canonicalize before persist + tell the user what changed).
  - `on_close` persists via `dict set ::biochemeleon::state setup $state`; Phase 16's Game tab should read from the same `::biochemeleon::state setup` key (the canonical in-memory state).

## Key Lessons for Downstream
1. **Tcl 8.5 `variable a b` = name-VALUE pairs (scalar `set a b`), NOT name links.** To link multiple namespace vars in one scope, use one-per-line `variable a; variable b`. The multi-name form silently does scalar assignment and will crash if the target is an array. This is a language quirk the research didn't flag — probe any multi-var `variable` before relying on it.
2. **Per-rep sum live-capping (dynamic spinbox `-to = hider_count - sum(others)`)** matches v1 behavior (per-rep counts partition the total). Three-pronged: clamp-on-enable + dynamic -to per rep + clamp-on-cap-shrink. The authoritative clamp is still validate_state on Save.
3. **validate_state-on-save + tk_messageBox warning + save validated state** is the GUI/pure-layer consistency pattern: the GUI never writes a non-validated state to disk; the user is told what was clamped. Reuse for Phase 20's full Save.
4. **(Carried forward) [info script] is dynamic/call-time** (14-02): proc bodies capture `script_dir` at source time. The 14-04 callbacks honor this (no `[info script]` in callback bodies; `select_demo` delegates to `demos::load_demo` which already captured `script_dir`).
5. **(Carried forward) `dict get` 3-arg default form is a MYTH in tcl 8.5.6** (14-03): use `dict exists` + `dict get` (the `_dget` helper pattern). apply_state still uses `_dget`.

---
*Phase: 14-setup-tab-bundled-demos*
*Completed: 2026-08-29*
