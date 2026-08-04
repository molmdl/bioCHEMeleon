---
phase: 02-setup-tab-configuration-bundled-demos
plan: 02
subsystem: data
tags: [demos, pdb, rcsb, citations, data-bundling, demo-01]

# Dependency graph
requires:
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: biochemeleon/ package scaffold (data/ subdirectory did not exist prior to this plan)
provides:
  - "6 bundled demo PDB files in biochemeleon/data/demos/ (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) — valid PDBs with HEADER + ATOM records"
  - "biochemeleon/data/demos/SOURCES.md — per-bundle citations (PDB ID, DOI, authors, journal, PMID, method) for all 6 demos"
  - "data/demos/ directory tracked by git (not gitignored) per DEMO-01 'bundle in the repo' requirement"
affects: [02-setup-tab-configuration-bundled-demos (02-03 demos.py load_demo resolves these files), 09-large-demo-fetch (DATA_SOURCES.md will absorb SOURCES.md)]

# Tech tracking
tech-stack:
  added: []  # pure data files, no code dependencies
  patterns:
    - "Bundled demo PDBs live under biochemeleon/data/demos/ (package-relative) so __file__-relative resolution in load_demo works identically from repo or installed plugin"
    - "Per-bundle SOURCES.md satisfies DEMO-01 'sources cited' until Phase 9 consolidates into repo-root DATA_SOURCES.md"

key-files:
  created:
    - biochemeleon/data/demos/1znf.pdb
    - biochemeleon/data/demos/1xdn.pdb
    - biochemeleon/data/demos/5e54.pdb
    - biochemeleon/data/demos/1k8p.pdb
    - biochemeleon/data/demos/2qbz.pdb
    - biochemeleon/data/demos/4wb3.pdb
    - biochemeleon/data/demos/SOURCES.md
  modified: []

key-decisions:
  - "Downloaded PDBs uncompressed (not gzipped) per research §4.2 — the 6 small demos are fine uncompressed"
  - "PDB filenames are lowercase to match the DEMO_MANIFEST 'file' field ({id}.pdb)"
  - "SOURCES.md content written verbatim from research §4.5 paste-ready citations (HIGH confidence — fields fetched from RCSB REST API on 2026-08-03)"

patterns-established:
  - "Pattern: Bundled data lives in biochemeleon/data/ (package-relative) so __file__-relative path resolution works from both repo and installed plugin locations"

# Metrics
duration: 1min
completed: 2026-08-04
---

# Phase 2 Plan 2: Bundled Demo PDBs Summary

**6 small demo PDB files downloaded from RCSB and bundled in biochemeleon/data/demos/ with per-bundle citations in SOURCES.md (DEMO-01 satisfied)**

## Performance

- **Duration:** ~1 min
- **Completed:** 2026-08-04
- **Tasks:** 1 (download + verify + write SOURCES.md + commit)
- **Files created:** 7 (6 PDBs + SOURCES.md)

## Accomplishments
- Downloaded 6 demo PDBs from RCSB (https://files.rcsb.org/download/{ID}.pdb): 1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3
- Verified each file is a valid PDB (starts with HEADER record, contains ATOM/HETATM records — not HTML 404 error pages)
  - 1znf: 15688 atom records (NMR, 37 models)
  - 1xdn: 2597 atom records (X-ray, 1.2 Å)
  - 5e54: 2844 atom records (XFEL, 2.3 Å)
  - 1k8p: 555 atom records (X-ray, 2.4 Å)
  - 2qbz: 3408 atom records (X-ray, 2.6 Å)
  - 4wb3: 3779 atom records (X-ray, 2.0 Å)
- Wrote biochemeleon/data/demos/SOURCES.md (64 lines) with per-bundle citations: PDB ID, DOI, title, authors, publication (journal + vol/pp + year + PMID), method, and notes for all 6 demos
- Verified data/demos/ is NOT gitignored (git tracks the files — DEMO-01 requires bundling in the repo)
- All 4 must-have truths verified: 6 valid PDBs exist, SOURCES.md cites all 6 with full metadata, filenames lowercase match DEMO_MANIFEST 'file' field, directory tracked by git

## Task Commits

1. **feat(02-02): bundle 6 demo PDBs with cited sources (DEMO-01)** — `af6e93e` (7 files: 6 PDBs + SOURCES.md, 43176 insertions)

**Plan metadata:** pending (docs commit after this SUMMARY)

## Files Created/Modified
- `biochemeleon/data/demos/1znf.pdb` — Zinc finger DNA-binding domain (Protein Easy demo, 212 atoms NMR)
- `biochemeleon/data/demos/1xdn.pdb` — RNA editing ligase 1 (Protein Hard demo, 2597 atoms X-ray)
- `biochemeleon/data/demos/5e54.pdb` — Adenine riboswitch aptamer (RNA Easy demo, 2844 atoms XFEL)
- `biochemeleon/data/demos/1k8p.pdb` — Human telomeric G-quadruplex (DNA Easy demo, 555 atoms X-ray)
- `biochemeleon/data/demos/2qbz.pdb` — M-Box metal-sensing riboswitch (RNA Hard demo, 3408 atoms X-ray)
- `biochemeleon/data/demos/4wb3.pdb` — C5a + L-RNA/L-DNA aptamer NOX-D20 (Mixed demo, 3779 atoms X-ray)
- `biochemeleon/data/demos/SOURCES.md` — Per-bundle citations (PDB ID + DOI + authors + journal + PMID + method) for all 6 demos

## Decisions Made
- **Downloaded uncompressed PDBs (not .pdb.gz).** Rationale: research §4.2 explicitly states "the 6 small demos are fine uncompressed"; gzip would add a decompression step in load_demo for negligible size savings on small files.
- **Filenames lowercase ({id}.pdb).** Rationale: matches the DEMO_MANIFEST 'file' field exactly (e.g. `'file': '1znf.pdb'`), so `os.path.join(..., meta['file'])` resolves correctly. PyMOL object names are also conventionally lowercase.
- **SOURCES.md content written verbatim from research §4.5.** Rationale: research already fetched and validated all citation fields from the RCSB REST API (HIGH confidence). Rewriting from scratch would risk transcription errors; the paste-ready content was reviewed during research.

## Deviations from Plan
None — plan executed exactly as written. The single task (download + verify + write SOURCES.md + commit) followed the plan's steps verbatim.

## Issues Encountered
None. All 6 downloads succeeded on the first curl pass; all 6 files passed the HEADER + ATOM/HETATM validity check; SOURCES.md wrote cleanly; git tracked the directory (not gitignored).

`rg` (ripgrep) is not installed in the WSL shell, so the plan's `rg`-based verification commands were substituted with `grep` (functionally equivalent). This did not affect verification outcomes.

## User Setup Required
None — no external service configuration. RCSB PDB is a public CC0-licensed data source.

## Next Phase Readiness
- **Ready for Plan 02-03** (Populate demos.py + gui_setup.py): the 6 PDB files exist at the exact paths `load_demo` will resolve via `os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])`. The SOURCES.md content is complete for the Phase-2 smoke test (Plan 02-04 Test 4 step 4).
- **Ready for Phase 9** (Large Demo Fetch): SOURCES.md will be absorbed into the consolidated repo-root DATA_SOURCES.md (DEMO-04). The 6 bundled IDs are the seed set; Phase 9 extends DEMO_MANIFEST and DATA_SOURCES.md with fetched large demos.
- **No blockers or concerns.** All files are valid, committed, and match the DEMO_MANIFEST contract from Plan 02-01.

---
*Phase: 02-setup-tab-configuration-bundled-demos*
*Completed: 2026-08-04*
