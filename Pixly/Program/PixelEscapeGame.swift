/// Swift port of ball.c and landscape.c from the original Pixel Escape.
/// Coordinates are 1-based console cells; `tick()` is one 20 ms timer step of main.c.
struct PixelEscapeGame: Sendable {
    static let tickInterval = 0.020
    static let lastColumn = 80          // LAST_LAND
    static let whiteZone = 15           // WHITE_ZONE
    static let obstacleHeight = 3       // HINDERNISS_HEIGHT
    static let playerX = 5              // XPOS
    static let startY = 13
    static let landRange = 1...(24 - whiteZone)
    /// How far ahead the landscape and the bars are worked out. The game plays exactly as on the
    /// 80-column console; a wider screen only shows more of what is already on its way.
    static let horizon = 240

    /// `land[z - 1]` is the lowest wall row at the top of column `z`, up to the horizon.
    private(set) var land: [Int]
    private(set) var obstaclePosition = -1
    private(set) var obstacleStart = 14
    private(set) var y = startY
    private(set) var upDown = 0
    private(set) var control = 0
    private(set) var lastPosition = startY
    private(set) var tail = [Int](repeating: startY, count: 4)
    private(set) var score = 0
    private(set) var isOver = false
    /// Start rows of the bars still to come, the next one first.
    private var upcomingStarts: [Int] = []
    private var rng: SeededGenerator
    private var barRNG: SeededGenerator

    init(seed: UInt64 = .random(in: .min ... .max)) {
        rng = SeededGenerator(seed: seed)
        barRNG = SeededGenerator(seed: seed ^ 0x5DEE_CE66_D1CE_4E5B)
        let blackZone = (25 - Self.whiteZone) / 2 + 1
        land = Array(repeating: blackZone - 1, count: Self.lastColumn)
        // The original draws a new column only as it enters at 80; beyond that, the same random
        // walk is just done in advance.
        while land.count < Self.horizon {
            land.append(nextColumn(after: land[land.count - 1]))
        }
        fillUpcomingStarts()
    }

    var obstacleX: Int? {
        obstaclePosition >= 0 ? Self.lastColumn - obstaclePosition : nil
    }

    /// Every bar up to the horizon: the one the original console shows, and the ones on their way.
    /// The next bar enters at column 80 when the current one wraps, so it is 80 columns behind it.
    var obstacles: [(x: Int, start: Int)] {
        var bars: [(x: Int, start: Int)] = []
        if let obstacleX {
            bars.append((obstacleX, obstacleStart))
        }
        var x = (obstacleX ?? 1) + Self.lastColumn
        for start in upcomingStarts where x <= Self.horizon {
            bars.append((x, start))
            x += Self.lastColumn
        }
        return bars
    }

    func isSolid(x: Int, y: Int) -> Bool {
        let top = land[x - 1]
        return top >= y || top + Self.whiteZone + 1 <= y
    }

    func isObstacle(x: Int, y: Int) -> Bool {
        obstacleX == x && (obstacleStart..<obstacleStart + Self.obstacleHeight).contains(y)
    }

    /// `check()` from landscape.c.
    func collides(x: Int, y: Int) -> Bool {
        isObstacle(x: x, y: y) || isSolid(x: x, y: y)
    }

    mutating func jump() {
        guard !isOver else { return }
        y -= 1
        updateTail()
        upDown += 2
    }

    mutating func tick() {
        guard !isOver else { return }
        score += 2
        moveLandscape()
        if collides(x: Self.playerX, y: y) {
            isOver = true
        } else {
            moveDown()
        }
    }

    mutating func moveLandscape() {
        moveObstacle()
        land.removeFirst()
        land.append(nextColumn(after: land[land.count - 1]))
    }

    /// The random walk of the wall at the right edge, kept inside the console.
    private mutating func nextColumn(after last: Int) -> Int {
        if last == Self.landRange.lowerBound {
            return last + Int.random(in: 0...1, using: &rng)
        }
        if last == Self.landRange.upperBound {
            return last - Int.random(in: 0...1, using: &rng)
        }
        return last + Int.random(in: -1...1, using: &rng)
    }

    private mutating func moveObstacle() {
        obstaclePosition = (obstaclePosition + 1) % Self.lastColumn
        // The C code compared against LAST_LAND, which the modulo never reaches, so the bar
        // was stuck on rows 14–16. Pick a new start each pass as its comment intended (10–12).
        if obstaclePosition == 0 {
            obstacleStart = upcomingStarts.removeFirst()
            fillUpcomingStarts()
        }
    }

    /// Enough bars chosen ahead to fill the horizon (one enters every 80 columns).
    private mutating func fillUpcomingStarts() {
        while upcomingStarts.count < Self.horizon / Self.lastColumn + 1 {
            upcomingStarts.append(Int.random(in: 0..<Self.obstacleHeight, using: &barRNG) + 25 - Self.whiteZone)
        }
    }

    private mutating func moveDown() {
        control += 1
        guard control == 3 else { return }
        upDown -= 1
        if upDown > 0 {
            y -= 1
        } else if upDown < 0 {
            y += 1
        }
        updateTail()
        if upDown < 0 {
            upDown = 0
        }
        control = 0
    }

    /// `Tail()` from ball.c: remembers the last four distinct rows.
    private mutating func updateTail() {
        guard lastPosition != y else { return }
        tail.removeFirst()
        tail.append(lastPosition)
        lastPosition = y
    }
}
