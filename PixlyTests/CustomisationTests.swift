import Foundation
import Testing
@testable import Pixly

@MainActor
final class FakeIconSwitcher: AppIconSwitching {
    var current: ThemeID?
    var isSupported = true
    private(set) var applied: [ThemeID] = []

    init(current: ThemeID? = .classic) {
        self.current = current
    }

    func apply(_ icon: ThemeID) async -> Bool {
        guard isSupported else { return false }
        applied.append(icon)
        current = icon
        return true
    }
}

@MainActor
struct PreferencesTests {
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "pixly-preferences-\(UUID().uuidString)"))
    }

    @Test func choicesPersist() async throws {
        let defaults = try makeDefaults()
        defaults.set("heart", forKey: "avatar")
        let icons = FakeIconSwitcher(current: nil)
        let preferences = Preferences(defaults: defaults, iconSwitcher: icons)
        #expect(preferences.theme == .classic)
        #expect(preferences.avatar == .heart)
        #expect(preferences.appIcon == .classic)
        #expect(!preferences.scanlines)

        preferences.previewTheme = .light
        #expect(preferences.effectiveTheme == .light)
        preferences.setTheme(.amber)
        #expect(preferences.previewTheme == nil)
        #expect(preferences.effectiveTheme == .amber)
        preferences.setScanlines(true)
        #expect(await preferences.setAppIcon(.light))
        #expect(icons.applied == [.light])

        let reloaded = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher(current: nil))
        #expect(reloaded.theme == .amber)
        #expect(reloaded.appIcon == .light)
        #expect(reloaded.avatar == .heart)
        #expect(reloaded.scanlines)
    }

    @Test func aRemovedAvatarFallsBackToPixel() throws {
        let defaults = try makeDefaults()
        defaults.set("smiley", forKey: "avatar")
        #expect(Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher()).avatar == .pixel)
    }

    @Test func welcomeIsShownOnce() throws {
        let defaults = try makeDefaults()
        let preferences = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher())
        #expect(!preferences.hasSeenWelcome)
        preferences.markWelcomeSeen()
        #expect(Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher()).hasSeenWelcome)
    }

    @Test func theSystemIconWinsOverTheStoredChoice() throws {
        let defaults = try makeDefaults()
        defaults.set("amber", forKey: "appIcon")
        let preferences = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher(current: .classic))
        #expect(preferences.appIcon == .classic)
    }

    @Test func anUnsupportedIconIsNotStored() async throws {
        let icons = FakeIconSwitcher()
        icons.isSupported = false
        let preferences = Preferences(defaults: try makeDefaults(), iconSwitcher: icons)
        #expect(await preferences.setAppIcon(.amber) == false)
        #expect(preferences.appIcon == .classic)
    }
}

struct PixlyThemeTests {
    @Test(arguments: ThemeID.allCases)
    func paletteKeepsTheGameReadable(_ id: ThemeID) {
        let theme = id.palette
        #expect(theme.consoleHex.count == ConsoleColor.allCases.count)
        #expect(theme.backdrop.count == 9)
        func hex(_ color: ConsoleColor) -> UInt32 { theme.consoleHex[Int(color.rawValue)] }
        // Tunnel against walls, and menu text against the background.
        #expect(contrast(hex(.white), hex(.black)) >= 4.5)
        // The red bar against the tunnel.
        #expect(contrast(hex(.red), hex(.white)) >= 2.5)
        // Text on the save-score bars.
        #expect(contrast(hex(.white), hex(.green)) >= 3)
        #expect(contrast(hex(.white), hex(.lightRed)) >= 3)
        // The selected menu entry stands out from the others.
        #expect(contrast(hex(.darkGray), hex(.black)) < contrast(hex(.white), hex(.black)))
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (first, second) = (luminance(a), luminance(b))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

@MainActor
struct SettingsMenuTests {
    private func makeProgram(icons: FakeIconSwitcher) throws -> PixlyProgram {
        let defaults = try #require(UserDefaults(suiteName: "pixly-settings-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults, iconSwitcher: icons)
        return PixlyProgram(preferences: preferences, defaults: defaults, loadingStep: .zero)
    }

    private func row(_ y: Int, of program: PixlyProgram) -> String {
        (1...80).map { String(program.console[$0, y].character) }.joined().trimmingCharacters(in: .whitespaces)
    }

    @Test func settingsSitsInTheMainMenu() async throws {
        let program = try makeProgram(icons: FakeIconSwitcher())
        await program.run()
        #expect(row(13, of: program) == "Settings")
        program.press(at: (x: 40, y: 13))
        #expect(program.screen == .settings)
        #expect(row(11, of: program) == "> Theme: Classic <")
        #expect(row(12, of: program) == "App Icon: Classic")
        #expect(row(13, of: program) == "Scanlines: Off")
        program.handle(.escape)
        #expect(program.screen == .menu)
        #expect(program.selection == 4)
    }

    @Test func scanlinesToggleInPlace() async throws {
        let program = try makeProgram(icons: FakeIconSwitcher())
        await program.run()
        program.press(at: (x: 40, y: 13))
        program.press(at: (x: 40, y: 13))
        #expect(program.screen == .settings)
        #expect(program.preferences.scanlines)
        #expect(row(13, of: program) == "> Scanlines: On <")
    }

    @Test func themeMenuPreviewsThenCommits() async throws {
        let program = try makeProgram(icons: FakeIconSwitcher())
        let preferences = program.preferences
        await program.run()
        program.moveSelection(3)
        program.handle(.enter)
        program.handle(.enter)
        #expect(program.screen == .theme)
        #expect(program.selection == 1)
        #expect(program.console[43, 7].background == .red)

        program.handle(.down)
        #expect(preferences.previewTheme == .phosphor)
        #expect(preferences.theme == .classic)
        program.moveSelection(10)
        #expect(preferences.previewTheme == nil)
        program.handle(.escape)
        #expect(program.screen == .settings)
        #expect(preferences.previewTheme == nil)

        program.handle(.enter)
        program.handle(.down)
        program.handle(.down)
        program.handle(.down)
        program.handle(.space)
        #expect(preferences.theme == .light)
        #expect(preferences.previewTheme == nil)
        #expect(program.screen == .settings)
        #expect(row(11, of: program) == "> Theme: Light <")
    }

    @Test func appIconMenuSwitchesTheIcon() async throws {
        let icons = FakeIconSwitcher()
        let program = try makeProgram(icons: icons)
        await program.run()
        program.moveSelection(3)
        program.handle(.enter)
        program.handle(.down)
        program.handle(.enter)
        #expect(program.screen == .appIcon)
        #expect(program.selection == 1)

        program.handle(.down)
        program.handle(.down)
        program.handle(.enter)
        await program.iconTask?.value
        #expect(icons.applied == [.amber])
        #expect(program.preferences.appIcon == .amber)
        #expect(row(19, of: program) == "App icon set to Amber")
        #expect(row(14, of: program) == "> Amber (current) <")
    }

    @Test func quittingMidPreviewRestoresTheTheme() async throws {
        let program = try makeProgram(icons: FakeIconSwitcher())
        await program.run()
        program.moveSelection(3)
        program.handle(.enter)
        program.handle(.enter)
        program.handle(.down)
        #expect(program.preferences.effectiveTheme == .phosphor)
        program.terminate()
        #expect(program.preferences.effectiveTheme == .classic)
    }
}
