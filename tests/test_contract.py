from visual_engine.contracts import BBoxNorm, DetectedObject, make_frame_payload
from visual_engine.testing_engine import validate_frame_payload


def test_make_frame_payload_valid() -> None:
    p = make_frame_payload(
        frame_id=1,
        timestamp_ms=100,
        vision_duration_ms=10,
        objects=[
            DetectedObject(
                object_id="car_001",
                class_name="car",
                confidence=0.9,
                bbox=BBoxNorm(0.5, 0.5, 0.2, 0.1),
                distance_m=10.0,
                pan_value=0.0,
                velocity_mps=0.0,
                priority="NORMAL",
            )
        ],
        camera={
            "lens_status": "ok",
            "lens_laplacian_var": 150.0,
            "lens_announce": None,
        },
    )
    assert validate_frame_payload(p) == []
