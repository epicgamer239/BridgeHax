from __future__ import annotations

import argparse

from .app import apply_overrides, create_app
from .config import VisualConfig


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="VisionBridge visual engine server.")
    parser.add_argument("--host", default="127.0.0.1", help="Flask bind host.")
    parser.add_argument("--port", default=8765, type=int, help="Flask bind port.")
    parser.add_argument("--camera-index", default=None, type=int, help="OpenCV camera index.")
    parser.add_argument("--confidence", default=None, type=float, help="Detection confidence threshold.")
    parser.add_argument(
        "--focal-length-px",
        default=None,
        type=float,
        help="Override: single focal length in pixels (both axes). If omitted, HFOV is used.",
    )
    parser.add_argument(
        "--hfov-deg",
        default=None,
        type=float,
        help="Horizontal field of view in degrees (eval / webcam; default 63). Ignored if --focal-length-px is set.",
    )
    parser.add_argument("--emit-hz", default=None, type=float, help="Output payload frequency.")
    parser.add_argument(
        "--no-local-camera",
        action="store_true",
        help="Do not use the Mac/PC webcam; iPhone (or any client) sends frames via POST /infer.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = apply_overrides(
        VisualConfig(),
        confidence=args.confidence,
        focal_length_px=args.focal_length_px,
        horizontal_field_of_view_deg=args.hfov_deg,
        emit_hz=args.emit_hz,
        camera_index=args.camera_index,
    )
    app = create_app(config, use_local_camera=not args.no_local_camera)
    app.run(host=args.host, port=args.port, debug=False, threaded=True, use_reloader=False)


if __name__ == "__main__":
    main()

