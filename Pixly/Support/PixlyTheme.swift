import SwiftUI

enum ThemeID: String, CaseIterable, Sendable {
    case classic, phosphor, amber, light

    var title: String {
        switch self {
        case .classic: "Classic"
        case .phosphor: "Phosphor"
        case .amber: "Amber"
        case .light: "Light"
        }
    }

    var palette: PixlyTheme {
        switch self {
        case .classic: .classic
        case .phosphor: .phosphor
        case .amber: .amber
        case .light: .light
        }
    }

    /// The alternate app icon for this theme; `nil` is the primary (Classic) icon.
    var iconName: String? {
        self == .classic ? nil : "AppIcon-\(title)"
    }
}

/// Every colour the app uses: the shell and window chrome, and the 16-colour console palette
/// that the game, menus and save-score window are drawn with.
struct PixlyTheme: Sendable {
    let colorScheme: ColorScheme
    let text: Color
    let dim: Color
    let prompt: Color
    let accent: Color
    let warning: Color
    let error: Color
    let art: Color
    let artGlow: Double
    let buttonTint: Color
    let windowBackground: Color
    let stroke: Color
    /// Nine colours for the 3×3 backdrop mesh.
    let backdrop: [Color]
    let scanlines: Color
    /// sRGB hex for each `ConsoleColor`, in raw-value order. Cell backgrounds, and text too unless
    /// `inkHex` is set.
    let consoleHex: [UInt32]
    /// Text colours, when they differ from the backgrounds: Light draws dark ink on light cells.
    var inkHex: [UInt32]? = nil

    func console(_ color: ConsoleColor) -> Color {
        Color(hex: consoleHex[Int(color.rawValue)])
    }

    func ink(_ color: ConsoleColor) -> Color {
        Color(hex: (inkHex ?? consoleHex)[Int(color.rawValue)])
    }
}

extension PixlyTheme {
    /// The Windows console the game was written for, with its yellow as the main colour.
    static let classic = PixlyTheme(
        colorScheme: .dark,
        text: Color(hex: 0xCCCCCC),
        dim: Color(hex: 0x767676),
        prompt: Color(hex: 0xF9F1A5),
        accent: Color(hex: 0x61D6D6),
        warning: Color(hex: 0xD670D6),
        error: Color(hex: 0xE74856),
        art: Color(hex: 0xF9F1A5),
        artGlow: 0.3,
        buttonTint: Color(hex: 0xA68200),
        windowBackground: Color(hex: 0x0C0C0C, opacity: 0.92),
        stroke: .white.opacity(0.1),
        backdrop: [
            .black, Color(hex: 0x14120A), .black,
            Color(hex: 0x0F0D05), Color(hex: 0x201B0B), .black,
            .black, Color(hex: 0x100E08), .black,
        ],
        scanlines: .white.opacity(0.03),
        consoleHex: [
            0x000000, 0x0038D9, 0x007A00, 0x3B96DE, 0x990F05, 0x871799, 0xC29C00, 0xBFBFBF,
            0x757575, 0x3B78FF, 0x17C70D, 0x61D6D6, 0xE84757, 0xB5009E, 0xFAF2A6, 0xFFFFFF,
        ]
    )

    /// Green phosphor CRT: the shell look Pixly started with, and a monochrome green console.
    static let phosphor = PixlyTheme(
        colorScheme: .dark,
        text: .white.opacity(0.9),
        dim: .white.opacity(0.45),
        prompt: Color(hex: 0x5CF28C),
        accent: Color(hex: 0x73CCFF),
        warning: Color(hex: 0xD973FF),
        error: Color(hex: 0xFF6B66),
        art: Color(hex: 0x5CF28C),
        artGlow: 0.55,
        buttonTint: Color(hex: 0x1F8C47),
        windowBackground: .black.opacity(0.8),
        stroke: .white.opacity(0.1),
        backdrop: [
            .black, Color(hex: 0x051F12), .black,
            Color(hex: 0x080F24), Color(hex: 0x052E1A), .black,
            .black, Color(hex: 0x0D0D1F), .black,
        ],
        scanlines: .white.opacity(0.025),
        consoleHex: [
            0x020A04, 0x0E3A1F, 0x0F5C2E, 0x3FBF6A, 0x0F6E36, 0x2FA85A, 0x7FD99A, 0x7FD99A,
            0x2E7A48, 0x2E7A48, 0x8DFFB0, 0x8DFFB0, 0x0A3A1C, 0x5CF28C, 0xB8FFCB, 0x5CF28C,
        ]
    )

    /// Amber monochrome terminal.
    static let amber = PixlyTheme(
        colorScheme: .dark,
        text: Color(hex: 0xFFB84D),
        dim: Color(hex: 0x9A7431),
        prompt: Color(hex: 0xFFB000),
        accent: Color(hex: 0xFFD27F),
        warning: Color(hex: 0xFF8A3D),
        error: Color(hex: 0xFF5A36),
        art: Color(hex: 0xFFB000),
        artGlow: 0.5,
        buttonTint: Color(hex: 0xB36B00),
        windowBackground: Color(hex: 0x0D0700, opacity: 0.85),
        stroke: Color(hex: 0xFFB000, opacity: 0.12),
        backdrop: [
            .black, Color(hex: 0x1A0E00), .black,
            Color(hex: 0x120A00), Color(hex: 0x2A1600), .black,
            .black, Color(hex: 0x140B02), .black,
        ],
        scanlines: Color(hex: 0xFFB000, opacity: 0.03),
        consoleHex: [
            0x0D0700, 0x5C3A00, 0x5C3A00, 0xB37A1A, 0xD1340F, 0xC2651A, 0xCC8A00, 0xCC9A4D,
            0x7A5424, 0x7A5424, 0xFFD27F, 0xFFD27F, 0x4A1E08, 0xFF9A3D, 0xFFE0A3, 0xFFB000,
        ]
    )

    /// Ink on paper: a white tunnel between light grey walls, with dark text on the light cells.
    static let light = PixlyTheme(
        colorScheme: .light,
        text: Color(hex: 0x1F1F1F),
        dim: Color(hex: 0x7A776F),
        prompt: Color(hex: 0x1E7A3C),
        accent: Color(hex: 0x1F5FBF),
        warning: Color(hex: 0x9C2BB0),
        error: Color(hex: 0xC4312B),
        art: Color(hex: 0x1E7A3C),
        artGlow: 0.15,
        buttonTint: Color(hex: 0x1E7A3C),
        windowBackground: Color(hex: 0xF4F1EA, opacity: 0.92),
        stroke: .black.opacity(0.1),
        backdrop: [
            Color(hex: 0xF7F5F0), Color(hex: 0xE6F0E8), Color(hex: 0xF7F5F0),
            Color(hex: 0xE9ECF5), Color(hex: 0xDDEEDD), Color(hex: 0xF7F5F0),
            Color(hex: 0xF7F5F0), Color(hex: 0xECEAF2), Color(hex: 0xF7F5F0),
        ],
        scanlines: .black.opacity(0.02),
        consoleHex: [
            0xE5E5E5, 0x9DB8E8, 0x7CC896, 0x9FD3E0, 0xE5483C, 0xD49BE0, 0xE3CB7A, 0xE9E6DF,
            0xC9C5BC, 0xBFD2F2, 0x9ED9B0, 0xB9E2EC, 0xF08A80, 0xE2B3EC, 0xF2E3A6, 0xFFFFFF,
        ],
        inkHex: [
            0x2B2A27, 0x1F5FBF, 0x1E7A3C, 0x1F7A8C, 0xE5483C, 0x9C2BB0, 0x8A6D00, 0x5E5A53,
            0x7A766E, 0x1F5FBF, 0x1E7A3C, 0x1F7A8C, 0xC4312B, 0x9C2BB0, 0x8A6D00, 0x1F1F1F,
        ]
    )
}

extension EnvironmentValues {
    @Entry var theme: PixlyTheme = .classic
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
