import VisionBridgeKit
import Combine
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import AVFoundation
#endif

/// Owns the three runtime wires: on-device **vision** (optional), **camera**, **hearing**.
@MainActor
final class AppViewModel: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var modelAvailable: Bool = false

    /// YOLOv8m Open Images V7 (601 classes); CoreML from `scripts/export_coreml.py` → `yolov8m-oiv7.mlpackage`.
    private static func makeVisionEngine() -> OnDeviceVisionEngine? {
        guard let detector = try? CoreMLDetector(modelResourceName: "yolov8m-oiv7", bundle: .main) else { return nil }
        return OnDeviceVisionEngine(detector: detector)
    }

    let hearing: HearingEngine
    private(set) var session: VisionBridgeSession?
    private var camera: CameraPipeline?
    private var sessionSink: AnyCancellable?
    private var hearingSink: AnyCancellable?

    init() {
        hearing = HearingEngine()
        hearingSink = hearing.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if let eng = AppViewModel.makeVisionEngine() {
            let s = VisionBridgeSession(engine: eng)
            session = s
            modelAvailable = true
            sessionSink = s.$lastPayload
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
            applyVisionSpeechPolicy()
            hearing.start(vision: s)
        } else {
            modelAvailable = false
            session = nil
            applyVisionSpeechPolicy()
            hearing.start(vision: nil)
            hearing.announceSystemMessageOnce(
                key: "model-missing",
                message: "Vision model unavailable. Please reinstall the app."
            )
        }
    }

    private func applyVisionSpeechPolicy() {
        hearing.setVisionSpeechEnabled(!modelAvailable || isScanning)
    }

    func setScanning(_ on: Bool) {
        isScanning = on
        applyVisionSpeechPolicy()
        guard on else {
            camera?.stop()
            camera = nil
            session?.clearPayload()
            hearing.speakImmediate("Bridge stopped")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        hearing.speakImmediate("Bridge active")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #if os(iOS)
        guard let s = session else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            hearing.announceSystemMessageOnce(
                key: "camera-denied",
                message: "Camera access required. Please enable in Settings."
            )
            return
        }
        if camera == nil { camera = CameraPipeline(vision: s) }
        Task {
            try? await camera?.start()
        }
        #endif
    }

    #if os(iOS)
    /// Live camera preview; only non-`nil` while scanning with an on-device model (same graph as `VisionBridgeSession`).
    var captureSessionForPreview: AVCaptureSession? { camera?.captureSession }
    #endif
}

