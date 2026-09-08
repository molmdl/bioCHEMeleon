# Testing Patterns

**Analysis Date:** 2026-09-08 (supersedes 2026-08-22 version — Phases 16, 17.1, 17.2 of the v2 VMD port landed since)

## Two Test Stacks

| | v1 PyMOL (SHIPPED) | v2 VMD (ACTIVE) |
|---|---|---|
| Framework | Python 3.6 `unittest` | `tcltest` under **headless VMD** |
| Location | `pymol/tests/` (5 files) | `vmd/tests/` (6 `.test` files) + `vmd/smoke/` (31 `.tcl` files) |
| Count | **346 tests, all green** (`Ran 346 tests in 0.078s OK`, verified 2026-09-08) | **205 suite tests** + 31 smokes (29 green, 2 known draw-dependent flakes) |
| GUI | human-verify checkpoints | human-verify checkpoints (Tk auto-driver) |

---

# PART A — v2 VMD Testing — ACTIVE

## Test Framework

**Runner: headless VMD — NOT tclsh.**

> **`tclsh` is NOT available in this WSL session** (verified 2026-09-08: `command not found`; only the `libtcl8.6` shared library is installed, no shell binary). The stale "tclsh is available in WSL" statement in `vmd/AGENTS.md` Commands section no longer holds. EVERY test and smoke runs under `vmd -dispdev text -e`. Suite files may still carry an "or standalone tclsh if installed" comment line (e.g. `vmd/tests/test_setup_state.test:4`) — ignore it; use the VMD runner.

- Tcl 8.5.6 inside VMD 1.9.3 (Windows build; WSL alias `vmd` → `vmd.exe`).
- `tcltest` ships inside VMD's Tcl (`package require tcltest` works under `-dispdev text`).
- No config file; conventions live in the file headers and `.planning/phases/` plan docs.

**Run commands (the canonical forms):**

```bash
# 0. ONE-TIME staging (repo root) — VMD needs a Windows-visible copy:
mkdir -p tmp/biochemeleon-vmd && cp -r vmd tmp/biochemeleon-vmd/

# 1. A single tcltest suite (headless VMD, from the staging root):
bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/test_setup_state.test -eofexit < /dev/null'

# 2. A smoke (usually with a timeout + grep of the essentials):
timeout 300 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase17_splice_smoke.tcl -eofexit < /dev/null' 2>&1 | grep -E "BCHM_SMOKE_RESULT|ERROR\)|bad switch"

# 3. tcl syntax check of a lib file (load with no error — pure files only):
#    no tclsh available — use a headless VMD one-liner or the suite run itself.
```

Rules baked into those commands:
- `bash -ic` loads the WSL alias; `< /dev/null` prevents the console hang; run from a `/mnt/c/...` cwd (Windows VMD cannot resolve WSL-external paths; the staging copy under `tmp/` IS Windows-visible).
- `-eofexit` makes VMD exit at stdin EOF.
- **Suite runs must be SEQUENTIAL** — mutation's shared `$env(TEMP)/biochemeleon_game.pdb` forbids parallel VMD instances (17.1-13 gate protocol note, `.planning/STATE.md:149`).

## Marker Parsing (NEVER trust exit codes)

VMD does NOT propagate tcl exit codes (`$?` is always 0) and `vmd -e` **catches top-level errors and CONTINUES** (possible false-PASS). Every suite/smoke therefore prints a machine-parseable marker line, and the harness scans the FULL log:

- Suites: `BCHM_TEST_RESULT Total=<n> Passed=<n> Failed=<n> Skipped=<n>` (`vmd/tests/test_setup_state.test:314-318`).
- Smokes: `BCHM_SMOKE_RESULT PASS=1 FAIL=none` or `PASS=0 FAIL=<comma-list>` (`vmd/smoke/phase13_smoke.tcl:51-53` through `phase17_e2e_smoke.tcl:810-815` — identical harness in all 31 files).

**False-PASS detection — scan for `bad switch` IN ADDITION to `ERROR)`:**
```bash
... 2>&1 | grep -E "BCHM_SMOKE_RESULT|ERROR\)|bad switch"
```
A clean run shows exactly one marker line, zero `ERROR)`, zero `bad switch`, and ends with `Exiting normally`. The `bad switch` scan exists because VMD/Tk error paths can print switch-usage errors without an `ERROR)` prefix. Every phase-17 smoke header documents this ("the regexp -- false-PASS lesson", e.g. `vmd/smoke/phase17_capstone_smoke.tcl:103-106`).

**`regexp --` corollary:** any log-scanning regexp whose pattern starts with `-` MUST use `regexp --` (`vmd/smoke/phase15_mutation_smoke.tcl:88`, `phase17_cpk_smoke.tcl:163-166`).

## Test File Organization

**Suites — `vmd/tests/test_<module>.test`** (one per PURE lib module; mol-coupled code is NEVER tcltest-tested):

| Suite | Tests | Covers |
|---|---|---|
| `vmd/tests/test_setup_state.test` | 47 | setup schema, validate_state clamps, randomize_per_rep/state, format_remaining |
| `vmd/tests/test_registry.test` | 37 | registry records, DI reconstruction, resid-block API (17.2-02) |
| `vmd/tests/test_generators.test` | 26 | sphere/bonded placement geometry |
| `vmd/tests/test_rep_tiers.test` | 49 | tier dispatch, kind/style_args, resolve_per_rep (widened 17.2-03) |
| `vmd/tests/test_game_logic.test` | 15 | state machine, countdown, drift-free timer, log model |
| `vmd/tests/test_splice.test` | 31 | residue-splice geometry (17.2-01) |
| **Total** | **205** | 6/6 Failed=0 at the 17.2-11 full-suite gate |

**Smokes — `vmd/smoke/phase<N>_<topic>_smoke.tcl`** (31 files, phase-prefixed: 1 phase13, 2 phase14, 4 phase15, 8 phase16, 16 phase17). Smokes verify the mol-coupled layer at the real VMD 1.9.3 runtime tier. Current full-suite gate: **29/31 PASS=1** (the 2 flakes below).

**GUI drivers — `vmd/tests/<topic>_verify.tcl`** (Tk-gated, no `.test` suffix, no marker — NOT part of the headless gate; their load-gate skip is exercised inside `phase16_pick_smoke`).

## Suite Structure (copy this skeleton)

From `vmd/tests/test_setup_state.test` (the pattern all 6 follow):

```tcl
# vmd/tests/test_<module>.test
# tcltest suite for the pure-layer <module> module.
# Run under headless VMD: bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/test_<module>.test -eofexit < /dev/null'

package require tcltest
namespace import ::tcltest::*
configure -verbose {start pass body error}

# Source the pure layer. Under `vmd -e`, [info script] is EMPTY (the probe
# verified this), so use [pwd] (VMD cwd = the staging root) to locate files.
source [file join [pwd] vmd lib <module>.tcl]

# --- optional pure test helpers (e.g. vec_close in test_splice.test) ---

test <behavior_name> {} -body {
    ::biochemeleon::<module>::<proc> <args>
} -result <exact>

# CRITICAL: read numTests BEFORE cleanupTests (cleanupTests resets the array).
# Print the machine-parseable marker — VMD does NOT propagate tcl exit codes.
set total $::tcltest::numTests(Total)
set passed $::tcltest::numTests(Passed)
set failed $::tcltest::numTests(Failed)
set skipped $::tcltest::numTests(Skipped)
puts "BCHM_TEST_RESULT Total=$total Passed=$passed Failed=$failed Skipped=$skipped"
cleanupTests
```

Patterns:
- Test names are behavior sentences in snake_case: `validate_state_clamps_hider_count_to_cap`, `block_survives_reconstruct`, `randomize_per_rep_seed_determinism`.
- `-result` asserts EXACT values (strings/lists/numbers) — `expr {...}` returning 1/0 for predicate tests.
- Section banners with phase IDs separate eras of a suite: `# Phase 14: validate_state (full impl) — ~13 cases` (`test_setup_state.test:68-71`), and note which tests a later phase inverted (`test_rep_tiers.test:51-53` "inverted by 17.2-03 seam widening").
- No explicit `exit` in suites — see suite_driver.tcl below.

## Smoke Structure (copy this harness)

From `vmd/smoke/phase17_e2e_smoke.tcl` (and all 31):

```tcl
set failures [list]
proc _bail {tag msg} { upvar 1 failures f; lappend f "$tag:$msg" }
proc _feq {a b} { ... }   ;# eps float compare

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set gs [list]

# Source lib files in dependency order ([pwd]-relative). registry sourced
# EXACTLY ONCE (re-sourcing would WIPE _records).
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry    [file join [pwd] vmd lib registry.tcl] \
    ... ] { source $path }

# ... steps: per-step catch + _bail "name:exp=X got=Y" ...

# ---- Report: marker + exit ----
puts "E2E_INFO <evidence echo>"
set nfail [llength $failures]
if {$nfail == 0} { puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none" } \
else { puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]" }
exit
```

Smoke conventions:
- **Explicit `exit` at the end** (suites lack it — that's why the gate needs the driver wrapper).
- **NO TEST HOOKS into lib internals for e2e smokes** — public-surface smokes drive only `game::start_game` / `game::on_pick` / `game::cleanup` + registry READ procs, and the runner GREPS the smoke for banned internal proc names (must find ZERO) — `vmd/smoke/phase17_e2e_smoke.tcl:80-86`.
- **Source order mirrors the entry** minus GUI files: setup_state, registry, generators, game_logic, rep_tiers, demos, backup, mutation, hiders, game.
- **Tachyon render technique** (17.1-08 template, 17.2-04 harness origin in `phase17_splice_smoke.tcl`): `axes location off` first; probe rep added LAST (highest index — deleting it never renumbers earlier reps) and deleted after each render; every OTHER rep emptied by `modselect` to a null selection (`mol showrep` is IGNORED in text mode — probe F6) and restored after; baseline-zero render (selection `index 999999`) proves the parser counts the real scene; primitive tokens (FCylinder/STri/TriStrip/Sphere) parsed with `\m` word-boundary regexes so "TriStrip" can never false-match "STri".
- **Single-frame collapse loader:** 1znf ships 2 models — a frame-0-pinned `writepdb` round-trip precedes rounds so every coordinate read/write is deterministic frame-0 geometry (the 17.2-04 fix `c54d77c`).

## The Full-Suite Gate Procedure (as executed 17.2-11)

```bash
# Fresh staging per gate run:
mkdir -p tmp/<gate-dir> && cp -r vmd tmp/<gate-dir>/

# 1. Suites — via the staging-only driver (suites have NO explicit exit):
#    tmp/<gate-dir>/suite_driver.tcl = "source the suite by name, then exit";
#    the suite name is sed-swapped per run.
#    WHY: under `vmd -e ... -eofexit < /dev/null` VMD's text console HANGS
#    past stdin EOF over the WSL->Windows pipe (first 17.2-11 suite run
#    COMPLETED 47/47 in-log, then hung — 17.2-11-SUMMARY Rule-3 deviation).
bash -ic 'cd tmp/<gate-dir> && vmd -dispdev text -e suite_driver.tcl -eofexit < /dev/null'
#    Per suite: parse BCHM_TEST_RESULT (Failed=0), zero ERROR)/bad switch, clean exit.

# 2. Smokes — all 31, one command each, per-file log:
timeout 300 bash -ic 'cd tmp/<gate-dir> && vmd -dispdev text -e vmd/smoke/<name>.tcl -eofexit < /dev/null' > <log> 2>&1
#    Per log: PASS=1 + zero ERROR) + zero "bad switch" + `Exiting normally`.

# 3. Code gates (on the repo, not staging):
grep -rnE "\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/ vmd/gui/   # -> 0
grep -rnE "grab set" vmd/gui/                                                                                # -> 0
grep -rn "mol ssrecalc" vmd/lib/ | grep -v "^\S*:\s*#"                                                       # -> 0
```

**PASS=1 x3 convention:** any new or changed smoke needs 3 consecutive PASS=1 runs before "green" is declared — the runs exercise different PRNG draws (`splice-smoke-run1..25.log` at repo root shows the 17.2-04 evidence chain). All gate runs SEQUENTIAL (shared `$env(TEMP)` combined-PDB). Reference gate record: `.planning/phases/17.2-cartoon-newcartoon-generators/17.2-11-SUMMARY.md` (44 logs, 205/205 suites, 29/31 smokes).

## GUI Human-Verify Checkpoints (the Tk split)

Tk loads ONLY in GUI mode (`-dispdev win`) — text mode cannot render widgets or fire real picks. GUI behavior is verified by a **Tk-guarded auto-driver** the human sources in a real VMD GUI.

**Canonical driver: `vmd/tests/rep_verify.tcl`** (extended by 17.2-12; modeled on `pick_verify.tcl` from 16-12, which itself stays UNREPAIRED as a Phase-16 historical artifact):
- **Tk guard if-wrap** at file top: `if {![info exists ::tk_version]} { vmdcon -warn ...; return }` — sourcing under `-dispdev text` no-ops with ONE warn line (an if-wrap is ONE command in both source and -e evaluation) — `rep_verify.tcl:62-64`.
- **Headless probe knob:** `set ::pv_probe 1` before sourcing defines all `pv_*` procs + resolves paths but SKIPS the GUI session (definition check without a display) — `rep_verify.tcl:631-635`.
- **`pv_*` observer/driver procs:** `pv_log` (timestamped append to `rep_verify_log.txt` + `vmdcon -info` echo), `pv_observe` (pick observer with the `{args}` signature — a positional signature makes VMD's own write FAIL and lose the pick; every value read is catch-guarded with a `?` placeholder), `pv_observe_fallback` (17.2-12 READ-ONLY resid + `hider_for_resid` verdict logging), `pv_state` (idempotent full state dump incl. per-tier rep read-backs), `pv_round2`/`pv_round3` (lock-scene + Cartoon rounds via `validate_state` → `apply_state` → `on_start` — always the REAL GUI path), `pv_cleanup`/`pv_cleanup_check`, `pv_report`, `pv_instructions`.
- **Paste-safety rule:** the human's whole job is pasting ONE-LINE commands (`source vmd/tests/rep_verify.tcl`, `pv_round2`, `pv_round3`, `pv_report`, `pv_cleanup`) and pressing `p` once per round (the LOCKED first-click quirk: pasted `mouse mode pick*` never arms delivery — only the hotkey dispatch path does). Everything else is auto-logged to `tmp/biochemeleon-vmd/rep_verify_log.txt` (open-append + flush per line).
- **Session hygiene:** re-sourcing resets `::pv_finds`/`::pv_rounds` counters but the log FILE is append-only (history survives); `::pv_gs` cleanup stash refreshes per round (round-3 unsets it — stale molids would fail `pv_cleanup` harmlessly, `rep_verify.tcl:404-408`).

## Mocking and Fakes

**Tcl has no mock framework** — the codebase uses four hand-rolled patterns:

**1. Dependency-injection fakes (pure-layer suites).** Pure procs accept command prefixes; tests inject `[list apply ...]` lambdas:
```tcl
# vmd/tests/test_registry.test:20 — fake sentinel iterator:
::biochemeleon::registry::reconstruct_from_sentinels [list apply {{} { return {5 10 15} }}]
# Bound-arg prefix (proves {*} expands multi-element command words), :69:
[list apply {{fake_molid} { return {7 8} }} "dummy_molid"]
```

**2. Clock injection (game_logic).** `clock seconds` cannot be stubbed, so timer procs take an OPTIONAL trailing `now` argument (empty = use `[clock seconds]`); tests inject fixed epochs (epoch 1000, now 1065 → elapsed 65). Production callers never pass it — `vmd/lib/game_logic.tcl` "TEST INJECTION" block.

**3. Explicit-seed PRNG discipline (Pitfall 4).** Tcl's PRNG is GLOBAL per-interpreter and state persists across tcltest cases. Every randomized call in tests passes an EXPLICIT seed, and the seeds are PROBED against this VMD binary's 8.5.6 PRNG so pinned expectations hold deterministically — `vmd/tests/test_rep_tiers.test:7-17` documents the probe table (seed 173 → sum exactly 10 as `{Tube 3 Cartoon 6 CPK 1}`; seed 42 → exactly 3; seeds 1..20 union covers all 10 GAME_REPS) and the re-probe rule ("re-probe on any binary OR DOMAIN change — 17.2-03 widened the randomize domain, which changes every draw"). Seed-determinism pairs (`seed 42` twice equal; `seed 1` vs `seed 2` different) appear in every randomized suite section.

**4. Recording callbacks (smokes).** Callback targets are GLOBALS written by injected 1-arg/0-arg/2-arg procs — `::LOG_LOG` and `::WINS` are lists (lappend recorders), `::REM_TICKS` is a scalar `{incr}` (the only zero-arg-safe recorder) — `vmd/smoke/phase17_e2e_smoke.tcl:133-139`. Assertions then check `status_of`, `remaining_by_rep`, log-line text, and win_cb firing counts.

**Fake domain fixtures (not "mocks" but crafted atom state):**
- Fake resid block: hider residues at resids 9001+k (disjoint from real demo resids ≤ ~500); registry's `hider_for_resid` zips resid → the block's CA index; 9005/9999 are the miss cases (`rep_verify.tcl:244-253`, `phase17_e2e_smoke.tcl:26-27`).
- Sentinel atoms: fake GAM atoms with CA-only `beta -999.0`, `segid GAME`, chain from the anchor (simple tiers hard-code chain G) — asserted via `atomselect "resname GAM and beta < 0"`.
- `rt_rec` helper (`vmd/tests/test_rep_tiers.test:32-33`): builds backup-shaped `{style sel color material}` 4-element records with a fixed color/material.

**What NOT to fake:** the real atomselect/`mol` layer in smokes — smokes exist precisely to exercise it at the real runtime tier. Pure-layer suites must NEVER need it (that's what DI is for).

## Draw-Adaptive Assertion Pattern (17.2-10/17.2-11 convention)

Generation is random; assertions must survive every draw branch:
- **Request-side pins assert UNCONDITIONALLY** (per_rep stashed verbatim GAME_REPS-ordered, P9 `hider_count == effective_total`, dict shape).
- **Layout pins assert OBSERVED-layout invariants** (sentinel count == registry count, resid zip `9001+i` == i-th CA in file order, 4-5 atom strides) — draw-independent at any generated count.
- **Strict exact pins assert ONLY when the draw generated in full** (idealized atom-count formula `orig + simple×1 + residue×5` asserted "whenever the draw generated in full with every anchor carrying CB").
- Rationale: a literal `{Cartoon 3}` pin flakes when `randomize_per_rep`'s subset contract can underspend (`c = randint(0, n)`) — documented as the 17.1-13 PLAN-DETAIL precedent and re-applied in 17.2-11 rounds D/E.

## Known Flaky / Pre-Existing Red Smokes (as of 2026-09-08)

Characterized in 17.2-11 (both SMOKE-side assertion defects, engine correct; zero lib changes; recorded for a gap-closure plan — do NOT treat as regressions):

1. **`vmd/smoke/phase17_dispatch_smoke.tcl` step-8** (known since 17.2-03/17.2-09): failing asserts `reg2_count:exp=5 got=0` / `rbr3_sum` / `idxs2_count` — the bare 2-arg randomize draw on 1k8p (DNA) can include residue tier `Tube` → `Warning) ... could not generate -- dropped` → 0-1 generated vs the pinned 5. Draw-dependent (3/3 red in the 17.2-11 session; 2/3 earlier). Fix recipe: drop-ungeneratable-tiers + effective-total recompute + the 17.2-10 draw-adaptive rewrite.
2. **`vmd/smoke/phase17_licorice_smoke.tcl`** (pre-existing P-pin defect): pins element VDW radius P 1.55 and P color tan `{0.5 0.5 0.31}`; VMD's actual table reads P radius 1.80 and renders `{0.5 0.5 0.2}`. Draw-dependent (2/3 red — only when a 1k8p backbone-P anchor draws; the smoke's own lines 164-168 anticipated the re-pin). Fix recipe: re-pin P radius 1.80 + the observed P color (or assert the color family).

Everything else is green: 29/31 smokes PASS=1, 205/205 suite tests, all three grep gates zero (17.2-11 gate, fresh staging).

## TDD Workflow (how tests get written)

- **RED → GREEN → REFACTOR at plan granularity:** `test(17.2-01): add failing residue-splice geometry suite` (the suite sources a not-yet-existing module and EXPECTS the failure — `vmd/tests/test_splice.test:12-13`) → `feat(17.2-01): pure residue-splice geometry module` → follow-up `fix(17.2-04)` commits.
- Suite count transitions are recorded in summaries (rep_tiers 32 → 49; gate 147 → 164 → 205).
- Parallel plans commit on isolated `exec/NN-MM` worktree branches; merged in dependency order (root `AGENTS.md` protocol).

---

# PART B — v1 PyMOL Testing — SHIPPED (condensed)

**Run commands (repo root):**
```bash
python3.6 -m unittest discover -s tests -v    # 346 tests, ~0.08s, all green (verified 2026-09-08)
python3.6 -m unittest tests.test_setup_state -v   # 125
python3.6 -m unittest tests.test_registry -v      # 102
python3.6 -m unittest tests.test_generators -v    # 47  (grew from 35)
python3.6 -m unittest tests.test_persistence -v   # 37
python3.6 -m unittest tests.test_game_controller -v  # 35
```

**The MagicMock stub pattern** (the load-bearing trick — `pymol/biochemeleon/__init__.py` imports `pymol.Qt` at module level, which fails in WSL):
```python
if 'pymol' not in sys.modules:
    sys.modules['pymol'] = MagicMock()
    sys.modules['pymol.Qt'] = MagicMock()
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from biochemeleon.<module> import <names>
```
- Present at the top of all 5 test files in `pymol/tests/`; `game.cmd.reset_mock()` in `setUp` isolates call-count assertions; set `return_value`s when code reads returns.
- v1 smokes (`pymol/smoke/phase<N>_smoke.py`) run via Windows PyMOL headless (`bash wsl2win_cp.sh` staging → `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\<file>.py`); GUI paths are human-verify checkpoints.
- Error testing: `assertRaises(ValueError)` for invalid rep, `KeyError` for duplicate keys, `ValueError` for bad sidecar magic/version.
- Determinism: pure generators take `seed`; tests assert same-seed equality / different-seed difference and probe distributions with `for seed in range(100)` loops.

---

## Where to Add New Tests (v2)

1. **New PURE lib module** → `vmd/tests/test_<module>.test` following the suite skeleton above (marker block at the end; `[pwd]`-relative source; explicit seeds for anything randomized). Add its count to the gate table in the phase summary.
2. **New mol-coupled behavior** → extend the relevant `vmd/smoke/phase<N>_<topic>_smoke.tcl` or add `phase<N+1>_<topic>_smoke.tcl` with the standard harness (`_bail` + marker + `exit` + full-log-scan comment); run PASS=1 x3 sequentially.
3. **New GUI surface** → extend `vmd/tests/rep_verify.tcl` (a new `pv_*` proc + an instructions line), then declare the human-verify checkpoint in the plan; a text-mode `-e` run of the driver (or `::pv_probe 1`) must show one warn line / probe line and zero errors.
4. **Never** run tcltest via tclsh (absent) and never trust `$?` — parse the marker, scan the full log for `ERROR)` + `bad switch`, require `Exiting normally`.

---

*Testing analysis: 2026-09-08*
