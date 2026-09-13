import Foundation
import Testing
@testable import Pixly

struct SmoothEscapeGameTests {
    private let step = 1.0 / 120

    @Test func theReadyStateBobsWithoutScrolling() {
        var game = SmoothEscapeGame(aspect: 0.46, seed: 1)
        for _ in 0..<240 {
            game.update(dt: step)
        }
        #expect(game.state == .ready)
        #expect(game.distance == 0)
        #expect(abs(game.playerY - 0.5) <= 0.021)
    }

    @Test func aJumpStartsTheRunAndRises() {
        var game = SmoothEscapeGame(aspect: 0.46, seed: 1)
        game.jump()
        #expect(game.state == .running)
        #expect(game.velocity < 0)
        let start = game.playerY
        for _ in 0..<12 {
            game.update(dt: step)
        }
        #expect(game.playerY < start)
        #expect(game.distance > 0)
        #expect(game.score > 0)
    }

    @Test func notJumpingEndsTheRun() {
        var game = SmoothEscapeGame(aspect: 0.46, seed: 2)
        game.jump()
        var ticks = 0
        while game.state == .running, ticks < 1200 {
            game.update(dt: step)
            ticks += 1
        }
        #expect(game.state == .over)
    }

    @Test(arguments: [1, 2, 3] as [UInt64])
    func theTunnelStaysOpenAndInside(seed: UInt64) {
        var game = SmoothEscapeGame(aspect: 0.46, seed: seed)
        game.generate(through: 200)
        var valid = true
        for i in 0..<20_000 {
            let x = Double(i) * 0.01
            let top = game.top(at: x)
            let bottom = game.bottom(at: x)
            if top < 0 || bottom > 1 || bottom - top < SmoothEscapeGame.minGap - SmoothEscapeGame.rowHeight - 1e-9 {
                valid = false
                break
            }
        }
        #expect(valid)
    }

    @Test func wallsAreRightAngledSteps() {
        var game = SmoothEscapeGame(aspect: 0.46, seed: 5)
        game.generate(through: 60)
        let width = SmoothEscapeGame.columnWidth
        var flat = true
        var onGrid = true
        var risers = 0
        for column in stride(from: 0.0, through: 50, by: width) {
            let top = game.top(at: column + 0.001)
            if top != game.top(at: column + width - 0.001) { flat = false }
            let rows = top / SmoothEscapeGame.rowHeight
            if abs(rows - rows.rounded()) > 1e-6 { onGrid = false }
            if top != game.top(at: column + width + 0.001) { risers += 1 }
        }
        #expect(flat)
        #expect(onGrid)
        #expect(risers > 50)
    }

    @Test func barsAlwaysLeaveAPassage() {
        var game = SmoothEscapeGame(aspect: 0.46, seed: 7)
        game.generate(through: 150)
        #expect(game.bars.count > 50)
        let blocked = game.bars.filter { bar in
            let above = bar.top - game.top(at: bar.x)
            let below = game.bottom(at: bar.x) - bar.bottom
            return max(above, below) < SmoothEscapeGame.minPassage - 1e-9
        }
        #expect(blocked.isEmpty)
    }

    @Test func theSameSeedBuildsTheSameTunnel() {
        var first = SmoothEscapeGame(aspect: 0.46, seed: 9)
        var second = SmoothEscapeGame(aspect: 0.46, seed: 9)
        first.generate(through: 40)
        second.generate(through: 40)
        #expect(first.bars == second.bars)
        #expect(first.top(at: 17.3) == second.top(at: 17.3))
    }

    @Test(arguments: [11, 12, 13] as [UInt64])
    func anAutopilotSurvivesTheOpening(seed: UInt64) {
        var game = SmoothEscapeGame(aspect: 0.46, seed: seed)
        game.jump()
        for _ in 0..<(120 * 15) where game.state == .running {
            if game.playerY > target(in: game), game.velocity > 0, apexClearsTheCeiling(in: game) {
                game.jump()
            }
            game.update(dt: step)
        }
        #expect(game.state == .running)
    }

    /// Like a player would: don't jump into a ceiling that steps down just ahead.
    private func apexClearsTheCeiling(in game: SmoothEscapeGame) -> Bool {
        let apex = SmoothEscapeGame.jumpVelocity * SmoothEscapeGame.jumpVelocity / (2 * SmoothEscapeGame.gravity)
        let x = game.playerWorldX
        let ceiling = stride(from: -SmoothEscapeGame.radius, through: 0.2, by: 0.01).map { game.top(at: x + $0) }.max() ?? 0
        return game.playerY - apex - SmoothEscapeGame.radius > ceiling + 0.01
    }

    /// Where a player would aim: the middle of the next passage, a little low because a jump rises.
    private func target(in game: SmoothEscapeGame) -> Double {
        let x = game.playerWorldX
        if let bar = game.bars.first(where: { $0.x + SmoothEscapeGame.Bar.width > x - 0.03 && $0.x < x + 0.35 }) {
            let ceiling = game.top(at: bar.x)
            let floor = game.bottom(at: bar.x)
            let passage = bar.top - ceiling > floor - bar.bottom ? (ceiling, bar.top) : (bar.bottom, floor)
            return (passage.0 + passage.1) / 2 + 0.06
        }
        return (game.top(at: x + 0.1) + game.bottom(at: x + 0.1)) / 2 + 0.06
    }
}

@MainActor
struct SmoothProgramTests {
    @Test func aRunSavesIntoItsOwnScoreTable() throws {
        let defaults = try #require(UserDefaults(suiteName: "pixly-smooth-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher())
        let program = SmoothProgram(preferences: preferences, defaults: defaults)
        var submitted: [Int] = []
        program.onScore = { submitted.append($0) }

        program.jump()
        var ticks = 0
        while program.result == nil, ticks < 1200 {
            program.step()
            ticks += 1
        }
        let result = try #require(program.result)
        #expect(submitted == [result.score])
        #expect(result.isNewHighscore)

        program.name = "Smooth"
        program.saveAndRetry()
        #expect(program.result == nil)
        #expect(program.game.state == .ready)
        #expect(program.scores.entries.first?.name == "Smooth")
        #expect(ScoreStore(defaults: defaults).entries.isEmpty)
        #expect(ScoreStore(defaults: defaults, key: SmoothProgram.scoreKey).entries.count == 1)
    }
}
