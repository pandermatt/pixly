import SwiftUI

extension ConsoleColor {
    var color: Color {
        switch self {
        case .black: Color(red: 0, green: 0, blue: 0)
        case .blue: Color(red: 0, green: 0.22, blue: 0.85)
        case .green: Color(red: 0, green: 0.48, blue: 0)
        case .cyan: Color(red: 0.23, green: 0.59, blue: 0.87)
        case .red: Color(red: 0.6, green: 0.06, blue: 0.02)
        case .magenta: Color(red: 0.53, green: 0.09, blue: 0.6)
        case .brown: Color(red: 0.76, green: 0.61, blue: 0)
        case .gray: Color(red: 0.75, green: 0.75, blue: 0.75)
        case .darkGray: Color(red: 0.46, green: 0.46, blue: 0.46)
        case .lightBlue: Color(red: 0.23, green: 0.47, blue: 1)
        case .lightGreen: Color(red: 0.09, green: 0.78, blue: 0.05)
        case .lightCyan: Color(red: 0.38, green: 0.84, blue: 0.84)
        case .lightRed: Color(red: 0.91, green: 0.28, blue: 0.34)
        case .lightMagenta: Color(red: 0.71, green: 0, blue: 0.62)
        case .yellow: Color(red: 0.98, green: 0.95, blue: 0.65)
        case .white: Color(red: 1, green: 1, blue: 1)
        }
    }
}

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
    static func draw(_ buffer: ConsoleBuffer, layout: ConsoleLayout, in context: inout GraphicsContext) {
        context.fill(Path(layout.frame), with: .color(.black))

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
            context.fill(path, with: .color(color.color))
        }

        let font = Font.system(size: layout.cellWidth / 0.6, weight: .regular, design: .monospaced)
        for y in 1...ConsoleBuffer.rows {
            for x in 1...ConsoleBuffer.columns {
                let cell = buffer[x, y]
                guard cell.character != " " else { continue }
                let rect = layout.rect(x: x, y: y)
                let shading = GraphicsContext.Shading.color(cell.foreground.color)
                switch cell.character {
                case "■":
                    context.fill(Path(CGRect(x: rect.minX, y: rect.midY - rect.width / 2, width: rect.width, height: rect.width)), with: shading)
                case ".":
                    let radius = max(rect.width * 0.14, 0.75)
                    context.fill(Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.minY + rect.height * 0.72 - radius, width: radius * 2, height: radius * 2)), with: shading)
                case "_":
                    context.fill(Path(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.84, width: rect.width, height: max(rect.height * 0.06, 1))), with: shading)
                default:
                    context.draw(Text(String(cell.character)).font(font).foregroundStyle(cell.foreground.color), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                }
            }
        }
    }
}
