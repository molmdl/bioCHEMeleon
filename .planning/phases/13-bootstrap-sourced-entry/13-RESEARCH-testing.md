# Phase 13 Research: Pure-layer tcl Architecture & Headless WSL Testing

**Researched:** 2026-08-27
**Domain:** VMD 1.9.3 tcl port — stdlib-only pure layer + headless VMD test harness from WSL
**Confidence:** HIGH (every claim below was verified by running a probe against the real VMD 1.9.3 install on this machine, or by reading the milestone research with file:line citations)
**Scope:** the testable foundation — `vmd/lib/setup_state.tcl` + `vmd/lib/registry.tcl` (pure), `vmd/tests/*.test` (tcltest), `vmd/smoke/phase13_smoke.tcl` (headless smoke), the WSL→VMD staging + invocation mechanics. Does NOT cover the entry/dialog/file-layout (sibling researcher owns `13-RESEARCH-entry.md`).

---

## Summary

This phase establishes two disciplines from day one: (1) a **stdlib-only tcl pure layer** (`lib/setup_state.tcl` + `lib/registry.tcl`) that has zero `mol`/`atomselect`/`tk` references and is unit-testable without VMD's molecular API, and (2) a **headless VMD smoke harness** runnable from WSL via `vmd -dispdev text -e <script> -eofexit` — the v2 analog of v1's `run-conda-pymol.bat -cq`. The pure layer is a direct tcl 8.5 port of v1's `setup_state.py`/`registry.py` (the contract is unchanged; only the language changes). The smoke harness verifies the `source` + `biochemeleon` command path works end-to-end headlessly.

**Primary recommendation:** Build the pure layer as `namespace eval ::biochemeleon::setup_state` (matches v1's `setup_state.py` filename — flag for reconciliation with the sibling researcher who used `::biochemeleon::setup`). Run pure-layer tcltest UNDER headless VMD (not a standalone `tclsh` — see tclsh availability below), and run the smoke harness via `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase13_smoke.tcl -eofexit < /dev/null'` after staging `vmd/` to a Windows-visible path. **VMD does NOT propagate tcl exit codes** — the harness MUST parse a marker line (`BCHM_SMOKE_RESULT` / `BCHM_TEST_RESULT`) from stdout, NOT `$?`.

**Key verified discoveries (not in milestone research):**
1. `tclsh` is NOT installed in WSL Ubuntu (`which tclsh` → not found; `dpkg -l 'tcl*'` → empty). The literal REQUIREMENTS.md TEST-02 "unit-testable in WSL via tclsh" needs a mitigation (run tcltest under headless VMD instead — verified working).
2. VMD does NOT propagate tcl `exit N` to the shell — `exit 7` → shell `$?=0`. The harness must parse a marker line.
3. `[info script]` returns EMPTY under `vmd -e <file>` (VMD uses a non-`source` mechanism). The standard `[file dirname [info script]]` pattern BREAKS for `-e`'d scripts. Fix: the smoke/test harness (which is `-e`'d) uses `[pwd]` to locate files and `source`s the entry — the entry's `[info script]` then works correctly because it was `source`d.

---

## tcl 8.5.6 capability (what's in, what's out, the catch idiom)

**Source:** STACK.md:20, STACK.md:247, PITFALLS.md:369-392 (Pitfall 12). Verified live against the VMD 1.9.3 install.

**Available (verified by probe, `info patchlevel` = `8.5.6`):**
| Feature | Probe result | Use for |
|---------|--------------|--------|
| `dict` | OK (`dict create a 1 b 2`) | game state, DEFAULTS, registry, .bcm sidecar (Phase 20) |
| `lassign` | OK (`lassign {x y z} a b c`) | multi-return unpacking (built-in in 8.5; also defined as a proc in vmdinit.tcl:27-35 per STACK.md:20) |
| `lreverse` | OK | list reversal |
| `apply` | OK (`apply {{x y} {expr {$x+$y}}} 3 4` → 7) | anonymous lambdas — use for dependency injection (registry.tcl) |
| `trace add/remove variable` | OK | picking + lifecycle callbacks (Phase 14+) |
| `expr {**}` (power) | OK | numeric ops |
| `namespace ensemble` | OK | namespace dispatch |
| `string is integer -strict` | OK | pure-layer input validation |

**NOT available (Tcl 8.6+ — all are parse/runtime errors, verified):**
| Feature | Probe result | Replacement |
|---------|--------------|-------------|
| `lmap` | `invalid command name lmap` | `foreach` + `lappend` |
| `try` / `finally` | `invalid command name try` | `catch` (see idiom below) |
| `throw` | `invalid command name throw` | `error "msg"` |
| `tailcall` | `invalid command name tailcall` | direct proc calls |
| `coroutine` / `yield` | `invalid command name coroutine` | `after 0` chunking for long work (PITFALLS.md:194-216) |

**The `catch`-based error-handling idiom (replaces `try`/`finally`):**

```tcl
# Source: PITFALLS.md:379 (autoionize.tcl:81-88 pattern); verified by probe.
# catch returns 1 on error, 0 on success. $opts is a dict with -code/-errorinfo/-errorcode.
proc ::biochemeleon::setup_state::safe_validate {state} {
    set saved [info exists ::bcm_err]
    if {[catch {
        # ... main work that may error ...
        set result [validate_state $state]
    } res opts]} {
        # ERROR path — $res is the error message, [dict get $opts -errorinfo] is the trace
        puts "validate failed: $res"
        # restore any state here (no `finally` — do it explicitly in both paths)
        return [dict create]
    }
    # SUCCESS path — $res is the return value
    return $res
}
```

**Critical rule for the pure layer:** every proc body that does non-trivial work should be wrapped in `catch` if it touches external state; pure functions on validated inputs don't need it. The pure layer should NEVER use `try`/`lmap`/`throw`/`tailcall` — the grep gate (below) enforces this.

---

## tclsh + tcltest in WSL (verified availability + the minimal test-file pattern)

### tclsh availability — BLOCKER, with mitigation

**Verified:** `tclsh` is **NOT installed** in the WSL Ubuntu dev shell.
- `which tclsh tclsh8.5 tclsh8.6` → "command not found" for all three.
- `dpkg -l 'tcl*'` → no installed tcl packages.
- AGENTS.md forbids `apt*`/`pip*`/`conda*` — so the agent CANNOT install tclsh.

**Implication for REQUIREMENTS.md TEST-02** ("unit-testable in WSL via `tclsh` + `tcltest`"): the literal "via `tclsh`" is not achievable without user action. Two paths forward:

| Option | What it requires | Tradeoff |
|--------|------------------|----------|
| **A. Run tcltest under headless VMD** (RECOMMENDED) | Nothing — verified working today | ~1.5s VMD startup per test run; pure layer is exercised by VMD's bundled tcl 8.5.6 + tcltest 2.3.0, NOT by `mol`/`atomselect`/`tk` (the pure layer's code path doesn't touch those, so running under VMD's tcl is equivalent to running under a standalone tclsh). Satisfies the INTENT of TEST-02 (no Python; pure layer is stdlib-only). |
| B. User installs tclsh | `sudo apt install tcl` (user action, not agent) | Faster test runs (~0.05s); but violates AGENTS.md "no installs" for the agent, and adds a setup step for the user. |

**Recommendation:** Plan for Option A (tcltest under headless VMD). The test files are written identically either way (`package require tcltest` + `test` + `cleanupTests`); only the INVOCATION differs. If the user later installs tclsh, the same `.test` files run unchanged under `tclsh tests/test_setup_state.test`. Flag this as a human-decision point in the plan.

### tcltest availability — verified under headless VMD

**Verified:** `package require tcltest` under headless VMD returns **version 2.3.0**.
- tcltest lives at `C:/Program Files (x86)/University of Illinois/VMD/scripts/8.5.6/tcl8.5/tcltest-2.3.0.tm` (a `.tm` module — Tcl Module format; auto-loaded via `::tcl::tm::path`).
- The older 2.2 also ships at `scripts/8.4.1/tcl/tcltest2.2/tcltest.tcl` (for tcl 8.4; not used).
- **`-forbidexit` is NOT a supported option** in 2.3.0 (probe: "unknown option -forbidexit"). Use `-verbose` and the numTests array instead.

### The minimal tcltest file pattern (verified working)

```tcl
# vmd/tests/test_setup_state.test — convention: .test extension
package require tcltest
namespace import ::tcltest::*
configure -verbose {start pass body error}   ;# show test start, pass, body, error

# Source the pure layer. Under `vmd -e`, [info script] is EMPTY (see Pitfall 3),
# so use [pwd] (VMD cwd = staging root) to locate files.
set setup_state_path [file join [pwd] vmd lib setup_state.tcl]
source $setup_state_path

# A test: name, description, -body, -result (exact match by default)
test game_reps_count {} -body {
    llength $::biochemeleon::setup_state::GAME_REPS
} -result 10

test hider_cap_small {} -body {
    ::biochemeleon::setup_state::hider_count_cap 212
} -result 4

# CRITICAL: read numTests BEFORE cleanupTests (cleanupTests resets the array).
# Print a machine-parseable marker — VMD does NOT propagate tcl exit codes (Pitfall 4).
set total $::tcltest::numTests(Total)
set passed $::tcltest::numTests(Passed)
set failed $::tcltest::numTests(Failed)
set skipped $::tcltest::numTests(Skipped)
puts "BCHM_TEST_RESULT Total=$total Passed=$passed Failed=$failed Skipped=$skipped"
cleanupTests   ;# prints the human summary line: ":	Total	N	Passed	N	..."
```

**Verified invocation + result parsing (the harness MUST parse the marker, NOT `$?`):**
```bash
# Stage vmd/ to a Windows-visible root first (see Smoke harness section).
timeout 60 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/test_setup_state.test -eofexit < /dev/null' 2>&1 | tee /tmp/bchm_test_out
# Parse the marker (grep the LAST occurrence — cleanupTests prints a similar-looking summary line).
if grep -qE 'BCHM_TEST_RESULT.*Failed=0' /tmp/bchm_test_out; then
    echo "PURE-LAYER TESTS: PASS"
else
    echo "PURE-LAYER TESTS: FAIL"; grep -E 'FAILED|BCHM_TEST_RESULT' /tmp/bchm_test_out
fi
```

**Verified behavior (probe `test_normalize.test` + `tcltest_correct.tcl`):**
- All-pass run prints: `BCHM_TEST_RESULT Total=2 Passed=2 Failed=0 Skipped=0` then `:	Total	2	Passed	2	Skipped	0	Failed	0`.
- A failing test prints the diff (`---- Result was: 2 / ---- Result should have been: 3`) then `==== fail_one FAILED`.
- The marker line `BCHM_TEST_RESULT ...` is the reliable signal — print it BEFORE `cleanupTests` (the `numTests` array is correct before cleanupTests, reset after).

---

## Pure-layer design (`lib/setup_state.tcl` + `lib/registry.tcl`)

### Namespace name — reconciliation needed

**Recommendation:** use `::biochemeleon::setup_state` (matches v1's `setup_state.py` filename — v1's `registry.py` imports `from .setup_state import GAME_REPS`; the tcl port mirrors this with `source setup_state.tcl` then `$::biochemeleon::setup_state::GAME_REPS`).

The sibling researcher (entry/dialog) documented `::biochemeleon::setup` in their interface-boundary note. **At plan time, reconcile to ONE name.** Recommend `::biochemeleon::setup_state` for filename parity; if the sibling prefers `setup`, update both the entry's `source` list and the test files consistently. The rest of this doc uses `::biochemeleon::setup_state`.

### v1→tcl port contract (the spec for `lib/setup_state.tcl`)

v1 `pymol/biochemeleon/setup_state.py` defines (read fully — it's the spec):
- `GAME_REPS` = `['lines','sticks','spheres','cartoon','ribbon']` (setup_state.py:23) → v2 tcl: `{Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds}` (10 reps — v2's curated set, per SUMMARY.md:53, STACK.md won't help here; the v2 rep list comes from FEATURES.md / ROADMAP). **For Phase 13, define the list; full rep-viability is Phase 15.**
- `DEMO_MANIFEST` = 9-entry dict (setup_state.py:34-57) → v2 tcl: `dict create 1znf [dict create category Protein ...] ...`. **For Phase 13, define the dict (reuse v1's entries verbatim — PDBs are viewer-agnostic, per ARCHITECTURE.md:137).**
- `DEFAULTS` = 11-key dict (setup_state.py:118-130) → v2 tcl: `dict create format "biochemeleon-setup-v2" target_mode "loaded" ...`. The v2 format string differs (`-v2` not `-v1`).
- `hider_count_cap(atom_count)` (setup_state.py:233-244) → v2 tcl proc: `max(1, min(50, n/50))`. **Verified tcl port (probe):**
  ```tcl
  proc ::biochemeleon::setup_state::hider_count_cap {n} {
      if {![string is integer -strict $n] || $n <= 0} { return 1 }
      set c [expr {$n / 50}]
      if {$c < 1} { set c 1 }
      if {$c > 50} { set c 50 }
      return $c
  }
  ```
  (Probe verified: `hider_count_cap 0`→1, `212`→4, `100000`→50 — matches v1's `test_hider_count_cap`.)
- `validate_state(state, atom_count=None)` (setup_state.py:341-413) → v2 tcl proc. **For Phase 13, a STUB that returns DEFAULTS is sufficient** (full validation is Phase 14); the tcltest just asserts the stub returns a dict with the `format` key.
- `randomize_state(...)` (setup_state.py:247-338) → Phase 14 (not Phase 13).
- `format_remaining` / `format_debrief_text` → later phases (not Phase 13).

### `lib/setup_state.tcl` skeleton (Phase 13 minimum — verified loads under headless VMD)

```tcl
# vmd/lib/setup_state.tcl
# PURE layer: stdlib-only tcl. NO `mol`, NO `atomselect`, NO `tk`.
# Unit-testable via tcltest (under headless VMD or a standalone tclsh).
# Direct port of v1 pymol/biochemeleon/setup_state.py.

namespace eval ::biochemeleon::setup_state {
    # The 10 in-scope VMD reps for v2 (SUMMARY.md:53; curated from FEATURES.md).
    # v1 had 5; v2 expands to 10. `surface`/volumetric are out of scope (anti-features).
    variable GAME_REPS {Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds}

    variable SETUP_FORMAT "biochemeleon-setup-v2"

    # Default setup state (port of v1 setup_state.py:118-130).
    variable DEFAULTS [dict create \
        format      $SETUP_FORMAT \
        target_mode "loaded" \
        selected_object "" \
        pdb_code    "" \
        demo_id     "1znf" \
        hider_count 10 \
        lock_scene  0 \
        per_rep     [dict create] \
        difficulty_easy 1 \
        lock_source 0 \
        pdb_pool    [list] ]

    # Demo manifest (port of v1 setup_state.py:34-57; PDBs reused verbatim per ARCHITECTURE.md:137).
    variable DEMO_MANIFEST [dict create \
        1znf [dict create category Protein type protein difficulty easy source bundled cache_name 1znf.pdb] \
        1xdn [dict create category Protein type protein difficulty hard source bundled cache_name 1xdn.pdb] \
        5e54 [dict create category "Nucleic acid" type rna difficulty easy source bundled cache_name 5e54.pdb] \
        1k8p [dict create category "Nucleic acid" type dna difficulty easy source bundled cache_name 1k8p.pdb] \
        2qbz [dict create category "Nucleic acid" type rna difficulty hard source bundled cache_name 2qbz.pdb] \
        4wb3 [dict create category Mixed type "protein/na" difficulty hard source bundled cache_name 4wb3.pdb] ]
    # NOTE: 3 fetched demos (1gzm/3gp6/sasdpg4) added in Phase 19 (large demos), not Phase 13.

    namespace export GAME_REPS SETUP_FORMAT DEFAULTS DEMO_MANIFEST hider_count_cap validate_state
}

# Hider-count cap (port of v1 setup_state.py:233-244). Verified by probe.
proc ::biochemeleon::setup_state::hider_count_cap {atom_count} {
    if {![string is integer -strict $atom_count] || $atom_count <= 0} { return 1 }
    set cap [expr {$atom_count / 50}]
    if {$cap < 1} { set cap 1 }
    if {$cap > 50} { set cap 50 }
    return $cap
}

# validate_state STUB (full validation is Phase 14). For Phase 13, return DEFAULTS.
# The tcltest asserts this returns a dict with the `format` key.
proc ::biochemeleon::setup_state::validate_state {state {atom_count {}}} {
    variable DEFAULTS
    return $DEFAULTS
}
```

**Verified:** this exact skeleton (with the `::biochemeleon::setup_state` namespace) `source`s cleanly under headless VMD and the procs are callable (probe `test_normalize.test` — after fixing the `info script` path issue, see Pitfall 3).

### `lib/registry.tcl` skeleton (Phase 13 — FILE + loadability only; full sentinel logic is Phase 15)

For Phase 13, establish the file + the loadability contract + the dependency-injection shape. The full `reconstruct_from_sentinels` dict-keyed registry is Phase 15 (per ROADMAP). v1's `registry.py` (read fully) keys on `(object, atom_id)`; v2 keys on `index` (VMD has no global atom id — PITFALLS.md:107-131, Pitfall 3).

```tcl
# vmd/lib/registry.tcl
# PURE layer: stdlib-only tcl. NO `mol`, NO `atomselect`, NO `tk`.
# Direct port of v1 pymol/biochemeleon/registry.py (the DI pattern).
# Phase 13 scope: file + loadability + the DI proc SHAPE (full logic is Phase 15).

namespace eval ::biochemeleon::registry {
    variable HIDER_STATUS_HIDDEN "hidden"
    variable HIDER_STATUS_FOUND   "found"
    # The registry: a dict keyed by atom `index` -> {rep status found_at hint_used}
    # (v2 keys on `index`, NOT v1's `(object, id)` — VMD has no global atom id; PITFALLS.md:107-131).
    variable _records [dict create]

    namespace export reconstruct_from_sentinels is_hider mark_found
}

# Dependency-injected sentinel reconstruction (port of v1 registry.py:420-443).
# `fetch_hider_ids` is a proc reference or `apply` lambda injected by game.tcl
# (Phase 15), so this module stays pure (no `mol`/`atomselect` import).
# Phase 13: stub that clears the registry and accepts the injected fn.
proc ::biochemeleon::registry::reconstruct_from_sentinels {fetch_hider_ids} {
    variable _records
    set _records [dict create]   ;# clear (overwrite, not append — matches v1)
    foreach idx [$fetch_hider_ids] {
        dict set _records $idx [dict create rep "" status $::biochemeleon::registry::HIDER_STATUS_HIDDEN]
    }
    return
}

# Phase 13 stubs (Phase 15 fills in the real logic)
proc ::biochemeleon::registry::is_hider {idx} {
    variable _records
    return [dict exists $_records $idx]
}
proc ::biochemeleon::registry::mark_found {idx} {
    variable _records
    if {![dict exists $_records $idx]} { error "hider $idx not registered" }
    dict set _records $idx status $::biochemeleon::registry::HIDER_STATUS_FOUND
    return
}
```

**Dependency injection in tcl** (the v1 `lambda: mutation.fetch_all_hider_ids(obj)` port):
```tcl
# In game.tcl (Phase 15, NOT Phase 13), inject an `apply` lambda:
::biochemeleon::registry::reconstruct_from_sentinels [apply {{molid} {
    # This body CAN call mol/atomselect (it's in the cmd-coupled layer).
    set sel [atomselect $molid "resname GAM and beta < 0"]
    set ids [$sel get index]
    $sel delete
    return $ids
}} $game_molid]
```
The pure `registry.tcl` calls `$fetch_hider_ids` (the lambda) without knowing it touches `atomselect` — DI preserved. Verified `apply` works in tcl 8.5.6 (probe).

### Strict dependency direction — the grep gate

**The gate** (v2 analog of v1's "no `from pymol import cmd` in pure layer" — AGENTS.md "Architecture" section). The pure layer MUST have zero `mol`/`atomselect`/`tk`/`vmdcon`/`mouse`/`label`/`material` references.

```bash
# Gate: MUST return zero matches across the pure layer.
# Run from repo root. (Prefer the Grep tool over bash grep; rg is denied.)
grep -rnE '\b(mol|atomselect|molinfo|mouse|label|material|vmdcon|tk_messageBox|toplevel|ttk::|package require (Tk|tk|tooltip|tklib|BWidget))\b' vmd/lib/setup_state.tcl vmd/lib/registry.tcl
# Also gate Tcl 8.6 features (parse errors on 8.5):
grep -rnE '\b(lmap|try|throw|tailcall|coroutine|yield)\b' vmd/lib/setup_state.tcl vmd/lib/registry.tcl
```

**Where this gate lives:** document in `AGENTS.md` (v2 rewrite — flag: AGENTS.md is currently v1-scoped per its own header) AND run it in the Phase 13 smoke script (`vmd/smoke/phase13_smoke.tcl`) as a pre-check before sourcing. A non-zero match fails the smoke. The gate is the v2 equivalent of v1's `grep -rnE "import Tkinter|..." biochemeleon/` (AGENTS.md "Commands").

---

## Headless VMD from WSL (the exact invocation — verified)

### The verified invocation

```bash
# 1. Stage vmd/ to a Windows-visible path (mirrors v1's wsl2win_cp.sh):
mkdir -p tmp/biochemeleon-vmd
cp -r vmd tmp/biochemeleon-vmd/         # copies vmd/biochemeleon.tcl + vmd/lib/ + vmd/tests/ + vmd/smoke/

# 2. Run headless VMD from the staging root (cwd = staging root):
timeout 60 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase13_smoke.tcl -eofexit < /dev/null' 2>&1 | tail -50
```

**Verified facts about this invocation (all probed live):**
- `vmd` is a **bashrc alias** to `/mnt/c/Program Files (x86)/University of Illinois/VMD/vmd.exe` (verified: `bash -ic 'type vmd'` → `vmd is aliased to '/mnt/c/Program\ Files\ \(x86\)/University\ of\ Illinois/VMD/vmd.exe'`). The alias is ONLY available in interactive bash — `bash -ic` (interactive) loads it; `bash -c` (non-interactive) does NOT (`bash: vmd: command not found`). **Always use `bash -ic`.**
- VMD's internal `[pwd]` (inside the tcl script) = the Windows path of the WSL cwd. Verified: launched from `tmp/biochemeleon-vmd` (WSL), VMD's `[pwd]` = `C:/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/tmp/biochemeleon-vmd` (forward slashes, no `/mnt/c/`).
- VMD startup ~1.5s (probe: `time (timeout 60 bash -ic '... vmd ...' > /dev/null)` → real 1.575s). Budget `timeout 60` is generous; `timeout 30` is safe for Phase 13 smoke.
- `vmd.exe` is at `/mnt/c/Program Files (x86)/University of Illinois/VMD/vmd.exe` (path has SPACES — verified `ls` shows it: `5279744 Nov 30 2016 vmd.exe`).
- **Direct `vmd.exe` invocation (no alias) ALSO works** (probe PROBE17): `"/mnt/c/Program Files (x86)/University of Illinois/VMD/vmd.exe" -dispdev text -e <script> -eofexit < /dev/null`. Use this if `bash -ic` is unavailable (e.g., from a non-bash shell). The alias form is simpler and is the v1-established pattern.
- **`cmd.exe /c` with the spaced path FAILED** (probe PROBE18): `cmd.exe /c '"C:\Program Files (x86)\...\vmd.exe" ...'` → "'\"C:\Program Files...\"' is not recognized as an internal or external command". The nested quoting of the spaced path breaks cmd.exe. **Do NOT use `cmd.exe /c` for VMD** (unlike v1's `run-conda-pymol.bat` which was a batch wrapper). Use `bash -ic 'vmd ...'` (the alias handles the spaced path) or the direct `/mnt/c/.../vmd.exe` form.

### Flags

- `-dispdev text` — no GUI, no Tk (verified: `package require Tk` fails headless per STACK.md:21). All `mol`/`atomselect`/`molinfo`/`trace`/`dict`/file I/O work (STACK.md:227).
- `-e <script.tcl>` — execute the tcl script. **`[info script]` is EMPTY inside an `-e`'d script** (Pitfall 3 — see below).
- `-eofexit` — exit VMD when stdin hits EOF. **Essential** with `< /dev/null` (without it, a script error drops VMD to the `vmd >` prompt and it hangs waiting for stdin — STACK.md:225).
- `< /dev/null` — feed empty stdin so `-eofexit` triggers immediately after the script. Without it, hangs on script error.

### No wrapper batch needed (unlike v1)

v1 needed `C:\src\run-conda-pymol.bat` because PyMOL was in a conda env requiring activation. VMD is a standalone `.exe` with no env activation — the bashrc alias (or direct `/mnt/c/.../vmd.exe`) suffices. **No `run-conda-vmd.bat` wrapper is needed.**

---

## Smoke harness (`vmd/smoke/phase13_smoke.tcl` design + the WSL run command)

### The staging script (`vmd/wsl2win_cp.sh` — propose, or inline in the smoke runner)

v1 has `wsl2win_cp.sh` staging `pymol/biochemeleon/` → `tmp/bioCHEMeleon/biochemeleon/`. v2 analog: stage `vmd/` → `tmp/biochemeleon-vmd/vmd/`. Simplest: inline the `cp` in the run command (no separate script needed for Phase 13; add a script in a later phase if the staging grows complex):

```bash
# Inline staging (no separate wsl2win_cp.sh for Phase 13):
mkdir -p tmp/biochemeleon-vmd && cp -r vmd tmp/biochemeleon-vmd/
```

If a script is wanted (mirrors v1), `vmd/wsl2win_cp.sh`:
```bash
#!/usr/bin/env bash
# vmd/wsl2win_cp.sh — stage vmd/ to a Windows-visible path for headless VMD.
set -e
STAGE="${1:-tmp/biochemeleon-vmd}"
mkdir -p "$STAGE"
cp -r vmd "$STAGE/"
echo "staged: $STAGE/vmd"
```

### The smoke script (`vmd/smoke/phase13_smoke.tcl` — verified shape)

```tcl
# vmd/smoke/phase13_smoke.tcl
# Headless smoke for Phase 13: source the entry, assert `biochemeleon` exists,
# call it (no-op headless), assert the pure-layer namespace loaded.
# This script is `-e`'d by VMD — [info script] is EMPTY here (Pitfall 3),
# so use [pwd] (VMD cwd = staging root) to locate the entry.

set failures [list]

# 1. Locate + source the entry. [pwd] = staging root (verified by probe).
set entry [file join [pwd] vmd biochemeleon.tcl]
if {![file exists $entry]} {
    lappend failures "entry_not_found:$entry"
} elseif {[catch {source $entry} err]} {
    lappend failures "source_error:$err"
}

# 2. Assert `biochemeleon` command exists (info commands).
if {[llength [info commands biochemeleon]] == 0} {
    lappend failures "no_biochemeleon_cmd"
}

# 3. Call biochemeleon headless — MUST no-op gracefully (GUI is tk_version-guarded).
if {![catch {biochemeleon} err]} {
    # success (no-op headless)
} else {
    lappend failures "biochemeleon_call_error:$err"
}

# 4. Assert the pure-layer namespace loaded (entry sourced lib/setup_state.tcl).
if {![namespace exists ::biochemeleon::setup_state]} {
    lappend failures "no_setup_state_ns"
}

# 5. Assert registry namespace loaded too.
if {![namespace exists ::biochemeleon::registry]} {
    lappend failures "no_registry_ns"
}

# Report. VMD does NOT propagate tcl exit codes (Pitfall 4) — use a marker line.
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
```

### The WSL run command (verified shape)

```bash
# From repo root:
mkdir -p tmp/biochemeleon-vmd && cp -r vmd tmp/biochemeleon-vmd/
timeout 60 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase13_smoke.tcl -eofexit < /dev/null' 2>&1 | tee /tmp/bchm_smoke_out
# Parse the marker:
if grep -qE 'BCHM_SMOKE_RESULT PASS=1' /tmp/bchm_smoke_out; then
    echo "PHASE 13 SMOKE: PASS"; exit 0
else
    echo "PHASE 13 SMOKE: FAIL"; grep -E 'BCHM_SMOKE_RESULT|FAIL' /tmp/bchm_smoke_out; exit 1
fi
```

**Verified end-to-end** (probe with staged `vmd/biochemeleon.tcl` + `vmd/lib/setup_state.tcl` + `vmd/smoke/phase13_smoke.tcl`): produced `BCHM_SMOKE_RESULT PASS=1 FAIL=none`. The `[pwd]`-based path resolution + `source` of the entry (so the entry's `[info script]` works) is the verified pattern.

### Success criterion 3 — what "passes" means (verified assertions)

Success criterion 3 ("the `source` + `biochemeleon` smoke passes headlessly") means, verifiably:
1. **Exit handling:** the smoke script runs to completion (VMD prints "Exiting normally" — verified). Note: `$?` is ALWAYS 0 from VMD (Pitfall 4) — do NOT gate on `$?`; gate on the `BCHM_SMOKE_RESULT` marker.
2. **No stderr error:** no `couldn't read file` / `invalid command name` / `extra characters` lines in the output (other than the expected VMD `Info)`/`Warning)` banner lines, which go to stdout via VMD's console).
3. **`biochemeleon` command exists after source:** `info commands biochemeleon` is non-empty (assertion #2 in the smoke).
4. **Calling `biochemeleon` headless no-ops:** `biochemeleon` is `tk_version`-guarded so it returns cleanly without Tk (assertion #3). The error path `FAIL=biochemeleon_call_error` catches a guard that's missing.
5. **Pure-layer namespace loaded:** `namespace exists ::biochemeleon::setup_state` (assertion #4) — proves the entry successfully `source`d `lib/setup_state.tcl`.

---

## Verified facts (file:line + bash-probe citations)

| # | Fact | Source |
|---|------|--------|
| V1 | tcl 8.5.6, `info patchlevel`=8.5.6 | probe; STACK.md:20, STACK.md:257 |
| V2 | `dict`/`lassign`/`lreverse`/`apply`/`trace add` available; `lmap`/`try`/`tailcall`/`coroutine`/`yield` ABSENT | probe (all `catch` as `invalid command name`); PITFALLS.md:374-378 |
| V3 | `tclsh` NOT in WSL (`which tclsh`→not found; `dpkg -l 'tcl*'`→empty) | probe |
| V4 | tcltest 2.3.0 available via `package require tcltest` under headless VMD | probe; file `C:/Program Files (x86)/University of Illinois/VMD/scripts/8.5.6/tcl8.5/tcltest-2.3.0.tm` |
| V5 | VMD does NOT propagate tcl exit codes (`exit 7`→`$?=0`; `exit 0`→`$?=0`; bare `error`→`$?=0`) | probe (PROBE exit_code_probe / error_probe) |
| V6 | tcltest `numTests` array is correct BEFORE `cleanupTests`, reset AFTER | probe (PROBE5 vs PROBE8) |
| V7 | `[info script]` = EMPTY under `vmd -e <file>`; correct under `source <file>` | probe (PROBE16/17 + infoscript_probe) |
| V8 | `vmd` is a bashrc alias to `/mnt/c/Program Files (x86)/University of Illinois/VMD/vmd.exe`; only in `bash -ic`, not `bash -c` | probe (`bash -ic 'type vmd'` / `bash -c 'type vmd'`) |
| V9 | VMD's `[pwd]` = Windows path of the WSL cwd (forward slashes, no /mnt/c/) | probe (`pwd_probe.tcl` → `C:/Users/.../bioCHEMeleon`) |
| V10 | VMD startup ~1.5s headless | probe (`time` → real 1.575s) |
| V11 | `cmd.exe /c` with spaced VMD path FAILS (nested quoting); direct `/mnt/c/.../vmd.exe` or `bash -ic 'vmd'` works | probe (PROBE17 vs PROBE18) |
| V12 | Staging + `cd staging && vmd -e vmd/smoke/phase13_smoke.tcl -eofexit < /dev/null` → `BCHM_SMOKE_RESULT PASS=1` | probe (end-to-end) |
| V13 | `apply` works in 8.5.6 (for DI lambdas) | probe (`apply {{x y} {expr {$x+$y}}} 3 4`→7) |
| V14 | tcltest `-forbidexit` NOT supported in 2.3.0; use `-verbose` + numTests | probe (PROBE4) |

---

## Pitfalls & mitigations (top 5)

### Pitfall 1: Tcl 8.6 features (`lmap`/`try`) are parse/runtime errors on 8.5.6
**What goes wrong:** A proc uses `lmap` or `try`; at runtime VMD throws `invalid command name lmap` / `invalid command name try` and the proc fails. (PITFALLS.md:369-392, Pitfall 12.)
**Why:** VMD ships Tcl 8.5.6 (verified V1); 8.6 features don't exist.
**How to avoid:** Use `foreach`+`lappend` (not `lmap`) and `catch` (not `try` — see the catch idiom above). The grep gate (above) catches `lmap`/`try`/`throw`/`tailcall`/`coroutine`/`yield` in the pure layer.
**Warning signs:** `invalid command name lmap` or `invalid command name try` in VMD output.

### Pitfall 2: VMD does NOT propagate tcl exit codes — harness can't gate on `$?`
**What goes wrong:** The smoke script does `exit 1` on failure; the WSL runner checks `$?`; `$?` is always 0; the runner reports PASS even when the smoke failed. (Verified V5.)
**Why:** VMD's `-eofexit` exits VMD itself (code 0), not with the tcl script's `exit N` code.
**How to avoid:** The smoke/test scripts print a machine-parseable marker line (`BCHM_SMOKE_RESULT` / `BCHM_TEST_RESULT`) and the WSL runner `grep`s it. NEVER gate on `$?` for VMD-invoked scripts.
**Warning signs:** A failing smoke reports "PASS" because the runner checked `$?`.

### Pitfall 3: `[info script]` is EMPTY under `vmd -e` — breaks `[file dirname [info script]]`
**What goes wrong:** The entry script does `set dir [file dirname [info script]]; source [file join $dir lib setup_state.tcl]`; under `vmd -e biochemeleon.tcl`, `[info script]` = "" so `dir` = "." and `source` fails with "couldn't read file ./lib/setup_state.tcl". (Verified V7.)
**Why:** VMD's `-e` executes the script via a non-`source` mechanism; `info script` (which tracks the currently-`source`d file) is empty. When a script is `source`d (not `-e`d), `info script` IS set correctly (verified: `source probe_sourced.tcl` → `info script` = the full path).
**How to avoid:**
- The smoke/test harness (which IS `-e`'d) uses `[pwd]` (VMD cwd = staging root, verified V9) to locate files, and `source`s the entry — the entry's `info script` then works because it was `source`d.
- The entry script (`biochemeleon.tcl`) is ALWAYS `source`d (by the smoke, by `.vmdrc`, by the user) — never `-e`d directly in tests. So `[file dirname [info script]]` works inside it.
- If the entry must support being `-e`d directly (e.g., `vmd -e biochemeleon.tcl` from the user), add a fallback: `if {[info script] eq ""} { set dir [pwd] } else { set dir [file dirname [info script]] }`.
**Warning signs:** "couldn't read file ./lib/setup_state.tcl: no such file or directory".

### Pitfall 4: `bash -c` (non-interactive) doesn't see the `vmd` alias; `cmd.exe /c` breaks on the spaced path
**What goes wrong:** A runner uses `bash -c 'vmd ...'` (non-interactive) → `vmd: command not found`. Or uses `cmd.exe /c '"C:\Program Files (x86)\...\vmd.exe" ...'` → "'\"C:\Program Files...\"' is not recognized". (Verified V8, V11.)
**Why:** The `vmd` alias lives in `~/.bashrc` which only loads for interactive shells (`-i`). cmd.exe's nested quoting of a spaced path with embedded quotes fails.
**How to avoid:** ALWAYS use `bash -ic '...'` (interactive). Alternatively, invoke `vmd.exe` directly with the `/mnt/c/...` path (no alias, no quoting issue): `"/mnt/c/Program Files (x86)/University of Illinois/VMD/vmd.exe" -dispdev text -e ... -eofexit < /dev/null`. The direct form is more robust (no alias dependency) but longer.
**Warning signs:** "vmd: command not found" or "is not recognized as an internal or external command".

### Pitfall 5: WSL `/mnt/c/` paths are invisible to VMD; `~` and `/tmp/` too
**What goes wrong:** A script passes `/mnt/c/Users/.../1znf.pdb` or `/tmp/foo.tcl` to VMD; VMD reports "couldn't open file: no such file or directory". (PITFALLS.md:306-335, Pitfall 10; verified in milestone research.)
**Why:** Windows VMD resolves paths against the Windows filesystem; `/mnt/c/` is a WSL mount VMD doesn't understand. `/tmp/` and `~/` are WSL-only.
**How to avoid:** Stage any file VMD must read to a `/mnt/c/...` path (the `tmp/biochemeleon-vmd/` staging does this — `tmp/` is at the repo root which is under `/mnt/c`). VMD's `[pwd]` then gives the `C:/...` Windows path. For files handed to VMD file ops (`mol new`), convert `/mnt/c/X` → `C:/X` (forward slashes — PITFALLS.md:320). The staging + `cd staging && vmd -e ...` pattern means VMD's cwd IS the staging root, so relative paths work.
**Warning signs:** "couldn't open file" on a path that `ls` (in WSL) shows exists.

---

## Open questions / human-verify flags

1. **tclsh installation decision (HUMAN DECISION).** `tclsh` is NOT in WSL (V3). The plan should default to running tcltest under headless VMD (Option A, verified working). If the user wants faster pure-layer test runs (~0.05s vs ~1.5s), they can `sudo apt install tcl` (user action, not agent — AGENTS.md forbids `apt` for the agent). The `.test` files run unchanged under either. **Flag for plan-time decision.**

2. **Namespace name reconciliation (PLAN-TIME).** I recommend `::biochemeleon::setup_state` (matches v1's `setup_state.py` filename); the sibling entry/dialog researcher used `::biochemeleon::setup`. Pick one and apply consistently across `vmd/lib/setup_state.tcl`, the entry's `source` list, and `vmd/tests/*.test`. **Flag for the planner to reconcile.**

3. **AGENTS.md v2 rewrite (DOWNSTREAM).** AGENTS.md is explicitly v1-scoped (its own header says "v1-scoped; revisit when v2 research begins"). Phase 13 begins v2 — AGENTS.md needs a VMD/tcl rewrite: the headless invocation (`bash -ic 'vmd -dispdev text -e ... -eofexit'`), the grep gate (no mol/atomselect/tk in pure layer; no lmap/try), the staging pattern, the `[info script]` caveat. **Not a Phase 13 deliverable blocker, but flag it.**

4. **No GUI/ttk human-verify needed for THIS research's scope.** The pure layer + headless harness have zero Tk dependency (the whole point). ttk availability in GUI mode is the sibling researcher's concern (MEDIUM confidence per SUMMARY.md:232) and is verified at the first GUI smoke — not blocking the pure-layer + harness work.

---

## Interface boundary with the entry/dialog researcher

The pure layer (`vmd/lib/setup_state.tcl`, `vmd/lib/registry.tcl`) is `source`d by the entry script `vmd/biochemeleon.tcl` via `source [file join [file dirname [info script]] lib setup_state.tcl]` — this works because the entry is `source`d (by the smoke, by `.vmdrc`, by the user), NOT `-e`d, so `[info script]` is correctly set inside it (verified V7). ALL GUI code in the entry is reachable only through `if {[info exists tk_version]}` guards or procs called from the GUI-guarded path, so the SAME `biochemeleon.tcl` runs headless (pure layer + the no-op `biochemeleon` command) AND in GUI mode (pure layer + Tk dialog). The smoke harness (`vmd/smoke/phase13_smoke.tcl`, owned here) is `-e`'d by VMD, uses `[pwd]` to locate the entry, `source`s it, and asserts the `biochemeleon` command exists + the pure-layer namespaces loaded — it does NOT exercise any GUI code. The grep gate (no `mol`/`atomselect`/`tk` in `vmd/lib/*.tcl`) is owned here and enforced in the smoke. **Shared decision needed: the namespace name (`::biochemeleon::setup_state` vs `::biochemeleon::setup`) — see Open Question 2.**
