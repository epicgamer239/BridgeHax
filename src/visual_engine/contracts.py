from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass(slots=True)
class BBoxNorm:
    x_center_norm: float
    y_center_norm: float
    width_norm: float
    height_norm: float


@dataclass(slots=True)
class DetectedObject:
    object_id: str
    class_name: str
    confidence: float
    bbox: BBoxNorm
    distance_m: float
    pan_value: float
    velocity_mps: float
    priority: str

    def to_contract(self) -> dict:
        payload = asdict(self)
        payload["class"] = payload.pop("class_name")
        return payload


def make_frame_payload(
    frame_id: int,
    timestamp_ms: int,
    vision_duration_ms: int,
    objects: list[DetectedObject],
    camera: dict | None = None,
) -> dict:
    payload: dict = {
        "frame_id": frame_id,
        "timestamp_ms": timestamp_ms,
        "vision_duration_ms": vision_duration_ms,
        "objects": [obj.to_contract() for obj in objects],
    }
    if camera is not None:
        payload["camera"] = camera
    return payload
