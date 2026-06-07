import cv2
import numpy as np

from visual_engine.config import VisualConfig
from visual_engine.lens_quality import LensWarningState, laplacian_variance_bgr


def test_laplacian_sharp_above_blur() -> None:
    sharp = np.random.randint(0, 256, (240, 320, 3), dtype=np.uint8)
    blur = cv2.GaussianBlur(sharp, (25, 25), 0)
    vs = laplacian_variance_bgr(sharp)
    vb = laplacian_variance_bgr(blur)
    assert vs > vb, f"sharp {vs} vs blur {vb}"


def test_lens_warning_after_consecutive_blur() -> None:
    sharp = np.random.randint(0, 256, (240, 320, 3), dtype=np.uint8)
    blur = cv2.GaussianBlur(sharp, (25, 25), 0)
    vs = laplacian_variance_bgr(sharp)
    vb = laplacian_variance_bgr(blur)
    thr = (vs + vb) / 2.0
    cfg = VisualConfig(
        enable_lens_check=True,
        lens_laplacian_threshold=thr,
        lens_warn_consecutive=3,
    )
    st = LensWarningState(cfg)
    assert st.update(blur)["lens_status"] == "ok"
    assert st.update(blur)["lens_status"] == "ok"
    assert st.update(blur)["lens_status"] == "warning"
    assert st.update(sharp)["lens_status"] == "ok"
