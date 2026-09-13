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
    /// The files `buildCommand` compiles; their `#include "…"` lines pull in the headers.
    static let buildSources = ["main.c", "ball.c", "landscape.c", "score.c"]
    /// Brings back source files removed with `rm`. Not in the help: the start button offers it.
    static let restoreCommand = "git checkout -- ."
    /// Pixly 2.0 is the Swift rewrite, and it compiles cleanly.
    static let buildCommand2 = "swiftc -O -o pixly2 Pixly2.swift"

    static let files = [
        "Pixly.xcodeproj", "Pixly2.swift", "ball.c", "ball.h", "consoleio.h", "credits.txt", "landscape.c", "landscape.h", "main.c",
        "pixel_escape.cbp", "score.c", "score.h", "timer.h",
    ]
    static let directories = ["Pixly.xcodeproj"]
    static let xcodeprojContents = "project.pbxproj  project.xcworkspace  xcshareddata"
    static let repository = "https://github.com/pandermatt/pixly"

    /// What `cat Pixly2.swift` shows: the heart of `SmoothEscapeGame.swift`, then a link to the rest.
    static let pixly2Excerpt = """
        import Foundation

        /// Pixly 2.0: the same escape with continuous physics. The pixel and the scrolling are
        /// smooth, but the walls keep the original's stepped look.
        struct SmoothEscapeGame: Sendable {
            static let gravity = 3.2
            static let jumpVelocity = 0.95
            static let maxFallSpeed = 1.3
            /// Walls and bars snap to 20 rows, so every step is a square block.
            static let rowHeight = 1.0 / 20

            mutating func jump() {
                guard state != .over else { return }
                state = .running
                velocity = -Self.jumpVelocity
            }

            mutating func update(dt: Double) {
                switch state {
                case .running:
                    velocity = min(velocity + Self.gravity * dt, Self.maxFallSpeed)
                    playerY += velocity * dt
                    distance += speed * dt
                    if isColliding {
                        state = .over
                    }
                // …
                }
            }
            // …
        }
        """

    static let credits = """
        Pixel Escape, the original C console game
        © Pascal Andermatt, Jan Huber, Adrian Schrempp

        Pixly, its iOS and macOS port
        """

    /// What `rm -rf /` pretends to delete, on the way to taking the shell with it.
    static let rootPaths = ["/Applications/Pixly.app", "/Library/Fonts", "/System/Library/CoreServices/Finder.app", "/Users/player/.pixlyrc"]
        + files.map { "/Users/player/\($0)" }
        + ["/Users/player/highscore.txt", "/usr/lib/libconsoleio.a", "/usr/bin/gcc", "/bin/ls", "/bin/rm", "/bin/zsh", "/System/Library/Kernels/kernel"]

    static func source(named name: String) -> String? {
        if name == "credits.txt" {
            return credits
        }
        if name == "Pixly2.swift" {
            return pixly2Excerpt
        }
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

    #if os(tvOS)
    /// Nothing can be typed on a TV, so help explains the buttons instead of commands.
    static let help = [
        Line(gameHint, .accent),
        Line(""),
        Line("buttons:"),
        .entry("start", "compile & run pixly"),
        .entry("2.0", "Pixly 2.0: smooth jumps"),
        .entry("trophy", "the Game Center leaderboard"),
        Line("theme and avatar: Settings in pixly's menu", .dim),
    ]
    #else
    /// Most important first: how to play, how to start, then everything else.
    static let help = [
        Line(gameHint, .accent),
        Line(""),
        Line("commands:"),
        .entry("start", "compile & run pixly"),
        .entry("start2", "Pixly 2.0: smooth jumps, portrait"),
        .entry("settings", "theme, app icon, avatar and scanlines"),
        .entry("highscore", "show local highscores"),
        .entry("highscore2", "show Pixly 2.0 highscores"),
        .entry("leaderboard", "open the Game Center leaderboard"),
        .entry("welcome", "show the welcome screen again"),
        Line("tab completes commands, files and values", .dim),
    ]
    #endif

    #if os(macOS)
    private static let startHint = "click start, or type 'help'."
    private static let gameHint = "how to play: space to jump, dodge the walls and red bars (⌃C exits)"
    #elseif os(tvOS)
    private static let startHint = "select start to play."
    private static let gameHint = "how to play: click the remote (or press A) to jump, dodge the walls and red bars"
    #else
    private static let startHint = "tap start, or type 'help'."
    private static let gameHint = "how to play: tap to jump, dodge the walls and red bars"
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
