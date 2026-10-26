import PhotosUI
import SwiftUI

/// First run: welcome → sign in → three quick questions → face setup → photo access.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app

    enum Step: Hashable { case welcome, signIn, question(Int), faceIntro, faceScan, faceUpload, photos }
    @State private var step: Step = .welcome

    var body: some View {
        ZStack {
            Group {
                switch step {
                case .welcome: WelcomeStep { go(app.account.isSignedIn ? .question(0) : .signIn) }
                case .signIn: SignInStep { go(.question(0)) }
                case .question(let i): QuestionStep(index: i) { go(i < QuestionStep.count - 1 ? .question(i + 1) : .faceIntro) }
                case .faceIntro:
                    FaceIntroStep(useCamera: { go(.faceScan) }, useUpload: { go(.faceUpload) }, skip: { go(.photos) })
                case .faceScan: FaceScanView(done: { go(.photos) }, cancel: { go(.faceIntro) })
                case .faceUpload: FaceUploadView(done: { go(.photos) }, cancel: { go(.faceIntro) })
                case .photos: PhotoAccessStep { app.account.hasCompletedOnboarding = true }
                }
            }
            .transition(.blurReplace(.downUp))
            .id(step)
            if let previous = previousStep {
                VStack {
                    HStack {
                        Button { go(previous) } label: { Image(systemName: "chevron.backward") }
                            .buttonStyle(RoundGlassButtonStyle())
                            .accessibilityLabel("Back")
                            .accessibilityIdentifier("onboardingBack")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    /// Where Back goes. Face scan and photo picking have their own back buttons.
    private var previousStep: Step? {
        switch step {
        case .welcome, .faceScan, .faceUpload: nil
        case .signIn: .welcome
        case .question(0): app.account.isSignedIn ? .welcome : .signIn
        case .question(let i): .question(i - 1)
        case .faceIntro: .question(QuestionStep.count - 1)
        case .photos: .faceIntro
        }
    }

    private func go(_ next: Step) {
        withAnimation(.smooth(duration: 0.7)) { step = next }
    }
}

// MARK: - Welcome

struct WelcomeStep: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            FloatingPhotos()
                .frame(height: 280)
                .riseIn(delay: 0.1)
            Text("Eymra")
                .font(Theme.display(58))
                .revealOnAppear(delay: 0.5, duration: 1.4)
                .padding(.top, 20)
            Text("Your best moments, picked for you.")
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 6)
                .revealOnAppear(delay: 1.1, duration: 1.0)
            Spacer()
            Button("Let's begin", action: next)
                .buttonStyle(.glassPrimary)
                .riseIn(delay: 1.4)
                .accessibilityIdentifier("onboardingStart")
        }
        .padding(24)
    }
}

/// An illustration of photos floating up out of a pile: little skies, hills and suns, drawn, not bundled.
struct FloatingPhotos: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lift = false

    private struct Card { var x: CGFloat; var y: CGFloat; var angle: Double; var sky: Color; var ground: Color; var sun: Bool }
    private let cards: [Card] = [
        Card(x: -96, y: 30, angle: -14, sky: Color(red: 0.74, green: 0.85, blue: 0.95), ground: Color(red: 0.62, green: 0.78, blue: 0.60), sun: true),
        Card(x: 96, y: 40, angle: 12, sky: Color(red: 0.96, green: 0.86, blue: 0.74), ground: Color(red: 0.80, green: 0.72, blue: 0.58), sun: false),
        Card(x: 0, y: -10, angle: -2, sky: Color(red: 0.66, green: 0.80, blue: 0.94), ground: Color(red: 0.55, green: 0.72, blue: 0.56), sun: true),
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.8), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300)
            ForEach(cards.indices, id: \.self) { i in
                let c = cards[i]
                miniPhoto(c)
                    .rotationEffect(.degrees(c.angle + (lift ? (i.isMultiple(of: 2) ? 2 : -2) : 0)))
                    .offset(x: c.x, y: c.y + (lift ? -8 : 4) * (i == 2 ? 1.4 : 1))
                    .zIndex(i == 2 ? 1 : 0)
            }
        }
        .onAppear {
            guard !reduceMotion && !Theme.stillMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { lift = true }
        }
        .accessibilityHidden(true)
    }

    private func miniPhoto(_ c: Card) -> some View {
        ZStack(alignment: .bottom) {
            c.sky
            Ellipse().fill(c.ground).frame(width: 200, height: 110).offset(y: 50)
            if c.sun {
                Circle().fill(Color(red: 1, green: 0.84, blue: 0.45)).frame(width: 26, height: 26).offset(x: 34, y: -96)
            }
        }
        .frame(width: 128, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
    }
}

// MARK: - Sign in

struct SignInStep: View {
    @Environment(AppModel.self) private var app
    let next: () -> Void
    @State private var name = ""

    var body: some View {
        let account = app.account
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
                Text("Make it yours").font(Theme.title(32))
                    .revealOnAppear()
                Text("Sign in so Eymra can remember you, your style and your face. All of it stays on this phone.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .glassCard()
            Spacer()
            if GoogleSignIn.isConfigured {
                Button {
                    Task {
                        await account.signInWithGoogle()
                        if account.isSignedIn { next() }
                    }
                } label: {
                    HStack(spacing: 10) {
                        GoogleMark()
                        Text(account.isSigningIn ? "Signing in…" : "Continue with Google")
                    }
                }
                .buttonStyle(.glassPrimary)
                .disabled(account.isSigningIn)
                .accessibilityIdentifier("googleSignIn")
            } else {
                VStack(spacing: 12) {
                    Text("Google sign-in will be switched on soon. For now, just tell us your name.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                    TextField("Your first name", text: $name)
                        .textContentType(.givenName)
                        .font(.system(size: 18, design: .serif))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 16)
                        .glassCapsule(interactive: false)
                        .accessibilityIdentifier("nameField")
                    Button("Continue") {
                        account.continueWithName(name)
                        next()
                    }
                    .buttonStyle(.glassPrimary)
                    .accessibilityIdentifier("continueWithName")
                }
            }
            if let error = account.signInError {
                Text(error).font(.footnote).foregroundStyle(.red.opacity(0.8)).multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}

/// A simple four-colour "G" drawn in text, so no logo asset is bundled.
struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(
                AngularGradient(colors: [.red, .yellow, .green, .blue, .red], center: .center)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Questions

struct QuestionStep: View {
    @Environment(AppModel.self) private var app
    let index: Int
    let next: () -> Void

    static let count = 3

    private struct Option: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let apply: (inout UserPrefs) -> Void
        let isSelected: (UserPrefs) -> Bool
    }

    private var question: (title: String, subtitle: String, options: [Option]) {
        switch index {
        case 0:
            return (String(localized: "What do you love to post?"), String(localized: "We'll lean your picks this way. You can change it any time."), [
                Option(id: "mostlyMe", title: String(localized: "Mostly me"), detail: String(localized: "Photos where I'm the star"), symbol: "person.fill",
                       apply: { $0.style = .mostlyMe }, isSelected: { $0.style == .mostlyMe }),
                Option(id: "meAndFriends", title: String(localized: "Me with my friends"), detail: String(localized: "Good times together"), symbol: "person.2.fill",
                       apply: { $0.style = .meAndFriends }, isSelected: { $0.style == .meAndFriends }),
                Option(id: "mix", title: String(localized: "A bit of everything"), detail: String(localized: "Me, friends, places, food"), symbol: "square.grid.2x2.fill",
                       apply: { $0.style = .mix }, isSelected: { $0.style == .mix }),
                Option(id: "places", title: String(localized: "Places and things"), detail: String(localized: "Views, food and details"), symbol: "mountain.2.fill",
                       apply: { $0.style = .places }, isSelected: { $0.style == .places }),
            ])
        case 1:
            return (String(localized: "How do you feel about group photos?"), String(localized: "Some people love them, some don't."), [
                Option(id: "love", title: String(localized: "Love them"), detail: String(localized: "The more the merrier"), symbol: "heart.fill",
                       apply: { $0.groups = .love }, isSelected: { $0.groups == .love }),
                Option(id: "sometimes", title: String(localized: "Sometimes"), detail: String(localized: "If it's a really good one"), symbol: "hand.thumbsup.fill",
                       apply: { $0.groups = .sometimes }, isSelected: { $0.groups == .sometimes }),
                Option(id: "rarely", title: String(localized: "Not really"), detail: String(localized: "I'd rather post photos of me"), symbol: "person.fill.checkmark",
                       apply: { $0.groups = .rarely }, isSelected: { $0.groups == .rarely }),
            ])
        default:
            return (String(localized: "How should your photos flow?"), String(localized: "This sets the order of your post."), [
                Option(id: "story", title: String(localized: "Like a story"), detail: String(localized: "A great first photo, then the day in order"), symbol: "book.pages.fill",
                       apply: { $0.story = .story }, isSelected: { $0.story == .story }),
                Option(id: "bestFirst", title: String(localized: "Best first"), detail: String(localized: "Strongest photos at the front"), symbol: "star.fill",
                       apply: { $0.story = .bestFirst }, isSelected: { $0.story == .bestFirst }),
            ])
        }
    }

    var body: some View {
        let q = question
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<Self.count, id: \.self) { i in
                    Capsule().fill(Theme.ink.opacity(i <= index ? 0.8 : 0.18)).frame(width: i == index ? 26 : 10, height: 6)
                }
            }
            .padding(.top, 12)
            Spacer()
            Text(q.title).font(Theme.title(32))
                .revealOnAppear()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(q.options.enumerated()), id: \.element.id) { optionIndex, option in
                    let selected = option.isSelected(app.account.prefs)
                    Button {
                        option.apply(&app.account.prefs)
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            next()
                        }
                    } label: {
                        VStack(spacing: 14) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 30, weight: .regular))
                                .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                                .frame(width: 66, height: 66)
                                .background(Circle().fill(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.ink.opacity(0.07))))
                                .scaleEffect(selected ? 1.06 : 1)
                            Text(option.title)
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 156)
                        .padding(.horizontal, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .glassCard(cornerRadius: 26, tint: selected ? .white.opacity(0.5) : nil)
                        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                        .animation(Theme.Motion.pop, value: selected)
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: selected)
                    .riseIn(delay: 0.25 + Double(optionIndex) * 0.07)
                    .accessibilityHint(option.detail)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("answer-\(option.id)")
                }
            }
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Face intro

struct FaceIntroStep: View {
    let useCamera: () -> Void
    let useUpload: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            FaceOrbit()
                .frame(height: 200)
                .riseIn(delay: 0.1)
            Text("Help Eymra find you").font(Theme.title(30)).multilineTextAlignment(.center)
                .revealOnAppear(delay: 0.3)
            HStack(spacing: 10) {
                factChip("person.2", "Tell you apart")
                factChip("camera.viewfinder", "5 quick angles")
                factChip("lock", "Stays on phone")
            }
            .riseIn(delay: 0.5)
            Spacer()
            if FaceScanner.hasCamera {
                Button("Use the camera", action: useCamera)
                    .buttonStyle(.glassPrimary)
                    .accessibilityIdentifier("faceUseCamera")
                Button("Choose photos of me instead", action: useUpload)
                    .buttonStyle(.glassSoft)
                    .accessibilityIdentifier("faceUseUpload")
            } else {
                Button("Choose photos of me", action: useUpload)
                    .buttonStyle(.glassPrimary)
                    .accessibilityIdentifier("faceUseUpload")
            }
            Button("Skip for now", action: skip)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .accessibilityIdentifier("faceSkip")
        }
        .padding(24)
    }
}

extension FaceIntroStep {
    fileprivate func factChip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
            Text(text).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 20)
    }
}

/// A face with five dots circling it, one per angle of the scan.
struct FaceOrbit: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = 0.0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 220, height: 220)
            Circle().stroke(Theme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [3, 6])).frame(width: 150, height: 150)
            Image(systemName: "face.smiling").font(.system(size: 64, weight: .ultraLight))
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(Theme.ink).frame(width: 9, height: 9)
                    .offset(y: -75)
                    .rotationEffect(.degrees(Double(i) * 72 + turn))
            }
        }
        .onAppear {
            guard !reduceMotion && !Theme.stillMotion else { return }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { turn = 360 }
        }
        .accessibilityHidden(true)
    }
}

struct DreamLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.icon.frame(width: 22).foregroundStyle(Theme.inkSoft)
            configuration.title.foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Photo access

struct PhotoAccessStep: View {
    @Environment(AppModel.self) private var app
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .ultraLight))
            Text("Let Eymra see your photos").font(Theme.title(30)).multilineTextAlignment(.center)
                .revealOnAppear()
            Text("Eymra looks through your photos to find the ones worth sharing. Your photos stay yours.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(20)
                .glassCard()
            Spacer()
            if app.access == .denied {
                Text("Photo access is off. You can turn it on in Settings.")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                Button("Open Settings") { app.openSystemSettings() }.buttonStyle(.glassPrimary)
                Button("Continue anyway", action: done).buttonStyle(.glassSoft)
            } else {
                Button("Allow access") {
                    Task {
                        if !app.access.isUsable { await app.requestAccess() }
                        if app.access.isUsable { done() }
                    }
                }
                .buttonStyle(.glassPrimary)
                .accessibilityIdentifier("allowAccess")
            }
        }
        .padding(24)
    }
}
