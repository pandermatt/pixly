import Testing
@testable import Pixly

struct PixelEscapeGameTests {
    @Test func startsLikeTheOriginal() {
        let game = PixelEscapeGame(seed: 1)
        #expect(game.land.count == PixelEscapeGame.horizon)
        #expect(game.land.prefix(80).allSatisfy { $0 == 5 })
        #expect(game.y == 13)
        #expect(game.tail == [13, 13, 13, 13])
        #expect(game.score == 0)
        #expect(game.obstacleX == nil)
    }

    @Test func wallsMatchCheckFromLandscapeC() {
        let game = PixelEscapeGame(seed: 1)
        #expect(game.isSolid(x: 5, y: 5))
        #expect(!game.isSolid(x: 5, y: 6))
        #expect(!game.isSolid(x: 5, y: 20))
        #expect(game.isSolid(x: 5, y: 21))
    }

    @Test func tickScoresTwoAndBringsInTheObstacle() {
        var game = PixelEscapeGame(seed: 1)
        game.tick()
        #expect(game.score == 2)
        #expect(game.obstacleX == 80)
        #expect((10...12).contains(game.obstacleStart))
    }

    @Test func fallsOneRowEveryThirdTick() {
        var game = PixelEscapeGame(seed: 1)
        game.tick()
        game.tick()
        #expect(game.y == 13)
        game.tick()
        #expect(game.y == 14)
        for _ in 0..<3 { game.tick() }
        #expect(game.y == 15)
    }

    @Test func jumpRisesImmediatelyThenOnceMoreBeforeFalling() {
        var game = PixelEscapeGame(seed: 1)
        game.jump()
        #expect(game.y == 12)
        for _ in 0..<3 { game.tick() }
        #expect(game.y == 11)
        #expect(game.tail == [13, 13, 13, 12])
        for _ in 0..<3 { game.tick() }
        #expect(game.y == 11)
        for _ in 0..<3 { game.tick() }
        #expect(game.y == 12)
    }

    @Test func landscapeStaysInsideTheConsole() {
        var game = PixelEscapeGame(seed: 42)
        var valid = true
        for _ in 0..<20_000 {
            game.moveLandscape()
            let inRange = game.land.allSatisfy { PixelEscapeGame.landRange.contains($0) }
            if !inRange || abs(game.land[79] - game.land[78]) > 1 {
                valid = false
                break
            }
        }
        #expect(valid)
    }

    @Test func obstacleWrapsEveryEightyColumnsInsideTheSafeZone() {
        var game = PixelEscapeGame(seed: 7)
        var valid = true
        for step in 0..<800 {
            game.moveLandscape()
            let rows = game.obstacleStart..<game.obstacleStart + PixelEscapeGame.obstacleHeight
            if game.obstacleX != 80 - step % 80 || rows.contains(where: { game.isSolid(x: game.obstacleX!, y: $0) }) {
                valid = false
                break
            }
        }
        #expect(valid)
    }

    @Test func notJumpingEndsTheGame() {
        var game = PixelEscapeGame(seed: 3)
        var ticks = 0
        while !game.isOver, ticks < 1000 {
            game.tick()
            ticks += 1
        }
        #expect(game.isOver)
        #expect(game.score == ticks * 2)
    }

    @Test func theLandscapeAheadIsWhatScrollsIntoView() {
        var game = PixelEscapeGame(seed: 5)
        let ahead = Array(game.land[80..<120])
        for _ in 0..<40 {
            game.moveLandscape()
        }
        #expect(Array(game.land[40..<80]) == ahead)
    }

    @Test func barsOnTheirWayArriveAtColumnEightyAsPlanned() {
        var game = PixelEscapeGame(seed: 5)
        let coming = game.obstacles
        #expect(coming.map(\.x) == [81, 161])

        game.moveLandscape()
        #expect(game.obstacleX == 80)
        #expect(game.obstacleStart == coming[0].start)
        #expect(game.obstacles.map(\.x) == [80, 160, 240])

        for _ in 0..<80 {
            game.moveLandscape()
        }
        #expect(game.obstacleX == 80)
        #expect(game.obstacleStart == coming[1].start)
    }

    @Test func sameSeedSameLandscape() {
        var a = PixelEscapeGame(seed: 9)
        var b = PixelEscapeGame(seed: 9)
        for _ in 0..<500 {
            a.moveLandscape()
            b.moveLandscape()
        }
        #expect(a.land == b.land)
        #expect(a.obstacleStart == b.obstacleStart)
    }
}
