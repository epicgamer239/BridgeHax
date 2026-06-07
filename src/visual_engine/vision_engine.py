from __future__ import annotations

from dataclasses import dataclass
from time import perf_counter

import numpy as np
from ultralytics import YOLO

from .bbox_in_frame import bbox_area_fraction_inside_image
from .config import VisualConfig
from .distance_model import monocular_distance_m
from .contracts import BBoxNorm, DetectedObject
from .tracker import ObjectTracker


@dataclass(slots=True)
class VisionResult:
    objects: list[DetectedObject]
    duration_ms: int


class VisionEngine:
    def __init__(self, config: VisualConfig) -> None:
        self._config = config
        self._model = YOLO(config.model_path)
        self._tracker = ObjectTracker(
            max_gap_s=config.max_tracking_gap_s,
            max_match_distance_norm=config.max_match_distance_norm,
        )
        self._names = self._model.names

    def process_frame(self, frame: np.ndarray) -> VisionResult:
        start = perf_counter()
        frame_h, frame_w = frame.shape[:2]
        results = self._model.predict(
            source=frame,
            conf=self._config.confidence_threshold,
            verbose=False,
            classes=None,
        )

        min_frac = self._config.min_bbox_area_fraction_in_frame
        class_conf = self._config.class_confidence_thresholds
        class_min_area = self._config.min_box_area_fraction_by_class

        detections: list[dict] = []
        for result in results:
            for box in result.boxes:
                confidence = float(box.conf.item())
                class_id = int(box.cls.item())
                class_name = str(self._names[class_id]).lower().strip()
                if class_name not in self._config.target_classes:
                    continue
                if confidence < class_conf.get(class_name, self._config.confidence_threshold):
                    continue
                x1, y1, x2, y2 = [float(v) for v in box.xyxy[0].tolist()]
                if (
                    bbox_area_fraction_inside_image(
                        x1, y1, x2, y2, frame_w, frame_h
                    )
                    < min_frac
                ):
                    continue
                bbox_w = max(x2 - x1, 1.0)
                bbox_h = max(y2 - y1, 1.0)
                x_center = (x1 + x2) / 2.0
                y_center = (y1 + y2) / 2.0

                pan_value = (x_center / frame_w - 0.5) * 2.0
                w_norm = bbox_w / frame_w
                h_norm = bbox_h / frame_h
                area_norm = w_norm * h_norm
                if area_norm < class_min_area.get(class_name, 0.0):
                    continue
                distance_m = monocular_distance_m(
                    class_name,
                    self._config.known_heights_m,
                    self._config.known_widths_m,
                    self._config.focal_length_px,
                    frame_w,
                    frame_h,
                    w_norm,
                    h_norm,
                    horizontal_fov_deg=self._config.horizontal_field_of_view_deg,
                )

                detections.append(
                    {
                        "class_name": class_name,
                        "confidence": round(confidence, 2),
                        "bbox": {
                            "x_center_norm": round(x_center / frame_w, 4),
                            "y_center_norm": round(y_center / frame_h, 4),
                            "width_norm": round(bbox_w / frame_w, 4),
                            "height_norm": round(bbox_h / frame_h, 4),
                        },
                        "distance_m": distance_m,
                        "pan_value": round(float(np.clip(pan_value, -1.0, 1.0)), 3),
                    }
                )

        tracked = self._tracker.update(detections)
        objects = [
            DetectedObject(
                object_id=item["object_id"],
                class_name=item["class_name"],
                confidence=item["confidence"],
                bbox=BBoxNorm(**item["bbox"]),
                distance_m=item["distance_m"],
                pan_value=item["pan_value"],
                velocity_mps=item["velocity_mps"],
                priority=item["priority"],
            )
            for item in tracked
        ]
        duration_ms = int((perf_counter() - start) * 1000)
        return VisionResult(objects=objects, duration_ms=duration_ms)
