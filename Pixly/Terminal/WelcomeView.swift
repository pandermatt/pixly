import SwiftUI

/// Apple-style welcome sheet, shown on first launch and with the `welcome` command.
struct WelcomeView: View {
    let onContinue: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 40) {
                    Text("Welcome to Pixly")
                        .font(.system(size: 34, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 64)

                    VStack(alignment: .leading, spacing: 26) {
                        feature(
                            "gamecontroller.fill",
                            title: "It's a game, not a terminal",
                            detail: "Pixly only looks like a command line. Underneath is an arcade game: steer one pixel through an endless tunnel."
                        )
                        #if os(macOS)
                        feature(
                            "space",
                            title: "Press space to jump",
                            detail: "Press the space bar to jump. Stay clear of the walls and the red bars."
                        )
                        #else
                        feature(
                            "hand.tap.fill",
                            title: "Tap to jump",
                            detail: "Tap anywhere on the screen to jump. Stay clear of the walls and the red bars."
                        )
                        #endif
                        feature(
                            "play.fill",
                            title: "Press start",
                            detail: "Start compiles the original C game and runs it. Your best scores go to Game Center."
                        )
                        feature(
                            "paintpalette.fill",
                            title: "Make it yours",
                            detail: "Pick a theme, avatar and app icon in Settings, or type `settings` in the terminal."
                        )
                    }
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(theme.buttonTint)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: 468)
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
        }
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
        .interactiveDismissDisabled()
    }

    private func feature(_ symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(theme.prompt)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
