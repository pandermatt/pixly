import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The commands that aren't in `help`: for whoever types them anyway.
enum ShellJokes {
    typealias Line = BootScript.Line

    struct SystemInfo {
        var uptime: TimeInterval
        var theme: String
        var icon: String
        var avatar: String
        var best: Int
        var best2: Int
    }

    @MainActor
    static func neofetch(_ info: SystemInfo) -> [Line] {
        [
            Line(BootScript.banner, .art),
            Line("player@pixly", .success),
            Line("------------", .dim),
            .entry("OS", "PixelOS 1.0 (80×25)"),
            .entry("Host", host),
            .entry("Kernel", "consoleio.h"),
            .entry("Uptime", duration(info.uptime)),
            .entry("Shell", "zsh (probably)"),
            .entry("Theme", info.theme),
            .entry("Icon", info.icon),
            .entry("Avatar", info.avatar),
            .entry("Highscore", "\(info.best) · 2.0: \(info.best2)"),
            .entry("Pixels", "1"),
            Line("", .palette),
        ]
    }

    @MainActor
    private static var host: String {
        #if os(macOS)
        "Mac"
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: "iPad"
        case .tv: "Apple TV"
        default: "iPhone"
        }
        #endif
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 {
            return "\(Int(seconds)) secs"
        }
        if minutes < 60 {
            return "\(minutes) min\(minutes == 1 ? "" : "s")"
        }
        return "\(minutes / 60) h, \(minutes % 60) mins"
    }

    /// `git` and a subcommand; `nil` when the shell doesn't know it. `git checkout -- .` isn't
    /// a joke and lives in `TerminalSession`.
    static func git(_ arguments: [String], removedFiles: Set<String>) -> [Line]? {
        guard let subcommand = arguments.first else {
            return [
                Line("what is git? a time machine for code. the pixel wishes it had one.", .accent),
                Line("usage: git [--version] [--help] <command> [<args>]", .dim),
            ]
        }
        switch subcommand {
        case "status":
            var lines = [Line("On branch main"), Line("Your pixel is ahead of 'origin/tunnel' by 1 jump."), Line("")]
            if removedFiles.isEmpty {
                lines.append(Line("nothing to commit, working tree clean"))
            } else {
                lines += [Line("Changes not staged for commit:"), Line("  (use \"git checkout -- .\" to bring them back)", .dim)]
                lines += removedFiles.sorted().map { Line("        deleted:    \($0)", .error) }
            }
            return lines
        case "log":
            return [
                .entry("3f1a2b0", "port to Swift (Pascal Andermatt)"),
                .entry("9c4e7d1", "FINAL final version (Adrian Schrempp)"),
                .entry("b72a90e", "final version 2 (Jan Huber)"),
                .entry("41d5c3f", "final version (Pascal Andermatt)"),
                .entry("0e8f6a2", "fix pixel escaping through walls (Jan Huber)"),
                .entry("a1b2c3d", "initial commit (Adrian Schrempp)"),
            ]
        case "blame":
            return [Line("it was the pixel.")]
        case "push" where arguments.contains("--force") || arguments.contains("-f"):
            return [
                Line("I just force pushed. to main. on a Friday.", .warning),
                Line("remote: rewriting history…", .dim),
                Line("remote: everyone's highscores are yours now", .dim),
                Line("(just kidding. nothing changed.)", .dim),
            ]
        case "push":
            return [Line("Everything up-to-date. the pixel is not.")]
        case "pull":
            return [Line("Already up to date.")]
        case "commit":
            return [Line("nothing to commit. the pixel is committed to escaping.")]
        default:
            return nil
        }
    }

    static let top = [
        Line("Processes: 5 total, 1 escaping", .dim),
        Line("PID   COMMAND    %CPU  MEM", .accent),
        Line("1     pixel      99.9  1 px"),
        Line("42    tunnel     12.0  80×25"),
        Line("64    red_bar     6.6  3 rows"),
        Line("128   zsh         0.1  4 KB"),
        Line("256   gcc         0.0  zombie"),
        Line("(press q to quit. it already did.)", .dim),
    ]

    /// `ping` answers PONG, of course; with a host it pings it first.
    static func ping(_ host: String?) -> [Line] {
        guard let host else { return [Line("PONG", .success)] }
        return [Line("PING \(host): 56 data bytes")]
            + (0..<3).map { Line("64 bytes from \(host): icmp_seq=\($0) ttl=64 time=1 jump") }
            + [Line("PONG", .success)]
    }

    static let teapot = Line("418 I'm a teapot", .warning)
}
