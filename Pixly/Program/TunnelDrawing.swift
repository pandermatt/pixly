extension ConsoleBuffer {
    /// The playing field of `renderGame()` in main.c on rows 1–24, across the whole buffer: walls
    /// and tunnel, every red bar in view, the dotted trail and the pixel. Shared by the classic
    /// program and the watch.
    mutating func drawTunnel(_ game: ClassicGame, glyph: Character) {
        let columns = min(width, ClassicGame.horizon)
        for y in 1...24 {
            for x in 1...columns {
                set(x, y, Cell(character: " ", foreground: .black, background: game.isSolid(x: x, y: y) ? .black : .white))
            }
        }
        for bar in game.obstacles where bar.x <= columns {
            for y in bar.start..<bar.start + ClassicGame.obstacleHeight {
                set(bar.x, y, Cell(character: " ", foreground: .red, background: .red))
            }
        }
        for (index, row) in game.tail.enumerated() where (1...24).contains(row) && !game.isSolid(x: index + 1, y: row) {
            set(index + 1, row, Cell(character: ".", foreground: .black, background: .white))
        }
        if (1...24).contains(game.y) {
            set(ClassicGame.playerX, game.y, Cell(character: glyph, foreground: .black, background: .white))
        }
    }
}
