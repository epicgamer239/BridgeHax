"""
Bench / desk simulation: synthetic BGR frames, no live camera, no iPhone.

Use for demos, CI (lens path without YOLO), or optional YOLO on random noise
(`vision_random` — may yield zero objects).

CLI: `PYTHONPATH=src python -m visual_engine.simulation --scenario lens_streak`
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field, replace
from time import time
from typing import Any, Literal

import numpy as np

from .config import VisualConfig
from .contracts import make_frame_payload
from .lens_quality import LensWarningState, laplacian_variance_bgr
from .synthesis import (
    gaussian_blur_bgr,
    lens_streak_sequence,
    random_sharp_bgr,
)
from .testing_engine import validate_frame_payload

ScenarioName = Literal["lens_streak", "lens_sharp", "vision_random"]


@dataclass
class SimulationReport:
    """Output of a simulation run (for tests, JSON export, or judges)."""

    scenario: str
    frame_count: int
    payloads: list[dict[str, Any]] = field(default_factory=list)
    validation_errors: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def ok(self) -> bool:
        return not self.validation_errors and all(
            not validate_frame_payload(p) for p in self.payloads
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "scenario": self.scenario,
            "frame_count": self.frame_count,
            "success": self.ok(),
            "validation_errors": self.validation_errors,
            "notes": self.notes,
            "payloads": self.payloads,
        }

    def payloads_json(self) -> str:
        return json.dumps(self.payloads, indent=2)


class SimulationEngine:
    """
    Synthetic frames + same payload merge as the Flask service
    (vision + optional lens) without a camera.
    """

    def __init__(self, config: VisualConfig | None = None) -> None:
        self._config = config or VisualConfig()

    def _calibrate_lens_threshold(
        self, sharp_bgr: np.ndarray, blur_bgr: np.ndarray
    ) -> VisualConfig:
        vs = laplacian_variance_bgr(
            sharp_bgr, max_side=self._config.lens_laplacian_max_side
        )
        vb = laplacian_variance_bgr(
            blur_bgr, max_side=self._config.lens_laplacian_max_side
        )
        if not (vs > vb):
            raise ValueError(
                f"calibration expected sharp var > blur var, got {vs} vs {vb}"
            )
        thr = (vs + vb) / 2.0
        return replace(
            self._config, lens_laplacian_threshold=thr, enable_lens_check=True
        )

    def run_lens_streak(
        self,
        n_sharp: int = 2,
        n_blur: int = 4,
    ) -> SimulationReport:
        """
        Some sharp random frames, then repeated heavy blur (smear).
        Auto-calibrates `lens_laplacian_threshold` so blur reads as "low."
        With enough consecutive blur frames, `lens_status` -> warning.
        """
        if n_sharp < 1 or n_blur < 1:
            raise ValueError("lens_streak needs n_sharp >= 1 and n_blur >= 1")
        seq = lens_streak_sequence(n_sharp, n_blur)
        s0 = next(b for lab, b in seq if lab == "sharp")
        b0 = next(b for lab, b in seq if lab == "blur")
        cfg = self._calibrate_lens_threshold(s0, b0)
        warn_after = 2 if n_blur >= 2 else 1
        cfg2 = replace(cfg, lens_warn_consecutive=warn_after)
        st = LensWarningState(cfg2)
        report = SimulationReport(
            scenario="lens_streak", frame_count=len(seq), notes=[]
        )
        for i, (_lab, bgr) in enumerate(seq, start=1):
            camera = st.update(bgr) if cfg2.enable_lens_check else None
            p = make_frame_payload(
                frame_id=i,
                timestamp_ms=1_000_000 + i,
                vision_duration_ms=0,
                objects=[],
                camera=camera,
            )
            report.payloads.append(p)
            for e in validate_frame_payload(p):
                report.validation_errors.append(f"frame {i}: {e}")
        report.notes.append(
            f"threshold≈{cfg2.lens_laplacian_threshold:.1f} warn_streak>={cfg2.lens_warn_consecutive}"
        )
        return report

    def run_lens_sharp(
        self,
        frames: int = 5,
    ) -> SimulationReport:
        """All sharp random noise → `lens_status` should stay ok."""
        b0 = random_sharp_bgr(240, 320, seed=0)
        b_blur = gaussian_blur_bgr(b0, 25)
        b1 = random_sharp_bgr(240, 320, seed=1)
        cfg = self._calibrate_lens_threshold(b1, b_blur)
        st = LensWarningState(cfg)
        report = SimulationReport(
            scenario="lens_sharp", frame_count=frames, notes=[]
        )
        for i in range(frames):
            bgr = random_sharp_bgr(240, 320, seed=10 + i)
            cam = st.update(bgr) if cfg.enable_lens_check else None
            p = make_frame_payload(
                frame_id=i + 1,
                timestamp_ms=2_000_000 + i,
                vision_duration_ms=0,
                objects=[],
                camera=cam,
            )
            report.payloads.append(p)
            for e in validate_frame_payload(p):
                report.validation_errors.append(f"frame {i+1}: {e}")
            if p.get("camera", {}).get("lens_status") == "warning":
                report.validation_errors.append(
                    f"frame {i+1}: unexpected lens warning on sharp sim"
                )
        return report

    def run_vision_random(
        self,
        frames: int = 2,
        width: int = 640,
        height: int = 480,
    ) -> SimulationReport:
        """
        Full YOLOv8m Open Images V7 on random BGR (often 0 objects). Pulls in `yolov8m-oiv7.pt` on first use.
        Requires: `ultralytics` and model weights.
        """
        from .vision_engine import VisionEngine

        report = SimulationReport(
            scenario="vision_random",
            frame_count=frames,
            notes=["yolov8m-oiv7 + lens merge"],
        )
        engine = VisionEngine(self._config)
        st = (
            LensWarningState(self._config) if self._config.enable_lens_check else None
        )
        for i in range(frames):
            bgr = random_sharp_bgr(height, width, seed=200 + i)
            vr = engine.process_frame(bgr)
            camera = st.update(bgr) if st else None
            p = make_frame_payload(
                frame_id=i + 1,
                timestamp_ms=int(time() * 1000),
                vision_duration_ms=vr.duration_ms,
                objects=vr.objects,
                camera=camera,
            )
            report.payloads.append(p)
            for e in validate_frame_payload(p):
                report.validation_errors.append(f"frame {i+1}: {e}")
        return report

    def run(
        self,
        scenario: ScenarioName,
        **kwargs: Any,
    ) -> SimulationReport:
        if scenario == "lens_streak":
            return self.run_lens_streak(
                n_sharp=kwargs.get("n_sharp", 2),
                n_blur=kwargs.get("n_blur", 4),
            )
        if scenario == "lens_sharp":
            return self.run_lens_sharp(frames=kwargs.get("frames", 5))
        if scenario == "vision_random":
            return self.run_vision_random(
                frames=kwargs.get("frames", 2),
                width=kwargs.get("width", 640),
                height=kwargs.get("height", 480),
            )
        raise ValueError(f"unknown scenario: {scenario}")


def _parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="VisionBridge vision simulation (synthetic frames).")
    p.add_argument(
        "--scenario",
        choices=["lens_streak", "lens_sharp", "vision_random"],
        default="lens_streak",
        help="lens_streak: smudge warning; lens_sharp: all ok; vision_random: YOLOv8m-oiv7+noise (slow, downloads model).",
    )
    p.add_argument("--n-sharp", type=int, default=2, help="lens_streak: sharp lead-in frames")
    p.add_argument("--n-blur", type=int, default=4, help="lens_streak: smeared tail frames")
    p.add_argument("--frames", type=int, default=5, help="lens_sharp / vision_random frame count")
    p.add_argument(
        "--print",
        action="store_true",
        help="print full report JSON to stdout (includes payloads).",
    )
    p.add_argument(
        "--payloads-only",
        action="store_true",
        help="print only the JSON array of frame payloads.",
    )
    return p.parse_args()


def main() -> int:
    args = _parse()
    eng = SimulationEngine(VisualConfig())
    try:
        r = eng.run(
            args.scenario,
            n_sharp=args.n_sharp,
            n_blur=args.n_blur,
            frames=args.frames,
        )
    except Exception as e:  # noqa: BLE001
        err = {"success": False, "error": str(e), "scenario": args.scenario}
        print(json.dumps(err, indent=2))
        return 1
    if args.payloads_only:
        print(r.payloads_json())
    elif args.print:
        print(json.dumps(r.to_dict(), indent=2))
    else:
        out = {k: v for k, v in r.to_dict().items() if k != "payloads"}
        out["payload_count"] = len(r.payloads)
        out["first_camera"] = (r.payloads[0].get("camera") if r.payloads else None)
        out["last_camera"] = (r.payloads[-1].get("camera") if r.payloads else None)
        print(json.dumps(out, indent=2))
    return 0 if r.ok() else 1


if __name__ == "__main__":
    sys.exit(main())
