import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @StateObject private var state = ZenState.shared
    @State private var showingSettings = false
    @State private var settingsContentHeight: CGFloat = 300
    private var theme: ZenTheme { ZenTheme(hex: state.themeHex) }
    @State private var isMicDenied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isMicDenied {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Microphone access is required to record memos.")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.15))
                }

                GridView()
            }
            .background(
                theme.background
                    .ignoresSafeArea()
            )
            .onAppear {
                checkMicPermission()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(action: {
                    showingSettings.toggle()
                }) {
                    Image(systemName: "paintbrush.fill")
                }
                .help("Appearance")
                .accessibilityLabel("Appearance")

                SettingsLink {
                    Image(systemName: "gearshape.fill")
                }
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
        }
        .overlay(alignment: .topTrailing) {
            if showingSettings {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showingSettings = false }

                    GeometryReader { geometry in
                        ScrollView {
                            ThemeSettingsView(state: state)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    settingsContentHeight = height
                                }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: 340, height: min(settingsContentHeight, max(0, geometry.size.height - 24)))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    .padding(12)
                }
                .onExitCommand { showingSettings = false }
            }
        }
        .environment(\.zenTheme, theme)
        .foregroundStyle(theme.foreground)
        .tint(theme.foreground)
        .toolbarBackground(theme.background, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func checkMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        isMicDenied = (status == .denied || status == .restricted)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
