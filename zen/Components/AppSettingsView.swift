import SwiftUI
import AppKit

/// Native Settings tabs; each page follows the memo theme so it reads as part
/// of Zen, and is short enough that nothing needs scrolling.
struct AppSettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general, model, about
        var id: Self { self }
    }

    @ObservedObject private var state = ZenState.shared
    @State private var page: Page
    private var theme: ZenTheme { ZenTheme(hex: state.themeHex) }

    // A one-time seed for previews and visual verification.
    init(initialPage: Page = .general) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        TabView(selection: $page) {
            Tab("General", systemImage: "gearshape", value: Page.general) {
                SettingsPage { GeneralSettings() }
            }
            Tab("Model", systemImage: "waveform", value: Page.model) {
                SettingsPage { ModelSettings() }
            }
            Tab("About", systemImage: "info.circle", value: Page.about) {
                SettingsPage { AboutSettings() }
            }
        }
        .tint(theme.foreground)
        .environment(\.zenTheme, theme)
        .containerBackground(theme.background, for: .window)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

/// Fixed width and content height, so the Settings window resizes per tab.
private struct SettingsPage<Content: View>: View {
    @Environment(\.zenTheme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .fontDesign(.rounded)
            .foregroundStyle(theme.foreground)
            .tint(theme.foreground)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var autoPaste = AutoPasteService.shared
    @ObservedObject private var hotkey = HotkeyManager.shared
    @State private var testText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection {
                SettingsRow("Recording shortcut", detail: "Hold to talk. Double-tap to talk hands-free.") {
                    ShortcutRecorder()
                }
                if let error = hotkey.registrationError {
                    SettingsDivider()
                    SettingsNote(error, systemImage: "exclamationmark.triangle")
                }
            }

            SettingsSection {
                SettingsRow("Show widget when idle") {
                    Toggle("Show widget when idle", isOn: $state.showsIdleWidget)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("Widget position") {
                    Picker("Widget position", selection: $state.widgetPosition) {
                        ForEach(WidgetPosition.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsSection {
                SettingsRow("Paste after recording") {
                    Toggle("Paste after recording", isOn: $state.autoPasteEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsDivider()
                if autoPaste.isTrusted {
                    SettingsRow("Accessibility enabled", systemImage: "checkmark.circle.fill") {
                        Button("Manage…") { AccessibilityPermissionGuide.shared.show() }
                            .buttonStyle(.zenCapsule)
                    }
                } else {
                    SettingsRow("Accessibility access needed", systemImage: "hand.raised") {
                        Button("Set up…") {
                            state.autoPasteEnabled = true
                            AccessibilityPermissionGuide.shared.show()
                        }
                        .buttonStyle(.zenCapsule(prominent: true))
                    }
                }
                SettingsDivider()
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Try it: click here, then press \(state.recordingShortcut.displayString)", text: $testText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(theme.foreground.opacity(0.07), in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.foreground.opacity(0.14)))
                        .accessibilityLabel("Test automatic paste")
                    if let message = autoPaste.deliveryMessage {
                        Text(message)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(theme.foreground.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
            }
        }
        .onAppear { autoPaste.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            autoPaste.refreshPermission()
        }
    }
}

// MARK: - Model

private struct ModelSettings: View {
    @Environment(\.zenTheme) private var theme
    @ObservedObject private var state = ZenState.shared
    @ObservedObject private var service = TranscriptionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TranscriptionModel.allCases) { model in
                ModelCard(model: model, isSelected: model == state.transcriptionModel, palette: .theme(theme)) {
                    state.transcriptionModel = model
                    // Load it now if it's installed, so the next recording doesn't wait.
                    service.preloadIfInstalled(model)
                }
            }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.zenTheme) private var theme

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zen").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(version)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(theme.foreground.opacity(0.7))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 4)

            SettingsSection {
                SettingsRow("Introduction") {
                    Button("Replay") {
                        // The full introduction, with the handwritten zen and its music.
                        NSApp.keyWindow?.close()
                        if let appDelegate = AppDelegate.shared {
                            appDelegate.showDemoOnboarding()
                        } else {
                            openWindow(id: "onboarding")
                        }
                    }
                    .buttonStyle(.zenCapsule)
                }
                SettingsDivider()
                SettingsRow("Your memos") {
                    Button("Show in Finder") {
                        let storage = ZenState.shared.storage
                        storage.createDirectories()
                        NSWorkspace.shared.activateFileViewerSelecting([storage.historyURL])
                    }
                    .buttonStyle(.zenCapsule)
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    @Environment(\.zenTheme) private var theme
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.foreground.opacity(0.65))
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .background(theme.foreground.opacity(0.05), in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.foreground.opacity(0.13)))
            if let footer {
                Text(footer)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.foreground.opacity(0.6))
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    @Environment(\.zenTheme) private var theme
    let title: String
    var detail: String?
    var systemImage: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, detail: String? = nil, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium, design: .rounded))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(theme.foreground.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            trailing.fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct SettingsNote: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
    }
}

private struct SettingsDivider: View {
    @Environment(\.zenTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.foreground.opacity(0.1))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// A capsule button in theme colors; `prominent` fills it for the main action.
struct ZenCapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleLabel(configuration: configuration, prominent: prominent)
    }

    private struct CapsuleLabel: View {
        @Environment(\.zenTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let prominent: Bool

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? theme.background : theme.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(prominent ? theme.foreground : theme.foreground.opacity(0.12))
                        .overlay(Capsule().strokeBorder(theme.foreground.opacity(prominent ? 0 : 0.16)))
                }
                .opacity(configuration.isPressed ? 0.75 : isEnabled ? 1 : 0.45)
                .contentShape(.capsule)
        }
    }
}

extension ButtonStyle where Self == ZenCapsuleButtonStyle {
    static var zenCapsule: ZenCapsuleButtonStyle { ZenCapsuleButtonStyle() }
    static func zenCapsule(prominent: Bool) -> ZenCapsuleButtonStyle { ZenCapsuleButtonStyle(prominent: prominent) }
}
