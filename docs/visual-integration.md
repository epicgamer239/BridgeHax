# VisionBridge Visual Engine Integration Guide

This module is fully standalone. Use it to align **iOS (UI/UX + Audio)**, **Python (this repo, `main`)**, and the shared JSON contract from `PRD.md`.

## Layout for the team

| Role | What to build against |
|------|------------------------|
| **Visual (this service)** | YOLOv8 → same JSON for every path below |
| **UI/UX (Swift)** | `URLSession` to `http://<host>:8765` (see iOS below); Judge dashboard can use `GET /frame` or mirror `POST /infer` results |
| **Audio (Swift)** | Parse `objects[]`, map `class` + `pan_value` + `distance_m` + `object_id` to spatial audio |
| **Dev laptop** | Optional Mac/PC **webcam** with `GET /frame`; or iPhone as camera with `POST /infer` to the same server |

## Service contract

- **Judge / demo (browser):** `http://<host>:8765/judge` — live view of the same `FramePayload` the phone produces; `GET /health` adds **`hints`** and **`narration_lines`**. Good for a projector during judging.
- **Port (PRD default):** `8765`
- **Latest snapshot:** `GET /frame` (same body as a successful `POST /infer`)
- **iOS / one-shot from an image:** `POST /infer` (JPEG) — **updates** the latest payload so `GET /frame` stays in sync
- **Target rate:** ~`15 Hz` (local camera loop; iOS should send frames at a similar rate when using `/infer`)
- **CORS:** enabled (`Access-Control-Allow-Origin: *`) so a browser dashboard on UI/UX can call the API

### `POST /infer` (iOS → Mac during integration)

- **URL:** `http://<mac-lan-ip>:8765/infer` (iPhone and Mac on the same Wi-Fi)
- **Body (choose one):**
  1. Raw **JPEG** bytes, `Content-Type: image/jpeg`
  2. `multipart/form-data` with a file field named **`image`**
- **Response:** same JSON object as in “JSON payload” (plus HTTP 200)

Run the server so it does **not** open the laptop camera (iPhone is the only camera):

```bash
PYTHONPATH=src python -m visual_engine.main --host 0.0.0.0 --port 8765 --no-local-camera
```

`0.0.0.0` makes the service reachable on your LAN. Your UI/UX partner should set **App Transport Security** to allow that **HTTP** local URL (e.g. `NSAppTransportSecurity` / `NSExceptionDomains` in `Info.plist`, or `NSAllowsLocalNetworking` for local-only).

### iOS (Swift) sketch — send one JPEG

Use `AVCapture` to produce JPEG `Data`, then:

```swift
var request = URLRequest(url: baseURL.appendingPathComponent("infer"))
request.httpMethod = "POST"
request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
request.httpBody = jpegData
// URLSession.dataTask: decode JSON to match docs/contract.example.json
```

Your Audio module can use the **response** directly or poll `GET /frame` (same contract).

- **Endpoints:** `GET /health`, `GET /frame`, `POST /infer`, `OPTIONS` (CORS preflight)
- **Local webcam mode:** `GET /frame` updates at `15 Hz` target (with gate fallback in code)
- **iOS + `--no-local-camera`:** you drive the rate with `POST /infer`; `GET /frame` still returns the last result for any client that wants to poll

### JSON payload

When lens checks are enabled (default in Python; configurable in iOS), responses include a **`camera`** object:

- `lens_status` — `ok` or `warning` (smeared / low sharpness for several frames)
- `lens_laplacian_var` — Laplacian variance of a downscaled grayscale view (higher = sharper)
- `lens_announce` — short user-facing string for TTS/announce when `warning`, else `null`

On iOS, **`VisionBridgeSession`** uses `AVSpeechSynthesizer` to read `lens_announce` (with a cooldown). Your UI/UX can also show a haptic or banner if you prefer.

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
      "pan_value": -0.36,
      "velocity_mps": 2.1,
      "priority": "HIGH"
    }
  ]
}
```

## Required Class Filter

The engine emits only:

- `person`
- `car`
- `bicycle`
- `motorcycle`
- `truck`
- `bus`

## Priority Rule

- `HIGH` when `distance_m < 3.0`
- `NORMAL` otherwise

## Health endpoint

`GET /health` includes:

- `running`
- `inference_source` — `local_camera` vs `ios_or_remote`
- `local_camera` — whether OpenCV is capturing
- `frame_id`, `latest_object_count`, `effective_emit_hz`, `avg_detection_ms`

## Audio + UI/UX

- **Audio:** use `object_id` as a stable key for audio nodes; update position each `frame_id` / `timestamp_ms`.
- **UI/UX dashboard:** `GET /frame` for a live JSON panel; CORS is on for a web view if needed.
- **Latency line (judge view):** compare `timestamp_ms` from this payload to receive time; `vision_duration_ms` is the detector-only slice.

A minimal example file lives at `docs/contract.example.json` (copy types from there into Swift `Codable` if you like).

