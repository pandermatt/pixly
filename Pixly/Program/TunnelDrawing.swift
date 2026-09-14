extension ConsoleBuffer {
    /// The playing field of `renderGame()` in main.c on rows 1–24: walls and tunnel, the red bar,
    /// the dotted trail and the pixel. Shared by the classic program and the watch.
    mutating func drawTunnel(_ game: PixelEscapeGame, glyph: Character) {
        for y in 1...24 {
            for x in 1...Self.columns {
                set(x, y, Cell(character: " ", foreground: .black, background: game.isSolid(x: x, y: y) ? .black : .white))
            }
        }
        if let obstacleX = game.obstacleX {
            for y in game.obstacleStart..<game.obstacleStart + PixelEscapeGame.obstacleHeight {
                set(obstacleX, y, Cell(character: " ", foreground: .red, background: .red))
            }
        }
        for (index, row) in game.tail.enumerated() where (1...24).contains(row) && !game.isSolid(x: index + 1, y: row) {
            set(index + 1, row, Cell(character: ".", foreground: .black, background: .white))
        }
        if (1...24).contains(game.y) {
            set(PixelEscapeGame.playerX, game.y, Cell(character: glyph, foreground: .black, background: .white))
        }
    }
}
