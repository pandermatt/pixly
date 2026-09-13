struct TerminalLine: Identifiable, Equatable, Sendable {
    enum Style: Sendable {
        case output, dim, accent, success, warning, error, art, command
    }

    let id: Int
    let text: String
    let style: Style
}
