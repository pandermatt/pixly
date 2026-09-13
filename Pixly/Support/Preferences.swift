import Foundation
import Observation

/// Changes the app icon. The system implementation lives in `AppIconSwitcher.swift`.
@MainActor
protocol AppIconSwitching {
    /// The icon the system reports, or `nil` when the platform doesn't remember one.
    var current: ThemeID? { get }
    func apply(_ icon: ThemeID) async -> Bool
}

/// Theme, avatar, app icon and scanline choices, stored in UserDefaults.
@Observable @MainActor
final class Preferences {
    private static let themeKey = "theme"
    private static let appIconKey = "appIcon"
    private static let avatarKey = "avatar"
    private static let scanlinesKey = "scanlines"
    private static let welcomeKey = "hasSeenWelcome"

    private(set) var theme: ThemeID
    private(set) var appIcon: ThemeID
    private(set) var avatar: Avatar
    /// CRT-style lines over the terminal and the game console.
    private(set) var scanlines: Bool
    private(set) var hasSeenWelcome: Bool
    /// Set while browsing the Theme menu, so the whole app recolours before the choice is made.
    var previewTheme: ThemeID?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let iconSwitcher: any AppIconSwitching

    init(defaults: UserDefaults = .standard, iconSwitcher: (any AppIconSwitching)? = nil) {
        let switcher = iconSwitcher ?? SystemAppIconSwitcher()
        self.defaults = defaults
        self.iconSwitcher = switcher
        theme = defaults.string(forKey: Self.themeKey).flatMap(ThemeID.init(rawValue:)) ?? .classic
        avatar = defaults.string(forKey: Self.avatarKey).flatMap(Avatar.init(rawValue:)) ?? .pixel
        scanlines = defaults.object(forKey: Self.scanlinesKey) as? Bool ?? false
        hasSeenWelcome = defaults.bool(forKey: Self.welcomeKey)
        appIcon = switcher.current ?? defaults.string(forKey: Self.appIconKey).flatMap(ThemeID.init(rawValue:)) ?? .classic
    }

    var effectiveTheme: ThemeID {
        previewTheme ?? theme
    }

    func setTheme(_ theme: ThemeID) {
        self.theme = theme
        previewTheme = nil
        defaults.set(theme.rawValue, forKey: Self.themeKey)
    }

    func setAvatar(_ avatar: Avatar) {
        self.avatar = avatar
        defaults.set(avatar.rawValue, forKey: Self.avatarKey)
    }

    func setScanlines(_ scanlines: Bool) {
        self.scanlines = scanlines
        defaults.set(scanlines, forKey: Self.scanlinesKey)
    }

    func markWelcomeSeen() {
        hasSeenWelcome = true
        defaults.set(true, forKey: Self.welcomeKey)
    }

    @discardableResult
    func setAppIcon(_ icon: ThemeID) async -> Bool {
        guard await iconSwitcher.apply(icon) else { return false }
        appIcon = icon
        defaults.set(icon.rawValue, forKey: Self.appIconKey)
        return true
    }

    /// macOS forgets a custom Dock icon when the app quits, so apply it again at launch.
    func restoreAppIcon() async {
        guard iconSwitcher.current == nil, appIcon != .classic else { return }
        _ = await iconSwitcher.apply(appIcon)
    }
}
