from __future__ import annotations

from typing import Any

__all__ = ["hints_from_payload", "VISUAL_VERSION"]

VISUAL_VERSION = "0.2.0"

_OBJECT_LABEL: dict[str, str] = {
    "person": "person",
    "car": "car",
    "bicycle": "bicycle",
    "motorcycle": "motorcycle",
    "truck": "truck",
    "bus": "bus",
}


def _snippets(objects: list[dict[str, Any]], nearest: dict[str, Any] | None) -> list[str]:
    if not objects:
        return ["No objects in view", "Lanyard path clear for demo"]
    out: list[str] = []
    n = len(objects)
    high = [o for o in objects if str(o.get("priority", "")).upper() == "HIGH"]
    if high:
        out.append(f"{len(high)} high-priority (within ~3 m)")
    if nearest:
        c = str(nearest.get("class", "object"))
        d = float(nearest.get("distance_m", 0.0) or 0.0)
        p = str(nearest.get("pan_value", 0.0) or 0.0)
        out.append(f"Nearest: {c} at {d:.1f} m (pan {float(p):+.2f})")
    if n:
        out.append(f"{n} object(s) tracked this frame")
    return out


def hints_from_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Derive quick UI / narration fields from a FramePayload-shaped dict. Safe if keys missing."""
    objects = payload.get("objects")
    if not isinstance(objects, list) or not objects:
        camera = payload.get("camera")
        if isinstance(camera, dict) and str(camera.get("lens_status", "")).lower() == "warning":
            lens_announce = camera.get("lens_announce")
            msg = "Clean camera lens" if not lens_announce else str(lens_announce)[: 120]
        else:
            msg = "No objects detected"
        return {
            "object_count": 0,
            "nearest_distance_m": None,
            "nearest_class": None,
            "nearest_object_id": None,
            "high_priority_count": 0,
            "lens_status": (camera or {}).get("lens_status") if isinstance(camera, dict) else None,
            "narration_lines": [msg, "Hearing: spatial cues idle"],
            "visual_version": VISUAL_VERSION,
        }

    def dist_key(o: dict[str, Any]) -> float:
        try:
            return float(o.get("distance_m", 9_999.0) or 9_999.0)
        except (TypeError, ValueError):
            return 9_999.0

    sorted_obs = sorted((o for o in objects if isinstance(o, dict)), key=dist_key)
    nearest: dict[str, Any] | None = sorted_obs[0] if sorted_obs else None
    high_priority_count = sum(
        1 for o in objects if isinstance(o, dict) and str(o.get("priority", "")).upper() == "HIGH"
    )

    camera = payload.get("camera")
    lens_status: str | None = None
    if isinstance(camera, dict):
        lens_status = str(camera.get("lens_status")) if camera.get("lens_status") is not None else None

    ncls: str | None
    noid: str | None
    ndist: float | None
    if nearest:
        raw_cls = str(nearest.get("class", "object"))
        ncls = _OBJECT_LABEL.get(raw_cls, raw_cls)
        noid = str(nearest.get("object_id", "")) or None
        try:
            ndist = float(nearest.get("distance_m", 0.0) or 0.0)
        except (TypeError, ValueError):
            ndist = None
    else:
        ncls, noid, ndist = None, None, None

    raw_list: list[dict[str, Any]] = [o for o in objects if isinstance(o, dict)]
    return {
        "object_count": len(objects),
        "nearest_distance_m": ndist,
        "nearest_class": ncls,
        "nearest_object_id": noid,
        "high_priority_count": high_priority_count,
        "lens_status": lens_status,
        "narration_lines": _snippets(raw_list, nearest),
        "visual_version": VISUAL_VERSION,
    }
