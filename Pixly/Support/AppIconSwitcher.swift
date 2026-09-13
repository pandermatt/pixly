#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SystemAppIconSwitcher: AppIconSwitching {
    #if os(macOS)
    /// macOS has no alternate icons for the bundle; only the running app's Dock icon can change.
    var current: ThemeID? { nil }

    func apply(_ icon: ThemeID) async -> Bool {
        NSApp.applicationIconImage = icon.iconName.flatMap { NSImage(named: "Dock-\($0)") }
        return true
    }
    #elseif os(tvOS)
    /// tvOS apps have a single icon.
    var current: ThemeID? { nil }

    func apply(_ icon: ThemeID) async -> Bool {
        false
    }
    #else
    var current: ThemeID? {
        let name = UIApplication.shared.alternateIconName
        return ThemeID.allCases.first { $0.iconName == name } ?? .classic
    }

    func apply(_ icon: ThemeID) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        guard UIApplication.shared.alternateIconName != icon.iconName else { return true }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.iconName)
            return true
        } catch {
            return false
        }
    }
    #endif
}
