import SwiftUI

/// The welcome: drawn photos fly in scattered, line up, close into a ring around the name, then open into a
/// wide arc with the line underneath. Drag up or down to morph between ring and arc, drag sideways along the arc
/// to slide through it, tap a photo to flip it.
struct PhotoRingIntro: View {
    enum Phase { case scatter, line, ring }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .scatter
    /// 0 is the ring, 1 is the arc.
    @State private var morph: Double = 0
    @State private var morphAtDragStart: Double?
    /// How far the arc has been slid, in degrees.
    @State private var slide: Double = 0
    @State private var slideAtDragStart: Double?
    @State private var touched = false

    private static let count = 16
    private static let cardSize = CGSize(width: 56, height: 78)
    /// Fixed, so the scatter is the same every launch and never jumps between renders.
    private static let scatter: [(x: Double, y: Double, angle: Double)] = (0..<count).map { i in
        let a = Double(i) * 2.399963, d = 0.6 + Double((i * 7) % 5) / 6
        return (cos(a) * 520 * d, sin(a) * 640 * d, Double((i * 53) % 180) - 90)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(0..<Self.count, id: \.self) { i in
                    let t = target(i, in: size)
                    FlipPrint(index: i)
                        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                        .scaleEffect(t.scale)
                        .rotationEffect(.degrees(t.angle))
                        .offset(x: t.x, y: t.y)
                        .opacity(t.opacity)
                        .zIndex(Double(i))
                        .animation(.spring(response: 0.9, dampingFraction: 0.78).delay(phaseDelay(i)), value: phase)
                        .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.86), value: morph)
                        .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.86), value: slide)
                }
                title(in: size)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(drag(in: size))
        }
        .task { await play() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: phase)
        .sensoryFeedback(.selection, trigger: morph >= 0.5)
    }

    // MARK: Text

    /// The name sits in the middle of the ring, then rises to the top as the ring opens into the arc.
    private func title(in size: CGSize) -> some View {
        VStack(spacing: 8) {
            Text("Eymra")
                .font(Theme.display(54))
            Text("Your best moments, picked for you.")
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(Theme.inkSoft)
                .opacity(morph)
            Text("Swipe up")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 10)
                .opacity(phase == .ring && !touched ? max(0, 1 - morph * 3) : 0)
        }
        .multilineTextAlignment(.center)
        .offset(y: lerp(0, -size.height * 0.27, morph))
        .scaleEffect(lerp(0.86, 1, morph))
        .opacity(phase == .ring ? 1 : 0)
        .blur(radius: phase == .ring ? 0 : 8)
        .animation(.easeOut(duration: 0.9), value: phase)
        .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.86), value: morph)
        .allowsHitTesting(false)
    }

    // MARK: Layout

    private struct Target { var x: Double; var y: Double; var angle: Double; var scale: Double; var opacity: Double }

    private func target(_ i: Int, in size: CGSize) -> Target {
        let n = Double(Self.count)
        switch phase {
        case .scatter:
            let s = Self.scatter[i]
            return Target(x: s.x, y: s.y, angle: s.angle, scale: 0.6, opacity: 0)
        case .line:
            let spacing = 62.0
            return Target(x: (Double(i) - (n - 1) / 2) * spacing, y: 0, angle: 0, scale: 1, opacity: 1)
        case .ring:
            // Ring around the name.
            let radius = min(Double(size.width) * 0.42, 160)
            let ringAngle = Double(i) / n * 360 - 90
            let ringRad = ringAngle * .pi / 180
            let ring = (x: cos(ringRad) * radius, y: sin(ringRad) * radius, angle: ringAngle + 90)
            // A wide rainbow arc, high point a little below the middle, its ends running off the sides.
            let arcRadius = Double(size.width) * 1.25
            let apex = Double(size.height) * 0.04
            let spread = 104.0
            let step = spread / (n - 1)
            let arcAngle = -90 - spread / 2 + Double(i) * step + slide
            let arcRad = arcAngle * .pi / 180
            let arc = (x: cos(arcRad) * arcRadius, y: sin(arcRad) * arcRadius + apex + arcRadius, angle: arcAngle + 90)
            return Target(x: lerp(ring.x, arc.x, morph), y: lerp(ring.y, arc.y, morph),
                          angle: lerp(ring.angle, arc.angle, morph), scale: lerp(1, 1.45, morph), opacity: 1)
        }
    }

    /// Cards leave the scatter one after another; the ring closes all at once.
    private func phaseDelay(_ i: Int) -> Double {
        guard !reduceMotion else { return 0 }
        return phase == .line ? Double(i) * 0.03 : 0
    }

    // MARK: Sequence and gestures

    private func play() async {
        if reduceMotion || Theme.stillMotion {
            phase = .ring
            morph = 1
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        phase = .line
        try? await Task.sleep(for: .milliseconds(1300))
        phase = .ring
        // Open into the arc on its own if nobody has swiped by then.
        try? await Task.sleep(for: .milliseconds(2400))
        if !touched { morph = 1 }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard phase == .ring else { return }
                touched = true
                let startMorph = morphAtDragStart ?? morph
                let startSlide = slideAtDragStart ?? slide
                morphAtDragStart = startMorph
                slideAtDragStart = startSlide
                morph = min(1, max(0, startMorph - value.translation.height / 260))
                // Sideways moves along the arc, only once it's open.
                if morph > 0.8 {
                    slide = min(30, max(-30, startSlide + value.translation.width / 8))
                }
            }
            .onEnded { value in
                guard phase == .ring else { return }
                morph = morph - value.predictedEndTranslation.height / 1200 > 0.5 ? 1 : 0
                slide = min(24, max(-24, slide))
                morphAtDragStart = nil
                slideAtDragStart = nil
            }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

/// One drawn print. Tap it to turn it over: the back is marked as a keeper.
private struct FlipPrint: View {
    let index: Int
    @State private var flipped = false

    private static let scenes: [(sky: Color, ground: Color, sea: Color?, sun: Bool)] = [
        (Color(red: 0.74, green: 0.85, blue: 0.95), Color(red: 0.62, green: 0.78, blue: 0.60), nil, true),
        (Color(red: 0.98, green: 0.80, blue: 0.64), Color(red: 0.86, green: 0.62, blue: 0.48), Color(red: 0.93, green: 0.66, blue: 0.52), true),
        (Color(red: 0.80, green: 0.90, blue: 0.94), Color(red: 0.93, green: 0.86, blue: 0.72), Color(red: 0.42, green: 0.66, blue: 0.74), false),
        (Color(red: 0.96, green: 0.88, blue: 0.76), Color(red: 0.80, green: 0.70, blue: 0.56), nil, false),
        (Color(red: 0.66, green: 0.80, blue: 0.94), Color(red: 0.55, green: 0.72, blue: 0.56), nil, true),
        (Color(red: 0.93, green: 0.84, blue: 0.80), Color(red: 0.76, green: 0.58, blue: 0.50), nil, false),
        (Color(red: 0.84, green: 0.91, blue: 0.86), Color(red: 0.50, green: 0.66, blue: 0.52), Color(red: 0.55, green: 0.74, blue: 0.78), true),
        (Color(red: 0.99, green: 0.90, blue: 0.72), Color(red: 0.88, green: 0.72, blue: 0.50), nil, true),
    ]

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back.opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: flipped)
        .onTapGesture { flipped.toggle() }
        .sensoryFeedback(.selection, trigger: flipped)
        .accessibilityHidden(true)
    }

    private var front: some View {
        let s = Self.scenes[index % Self.scenes.count]
        return ZStack(alignment: .bottom) {
            s.sky
            if let sea = s.sea { Rectangle().fill(sea).frame(height: 34) }
            Ellipse().fill(s.ground).frame(width: 96, height: 50).offset(y: s.sea == nil ? 24 : 36)
            if s.sun {
                Circle().fill(Color(red: 1, green: 0.86, blue: 0.5)).frame(width: 12, height: 12).offset(x: 12, y: -50)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.ink)
            .overlay {
                VStack(spacing: 2) {
                    Text("a").font(.system(size: 8, weight: .bold)).textCase(.uppercase).tracking(1).foregroundStyle(Theme.ember)
                    Text("keeper").font(.system(size: 13, weight: .semibold, design: .serif)).italic().foregroundStyle(Theme.onInk)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
    }
}
