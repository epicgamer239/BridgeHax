import CoreVideo
import Foundation
import ImageIO

#if os(iOS)
import AVFoundation
import CoreMedia
#endif

/// Wire `AVCaptureSession` → `VisionBridgeSession.ingest` on iOS. On macOS the type exists for
/// `swift build` but `start()` throws — use a USB camera + Python bridge, or a host app.
public enum CameraPipelineError: Error, Sendable, Equatable {
    case cameraPermissionDenied
    case noSuitableVideoDevice
    case cannotAddInput
    case cannotAddOutput
    case inputCreationFailed
    case unavailableOnThisPlatform
}

#if os(iOS)
/// Pushes BGRA frames from the back camera to `OnDeviceVisionEngine` via `VisionBridgeSession`.
public final class CameraPipeline: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let vision: VisionBridgeSession
    private let imageOrientation: CGImagePropertyOrientation
    private let session: AVCaptureSession
    private let sessionQueue: DispatchQueue
    private let bufferQueue: DispatchQueue
    private var configured = false
    private var captureDevice: AVCaptureDevice?
    private var thermalStereoGuard: ThermalStereoGuard?

    @Published public private(set) var isRunning = false

    /// The same `AVCaptureSession` that drives vision. Attach an `AVCaptureVideoPreviewLayer` in the app to show a live viewfinder.
    public var captureSession: AVCaptureSession { session }

    /// - Parameters:
    ///   - vision: Session that owns the vision engine; receives frames on the main actor.
    ///   - imageOrientation: Vision orientation for the rear camera in portrait. Tune for lanyard / landscape use.
    public init(vision: VisionBridgeSession, imageOrientation: CGImagePropertyOrientation = .right) {
        self.vision = vision
        self.imageOrientation = imageOrientation
        self.session = AVCaptureSession()
        self.sessionQueue = DispatchQueue(label: "com.dualsight.capture.session", qos: .userInitiated)
        // Keep camera delivery off the main queue; slightly higher QoS for smoother start under load.
        self.bufferQueue = DispatchQueue(label: "com.dualsight.capture.buffer", qos: .userInteractive)
        super.init()
        let guardRef = ThermalStereoGuard()
        guardRef.onShouldDisableStereo = { [weak self] in
            self?.onThermalStereoShouldDisable?()
        }
        self.thermalStereoGuard = guardRef
    }

    /// Future: tear down multi-cam stereo when thermal state is serious. Monocular capture is unchanged.
    public var onThermalStereoShouldDisable: (() -> Void)?

    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }

    public func start() async throws {
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { c.resume(returning: $0) }
        }
        if !ok { throw CameraPipelineError.cameraPermissionDenied }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    if !self.configured {
                        try self.configureSession()
                        self.configured = true
                    }
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.isRunning = self?.session.isRunning ?? false
                    }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        sessionQueue.async { [self] in
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else {
            session.commitConfiguration()
            throw CameraPipelineError.noSuitableVideoDevice
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw CameraPipelineError.inputCreationFailed
        }
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            session.commitConfiguration()
            throw CameraPipelineError.cannotAddInput
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            session.commitConfiguration()
            throw CameraPipelineError.cannotAddOutput
        }

        output.setSampleBufferDelegate(self, queue: bufferQueue)
        self.captureDevice = device
        session.commitConfiguration()
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let device = captureDevice else { return }
        let o = imageOrientation
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let intrinsics = CameraIntrinsicsReader.read(
            device: device,
            frameWidth: w,
            frameHeight: h,
            sampleBuffer: sampleBuffer
        )
        vision.ingest(pixelBuffer: pixelBuffer, orientation: o, intrinsics: intrinsics)
    }
}

#else

/// Placeholder: macOS has no in-package camera loop; use the Python service or a host app.
public final class CameraPipeline: ObservableObject {
    @Published public private(set) var isRunning = false

    public init(vision: VisionBridgeSession, imageOrientation: CGImagePropertyOrientation = .right) {
        _ = (vision, imageOrientation)
    }

    public func start() async throws {
        throw CameraPipelineError.unavailableOnThisPlatform
    }

    public func stop() {
        isRunning = false
    }
}

#endif
