/// The 16 colours of the Windows console exposed by the original consoleio.h.
enum ConsoleColor: UInt8, Sendable, CaseIterable {
    case black, blue, green, cyan, red, magenta, brown, gray
    case darkGray, lightBlue, lightGreen, lightCyan, lightRed, lightMagenta, yellow, white
}

/// An 80×25 character console with the same gotoxy/textcolor/printf semantics the C game used.
/// Coordinates are 1-based, like consoleio.h. A wide screen can make it wider: the original's
/// 80-column screens are then centred, and the landscape fills the extra columns.
struct ConsoleBuffer: Equatable, Sendable {
    struct Cell: Equatable, Sendable {
        var character: Character = " "
        var foreground: ConsoleColor = .white
        var background: ConsoleColor = .black
    }

    static let columns = 80
    static let rows = 25

    /// The number of columns: 80 like the Windows console, or more on a wide screen.
    let width: Int
    private(set) var cells: [Cell]
    private(set) var cursorX = 1
    private(set) var cursorY = 1
    private(set) var foreground = ConsoleColor.white
    private(set) var background = ConsoleColor.black

    init(columns: Int = ConsoleBuffer.columns) {
        width = max(columns, Self.columns)
        cells = Array(repeating: Cell(), count: width * Self.rows)
    }

    /// Columns added on the left of the original 80, so its screens stay centred.
    var margin: Int {
        (width - Self.columns) / 2
    }

    /// `xPositionForCenteredText` from main.c.
    static func centeredX(_ text: String) -> Int {
        40 - text.count / 2
    }

    subscript(x: Int, y: Int) -> Cell {
        cells[(y - 1) * width + (x - 1)]
    }

    mutating func textcolor(_ foreground: ConsoleColor, _ background: ConsoleColor) {
        self.foreground = foreground
        self.background = background
    }

    /// A position on the original 80-column console (centred in a wider one).
    mutating func gotoxy(_ x: Int, _ y: Int) {
        cursorX = x + margin
        cursorY = y
    }

    /// A position counted from the left edge of the whole buffer, for rows that span a wide screen.
    mutating func gotoxy(fromLeft x: Int, _ y: Int) {
        cursorX = x
        cursorY = y
    }

    mutating func clrscr() {
        cells = Array(repeating: Cell(character: " ", foreground: foreground, background: background), count: width * Self.rows)
        cursorX = 1
        cursorY = 1
    }

    mutating func write(_ text: String) {
        for character in text {
            switch character {
            case "\n":
                cursorX = 1 + margin
                cursorY += 1
            case "\t":
                cursorX = ((cursorX - 1) / 8 + 1) * 8 + 1
            default:
                set(cursorX, cursorY, Cell(character: character, foreground: foreground, background: background))
                cursorX += 1
                if cursorX > width {
                    cursorX = 1
                    cursorY += 1
                }
            }
        }
    }

    mutating func set(_ x: Int, _ y: Int, _ cell: Cell) {
        guard (1...width).contains(x), (1...Self.rows).contains(y) else { return }
        cells[(y - 1) * width + (x - 1)] = cell
    }
}
