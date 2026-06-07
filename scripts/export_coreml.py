#!/usr/bin/env python3
"""Export Ultralytics YOLOv8m Open Images V7 to CoreML with NMS for Vision (iOS).

Run from repo root: pip install -r requirements.txt && python3 scripts/export_coreml.py

Output: `yolov8m-oiv7.mlpackage` in the repo root and copied to `App/` for the synchronized Xcode group.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from ultralytics import YOLO

REPO = Path(__file__).resolve().parents[1]
PT_FILE = "yolov8m-oiv7.pt"
BUNDLE_STEM = "yolov8m-oiv7"


def main() -> None:
    model = YOLO(PT_FILE)
    out = model.export(
        format="coreml",
        nms=True,
        imgsz=640,
    )
    out_path = Path(out).resolve()
    print("Exported:", out_path)
    if not out_path.exists():
        return
    dest = out_path.parent / f"{BUNDLE_STEM}.mlpackage"
    if out_path != dest:
        if dest.exists():
            shutil.rmtree(dest)
        out_path.rename(dest)
        print("Renamed to:", dest)
    app_dest = REPO / "App" / f"{BUNDLE_STEM}.mlpackage"
    if app_dest.exists():
        shutil.rmtree(app_dest)
    shutil.copytree(dest, app_dest)
    shutil.rmtree(dest)
    print("Copied to:", app_dest, "(removed duplicate next to script cwd)")
    print(
        f"Ensure {BUNDLE_STEM}.mlpackage is included in the iOS app target "
        f"(repo `App/` folder is synchronized into the VisionBridge target)."
    )


if __name__ == "__main__":
    main()
