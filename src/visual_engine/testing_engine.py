"""VisionBridge automated test / validation engine (no external test runner required).

Use from CI:  `PYTHONPATH=src python -m visual_engine.testing_engine`
Or pytest:     `pytest tests/ -q`
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from typing import Any

REQUIRED_TOP_KEYS = frozenset(
    {"frame_id", "timestamp_ms", "vision_duration_ms", "objects"}
)
OBJECT_KEYS = frozenset(
    {
        "object_id",
        "class",
        "confidence",
        "bbox",
        "distance_m",
        "pan_value",
        "velocity_mps",
        "priority",
    }
)
BBOX_KEYS = frozenset(
    {"x_center_norm", "y_center_norm", "width_norm", "height_norm"}
)
CAMERA_KEYS = frozenset({"lens_status", "lens_laplacian_var", "lens_announce"})


@dataclass
class TestReport:
    passed: list[str] = field(default_factory=list)
    failed: list[str] = field(default_factory=list)

    def ok(self) -> bool:
        return len(self.failed) == 0

    def to_dict(self) -> dict[str, Any]:
        return {"passed": self.passed, "failed": self.failed, "success": self.ok()}


def validate_frame_payload(payload: dict[str, Any]) -> list[str]:
    """Return a list of human-readable errors; empty means valid."""
    errors: list[str] = []
    missing = REQUIRED_TOP_KEYS - payload.keys()
    if missing:
        errors.append(f"missing top-level keys: {sorted(missing)}")
        return errors
    if not isinstance(payload["objects"], list):
        errors.append("objects must be a list")
        return errors
    for i, obj in enumerate(payload["objects"]):
        if not isinstance(obj, dict):
            errors.append(f"objects[{i}] must be object")
            continue
        om = OBJECT_KEYS - obj.keys()
        if om:
            errors.append(f"objects[{i}] missing keys: {sorted(om)}")
        bb = obj.get("bbox")
        if isinstance(bb, dict):
            bm = BBOX_KEYS - bb.keys()
            if bm:
                errors.append(f"objects[{i}].bbox missing: {sorted(bm)}")
    if "camera" in payload:
        cam = payload["camera"]
        if not isinstance(cam, dict):
            errors.append("camera must be object")
        else:
            cm = CAMERA_KEYS - cam.keys()
            if cm:
                errors.append(f"camera missing keys: {sorted(cm)}")
    return errors


def _smoke_lens() -> None:
    import cv2
    import numpy as np

    from .config import VisualConfig
    from .lens_quality import LensWarningState, laplacian_variance_bgr

    sharp = np.random.randint(0, 256, (240, 320, 3), dtype=np.uint8)
    blur = cv2.GaussianBlur(sharp, (25, 25), 0)
    vs = laplacian_variance_bgr(sharp)
    vb = laplacian_variance_bgr(blur)
    if not (vs > vb):
        raise AssertionError(
            f"expected sharp laplacian variance > blurred: {vs} vs {vb}"
        )
    thr = (vs + vb) / 2.0
    cfg = VisualConfig(
        enable_lens_check=True,
        lens_laplacian_threshold=thr,
        lens_warn_consecutive=2,
    )
    st = LensWarningState(cfg)
    st.update(blur)
    c2 = st.update(blur)
    if c2["lens_status"] != "warning":
        raise AssertionError("expected warning after consecutive blurred frames")


def _smoke_contract() -> None:
    from .contracts import BBoxNorm, DetectedObject, make_frame_payload

    p = make_frame_payload(
        frame_id=1,
        timestamp_ms=1,
        vision_duration_ms=5,
        objects=[
            DetectedObject(
                object_id="p_001",
                class_name="person",
                confidence=0.9,
                bbox=BBoxNorm(0.5, 0.5, 0.1, 0.2),
                distance_m=3.0,
                pan_value=0.0,
                velocity_mps=0.0,
                priority="NORMAL",
            )
        ],
        camera={
            "lens_status": "ok",
            "lens_laplacian_var": 200.0,
            "lens_announce": None,
        },
    )
    err = validate_frame_payload(p)
    if err:
        raise AssertionError(err)


def _smoke_simulation() -> None:
    from .simulation import SimulationEngine

    e = SimulationEngine()
    rep = e.run_lens_streak(n_sharp=2, n_blur=4)
    if not rep.ok():
        raise AssertionError(rep.validation_errors)
    cams = [p.get("camera") for p in rep.payloads if p.get("camera")]
    if not cams or not any(
        isinstance(c, dict) and c.get("lens_status") == "warning" for c in cams
    ):
        raise AssertionError("lens_streak sim should end with at least one lens warning")


def run_built_in_smoke() -> TestReport:
    r = TestReport()
    for name, fn in [
        ("smoke_contract", _smoke_contract),
        ("smoke_lens", _smoke_lens),
        ("smoke_simulation", _smoke_simulation),
    ]:
        try:
            fn()
            r.passed.append(name)
        except Exception as e:  # noqa: BLE001 — surface all failures
            r.failed.append(f"{name}: {e!s}")
    return r


def main() -> int:
    r = run_built_in_smoke()
    print(json.dumps(r.to_dict(), indent=2))
    return 0 if r.ok() else 1


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:  # noqa: BLE001
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)
    else:
        sys.exit(rc)
