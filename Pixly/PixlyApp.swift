import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct PixlyApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var gameCenter = GameCenterManager()
    @State private var preferences = Preferences()

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                TerminalView()
            }
            .environment(gameCenter)
            .environment(preferences)
            #if os(macOS)
            .frame(minWidth: 760, minHeight: 520)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        #endif
    }
}

/// Applies the current (or previewed) theme to everything below it.
struct ThemedRoot<Content: View>: View {
    @Environment(Preferences.self) private var preferences
    @ViewBuilder let content: Content

    var body: some View {
        let theme = preferences.effectiveTheme.palette
        content
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.prompt)
            .animation(.smooth(duration: 0.35), value: preferences.effectiveTheme)
            .task { await preferences.restoreAppIcon() }
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationController.mask
    }
}

/// The original ran in an 80×25 console, so the program is locked to landscape on iPhone.
@MainActor
enum OrientationController {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    static func lockLandscape() {
        update(mask: .landscape, rotateTo: .landscape)
    }

    static func unlock() {
        update(mask: .allButUpsideDown, rotateTo: .portrait)
    }

    private static func update(mask: UIInterfaceOrientationMask, rotateTo orientation: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }
}
#else
/// Mac windows are resizable, so there is nothing to lock.
@MainActor
enum OrientationController {
    static func lockLandscape() {}
    static func unlock() {}
}
#endif
