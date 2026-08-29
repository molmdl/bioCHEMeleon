# Phase 15: Mutation Safety & Hider Registry — Research (Registry real logic + game.tcl + test strategy)

**Researched:** 2026-08-30
**Domain:** VMD 1.9.3 tcl — pure-layer hider registry (dict + DI) + GameController composition root + headless tcltest/smoke strategy
**Confidence:** HIGH (DI injection shape + atomselect API **probed against the real VMD 1.9.3 install**; registry/test/smoke patterns ported from verified v1 + Phase 13)

**Scope of THIS doc:** `vmd/lib/registry.tcl` (fill real logic), `vmd/lib/game.tcl` (GameController composition root), the entry-script source change, and the two-layer test strategy (pure-registry tcltest + capstone full-pipeline headless smoke). Sibling researchers own (A) `mutation.tcl` PDB-rebuild mechanics and (B) `backup.tcl` viewpoint+reps. The responsibility split between the three mol-coupled modules is RECOMMENDED here and **must be reconciled by the planner** with researchers A & B.

## Summary

The registry is already a working PURE stub (Phase 13): a `dict` keyed by atom `index` → `{rep status}`, with `reconstruct_from_sentinels` using dependency injection via `[{*}$fetch_hider_ids]`. Phase 15 fills the **minimal** real logic: add `count_hiders` and `reset` (both have concrete Phase 15 callers — the smoke and cleanup respectively); leave `rep` empty for placeholder hiders (real rep assignment is Phase 16/17 generators). `game.tcl` is a thin orchestrator — `start_game` / `cleanup` / `restart` — that wires `backup` + `mutation` + `registry`, owns the `game_state` dict, and is the **only** module that touches all three. game.tcl injects the atomselect `apply` lambda into the registry (the only place atomselect touches the registry); the **exact, probed** injection line is documented below.

The capstone proof is `vmd/smoke/phase15_smoke.tcl`: load 1k8p (555 atoms) → `start_game 5` → assert game_molid has 560 atoms + 5 `resname GAM and beta < 0` sentinels + `registry::count_hiders == 5` → `cleanup` → assert restored molid has 555 atoms + saved reps + 0 sentinels + `count_hiders == 0`. This is where "it all works together" gets demonstrated.

**Primary recommendation:** Fill registry with `count_hiders` + `reset` only (YAGNI); build `game.tcl` as a thin orchestrator that delegates each `mol delete + mol new` to exactly one mol-bridge module (backup owns the restore-reload, mutation owns the mutate-reload, game owns neither); inject the atomselect lambda via `[list apply {{molid} {...}} $game_molid]` (NEVER `[apply ...]`).

## API findings

### DI injection shape — VERIFIED by headless probe (HIGH confidence)

Probe `tmp/probe15c/probe.tcl` ran against the real VMD 1.9.3 install (`BCHM_SMOKE_RESULT PASS=1 FAIL=none`). It loaded 1k8p (555 atoms), tagged atoms 100–104 in-place via `atomselect` (`resname GAM` + `beta -999` + `segname GAME`), built the **molid-bound** apply lambda, and called `reconstruct_from_sentinels`:

```tcl
# game.tcl injects THIS (verified):
::biochemeleon::registry::reconstruct_from_sentinels [list apply {{molid} {
    set sel [atomselect $molid "resname GAM and beta < 0"]
    set ids [$sel get index]
    $sel delete
    return $ids
}} $game_molid]
```

Probe results (from `out.txt`):
- The lambda returned `100 101 102 103 104` (the 5 tagged indices, as integers). `reconstruct_from_sentinels` registered all 5.
- `is_hider 100..104` → 1; `is_hider 0` → 0. Confirmed.
- `DEBUG buggy_form_evaluates_to: 100 101 102 103 104` — `[apply {lambda} $molid]` (without `list`) **evaluates immediately** and returns the id-list *value*. Passing that to `reconstruct_from_sentinels` would make `[{*}$fetch_hider_ids]` try to run `100 101 102 103 104` as a command → `invalid command name "100"`. This is the 13-01 bug, now concretely demonstrated.
- `DEBUG correct_form_is_command_prefix: apply {{molid} {...}} 0` — `[list apply {lambda} $molid]` yields the **command prefix** (a 3-element list). `[{*}$fetch_hider_ids]` expands it to `apply {lambda} 0` and invokes it. Correct.

**Note:** Phase 13's existing `test_registry.test` only exercised **zero-arg** lambdas (`[list apply {{} { return {5 10 15} }}]`). The probe is the first verification of the **one-arg (molid-bound)** form that game.tcl actually uses. The pure tcltest additions below add a bound-arg fake-lambda case so the pure suite also mirrors game.tcl's shape.

### atomselect API (citations: `vmd-ref/scripts/atomselect.tcl`; `.planning/research/STACK.md` §node122; `.planning/research/FEATURES.md` test3/test6)

| Operation | Form | Verified |
|---|---|---|
| Create selection | `set sel [atomselect $molid "resname GAM and beta < 0"]` | probe ✓ |
| Read atom `index` | `set ids [$sel get index]` → flat list of integer indices | probe ✓ (returned `100 101 102 103 104`) |
| Set sentinel fields | `$sel set resname GAM; $sel set beta -999; $sel set segname GAME` | probe ✓ (selector then found 5) |
| Count | `[$sel num]` → int | probe ✓ |
| **Delete (avoid leak)** | `$sel delete` | probe ✓ (called after every get) |
| Multi-attr read | `[$sel get {name type index resname resid chain segname x y z}]` → list-of-lists | `atomselect.tcl:76-77` (`vmd_print_atom_info`) |

**Attribute name note:** VMD's atomselect attribute for the segment field is `segname` (PyMOL's `segi`); `segid` is also accepted as a selector keyword/attribute (PITFALLS.md:113). The canonical **selector** is `resname GAM and beta < 0` (robust — does NOT depend on segid/segname column alignment; FEATURES.md test6, SUMMARY.md:49). game.tcl's injected lambda uses exactly this selector, so it is immune to the segid-vs-segname/column-alignment question (which is researcher A's sentinel-tagging concern).

### Registry record schema (current stub → Phase 15)

The stub (registry.tcl:13-16) records: `index → {rep "" status hidden}`. **Phase 15 keeps this schema unchanged.** Rationale:
- `index` is the dict KEY (VMD has no global atom id; `index` is stable within a molid's lifetime — PITFALLS.md:31, SUMMARY.md:106). Not stored redundantly in the record (v1 stored `id` in HiderRecord because its key was a `(object, id)` tuple; v2's key IS the index).
- `rep` stays `""` for Phase 15 placeholder hiders. The sentinel carries no rep (v1 Open Risk 6; SUMMARY.md:241). Real rep assignment (which GAME_REP a hider mimics) is Phase 16/17 generator work. **Recommendation: leave `rep` empty in Phase 15; do not add rep-population logic or rep validation now.**
- `status` is `hidden` (default) / `found` (set by `mark_found`). `mark_found` exists and is tested but is NOT exercised in Phase 15 (no click loop until Phase 16). Keep it.
- v1's `pos` / `is_altconf` / `endpoint_resvs` / `alt_tag` fields are NOT needed in Phase 15 (hint/reveal = Phase 6-equiv; alt-conf = Phase 11-equiv). YAGNI. Add when the phase that needs them arrives.

### game_state dict shape (returned by `start_game`, consumed by `cleanup`/`restart`)

```tcl
dict create \
    game_molid  <int>     ;# the NEW molid (combined PDB: original + hider atoms, sentinels tagged in-place)
    hider_count <int>     ;# N placeholder hiders (for restart to re-start with the same count)
    snapshot    <snap>    ;# backup::snapshot result: {pdb_path viewpoint reps} captured from the ORIGINAL before mutate
```

- `snapshot` embeds everything `cleanup` needs to restore the original: `pdb_path` (→ `mol new`), `viewpoint` + `reps` (→ re-apply). backup.tcl owns the snapshot's internal shape (researcher B).
- `original_molid` is intentionally NOT stored: after `mutation::mutate` does `mol delete $original_molid`, that molid is gone (molids are monotonic, never reused — PITFALLS.md:31). Storing a dead molid would be misleading. The original is recoverable only via `snapshot`'s `pdb_path`.
- `game_molid` IS stored (cleanup must `mol delete` it before reloading the original).

## Recommended approach

### 1. `vmd/lib/registry.tcl` — fill real logic (KEEP PURE)

Existing procs (keep, already tested): `reconstruct_from_sentinels {fetch_hider_ids}`, `is_hider {idx}`, `mark_found {idx}`.

**New procs for Phase 15 (minimal — both have concrete Phase 15 callers):**

| Proc | Signature | Purpose | Justification vs HIDER-02 / SC3 |
|---|---|---|---|
| `count_hiders` | `count_hiders {} → int` | Return `[dict size $_records]` | SC3 smoke asserts `count_hiders == 5`. Together with `atomselect` count == 5 + `is_hider` true for the 5 sentinel indices, this proves the registry has **exactly** the sentinel set (no more, no less). Without it, the smoke can only prove each sentinel `is_hider` (cannot prove the registry isn't over-populated). **REQUIRED.** |
| `reset` | `reset {} → {}` | `set _records [dict create]` | `cleanup` clears the registry after restore so post-cleanup `is_hider`/`count_hiders` return 0 (v1 parity: `game.py` cleanup does `self.registry = registry.HiderRegistry()`). Clearer than `reconstruct_from_sentinels [list apply {{} {return [list]}}]`. **Justified** (cleanup is a Phase 15 caller, not speculative). |

**DEFER to Phase 16/19 (YAGNI for Phase 15 — no Phase 15 caller):** `count_found`, `count_remaining` (= `count_hiders` − `count_found`, derivable; needed when the click loop exists), `list_hider_indices` (generators need it for placement; the smoke proves exactness via `count_hiders` + `is_hider`-per-sentinel without it), `hider_status` (a status reader; `mark_found` + `is_hider` suffice for Phase 15). Add these when the phase that calls them arrives.

**Export list** (registry.tcl:19) — add the two new public procs:
```tcl
namespace export reconstruct_from_sentinels is_hider mark_found count_hiders reset
```

**Purity gate (MUST stay clean):** `vmd/lib/registry.tcl` must contain ZERO `mol`/`atomselect`/`tk`/`toplevel`/`ttk::` tokens and ZERO tcl 8.6 idioms (`lmap`/`try`/`throw`/`tailcall`/`coroutine`/`yield`/`finally`). The grep gate (re-run after editing):
```bash
grep -rnE "\bmol\b|\batomselect\b|\btk\b|\btoplevel\b|\bttk::|\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/registry.tcl
# MUST return zero matches.
```

### 2. `vmd/lib/game.tcl` — GameController composition root (NEW)

game.tcl is the **only** module that references all three of `backup`/`mutation`/`registry`. It owns the `game_state` dict and the atomselect-lambda injection. It owns **no** `mol delete`/`mol new` directly — each reload is delegated to exactly one mol-bridge module (see responsibility split below).

```tcl
# vmd/lib/game.tcl -- Phase 15 composition root.
# Wires backup (viewpoint+reps) + mutation (PDB-rebuild+sentinel) + registry (pure).
# The ONLY module that touches all three; injects the atomselect apply-lambda
# into registry (the only place atomselect touches the registry).
# Sources NOTHING (the entry sources backup+mutation+registry in dep order
# before this file; re-sourcing registry here would WIPE _records -- do not).

namespace eval ::biochemeleon::game {
    namespace export start_game cleanup restart
}

# Begin a round. Phase 15: N placeholder hiders (mutation::make_placeholder_hiders).
# Phase 16 replaces make_placeholder_hiders with real sphere placement + reads setup.
# Returns game_state dict {game_molid hider_count snapshot}.
proc ::biochemeleon::game::start_game {molid hider_count} {
    # 1. Snapshot BEFORE any mutation (record original pdb_path + viewpoint + reps).
    set snapshot [::biochemeleon::backup::snapshot $molid]
    # 2. Build the combined PDB (original + N placeholder hider atoms). (mutation, researcher A)
    set combined_pdb [::biochemeleon::mutation::make_placeholder_hiders $molid $hider_count]
    # 3. Mutate: mol delete original + mol new combined + tag sentinels in-place. (mutation)
    set game_molid [::biochemeleon::mutation::mutate $molid $combined_pdb]
    # 4. SC4: re-apply saved reps + viewpoint to the NEW game_molid (viewmaster-style).
    ::biochemeleon::backup::apply $snapshot $game_molid
    # 5. Reconstruct the registry from sentinels (DI: inject the atomselect apply-lambda).
    ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{molid} {
        set sel [atomselect $molid "resname GAM and beta < 0"]
        set ids [$sel get index]
        $sel delete
        return $ids
    }} $game_molid]
    return [dict create game_molid $game_molid hider_count $hider_count snapshot $snapshot]
}

# Cleanup: restore the original molecule (mol delete game_molid + mol new original +
# re-apply reps+viewpoint), then clear the registry. Returns the restored molid.
proc ::biochemeleon::game::cleanup {game_state} {
    set restored [::biochemeleon::backup::restore [dict get $game_state snapshot]]
    ::biochemeleon::registry::reset
    return $restored
}

# Restart: cleanup, then re-start with the same hider_count on the restored molid.
proc ::biochemeleon::game::restart {game_state} {
    set hider_count [dict get $game_state hider_count]
    set molid [::biochemeleon::game::cleanup $game_state]
    return [::biochemeleon::game::start_game $molid $hider_count]
}
```

**Why `start_game {molid hider_count}` is Phase-16-ready:** Phase 16 replaces the single `make_placeholder_hiders` line with real generator dispatch (sphere placement from `setup_state`), but the `start_game` signature, the `game_state` shape, and the DI injection line stay identical. Keep the signature minimal (`molid hider_count`); do NOT add setup-state params in Phase 15.

### 3. Entry-script change (`vmd/biochemeleon.tcl`)

The entry currently sources (lines 70-80): `setup_state.tcl` → `registry.tcl` → `demos.tcl` → `gui/dialog.tcl`. Phase 15 ADDS three source lines in dependency order, **after `demos.tcl` and before `gui/dialog.tcl`**:

```tcl
set _dir [file dirname [info script]]
source [file join $_dir lib setup_state.tcl]
source [file join $_dir lib registry.tcl]
source [file join $_dir lib demos.tcl]
# Phase 15: mol bridges + composition root.
source [file join $_dir lib backup.tcl]
source [file join $_dir lib mutation.tcl]
source [file join $_dir lib game.tcl]
source [file join $_dir gui dialog.tcl]
unset _dir
```

**Dependency order rationale:** `setup_state` (pure) → `registry` (pure) → `demos` (mol, sources setup_state itself) → `backup` (mol) → `mutation` (mol) → `game` (composition root, references backup+mutation+registry namespaces — MUST be sourced after them) → `dialog` (GUI, independent of game).

**CRITICAL — do NOT double-source registry.tcl:**
- `backup.tcl` / `mutation.tcl` MAY `source setup_state.tcl` themselves for constants (harmless — `setup_state`'s `namespace eval` re-inits CONSTANTS to identical values; this is the existing `demos.tcl` pattern, demos.tcl:12).
- `backup.tcl` / `mutation.tcl` / `game.tcl` MUST NOT `source registry.tcl`. `registry.tcl`'s `namespace eval` re-inits `_records` to empty — re-sourcing would WIPE a populated registry. The entry sources registry.tcl exactly ONCE; the other modules reference `::biochemeleon::registry::*` at call time (proc resolution is at call time in tcl, so source order only needs the namespace to exist before the first CALL, which is always after the entry finishes sourcing).
- `game.tcl` sources NOTHING (it assumes the entry sourced its deps; for standalone test use, the test sources the lib files in dep order directly — see smoke skeleton).

### 4. Responsibility split (backup / mutation / game) — RECOMMENDED, planner must reconcile

The central design question: **who owns each `mol delete + mol new`?** In v1, `backup.restore` owned the reload (`cmd.delete + cmd.create`) and `mutation.insert_hider` was in-place (no reload). In v2, BOTH the mutate path and the restore path require a reload (VMD can't add/remove atoms in place — PITFALLS.md:65, Pitfall 8). My recommendation gives each mol-bridge module exactly ONE reload, and game.tcl none:

| Module | Owns this reload | Recommended procs (interface game.tcl consumes) |
|---|---|---|
| `backup.tcl` (researcher B) | **restore-reload** (reload the pristine original) | `snapshot {molid} → {pdb_path viewpoint reps}`; `apply {snapshot molid}` (apply reps+viewpoint to a molid, NO mol delete); `restore {snapshot} → new_molid` (`mol delete <top> + mol new <pdb_path> + apply`) |
| `mutation.tcl` (researcher A) | **mutate-reload** (reload the combined PDB) | `make_placeholder_hiders {molid hider_count} → combined_pdb_path`; `mutate {molid combined_pdb_path} → new_molid` (`mol delete $molid + mol new $combined_pdb + tag sentinels`); (tagging may be a `tag_sentinels {molid}` helper folded into `mutate`) |
| `game.tcl` (this doc) | **none** — orchestrates | `start_game` / `cleanup` / `restart`; calls `backup::snapshot` → `mutation::make_placeholder_hiders` → `mutation::mutate` → `backup::apply` → `registry::reconstruct_from_sentinels` |

**Why this split:** it mirrors v1's spirit (backup owns restore), keeps each mol-bridge cohesive (backup = "viewpoint+reps+original-path"; mutation = "atoms+sentinels+combined-PDB"; neither knows the other's concern), and keeps game.tcl a thin orchestrator (like v1 `game.py`). `backup::apply` is called by game.tcl **after** `mutation::mutate` (SC4: "restored on the new molid") — this keeps mutation unaware of reps/viewpoint and backup unaware of the combined PDB.

**⚠️ Flag for the planner:** researchers A & B may propose alternatives (e.g., game.tcl owns all `mol delete`/`mol new` and backup/mutation are pure helpers; or `mutation::mutate` takes only the combined PDB and game deletes the original). The planner MUST reconcile the three researchers' splits into ONE coherent design. The non-negotiable constraints (regardless of split): (a) `backup::snapshot` MUST run before any `mol delete` (captures original state); (b) `registry::reconstruct_from_sentinels` MUST run after the combined PDB is loaded + sentinels tagged (the lambda selects on the game_molid); (c) the atomselect lambda is injected ONLY by game.tcl; (d) every `atomselect` is `$sel delete`'d before any `mol delete` (stale-data pitfall).

## Pitfalls

### 1. `[$fetch_hider_ids]` vs `[{*}$fetch_hider_ids]` — the 13-01 DI bug (HIGH, verified)
**What goes wrong:** Injecting an `apply` lambda via `[apply {lambda} $molid]` (no `list`) **evaluates it immediately**, returning the id-list *value* (`100 101 102 103 104`). `reconstruct_from_sentinels` then does `[{*}$fetch_hider_ids]` which tries to expand that value as a command → `invalid command name "100"`. Symptom: 4/5 registry tests failed in Phase 13 (13-01-SUMMARY.md:100-106).
**Root cause:** `$cmd` (single variable substitution) invokes a single-word command; an `apply` lambda is a multi-word command *prefix* that needs argument EXPANSION (`{*}`), not substitution.
**How to avoid:** game.tcl injects via `[list apply {lambda} $game_molid]` (a VALUE / command prefix); registry calls `[{*}$fetch_hider_ids]`. The 13-RESEARCH-testing.md skeleton (line 288) shows the BUGGY `[apply ...]` form — do NOT copy it. **Probe-verified** (see DEBUG lines above).
**Also:** the same bug appears if a proc-name injection is written `[my_proc]` (calls immediately) vs passing `my_proc` (the name) and letting `[{*}]` expand the 1-element list to itself. The `{*}` form works for BOTH proc names and apply lambdas — always use it.

### 2. atomselect leaks + stale data on a deleted molecule (HIGH)
**What goes wrong:** `atomselect` objects leak if not `$sel delete`'d. Worse: a dangling atomselect on a `mol delete`'d molecule returns **STALE data silently** (no error) — PITFALLS.md:106, vmd/AGENTS.md.
**How to avoid:** every `atomselect` path `$sel delete`'s before returning (the injected lambda does this). Never cache a selection across `mol delete`/reload (molid changes). In game.tcl, the lambda creates + deletes the selection in one call; it does not survive across `start_game`/`cleanup`.

### 3. molid changes on reload — registry is NOT persisted (HIGH)
**What goes wrong:** `index` is stable within a molid's lifetime, but **molid changes on every reload** (molids monotonic, never reused — PITFALLS.md:31). So the registry CANNOT be persisted across `start_game`→`cleanup`→`restart` by molid; it must REBUILD from sentinels each time a combined molecule is loaded.
**How to avoid:** `start_game` always calls `reconstruct_from_sentinels` (which clears first — overwrite, not append). `cleanup` calls `reset`. `restart` = `cleanup` + `start_game` (the new `start_game` reconstructs on the fresh game_molid). The registry is a namespace singleton with NO cross-reload persistence in Phase 15 (persistence/.bcm sidecar is a much later phase).

### 4. Keeping registry pure — the grep gate (MEDIUM, easy to violate by accident)
**What goes wrong:** Adding a "convenience" `mol`/`atomselect` call inside registry.tcl breaks the pure-layer contract and makes it un-unit-testable in WSL (tcltest without VMD).
**How to avoid:** registry.tcl references ONLY stdlib tcl + its own namespace vars. The atomselect lambda is INJECTED by game.tcl — registry calls `[{*}$fetch_hider_ids]` without knowing it touches atomselect. Re-run the grep gate (§Recommended approach 1) after every registry edit. Comments use literal-worded prohibitions ("no molecular-viewer API") not the forbidden tokens, to keep the gate clean (13-01-SUMMARY.md:44).

### 5. `molinfo $m get filename` returns a list-of-lists (MEDIUM — backup's concern, but game_state consumes it)
`molinfo $m get filename` returns a list-of-lists; use `[lindex [molinfo $m get filename] 0]` for the first file path (PITFALLS.md:443). backup.tcl's `snapshot` must normalize this into `snapshot`'s `pdb_path`. game.tcl just passes `snapshot` through; it does not parse `filename` itself.

### 6. Sentinel survives only in memory (not via `save_state`) — NOT a Phase 15 problem (LOW, but note it)
Pitfall 7: `save_state` does NOT persist `beta`/`segid`/script-modified atom data (save_state.tcl:39-46). In Phase 15 this is irrelevant — the sentinel is tagged in-place via `atomselect` after `mol new` of the combined PDB, lives in memory for the round, and is gone on `mol delete` (cleanup). No `save_state` in Phase 15. (Persistence/.bcm is a much later phase.) The in-place tagging is robust against PDB column misalignment (AGENTS.md; researcher A's job). game.tcl's lambda reads `resname GAM and beta < 0` (canonical, column-independent).

## Open questions

1. **backup.tcl / mutation.tcl / game.tcl responsibility split** — RECOMMENDATION given above (backup owns restore-reload; mutation owns mutate-reload; game owns neither). **The planner MUST reconcile** this with researchers A & B's recommendations into ONE coherent design. Non-negotiable constraints listed in §Recommended approach 4. If researchers A/B prefer game.tcl to own `mol delete`/`mol new`, the `game_state` shape and DI injection line are unaffected — only the bodies of `start_game`/`cleanup` change.

2. **`rep` field population in Phase 15** — RECOMMEND: leave `rep` empty (`""`) for placeholder hiders. The sentinel carries no rep; real rep assignment is Phase 16/17 generator work. Phase 15 does NOT add rep-population, rep validation, or a `set_rep` proc. (Consistent with v1 `reconstruct_from_sentinels` setting `rep=None`.) The smoke does not assert on `rep`.

3. **Viewpoint-match assertion in the capstone smoke** — RECOMMEND: the smoke asserts `numreps` matches (simple, robust) and delegates the precise viewpoint-matrix match to a `backup` helper (e.g. `backup::viewpoint_equal {snap molid}` — researcher B may provide). If researcher B does not provide a compare helper, the smoke can compare one matrix element (e.g. `molinfo $m get {rotate_matrix}` equality) as a weaker check. **Flag for reconciliation with researcher B.** SC4 requires "viewpoint … restored on the new molid"; the exact assertion strength is researcher B's call.

4. **Does `cleanup` clear the registry?** — RECOMMEND yes, via `registry::reset` (v1 parity; post-cleanup `is_hider`/`count_hiders` return 0). If the planner prefers not to add `reset`, `cleanup` can call `reconstruct_from_sentinels [list apply {{} {return [list]}}]` (reuses the existing tested proc) — but `reset` is clearer.

## Test strategy

Two layers, matching the established Phase 13/14 pattern.

### Layer A: pure-registry tcltest — extend `vmd/tests/test_registry.test` (NO VMD atomselect; runs under headless VMD tcltest)

Add these cases to the existing 5 (keep the existing 5 unchanged). DI uses `[list apply ...]` command prefixes (VALUES, not evaluated). The bound-arg case mirrors game.tcl's molid-bound shape WITHOUT atomselect.

```tcl
# ---- Phase 15 additions: count_hiders + reset + bound-arg DI ----

test count_hiders_after_reconstruct {} -body {
    ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{} { return {5 10 15} }}]
    ::biochemeleon::registry::count_hiders
} -result 3

test count_hiders_empty {} -body {
    ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{} { return [list] }}]
    ::biochemeleon::registry::count_hiders
} -result 0

test reset_clears_records {} -body {
    ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{} { return {1 2} }}]
    ::biochemeleon::registry::reset
    list [::biochemeleon::registry::count_hiders] [::biochemeleon::registry::is_hider 1]
} -result {0 0}

# Mirrors game.tcl's molid-bound apply-lambda injection shape (bound arg, no atomselect).
# Proves [{*}$fetch_hider_ids] expands the 3-element command prefix (apply {lambda} <arg>).
test reconstruct_with_bound_arg_lambda {} -body {
    ::biochemeleon::registry::reconstruct_from_sentinels \
        [list apply {{fake_molid} { return {7 8} }} "dummy_molid"]
    list [::biochemeleon::registry::is_hider 7] \
         [::biochemeleon::registry::is_hider 8] \
         [::biochemeleon::registry::count_hiders]
} -result {1 1 2}
```

**Harness conventions (established Phase 13, MANDATORY):**
- Source via `[pwd]`: `source [file join [pwd] vmd lib registry.tcl]` (under `vmd -e`, `[info script]` is empty — 13-RESEARCH-testing.md Pitfall 3).
- Result marker printed **BEFORE** `cleanupTests` (the `numTests` array is correct before, reset after):
  ```tcl
  set total $::tcltest::numTests(Total)
  set passed $::tcltest::numTests(Passed)
  set failed $::tcltest::numTests(Failed)
  set skipped $::tcltest::numTests(Skipped)
  puts "BCHM_TEST_RESULT Total=$total Passed=$passed Failed=$failed Skipped=$skipped"
  cleanupTests
  ```
- Run: `bash -ic 'cd tmp/<stage> && vmd -dispdev text -e vmd/tests/test_registry.test -eofexit < /dev/null' 2>&1 | tail -80` (stage with `cp -r vmd tmp/<stage>/`). VMD does NOT propagate exit codes (`$?` always 0) → parse the `BCHM_TEST_RESULT` marker, NEVER `$?`.
- The pure-layer grep gate MUST stay clean after editing registry.tcl.

### Layer B: capstone full-pipeline headless smoke — `vmd/smoke/phase15_smoke.tcl` (NEW)

This is the end-to-end proof that backup + mutation + registry + game work together (SC1, SC2, SC3, SC4). It sources the lib files directly in dependency order (mirrors `phase14_mol_smoke.tcl`'s direct-source pattern, NOT the entry — avoids GUI/dialog baggage). It loads a real demo, runs a full round, and asserts every success criterion.

```tcl
# vmd/smoke/phase15_smoke.tcl
# Capstone headless smoke for Phase 15: the full backup -> mutate -> reconstruct ->
# cleanup -> restore pipeline. Proves SC1-SC4 end-to-end.
# -e'd by VMD: [info script] is EMPTY -> use [pwd] (staging root). VMD does NOT
# propagate exit codes -> parse BCHM_SMOKE_RESULT, NEVER $?.

set failures [list]
proc _bail {tag msg} { upvar 1 failures f; lappend f "$tag:$msg" }

# Source lib files in dependency order. registry is pure+standalone; demos sources
# setup_state itself (for load_demo); backup/mutation are mol bridges; game is the
# composition root (sources nothing -- assumes deps already sourced).
source [file join [pwd] vmd lib registry.tcl]
source [file join [pwd] vmd lib demos.tcl]
source [file join [pwd] vmd lib backup.tcl]
source [file join [pwd] vmd lib mutation.tcl]
source [file join [pwd] vmd lib game.tcl]

# 1. Load 1k8p (555 atoms). Set up reps + viewpoint on the original so SC4 can
#    verify save/restore (backup.snapshot captures them).
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    if {[molinfo $orig_molid get numatoms] != 555} { _bail orig_atoms "exp=555" }
    # Add a VDW rep (default is Lines only) so numreps > 1 is restorable.
    catch {mol representation VDW}
    catch {mol addrep $orig_molid}
    set saved_numreps [molinfo $orig_molid get numreps]
}

# 2. start_game: 5 placeholder hiders.
if {[catch {::biochemeleon::game::start_game $orig_molid 5} gs]} {
    _bail start_game $gs
} else {
    set game_molid [dict get $gs game_molid]

    # SC1: game_molid has 555+5 = 560 atoms.
    if {[molinfo $game_molid get numatoms] != 560} {
        _bail game_atoms "exp=560 got=[molinfo $game_molid get numatoms]"
    }
    # SC1: exactly 5 sentinels via the canonical selector.
    if {![catch {atomselect $game_molid "resname GAM and beta < 0"} sel]} {
        set sent_ids [$sel get index]
        if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
        $sel delete
    } else { _bail sentinel_sel $sel }

    # SC3: registry recorded exactly the 5 sentinel indices.
    if {[::biochemeleon::registry::count_hiders] != 5} {
        _bail registry_count "exp=5 got=[::biochemeleon::registry::count_hiders]"
    }
    foreach idx $sent_ids {
        if {![::biochemeleon::registry::is_hider $idx]} { _bail is_hider_true $idx }
    }
    if {[::biochemeleon::registry::is_hider 0]} { _bail is_hider_false "idx 0" }

    # SC4: reps restored on the new game_molid (viewpoint delegate to backup -- see OQ3).
    if {[molinfo $game_molid get numreps] != $saved_numreps} {
        _bail game_numreps "exp=$saved_numreps got=[molinfo $game_molid get numreps]"
    }

    # 3. cleanup: restore the original.
    if {[catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
        _bail cleanup $restored_molid
    } else {
        # SC2: restored has 555 atoms (no hiders).
        if {[molinfo $restored_molid get numatoms] != 555} {
            _bail restored_atoms "exp=555 got=[molinfo $restored_molid get numatoms]"
        }
        # SC2: same reps as the original.
        if {[molinfo $restored_molid get numreps] != $saved_numreps} {
            _bail restored_numreps "exp=$saved_numreps got=[molinfo $restored_molid get numreps]"
        }
        # SC2: no sentinels remain.
        if {![catch {atomselect $restored_molid "resname GAM and beta < 0"} sel2]} {
            if {[$sel2 num] != 0} { _bail restored_sentinels "got=[$sel2 num]" }
            $sel2 delete
        } else { _bail restored_sentinel_sel $sel2 }
        # SC3: registry cleared after cleanup.
        if {[::biochemeleon::registry::count_hiders] != 0} {
            _bail registry_after_cleanup "exp=0 got=[::biochemeleon::registry::count_hiders]"
        }
    }
}

# Report.
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
```

**Smoke harness conventions (established Phase 13/14, MANDATORY):**
- Run from a `/mnt/c` staging root: `mkdir -p tmp/phase15-stage && cp -r vmd tmp/phase15-stage/` (NO `rm` — opencode.json denies it; `tmp/` is gitignored).
- Invoke: `bash -ic 'cd tmp/phase15-stage && vmd -dispdev text -e vmd/smoke/phase15_smoke.tcl -eofexit < /dev/null' > out.txt 2>&1; tail -80 out.txt` (use `timeout 180` + file redirect; the `| tail` pipe with no timeout can hang — learned during this research's probe).
- The smoke script ends with `exit` (defensive — `-eofexit` should exit at EOF, but an explicit `exit` guarantees it even if an error leaves VMD at the `vmd >` prompt).
- Parse `BCHM_SMOKE_RESULT PASS=1 FAIL=<...>`, NEVER `$?` (VMD always exits 0).
- Every `atomselect` is `$sel delete`'d (leak + stale-data pitfall).
- The smoke delegates viewpoint-matrix equality to `backup` (OQ3); the skeleton above asserts `numreps` (robust) and leaves the precise viewpoint check as a `backup`-helper call to be inserted per researcher B's API.

## Sources

### Primary (HIGH confidence)
- **Headless VMD 1.9.3 probe** (`tmp/probe15c/probe.tcl` + `out.txt`, run 2026-08-30): verified the molid-bound apply-lambda DI injection `[list apply {{molid} {...}} $molid]` + `[{*}$fetch_hider_ids]` works end-to-end with a real `atomselect`; `$sel get index` returns integer indices; `$sel delete` cleans up; `resname GAM and beta < 0` selector finds tagged atoms; `is_hider` correctly distinguishes registered vs unregistered. Concretely demonstrated the `[apply ...]` (buggy) vs `[list apply ...]` (correct) distinction.
- **`vmd-ref/scripts/atomselect.tcl`** (VMD 1.9.3 core): `atomselect $molid "..."`, `$sel get $attr` / `$sel get index`, `$sel set`, `$sel num`, `$sel delete`, multi-attr list-of-lists return (`vmd_print_atom_info:69-82`).
- **Existing code** (read directly): `vmd/lib/registry.tcl` (Phase 13 stubs), `vmd/tests/test_registry.test` (5 cases + harness conventions), `vmd/biochemeleon.tcl` (entry source order + re-source guard), `vmd/lib/setup_state.tcl` (GAME_REPS), `vmd/lib/demos.tcl` (load_demo, script_dir pattern), `vmd/smoke/phase13_smoke.tcl` + `phase14_mol_smoke.tcl` (smoke conventions).
- **v1 shipped code** (the ported pattern): `pymol/biochemeleon/registry.py` (DI `reconstruct_from_sentinels`, rep=None tolerance, keyed by `(object,id)` — v2 keys on `index`), `pymol/biochemeleon/game.py` (GameController orchestrator: start/cleanup/reconstruct_registry; cleanup resets registry), `pymol/biochemeleon/backup.py` + `mutation.py` (the cmd-bridge split being adapted to VMD's reload-based model).

### Secondary (MEDIUM confidence)
- **`.planning/research/{STACK,PITFALLS,FEATURES,SUMMARY}.md`** (VMD-specific research, verified against the real install): `molinfo $m get filename` list-of-lists (PITFALLS:443); viewpoint matrices `molinfo $mol get {rotate_matrix center_matrix scale_matrix global_matrix}` (viewmaster pattern, FEATURES:433); canonical selector `resname GAM and beta < 0` (FEATURES test6, SUMMARY:49); `index` stable within molid lifetime, molid changes on reload (PITFALLS:31, SUMMARY:106); `save_state` drops beta/segid (PITFALLS Pitfall 7 — not a Phase 15 concern); `atomselect get` works for `index` + 17 other attrs (FEATURES test3).
- **`13-01-SUMMARY.md`** (the DI bug fix): `[$fetch_hider_ids]` → `[{*}$fetch_hider_ids]`; tests use `[list apply ...]` (value) not `[apply ...]` (evaluated); "Downstream plans (Phase 15 game.tcl) MUST use the `{*}` form when injecting `apply` lambdas."
- **`vmd/AGENTS.md`** + **root `AGENTS.md`**: WSL/Windows split, headless invocation, tcl 8.5.6 limits, sentinel rules, atomselect-leak/stale-data rules.

## Metadata

**Confidence breakdown:**
- DI injection shape + atomselect API: **HIGH** — probed against the real VMD 1.9.3 install (PASS).
- Registry real logic (count_hiders + reset): **HIGH** — trivial dict ops on the existing tested stub; pure-layer pattern established in Phase 13.
- game.tcl GameController design: **HIGH** for the DI injection line + game_state shape + entry change (verified patterns); **MEDIUM** for the exact proc bodies (depend on the backup/mutation API, which is researcher A/B's and must be reconciled).
- Test strategy: **HIGH** — both layers follow established, verified Phase 13/14 harness conventions; the pure tcltest reuses the working DI pattern; the capstone smoke mirrors `phase14_mol_smoke.tcl`.

**Research date:** 2026-08-30
**Valid until:** 2026-09-29 (30 days; stable — VMD 1.9.3 / tcl 8.5.6 are fixed installs, no fast-moving deps). The only time-sensitive element is reconciliation with researchers A & B's backup/mutation API designs, which the planner resolves immediately.
