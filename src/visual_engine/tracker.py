from __future__ import annotations

from dataclasses import dataclass
from math import hypot
from time import monotonic


@dataclass(slots=True)
class TrackState:
    object_id: str
    class_name: str
    x_center_norm: float
    y_center_norm: float
    distance_m: float
    updated_at: float


class ObjectTracker:
    def __init__(self, max_gap_s: float = 1.0, max_match_distance_norm: float = 0.2) -> None:
        self._tracks: dict[str, TrackState] = {}
        self._class_counters: dict[str, int] = {}
        self._max_gap_s = max_gap_s
        self._max_match_distance_norm = max_match_distance_norm

    def update(self, detections: list[dict]) -> list[dict]:
        now = monotonic()
        self._expire_old_tracks(now)
        assigned: list[dict] = []
        used_track_ids: set[str] = set()

        for detection in detections:
            class_name = detection["class_name"]
            x = detection["bbox"]["x_center_norm"]
            y = detection["bbox"]["y_center_norm"]
            distance_m = detection["distance_m"]

            track = self._best_track_match(class_name, x, y, used_track_ids)
            if track is None:
                object_id = self._next_object_id(class_name)
                velocity_mps = 0.0
            else:
                dt = max(now - track.updated_at, 1e-3)
                velocity_mps = abs(track.distance_m - distance_m) / dt
                object_id = track.object_id
                used_track_ids.add(track.object_id)

            self._tracks[object_id] = TrackState(
                object_id=object_id,
                class_name=class_name,
                x_center_norm=x,
                y_center_norm=y,
                distance_m=distance_m,
                updated_at=now,
            )

            assigned.append(
                {
                    **detection,
                    "object_id": object_id,
                    "velocity_mps": round(velocity_mps, 2),
                    "priority": "HIGH" if distance_m < 3.0 else "NORMAL",
                }
            )
        return assigned

    def _best_track_match(
        self,
        class_name: str,
        x: float,
        y: float,
        used_track_ids: set[str],
    ) -> TrackState | None:
        best: TrackState | None = None
        best_distance = float("inf")
        for state in self._tracks.values():
            if state.class_name != class_name or state.object_id in used_track_ids:
                continue
            dist = hypot(state.x_center_norm - x, state.y_center_norm - y)
            if dist < best_distance:
                best_distance = dist
                best = state
        if best is None or best_distance > self._max_match_distance_norm:
            return None
        return best

    def _expire_old_tracks(self, now: float) -> None:
        expired = [
            object_id
            for object_id, state in self._tracks.items()
            if now - state.updated_at > self._max_gap_s
        ]
        for object_id in expired:
            self._tracks.pop(object_id, None)

    def _next_object_id(self, class_name: str) -> str:
        current = self._class_counters.get(class_name, 0) + 1
        self._class_counters[class_name] = current
        return f"{class_name}_{current:03d}"

