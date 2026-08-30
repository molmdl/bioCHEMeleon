---
phase: 15-mutation-safety-hider-registry
verified: 2026-08-30T07:29:31Z
status: passed
score: 4/4 success criteria verified (all 5 plans' must_haves verified)
re_verification: null
gaps: []
notes:
  - "One WARNING-level defect found in a module smoke (vmd/smoke/phase15_mutation_smoke.tcl:84 — regexp pattern starting with '-' parsed as a switch, silently skipping that smoke's PDB file-content sub-checks). NOT a phase-goal gap: the capstone (the phase exit gate) is clean and authoritative, and the mutation smoke's mutate-path assertions (which prove SC1/SC3-DI/SC2-mech) all ran and passed. Fix is a one-token change (`regexp -- {-999\.0}`); deferred per verify-only scope."
human_verification: none required  # Phase 15 planned no GUI checkpoint; all SCs headless-verified
---

# Phase 15: Mutation Safety & Hider Registry — Verification Report

**Phase Goal:** Hiders can be generated into a molecule and cleaned up, leaving the original intact — the highest-risk VMD-specific unknown (no in-place insertion; PDB-rebuild) is de-risked BEFORE any generator is built on it.
**Verified:** 2026-08-30T07:29:31Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Verification Method

Code-inspected all 5 artifacts at three levels (exists / substantive / wired), grep-verified every plan `key_links` pattern, ran the purity gates, then executed **all 4 headless VMD smokes + the tcltest suite** against a fresh staging copy (`tmp/verify15/vmd`, `diff`-verified identical to the repo tree). Markers parsed, never `$?` (VMD does not propagate exit codes). Full captures scanned for `ERROR)` lines.

---

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | backup → rebuild combined PDB → `mol new` → tag sentinels produces ONE molecule with original + hiders, tagged `resname=GAM`/`beta=-999`/`segid=GAME`, countable via canonical selector `resname GAM and beta < 0` | ✓ VERIFIED | `mutation.tcl` 5 procs + HID_* constants + `_hider_record` (78-col format, beta `%6.1f` line 74, segid `%-4s` cols 73-76); `tag_sentinels` sets beta/segid in-place via atomselect and `$sel delete`s (lines 117-132); capstone run: VMD loaded combined PDB → `Atoms: 560`, 5 sentinels via canonical selector at indices 555-559, segid `GAME GAME GAME GAME GAME`, original atom0 name `N1` intact — marker `PASS=1 FAIL=none` (any miss would `_bail` into the FAIL list) |
| SC2 | cleanup (`mol delete` game + `mol new` original + re-apply reps) restores the original exactly — no hider residue; restart uses the same mechanism | ✓ VERIFIED | `backup.tcl::restore {snapshot molid_to_delete}` deletes the PASSED molid (line 110: `mol delete $molid_to_delete`), NOT `snapshot.molid`; `game.tcl::cleanup` passes `[dict get $game_state game_molid]` (line 86) + `registry::reset` (line 87); `restart` = cleanup + start_game (lines 97-101); capstone SC2a-d all passed: restored 555 atoms, numreps==saved, 0 sentinels, **and the false-pass guard** — `catch {molinfo $game_molid get numatoms}` errored (game_molid actually deleted, no 560-atom leak) |
| SC3 | hider registry (pure `dict` in `lib/registry.tcl`) records each hider's `index` and reconstructs from sentinels on reload — unit-tested via tcltest in WSL without VMD (DI sentinel reconstruction) | ✓ VERIFIED | `registry.tcl` grep gates: **ZERO** `mol/atomselect/molinfo/tk/toplevel/ttk` tokens, **ZERO** tcl 8.6 idioms; `count_hiders` = `dict size $_records` (line 64), `reset` = `set _records [dict create]` (line 72); exports extended (line 19); DI expansion `foreach idx [{*}$fetch_hider_ids]` (line 34); test run: `BCHM_TEST_RESULT Total=9 Passed=9 Failed=0 Skipped=0` — all 9 cases incl. the 4 new ones (`count_hiders_after_reconstruct`, `count_hiders_empty`, `reset_clears_records`, `reconstruct_with_bound_arg_lambda`), the last mirroring game.tcl's molid-bound `[list apply {lambda} <arg>]` shape |
| SC4 | viewpoint + rep list saved before mutation and restored on the new molid after reload (viewmaster-style round-trip) | ✓ VERIFIED | `backup.tcl`: viewmaster 4-matrix positional get/set `{rotate_matrix center_matrix scale_matrix global_matrix}` (lines 41/86 — SAME order); rep clear = captured-count + always `mol delrep 0` loop (line 73), re-apply = form B `mol addrep` + `mod*` (lines 78-82); `game.tcl::start_game` ordering: snapshot (line 48) **before** mutate (52), `backup::apply` on game_molid **after** mutate (54); capstone: reps restored on game_molid (2==2) and viewpoint maxdiff on restored molid = **0** (echoed) < 1e-4 |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `vmd/lib/registry.tcl` | +`count_hiders` +`reset`, stays PURE, exports updated | ✓ (74 ln) | ✓ no stubs | ✓ imported by test + capstone + game (call-time) | ✓ VERIFIED |
| `vmd/lib/mutation.tcl` | 5 procs + `_hider_record` + `HID_*` + script_dir; canonical selector; `%6.1f`; `$sel delete` discipline; NO restore/cleanup proc | ✓ (168 ln) | ✓ no stubs | ✓ called by game.tcl:50/52 + smokes | ✓ VERIFIED |
| `vmd/lib/backup.tcl` | snapshot/apply/restore; 2-arg restore deletes PASSED molid; delrep-0 loop; viewmaster order; NO atomselect; sources NOTHING | ✓ (114 ln) | ✓ no stubs | ✓ called by game.tcl:48/54/86 | ✓ VERIFIED |
| `vmd/lib/game.tcl` | start_game/cleanup/restart; `list apply` DI (not bare `apply`); cleanup passes game_molid; sources NOTHING; owns NO mol delete/new | ✓ (101 ln) | ✓ no stubs | ✓ composition root; entry sources it | ✓ VERIFIED |
| `vmd/biochemeleon.tcl` | sources backup→mutation→game after demos.tcl, before gui/dialog.tcl; registry sourced EXACTLY ONCE | ✓ (154 ln) | ✓ | ✓ lines 85-93; only `source ... registry.tcl` in tree (line 72) | ✓ VERIFIED |
| `vmd/tests/test_registry.test` | 9 cases (5 original + 4 new) | ✓ (83 ln) | ✓ | ✓ sources registry.tcl; ran green | ✓ VERIFIED |
| `vmd/smoke/phase15_mutation_smoke.tcl` | SC1 + SC3-DI module smoke, BCHM_SMOKE_RESULT | ✓ (148 ln) | ⚠️ see Warning W1 | ✓ ran: `PASS=1 FAIL=none` | ✓ VERIFIED (w/ warning) |
| `vmd/smoke/phase15_backup_smoke.tcl` | SC2 + SC4 round-trip incl. dead-original regression guard | ✓ (205 ln) | ✓ | ✓ ran: `PASS=1 FAIL=none` | ✓ VERIFIED |
| `vmd/smoke/phase15_game_smoke.tcl` | game orchestration + game_molid-deleted contract | ✓ (171 ln) | ✓ | ✓ ran: `PASS=1 FAIL=none` | ✓ VERIFIED |
| `vmd/smoke/phase15_smoke.tcl` | CAPSTONE: full pipeline through public game API only | ✓ (209 ln) | ✓ | ✓ ran: `PASS=1 FAIL=none` | ✓ VERIFIED |

### Key Link Verification (plan `key_links` patterns grep-verified)

| From | To | Via | Status |
|------|----|----|--------|
| `registry::reconstruct_from_sentinels` | `count_hiders` / `_records` | `variable _records` + `dict size $_records` (registry.tcl:63-64); `set _records [dict create]` ×2 (lines 33, 72) | ✓ WIRED |
| `test_registry.test` | `registry.tcl` | `source [file join [pwd] vmd lib registry.tcl]` (line 12) | ✓ WIRED |
| `mutation::mutate` | write_combined_pdb → mol delete → mol new → tag_sentinels | mutation.tcl:163-166 (all 4 steps in order) | ✓ WIRED |
| `mutation::fetch_hider_indices` | canonical selector | `atomselect $molid "resname $HID_RESNAME and beta < 0"` (line 142) | ✓ WIRED |
| `mutation::tag_sentinels` | in-place set beta/segid | `$sel set beta` (122) + `$sel set segid` (123) + `$sel delete` (130) | ✓ WIRED |
| `backup::snapshot/apply` | viewmaster 4-matrix positional | combined get (41) / set (86), identical field order | ✓ WIRED |
| `backup::restore` | mol delete PASSED molid → mol new filename | backup.tcl:110-111 (`$molid_to_delete`, NOT `[dict get $snapshot molid]`) | ✓ WIRED |
| `backup::apply` | delrep-0 loop + addrep + mod* | backup.tcl:73-82 | ✓ WIRED |
| `game::start_game` | snapshot → mutate → apply → reconstruct | game.tcl:48→52→54→61 in the non-negotiable order | ✓ WIRED |
| `game::start_game` | DI as command-prefix VALUE | `[list apply {{molid} {...}} $game_molid]` (line 61) — **`list apply`, NOT bare `apply`** ✓ | ✓ WIRED |
| `game::cleanup` | `backup::restore $snapshot $game_molid` + `registry::reset` | game.tcl:86-87 | ✓ WIRED |
| `biochemeleon.tcl` | lib source order | setup_state(71) → registry(72) → demos(85) → backup(90) → mutation(91) → game(92) → dialog(93); registry sourced ONCE (only occurrence in tree) | ✓ WIRED |
| capstone | game::start_game → game::cleanup | phase15_smoke.tcl:118, 164 (bridges/registry never called directly) | ✓ WIRED |

### Isolation Gates (all grep-verified ZERO matches)

- `registry.tcl` mol/atomselect/molinfo/tk/toplevel/ttk tokens: **0** (stays PURE)
- tcl 8.6 idioms (`lmap|try|throw|finally|tailcall|coroutine|yield`) in all of `vmd/lib/`: **0**
- `atomselect` in `backup.tcl`: **0**
- `source` lines in `game.tcl`: **0** (sources nothing) · in `backup.tcl`: **0** (standalone)
- `mol delete`/`mol new` in `game.tcl`: **0** (delegates to mutation::mutate / backup::restore only)
- Stub/TODO/placeholder patterns across all 10 phase files: **0**

---

## Smoke & Test Evidence (captured 2026-08-30, headless VMD 1.9.3 via WSL)

```
# CAPSTONE (phase15_smoke.tcl — SC1-SC4 end-to-end)
BCHM_SMOKE_RESULT PASS=1 FAIL=none            # ERROR) lines: 0
  run trace: 1k8p load Atoms: 555 → combined PDB Atoms: 560 → restore reload Atoms: 555
  echoed: vp_orig (4-matrix) … maxdiff=0  →  viewpoint round-trip exact

# TCLTEST SUITE (vmd/tests/test_registry.test, headless VMD, no GUI)
BCHM_TEST_RESULT Total=9 Passed=9 Failed=0 Skipped=0
  9/9 PASSED incl. count_hiders_after_reconstruct, count_hiders_empty,
  reset_clears_records, reconstruct_with_bound_arg_lambda

# MODULE SMOKES
phase15_mutation_smoke.tcl: BCHM_SMOKE_RESULT PASS=1 FAIL=none   # ERROR) lines: 0 (see W1)
phase15_backup_smoke.tcl:   BCHM_SMOKE_RESULT PASS=1 FAIL=none   # ERROR) lines: 0
phase15_game_smoke.tcl:     BCHM_SMOKE_RESULT PASS=1 FAIL=none   # ERROR) lines: 0
```

Capstone run trace from the capture (proving the pipeline executed): `Opened coordinate file .../Temp/biochemeleon_game.pdb` → `Atoms: 560 ... Segments: 2` → reload of `1k8p.pdb` → `Atoms: 555 ... Segments: 1` → `0` (post-cleanup `count_hiders`) → marker. The `PASS=1` is a genuine all-assertions gate: every SC1-SC4 check `_bail`s a named tag into `failures` on miss (phase15_smoke.tcl:42-45, 203-208), including the SC2d leak guard (`game_molid_leaked`) and the DI-key guard (`gs_key_game_molid`).

---

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| HIDER-01 (PDB-rebuild; hiders in SAME molecule) | ✓ SATISFIED | `mutation.tcl` write_combined_pdb + mutate; capstone: one 560-atom molecule (555+5), Segments: 2 |
| HIDER-02 (sentinel GAM/-999/GAME in-place via atomselect; registry keyed by index, reconstructable) | ✓ SATISFIED | tag_sentinels in-place tagging; registry `_records` keyed by index; reconstruct via DI from sentinels proven by capstone (count==5, is_hider 555-559) + pure suite 9/9 |

(REQUIREMENTS.md status table still shows "Pending" — updating it is the orchestrator's phase-close step, not the verifier's.)

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `vmd/smoke/phase15_mutation_smoke.tcl` | 84 | `regexp {-999\.0} $l` — pattern starts with `-`, Tcl parses it as an unknown switch → error `bad switch "-999\.0": must be -all, -about, ...` | ⚠️ Warning (W1) | The error raised mid-`foreach` aborted the smoke's §2a file-content check block (560-records / 5-hider-lines / hider-format assertions); VMD `-e` caught the top-level error and **continued**, and the bare error line lacks the `ERROR)` prefix so the runner scan missed it → those three sub-assertions were **silently skipped** while the smoke still printed `PASS=1 FAIL=none` |

**W1 assessment — NOT a phase-goal gap:**
- The authoritative SC1-SC4 gate is the **capstone** (`phase15_smoke.tcl`), which has no such bug (checks sentinel props via `atomselect get`, not file-line regexps) and ran clean.
- The mutation smoke's **mutate-path assertions (§3-§4) all ran and passed** — capture echoes show m0b=1 → m1=2 → n1=560 → sentinel selector `atomselect3` → indices `555 556 557 558 559` → cleanup reload m2=3 → leftover selector → `0` sentinels → `FAIL=none`. SC1/SC3-DI/SC2-mech remain proven.
- The skipped §2a check is redundant-by-design: the combined PDB's parseability + sentinel fields are proven end-to-end by mol-new + canonical-selector + in-place tagging (the design's authoritative mechanism; file-level `%6.1f`/segid survival was separately probe-verified per 15-02 SUMMARY).
- **Recommended fix (deferred, one token):** `regexp -- {-999\.0} $l` on line 84; also consider making module-smoke runners fail on ANY `bad switch|invalid command|wrong # args` line, not just `ERROR)`.

No other anti-patterns: zero TODO/FIXME/placeholder markers, zero 8.6 idioms, zero empty handlers, zero console-only implementations across all 10 phase files.

---

## Human Verification Required

**None required.** Phase 15 planned no GUI checkpoint (per ROADMAP plan list and the 5 SUMMARYs) — every success criterion is headless-verifiable and was headless-verified above. The first GUI-touching human-verify checkpoint belongs to Phase 16 (pick mechanism).

---

## Gaps Summary

**None.** All 4 success criteria verified with code-existence + wiring + live headless-smoke evidence; all 5 plans' must_haves (truths, artifacts, key_links) confirmed against the actual tree; requirements HIDER-01/HIDER-02 satisfied. One warning-level smoke defect (W1) documented above with a deferred one-token fix — it does not block the phase goal: the highest-risk VMD-specific unknown (PDB-rebuild mutation safety) is de-risked, and the generator work in Phase 16 can build on `game::start_game`/`game::cleanup` as proven.

---

_Verified: 2026-08-30T07:29:31Z_
_Verifier: OpenCode (gsd-verifier)_
