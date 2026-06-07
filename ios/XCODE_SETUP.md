# Building the VisionBridge iOS app (Xcode)

## 1. Open the committed project (recommended)

At the repo root:

- **VisionBridge/VisionBridge.xcodeproj** — iOS app target with **File System Synchronized** sources pointing at **`../App`** and a local **Swift Package** dependency on **`../ios/VisionBridgeKit`**.

In Xcode, open that project, pick an **iOS Simulator** (e.g. iPhone) as the run destination, then **Build** (⌘B). No manual “add all Swift files” step is required: everything under `App/` is in the app target.

If you do **not** use this project, create your own and link **`VisionBridgeKit`** (see below).

## 2. `VisionBridgeKit` (already wired in the committed project)

The committed target already resolves **`ios/VisionBridgeKit`**. If you add a new app target or project from scratch:

1. **File → Add Package Dependencies… → Add Local…**
2. Select `ios/VisionBridgeKit` (the folder containing `Package.swift`).
3. Add **VisionBridgeKit** to the app target.

## 3. App sources

With **`../App`** synchronized into the app target, all Swift files there are compiled, including e.g. **`VisionBridgeAppEntry.swift`**, **`HearingEngine.swift`**, **`SettingsView.swift`**, **`VisionBridgeFeatureFlags.swift`**, etc. Do **not** add `App` sources to the **`VisionBridgeKit`** product.

**If you use a new Xcode app template:** remove its template `ContentView` / `App` struct if you replace them with the repo’s `App/` files.

## 4. CoreML model

1. From repo root: `python3 scripts/export_coreml.py` (see `ios/README.md`).
2. Ensure **`yolov8m-oiv7.mlpackage`** is under **`App/`** (run `python3 scripts/export_coreml.py` from repo root). The Xcode project syncs `App/` into the **VisionBridge** target.

Without the model, the app still runs **hearing** by polling the Python **`GET /frame`** endpoint (Settings → Development).

## 5. Info.plist (app target)

Merge at least:

- **Privacy – Camera** (`NSCameraUsageDescription`): e.g. *“VisionBridge uses the camera to detect objects for spatial audio.”*
- **App Transport Security**: **Allow arbitrary loads in local networks** (or use **`NSAppTransportSecurity` → `NSAllowsLocalNetworking` = true**) so `http://<mac-ip>:8765` works on device.

A reference plist fragment is in **`App/Info.plist.example`** (copy keys into the target’s Info or use a build setting).

## 6. One `@main` only

- Keep **`VisionBridgeAppEntry`** as the only `@main`.
- Do not compile the old **`AudioEngine/AudioEngineApp/AudioEngineApp.swift`** in this target (or leave it out of the target); it is reference-only.

## 7. Run

- **On-device + CoreML:** start scanning; hearing uses `VisionBridgeSession` + `CameraPipeline`.
- **Lab + Python only:** `PYTHONPATH=src python -m visual_engine.main --host 0.0.0.0 --port 8765` on the Mac; on the phone set **Settings → Development → bridge URL** to `http://<mac-lan-ip>:8765`.

Server exposes **`/frame`**, **`/payload`** (alias), **`/health`**, **`/infer`**, **`/judge`**.
## 8. Visual Identity (App Icon & Splash)

To ensure the app feels like a premium product for the judges:

### App Icon
1. Open **Assets.xcassets** -> **AppIcon**.
2. Drag the **dualsight_app_icon** into the 1024px universal slot.
3. In the Attributes Inspector, set **Devices** to "Single Size" for quick setup.

### Launch Screen
1. Drag **dualsight_splash_logo** into **Assets.xcassets** and name it `LaunchLogo`.
2. In the app target **Info** tab, add a **Launch Screen** dictionary.
3. Inside it, add **Image Name** = `LaunchLogo` and **Background Color** = `Black`.
