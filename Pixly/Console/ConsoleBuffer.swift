/// The 16 colours of the Windows console exposed by the original consoleio.h.
enum ConsoleColor: UInt8, Sendable, CaseIterable {
    case black, blue, green, cyan, red, magenta, brown, gray
    case darkGray, lightBlue, lightGreen, lightCyan, lightRed, lightMagenta, yellow, white
}

/// An 80×25 character console with the same gotoxy/textcolor/printf semantics the C game used.
/// Coordinates are 1-based, like consoleio.h.
struct ConsoleBuffer: Equatable, Sendable {
    struct Cell: Equatable, Sendable {
        var character: Character = " "
        var foreground: ConsoleColor = .white
        var background: ConsoleColor = .black
    }

    static let columns = 80
    static let rows = 25

    private(set) var cells: [Cell]
    private(set) var cursorX = 1
    private(set) var cursorY = 1
    private(set) var foreground = ConsoleColor.white
    private(set) var background = ConsoleColor.black

    init() {
        cells = Array(repeating: Cell(), count: Self.columns * Self.rows)
    }

    /// `xPositionForCenteredText` from main.c.
    static func centeredX(_ text: String) -> Int {
        40 - text.count / 2
    }

    subscript(x: Int, y: Int) -> Cell {
        cells[(y - 1) * Self.columns + (x - 1)]
    }

    mutating func textcolor(_ foreground: ConsoleColor, _ background: ConsoleColor) {
        self.foreground = foreground
        self.background = background
    }

    mutating func gotoxy(_ x: Int, _ y: Int) {
        cursorX = x
        cursorY = y
    }

    mutating func clrscr() {
        cells = Array(repeating: Cell(character: " ", foreground: foreground, background: background), count: Self.columns * Self.rows)
        cursorX = 1
        cursorY = 1
    }

    mutating func write(_ text: String) {
        for character in text {
            switch character {
            case "\n":
                cursorX = 1
                cursorY += 1
            case "\t":
                cursorX = ((cursorX - 1) / 8 + 1) * 8 + 1
            default:
                set(cursorX, cursorY, Cell(character: character, foreground: foreground, background: background))
                cursorX += 1
                if cursorX > Self.columns {
                    cursorX = 1
                    cursorY += 1
                }
            }
        }
    }

    mutating func set(_ x: Int, _ y: Int, _ cell: Cell) {
        guard (1...Self.columns).contains(x), (1...Self.rows).contains(y) else { return }
        cells[(y - 1) * Self.columns + (x - 1)] = cell
    }
}
