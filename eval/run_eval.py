#!/usr/bin/env python3
"""Run local evaluation for VisionBridge vision pipeline.

Supports labels via CSV:
frame,class,x1,y1,x2,y2,distance_bucket

Distance bucket accepted values: <1m,1-3m,3-6m,>6m
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean

import cv2
import numpy as np

import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from visual_engine.config import VisualConfig  # noqa: E402
from visual_engine.vision_engine import VisionEngine  # noqa: E402


DIST_BUCKETS = ("<1m", "1-3m", "3-6m", ">6m")


def bucket_distance(d: float) -> str:
    if d < 1.0:
        return "<1m"
    if d < 3.0:
        return "1-3m"
    if d < 6.0:
        return "3-6m"
    return ">6m"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="VisionBridge eval harness")
    p.add_argument("--clips-dir", type=Path, required=True, help="Directory with video clips")
    p.add_argument("--labels-csv", type=Path, required=True, help="Ground truth CSV")
    p.add_argument("--report-path", type=Path, default=Path("eval/report.md"), help="Markdown report output")
    p.add_argument("--dry-run", action="store_true", help="Validate inputs and print what would run")
    return p.parse_args()


def load_labels(csv_path: Path) -> dict[tuple[str, int], list[dict]]:
    out: dict[tuple[str, int], list[dict]] = defaultdict(list)
    with csv_path.open(newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        for row in r:
            clip = row["frame"].split(":")[0] if ":" in row["frame"] else row["frame"]
            frame_idx = int(row["frame"].split(":")[1]) if ":" in row["frame"] else int(row.get("frame_idx", 0))
            out[(clip, frame_idx)].append(
                {
                    "class": row["class"].strip().lower(),
                    "bbox": [float(row["x1"]), float(row["y1"]), float(row["x2"]), float(row["y2"])],
                    "distance_bucket": row["distance_bucket"].strip(),
                }
            )
    return out


def iou_xyxy(a: list[float], b: list[float]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    aa = max(1e-9, (ax2 - ax1) * (ay2 - ay1))
    ba = max(1e-9, (bx2 - bx1) * (by2 - by1))
    return inter / max(1e-9, aa + ba - inter)


def run_eval(clips_dir: Path, labels: dict[tuple[str, int], list[dict]]) -> dict:
    eng = VisionEngine(VisualConfig())
    tp = defaultdict(int)
    fp = defaultdict(int)
    fn = defaultdict(int)
    distance_bucket_errors = defaultdict(list)

    clips = sorted(p for p in clips_dir.iterdir() if p.suffix.lower() in {".mp4", ".mov", ".m4v"})
    for clip in clips:
        cap = cv2.VideoCapture(str(clip))
        frame_idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            gt = labels.get((clip.name, frame_idx), [])
            pred = eng.process_frame(frame).objects
            pred_rows = []
            h, w = frame.shape[:2]
            for p in pred:
                x1 = (p.bbox.x_center_norm - p.bbox.width_norm / 2.0) * w
                x2 = (p.bbox.x_center_norm + p.bbox.width_norm / 2.0) * w
                y1 = (p.bbox.y_center_norm - p.bbox.height_norm / 2.0) * h
                y2 = (p.bbox.y_center_norm + p.bbox.height_norm / 2.0) * h
                pred_rows.append({"class": p.class_name.lower(), "bbox": [x1, y1, x2, y2], "distance_m": p.distance_m})

            used = set()
            for g in gt:
                gcls = g["class"]
                best_iou = 0.0
                best_j = None
                for j, p in enumerate(pred_rows):
                    if j in used or p["class"] != gcls:
                        continue
                    ii = iou_xyxy(g["bbox"], p["bbox"])
                    if ii > best_iou:
                        best_iou = ii
                        best_j = j
                if best_j is not None and best_iou >= 0.5:
                    used.add(best_j)
                    tp[gcls] += 1
                    pb = bucket_distance(pred_rows[best_j]["distance_m"])
                    distance_bucket_errors[gcls].append((g["distance_bucket"], pb))
                else:
                    fn[gcls] += 1
            for j, p in enumerate(pred_rows):
                if j not in used:
                    fp[p["class"]] += 1
            frame_idx += 1
        cap.release()

    per_class = {}
    for c in sorted(set(tp) | set(fp) | set(fn)):
        t, f_p, f_n = tp[c], fp[c], fn[c]
        prec = t / max(1, t + f_p)
        rec = t / max(1, t + f_n)
        fpr = f_p / max(1, t + f_p + f_n)
        errs = distance_bucket_errors.get(c, [])
        acc = mean([1.0 if a == b else 0.0 for a, b in errs]) if errs else 0.0
        per_class[c] = {
            "precision": prec,
            "recall": rec,
            "false_positive_rate": fpr,
            "distance_bucket_accuracy": acc,
            "samples": len(errs),
        }
    return {"per_class": per_class}


def write_report(path: Path, result: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# VisionBridge Eval Report", "", "## Per-class metrics", ""]
    lines.append("| class | precision | recall | false_positive_rate | distance_bucket_accuracy | samples |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for c, m in sorted(result["per_class"].items()):
        lines.append(
            f"| {c} | {m['precision']:.3f} | {m['recall']:.3f} | {m['false_positive_rate']:.3f} | {m['distance_bucket_accuracy']:.3f} | {m['samples']} |"
        )
    lines.append("")
    lines.append("## Distance buckets")
    lines.append(f"- Buckets: {', '.join(DIST_BUCKETS)}")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    args = parse_args()
    labels = load_labels(args.labels_csv)
    if args.dry_run:
        clips = sorted(p.name for p in args.clips_dir.iterdir() if p.suffix.lower() in {".mp4", ".mov", ".m4v"})
        print("Dry run")
        print("clips:", clips)
        print("labels rows:", sum(len(v) for v in labels.values()))
        print("report:", args.report_path)
        return
    res = run_eval(args.clips_dir, labels)
    write_report(args.report_path, res)
    print("Wrote report:", args.report_path)


if __name__ == "__main__":
    main()
