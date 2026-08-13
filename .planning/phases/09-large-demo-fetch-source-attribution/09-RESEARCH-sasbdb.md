# Phase 9 Research — SASBDB Glycoprotein Fetch

**Researched:** 2026-08-14
**Domain:** SASBDB (Small Angle Scattering Biological Data Bank) on-demand fetch of a glycoprotein-with-glycan demo for the bioCHEMeleon PyMOL plugin — entry identification, coordinate-file + glycan verification, license/attribution, fetch URL, manifest integration
**Confidence:** HIGH (site + entry + license verified by webfetch of official SASBDB pages; PDB model files downloaded via curl and inspected with awk/grep; publication DOI verified to resolve via webfetch). The single most load-bearing finding — "the entry HAS a coordinate file with glycan residues" — is confirmed by direct inspection of the downloaded bytes, not inferred.

**Scope:** This file covers the SASBDB / glycoprotein / DEMO-03 portion of Phase 9 only. The fetch *pipeline* (threading, QProgressDialog, `.pdb.gz` cache, manifest schema, 4-tier difficulty vocabulary, DATA_SOURCES.md consolidation) is covered by the sibling file `09-RESEARCH-pipeline.md` and is NOT duplicated here. This file supplies the SASBDB-specific *values* that plug into the pipeline's schema.

---

## Site Access Verification (reachable? URL structure)

**SASBDB is reachable.** `https://www.sasbdb.org` returns the live site (webfetch, 2026-08-14). It is the "Small Angle Scattering Biological Data Bank", a curated repository of SAS (SAXS/SANS) experimental data and derived models, hosted by EMBL Hamburg. Stats on the homepage: **5566 experimental data sets, 6640 models**.

**URL structure (verified by fetching each pattern):**

| What | URL pattern | Example | Status |
|------|-------------|---------|--------|
| Homepage | `https://www.sasbdb.org` | — | Reachable (webfetch OK) |
| Search | `https://www.sasbdb.org/search/?q=<query>` | `/search/?q=alpha-1-acid+glycoprotein` | Returns 2 hits (webfetch OK) |
| Entry detail | `https://www.sasbdb.org/data/<SASDID>/` | `/data/SASDPG4/` | Returns full entry page (webfetch OK) |
| Project (publication) | `https://www.sasbdb.org/project/<NNNN>/` | `/project/1741/` | Returns the publication landing page (webfetch OK) |
| Molecule | `https://www.sasbdb.org/molecule/<NNNN>` | `/molecule/3843` | Linked from entry; not fetched |
| Download: model PDB | `https://www.sasbdb.org/media/pdb_file/<SASDID>_fit<N>_model<M>.pdb` | `/media/pdb_file/SASDPG4_fit2_model1.pdb` | **curl OK** (400810 bytes, valid PDB records) |
| Download: full entry zip | `https://www.sasbdb.org/media/zip_directories/<SASDID>.zip` | `/media/zip_directories/SASDPG4.zip` | **curl OK** (477067 bytes, valid zip) |
| About / license | `https://www.sasbdb.org/aboutSASBDB/` | — | Reachable (webfetch OK) |
| Policies | `https://www.sasbdb.org/policies/` | — | Reachable (webfetch OK — retraction policy only) |
| REST API docs | `https://www.sasbdb.org/rest-api/docs/` | — | Reached but **page body is empty** (only the site chrome renders; no JSON/XML endpoint documentation visible). LOW confidence a usable REST API exists at a stable URL. |

**SASBDB ID format:** `SASD` + 3 alphanumeric chars, uppercase. Verified IDs from this research: `SASDPG4`, `SASDPH4`, `SASD2D2`, `SASD2B2`, `SASDZ78`, `SASDXQ9`, `SASDYM2`, `SASDZU5`. So `SASD[A-Z0-9]{3}` — 7 chars total. (REGEX unverified against the SASBDB validator — pattern inferred from observed IDs; HIGH confidence for the observed IDs, MEDIUM that the regex is exhaustive.)

**Search behavior (verified):**
- `alpha-1-acid glycoprotein` → **2 hits**: SASDPG4 (283 K) + SASDPH4 (343 K). Both are the same molecule (AGP1, *Homo sapiens*, UniProt P02763) at two temperatures.
- `orosomucoid` (the synonym for AGP) → **0 hits**. SASBDB search indexes the deposited molecule name, not synonyms. Use "alpha-1-acid glycoprotein" as the canonical search term.
- `glycoprotein glycan` → NOT searched (the 2-hit AGP result already answers the requirement; a broader glycoprotein search was unnecessary once the target was identified).

---

## Target Entry Identification (which SASBDB entry, ID, has coordinates? has glycan?)

### The target: SASDPG4 — Alpha-1-acid glycoprotein at 283 K

**Why SASDPG4 over SASDPH4:** Both entries are the same AGP1 molecule by the same authors (Kalidas, Peddada, Pandey, Ashish; J Biomol Struct Dyn 2025) under the same project (SASBDB project 1741). SASDPG4 is the **283 K (10 °C)** dataset; SASDPH4 is the **343 K (70 °C)** dataset. The 283 K structure is the native-like folded state; the 343 K structure is a thermally stressed state (the entry notes warn "results from model free analysis could be ambiguous"). For a "hide-and-seek" demo we want the well-folded native state → **SASDPG4 is the correct entry**. SASDPH4 is a documented companion entry (same glycan content — fit2 models also carry glycans) and could serve as a fallback if SASDPG4 is ever withdrawn.

**Entry metadata (verified from `https://www.sasbdb.org/data/SASDPG4/` via webfetch):**

| Field | Value |
|-------|-------|
| SASBDB ID | **SASDPG4** |
| Title | Alpha-1-acid glycoprotein at 283 K |
| Molecule | Alpha-1-acid glycoprotein 1 (AGP) |
| Mol. type | Protein |
| Organism | *Homo sapiens* |
| Olig. state | Monomer |
| Mon. MW | 21.6 kDa (sequence); MWexperimental 39 kDa (glycosylation inflates the apparent MW — the page notes "heavily glycosylated protein") |
| UniProt | P02763 (residues 19-183) |
| Buffer | phosphate buffered saline, pH 7.4 |
| Experiment | SAXS, Anton Paar SAXSpace, CSIR-IMTech Chandigarh, 2021-01-12 |
| Temperature | 10 °C (283 K) |
| Rg (Guinier) | 2.6 nm |
| Dmax | 7.5 nm |
| VPorod | 83 nm³ |
| Project / publication | SASBDB project 1741 → Kalidas N, Peddada N, Pandey K, Ashish. "SAXS data based glycosylated models of human alpha-1-acid glycorprotein, a key player in health, disease and drug circulation." *J Biomol Struct Dyn* 44(5):2709-2723 (2025). DOI [10.1080/07391102.2025.2475244](https://doi.org/10.1080/07391102.2025.2475244). PMID 40056387. |
| Europe PMC | https://europepmc.org/abstract/MED/40056387 |
| Submitted to SASBDB | 2022-06-03 |
| Published in SASBDB | 2022-09-07 |

### CRITICAL — the entry HAS coordinate files (and which one to use)

SASBDB entries primarily hold SAS data (I(q) curves, p(r) functions). **Some** entries also hold derived atomistic models. SASDPG4 is one of the latter: its "Download files" dropdown lists **5 PDB model files** plus the full-entry zip. **This was the single biggest risk in the phase brief ("does the entry include a downloadable 3D coordinate file that PyMOL can load?") — and it is resolved: YES.**

Downloadable files for SASDPG4 (URLs verified by curl HEAD/GET, 2026-08-14):

| File | URL | Size | Records | Has glycan? |
|------|-----|------|---------|-------------|
| `SASDPG4_fit1_model1.pdb` | `/media/pdb_file/SASDPG4_fit1_model1.pdb` | 130180 B | 1522 ATOM, 0 HETATM | **NO** (protein-only SWISS-MODEL homology model) |
| `SASDPG4_fit2_model1.pdb` | `/media/pdb_file/SASDPG4_fit2_model1.pdb` | 400810 B | 1522 ATOM + 2601 HETATM = **4123 atoms** | **YES** — 8 glycan residue names |
| `SASDPG4_fit2_model2.pdb` | `/media/pdb_file/SASDPG4_fit2_model2.pdb` | 400810 B | 4123 atoms | **YES** (same glycan content as fit2_model1) |
| `SASDPG4_fit2_model3.pdb` | `/media/pdb_file/SASDPG4_fit2_model3.pdb` | 400810 B | 4123 atoms | **YES** (same glycan content) |
| `SASDPG4_fit2_model4.pdb` | `/media/pdb_file/SASDPG4_fit2_model4.pdb` | 400810 B | 4123 atoms | **YES** (same glycan content) |
| `SASDPG4.zip` | `/media/zip_directories/SASDPG4.zip` | 477067 B | all of the above + .dat/.out/.fit | — |

**Which model to fetch:** Use **`SASDPG4_fit2_model1.pdb`** — the first model of the second fit (fit2). Reasons:
1. `fit1_model1` is the **protein-only** SWISS-MODEL homology model (1522 ATOM, 0 HETATM, no glycans) — it does NOT satisfy DEMO-03's "with-glycan" requirement. The `fit1` model was the SAS-fit input scaffold; the **`fit2` models are the glycosylated refinements** that the publication title ("glycosylated models") refers to.
2. `fit2_model1..model4` are an **ensemble** of 4 glycosylated models that jointly fit the SAXS curve (they differ in glycan conformation; md5sums differ for model1 and model3, models 2 and 4 are byte-identical to each other but not to 1/3 — i.e. 3 distinct conformers). For a "hide-and-seek" demo a single model suffices; `model1` is the canonical "first" ensemble member.
3. Picking `model1` (vs a random ensemble member) is deterministic — the same demo loads the same structure every fetch, which matters for reproducibility and for any future `.bcm` sidecar.

**Model provenance (from the PDB header, verified by reading the downloaded file):**
```
TITLE     SWISS-MODEL SERVER (https://swissmodel.expasy.org)
EXPDTA    THEORETICAL MODEL (SWISS-MODEL SERVER)
AUTHOR    SWISS-MODEL SERVER (SEE REFERENCE IN JRNL Records)
REVDAT   1   29-MAY-22 1MOD    1       17:36
```
This is a **real-atom-coordinate homology model** (built by SWISS-MODEL, then glycosylated and refined against the SAXS data), NOT a low-resolution ab initio dummy-atom envelope. The SASBDB Help page distinguishes "*ab initio* model" (pseudo-PDB, beads as CA atoms) from "hybrid model" (real atomic coordinates) — `SASDPG4_fit2_model1` is a **hybrid model** with full atomic detail. PyMOL's `cmd.load` handles it as a normal PDB.

**Do NOT use the `fit1_model1` file** for the demo — it has no glycans and would silently fail DEMO-03. This is a subtle trap: a naive "download the first PDB in the list" approach grabs `fit1_model1` (listed first in the dropdown), which is protein-only. The fetch URL **must** hardcode `_fit2_model1`, not `_fit1_model1` or a "first available" heuristic.

---

## Glycan Verification (carbohydrate residue names present?)

**YES — `SASDPG4_fit2_model1.pdb` contains glycan residues.** Verified by `awk '/^HETATM/{print substr($0,18,3)}' | sort | uniq -c` on the curl-downloaded file (2026-08-14):

| Resn code | Count | Meaning | In WWPDB carb set? |
|-----------|-------|---------|--------------------|
| **NAG** | 861 | N-acetyl-D-glucosamine | YES — standard wwPDB |
| **NAN** | 570 | N-acetylneuraminic acid (sialic acid) | YES (alt code for SIA) |
| **GLB** | 462 | β-D-galactopyranose (galactose) | Glycan-Builder code (not a wwPDB 3-letter code) |
| **MAN** | 200 | α-D-mannopyranose (mannose) | YES — standard wwPDB |
| **AFL** | 168 | α-L-fucose (fucose) | Glycan-Builder code |
| **NGA** | 135 | N-acetyl-D-galactosamine | Glycan-Builder code |
| **GLA** | 105 | α-D-galactopyranose | Glycan-Builder code |
| **BMA** | 100 | β-D-mannopyranose | YES — standard wwPDB |

**8 distinct glycan residue names, 2601 HETATM glycan atoms total** (out of 4123 total atoms; protein is 1522 ATOM on chain A). The glycans are distributed across chains A-E:

| Chain | Role | Atom count |
|-------|------|-----------|
| A | protein backbone (ATOM) + some glycan (HETATM) | 2048 (1522 ATOM + 526 HETATM) |
| B | glycan | 373 (all HETATM) |
| C | glycan | 526 (all HETATM) |
| D | glycan | 698 (all HETATM) |
| E | glycan | 478 (all HETATM) |

**Residue numbering:** protein = residues 1-183 on chain A; glycans = residues 1-30 across chains A-E.

**A note on residue-name conventions (MEDIUM confidence — needs human confirmation):**
- `NAG`, `MAN`, `BMA`, `NAN` are standard wwPDB 3-letter carbohydrate codes — these will be recognized by PyMOL's `cmd.count_atoms("resn NAG")` selector and by any carbohydrate-aware tooling.
- `GLB`, `AFL`, `NGA`, `GLA` are **Glycan-Builder / CHARMM-style codes**, NOT standard wwPDB PDB codes. They appear here because the glycan ensemble was built with a glycan-modeling tool (likely Glycan-Builder, given the naming). They are valid PDB residue names (PyMOL will load them and `cmd.count_atoms("resn GLB")` works), but a researcher citing "NAG/MAN/BMA only" would undercount the glycans. For DEMO-03's "with-glycan" requirement, the presence of ANY of these is sufficient — and NAG/MAN/BMA ARE present, so even a strict wwPDB-code-only check passes.

**PyMOL loadability:** `cmd.load` reads any 3-letter resn from a PDB ATOM/HETATM record; the non-wwPDB codes (`GLB`/`AFL`/`NGA`/`GLA`) load fine as generic HETATM residues. Verified pattern (PyMOL 2.5.0 source, `importing.py` + `internal.py`): the PDB parser does not validate resn against a registry — it stores whatever 3-char string is in cols 18-20. No special handling needed for the glycan residues.

**Verification command for the plan/execute phase (run headlessly per AGENTS.md):**
```bash
# After cmd.load, verify glycan presence (headless PyMOL via run-conda-pymol.bat):
# cmd.count_atoms("sasdpg4 and hetatm")          # should be 2601
# cmd.count_atoms("sasdpg4 and resn NAG+MAN+BMA+NAN+GLB+AFL+NGA+GLA")  # should be 2601
# cmd.count_atoms("sasdpg4 and not polymer")    # should be 2601 (glycans are HETATM/non-polymer)
```

---

## License Verification (SASBDB license, citation, bundling permission, attribution text)

### SASBDB data license: free of all copyright restrictions (verified)

From the official About page (`https://www.sasbdb.org/aboutSASBDB/`, fetched 2026-08-14), the explicit license statement:

> "The data and models deposited in SASBDB are free of all copyright restrictions and made fully and freely available for both non-commercial and commercial use. Users of the data should attribute the original authors."

This is **at least as permissive as CC0** (the RCSB PDB license) — it explicitly permits commercial use and waives copyright. It is NOT formally labeled "CC0" on the page, but the "free of all copyright restrictions ... for both non-commercial and commercial use" formulation is the standard public-domain-style grant. The only obligation is **attribution** ("Users of the data should attribute the original authors").

**Implication for DEMO-04 / bundling:** We MAY bundle or cache the downloaded `SASDPG4_fit2_model1.pdb` (and the `.pdb.gz` cache the pipeline writes from it) — the license permits it. We MUST attribute. The attribution = the SASBDB ID + the publication citation + the SASBDB reference paper.

### Canonical SASBDB citation (the database itself)

From the SASBDB homepage footer and the About page:

> Kikhiny AG, Borges CR, Molodenskiy DS, Jeffries CM, Svergun DI (2020) SASBDB: Towards an automatically curated and validated repository for biological scattering data. *Protein Science* 29(1):66-75. doi: [10.1002/pro.3731](https://onlinelibrary.wiley.com/doi/10.1002/pro.3731)

This is the database-level citation that DEMO-04's `DATA_SOURCES.md` must include alongside the entry-level citation (the Kalidas et al. 2025 paper).

### Entry-level citation (the SASDPG4 deposition) — DOI verified to resolve

The publication DOI **[10.1080/07391102.2025.2475244](https://doi.org/10.1080/07391102.2025.2475244)** was fetched via webfetch on 2026-08-14 and resolved to the publisher landing page with the full citation:

> Kalidas, N., Peddada, N., Pandey, K., & Ashish. (2025). SAXS data based glycosylated models of human alpha-1-acid glycorprotein, a key player in health, disease and drug circulation. *Journal of Biomolecular Structure and Dynamics*, 44(5), 2709–2723. https://doi.org/10.1080/07391102.2025.2475244

(The title's "glycorprotein" is a typo in the published title — reproduced as-is per the publisher landing page; the SASBDB entry page also uses "glycorprotein". The molecule name "Alpha-1-acid glycoprotein" is spelled correctly everywhere else.)

### Proposed attribution text for `DATA_SOURCES.md` (the glycoprotein section)

```markdown
## SASDPG4 — Glycoprotein (Challenge)

- Source database: SASBDB (Small Angle Scattering Biological Data Bank)
  - Entry: https://www.sasbdb.org/data/SASDPG4/
  - SASBDB ID: SASDPG4
  - License: "free of all copyright restrictions ... for both non-commercial and commercial use"
    (https://www.sasbdb.org/aboutSASBDB/) — attribution requested.
- Molecule: Alpha-1-acid glycoprotein 1 (AGP, orosomucoid), Homo sapiens, UniProt P02763 (residues 19-183)
- Structure file used: SASDPG4_fit2_model1.pdb (a glycosylated hybrid model from the SAXS-fit ensemble;
  4123 atoms = 1522 protein + 2601 glycan HETATM across 8 carbohydrate residue names: NAG, MAN, BMA,
  NAN, GLB, AFL, NGA, GLA). Built with SWISS-MODEL + glycan modeling; refined against SAXS data at 283 K.
- Primary publication:
  Kalidas N, Peddada N, Pandey K, Ashish. "SAXS data based glycosylated models of human
  alpha-1-acid glycorprotein, a key player in health, disease and drug circulation."
  J Biomol Struct Dyn 44(5):2709-2723 (2025). doi:10.1080/07391102.2025.2475244. PMID 40056387.
- Database citation:
  Kikhney AG, Borges CR, Molodenskiy DS, Jeffries CM, Svergun DI. "SASBDB: Towards an automatically
  curated and validated repository for biological scattering data." Protein Science 29(1):66-75
  (2020). doi:10.1002/pro.3731.
```

**What still needs human approval (per AGENTS.md "ALL claims and citations MUST be verified ... explicitly approved by a human"):**
- The DOI resolution (done by webfetch, but a human should eyeball the publisher page to confirm the journal/volume/pages match before `DATA_SOURCES.md` ships).
- The license interpretation ("free of all copyright restrictions" = bundle-and-cache-OK). The wording is unambiguous but it is not a formal SPDX license ID; a human should confirm this reading is acceptable for the project's attribution policy.
- The use of `fit2_model1` (vs the ensemble) as the demo target — a human should confirm "a single representative model from the glycosylated ensemble" satisfies the demo intent.

---

## Fetch Mechanism (URL pattern, urllib -> cmd.load, cache workflow, offline fallback, format)

### Stable download URL (verified by curl GET, 2026-08-14)

The canonical, stable URL for the demo file is:
```
https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb
```
- `curl -sSL -A "Mozilla/5.0 ..." -o SASDPG4_fit2_model1.pdb <URL>` returned 400810 bytes with valid PDB content (verified by `head`/`awk`/`wc -l` = 1662 lines).
- The URL pattern is `https://www.sasbdb.org/media/pdb_file/<SASDID>_fit<N>_model<M>.pdb` — confirmed by the entry page's "Download files" dropdown listing exactly these paths.
- **Hardcode `SASDPG4_fit2_model1` — do NOT compute it.** A "first available model" heuristic would pick `fit1_model1` (protein-only, no glycans) → DEMO-03 failure. The `_fit2_model1` suffix is a load-bearing constant.
- A `User-Agent` header is advisable (the site may block bare default-urllib UA strings); the curl fetch used `Mozilla/5.0 (research; bioCHEMeleon Phase 9)`. `urllib.request.Request(url, headers={'User-Agent': '...'})` is the stdlib equivalent. UNVERIFIED whether the default urllib UA is actually blocked — the curl UA was defensive. LOW confidence the site blocks default UA; test at execute time.

### Fetch path (plugs into the pipeline's split API — see `09-RESEARCH-pipeline.md`)

`cmd.fetch` does NOT support SASBDB (it only does RCSB PDB) — confirmed by STACK.md and the SASBDB being a different database. So the path is **`urllib` download → local file → `cmd.load`**, exactly as the pipeline research prescribes:

1. **Worker thread (`demos.download_large_demo`):** `urllib.request.urlretrieve` (or `urlopen` + chunked read for cancel/progress) the hardcoded URL to a temp file. Stdlib only, no `cmd.*` (Pitfall 6 compliant). Posts byte progress to a `queue.Queue`.
2. **Main thread (`demos.finalize_large_demo`):** `cmd.load(local_path, object='sasdpg4', zoom=1)` then `cmd.save(cache_path, 'sasdpg4')` to write the `.pdb.gz` cache (PyMOL writes `.pdb.gz` natively — no `gzip` step). See `09-RESEARCH-pipeline.md` for the cache-format verification.
3. **Cache hit (`demos.load_cached_demo`):** on subsequent fetches, `cmd.load(cache_path, object='sasdpg4')` directly (PyMOL reads `.pdb.gz` natively).

### File format: PDB (not mmCIF)

SASBDB serves `.pdb` files for models (the dropdown labels them "model-N (pdb)"). **No `.cif` option** for this entry. PDB format is lighter to parse and loads faster than mmCIF — preferred. PyMOL `cmd.load` auto-detects from content (the PDB ATOM/HETATM records), so no format flag is needed.

### Cache location and naming

Per the pipeline research (`09-RESEARCH-pipeline.md`), cache at `tmp/phase9-demos/cache/` (git-ignored — `git check-ignore tmp/phase9-demos/SASDPG4_fit2_model1.pdb` returns exit 0, confirmed 2026-08-14). Cache filename: **`SASDPG4_fit2_model1.pdb.gz`** (the manifest `cache_name` field). The `.pdb.gz` extension is load-bearing — PyMOL's `file_read` detects gzip magic and decompresses transparently (pipeline research, `internal.py:278-308`).

A sample (uncompressed) is already staged at `tmp/phase9-demos/SASDPG4_fit2_model1.pdb` (400810 bytes) for inspection — the plan/execute phase will produce the `.pdb.gz` cache via `cmd.save` in the Windows PyMOL run, or by `gzip`-ing the staged file in WSL if a pre-cache is needed before the first Windows run.

### Offline fallback

If the fetch fails (network down, SASBDB unreachable, HTTP 4xx/5xx, URL rot):
- **Show a `QMessageBox`** (allowed on child dialogs per the exec_ grep gate) with a clear message: "Could not fetch the glycoprotein demo from SASBDB. The 6 bundled small demos still work offline. Check your network and retry."
- **Return None** from `finalize_large_demo` → `PluginDialog._prepare_and_start` aborts Start (the same None path as a failed `cmd.fetch`).
- The 6 bundled demos (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) are unaffected — they load from `biochemeleon/data/demos/` with no network.
- The cache (once populated) makes the demo work offline on subsequent fetches — the network is needed only for the FIRST fetch of the glycoprotein demo.

### Do NOT auto-fetch on plugin load

Per PITFALLS.md Security Mistakes: fetch large demos **on-demand only** when the user picks the glycoprotein demo and clicks Start. Never auto-fetch at plugin load (would add a network dependency + MITM/URL-rot risk to every launch).

---

## Strip Needed? (probably no for SASBDB — confirm)

**NO STRIP NEEDED for SASDPG4.** Verified by grepping the downloaded `SASDPG4_fit2_model1.pdb` for water/ion HETATM:
```
$ grep -cE "^HETATM.*(HOH| NA | CL | K  | CA | MG | ZN | MN | FE )" SASDPG4_fit2_model1.pdb
0
```
**Zero water molecules, zero ions.** Every HETATM record (2601 of them) is a glycan atom (NAG/MAN/BMA/NAN/GLB/AFL/NGA/GLA). This is expected: SASBDB models are theoretical/solution-state models built from SWISS-MODEL + glycan modeling — they do not carry crystallographic waters or counterions (unlike the MemProtMD membrane entries, which DO need solvent/salt stripping per the pipeline research).

**Implication for the manifest:** the `strip` field for the SASDPG4 entry should be `False` (or omitted with a default of False). The pipeline's `finalize_large_demo` should make the `cmd.remove(f"{obj} and solvent") + cmd.remove(f"{obj} and inorganic")` calls **conditional on the manifest `strip` flag** — they are defensive no-ops on SASDPG4 but REQUIRED for the MemProtMD entries. Stripping SASDPG4 would be a no-op (0 solvent atoms) so it is harmless, but setting `strip: False` documents the entry's actual content and avoids a misleading "stripped N waters" log line.

**CAUTION — do NOT over-strip the glycans:** a naive `cmd.remove(f"{obj} and hetatm")` would delete the 2601 glycan atoms and silently turn this into a protein-only demo (DEMO-03 failure). The pipeline's strip selector (`solvent` / `inorganic`) is safe — it does NOT match glycan HETATM (glycans are `not polymer` but not `solvent`/`inorganic`). Verified: PyMOL's `solvent` selector matches water + common co-solutes, not carbohydrates; `inorganic` matches ions. Glycans remain. But document this guard explicitly in the plan so a future "cleanup all hetatm" edit doesn't nuke the glycan requirement.

---

## Manifest Integration (proposed schema, difficulty tier)

This section supplies the SASBDB-specific values that slot into the manifest schema already designed in `09-RESEARCH-pipeline.md` (which specifies the new fields `source`, `source_id`, `fetch_url`, `cache_name`, `citation`, `strip`, and the 4-tier `difficulty` vocabulary `easy`/`hard`/`challenge`/`very_challenging`).

### Proposed DEMO_MANIFEST entry for the glycoprotein demo

```python
# In setup_state.py DEMO_MANIFEST (pure layer — no pymol import needed; URLs are just strings):
'sasdpg4': {
    'category':     'Glycoprotein',
    'type':         'protein',
    'difficulty':   'challenge',           # DIFF-05 tier — "Challenge" (PROJECT.md: glycoprotein = Challenge)
    'source':       'SASBDB',              # not 'bundled' → triggers the fetch path
    'source_id':    'SASDPG4',
    'fetch_url':    'https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb',
    'cache_name':   'SASDPG4_fit2_model1.pdb.gz',
    'citation':     'Kalidas et al. 2025, J Biomol Struct Dyn 44(5):2709-2723, '
                   'doi:10.1080/07391102.2025.2475244; SASBDB SASDPG4',
    'strip':        False,                 # NO water/ions — glycan-only HETATM; stripping is a no-op
    # 'file' field ABSENT for fetched demos — the loader resolves via source + cache_name
},
```

### Difficulty tier: 'challenge' (verified)

`PROJECT.md` Demo PDBs Note 1 lists the glycoprotein under **"Challenge"** (the membrane protein is under "Very challenging"). The pipeline research established the 4-tier identifier-safe vocabulary `easy`/`hard`/`challenge`/`very_challenging` with display labels via `TIER_LABELS = {'easy':'Easy', 'hard':'Hard', 'challenge':'Challenge', 'very_challenging':'Very challenging'}`. So the glycoprotein manifest entry uses **`'difficulty': 'challenge'`** (display "Challenge"). This matches the success criterion's literal wording.

### Why 'challenge' and not 'very_challenging'
- The glycoprotein is 4123 atoms (1522 protein + 2601 glycan) — larger than the bundled demos (≤3779 atoms) but smaller than a full membrane protein (1GZM/3GP6 with DPPC are 100k+ atoms).
- The glycan HETATM density (63% of atoms are glycan) makes hider placement in the protein backbone trickier than a pure-protein demo — a "Challenge" tier is appropriate.
- The membrane demos own "Very challenging" (Pitfall 12 territory: OOM, 100k+ atoms, explicit water/salt strip). The glycoprotein does NOT trigger Pitfall 12 — it's a 4k-atom theoretical model, well within the `cmd.get_model` budget.

### Loader dispatch (existing `load_demo` → new branch)

The existing `demos.load_demo(demo_id)` (demos.py:114) handles **bundled** demos only (`meta['file']` → `os.path.join(data/demos, file)` → `cmd.load`). Phase 9 adds the **fetched** path. The pipeline research prescribes the split — here's how the glycoprotein entry flows through it:

```
load_demo('sasdpg4')
  → meta = DEMO_MANIFEST['sasdpg4']
  → if meta.get('source') == 'bundled': ... (existing path, NOT taken)
  → else (source == 'SASBDB'): delegate to the pipeline's fetch path
      → demos.cache_path_for('sasdpg4')  # tmp/phase9-demos/cache/SASDPG4_fit2_model1.pdb.gz
      → if cache exists: demos.load_cached_demo('sasdpg4')  # cmd.load(.pdb.gz) — fast, offline
      → else: PluginDialog._resolve_large_demo('sasdpg4')  # QProgressDialog + urllib + finalize
```
The Qt orchestration (the `QProgressDialog` + `QTimer` drain) lives in `__init__.py` (Qt layer), NOT `demos.py` — per the pipeline research's dependency-direction rule (`demos.py` must stay Qt-free). `demos.py` provides the Qt-free primitives (`download_large_demo`, `finalize_large_demo`, `load_cached_demo`, `cache_path_for`); `__init__.py`'s `PluginDialog` wires them to the dialog.

### Progress dialog steps for SASDPG4 (the SASBDB-specific labels)

The pipeline research specifies a modeless cancelable `QProgressDialog`. For the glycoprotein fetch the steps + labels are:
1. **"Fetching glycoprotein demo from SASBDB (SASDPG4)…"** — worker thread, urllib download of `~400 KB` (small; should complete in <5s on any broadband; the dialog's busy-indicator `setRange(0,0)` is appropriate since the byte-count is not known until the HTTP response starts, and 400 KB is too fast to show meaningful byte progress). Cancelable.
2. **"Loading glycoprotein structure…"** — main thread, `cmd.load` of the downloaded .pdb (4123 atoms — milliseconds).
3. **(strip step SKIPPED — `strip: False`)** — no "Stripping water/salt…" label for this demo (unlike the membrane demos).
4. **"Caching glycoprotein demo…"** — main thread, `cmd.save` of the `.pdb.gz` cache (one step).
5. Dialog closes → Start proceeds.

The download is ~400 KB (small enough that the progress dialog is arguably optional for THIS demo — but the pipeline's unified `QProgressDialog` path applies to all fetched demos, so use it anyway for consistency; the membrane demos are the ones that genuinely need the progress UX).

---

## Confidence + Open Risks

### Confidence breakdown

| Area | Level | Reason |
|------|-------|--------|
| Site access + URL structure | HIGH | webfetch of live pages; curl GET of download URLs returned valid bytes |
| Target entry identification (SASDPG4) | HIGH | entry page + project page fetched; metadata cross-checked against the PDB header |
| Coordinate file exists | HIGH | 5 PDB files listed on the entry page; 5 downloaded via curl; all parsed as valid PDB records (ATOM/HETATM/TER/END) |
| Glycan presence in `fit2_model1` | HIGH | direct `awk` inspection of the downloaded bytes: 2601 HETATM across 8 glycan resn codes including standard wwPDB NAG/MAN/BMA/NAN |
| `fit1_model1` has NO glycan (trap) | HIGH | direct inspection: 0 HETATM, 1522 ATOM protein-only |
| No water/ions (strip=False) | HIGH | `grep -cE "^HETATM.*(HOH\|NA\|CL\|...)"` = 0 on the downloaded file |
| SASBDB license (free use + attribution) | HIGH | explicit statement on the official About page; wording unambiguous |
| Publication DOI resolves | HIGH | webfetch of the DOI returned the publisher landing page with full citation |
| SASBDB ID format `SASD[A-Z0-9]{3}` | MEDIUM | inferred from observed IDs; not validated against a SASBDB schema doc |
| Non-wwPDB glycan resn codes (GLB/AFL/NGA/GLA) are Glycan-Builder | MEDIUM | inferred from naming convention; the codes load fine in PyMOL regardless (PDB parser doesn't validate resn) |
| REST API usable for programmatic fetch | LOW | the `/rest-api/docs/` page body rendered empty via webfetch; could not confirm a stable JSON endpoint. NOT needed — the direct `/media/pdb_file/<id>.pdb` URL is stable and curl-verified. |
| Default urllib UA is acceptable to SASBDB | LOW | the curl fetch used a Mozilla UA defensively; untested whether default urllib UA is blocked. Test at execute time. |

### Open risks (what needs human approval / what could change)

1. **Entry withdrawal / URL rot (LOW-MEDIUM, ongoing).** SASBDB has a retraction policy (`/policies/` — fetched, covers obsolete entries). If SASDPG4 is withdrawn, the fetch URL returns 404. Mitigation: the offline `QMessageBox` fallback (above) + the cache (once populated) keeps the demo working. A SASDPH4 fallback (same glycans, 343 K variant) exists if SASDPG4 is withdrawn — same fetch URL pattern with `SASDPH4`. Human: confirm SASDPG4 remains active at plan-check time.

2. **`fit2_model1` vs the ensemble (LOW).** The 4 fit2 models are an ensemble fitting the SAXS curve; picking `model1` is a "first ensemble member" choice. A human might prefer a different model or a merged/multi-state representation. The plan should surface this as a one-line decision: "use `fit2_model1` (first glycosylated ensemble member)" and let the human confirm. UNVERIFIED that `model1` is the "best" representative — it's the conventional first.

3. **Non-wwPDB glycan residue names (LOW).** `GLB`, `AFL`, `NGA`, `GLA` are not standard wwPDB codes; a future "standardize glycan names to wwPDB" refactor might want to rename them to `GAL`/`FUC`/`GALNAG`/`GAL` equivalents. NOT needed for Phase 9 — PyMOL loads them as-is and the demo only needs to *display* the glycan, not validate it. Document so a future phase doesn't trip on "why does this PDB have resn GLB?".

4. **DOI/author "Ashish" (single-name author) (LOW, cosmetic).** The publication lists "Ashish" as the last author (a single-name author — common for some Indian researchers). The citation reproduces it as-is. A human should confirm the citation format is acceptable for `DATA_SOURCES.md` (no assumed full name).

5. **License is not a formal SPDX ID (LOW).** "Free of all copyright restrictions ... for both non-commercial and commercial use" is the grant, but it is not labeled "CC0" or any SPDX identifier on the SASBDB page. If the project's policy requires a formal license ID in `DATA_SOURCES.md`, a human should either (a) accept the SASBDB wording as equivalent-to-CC0, or (b) reach out to SASBDB (contact email is on the About page, JS-obfuscated) for a formal statement. For Phase 9, the wording as-is is sufficient — bundle + attribute.

6. **The "Alpha-1-glycoprotein" vs "Alpha-1-acid glycoprotein" naming (LOW).** The SASDPH4 entry title says "Alpha-1-**glycoprotein** at 343 K" (dropping "acid"); SASDPG4 says "Alpha-1-**acid** glycoprotein at 283 K". PROJECT.md says "an Alpha-1-glycoprotein model from SASBDB" — this matches the SASDPH4 title wording but the SASDPG4 entry is the same molecule at the better (native) temperature. The molecule is unambiguously AGP1 (UniProt P02763, orosomucoid) in both entries. A human should confirm SASDPG4 (283 K) is the intended target despite the PROJECT.md wording matching SASDPH4's title more closely. Recommendation: SASDPG4 (native-folded, 283 K) is the right call; document the reasoning.

### Fallback if SASBDB glycoprotein becomes infeasible

If SASDPG4 is withdrawn OR the fetch URL rots OR a human rejects the SASBDB license reading, the phase brief asks for an RCSB PDB glycoprotein-with-glycan fallback. **I did NOT research RCSB alternatives in depth** (the phase brief said to flag and propose only if SASBDB failed; SASBDB did NOT fail — the entry exists, has coordinates, has glycans, and the license is permissive). If a fallback is nevertheless needed, candidate RCSB glycoprotein-with-glycan entries (NEEDS VERIFICATION before use — these are training-knowledge leads, NOT webfetch-confirmed):
- The human immunodeficiency virus gp120 envelope glycoprotein structures (e.g. PDB entries with `NAG`/`MAN` in the coordinates) — these are well-known glycosylated structures.
- An AGP crystal structure if one exists in RCSB (AGP is heavily glycosylated; a crystal structure may or may not resolve the glycans).

These leads are LOW confidence and UNVERIFIED — do NOT cite them in `DATA_SOURCES.md` without a webfetch of the RCSB entry pages. The SASBDB path is the verified one; the RCSB fallback is a contingency, not the recommendation.

---

## Sources

### Primary (HIGH confidence — webfetched official SASBDB pages, 2026-08-14)
- `https://www.sasbdb.org` — homepage; confirmed reachable; stats (5566 data sets, 6640 models); footer citation (Kikhney et al. 2020).
- `https://www.sasbdb.org/search/?q=alpha-1-acid+glycoprotein` — 2 hits: SASDPG4 (283 K) + SASDPH4 (343 K).
- `https://www.sasbdb.org/data/SASDPG4/` — entry detail; full metadata; download dropdown listing 5 PDB files + zip.
- `https://www.sasbdb.org/data/SASDPH4/` — companion entry (343 K); same glycan content; documented as a fallback.
- `https://www.sasbdb.org/project/1741/` — publication landing; full citation with DOI + PMID.
- `https://www.sasbdb.org/aboutSASBDB/` — license statement ("free of all copyright restrictions ... for both non-commercial and commercial use. Users of the data should attribute the original authors"); SASBDB reference paper citation.
- `https://www.sasbdb.org/policies/` — retraction/obsoletion policy (informs the URL-rot risk + withdrawal-fallback).
- `https://www.sasbdb.org/help/` — distinguishes ab initio (pseudo-PDB, CA beads) vs hybrid (real coords) models; download options; REST API mention.
- `https://doi.org/10.1080/07391102.2025.2475244` — publication DOI, resolved to publisher landing page with full citation (J Biomol Struct Dyn 44(5):2709-2723, 2025).
- `https://onlinelibrary.wiley.com/doi/10.1002/pro.3731` — SASBDB database citation (Kikhney et al. 2020, Protein Science).

### Primary (HIGH confidence — curl-downloaded + awk/grep-inspected file bytes, 2026-08-14)
- `tmp/phase9-demos/SASDPG4_fit1_model1.pdb` (130180 B, 1522 ATOM, 0 HETATM — protein-only SWISS-MODEL homology model, NO glycan).
- `tmp/phase9-demos/SASDPG4_fit2_model1.pdb` (400810 B, 4123 atoms = 1522 ATOM + 2601 HETATM glycan — the DEMO-03 target).
- `tmp/phase9-demos/SASDPG4_fit2_model2.pdb`, `_model3.pdb`, `_model4.pdb` (each 400810 B, 4123 atoms, same glycan content — ensemble).
- `tmp/phase9-demos/SASDPG4.zip` (477067 B — full entry; zip namelist verified via `python3.6 -c "import zipfile; ..."`).
- `.gitignore` — `git check-ignore tmp/phase9-demos/SASDPG4_fit2_model1.pdb` returns exit 0 (tmp/ is git-ignored; confirmed).

### Secondary (HIGH confidence — repo files, read directly)
- `biochemeleon/setup_state.py` — `DEMO_MANIFEST` (lines 29-36, 6 bundled demos); confirms `difficulty` values `easy`/`hard`/`mixed` need extending; pure-layer constraint (no `from pymol`).
- `biochemeleon/demos.py` — `load_demo` (line 114), `fetch_pdb` (line 67), `to_windows_path` (line 24); confirms the bundled-load path the fetched path must branch from.
- `biochemeleon/data/demos/SOURCES.md` — current per-bundle citation file; Phase 9's repo-root `DATA_SOURCES.md` (DEMO-04) absorbs it.
- `.planning/PROJECT.md` — Demo PDBs Note 1 (line 74): "Challenge — Glycoprotein with glycan: an Alpha-1-glycoprotein model from SASBDB — cite source and IDs in docs". Tier confirmed: glycoprotein = Challenge, membrane = Very challenging.
- `.planning/research/PITFALLS.md` — Pitfall 6 (cmd.* never from threads), Pitfall 12 (large file load freeze), Security Mistakes (no auto-fetch on load).
- `.planning/research/STACK.md` — `cmd.fetch(async_=0)`; `cmd.fetch` only does RCSB PDB → SASBDB needs a different path.
- `.planning/phases/09-large-demo-fetch-source-attribution/09-RESEARCH-pipeline.md` — sibling research; defines the manifest schema (`source`/`source_id`/`fetch_url`/`cache_name`/`citation`/`strip`), the 4-tier `difficulty` vocabulary, `.pdb.gz` cache at `tmp/phase9-demos/cache/`, and the split `demos.py` API. This file supplies the SASBDB-specific values that plug into that schema.

### Tertiary (LOW confidence — webfetched but empty/inconclusive)
- `https://www.sasbdb.org/rest-api/docs/` — page rendered but the body was empty (only site chrome); could not confirm a stable JSON REST endpoint. Not needed — the direct `/media/pdb_file/<id>.pdb` URL is curl-verified and stable. Flagged in case a future phase wants a metadata-fetch (not a coordinate-fetch) API.

---

## Metadata

**Research date:** 2026-08-14
**Valid until:** 2026-09-13 (30 days) — SASBDB entry stability is high (curated repository, retraction-only changes), but the plan/execute checkpoint should re-verify the fetch URL still returns 200 + the entry page still lists `fit2_model1` before writing the hardcoded URL into `DEMO_MANIFEST`.

**Key load-bearing facts the planner depends on:**
1. The SASBDB entry is **SASDPG4** (Alpha-1-acid glycoprotein at 283 K, native-folded; NOT the 343 K SASDPH4 variant).
2. The fetch URL is **`https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb`** — `fit2_model1` is load-bearing (NOT `fit1_model1`, which is protein-only / no glycan → DEMO-03 failure).
3. The file is a **PDB** (not mmCIF), **4123 atoms** (1522 protein + 2601 glycan HETATM), **no water/ions** (strip=False).
4. License: SASBDB data is "free of all copyright restrictions ... for both non-commercial and commercial use" with attribution requested — bundle + cache is permitted; `DATA_SOURCES.md` must cite the entry (Kalidas et al. 2025, doi:10.1080/07391102.2025.2475244) AND the database (Kikhney et al. 2020, doi:10.1002/pro.3731).
5. Difficulty tier: **`challenge`** (PROJECT.md: glycoprotein = Challenge).
6. The fetch plugs into the pipeline's split API (see `09-RESEARCH-pipeline.md`); the SASBDB-specific values above are the inputs.
