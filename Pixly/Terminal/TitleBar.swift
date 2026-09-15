import SwiftUI

struct TitleBar: View {
    let title: String
    let canInterrupt: Bool
    let onInterrupt: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        // The title stays in the middle of the bar; the pixel and ⌃C sit on top of its edges,
        // so it doesn't move when ⌃C comes and goes.
        Text(verbatim: title)
            .font(Theme.mono(12, weight: .medium))
            .foregroundStyle(theme.dim)
            .lineLimit(1)
            .padding(.horizontal, 44)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                // Pixly's own pixel rather than window buttons: this is a game, not a Mac window.
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(theme.prompt)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .trailing) {
                if canInterrupt {
                    Button(action: onInterrupt) {
                        Text(verbatim: "⌃C").font(Theme.mono(13, weight: .bold)).foregroundStyle(theme.prompt)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Interrupt")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .glassEffect(.regular, in: .capsule)
    }
}
