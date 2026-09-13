import Foundation

enum BootScript {
    struct Line: Sendable {
        let text: String
        let style: TerminalLine.Style
        let label: String?

        init(_ text: String, _ style: TerminalLine.Style = .output, label: String? = nil) {
            self.text = text
            self.style = style
            self.label = label
        }

        /// A help entry, laid out in two columns so it stays aligned when it wraps.
        static func entry(_ command: String, _ detail: String) -> Line {
            Line(detail, .definition, label: command)
        }
    }

    static let buildCommand = "gcc -Wall -O2 -o pixly main.c ball.c landscape.c score.c -Llib -lconsoleio"

    static let files = ["ball.c", "ball.h", "consoleio.h", "landscape.c", "landscape.h", "main.c", "pixel_escape.cbp", "score.c", "score.h", "timer.h"]

    static func source(named name: String) -> String? {
        guard files.contains(name), let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func lastLogin(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss"
        return "Last login: \(formatter.string(from: date)) on ttys001"
    }

    /// "ANSI Shadow" lettering: every glyph is six rows tall.
    static let banner = [
        "██████╗ ██╗██╗  ██╗██╗   ██╗   ██╗",
        "██╔══██╗██║╚██╗██╔╝██║   ╚██╗ ██╔╝",
        "██████╔╝██║ ╚███╔╝ ██║    ╚████╔╝ ",
        "██╔═══╝ ██║ ██╔██╗ ██║     ╚██╔╝  ",
        "██║     ██║██╔╝ ██╗███████╗ ██║   ",
        "╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝ ╚═╝   ",
    ].joined(separator: "\n")

    static let motd = [
        Line(""),
        Line("pixly — one pixel, one tunnel, no way out", .accent),
        Line("a port of \"Pixel Escape\", our C console game (consoleio.h, 80×25)", .dim),
        Line(""),
        Line(startHint),
        Line(""),
    ]

    static let help = [
        Line("commands:"),
        .entry("start", "compile & run pixly"),
        .entry("./pixly", "run without compiling"),
        .entry("leaderboard", "open the Game Center leaderboard"),
        .entry("highscore", "show local highscores"),
        .entry("settings", "theme, app icon, avatar and scanlines"),
        .entry("theme [NAME]", "classic, phosphor, amber or light"),
        .entry("icon [NAME]", "switch the app icon"),
        .entry("welcome", "show the welcome screen again"),
        .entry("ls, cat FILE", "the original C source and ~/.pixlyrc"),
        .entry("credits", "who made this"),
        .entry("clear", "clear the screen"),
        Line(gameHint, .dim),
        Line("tab completes commands, files and values", .dim),
    ]

    #if os(macOS)
    private static let startHint = "click start, or type 'help'."
    private static let gameHint = "in game: space to jump · q to quit · ⌃C to exit"
    #else
    private static let startHint = "tap start, or type 'help'."
    private static let gameHint = "in game: tap to jump · q to quit"
    #endif

    static let compilerOutput = [
        Line("main.c: In function 'xPositionForCenteredText':"),
        Line("main.c:22:16: warning: implicit declaration of function 'strlen' [-Wimplicit-function-declaration]", .warning),
        Line("   22 |     return 40-(strlen(text)/2);", .dim),
        Line("      |                ^~~~~~", .dim),
        Line("main.c:5:1: note: include '<string.h>' or provide a declaration of 'strlen'", .accent),
        Line("score.c: In function 'highscore':"),
        Line("score.c:108:5: warning: this 'if' clause does not guard... [-Wmisleading-indentation]", .warning),
        Line("  108 |     if (scoresCount > 0);", .dim),
        Line("      |     ^~", .dim),
        Line("score.c:109:5: note: ...this statement, but the latter is misleadingly indented as if it were guarded by the 'if'", .accent),
        Line("  109 |     {", .dim),
        Line("      |     ^", .dim),
    ]
}
