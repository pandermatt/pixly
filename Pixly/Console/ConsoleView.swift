import SwiftUI

/// Where the 80×25 grid sits inside a view, keeping the 1:2 character cell of the Windows console.
struct ConsoleLayout: Equatable {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let origin: CGPoint

    init(size: CGSize, scale: CGFloat) {
        let fitted = min(size.width / CGFloat(ConsoleBuffer.columns), size.height / CGFloat(ConsoleBuffer.rows * 2))
        let width = max(1 / scale, (fitted * scale).rounded(.down) / scale)
        cellWidth = width
        cellHeight = width * 2
        origin = CGPoint(
            x: ((size.width - width * CGFloat(ConsoleBuffer.columns)) / 2 * scale).rounded() / scale,
            y: ((size.height - width * 2 * CGFloat(ConsoleBuffer.rows)) / 2 * scale).rounded() / scale
        )
    }

    var frame: CGRect {
        CGRect(x: origin.x, y: origin.y, width: cellWidth * CGFloat(ConsoleBuffer.columns), height: cellHeight * CGFloat(ConsoleBuffer.rows))
    }

    func rect(x: Int, y: Int, width: Int = 1) -> CGRect {
        CGRect(x: origin.x + CGFloat(x - 1) * cellWidth, y: origin.y + CGFloat(y - 1) * cellHeight, width: CGFloat(width) * cellWidth, height: cellHeight)
    }

    func cell(at point: CGPoint) -> (x: Int, y: Int)? {
        let x = Int(((point.x - origin.x) / cellWidth).rounded(.down)) + 1
        let y = Int(((point.y - origin.y) / cellHeight).rounded(.down)) + 1
        guard (1...ConsoleBuffer.columns).contains(x), (1...ConsoleBuffer.rows).contains(y) else { return nil }
        return (x, y)
    }
}

enum ConsoleRenderer {
    static func draw(_ buffer: ConsoleBuffer, layout: ConsoleLayout, theme: PixlyTheme, in context: inout GraphicsContext) {
        context.fill(Path(layout.frame), with: .color(theme.console(.black)))

        var backgrounds: [ConsoleColor: Path] = [:]
        for y in 1...ConsoleBuffer.rows {
            var x = 1
            while x <= ConsoleBuffer.columns {
                let background = buffer[x, y].background
                var end = x
                while end < ConsoleBuffer.columns, buffer[end + 1, y].background == background {
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
            for x in 1...ConsoleBuffer.columns {
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
