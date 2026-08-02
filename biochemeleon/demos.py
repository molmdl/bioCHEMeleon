"""DemoLoader (manifest + bundled PDBs) — populated in Phase 2.

TODO (Phase 2): implement to_windows_path() helper here (or in a util module)
to convert /mnt/c/... WSL paths to C:\\... Windows paths before passing them
to cmd.load — PyMOL runs as a Windows process and cannot resolve WSL paths.
See PITFALLS.md Pitfall 11. This helper is NOT needed in Phase 1 because
Phase 1 loads no files; it is documented here so it is not forgotten.
"""
