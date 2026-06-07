import numpy as np
import pytest

from visual_engine.lens_quality import laplacian_variance_bgr
from visual_engine.synthesis import (
    lens_streak_sequence,
    random_sharp_bgr,
    uniform_bgr,
)


def test_sharp_higher_laplacian_than_uniform() -> None:
    sharp = random_sharp_bgr(120, 160, seed=0)
    flat = uniform_bgr(120, 160)
    assert laplacian_variance_bgr(sharp) > laplacian_variance_bgr(flat) * 0.5


def test_lens_streak_sequence_labels() -> None:
    seq = lens_streak_sequence(2, 3, 64, 80, seed=0)
    assert [t for t, _ in seq] == ["sharp", "sharp", "blur", "blur", "blur"]


def test_synthesis_deterministic_seed() -> None:
    a = random_sharp_bgr(10, 10, seed=99)
    b = random_sharp_bgr(10, 10, seed=99)
    assert np.array_equal(a, b)
