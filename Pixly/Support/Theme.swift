import SwiftUI

/// Fixed styling; colours come from `PixlyTheme` in the environment.
enum Theme {
    static let trafficRed = Color(red: 1, green: 0.37, blue: 0.34)
    static let trafficYellow = Color(red: 1, green: 0.74, blue: 0.18)
    static let trafficGreen = Color(red: 0.16, green: 0.79, blue: 0.25)

    /// Sizes are for a phone or a desk; a TV is watched from the couch.
    #if os(tvOS)
    static let scale: CGFloat = 2
    #else
    static let scale: CGFloat = 1
    #endif

    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight, design: .monospaced)
    }
}

/// Softly coloured ground so the Liquid Glass chrome has something to refract.
struct Backdrop: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: theme.backdrop
        )
        .ignoresSafeArea()
    }
}

/// Thin horizontal CRT lines; `color` defaults to the theme's shell scanlines.
struct Scanlines: View {
    var color: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        let color = color ?? theme.scanlines
        Canvas { context, size in
            var path = Path()
            var y = 0.0
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}
