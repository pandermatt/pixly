import Foundation
import Observation
import QuartzCore

/// Runs Pixly 2.0: ticks the smooth engine, keeps the score table and the cosmetic particles.
@Observable @MainActor
final class SmoothProgram {
    struct Result: Equatable, Sendable {
        let score: Int
        let best: Int
        let isNewHighscore: Bool
    }

    /// World-space sparks for jumps and crashes.
    struct Particle: Sendable {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var life = 0.0
        let lifetime: Double
    }

    static let tick = 1.0 / 120
    static let scoreKey = "scores2"

    private(set) var game: SmoothEscapeGame
    private(set) var particles: [Particle] = []
    private(set) var isPaused = false
    private(set) var jumpCount = 0
    private(set) var result: Result?
    private(set) var scores: ScoreStore
    var name = ""

    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored var playerAlias: @MainActor () -> String? = { nil }
    @ObservationIgnored var onScore: @MainActor (Int) -> Void = { _ in }

    @ObservationIgnored private let startDate = Date()
    @ObservationIgnored private var aspect: Double
    @ObservationIgnored private var ticker: DisplayLinkTicker?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var isSaved = false
    @ObservationIgnored private var random = SystemRandomNumberGenerator()

    init(preferences: Preferences, defaults: UserDefaults = .standard, aspect: Double = 0.46) {
        self.preferences = preferences
        self.aspect = aspect
        game = SmoothEscapeGame(aspect: aspect)
        scores = ScoreStore(defaults: defaults, key: Self.scoreKey)
    }

    var runtime: TimeInterval {
        Date().timeIntervalSince(startDate)
    }

    var best: Int {
        max(scores.best, game.score)
    }

    func start() {
        guard ticker == nil else { return }
        let ticker = DisplayLinkTicker { [weak self] timestamp in
            self?.frame(timestamp)
        }
        self.ticker = ticker
        ticker.start()
    }

    func terminate() {
        ticker?.stop()
        ticker = nil
    }

    /// The playfield changed size: a run that hasn't started yet adapts to it.
    func resize(aspect newAspect: Double) {
        guard newAspect.isFinite, newAspect > 0, abs(newAspect - aspect) > 0.01 else { return }
        aspect = newAspect
        if game.state == .ready {
            game = SmoothEscapeGame(aspect: newAspect)
        }
    }

    func jump() {
        guard result == nil, game.state != .over else { return }
        if isPaused {
            isPaused = false
            lastTimestamp = nil
        }
        game.jump()
        jumpCount += 1
        burst(count: 5, speed: 0.3, angles: (.pi * 0.25)...(.pi * 0.75), lifetime: 0.2...0.4)
    }

    func pause() {
        guard game.state == .running, result == nil else { return }
        isPaused = true
    }

    func save() {
        guard let result, !isSaved else { return }
        scores.add(name: name, score: result.score)
        isSaved = true
    }

    func saveAndRetry() {
        save()
        retry()
    }

    func retry() {
        result = nil
        isSaved = false
        particles = []
        isPaused = false
        accumulator = 0
        lastTimestamp = nil
        game = SmoothEscapeGame(aspect: aspect)
    }

    /// One fixed 1/120 s step.
    func step() {
        if game.state != .over {
            game.update(dt: Self.tick)
        }
        updateParticles(dt: Self.tick)
        if game.state == .over, result == nil {
            finish()
        }
    }

    private func frame(_ timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard !isPaused, let lastTimestamp else { return }
        guard game.state != .over || !particles.isEmpty else { return }
        accumulator += min(timestamp - lastTimestamp, 0.1)
        while accumulator >= Self.tick {
            accumulator -= Self.tick
            step()
        }
    }

    private func finish() {
        let score = game.score
        let previousBest = scores.best
        result = Result(score: score, best: max(previousBest, score), isNewHighscore: score > previousBest)
        if let alias = playerAlias() {
            name = alias
        }
        onScore(score)
        burst(count: 28, speed: 0.7, angles: 0...(2 * .pi), lifetime: 0.35...0.8)
    }

    private func burst(count: Int, speed: Double, angles: ClosedRange<Double>, lifetime: ClosedRange<Double>) {
        for _ in 0..<count {
            let angle = Double.random(in: angles, using: &random)
            let magnitude = speed * Double.random(in: 0.35...1, using: &random)
            particles.append(Particle(
                x: game.playerWorldX,
                y: game.playerY,
                vx: cos(angle) * magnitude - 0.15,
                vy: sin(angle) * magnitude,
                lifetime: Double.random(in: lifetime, using: &random)
            ))
        }
        if particles.count > 120 {
            particles.removeFirst(particles.count - 120)
        }
    }

    private func updateParticles(dt: Double) {
        guard !particles.isEmpty else { return }
        for index in particles.indices {
            particles[index].x += particles[index].vx * dt
            particles[index].y += particles[index].vy * dt
            particles[index].vy += 1.6 * dt
            particles[index].life += dt
        }
        particles.removeAll { $0.life >= $0.lifetime }
    }
}
