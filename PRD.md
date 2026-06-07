# PRD: VisionBridge — TTS Assistive Perception Engine

**Independence Hackathon · BRIDGE Theme**
**Version:** 2.0.0 — As-Built Specification
**Status:** Field-beta candidate (advanced prototype)
**Repository:** VisionBridge (local) — product name **VisionBridge**

---

## Document status legend

| Label | Meaning |
|-------|---------|
| **Shipped** | Verified in `main`; default app path |
| **Implemented, unwired** | Code exists in `VisionBridgeKit` / `App/` but not active in default runtime |
| **Planned** | Specified here; not yet in repo |
| **Deprecated** | Superseded; kept for history only |

> **PRD maintenance:** When behavior or the JSON contract changes, update **§5**, bump the **Version** line (major = shipped/planned shift, minor = contract or policy, patch = typos), and keep **`docs/contract.example.json`**, **`README.md`**, **`docs/visual-integration.md`**, and **`docs/manual_test_scenarios.md`** in sync. Append vision/contract changes to **`docs/VISION_BRANCH_LOG.md`** in the same commit.

---

## 0. Executive summary

**VisionBridge** is an on-device iOS accessibility engine that uses the iPhone camera and CoreML object detection to identify nearby obstacles and hazards, then speaks concise, directional guidance through text-to-speech (TTS).

**Shipped modality:** Priority-gated **TTS** with directional phrasing, distance confidence tiers, deduplication, haptics, and a live radar HUD — **not** a continuous 3D spatial audio soundscape.

**Primary user:** People who are blind or have low vision navigating environments where some hazards are visually obvious but acoustically silent (parked EVs, cyclists, curbs, stairs).

**Production path:** iPhone on-body (lanyard or chest mount), **100% on-device inference**, no cloud required for live assist.

**Dev/integration path:** Optional Python Flask bridge on a Mac (`POST /infer`, `GET /frame`) for judge dashboards and team testing — **not** the sponsor edge-AI story unless inference runs on the phone.

---

## 1. Product definition

### 1.1 Theme alignment (BRIDGE)

The product **bridges** the visual world to spoken awareness. In the shipped build, this bridge is expressed as **spoken guidance** — class, direction, and estimated distance — rather than persistent spatial audio objects. The metaphor is clear: the phone sees; the user hears what matters, connecting the sighted world to those who cannot see.

### 1.2 Safety disclaimer (required everywhere)

VisionBridge is **assistive technology**. It is **not** a replacement for:

- A white cane or guide dog
- Orientation and mobility (O&M) training
- Human judgment or traffic rules

All distances are **estimates**, not measurements. Detection can miss objects, misclassify them, or report impossible ranges. Users must treat output as supplementary awareness, not guaranteed truth.

This disclaimer must appear in: PRD, README, onboarding, in-app safety strip (`ContentView`), demo script, and App Store copy.

### 1.3 Operating envelope

| Assumption | Specification |
|------------|---------------|
| Device | iPhone 12 or newer recommended (Apple Neural Engine) |
| Camera | Rear wide camera, forward-facing on body |
| Mount | Lanyard or chest; stable enough for tracking |
| Movement | Walking pace; rapid pan triggers speech queue flush |
| Lighting | Daylight / typical indoor; low-light reduces confidence |
| Headphones | Recommended for clarity; **not** required for HRTF (not shipped) |
| Network | **None** required for on-device path |
| LiDAR | iPhone Pro only; depth tier **implemented but unwired** (see §3.3) |

### 1.4 Success criteria (measurable)

| Goal | Demo target | Field-beta target |
|------|-------------|-------------------|
| Hazard detection (person, vehicle) | Usable in controlled clips | ≥85% recall on eval set (§3.1) |
| Speech signal-to-noise | No overlap in manual scenarios | ≤2 utterances / 5s in critical-only dense scene |
| Distance trust | No absurd numeric speech | Confidence-aware phrasing 100% of distance lines |
| On-device inference | Model loads, scan runs | Clean install + 15+ min session without crash |
| Latency (vision) | `vision_duration_ms` visible in HUD | p50 ≤ 50 ms on target device |

---

## 2. Shipped user experience

### 2.1 First-run flow (**Shipped**)

1. **Onboarding** (`OnboardingView`) — 3-page intro; user taps through to "Start VisionBridge."
2. **Auto-start scan** — If CoreML model is bundled, scanning begins on dashboard appear (`ContentView`).
3. **Live dashboard** — Radar visualization, threat indicator, optional payload HUD, settings access.
4. **Stop scan** — User stops via scan control; hears "VisionBridge scan stopped."

> **Planned:** Optional "Lanyard Mode" — fullscreen minimal status dot only (PRD v1 described this; not shipped).

### 2.2 App states

| State | User-visible behavior |
|-------|----------------------|
| `IDLE` | Model missing or scan off; system messages only |
| `SCANNING` | Camera + vision active; TTS + haptics per policy |
| `ALERT` | HUD shows alert when `distance_m < 3` **and** `velocity_mps > 1.5` (visual indicator only; speech priority uses distance tier) |
| `MUTED` | Two-finger double-tap → 10s silence + resume banner |
| `DEBUG` | Payload HUD, detection overlay, judge web UI (`ui/`) |

### 2.3 What the user hears (**Shipped**)

Example utterances (via `PhraseBuilder`):

| Confidence | Example |
|------------|---------|
| High | "Person to the left, about 2.3 meters away" |
| Medium | "Car straight ahead, roughly 5 meters" |
| Low | "Bicycle to the right" (no numeric distance) |
| Unavailable | "Chair detected" |

**Empty scene:** "No obstacles detected" — at most once per 12 seconds while scanning.

**System one-shots:** Model missing, camera denied — spoken once per session key.

### 2.4 Physical UI (**Shipped**)

**Haptics** (`HapticManager`) fire on high-priority or very-close objects even when speech is deduped:

| Condition | Haptic |
|-----------|--------|
| `distance_m < 1.5` | Critical threat |
| `priority == HIGH` | Warning |
| Close non-high | Discovery |

Toggle: Settings → Haptics (default **on**).

### 2.5 Controls & accessibility (**Shipped**)

| Control | Action |
|---------|--------|
| Scan toggle | Start/stop camera + vision |
| Settings | Verbosity, voice style, units, critical-only, suppressed classes, telemetry, bridge URL |
| Two-finger double-tap | Mute speech 10 seconds |
| VoiceOver | Semantic labels on radar, scan, settings, mute banner |
| Dynamic Type | Settings and dashboard use semantic fonts |

### 2.6 Audio session (**Shipped**)

`AVAudioSession` category `.playback` with `.mixWithOthers` and `.duckOthers` — guidance ducks background music/podcasts when speaking.

### 2.7 Failure states

| Condition | Behavior |
|-----------|----------|
| Model not bundled | `modelAvailable = false`; one-shot reinstall message; bridge fallback optional |
| Camera denied | One-shot Settings prompt; scan does not start |
| Lens smudge | **Implemented, unwired** — `camera.lens_*` in contract; defaults off |
| Bridge unreachable | On-device path continues if model present; `isUsingOnDevicePayload` reflects source |
| Scene change (>50% object drop) | Normal speech queue flushed immediately |

### 2.8 Judge / demo surfaces (**Shipped**)

- **iOS:** Payload HUD, optional bounding-box debug view, latency from `vision_duration_ms`
- **Web:** `ui/` dashboard polling Flask `GET /frame` / `GET /health`
- **Flask:** `GET /judge` live HTML panel

**Deprecated in docs:** WebSocket bridge (never implemented; HTTP polling only).

---

## 3. Perception engine

### 3.1 Vision model (**Shipped**)

| Property | Value |
|----------|-------|
| Model | YOLOv8m Open Images V7 — `yolov8m-oiv7.mlpackage` |
| Classes (model) | 601 Open Images V7 |
| Classes (emitted) | Mobility-focused subset in `VisionConfiguration.targetClassNames` |
| Runtime | CoreML + Vision (`VNCoreMLRequest`) on Apple Neural Engine |
| Rate cap | ~15 Hz emit; frames dropped if inference in-flight |
| Input | `CVPixelBuffer` from `CameraPipeline` |
| Export | `scripts/export_coreml.py` |

**Python parity:** `src/visual_engine/` mirrors contract for dev/eval (`eval/run_eval.py`).

### 3.2 Class policy

Three tiers govern detection allowlist and speech eligibility:

#### Tier A — Hazard (always eligible for speech)

`person`, `car`, `truck`, `bus`, `bicycle`, `motorcycle`, `dog`, `stairs`

Lower confidence bar at speech time (0.45–0.52 via `safetyTier`).

#### Tier B — Context (speech in normal/low-noise modes)

`traffic light`, `stop sign`, `fire hydrant`, `bench`, `chair`, `couch`, `cat`, `umbrella`, `backpack`, `handbag`, `suitcase`, `waste container`, `building`, `plant`, `bottle`

#### Tier C — Low-value / indoor clutter (detected; suppressed by default or high threshold)

`mobile phone`, `laptop`, `television`, `computer keyboard`, `computer mouse`, `remote control`, `coffee cup`, `computer monitor`, `kitchen & dining room table`

Per-class confidence overrides in `VisionConfiguration.classConfidenceThresholds` (e.g. mobile phone ≥ 0.86).

**User override:** Settings → suppressed classes CSV (default includes `clock`, `vase`, `wine glass`, `teddy bear`, `toothbrush`).

**Planned:** Sync Python `VisualConfig.target_classes` with iOS list (`building` currently iOS-only).

### 3.3 Distance estimation

#### Shipped: Monocular pinhole (all devices)

```
distance_m = (known_physical_size_m × focal_length_px) / bbox_axis_px
```

- **iOS:** `CameraIntrinsics` from `AVCaptureDevice` / sample buffer (`CameraIntrinsicsReader`) — **not** a fixed 850 px fudge factor.
- **Python bridge:** Default `focal_length_px = 850`; calibrate via `visual_engine.calibration` CLI.
- **Axes:** Height and width when both known; geometric mean when consistent (`VisionGeometry`).
- **Output clamps:** 0.3–20 m; large bbox fill → cap at 0.5 m.
- **Unmeasurable:** Sentinel `99.0` → `distance_confidence: unavailable`; no numeric speech.

**Known limitations (document, do not hide):**

- Reference heights/widths are population averages — children, trucks, partial boxes skew results.
- No LiDAR on non-Pro devices.
- First frames dropped until intrinsics available (`OnDeviceVisionEngine` guard).
- Python and iOS focal pipelines are **not numerically identical**.

#### Implemented, unwired: LiDAR depth tier (Pro devices)

`LiDARCaptureSession`, `sampleDepth(from:bbox:)`, forward **wall-ahead** probe in `OnDeviceVisionEngine`:

- Valid LiDAR sample → `distance_confidence: high`
- Invalid LiDAR → monocular fallback + `distance_confidence: low`
- Wall probe → synthetic `wall` object in payload

**Requirement to ship:** Wire `AppViewModel` to `LiDARCaptureSession` on supported hardware (today uses `CameraPipeline` only).

#### Planned: Guided calibration wizard

User places known object at known distance; app persists per-device focal adjustment.

### 3.4 Distance confidence (**Shipped**)

Assessed by `DistanceConfidenceAssessor` (monocular) or set by LiDAR sampler.

| Level | When | Speech |
|-------|------|--------|
| `high` | Stable bbox, low area variance, known size — or LiDAR-valid | Numeric (1 decimal if < 3 m) |
| `medium` | Moderate stability | Rounded meters / "roughly N feet" |
| `low` | Jump dampening, unstable box | Direction only + "nearby" / "farther ahead" |
| `unavailable` | No known size, heavy occlusion, unmeasurable | "Class detected" |

### 3.5 Tracking & priority

**Tracking** (`ObjectTracker`): persistent `object_id`, bbox association, `velocity_mps` = |Δdistance| / Δt.

| Field | Shipped rule |
|-------|--------------|
| `priority` | `"HIGH"` if `distance_m < highPriorityDistanceM` (default **3.0 m**) |
| `velocity_mps` | Scalar; used for **HUD alert** (`alertActive`), not speech priority gating |
| ID churn | Max match distance 0.24 norm; stale prune every 60 frames |

**Planned:** Directional approach velocity; `HIGH` only when approaching fast (`velocity > 1.5 m/s` toward user).

### 3.6 Lens quality (**Implemented, unwired**)

Laplacian variance on downscaled frame; consecutive low frames → `camera.lens_status: warning` + optional `lens_announce` TTS.

Defaults: `enableLensCheck: false`, `enableLensSpeech: false` in `VisionBridgeSession`.

**Planned for beta:** Enable lens check by default; one debounced smudge warning per session.

### 3.7 Detection accuracy requirements

Offline eval via `eval/run_eval.py` + labeled clips (`docs/manual_test_scenarios.md`).

| Metric | Demo | Field beta |
|--------|------|------------|
| Person recall @ 2–6 m | Manual pass | ≥ 85% |
| Vehicle recall @ 3–15 m | Manual pass | ≥ 80% |
| False positives (empty hallway) | ≤ 1 per 10 s speech | ≤ 0.2 / min |
| Distance bucket accuracy | Qualitative | ±1 bucket on 50% of labeled frames |

**Required test scenes:** empty hallway, person crossing, crowded sidewalk, vehicle at curb, night, lens smudge, rapid pan, frame-edge partials, background/foreground, headphones connect/disconnect.

### 3.8 Frame filtering

- Global min in-frame bbox area: **70%** (`minBboxAreaFractionInFrame`)
- Per-class min area for tiny false-positive classes (`minBoxAreaFractionByClass`)
- Pan gate: objects far off-axis may be suppressed for speech (`passesPanGate`)

---

## 4. Hearing engine (TTS policy)

**Shipped:** `App/HearingEngine.swift` — TTS-only; no `AVAudioEnvironmentNode` graph in production app.

**Deprecated prototype:** `AudioEngine/` — spatial tones + polling bridge (reference only).

### 4.1 Scheduler

| Mechanism | Value |
|-----------|-------|
| High priority | LIFO stack |
| Normal | FIFO queue |
| Max announcements / frame | 1 |
| Min interval between any speech | 0.85 s |
| Per-object cooldown | 10 s |
| Per-class cooldown | 4 s (furniture 4 s; "Computer" phrase 3 s) |
| Per-spatial-cell cooldown | 4 s |
| Queue cap per tier | 6 |
| Item TTL | 1.1 s |
| Stable frames before first speak | 3 |
| Min detector confidence (speech) | 0.62 (tier overrides apply earlier in pool) |
| Forced speak fallback | 2.2 s if detections present but all deduped |
| Scene flush | >50% object-count drop → flush normal queue |

### 4.2 Verbosity modes

| Mode | `ttsVerbosity` / flags | Behavior |
|------|------------------------|----------|
| **Low noise** (default) | `low` | Short phrases; suppresses non-high unless `hearingTones` forces periodic top-object line |
| **Normal** | `normal` | Full phrasing |
| **Critical only** | `ttsCriticalOnly` | Only `DetectionConfig.highPriorityClasses` within 3 m; ≤2 utterances / 5 s |

### 4.3 Voice styles

| Style | Character |
|-------|-----------|
| `calm` (default) | Softer rate/pitch |
| `clear` | Higher clarity |
| `compact` | Faster, shorter |

### 4.4 Distance units

`metric` (default) or `imperial` — all distance strings via `PhraseBuilder.phraseForDistance`.

### 4.5 Critical-only gating

When enabled, only hazard-tier classes under 3 m speak. Window limit: max 2 critical lines per 5 seconds.

### 4.6 Bridge fallback (**Shipped**)

If no on-device session, polls `GET /frame` at ~15 Hz (`pollInterval 0.066 s`). Configurable base URL in Settings (default `http://127.0.0.1:8765`).

### 4.7 Telemetry (**Shipped**, opt-in)

`TTSTelemetryStore` — queue depth, drop reasons, time-to-speak. Export from Settings when `ttsTelemetryEnabled`.

---

## 5. Technical contract

### 5.1 `FramePayload` JSON schema

```json
{
  "frame_id": 1042,
  "timestamp_ms": 1714052800123,
  "vision_duration_ms": 34,
  "camera": {
    "lens_status": "ok",
    "lens_laplacian_var": 235.4,
    "lens_announce": null
  },
  "objects": [
    {
      "object_id": "car_001",
      "class": "car",
      "confidence": 0.87,
      "bbox": {
        "x_center_norm": 0.32,
        "y_center_norm": 0.61,
        "width_norm": 0.18,
        "height_norm": 0.14
      },
      "distance_m": 8.4,
      "distance_confidence": "medium",
      "pan_value": -0.36,
      "velocity_mps": 2.1,
      "priority": "NORMAL"
    }
  ]
}
```

**Field definitions:**

| Field | Type | Notes |
|-------|------|-------|
| `frame_id` | int | Monotonic per session |
| `timestamp_ms` | int64 | Unix epoch ms |
| `vision_duration_ms` | int | Inference + post-process on device |
| `camera` | object? | Omitted when lens check disabled |
| `camera.lens_status` | `"ok"` \| `"warning"` | |
| `camera.lens_laplacian_var` | float | Sharpness proxy |
| `camera.lens_announce` | string? | TTS text when warning; else null |
| `object_id` | string | `{class}_{counter}` stable across frames |
| `class` | string | Lowercase Open Images V7 name |
| `confidence` | float | 0–1 |
| `bbox.*_norm` | float | 0–1, top-left origin for y |
| `distance_m` | float | Meters; clamped |
| `distance_confidence` | string? | `high` \| `medium` \| `low` \| `unavailable` |
| `pan_value` | float | −1 (left) to +1 (right) |
| `velocity_mps` | float | Non-negative scalar |
| `priority` | string | `"HIGH"` \| `"NORMAL"` |

**Synthetic classes (LiDAR path only):** `wall` — forward obstacle probe.

Canonical example: `docs/contract.example.json`.

### 5.2 Python Flask API (dev / judge)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Process status, rolling averages |
| `/frame` | GET | Latest `FramePayload` snapshot |
| `/payload` | GET | Alias used by legacy AudioEngine simulator |
| `/infer` | POST | JPEG body → infer + update snapshot |
| `/judge` | GET | HTML judge panel |
| CORS | OPTIONS | `Access-Control-Allow-Origin: *` |

Default bind: `127.0.0.1:8765`. LAN: `--host 0.0.0.0`, iPhone `POST /infer`, server `--no-local-camera`.

### 5.3 Latency budget (revised, honest)

| Stage | Instrument | Demo p50 | Stretch |
|-------|------------|----------|---------|
| Vision inference | `vision_duration_ms` in payload | ≤ 50 ms | ≤ 35 ms |
| Vision → speech decision | Telemetry | ≤ 50 ms | ≤ 30 ms |
| Decision → phoneme start | TTS telemetry `timeToSpeakMs` | ≤ 200 ms | ≤ 100 ms |

> **Note:** Sub-100 ms end-to-end to **first audible phoneme** is a stretch goal, not a safety guarantee. TTS queueing and dedupe intentionally add delay to prevent overlap. The safety story is **conservative speech policy + haptics**, not raw speed alone.

### 5.4 Configuration source of truth

| Knob | Swift (`VisionConfiguration`) | Python (`VisualConfig`) |
|------|------------------------------|---------------------------|
| `confidence_threshold` | 0.58 | 0.58 |
| `min_bbox_area_fraction_in_frame` | 0.7 | 0.7 |
| Focal length | `CameraIntrinsics` (live) | 850 px default |
| `high_priority_distance_m` | 3.0 | 3.0 |
| `enable_lens_check` | false (default) | configurable |
| Target classes | includes `building` | no `building` |

**Planned:** Single exported config manifest consumed by both stacks.

### 5.5 Repository map (as-built)

#### iOS app — `App/`

| File | Purpose |
|------|---------|
| `VisionBridgeAppEntry.swift` | `@main` |
| `AppViewModel.swift` | Vision + camera + hearing orchestration |
| `HearingEngine.swift` | TTS scheduler |
| `ContentView.swift` | Dashboard, mute, auto-scan |
| `RadarView.swift` | 100° field visualization |
| `SettingsView.swift` | Feature flags |
| `OnboardingView.swift` | First-run flow |
| `HapticManager.swift` | Proximity haptics |
| `DetectionConfig.swift` | Hazard class set |
| `VisionBridgeFeatureFlags.swift` | UserDefaults feature gates |

#### Swift package — `ios/VisionBridgeKit/`

| Module | Purpose |
|--------|---------|
| `OnDeviceVisionEngine.swift` | CoreML loop, rate cap, LiDAR hooks |
| `CoreMLDetector.swift` | Vision request + OIV7 mapping |
| `ObjectTracker.swift` | IDs, velocity, priority |
| `VisionGeometry.swift` | Pan, distance, clamps |
| `CameraPipeline.swift` | AVFoundation capture |
| `CameraIntrinsics.swift` | Focal length from device |
| `VisionBridgeSession.swift` | `@Published lastPayload` |
| `SpeechSupport.swift` | `PhraseBuilder`, `DistanceConfidenceAssessor` |
| `LiDARCaptureSession.swift` | **Unwired** ARKit path |
| `ContractModels.swift` | Codable contract types |

#### Python — `src/visual_engine/`

See PRD v1 §4.2 table; entrypoint: `python -m visual_engine.main --port 8765`.

#### Tooling

| Path | Purpose |
|------|---------|
| `scripts/export_coreml.py` | YOLO → CoreML |
| `eval/run_eval.py` | Offline vision metrics |
| `tests/` | Pytest contract + vision |
| `docs/manual_test_scenarios.md` | Manual QA |
| `docs/FINISH_PROJECT_MEGA_CHECKLIST.md` | Remaining work |

---

## 6. Roadmap (planned & deprecated)

### 6.1 Planned — next releases

| Item | Benefit |
|------|---------|
| Wire `LiDARCaptureSession` in `AppViewModel` | High-confidence distance on Pro devices |
| Guided focal calibration wizard | Per-device distance accuracy |
| Enable lens check by default | Smudge awareness |
| Directional approach velocity | True fast-hazard priority |
| Accelerometer frame gating | Battery savings at idle walk |
| Critical-only + eval-driven cooldown tuning | Field-validated speech rate |
| Custom hazard fine-tune (YOLOv8m) | Street-specific recall |
| Config manifest sync (Swift ↔ Python) | Parity |

### 6.2 Deprecated — do not promise in pitch

| Item | Replacement |
|------|-------------|
| 3D auditory twin (continuous tones) | TTS guidance |
| `AVAudioEnvironmentNode` HRTF graph | Directional TTS phrases |
| AirPods Pro mandatory | Headphones recommended |
| Zero-touch / no UI | Dashboard + settings |
| WebSocket lab bridge | HTTP polling |
| YOLO-World open-vocabulary | YOLOv8m OIV7 (rolled back; see finish checklist §11) |
| `VisionBridgeRuntime/` path in old docs | `App/` + `VisionBridgeKit` |
| Mac+Wi-Fi as production inference | On-device CoreML only |

### 6.3 Future vision (post-beta)

Hybrid hearing mode: TTS for labels + optional spatial bed for proximity (feature-flagged). Requires separate validation suite on AirPods Pro.

---

## 7. Acceptance criteria & QA linkage

Every shipped behavior must map to a row in `docs/manual_test_scenarios.md` or an eval metric.

### 7.1 Release gate (`docs/release_checklist.md`)

- [ ] App builds clean; model bundled
- [ ] TTS-only verified; no spatial audio graph in app target
- [ ] Distance phrasing uses `PhraseBuilder` tiers only
- [ ] Critical-only: ≤2 utterances / 5 s in dense scene
- [ ] Telemetry export works
- [ ] No-detection cadence ≥ 10 s
- [ ] Camera denied / model missing: one-shot only
- [ ] Two-finger double-tap mute + resume
- [ ] README + PRD + onboarding aligned (this document)

### 7.2 PRD ↔ code sync checklist (per release)

- [ ] §3.2 class table matches `VisionConfiguration` + `VisualConfig`
- [ ] §4 scheduler constants match `HearingEngine` (grep cooldowns)
- [ ] §5 JSON matches `ContractModels.swift` + `contract.example.json`
- [ ] Shipped vs unwired labels still accurate
- [ ] Pitch script uses "estimated distance" and "TTS guidance"

---

## 8. Pitch (updated for v2)

### 30-second elevator (memorize)

> *"Millions of Americans navigate a world that has gone silent — electric cars, bikes, and curbs don't announce themselves.*
>
> *VisionBridge turns an iPhone into a second pair of eyes that **speaks** what it sees: people, vehicles, obstacles — with direction and estimated distance — running **100% on-device**, no internet required.*
>
> *It won't replace a cane or a guide dog. It adds a layer of awareness when vision alone isn't enough — with haptics, priority speech, and honest uncertainty. Built for Independence Hackathon. This is the bridge between sight and sound."*

---

## Appendix A — Version history

| Version | Summary |
|---------|---------|
| **1.0** | Competition draft: spatial audio, branch tasks, 24 h timeline |
| **1.1** | iPhone target, Flask bridge, CoreML path |
| **1.2.x** | Lens contract, pytest, VisionBridgeKit map, as-built §4.2 |
| **2.0.0** | **This document:** shipped TTS UX, confidence tiers, class policy, honest latency, LiDAR unwired, roadmap quarantine |

---

## Appendix B — Historical branch tasks (deprecated)

The original 24-hour hackathon split (`Visual` / `Audio` / `UI/UX` branches) is preserved in git history only. All integration lives on `main`. Refer to §5.5 and `docs/VISION_BRANCH_LOG.md` for current entrypoints.

---

*Built for Independence Hackathon · BRIDGE Theme*
