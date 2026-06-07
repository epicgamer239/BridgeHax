from __future__ import annotations

import atexit
from dataclasses import replace
from threading import Lock, Thread
from pathlib import Path
from time import perf_counter, sleep, time
from typing import Any

import cv2
import numpy as np
from flask import Flask, Response, jsonify, request

from .config import VisualConfig
from .contracts import make_frame_payload
from .demo_hints import VISUAL_VERSION, hints_from_payload
from .lens_quality import LensWarningState
from .vision_engine import VisionEngine


class VisionService:
    def __init__(self, config: VisualConfig, use_local_camera: bool = True) -> None:
        self._config = config
        self._engine = VisionEngine(config)
        self._lens = LensWarningState(config) if config.enable_lens_check else None
        self._use_local_camera = use_local_camera
        self._capture: cv2.VideoCapture | None = None
        if use_local_camera:
            self._capture = cv2.VideoCapture(config.camera_index)
            self._capture.set(cv2.CAP_PROP_FRAME_WIDTH, config.frame_width)
            self._capture.set(cv2.CAP_PROP_FRAME_HEIGHT, config.frame_height)
            self._capture.set(cv2.CAP_PROP_FPS, config.emit_hz)

        self._payload_lock = Lock()
        self._stats_lock = Lock()
        self._latest_payload = make_frame_payload(
            frame_id=0, timestamp_ms=int(time() * 1000), vision_duration_ms=0, objects=[]
        )
        self._running = False
        self._worker: Thread | None = None
        self._frame_id = 0
        self._avg_detection_ms = 0.0
        self._effective_emit_hz = config.emit_hz
        self._latest_object_count = 0
        # When only iOS sends frames, mark source for /health
        self._inference_source = "local_camera" if use_local_camera else "ios_or_remote"
        self._t0 = time()

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        if not self._use_local_camera:
            return
        if self._capture is None or not self._capture.isOpened():
            raise RuntimeError("Camera could not be opened. Use --no-local-camera for iOS-only inference.")
        self._worker = Thread(target=self._run_loop, name="vision-loop", daemon=True)
        self._worker.start()

    def stop(self) -> None:
        self._running = False
        if self._worker and self._worker.is_alive():
            self._worker.join(timeout=2.0)
        if self._capture is not None:
            self._capture.release()
            self._capture = None

    def process_bgr_frame(self, bgr: np.ndarray) -> dict[str, Any]:
        """Run detection on a single BGR image (e.g. from an iOS camera) and update latest payload."""
        return self._apply_bgr(bgr, update_stats=True)

    def _apply_bgr(self, bgr: np.ndarray, update_stats: bool) -> dict[str, Any]:
        result = self._engine.process_frame(bgr)
        camera: dict | None = self._lens.update(bgr) if self._lens else None
        with self._stats_lock:
            self._frame_id += 1
            payload = make_frame_payload(
                frame_id=self._frame_id,
                timestamp_ms=int(time() * 1000),
                vision_duration_ms=result.duration_ms,
                objects=result.objects,
                camera=camera,
            )
        with self._payload_lock:
            self._latest_payload = payload
        with self._stats_lock:
            if update_stats:
                self._avg_detection_ms = (self._avg_detection_ms * 0.9) + (result.duration_ms * 0.1)
                self._latest_object_count = len(result.objects)
                if self._avg_detection_ms > self._config.max_detection_ms:
                    self._effective_emit_hz = 10.0
                else:
                    self._effective_emit_hz = self._config.emit_hz
        return dict(payload)

    def latest_payload(self) -> dict:
        with self._payload_lock:
            return dict(self._latest_payload)

    def status(self) -> dict:
        with self._stats_lock:
            return {
                "running": self._running,
                "inference_source": self._inference_source,
                "local_camera": self._use_local_camera,
                "frame_id": self._frame_id,
                "latest_object_count": self._latest_object_count,
                "effective_emit_hz": round(self._effective_emit_hz, 2),
                "avg_detection_ms": round(self._avg_detection_ms, 2),
            }

    def _run_loop(self) -> None:
        if self._capture is None:
            return
        next_emit = perf_counter()
        while self._running:
            now = perf_counter()
            if now < next_emit:
                sleep(next_emit - now)
                continue

            ok, frame = self._capture.read()
            if not ok:
                sleep(0.05)
                continue

            self._apply_bgr(frame, update_stats=True)
            with self._stats_lock:
                interval_s = 1.0 / self._effective_emit_hz
            next_emit = perf_counter() + interval_s


def _add_cors_headers(response: Any) -> Any:
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    return response


def create_app(config: VisualConfig, use_local_camera: bool = True) -> Flask:
    app = Flask(__name__)
    app.after_request(_add_cors_headers)

    service = VisionService(config, use_local_camera=use_local_camera)
    service.start()

    @app.get("/health")
    def health() -> tuple[dict, int]:
        snap = service.latest_payload()
        body = {
            "status": "ok",
            **service.status(),
            "uptime_s": round(time() - service._t0, 2),
            "visual_version": VISUAL_VERSION,
            "hints": hints_from_payload(snap),
        }
        return body, 200

    @app.get("/frame")
    def frame() -> tuple[dict, int]:
        return jsonify(service.latest_payload()), 200

    @app.get("/payload")
    def payload() -> tuple[dict, int]:
        """Alias of `/frame` (same contract). Use this name for the Hearing / spatial engine."""
        return jsonify(service.latest_payload()), 200

    @app.route("/infer", methods=["POST", "OPTIONS"])
    def infer() -> tuple[Any, int]:
        if request.method == "OPTIONS":
            return "", 204
        bgr: np.ndarray | None = None
        upload = request.files.get("image")
        if upload is not None and getattr(upload, "filename", None):
            nparr = np.frombuffer(upload.read(), np.uint8)
            bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if bgr is None:
            raw = request.get_data(cache=False, as_text=False)
            if raw:
                nparr = np.frombuffer(raw, np.uint8)
                bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if bgr is None or bgr.size == 0:
            return (
                jsonify(
                    {
                        "error": "expected JPEG: raw POST body (image/jpeg) or multipart file field 'image'.",
                    }
                ),
                400,
            )
        payload = service.process_bgr_frame(bgr)
        return jsonify(payload), 200

    _judge_path = Path(__file__).with_name("judge.html")

    @app.get("/")
    def index() -> str:
        return (
            "<!DOCTYPE html><html><head><meta charset='utf-8'/><title>VisionBridge Visual</title></head><body"
            " style='font-family:system-ui;background:#0a0c10;color:#e8eaef;padding:2rem;'>"
            "<h1>VisionBridge — Visual</h1><p>"
            "<a style='color:#6ea8ff' href='/judge'>Open judge + demo dashboard</a> (best for live pitch)</p>"
            "<p><a style='color:#6ea8ff' href='/health'>/health</a> &middot; "
            "<a style='color:#6ea8ff' href='/frame'>/frame</a></p></body></html>"
        )

    @app.get("/judge")
    def judge() -> Any:
        try:
            html = _judge_path.read_text(encoding="utf-8")
        except OSError as e:
            return (
                jsonify(
                    {
                        "error": "judge.html missing",
                        "path": str(_judge_path),
                        "details": str(e),
                    }
                ),
                500,
            )
        return Response(html, mimetype="text/html; charset=utf-8")

    atexit.register(service.stop)

    return app


def apply_overrides(
    config: VisualConfig,
    confidence: float | None = None,
    focal_length_px: float | None = None,
    horizontal_field_of_view_deg: float | None = None,
    emit_hz: float | None = None,
    camera_index: int | None = None,
) -> VisualConfig:
    updated = config
    if confidence is not None:
        updated = replace(updated, confidence_threshold=confidence)
    if focal_length_px is not None:
        updated = replace(updated, focal_length_px=focal_length_px)
    if horizontal_field_of_view_deg is not None:
        updated = replace(updated, horizontal_field_of_view_deg=horizontal_field_of_view_deg)
    if emit_hz is not None:
        updated = replace(updated, emit_hz=emit_hz)
    if camera_index is not None:
        updated = replace(updated, camera_index=camera_index)
    return updated

