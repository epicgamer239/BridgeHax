import pytest

from visual_engine.config import VisualConfig
from visual_engine.simulation import SimulationEngine, SimulationReport


def test_simulation_lens_streak_produces_valid_payloads() -> None:
    eng = SimulationEngine(VisualConfig())
    r = eng.run_lens_streak(n_sharp=2, n_blur=4)
    assert isinstance(r, SimulationReport)
    assert r.scenario == "lens_streak"
    assert len(r.payloads) == 6
    assert r.ok()
    assert any(
        p.get("camera", {}).get("lens_status") == "warning" for p in r.payloads
    )


def test_simulation_lens_sharp_stays_ok() -> None:
    r = SimulationEngine(VisualConfig()).run_lens_sharp(frames=4)
    assert r.ok()
    for p in r.payloads:
        cam = p.get("camera")
        if cam:
            assert cam.get("lens_status") == "ok"


@pytest.mark.slow
def test_simulation_vision_random_runs() -> None:
    """YOLO: downloads weights on first run; can take tens of seconds."""
    r = SimulationEngine(VisualConfig()).run_vision_random(frames=1, width=320, height=240)
    assert r.frame_count == 1
    assert len(r.payloads) == 1
    # random noise: usually no allowlist class hits
    assert "objects" in r.payloads[0]
