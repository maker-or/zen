import SwiftUI
import AVFoundation
import AppKit

@MainActor
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var state: ZenState
    @ObservedObject private var service: TranscriptionService
    @ObservedObject private var autoPaste = AutoPasteService.shared
    @State private var step: OnboardingStep
    @State private var microphoneStatus = AVAuthorizationStatus.notDetermined
    @State private var requestingMicrophone = false
    @State private var preparingModel = false
    private let onFinish: () -> Void

    // A one-time seed for previews and visual verification.
    init(state: ZenState? = nil, service: TranscriptionService? = nil,
         initialStep: OnboardingStep = .welcome, onFinish: @escaping () -> Void) {
        self.state = state ?? .shared
        self.service = service ?? .shared
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    pageContent
                        .id(step)
                        .transition(.opacity)
                        .padding(.top, geometry.size.height * (step == .models ? 0.07 : 0.15))
                        .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
                    .padding(.bottom, max(20, geometry.size.height * 0.028))
            }
            .padding(.leading, geometry.size.width * 0.065)
            .padding(.trailing, geometry.size.width * 0.045)
        }
        .frame(minWidth: 680, minHeight: 600)
        .fontDesign(.rounded)
        .foregroundStyle(OnboardingPalette.foreground)
        .tint(OnboardingPalette.accent)
        .background(OnboardingPalette.background.ignoresSafeArea())
        .containerBackground(OnboardingPalette.background, for: .window)
        .presentationBackground(OnboardingPalette.background)
        .background(OnboardingWindowControls())
        .preferredColorScheme(.dark)
        .onAppear {
            autoPaste.refreshPermission()
            refreshMicrophoneStatus()
            if !state.transcriptionModel.isSupported { state.transcriptionModel = .voz }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            autoPaste.refreshPermission()
            refreshMicrophoneStatus()
        }
        .task(id: requestingMicrophone) {
            guard requestingMicrophone else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            requestingMicrophone = false
            refreshMicrophoneStatus()
            if granted { navigate(to: .capture) }
        }
        .onExitCommand(perform: onFinish)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if step == .welcome {
                OnboardingOpening()
            } else {
                if step == .capture {
                    OnboardingShortcutHeading()
                } else {
                    OnboardingAnimatedHeading(text: headline)
                        .id(headline)
                }
                if !explanation.isEmpty {
                    Text(explanation)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(OnboardingPalette.secondary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                        .onboardingReveal(index: 8)
                }

                if step == .capture {
                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingShortcutCheck()
                        ShortcutRecorder(style: .onboarding)
                    }
                    .onboardingReveal(index: 9)
                }

                if step == .models {
                    OnboardingModelPicker(state: state, service: service, isPreparing: isPreparingModel)
                        .onboardingReveal(index: 8)
                    if !service.isModelInstalled(state.transcriptionModel) {
                        Button(isPreparingModel ? "Continue while preparing" : "Download later") {
                            if let next = step.next { navigate(to: next) }
                        }
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(OnboardingPalette.secondary)
                        .buttonStyle(.plain)
                        .underline()
                        .onboardingReveal(index: 9)
                    }
                }

                if step == .paste {
                    if autoPaste.isTrusted {
                        Label("Automatic paste is ready", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(OnboardingPalette.accent)
                            .onboardingReveal(index: 8)
                    } else {
                        Button {
                            state.autoPasteEnabled = true
                            AccessibilityPermissionGuide.shared.show()
                        } label: {
                            Label("Enable automatic paste", systemImage: "hand.tap.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(OnboardingPalette.background)
                                .padding(.horizontal, 22).padding(.vertical, 14)
                                .background(OnboardingPalette.accent, in: .capsule)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .onboardingReveal(index: 8)
                    }
                }

                if step == .microphone && (microphoneStatus == .notDetermined || microphoneStatus == .denied) {
                    Button("Continue without microphone") { navigate(to: .capture) }
                        .font(.system(size: 13, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundStyle(OnboardingPalette.secondary)
                        .underline()
                        .disabled(requestingMicrophone)
                        .onboardingReveal(index: 9)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let previous = step.previous {
                Button { navigate(to: previous) } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 44, height: 56)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OnboardingPalette.accent)
                .help("Back to \(previous.navigationTitle)")
                .accessibilityLabel("Back")
                .accessibilityIdentifier("onboarding.back")
                .disabled(requestingMicrophone)
            }
            Spacer()
            Button(action: advance) {
                HStack(spacing: 10) {
                    if requestingMicrophone || (step == .models && isPreparingModel) {
                        ProgressView().controlSize(.mini).tint(OnboardingPalette.background)
                    }
                    if primaryButtonShowsTitle {
                        Text(primaryButtonTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    if !requestingMicrophone && !(step == .models && isPreparingModel) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: primaryButtonShowsTitle ? 20 : 28, weight: .regular))
                    }
                }
                .foregroundStyle(OnboardingPalette.background)
                .padding(.horizontal, primaryButtonShowsTitle ? 22 : 0)
                .frame(width: primaryButtonShowsTitle ? nil : 56, height: 56)
                .background(OnboardingPalette.accent, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(primaryButtonTitle)
            .accessibilityIdentifier("onboarding.next")
            .help(primaryButtonTitle)
            .disabled(requestingMicrophone || (step == .models && (isPreparingModel || !state.transcriptionModel.isSupported)))
        }
    }

    private var headline: String {
        switch step {
        case .welcome: return "Type at the speed\nof your thoughts"
        case .capture: return "Press \(state.recordingShortcut.spokenDescription)"
        case .privacy: return "Your voice stays\non your Mac."
        case .models: return "Choose your\nspeech model."
        case .paste: return "Speak your words.\nWrite them anywhere."
        case .microphone:
            switch microphoneStatus {
            case .authorized: return "Microphone\nready."
            case .denied: return "Allow microphone\naccess."
            case .restricted: return "Microphone\nunavailable."
            default: return "Enable your\nmicrophone."
            }
        }
    }

    private var explanation: String {
        switch step {
        case .welcome: return ""
        case .capture: return "Hold it to talk, let go to paste.\nDouble-tap it to talk hands-free."
        case .privacy: return "Transcribed on this Mac. Never sent anywhere."
        case .models: return ""
        case .paste: return "Your words land where you’re typing."
        case .microphone:
            switch microphoneStatus {
            case .denied: return "Turn on Zen in System Settings → Privacy & Security → Microphone."
            case .restricted: return "This Mac doesn’t allow microphone access."
            default: return ""
            }
        }
    }

    private var primaryButtonTitle: String {
        if requestingMicrophone { return "Waiting for permission…" }
        if step == .models {
            // An installed model only needs loading, which happens in the background.
            if service.isModelInstalled(state.transcriptionModel) { return "Continue" }
            switch service.modelStates[state.transcriptionModel] {
            case .ready: return "Continue"
            case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
            case .loading: return "Preparing…"
            case .failed: return "Retry download"
            case nil: return preparingModel ? "Preparing…" : "Download & Prepare"
            }
        }
        if step == .microphone && microphoneNeedsAction {
            return microphoneStatus == .denied ? "Open System Settings" : "Enable microphone"
        }
        if let next = step.next { return "Continue to \(next.navigationTitle)" }
        return "Open Zen"
    }

    /// The steps that act rather than just move on say what they do.
    private var primaryButtonShowsTitle: Bool {
        step == .models || step == .capture || (step == .microphone && microphoneNeedsAction)
    }

    private var microphoneNeedsAction: Bool {
        microphoneStatus == .notDetermined || microphoneStatus == .denied
    }

    private func advance() {
        switch step {
        case .models:
            let model = state.transcriptionModel
            guard service.isModelInstalled(model) else {
                prepareSelectedModel()
                return
            }
            service.preloadIfInstalled(model)
        case .microphone where microphoneStatus == .notDetermined:
            requestingMicrophone = true
            return
        case .microphone where microphoneStatus == .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return
        default:
            break
        }
        if let next = step.next {
            navigate(to: next)
        } else {
            onFinish()
        }
    }

    private func navigate(to next: OnboardingStep) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.18)) {
            step = next
        }
    }

    private func refreshMicrophoneStatus() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private var isPreparingModel: Bool {
        if service.isModelInstalled(state.transcriptionModel) { return false }
        if preparingModel { return true }
        switch service.modelStates[state.transcriptionModel] {
        case .downloading, .loading: return true
        default: return false
        }
    }

    private func prepareSelectedModel() {
        guard !isPreparingModel, state.transcriptionModel.isSupported else { return }
        let model = state.transcriptionModel
        preparingModel = true
        Task {
            defer { preparingModel = false }
            // The shared service keeps progress and retry state for Settings too.
            try? await service.prepareModel(model)
        }
    }
}

#Preview("Introduction") {
    OnboardingView(onFinish: {})
        .frame(width: 860, height: 660)
}

#Preview("Microphone") {
    OnboardingView(initialStep: .microphone, onFinish: {})
        .frame(width: 680, height: 600)
}
