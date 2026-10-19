import AppKit
import ApplicationServices
import SwiftUI

/// A small, nonactivating drag source follows System Settings. It never edits
/// privacy settings: macOS handles the drop and the user enables the switch.
@MainActor
final class AccessibilityPermissionGuide {
    static let shared = AccessibilityPermissionGuide()
    private var panel: NSPanel?
    private var trackingTask: Task<Void, Never>?

    func show() {
        close()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)

        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 530, height: 146),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AccessibilityDragBar(onClose: { [weak self] in self?.close() }))
        self.panel = panel
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                AutoPasteService.shared.refreshPermission()
                if AutoPasteService.shared.isTrusted { self.close(); return }
                self.followSettingsWindow()
                do { try await Task.sleep(for: .milliseconds(400)) }
                catch { return }
            }
        }
    }

    func close() {
        trackingTask?.cancel()
        trackingTask = nil
        panel?.close()
        panel = nil
    }

    private func followSettingsWindow() {
        guard let panel else { return }
        guard let settings = NSWorkspace.shared.frontmostApplication,
              settings.bundleIdentifier == "com.apple.systempreferences",
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let bounds = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? Int32) == settings.processIdentifier
                    && ($0[kCGWindowLayer as String] as? Int) == 0
                    && (($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }?.width ?? 0) > 400
              })?[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              let primaryScreen = NSScreen.screens.first else {
            panel.orderOut(nil)
            return
        }
        // Window Server coordinates use the top-left of the primary screen.
        let width = min(530, max(320, rect.width - 40))
        let frame = CGRect(x: rect.midX - width / 2,
                           y: primaryScreen.frame.maxY - rect.maxY + 20,
                           width: width, height: 146)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
    }
}

struct AccessibilityDragBar: View {
    let onClose: () -> Void
    private let appURL = Bundle.main.bundleURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.up")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Drag Zen into the Accessibility list above")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Then turn on the switch beside Zen.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").padding(4) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close permission guide")
            }
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable().frame(width: 32, height: 32)
                Text("Zen").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "hand.draw").foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .onDrag { NSItemProvider(object: appURL as NSURL) }
            .accessibilityLabel("Zen application. Drag into the Accessibility list.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
