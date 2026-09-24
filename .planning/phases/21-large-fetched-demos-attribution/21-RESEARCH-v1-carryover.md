# Phase 21: Large Fetched Demos & Attribution — Research (V1 CARRYOVER angle)

**Researched:** 2026-09-25
**Domain:** v1 Phase 09 (PyMOL plugin) large-demo fetch/strip/compress/cache/attribution — what carries over to v2 (VMD 1.9.3 Tcl)
**Confidence:** HIGH (every claim below verified against v1 code + planning docs in this repo; no external claims introduced)

> Companion doc: the HOW-to-fetch-in-VMD questions (TLS/HTTPS, Tcl http package, chunking)
> are the **mechanics researcher's** scope. This doc covers **WHAT v1 did and what's reusable**:
> pipeline shape, exact processing steps, cache layout/naming, difficulty metadata model,
> attribution texts + approval status, and failure modes v1 hit.

---

## Summary

v1 Phase 09 shipped a complete, human-approved large-demo pipeline: a 9-entry manifest with a
uniform fetch-source schema, a **pure-text SOL/NA/CL strip that runs BEFORE the viewer ever
loads the file** (the ~95k-atom wet PDB never enters the viewer), a `.pdb.gz` cache written by
the viewer's native save (gzip in one step) and read natively on cache hit, a worker/main-thread
split with a modeless cancelable progress dialog, 4-tier difficulty metadata surfaced in the demo
sub-menu, and a repo-root `DATA_SOURCES.md` consolidating every citation. All 4 success criteria
were verified against the codebase AND human-approved on 2026-08-16 (09-VERIFICATION.md:4-5,50-70).

The highest-value carryovers for v2 are: (1) the **pure residue-name strip helper** (`SOL/NA/CL`,
padding-agnostic `line[17:20]` slice) — trivially portable to Tcl and even more important in v2,
since VMD 1.9.3 is slower than PyMOL on huge loads; (2) the **strip-before-load discipline**
(never let the wet file reach the viewer); (3) the **empirical strip-count self-checks**
(3gp6: 76,018 stripped = 75,789 SOL + 116 NA + 113 CL) as v2 verification targets; (4) the
**manifest schema + TIER_LABELS model** (v2's manifest currently has only 6 bundled entries with
5 keys — it needs the fetched-schema extension); and (5) **DATA_SOURCES.md verbatim reuse**
(DEMO-04 explicitly says reuse; the texts are already human-approved — only a v2 re-approval
checkpoint is needed, not re-research).

The parts that do NOT port are the **concurrency machinery**: v1's worker-thread + queue +
QTimer-drain pattern has no Tcl equivalent (Tcl is single-threaded) — v2 uses `after 0`
cooperative chunking instead (vmd/AGENTS.md:140). Likewise `.pdb.gz` gzip writing was free in
PyMOL (`cmd.save` handles it natively) but Tcl 8.5 has no zlib package — the compression step
needs a v2-specific decision (open question #1). v1's two runtime bugs (`.dry` extension dispatch
failure; SASBDB HARICA SSL gap) are documented below with their v2 analogues.

**Primary recommendation:** Carry the pipeline *shape* and *data* (strip set, counts, URLs,
cache naming, tier model, citation texts) from v1 wholesale; reimplement the *execution
machinery* (fetch, progress, compression) in Tcl-idiomatic single-threaded form per the
mechanics research.

---

## 1. v1 Pipeline (verified against code)

### 1.1 End-to-end flow

```
Start clicked, mode=demo, id=fetched (e.g. '3gp6')
  └─ load_demo(id)                       demos.py:149-197
       branches on meta.get('source','bundled')        demos.py:183
       ├─ bundled  -> cmd.load(data/demos/{cache_name})            demos.py:188-194
       └─ fetched  -> load_cached_demo(id)                         demos.py:184
            ├─ cache HIT  -> cmd.load(<cwd>/cache/<cache_name>)    demos.py:523-550
            └─ cache MISS -> return None  (SIGNAL: "caller must fetch")
  └─ _prepare_and_start sees None -> stash _pending_large_demo + _state
       -> _resolve_large_demo(id) -> return (None,None,[]) SILENTLY   __init__.py:332-334
  └─ _resolve_large_demo                                __init__.py:545-677
       defensive re-check load_cached_demo (574)
       QProgressDialog: NonModal .show(), setAutoClose(False),
         setAutoReset(False), setMinimumDuration(500)      __init__.py:579-586
       queue.Queue + threading.Event; progress.canceled -> cancel.set  (588-590)
       daemon Thread worker = download_large_demo(id, tmp_path, q, cancel) (593-597)
       recursive QTimer.singleShot(100, drain) — drain polls queue      (601-676)
  └─ WORKER (stdlib only, ZERO cmd.*, ZERO viewer calls)  demos.py:358-419
       makedirs(<cwd>/cache/)                            demos.py:399-401
       _urlopen_with_ssl_fallback(url, 60, queue)        demos.py:402   (60s timeout)
       read 64KB blocks; cancel check per block          demos.py:407-410
       posts ('progress',pct) / ('done',) / ('error',msg) / ('canceled',)  407-419
  └─ DRAIN 'done' branch (MAIN thread)                   __init__.py:614-648
       finalize_large_demo(id, tmp_path)                 __init__.py:620
       cleanup_temp(tmp_path)                            __init__.py:621
       finalize-None guard -> QMessageBox "Fetch failed" (623-633)
       success -> _continue_after_large_demo_fetch(obj, stashed_state)
                  + tab switch + countdown + re-enable Export        (639-647)
  └─ finalize_large_demo (MAIN thread, cmd.*)            demos.py:422-520
       if meta['strip'] and source=='memprotmd':         demos.py:476
           read .raw text -> strip_resn_from_pdb(raw, {'SOL','NA','CL'})  478-480
           write <raw>.dry -> cmd.load the .dry          481-484
       else: cmd.load the .raw as-is (SASBDB strip=False)  488
       cmd.load(..., format='pdb')  ← explicit format (see Pitfall F1)  501
       makedirs(cache_dir); cmd.save(<cache>/<cache_name>)  [.pdb.gz]   506-513
       cache-write failure NON-FATAL (object already loaded)            514-515
       cleanup .dry                                                     518-519
```

**The contract that makes it work:** `load_demo` returns `None` for a fetched cache miss — the
GUI layer treats that as "trigger async fetch", never as an error (demos.py:156-170 docstring;
`__init__.py:189-198` pending flags). Every failure path returns None / posts an event; nothing
raises to the GUI.

### 1.2 The worker (download) details worth porting as *parameters*

| Detail | v1 value | Evidence |
|---|---|---|
| Timeout | 60 s (flagged "may be tight" for 7.5–9.3 MB files; unresolved) | demos.py:402; 09-03-SUMMARY:195 |
| Read granularity | 64 KB blocks; progress = `received*100//total` when Content-Length known | demos.py:403-416 |
| Cancellation | `threading.Event` checked between blocks; `progress.canceled` signal wired to it | demos.py:407-409; `__init__.py:590` |
| User-Agent | `bioCHEMeleon/1.0` header set because "some hosts (notably SASBDB) may block the bare default urllib UA" | demos.py:333-334, 387 |
| Temp path | deterministic `<cwd>/cache/<id>.raw` (NOT tempfile) — survives an interrupted fetch for inspection | demos.py:260-287 |
| Temp cleanup | idempotent, best-effort, silent on missing/OSError | demos.py:290-301 |
| Queue events | `('progress',pct)` / `('done',)` / `('error',msg)` / `('canceled',)` / `('warning',msg)` | demos.py:371-374, 350-354 |

**v2 note:** the worker/queue/thread machinery does NOT port (Tcl single-threaded). The
*parameters* (timeout, block size, UA header, deterministic temp path, idempotent cleanup,
event vocabulary) carry over as design constants for the Tcl fetch implementation.

### 1.3 SSL fallback (v1 tech debt — noted for possible porting in STATE.md)

`_urlopen_with_ssl_fallback` (demos.py:304-355):
- First attempt: default **verifying** context.
- On failure where `isinstance(urllib_error.reason, ssl.SSLError)` → retry with
  `check_hostname=False` / `verify_mode=CERT_NONE` (demos.py:347-349).
- Posts `('warning', msg)` on fallback ("Certificate verification unavailable for this host;
  retrying without verification (public structure file).") (demos.py:350-354).
- **Exception-shape lesson (load-bearing):** `urlopen` does NOT raise a bare `ssl.SSLError` for
  cert-verification failure — it wraps it as `URLError(reason=SSLCertVerificationError(...))`
  (demos.py:315-321, verified empirically in v1). A bare `except ssl.SSLError` is kept only as a
  defensive net (342-344). Non-SSL URLErrors (404/DNS/timeout) must be re-raised, not retried.

**v2 status:** v2 Tcl has NO tls package at all (vmd/lib/demos.tcl:105-107 stub; STATE.md 14-02),
so this fallback cannot port as-is — the whole HTTPS mechanism is the mechanics researcher's
question. If v2 ends up shelling out to an HTTPS-capable tool, the *concept* (verify first,
downgrade only on cert-verify failure for known academic public-file hosts, warn the user)
is the v1-approved precedent.

---

## 2. Strip / Compress specifics (verified)

### 2.1 What v1 removed and what it KEPT

**Removed — exactly 3 residue names, ATOM lines only** (`setup_state.py:193`):

```python
STRIP_RESN_MEMPROTMD = {'SOL', 'NA', 'CL'}   # GROMACS water + Na+/Cl- counter-ions
```

- Filter targets ONLY lines starting with `ATOM` (`setup_state.py:223`). All non-ATOM records —
  TITLE, CRYST1, MODEL, TER, ENDMDL, END, REMARK, **HETATM** — are preserved unconditionally
  (`setup_state.py:203-205`).
- Residue name read from PDB columns 18–20 (`line[17:20]`) then `.strip()`-ed → padding-agnostic
  (`'NA '`, `' NA'`, `'NA'` all match) (`setup_state.py:224`).
- **Why not a `hetatm`-keyed or selector-based strip:** MemProtMD records EVERYTHING — protein,
  lipids, water, ions — as ATOM records with **0 HETATM** (09-RESEARCH-memprotmd.md:213,
  verified by live-file diff). A hetatm filter would strip nothing; a `solvent`/`inorganic`
  selector strip was rejected because the C-level classification of ATOM-record ions could not
  be verified from Python source (09-RESEARCH-memprotmd.md:244-247). The explicit resn filter is
  deterministic and "can never drop a DPP lipid or a protein residue" (`setup_state.py:210-214`).

**Deliberately KEPT (this is the blending-fidelity contract):**
- **DPP / DPPC membrane lipids** — organic, not in the strip set; survive by construction
  (demos.py:427-433; `setup_state.py:212-214`).
- **The protein coordinates, unaltered** — MemProtMD atomistic embedding preserved as-is
  (DATA_SOURCES.md:118-121).
- **All HETATM records** — irrelevant for MemProtMD (0 HETATM) but load-bearing for SASBDB.

### 2.2 Empirical strip counts (v2's verification targets)

| Entry | Wet bytes | Wet atoms | Dry atoms | Strip math | Evidence |
|---|---|---|---|---|---|
| 3gp6 | 7,524,042 (7.5 MB) | 95,239 | 19,221 | 95,239−19,221 = 76,018 = SOL 75,789 + NA 116 + CL 113 ✓ | DATA_SOURCES.md:116,123-125; 09-RESEARCH-memprotmd.md:96,230 |
| 1gzm | 9,314,128 (9.3 MB) | 117,898 | **UNMEASURED** | same resn set present in wet: SOL 91,638 + NA 147 + CL 139 | DATA_SOURCES.md:104-106,125; 09-RESEARCH-memprotmd.md:97 |

The 1gzm dry size was never recorded — DATA_SOURCES.md:105-106 still says "to be verified at
execute time" even after the phase passed (the GUI checkpoint verified function, not byte
counts). **v2 should record it at execute time** (open question #2).

### 2.3 SASBDB: strip=False (over-strip CAUTION — highest-risk data rule in this phase)

- `sasdpg4` manifest entry: `'strip': False` (`setup_state.py:44-47`). `finalize_large_demo`
  gates the strip on **BOTH** `meta['strip']` **AND** `source=='memprotmd'` (demos.py:476) —
  the downloaded file is loaded as-is.
- Why: the model has **zero water, zero ions** — every one of the **2,601 HETATM records is a
  glycan atom** across 8 residue names (NAG, MAN, BMA, NAN, GLB, AFL, NGA, GLA); 4,123 atoms
  total = 1,522 protein + 2,601 glycan (DATA_SOURCES.md:147-152,167-174; verified by grep in
  09-RESEARCH-sasbdb.md, "0 matches for solvent records").
- **CAUTION (quote):** "do NOT over-strip: a `cmd.remove hetatm` would delete the 2601 glycan
  atoms and silently fail DEMO-03" (DATA_SOURCES.md:172-174; 09-RESEARCH-sasbdb.md:257-259).
  A blanket hetatm removal turns this into a protein-only demo *silently*.
- Related trap (from research, load-bearing URL constant): fetch **`SASDPG4_fit2_model1.pdb`**
  specifically — `fit1_model1` (listed first on the entry page) is **protein-only with NO
  glycan** and would silently fail DEMO-03 (09-RESEARCH-sasbdb.md:97; DATA_SOURCES.md:149-152).

### 2.4 Compression (v1 mechanism + observed sizes)

- Mechanism: `cmd.save('<cache>/<id>.pdb.gz', obj)` — PyMOL's save opens `gzip.open` when the
  filename ends in `.gz`, one call writes the gzipped PDB (demos.py:504-513; exporting.py:912
  per docstring). `cmd.load` reads `.pdb.gz` natively via gzip-magic detection
  (demos.py:533-535, internal.py:278-308 per docstring). **No stdlib gzip step, no manual
  decompress** — the compression is a free side effect of the save path.
- Observed sizes (3gp6): dry 1,518,620 bytes (1.5 MB) → compressed **231,087 bytes (~231 KB,
  ~15%)** (DATA_SOURCES.md:116; 09-RESEARCH-memprotmd.md:96).
- Load-time impact: **not measured in v1** — no millisecond numbers recorded anywhere in the
  Phase 9 docs. Qualitative evidence only: cache-hit loads were synchronous and instant-feeling
  (demos.py:529-531 "A cache hit is synchronous (no dialog) and offline"); the wet file never
  touched the viewer so the only large load was the ~19k-atom dry PDB.

**v2 gap:** Tcl 8.5 has no zlib package, so "write gzip from Tcl" is not free like `cmd.save`
was. Whether VMD's Tcl build exposes zlib, or v2 caches plain `.pdb` (1.5–2 MB is tolerable), or
VMD's own PDB reader can be fed something else — is **open question #1** for the mechanics
research. ROADMAP SC1 says "compress" so the planner must resolve this deliberately, not by
silently dropping the step.

---

## 3. Cache design (verified)

### 3.1 Layout & naming (final v1 state)

| Item | Value | Evidence |
|---|---|---|
| Cache dir | `<cwd>/cache/` — single FLAT dir (`os.path.join(os.getcwd(), 'cache')`) | demos.py:225 |
| Temp download | `<cwd>/cache/<demo_id>.raw` (same dir, co-located) | demos.py:287 |
| Strip intermediate | `<raw path>.dry` (`3gp6.raw.dry`) | demos.py:481 |
| Cached artifact names | `1gzm.pdb.gz`, `3gp6.pdb.gz`, `SASDPG4_fit2_model1.pdb.gz` (from manifest `cache_name`) | setup_state.py:47,52,56 |
| Format | gzipped PDB written by `cmd.save`, read natively by `cmd.load` | demos.py:504-513, 533-535 |
| Dir creation | auto-created in BOTH worker (parent makedirs, demos.py:399-401) and finalize (makedirs, demos.py:507-510) — a download never fails on missing parent (the original Pitfall E failure) | demos.py:396-401 |

### 3.2 Layout history (3 relocations — avoid re-litigating)

1. Original research: `tmp/phase9-demos/cache/` repo-relative (09-RESEARCH-pipeline.md:296-299).
2. quick-003: relocated to `<cwd>/tmp/phase9-demos/cache/` for `cmd.fetch` parity (installed-
   plugin Pitfall E).
3. quick-004: **flattened to `<cwd>/cache/`** — one dir for transient `.raw`/`.dry` AND
   persistent `.pdb.gz` (.planning/quick/004-flatten-phase9-demo-cache-to-cache-dir/, must_haves).

**v2 note:** v2's ROADMAP SC1 chooses a **fourth** location — `data/demos/cache/` (script-
relative, like v2's bundled-demo path at vmd/lib/demos.tcl:75). This is *better* than v1's cwd
layout (works regardless of launch cwd; no installed-plugin Pitfall E class at all) and is a
deliberate v2 decision — keep it, don't port the cwd logic.

### 3.3 Cache-hit logic & invalidation

- Hit test: `is_cached(id)` = `os.path.exists(cache_path)` — **existence only**. No checksum,
  timestamp, size check, or version tag. No explicit invalidation mechanism (demos.py:247-257, 542-544).
- **Self-healing property:** a corrupt/partial cached file fails `cmd.load` → `load_cached_demo`
  returns None → treated as a cache miss → next attempt re-downloads (demos.py:546-550; the
  same None flows through `load_demo`'s branch into the fetch orchestration). So "invalidation"
  is emergent, not implemented.
- Cache-write failure is **non-fatal**: the object is already loaded; success returns the obj
  name even if `cmd.save` fails (demos.py:513-515). The cache is a performance optimization,
  never a correctness requirement.
- Cache-miss-as-None signaling: `load_demo` returns None on fetched miss (demos.py:183-184) —
  the caller distinguishes "must fetch" from "load failed" via the pending-flags stash
  (`__init__.py:332-334`), not via exceptions.

---

## 4. Difficulty metadata model (DIFF-05)

### 4.1 The exact 4-tier model

- **Storage:** identifier-safe keys in each manifest entry's `difficulty` field —
  `easy` / `hard` / `challenge` / `very_challenging` (no spaces: dict-key + grep friendly).
- **Display map** (`TIER_LABELS`, `setup_state.py:65-70`):

```python
TIER_LABELS = {
    'easy': 'Easy',
    'hard': 'Hard',
    'challenge': 'Challenge',
    'very_challenging': 'Very challenging',
}
```

The manifest stores keys; only the GUI maps through `TIER_LABELS` — single source of the
display vocabulary, exactly matching the SC's literal labels.

### 4.2 Tier-assignment criteria (what mapped each demo)

Atom count + visualization complexity — NOT atom count alone (09-RESEARCH-pipeline.md:442-452):

| Demo | Atoms | Tier | Rationale (from research) |
|---|---|---|---|
| 1znf | 212 | easy | zinc finger |
| 5e54 | — | easy | riboswitch aptamer |
| 1k8p | 428 | easy | G-quadruplex |
| 1xdn | 2,095 | hard | RNA ligase |
| 2qbz | 3,263 | hard | M-Box riboswitch |
| 4wb3 | 3,779 | hard | protein/NA hybrid; **was `'mixed'` — Phase 2 deferral resolved to `hard`** |
| sasdpg4 | 4,123 | **challenge** | new complexity axis: **glycan visualization** (not just size) |
| 1gzm | 19k+ dry / 117,898 wet | very_challenging | 7-TM membrane protein + DPPC bilayer |
| 3gp6 | 19,221 dry / 95,239 wet | very_challenging | beta-barrel + full DPPC membrane, 100k+ wet atoms |

Result: 3 easy + 3 hard + 1 challenge + 2 very_challenging = 9 demos, 4 tiers.
(Note: v1's research table describes 1gzm as "bacteriorhodopsin" — see §6.2 for why that
descriptor is wrong and needs human approval to fix.)

### 4.3 How the UI surfaced it (v1)

- **Flat QComboBox kept** (9 items < the 15-item QTreeWidget threshold from Phase 2 research)
  (09-RESEARCH-pipeline.md:454-461; gui_setup.py:170-171).
- Display string: `"{category} — {id} ({tier})"` e.g. `"Membrane protein — 3gp6 (Very challenging)"`
  (gui_setup.py:172-176).
- `.title()` fallback for any unmapped tier value, defensively (gui_setup.py:173).
- **Manifest tier-ordered** (easy → hard → challenge → very_challenging) so the combo shows a
  natural difficulty progression — the order IS the UI feature (setup_state.py:35-57;
  09-01-SUMMARY key-decisions).
- Tooltip: "Pick a bundled demo molecule. Tier (Easy → Very challenging) is shown in the name."
  (gui_setup.py:177-179).
- `insertSeparator` between tier groups was considered and **NOT done** (nice-to-have,
  09-RESEARCH-pipeline.md:464).
- Attribution did NOT surface in the GUI — only in docs (DATA_SOURCES.md) + manifest `citation`
  cross-ref keys. The SCs never required in-GUI citations.

### 4.4 v2 surface today (the delta Phase 21 fills)

- v2 `DEMO_MANIFEST` (vmd/lib/setup_state.tcl:34-41): **6 bundled entries, 5 keys** —
  `category type difficulty source cache_name`. Missing vs v1 schema: `source_id`,
  `fetch_url`, `citation`, `strip` — and the 3 fetched entries entirely.
- v2 difficulty keys already exist on the bundled 6 (`easy`/`hard`) and match v1 values.
- v2 demo UI: ttk menubutton + cascade menu built from the manifest (vmd/gui/setup_tab.tcl:104,
  127, 153); a Phase-14 placeholder note at line 149 ("bundled demos only; fetch at Start")
  must be updated. The v1 display format + tier-ordered manifest + label map port directly
  (Tcl: `array`/`dict` TIER_LABELS + `string totitle` fallback).

---

## 5. Attribution inventory (exact approved texts + status)

Single source of truth: repo-root **`DATA_SOURCES.md`** (202 lines, 5 sections; created Phase 9
plan 09-04, commit 3415d88). `pymol/biochemeleon/data/demos/SOURCES.md` was reduced to a 2-line
stub pointer to it (09-04-SUMMARY:93) — and **v2 already reuses the same stub**
(vmd/data/demos/SOURCES.md is the identical 2-line pointer, verified). Manifest `citation`
fields (`'1GZM'`, `'SASDPG4'`, …) are short cross-ref keys into DATA_SOURCES.md sections, not
full citations (setup_state.py:36-56; 09-01-SUMMARY key-decisions).

### 5.1 MemProtMD (DEMO-02) — license CC-BY 4.0; attribution REQUIRED

Verbatim from DATA_SOURCES.md:75-96 (human-approved 2026-08-16, see §5.5):

> The membrane coordinates (DPPC bilayer) and the atomistic embedding are derived from
> MemProtMD and licensed under the Creative Commons Attribution 4.0 International License
> (https://creativecommons.org/licenses/by/4.0/). Attribution required:
>
>   Newport TD, Sansom MSP, Stansfeld PJ. The MemProtMD database: a resource for
>   membrane-embedded protein structures and their lipid interactions. Nucleic
>   Acids Res. 2019;47(D1):D390-D397. DOI: 10.1093/nar/gky1047
>
>   Stansfeld PJ, Goose JE, Caffrey M, Carpenter EP, Parker JL, Newstead S,
>   Sansom MS. MemProtMD: Automated Insertion of Membrane Protein Structures into
>   Explicit Lipid Membranes. Structure. 2015;23(7):1350-1361.
>   DOI: 10.1016/j.str.2015.05.006
>
> The underlying protein structures are from the RCSB PDB (CC0 1.0):
>
>   1GZM — Bovine rhodopsin. Li J, Edwards P, Burghammer M, Villa C, Schertler GFX.
>     J Mol Biol 343:1409 (2004). DOI: 10.1016/j.jmb.2004.08.090. PDB DOI:
>     10.2210/pdb1gzm/pdb
>   3GP6 — PagP. Cuesta-Seijo JA, Neale C, Khan MA, Moktar J, Tran CD, Bishop RE,
>     Pomes R, Prive GG. Structure 18:1210-1219 (2010).
>     DOI: 10.1016/j.str.2010.06.014. PDB DOI: 10.2210/pdb3gp6/pdb

- License verification provenance: CC-BY 4.0 string "verified 2026-08-14 from the site JS
  bundle … the license string 'Licensed using a Creative Commons Attribution 4.0 International
  License' appears in the download-panel component" (DATA_SOURCES.md:130-133). CC-BY 4.0
  explicitly **permits bundling the processed/derived PDB with attribution** (DATA_SOURCES.md:133).
- Fetch URLs (verified live, HTTP 200, real PDB content, at research time):
  `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/{id}_default_dppc/files/structures/at.pdb`
  (DATA_SOURCES.md:102,113; manifest setup_state.py:51,55; live-fetch evidence
  09-RESEARCH-memprotmd.md:493). Entry pages: `https://memprotmd.bioch.ox.ac.uk/_ref/PDB/1gzm/`
  (DATA_SOURCES.md:103,114).
- History note: the FIRST researched MemProtMD DOI (`10.1038/s41592-018-0220-9`) **404'd** and
  was replaced by the two citations above across all planning records
  (09-04-SUMMARY:74, key-decisions). Also `oxy.ac.uk` → `ox.ac.uk` domain typo was fixed
  (09-04-SUMMARY:75). Both wrong values are verified absent from current docs
  (09-VERIFICATION.md:96). **Do not re-introduce them.**

### 5.2 SASBDB (DEMO-03) — license: free use with attribution requested

Verbatim from DATA_SOURCES.md:139-165:

> ### SASDPG4 — Alpha-1-acid glycoprotein 1 (Challenge)
> - Source database: SASBDB (Small Angle Scattering Biological Data Bank)
>   - Entry: https://www.sasbdb.org/data/SASDPG4/
>   - SASBDB ID: SASDPG4
>   - License: "free of all copyright restrictions and made fully and freely
>     available for both non-commercial and commercial use. Users of the data
>     should attribute the original authors." (https://www.sasbdb.org/aboutSASBDB/)
>     Attribution requested.
> - Molecule: Alpha-1-acid glycoprotein 1 (AGP, orosomucoid), Homo sapiens,
>   UniProt P02763 (residues 19-183)
> - Structure file used: SASDPG4_fit2_model1.pdb (a glycosylated hybrid model from
>   the SAXS-fit ensemble; 4123 atoms = 1522 protein + 2601 glycan HETATM across
>   8 carbohydrate residue names: NAG, MAN, BMA, NAN, GLB, AFL, NGA, GLA). Built
>   with SWISS-MODEL + glycan modeling; refined against SAXS data at 283 K.
> - Fetch URL: https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb
> - Primary publication:
>   Kalidas N, Peddada N, Pandey K, Ashish. "SAXS data based glycosylated models
>   of human alpha-1-acid glycorprotein, a key player in health, disease and drug
>   circulation." J Biomol Struct Dyn 44(5):2709-2723 (2025).
>   DOI: 10.1080/07391102.2025.2475244. PMID 40056387.
>   (Note: the published title's "glycorprotein" is a typo in the published title —
>   reproduced as-is per the publisher landing page.)
> - Database citation:
>   Kikhney AG, Borges CR, Molodenskiy DS, Jeffries CM, Svergun DI. "SASBDB:
>   Towards an automatically curated and validated repository for biological
>   scattering data." Protein Science 29(1):66-75 (2020).
>   DOI: 10.1002/pro.3731.

Fidelity rules v1 established: the "glycorprotein" typo is reproduced **verbatim on purpose**
(09-04-SUMMARY:47 — citation fidelity to the published record); the `_fit2_model1` suffix is a
**load-bearing constant** (fit1 has no glycan → silent DEMO-03 failure).

### 5.3 Bundled 6 + PDB_POOL + PyMOL (context — already reused by v2)

- 6 bundled RCSB PDB demos: CC0 1.0, per-entry PDB ID + DOI + title + authors + publication in
  DATA_SOURCES.md §1 (lines 15-69). v2 already ships these PDBs (vmd/data/demos/) and the stub.
- PDB_POOL blanket CC0; PyMOL/Schrödinger §5 — v2 will cite VMD analogues separately (out of
  scope here; the mechanics/other researchers own VMD citations).

### 5.4 Approval status per item

| Item | Status | Evidence |
|---|---|---|
| MemProtMD CC-BY 4.0 license + both citations (Newport 2019, Stansfeld 2015) | **human-approved 2026-08-16** (SC3 checkpoint) | 09-04-SUMMARY:78; 09-VERIFICATION.md:65 |
| 1GZM / 3GP6 PDB citations + DOIs | **human-approved 2026-08-16** (SC3) | 09-VERIFICATION.md:62-65 |
| SASBDB license + Kalidas 2025 + Kikhney 2020 | **human-approved 2026-08-16** (SC3) | 09-VERIFICATION.md:62-65 |
| SC1 fetch behavior, SC2 glycan fetch, SC4 tier labels | **human-approved 2026-08-16** (SC1/SC2/SC4 checkpoints) | 09-03-SUMMARY:92; 09-VERIFICATION.md:51-60,66-70 |
| Reusing these texts in v2 docs/code | **[HUMAN-APPROVAL-NEEDED]** — per root AGENTS.md "ALL claims and citations MUST be verified … and explicitly approved by a human"; DEMO-04 says reuse + re-verify MemProtMD per-entry license before bundling. Texts are unchanged from v1's approval, so this is a cheap re-approval checkpoint in the v2 phase (present the same DATA_SOURCES.md sections), NOT re-research. | root AGENTS.md; REQUIREMENTS.md:75 |
| Fixing the §2 heading inconsistency (see §6.2) | **[HUMAN-APPROVAL-NEEDED]** | below |

### 5.5 DEMO-04's "verify MemProtMD per-entry license before bundling" — v1 precedent

v1 satisfied this via the human-verify checkpoint being the formal gate ("the checkpoint
approval is the formal record of license verification before bundling", 09-04-SUMMARY key-
decisions). For v2: same pattern — a `checkpoint:human-verify` task re-presenting the §2/§3
license blocks + confirming the MemProtMD site still serves the same license string is the
cheapest compliant gate.

---

## 6. v1 Failure modes & pitfalls (all hit in practice)

### F1. Unrecognized file extension → silent load failure (`.dry` / `.raw`) — commit d54f22e
- **What happened:** `finalize_large_demo` wrote the stripped file as `<raw>.dry` and called
  `cmd.load` without a format kwarg; PyMOL's `filename_to_format` dispatches by extension,
  `.dry` is unregistered → `CmdException('unsupported file type: dry')` → swallowed by
  try/except → finalize returned None → user saw "Load failed" and orphaned `.dry` files
  persisted (cleanup ran after the failed load) (09-03-SUMMARY:144; demos.py:449-459).
- **Fix:** explicit `format='pdb'` on the shared `cmd.load` — one fix covered both the `.dry`
  (MemProtMD) and latent `.raw` (SASBDB first-fetch) paths (09-03-SUMMARY:145-147).
- **v2 analogue:** v2 already avoids this class — `mol new $path type pdb` passes the type
  explicitly (vmd/lib/demos.tcl:85). **Rule for v2: ALWAYS pass `-type pdb` when loading any
  temp/intermediate file, never rely on extension detection.**

### F2. SASBDB SSL HARICA certificate gap on Windows — commit e0f8302
- **What happened:** sasbdb.org's chain (HARICA RootCA 2015 → GEANT TLS RSA 1 → sasbdb.org)
  verified from WSL but failed on Windows conda Python 3.9.13 (certifi 2023.07.22 lacks the
  HARICA root) → `URLError(SSLCertVerificationError)` on the user's first real fetch
  (09-03-SUMMARY:150-153). MemProtMD worked (its root CA IS in certifi) — a host-dependent,
  platform-dependent failure that WSL testing could not catch.
- **Fix:** `_urlopen_with_ssl_fallback` (§1.3). Lesson: the exception shape is
  `URLError(reason=SSLError)`, not a bare `SSLError`.
- **v2 analogue:** v2's HTTPS problem is more fundamental (no tls package at all). Whatever
  mechanism Phase 21 picks, expect **per-host, per-platform cert behavior differences** and
  test BOTH MemProtMD and SASBDB from the Windows side. A v2 "verify, downgrade with warning"
  precedent exists in v1's approved tradeoff (09-03-SUMMARY:125).

### F3. finalize-None guard (crash-class bug caught pre-checkpoint) — commit 925cb56
- A `None` from finalize flowing into the continuation would crash the drain with a stack
  trace; the guard turned it into a readable "Fetch failed" QMessageBox + pending-flag cleanup
  (09-03-SUMMARY:134-140). **This guard is what made F1 diagnosable.** v2: wrap the
  fetch→load step so ANY failure surfaces as a user-readable dialog, never a raw Tcl error
  leaking into the console (v2 convention: procs `return -code error`, GUI catches —
  vmd/lib/demos.tcl:55-56 docstring).

### F4. Cache path Pitfall E (installed plugin) — resolved by 2 relocations
- Repo-relative `tmp/` broke for an installed plugin (09-RESEARCH-pipeline.md:214-219).
- v1's final answer: cwd-based `<cwd>/cache/` (quick-003 + quick-004). v2's answer
  (`data/demos/cache/` script-relative) is strictly better — no cwd dependence at all.

### F5. Pitfall C — strip ≠ hider-cleanup filter confusion (documentation discipline)
- The pre-game DEMO-02 water/salt strip is a deliberate data transform, NOT the game-time
  hider cleanup (which must use sentinel-only filters). v1 documented the distinction in the
  finalize docstring (demos.py:427-433). v2 has the same two concepts (hiders.tcl sentinel
  rules) — keep the distinction explicit in the v2 strip proc's comments.

### F6. Pitfall D — selector-based ion strip can remove structural ions
- `inorganic`-style selectors match catalytic/structural metals (ZN/CA/MG), not just bulk salt
  (09-RESEARCH-pipeline.md:216-221). v1's pure resn filter ({SOL,NA,CL} only) sidesteps this
  **by construction**. If v2 implements the strip as a VMD atomselect deletion instead of text
  filtering, this pitfall re-appears — carry the resn-list approach instead (verdict table #4).

### F7. Native alt-confs in the large demos break cartoon-segment hiders (out-of-phase discovery)
- During the 09-03 checkpoint: 1gzm/3gp6/sasdpg4 carry native alternate conformations; the
  cartoon-segment hider's anchor selection matched twice → `AssertionError: expected 1 anchor
  id, got [25, 25]` (09-03-SUMMARY:158-165; .planning/debug/pending/phase11-membrane-…md).
  Sphere hiders always worked; SC1 only required fetch→start completes.
- v1 later fixed it (quick-009-fix-altconf-anchor-duplicate). **v2 relevance:** Phase 21's demos
  are exactly the alt-conf-heavy molecules; v2's splice.tcl already handles altloc columns in
  anchors (vmd/lib/splice.tcl:258 mentions "altloc 17 (space)") — but Phase 21 testing MUST
  include start-a-game on all three large demos to confirm no v2 analogue of this bug.
  Phase 21 itself only owes fetch→start (ROADMAP SC1-2), same as v1.

### F8. Smaller concerns v1 documented but did NOT fix (carry as v2 considerations)
- 60 s download timeout "may be tight" for 7.5–9.3 MB wet files (09-03-SUMMARY:195) — consider
  longer/configurable in v2.
- SASBDB may block bare default UA strings (LOW confidence, defensive UA set anyway,
  09-RESEARCH-sasbdb.md:214) — set a UA header in v2 whatever the mechanism.
- SSL fallback is a standing security tradeoff; hardening (bundle HARICA root) was declared out
  of scope (09-03-SUMMARY:194).

---

## 7. Carryover verdict table (per v1 capability)

| # | v1 capability | v1 evidence | Verdict for v2 | Effort hint |
|---|---|---|---|---|
| 1 | 9-entry manifest, uniform fetch-source schema (`source`/`source_id`/`fetch_url`/`cache_name`/`citation`/`strip`) | setup_state.py:34-57 | **Carry data as-is** — extend v2 `DEMO_MANIFEST` (currently 6 bundled × 5 keys, setup_state.tcl:34-41) with the 3 fetched entries + 4 new keys | Small — dict-create edits; keep lowercase `source` vocabulary (`bundled`/`memprotmd`/`sasbdb`) |
| 2 | `TIER_LABELS` 4-tier display map | setup_state.py:65-70 | **Carry** — trivial Tcl dict/array | Tiny |
| 3 | Tier-ordered manifest + `"{category} — {id} ({tier})"` display + `.title()` fallback | gui_setup.py:172-179; setup_state.py:35-57 | **Carry** into setup_tab.tcl demo menu (menubutton cascade, setup_tab.tcl:127,153); tier ordering = dict insertion order (Tcl 8.5 dicts preserve insertion order — verified by v2's existing ordered manifest) | Small |
| 4 | `STRIP_RESN_MEMPROTMD` {'SOL','NA','CL'} + pure `strip_resn_from_pdb` (ATOM-only, `line[17:20].strip()`, padding-agnostic) | setup_state.py:193,196-228 | **Carry — highest-value port.** Pure Tcl re-write: `string range $line 17 19` + `string trim`; keep ATOM-only + unconditional non-ATOM preservation | Small (~20-line proc + tcltest suite mirroring v1's padding/preserve tests) |
| 5 | Strip BEFORE viewer load (wet 95k-atom file never enters viewer) | demos.py:474-486; 09-RESEARCH-memprotmd.md:247-282 | **Carry as invariant** — even more important in VMD (100k+ atom `mol new` is the expensive path; vmd/AGENTS.md:137 budget) | Design rule, free |
| 6 | Strip gating: `strip==1 && source eq "memprotmd"` (SASBDB loads as-is) | demos.py:476,488 | **Carry** — same boolean gate in Tcl | Tiny |
| 7 | Empirical strip-count self-checks (3gp6: 76,018 = 75,789+116+113; dry 19,221) as verification targets | DATA_SOURCES.md:123-125 | **Carry** — encode as v2 smoke assertions (atom counts post-strip) | Tiny |
| 8 | Cache layout: single flat dir, `.raw` temp + `.dry` intermediate + `.pdb.gz` cache co-located; auto-mkdir in both writer paths | demos.py:203-301,399-401,506-510 | **Adapt** — keep flat + co-located + auto-mkdir, but use v2's script-relative `data/demos/cache/` (ROADMAP SC1), NOT v1's cwd base | Small |
| 9 | Cache naming: `<cache_name>` from manifest (`1gzm.pdb.gz`…); deterministic temp `<id>.raw`; idempotent cleanup | setup_state.py:47,52,56; demos.py:287,290-301 | **Carry** naming; **compression suffix TBD** (open question #1 — Tcl 8.5 has no zlib; may become plain `.pdb`) | Small |
| 10 | Cache-hit = existence check; corrupt cache self-heals via re-download; cache-write failure non-fatal | demos.py:247-257,513-515,542-550 | **Carry semantics** (existence-only, self-healing, non-fatal write) | Tiny |
| 11 | Cache-miss-as-None/error signaling contract (loader returns "must fetch" vs GUI owns fetch UI) | demos.py:156-170; `__init__.py:189-198,332-334` | **Adapt to v2 conventions** — v2 procs use `return -code error` + GUI catch (demos.tcl:55-56,69-74); branch `load_demo` on `source` (the branch point is already stubbed at demos.tcl:66-74 with an explicit Phase-21 pointer) | Small |
| 12 | Explicit-format load (`format='pdb'`) for temp/intermediate files | demos.py:449-459,501 | **Already v2 pattern** — `mol new $path type pdb`; just apply it to temp files too | Free (rule) |
| 13 | Worker thread + queue + QTimer drain + modeless cancelable QProgressDialog | `__init__.py:545-677`; demos.py:358-419 | **Does NOT port (no threads in Tcl).** Re-implement single-threaded: chunked download via `after`/fileevent + ttk::progressbar + cancel flag — mechanics researcher's design. Keep v1's event vocabulary (`progress`/`done`/`error`/`canceled`/`warning`) as the state-machine shape | Medium — this is Phase 21's core new machinery |
| 14 | SSL fallback (verify-first, CERT_NONE retry, warning event) | demos.py:304-355 | **Cannot port as-is (no tls).** Concept approved as v1 precedent; actual HTTPS mechanism = open question #3 (mechanics) | TBD by mechanics research |
| 15 | Download parameters: 60 s timeout (flagged tight), 64 KB blocks, Content-Length progress %, UA header, cancel-per-block | demos.py:402-416,333-334 | **Carry as parameters** into whatever Tcl fetch mechanism is chosen (raise timeout; keep UA) | Tiny |
| 16 | Pending-state stash + "drain owns continuation + all error/cancel UI" + re-entrancy guard (`_pending_large_demo`) | `__init__.py:189-198,250-257,332-334,545-677` | **Carry the concept** in Tcl form: a single "fetch in progress" flag; Start/Export re-entry suppressed while set; the fetch completion callback owns tab-switch + countdown continuation | Small-medium (GUI glue) |
| 17 | Export-button async guard (disable while fetch possible; re-enable after success) | `__init__.py:210-220,564-585` | **Carry concept** — prevent any second action that would re-enter the fetch continuation | Small |
| 18 | DATA_SOURCES.md repo-root attribution + SOURCES.md stub | DATA_SOURCES.md (whole); vmd/data/demos/SOURCES.md stub already present | **Carry verbatim (DEMO-04).** v2 docs reference the same repo-root file; add a v2-facing processing note only if v2 behavior differs. Re-approval checkpoint **[HUMAN-APPROVAL-NEEDED]** (§5.4) | Tiny docs + checkpoint |
| 19 | Manifest `citation` cross-ref keys → DATA_SOURCES.md sections | setup_state.py:36-56 | **Carry** (add `citation` key to the 3 new entries; optionally all 9) | Tiny |
| 20 | `hider_count_cap` as function of atom count | setup_state.py:233-244 → **already ported** vmd/lib/setup_state.tcl:51-59 (1/50 clamp [1,50]; probe-verified) | **Already done in v2** — nothing to do | None |
| 21 | **Warn before Start on >~20k atoms** (ROADMAP SC4) | **NO v1 analogue** — v1 had no such warning (grep verified: no >20k warn anywhere in v1 GUI code) | **v2-only new work** — small dialog/megawidget warn in the Start path; atom count via `molinfo $m get numatoms` | Small |
| 22 | Offline-safe randomize (non-lock demo pick excludes fetched demos) | setup_state.py:322-324 | **Already done in v2** — setup_state.tcl:272-274 has the identical `bundled_ids` filter; just confirm it still holds when the 3 fetched entries are added (it filters `source eq "bundled"`, so yes) | Verify only |
| 23 | PDB_POOL / fetch-mode (RCSB randomize) | setup_state.py:78-112 | **Out of Phase 21 scope** (v2 Phase 16+ fetch mode is a separate roadmap item; v2's `fetch_pdb` stub errors deliberately, demos.tcl:105-107). Phase 21 covers the 3 manifest demos only | Skip |

---

## 8. Open questions for the planner

1. **Compression mechanism in Tcl 8.5 (blocks ROADMAP SC1's "compress" wording).**
   v1 got gzip for free (`cmd.save` native). Tcl 8.5 has no zlib package; VMD 1.9.3's Tcl build
   must be probed (`package require zlib` under `vmd -dispdev text`). Options: (a) probe VMD's
   Tcl for zlib; (b) cache plain `.pdb` (1.5 MB dry 3gp6 / ~2 MB est. 1gzm — tolerable, and
   VMD's readers handle gzip transparently anyway if a gz ever appears); (c) shell out to an
   external compressor (fragile on Windows). **Recommend:** mechanics researcher probes (a),
   falls back to (b); planner should pre-authorize the SC1 wording to accept "compressed OR
   plain cached at documented size" so the phase isn't blocked. Do NOT hand-roll gzip in Tcl.
2. **1gzm dry/compressed size never recorded.** DATA_SOURCES.md:105-106 still says "to be
   verified at execute time". v2's execute step should measure and backfill (completes v1's
   record too). Also gives the >20k-atom warn (SC4) its real trigger: dry 1gzm ≈ 19-20k atoms —
   right at the boundary; wet is 117,898.
3. **HTTPS fetch mechanism in VMD 1.9.3 (no tls package)** — all three v1 fetch_urls are https.
   This is the mechanics researcher's question (STATE.md 14-02 explicitly deferred it to Phase
   21). v1's SSL-fallback *concept* is the approved precedent for whatever mechanism lands.
   Until resolved, every pipeline step after "download" in this doc is mechanism-independent.
4. **DATA_SOURCES.md §2 heading inconsistency — needs a human-approved fix.**
   Line 98 says "### 1GZM — bacteriorhodopsin (Very challenging)" while line 91 (and the cited
   paper, Li et al. 2004) says **Bovine rhodopsin**; the v1 tier-table rationale
   (09-RESEARCH-pipeline.md:451) repeats "bacteriorhodopsin". The citation block is correct;
   the descriptor label is wrong. Since ALL claims must be human-approved
   **[HUMAN-APPROVAL-NEEDED]**: propose correcting the heading (and any v2 UI category text) to
   "Bovine rhodopsin" during Phase 21's docs task. Does not block fetch work.
5. **Where fetched-demo attribution surfaces in v2.** v1 surfaced citations ONLY in
   documentation (DATA_SOURCES.md + manifest cross-ref keys), never in-GUI; v2 SC2 likewise
   requires "cited in documentation". Planner should confirm no in-GUI attribution requirement
   is being silently added; if the demo menu should carry a source hint, that's new scope.
6. **v2 fetch UX shape.** v1's modeless progress dialog + async continuation is UX-proven but
   Tk-idiomatic reimplementation (ttk::progressbar in a transient toplevel, `after`-driven)
   hasn't been designed yet. The continuation-ownership + re-entrancy-guard concepts (verdict
   #16/#17) are the parts worth keeping verbatim; the widget choice is open.
7. **Alt-conf game-loop testing.** v1's F7 (native alt-confs breaking cartoon-segment hiders)
   was fixed in v1 (quick-009) and v2's splice already parses altloc columns — but Phase 21
   should include a start-a-game smoke on all three large demos (sphere AND cartoon/ribbon
   hiders) so any v2 analogue surfaces in-phase, not in a later phase's checkpoint (v1 got
   lucky that sphere hiders satisfied SC1).

---

## Sources

### Primary (HIGH — repo files, read in full this session)
- `DATA_SOURCES.md` (repo root, 202 lines) — all quoted attribution texts, strip counts, sizes
- `pymol/biochemeleon/setup_state.py:34-70,184-228,233-244` — manifest, TIER_LABELS, strip set + helper, hider cap
- `pymol/biochemeleon/demos.py:1-550` (full read) — load_demo branching, cache/temp helpers, SSL fallback, worker, finalize, cache-hit loader
- `pymol/biochemeleon/__init__.py:189-346,545-677` — pending flags, _prepare_and_start branch, _resolve_large_demo drain
- `pymol/biochemeleon/gui_setup.py:155-189,345` — demo_combo tier display, hider-cap wiring
- `vmd/lib/setup_state.tcl:34-59,272-274` — v2 manifest (6 bundled, 5 keys), hider_count_cap, bundled-only randomize
- `vmd/lib/demos.tcl:50-110` — v2 load_demo (non-bundled reject + Phase-21 branch pointer), fetch_pdb stub
- `vmd/gui/setup_tab.tcl:104,127,149,153` — v2 demo menubutton surface
- `vmd/AGENTS.md:137-145` — v2 perf rules (after 0 chunking, atomselect narrowing, budgets)
- `.planning/REQUIREMENTS.md:73-75,94,150-153` — DEMO-02/03/04, DIFF-05 texts + phase mapping
- `.planning/ROADMAP.md:265-277` — Phase 21 goal + 4 SCs
- `.planning/phases/09-…/09-0{1..4}-SUMMARY.md`, `09-VERIFICATION.md` — build record + approvals
- `.planning/phases/09-…/09-RESEARCH-{pipeline,memprotmd,sasbdb}.md` (targeted sections) — strip analysis, tier rationale, URL/fetch verification
- `.planning/quick/003-…/, 004-…/` — cache-layout relocation history
- `.planning/STATE.md:112` — 14-02 fetch_pdb stub note ("Phase 21 real fetch; VMD 1.9.3 lacks tls")

### Secondary
- v1 commit references (d54f22e, e0f8302, 925cb56, 3415d88, a360e34, quick-009) — cited from the
  summaries/verification above; commit hashes not independently re-read this session (LOW risk —
  summaries + current code agree).

## Metadata

**Confidence breakdown:**
- v1 pipeline & cache: HIGH — verified line-by-line against current code (docs and code agree,
  including the post-quick-004 cache layout which the older summaries describe differently)
- Strip/compress data: HIGH — empirically derived in v1 with atom-count math that checks exactly
- Difficulty model: HIGH — code + research table agree
- Attribution texts: HIGH for the texts themselves (verbatim quotes + recorded approval);
  the v2 REUSE needs its own approval checkpoint [HUMAN-APPROVAL-NEEDED]
- Carryover verdicts: HIGH for data/design carries; MEDIUM for the Tcl-concurrency adaptation
  shape (depends on mechanics research still to come)

**Research date:** 2026-09-25
**Valid until:** stable — v1 code is frozen (shipped); re-check only if DATA_SOURCES.md or the
MemProtMD/SASBDB sites change before Phase 21 executes (the license re-check is a planned
checkpoint anyway).
