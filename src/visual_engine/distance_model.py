"""Axis-aware monocular distance (meters), aligned with iOS `VisionGeometry.estimateMonocularDistanceM` / `CameraIntrinsics`."""

from __future__ import annotations

import math

# Tables mirror `VisionConfiguration` defaults in VisionBridgeKit (Open Images V7 allowlist).
KNOWN_HEIGHTS_M: dict[str, float] = {
    "person": 1.70,
    "car": 1.50,
    "truck": 3.20,
    "bus": 3.50,
    "motorcycle": 1.20,
    "bicycle": 1.10,
    "dog": 0.50,
    "cat": 0.30,
    "chair": 0.90,
    "kitchen & dining room table": 0.75,
    "laptop": 0.24,
    "mobile phone": 0.15,
    "bottle": 0.25,
    "coffee cup": 0.12,
    "backpack": 0.55,
    "suitcase": 0.65,
    "traffic light": 0.90,
    "stop sign": 0.75,
    "fire hydrant": 0.60,
    "bench": 0.90,
    "umbrella": 1.00,
    "couch": 0.90,
    "plant": 0.6,
    "handbag": 0.3,
    "television": 0.50,
    "computer keyboard": 0.05,
    "computer mouse": 0.04,
    "remote control": 0.03,
    "stairs": 0.25,
    "waste container": 0.9,
    "computer monitor": 0.45,
}

KNOWN_WIDTHS_M: dict[str, float] = {
    "person": 0.50,
    "car": 1.80,
    "truck": 2.40,
    "bus": 2.50,
    "motorcycle": 1.00,
    "bicycle": 1.70,
    "couch": 1.80,
    "kitchen & dining room table": 1.20,
    "laptop": 0.32,
    "dog": 0.60,
    "cat": 0.40,
    "bench": 1.50,
    "suitcase": 0.45,
    "chair": 0.55,
    "plant": 0.45,
    "backpack": 0.4,
    "handbag": 0.4,
    "mobile phone": 0.08,
    "bottle": 0.08,
    "coffee cup": 0.1,
    "umbrella": 0.9,
    "traffic light": 0.4,
    "fire hydrant": 0.45,
    "stop sign": 0.6,
    "television": 0.9,
    "computer keyboard": 0.45,
    "computer mouse": 0.1,
    "remote control": 0.08,
    "stairs": 1.2,
    "waste container": 0.45,
    "computer monitor": 0.55,
}


def focal_from_hfov(frame_width: int, hfov_deg: float) -> float:
    w = max(1, int(frame_width))
    return (w / 2.0) / math.tan(math.radians(hfov_deg) / 2.0)


def _focal_pair_from_hfov(frame_width: int, frame_height: int, hfov_deg: float) -> tuple[float, float]:
    w = max(1, float(frame_width))
    h = max(1, float(frame_height))
    h_fov = math.radians(hfov_deg)
    f_x = (w / 2.0) / max(math.tan(h_fov / 2.0), 0.01)
    v_fov = 2.0 * math.atan((h / w) * math.tan(h_fov / 2.0))
    f_y = (h / 2.0) / max(math.tan(v_fov / 2.0), 0.01)
    return f_x, f_y


def _apply_output_clamps(meters: float, width_norm: float, height_norm: float) -> float:
    m = min(max(meters, 0.3), 20.0)
    if not math.isfinite(m):
        m = 0.3
    if width_norm > 0.60 or height_norm > 0.60:
        m = min(m, 0.5)
    return round(m * 100) / 100.0


def monocular_distance_m(
    class_name: str,
    known_heights_m: dict[str, float] | None,
    known_widths_m: dict[str, float] | None,
    focal_length_px: float | None,
    image_width: int,
    image_height: int,
    width_norm: float,
    height_norm: float,
    horizontal_fov_deg: float = 63.0,
) -> float:
    """
    `focal_length_px` — optional explicit calibration; when None, f_x / f_y are derived from
    `horizontal_fov_deg` and frame size (eval / laptop / webcam, no iOS device intrinsics).
    """
    c = class_name.lower().strip()
    kh_map = KNOWN_HEIGHTS_M if known_heights_m is None else known_heights_m
    kw_map = KNOWN_WIDTHS_M if known_widths_m is None else known_widths_m
    if focal_length_px is not None and focal_length_px > 0:
        f_x = f_y = float(focal_length_px)
    else:
        f_x, f_y = _focal_pair_from_hfov(image_width, image_height, horizontal_fov_deg)

    bbox_wpx = width_norm * float(image_width)
    bbox_hpx = height_norm * float(image_height)

    kh = kh_map.get(c)
    kw = kw_map.get(c)

    parts: list[tuple[str, float]] = []
    if kh is not None and bbox_hpx > 10:
        parts.append(("height", (kh * f_y) / bbox_hpx))
    if kw is not None and bbox_wpx > 10:
        parts.append(("width", (kw * f_x) / bbox_wpx))

    if not parts:
        return 99.0
    if len(parts) == 1:
        return _apply_output_clamps(parts[0][1], width_norm, height_norm)

    d_h = parts[0][1]
    d_w = parts[1][1]
    if d_h > 0 and d_w > 0 and max(d_h, d_w) / min(d_h, d_w) < 2.0:
        raw = math.sqrt(d_h * d_w)
    else:
        raw = d_w if bbox_wpx >= bbox_hpx else d_h
    return _apply_output_clamps(raw, width_norm, height_norm)


def estimate_distance(
    class_name: str,
    bbox_xywh_norm: tuple[float, float, float, float],
    frame_width: int,
    frame_height: int,
    f_x: float,
    f_y: float,
) -> float | None:
    """Synchronous eval helper — same selection rules as on-device, using separate f_x / f_y."""
    _x, _y, w_norm, h_norm = bbox_xywh_norm
    bbox_wpx = w_norm * float(frame_width)
    bbox_hpx = h_norm * float(frame_height)
    c = class_name.lower().strip()
    kh = KNOWN_HEIGHTS_M.get(c)
    kw = KNOWN_WIDTHS_M.get(c)
    parts: list[float] = []
    if kh is not None and bbox_hpx > 10:
        parts.append((kh * f_y) / bbox_hpx)
    if kw is not None and bbox_wpx > 10:
        parts.append((kw * f_x) / bbox_wpx)
    if not parts:
        return None
    if len(parts) == 1:
        return _apply_output_clamps(parts[0], w_norm, h_norm)
    d_h, d_w = parts[0], parts[1]
    if d_h > 0 and d_w > 0 and max(d_h, d_w) / min(d_h, d_w) < 2.0:
        raw = math.sqrt(d_h * d_w)
    else:
        raw = d_w if bbox_wpx >= bbox_hpx else d_h
    return _apply_output_clamps(raw, w_norm, h_norm)


if __name__ == "__main__":
    f = focal_from_hfov(1920, 63.0)
    projected_w_px = (0.32 / 0.25) * f
    w_n = projected_w_px / 1920
    d = estimate_distance("laptop", (0.1, 0.3, w_n, w_n * 0.6), 1920, 1080, f, f)
    print(f"f_px={f:.1f} laptop@0.25m estimate={d!s}m")
