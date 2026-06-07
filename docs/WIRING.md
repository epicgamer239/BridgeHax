# End-to-end wiring (Visual)

Use this as a **checklist** to connect camera → vision → consumers. Deeper API notes live in [visual-integration.md](visual-integration.md) and the PRD.

## 1. Repository and Python service

- Branch: **`Visual`** (pull before integrating).
- Create a venv, install from `requirements.txt`, then from repo root with `pythonpath` pointing at `src`:

  ```bash
  PYTHONPATH=src python -m visual_engine.main --host 0.0.0.0 --port 8765
  ```

- iPhone or another client is the only camera (no Mac webcam): add **`--no-local-camera`** and drive **`POST /infer`** from the app (see [visual-integration.md](visual-integration.md)).
- **Landing / judge view:** `GET /` — **`GET /judge`** (projector-friendly live bboxes + stats + optional browser TTS). **Health check:** `GET /health` (adds **`hints`**, **`uptime_s`**, **`narration_lines`**) — **Frame mirror:** `GET /frame` and **`GET /payload`** (alias; use either name) — same JSON as a successful infer.

## 2. iOS: on-device path (VisionBridgeKit)

1. Add **VisionBridgeKit** (local Swift package) to your Xcode app target.
2. Bundle a **CoreML** model; construct **`CoreMLDetector` → `OnDeviceVisionEngine` → `VisionBridgeSession`**.
3. Wire the camera: create **`CameraPipeline(vision: session)`** and call **`await pipeline.start()`** after your UI is ready. Stop with **`pipeline.stop()`** on teardown.
4. **Info.plist:** `NSCameraUsageDescription` (user-facing string for why the camera is used).
5. Optional: observe **`VisionBridgeSession`’s `lastPayload`** for UI; use **`FramePayload.jsonString()`** for debug overlays or file logging.

`CameraPipeline` uses preset **VGA 640×480**, BGRA buffers, and the **back** wide camera. Set **`imageOrientation:`** in the initializer if the physical mount (e.g. lanyard) does not match the default **`.right`** (portrait rear camera with Vision).

## 3. iOS: dev bridge to the Mac (no CoreML in loop)

- Same **`FramePayload`** JSON (decode server responses the same as on-device `Codable`).
- Send JPEGs to **`POST /infer`**, or poll **`GET /frame`**. CORS and ATS exceptions for local HTTP are documented in [visual-integration.md](visual-integration.md).

## 4. Hearing (spatial audio)

- **Swift on-device:** subscribe to **`VisionBridgeSession.$lastPayload`**. Types in **`ios/VisionBridgeKit/.../ContractModels.swift`**: **`FramePayload`**, arrays of **`DetectedObjectDTO`** on **`objects`**. Per detection in Swift: **`objectId`**, **`objectClass`**, **`panValue`**, **`distanceM`**, **`velocityMps`**, **`priority`**, **`confidence`**, **`bbox`**. Server / Python JSON uses the same contract with **snake_case** keys; see **`docs/contract.example.json`**.
- **Lens:** `FramePayload.camera` (**`CameraHealthDTO`**). iOS TTS for smudge lines is built into **`VisionBridgeSession`**; your spatial engine can ignore **`camera`** or add haptics.
- **Python or another process:** decode **`GET /frame`** / **`POST /infer`** the same way.
- Keep **`objectId`** (JSON: **`object_id`**) **stable** across frames for **continuous** cues.

## 5. Quality gates before shipping a build

- **Python (fast):** `pytest -m "not slow"` from repo root.
- **Python (smoke, optional YOLO):** `python -m visual_engine.testing_engine` and/or `python -m visual_engine.simulation` (see README § simulation).
- **iOS:** run on device; confirm **`lastPayload` updates** and lens announcements behave when the camera is smeared or sharp.

## 6. Who owns what

| Layer | Owns |
|--------|------|
| **Visual (this repo)** | YOLO / CoreML → **`FramePayload`**, Flask bridge, simulation |
| **iOS app** | Session lifecycle, camera permissions, `CameraPipeline`, routing JSON to UI/Audio |
| **Hearing** | Map **`panValue` / `distanceM` / `objectId`** (and the rest) from **`objects`**, or the same fields from **JSON** |
