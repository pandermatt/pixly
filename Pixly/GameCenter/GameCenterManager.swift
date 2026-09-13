@preconcurrency import GameKit
import Observation
#if os(macOS)
import AppKit
typealias PlatformViewController = NSViewController
#else
import UIKit
typealias PlatformViewController = UIViewController
#endif

@Observable @MainActor
final class GameCenterManager {
    static let leaderboardID = "ch.pandermatt.pixly.highscore"
    private static let pendingScoreKey = "pendingGameCenterScore"

    private(set) var isAuthenticated = false
    private(set) var alias: String?

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { @Sendable [weak self] viewController, error in
            let manager = self
            Task { @MainActor in
                manager?.handleAuthentication(viewController: viewController, error: error)
            }
        }
    }

    /// Submits every finished run; Game Center keeps the best one. Scores made while
    /// signed out are kept and sent after the next sign-in.
    func submit(score: Int) {
        guard score > 0 else { return }
        Task { await send(score) }
    }

    func showLeaderboard() -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else { return false }
        GKAccessPoint.shared.trigger(leaderboardID: Self.leaderboardID, playerScope: .global, timeScope: .allTime) {}
        return true
    }

    private func handleAuthentication(viewController: PlatformViewController?, error: (any Error)?) {
        if let viewController {
            Self.present(viewController)
            return
        }
        let player = GKLocalPlayer.local
        isAuthenticated = player.isAuthenticated
        alias = player.isAuthenticated ? player.alias : nil
        GKAccessPoint.shared.isActive = false
        if player.isAuthenticated {
            Task { await sendPendingScore() }
        }
    }

    private func send(_ score: Int) async {
        guard GKLocalPlayer.local.isAuthenticated else {
            keepPending(score)
            return
        }
        do {
            try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.leaderboardID])
        } catch {
            keepPending(score)
        }
    }

    private func keepPending(_ score: Int) {
        let defaults = UserDefaults.standard
        defaults.set(max(score, defaults.integer(forKey: Self.pendingScoreKey)), forKey: Self.pendingScoreKey)
    }

    private func sendPendingScore() async {
        let pending = UserDefaults.standard.integer(forKey: Self.pendingScoreKey)
        guard pending > 0 else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingScoreKey)
        await send(pending)
    }

    private static func present(_ viewController: PlatformViewController) {
        #if os(macOS)
        let window = NSApp.keyWindow ?? NSApp.windows.first
        window?.contentViewController?.presentAsSheet(viewController)
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.present(viewController, animated: true)
        #endif
    }
}
