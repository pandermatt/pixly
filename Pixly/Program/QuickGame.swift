import Foundation
import Observation

/// The classic game on its own, without the shell, menus or save window: tap to start, tap (or
/// turn the crown) to jump, and after a crash tap again. The Apple Watch app plays this.
@Observable @MainActor
final class QuickGame {
    enum State: Equatable, Sendable {
        case ready, playing, over
    }

    /// A crash stays on screen this long before a tap starts the next run, so taps that were
    /// meant as jumps can't skip the score.
    static let restartDelay: TimeInterval = 1.5

    private(set) var state = State.ready
    private(set) var console = ConsoleBuffer()
    private(set) var score = 0
    private(set) var best: Int
    private(set) var isNewBest = false
    private(set) var isPaused = false
    private(set) var canRestart = false
    private(set) var jumpCount = 0

    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored var playerAlias: @MainActor () -> String? = { nil }
    /// A run ended: its score and how many jumps it took.
    @ObservationIgnored var onRunEnd: @MainActor (_ score: Int, _ jumps: Int) -> Void = { _, _ in }

    @ObservationIgnored private var game = PixelEscapeGame()
    @ObservationIgnored private var scores: ScoreStore
    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var crashTime: TimeInterval?
    @ObservationIgnored private var runJumps = 0

    init(preferences: Preferences, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        scores = ScoreStore(defaults: defaults)
        best = scores.best
        render()
    }

    /// The row the pixel is on, so a screen can draw the avatar larger than one cell.
    var playerRow: Int {
        game.y
    }

    /// A tap or a crown turn: starts a run, jumps, resumes, or after a crash starts the next run.
    func press() {
        switch state {
        case .ready:
            state = .playing
            jump()
        case .playing:
            if isPaused {
                isPaused = false
                lastTime = nil
            }
            jump()
        case .over:
            guard canRestart else { return }
            startRun()
            jump()
        }
    }

    func pause() {
        guard state == .playing, !isPaused else { return }
        isPaused = true
        lastTime = nil
    }

    /// One frame of the screen's clock: runs the 20 ms ticks of main.c that fit since the last one.
    func frame(at time: TimeInterval) {
        defer { lastTime = time }
        if state == .over, !canRestart, let crashTime, time - crashTime >= Self.restartDelay {
            canRestart = true
        }
        guard state == .playing, !isPaused, let lastTime else { return }
        accumulator += min(max(time - lastTime, 0), 0.1)
        while accumulator >= PixelEscapeGame.tickInterval, state == .playing {
            accumulator -= PixelEscapeGame.tickInterval
            game.tick()
            score = game.score
            if game.isOver {
                finish(at: time)
            }
        }
        render()
    }

    private func jump() {
        game.jump()
        jumpCount += 1
        runJumps += 1
        render()
    }

    private func finish(at time: TimeInterval) {
        state = .over
        crashTime = time
        canRestart = false
        isNewBest = score > best
        if score > 0 {
            scores.add(name: playerAlias() ?? "Watch", score: score)
        }
        best = max(best, score)
        onRunEnd(score, runJumps)
    }

    private func startRun() {
        game = PixelEscapeGame()
        state = .playing
        score = 0
        isNewBest = false
        isPaused = false
        canRestart = false
        accumulator = 0
        lastTime = nil
        crashTime = nil
        runJumps = 0
    }

    private func render() {
        var buffer = ConsoleBuffer()
        buffer.drawTunnel(game, glyph: preferences.avatar.glyph)
        console = buffer
    }
}
