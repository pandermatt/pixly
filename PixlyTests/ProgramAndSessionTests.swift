import Foundation
import Testing
@testable import Pixly

@MainActor
struct PixlyProgramTests {
    private func makeProgram() throws -> PixlyProgram {
        let defaults = try #require(UserDefaults(suiteName: "pixly-program-\(UUID().uuidString)"))
        return PixlyProgram(defaults: defaults, loadingStep: .zero)
    }

    @Test func loadsIntoTheMenu() async throws {
        let program = try makeProgram()
        await program.run()
        #expect(program.screen == .menu)
        #expect(program.console[40, 8].character == Avatar.pixel.glyph)
        #expect(row(10, of: program) == "> New Game")
        #expect(program.console[36, 10].foreground == .white)
        #expect(row(11, of: program) == "Highscore")
        #expect(program.console[34, 11].foreground == .darkGray)
    }

    @Test func menuEntriesShareOneLeftEdge() async throws {
        let program = try makeProgram()
        await program.run()
        let starts = (10...14).map { y in (1...80).first { program.console[$0, y].character != " " && program.console[$0, y].character != ">" } }
        #expect(Set(starts).count == 1)
        program.moveSelection(1)
        #expect(row(10, of: program) == "New Game")
        #expect(row(11, of: program) == "> Highscore")
    }

    private func row(_ y: Int, of program: PixlyProgram) -> String {
        (1...80).map { String(program.console[$0, y].character) }.joined().trimmingCharacters(in: .whitespaces)
    }

    @Test func playingUntilGameOverSavesTheScore() async throws {
        let program = try makeProgram()
        var submitted: [Int] = []
        program.onScore = { submitted.append($0) }
        await program.run()
        program.confirm()
        #expect(program.screen == .playing)

        var ticks = 0
        while program.screen == .playing, ticks < 2000 {
            program.advance()
            ticks += 1
        }
        #expect(program.screen == .saveScore)
        #expect(submitted == [ticks * 2])
        #expect(program.console[20, 8].background == .green)

        program.setName("Pascal")
        program.saveScore()
        #expect(program.screen == .menu)
        #expect(program.scores.entries == [ScoreEntry(name: "Pascal", score: ticks * 2)])
    }

    @Test func enterWhileTheNameIsStillTypingSavesTheWholeName() async throws {
        let program = try makeProgram()
        program.playerAlias = { "Pandermatt" }
        await program.run()
        program.confirm()
        var ticks = 0
        while program.screen == .playing, ticks < 2000 {
            program.advance()
            ticks += 1
        }
        #expect(program.screen == .saveScore)
        #expect(program.isTypingName)

        program.confirm()
        #expect(program.screen == .menu)
        #expect(!program.isTypingName)
        #expect(program.scores.entries.first?.name == "Pandermatt")
    }

    @Test func changingTheAvatar() async throws {
        let program = try makeProgram()
        await program.run()
        program.moveSelection(2)
        program.confirm()
        #expect(program.screen == .avatar)
        program.moveSelection(2)
        program.confirm()
        #expect(program.avatar == .heart)
        #expect(program.console[40, 8].character == Avatar.heart.glyph)
    }

    @Test func tappingAMenuRowActivatesIt() async throws {
        let program = try makeProgram()
        await program.run()
        program.press(at: (x: 40, y: 13))
        #expect(program.screen == .credits)
        program.press(at: nil)
        #expect(program.screen == .menu)
    }
}

@MainActor
struct TerminalSessionTests {
    private func bootedSession() async -> TerminalSession {
        let session = TerminalSession(charDelay: .zero, lineDelay: .zero)
        await session.boot()
        return session
    }

    @Test func bootsIntoTheShell() async {
        let session = TerminalSession(charDelay: .zero, lineDelay: .zero)
        #expect(session.mode == .booting)
        await session.boot()
        #expect(session.mode == .shell)
        #expect(session.showsPrompt)
    }

    @Test func startTypesTheBuildCommandThenLaunches() async {
        let session = await bootedSession()
        await session.compileAndRun()
        #expect(session.mode == .program)
        #expect(session.lines.contains { $0.style == .command && $0.text == BootScript.buildCommand })
        #expect(session.lines.last?.text == "./pixly")

        session.programExited(runtime: 12.5, interrupted: false)
        #expect(session.mode == .shell)
        #expect(session.lines.contains { $0.text.hasPrefix("Process returned 1 (0x1)") })
    }

    @Test func unknownCommand() async {
        let session = await bootedSession()
        await session.submit("pong")
        #expect(session.lines.last?.text == "zsh: command not found: pong")
    }

    @Test func catPrintsTheOriginalSource() async {
        let session = await bootedSession()
        await session.submit("cat ball.c")
        #expect(session.lines.contains { $0.text.contains("#define XPOS 5") })
    }

    @Test func clearEmptiesTheScrollback() async {
        let session = await bootedSession()
        await session.submit("clear")
        #expect(session.lines.isEmpty)
    }
}
