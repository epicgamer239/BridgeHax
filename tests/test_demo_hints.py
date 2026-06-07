from __future__ import annotations

from pathlib import Path

import pytest

from visual_engine.config import VisualConfig
from visual_engine.demo_hints import hints_from_payload


def test_hints_empty() -> None:
    h = hints_from_payload({"frame_id": 0, "timestamp_ms": 0, "vision_duration_ms": 0, "objects": []})
    assert h["object_count"] == 0
    assert h["nearest_class"] is None
    assert "narration_lines" in h
    assert h["visual_version"]


def test_hints_nearest() -> None:
    p = {
        "frame_id": 1,
        "timestamp_ms": 1,
        "vision_duration_ms": 12,
        "objects": [
            {
                "object_id": "a",
                "class": "car",
                "confidence": 0.9,
                "bbox": {"x_center_norm": 0.5, "y_center_norm": 0.5, "width_norm": 0.1, "height_norm": 0.1},
                "distance_m": 8.0,
                "pan_value": 0.0,
                "velocity_mps": 0.0,
                "priority": "NORMAL",
            },
            {
                "object_id": "b",
                "class": "person",
                "confidence": 0.9,
                "bbox": {"x_center_norm": 0.5, "y_center_norm": 0.5, "width_norm": 0.1, "height_norm": 0.1},
                "distance_m": 2.0,
                "pan_value": -0.2,
                "velocity_mps": 0.0,
                "priority": "HIGH",
            },
        ],
    }
    h = hints_from_payload(p)
    assert h["object_count"] == 2
    assert h["nearest_class"] == "person"
    assert h["high_priority_count"] == 1
    assert h["nearest_distance_m"] == 2.0


def test_app_health_includes_hints_and_uptime() -> None:
    pytest.importorskip("ultralytics")
    pytest.importorskip("cv2")
    from visual_engine.app import create_app

    app = create_app(VisualConfig(), use_local_camera=False)
    c = app.test_client()
    r = c.get("/health")
    assert r.status_code == 200
    d = r.get_json()
    assert d["status"] == "ok"
    assert "uptime_s" in d
    assert d["visual_version"]
    assert "object_count" in d["hints"]
    assert c.get("/judge").status_code == 200
    text = c.get("/judge").get_data(as_text=True)
    assert "VisionBridge" in text
    assert c.get("/").status_code == 200
    home = c.get("/").get_data(as_text=True)
    assert "judge" in home.lower() or "Judge" in home
    f = c.get("/frame").get_json()
    p = c.get("/payload").get_json()
    assert f == p


def test_judge_bundles_with_package() -> None:
    p = Path(__file__).resolve().parent.parent / "src" / "visual_engine" / "judge.html"
    assert p.is_file(), "judge.html must ship next to app.py for /judge"
