# VisionBridge on iOS (Swift / SwiftUI)

**Full app (Xcode):** see **`XCODE_SETUP.md`** — one app target, **`VisionBridgeKit`** package, and **`VisionBridgeRuntime/`** (`AppViewModel`, **`HearingEngine`**, single **`@main`**) wiring vision + camera + spatial audio. **`Info.plist.example`** covers camera and local HTTP.

The **`VisionBridgeKit`** Swift package runs **YOLOv8m (Open Images V7)** on-device via **CoreML + Vision** and produces the **same JSON-shaped `FramePayload`** as the Python server (`docs/contract.example.json`). Numeric labels map through **`OpenImagesV7Mapping`** (601 classes); **`VisionConfiguration.targetClassNames`** filters to the shipped mobility / scene subset.

## Team handoff (Visual is wired; you plug the app + audio)

| Who | You touch | What’s already in `VisionBridgeKit` |
|-----|-----------|---------------------------------|
| **UI / UX** | Xcode app target, `Info.plist`, black UI / lanyard layout from PRD | `CoreMLDetector` → `OnDeviceVisionEngine` → `VisionBridgeSession`; **`CameraPipeline`** → `ingest` (or roll your own `AVCapture` → `ingest`). Optional: **`PayloadHUD`** overlay (object count, vision ms, lens warning) + light **haptic** on high-priority objects (iOS). |
| **Hearing / Audio** | Spatialization and routing in your module | **Subscribe to** `VisionBridgeSession` **`$lastPayload`**. For each `FramePayload`, use **`objects`** as `[DetectedObjectDTO]` (`ContractModels.swift`). Primary cue fields: **`objectId`**, **`objectClass`**, **`panValue`**, **`distanceM`**, **`velocityMps`**, **`priority`**, **`confidence`**. JSON keys when decoding from the server match `docs/contract.example.json` (snake_case). |

`docs/WIRING.md` is the one-page E2E checklist. Python bridge: root **`README.md`** and **`docs/visual-integration.md`**.

## 1) Add the package in Xcode

1. **File → Add Package Dependencies… → Add Local…** and select `ios/VisionBridgeKit`.
2. Add **`VisionBridgeKit`** to your app target.

## 2) Export CoreML (`yolov8m-oiv7.mlpackage`)

On a machine with Python + Ultralytics (from repo root):

```bash
pip install ultralytics
python3 scripts/export_coreml.py
```

The script writes **`App/yolov8m-oiv7.mlpackage`** (the Xcode project syncs the **`App/`** tree into the app target). Example:

```swift
let detector = try CoreMLDetector(modelResourceName: "yolov8m-oiv7", bundle: .main)
let engine = OnDeviceVisionEngine(detector: detector)
let session = VisionBridgeSession(engine: engine)
```

Use the **Vision + NMS** export so `VNRecognizedObjectObservation` is produced. If you see zero detections, re-export with `nms=True` (the script does) and confirm the model is in the app bundle.

## 3) Camera → `VisionBridgeSession` (use **`CameraPipeline`**)

**`CameraPipeline.swift`** already wires **back camera, VGA, BGRA** → **`VisionBridgeSession.ingest`**. The app only needs to hold one instance, `await start()`, and `stop()` on teardown. Add **`NSCameraUsageDescription`** in the app `Info.plist`.

```swift
// After you have: VisionBridgeSession (see §2)
@State private var camera: CameraPipeline?

// Example lifecycle (e.g. .task + onDisappear):
if camera == nil { camera = CameraPipeline(vision: vision) } // `vision` is your VisionBridgeSession
try? await camera?.start()
// …
camera?.stop()
```

Override **`init(vision:imageOrientation:)`** if the lanyard mount is not the default **`.right`** (wrong orientation breaks **`panValue`** and distance).

### Manual `AVCaptureSession` (only if you need a custom graph)

- **Session preset:** **`vga640x480`** or **`hd1280x720`**. **Frame rate:** cap to **15–30 fps** with `activeVideoMinFrameDuration` / `Max`.
- **Queue:** `AVCaptureVideoDataOutput` delegate on a **serial** `DispatchQueue` (not the main thread). In `captureOutput`, `CVPixelBuffer` → **`vision.ingest(pixelBuffer:orientation:)`** with the correct **`CGImagePropertyOrientation`**.

## 4) SwiftUI

Hearing can **`Combine` sink** on **`vision.objectWillChange`** or the session’s published **`$lastPayload`**. For a quick UI probe, use **`vision.lastPayload`**. For logs or a debug HUD, **`try payload.jsonString(prettyPrinted: true)`** (`FramePayload+JSON.swift`).

**Hackathon / demo:** drop **`PayloadHUD(session: vision)`** in a corner of your lanyard screen so judges see live latency and count; on **iOS** a subtle **haptic** fires when at least one object is **HIGH** priority.

```swift
struct LanyardRoot: View {
    @StateObject private var vision: VisionBridgeSession = {
        let d = try! CoreMLDetector(modelResourceName: "yolov8m-oiv7", bundle: .main)
        return VisionBridgeSession(engine: OnDeviceVisionEngine(detector: d))
    }()

    var body: some View {
        Text(vision.lastPayload.map { "\($0.objects.count) objects" } ?? "…")
    }
}
```

Your UI partner owns the real **black / status-dot** layout from the PRD; this is only wiring.

## 5) Performance knobs (already in code + config)

| Knob | Location / behavior |
|------|----------------------|
| **15 Hz cap** | `VisionConfiguration.default.minEmitInterval` (1/15 s) drops extra frames before inference. |
| **Backpressure** | If a request is still running, new frames are dropped (`nil` completion). |
| **Background Vision** | `VNImageRequestHandler` uses `preferBackgroundProcessing`. |
| **Serial work queue** | One inference at a time on a high-priority queue. |
| **Class filter + conf** | Allowlist in `VisionConfiguration.targetClassNames`; `confidence >= 0.58` default. |
| **Calibration** | Adjust `focalLengthPixels` for the iPhone camera after a real-world tape measure + single reference object. |

## 6) Python bridge vs on-device

- **Shipping path (sponsor / latency story):** CoreML on the **phone** — no Mac, no Wi‑Fi required.
- **Python `POST /infer`:** optional for lab integration; see root `README.md`.

## 7) Lens / smudge detection (accessibility)

- **Payload:** `FramePayload.camera` with `lens_status`, `lens_laplacian_var`, `lens_announce` (see `docs/contract.example.json`).
- **Heuristic:** low Laplacian variance (blur / haze) for several frames in a row → `warning` and a non-null `lens_announce` string.
- **Speech (iOS):** `VisionBridgeSession` creates a **`LensWarningAnnouncer`** by default. Pass `enableLensSpeech: false` to disable.
- **Tuning:** `VisionConfiguration` — `lensLaplacianThreshold` (~100 for 400px long side, adjust per device), `lensWarnConsecutive` (default 4).

## 8) Tests

**Python (authoritative in CI):** from repo root, `pytest -q` and `PYTHONPATH=src python3 -m visual_engine.testing_engine`.

**This package (Xcode):** add a **Unit Test** target to your app, link `VisionBridgeKit`, and use `XCTest` against `LensStreakState` / `LensQualityAnalyzer` if you want on-device matrix tests. Command-line `swift test` for iOS packages may need a full **Xcode** toolchain; building with `swift build` is the usual headless check.
