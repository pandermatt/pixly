import SwiftUI

struct TerminalLineView: View {
    let line: TerminalLine

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
        case .art:
            // Menlo has every block and box-drawing glyph at the same advance, so the letters line up.
            Text(verbatim: line.text)
                .font(.custom("Menlo", size: 13))
                .foregroundStyle(Theme.green)
                .shadow(color: Theme.green.opacity(0.55), radius: 5)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.vertical, 6)
        case .output:
            Text(verbatim: line.text.isEmpty ? " " : line.text).foregroundStyle(Theme.text)
        case .dim:
            Text(verbatim: line.text).foregroundStyle(Theme.dim)
        case .accent:
            Text(verbatim: line.text).foregroundStyle(Theme.cyan)
        case .success:
            Text(verbatim: line.text).foregroundStyle(Theme.green)
        case .warning:
            Text(verbatim: line.text).foregroundStyle(Theme.magenta)
        case .error:
            Text(verbatim: line.text).foregroundStyle(Theme.red)
        }
    }
}

struct PromptText: View {
    let command: String
    var showsCursor = false
    var cursorVisible = true

    var body: some View {
        let prompt = Text(verbatim: TerminalSession.prompt).foregroundStyle(Theme.green).bold()
        let typed = Text(verbatim: command).foregroundStyle(Theme.text)
        let cursor = Text(verbatim: showsCursor ? "█" : "").foregroundStyle(cursorVisible ? Theme.green : .clear)
        Text("\(prompt) \(typed)\(cursor)")
    }
}

struct PromptLineView: View {
    let input: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
            PromptText(command: input, showsCursor: true, cursorVisible: visible)
        }
        .font(Theme.mono())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
