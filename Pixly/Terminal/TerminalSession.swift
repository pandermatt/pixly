import Foundation
import Observation

/// The simulated zsh session around the C program: scrollback, typing and commands.
@Observable @MainActor
final class TerminalSession {
    enum Mode: Equatable, Sendable {
        case booting, shell, compiling, program
    }

    static let prompt = "player@pixly ~ %"
    private static let maxLines = 500

    private(set) var lines: [TerminalLine] = []
    private(set) var mode = Mode.booting
    private(set) var isTyping = false
    var input = ""

    var isBusy: Bool { mode != .shell || isTyping }
    var showsPrompt: Bool { mode == .shell || isTyping }

    @ObservationIgnored var playerName: @MainActor () -> String = { "player" }
    @ObservationIgnored var onOpenLeaderboard: @MainActor () -> Bool = { false }
    @ObservationIgnored var highscores: @MainActor () -> [ScoreEntry] = { [] }

    @ObservationIgnored private let charDelay: Duration
    @ObservationIgnored private let lineDelay: Duration
    @ObservationIgnored private var nextID = 0

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
        await execute(command)
    }

    /// Runs a command the user entered with the keyboard.
    func submit(_ command: String) async {
        guard !isBusy else { return }
        input = ""
        append(command, .command)
        await execute(command)
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
            await compileAndRun()
        case "gcc", "cc":
            appendAll(BootScript.compilerOutput)
        case "./pixly", "pixly":
            mode = .compiling
            await wait(lineDelay * 3)
            mode = .program
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
            append(BootScript.files.joined(separator: "  "))
        case "cat":
            if argument.isEmpty {
                append("usage: cat FILE", .dim)
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
            append(line.text, line.style)
        }
    }

    private func append(_ text: String, _ style: TerminalLine.Style = .output) {
        lines.append(TerminalLine(id: nextID, text: text, style: style))
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
