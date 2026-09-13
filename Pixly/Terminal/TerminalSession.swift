import Foundation
import Observation

/// The simulated zsh session around the C program: scrollback, typing and commands.
@Observable @MainActor
final class TerminalSession {
    /// The classic port, or Pixly 2.0.
    enum Program: Equatable, Sendable {
        case classic, smooth
    }

    enum Mode: Equatable, Sendable {
        case booting, shell, compiling, program(Program)
    }

    nonisolated static let prompt = "player@pixly ~ %"
    nonisolated static let commands = [
        "./pixly", "./pixly2", "avatar", "brew", "cat", "clear", "coffee", "credits", "echo", "exit", "gcc", "git", "help",
        "highscore", "highscore2", "icon", "leaderboard", "ls", "make", "neofetch", "open", "ping", "rm", "scanlines",
        "settings", "start", "start2", "sudo", "theme", "top", "welcome", "whoami", "xcodebuild", "xed",
    ]
    private static let maxLines = 500

    private(set) var lines: [TerminalLine] = []
    private(set) var mode = Mode.booting
    private(set) var isTyping = false
    /// A question waiting for an answer (the `settings` prompts), shown instead of the prompt.
    private(set) var question: String?
    /// A command is still running (e.g. between `settings` questions).
    private(set) var isExecuting = false
    /// Source files removed with `rm`, still gone after a relaunch until they're restored.
    private(set) var removedFiles: Set<String>
    /// The last build stopped on a removed file.
    private(set) var buildFailed = false
    var input = ""

    /// Whether the keyboard can type into the prompt line.
    var acceptsInput: Bool { mode == .shell && !isTyping }
    /// Whether something is running, so buttons that start another command are disabled.
    var isBusy: Bool { !acceptsInput || question != nil || isExecuting }
    var showsPrompt: Bool { mode == .shell || isTyping }
    /// Whether the start button offers to bring the removed sources back instead of building.
    var canRestore: Bool { buildFailed && !removedFiles.isEmpty }
    var restoreTitle: String {
        let onlyC = removedFiles.allSatisfy { name in [".c", ".h", ".cbp"].contains { name.hasSuffix($0) } }
        return onlyC ? "restore C files" : "restore files"
    }

    @ObservationIgnored var preferences: Preferences?
    @ObservationIgnored var playerName: @MainActor () -> String = { "player" }
    @ObservationIgnored var onOpenLeaderboard: @MainActor () -> Bool = { false }
    @ObservationIgnored var onShowWelcome: @MainActor () -> Void = {}
    @ObservationIgnored var highscores: @MainActor () -> [ScoreEntry] = { [] }
    @ObservationIgnored var highscores2: @MainActor () -> [ScoreEntry] = { [] }
    /// Empties a score table: `rm highscore.txt` or `rm highscore2.txt`.
    @ObservationIgnored var resetScores: @MainActor (Program) -> Void = { _ in }
    /// The shell's secrets earn Game Center achievements.
    @ObservationIgnored var onAchievement: @MainActor (Achievement) -> Void = { _ in }

    @ObservationIgnored private let charDelay: Duration
    @ObservationIgnored private let lineDelay: Duration
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var pendingAnswer: CheckedContinuation<String, Never>?
    @ObservationIgnored private var questionChoices: [String] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let startDate = Date()
    private static let removedFilesKey = "removedFiles"

    init(charDelay: Duration = .milliseconds(22), lineDelay: Duration = .milliseconds(70), defaults: UserDefaults = .standard) {
        self.charDelay = charDelay
        self.lineDelay = lineDelay
        self.defaults = defaults
        removedFiles = Set(defaults.stringArray(forKey: Self.removedFilesKey) ?? []).intersection(BootScript.files)
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

    /// The start buttons: type the compiler command, show its output, then run the binary.
    func compileAndRun(_ program: Program = .classic) async {
        guard !isBusy else { return }
        await build(program)
    }

    private func build(_ program: Program) async {
        mode = .compiling
        switch program {
        case .classic:
            await autotype(BootScript.buildCommand)
            commitInput()
            await wait(lineDelay * 8)
            let errors = buildErrors()
            buildFailed = !errors.isEmpty
            guard errors.isEmpty else {
                appendAll(errors)
                mode = .shell
                return
            }
            for line in BootScript.compilerOutput {
                append(line.text, line.style)
                await wait(lineDelay)
            }
            await wait(lineDelay * 4)
            await autotype("./pixly")
        case .smooth:
            await autotype(BootScript.buildCommand2)
            commitInput()
            await wait(lineDelay * 6)
            buildFailed = removedFiles.contains("Pixly2.swift")
            guard !buildFailed else {
                append("<unknown>:0: error: no such file or directory: 'Pixly2.swift'", .error)
                mode = .shell
                return
            }
            await autotype("./pixly2")
        }
        commitInput()
        await wait(lineDelay * 3)
        mode = .program(program)
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
        guard case .program = mode else { return }
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
        case "make" where argument == "coffee":
            serveCoffee()
        case "start", "make", "run":
            await build(.classic)
        case "start2":
            await build(.smooth)
        case "gcc", "cc":
            appendAll(BootScript.compilerOutput)
        case "./pixly", "pixly":
            mode = .compiling
            await wait(lineDelay * 3)
            mode = .program(.classic)
        case "./pixly2", "pixly2":
            mode = .compiling
            await wait(lineDelay * 3)
            mode = .program(.smooth)
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
            listScores(highscores(), program: "./pixly")
        case "highscore2", "scores2":
            listScores(highscores2(), program: "./pixly2")
        case "ls":
            let words = parts.dropFirst()
            let hidden = words.contains { $0.hasPrefix("-") && $0.contains("a") }
            if let path = words.first(where: { !$0.hasPrefix("-") && ![".", "~", "~/"].contains($0) }) {
                if !visibleFiles.contains(path) {
                    append("ls: \(path): No such file or directory", .error)
                } else {
                    append(BootScript.directories.contains(path) ? BootScript.xcodeprojContents : path)
                }
            } else {
                let names = (hidden ? [".", "..", ".pixlyrc"] : []) + visibleFiles
                if !names.isEmpty {
                    append(names.joined(separator: "  "))
                }
            }
        case "rm":
            await remove(Array(parts.dropFirst()))
        case "git":
            if ["checkout -- .", "checkout .", "restore ."].contains(argument) {
                restoreRemovedFiles()
            } else if let lines = ShellJokes.git(Array(parts.dropFirst()), removedFiles: removedFiles) {
                appendAll(lines)
                if parts.dropFirst().first == "push", parts.contains("--force") || parts.contains("-f") {
                    onAchievement(.fridayDeploy)
                }
            } else {
                append("git: '\(parts[1])' is not a git command. See 'git --help'.", .error)
            }
        case "cat":
            if argument.isEmpty {
                append("usage: cat FILE", .dim)
            } else if argument == ".pixlyrc" || argument == "~/.pixlyrc", let rc = pixlyrc() {
                for line in rc {
                    append(line)
                }
            } else if let program = scoreProgram(named: argument), !scores(of: program).isEmpty {
                // score.c's pixel_escape.txt format, without its +5 "encryption".
                for entry in scores(of: program) {
                    append("\(entry.name)§\(entry.score)")
                }
            } else if BootScript.directories.contains(argument), visibleFiles.contains(argument) {
                append("cat: \(argument): Is a directory", .error)
            } else if !removedFiles.contains(argument), let source = BootScript.source(named: argument) {
                for line in source.components(separatedBy: "\n") {
                    append(line)
                }
                if argument.hasSuffix(".swift") {
                    append("// the whole game (Swift and C) is on GitHub:", .dim)
                    append(BootScript.repository, .link)
                }
                if argument != "credits.txt" {
                    onAchievement(.readTheSource)
                }
            } else {
                append("cat: \(argument): No such file or directory", .error)
            }
        case "neofetch":
            appendAll(ShellJokes.neofetch(ShellJokes.SystemInfo(
                uptime: Date().timeIntervalSince(startDate),
                theme: preferences?.theme.rawValue ?? ThemeID.classic.rawValue,
                icon: preferences?.appIcon.rawValue ?? ThemeID.classic.rawValue,
                avatar: (preferences?.avatar ?? .pixel).rawValue.lowercased(),
                best: highscores().map(\.score).max() ?? 0,
                best2: highscores2().map(\.score).max() ?? 0
            )))
            onAchievement(.showOff)
        case "top", "htop":
            appendAll(ShellJokes.top)
        case "ping":
            for line in ShellJokes.ping(parts.dropFirst().first) {
                append(line.text, line.style)
                await wait(lineDelay * 5)
            }
        case "coffee":
            serveCoffee()
        case "brew":
            if argument.hasSuffix("coffee") {
                serveCoffee()
            } else {
                append("brew: pixly is already installed.")
            }
        case "open", "xed", "xcodebuild":
            if name == "open", !["Pixly.xcodeproj", "Pixly2.swift"].contains(argument) {
                append(argument.isEmpty ? "usage: open FILE" : "open: nothing on this pixel can open \(argument)", .dim)
            } else if !visibleFiles.contains("Pixly.xcodeproj") {
                append("xcodebuild: error: 'Pixly.xcodeproj' does not exist.", .error)
            } else {
                append("Xcode doesn't fit on one pixel. read the project on GitHub:", .dim)
                append(BootScript.repository, .link)
            }
        case "credits":
            for line in BootScript.credits.components(separatedBy: "\n") {
                append(line)
            }
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

    private func listScores(_ entries: [ScoreEntry], program: String) {
        guard !entries.isEmpty else {
            append("no highscores yet. run \(program)", .dim)
            return
        }
        append("rank   score  name", .dim)
        for (index, entry) in entries.prefix(10).enumerated() {
            let rank = String(index + 1).padding(toLength: 4, withPad: " ", startingAt: 0)
            let score = String(repeating: " ", count: max(0, 8 - String(entry.score).count)) + String(entry.score)
            append("\(rank)\(score)  \(entry.name)", index == 0 ? .success : .output)
        }
    }

    // MARK: - Files

    /// What `ls` shows: the sources that weren't removed, and a score file for each table with scores.
    private var visibleFiles: [String] {
        let scoreFiles = [Program.classic, .smooth].filter { !scores(of: $0).isEmpty }.map(Self.scoreFile)
        return (BootScript.files.filter { !removedFiles.contains($0) } + scoreFiles).sorted()
    }

    private static func scoreFile(_ program: Program) -> String {
        program == .classic ? "highscore.txt" : "highscore2.txt"
    }

    private func scoreProgram(named name: String) -> Program? {
        [Program.classic, .smooth].first { Self.scoreFile($0) == name }
    }

    private func scores(of program: Program) -> [ScoreEntry] {
        program == .classic ? highscores() : highscores2()
    }

    /// `rm`: a removed source stays gone until restored, a score file takes its table with it,
    /// and `~/.pixlyrc` puts every setting back to its default. Globs expand like zsh's.
    private func remove(_ arguments: [String]) async {
        let names = arguments.filter { !$0.hasPrefix("-") }
        guard !names.isEmpty else {
            append("usage: rm [-f | -i] [-dIPRrvWx] file ...", .dim)
            return
        }
        let force = arguments.contains { $0.hasPrefix("-") && $0.contains("f") }
        if names.contains(where: { $0 == "/" || $0 == "/*" }) {
            if arguments.contains(where: { $0.hasPrefix("-") && $0.lowercased().contains("r") }) {
                await removeRoot()
            } else {
                append("rm: /: is a directory", .error)
            }
            return
        }
        var targets: [String] = []
        for name in names {
            guard name.contains("*") || name.contains("?") else {
                targets.append(name)
                continue
            }
            let matches = visibleFiles.filter { NSPredicate(format: "SELF LIKE %@", name).evaluate(with: $0) }
            guard !matches.isEmpty else {
                append("zsh: no matches found: \(name)", .error)
                return
            }
            targets += matches
        }
        for target in targets {
            let file = target.hasPrefix("~/") ? String(target.dropFirst(2)) : target
            if file == "." || file == ".." {
                append("rm: \".\" and \"..\" may not be removed", .error)
            } else if file == ".pixlyrc", let preferences {
                await preferences.resetSettings()
            } else if let program = scoreProgram(named: file), !scores(of: program).isEmpty {
                resetScores(program)
            } else if BootScript.directories.contains(file), !removedFiles.contains(file),
                      !arguments.contains(where: { $0.hasPrefix("-") && $0.lowercased().contains("r") }) {
                append("rm: \(target): is a directory", .error)
            } else if BootScript.files.contains(file), !removedFiles.contains(file) {
                removedFiles.insert(file)
                defaults.set(removedFiles.sorted(), forKey: Self.removedFilesKey)
            } else if !force {
                append("rm: \(target): No such file or directory", .error)
            }
        }
    }

    /// The start button after a failed build: types the git command that brings the sources back.
    func restoreFiles() async {
        await run(BootScript.restoreCommand)
    }

    /// `rm -rf /`, the easter egg: the system scrolls away, the shell eats its own scrollback,
    /// the kernel panics and the machine boots again. Nothing is actually removed.
    private func removeRoot() async {
        mode = .compiling
        append("rm: it is dangerous to operate recursively on '/'", .warning)
        append("rm: ignoring --preserve-root. good luck.", .warning)
        await wait(lineDelay * 10)
        for path in BootScript.rootPaths {
            append("removed '\(path)'", .dim)
            await wait(lineDelay / 2)
        }
        await wait(lineDelay * 6)
        while !lines.isEmpty {
            lines.removeLast(min(lines.count, max(2, lines.count / 12)))
            await wait(lineDelay)
        }
        await wait(lineDelay * 10)
        append("zsh: /bin/zsh: No such file or directory", .error)
        await wait(lineDelay * 12)
        append("panic(cpu 0 caller 0xffffff8000ba5e1e): \"the pixel escaped\"", .error)
        append("Debugger called: <panic>", .dim)
        append("rebooting…", .dim)
        await wait(lineDelay * 25)
        lines.removeAll()
        await wait(lineDelay * 8)
        mode = .booting
        await boot()
        append("(just kidding. nothing was deleted. please don't try this at home.)", .dim)
        onAchievement(.rmRoot)
    }

    private func serveCoffee() {
        appendAll([ShellJokes.teapot])
        onAchievement(.teapot)
    }

    private func restoreRemovedFiles() {
        let count = removedFiles.count
        if count > 0, buildFailed {
            onAchievement(.restored)
        }
        removedFiles = []
        buildFailed = false
        defaults.removeObject(forKey: Self.removedFilesKey)
        append("Updated \(count) path\(count == 1 ? "" : "s") from the index")
    }

    /// What gcc says when files it needs are gone: each missing input, then, per remaining
    /// source, its first `#include` of a missing header (gcc stops a file at a fatal error).
    private func buildErrors() -> [BootScript.Line] {
        var errors = BootScript.buildSources.filter { removedFiles.contains($0) }.map {
            BootScript.Line("gcc: error: \($0): No such file or directory", .error)
        }
        for name in BootScript.buildSources where !removedFiles.contains(name) {
            guard let source = BootScript.source(named: name) else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated() where line.hasPrefix("#include \"") {
                let header = line.split(separator: "\"").dropFirst().first.map(String.init) ?? ""
                guard removedFiles.contains(header) else { continue }
                errors += [
                    BootScript.Line("\(name):\(index + 1):10: fatal error: \(header): No such file or directory", .error),
                    BootScript.Line(String(format: "%5d | ", index + 1) + line, .dim),
                    BootScript.Line("      |          ^" + String(repeating: "~", count: header.count + 1), .dim),
                    BootScript.Line("compilation terminated."),
                ]
                break
            }
        }
        return errors
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
        case ("cat", 1): [".pixlyrc"] + visibleFiles
        case ("rm", _): visibleFiles + [".pixlyrc"]
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
