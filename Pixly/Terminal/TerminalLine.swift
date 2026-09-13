struct TerminalLine: Identifiable, Equatable, Sendable {
    enum Style: Sendable {
        case output, dim, accent, success, warning, error, art, command, answer
        /// A help entry: `label` is the command, `text` its description.
        case definition
    }

    let id: Int
    let text: String
    let style: Style
    /// The question in front of an `.answer` line, or the command of a `.definition`.
    var label: String? = nil
}
