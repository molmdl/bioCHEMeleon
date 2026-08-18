# DATA_SOURCES.md — bioCHEMeleon demo data sources & licenses

All external data sources for the bioCHEMeleon demo set. Every PDB ID, DOI,
SASBDB ID, and MemProtMD attribution is listed here with its license.
Verify before redistribution (DEMO-04).

---

## 1. Bundled small demos (RCSB PDB) — CC0 1.0

All PDB entries are © RCSB PDB, licensed CC0 1.0 (Public Domain Dedication).
https://www.rcsb.org/pages/policies
Cite: PDB ID + DOI + the corresponding publication + PyMOL (Schrödinger LLC).

### 1znf — Protein (Easy)
- PDB ID: 1ZNF
- DOI: https://doi.org/10.2210/pdb1znf/pdb
- Title: Three-dimensional solution structure of a single zinc finger DNA-binding domain.
- Authors: Lee, M.S.; Gippert, G.P.; Soman, K.V.; Case, D.A.; Wright, P.E.
- Publication: Science, vol. 245, pp. 635-637 (1989). PMID 2503871.
- Method: Solution NMR (37 models).

### 1xdn — Protein (Hard)
- PDB ID: 1XDN
- DOI: https://doi.org/10.2210/pdb1xdn/pdb
- Title: High resolution crystal structure of a key editosome enzyme from Trypanosoma brucei: RNA editing ligase 1.
- Authors: Deng, J.; Schnaufer, A.; Salavati, R.; Stuart, K.D.; Hol, W.G.
- Publication: J. Mol. Biol., vol. 343, pp. 601-613 (2004). DOI 10.1016/j.jmb.2004.08.041. PMID 15465048.
- Method: X-ray diffraction, 1.2 Å resolution.

### 5e54 — RNA (Easy)
- PDB ID: 5E54
- DOI: https://doi.org/10.2210/pdb5e54/pdb
- Title: Structures of riboswitch RNA reaction states by mix-and-inject XFEL serial crystallography.
- Authors: Stagno, J.R.; Liu, Y.; et al.; Wang, Y.-X. (full list in PDB header)
- Publication: Nature, vol. 541, pp. 242-246 (2017). DOI 10.1038/nature20599. PMID 27841871.
- Method: X-ray free-electron laser (XFEL) serial crystallography, 2.3 Å.
- Notes: Adenine riboswitch aptamer domain, apo (ligand-free) state.

### 1k8p — DNA (Easy)
- PDB ID: 1K8P
- DOI: https://doi.org/10.2210/pdb1k8p/pdb
- Title: Crystal structure of parallel quadruplexes from human telomeric DNA.
- Authors: Parkinson, G.N.; Lee, M.P.; Neidle, S.
- Publication: Nature, vol. 417, pp. 876-880 (2002). DOI 10.1038/nature755. PMID 12050675.
- Method: X-ray diffraction, 2.4 Å.
- Notes: Human telomeric G-quadruplex, parallel-stranded.

### 2qbz — RNA (Hard)
- PDB ID: 2QBZ
- DOI: https://doi.org/10.2210/pdb2qbz/pdb
- Title: Structure and mechanism of a metal-sensing regulatory RNA.
- Authors: Dann III, C.E.; Wakeman, C.A.; Sieling, C.L.; Baker, S.C.; Irnov, I.; Winkler, W.C.
- Publication: Cell, vol. 130, pp. 878-892 (2007). DOI 10.1016/j.cell.2007.06.051. PMID 17803910.
- Method: X-ray diffraction, 2.6 Å.
- Notes: M-Box riboswitch aptamer domain (metal-sensing regulatory RNA).

### 4wb3 — Mixed (Protein + Nucleic acid)
- PDB ID: 4WB3
- DOI: https://doi.org/10.2210/pdb4wb3/pdb
- Title: Structural basis for the targeting of complement anaphylatoxin C5a using a mixed L-RNA/L-DNA aptamer.
- Authors: Yatime, L.; Maasch, C.; Hoehlig, K.; Klussmann, S.; Andersen, G.R.; Vater, A.
- Publication: Nat. Commun., vol. 6, p. 6481 (2015). DOI 10.1038/ncomms7481. PMID 25901944.
- Method: X-ray diffraction, 2.0 Å.
- Notes: Mirror-image L-RNA/L-DNA aptamer NOX-D20 in complex with mouse C5a-desArg complement anaphylatoxin (protein/NA hybrid).

### License
RCSB PDB data files are available under the CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
(https://www.rcsb.org/pages/policies). Attribution is requested (above) per wwPDB policy.

---

## 2. Fetched membrane-protein demos (MemProtMD + RCSB) — DEMO-02 — CC-BY 4.0

These demos are fetched on demand from MemProtMD (https://memprotmd.bioch.ox.ac.uk).
The membrane coordinates (DPPC bilayer) and the atomistic embedding are derived from
MemProtMD and licensed under the Creative Commons Attribution 4.0 International License
(https://creativecommons.org/licenses/by/4.0/). Attribution required:

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

### 1GZM — bacteriorhodopsin (Very challenging)
- PDB ID: 1GZM (RCSB, CC0) — DOI: https://doi.org/10.2210/pdb1gzm/pdb
- Primary citation: Li J, Edwards P, Burghammer M, Villa C, Schertler GFX.
  J Mol Biol 343:1409 (2004). DOI: 10.1016/j.jmb.2004.08.090. PMID 15491621.
- MemProtMD download URL: https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/1gzm_default_dppc/files/structures/at.pdb
- MemProtMD entry page: https://memprotmd.bioch.ox.ac.uk/_ref/PDB/1gzm/
- Wet file size: 9,314,128 bytes (9.3 MB, 117,898 atoms)
- Dry size: to be verified at execute time (1gzm was not pre-staged at research time;
  estimated ~2 MB raw / ~300 KB compressed — the human-verify checkpoint confirms)

### 3GP6 — PagP beta-barrel (Very challenging)
- PDB ID: 3GP6 (RCSB, CC0) — DOI: https://doi.org/10.2210/pdb3gp6/pdb
- Primary citation: Cuesta-Seijo JA, Neale C, Khan MA, Moktar J, Tran CD, Bishop RE,
  Pomes R, Prive GG. Structure 18:1210-1219 (2010). DOI: 10.1016/j.str.2010.06.014.
  PMID 20826347.
- MemProtMD download URL: https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/3gp6_default_dppc/files/structures/at.pdb
- MemProtMD entry page: https://memprotmd.bioch.ox.ac.uk/_ref/PDB/3gp6/
- Wet file size: 7,524,042 bytes (7.5 MB, 95,239 atoms)
- Dry size: 1,518,620 bytes (1.5 MB, 19,221 atoms) — verified; compressed ~231 KB

### Processing note
Files were processed: water (SOL) and ions (NA, CL) stripped, then compressed,
before caching. The DPPC membrane and protein coordinates are preserved
unaltered from the MemProtMD atomistic snapshot.

Strip targets empirically verified (3gp6): SOL 75,789 + NA 116 + CL 113 = 76,018
stripped (wet 95,239 → dry 19,221). Same strip targets confirmed for 1gzm
(SOL 91,638 + NA 147 + CL 139 present in the wet file).

### License
PDB entries (1GZM, 3GP6): CC0 1.0 (RCSB PDB policy).
MemProtMD membrane coordinates (DPPC bilayer + atomistic embedding): CC-BY 4.0
International (verified 2026-08-14 from the site JS bundle at
https://memprotmd.bioch.ox.ac.uk — the license string "Licensed using a Creative
Commons Attribution 4.0 International License" appears in the download-panel
component). CC-BY 4.0 permits bundling the processed/derived PDB with attribution.

---

## 3. Fetched glycoprotein demo (SASBDB) — DEMO-03

### SASDPG4 — Alpha-1-acid glycoprotein 1 (Challenge)
- Source database: SASBDB (Small Angle Scattering Biological Data Bank)
  - Entry: https://www.sasbdb.org/data/SASDPG4/
  - SASBDB ID: SASDPG4
  - License: "free of all copyright restrictions and made fully and freely
    available for both non-commercial and commercial use. Users of the data
    should attribute the original authors." (https://www.sasbdb.org/aboutSASBDB/)
    Attribution requested.
- Molecule: Alpha-1-acid glycoprotein 1 (AGP, orosomucoid), Homo sapiens,
  UniProt P02763 (residues 19-183)
- Structure file used: SASDPG4_fit2_model1.pdb (a glycosylated hybrid model from
  the SAXS-fit ensemble; 4123 atoms = 1522 protein + 2601 glycan HETATM across
  8 carbohydrate residue names: NAG, MAN, BMA, NAN, GLB, AFL, NGA, GLA). Built
  with SWISS-MODEL + glycan modeling; refined against SAXS data at 283 K.
- Fetch URL: https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb
- Primary publication:
  Kalidas N, Peddada N, Pandey K, Ashish. "SAXS data based glycosylated models
  of human alpha-1-acid glycorprotein, a key player in health, disease and drug
  circulation." J Biomol Struct Dyn 44(5):2709-2723 (2025).
  DOI: 10.1080/07391102.2025.2475244. PMID 40056387.
  (Note: the published title's "glycorprotein" is a typo in the published title —
  reproduced as-is per the publisher landing page.)
- Database citation:
  Kikhney AG, Borges CR, Molodenskiy DS, Jeffries CM, Svergun DI. "SASBDB:
  Towards an automatically curated and validated repository for biological
  scattering data." Protein Science 29(1):66-75 (2020).
  DOI: 10.1002/pro.3731.

### Processing note
No strip needed (strip=False): the SASBDB model contains no water or ions — every
HETATM record (2601 of them) is a glycan atom. The file is cached as-is after
download.

CAUTION — do NOT over-strip: a `cmd.remove hetatm` would delete the 2601 glycan
atoms and silently fail DEMO-03. The strip selector (solvent/inorganic) is safe —
it does NOT match glycan HETATM.

### License
SASBDB data is "free of all copyright restrictions and made fully and freely
available for both non-commercial and commercial use. Users of the data should
attribute the original authors." (https://www.sasbdb.org/aboutSASBDB/)

---

## 4. PDB_POOL (Randomize fetch mode) — RCSB CC0

The curated PDB codes in PDB_POOL (setup_state.py) are all RCSB entries
(verified 2026-08-05). Blanket RCSB CC0 1.0 attribution applies (see §1 license
above). Individual citations are available at
https://www.rcsb.org/structure/{ID} for each PDB code in the pool.

The PDB_POOL entries are fetched on demand by the user's Randomize action — they
are not bundled in the repo. The blanket CC0 attribution suffices; no per-entry
citation is required in this file (the user can look up any individual entry at
the RCSB URL above).

---

## 5. PyMOL

Schrödinger LLC — https://pymol.org — cite per standard practice.

When publishing or presenting work created with bioCHEMeleon, cite PyMOL
(Schrödinger LLC) as the molecular graphics system used.
