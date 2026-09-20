import Foundation
import Testing
@testable import Pixly

@MainActor
struct QuickGameTests {
    private func makeGame() throws -> (QuickGame, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "pixly-quick-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher())
        return (QuickGame(preferences: preferences, defaults: defaults), defaults)
    }

    /// Feeds frames 20 ms apart until the run ends or `seconds` have passed; returns the last time.
    private func play(_ game: QuickGame, from start: TimeInterval, seconds: TimeInterval) -> TimeInterval {
        var time = start
        game.frame(at: time)
        while time < start + seconds, game.state == .playing {
            time += ClassicGame.tickInterval
            game.frame(at: time)
        }
        return time
    }

    @Test func waitsForTheFirstPress() throws {
        let (game, _) = try makeGame()
        game.frame(at: 0)
        game.frame(at: 5)
        #expect(game.state == .ready)
        #expect(game.score == 0)
        #expect(game.playerRow == ClassicGame.startY)
    }

    @Test func aCrashEndsTheRunAndIsReportedOnce() throws {
        let (game, defaults) = try makeGame()
        var runs: [(score: Int, jumps: Int)] = []
        game.onRunEnd = { runs.append(($0, $1)) }

        game.press()
        #expect(game.state == .playing)
        #expect(game.jumpCount == 1)
        let crash = play(game, from: 0, seconds: 40)
        #expect(game.state == .over)
        #expect(game.score > 0)
        #expect(game.isNewBest)
        #expect(game.best == game.score)
        #expect(ScoreStore(defaults: defaults).best == game.score)
        #expect(runs.count == 1)
        #expect(runs.first?.score == game.score)
        #expect(runs.first?.jumps == 1)

        game.frame(at: crash + 1)
        #expect(runs.count == 1)
    }

    @Test func pressesRightAfterACrashDontStartTheNextRun() throws {
        let (game, _) = try makeGame()
        game.press()
        let crash = play(game, from: 0, seconds: 40)
        game.press()
        #expect(game.state == .over)
        #expect(!game.canRestart)

        game.frame(at: crash + QuickGame.restartDelay + 0.1)
        #expect(game.canRestart)
        game.press()
        #expect(game.state == .playing)
        #expect(game.score == 0)
    }

    @Test func pausingStopsTheClockUntilThePlayerTaps() throws {
        let (game, _) = try makeGame()
        game.press()
        game.frame(at: 0)
        game.frame(at: 0.1)
        let score = game.score
        #expect(score > 0)

        game.pause()
        game.frame(at: 0.2)
        game.frame(at: 3)
        #expect(game.score == score)
        #expect(game.isPaused)
        game.press()
        #expect(!game.isPaused)
        #expect(game.state == .playing)
    }

    @Test func aStretchedLayoutFillsTheWholeSize() {
        let layout = ConsoleLayout(stretching: CGSize(width: 200, height: 240), rows: 24)
        let corner = layout.rect(x: 80, y: 24)
        #expect(layout.rect(x: 1, y: 1).origin == .zero)
        #expect(corner.maxX == 200)
        #expect(corner.maxY == 240)
    }
}

#if canImport(WatchConnectivity)
@MainActor
struct WatchSyncTests {
    @Test func thePhonesLookReachesTheWatch() throws {
        let phone = Preferences(defaults: try #require(UserDefaults(suiteName: "pixly-phone-\(UUID().uuidString)")), iconSwitcher: FakeIconSwitcher())
        let watch = Preferences(defaults: try #require(UserDefaults(suiteName: "pixly-watch-\(UUID().uuidString)")), iconSwitcher: FakeIconSwitcher())
        phone.setTheme(.amber)
        phone.setAvatar(.heart)

        let context = WatchSync.context(for: phone)
        WatchSync.apply(theme: context["theme"], avatar: context["avatar"], to: watch)
        #expect(watch.theme == .amber)
        #expect(watch.avatar == .heart)

        WatchSync.apply(theme: "neon", avatar: nil, to: watch)
        #expect(watch.theme == .amber)
        #expect(watch.avatar == .heart)
    }
}
#endif
