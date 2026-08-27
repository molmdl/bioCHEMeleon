# vmd/lib/setup_state.tcl
# PURE layer: stdlib-only tcl. No molecular-viewer API, no GUI toolkit.
# Unit-testable via tcltest (under headless VMD or a standalone tclsh).
# Direct port of v1 pymol/biochemeleon/setup_state.py (Python -> tcl 8.5).

namespace eval ::biochemeleon::setup_state {
    # The 10 in-scope VMD representations for v2 (curated from FEATURES.md).
    # v1 had 5; v2 expands to 10. Surface/volumetric reps are out of scope
    # (anti-features — they do not fit the discrete-atom blend-in mechanic).
    variable GAME_REPS {Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds}

    # JSON schema version tag for setup files (v2, not v1).
    variable SETUP_FORMAT "biochemeleon-setup-v2"

    # Default setup state (port of v1 setup_state.py:118-130).
    # 11 keys: format, target_mode, selected_object, pdb_code, demo_id,
    # hider_count, lock_scene, per_rep, difficulty_easy, lock_source, pdb_pool.
    variable DEFAULTS [dict create \
        format          "biochemeleon-setup-v2" \
        target_mode     "loaded" \
        selected_object "" \
        pdb_code        "" \
        demo_id         "1znf" \
        hider_count     10 \
        lock_scene      0 \
        per_rep         [dict create] \
        difficulty_easy 1 \
        lock_source     0 \
        pdb_pool        [list] ]

    # Demo manifest: 6 BUNDLED demo entries (port of v1 setup_state.py:34-57).
    # PDBs are viewer-agnostic and reused verbatim per ARCHITECTURE.md.
    # The 3 fetched demos (1gzm/3gp6/sasdpg4) are added in a later phase, NOT here.
    variable DEMO_MANIFEST [dict create \
        1znf [dict create category Protein       type protein    difficulty easy source bundled cache_name 1znf.pdb] \
        1xdn [dict create category Protein       type protein    difficulty hard source bundled cache_name 1xdn.pdb] \
        5e54 [dict create category "Nucleic acid" type rna        difficulty easy source bundled cache_name 5e54.pdb] \
        1k8p [dict create category "Nucleic acid" type dna        difficulty easy source bundled cache_name 1k8p.pdb] \
        2qbz [dict create category "Nucleic acid" type rna        difficulty hard source bundled cache_name 2qbz.pdb] \
        4wb3 [dict create category Mixed         type "protein/na" difficulty hard source bundled cache_name 4wb3.pdb] ]

    # Export the public symbols so callers may `namespace import` them.
    # Tests and the entry script use fully-qualified names; the export
    # list documents the public contract (full validation is a later phase).
    namespace export GAME_REPS SETUP_FORMAT DEFAULTS DEMO_MANIFEST hider_count_cap validate_state
}

# Hider-count cap (port of v1 setup_state.py:233-244).
# Heuristic: 1 hider per ~50 atoms, clamped to [1, 50].
# Verified by probe: 0 -> 1, 212 -> 4, 100000 -> 50 (matches v1).
proc ::biochemeleon::setup_state::hider_count_cap {atom_count} {
    if {![string is integer -strict $atom_count] || $atom_count <= 0} {
        return 1
    }
    set cap [expr {$atom_count / 50}]
    if {$cap < 1} { set cap 1 }
    if {$cap > 50} { set cap 50 }
    return $cap
}

# validate_state STUB (full validation is a later phase). For now, return
# DEFAULTS. The tcltest asserts this returns a dict with the `format` key.
proc ::biochemeleon::setup_state::validate_state {state {atom_count {}}} {
    variable DEFAULTS
    return $DEFAULTS
}
