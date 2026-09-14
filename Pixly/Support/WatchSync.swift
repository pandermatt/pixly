#if canImport(WatchConnectivity)
import WatchConnectivity

/// Keeps the Apple Watch in the iPhone's theme and avatar: the phone sends them as the
/// application context whenever they change, and the watch applies whatever arrives (and keeps
/// it, so the last look survives without the phone).
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private var preferences: Preferences?

    func start(preferences: Preferences) {
        self.preferences = preferences
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    /// Sends the current look; the system delivers it the next time the watch app runs.
    func send() {
        guard let preferences, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(Self.context(for: preferences))
    }
    #endif

    static func context(for preferences: Preferences) -> [String: String] {
        ["theme": preferences.theme.rawValue, "avatar": preferences.avatar.rawValue]
    }

    /// Applies what the phone sent; unknown values (from a newer app version) are ignored.
    static func apply(theme: String?, avatar: String?, to preferences: Preferences) {
        if let theme = theme.flatMap(ThemeID.init(rawValue:)), theme != preferences.theme {
            preferences.setTheme(theme)
        }
        if let avatar = avatar.flatMap(Avatar.init(rawValue:)), avatar != preferences.avatar {
            preferences.setAvatar(avatar)
        }
    }

    fileprivate func receive(theme: String?, avatar: String?) {
        guard let preferences else { return }
        Self.apply(theme: theme, avatar: avatar, to: preferences)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        #if os(iOS)
        Task { @MainActor in
            WatchSync.shared.send()
        }
        #else
        let context = session.receivedApplicationContext
        let theme = context["theme"] as? String
        let avatar = context["avatar"] as? String
        Task { @MainActor in
            WatchSync.shared.receive(theme: theme, avatar: avatar)
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let theme = applicationContext["theme"] as? String
        let avatar = applicationContext["avatar"] as? String
        Task { @MainActor in
            WatchSync.shared.receive(theme: theme, avatar: avatar)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another watch: start talking to that one.
        session.activate()
    }
    #endif
}
#endif
