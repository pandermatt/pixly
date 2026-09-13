import SwiftUI

struct TitleBar: View {
    let title: String
    let canInterrupt: Bool
    let onInterrupt: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onInterrupt) {
                    Circle()
                        .fill(Theme.trafficRed)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(.black.opacity(0.55))
                                .opacity(canInterrupt ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canInterrupt)
                .accessibilityLabel("Quit program")
                Circle().fill(Theme.trafficYellow).frame(width: 12, height: 12)
                Circle().fill(Theme.trafficGreen).frame(width: 12, height: 12)
            }
            .frame(width: 64, alignment: .leading)

            Text(verbatim: title)
                .font(Theme.mono(12, weight: .medium))
                .foregroundStyle(theme.dim)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Group {
                if canInterrupt {
                    Button(action: onInterrupt) {
                        Text(verbatim: "⌃C").font(Theme.mono(13, weight: .bold)).foregroundStyle(theme.prompt)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Interrupt")
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
    }
}
