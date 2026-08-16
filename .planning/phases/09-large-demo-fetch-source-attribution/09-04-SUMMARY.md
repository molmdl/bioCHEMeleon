---
phase: 09-large-demo-fetch-source-attribution
plan: 04
subsystem: docs
tags: [attribution, licensing, cc-by-4.0, cc0, memprotmd, sasbdb, rcsb-pdb, citations, doi, sasbdb, sources]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: DEMO_MANIFEST in biochemeleon/setup_state.py (the 9 demos + PDB_POOL that DATA_SOURCES.md documents)
  - phase: 09-large-demo-fetch-source-attribution (plans 09-01, 09-02, 09-03)
    provides: The bundled/fetched demos that require attribution; the empirical strip-target counts (3gp6: 76,018 atoms stripped) recorded from 09-02 execute-time fetches
  - phase: 09-large-demo-fetch-source-attribution research (09-RESEARCH-pipeline.md, 09-RESEARCH-memprotmd.md, 09-RESEARCH-sasbdb.md)
    provides: Verified licenses (MemProtMD CC-BY 4.0, SASBDB free-of-copyright, RCSB CC0 1.0) and the corrected citations (Stansfeld 2015 Structure, Newport 2019 NAR, Kalidas 2025, Kikhney 2020)
provides:
  - DATA_SOURCES.md at repo root — single source of truth for all 9 demos + PDB_POOL + PyMOL attribution
  - Corrected MemProtMD attribution (CC-BY 4.0 + Stansfeld 2015 Structure + Newport 2019 NAR) replacing the wrong 10.1038/s41592-018-0220-9 DOI that 404s
  - Corrected memprotmd.bioch.ox.ac.uk domain (the prior oxy.ac.uk typo caused a false "site unreachable" finding)
  - SOURCES.md reduced to a 3-line stub pointer (preserves the old path for any hardcoded external references)
  - Human-verified license/citation accuracy (SC3 MemProtMD per-entry licenses verified before bundling)
affects: [10-release-prep (DATA_SOURCES.md is the canonical attribution for any release/publication), any future phase that re-cites PDB IDs / DOIs / MemProtMD / SASBDB entries, README.md if it ever duplicates attribution]

# Tech tracking
tech-stack:
  added: []  # Pure documentation — no libraries
  patterns:
    - "Repo-root DATA_SOURCES.md as single source of truth for attribution; legacy SOURCES.md reduced to a stub pointer to preserve backward compatibility with hardcoded references"
    - "License-block verbatim copy from research records (CC-BY 4.0 attribution text copied verbatim from 09-RESEARCH-memprotmd.md:154-166) so any future license-text edits stay traceable to a verified source"
    - "Empirical strip-target byte counts recorded alongside each fetched entry (e.g., 3gp6: SOL 75,789 + NA 116 + CL 113 = 76,018 stripped; wet 95,239 → dry 19,221) so future fetches can verify they reproduced the expected result"
    - "Glycan HETATM over-strip caution: a `cmd.remove hetatm` would delete 2601 glycan atoms and silently fail DEMO-03; the safe selector is solvent/inorganic only"

key-files:
  created:
    - DATA_SOURCES.md  # repo root, 202 lines, 5 sections
  modified:
    - biochemeleon/data/demos/SOURCES.md  # reduced from ~66 lines to a 3-line stub pointer
    - .planning/PROJECT.md  # line 75: oxy.ac.uk -> ox.ac.uk domain typo
    - .planning/research/PITFALLS.md  # line 517 (MEDIUM->HIGH confidence), line 521 (wrong DOI -> corrected citations), line 541 (Sources section), line 353 (Security Mistakes table — deviation auto-fix)
    - .planning/research/SUMMARY.md  # line 224 (wrong DOI -> corrected citations)

key-decisions:
  - "DATA_SOURCES.md lives at repo root (NOT inside biochemeleon/) per 09-RESEARCH-pipeline.md:538 — discoverable from the project root for any release/publication tooling"
  - "SOURCES.md kept as a stub pointer rather than deleted to preserve backward compatibility with any hardcoded external references (09-RESEARCH-pipeline.md:542-544)"
  - "MemProtMD citations corrected to Newport 2019 NAR (10.1093/nar/gky1047, database paper, primary) + Stansfeld 2015 Structure (10.1016/j.str.2015.05.006, methodology) — the prior 10.1038/s41592-018-0220-9 DOI returns 404"
  - "SASDPG4_fit2_model1.pdb (NOT fit1_model1) cited in §3 — fit1 is protein-only with NO glycan; using it would silently fail DEMO-03 (09-RESEARCH-sasbdb.md:97)"
  - "Human-verify checkpoint is the SC3 gate: per AGENTS.md 'ALL claims and citations MUST be verified... and explicitly approved by a human' — the checkpoint approval is the formal record of license verification before bundling"
  - "Reproduced the published title's 'glycorprotein' typo verbatim in §3 (per 09-RESEARCH-sasbdb.md:170) rather than silently correcting it — preserves the citation's fidelity to the published record"

patterns-established:
  - "Pattern: Repo-root DATA_SOURCES.md is the single attribution source of truth; legacy SOURCES.md is a stub pointer (not deleted) to avoid breaking hardcoded external references"
  - "Pattern: License text is copied verbatim from the research record that verified it, so any future license-text edit is traceable to a verified source"
  - "Pattern: Empirical strip-target counts are recorded alongside each fetched entry as a self-check for future re-fetches"

# Metrics
duration: ~2 days wall-clock (checkpoint wait ~2d, active execution ~10 min between Task 1 commit at 2026-08-14T01:33:47Z and Task 2 commit at 2026-08-14T01:35:59Z)
completed: 2026-08-16
---

# Phase 9 Plan 4: Data Sources Attribution Summary

**DATA_SOURCES.md at repo root consolidating all 9 demos + PDB_POOL + PyMOL attribution with verified CC-BY 4.0 / CC0 / SASBDB-free licenses; MemProtMD domain typo + wrong DOI corrected across research records and human-approved for SC3 bundling.**

## Performance

- **Duration:** ~2 days wall-clock (active execution ~10 min; ~2-day checkpoint wait for human license/citation verification)
- **Started:** 2026-08-14T01:33Z (Task 1 first commit timestamp)
- **Completed:** 2026-08-16T09:39Z (SUMMARY creation, post-checkpoint approval)
- **Tasks:** 3 (2 auto + 1 checkpoint:human-verify)
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- **`DATA_SOURCES.md` created at repo root** (202 lines, 5 sections) as the single source of truth for all attribution: §1 six bundled RCSB PDB demos under CC0 1.0; §2 two MemProtMD membrane-protein demos (1GZM, 3GP6) under CC-BY 4.0 with corrected citations; §3 SASBDB glycoprotein (SASDPG4_fit2_model1) under "free of all copyright restrictions" license; §4 PDB_POOL blanket RCSB CC0; §5 PyMOL (Schrödinger LLC).
- **MemProtMD attribution corrected and verified:** the wrong DOI `10.1038/s41592-018-0220-9` (which 404s) was replaced with the verified Stansfeld 2015 Structure (`10.1016/j.str.2015.05.006`) + Newport 2019 NAR (`10.1093/nar/gky1047`) citations across DATA_SOURCES.md, PITFALLS.md, and SUMMARY.md. The CC-BY 4.0 license string was taken verbatim from 09-RESEARCH-memprotmd.md:154-166.
- **MemProtMD domain typo corrected:** `memprotmd.bioch.oxy.ac.uk` → `memprotmd.bioch.ox.ac.uk` in PROJECT.md — the typo caused a prior false "site unreachable" finding; site is now confirmed reachable (HTTP 200).
- **SASBDB glycoprotein demo documented with load-bearing caution:** §3 records `SASDPG4_fit2_model1.pdb` (NOT fit1_model1 — fit1 is protein-only with NO glycan, would silently fail DEMO-03 per 09-RESEARCH-sasbdb.md:97), the 4123-atom breakdown (1522 protein + 2601 glycan HETATM across 8 resn), the glycan-over-strip caution, and the Kalidas 2025 + Kikhney 2020 citations.
- **`biochemeleon/data/demos/SOURCES.md` reduced to a 3-line stub pointer** to `/DATA_SOURCES.md` — preserves the old path for any hardcoded external references while consolidating content at the repo root.
- **Human license/citation verification gate cleared:** the checkpoint:human-verify (Task 3) was approved by the user, satisfying SC3's "MemProtMD per-entry licenses verified before bundling" requirement per AGENTS.md ("ALL claims and citations MUST be verified... and explicitly approved by a human").

## Task Commits

Each task was committed atomically:

1. **Task 1: Create repo-root DATA_SOURCES.md + stub SOURCES.md** — `3415d88` (docs)
2. **Task 2: Fix oxy.ac.uk typo (PROJECT.md) + wrong DOI (PITFALLS.md + SUMMARY.md)** — `a360e34` (fix)
3. **Task 3: checkpoint:human-verify — License + citation accuracy review** — (no commit; checkpoint only, user approved)

**Plan metadata:** this `docs(09-04)` commit (SUMMARY only).

## Files Created/Modified

- `DATA_SOURCES.md` (created, repo root, 202 lines) — Single source of truth: §1 bundled RCSB PDB demos (CC0 1.0); §2 MemProtMD demos 1GZM + 3GP6 (CC-BY 4.0 + corrected citations); §3 SASBDB glycoprotein SASDPG4_fit2_model1 (free-use license); §4 PDB_POOL blanket RCSB CC0; §5 PyMOL (Schrödinger LLC).
- `biochemeleon/data/demos/SOURCES.md` (modified) — Reduced to a 3-line stub pointer to `/DATA_SOURCES.md`.
- `.planning/PROJECT.md` (modified, line 75) — `memprotmd.bioch.oxy.ac.uk` → `memprotmd.bioch.ox.ac.uk`.
- `.planning/research/PITFALLS.md` (modified) — line 517 confidence MEDIUM→HIGH; line 521 wrong DOI replaced with corrected citations + "site reachable" note; line 541 same fix in Sources section; line 353 stale 'Stansfeld et al. Nat. Methods 2018' reference in Security Mistakes table (deviation auto-fix).
- `.planning/research/SUMMARY.md` (modified, line 224) — Same wrong-DOI → corrected-citations fix.

## Decisions Made

- **Repo-root location for DATA_SOURCES.md** (not inside `biochemeleon/`) per 09-RESEARCH-pipeline.md:538 — keeps attribution discoverable from the project root for release/publication tooling.
- **SOURCES.md kept as a stub pointer** (not deleted) per 09-RESEARCH-pipeline.md:542-544 — preserves backward compatibility with any hardcoded external references.
- **MemProtMD citations = Newport 2019 NAR (primary database paper) + Stansfeld 2015 Structure (methodology)** — the prior `10.1038/s41592-018-0220-9` DOI returns 404; the corrected DOIs are confirmed resolvable.
- **SASDPG4_fit2_model1.pdb** (not fit1_model1) cited in §3 — fit1 is protein-only with no glycan; using it would silently fail DEMO-03 (09-RESEARCH-sasbdb.md:97).
- **Published title's "glycorprotein" typo reproduced verbatim** in §3 per 09-RESEARCH-sasbdb.md:170 — preserves citation fidelity to the published record rather than silently correcting.
- **Human-verify checkpoint is the SC3 gate** — per AGENTS.md "ALL claims and citations MUST be verified... and explicitly approved by a human"; the checkpoint approval is the formal record of license verification before bundling.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stale wrong citation venue in PITFALLS.md Security Mistakes table**

- **Found during:** Task 2 (Fix oxy.ac.uk typo + wrong DOI in research records)
- **Issue:** The plan listed PITFALLS.md:521 + :541 and SUMMARY.md:224 as the wrong-DOI sites. While editing PITFALLS.md, the executor found a *third* wrong-citation instance at PITFALLS.md:353 in the Security Mistakes table — a stale `Stansfeld et al. Nat. Methods 2018` reference that, if left in place, would continue to mislead future readers about the MemProtMD citation venue even after the :521 and :541 corrections.
- **Fix:** Applied the same wrong-citation → corrected-citations transformation to PITFALLS.md:353 (replaced the Nat. Methods 2018 reference with the corrected Stansfeld 2015 Structure + Newport 2019 NAR citations). Documented inline in the Task 2 commit message as a Rule 1 auto-fix.
- **Files modified:** `.planning/research/PITFALLS.md` (line 353)
- **Verification:** After the fix, `grep "10.1038/s41592-018-0220-9" .planning/research/PITFALLS.md` returns zero matches — every wrong-DOI instance in PITFALLS.md is now gone, not just the two the plan called out.
- **Committed in:** `a360e34` (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** The auto-fix tightens the plan's stated goal ("wrong DOI removed from PITFALLS.md"). The plan named two sites; the executor found and fixed a third. No scope creep — the third site is the same wrong citation the plan already targeted, just at a location the plan didn't enumerate.

## Issues Encountered

None — both auto tasks completed on the first pass. The checkpoint wait was ~2 days wall-clock (the user approved on 2026-08-16 after the execution on 2026-08-14); this is normal human-verification latency, not a defect.

## User Setup Required

None — no external service configuration required. This plan produced only documentation and research-record corrections.

## Next Phase Readiness

- **SC3 satisfied:** `DATA_SOURCES.md` documents all PDB IDs, DOIs, SASBDB IDs, and MemProtMD attribution; MemProtMD per-entry licenses (CC-BY 4.0) verified and human-approved before bundling.
- **Research-record errors corrected:** no future phase can re-cite the wrong DOI `10.1038/s41592-018-0220-9` or the `oxy.ac.uk` domain typo — both are now absent from `.planning/` (verified by the user's item-6 checkpoint review: the only remaining matches are planning docs that *reference the issue* as documentation, which is acceptable).
- **Blockers/concerns:** None. DATA_SOURCES.md is ready to serve as the canonical attribution source for any Phase 10 release/publication work and for any future phase that needs to cite a PDB ID / DOI / MemProtMD / SASBDB entry.

---
*Phase: 09-large-demo-fetch-source-attribution*
*Completed: 2026-08-16*
