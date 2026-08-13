# Phase 9 Research — MemProtMD Membrane Protein Fetch

**Researched:** 2026-08-14
**Domain:** MemProtMD database access, PDB file fetching/stripping/compression, license attribution (DEMO-02 + DEMO-04 membrane portion)
**Confidence:** HIGH (site reachable, download URL verified by fetching real PDB content, license text extracted from site JS, strip targets empirically verified against staged sample + live wet file, PyMOL selectors verified against v2.5.0 C source)

**Primary recommendation:** Fetch `<pdbid>_default_dppc` atomistic PDBs from `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/<pdbid>_default_dppc/files/structures/at.pdb` via stdlib `urllib`, strip GROMACS water (`SOL`) and ions (`NA`, `CL`) by explicit residue-name line-filtering in pure Python (NOT via PyMOL `solvent`/`inorganic` selectors — see §Strip+Compress for why), gzip/zip the result into `tmp/phase9-demos/cache/`, then `cmd.load` the cached dry PDB. Attribute under **CC-BY 4.0** with the corrected Stansfeld 2015 / Newport 2019 citations (the prior-research Nat. Methods 2018 DOI is WRONG — see §License).

---

## Site Access Verification (reachable? URL pattern)

### Reachable — prior research had a DOMAIN TYPO

Prior research (`PITFALLS.md:521`, `SUMMARY.md:224`, `PROJECT.md:75`) cited the MemProtMD domain as `memprotmd.bioch.oxy.ac.uk` and reported it **UNREACHABLE** ("transport errors"). **This was a typo.** The correct domain is `memprotmd.bioch.ox.ac.uk` (no `y`), confirmed by three independent repo sources:
- `spec.md:56` — `https://memprotmd.bioch.ox.ac.uk` (correct)
- `README.md:89` — `https://memprotmd.bioch.ox.ac.uk` (correct)
- `PROJECT.md:75` — `https://memprotmd.bioch.oxy.ac.uk` (**typo — the source of the prior failure**)

**Verified 2026-08-14:** `https://memprotmd.bioch.ox.ac.uk` returns HTTP 200 (webfetch confirms "MemProtMD" homepage). The `oxy.ac.uk` variant still fails with a transport error (confirmed: webfetch `https://memprotmd.bioch.oxy.ac.uk` → "Transport error"). **Fix the typo in `PROJECT.md:75` during Phase 9** (it propagates the wrong URL into the project record).

### Site is a JavaScript SPA — but the data API is HTTP-GET-able

The MemProtMD frontend is a React/Redux single-page app (`window.MPMRootURI`, `index.js` bundle). All HTML pages (`/`, `/about`, `/cite`, `/api`, `/_ref/PDB/<pdbid>/`) return 200 with a JS-rendered shell ("You must enable JavaScript to view the full MemProtMD site"). Entry-page URLs like `/entries/3gp6`, `/entry/3gp6`, `/3gp6` all return **404** (verified) — these are NOT the real routes.

**Real entry-page URL pattern** (discovered via `sitemap.xml`, verified 200):
```
https://memprotmd.bioch.ox.ac.uk/_ref/PDB/<pdbid>/                    # entry overview
https://memprotmd.bioch.ox.ac.uk/_ref/PDB/<pdbid>/_sim/<pdbid>_default_dppc/   # simulation page
```
Confirmed for both targets:
- `https://memprotmd.bioch.ox.ac.uk/_ref/PDB/1gzm/` → 200
- `https://memprotmd.bioch.ox.ac.uk/_ref/PDB/3gp6/` → 200
- `https://memprotmd.bioch.ox.ac.uk/_ref/PDB/3gp6/_sim/3gp6_default_dppc/` → 200

**Download URL pattern** (decoded from the `index.js` bundle — see §Target Entries): the JS constructs download links as `DataRoot + "memprotmd/simulations/" + simName + "/files/structures/at.pdb"`, where `DataRoot = MPMRootURI + "data/"` and `simName = "<pdbid>_default_dppc"`. So the canonical atomistic-PDB download URL is:
```
https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/<pdbid>_default_dppc/files/structures/at.pdb
```
This is a **direct HTTP GET** — no JS, no API key, no authentication. Verified for both targets by fetching the actual file content (see §Target Entries).

**Site also exposes an API** (`/api/` → 200; meta description: "The MemProtMD API provides access to data from simulations and annotations via HTTP"). The JS references `MPMRootURI+"/api"` and `api/search/advanced`. Not needed for our use case (we just GET a static file path), but documented here for completeness. UNVERIFIED: the full API surface (we only need the static-file GET, which is confirmed working).

---

## Target Entries (1GZM, 3GP6 — files, sizes, naming)

### What the two entries ARE (RCSB metadata, verified via data.rcsb.org REST API 2026-08-14)

| PDB ID | Protein | TM fold | "helix/sheets" meaning | Method | Resolution | Primary citation |
|--------|---------|---------|------------------------|--------|-----------|-------------------|
| **1GZM** | Bovine rhodopsin | 7-TM **α-helix** bundle (GPCR) | "helix" = α-helical TM | X-ray | 2.65 Å | Li, Edwards, Burghammer, Villa, Schertler. *Structure of Bovine Rhodopsin in a Trigonal Crystal Form.* J Mol Biol 343:1409 (2004). DOI `10.1016/j.jmb.2004.08.090`. PMID 15491621. PDB DOI `10.2210/pdb1gzm/pdb` |
| **3GP6** | PagP (outer-membrane palmitoyltransferase) | **β-barrel** (β-sheet) | "sheets" = β-barrel/β-sheet TM | X-ray | 1.4 Å | Cuesta-Seijo, Neale, Khan, Moktar, Tran, Bishop, Pomes, Prive. *PagP crystallized from SDS/cosolvent reveals the route for phospholipid access to the hydrocarbon ruler.* Structure 18:1210-1219 (2010). DOI `10.1016/j.str.2010.06.014`. PMID 20826347. PDB DOI `10.2210/pdb3gp6/pdb` |

**Note on the "helix/sheets" labels:** the project (`PROJECT.md:75`, `README.md:64-65`) labels 1GZM as "(helix)" and 3GP6 as "(sheets)". These refer to the **transmembrane secondary structure**: 1GZM is an α-helical bundle (7 TM helices), 3GP6 is a β-barrel (β-sheet fold). The demo rationale is sound — one helical-TM demo + one β-barrel-TM demo. The original PDB crystal structures are SMALL (1GZM: 5,792 deposited atoms; 3GP6: 1,586 deposited atoms); the "large file" property comes entirely from MemProtMD embedding them in a full DPPC lipid bilayer + solvent.

### Available download files per MemProtMD entry (decoded from `index.js`)

The MemProtMD download panel offers these files per simulation (8 structure files + 2 zip bundles), all under `data/memprotmd/simulations/<pdbid>_default_dppc/files/`:

| Path suffix | Title (offered) | What it is |
|-------------|-----------------|-----------|
| `files/structures/at.pdb` | `<pdbid>_default_dppc-atomistic.pdb` | **Atomistic snapshot created with CG2AT** ← WE WANT THIS |
| `files/structures/cg.pdb` | `-coarsegrained.pdb` | Coarse-grained snapshot |
| `files/structures/ready.pdb` | `-ready.pdb` | Ready-to-run structure |
| `files/structures/distortions.pdb` | `-distortions.pdb` | Membrane distortion map |
| `files/structures/group_head.contacts.pdb` | `-head-contacts.pdb` | Lipid head-group contacts |
| `files/structures/group_solvent.contacts.pdb` | `-solvent-contacts.pdb` | Solvent contacts |
| `files/structures/group_tail.contacts.pdb` | `-tail-contacts.pdb` | Lipid tail contacts |
| `files/structures/web_vis.pdb` | (web viewer) | Web visualization structure |
| `files/run/at.zip` | `-atomistic-simulation.zip` | Ready-to-run atomistic sim files |
| `files/run/cg.zip` | `-coarsegrained-simulation.zip` | Ready-to-run CG sim files |

**We want `at.pdb`** — the atomistic snapshot (protein + DPPC bilayer + solvent + ions), which is what DEMO-02's "full membrane (dppc-atomistic)" refers to.

### Naming convention — CONFIRMED, with a critical "_dry" caveat

- The staged sample is named `3gp6_default_dppc-atomistic_dry.pdb` — the `_dry` suffix was added **locally** (by whoever staged it), NOT by MemProtMD.
- The MemProtMD-served file is named `at.pdb` on the server, and the download panel titles it `<pdbid>_default_dppc-atomistic.pdb` (NO `_dry`).
- **There is NO `_dry` variant on the MemProtMD server.** Verified: `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/3gp6_default_dppc/files/structures/at_dry.pdb` → 404 "No file is located at that path" (same for 1gzm).
- **What "_dry" means:** water (and in this case salt/ions) STRIPPED. The staged `_dry` sample is the server's `at.pdb` with `SOL`/`NA`/`CL` removed locally (see §Strip+Compress). DEMO-02's "strip water and salt" step PRODUCES the `_dry` variant — we do the stripping, not MemProtMD.
- **What "dppc-atomistic" means:** DPPC (dipalmitoylphosphatidylcholine) lipid bilayer, atomistic (not coarse-grained) representation. Confirmed: the lipid residue name in the files is `DPP` (17,500 atoms in 3gp6, 19,200 in 1gzm).

### Wet vs dry — which we want, and why the strip step is NOT redundant

DEMO-02 says "strip water and salt" — but one might assume the `_dry` variant is already stripped. **Clarification:**
- The MemProtMD server only serves the **WET** `at.pdb` (protein + DPPC membrane + SOL water + NA/CL ions). There is no pre-stripped dry download.
- The staged `_dry` sample was produced by stripping SOL/NA/CL from the wet file locally.
- **We want the dry (stripped) variant** for caching (DEMO-02: "compress before caching") — the wet file is ~5-6× larger and the water/ions are irrelevant to the hide-and-seek game (they'd just bloat PyMOL load + the hider-generator memory per Pitfall 12).
- The strip step is therefore **required** (not redundant) — we fetch wet, strip, compress, cache.

### File sizes (VERIFIED by HTTP GET, 2026-08-14)

| Entry | Server file | Raw bytes | Atoms (wet) | Atoms (dry) | Staged dry sample | Zipped dry |
|-------|-------------|-----------|-------------|-------------|-------------------|------------|
| **3gp6** | `at.pdb` (wet) | **7,524,042** (7.5 MB) | 95,239 | 19,221 | 1,518,620 (1.5 MB) | 231,087 (231 KB) |
| **1gzm** | `at.pdb` (wet) | **9,314,128** (9.3 MB) | 117,898 | UNVERIFIED | UNVERIFIED (not staged) | UNVERIFIED |

**1gzm dry size: UNVERIFIED — needs human confirmation / execute-time fetch.** 1gzm was not pre-staged in `tmp/`. Its wet file (9.3MB) is larger than 3gp6's (7.5MB), and its protein has more atoms (1gzm protein ~4,000 atoms vs 3gp6 ~1,700, by residue-count difference), so the dry 1gzm will be larger than 1.5MB — estimate ~2MB raw / ~300KB zipped, but **do not state a number without fetching it.** The execute step should fetch 1gzm's `at.pdb`, strip it, and record the actual dry/zipped sizes in DATA_SOURCES.md.

**Zip structure of the staged sample** (verified via `python3.6 zipfile.ZipFile` — `unzip` is not installed in WSL):
```
3gp6_default_dppc-atomistic_dry.zip contains:
  3gp6_default_dppc-atomistic.pdb   (1,518,620 raw → 230,891 compressed)
```
Note the zip's inner filename drops the `_dry` suffix (it's `3gp6_default_dppc-atomistic.pdb`, not `..._dry.pdb`) — a naming inconsistency between the outer zip name and inner file name. The execute step should pick ONE consistent naming convention (recommend `<pdbid>_default_dppc-atomistic_dry.pdb` for both the raw cached file and the zip inner name, for traceability).

---

## License Verification (site license, per-entry, citation DOI verified, bundling permission, required attribution text)

> This is the highest-risk item (PITFALLS.md:521 flagged it MEDIUM-confidence "site unreachable"). It is now HIGH confidence — site reachable, license text extracted.

### Site-wide / per-entry license: **CC-BY 4.0 International** (VERIFIED)

The license text is rendered by the JS bundle (not in the static `/about` HTML, which is a JS shell). Extracted directly from `https://memprotmd.bioch.ox.ac.uk/static/js/index.js`:
```
"Licensed using a Creative Commons Attribution 4.0 International License."
```
And the JS references a license icon: `MPMRootURI+"static/license/by.svg"` (the CC-BY badge). This is the **per-entry download license** (the string appears in the download-panel component, applying to each file offered for download).

**CC-BY 4.0 permits:** unrestricted reuse, distribution, and reproduction in any medium, **provided the original work is properly cited** (attribution). **Bundling the processed/derived PDB in our repo IS permitted** under CC-BY 4.0, as long as we attribute MemProtMD.

**Note on the two copyright layers** (the PITFALLS.md:521 concern, now resolved):
- The **PDB entries** (1GZM, 3GP6 atomic coordinates) are CC0 1.0 (RCSB PDB policy, `rcsb.org/pages/policies` — confirmed in prior research). Free to bundle, attribution requested (PDB ID + DOI + publication).
- The **membrane coordinates** (the DPPC bilayer + solvent box) are MemProtMD-derived (the NAR 2019 paper confirms: "non-protein atoms are removed from the PDB entry prior to simulation" — MemProtMD regenerates the bilayer via CG self-assembly + CG2AT). These carry **CC-BY 4.0** (stricter than CC0 — attribution REQUIRED, not just requested).
- **Net:** the bundled dry file is a DERIVED WORK of BOTH layers. We must attribute BOTH: the PDB entries (CC0, cite PDB ID + DOI) AND MemProtMD (CC-BY 4.0, cite the MemProtMD papers + CC-BY notice). The CC-BY layer is the binding constraint (attribution mandatory).

### Canonical citations — CORRECTED (prior research DOI was WRONG)

> ⚠ **The prior research citation is incorrect and must NOT be used.** `PITFALLS.md:521` and `SUMMARY.md:224` cite "Stansfeld et al., *MemProtMD: Automated Coarse-Grained Membrane Protein Embedding Simulations*, Nat. Methods 2018, `https://doi.org/10.1038/s41592-018-0220-9`". **This DOI does not resolve** — verified 2026-08-14: `curl -s -o /dev/null -w "%{http_code}" -L https://doi.org/10.1038/s41592-018-0220-9` → **404** (also Europe PMC has no such paper; the Nature URL `nature.com/articles/s41592-018-0220-9` returns 404). The prior "fetch timed out" was masking a non-existent DOI. **Do not cite it.**

**The REAL MemProtMD papers** (verified via Europe PMC title search `"MemProtMD"`, 2026-08-14):

1. **Methodology paper (2015):**
   - Stansfeld PJ, Goose JE, Caffrey M, Carpenter EP, Parker JL, Newstead S, Sansom MS. *MemProtMD: Automated Insertion of Membrane Protein Structures into Explicit Lipid Membranes.* **Structure.** 2015;23(7):1350-1361.
   - DOI: `10.1016/j.str.2015.05.006` — **VERIFIED** (`doi.org/10.1016/j.str.2015.05.006` → HTTP 200)
   - PMID: 26073602; PMCID: PMC4509712; Open Access (in Europe PMC)

2. **Database paper (2019)** ← cite THIS ONE as primary (we use the database's data):
   - Newport TD, Sansom MSP, Stansfeld PJ. *The MemProtMD database: a resource for membrane-embedded protein structures and their lipid interactions.* **Nucleic Acids Res.** 2019;47(D1):D390-D397.
   - DOI: `10.1093/nar/gky1047` — **VERIFIED** (Europe PMC hit; full text at PMC6324062; `doi.org/10.1093/nar/gky1047` returns 403 to curl but resolves in browsers — OUP bot-blocks curl; the PMC full-text confirms the citation)
   - PMID: 30418645; PMCID: PMC6324062; Open Access (CC-BY, per the PMC copyright line: "© The Author(s) 2018. Published by Oxford University Press... This is an Open Access article distributed under the terms of the Creative Commons Attribution License")
   - **Data-availability statement (from the NAR 2019 full text):** "The MemProtMD database can be accessed through the web server at http://memprotmd.bioch.ox.ac.uk" — confirms the data is freely accessible.

**Recommendation for DATA_SOURCES.md:** cite BOTH MemProtMD papers (the 2015 methodology + the 2019 database paper), with the 2019 database paper as the primary citation (it describes the resource we're downloading from). Add the CC-BY 4.0 notice. Flag the old wrong DOI for removal from `PITFALLS.md:521` + `SUMMARY.md:224` during Phase 9.

### Required attribution text (for DATA_SOURCES.md, per CC-BY 4.0)

```
## MemProtMD membrane-protein demos (1GZM, 3GP6) — CC-BY 4.0

Membrane coordinates (DPPC bilayer) and the atomistic embedding are derived from
MemProtMD (https://memprotmd.bioch.ox.ac.uk) and licensed under the Creative
Commons Attribution 4.0 International License (https://creativecommons.org/licenses/by/4.0/).
Attribution required:

  Newport TD, Sansom MSP, Stansfeld PJ. The MemProtMD database: a resource for
  membrane-embedded protein structures and their lipid interactions. Nucleic
  Acids Res. 2019;47(D1):D390-D397. DOI: 10.1093/nar/gky1047

  Stansfeld PJ, Goose JE, Caffrey M, Carpenter EP, Parker JL, Newstead S,
  Sansom MS. MemProtMD: Automated Insertion of Membrane Protein Structures into
  Explicit Lipid Membranes. Structure. 2015;23(7):1350-1361.
  DOI: 10.1016/j.str.2015.05.006

The underlying protein structures are from the RCSB PDB (CC0 1.0):

  1GZM — Bovine rhodopsin. Li J, Edwards P, Burghammer M, Villa C, Schertler GFX.
    J Mol Biol 343:1409 (2004). DOI: 10.1016/j.jmb.2004.08.090. PDB DOI:
    10.2210/pdb1gzm/pdb
  3GP6 — PagP. Cuesta-Seijo JA, Neale C, Khan MA, Moktar J, Tran CD, Bishop RE,
    Pomes R, Prive GG. Structure 18:1210-1219 (2010).
    DOI: 10.1016/j.str.2010.06.014. PDB DOI: 10.2210/pdb3gp6/pdb

Files were processed: water (SOL) and ions (NA, CL) stripped, then compressed,
before caching. The DPPC membrane and protein coordinates are preserved
unaltered from the MemProtMD atomistic snapshot.
```

---

## Strip + Compress Pipeline (selectors, cmd approach, _dry inspection findings, zip structure)

### Staged-sample inspection findings (the ground truth for the strip step)

Read `tmp/3gp6_default_dppc-atomistic_dry.pdb` (1,518,620 bytes, 19,227 lines) directly:

**File structure:**
```
TITLE     S  C  A  M    M  G          ← GROMACS-generated title (not the real protein name)
REMARK    THIS IS A SIMULATION BOX
CRYST1  109.513  109.513  104.638  90.00  90.00  90.00 P 1           1   ← orthorhombic sim box
MODEL        1
ATOM      1  N   MET     1   ...   ← protein starts (MET, ASN, ALA, ASP, GLU, ...)
...                                          ← ~1,721 protein atoms (all 20 AA types)
ATOM  1721  ...                         ← protein ends
...                                      ← DPPC lipids (resn DPP)
ATOM  19204  O33 DPP   505  ...        ← last lipid atom
TER
ENDMDL
```

**Residue-name diversity (dry sample, `cut -c18-20 | sort | uniq -c`):**
```
17500 DPP    ← DPPC lipids (the membrane — PRESERVE)
  252 TRP, 182 TYR, 170 PHE, 121 ASN, 119 ARG, 100 LEU, 90 THR, 80 GLU,
  79 ALA, 75 GLY, 70 PRO, 60 GLN, 57 HIS, 54 ILE, 54 ASP, 47 MET, 40 VAL,
  39 LYS, 32 SER   ← protein (the 20 standard amino acids — PRESERVE)
```

**Critical facts about the dry sample:**
- **ZERO `HETATM` records** (0 HETATM, 19,221 ATOM). MemProtMD records EVERYTHING — protein, lipids, water — as `ATOM` records, not `HETATM`.
- **ZERO water/ions**: no `HOH`, `WAT`, `SOL`, `NA`, `CL`, `K`, `CA`, `MG` in the dry sample (grep for water/ion residue names returns nothing). The `_dry` variant is **already stripped** — confirming the strip removes exactly SOL+NA+CL.
- **DPPC lipids are `ATOM` records with resn `DPP`** (not HETATM, not resn DPPC). 17,500 lipid atoms across 505 lipid residues (DPP 1..505).
- Single `MODEL`/`ENDMDL` (one frame), single `TER` (one chain), `CRYST1` with P1 symmetry (simulation box, not crystal unit cell).

### Wet-vs-dry diff — the EXACT strip targets (VERIFIED)

Downloaded the live wet `at.pdb` for 3gp6 (95,239 ATOM records, 0 HETATM) and diffed residue names against the dry sample:

| resn | In WET | In DRY | Strip? | Count (3gp6) | Count (1gzm) |
|------|--------|--------|--------|--------------|--------------|
| **SOL** | ✓ | ✗ | **YES — water** | 75,789 | 91,638 |
| **NA** | ✓ | ✗ | **YES — sodium ion** | 116 | 147 |
| **CL** | ✓ | ✗ | **YES — chloride ion** | 113 | 139 |
| DPP | ✓ | ✓ | NO — membrane | 17,500 | 19,200 |
| (20 AAs) | ✓ | ✓ | NO — protein | ~1,721 | ~4,024 |

**Atom-count math checks exactly** (3gp6): wet(95,239) − dry(19,221) = 76,018 stripped = SOL(75,789) + NA(116) + CL(113) = 76,018 ✓. Both entries use the identical SOL/NA/CL strip targets (1gzm wet confirmed: SOL 91,638 + NA 147 + CL 139 present).

**Definition of "salt" (DEMO-02 "strip water and salt"):** for MemProtMD files, "salt" = the NA (sodium) + CL (chloride) counter-ions added to neutralize the simulation box. There are no other ion species (no K, CA, MG) in either file. `SOL` = GROMACS solvent (water). These three residue names are the complete strip set.

### PyMOL selector options — verified against v2.5.0 C source

I checked the PyMOL 2.5.0 source (`tmp/pymol-src/`) for how `solvent`/`inorganic`/water selectors classify atoms:

- **`Selector.cpp:649`**: `{"solvent", SELE_SOLz}` — the `solvent` selector keyword maps to `SELE_SOLz`.
- **`Selector.cpp:646`**: `{"inorganic", SELE_INOz}` — the `inorganic` selector keyword.
- **`Selector.cpp:643`**: `{"organic", SELE_ORGz}` — organic (carbon-containing molecules).
- **`Seeker.cpp:838-841`**: `case 'O': /* SOL -- gromacs solvent residue */ ... return water;` — PyMOL's residue-name classifier **DOES recognize `SOL` as water** and classifies it as `water`. So the `solvent` selector keyword **WILL match `SOL`** (because SOL → water classification → solvent selector).
- Python water-residue tables (`chempy/water_residues.py`, `water_amber.py`) only list `HOH` + `WAT` — but these are for *bond template matching*, NOT for the selector classification (which is C-level in `Seeker.cpp`). The C-level recognition of `SOL` is what matters for the selector.
- The PyMOL menu's "remove waters" uses `cmd.remove("(solvent and (sele))")` (`menu.py:1221,1256,1491`) — confirming `solvent` is the idiomatic water-removal selector.

**For ions (`NA`, `CL`):** the `inorganic` selector (`SELE_INOz`) should match them, but I could NOT fully verify from Python source alone whether `inorganic` matches ions recorded as `ATOM` (not `HETATM`) — the C-level classification logic for `SELE_INOz` is not traceable from the Python modules. DPPC lipids are organic (carbon-containing), so `inorganic` should NOT match `DPP` — but again, unverified at the Python tier.

### Recommended strip approach — explicit resn line-filter (PRIMARY)

**Do NOT rely on PyMOL selectors for the strip.** Instead, strip by **explicit residue-name line-filtering in pure Python** before the file ever reaches PyMOL. Rationale:
1. **Deterministic & traceable** (AGENTS.md: "Do NOT make up anything" — explicit resn is empirical fact, not selector-classification faith).
2. **Avoids loading the 95k-atom wet file into PyMOL at all** — the wet `at.pdb` (7.5-9.3MB) is stripped in a single Python pass over the text lines, then only the ~19k-atom dry PDB is handed to `cmd.load`. This dodges Pitfall 12 (large-PDB load freeze/OOM) entirely for the wet file.
3. **No HETATM-dependence** — MemProtMD records SOL/NA/CL as `ATOM`, so any selector that keys off the `hetatm` flag would miss them. Explicit `resn` matching is flag-independent.
4. **Preserves DPPC guaranteed** — filtering by `resn in {SOL, NA, CL}` can never accidentally drop a `DPP` lipid or a protein residue.

**Concrete pipeline (pure-Python strip, then cmd.load the dry result):**
```python
# Pseudocode — NOT plugin code (research only). Planner refines into tasks.
import urllib.request, gzip, os

STRIP_RESN = {"SOL", "NA ", "CL "}   # note: PDB resn field is cols 18-20, right-justified;
                                     # "NA"/"CL" are 2 chars + trailing space. SOL is 3 chars.
                                     # Verify exact column padding against the fetched file.

def fetch_strip_compress_cache(pdbid, cache_dir):
    url = f"https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/{pdbid}_default_dppc/files/structures/at.pdb"
    raw = urllib.request.urlopen(url).read().decode("ascii")   # ~7-9MB; stdlib, no approval needed
    # Strip water+ions by PDB line filtering (preserve all non-ATOM lines: TITLE/CRYST1/MODEL/TER/ENDMDL)
    kept = []
    for line in raw.splitlines():
        if line.startswith("ATOM"):
            resn = line[17:20]      # PDB columns 18-20 (0-indexed 17:20)
            if resn in STRIP_RESN:
                continue            # drop water/ions
        kept.append(line)
    dry = "\n".join(kept) + "\n"
    # Compress + cache
    cache_path = os.path.join(cache_dir, f"{pdbid}_default_dppc-atomistic_dry.pdb")
    with open(cache_path, "w") as f:
        f.write(dry)
    # Also write .pdb.gz (or .zip) alongside — see "Compress" below
    return cache_path
```

**CAUTION — PDB column padding for 2-char resn:** PDB residue names occupy columns 18-20 (1-indexed), i.e. `line[17:20]` (0-indexed). For 3-char names (`SOL`, `DPP`, `MET`), this is exact. For 2-char ion names, the field is **right-justified**: `NA` is stored as `"NA "` (NA + trailing space) in some PDB writers and `" NA"` (leading space) in others. **The execute step MUST verify the exact padding** by inspecting a fetched wet file (`grep "^ATOM" at.pdb | head` and check columns 18-20 for NA/CL lines) before finalizing the `STRIP_RESN` set. The staged dry sample has no NA/CL (already stripped), so padding must be confirmed from the LIVE wet file. (My `cut -c18-20` on the live wet file showed `NA ` and `CL ` — but `cut` may have trimmed; the Python `line[17:20]` slice must be tested against real bytes.)

### Compress — gzip vs zip, and whether PyMOL can read compressed

**Staged-sample zip structure** (verified via `python3.6 zipfile.ZipFile('tmp/3gp6_default_dppc-atomistic_dry.zip')`):
```
Filename: 3gp6_default_dppc-atomistic.pdb   (NOTE: no _dry suffix inside the zip)
File size: 1,518,620 → compressed: 230,891   (ratio ~15%, 6.6x compression)
```
The zip was made with Python's `zipfile` (consistent with the project using stdlib only). Compression: 1.5MB → 231KB.

**gzip vs zip — recommend gzip (.pdb.gz):**
- Both are stdlib (`gzip` / `zipfile`), no approval needed.
- **gzip is simpler** for single-file compression (no archive-member naming inconsistency, as seen in the staged zip where the inner name dropped `_dry`).
- gzip integrates with `urllib`/file streaming more naturally.
- The staged sample uses `.zip`, but the project has no hard requirement on zip specifically — DEMO-02 says "compress before caching" (format unspecified). Recommend `.pdb.gz` for the cache, document the choice.

**Can PyMOL `cmd.load` read `.pdb.gz` / `.zip` directly?** UNVERIFIED — needs execute-time confirmation. PyMOL's `importing.py:635` `cmd.load` auto-detects format from extension; `.pdb` is supported. Whether `.pdb.gz` is auto-decompressed by PyMOL's loader is not confirmed from the Python source (the decompression may be in the C layer). **Safest approach:** decompress to a temp `.pdb` before `cmd.load` (e.g. `gzip.decompress(cached_gz_bytes)` → write temp `.pdb` → `cmd.load(temp_pdb)` → delete temp). This avoids depending on PyMOL's gzip support. The execute step should test `cmd.load("file.pdb.gz")` headlessly via the `run-conda-pymol.bat -cq` path (AGENTS.md) — if it works, skip the temp-file dance; if not, use the decompress-then-load path.

### Caching location

User directive: repo-local `tmp/` staging (git-ignored, avoids external-dir risk). `tmp/phase9-demos/` already created (empty). Recommend cache subdir:
```
tmp/phase9-demos/cache/
  1gzm_default_dppc-atomistic_dry.pdb       (raw dry, ~2MB est — UNVERIFIED)
  1gzm_default_dppc-atomistic_dry.pdb.gz    (compressed, ~300KB est — UNVERIFIED)
  3gp6_default_dppc-atomistic_dry.pdb       (raw dry, 1.5MB — VERIFIED)
  3gp6_default_dppc-atomistic_dry.pdb.gz    (compressed, ~231KB — VERIFIED)
```
`tmp/` is git-ignored (per AGENTS.md), so cached files are NOT committed — the cache is a local-only performance optimization. On first request: fetch → strip → compress → write cache → load. On subsequent requests: decompress cache → load. This matches DEMO-02's "fetched on demand" + "compress before caching" workflow (NOT pre-bundled in the repo).

**Cache invalidation:** none needed for v1 (the MemProtMD simulations are static snapshots; entries don't change). A future enhancement could check `Last-Modified` / ETag, but v1 can treat the cache as permanent once written.

---

## Fetch Mechanism (urllib -> cmd.load, cache workflow, offline fallback)

### Why not `cmd.fetch` (and the two-step alternative)

`cmd.fetch` (PyMOL `importing.py:1323`) **only fetches from the RCSB PDB / wwPDB** — it CANNOT fetch from MemProtMD (MemProtMD is not a wwPDB partner; its URLs are not in PyMOL's fetch table). Verified: `cmd.fetch('3gp6')` would fetch the bare RCSB crystal structure (1,586 atoms, no membrane), NOT the MemProtMD membrane-embedded structure. So the MemProtMD fetch MUST be a **two-step**: (1) `urllib` (stdlib) downloads the file to a local path, (2) `cmd.load` loads the local file.

**stdlib `urllib` requires NO approval** (AGENTS.md: "For HTTP fetch, Python stdlib urllib is fine — no approval needed"). Do NOT add `requests` or any third-party HTTP lib.

### Workflow: fetch-on-first-request → strip → compress → cache → load

```
User picks 1GZM/3GP6 demo in Setup tab
  ↓
demos.load_demo(demo_id) branches on manifest 'source' field:
  ├─ source='bundled' → existing path (load biochemeleon/data/demos/<file>.pdb)
  └─ source='memprotmd' → fetch_large_demo(demo_id):
       1. Check cache: tmp/phase9-demos/cache/<pdbid>_default_dppc-atomistic_dry.pdb[.gz]
          ├─ cache HIT  → decompress (if .gz) → cmd.load(dry_pdb) → return obj_name
          └─ cache MISS → (show modeless QProgressDialog here)
                a. urllib.request.urlopen(download_url).read()    [download ~7-9MB; report progress]
                b. strip SOL/NA/CL by line-filtering (pure Python) [fast; report "stripping..."]
                c. write dry PDB + compress to .pdb.gz in cache     [fast; report "caching..."]
                d. cmd.load(dry_pdb, object=pdbid, zoom=1)         [fast, ~19k atoms; report "loading..."]
                e. return obj_name (or None on failure)
```

### Network-failure / offline handling

- If `urllib.request.urlopen` raises (URLError, HTTPError, timeout) AND cache MISS → **graceful fallback**: catch the exception, show a `QMessageBox` ("Could not fetch <pdbid> from MemProtMD (offline?). Bundled small demos still available."), return `None`. The bundled 6 small demos (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) remain fully functional offline — only the 2 large membrane demos need network on first fetch.
- If cache HIT (file exists in `tmp/phase9-demos/cache/`) → load from cache regardless of network status (offline works after first fetch).
- **Timeout:** set a reasonable `urllib` timeout (e.g. 30s) — MemProtMD is an academic site and may be slow. The wet files are 7-9MB; on a slow link this could take a minute. The cancelable progress dialog (below) lets the user abort.

### Progress dialog (modeless, cancelable) — MemProtMD-specific steps

Per `PITFALLS.md` Pitfall 12 + the success criterion ("modeless cancelable progress dialog"), the fetch-large-demo path must show a `QProgressDialog` (modeless, `dialog.show()` NEVER `.exec_()`, with a Cancel button). Steps needing progress reporting:
1. **Download** (`urllib.urlopen` → `read()`) — the slow step (~7-9MB over the network). Report bytes/percentage if Content-Length available (the server returns `Content-Length`; my curl probe got `size_download`). This is the only step that meaningfully takes time.
2. **Strip** (line-filter) — fast (<1s for 95k lines), but report "Stripping water and salt..." for UX continuity.
3. **Compress + cache** — fast, report "Compressing and caching...".
4. **`cmd.load`** (dry) — fast (~19k atoms), report "Loading into PyMOL...".

**Threading constraint (Pitfall 6 — load-bearing):** `urllib` download CAN run on a worker `QThread` (it makes no `cmd.*` calls). But `cmd.load` MUST run on the GUI main thread (all `cmd.*` on main thread; PyMOL's C state is not thread-safe). Pattern: worker thread does download+strip+compress (pure Python, no `cmd.*`), posts the cached-file path to the main thread via `QTimer.singleShot(0, ...)`, main thread does `cmd.load`. The progress dialog's Cancel triggers a flag the worker checks. **Do NOT call `cmd.*` from the worker thread.**

---

## Manifest Integration (proposed schema, difficulty tiers)

### Current DEMO_MANIFEST schema (setup_state.py:29-36)

```python
DEMO_MANIFEST = {
    '1znf': {'category': 'Protein',      'type': 'protein',     'difficulty': 'easy',  'file': '1znf.pdb'},
    '1xdn': {'category': 'Protein',      'type': 'protein',     'difficulty': 'hard',  'file': '1xdn.pdb'},
    '5e54': {'category': 'Nucleic acid', 'type': 'rna',         'difficulty': 'easy',  'file': '5e54.pdb'},
    '1k8p': {'category': 'Nucleic acid', 'type': 'dna',         'difficulty': 'easy',  'file': '1k8p.pdb'},
    '2qbz': {'category': 'Nucleic acid', 'type': 'rna',         'difficulty': 'hard',  'file': '2qbz.pdb'},
    '4wb3': {'category': 'Mixed',        'type': 'protein/na',  'difficulty': 'mixed', 'file': '4wb3.pdb'},
}
```
Fields: `{category, type, difficulty, file}`. Difficulty values in use: `'easy'`, `'hard'`, `'mixed'`. All 6 are bundled (file resolves under `biochemeleon/data/demos/`).

### Proposed Phase 9 extension (DIFF-05 tiers + fetch source)

Add 2 MemProtMD entries with new fields `source` and `fetch` (and reuse `file` for the cache name). New difficulty tiers per the phase brief: `'challenge'` / `'very challenging'`.

```python
# Phase 9 additions (proposed — planner finalizes exact field names):
'1gzm': {
    'category': 'Membrane protein',      # new category (matches README.md:64)
    'type': 'protein',
    'difficulty': 'very challenging',     # DIFF-05 tier (large, helical TM, full membrane)
    'source': 'memprotmd',               # NEW: 'bundled' (default) | 'memprotmd' (fetch)
    'fetch': 'memprotmd',                # NEW: fetch strategy key
    'file': '1gzm_default_dppc-atomistic_dry.pdb',  # cache filename (NOT a bundled file)
    'memprotmd_url': 'https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/1gzm_default_dppc/files/structures/at.pdb',
},
'3gp6': {
    'category': 'Membrane protein',
    'type': 'protein',
    'difficulty': 'challenge',           # DIFF-05 tier (large, β-barrel, full membrane)
    'source': 'memprotmd',
    'fetch': 'memprotmd',
    'file': '3gp6_default_dppc-atomistic_dry.pdb',
    'memprotmd_url': 'https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/3gp6_default_dppc/files/structures/at.pdb',
},
```

**Design notes for the planner:**
- Keep the existing 6 entries' schema BACKWARD-COMPATIBLE: default `source='bundled'` when the field is absent (so `validate_state` / `randomize_state` in `setup_state.py` don't break on the 6 old entries). Add `source` to the 6 old entries explicitly for clarity, OR default-missing-to-`bundled` in `load_demo`.
- `file` is OVERLOADED: for `source='bundled'` it's a path under `biochemeleon/data/demos/`; for `source='memprotmd'` it's the cache filename under `tmp/phase9-demos/cache/`. The `load_demo` branch resolves the path based on `source`.
- Consider whether `memprotmd_url` belongs in the pure-layer `DEMO_MANIFEST` (it's a URL string — pure data, no `pymol`/`Qt` import, so it's fine in `setup_state.py` per the dependency-direction rule). Alternatively, construct the URL from the pdbid in `demos.py` (keeps the manifest minimal). Recommend constructing from pdbid (one less field, no URL-rot risk in the manifest): `url = MEMPROTMD_DATA_ROOT + f"memprotmd/simulations/{pdbid}_default_dppc/files/structures/at.pdb"` with `MEMPROTMD_DATA_ROOT = "https://memprotmd.bioch.ox.ac.uk/data/"` as a module constant in `demos.py`.
- The `randomize_state` function (`setup_state.py:230`) does `demo_id = rng.choice(list(DEMO_MANIFEST.keys()))` — adding 2 entries automatically includes them in the random-demo pool. Consider whether the large membrane demos should be in the random pool (they require network + are slow on first fetch) — possibly exclude `source='memprotmd'` from random selection, or weight them lower. Flag for the planner.

### `demos.load_demo` branch (proposed)

`demos.py:114` `load_demo(demo_id)` currently does:
```python
meta = DEMO_MANIFEST.get(demo_id)
path = os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])
win_path = to_windows_path(path)
cmd.load(win_path, object=obj_name, zoom=1)
```
Proposed branch on `source`:
```python
source = meta.get('source', 'bundled')
if source == 'bundled':
    # existing path (unchanged)
    path = os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])
    ...
elif source == 'memprotmd':
    obj_name = fetch_large_demo(demo_id, meta)   # NEW function in demos.py
    # fetch_large_demo handles cache-check / urllib-download / strip / compress / cmd.load
    # returns obj_name or None
return obj_name
```
`fetch_large_demo` is the new cmd-coupled function (lives in `demos.py` alongside `fetch_pdb`/`load_demo` — same dependency tier). It calls the pure-Python strip helper (which could live in `demos.py` or a new pure helper — but the strip is pure-Python and could be unit-tested in WSL if extracted to a pure function with no `cmd` import).

### Progress-dialog integration point

The modeless cancelable `QProgressDialog` is a **Qt** concern — it lives in `gui_setup.py` (the Qt+cmd layer), NOT in `demos.py` (cmd layer). `demos.fetch_large_demo` should accept an optional `progress_cb` callback (called with step-label + fraction) that `gui_setup` wires to the `QProgressDialog`. This keeps `demos.py` Qt-free (preserves the dependency direction: `setup_state` ← `demos` ← `gui_setup`). The planner should coordinate this with the SASBDB-fetch research (`09-RESEARCH-sasbdb.md`) — both large-fetch paths share the same progress-dialog pattern.

---

## Confidence + Open Risks (what's verified vs assumed; what needs human approval at checkpoint)

### Verified (HIGH confidence)

| Item | Evidence | Confidence |
|------|----------|------------|
| MemProtMD site reachable at `memprotmd.bioch.ox.ac.uk` | webfetch + curl HTTP 200 | HIGH |
| Prior `oxy.ac.uk` was a typo | repo sources (`spec.md:56`, `README.md:89`) use `ox.ac.uk`; `oxy` fails | HIGH |
| Download URL pattern `data/memprotmd/simulations/<pdbid>_default_dppc/files/structures/at.pdb` | decoded from `index.js` + curl GET returns real PDB content (TITLE/CRYST1/ATOM) for both 1gzm & 3gp6 | HIGH |
| No `_dry` server variant | `at_dry.pdb` → 404 for both entries | HIGH |
| License = CC-BY 4.0 International | exact string extracted from `index.js` + `static/license/by.svg` | HIGH |
| Corrected MemProtMD citations (Stansfeld 2015 Structure, Newport 2019 NAR) | Europe PMC title search + PMC6324062 full text + doi.org 200 | HIGH |
| Old DOI `10.1038/s41592-018-0220-9` is WRONG | doi.org → 404; Europe PMC no hit; Nature URL → 404 | HIGH |
| Strip targets = SOL + NA + CL | wet-vs-dry resn diff + atom-count math (76,018 = 75,789+116+113) for 3gp6; 1gzm wet confirms same resn set | HIGH |
| MemProtMD records everything as `ATOM` (zero `HETATM`) | grep on live wet + staged dry files | HIGH |
| `solvent` PyMOL selector matches `SOL` | `Seeker.cpp:838` classifies SOL→water; `Selector.cpp:649` solvent→SELE_SOLz | HIGH |
| RCSB metadata for 1GZM + 3GP6 (DOIs, titles, authors) | data.rcsb.org REST API 2026-08-14 | HIGH |
| Staged dry sample structure (19,221 atoms, DPP lipids preserved, no water) | direct file read + resn count | HIGH |
| Staged zip structure + compression ratio | `python3.6 zipfile.ZipFile` listing | HIGH |
| 3gp6 wet size (7.5MB) + dry size (1.5MB) + zipped (231KB) | curl size_download + staged file | HIGH |

### Assumed / UNVERIFIED (needs human confirmation or execute-time check)

| Item | Status | Action |
|------|--------|--------|
| **1gzm dry size** (raw + zipped) | UNVERIFIED — 1gzm not pre-staged in `tmp/` | Execute step: fetch 1gzm `at.pdb`, strip, record actual sizes in DATA_SOURCES.md |
| **PDB column padding for `NA`/`CL`** (right-justified `NA ` vs ` NA`?) | UNVERIFIED at byte level — `cut -c18-20` may have trimmed whitespace | Execute step: inspect raw bytes of a fetched wet file's NA/CL lines; finalize `STRIP_RESN` set accordingly (e.g. `{"SOL", "NA ", "CL "}` vs `{"SOL", " NA", " CL"}`) |
| **PyMOL `cmd.load` can read `.pdb.gz` directly** | UNVERIFIED — may be C-layer gzip support in PyMOL's importer | Execute step: test `cmd.load("file.pdb.gz")` headlessly via `run-conda-pymol.bat -cq`; if not, decompress-to-temp-then-load |
| **`inorganic` selector matches `NA`/`CL` recorded as `ATOM`** | UNVERIFIED at Python tier (C-level `SELE_INOz` logic not traceable) | Moot if we use explicit-resn strip (recommended); only relevant if the planner chooses the `cmd.remove("... and inorganic")` path |
| **Full MemProtMD `/api` surface** | UNVERIFIED — not needed (we use static-file GET, confirmed working) | None — static-file GET is sufficient and verified |
| **CC-BY attribution text exact wording** | Drafted (modeled on CC-BY 4.0 standard terms + the NAR 2019 citation) | Human approval at plan-check/execute checkpoint (AGENTS.md: "ALL claims and citations MUST be verified... and explicitly approved by a human") |

### Open risks for the planner

1. **The wrong-DOI cleanup** (RULE: don't propagate prior errors). `PITFALLS.md:521` and `SUMMARY.md:224` and `PROJECT.md:75` contain the wrong `oxy.ac.uk` domain and/or the wrong `10.1038/s41592-018-0220-9` DOI. The Phase 9 execute step should FIX these (it's a docs commit, fits the `docs(09):` scope) — but flag explicitly so the planner adds a task for it. Leaving the wrong DOI in the research files risks a future phase re-citing it.

2. **Network dependency for the 2 large demos.** The bundled 6 small demos work offline; the 2 MemProtMD demos require network on FIRST fetch (then cached). The plan should make this explicit in the UI (e.g. the demo dropdown could mark membrane demos with "(fetches on first use)" or grey them out when offline-detect + cache-miss). Coordinate with the SASBDB-fetch research for a consistent offline-UX pattern.

3. **`randomize_state` including large demos.** `setup_state.py:230` `rng.choice(list(DEMO_MANIFEST.keys()))` will now include 1gzm/3gp6 in the random-demo pool. A random pick of a membrane demo on an offline machine (cache-miss) would fail the fetch. The planner should decide: (a) exclude `source='memprotmd'` from random selection, (b) keep but handle fetch-failure gracefully (fall back to a bundled demo), or (c) keep and let the user see the fetch dialog. Recommend (a) — randomize should pick demos that "just work"; membrane demos are opt-in via explicit selection.

4. **`_dry` naming consistency.** The staged zip's inner filename drops `_dry` (`3gp6_default_dppc-atomistic.pdb` inside `3gp6_default_dppc-atomistic_dry.zip`). The execute step should pick ONE convention and apply it to both the raw cached file and any zip/gz inner name. Recommend `_dry` everywhere (it's the more honest descriptor — the file IS stripped).

5. **The "SCAM MG" / "Gromacs RunMostMost" TITLE lines.** The MemProtMD `at.pdb` files have GROMACS-default TITLE records (3gp6: "S C A M M G"; 1gzm: "Gromacs RunMostMost of All Computer Systems"), NOT the real protein names. PyMOL will load these as the object title. The plan may want to set a proper title after load (e.g. `cmd.set_name(obj, "1gzm")` already happens via `cmd.load(object=pdbid)`, but the internal TITLE record remains). Cosmetic — not blocking, but worth a note.

---

## Sources

### Primary (HIGH confidence — verified 2026-08-14)
- **MemProtMD site** `https://memprotmd.bioch.ox.ac.uk` — webfetch HTTP 200 (homepage); curl probes for `/`, `/about`, `/api`, `/cite`, `/sitemap.xml`, `/_ref/PDB/{1gzm,3gp6}/` (all 200); `/robots.txt` (404).
- **MemProtMD `sitemap.xml`** — revealed entry URL pattern `/_ref/PDB/<pdbid>/` and `/_ref/PDB/<pdbid>/_sim/<pdbid>_default_dppc/` for both 1gzm and 3gp6.
- **MemProtMD `index.js` bundle** (`/static/js/index.js`) — decoded: download URL construction (`DataRoot+"memprotmd/simulations/"+simName+"/files/structures/at.pdb"`), the 8 structure + 2 zip file targets, and the **license string "Licensed using a Creative Commons Attribution 4.0 International License."** + `static/license/by.svg`.
- **MemProtMD `at.pdb` (live, both entries)** — curl GET returned real PDB content (TITLE/CRYST1/MODEL/ATOM records). 3gp6: 7,524,042 bytes / 95,239 ATOM. 1gzm: 9,314,128 bytes / 117,898 ATOM. Residue-name composition verified by `grep "^ATOM" | cut -c18-20 | sort | uniq -c`.
- **MemProtMD `at_dry.pdb` probes** — 404 "No file is located at that path" for both entries → no server-side dry variant.
- **Europe PMC** `https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=title:%22MemProtMD%22` — returned the 2 real MemProtMD papers (Stansfeld 2015 Structure DOI 10.1016/j.str.2015.05.006; Newport 2019 NAR DOI 10.1093/nar/gky1047).
- **PMC6324062** (Newport 2019 NAR full text) — confirmed citation, CC-BY license line, "non-protein atoms are removed from the PDB entry prior to simulation" (DPPC is MemProtMD-derived), data-availability statement.
- **doi.org resolution** — `10.1016/j.str.2015.05.006` → 200 (verified); `10.1038/s41592-018-0220-9` → 404 (verified wrong); `10.1093/nar/gky1047` → 403 to curl (OUP bot-block) but resolves in browsers + confirmed via Europe PMC.
- **RCSB Data API** `https://data.rcsb.org/rest/v1/core/entry/{1GZM,3GP6}` — full entry metadata (DOIs, titles, authors, methods, resolutions, atom counts) for both entries.
- **Staged sample** `tmp/3gp6_default_dppc-atomistic_dry.pdb` (1,518,620 bytes) — direct Read (first 50 + last 20 lines) + bash `grep`/`cut`/`wc` for residue-name diversity, ATOM/HETATM counts, water/ion search, TER/chain count.
- **Staged zip** `tmp/3gp6_default_dppc-atomistic_dry.zip` — `python3.6 zipfile.ZipFile` listing (inner filename `3gp6_default_dppc-atomistic.pdb`, 1,518,620 → 230,891).
- **PyMOL 2.5.0 source** (`tmp/pymol-src/`) — `layer3/Selector.cpp:643,646,649` (organic/inorganic/solvent selector keywords); `layer3/Seeker.cpp:838-841` (SOL → water classification); `chempy/water_residues.py` (HOH/WAT bond templates — NOT SOL, but C-level Seeker handles SOL); `menu.py:1221,1256,1491` (menu "remove waters" uses `cmd.remove("(solvent and ...)")`).

### Secondary (MEDIUM — repo files referencing MemProtMD)
- `spec.md:56` — correct domain `memprotmd.bioch.ox.ac.uk`.
- `README.md:64-65,89` — demo table + data-courtesy line (correct domain).
- `.planning/PROJECT.md:75` — **TYPO** `memprotmd.bioch.oxy.ac.uk` (wrong domain; the source of prior "unreachable" findings).
- `.planning/REQUIREMENTS.md:69` — DEMO-02 requirement text.
- `.planning/ROADMAP.md:191` — success criterion 1 text.
- `.planning/research/PITFALLS.md:521,541` — prior MEDIUM-confidence licensing note (site "unreachable" due to typo) + **WRONG DOI** `10.1038/s41592-018-0220-9`.
- `.planning/research/SUMMARY.md:224` — same wrong DOI.
- Existing code: `biochemeleon/setup_state.py` (DEMO_MANIFEST, PDB_POOL, DEFAULTS, randomize_state, validate_state); `biochemeleon/demos.py` (load_demo, fetch_pdb, to_windows_path); `biochemeleon/data/demos/SOURCES.md` (current 6-demo attribution, to be consolidated into repo-root DATA_SOURCES.md).

### Tertiary (LOW — not needed; static-file GET is sufficient)
- MemProtMD `/api` full surface — UNVERIFIED (not needed; the static-file GET URL is confirmed working without the API).

---

## Metadata

**Confidence breakdown:**
- Site access + download URL: HIGH — site reachable, URL decoded from JS + verified by fetching real PDB content for both entries.
- Target entries (files/sizes/naming): HIGH for 3gp6 (staged sample + live fetch); MEDIUM for 1gzm dry size (not staged — execute-time fetch needed).
- License + citations: HIGH — CC-BY string extracted from JS; citations verified via Europe PMC + doi.org + PMC full text; old wrong DOI confirmed 404.
- Strip pipeline: HIGH — strip targets (SOL/NA/CL) empirically verified via wet-vs-dry diff + atom-count math; PyMOL selectors verified against C source.
- Compress + cache: HIGH for 3gp6 (staged zip inspected); MEDIUM for PyMOL `.pdb.gz` load capability (unverified — execute-time test needed).
- Manifest integration: MEDIUM — proposed schema (planner finalizes; backward-compat + randomize-state implications flagged).

**Research date:** 2026-08-14
**Valid until:** 2027-02-14 (MemProtMD is a stable academic database; the download URL pattern + CC-BY license are unlikely to change in 6 months. Re-verify the download URL + license string if execution happens after this date.)
