import math

from visual_engine.distance_model import (
    estimate_distance,
    focal_from_hfov,
    monocular_distance_m,
)


def test_laptop_sanity_10_inches_63_hfov() -> None:
    f = focal_from_hfov(1920, 63.0)
    projected_w_px = (0.32 / 0.25) * f
    w_norm = projected_w_px / 1920
    d = estimate_distance("laptop", (0.1, 0.3, w_norm, w_norm * 0.6), 1920, 1080, f, f)
    assert d is not None
    assert 0.20 <= d <= 0.35


def test_scissors_no_known_size() -> None:
    f = focal_from_hfov(1920, 63.0)
    assert (
        monocular_distance_m(
            "scissors", {}, {}, None, 1920, 1080, 0.2, 0.2, horizontal_fov_deg=63.0
        )
        == 99.0
    )
    d = estimate_distance("scissors", (0.1, 0.1, 0.1, 0.1), 1920, 1080, f, f)
    assert d is None


def test_fills_frame_clamp() -> None:
    f = focal_from_hfov(1920, 63.0)
    d = estimate_distance("laptop", (0.0, 0.0, 0.7, 0.2), 1920, 1080, f, f)
    assert d is not None
    assert d <= 0.5


def test_focal_1920_63_matches_expectation() -> None:
    f = focal_from_hfov(1920, 63.0)
    expected = (1920 / 2.0) / math.tan(math.radians(63.0) / 2.0)
    assert abs(f - expected) < 0.1
