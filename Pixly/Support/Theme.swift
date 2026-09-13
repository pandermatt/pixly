import SwiftUI

enum Theme {
    static let green = Color(red: 0.36, green: 0.95, blue: 0.55)
    static let buttonGreen = Color(red: 0.12, green: 0.55, blue: 0.28)
    static let text = Color.white.opacity(0.9)
    static let dim = Color.white.opacity(0.45)
    static let cyan = Color(red: 0.45, green: 0.8, blue: 1)
    static let magenta = Color(red: 0.85, green: 0.45, blue: 1)
    static let red = Color(red: 1, green: 0.42, blue: 0.4)
    static let trafficRed = Color(red: 1, green: 0.37, blue: 0.34)
    static let trafficYellow = Color(red: 1, green: 0.74, blue: 0.18)
    static let trafficGreen = Color(red: 0.16, green: 0.79, blue: 0.25)

    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Dark, slightly coloured ground so the Liquid Glass chrome has something to refract.
struct Backdrop: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .black, Color(red: 0.02, green: 0.12, blue: 0.07), .black,
                Color(red: 0.03, green: 0.06, blue: 0.14), Color(red: 0.02, green: 0.18, blue: 0.1), .black,
                .black, Color(red: 0.05, green: 0.05, blue: 0.12), .black,
            ]
        )
        .ignoresSafeArea()
    }
}

struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y = 0.0
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            context.fill(path, with: .color(.white.opacity(0.025)))
        }
        .allowsHitTesting(false)
    }
}
