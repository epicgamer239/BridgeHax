"""Synthetic BGR images for tests and bench simulation (no camera, no dataset files required)."""

from __future__ import annotations

import numpy as np

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None  # type: ignore[misc, assignment]


def random_sharp_bgr(
    height: int = 480,
    width: int = 640,
    seed: int | None = 42,
) -> np.ndarray:
    """High-frequency content → high Laplacian variance (lens: sharp)."""
    if seed is not None:
        rng = np.random.default_rng(seed)
    else:
        rng = np.random.default_rng()
    return rng.integers(0, 256, (height, width, 3), dtype=np.uint8)


def gaussian_blur_bgr(
    bgr: np.ndarray,
    kernel: int = 25,
) -> np.ndarray:
    if cv2 is None:
        raise RuntimeError("opencv-python is required for gaussian_blur_bgr")
    k = max(3, kernel | 1)
    return cv2.GaussianBlur(bgr, (k, k), 0)


def uniform_bgr(
    height: int = 480,
    width: int = 640,
    b: int = 120,
    g: int = 120,
    r: int = 120,
) -> np.ndarray:
    """Flat field → very low detail (lens: looks blurred for Laplacian)."""
    return np.full((height, width, 3), (b, g, r), dtype=np.uint8)


def lens_streak_sequence(
    n_sharp: int,
    n_blur: int,
    height: int = 240,
    width: int = 320,
    seed: int = 1,
) -> list[tuple[str, np.ndarray]]:
    """
    Labelled sequence: ("sharp", frame) and ("blur", frame) for simulations.
    Blur = heavy Gaussian on a random sharp frame to simulate smeared focus.
    """
    out: list[tuple[str, np.ndarray]] = []
    s = seed
    for _ in range(n_sharp):
        out.append(("sharp", random_sharp_bgr(height, width, seed=s)))
        s += 1
    sharp0 = random_sharp_bgr(height, width, seed=s)
    b = gaussian_blur_bgr(sharp0, 31)
    for _ in range(n_blur):
        out.append(("blur", b))
    return out
