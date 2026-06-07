# Vision pipeline — engineering log

This file is **append-only** (add new entries at the **top**). It records **vision** work in this repository: on-device / reference **vision pipeline**, **JSON contract**, **Python bridge**, **tests**, and **PRD/docs** that describe vision. (The filename **`VISION_BRANCH_LOG`** is historical; all work targets **`main`**.) **Audio** and **UI/UX** may keep their own logs; anything that **changes the vision contract or `VisionBridgeKit` API** still belongs here.

**How to use (continual, not end-of-sprint only):** After **each** **Visual**-scoped change, append **before** you push or open the PR: a short bullet under **today’s** `## YYYY-MM-DD` (start a new day section at the top when the calendar day changes). **Same commit** as the code is ideal. One bullet can cover a focused diff; for large work, a few bullets is fine. **Humans and coding agents** both follow this so judges and partners always see a fresh trail.

| Cadence | Action |
|--------|--------|
| **Every** vision PR / push to **`main`** | At least one new log bullet |
| New calendar day | New `## YYYY-MM-DD` block **above** older days |
| Contract or `FramePayload` change | Log entry + **PRD** / `contract.example.json` (see **PRD** maintenance) |

---

## 2026-04-25

- **Vision model revamp:** **YOLOv8m Open Images V7** (`yolov8m-oiv7.pt`, CoreML **`yolov8m-oiv7.mlpackage`**) replaces **YOLOv8n** / COCO; **`OpenImagesV7Mapping`** (601 classes) replaces **`COCOMapping`**. Removed YOLOE hybrid (**`yoloe-26n-seg`**, **`OpenVocabularyCoreMLDetector`**, **`DetectionMerge`**). Python + iOS allowlists use OIV7 **lowercased** class strings; added **`scripts/gen_open_images_v7_mapping.py`**. **`export_coreml.py`** writes the bundle to **`App/`** only.

- **Vision revert + frame gate (later same day):** back to **YOLOv8n** / COCO; removed YOLO-World path and `yolo_world_s`. **Python** `bbox_in_frame` + **iOS** `VisionGeometry.prdBboxVisibleAreaFraction` require most of the bbox area inside the image. **`App/yolo_world_s.mlpackage` removed;** re-exported **`yolov8n.mlpackage`**.

- **Vision model (Python + iOS):** default weights **`yolov8s-worldv2.pt`** (YOLO-World) instead of **`yolov8n.pt`**; CoreML export script outputs **`yolo_world_s.mlpackage`**. iOS loads **`yolo_world_s`** from the bundle, with fallback to legacy **`yolov8n`**.

- **YOLO-World `set_classes` (blind / mobility threat list):** Python `yolo_world_classes.py` and CoreML export share **`THREAT_YOLO_WORLD_CLASSES`** (e.g. **dog, trash can, traffic cone, electric scooter, road users**). iOS `VisionConfiguration.threatYoloIndexOrder` + `YoloClassIndexSemantics`; **legacy** `yolov8n` uses **`.coco80`** in `AppViewModel` so numeric ids still map to COCO names. **Re-export** `yolo_world_s.mlpackage` after this change; old bundle without `set_classes` at export will not match the new id order.

- **Threat prompt / canonical + CoreML in repo:** long CLIP disambiguation for **trash can** (vs hand bottle), stricter `min conf` and **min bbox height** for that class; Python and iOS aligned. `python3 scripts/export_coreml.py` (with `certifi` for SSL) produced **`App/yolo_world_s.mlpackage`**.

- **Hearing (iOS `App/HearingEngine`):** removed tone **beeps** / spatial audio tones; **spoken class names** (throttled) when **Say each object’s name** is on, optional **distance** when **Add distance in speech** is on; when the first is off, only **high-priority** lines if distance speech is on.

- **iOS live preview:** `VisionBridgeKit` **`CameraPipeline.captureSession`** + **`App/CameraFeedPreview.swift`** (`AVCaptureVideoPreviewLayer`); **`ContentView`** shows **“Live camera”** while **Start camera** (same session as YOLO ingest).

- **Settings & `VisionBridgeKit`:** SwiftUI **Settings** toggles (`UserDefaults` keys `bridgehax.feature.*`) for **3D bubble**, **hearing tones**, **distance TTS**, **haptics**, **Payload HUD**, **lens smudge TTS**; **`HearingEngine`** / **`HapticManager`** / **`LensWarningAnnouncer`** / **`PayloadHUD`** respect them. **`applyFeatureTogglesFromUserDefaults()`** on tone or spatial toggle (no global defaults observer, so the bridge URL field does not thrash audio).

---

## 2026-04-30

- **Hearing (iOS `App/HearingEngine`):** **`AVAudioEnvironmentNode`** 3D “**audio bubble**” (HRTF on headphone / AirPods / BT stereo; **equal-power** on speaker) + **`AVAudioSession`** route observer + **`isSpatialHeadphoneRouteActive`**. Tones get **`AVAudio3DPoint`** on a virtual ring; TTS unchanged. **ContentView** chips “3D BUBBLE” / “SPEAKER 2D” + accessibility.

---

## 2026-04-29

- **Final wiring (iOS + Python + hearing):** **`VisionBridgeRuntime/`** — **`AppViewModel`**, **`HearingEngine`** ( **`VisionBridgeKit.FramePayload`**, on-device **`$lastPayload`** or **`GET /frame`** bridge), **`VisionBridgeAppEntry`** (`@main`). **`ContentView`** + Settings bridge URL. **`GET /payload`** = **`/frame`** in **`app.py`**. **`ios/XCODE_SETUP.md`**, **`Info.plist.example`**, **`AudioEngine/README.md`** updated; legacy **`AudioEngineApp`** no longer `@main`.

---

## 2026-04-28

- **Main integration:** Merged **`origin/Visual`**, **`origin/UI/UX`**, **`origin/Audio`** into **`main`**. **`PRD.md`** “Winning Code Stack” conflict resolved: **iOS + CoreML** production path, **Flask** in-repo reference + **`/judge`**, optional external FastAPI/GCP/Firebase later. (UI/UX files under `ios/` and `ui/`; Hearing under **`AudioEngine/`** — coordinate paths with `ios/VisionBridgeKit` as needed.)
- **Single default branch:** Removed long-lived remotes **`Visual`**, **`UI/UX`**, **`Audio`**; **`main`** is the only remote branch. Added **`CONTRIBUTING.md`** (trunk-based workflow). Renamed this log’s title to **Vision pipeline** (filename unchanged for links).

---

## 2026-04-27

- **Process — continual logging:** Strengthened instructions in this file, **PRD** maintenance, and **README** so the log is **appended to on every** **Visual**-scoped change, not only at release. Replaces ad-hoc “ship day” only updates.

---

## 2026-04-26

- **Synthesis** (`synthesis.py`): random sharp BGR, Gaussian blur, flat **uniform** field, **`lens_streak_sequence()`** (tagged sharp/blur) for reproducible smudge demos without hardware.
- **Simulation engine** (`simulation.py`): **`SimulationEngine`**, **`SimulationReport`**; **`lens_streak`** / **`lens_sharp`** (no YOLO import) and **`vision_random`** (lazy `VisionEngine` + full contract); CLI **`python -m visual_engine.simulation`** with `--print` / `--payloads-only`. Lens-only path works in CI without `ultralytics`.
- **Tests:** `test_synthesis.py`, `test_simulation.py`; **`smoke_simulation`** in **`testing_engine.run_built_in_smoke`**. Pytest marker **`slow`** for optional YOLO sim.
- **Docs:** README §8 simulation; **PRD** §4.2 table rows for `synthesis` / `simulation`.

---

## 2026-04-25

- **Scaffolded Python vision service** (`src/visual_engine/`): Ultralytics **YOLOv8n** (`yolov8n.pt`), COCO class subset, confidence **≥ 0.55**, monocular distance + pan, simple **object_id** tracking and **velocity_mps** / **priority**, **~15 Hz** emit with **10 Hz** fallback when average detection time exceeds the gate.
- **Flask bridge** (`app.py`, `main.py`): **`GET /health`**, **`GET /frame`**, **`POST /infer`** (JPEG body or multipart `image`), CORS; **`--no-local-camera`** for iPhone-only capture to Mac; default port **8765**.
- **Contract** (`contracts.py`): `make_frame_payload` aligned with PRD; optional **`camera`** block when lens checks are on.
- **Lens / smudge heuristic** (`lens_quality.py`): Laplacian variance on downscaled gray frame; consecutive low readings → **`lens_status: warning`** and **`lens_announce`** text; tunable via **`VisualConfig`**.
- **Calibration CLI** (`calibration.py`): compute **`focal_length_px`** from real-world measurements.
- **Testing engine** (`testing_engine.py`): `validate_frame_payload`, in-process **`run_built_in_smoke`**; CLI **`python -m visual_engine.testing_engine`** with `PYTHONPATH=src`.
- **Pytest** (`tests/`, `pytest.ini`): contract, lens, testing-engine tests; **`requirements.txt`** includes **pytest** / **opencv-python** as needed.
- **On-device parity (iOS Swift package)** `ios/VisionBridgeKit/`: CoreML + Vision, same **`FramePayload`** / **`camera`** shape, **`VisionBridgeSession`**, lens analysis + **iOS TTS** announcer for warnings; **`scripts/export_coreml.py`** for **yolov8n** → CoreML with NMS.
- **Documentation**: `docs/visual-integration.md`, `docs/contract.example.json`, root **`README.md`**, **`ios/README.md`**, **`PRD.md`** (§4, §4.1, §4.2) updated to match the above.
- **Vision-only log (this file):** created **`docs/VISION_BRANCH_LOG.md`** as the append-only **Visual branch** engineering log; **`PRD.md`** (maintenance note + §4.1 **Docs in repo** row) and **`README.md`** (integration handoff) now reference it.
- **E2E wiring (follow-up):** iOS **`CameraPipeline`** — **`AVCaptureSession`** (VGA, BGRA, back wide) → **`VisionBridgeSession.ingest`**; **`FramePayload+JSON.swift`** for debug/logging; **`docs/WIRING.md`** checklist; macOS compiles a stub that throws from **`start()`**.
- **Hackathon / judge demo (later on same day):** **`GET /judge`** + **`judge.html`** (live canvas, `/health` + `/frame` poll, **Web Speech TTS**); `GET /` landing; **`/health`**: **`uptime_s`**, **`visual_version`**, **`hints`** + **`narration_lines`** via **`demo_hints`**. **iOS** **`PayloadHUD`** (stats + **haptic** on **HIGH**).

---

## Template (copy when adding a new day)

```markdown
## YYYY-MM-DD

- …
```
