# VisionBridge ◉

<div align="center">

```
  ╔═══════════════════════════════════════════════════════════╗
  ║                                                           ║
  ║              ◉  VisionBridge   E N G I N E            ║
  ║                                                           ║
  ║      Hearing Through Sight  |  On-Device First           ║
  ║                                                           ║
  ╚═══════════════════════════════════════════════════════════╝
```

**Independence Hackathon · BRIDGE Theme**

[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20SwiftUI-0D1117?style=for-the-badge&labelColor=161B22)](https://github.com/epicgamer239/VisionBridge)
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![CoreML](https://img.shields.io/badge/CoreML-ANE--Optimized-2563EB?style=for-the-badge)](https://developer.apple.com/documentation/coreml)

</div>

---

## What it is

**VisionBridge** is an on-device iOS accessibility engine that uses the iPhone camera and CoreML object detection to identify nearby obstacles and hazards, then speaks concise, directional guidance through **text-to-speech (TTS)**.

It "bridges" visual perception into a real-time **spoken awareness stream** — class, direction, and **estimated distance** — with priority gating, haptics, and a live radar HUD.

> **Assistive, not a replacement** for a white cane, guide dog, or orientation & mobility training. All distances are estimates. See [PRD.md](PRD.md) for the full specification.

---

## Key features (shipped)

### ◉ TTS guidance engine
- **Directional speech:** "Person to the left, about 2 meters away" via `PhraseBuilder`
- **Distance confidence tiers:** Numeric speech only when confidence is high or medium; vague phrasing when low
- **Priority gating:** Hazards (people, vehicles) speak first; clutter suppressed in low-noise mode
- **Ducking:** Lowers background audio (music/podcasts) when guidance plays

### ◉ 100° perception radar
- Glassmorphic UI showing the field ahead
- Non-linear distance scaling (nearby objects emphasized)
- Live sonar sweep while scanning

### ◉ Physical UI
- Proximity haptics via the Taptic Engine
- VoiceOver labels, Dynamic Type, large touch targets
- Auto-start scan when the model is ready

### ◉ Judge debug surfaces
- In-app payload HUD and latency (`vision_duration_ms`)
- Browser dashboard (`ui/`) polling the Flask bridge
- Optional telemetry export from Settings

---

## Engineering

### Vision loop
- **Model:** YOLOv8m on **Open Images V7** (601 classes; mobility-focused subset at runtime)
- **Runtime:** CoreML + Vision on the Apple Neural Engine (~15 Hz emit cap)
- **Tracking:** Persistent object IDs, velocity estimate, deduplicated speech

### Distance
- **Monocular:** Pinhole model with live `CameraIntrinsics` from the device camera
- **LiDAR (Pro):** Depth sampling implemented in `VisionBridgeKit`; wiring in the main app is planned

### Dev bridge (not the production path)
- Python Flask on port `8765` — `GET /frame`, `POST /infer`, `GET /judge`
- Same `FramePayload` JSON contract as iOS

---

## Technical stack

- **Core:** Swift 6.0, SwiftUI, Combine
- **AI/ML:** CoreML, Vision, YOLOv8m
- **Audio:** AVFoundation (`AVSpeechSynthesizer`, session ducking)
- **Haptics:** UIImpactFeedbackGenerator
- **Package:** `ios/VisionBridgeKit`

---

## Project structure

| Path | Purpose |
|------|---------|
| `App/` | iOS app UI, `HearingEngine`, assets |
| `ios/VisionBridgeKit/` | Camera, CoreML detector, tracker, contract types |
| `VisionBridge/` | Xcode project |
| `src/visual_engine/` | Python Flask bridge |
| `docs/` | PRD, contract, checklists |
| `scripts/` | CoreML export |
| `tests/` | Python tests |
| `ui/` | Judge web dashboard |

---

## Getting started

1. Open `VisionBridge/VisionBridge.xcodeproj` in **Xcode 15+**.
2. Ensure `App/yolov8m-oiv7.mlpackage` is in the app target (export via `scripts/export_coreml.py` if missing).
3. Build and run on a physical iPhone (12 or newer recommended).
4. (Optional) Python bridge: `pip install -r requirements.txt` then `PYTHONPATH=src python -m visual_engine.main --port 8765`

---

## Documentation

- **[PRD.md](PRD.md)** — Product requirements v2.0 (as-built)
- **[docs/contract.example.json](docs/contract.example.json)** — JSON payload schema
- **[docs/manual_test_scenarios.md](docs/manual_test_scenarios.md)** — QA scenarios

---

<div align="center">
  Built with ❤️ for IndyHax Hacks 2026.
</div>
