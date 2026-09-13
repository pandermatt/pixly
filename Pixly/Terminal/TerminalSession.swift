import Foundation
import Observation

/// The simulated zsh session around the C program: scrollback, typing and commands.
@Observable @MainActor
final class TerminalSession {
    enum Mode: Equatable, Sendable {
        case booting, shell, compiling, program
    }

    nonisolated static let prompt = "player@pixly ~ %"
    nonisolated static let commands = [
        "./pixly", "avatar", "cat", "clear", "credits", "echo", "exit", "gcc", "help", "highscore", "icon",
        "leaderboard", "ls", "make", "scanlines", "settings", "start", "sudo", "theme", "welcome", "whoami",
    ]
    private static let maxLines = 500

    private(set) var lines: [TerminalLine] = []
    private(set) var mode = Mode.booting
    private(set) var isTyping = false
    /// A question waiting for an answer (the `settings` prompts), shown instead of the prompt.
    private(set) var question: String?
    /// A command is still running (e.g. between `settings` questions).
    private(set) var isExecuting = false
    var input = ""

    /// Whether the keyboard can type into the prompt line.
    var acceptsInput: Bool { mode == .shell && !isTyping }
    /// Whether something is running, so buttons that start another command are disabled.
    var isBusy: Bool { !acceptsInput || question != nil || isExecuting }
    var showsPrompt: Bool { mode == .shell || isTyping }

    @ObservationIgnored var preferences: Preferences?
    @ObservationIgnored var playerName: @MainActor () -> String = { "player" }
    @ObservationIgnored var onOpenLeaderboard: @MainActor () -> Bool = { false }
    @ObservationIgnored var onShowWelcome: @MainActor () -> Void = {}
    @ObservationIgnored var highscores: @MainActor () -> [ScoreEntry] = { [] }

    @ObservationIgnored private let charDelay: Duration
    @ObservationIgnored private let lineDelay: Duration
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var pendingAnswer: CheckedContinuation<String, Never>?
    @ObservationIgnored private var questionChoices: [String] = []

    init(charDelay: Duration = .milliseconds(22), lineDelay: Duration = .milliseconds(70)) {
        self.charDelay = charDelay
        self.lineDelay = lineDelay
    }

    func boot() async {
        guard mode == .booting else { return }
        append(BootScript.lastLogin(Date()), .dim)
        append("")
        await wait(lineDelay * 2)
        append(BootScript.banner, .art)
        for line in BootScript.motd {
            await wait(lineDelay)
            append(line.text, line.style)
        }
        mode = .shell
    }

    /// The start button: type the gcc command, show its output, then run the binary.
    func compileAndRun() async {
        guard !isBusy else { return }
        await build()
    }

    private func build() async {
        mode = .compiling
        await autotype(BootScript.buildCommand)
        commitInput()
        await wait(lineDelay * 8)
        for line in BootScript.compilerOutput {
            append(line.text, line.style)
            await wait(lineDelay)
        }
        await wait(lineDelay * 4)
        await autotype("./pixly")
        commitInput()
        await wait(lineDelay * 3)
        mode = .program
    }

    /// Types a command into the prompt, then runs it.
    func run(_ command: String) async {
        guard !isBusy else { return }
        await autotype(command)
        commitInput()
        await perform(command)
    }

    /// A line the user entered with the keyboard: an answer to the open question, or a command.
    func submit(_ text: String) async {
        guard acceptsInput else { return }
        input = ""
        if let question, let pendingAnswer {
            self.question = nil
            self.pendingAnswer = nil
            append(text, .answer, label: question)
            pendingAnswer.resume(returning: text)
            return
        }
        guard !isExecuting else { return }
        append(text, .command)
        await perform(text)
    }

    private func perform(_ command: String) async {
        isExecuting = true
        await execute(command)
        isExecuting = false
    }

    func programExited(runtime: TimeInterval, interrupted: Bool) {
        guard mode == .program else { return }
        if interrupted {
            append("^C", .dim)
        } else {
            append("")
            append(String(format: "Process returned 1 (0x1)   execution time : %.3f s", runtime))
            append("Press any key to continue.")
        }
        mode = .shell
    }

    private func execute(_ raw: String) async {
        let parts = raw.split(separator: " ").map(String.init)
        guard let name = parts.first else { return }
        let argument = parts.dropFirst().joined(separator: " ")

        switch name {
        case "help":
            appendAll(BootScript.help)
        case "clear":
            lines.removeAll()
        case "start", "make", "run":
            await build()
        case "gcc", "cc":
            appendAll(BootScript.compilerOutput)
        case "./pixly", "pixly":
            mode = .compiling
            await wait(lineDelay * 3)
            mode = .program
        case "settings", "config":
            await settings(Array(parts.dropFirst()))
        case "theme":
            await change(.theme, to: argument)
        case "icon":
            await change(.icon, to: argument)
        case "avatar":
            await change(.avatar, to: argument)
        case "scanlines":
            await change(.scanlines, to: argument)
        case "welcome":
            onShowWelcome()
        case "leaderboard":
            append("opening Game Center leaderboard…", .accent)
            if !onOpenLeaderboard() {
                append("game center: not signed in (Settings › Game Center)", .error)
            }
        case "highscore", "scores":
            let entries = highscores()
            if entries.isEmpty {
                append("no highscores yet. run ./pixly", .dim)
            } else {
                append("rank   score  name", .dim)
                for (index, entry) in entries.prefix(10).enumerated() {
                    let rank = String(index + 1).padding(toLength: 4, withPad: " ", startingAt: 0)
                    let score = String(repeating: " ", count: max(0, 8 - String(entry.score).count)) + String(entry.score)
                    append("\(rank)\(score)  \(entry.name)", index == 0 ? .success : .output)
                }
            }
        case "ls":
            let hidden = argument.split(separator: " ").contains { $0.hasPrefix("-") && $0.contains("a") }
            append(((hidden ? [".", "..", ".pixlyrc"] : []) + BootScript.files).joined(separator: "  "))
        case "cat":
            if argument.isEmpty {
                append("usage: cat FILE", .dim)
            } else if argument == ".pixlyrc" || argument == "~/.pixlyrc", let rc = pixlyrc() {
                for line in rc {
                    append(line)
                }
            } else if let source = BootScript.source(named: argument) {
                for line in source.components(separatedBy: "\n") {
                    append(line)
                }
            } else {
                append("cat: \(argument): No such file or directory", .error)
            }
        case "credits":
            append("© Pascal Andermatt, Jan Huber, Adrian Schrempp")
        case "whoami":
            append(playerName())
        case "echo":
            append(argument)
        case "sudo":
            append("\(playerName()) is not in the sudoers file. This incident will be reported.", .error)
        case "exit", "logout":
            append("there is no escape. except pixel escape: try ./pixly", .dim)
        default:
            append("zsh: command not found: \(name)", .error)
        }
    }

    // MARK: - Settings

    private enum SettingKey: String, CaseIterable {
        case theme, icon, avatar, scanlines
    }

    /// The preferences rendered as a dotfile, for `cat ~/.pixlyrc`.
    private func pixlyrc() -> [String]? {
        guard let preferences else { return nil }
        return ["# ~/.pixlyrc — written by `settings`"] + SettingKey.allCases.map { "\($0.rawValue) = \(value(of: $0, in: preferences))" }
    }

    // MARK: - Tab completion

    /// Completes the word being typed, like zsh: a single match is filled in, a longer shared
    /// prefix is filled in, and otherwise the matches are listed.
    func complete() {
        guard acceptsInput else { return }
        let endsWithSpace = input.isEmpty || input.hasSuffix(" ")
        var words = input.split(separator: " ").map(String.init)
        let partial = endsWithSpace ? "" : (words.popLast() ?? "")
        let candidates: [String] = if question != nil {
            words.isEmpty ? questionChoices : []
        } else if words.isEmpty {
            Self.commands
        } else {
            completions(after: words)
        }
        let matches = candidates.filter { $0.lowercased().hasPrefix(partial.lowercased()) }
        guard !matches.isEmpty else { return }
        let head = words.map { $0 + " " }.joined()
        if matches.count == 1 {
            input = head + matches[0] + (question == nil ? " " : "")
        } else if let shared = sharedPrefix(of: matches), shared.count > partial.count {
            input = head + shared
        } else {
            append(matches.joined(separator: "  "), .dim)
        }
    }

    private func completions(after words: [String]) -> [String] {
        switch (words[0], words.count) {
        case ("cat", 1): [".pixlyrc"] + BootScript.files
        case ("ls", 1): ["-a"]
        case ("theme", 1), ("icon", 1): choices(for: .theme)
        case ("avatar", 1): choices(for: .avatar)
        case ("scanlines", 1): choices(for: .scanlines)
        case ("settings", 1): SettingKey.allCases.map(\.rawValue)
        case ("settings", 2): SettingKey(rawValue: words[1].lowercased()).map { choices(for: $0) } ?? []
        default: []
        }
    }

    private func sharedPrefix(of words: [String]) -> String? {
        guard var prefix = words.first else { return nil }
        for word in words.dropFirst() {
            while !word.lowercased().hasPrefix(prefix.lowercased()) {
                prefix.removeLast()
            }
        }
        return prefix
    }

    /// `settings` asks for every value like `npm init`; `settings theme amber` sets one directly.
    private func settings(_ arguments: [String]) async {
        guard let preferences else {
            append("settings: unavailable", .error)
            return
        }
        if let first = arguments.first {
            guard let key = SettingKey(rawValue: first.lowercased()) else {
                append("settings: unknown setting '\(first)' (theme, icon, avatar, scanlines)", .error)
                return
            }
            await change(key, to: arguments.dropFirst().joined(separator: " "))
            return
        }

        append("pixly settings — press enter to keep a value", .accent)
        append("")
        for key in SettingKey.allCases {
            while true {
                let current = value(of: key, in: preferences)
                let reply = await ask("\(key.rawValue) (\(choices(for: key).joined(separator: ", "))) [\(current)]:", choices: choices(for: key))
                let answer = reply.trimmingCharacters(in: .whitespaces)
                guard !answer.isEmpty else { break }
                if let error = await apply(answer, to: key, in: preferences) {
                    append("✗ \(error)", .error)
                } else {
                    append("✓ \(key.rawValue) = \(value(of: key, in: preferences))", .success)
                    break
                }
            }
        }
        append("")
        append("saved to ~/.pixlyrc", .dim)
    }

    /// `theme`, `icon` and `avatar`: list the choices, or set one.
    private func change(_ key: SettingKey, to argument: String) async {
        guard let preferences else {
            append("\(key.rawValue): unavailable", .error)
            return
        }
        if argument.isEmpty {
            let current = value(of: key, in: preferences)
            for choice in choices(for: key) {
                append((choice == current ? "* " : "  ") + choice, choice == current ? .success : .output)
            }
        } else if let error = await apply(argument, to: key, in: preferences) {
            append("\(key.rawValue): \(error)", .error)
        } else {
            append("\(key.rawValue): \(value(of: key, in: preferences))", .success)
        }
    }

    private func choices(for key: SettingKey) -> [String] {
        switch key {
        case .theme, .icon: ThemeID.allCases.map(\.rawValue)
        case .avatar: Avatar.allCases.map { $0.rawValue.lowercased() }
        case .scanlines: ["on", "off"]
        }
    }

    private func value(of key: SettingKey, in preferences: Preferences) -> String {
        switch key {
        case .theme: preferences.theme.rawValue
        case .icon: preferences.appIcon.rawValue
        case .avatar: preferences.avatar.rawValue.lowercased()
        case .scanlines: preferences.scanlines ? "on" : "off"
        }
    }

    /// Returns an error message, or `nil` once the value is applied.
    private func apply(_ answer: String, to key: SettingKey, in preferences: Preferences) async -> String? {
        let answer = answer.lowercased()
        switch key {
        case .theme:
            guard let theme = ThemeID(rawValue: answer) else { return "no such theme: \(answer)" }
            preferences.setTheme(theme)
        case .icon:
            guard let icon = ThemeID(rawValue: answer) else { return "no such icon: \(answer)" }
            guard await preferences.setAppIcon(icon) else { return "not supported on this device" }
        case .avatar:
            guard let avatar = Avatar.allCases.first(where: { $0.rawValue.lowercased() == answer }) else {
                return "no such avatar: \(answer)"
            }
            preferences.setAvatar(avatar)
        case .scanlines:
            guard answer == "on" || answer == "off" else { return "scanlines are on or off, not \(answer)" }
            preferences.setScanlines(answer == "on")
        }
        return nil
    }

    private func ask(_ question: String, choices: [String]) async -> String {
        await withCheckedContinuation { continuation in
            self.question = question
            questionChoices = choices
            pendingAnswer = continuation
        }
    }

    // MARK: - Output

    private func autotype(_ text: String) async {
        isTyping = true
        input = ""
        for character in text {
            input.append(character)
            if charDelay > .zero {
                await wait(charDelay + .milliseconds(Int.random(in: 0...20)))
            }
        }
        await wait(lineDelay * 3)
        isTyping = false
    }

    private func commitInput() {
        append(input, .command)
        input = ""
    }

    private func appendAll(_ script: [BootScript.Line]) {
        for line in script {
            append(line.text, line.style, label: line.label)
        }
    }

    private func append(_ text: String, _ style: TerminalLine.Style = .output, label: String? = nil) {
        lines.append(TerminalLine(id: nextID, text: text, style: style, label: label))
        nextID += 1
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    private func wait(_ duration: Duration) async {
        guard duration > .zero else { return }
        try? await Task.sleep(for: duration)
    }
}
