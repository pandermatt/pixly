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
    nonisolated static let leaderboardID = "ch.pandermatt.pixly.highscore"
    /// Pixly 2.0 scores are not comparable with the classic port, so they get their own board.
    nonisolated static let leaderboardID2 = "ch.pandermatt.pixly.highscore2"
    private static let leaderboards = [leaderboardID, leaderboardID2]

    private(set) var isAuthenticated = false
    private(set) var alias: String?

    private let achievementLog = AchievementLog()

    /// Unlocks an achievement, or moves its progress; each step is reported only once.
    func unlock(_ achievement: Achievement, percent: Double = 100) {
        guard achievementLog.record(achievement, percent: percent) else { return }
        Task { await report(achievement, percent: percent) }
    }

    /// A finished run unlocks the score tiers it reached.
    func recordRun(score: Int, program: TerminalSession.Program) {
        for achievement in Achievement.unlocked(byScore: score, in: program) {
            unlock(achievement)
        }
    }

    func addJumps(_ count: Int) {
        if let percent = achievementLog.addJumps(count) {
            unlock(.frequentFlyer, percent: percent)
        }
    }

    private func report(_ achievement: Achievement, percent: Double) async {
        guard GKLocalPlayer.local.isAuthenticated else {
            achievementLog.keepPending(achievement, percent: percent)
            return
        }
        let gameKitAchievement = GKAchievement(identifier: achievement.id)
        gameKitAchievement.percentComplete = percent
        gameKitAchievement.showsCompletionBanner = true
        do {
            try await GKAchievement.report([gameKitAchievement])
        } catch {
            achievementLog.keepPending(achievement, percent: percent)
        }
    }

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
    func submit(score: Int, leaderboardID: String = GameCenterManager.leaderboardID) {
        guard score > 0 else { return }
        Task { await send(score, to: leaderboardID) }
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
            Task { await sendPendingScores() }
        }
    }

    private func send(_ score: Int, to leaderboardID: String) async {
        guard GKLocalPlayer.local.isAuthenticated else {
            keepPending(score, for: leaderboardID)
            return
        }
        do {
            try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID])
        } catch {
            keepPending(score, for: leaderboardID)
        }
    }

    /// The classic board keeps its original key, so scores stored by earlier versions still get sent.
    private static func pendingKey(for leaderboardID: String) -> String {
        leaderboardID == Self.leaderboardID ? "pendingGameCenterScore" : "pendingGameCenterScore.\(leaderboardID)"
    }

    private func keepPending(_ score: Int, for leaderboardID: String) {
        let defaults = UserDefaults.standard
        let key = Self.pendingKey(for: leaderboardID)
        defaults.set(max(score, defaults.integer(forKey: key)), forKey: key)
    }

    private func sendPendingScores() async {
        for leaderboardID in Self.leaderboards {
            let key = Self.pendingKey(for: leaderboardID)
            let pending = UserDefaults.standard.integer(forKey: key)
            guard pending > 0 else { continue }
            UserDefaults.standard.removeObject(forKey: key)
            await send(pending, to: leaderboardID)
        }
        for (achievement, percent) in achievementLog.takePending() {
            await report(achievement, percent: percent)
        }
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
