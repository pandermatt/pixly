import Foundation

/// Pixly 2.0: the same escape with continuous physics. The pixel and the scrolling are smooth,
/// but the walls keep the original's stepped look: flat columns with right-angled risers.
/// Lengths are in playfield heights (the playfield is `aspect` wide and 1 tall, y grows
/// downwards), times in seconds.
struct SmoothEscapeGame: Sendable {
    enum State: Equatable, Sendable {
        case ready, running, over
    }

    struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    struct Bar: Equatable, Sendable {
        /// A whole column, like the original's red bar.
        static let width = SmoothEscapeGame.columnWidth
        /// World x of the left edge.
        var x: Double
        var top: Double
        var bottom: Double
    }

    private struct Control: Sendable {
        var center: Double
        var gap: Double
    }

    static let gravity = 3.2
    static let jumpVelocity = 0.95
    static let maxFallSpeed = 1.3
    static let radius = 0.018
    /// Where the pixel flies, as a fraction of the playfield width.
    static let playerX = 0.22
    static let startGap = 0.62
    static let minGap = 0.40
    static let minPassage = 0.20
    /// Width of one wall step: half a row, so the blocks have the 1:2 cells of the original console
    /// and neighbouring blocks step at different heights, as finely jagged as its landscape.
    static let columnWidth = 0.025
    /// Walls and bars snap to 20 rows.
    static let rowHeight = 1.0 / 20
    private static let controlSpacing = 0.25
    /// At least a row, so a column's wobble never pushes the tunnel off the screen.
    private static let wallMargin = 0.06
    private static let trailLength = 12

    let aspect: Double
    private(set) var state = State.ready
    /// World x at the left edge of the screen.
    private(set) var distance = 0.0
    private(set) var playerY = 0.5
    private(set) var velocity = 0.0
    private(set) var trail: [Point] = []
    private(set) var bars: [Bar] = []

    private let straightLength: Double
    private let seed: UInt64
    private var controls: [Control] = []
    private var nextBarX: Double
    private var rng: SeededGenerator
    private var readyTime = 0.0
    private var trailClock = 0.0

    init(aspect: Double, seed: UInt64 = .random(in: .min ... .max)) {
        let aspect = max(aspect, 0.3)
        self.aspect = aspect
        straightLength = aspect + 0.5
        nextBarX = aspect + 0.9
        self.seed = seed
        rng = SeededGenerator(seed: seed)
        generate(through: aspect + 1)
    }

    var score: Int {
        Int(distance / 0.01)
    }

    /// Scroll speed in playfield heights per second.
    var speed: Double {
        min(0.75, 0.42 + distance * 0.005)
    }

    var playerWorldX: Double {
        distance + aspect * Self.playerX
    }

    /// The lowest wall point above x: constant across a column and snapped to the row grid.
    func top(at x: Double) -> Double {
        let column = Self.columnStart(x)
        let sample = sample(column + Self.columnWidth / 2)
        return max(0, Self.snap(sample.center - sample.gap / 2) + wobble(column))
    }

    /// The highest wall point below x, stepped like `top(at:)`.
    func bottom(at x: Double) -> Double {
        let column = Self.columnStart(x)
        let sample = sample(column + Self.columnWidth / 2)
        return min(1, Self.snap(sample.center + sample.gap / 2) + wobble(column))
    }

    /// Like the original's landscape, the tunnel shifts a row from column to column (both walls
    /// together), which gives the edges their blocky look. Never more than one row between
    /// neighbours, and none in the straight start.
    private func wobble(_ column: Double) -> Double {
        guard column > straightLength else { return 0 }
        // Runs of one to four columns share a height, like the random walk of the original's
        // landscape; a new height every column would look like a comb.
        var index = Int64((column / Self.columnWidth).rounded())
        for _ in 0..<3 where random(index, salt: 0x9E37_79B9_7F4A_7C15) == 0 {
            index -= 1
        }
        return Double(random(index, salt: 0xD1B5_4A32_D192_ED03)) * Self.rowHeight
    }

    /// 0 or 1, the same every time for this column (and this seed).
    private func random(_ index: Int64, salt: UInt64) -> Int {
        var generator = SeededGenerator(seed: seed ^ (UInt64(bitPattern: index) &* salt))
        return Int.random(in: 0...1, using: &generator)
    }

    /// The epsilon keeps an x that is exactly on a column boundary (e.g. 142.85) from rounding
    /// down into the previous column.
    static func columnStart(_ x: Double) -> Double {
        (x / columnWidth + 1e-9).rounded(.down) * columnWidth
    }

    private static func snap(_ y: Double) -> Double {
        (y / rowHeight).rounded() * rowHeight
    }

    mutating func jump() {
        guard state != .over else { return }
        state = .running
        velocity = -Self.jumpVelocity
    }

    mutating func update(dt: Double) {
        switch state {
        case .ready:
            readyTime += dt
            playerY = 0.5 + sin(readyTime * 4) * 0.02
        case .running:
            velocity = min(velocity + Self.gravity * dt, Self.maxFallSpeed)
            playerY += velocity * dt
            distance += speed * dt
            generate(through: distance + aspect + 1)
            bars.removeAll { $0.x + Bar.width < distance - 0.2 }
            trailClock += dt
            if trailClock >= 1.0 / 30 {
                trailClock = 0
                trail.append(Point(x: playerWorldX, y: playerY))
                if trail.count > Self.trailLength {
                    trail.removeFirst()
                }
            }
            if isColliding {
                state = .over
            }
        case .over:
            break
        }
    }

    /// Builds the tunnel and bars up to world x; `update` does this while scrolling.
    mutating func generate(through x: Double) {
        while Double(controls.count - 3) * Self.controlSpacing < x {
            addControl()
        }
        while nextBarX < x {
            addBar(at: nextBarX)
            nextBarX += Double.random(in: 0.9...1.4, using: &rng)
        }
    }

    var isColliding: Bool {
        let x = playerWorldX
        let r = Self.radius
        if playerY - r < 0 || playerY + r > 1 {
            return true
        }
        for dx in [-r, 0, r] where playerY - r < top(at: x + dx) || playerY + r > bottom(at: x + dx) {
            return true
        }
        for bar in bars where bar.x - r <= x && x <= bar.x + Bar.width + r {
            let nearestX = min(max(x, bar.x), bar.x + Bar.width)
            let nearestY = min(max(playerY, bar.top), bar.bottom)
            if hypot(x - nearestX, playerY - nearestY) < r {
                return true
            }
        }
        return false
    }

    /// Catmull-Rom through the control centres; the walls then step along this curve.
    private func sample(_ x: Double) -> Control {
        let position = max(0, x / Self.controlSpacing)
        let last = controls.count - 1
        let i = min(Int(position), last - 1)
        let t = min(max(position - Double(i), 0), 1)
        func center(_ k: Int) -> Double {
            controls[min(max(k, 0), last)].center
        }
        let p0 = center(i - 1), p1 = center(i), p2 = center(i + 1), p3 = center(i + 2)
        let t2 = t * t
        let t3 = t2 * t
        let c = 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
        let gap = controls[i].gap + (controls[i + 1].gap - controls[i].gap) * t
        return Control(center: c, gap: gap)
    }

    private mutating func addControl() {
        let x = Double(controls.count) * Self.controlSpacing
        let gap = max(Self.minGap, Self.startGap - 0.0065 * max(0, x - straightLength))
        guard x > straightLength, let previous = controls.last else {
            controls.append(Control(center: 0.5, gap: gap))
            return
        }
        let limit = gap / 2 + Self.wallMargin
        let center = min(max(previous.center + Double.random(in: -0.09...0.09, using: &rng), limit), 1 - limit)
        controls.append(Control(center: center, gap: gap))
    }

    /// A bar sits in the middle of one column, on the row grid, and always leaves a passage.
    private mutating func addBar(at x: Double) {
        let column = Self.columnStart(x)
        let ceiling = self.top(at: column + Self.columnWidth / 2)
        let floor = self.bottom(at: column + Self.columnWidth / 2)
        // Two or three rows: with smooth jumps, holding one height is harder than in the original.
        for rows in [Int.random(in: 2...3, using: &rng), 2] {
            let height = Double(rows) * Self.rowHeight
            let candidates = stride(from: ceiling, through: floor - height + 1e-9, by: Self.rowHeight).filter { barTop in
                barTop - ceiling >= Self.minPassage - 1e-9 || floor - (barTop + height) >= Self.minPassage - 1e-9
            }
            if let barTop = candidates.randomElement(using: &rng) {
                bars.append(Bar(x: column + (Self.columnWidth - Bar.width) / 2, top: barTop, bottom: barTop + height))
                return
            }
        }
    }
}
