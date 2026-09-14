import SwiftUI

/// Pixly on Apple Watch: only the classic game, and it starts right away.
@main
struct PixlyWatchApp: App {
    @State private var gameCenter = GameCenterManager()
    @State private var preferences = Preferences()

    var body: some Scene {
        WindowGroup {
            let theme = preferences.theme.palette
            WatchGameView()
                .environment(gameCenter)
                .environment(preferences)
                .environment(\.theme, theme)
                .preferredColorScheme(theme.colorScheme)
                .task {
                    gameCenter.authenticate()
                    WatchSync.shared.start(preferences: preferences)
                }
        }
    }
}
