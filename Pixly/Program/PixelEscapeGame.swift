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

    /// `land[z - 1]` is the lowest wall row at the top of column `z`.
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
    private var rng: SeededGenerator

    init(seed: UInt64 = .random(in: .min ... .max)) {
        rng = SeededGenerator(seed: seed)
        let blackZone = (25 - Self.whiteZone) / 2 + 1
        land = Array(repeating: blackZone - 1, count: Self.lastColumn)
    }

    var obstacleX: Int? {
        obstaclePosition >= 0 ? Self.lastColumn - obstaclePosition : nil
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
        for z in 1..<Self.lastColumn {
            land[z - 1] = land[z]
        }
        let last = land[Self.lastColumn - 1]
        if last == Self.landRange.lowerBound {
            land[Self.lastColumn - 1] = last + Int.random(in: 0...1, using: &rng)
        } else if last == Self.landRange.upperBound {
            land[Self.lastColumn - 1] = last - Int.random(in: 0...1, using: &rng)
        } else {
            land[Self.lastColumn - 1] = last + Int.random(in: -1...1, using: &rng)
        }
    }

    private mutating func moveObstacle() {
        obstaclePosition = (obstaclePosition + 1) % Self.lastColumn
        // The C code compared against LAST_LAND, which the modulo never reaches, so the bar
        // was stuck on rows 14–16. Pick a new start each pass as its comment intended (10–12).
        if obstaclePosition == 0 {
            obstacleStart = Int.random(in: 0..<Self.obstacleHeight, using: &rng) + 25 - Self.whiteZone
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
