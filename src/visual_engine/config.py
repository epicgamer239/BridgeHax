from dataclasses import dataclass, field

# Open Images V7 class names (lowercase); allowlist for Ultralytics `yolov8m-oiv7.pt`.
_DEFAULT_TARGET: frozenset[str] = frozenset(
    {
        "person",
        "chair",
        "kitchen & dining room table",
        "backpack",
        "mobile phone",
        "laptop",
        "television",
        "computer keyboard",
        "computer mouse",
        "remote control",
        "bottle",
        "coffee cup",
        "stairs",
        "waste container",
        "computer monitor",
        "door",
    }
)


@dataclass(slots=True)
class VisualConfig:
    model_path: str = "yolov8m-oiv7.pt"
    target_classes: set[str] = field(default_factory=lambda: set(_DEFAULT_TARGET))
    suppressed_classes: set[str] = field(default_factory=set)
    confidence_threshold: float = 0.58
    class_confidence_thresholds: dict[str, float] = field(
        default_factory=lambda: {
            "mobile phone": 0.86,
            "remote control": 0.80,
            "computer mouse": 0.80,
            "computer keyboard": 0.74,
            "coffee cup": 0.72,
        }
    )
    min_box_area_fraction_by_class: dict[str, float] = field(
        default_factory=lambda: {
            "mobile phone": 0.0080,
            "remote control": 0.0100,
            "computer mouse": 0.0070,
            "coffee cup": 0.0060,
        }
    )
    # Minimum fraction of the bbox that must lie inside the frame (0–1). Drops edge/OOB false positives.
    min_bbox_area_fraction_in_frame: float = 0.7
    known_heights_m: dict[str, float] = field(
        default_factory=lambda: {
            "person": 1.7,
            "chair": 0.9,
            "kitchen & dining room table": 0.75,
            "backpack": 0.5,
            "mobile phone": 0.15,
            "laptop": 0.24,
            "television": 0.5,
            "computer keyboard": 0.05,
            "computer mouse": 0.04,
            "remote control": 0.03,
            "bottle": 0.25,
            "coffee cup": 0.12,
            "stairs": 0.25,
            "waste container": 0.9,
            "computer monitor": 0.45,
            "door": 2.0,
        }
    )
    # Horizontal physical size (m) for width-dominated bboxes; matches VisionBridge `knownWidthsM`.
    known_widths_m: dict[str, float] = field(
        default_factory=lambda: {
            "person": 0.5,
            "chair": 0.55,
            "kitchen & dining room table": 1.2,
            "backpack": 0.4,
            "mobile phone": 0.08,
            "laptop": 0.32,
            "television": 0.9,
            "computer keyboard": 0.45,
            "computer mouse": 0.1,
            "remote control": 0.08,
            "bottle": 0.08,
            "coffee cup": 0.1,
            "stairs": 1.2,
            "waste container": 0.45,
            "computer monitor": 0.55,
            "door": 0.9,
        }
    )
    # Eval / webcam: derive f_x, f_y from horizontal FOV (no device intrinsics). Optional override: single calibrated f in pixels.
    horizontal_field_of_view_deg: float = 63.0
    focal_length_px: float | None = None
    emit_hz: float = 15.0
    camera_index: int = 0
    frame_width: int = 640
    frame_height: int = 480
    max_detection_ms: float = 50.0
    max_tracking_gap_s: float = 1.0
    max_match_distance_norm: float = 0.20
    enable_lens_check: bool = False
    lens_laplacian_max_side: int = 400
    lens_laplacian_threshold: float = 100.0
    lens_warn_consecutive: int = 4
    lens_announcement_text: str = ""
