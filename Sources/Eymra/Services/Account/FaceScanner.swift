import AVFoundation
import CoreImage
import Foundation
import Vision

/// Where the user's head is pointing, from the front camera.
nonisolated struct FacePose: Sendable, Equatable {
    /// Degrees; the sign depends on mirroring, so the scan only relies on left and right being opposite.
    var yaw: Float
    /// Degrees; positive is nodding down (Vision's convention). nil when Vision can't tell.
    var pitch: Float?
    /// Normalised, upper-left origin.
    var box: CGRect
}

/// Front-camera capture with face pose tracking for the face setup.
/// `@unchecked Sendable`: the capture session, Vision request and CIContext are only touched on `queue`
/// (session setup and the frame callback both run there); the callbacks hand plain values to the main actor.
nonisolated final class FaceScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.eymra.facescan")
    private let request: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        r.revision = VNDetectFaceRectanglesRequestRevision3   // revision 3 reports pitch as well as yaw
        return r
    }()
    private let context = CIContext()
    private var frameIndex = 0
    private var captureNext = false
    private var onPose: (@Sendable (FacePose?) -> Void)?
    private var onCapture: (@Sendable (CGImage) -> Void)?

    static var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(onPose: @escaping @Sendable (FacePose?) -> Void, onCapture: @escaping @Sendable (CGImage) -> Void) {
        queue.async { [self] in
            self.onPose = onPose
            self.onCapture = onCapture
            if session.inputs.isEmpty { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            onPose = nil
            onCapture = nil
        }
    }

    /// The next analysed frame is delivered as a still.
    func capture() {
        queue.async { [self] in captureNext = true }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameIndex += 1
        guard frameIndex % 2 == 0 || captureNext, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        try? handler.perform([request])
        let face = (request.results ?? []).max { $0.boundingBox.width < $1.boundingBox.width }
        let pose = face.map { f in
            FacePose(yaw: Float((f.yaw?.doubleValue ?? 0) * 180 / .pi),
                     pitch: f.pitch.map { Float($0.doubleValue * 180 / .pi) },
                     box: CGRect(x: f.boundingBox.minX, y: 1 - f.boundingBox.maxY,
                                 width: f.boundingBox.width, height: f.boundingBox.height))
        }
        onPose?(pose)
        if captureNext, face != nil {
            captureNext = false
            let image = CIImage(cvPixelBuffer: buffer)
            if let cg = context.createCGImage(image, from: image.extent) { onCapture?(cg) }
        }
    }
}
