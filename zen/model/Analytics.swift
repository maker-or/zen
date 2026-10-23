import AppKit
import Foundation

/// Anonymous active-user counting through PostHog's capture API. Each install
/// gets a random ID; nothing about the person, their audio or their
/// transcripts is ever sent. Unique IDs per day/week/month in PostHog's
/// "Active users" insight give DAU/WAU/MAU.
@MainActor
enum Analytics {
    /// Project token from PostHog → Project settings, bundled at build time
    /// from `POSTHOG_API_KEY` (see scripts/release.sh). Without it, nothing is sent.
    private static let apiKey = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String ?? ""
    /// `https://eu.i.posthog.com` for an EU project.
    private static let host = URL(string: "https://us.i.posthog.com/i/v0/e/")!

    private static let installIDKey = "analytics.installID"
    private static let lastActiveKey = "analytics.lastActiveAt"
    /// One `app_active` per hour at most, however often the app is focused.
    private static let activeInterval: TimeInterval = 60 * 60

    private static var installID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
    }

    static func start() {
        capture("app_opened")
        recordActive()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { recordActive() }
        }
    }

    /// Dictation happens from other apps' windows, so Zen is rarely focused;
    /// call this on use as well as on activation.
    static func recordActive() {
        let defaults = UserDefaults.standard
        let now = Date()
        if let last = defaults.object(forKey: lastActiveKey) as? Date,
           now.timeIntervalSince(last) < activeInterval { return }
        defaults.set(now, forKey: lastActiveKey)
        capture("app_active")
    }

    static func capture(_ event: String) {
        #if DEBUG
        return
        #else
        guard !apiKey.isEmpty else { return }
        let info = Bundle.main.infoDictionary
        let body: [String: Any] = [
            "api_key": apiKey,
            "event": event,
            "distinct_id": installID,
            "properties": [
                "$process_person_profile": false,
                "$lib": "zen-macos",
                "app_version": info?["CFBundleShortVersionString"] as? String ?? "",
                "build": info?["CFBundleVersion"] as? String ?? "",
                "model": ZenState.shared.transcriptionModel.rawValue,
                "$os": "macOS",
                "$os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            ],
        ]
        var request = URLRequest(url: host)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
        #endif
    }
}
