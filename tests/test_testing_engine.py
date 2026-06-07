from visual_engine.testing_engine import (
    run_built_in_smoke,
    validate_frame_payload,
)


def test_builtin_smoke_engine() -> None:
    r = run_built_in_smoke()
    assert r.ok(), r.failed


def test_validate_payload_rejects_missing_object_key() -> None:
    err = validate_frame_payload(
        {
            "frame_id": 1,
            "timestamp_ms": 1,
            "vision_duration_ms": 1,
            "objects": [
                {
                    "object_id": "x",
                    "class": "car",
                    # missing fields
                }
            ],
        }
    )
    assert err
