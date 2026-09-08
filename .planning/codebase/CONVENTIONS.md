# Coding Conventions

**Analysis Date:** 2026-09-08 (supersedes 2026-08-22 version — Phases 16, 17.1, 17.2 of the v2 VMD port landed since)

## Two Viewers, Two Convention Sets

This repo ships TWO implementations of the same game. Conventions are per-viewer; do not mix idioms across them.

| | v1 PyMOL (SHIPPED) | v2 VMD (ACTIVE milestone) |
|---|---|---|
| Language | Python 3.6.9 | Tcl 8.5.6 (inside VMD 1.9.3) |
| Location | `pymol/` | `vmd/` |
| GUI | PyQt5 via `pymol.Qt` | Tk 8.5 + ttk |
| Domain namespace | `biochemeleon.*` modules | `::biochemeleon::<module>::` namespaces |
| Entry file | `pymol/biochemeleon/__init__.py` | `vmd/biochemeleon.tcl` |

Read the viewer-specific `pymol/AGENTS.md` / `vmd/AGENTS.md` before touching code. Everything below emphasizes **v2 (Tcl)** — it is where all current work happens — with v1 conventions condensed at the end.

---

# PART A — v2 VMD (Tcl) Conventions — ACTIVE

## Naming Patterns

**Namespaces:**
- Lib modules: `namespace eval ::biochemeleon::<module>::` — one namespace per file, module name == file stem: `::biochemeleon::setup_state` (`vmd/lib/setup_state.tcl`), `::biochemeleon::registry` (`vmd/lib/registry.tcl`), `::biochemeleon::generators`, `::biochemeleon::splice`, `::biochemeleon::rep_tiers`, `::biochemeleon::game_logic`, `::biochemeleon::demos`, `::biochemeleon::backup`, `::biochemeleon::mutation`, `::biochemeleon::hiders`, `::biochemeleon::game`, `::biochemeleon::pick_bridge`.
- GUI files: `::biochemeleon::setup_tab`, `::biochemeleon::game_tab`, `::biochemeleon::dialog`.
- Entry point: `::BCM::` (short prefix for the extension shell in `vmd/biochemeleon.tcl`).

**Procs:**
- ALWAYS fully qualified: `proc ::biochemeleon::splice::perp_vector {u {ref1 {...}}} {...}` — never bare `proc name`.
- Public API: declared in the module's `namespace export` list (the export list DOCUMENTS the contract; callers may use fully-qualified names or `namespace import`).
- Private helpers: leading underscore, NOT exported: `::biochemeleon::splice::_cross`, `_dot`, `_norm`, `_unit`; `::biochemeleon::mutation::_hider_record`.
- Verbs describe behavior: `validate_state`, `randomize_per_rep`, `reconstruct_from_sentinels`, `mark_found`, `count_remaining`, `resolve_per_rep`, `make_residue_hiders`, `tag_sentinels_mixed`.

**Constants (`variable`):**
- `UPPER_CASE` inside the `namespace eval` body, ONE `variable` declaration per line, with an inline `;#` comment giving units/why:
  ```tcl
  variable SPLICE_DISPLACEMENT 1.0  ;# A perpendicular to the peptide bond (hard envelope 1.43)
  variable RESID_BASE 9001          ;# disjoint fake-resid block start (real demo resids <= ~500)
  ```
  See `vmd/lib/splice.tcl:70-74`, `vmd/lib/generators.tcl:31-39`, `vmd/lib/mutation.tcl:38-46`.
- State-holding namespace variables are lowercase with a leading underscore for privates: `registry`'s `_records` and `_resid_block` (`vmd/lib/registry.tcl:20-31`).

**Files:**
- Lib/GUI: lowercase, underscores: `setup_state.tcl`, `game_logic.tcl`, `pick_bridge.tcl`.
- Tests: `vmd/tests/test_<module_under_test>.test` — mirrors the module (`test_rep_tiers.test` ↔ `vmd/lib/rep_tiers.tcl`).
- Smokes: `vmd/smoke/phase<N>_<topic>_smoke.tcl` (e.g. `phase17_splice_smoke.tcl`, `phase17_e2e_smoke.tcl`).
- GUI verify drivers: `vmd/tests/<topic>_verify.tcl` (`rep_verify.tcl`, `pick_verify.tcl`).

**Sentinel / domain values (fixed contract):**
- Hider sentinel: `resname GAM` (3 chars — a 4-char "GAME" is silently dropped by PDB columns) + `beta -999` (VALUE) + `segid GAME` (4 cols) + chain `G` + resid base `9001`.
- The canonical SELECTOR is `resname GAM and beta < 0` — NEVER `beta -999` as exact match, NEVER `beta < 0` alone (over-matches real atoms). See `vmd/lib/mutation.tcl:38-44`.
- Residue tiers get `beta -999.0` on the CA ONLY (`0.00` on N/C/O/CB) — Pitfall C6, `vmd/lib/mutation.tcl` header.
- Registry keys on atom `index` (NOT v1's `(object, id)` — VMD has no global atom id; molid changes on reload).

## File Header Convention (the provenance banner)

Every `vmd/lib/*.tcl` opens with a `# vmd/lib/<name>.tcl` path line, then a banner block that MUST state:
1. **Purity tier** in the first lines: `# PURE layer: stdlib-only tcl 8.5. No molecular-viewer API, no GUI toolkit -- unit-testable via tcltest under headless VMD` (pure files) or `# -- MOL BRIDGE: ...` (mol-coupled) or `# -- GUI layer / VIEW` (Tk files). See `vmd/lib/splice.tcl:1-15`, `vmd/lib/hiders.tcl:1-3`, `vmd/gui/game_tab.tcl:1-3`.
2. **What it sources** and why (with the "pure re-init on re-source is harmless" note): `vmd/lib/splice.tcl:50-62`, `vmd/lib/mutation.tcl:15-24`.
3. **Decision records** — durable design decisions with plan-ID citations, e.g. splice.tcl's "THE SS DECISION" block (`vmd/lib/splice.tcl:17-30`) and rep_tiers' "THE TIER SEAM" (`vmd/lib/rep_tiers.tcl:12-25`).
4. **Pitfall references** by ID (P1/P2/P6/P7/P9/P10, C1/C2/C6/C8) tied to the research docs in `.planning/phases/<phase>/`.

## Date-Stamped Discovery Comments

Discoveries from probe/GUI sessions are recorded IN CODE with plan IDs and dates, not in side docs alone:
- `# ... (LOCKED — GUI-verified 2026-08-30 plan 16-12; first-click quirk verified 2026-09-03 plans 16-16/16-17)` style — see `vmd/AGENTS.md` picking section (the convention's canonical form).
- In-code examples: `vmd/lib/hiders.tcl` cites "probe-verified", "P1"–"P10" pitfalls inline; `vmd/lib/game_logic.tcl` cites "16-RESEARCH-gametab SS1 row 1, SS6.10" and "the 04-04 lesson".
- Rule: every non-obvious behavior claim (an API quirk, a probe result, a GUI verification) carries the plan ID that proved it. Write `(verified <date> <plan-id>)` or `(P<n>)`/`(C<n>)` tags. Never state an unverified claim as fact — `spec.md` requires ALL claims verified.

## Tcl 8.5 Constraint Patterns (concrete do/don't)

Tcl inside VMD 1.9.3 is **8.5.6**. The 8.6-idiom grep gate must return ZERO (see Quality Gates).

**Error handling — no `try`/`finally`/`throw`:**
```tcl
# DON'T (8.6 — gate trips):
try { $sel delete } finally { ... }

# DO (the autoionize.tcl:81-88 pattern — always restore state in the catch branch):
if {[catch {
    ... risky script ...
} err]} {
    # restore state here, then re-raise or degrade
    error "context: $err"
}
```

**Iteration — no `lmap`:**
```tcl
# DON'T:
set doubled [lmap x $xs {expr {$x * 2}}]

# DO (foreach + lappend):
set doubled [list]
foreach x $xs { lappend doubled [expr {$x * 2}] }
# or: dict for {k v} $d { ... }
```

**`expr` MUST be braced** (speed + injection safety):
```tcl
# DON'T: expr {$a} + {$b}   /   expr $a + $b
# DO:
if {[_norm $u] < 1e-6} { ... }                       ;# vmd/lib/splice.tcl:115
return [expr {abs(double($a) - double($b)) < 1.0e-6}]
```

**Argument expansion — `{*}` not `[eval ...]`:**
```tcl
# DI command-prefix expansion (the idiomatic Tcl dependency injection):
foreach idx [{*}$fetch_hider_ids] { ... }            ;# vmd/lib/registry.tcl:45
```

**`regexp` with a pattern starting with `-` needs `--`** (the false-PASS lesson):
```tcl
# DON'T: regexp {-999\.0} $l          ;# -999 parsed as a regexp switch
# DO:
if {![regexp -- {-999\.0} $l] || ![regexp {GAME} $l]} { ... }   ;# vmd/smoke/phase15_mutation_smoke.tcl:88
if {[regexp -- {Rad\s+(-?[0-9.eE+-]+)} $line -> r]} { ... }     ;# vmd/smoke/phase17_cpk_smoke.tcl:163
```

**Membership and containment:**
- `lsearch -exact $list $item` (never bare `lsearch` — glob semantics).
- `string first` for substring checks (`vmd/lib/rep_tiers.tcl` header: "one `variable` declaration per line; `lsearch -exact` for membership; `string first` for the sentinel check").

**Variable scoping:** inside a proc, `variable <name>` (namespace var) or `global <name>` before use — undeclared access is "the #1 tcl beginner trap".

**`namespace eval` body re-runs on every `source`** — it re-initializes `variable`s. Guard persistent state with `info exists` (e.g. `vmd/biochemeleon.tcl`'s re-source guard). For lib constants the re-init is harmless IF values are identical (mutation.tcl:16-17 documents this deliberately).

**`[info script]` is EMPTY under `vmd -e`** (verified probe — VMD uses a non-source mechanism for -e). File location needs the cwd fallback:
```tcl
# vmd/lib/splice.tcl:54-62 — the sibling-locate pattern:
set ::_splice_dir [file dirname [info script]]
if {![file exists [file join $::_splice_dir generators.tcl]]} {
    set ::_splice_dir [file join [pwd] vmd lib]     ;# headless-VMD cwd = staging root
}
if {![file exists [file join $::_splice_dir generators.tcl]]} {
    error "splice.tcl: cannot locate sibling generators.tcl"   ;# LOUD, never silent
}
```
Tests and smokes simply use `source [file join [pwd] vmd lib <module>.tcl]` (VMD cwd = the staging root).

**`vwait` never re-enters the event loop for vars set in the same proc** — use `after` (see the AFTER-discipline below).

**Selection hygiene:** every `atomselect` object is `$sel delete`d — a dangling selection on a deleted molecule returns STALE data silently (`vmd/lib/mutation.tcl:5` header rule; every smoke re-states it).

**Headless-safe sourcing:** GUI files contain ONLY `namespace eval` + proc definitions at file scope — zero widget commands execute at source time, so `vmd -dispdev text -e` sourcing is safe (`vmd/gui/game_tab.tcl:31-36` states the contract). Tk-dependent drivers (e.g. `vmd/tests/rep_verify.tcl:62-64`) wrap the whole body in `if {![info exists ::tk_version]} { vmdcon -warn ...; return }`.

**GUI AFTER-discipline** (`vmd/gui/game_tab.tcl:9-20`, all 7 rules): every `after` id tracked + catch-cancel before re-arm; callbacks guard `winfo exists` and wrap widget writes in catch; conditional re-arm only while the state machine says so; schedule by VALUE with fully-qualified literal command names (viewmaster.tcl idiom); re-schedule at the END of the body; countdown = chained one-shots, timer = self-rescheduling; never call `update`, never block.

**Modeless main dialog:** NEVER `grab set` on the main panel (the grep gate enforces zero in `vmd/gui/`); `grab set` on transient sub-dialogs only (mergestructs pattern).

## Purity Tiers (ENFORCED — never reverse)

```
vmd/lib/setup_state.tcl   PURE (stdlib tcl only)          -> test_setup_state.test
vmd/lib/registry.tcl       PURE (+ GAME_REPS import)       -> test_registry.test
vmd/lib/generators.tcl     PURE                            -> test_generators.test
vmd/lib/splice.tcl         PURE (sources generators)       -> test_splice.test
vmd/lib/rep_tiers.tcl      PURE (sources setup_state)      -> test_rep_tiers.test
vmd/lib/game_logic.tcl     PURE (state machine/timer/log)  -> test_game_logic.test
vmd/lib/demos.tcl          mol bridge (mol/atomselect)
vmd/lib/backup.tcl         mol bridge
vmd/lib/mutation.tcl       mol bridge (sources setup_state/generators/splice)
vmd/lib/hiders.tcl         mol bridge (rep pairs, tier codes)
vmd/lib/pick_bridge.tcl    mol bridge (trace-based picking)
vmd/lib/game.tcl           COMPOSITION ROOT (wires backup+mutation+registry+hiders)
vmd/gui/*.tcl              Tk VIEW layer (no decisions)
```
- Pure files must have NO `mol`/`atomselect`/`molinfo`/`tk`/`toplevel` calls. Viewer access crosses the tier ONLY via dependency injection (the composition root passes a command prefix into a pure proc — `registry::reconstruct_from_sentinels {fetch_hider_ids}` receives the atomselect iterator from `game.tcl`).
- `registry.tcl` is sourced EXACTLY ONCE per process — re-sourcing WIPES `_records` (stated in `vmd/lib/mutation.tcl:22-24` and every smoke's source-order block).

## Error Handling

**Strategy:** `error` for caller bugs (surface them loudly); `catch` for environment/runtime failures (degrade gracefully); never a silent no-op on invalid input.

```tcl
# Caller bug -> clean error (vmd/lib/registry.tcl:60-66):
proc ::biochemeleon::registry::mark_found {idx} {
    variable _records
    if {![dict exists $_records $idx]} {
        error "hider $idx not registered"
    }
    ...
}

# Environment failure -> catch + restore (state restoration in the catch branch):
if {[catch {mol modstyle 0 $m2 $srcstyle} merr]} {
    pv_log "mirror modstyle FAILED: $merr (round-2 scene stays default)"
}

# Catch-guarded reads with a "?" placeholder (GUI driver convention, vmd/tests/rep_verify.tcl:95-99):
set a "?"
catch {set a $vmd_pick_atom}
```

**Smoke/test failure accumulation** — never abort mid-script; collect and report at the end:
```tcl
set failures [list]
proc _bail {tag msg} { upvar 1 failures f; lappend f "$tag:$msg" }
# ... per step: if {$x != $expected} { _bail stepname "exp=$expected got=$x" }
```
Assertion tag format: `<name>:exp=<expected> got=<actual>` (grep-able in logs; see the flake characterizations in `.planning/phases/17.2-.../17.2-11-SUMMARY.md`).

**Float comparisons** are eps-based, never `==` (`_feq` helper in `vmd/smoke/phase17_e2e_smoke.tcl:117-122`; `vec_close ... {eps 1e-12}` in `vmd/tests/test_splice.test:34-40`).

## Quality Gates (grep'd in smokes and gate runs — all must be ZERO)

```bash
# 1. Tcl 8.6-idiom gate (no 8.6 control flow in shipped code):
grep -rnE "\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/ vmd/gui/
# 2. Modeless gate:
grep -rnE "grab set" vmd/gui/
# 3. ssrecalc decision gate (never call mol ssrecalc in the generation flow — Pitfall C2):
grep -rn "mol ssrecalc" vmd/lib/ | grep -v "^\S*:\s*#"
```
(17.2-11 gate record: all three zero. See `.planning/phases/17.2-cartoon-newcartoon-generators/17.2-11-SUMMARY.md:122-125`.)

## Review / Verification Conventions

- **Byte-identity pins:** when extending a proc with an optional argument, the existing arities' behavior is pinned BYTE-IDENTICAL and verified by diff, not eyeball: "`write_combined_pdb` 3-arg behavior byte-identical" (`vmd/lib/mutation.tcl:458`; 17.2-04 PLAN:82 "Keep make_placeholder_hiders / make_bonded_hiders / _hider_record / tag_sentinels / fetch_hider_indices byte-identical"). Verify with a scoped `git diff` (e.g. 17.2-03's proc-signature gate: "`git diff` shows header comments + 2 constants + 1 docstring only; all 8 proc signatures byte-identical").
- **Diff-verified zero-change claims:** "the two red smokes NOT edited — `git diff a7f28a9..HEAD -- vmd/lib/` empty" (17.2-11). Any "no lib changes" claim in a summary is backed by an actual scoped diff command.
- **PASS=1 x3 consecutive** for any new/changed smoke before declaring green (run-to-run PRNG draws differ; three consecutive greens cover draw branches). See TESTING.md.
- **Plan-ID citations in code and docs** — every behavior claim traceable to the plan/research/GUI session that proved it.

## Commit Message Conventions

Conventional Commits with **phase-plan scope** (`.planning/config.json` has `commit_docs: true`):

```
feat(17.2-04): make_residue_hiders + residue PDB records + tag_sentinels_mixed (3-arg mutate dispatch)
test(17.2-01): add failing residue-splice geometry suite
fix(17.2-09): residue-tier supply-0 degrade instead of hard abort
docs(17.2-05): complete Cartoon tier smoke plan
docs(17.2-12): complete driver extension; GUI checkpoint pending human session
chore: track oc stats
merge: exec/17.2-08 (17.2-08 Tube tier smoke)
```

Rules:
- Scope = the plan ID (`17.2-04`), the phase (`16`, `15`), or a quick-fix ID (`quick-008`).
- TDD granularity: RED commit is `test(X.Y-NN): add failing ...` (suite written first, expected-fail noted in the test file — `vmd/tests/test_splice.test:12-13` "RED: splice.tcl does not exist yet — this source line is EXPECTED to fail"), GREEN is `feat(X.Y-NN): ...`, follow-up corrections are `fix(X.Y-NN): ...`.
- `docs(X.Y-NN): complete <thing> plan` closes each plan's doc commit.
- Merge commits after worktree-parallel waves: `merge: exec/NN-MM (<plan> <title>)` — merged in dependency order per the worktree protocol (root `AGENTS.md`).
- Planning docs ARE committed (`.planning/phases/...`).

---

# PART B — v1 PyMOL (Python) Conventions — SHIPPED (condensed)

Full details in the previous CONVENTIONS.md era are still valid; the essentials:

**Naming:** modules `snake_case` (`pymol/biochemeleon/setup_state.py`); functions `snake_case`; private `_underscore`; constants `UPPER_CASE` (`GAME_REPS`, `HIDER_STATUS_HIDDEN`); classes `PascalCase`; `HiderRecord` uses `__slots__`.

**Purity tiers (mirrors v2):** pure layer `pymol/biochemeleon/{setup_state,registry,generators,persistence}.py` (stdlib only, WSL-unit-testable); cmd-coupled `pymol/biochemeleon/{demos,backup,mutation,wizard}.py`; orchestrator `pymol/biochemeleon/game.py` (composition root); Qt+cmd GUI `pymol/biochemeleon/{__init__,gui_setup,gui_game}.py`.

**Domain sentinels (v1 vocabulary):** hider sentinel `segi='GAME'` + `b=-999`; selector `b < 0` never `b -999`; backup object `_bchm_backup` (underscore = hidden from public names); cleanup by `segi GAME` alone; registry keys on `cmd.identify` id, NEVER `index`.

**Error handling:** raise for caller bugs (`ValueError`/`KeyError`/`AttributeError`); return True/False for environment failures; never raise from reconcile/parse paths (degraded = playable); every destructive op preceded by `backup.snapshot()` (PyMOL Open Source has NO undo); restore is the TWO-step `cmd.delete` + `cmd.create`, never single-call.

**Qt:** imports ONLY via `from pymol.Qt import QtCore, QtGui, QtWidgets` (never `from PyQt5 import`); plugin entry `__init_plugin__(app=None)` with the `addmenuitemqt` import LOCAL to the function; module-level `dialog = None` singleton; main dialog MODELESS (`show()` + `raise_()` + `activateWindow()`, never `.exec_()`); modal `.exec_()` allowed on child dialogs only.

**Key v1 rules preserved:** `cmd.iterate`/`alter` with `space={'stored': ...}` never `None`; use `resv` not `int(resi)`; `cmd.sort` after `alter` of `segi`/`chain`; `cmd.fetch` with `async_=0`; `# noqa: F401` for intentional re-exports (`pymol/biochemeleon/persistence.py:28`); path guard `to_windows_path()` (`/mnt/c/...` → `C:\...`).

---

*Convention analysis: 2026-09-08*
