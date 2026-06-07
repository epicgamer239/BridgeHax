from visual_engine.bbox_in_frame import bbox_area_fraction_inside_image


def test_full_box_inside() -> None:
    assert bbox_area_fraction_inside_image(0.0, 0.0, 100.0, 100.0, 200, 200) == 1.0


def test_half_box_outside_left() -> None:
    # Half of 100px box is outside the left of a 200-wide image: x1=-50, x2=50
    f = bbox_area_fraction_inside_image(-50.0, 0.0, 50.0, 100.0, 200, 200)
    assert abs(f - 0.5) < 1e-6


def test_edge_visibility_grid() -> None:
    # Box width 100 in image width 200; shift from fully outside to fully inside.
    vis = {
        "0%": bbox_area_fraction_inside_image(-100, 0, 0, 100, 200, 200),
        "25%": bbox_area_fraction_inside_image(-75, 0, 25, 100, 200, 200),
        "50%": bbox_area_fraction_inside_image(-50, 0, 50, 100, 200, 200),
        "75%": bbox_area_fraction_inside_image(-25, 0, 75, 100, 200, 200),
        "100%": bbox_area_fraction_inside_image(0, 0, 100, 100, 200, 200),
    }
    assert vis["0%"] == 0.0
    assert abs(vis["25%"] - 0.25) < 1e-6
    assert abs(vis["50%"] - 0.5) < 1e-6
    assert abs(vis["75%"] - 0.75) < 1e-6
    assert abs(vis["100%"] - 1.0) < 1e-6


def test_filter_threshold_policy() -> None:
    # Policy asked in finish plan: below 40% filtered, above 60% pass.
    below = bbox_area_fraction_inside_image(-70, 0, 30, 100, 200, 200)  # 30%
    above = bbox_area_fraction_inside_image(-30, 0, 70, 100, 200, 200)  # 70%
    assert below < 0.40
    assert above > 0.60
