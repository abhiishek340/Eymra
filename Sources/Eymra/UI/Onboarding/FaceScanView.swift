import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// The steps of the guided face scan, each auto-captured once the head is held in place.
enum ScanStep: Int, CaseIterable {
    case straight, left, right, up, down

    var instruction: String {
        switch self {
        case .straight: String(localized: "Look straight at the camera")
        case .left: String(localized: "Slowly turn your head to the left")
        case .right: String(localized: "Now turn to the right")
        case .up: String(localized: "Lift your chin up a little")
        case .down: String(localized: "Now look down a little")
        }
    }

    var symbol: String {
        switch self {
        case .straight: "face.smiling"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

/// Drives the scan: checks each pose, holds briefly, captures, crops the face and makes its print.
@MainActor @Observable
final class FaceScanModel {
    let scanner = FaceScanner()
    var step: ScanStep = .straight
    var pose: FacePose?
    var captured: [ScanStep: (crop: CGImage, signature: [Float])] = [:]
    var finished = false
    var cameraDenied = false
    var holdProgress: Double = 0
    var canSkipStep = false
    private var holdStart: Date?
    private var stepStart = Date()
    private var firstTurnSign: Float?
    private var capturing = false
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    func start() async {
        guard await FaceScanner.requestAccess() else { cameraDenied = true; return }
        stepStart = Date()
        scanner.start(onPose: { [weak self] pose in
            Task { @MainActor in self?.update(pose) }
        }, onCapture: { [weak self] image in
            Task { @MainActor in await self?.store(image) }
        })
    }

    func stop() { scanner.stop() }

    var faceInFrame: Bool { pose != nil }

    private func update(_ pose: FacePose?) {
        self.pose = pose
        guard !finished, !capturing else { return }
        canSkipStep = step != .straight && Date().timeIntervalSince(stepStart) > 8
        guard let pose, matches(pose) else {
            holdStart = nil
            holdProgress = 0
            return
        }
        let start = holdStart ?? Date()
        holdStart = start
        holdProgress = min(1, Date().timeIntervalSince(start) / 0.4)
        if holdProgress >= 1 {
            capturing = true
            scanner.capture()
        }
    }

    /// Head turn signs depend on mirroring, so "left" takes whichever way the user first turns and "right" the other.
    private func matches(_ p: FacePose) -> Bool {
        let pitch = p.pitch ?? 0
        switch step {
        case .straight: return abs(p.yaw) < 10 && abs(pitch) < 12
        case .left:
            guard abs(p.yaw) > 20 else { return false }
            if firstTurnSign == nil { firstTurnSign = p.yaw > 0 ? 1 : -1 }
            return (p.yaw > 0 ? 1 : -1) == firstTurnSign
        case .right:
            guard abs(p.yaw) > 20, let s = firstTurnSign else { return false }
            return (p.yaw > 0 ? 1 : -1) == -s
        case .up: return p.pitch.map { $0 < -10 } ?? false
        case .down: return p.pitch.map { $0 > 10 } ?? false
        }
    }

    private func store(_ image: CGImage) async {
        if let face = await FaceEmbedder.largestFace(in: image) {
            captured[step] = face
            haptic.impactOccurred()
            advance()
        }
        capturing = false
        holdStart = nil
        holdProgress = 0
    }

    func skipStep() {
        advance()
    }

    private func advance() {
        if let next = ScanStep(rawValue: step.rawValue + 1) {
            withAnimation(.spring(duration: 0.4)) { step = next }
            stepStart = Date()
            canSkipStep = false
        } else {
            finished = true
            stop()
        }
    }
}

struct FaceScanView: View {
    @Environment(AppModel.self) private var app
    let done: () -> Void
    let cancel: () -> Void
    @State private var model = FaceScanModel()

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Button { model.stop(); cancel() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.glassSoft)
                    .accessibilityLabel("Back")
                Spacer()
            }
            Spacer(minLength: 0)
            if model.cameraDenied {
                Text("Camera access is off. You can turn it on in Settings, or choose photos of yourself instead.")
                    .multilineTextAlignment(.center).padding(20).glassCard()
                Button("Open Settings") { app.openSystemSettings() }.buttonStyle(.glassPrimary)
            } else if model.finished {
                finishedView
            } else {
                scanner
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var scanner: some View {
        VStack(spacing: 26) {
            ZStack {
                CameraPreview(session: model.scanner.session)
                    .frame(width: 270, height: 270)
                    .clipShape(Circle())
                // One arc per step: filled when captured, the current one fills while holding still.
                ForEach(ScanStep.allCases, id: \.self) { s in
                    let segment = 1.0 / Double(ScanStep.allCases.count)
                    let start = Double(s.rawValue) * segment + 0.01
                    let fill = model.captured[s] != nil ? 1 : (s == model.step ? model.holdProgress : 0)
                    Circle().trim(from: start, to: start + segment - 0.02)
                        .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    Circle().trim(from: start, to: start + (segment - 0.02) * fill)
                        .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                }
                .frame(width: 300, height: 300)
                .rotationEffect(.degrees(-90))
            }
            .padding(12)
            .glassCard(cornerRadius: 170)

            VStack(spacing: 10) {
                Image(systemName: model.step.symbol).font(.system(size: 26, weight: .light))
                Text(model.faceInFrame ? model.step.instruction : String(localized: "Fit your face inside the circle"))
                    .font(Theme.title(24))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("scanInstruction")
                Text("Step \(model.step.rawValue + 1) of \(ScanStep.allCases.count)")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassCard()
            if model.canSkipStep {
                Button("Skip this angle") { model.skipStep() }.buttonStyle(.glassSoft)
            }
        }
    }

    private var finishedView: some View {
        VStack(spacing: 20) {
            HStack(spacing: -14) {
                ForEach(ScanStep.allCases, id: \.self) { s in
                    if let face = model.captured[s] {
                        Image(decorative: face.crop, scale: 1)
                            .resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            Text("All set, \(app.account.greetingName)!").font(Theme.title(30))
            Text("Eymra now knows what you look like, so it can find you among your friends.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.inkSoft)
            Button("Continue") {
                let faces = ScanStep.allCases.compactMap { model.captured[$0] }
                app.account.saveFace(crops: faces.map(\.crop), prints: faces.map(\.signature))
                done()
            }
            .buttonStyle(.glassPrimary)
            .accessibilityIdentifier("faceScanDone")
        }
        .padding(24)
        .glassCard()
    }
}

/// Live front-camera preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        view.backgroundColor = .black.withAlphaComponent(0.2)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

// MARK: - Choose photos of me

struct FaceUploadView: View {
    @Environment(AppModel.self) private var app
    let done: () -> Void
    let cancel: () -> Void
    @State private var selection: [PhotosPickerItem] = []
    @State private var faces: [(crop: CGImage, signature: [Float])] = []
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: cancel) { Image(systemName: "chevron.left") }
                    .buttonStyle(.glassSoft)
                    .accessibilityLabel("Back")
                Spacer()
            }
            Spacer()
            Text("Choose photos of you").font(Theme.title(30))
            Text("Pick 3 to 6 photos where your face is clear. Different angles help. If there are other people in a photo, we'll use the biggest face.")
                .font(.system(size: 15)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                .padding(20).glassCard()
            if !faces.isEmpty {
                HStack(spacing: -12) {
                    ForEach(faces.indices, id: \.self) { i in
                        Image(decorative: faces[i].crop, scale: 1)
                            .resizable().scaledToFill()
                            .frame(width: 60, height: 60).clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center) }
            Spacer()
            // The label closure is Sendable, so it gets a plain string rather than reading view state.
            let pickerTitle = faces.isEmpty ? String(localized: "Choose photos") : String(localized: "Choose different photos")
            PhotosPicker(selection: $selection, maxSelectionCount: 6, matching: .images) {
                Text(pickerTitle)
            }
            .buttonStyle(faces.isEmpty ? AnyButtonStyle(.glassPrimary) : AnyButtonStyle(.glassSoft))
            .disabled(working)
            if !faces.isEmpty {
                Button("Use these") {
                    app.account.saveFace(crops: faces.map(\.crop), prints: faces.map(\.signature))
                    done()
                }
                .buttonStyle(.glassPrimary)
            }
        }
        .padding(24)
        .onChange(of: selection) { _, items in Task { await load(items) } }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        working = true
        defer { working = false }
        var found: [(crop: CGImage, signature: [Float])] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cg = try? PhotoLibrary.upright(image),
                  let face = await FaceEmbedder.largestFace(in: cg) else { continue }
            found.append(face)
        }
        faces = found
        message = found.isEmpty
            ? String(localized: "We couldn't find a face in those photos. Try ones where your face is bigger and clearer.")
            : String(localized: "Found you in \(found.count) of \(items.count) photos.")
    }
}

/// Type-erased button style so a view can switch between two styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
