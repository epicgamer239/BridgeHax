"""Helpers to drop detections that are mostly outside the image (Vision/CoreML OOB quirk)."""

from __future__ import annotations


def bbox_area_fraction_inside_image(
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    image_width: int,
    image_height: int,
) -> float:
    """
    Intersection of axis-aligned box with the image, divided by full box area.
    Ultralytics `xyxy` is left, top, right, bottom in pixel coordinates, origin top-left.
    """
    box_w = max(0.0, x2 - x1)
    box_h = max(0.0, y2 - y1)
    box_a = max(1e-9, box_w * box_h)
    ix1 = max(0.0, x1)
    iy1 = max(0.0, y1)
    ix2 = min(float(image_width), x2)
    iy2 = min(float(image_height), y2)
    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    return (iw * ih) / box_a
