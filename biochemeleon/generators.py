"""Sphere-hider generator - pure geometry (stdlib random only, WSL-testable).

NO ``pymol`` import, NO ``pymol.Qt`` import. The cmd-coupled caller
(``__init__.py``) fetches the bounding box via ``cmd.get_extent`` and
feeds it here; the returned positions become ``(pos, 'spheres')`` specs
for ``GameController.start``.

This module mirrors the purity convention of ``registry.py`` and
``setup_state.py`` (AGENTS.md: pure layer <- cmd-coupled layer; never
reversed) so it is WSL-unit-testable.
"""

import random


def generate_sphere_positions(extent, n, seed=None):
    """Generate ``n`` random ``[x,y,z]`` positions within the bounding box.

    extent: ``[[xmin,ymin,zmin],[xmax,ymax,zmax]]`` from ``cmd.get_extent``.
    n: number of positions. seed: int for deterministic output (tests).
    Returns: list of ``[x,y,z]`` lists (empty list when ``n <= 0``).
    """
    rng = random.Random(seed)
    (xmin, ymin, zmin) = extent[0]
    (xmax, ymax, zmax) = extent[1]
    positions = []
    for _ in range(n):
        positions.append([
            rng.uniform(xmin, xmax),
            rng.uniform(ymin, ymax),
            rng.uniform(zmin, zmax),
        ])
    return positions
