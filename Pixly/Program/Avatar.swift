/// Avatars drawn with CP437 glyphs, as in the original's "Avatar wechseln" menu.
enum Avatar: String, CaseIterable, Sendable {
    case pixel, heart, diamond

    var glyph: Character {
        switch self {
        case .pixel: "■"
        case .heart: "♥\u{FE0E}"
        case .diamond: "♦\u{FE0E}"
        }
    }

    var title: String {
        switch self {
        case .pixel: "Pixel"
        case .heart: "Heart"
        case .diamond: "Diamond"
        }
    }

    /// How Pixly 2.0 draws the avatar: the pixel stays a square, the others become emoji.
    var emoji: String? {
        switch self {
        case .pixel: nil
        case .heart: "❤️"
        case .diamond: "💎"
        }
    }
}
