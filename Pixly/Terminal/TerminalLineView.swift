import SwiftUI

struct TerminalLineView: View {
    let line: TerminalLine
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .font(Theme.mono())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch line.style {
        case .command:
            PromptText(command: line.text)
        case .answer:
            PromptText(prompt: line.label ?? "", command: line.text, isQuestion: true)
        case .definition:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // A column exactly 16 monospaced characters wide, so descriptions wrap under themselves.
                Text(verbatim: String(repeating: " ", count: 16))
                    .overlay(alignment: .leading) {
                        Text(verbatim: "  " + (line.label ?? ""))
                            .foregroundStyle(theme.prompt)
                            .fixedSize()
                    }
                Text(verbatim: line.text)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .art:
            // Menlo has every block and box-drawing glyph at the same advance, so the letters line up.
            Text(verbatim: line.text)
                .font(.custom("Menlo", size: 13 * Theme.scale))
                .foregroundStyle(theme.art)
                .shadow(color: theme.art.opacity(theme.artGlow), radius: 5)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.vertical, 6)
        case .output:
            Text(verbatim: line.text.isEmpty ? " " : line.text).foregroundStyle(theme.text)
        case .dim:
            Text(verbatim: line.text).foregroundStyle(theme.dim)
        case .accent:
            Text(verbatim: line.text).foregroundStyle(theme.accent)
        case .success:
            Text(verbatim: line.text).foregroundStyle(theme.prompt)
        case .warning:
            Text(verbatim: line.text).foregroundStyle(theme.warning)
        case .error:
            Text(verbatim: line.text).foregroundStyle(theme.error)
        case .link:
            #if os(tvOS)
            // There's no browser on Apple TV to open it in.
            Text(verbatim: line.text)
                .underline()
                .foregroundStyle(theme.accent)
            #else
            if let url = URL(string: line.text) {
                Link(destination: url) {
                    Text(verbatim: line.text)
                        .underline()
                        .foregroundStyle(theme.accent)
                }
            }
            #endif
        case .palette:
            VStack(alignment: .leading, spacing: 0) {
                ForEach([0, 8], id: \.self) { start in
                    HStack(spacing: 0) {
                        ForEach(ConsoleColor.allCases[start..<start + 8], id: \.self) { color in
                            Rectangle()
                                .fill(theme.console(color))
                                .frame(width: 22, height: 14)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// The shell prompt (or a `settings` question) followed by what was typed.
struct PromptText: View {
    var prompt = TerminalSession.prompt
    let command: String
    var isQuestion = false
    var showsCursor = false
    var cursorVisible = true
    @Environment(\.theme) private var theme

    var body: some View {
        let label = isQuestion
            ? Text(verbatim: prompt).foregroundStyle(theme.accent)
            : Text(verbatim: prompt).foregroundStyle(theme.prompt).bold()
        let typed = Text(verbatim: command).foregroundStyle(theme.text)
        let cursor = Text(verbatim: showsCursor ? "█" : "").foregroundStyle(cursorVisible ? theme.prompt : .clear)
        Text("\(label) \(typed)\(cursor)")
    }
}

struct PromptLineView: View {
    let input: String
    var question: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
            PromptText(
                prompt: question ?? TerminalSession.prompt,
                command: input,
                isQuestion: question != nil,
                showsCursor: true,
                cursorVisible: visible
            )
        }
        .font(Theme.mono())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
