from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .config import VisualConfig


@dataclass(slots=True)
class LensAnalysis:
    laplacian_variance: float
    lens_status: str  # "ok" | "warning"
    announce: str | None


def laplacian_variance_bgr(
    bgr: np.ndarray,
    max_side: int = 400,
) -> float:
    h, w = bgr.shape[:2]
    m = max(h, w)
    if m > max_side and m > 0:
        scale = max_side / m
        bgr = cv2.resize(
            bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA
        )
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


class LensWarningState:
    """Persistent lens-smudge detector: low sharpness (Laplacian variance) over several frames."""

    def __init__(self, config: VisualConfig) -> None:
        self._config = config
        self._streak: int = 0

    def update(self, bgr: np.ndarray) -> dict:
        if not self._config.enable_lens_check:
            return {
                "lens_status": "ok",
                "lens_laplacian_var": 0.0,
                "lens_announce": None,
            }
        v = laplacian_variance_bgr(
            bgr, max_side=self._config.lens_laplacian_max_side
        )
        if v < self._config.lens_laplacian_threshold:
            self._streak += 1
        else:
            self._streak = 0

        if self._streak >= self._config.lens_warn_consecutive:
            st = "warning"
            ann = self._config.lens_announcement_text
        else:
            st = "ok"
            ann = None

        return {
            "lens_status": st,
            "lens_laplacian_var": round(v, 2),
            "lens_announce": ann,
        }

    def reset(self) -> None:
        self._streak = 0
