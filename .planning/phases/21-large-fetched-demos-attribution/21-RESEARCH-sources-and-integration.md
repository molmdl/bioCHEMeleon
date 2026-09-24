# Phase 21 Research — Large Fetched Demos & Attribution (DATA SOURCES + V2 INTEGRATION POINTS)

**Researched:** 2026-09-25
**Domain:** MemProtMD/SASBDB/RCSB fetch URLs + licenses (DEMO-02/03/04), difficulty tiers (DIFF-05), and the exact v2 tcl integration seams (fetch pipeline, manifest, GUI sub-menu, Start-flow warning)
**Confidence:** HIGH for URLs/licenses (all re-verified live today via curl) and for code seams (read from current source); MEDIUM for the v2 transport + compression mechanics (VMD 1.9.3 runtime capabilities need empirical probes — sibling researcher covers those)
**Scope note:** Read-only research + URL verification. No VMD was run (empirical VMD probes are a sibling researcher's file). v1 answers live in `.planning/phases/09-large-demo-fetch-source-attribution/09-RESEARCH-{memprotmd,sasbdb,pipeline}.md` — re-verified where they matter, summarized, not duplicated.

---

## 1. Source inventory (verified 2026-09-25)

All statuses below are from live curl probes made **today** (range-GETs / HEAD-ish; full wet files were NOT re-downloaded — sizes from v1's verified 2026-08-14 byte counts, which are recorded in `DATA_SOURCES.md:104,115-116`).

| Demo | Provider | Verified URL (HTTP status today) | Format | Size (v1-verified) | License (per-entry) | VMD 1.9.3 loadability |
|------|----------|----------------------------------|--------|--------------------|---------------------|------------------------|
| **1GZM** | MemProtMD | `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/1gzm_default_dppc/files/structures/at.pdb` — **206** (range GET, real PDB content: `TITLE Gromacs RunMostMost…`, `CRYST1 138.600 102.061 108.694 … P 1`, `ATOM 1 N MET`, `ATOM 2 H1 MET` — hydrogens present) | PDB (wet: protein + DPPC bilayer + SOL water + NA/CL ions, **all as ATOM records, zero HETATM**) | wet 9,314,128 B / **117,898 atoms**; dry (SOL+NA+CL stripped) **EST ~25,974 atoms / ~2 MB — arithmetic estimate, UNVERIFIED until first fetch** (117,898 − 91,638 SOL − 147 NA − 139 CL) | **CC-BY 4.0** (site-wide download-panel license; string re-verified today in `/static/js/index.js`: "Licensed using a Creative Commons Attribution 4.0 International License."; per-entry page HTML is a JS shell — no per-entry divergence observable, so per-entry license = the shared CC-BY 4.0 panel) | **YES after strip** (plain PDB; `mol new … type pdb` is the existing path, `demos.tcl:78`). Wet file loads too but must NOT be the game target |
| **3GP6** | MemProtMD | `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/3gp6_default_dppc/files/structures/at.pdb` — **206** (real PDB content: `TITLE S C A M M G`, `CRYST1 109.513 …`) | same as 1GZM | wet 7,524,042 B / **95,239 atoms**; dry **19,221 atoms / 1,518,620 B** (v1-verified; zipped 231,087 B) | CC-BY 4.0 (same mechanism) | YES after strip |
| **SASDPG4** (glycoprotein) | SASBDB | `https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb` — **206** (real PDB content: `TITLE SWISS-MODEL SERVER`, `EXPDTA THEORETICAL MODEL`); entry page `https://www.sasbdb.org/data/SASDPG4/` — **200** | **PDB only for this entry** — entry page lists `pdb_file` (17 mentions) and **zero `.cif`/mmCIF** (grep-verified today). `fit2_model1` is load-bearing: `fit1_model1` is protein-only (0 HETATM, no glycan → DEMO-03 silent failure) | 400,810 B / **4,123 atoms** (1,522 protein ATOM + 2,601 glycan HETATM; 8 glycan resn: NAG, MAN, BMA, NAN, GLB, AFL, NGA, GLA) | "free of all copyright restrictions and made fully and freely available for both non-commercial and commercial use. Users of the data should attribute the original authors." (re-verified today on `/aboutSASBDB/`) | **YES as-is** (plain PDB, VMD loads any 3-char resn; no strip needed — 0 water/ions, v1 grep-verified) |
| (fallback) 1GZM/3GP6 bare | RCSB | `https://files.rcsb.org/download/1GZM.pdb` — **200** (`HEADER … STRUCTURE OF BOVINE RHODOPSIN IN A TRIGONAL CRYSTAL FORM`); `…/3GP6.pdb` — **200**; **plain `http://files.rcsb.org/download/1GZM.pdb` — 200, NO redirect** | PDB | 1GZM 5,792 deposited atoms; 3GP6 1,586 (v1, RCSB API) | CC0 1.0 (RCSB policy, `DATA_SOURCES.md:11`) | YES — but these are the **bare crystal structures, NOT the membrane assemblies**. DEMO-02 wants the MemProtMD membrane-embedded ones (DPPC bilayer is the point). RCSB copies are a *fallback*, never the primary |
| (fallback) SASDPG4 on RCSB | — | N/A — SASDPG4 is a SAXBDB-only SAXS model, no RCSB mirror exists (different database, different structure) | — | — | — | — |

**Plain-HTTP transport probe (decisive for VMD):**

| Server | plain HTTP result | Consequence for VMD 1.9.3 (Tcl http, **no tls** — `demos.tcl:102-105`) |
|--------|-------------------|------------------------------------------------------------------------|
| memprotmd.bioch.ox.ac.uk | **301 → https** | Tcl http **cannot** fetch MemProtMD (can't follow to HTTPS) |
| www.sasbdb.org | **302 → https** | Tcl http **cannot** fetch SASBDB |
| files.rcsb.org | **200 (no redirect)** | Tcl http **CAN** fetch RCSB over plain HTTP: `http://files.rcsb.org/download/<CODE>.pdb` — the viable transport for `target_mode=fetch` (SETUP-01). Caveat: plain HTTP = no TLS → MITM exposure; v1 accepted a weaker posture already (`PROJECT.md:90`: `check_hostname=False` SSL-fallback debt) |

**1GZM naming error to fix (DEMO-04):** `DATA_SOURCES.md:98` heading says "1GZM — **bacteriorhodopsin** (Very challenging)" — wrong. RCSB header verified today: **bovine rhodopsin** (`STRUCTURE OF BOVINE RHODOPSIN IN A TRIGONAL CRYSTAL FORM`). The file is internally inconsistent: `DATA_SOURCES.md:91` already cites it correctly as "Bovine rhodopsin". Same error in `09-RESEARCH-pipeline.md:434`. Also `09-RESEARCH-pipeline.md:435` calls 3GP6 "OmpA beta-barrel" — it is **PagP** (`DATA_SOURCES.md:94,108` correct). Fix both at the `DATA_SOURCES.md:98` heading + add VMD as the v2 graphics system beside §5 PyMOL. **[HUMAN-APPROVAL-NEEDED]** (citation text change, per root AGENTS.md "ALL claims and citations MUST BE VERIFIED … and explicitly approved by a human").

**SASBDB format risk callout (research question A.2):** RESOLVED — **no blocker**. The phase brief feared "SASBDB only serves mmCIF" → for SASDPG4 it does not: the entry serves 5 PDB model files + a zip, no cif (`/data/SASDPG4/` grep-verified today). VMD 1.9.3's limited/absent mmCIF support is therefore moot for this demo. The remaining SASBDB risks are unchanged from v1: URL rot / entry withdrawal (mitigation: cache + SASDPH4 same-pattern fallback) and the `fit1_model1`-vs-`fit2_model1` trap (hardcode `_fit2_model1`; a "first file" heuristic silently breaks DEMO-03).

---

## 2. v1 difficulty assignments (DIFF-05) + atom-count sizing signal

v1's settled, human-approved assignments are encoded as headings in `DATA_SOURCES.md` (the DEMO-04 artifact v1 shipped): 1GZM "(Very challenging)" (`:98`), 3GP6 "(Very challenging)" (`:108`), SASDPG4 "(Challenge)" (`:139`), bundled six under §1. The full 9-demo tier table with rationale is `09-RESEARCH-pipeline.md:425-437`. **One v1 research self-contradiction resolved:** `09-RESEARCH-memprotmd.md:397` proposed 3gp6='challenge', but the pipeline tier table AND the human-approved `DATA_SOURCES.md` both say **Very challenging** — the approved artifact wins.

| Demo | Tier (v1 settled) | v2 manifest difficulty value | Size signal (records = grep `^(ATOM|HETATM)` of `vmd/data/demos/*.pdb` today; VMD `numatoms` = per-frame) |
|------|-------------------|------------------------------|------|
| 1znf | Easy | `easy` (already, `setup_state.tcl:35`) | 15,688 records — 37-model NMR ensemble; **VMD numatoms = 424** (smoke-pinned: 17.x capstones consistently report 424-425) |
| 5e54 | Easy | `easy` (`:37`) | 2,844 records |
| 1k8p | Easy | `easy` (`:38`) | 555 records |
| 1xdn | Hard | `hard` (`:36`) | 2,597 records |
| 2qbz | Hard | `hard` (`:39`) | 3,408 records |
| 4wb3 | Hard (v1 was 'mixed' → settled to hard) | **`hard` already in v2** (`setup_state.tcl:40`) — the v1 'mixed' reconciliation is already done | 3,779 records |
| SASDPG4 | Challenge | `challenge` (new) | 4,123 atoms |
| 1GZM | Very challenging | `very_challenging` (new) | wet 117,898 / dry est ~25,974 |
| 3GP6 | Very challenging | `very_challenging` (new) | wet 95,239 / dry 19,221 |

Store identifier-safe values (`easy`/`hard`/`challenge`/`very_challenging`) in the manifest; map to display labels via a `TIER_LABELS`-style variable ("Easy"/"Hard"/"Challenge"/"Very challenging") — exactly v1's vocabulary (`09-RESEARCH-pipeline.md:397-402`). Result: 3 easy + 3 hard + 1 challenge + 2 very_challenging = 4 tiers, matching the criterion literally.

**>20k-atom warning nuance (SC4):** the warning fires for **1GZM-dry (~25,974 > 20k)** but **NOT for 3GP6-dry (19,221 < 20k)** — a deliberately knife-edge pair. Wet files (95k/118k) are far over but should never reach `mol new` as the game target. Pin exact dry counts empirically at first fetch (sibling probe / execute step).

**Hider cap already saturates:** `hider_count_cap` (`setup_state.tcl:51-59`, `atom_count/50` clamped [1,50]) returns 50 for BOTH large demos (19,221/50→384→50; 25,974/50→519→50). SC4's "cap hider count as a function of atom count" is **already implemented** — Phase 21 only needs to *prove* it at large atom counts (smoke assert), not change it.

---

## 3. V2 integration map (per file, exact seams)

### 3.1 `vmd/lib/setup_state.tcl` (PURE layer)

| What | Where | Change |
|------|-------|--------|
| `DEMO_MANIFEST` | `setup_state.tcl:34-40` | Add 3 entries. Current per-entry keys: `{category type difficulty source cache_name}` (v2 already flattened v1's `file`→`cache_name`). For fetched entries: `source memprotmd` / `source sasbdb` (the `load_demo` guard at `demos.tcl:68` branches on `source ne "bundled"`, so any non-bundled value works — pick these two), `cache_name` = cache filename (e.g. `1gzm_default_dppc-atomistic_dry.pdb` / `sasdpg4_fit2_model1.pdb`), plus NEW fields `fetch_url` (explicit URL = traceable against DATA_SOURCES.md; alternative is deriving from a `MEMPROTMD_DATA_ROOT` constant in demos.tcl — v1 recommended deriving, `09-RESEARCH-memprotmd.md:408`, but explicit-in-manifest is more grep-able; planner's call) and `strip` (1 for MemProtMD, 0 for SASDPG4). Optional `approx_atoms` for pre-load info display. |
| `TIER_LABELS` | new `variable` near line 34 | `variable TIER_LABELS [dict create easy Easy hard Hard challenge Challenge very_challenging "Very challenging"]`; add to the `namespace export` list (line 45). |
| `randomize_state` | `setup_state.tcl:270-275` | **NO CHANGE** — it already filters `source eq "bundled"` when building the random demo pool, so fetched demos are automatically excluded from Randomize (exactly v1's recommendation (a), already implemented in v2). |
| `validate_state` demo_id check | `setup_state.tcl:148-151` | **NO CHANGE** — membership check against `DEMO_MANIFEST` accepts the new ids the moment the manifest is extended. |
| `hider_count_cap` | `setup_state.tcl:51-59` | **NO CHANGE** (saturates at 50 for large demos — see §2). Smoke-assert `hider_count_cap 95239 == 50` etc. |
| DEFAULTS / SETUP_FORMAT | `setup_state.tcl:13-29` | **NO CHANGE** — no new setup-state keys (see §4). |

### 3.2 `vmd/lib/demos.tcl` (mol bridge — where the fetch pipeline lives)

Current shape: 8 exported procs (`demos.tcl:27-29`): `to_vmd_path list_loaded_molecules load_demo get_active_reps fetch_pdb save_setup load_setup atom_count`.

| Seam | Lines | What Phase 21 does |
|------|-------|--------------------|
| `script_dir` capture | `demos.tcl:26` (frozen at SOURCE time — the 14-02 lesson, documented inline at `:19-25`) | Reuse for the cache dir: `[file join $script_dir .. data demos cache]` — mirrors `load_demo`'s bundled-path resolution (`:75-76`: `file normalize [file join $script_dir .. data demos $cache_name]`). `git check-ignore vmd/data/demos/cache/1gzm.pdb` → ignored via `.gitignore:20` (`cache`) + `:19` (`**/cache/**`), verified today. |
| `load_demo` non-bundled guard | `demos.tcl:65-70` (explicitly anticipates this phase: "If a later phase adds fetched demos, branch on `[dict get $meta source]` here (v1 demos.py:183)") | Replace the `return -code error` with the fetched branch: cache HIT → `mol new <cache_path> type pdb` (return molid); cache MISS → `return -code error "not cached: fetch required"` (GUI orchestrates the fetch — the load proc stays synchronous). |
| `fetch_pdb` STUB | `demos.tcl:102-108` (`return -code error "fetch_pdb not implemented in Phase 14 (VMD 1.9.3 lacks tls …)"`) | Grows into the real RCSB fetch for `target_mode=fetch` (SETUP-01): signature stays `fetch_pdb {code}` → returns molid. Transport: `::http::geturl http://files.rcsb.org/download/<CODE>.pdb` (plain HTTP **verified 200 today**) — the in-tree precedent for Tcl-http→file is VMD's own `vmdhttpcopy` (`vmd-ref/scripts/biocore.tcl:67-101`: `::http::geturl $url -channel $out -progress … -binary 1`). Alternative: `mol pdbload <4-char>` (documented VMD command, `STACK.md:260`, UG node140) — **internal protocol UNVERIFIED; sibling probe**. |
| NEW procs (implied) | — | `cache_dir` (script_dir-relative), `cache_path_for {demo_id}`, `is_cached {demo_id}` (pure-ish, tclsh-testable), `load_cached_demo {demo_id}` → molid/0, `strip_and_cache {demo_id molid}` → cache path (see strip below), `download_to_file {url dest {progress_cb}}` (transport-dependent — see §5). Keep demos.tcl **Tk-free** (dependency direction, AGENTS.md architecture diagram): progress UI lives in the GUI layer, demos.tcl exposes primitives + takes a progress callback proc name, same split v1 used (`09-RESEARCH-pipeline.md:474-486`). |

**Strip — the v1 approach does NOT port.** v1 stripped in-memory (`cmd.remove` + `cmd.save`, `09-RESEARCH-pipeline.md:279-291`) — **VMD cannot delete atoms in-place** (`vmd/AGENTS.md`: "no per-atom delete"). Two v2 options:

- **Option B (recommended): VMD-native selection-write.** `mol new <wet.pdb> type pdb` → `[atomselect $molid "not resname SOL NA CL"] writepdb <dry.pdb>` → `mol delete` → `mol new <dry.pdb>`. Uses VMD's C machinery (fast, no Tcl-side PDB parsing); transiently loads the 95k-118k-atom wet molecule (acceptable — VMD handles 100k+ atom PDBs routinely; the *game* target is the dry file).
- **Option A (alternative): pure-Tcl line filter** before `mol new` (drop ATOM lines whose cols 18-20 ∈ {SOL, NA, CL} — v1 empirically verified the strip set with exact atom-count math: 3gp6 wet 95,239 − (75,789 SOL + 116 NA + 113 CL) = 19,221 dry ✓, `09-RESEARCH-memprotmd.md:218-232`). tclsh-unit-testable, never loads the wet molecule — but the ~800k-line pass over 1GZM's 9.3 MB is seconds of Tcl CPU → must be `after 0`-chunked (SC4's chunking clause) or done as one `read`+`split` gulp (~9.3 MB string is fine).

Either way: **strip by explicit `resname SOL NA CL`** (the v1-verified set — "salt" = the NA/CL counter-ions; no other ion species present). Do NOT use VMD's `water` keyword — whether VMD's water-name list includes GROMACS `SOL` is UNVERIFIED. Do NOT strip SASDPG4 (`strip 0`; its 2,601 HETATM are ALL glycan — a naive hetatm-strip would silently fail DEMO-03, `DATA_SOURCES.md:172-174`).

**Compression — open mechanic.** Tcl 8.5.6 has no zlib and VMD 1.9.3's PDB gzip read/write is UNVERIFIED. Sibling probes to run: (1) `mol new <file>.pdb.gz` on a staged gz; (2) `package require zlib` / `info commands zlib` inside VMD. If gz read works: cache `.pdb.gz` (DEM-02's "compress" satisfied literally). If not: cache plain dry `.pdb` (1.5-2 MB each, gitignored) and record the deviation **[HUMAN-APPROVAL-NEEDED]** (requirement text says "compress before caching"), or gzip via `exec` (see §5).

### 3.3 `vmd/gui/setup_tab.tcl` (DIFF-05 sub-menu)

| Seam | Lines | Change |
|------|-------|--------|
| Demo menu build | `setup_tab.tcl:153-162` — plain tk `menubutton $pd.pick` + `menu $pd.pick.menu` (the clonerep idiom, NOT ttk; ttk has no menubutton in 8.5), one `add command -label $did` per manifest key | Tier-surface the demo menu. **Recommended (SETUP-01's literal "sub-menu"): tier cascades** — Tcl 8.5 `menu add cascade -label "Easy" -menu $tiermenu` is available; 4 tier sub-menus (ordered easy → hard → challenge → very_challenging), entries labeled from the manifest: `"$category — $did"` with `-command [list ::biochemeleon::setup_tab::select_demo $did]` (keep the `[list]`-built callback, Pitfall 7, `:160`). **Simpler alternative:** keep one flat menu, tier-ordered, labels `"$did ($tier_label)"` via TIER_LABELS — v1's QComboBox choice (`09-RESEARCH-pipeline.md:444-459`). Both satisfy DIFF-05's "surfaced"; the cascade also satisfies SETUP-01's "sub-menu for demo categories" wording (REQUIREMENTS.md:20). Planner picks. |
| `select_demo` | `setup_tab.tcl:404-417` | Must branch for fetched demos: set `::biochemeleon::setup_tab::demo_id` (fully-qualified set — the parameter shadows the ns var, `:408`) + `mode` demo + `switch_page` **WITHOUT calling `load_demo`** for non-bundled sources (no molid exists pre-fetch; a cache-HIT may optionally load + `update_cap`). Show tier + source + approx size in an info label (new `ttk::label` on the demo page). Current behavior (immediate `load_demo` at `:411`) stays for bundled demos. |
| `update_cap` | `setup_tab.tcl:494-531` | **NO structural change** — it is already the cap-as-function-of-atom-count GUI wiring (`demos::atom_count` → `hider_count_cap` → spinbox `-to` + clamp, `:503-511`). For un-loaded fetched demos it no-ops (`current_molid` empty, `:502`) — fine, since large-demo caps saturate at 50 anyway. |
| Fetch page note | `setup_tab.tcl:146-151` (`ttk::label $pf.note -text "Phase 14: bundled demos only; fetch at Start (Phase 16+)"`) | Update the stale text once fetch is real. |

### 3.4 `vmd/gui/dialog.tcl` — `on_start` (warning seam + async fetch)

`on_start` flow today (`dialog.tcl:143-226`): 1. collect_state → 2. resolve target per mode (loaded `:153-167` / demo `:168-173` / fetch-stub `:174-184`) → 3. `validate_state` with `atom_count` (`:187-192`, the atom_count already computed via `demos::atom_count $molid` at `:188`) → 3.5 `pick_bridge::deactivate` (`:203`) → 4. `game::start_game` (`:209-216`) → 5-7. difficulty/raise/countdown.

| Seam | Where | Change |
|------|-------|--------|
| **>~20k-atom warning** | Between step 3 and step 3.5 (after the molid + atom count exist, before any game state) | `set natoms [::biochemeleon::demos::atom_count $molid]; if {$natoms > 20000 && ![tk_messageBox -type yesno -icon warning -parent $w -title bioCHEMeleon -message "…~$natoms atoms… continue?"]} { return }`. `tk_messageBox` is the repo's dialog primitive (7 existing call sites in this file). Abort = plain `return` (the established abort shape, `:149,165,172,181,191,215`). |
| Demo branch fetch orchestration | `dialog.tcl:168-173` | Branch on `[dict get $DEMO_MANIFEST $demo_id source]`: bundled → current `load_demo`; fetched → `demos::load_cached_demo` (hit: synchronous molid) OR cache-miss → **launch the fetch and RETURN** — the rest of on_start (steps 3-7) must run in the fetch-completion callback. This is the phase's biggest structural change: on_start needs a continuation path (e.g. `::biochemeleon::_start_after_fetch $state $molid` invoked from the download-completion callback). The repo's continuation idiom is the self-rescheduling `after` chain (`game_tab.tcl:251,267,375`; one-shot `after 1000` countdown pattern) — and `update` is banned (`game_tab.tcl:34-35`: "`update` is never called and the event…"). Tcl's `::http::geturl -command` completion is itself event-loop-driven, so the async shape fits naturally. |
| Double-load wart (pre-existing) | `setup_tab.tcl:411` + `dialog.tcl:169` | select_demo loads the demo, then on_start's demo branch loads it AGAIN (second `mol new`). Harmless for 555-3,779-atom demos; doubles cost for 19-26k-atom demos (and would double-fetch). Planner should either make `load_demo` return the existing molid when the same demo is already the live target (track last demo→molid in demos.tcl) or skip select-time loading for fetched demos (recommended — fetch-on-Start is the design anyway). |

### 3.5 Conventions to respect (all verified in source)

- **Pure layer stays pure:** manifest/TIER_LABELS/cache-name data → `setup_state.tcl`; NO `mol`/`tk` there (`setup_state.tcl:1-4`). Strip/cache/fetch mol work → `demos.tcl`; Tk (progress dialog, message boxes) → `vmd/gui/` only. demos.tcl must not grow Tk calls (it currently has zero).
- **Tcl 8.5.6:** no `lmap`/`try`/`throw`/`tailcall`/`coroutine`/`yield`/`finally` (grep gate); brace all `expr`; `catch`+`errorCode` for cleanup; `dict get` has no 3-arg default form → `_dget` helper (`setup_tab.tcl:56-59`).
- **Headless smoke pattern:** `BCHM_SMOKE_RESULT PASS=1` marker line; harness "greps the marker line, NEVER `$?` (VMD always exits 0)" (`phase14_mol_smoke.tcl:13,144-146`); full-log scan for `ERROR)`/`bad switch`; ×3 sequential runs on fresh staging. A new `vmd/smoke/phase21_*.tcl` follows this. **Network fetches must NOT be inside the automated smoke** (flake risk) — smoke tests the pure parts (manifest, TIER_LABELS, cap at large counts, cache-path helpers, Option-A strip filter) with staged fixtures; the live fetch is a human-verify checkpoint.
- **8-proc export list** (`demos.tcl:27-29`) grows with the new procs (namespace export hygiene).

---

## 4. .bcm / pure-layer schema implications

**NO schema change required.** Verified reasoning:

- `SETUP_FORMAT` stays `"biochemeleon-setup-v2"` (`setup_state.tcl:13`); `DEFAULTS` keeps its 11 keys (`setup_state.tcl:18-29`). DIFF-05 difficulty lives in `DEMO_MANIFEST` (pure data), **not** in setup state → nothing new to serialize.
- `demo_id` round-trips through the existing scalar branch (`save_setup` `demos.tcl:128-129` `puts $fh "$k $v"`; `load_setup` default case `:168` + DEFAULTS-order rebuild list `:176`). New ids (`1gzm`, `3gp6`, `sasdpg4`) are just scalar values; `validate_state`'s membership check (`setup_state.tcl:148-151`) accepts them once the manifest is extended. An offline `.bcm` with `demo_id 1gzm` loads fine (pure data); Start then fails at the fetch with the existing error-dialog path — acceptable, no schema workaround needed.
- **18-05 coordination (per brief):** `.planning/phases/18-materials-exploration/18-05-PLAN.md` defines the `.bcm` per_mat extension pattern — per_mat gets its own line family (mirroring per_rep) + `load_setup`'s rebuild list grows to `{… pdb_pool material_blending per_mat}` (18-05-PLAN.md:65). **18-05 is planned but NOT executed**: grep confirms zero `material_blending`/`per_mat` in `vmd/lib/` today, no `18-05-SUMMARY.md`, and STATE.md positions the project at 17.2. Phase 21 adds **no** setup-state keys → zero overlap with that pattern; the only conflict surface is `demos.tcl` itself (18-05 edits `save_setup`/`load_setup`, Phase 21 edits `load_demo`/`fetch_pdb` + adds procs — different procs, same file → plan ordering or disjoint waves if 18 lands concurrently).

---

## 5. Open questions for the planner

1. **HTTPS transport for MemProtMD + SASBDB — the load-bearing decision.** Tcl http (no tls, `demos.tcl:102-105`) + both servers force HTTPS (301/302 verified today) ⇒ Tcl cannot fetch the two large-demo sources. Options: (a) `exec curl.exe` (ships with Windows 10 1803+; uses the OS trust store — would also *resolve* v1's SASBDB HARICA cert debt, `PROJECT.md:90`); (b) `exec powershell -Command Invoke-WebRequest` (always present, ~1-2 s startup); (c) vendor a tls package under `vmd/3rd_party_lib/` (user-approval + Windows binary — heavy); (d) manual-download fallback (open URL, user saves into the cache dir). **[HUMAN-APPROVAL-NEEDED]** — (a)/(b) introduce an OS-tool dependency that the "only what VMD ships" constraint doesn't literally cover; the RCSB fetch tab is unaffected (plain HTTP verified). Sibling empirical probe should confirm what VMD's Tcl can/cannot do (`package require tls` expected to fail; `mol pdbload` behavior).
2. **Compression at runtime.** `mol new x.pdb.gz` support + `package require zlib` in VMD 1.9.3: UNVERIFIED (sibling probe). Determines whether DEMO-02's "compress before caching" is literally satisfiable in-script or needs an exec-based gzip / plain-file deviation **[HUMAN-APPROVAL-NEEDED if deviating]**.
3. **Strip strategy:** Option B (VMD selection-write, recommended) vs Option A (Tcl line filter) — both documented in §3.2; B is less code, A is tclsh-testable and never loads the wet molecule. Planner picks (or does A as the cache-prep step and B defensively — but doing both is redundant).
4. **on_start async restructure:** cache-miss fetch forces a continuation-passing split of on_start (§3.4). Confirm the planner wants the full continuation vs a simpler "fetch first (dialog-driven), then user re-clicks Start" two-phase UX (v1 solved this with a QTimer re-entry, option (b), `09-RESEARCH-pipeline.md:487`).
5. **1GZM dry size/atoms:** arithmetic EST ~25,974 atoms / ~2 MB — record actuals at first fetch into DATA_SOURCES.md (v1 left the same TODO, `DATA_SOURCES.md:105-106`).
6. **`mol pdbload`** exists per STACK.md:260 (UG node140) but its runtime protocol/behavior in 1.9.3 is unprobed — sibling probe; decides fetch_pdb's transport for RCSB codes.
7. **Double-load wart** (select_demo + on_start both `mol new`): fix in Phase 21 or leave for the fetch-on-Start redesign to absorb (§3.4).
8. **Phase-ordering:** ROADMAP:268 says Phase 21 depends on Phase 20 (persistence, `.bcmz` combined-PDB) — Phase 20 has no `20-*` dir/plans yet. Confirm with the orchestrator whether 21 proceeds before 20 (the DEMO-02/03/04/05 work is independent of persistence; the dependency looks soft).
9. **Demo-menu shape:** tier cascades (SETUP-01 literal "sub-menu") vs flat tier-ordered labels (§3.3) — one-line planner decision.
10. **DATA_SOURCES.md fixes:** bacteriorhodopsin→bovine rhodopsin (`:98`), optionally add VMD to §5 graphics-system note; reused v1 citations remain human-approved, the *edits* need approval **[HUMAN-APPROVAL-NEEDED]**.

---

## Sources

### Primary — live verification (today, 2026-09-25, curl from WSL)
- MemProtMD `at.pdb` 1gzm + 3gp6 (HTTP 206, real PDB bytes inspected); plain-HTTP 301→https probe; `/_ref/PDB/{1gzm,3gp6}/` 200; `/static/js/index.js` CC-BY 4.0 string re-extracted.
- SASBDB `SASDPG4_fit2_model1.pdb` (206, real PDB bytes); `/data/SASDPG4/` 200 + format grep (pdb_file only, no cif); `/aboutSASBDB/` license sentence re-extracted; plain-HTTP 302→https probe.
- RCSB `files.rcsb.org/download/{1GZM,3GP6}.pdb` (200 https; 1GZM also **200 over plain http**) + 1GZM header read (bovine rhodopsin).
- `git check-ignore -v vmd/data/demos/cache/1gzm.pdb` → `.gitignore:20` (`cache`).

### Primary — repo code (read today, line refs current)
- `vmd/lib/demos.tcl` (script_dir :26; load_demo :58-82 + source guard :65-70; fetch_pdb stub :102-108; save/load :116-181; atom_count :186-189)
- `vmd/lib/setup_state.tcl` (GAME_REPS :10; SETUP_FORMAT :13; DEFAULTS :18-29; DEMO_MANIFEST :34-40; export :45; hider_count_cap :51-59; validate_state :126-197 esp. demo_id :148-151 + cap :152-165; randomize_state bundled-only pool :270-275)
- `vmd/gui/setup_tab.tcl` (demo menu :153-162; select_demo :404-417; update_cap :494-531; fetch note :149; _dget :56-59)
- `vmd/gui/dialog.tcl` (open_dialog :49-73; on_start :143-226 — demo branch :168-173, validate+atom_count :187-192, abort shape)
- `vmd/gui/game_tab.tcl` (after-chaining idiom :251,267,375; no-`update` rule :34-35)
- `vmd/data/demos/` (6 PDBs + 2-line SOURCES.md stub); record counts grepped today
- `.gitignore` (cache rules :19-20); `vmd-ref/scripts/biocore.tcl:25,67-101` (vmdhttpcopy — Tcl-http→file precedent)

### Primary — v1 research (verified, reused)
- `.planning/phases/09-large-demo-fetch-source-attribution/09-RESEARCH-memprotmd.md` (URL decode, sizes, strip-set atom math, license extraction, 1gzm-dry TODO)
- `…/09-RESEARCH-sasbdb.md` (SASDPG4 entry, fit2_model1 trap, glycan resn census, license, strip=False)
- `…/09-RESEARCH-pipeline.md` (split API, manifest schema, 4-tier vocabulary + 9-demo tier table :425-437, display format)
- `DATA_SOURCES.md` (202 lines; §1 bundled CC0, §2 MemProtMD CC-BY 4.0, §3 SASBDB, §4 pool, §5 PyMOL; tier headings :98,108,139)
- `.planning/phases/18-materials-exploration/18-05-PLAN.md` (.bcm per_mat extension pattern :57-72; NOT yet executed)
- `.planning/REQUIREMENTS.md:20,72-75,94` (SETUP-01 sub-menu wording; DEMO-02/03/04, DIFF-05); `.planning/ROADMAP.md:249-279` (Phase 20/21 goals + SC1-4)
- `STACK.md:260` (`mol pdbload`); `vmd/AGENTS.md` (no-atom-delete, Tcl 8.5 constraints, performance budget, headless smoke contract)

### Unverified (flagged for the sibling VMD-probe researcher)
- `mol new *.pdb.gz` gzip support; `package require zlib`; `package require tls` (expected absent); `mol pdbload` protocol; VMD `water` keyword vs `SOL`; exact VMD `numatoms` per bundled demo (1znf multi-model: records 15,688 vs numatoms 424 smoke-pinned); 1gzm dry atom count/size.

**Research date:** 2026-09-25 · **Valid until:** ~2026-10-25 (academic DB URLs stable; re-verify the three download URLs + license strings if execution slips past 30 days)
