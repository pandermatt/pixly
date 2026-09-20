import SwiftUI

/// Where the console grid sits inside a view, keeping the 1:2 character cell of the Windows console.
struct ConsoleLayout: Equatable {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let origin: CGPoint
    let columns: Int

    /// All 80 columns across the width and the first `rows` rows down the height, whatever shape
    /// that makes the cells: the watch stretches the tunnel over its tall screen.
    init(stretching size: CGSize, rows: Int = ConsoleBuffer.rows) {
        columns = ConsoleBuffer.columns
        cellWidth = size.width / CGFloat(columns)
        cellHeight = size.height / CGFloat(rows)
        origin = .zero
    }

    init(size: CGSize, scale: CGFloat, columns: Int = ConsoleBuffer.columns) {
        self.columns = columns
        let fitted = min(size.width / CGFloat(columns), size.height / CGFloat(ConsoleBuffer.rows * 2))
        let width = max(1 / scale, (fitted * scale).rounded(.down) / scale)
        cellWidth = width
        cellHeight = width * 2
        origin = CGPoint(
            x: ((size.width - width * CGFloat(columns)) / 2 * scale).rounded() / scale,
            y: ((size.height - width * 2 * CGFloat(ConsoleBuffer.rows)) / 2 * scale).rounded() / scale
        )
    }

    /// How many columns fit when the 25 rows fill the height: at least the original 80, at most
    /// as far as the game looks ahead. An even count keeps the original screens centred.
    static func columns(fitting size: CGSize) -> Int {
        guard size.width > 0, size.height > 0 else { return ConsoleBuffer.columns }
        let cellWidth = size.height / CGFloat(ConsoleBuffer.rows * 2)
        let fitting = Int((size.width / cellWidth).rounded(.down))
        let columns = min(max(fitting, ConsoleBuffer.columns), ClassicGame.horizon)
        return columns - columns % 2
    }

    var frame: CGRect {
        CGRect(x: origin.x, y: origin.y, width: cellWidth * CGFloat(columns), height: cellHeight * CGFloat(ConsoleBuffer.rows))
    }

    func rect(x: Int, y: Int, width: Int = 1) -> CGRect {
        CGRect(x: origin.x + CGFloat(x - 1) * cellWidth, y: origin.y + CGFloat(y - 1) * cellHeight, width: CGFloat(width) * cellWidth, height: cellHeight)
    }

    func cell(at point: CGPoint) -> (x: Int, y: Int)? {
        let x = Int(((point.x - origin.x) / cellWidth).rounded(.down)) + 1
        let y = Int(((point.y - origin.y) / cellHeight).rounded(.down)) + 1
        guard (1...columns).contains(x), (1...ConsoleBuffer.rows).contains(y) else { return nil }
        return (x, y)
    }
}

enum ConsoleRenderer {
    static func draw(_ buffer: ConsoleBuffer, layout: ConsoleLayout, theme: PixlyTheme, in context: inout GraphicsContext) {
        context.fill(Path(layout.frame), with: .color(theme.console(.black)))
        let columns = min(buffer.width, layout.columns)

        var backgrounds: [ConsoleColor: Path] = [:]
        for y in 1...ConsoleBuffer.rows {
            var x = 1
            while x <= columns {
                let background = buffer[x, y].background
                var end = x
                while end < columns, buffer[end + 1, y].background == background {
                    end += 1
                }
                if background != .black {
                    backgrounds[background, default: Path()].addRect(layout.rect(x: x, y: y, width: end - x + 1))
                }
                x = end + 1
            }
        }
        for (color, path) in backgrounds {
            context.fill(path, with: .color(theme.console(color)))
        }

        let font = Font.system(size: layout.cellWidth / 0.6, weight: .regular, design: .monospaced)
        for y in 1...ConsoleBuffer.rows {
            for x in 1...columns {
                let cell = buffer[x, y]
                guard cell.character != " " else { continue }
                let rect = layout.rect(x: x, y: y)
                let color = theme.ink(cell.foreground)
                switch cell.character {
                case "■":
                    context.fill(Path(CGRect(x: rect.minX, y: rect.midY - rect.width / 2, width: rect.width, height: rect.width)), with: .color(color))
                case ".":
                    let radius = max(rect.width * 0.14, 0.75)
                    context.fill(Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.minY + rect.height * 0.72 - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                case "_":
                    context.fill(Path(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.84, width: rect.width, height: max(rect.height * 0.06, 1))), with: .color(color))
                default:
                    context.draw(Text(String(cell.character)).font(font).foregroundStyle(color), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                }
            }
        }
    }
}
