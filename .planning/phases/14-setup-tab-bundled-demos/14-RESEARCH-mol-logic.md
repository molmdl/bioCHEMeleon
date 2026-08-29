# Phase 14 Research: mol-bridge (`demos.tcl`) + pure-layer setup-state logic

**Researched:** 2026-08-29
**Domain:** VMD 1.9.3 tcl — mol/molinfo command surface + tcl 8.5 pure-layer port of v1 `setup_state.py` validate/randomize + quick-008 SETUP-06 distribution
**Confidence:** HIGH (every mol/molinfo claim verified by a headless probe against the real VMD 1.9.3 install on this machine; every pure-tcl algorithm verified by a probe run under headless VMD's tcl 8.5.6)
**Scope:** the mol/logic aspect of Phase 14 — `vmd/lib/demos.tcl` (mol bridge) + the `validate_state`/`randomize_state`/`randomize_per_rep` additions to `vmd/lib/setup_state.tcl` (pure layer) + the Save/Load setup format + the tcltest cases. The GUI researcher owns ttk widgets/form layout/Save-Load dialogs.

---

## Summary

Phase 14 ports two things from v1: (1) the **mol bridge** (`pymol/biochemeleon/demos.py` → `vmd/lib/demos.tcl`) — molecule enumeration, demo loading, active-rep detection, PDB fetch — using VMD's `mol new`/`molinfo`/`mol addrep`/`mol delrep`/`mol modstyle` command surface instead of PyMOL's `cmd.*`; and (2) the **pure-layer setup-state logic** (`setup_state.py`'s `validate_state` full impl + `randomize_state` + the quick-008 `randomize_per_rep` distribution) into `vmd/lib/setup_state.tcl`, kept stdlib-only (no `mol`, no `tk`) so it stays tcltest-unit-testable under headless VMD.

**Primary recommendation:** Build `demos.tcl` as `namespace eval ::biochemeleon::demos` with four verified procs — `to_vmd_path`, `list_loaded_molecules`, `load_demo`, `get_active_reps` (plus a deferred/stub `fetch_pdb`). Resolve bundled-demo paths via `[file dirname [info script]]` (script-relative → always a `C:/` path inside VMD, no `/mnt/c` conversion needed). Port `validate_state` as a **deterministic clamp** (NO randomness — port v1 exactly, including the insertion-order per_rep-sum drop-overflow rule), `randomize_state` as the Randomize button (uses the global `expr {srand($seed)}`/`expr {rand()}` PRNG, calls `randomize_per_rep` for the per_rep field), and `randomize_per_rep` as the **quick-008 pure helper** (random non-empty subset + non-empty guarantee — the "baked in" fix). Use the **key-value line format** for Save/Load with a **DEFAULTS-key-order rebuild on load** (verified to give order-stable `dict eq` round-trip).

**Key verified discoveries (not in milestone research):**
1. **`molinfo $mol get name` is READ-ONLY** (`molinfo set name` errors: "cannot find molinfo attribute 'name'") AND `mol new` accepts NO name option (the `name` keyword is silently ignored; positional name errors). A molecule's name is ALWAYS the loaded filename basename (e.g. `1k8p.pdb`). The dropdown must display `"<name> (<molid>)"`; you cannot rename.
2. **The `rep` field from `molinfo $mol get "{rep $i} ..."` returns the STYLE NAME** (e.g. `Lines`, `VDW`, `NewCartoon`), and ALL 10 GAME_REPS style names match EXACTLY (`set=<X> got=<X> match=1` for every one). Single-field `molinfo $mol get {rep 0}` FAILS — you MUST use the combined-braces form `"{rep $i} {selection $i} {color $i} {material $i}"` + `foreach {r s c m} ... { break }` (the clonerep/viewmaster pattern).
3. **`mol repname $mol $i` is STABLE across `mol delrep` renumbering** — deleting rep 0 shifts indices but the surviving reps KEEP their original `rep0`/`rep1`/... names. Track game reps by `repname`, never by index (confirms AGENTS.md).
4. **`expr {srand($seed)}` IS available in tcl 8.5.6** and IS deterministic (same seed → identical `rand()` sequence, verified). This is the tcl-8.5 port of Python's `random.Random(seed)`. CAVEAT: it's a **GLOBAL** per-interpreter PRNG (no per-instance `Random`) — tests must seed immediately before a sequence and never interleave other `rand()` calls.
5. **`mol new <url>` and `mol load pdb <code>` BOTH FAIL** for RCSB fetch ("Unable to load file 'https://...'", "Could not read file 1CRN"). VMD 1.9.3 has the `http` tcl package (v2.7.2) but NOT `tls` (so HTTPS is impossible; RCSB is https-only). Fetch-from-PDB must be deferred to Phase 21 (large demos) or implemented as a best-effort `http` download (http URL only) — flag as an open question.
6. **tcl `dict eq` is ORDER-SENSITIVE** (it compares string representations). A round-trip that reorders keys fails `eq` even with identical content. Fix: rebuild the loaded dict in **DEFAULTS key order** (verified: `loaded eq test_state: 1`).
7. The **per_rep-sum clamp DROPS overflow entries** (does NOT truncate them to fit) — v1 semantics, verified. `{VDW 5 Cartoon 5 Lines 5}` with hider_count=8 → `{VDW 5}` (sum=5), because Cartoon 5 > remaining 3 → dropped entirely.

---

## Standard Stack — verified mol/molinfo command table

Every command below was probed live against VMD 1.9.3 headless (`vmd -dispdev text -e probe_mol.tcl`). "Verified output" is the actual probed response.

### Core mol / molinfo commands

| Command | Exact syntax | Verified output / behavior | Use in v2 |
|---------|--------------|----------------------------|-----------|
| Load a PDB | `mol new <path> type pdb` | returns the new **molid** (int, starts at 0, monotonic) | `load_demo` |
| List molids | `molinfo list` | space-separated list of molids: `0 1` (empty if none) | `list_loaded_molecules` |
| Count mols | `molinfo num` | integer count | dropdown enable/disable |
| Top molid | `molinfo top` | the top molid (set by last `mol new`) | "selected_object" default |
| Molecule name | `molinfo $mol get name` | **filename basename** e.g. `1k8p.pdb` (READ-ONLY — `molinfo set name` errors) | dropdown display |
| Atom count | `molinfo $mol get numatoms` | integer (1k8p→555, 1znf→424, …) | `hider_count_cap` input |
| File path | `molinfo $mol get filename` | full `C:/...` path the mol was loaded from | (informational) |
| Rep count | `molinfo $mol get numreps` | integer; a freshly loaded mol has **1** default rep (`Lines/all/Name/Opaque`) | `get_active_reps` loop bound |
| Per-rep data | `molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` | flat list `{style sel color mat}` — `style` is the STYLE NAME (`Lines`,`VDW`,…) | `get_active_reps` (the ONLY working form — see Pitfall 3) |
| Stable rep name | `mol repname $mol $i` | `rep0`,`rep1`,… — **STABLE across `mol delrep`** renumbering | track game reps by name (Phase 15+) |
| Add rep | `mol addrep $mol` | adds a rep using current defaults (set first via `mol representation`/`mol color`/`mol selection`/`mol material`); index = `numreps-1` after add | rep setup (Phase 15+) |
| Set rep style | `mol modstyle $i $mol <StyleName>` | changes rep $i's style; accepts all 10 GAME_REPS names | rep setup |
| Delete rep | `mol delrep $i $mol` | deletes rep at index $i; **surviving reps renumber** but keep `repname` | cleanup (delete index 0 in a loop) |
| Delete molecule | `mol delete $mol` | removes the molecule; molids are **monotonic, NOT reused** | cleanup/reload (Phase 15) |

### Verified atom counts + hider_count_cap per bundled demo (probed)

| demo_id | numatoms | cap = `max(1,min(50, n/50))` | filename (mol name) |
|---------|----------|----------------------------|--------------------|
| 1znf | 424 | **8** | 1znf.pdb |
| 1xdn | 2597 | 50 (clamped) | 1xdn.pdb |
| 5e54 | 2844 | 50 (clamped) | 5e54.pdb |
| 1k8p | 555 | **11** | 1k8p.pdb |
| 2qbz | 3408 | 50 (clamped) | 2qbz.pdb |
| 4wb3 | 3779 | 50 (clamped) | 4wb3.pdb |

(All 6 demos load successfully via `mol new <staged-path>/vmd/data/demos/<id>.pdb type pdb` — verified.)

### GAME_REPS style-name match (probed — ALL 10 match exactly)

```
set=<Lines>        got=<Lines>        match=1
set=<VDW>          got=<VDW>          match=1
set=<Licorice>     got=<Licorice>     match=1
set=<CPK>          got=<CPK>          match=1
set=<Cartoon>      got=<Cartoon>      match=1
set=<NewCartoon>   got=<NewCartoon>   match=1
set=<Trace>        got=<Trace>        match=1
set=<Tube>         got=<Tube>         match=1
set=<Points>       got=<Points>       match=1
set=<DynamicBonds> got=<DynamicBonds> match=1
```
This means `get_active_reps` can match the `rep` field against `$GAME_REPS` with `lsearch -exact` — no name translation needed.

### tcl 8.5 PRNG (probed)

| Command | Behavior |
|---------|----------|
| `expr {rand()}` | returns float in `[0, 1)` (0 inclusive, 1 exclusive) |
| `expr {srand($seed)}` | seeds the **global** PRNG and returns the first value; `$seed` is an integer |
| Determinism | `srand(123)` then 5× `rand()` == `srand(123)` then 5× `rand()` (verified `eq`=1) |
| `int(rand() * N)` | integer in `[0, N-1]` → use `1 + int(rand() * $cap)` for `[1, cap]` |

**There is NO per-instance PRNG** (no `random.Random()` analog). The global state is shared across all procs in the interpreter. See Pitfall 4.

### Tcl packages available in VMD 1.9.3 (probed)

| Package | Available | Implication |
|---------|-----------|------------|
| `tcltest` | YES (v2.3.0, Phase 13) | pure-layer unit tests under headless VMD |
| `http` | YES (v2.7.2) | HTTP download possible (but http only) |
| `tls` | **NO** ("can't find package tls") | **HTTPS impossible** — RCSB (https-only) fetch needs Phase 21 work |

---

## Architecture Patterns

### Recommended file layout (strict layering — from `vmd/AGENTS.md`)

```
vmd/lib/setup_state.tcl   PURE: stdlib tcl. NO mol, NO tk. tcltest-unit-testable.
   ↑ (sources setup_state)
vmd/lib/demos.tcl          MOL BRIDGE: uses mol/molinfo/atomselect. sources setup_state.
   ↑ (sources setup_state AND demos)
vmd/gui/setup_tab.tcl      Tk + mol: the Setup tab widgets.
```

`demos.tcl` is the mol bridge (mirrors v1's `demos.py`). It `source`s `setup_state.tcl` for `GAME_REPS`/`DEMO_MANIFEST`, and wraps every `mol`/`molinfo` call in `catch` (tcl 8.5 has no `try`). The GUI sources BOTH `setup_state.tcl` (for `DEFAULTS`/`validate_state`/`randomize_state`) AND `demos.tcl` (for `load_demo`/`get_active_reps`/`list_loaded_molecules`).

### Pattern 1: script-relative path resolution (no `/mnt/c` conversion for bundled demos)
**What:** `load_demo` resolves the demo PDB via `[file dirname [info script]]` (the `demos.tcl` location), so the path is ALWAYS a `C:/` Windows path inside VMD — no `/mnt/c` → `C:/` conversion needed for bundled demos.
**When to use:** ALWAYS for bundled-demo paths. The entry `source`s `demos.tcl` via `source [file join $_dir lib demos.tcl]`, so `[info script]` inside `demos.tcl` is correctly set (verified — `source` sets `info script`; only `vmd -e` leaves it empty, per Phase 13 Pitfall 3).
**Verified:** probe confirmed `[info script]` inside a `source`'d helper returns the full `C:/...` path.
**Example:**
```tcl
# Inside demos.tcl, sourced by the entry:
proc ::biochemeleon::demos::load_demo {demo_id} {
    variable DEMO_MANIFEST
    if {![dict exists $DEMO_MANIFEST $demo_id]} { return -code error "unknown demo: $demo_id" }
    set cache_name [dict get $DEMO_MANIFEST $demo_id cache_name]
    # demos.tcl is at <root>/vmd/lib/demos.tcl; data at <root>/vmd/data/demos/
    set path [file normalize [file join [file dirname [info script]] .. data demos $cache_name]]
    set path [to_vmd_path $path]  ;# defensive guard (no-op for C:/ paths)
    if {![file exists $path]} { return -code error "demo file not found: $path" }
    set molid [mol new $path type pdb]
    return $molid
}
```

### Pattern 2: rep query via the combined-braces molinfo form
**What:** The ONLY working per-rep query is the combined-braces form returning a flat list, unpacked with `foreach {r s c m} ... { break }`.
**When to use:** `get_active_reps` (lock-scene detection) and any rep inspection (Phase 15 backup/restore).
**Verified:** single-field `molinfo $mol get {rep 0}` FAILS ("cannot find molinfo attribute '0'"); the combined form works (clonerep.tcl:103, viewmaster.tcl:252).
**Example:**
```tcl
proc ::biochemeleon::demos::get_active_reps {mol} {
    variable GAME_REPS
    set active [list]
    set n [molinfo $mol get numreps]
    for {set i 0} {$i < $n} {incr i} {
        foreach {style sel col mat} [molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        if {[lsearch -exact $GAME_REPS $style] >= 0} {
            lappend active $style
        }
    }
    return $active
}
```

### Pattern 3: mol bridge error handling with `catch` (no `try` in tcl 8.5)
**What:** Every `mol`/`molinfo` call that can fail (file not found, bad molid) is wrapped in `catch` and returns a sentinel (`-code error` or empty) rather than raising.
**When to use:** All mol-bridge procs. The GUI catches and shows a dialog.
**Example:** see `load_demo` above (returns `-code error` with a message; the GUI wraps the call in `catch`).

### Anti-Patterns to Avoid
- **Single-field `molinfo $mol get {rep $i}`** — fails. Use the combined-braces form.
- **Tracking reps by index** — `mol delrep` renumbers. Track by `mol repname` (Phase 15+).
- **Renaming a molecule via `molinfo set name`** — read-only. The name is the filename. Display it as-is.
- **`mol new <name> type pdb` positional name** — errors ("Illegal molecule specification"). `mol new` takes NO name.
- **Baking randomness into `validate_state`** — makes the deterministic clamp non-deterministic and untestable. Keep randomness in `randomize_state`/`randomize_per_rep` only.
- **Truncating per_rep counts to fit hider_count** — v1 DROPS overflow entries (insertion order), it does NOT truncate. `{VDW 5 Cartoon 5}` with hc=8 → `{VDW 5}`, NOT `{VDW 5 Cartoon 3}`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-rep style query | loop with `molinfo get {rep $i}` | `molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` + `foreach {r s c m}` | single-field form FAILS (verified); the combined form is the only working one (clonerep/viewmaster) |
| Random subset of reps | manual index juggling | Fisher-Yates partial shuffle (`_sample`) | `rng.sample` has no tcl 8.5 builtin; partial Fisher-Yates is the verified O(n) port |
| Setup-file format | JSON (no `json` package) / sourced-tcl-dict (level/quoting traps) | key-value line format + DEFAULTS-order rebuild | verified round-trip `dict eq`=1; no parser/level issues; `dict`-serialization via `sourced script` failed with "bad level" in probe |
| Deterministic PRNG | custom LCG | `expr {srand($seed)}` + `expr {rand()}` | built-in, deterministic (verified); only caveat is global state |
| Molecule enumeration | `molinfo list` + manual name lookup | `molinfo list` + `molinfo $m get name` | the verified pair; name is the filename basename |

**Key insight:** VMD's `molinfo` rep query is the load-bearing primitive for lock-scene detection AND for Phase 15 backup/restore. Get it right once (the combined-braces form) and reuse it everywhere.

---

## Common Pitfalls

### Pitfall 1: `molinfo get name` is read-only; `mol new` takes no name
**What goes wrong:** You try `molinfo $mol set name "custom"` → "cannot find molinfo attribute 'name'". Or `mol new <path> name "custom" type pdb` → the `name` is silently ignored (name stays the filename). Or `mol new <path> <name> type pdb` → "Illegal molecule specification 'pdb'".
**Why:** VMD derives the molecule name from the loaded filename and exposes it read-only. There is no rename API.
**How to avoid:** The dropdown displays `"[molinfo $m get name] ($m)"` (e.g. `1k8p.pdb (0)`). Accept that loading the same demo twice yields two same-named entries with different molids. If a cleaner display is wanted, strip the `.pdb` extension in the GUI display string (cosmetic only — do NOT try to rename the molecule).
**Warning signs:** "cannot find molinfo attribute 'name'" or "Illegal molecule specification".

### Pitfall 2: `mol delrep` renumbers — track by `repname`, not index
**What goes wrong:** You delete rep 1, then query rep 2 — but rep 2 became rep 1, so you query the wrong rep / miss one.
**Why:** `mol delrep $i $mol` shifts all higher-index reps down by 1. BUT `mol repname $mol $i` returns the ORIGINAL name (stable). Verified: after deleting rep0+rep0, `idx0 style=<Cartoon> repname=<rep2>` (the rep formerly at index 2).
**How to avoid:** Track game reps by `repname` (stable), never by index. To delete all reps, loop `mol delrep 0 $mol` (always delete index 0 — clonerep.tcl:95 pattern). To delete a specific rep, look up its current index by scanning `repname` matches, then delete that index.
**Warning signs:** Reps "disappear" or duplicate after a delete.

### Pitfall 3: single-field `molinfo get {rep $i}` fails — use the combined-braces form
**What goes wrong:** `molinfo $mol get {rep 0}` → "cannot find molinfo attribute '0'" / "incorrect format for 'get'".
**Why:** `molinfo get` parses the braced argument as a list of attribute specs; `{rep 0}` is split into `rep` and `0` as two separate (invalid) attributes. The combined form `"{rep $i} {selection $i} ..."` is ONE argument where each `{...}` is a sub-spec.
**How to avoid:** ALWAYS use `molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` and unpack with `foreach {r s c m} ... { break }`. This is the verified clonerep/viewmaster pattern.
**Warning signs:** "cannot find molinfo attribute" on a rep query.

### Pitfall 4: tcl PRNG is GLOBAL — seed ordering and interleaving matter
**What goes wrong:** `randomize_state` seeds `srand(42)`, calls `randomize_per_rep` (no seed, continues sequence), but a `rand()` call elsewhere (another proc, a test setup) between the seed and the sequence corrupts determinism.
**Why:** tcl 8.5 has ONE global PRNG per interpreter (no `random.Random()` per-instance). `srand($seed)` reseeds the global state; every `rand()` advances it.
**How to avoid:** (1) `randomize_state` seeds ONCE at the top (if seed given) and calls `randomize_per_rep` with NO seed (so it continues the sequence — do NOT let `randomize_per_rep` reseed when called from `randomize_state`). (2) `randomize_per_rep` seeds itself ONLY when a seed is explicitly passed (standalone/test use). (3) In tcltests, every randomness test passes an explicit seed and does NOT interleave other `rand()` calls. (4) The global state persists across tcltest cases in a run — every randomize test MUST pass its own seed (never rely on "random" output).
**Warning signs:** a determinism test flaps (passes alone, fails when run with other tests).

### Pitfall 5: tcl `dict eq` is order-sensitive
**What goes wrong:** Save/Load round-trip returns `dict eq` = 0 even though every key/value is identical.
**Why:** `dict eq` compares the STRING representation, and tcl dicts preserve insertion order. If the loaded dict inserts keys in a different order than the original (e.g. `per_rep` set last after the parse loop), the string reps differ.
**How to avoid:** On load, rebuild the dict in **DEFAULTS key order** (the canonical order): parse into a temp dict, then `foreach k $DEFAULTS_KEYS { if {[dict exists $tmp $k]} { dict set loaded $k [dict get $tmp $k] } }`. Verified: `loaded eq test_state: 1`.
**Warning signs:** round-trip `dict eq` = 0 with identical content.

### Pitfall 6: VMD has no RCSB fetch; HTTPS is impossible (no `tls`)
**What goes wrong:** `mol new https://files.rcsb.org/download/1CRN.pdb type pdb` → "Unable to load file 'https://...'". `mol load pdb 1CRN` → "Could not read file 1CRN". A `package require http` + `::http::geturl https://...` → fails (no tls).
**Why:** VMD 1.9.3 ships `http` (v2.7.2) but NOT `tls`, so HTTPS is unavailable. RCSB serves PDBs over HTTPS only. There is no built-in RCSB fetch command.
**How to avoid:** For Phase 14, the bundled-demo path is the primary SETUP-01 path (verified working). Treat "fetch from PDB" as a best-effort/deferred feature: implement `fetch_pdb` as a stub that returns `-code error "fetch not implemented in Phase 14; bundled demos only"` OR a best-effort `http` download to a temp file then `mol new` (http URL only, will fail for RCSB https). The robust fetch (with network/tls handling) is Phase 21 (large demos). Flag the GUI to show the PDB-fetch option but handle the error gracefully.
**Warning signs:** "Unable to load file 'https://...'" or "Could not read file <code>".

### Pitfall 7: the per_rep-sum clamp DROPS overflow, it does NOT truncate
**What goes wrong:** You "clamp" `{VDW 5 Cartoon 5}` with hider_count=8 to `{VDW 5 Cartoon 3}` (truncating Cartoon to fit) — that is NOT v1's behavior.
**Why:** v1 (`validate_state` lines 400-407) iterates in insertion order, KEEPS entries that fit the remaining budget, and DROPS entries that would overflow. It never truncates a count.
**How to avoid:** Match v1 exactly: `if {$c <= $remaining} { dict set clamped $rep $c; incr remaining -$c }` (else skip). Verified: `{VDW 5 Cartoon 5 Lines 5}` hc=8 → `{VDW 5}` (sum=5).
**Warning signs:** a per_rep sum that exactly equals hider_count after a "clamp" (suspicious — v1 often leaves sum < hider_count).

---

## Code Examples — verified skeletons

### `vmd/lib/demos.tcl` (mol bridge — verified proc shapes)

Every proc below was probed headlessly and produced the expected output (see `probe_demos.tcl`). Wrap the `source` of `setup_state.tcl` for the constants.

```tcl
# vmd/lib/demos.tcl
# MOL BRIDGE: sources setup_state (for GAME_REPS/DEMO_MANIFEST); uses mol/molinfo.
# Mirrors pymol/biochemeleon/demos.py. The GUI sources BOTH setup_state AND this file.
# Tcl 8.5: catch (not try), foreach+lappend (not lmap).

# Source the pure layer for constants (setup_state.tcl is in the same lib/ dir).
source [file join [file dirname [info script]] setup_state.tcl]

namespace eval ::biochemeleon::demos {
    # Import the shared constants from the pure layer (fully-qualified access also works).
    # GAME_REPS / DEMO_MANIFEST live in ::biochemeleon::setup_state.
    namespace export to_vmd_path list_loaded_molecules load_demo get_active_reps fetch_pdb
}

# WSL -> VMD path guard: /mnt/c/... -> C:/... (forward slashes). No-op for other paths.
# Source: AGENTS.md "WSL→VMD path guard". Bundled-demo paths are script-relative (C:/) so
# this is a defensive guard for any externally-supplied /mnt/c paths (e.g. a user PDB).
proc ::biochemeleon::demos::to_vmd_path {path} {
    if {[regexp {^/mnt/([a-zA-Z])/(.*)$} $path -> drive rest]} {
        return "[string toupper $drive]:/$rest"
    }
    return $path
}

# SETUP-01: enumerate loaded molecules for the dropdown.
# Returns a list of display strings "<name> (<molid>)" for every loaded molecule.
proc ::biochemeleon::demos::list_loaded_molecules {} {
    set out [list]
    foreach m [molinfo list] {
        lappend out "[molinfo $m get name] ($m)"
    }
    return $out
}

# SETUP-01 / DEMO-01: load a bundled demo PDB by manifest id. Returns the new molid.
# Errors (via -code error) on unknown id / missing file / mol-new failure; the GUI
# catches and shows a dialog. Paths are script-relative (C:/) so no /mnt/c conversion.
proc ::biochemeleon::demos::load_demo {demo_id} {
    variable ::biochemeleon::setup_state::DEMO_MANIFEST
    if {![dict exists $DEMO_MANIFEST $demo_id]} {
        return -code error "unknown demo: $demo_id"
    }
    set meta [dict get $DEMO_MANIFEST $demo_id]
    # Phase 14 manifest has ONLY bundled demos. If a later phase adds fetched demos,
    # branch on [dict get $meta source] here (v1 demos.py:183). For now: bundled only.
    if {[dict get $meta source] ne "bundled"} {
        return -code error "non-bundled demo not supported in Phase 14: $demo_id"
    }
    set cache_name [dict get $meta cache_name]
    # demos.tcl is at <root>/vmd/lib/demos.tcl; data at <root>/vmd/data/demos/.
    set path [file normalize [file join [file dirname [info script]] .. data demos $cache_name]]
    set path [::biochemeleon::demos::to_vmd_path $path]
    if {![file exists $path]} { return -code error "demo file not found: $path" }
    if {[catch {mol new $path type pdb} molid]} {
        return -code error "mol new failed: $molid"
    }
    return $molid
}

# SETUP-03: detect the active reps on a molecule (lock-scene). Returns the subset
# of GAME_REPS whose style matches a currently-displayed rep. Uses the verified
# combined-braces molinfo form. Skips reps whose style is not in GAME_REPS (surface/etc).
proc ::biochemeleon::demos::get_active_reps {mol} {
    variable ::biochemeleon::setup_state::GAME_REPS
    set active [list]
    if {[catch {molinfo $mol get numreps} n]} { return $active }  ;# bad molid -> empty
    for {set i 0} {$i < $n} {incr i} {
        foreach {style sel col mat} [molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        if {[lsearch -exact $GAME_REPS $style] >= 0} {
            lappend active $style
        }
    }
    return $active
}

# SETUP-01 fetch: STUB for Phase 14. VMD 1.9.3 has http but NO tls -> HTTPS (RCSB) fails.
# The robust fetch (network + tls) is Phase 21 (large demos). The GUI shows the option
# but catches the error. Signature mirrors v1 demos.fetch_pdb (code -> obj_name).
proc ::biochemeleon::demos::fetch_pdb {code} {
    return -code error "fetch_pdb not implemented in Phase 14 (VMD 1.9.3 lacks tls for HTTPS); use a bundled demo"
}
```

**Verified:** `load_demo` loaded all 6 demos (molids 0-5, correct atom counts); `get_active_reps` returned `<Lines>` for a fresh mol and `Lines VDW Cartoon Licorice` after adding reps, then `VDW Cartoon Licorice` after `delrep 0`; `list_loaded_molecules` returned the 6 display strings; `to_vmd_path` converted `/mnt/c/Users/foo` → `C:/Users/foo` and passed through `C:/already` and `relative/path`. (The "Error reading PDB file ... Temp" lines when adding Cartoon reps are the Stride secondary-structure warning — harmless; the rep is still created with the style set.)

### `vmd/lib/setup_state.tcl` additions (pure layer — verified algorithms)

Append these to the existing `setup_state.tcl` (which already has `GAME_REPS`, `DEFAULTS`, `DEMO_MANIFEST`, `hider_count_cap`, and the `validate_state` STUB). The STUB is REPLACED by the full impl below. `randomize_state` and `randomize_per_rep` are NEW. All verified by `probe_pure.tcl`.

```tcl
# ---- internal helpers (pure; not exported) ----

# Python bool() semantics for setup-state coercion: 0/""/false -> 0, else 1.
proc ::biochemeleon::setup_state::_to_bool {v} {
    if {$v eq "" || $v eq "0" || $v eq "false" || $v eq "False"} { return 0 }
    return 1
}

# randint [lo, hi] inclusive (both ends). Uses the global PRNG.
proc ::biochemeleon::setup_state::_randint {lo hi} {
    return [expr {$lo + int(rand() * ($hi - $lo + 1))}]
}

# random element of a list.
proc ::biochemeleon::setup_state::_choice {lst} {
    return [lindex $lst [expr {int(rand() * [llength $lst])}]]
}

# n distinct elements of lst (without replacement) — Fisher-Yates partial shuffle.
# Port of Python's random.sample. n in [1, len] (caller guarantees >=1).
proc ::biochemeleon::setup_state::_sample {lst n} {
    set copy $lst
    set len [llength $copy]
    if {$n > $len} { set n $len }
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {$i + int(rand() * ($len - $i))}]
        set tmp [lindex $copy $i]
        lset copy $i [lindex $copy $j]
        lset copy $j $tmp
    }
    return [lrange $copy 0 [expr {$n - 1}]]
}

# Validate a PDB code: exactly 4 lowercase alnum chars, or "".
proc ::biochemeleon::setup_state::_validate_pdb_code {code} {
    if {$code eq ""} { return "" }
    set c [string tolower [string trim $code]]
    if {[string length $c] == 4 && [regexp {^[a-z0-9]+$} $c]} { return $c }
    return ""
}

# Validate a PDB pool: list of 4-char lowercase alnum codes, deduped, bound to 100.
# v2 DIFFERENCE from v1: an empty/invalid pool returns [list] (empty), NOT the v1
# 33-entry PDB_POOL (v2 has no PDB_POOL constant; fetch is Phase 21). The empty pool
# causes randomize_state's fetch mode to re-roll to demo (the empty-pool guard).
proc ::biochemeleon::setup_state::_validate_pdb_pool {pool} {
    if {![info exists pool] || $pool eq ""} { return [list] }
    set seen [list]
    set seen_set [dict create]
    foreach code $pool {
        set c [_validate_pdb_code $code]
        if {$c ne "" && ![dict exists $seen_set $c]} {
            lappend seen $c
            dict set seen_set $c 1
            if {[llength $seen] >= 100} { break }
        }
    }
    return $seen
}

# ---- validate_state (FULL port of v1 setup_state.py:341-413) ----
# DETERMINISTIC clamp: fills missing keys from DEFAULTS, clamps hider_count to
# [1, cap], drops invalid per_rep keys/counts, clamps per_rep sum to <= hider_count
# (insertion-order keep + drop overflow), validates enums, returns a NEW dict.
# NO randomness (randomness is in randomize_state/randomize_per_rep).
proc ::biochemeleon::setup_state::validate_state {state {atom_count {}}} {
    variable DEFAULTS
    variable DEMO_MANIFEST
    variable GAME_REPS
    # Start from a fresh copy of DEFAULTS (canonical key order).
    set result $DEFAULTS
    # Non-dict input -> DEFAULTS.
    if {![info exists state] || $state eq "" || [catch {dict size $state}]} { return $result }

    # target_mode
    if {[dict exists $state target_mode]} {
        set mode [dict get $state target_mode]
        if {$mode eq "loaded" || $mode eq "fetch" || $mode eq "demo"} {
            dict set result target_mode $mode
        }
    }
    # selected_object / pdb_code
    if {[dict exists $state selected_object]} { dict set result selected_object [dict get $state selected_object] }
    if {[dict exists $state pdb_code]} {
        dict set result pdb_code [string tolower [string trim [dict get $state pdb_code]]]
    }
    # demo_id
    if {[dict exists $state demo_id]} {
        set did [dict get $state demo_id]
        if {[dict exists $DEMO_MANIFEST $did]} { dict set result demo_id $did }
    }
    # hider_count (clamped to [1, cap]; cap = hider_count_cap(atom_count) or 50)
    if {[string is integer -strict $atom_count] && $atom_count > 0} {
        set cap [hider_count_cap $atom_count]
    } else {
        set cap 50
    }
    if {[dict exists $state hider_count] && [string is integer -strict [dict get $state hider_count]]} {
        set hc [dict get $state hider_count]
    } else {
        set hc [dict get $DEFAULTS hider_count]
    }
    if {$hc < 1} { set hc 1 }
    if {$hc > $cap} { set hc $cap }
    dict set result hider_count $hc

    # lock_scene / difficulty_easy (bool coercion)
    if {[dict exists $state lock_scene]} { dict set result lock_scene [_to_bool [dict get $state lock_scene]] }
    if {[dict exists $state difficulty_easy]} { dict set result difficulty_easy [_to_bool [dict get $state difficulty_easy]] }

    # per_rep: drop invalid keys (not in GAME_REPS), drop zero/negative counts.
    set clean [dict create]
    if {[dict exists $state per_rep] && ![catch {dict size [dict get $state per_rep]}]} {
        dict for {rep cnt} [dict get $state per_rep] {
            if {[lsearch -exact $GAME_REPS $rep] < 0} { continue }
            if {![string is integer -strict $cnt] || $cnt <= 0} { continue }
            dict set clean $rep $cnt
        }
    }
    # per_rep-sum clamp: insertion-order keep + drop overflow (runs AFTER hider_count clamp).
    set clamped [dict create]
    set remaining $hc
    dict for {rep cnt} $clean {
        if {$cnt <= $remaining} {
            dict set clamped $rep $cnt
            incr remaining -$cnt
        }
    }
    dict set result per_rep $clamped

    # New fields (Gap 3 + Gap 4)
    if {[dict exists $state lock_source]} { dict set result lock_source [_to_bool [dict get $state lock_source]] }
    if {[dict exists $state pdb_pool]} {
        dict set result pdb_pool [_validate_pdb_pool [dict get $state pdb_pool]]
    }
    return $result
}

# ---- randomize_per_rep (quick-008 pure helper) ----
# Distribute hider_count across a random NON-EMPTY subset of game_reps.
# Guarantees at least one rep with count > 0 when hider_count > 0 (the quick-008
# fix that replaces the old all-spheres fallback). game_reps is a PARAMETER
# (dependency-injected) so this stays pure. seed -> deterministic (for tests).
proc ::biochemeleon::setup_state::randomize_per_rep {hider_count game_reps {seed {}}} {
    if {$seed ne ""} { expr {srand($seed)} }
    if {$hider_count <= 0 || [llength $game_reps] == 0} { return [dict create] }
    set n [_randint 1 [llength $game_reps]]  ;# NON-EMPTY subset (1..len) -- the quick-008 core
    set reps [_sample $game_reps $n]
    set per_rep [dict create]
    set remaining $hider_count
    foreach rep $reps {
        if {$remaining <= 0} { break }
        set c [_randint 0 $remaining]
        if {$c > 0} {
            dict set per_rep $rep $c
            incr remaining -$c
        }
    }
    # Guarantee non-empty: if every draw came back 0 (possible when hider_count==1),
    # put the full count on a random rep (matches v1 quick-008 line 150-151).
    if {[dict size $per_rep] == 0} {
        dict set per_rep [_choice $game_reps] $hider_count
    }
    return $per_rep
}

# ---- randomize_state (Randomize button; port of v1 setup_state.py:247-338) ----
# Returns a complete random state dict (all DEFAULTS keys). If seed given, deterministic.
# Uses the GLOBAL PRNG: seeds once at top (if seed), calls randomize_per_rep with NO
# seed (continues the sequence). lock_source preserves target; else random mode.
proc ::biochemeleon::setup_state::randomize_state {{seed {}} {atom_count {}} {lock_source 0} {locked_state {}} {pdb_pool {}}} {
    variable DEFAULTS
    variable DEMO_MANIFEST
    variable GAME_REPS
    variable SETUP_FORMAT
    if {$seed ne ""} { expr {srand($seed) }
    # cap + hider_count
    if {[string is integer -strict $atom_count] && $atom_count > 0} {
        set cap [hider_count_cap $atom_count]
    } else {
        set cap 50
    }
    if {$cap < 1} { set cap 1 }
    set hider_count [_randint 1 $cap]
    # resolve the fetch pool (v2: empty default; empty -> fetch re-rolls to demo)
    if {$pdb_pool ne ""} { set pool_for_fetch [_validate_pdb_pool $pdb_pool] } else { set pool_for_fetch [list] }

    # lock_source branch (preserve target; only randomize hider composition)
    if {$lock_source && $locked_state ne "" && ![catch {dict size $locked_state}]} {
        set mode [dict get $locked_state target_mode]
        if {$mode ne "loaded" && $mode ne "fetch" && $mode ne "demo"} { set mode "loaded" }
        set selected_object [dict get $locked_state selected_object]
        set pdb_code [string tolower [string trim [dict get $locked_state pdb_code]]]
        set did [dict get $locked_state demo_id]
        if {![dict exists $DEMO_MANIFEST $did]} { set did "1znf" }
        set demo_id $did
    } else {
        # random mode (weighted toward demo): loaded/fetch/demo/demo
        set mode [_choice [list loaded fetch demo demo]]
        if {$mode eq "fetch" && [llength $pool_for_fetch] == 0} { set mode "demo" }  ;# empty pool -> never fetch
        set selected_object ""
        if {$mode eq "fetch"} {
            set pdb_code [_choice $pool_for_fetch]
        } else {
            set pdb_code ""
        }
        # demo from BUNDLED demos only (offline-safe; Phase 14 manifest is all bundled)
        set bundled_ids [list]
        foreach did [dict keys $DEMO_MANIFEST] {
            if {[dict get $DEMO_MANIFEST $did source] eq "bundled"} { lappend bundled_ids $did }
        }
        set demo_id [_choice $bundled_ids]
    }
    # per_rep via randomize_per_rep (NO seed -> continues the global sequence; quick-008 baked in)
    set per_rep [randomize_per_rep $hider_count $GAME_REPS]
    set lock_scene [_choice [list 0 1]]
    set difficulty_easy [_choice [list 0 1]]
    return [dict create \
        format          $SETUP_FORMAT \
        target_mode     $mode \
        selected_object $selected_object \
        pdb_code        $pdb_code \
        demo_id         $demo_id \
        hider_count     $hider_count \
        lock_scene      $lock_scene \
        per_rep         $per_rep \
        difficulty_easy $difficulty_easy \
        lock_source     [_to_bool $lock_source] \
        pdb_pool        [_validate_pdb_pool $pdb_pool]]
}
```

**Verified (probe_pure.tcl):**
- `randomize_per_rep 10 $GAME_REPS 42` → `Tube 5 CPK 1 Cartoon 4`; deterministic (`r1 eq r2`=1); seed 1 ≠ seed 2; non-empty guarantee holds across 20 seeds with hider_count=1; hc=0/-5/empty-reps → `{}`; all counts>0 and sum≤15 across 30 seeds; hc=1 → one rep count 1.
- per_rep-sum clamp: `{VDW 5 Cartoon 5 Lines 5}` hc=8 → `{VDW 5}` (sum=5, overflow dropped); invalid key `Surface` dropped; zero/negative counts dropped.

**Update the `namespace export` line** in `setup_state.tcl` to add the new public procs:
```tcl
namespace export GAME_REPS SETUP_FORMAT DEFAULTS DEMO_MANIFEST hider_count_cap validate_state randomize_state randomize_per_rep
```

---

## Save/Load Setup format (verified round-trip)

This is the **setup parameters only** (the 11 DEFAULTS keys) — NOT the full `.bcm` game-state persistence (Phase 20). No `json` package in VMD 1.9.3. The verified recommendation: **key-value line format + DEFAULTS-key-order rebuild on load**. This lives in the mol bridge (`demos.tcl`) or a small `lib/persistence.tcl` helper — NOT the pure layer (per the objective). It is stdlib-only (open/puts/gets/close), so it's testable, but it's file I/O grouped with the setup bridge.

**Recommendation:** add `save_setup`/`load_setup` to `demos.tcl` (keeps the file count down; they don't need `mol` but are setup-config I/O). Mark them stdlib-only in the docstring.

### Verified format + read/write example

```tcl
# The on-disk format (human-readable, line-oriented):
#   format biochemeleon-setup-v2
#   target_mode demo
#   selected_object
#   pdb_code
#   demo_id 1k8p
#   hider_count 11
#   lock_scene 0
#   per_rep_count 2
#   per_rep_entry VDW 3
#   per_rep_entry Cartoon 2
#   difficulty_easy 1
#   lock_source 0
#   pdb_pool_count 2
#   pdb_pool_entry 1znf
#   pdb_pool_entry 1k8p

proc ::biochemeleon::demos::save_setup {state filepath} {
    variable ::biochemeleon::setup_state::SETUP_FORMAT
    set fh [open $filepath w]
    puts $fh "format $SETUP_FORMAT"
    dict for {k v} $state {
        if {$k eq "format"} continue
        if {$k eq "per_rep"} {
            puts $fh "per_rep_count [dict size $v]"
            dict for {rep cnt} $v { puts $fh "per_rep_entry $rep $cnt" }
        } elseif {$k eq "pdb_pool"} {
            puts $fh "pdb_pool_count [llength $v]"
            foreach code $v { puts $fh "pdb_pool_entry $code" }
        } else {
            puts $fh "$k $v"
        }
    }
    close $fh
}

proc ::biochemeleon::demos::load_setup {filepath} {
    variable ::biochemeleon::setup_state::DEFAULTS
    if {![file exists $filepath]} { return -code error "setup file not found: $filepath" }
    set fh [open $filepath r]
    set tmp [dict create]
    set per_rep [dict create]
    set pdb_pool [list]
    while {[gets $fh line] >= 0} {
        set parts [split $line " "]
        set key [lindex $parts 0]
        switch -- $key {
            "format"         { dict set tmp format [lindex $parts 1] }
            "per_rep_count"  { }
            "per_rep_entry"  { dict set per_rep [lindex $parts 1] [lindex $parts 2] }
            "pdb_pool_count" { }
            "pdb_pool_entry" { lappend pdb_pool [lindex $parts 1] }
            default          { dict set tmp $key [lindex $parts 1] }
        }
    }
    close $fh
    dict set tmp per_rep $per_rep
    dict set tmp pdb_pool $pdb_pool
    # REBUILD in DEFAULTS key order for order-stable dict eq round-trip (Pitfall 5).
    set loaded [dict create]
    foreach k {format target_mode selected_object pdb_code demo_id hider_count lock_scene per_rep difficulty_easy lock_source pdb_pool} {
        if {[dict exists $tmp $k]} { dict set loaded $k [dict get $tmp $k] }
    }
    # Validate through the pure layer (canonicalizes + clamps) before returning.
    return [::biochemeleon::setup_state::validate_state $loaded]
}
```

**Verified:** `save_setup` then `load_setup` of a state with `per_rep {VDW 3 Cartoon 2}` and `pdb_pool {1znf 1k8p}` round-trips with `loaded eq test_state: 1` (DEFAULTS-order rebuild is the critical fix — without it, `eq`=0 because `per_rep` would land last). The final `validate_state` call canonicalizes any out-of-range/invalid values loaded from a hand-edited file (defense in depth). The `format` line lets a future loader reject mismatched versions.

**Why not the sourced-tcl-dict alternative:** probed — `uplevel 1 [list source $file]` from a `-e`'d harness fails ("bad level 1"); generating a `dict create` literal with nested dicts + lists via `[list $v]` is fragile (quoting); and `source`-ing an arbitrary file as code is a security smell. The key-value line format is simpler, parser-robust, and verified.

---

## tcltest case list (extends the existing 12 cases in `test_setup_state.test`)

The existing `test_setup_state.test` has 12 cases (GAME_REPS, hider_count_cap, SETUP_FORMAT, DEFAULTS, DEMO_MANIFEST, validate_state stub). The existing `validate_state_stub_returns_defaults` test will need updating (the full impl no longer returns DEFAULTS for empty input — it returns DEFAULTS for non-dict input, but for a `dict create` it returns a validated dict; the stub test should be replaced/renamed). Phase 14 ADDS these cases (all use explicit seeds for determinism — Pitfall 4):

### validate_state (full impl) — ~12 cases
- `validate_state_non_dict_returns_defaults` — input `"foo"` → DEFAULTS
- `validate_state_fills_missing_keys` — partial dict `{demo_id 5e54}` → all 11 keys present
- `validate_state_clamps_hider_count_to_cap` — `{hider_count 999}` + atom_count=212 → hider_count=4
- `validate_state_clamps_hider_count_min_1` — `{hider_count 0}` → hider_count=1
- `validate_state_clamps_hider_count_default_cap_50_no_atom_count` — `{hider_count 999}` (no atom_count) → 50
- `validate_state_clamps_per_rep_sum_drop_overflow` — `{hider_count 8 per_rep {VDW 5 Cartoon 5 Lines 5}}` → per_rep=`{VDW 5}` (sum 5, overflow dropped)
- `validate_state_drops_invalid_per_rep_key` — `per_rep {Surface 5 VDW 2}` → `{VDW 2}` (Surface not in GAME_REPS)
- `validate_state_drops_zero_negative_counts` — `per_rep {VDW 0 Cartoon -3 Lines 4}` → `{Lines 4}`
- `validate_state_invalid_target_mode_falls_to_loaded` — `{target_mode "foo"}` → target_mode="loaded"
- `validate_state_invalid_demo_id_falls_to_1znf` — `{demo_id "xxxx"}` → demo_id="1znf"
- `validate_state_lowercase_pdb_code` — `{pdb_code "1UBQ"}` → "1ubq"
- `validate_state_does_not_mutate_input` — input dict unchanged after call (compare a saved copy)
- `validate_state_pdb_pool_filters_and_dedupes` — `{pdb_pool {1ubq 1UBQ 12345 1ubq}}` → `{1ubq}` (lowercase, deduped, 5-char dropped)

### randomize_per_rep (quick-008) — ~8 cases
- `randomize_per_rep_zero_count_empty` — `0 $GAME_REPS 5` → `{}`
- `randomize_per_rep_negative_count_empty` — `-5 $GAME_REPS 5` → `{}`
- `randomize_per_rep_empty_game_reps_empty` — `5 [list] 5` → `{}`
- `randomize_per_rep_seed_determinism` — `(10 $GAME_REPS 42)` twice → `eq`=1
- `randomize_per_rep_seed_difference` — seed 1 ≠ seed 2
- `randomize_per_rep_non_empty_when_count_positive` — for seed 0..19, hider_count=1 → dict size ≥ 1 (the quick-008 guarantee)
- `randomize_per_rep_all_counts_positive_and_sum_le_total` — for seed 0..29, hider_count=15 → every count > 0 and sum ≤ 15
- `randomize_per_rep_count_one_single_rep` — hider_count=1, fixed seed → exactly one rep with count 1

### randomize_state — ~8 cases
- `randomize_state_seed_determinism` — `(42)` twice → `eq`=1
- `randomize_state_seed_difference` — seed 1 ≠ seed 2
- `randomize_state_has_all_defaults_keys` — result has all 11 keys
- `randomize_state_hider_count_in_range` — for seed 0..9 + atom_count=212 → hider_count in [1, 4]
- `randomize_state_lock_source_preserves_target` — lock_source=1 + locked_state `{target_mode demo demo_id 5e54 ...}` → result target_mode=demo, demo_id=5e54
- `randomize_state_lock_source_no_locked_state_falls_back` — lock_source=1, locked_state="" → random mode (not an error)
- `randomize_state_empty_pdb_pool_fetch_rerolls_to_demo` — pdb_pool="" + many seeds → target_mode never "fetch"
- `randomize_state_per_rep_non_empty_when_hider_count_positive` — for seed 0..9 → per_rep dict size ≥ 1 (quick-008 baked in)

**Run command (unchanged from Phase 13):**
```bash
mkdir -p tmp/biochemeleon-vmd && cp -r vmd tmp/biochemeleon-vmd/
timeout 60 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/test_setup_state.test -eofexit < /dev/null' 2>&1 | tee /tmp/bchm_test_out
grep -E 'BCHM_TEST_RESULT' /tmp/bchm_test_out  # parse the marker, NOT $?
```

**Test-harness note:** the existing `validate_state_stub_returns_defaults` test asserts `dict exists $result format` on `validate_state [dict create]`. The full impl returns a validated dict that STILL has the `format` key (from DEFAULTS), so that test continues to PASS unchanged — but rename it to `validate_state_empty_dict_returns_defaults_with_format` for clarity, and ADD the new cases above.

---

## State of the Art — v1 → v2 differences

| v1 (PyMOL) | v2 (VMD 1.9.3) | Impact |
|------------|----------------|--------|
| `cmd.get_names('public_objects')` + `cmd.get_type` | `molinfo list` + `molinfo $m get name` | name is the FILENAME (read-only), not a settable object name |
| `cmd.load(path, object=name)` (named load) | `mol new <path> type pdb` (NO name option) | cannot name at load; display `"<filename> (<molid>)"` |
| `cmd.fetch(code, async_=0)` (RCSB fetch) | NO built-in fetch; `mol new <url>` fails; no `tls` for HTTPS | fetch deferred to Phase 21; Phase 14 stub |
| `cmd.count_atoms("{obj} and rep {rep}") > 0` | `molinfo $mol get numreps` + per-rep style query | VMD has a direct rep list (cleaner than PyMOL's atom-count proxy) |
| `random.Random(seed)` (per-instance PRNG) | `expr {srand($seed)}` + `expr {rand()}` (GLOBAL) | determinism works but tests must seed + not interleave (Pitfall 4) |
| `PDB_POOL` 33-entry default (fetch pool) | `pdb_pool [list]` (empty) in DEFAULTS | v2 has no PDB_POOL constant; fetch is Phase 21; empty pool → fetch re-rolls to demo |
| `DEMO_MANIFEST` 9 entries (6 bundled + 3 fetched) | `DEMO_MANIFEST` 6 bundled only | Phase 14 manifest is bundled-only; `load_demo` source-branch is trivial (reject non-bundled) |
| `randomize_per_rep` separate (called at START) | `randomize_state` CALLS `randomize_per_rep` + START flow calls it (Phase 16) | quick-008 baked into BOTH the Randomize button and the START flow |
| per_rep-sum clamp: drop overflow (insertion order) | SAME (drop overflow) | port verbatim; do NOT truncate |

**Deprecated/outdated (do NOT port to v2):**
- v1's `to_windows_path` (backslashes) → v2's `to_vmd_path` (FORWARD slashes; AGENTS.md: "C:/..." not "C:\\...").
- v1's `_validate_pdb_pool` returning `PDB_POOL` on empty → v2 returns empty (no PDB_POOL).
- v1's all-spheres fallback at START (`__init__.py:477-482`) → v2 bakes quick-008 into `randomize_state`/`randomize_per_rep` (no fallback).

---

## Open Questions (flag for the planner)

1. **"distribute across ALL reps" vs v1 quick-008 "random non-empty subset" — DECISION POINT.**
   - What we know: the ROADMAP success criterion #2 says "a total-only count randomly distributes across all reps (quick-008 baked in)". The objective says "distribute across ALL reps in GAME_REPS randomly ... v1's quick-008 patch". BUT v1's actual quick-008 (`randomize_per_rep`) distributes across a **random non-empty SUBSET** of reps (1 to len), NOT all reps (verified in `pymol/biochemeleon/generators.py:252` + the 008-PLAN). The "ALL reps" prose contradicts the "v1's quick-008 patch" reference.
   - What's unclear: does the user want (a) the verified v1 quick-008 behavior (random non-empty subset — RECOMMENDED, it's what "v1's quick-008 patch" literally is and what "baked in" means), or (b) a literal "every rep gets a share" distribution?
   - Recommendation: implement (a) — the v1 quick-008 `randomize_per_rep` exactly (random non-empty subset + non-empty guarantee). It's the verified reference. If the user prefers (b), the planner can change `_randint 1 [llength $game_reps]` to `[llength $game_reps]` (all reps) and adjust the distribution — a small, localized change. **Flag for plan-time decision.**

2. **fetch_pdb — Phase 14 stub vs best-effort http — DECISION POINT.**
   - What we know: VMD 1.9.3 has `http` (v2.7.2) but NO `tls`; RCSB is HTTPS-only. `mol new <url>` and `mol load pdb <code>` both FAIL (verified). The robust fetch (tls/network) is Phase 21.
   - What's unclear: should Phase 14 ship (a) a `fetch_pdb` STUB that errors cleanly (RECOMMENDED — the bundled demos are the primary SETUP-01 path and the success criterion), or (b) a best-effort `http` download over an http URL (may fail for RCSB https)?
   - Recommendation: (a) stub for Phase 14; the GUI shows the PDB-fetch option but catches the error and points to bundled demos. Phase 21 implements the real fetch. **Flag for plan-time decision.**

3. **pdb_pool default — v2 empty vs a v2 pool — DECISION POINT (minor).**
   - What we know: v2 DEFAULTS has `pdb_pool [list]` (empty); v1 had a 33-entry `PDB_POOL`. The 33 entries were verified in v1 Phase 9 (a fetch feature). v2 hasn't ported them.
   - Recommendation: keep v2 DEFAULTS empty for Phase 14 (fetch is Phase 21); `randomize_state` fetch mode re-rolls to demo on empty pool (the guard). If the user wants the 33-pool ported now, it's a small addition (copy the verified list from `setup_state.py:78-112` into a `PDB_POOL` variable + `_validate_pdb_pool` default). **Flag for plan-time decision.**

4. **Save/Load file location + extension — minor.**
   - What we know: the format is verified (key-value lines). The GUI Save/Load dialog picks the path (GUI researcher's scope).
   - Recommendation: use a `.bcm` extension (consistent with the future Phase 20 `.bcm` game-state sidecar) OR `.txt`. The `save_setup`/`load_setup` procs take a filepath param (GUI-chosen). The format line `format biochemeleon-setup-v2` lets a future loader reject mismatched versions. **Flag to coordinate with the GUI researcher.**

---

## Sources

### Primary (HIGH confidence — probed live against VMD 1.9.3 on this machine)
- `tmp/biochemeleon-vmd/probe_mol.tcl` — mol new, molinfo list/name/numatoms/filename, default reps, addrep+modstyle+delrep, GAME_REPS style-name match (all 10), atom counts for all 6 demos, `expr rand()`/`srand()`, `mol new <url>` (FAILED), `mol load pdb` (FAILED)
- `tmp/biochemeleon-vmd/probe_mol2.tcl` — `molinfo set name` (READ-ONLY), `mol new name` (ignored), positional name (errors), `mol load pdb` (fails), repname stability across delrep-0 loop (STABLE confirmed), single-field `molinfo get {rep 0}` (FAILS), srand determinism (CONFIRMED), `int(rand()*N)` randint
- `tmp/biochemeleon-vmd/probe_mol3.tcl` — `http` package (v2.7.2 available), `tls` (NOT available), `mol delete` + monotonic molids, key-value save/load round-trip (order-sensitivity discovered)
- `tmp/biochemeleon-vmd/probe_save.tcl` — DEFAULTS-key-order rebuild → `loaded eq test_state: 1` (the fix for order-sensitivity)
- `tmp/biochemeleon-vmd/probe_demos.tcl` — verified `to_vmd_path`, `list_loaded_molecules`, `load_demo` (all 6 demos), `get_active_reps` (default + added reps + after delrep), `[info script]` under `source`
- `tmp/biochemeleon-vmd/probe_pure.tcl` — verified `_clamp_per_rep` (drop overflow), `randomize_per_rep` (determinism, non-empty guarantee, all counts>0, sum≤total), Fisher-Yates `_sample`

### Secondary (MEDIUM confidence — reference plugin source, verified patterns)
- `vmd-ref/plugins/clonerep1.3/clonerep.tcl:93-127` — `mol delrep 0` loop + `molinfo get "{rep $i} {selection $i} {color $i} {material $i}"` + `mol addrep`/`mol modstyle` (the rep-management patterns)
- `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:246-319` — `save_reps`/`restore_reps` (rep save/restore round-trip; `mol modstyle`/`mol modselect`/`mol modcolor`/`mol modmaterial`)
- `pymol/biochemeleon/setup_state.py:233-413` — v1 `hider_count_cap`/`randomize_state`/`validate_state` (the port source)
- `pymol/biochemeleon/demos.py:59-197` — v1 `to_windows_path`/`list_loaded_molecule_objects`/`fetch_pdb`/`get_active_reps`/`load_demo` (the port source)
- `pymol/biochemeleon/generators.py:252-283` — v1 `randomize_per_rep` (the quick-008 reference; random NON-EMPTY subset + non-empty guarantee)
- `.planning/quick/008-randomize-reps-when-total-only/008-PLAN.md:100-152` — the quick-008 algorithm spec (confirms subset, not all-reps)
- `.planning/phases/13-bootstrap-sourced-entry/13-RESEARCH-testing.md` — Phase 13 patterns (tcl 8.5 capabilities, headless VMD invocation, `[info script]` under source, BCHM_TEST_RESULT marker, grep gate)

### Tertiary (LOW confidence — none; all claims are probe-verified)

---

## Metadata

**Confidence breakdown:**
- mol/molinfo command surface: **HIGH** — every command + output probed live against VMD 1.9.3.
- load_demo / get_active_reps / list_loaded_molecules / to_vmd_path: **HIGH** — full proc skeletons probed headlessly with all 6 demos.
- validate_state full port: **HIGH** — per_rep-sum clamp + field validation algorithms probed in pure tcl.
- randomize_state / randomize_per_rep: **HIGH** — determinism, non-empty guarantee, count ranges probed.
- Save/Load format: **HIGH** — round-trip `dict eq`=1 verified with the DEFAULTS-order rebuild.
- fetch_pdb: **HIGH** (that it fails) / **MEDIUM** (the deferral recommendation is a plan-time decision).
- tcltest case list: **MEDIUM** — the cases are derived from the verified algorithms but the exact test bodies are the planner's to write.

**Research date:** 2026-08-29
**Valid until:** 2026-09-29 (30 days — VMD 1.9.3 is a fixed 2016 build; the mol/molinfo surface is stable; the pure-tcl algorithms are stable. Re-verify only if VMD is upgraded.)
