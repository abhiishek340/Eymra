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
        }
        .foregroundStyle(Theme.ink)
    }

    private func go(_ next: Step) {
        withAnimation(.smooth(duration: 0.7)) { step = next }
    }
}

// MARK: - Welcome

struct WelcomeStep: View {
    let next: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Eymra")
                .font(Theme.display(60))
                .revealOnAppear(delay: 0.2, duration: 1.6)
            Text("Your best moments, picked for you.")
                .font(.system(size: 18, design: .serif))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 8)
                .revealOnAppear(delay: 1.0, duration: 1.2)
            Spacer()
            VStack(spacing: 14) {
                Text("“Every day out has a story. We'll find the photos that tell it.”")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                Text("You took hundreds of photos. Eymra looks through them and picks the few worth posting: the best of each moment, no repeats, a bit of everything.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .glassCard()
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            .animation(.smooth(duration: 1.2).delay(1.4), value: appear)
            Button("Let's begin", action: next)
                .buttonStyle(.glassPrimary)
                .padding(.top, 22)
                .accessibilityIdentifier("onboardingStart")
        }
        .padding(24)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { appear = true } }
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
            Text(q.subtitle).font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                .revealOnAppear(delay: 0.4)
            VStack(spacing: 12) {
                ForEach(Array(q.options.enumerated()), id: \.element.id) { optionIndex, option in
                    Button {
                        option.apply(&app.account.prefs)
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            next()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .glassCapsule(interactive: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.system(size: 17, weight: .semibold, design: .serif))
                                Text(option.detail).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            if option.isSelected(app.account.prefs) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ink)
                            }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                        .glassCard(cornerRadius: 22, tint: option.isSelected(app.account.prefs) ? .white.opacity(0.45) : nil, interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: option.isSelected(app.account.prefs))
                    .riseIn(delay: 0.3 + Double(optionIndex) * 0.08)
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
            ZStack {
                Circle().fill(.white.opacity(0.25)).frame(width: 150, height: 150).blur(radius: 10)
                Image(systemName: "face.dashed")
                    .font(.system(size: 72, weight: .ultraLight))
            }
            Text("Help Eymra find you").font(Theme.title(32)).multilineTextAlignment(.center)
                .revealOnAppear()
            VStack(alignment: .leading, spacing: 12) {
                Label("Your friends are in lots of your photos. To pick the ones you want to post, Eymra needs to know which face is yours.", systemImage: "person.2")
                Label("A quick look at your face from a few angles is all it takes.", systemImage: "camera.viewfinder")
                Label("It stays on this phone and is never uploaded.", systemImage: "lock")
            }
            .font(.system(size: 15))
            .labelStyle(DreamLabelStyle())
            .padding(20)
            .glassCard()
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
