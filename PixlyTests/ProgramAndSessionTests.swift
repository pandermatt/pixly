import Foundation
import Testing
@testable import Pixly

@MainActor
struct PixlyProgramTests {
    private func makeProgram() throws -> PixlyProgram {
        let defaults = try #require(UserDefaults(suiteName: "pixly-program-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher())
        return PixlyProgram(preferences: preferences, defaults: defaults, loadingStep: .zero)
    }

    private func row(_ y: Int, of program: PixlyProgram) -> String {
        (1...80).map { String(program.console[$0, y].character) }.joined().trimmingCharacters(in: .whitespaces)
    }

    private func playUntilGameOver(_ program: PixlyProgram) -> Int {
        var ticks = 0
        while program.screen == .playing, ticks < 2000 {
            program.advance()
            ticks += 1
        }
        return ticks
    }

    @Test func loadsIntoTheMenu() async throws {
        let program = try makeProgram()
        await program.run()
        #expect(program.screen == .menu)
        #expect(program.console[40, 8].character == Avatar.pixel.glyph)
        #expect(row(10, of: program) == "> New Game <")
        #expect(program.console[36, 10].foreground == .white)
        #expect(row(11, of: program) == "Highscore")
        #expect(program.console[36, 11].foreground == .darkGray)
    }

    @Test func menuEntriesAreCentred() async throws {
        let program = try makeProgram()
        await program.run()
        program.moveSelection(1)
        #expect(row(10, of: program) == "New Game")
        #expect(row(11, of: program) == "> Highscore <")
        for y in 10...15 {
            let used = (1...80).filter { program.console[$0, y].character != " " }
            let centre = Double(used.first! + used.last!) / 2
            #expect(abs(centre - 39.5) <= 0.5)
        }
    }

    @Test func hoveringAnEntrySelectsIt() async throws {
        let program = try makeProgram()
        await program.run()
        program.hover(at: (x: 40, y: 12))
        #expect(program.selection == 3)
        #expect(row(12, of: program) == "> Change Avatar <")
        program.hover(at: (x: 5, y: 13))
        #expect(program.selection == 3)
        program.hover(at: (x: 40, y: 20))
        #expect(program.selection == 3)
        program.handle(.up)
        #expect(program.selection == 2)
    }

    @Test func aWideConsoleCentresTheOriginalScreens() {
        var buffer = ConsoleBuffer(columns: 100)
        #expect(buffer.margin == 10)
        buffer.gotoxy(ConsoleBuffer.centeredX("GAME OVER!"), 10)
        buffer.write("GAME OVER!")
        #expect(buffer[45, 10].character == "G")
        buffer.gotoxy(fromLeft: 1, 25)
        buffer.write("7")
        #expect(buffer[1, 25].character == "7")
    }

    @Test func aWideScreenShowsMoreLandscapeWithTheSameGame() async throws {
        let program = try makeProgram()
        await program.run()
        program.setColumns(120)
        #expect(program.console.width == 120)
        #expect(program.console[54, 10].character == ">")

        program.confirm()
        #expect(program.screen == .playing)
        #expect(program.console.width == 120)
        // The tunnel (always open on rows 10–15) reaches the right edge, the score bar spans it.
        #expect(program.console[120, 12].background == .white)
        #expect(program.console[2, 25].character == "0")
        #expect(program.console[118, 25].character == "0")
        #expect(ConsoleLayout.columns(fitting: CGSize(width: 1_500, height: 500)) == 150)
        #expect(ConsoleLayout.columns(fitting: CGSize(width: 400, height: 500)) == 80)
    }

    @Test func afterACrashATapAnywhereContinuesOnceTheScoreHasShown() async throws {
        let defaults = try #require(UserDefaults(suiteName: "pixly-continue-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults, iconSwitcher: FakeIconSwitcher())
        let program = PixlyProgram(preferences: preferences, defaults: defaults, loadingStep: .zero, continueDelay: .milliseconds(50))
        await program.run()
        program.confirm()
        _ = playUntilGameOver(program)
        #expect(program.screen == .saveScore)

        // Straight after the crash a tap only shows how to continue.
        program.press(at: nil)
        #expect(program.screen == .saveScore)
        #expect(!program.canContinue)

        for _ in 0..<100 where !program.canContinue {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(program.canContinue)
        program.press(at: nil)
        #expect(program.screen == .menu)
        #expect(program.scores.entries.count == 1)
    }

    @Test func selectingAnEntryByNumber() async throws {
        let program = try makeProgram()
        await program.run()
        #expect(program.currentMenu?.count == 6)
        program.select(4)
        #expect(program.selection == 4)
        #expect(row(13, of: program) == "> Settings <")
        program.select(0)
        program.select(7)
        #expect(program.selection == 4)
    }

    @Test func avatarMenuPreviewsTheHighlightedAvatar() async throws {
        let program = try makeProgram()
        await program.run()
        program.moveSelection(2)
        program.handle(.space)
        #expect(program.screen == .avatar)
        #expect(program.console[40, 8] == .init(character: Avatar.pixel.glyph, foreground: .black, background: .white))
        program.handle(.down)
        #expect(program.console[40, 8].character == Avatar.heart.glyph)
        #expect(row(13, of: program) == "> Heart <")
        program.handle(.space)
        #expect(program.avatar == .heart)
        #expect(program.screen == .menu)
    }

    @Test func everySubmenuEndsWithBackAfterAnEmptyLine() async throws {
        let program = try makeProgram()
        await program.run()

        program.press(at: (x: 40, y: 12))
        #expect(program.screen == .avatar)
        #expect(row(15, of: program).isEmpty)
        #expect(row(16, of: program) == "Back")
        program.press(at: (x: 40, y: 16))
        #expect(program.screen == .menu)
        #expect(program.selection == 3)

        program.press(at: (x: 40, y: 13))
        #expect(program.screen == .settings)
        #expect(row(14, of: program).isEmpty)
        #expect(row(15, of: program) == "Back")

        program.press(at: (x: 40, y: 11))
        #expect(program.screen == .theme)
        #expect(row(17, of: program) == "Back")
        program.press(at: (x: 40, y: 17))
        #expect(program.screen == .settings)

        program.handle(.down)
        program.handle(.enter)
        #expect(program.screen == .appIcon)
        program.moveSelection(10)
        #expect(row(17, of: program) == "> Back <")
        program.handle(.enter)
        #expect(program.screen == .settings)

        program.moveSelection(10)
        program.handle(.space)
        #expect(program.screen == .menu)
        #expect(program.selection == 4)
    }

    @Test func aNewGameWaitsForTheFirstTap() async throws {
        let program = try makeProgram()
        await program.run()
        program.confirm()
        #expect(program.screen == .playing)
        #expect(program.isWaitingToStart)
        #expect(row(9, of: program).contains("START"))
        #expect(program.game.score == 0)

        program.press(at: (x: 40, y: 12))
        #expect(!program.isWaitingToStart)
        #expect(!row(9, of: program).contains("START"))
        #expect(program.game.y == ClassicGame.startY - 1)
    }

    @Test func playingUntilGameOverSavesTheScore() async throws {
        let program = try makeProgram()
        var submitted: [Int] = []
        program.onScore = { submitted.append($0) }
        await program.run()
        program.confirm()
        #expect(program.screen == .playing)

        let ticks = playUntilGameOver(program)
        #expect(program.screen == .saveScore)
        #expect(submitted == [ticks * 2])
        #expect(program.console[20, 8].background == .green)

        program.setName("Pascal")
        program.saveScore()
        #expect(program.screen == .menu)
        #expect(program.scores.entries == [ScoreEntry(name: "Pascal", score: ticks * 2)])
    }

    @Test func restartKeepsTheScoreAndGoesStraightBackIn() async throws {
        let program = try makeProgram()
        await program.run()
        program.confirm()
        let ticks = playUntilGameOver(program)
        #expect(program.screen == .saveScore)

        program.setName("Pascal")
        program.saveAndRestart()
        #expect(program.scores.entries == [ScoreEntry(name: "Pascal", score: ticks * 2)])
        #expect(program.screen == .playing)
    }

    @Test func restartDoesNothingOutsideTheSaveScreen() async throws {
        let program = try makeProgram()
        await program.run()
        #expect(program.screen == .menu)
        program.saveAndRestart()
        #expect(program.screen == .menu)
        #expect(program.scores.entries.isEmpty)
    }

    @Test func tappingTheBottomBarSavesOnceTheNameIsTyped() async throws {
        let program = try makeProgram()
        await program.run()
        program.confirm()
        _ = playUntilGameOver(program)

        program.press(at: (x: 40, y: 17))
        #expect(program.screen == .saveScore)
        #expect(row(17, of: program).contains("continue"))

        program.setName("Tap")
        program.press(at: (x: 40, y: 12))
        #expect(program.screen == .saveScore)
        program.press(at: (x: 40, y: 17))
        #expect(program.screen == .menu)
        #expect(program.scores.entries.first?.name == "Tap")
    }

    @Test func theNameDialogSavesTheScore() async throws {
        let program = try makeProgram()
        program.playerAlias = { "Pandermatt" }
        await program.run()
        program.confirm()
        _ = playUntilGameOver(program)

        program.beginEditingName()
        #expect(program.isEditingName)
        #expect(program.draftName == "Pandermatt")
        #expect(!program.isTypingName)

        program.finishEditingName(save: false)
        #expect(!program.isEditingName)
        #expect(program.screen == .saveScore)

        program.beginEditingName()
        program.draftName = "Pascal"
        program.finishEditingName(save: true)
        #expect(program.screen == .menu)
        #expect(program.scores.entries.first?.name == "Pascal")
    }

    #if os(iOS)
    @Test func tappingTheNameOpensTheDialog() async throws {
        let program = try makeProgram()
        await program.run()
        program.confirm()
        _ = playUntilGameOver(program)
        program.press(at: (x: 40, y: 16))
        #expect(program.isEditingName)
    }
    #endif

    @Test func enterWhileTheNameIsStillTypingSavesTheWholeName() async throws {
        let program = try makeProgram()
        program.playerAlias = { "Pandermatt" }
        await program.run()
        program.confirm()
        _ = playUntilGameOver(program)
        #expect(program.screen == .saveScore)
        #expect(program.isTypingName)

        program.confirm()
        #expect(program.screen == .menu)
        #expect(!program.isTypingName)
        #expect(program.scores.entries.first?.name == "Pandermatt")
    }

    @Test func keyboardDrivesMenusAndNameEntry() async throws {
        let program = try makeProgram()
        await program.run()
        program.handle(.down)
        #expect(program.selection == 2)
        program.handle(.space)
        #expect(program.screen == .scoreTable)
        program.handle(.space)
        #expect(program.screen == .menu)
        program.handle(.enter)
        #expect(program.screen == .playing)

        _ = playUntilGameOver(program)
        program.handle(.space)
        #expect(program.screen == .saveScore)
        #expect(row(17, of: program).contains("continue"))

        program.setName("Pix")
        program.handle(.character("l"))
        program.handle(.character("y"))
        program.handle(.character("!"))
        program.handle(.space)
        #expect(program.screen == .saveScore)
        #expect(program.nameInput == "Pixly!")
        program.handle(.backspace)
        program.handle(.enter)
        #expect(program.screen == .menu)
        #expect(program.scores.entries.first?.name == "Pixly")
    }

    @Test func changingTheAvatar() async throws {
        let program = try makeProgram()
        await program.run()
        program.moveSelection(2)
        program.confirm()
        #expect(program.screen == .avatar)
        program.moveSelection(2)
        program.confirm()
        #expect(program.avatar == .diamond)
        #expect(program.console[40, 8].character == Avatar.diamond.glyph)
    }

    @Test func tappingAMenuRowActivatesIt() async throws {
        let program = try makeProgram()
        await program.run()
        program.press(at: (x: 40, y: 14))
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

    private func sessionWithPreferences(_ icons: FakeIconSwitcher) async throws -> (TerminalSession, Preferences) {
        let defaults = try #require(UserDefaults(suiteName: "pixly-session-\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults, iconSwitcher: icons)
        let session = await bootedSession()
        session.preferences = preferences
        return (session, preferences)
    }

    @Test func bootsIntoTheShell() async {
        let session = TerminalSession(charDelay: .zero, lineDelay: .zero)
        #expect(session.mode == .booting)
        await session.boot()
        #expect(session.mode == .shell)
        #expect(session.showsPrompt)
        #expect(session.lines.first?.text.hasPrefix("pixly shell") == true)
    }

    @Test func startTypesTheBuildCommandThenLaunches() async {
        let session = await bootedSession()
        await session.compileAndRun()
        #expect(session.mode == .program(.classic))
        #expect(session.lines.contains { $0.style == .command && $0.text == BootScript.buildCommand })
        #expect(session.lines.last?.text == "./pixly")

        session.programExited(runtime: 12.5, interrupted: false)
        #expect(session.mode == .shell)
        #expect(session.lines.contains { $0.text.hasPrefix("Process returned 1 (0x1)") })
    }

    @Test func helpListsCommandsAsTwoColumns() async {
        let session = await bootedSession()
        await session.submit("help")
        let entries = session.lines.filter { $0.style == .definition }
        #expect(entries.first?.label == "start")
        #expect(entries.first?.text == "compile & run pixly")
        #expect(entries.allSatisfy { ($0.label?.count ?? 99) <= 14 })
    }

    @Test func start2BuildsAndLaunchesPixly2() async {
        let session = await bootedSession()
        await session.submit("start2")
        #expect(session.mode == .program(.smooth))
        #expect(session.lines.contains { $0.style == .command && $0.text == BootScript.buildCommand2 })
        #expect(session.lines.last?.text == "./pixly2")
        #expect(!session.lines.contains { $0.style == .warning })

        session.programExited(runtime: 3, interrupted: true)
        #expect(session.mode == .shell)
        await session.submit("./pixly2")
        #expect(session.mode == .program(.smooth))
    }

    @Test func highscore2ListsTheSecondTable() async {
        let session = await bootedSession()
        session.highscores2 = { [ScoreEntry(name: "Smooth", score: 420)] }
        await session.submit("highscore2")
        #expect(session.lines.last?.text.hasSuffix("420  Smooth") == true)
        await session.submit("highscore")
        #expect(session.lines.last?.text == "no highscores yet. run ./pixly")
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
        await session.submit("cat credits.txt")
        #expect(session.lines.contains { $0.text == "© Pascal Andermatt, Jan Huber, Adrian Schrempp" })
        await session.submit("help")
        #expect(!session.lines.contains { ["credits", "theme [NAME]", "icon [NAME]", "ls, cat FILE", "./pixly", "clear"].contains($0.label) })
    }

    @Test func historyReadsTheBundledStoryWithoutAwardingSourceAchievement() async throws {
        let suite = "pixly-history-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TerminalSession(charDelay: .zero, lineDelay: .zero, defaults: defaults)
        await session.boot()
        var achievements: [Achievement] = []
        session.onAchievement = { achievements.append($0) }
        await session.submit("clear")
        await session.submit("history")
        let story = session.lines.dropFirst().map(\.text)
        #expect(story.first == "THE STORY OF PIXLY")
        #expect(story.contains { $0.contains("Winterthur") && $0.contains("C programming course") })
        #expect(!story.contains { $0.contains("Pascal") || $0.contains("Jan Huber") || $0.contains("Adrian") })
        #expect(achievements.isEmpty)
        await session.submit("clear")
        await session.submit("cat pixly-history.txt")
        #expect(session.lines.dropFirst().map(\.text) == story)
        #expect(achievements.isEmpty)
        #expect(session.mode == .shell)
    }

    @Test func historyFileSupportsDiscoveryRemovalAndRestore() async throws {
        let suite = "pixly-history-files-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TerminalSession(charDelay: .zero, lineDelay: .zero, defaults: defaults)
        await session.boot()
        await session.submit("ls")
        #expect(session.lines.last?.text.contains("pixly-history.txt") == true)
        await session.submit("help")
        #expect(session.lines.contains { $0.label == "history" })
        session.input = "hist"
        session.complete()
        #expect(session.input == "history ")
        session.input = "cat pixly-"
        session.complete()
        #expect(session.input == "cat pixly-history.txt ")
        await session.submit("rm pixly-history.txt")
        await session.submit("history")
        #expect(session.lines.last?.style == .error)
        #expect(session.lines.last?.text == "cat: pixly-history.txt: No such file or directory")
        await session.submit("git restore .")
        await session.submit("clear")
        await session.submit("history")
        #expect(session.lines.contains { $0.text == "THE STORY OF PIXLY" })
    }

    @Test func clearEmptiesTheScrollback() async {
        let session = await bootedSession()
        await session.submit("clear")
        #expect(session.lines.isEmpty)
    }

    @Test func themeCommandListsAndSwitchesThemes() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        await session.submit("theme")
        #expect(session.lines.contains { $0.text == "* classic" })
        await session.submit("theme Amber")
        #expect(preferences.theme == .amber)
        #expect(session.lines.last?.text == "theme: amber")
        await session.submit("theme neon")
        #expect(session.lines.last?.text == "theme: no such theme: neon")
    }

    @Test func iconCommandReportsUnsupportedDevices() async throws {
        let icons = FakeIconSwitcher()
        icons.isSupported = false
        let (session, _) = try await sessionWithPreferences(icons)
        await session.submit("icon amber")
        #expect(session.lines.last?.text == "icon: not supported on this device")
    }

    @Test func settingsAsksForEachValue() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        let command = Task { await session.submit("settings") }

        await answer("amber", to: "theme (classic, phosphor, amber, light) [classic]:", in: session)
        #expect(session.isBusy)
        await answer("", to: "icon", in: session)
        await answer("dragon", to: "avatar", in: session)
        await answer("Heart", to: "avatar", in: session)
        await answer("on", to: "scanlines (on, off) [off]:", in: session)
        await command.value

        #expect(session.question == nil)
        #expect(!session.isBusy)
        #expect(preferences.theme == .amber)
        #expect(preferences.appIcon == .classic)
        #expect(preferences.avatar == .heart)
        #expect(preferences.scanlines)
        #expect(session.lines.contains { $0.style == .answer && $0.label?.hasPrefix("theme") == true && $0.text == "amber" })
        #expect(session.lines.contains { $0.text == "✗ no such avatar: dragon" })
        #expect(session.lines.contains { $0.text == "✓ avatar = heart" })
        #expect(session.lines.last?.text == "saved to ~/.pixlyrc")
    }

    @Test func settingsWithArgumentsSetsDirectly() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        await session.submit("settings avatar diamond")
        #expect(preferences.avatar == .diamond)
        #expect(session.lines.last?.text == "avatar: diamond")
        await session.submit("settings volume 11")
        #expect(session.lines.last?.text == "settings: unknown setting 'volume' (theme, icon, avatar, scanlines)")
    }

    @Test func pixlyrcIsListedAndCatable() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        preferences.setTheme(.amber)
        preferences.setScanlines(false)
        await session.submit("ls -a")
        #expect(session.lines.last?.text.hasPrefix(".  ..  .pixlyrc  Pixly.xcodeproj  Pixly2.swift  ball.c") == true)
        await session.submit("cat ~/.pixlyrc")
        #expect(session.lines.suffix(5).map(\.text) == [
            "# ~/.pixlyrc — written by `settings`",
            "theme = amber",
            "icon = classic",
            "avatar = pixel",
            "scanlines = off",
        ])
    }

    @Test func tabCompletesCommandsFilesAndValues() async throws {
        let (session, _) = try await sessionWithPreferences(FakeIconSwitcher())
        session.input = "se"
        session.complete()
        #expect(session.input == "settings ")
        session.complete()
        #expect(session.lines.last?.text == "theme  icon  avatar  scanlines")
        session.input = "settings sc"
        session.complete()
        #expect(session.input == "settings scanlines ")
        session.input = "cat .p"
        session.complete()
        #expect(session.input == "cat .pixlyrc ")
        session.input = "theme a"
        session.complete()
        #expect(session.input == "theme amber ")
        session.input = "s"
        session.complete()
        #expect(session.input == "s")
        #expect(session.lines.last?.text == "scanlines  settings  start  start2  sudo")
        session.input = "./pix"
        session.complete()
        #expect(session.input == "./pixly")
        session.input = "wh"
        session.complete()
        #expect(session.input == "whoami ")
    }

    @Test func tabCompletesSettingsAnswers() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        let command = Task { await session.submit("settings") }
        for _ in 0..<200 where session.question == nil {
            await Task.yield()
        }
        session.input = "ph"
        session.complete()
        #expect(session.input == "phosphor")
        await session.submit(session.input)
        for key in ["icon", "avatar", "scanlines"] {
            await answer("", to: key, in: session)
        }
        await command.value
        #expect(preferences.theme == .phosphor)
    }

    private func sessionWithFiles() async throws -> (TerminalSession, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "pixly-files-\(UUID().uuidString)"))
        let session = TerminalSession(charDelay: .zero, lineDelay: .zero, defaults: defaults)
        await session.boot()
        return (session, defaults)
    }

    @Test func scoreFilesAreListedCatableAndRemovable() async throws {
        let (session, _) = try await sessionWithFiles()
        var classic = [ScoreEntry(name: "Pascal", score: 420), ScoreEntry(name: "Jan", score: 99)]
        session.highscores = { classic }
        session.resetScores = { program in
            if program == .classic { classic = [] }
        }
        await session.submit("ls")
        #expect(session.lines.last?.text.contains("consoleio.h  credits.txt  highscore.txt  landscape.c") == true)
        #expect(session.lines.last?.text.contains("highscore2.txt") == false)
        await session.submit("cat highscore.txt")
        #expect(session.lines.suffix(2).map(\.text) == ["Pascal§420", "Jan§99"])

        await session.submit("rm highscore.txt")
        #expect(classic.isEmpty)
        await session.submit("highscore")
        #expect(session.lines.last?.text == "no highscores yet. run ./pixly")
        await session.submit("cat highscore.txt")
        #expect(session.lines.last?.text == "cat: highscore.txt: No such file or directory")
        await session.submit("rm highscore2.txt")
        #expect(session.lines.last?.text == "rm: highscore2.txt: No such file or directory")
    }

    @Test func removedSourcesBreakTheBuildUntilRestored() async throws {
        let (session, defaults) = try await sessionWithFiles()
        await session.submit("rm ball.h *.cbp")
        #expect(!session.canRestore)
        await session.submit("ls")
        #expect(session.lines.last?.text.hasPrefix("Pixly.xcodeproj  Pixly2.swift  ball.c  consoleio.h  credits.txt  landscape.c") == true)
        #expect(session.restoreTitle == "restore C files")
        await session.submit("cat ball.h")
        #expect(session.lines.last?.text == "cat: ball.h: No such file or directory")

        await session.compileAndRun()
        #expect(session.mode == .shell)
        #expect(session.canRestore)
        #expect(session.lines.contains { $0.text == "main.c:8:10: fatal error: ball.h: No such file or directory" })
        #expect(session.lines.last?.text == "compilation terminated.")

        let relaunched = TerminalSession(charDelay: .zero, lineDelay: .zero, defaults: defaults)
        #expect(relaunched.removedFiles == ["ball.h", "pixly.cbp"])

        await session.restoreFiles()
        #expect(!session.canRestore)
        #expect(session.lines.suffix(2).map(\.text) == [BootScript.restoreCommand, "Updated 2 paths from the index"])
        await session.compileAndRun()
        #expect(session.mode == .program(.classic))
    }

    @Test func removingEverything() async throws {
        let (session, _) = try await sessionWithFiles()
        await session.submit("rm -rf *")
        await session.submit("ls")
        #expect(session.lines.last?.style == .command)
        await session.submit("rm *.c")
        #expect(session.lines.last?.text == "zsh: no matches found: *.c")
        await session.compileAndRun()
        #expect(session.mode == .shell)
        #expect(session.lines.contains { $0.text == "gcc: error: main.c: No such file or directory" })
    }

    @Test func removingPixlyrcResetsTheSettings() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        preferences.setTheme(.amber)
        preferences.setAvatar(.heart)
        preferences.setScanlines(true)
        await session.submit("rm .pixlyrc")
        #expect(preferences.theme == .classic)
        #expect(preferences.avatar == .pixel)
        #expect(!preferences.scanlines)
        preferences.setTheme(.light)
        await session.submit("rm ~/.pixlyrc")
        #expect(preferences.theme == .classic)
        await session.submit("cat .pixlyrc")
        #expect(session.lines.suffix(4).map(\.text) == ["theme = classic", "icon = classic", "avatar = pixel", "scanlines = off"])
    }

    @Test func theRootDirectoryMayNotBeRemoved() async throws {
        let (session, _) = try await sessionWithFiles()
        for command in ["rm -rf /", "rm /", "rm -rf /*"] {
            await session.submit(command)
            #expect(session.lines.last?.text == "rm: \"/\" may not be removed")
        }
        #expect(session.mode == .shell)
        #expect(session.removedFiles.isEmpty)
    }

    @Test func swiftSourceLinksToGitHubAndTheProjectIsADirectory() async throws {
        let (session, _) = try await sessionWithFiles()
        await session.submit("cat Pixly2.swift")
        #expect(session.lines.contains { $0.text.contains("static let jumpVelocity") })
        #expect(session.lines.last?.style == .link)
        #expect(session.lines.last?.text == BootScript.repository)
        await session.submit("cat Pixly.xcodeproj")
        #expect(session.lines.last?.text == "cat: Pixly.xcodeproj: Is a directory")
        await session.submit("ls Pixly.xcodeproj")
        #expect(session.lines.last?.text == BootScript.xcodeprojContents)
        await session.submit("open Pixly.xcodeproj")
        #expect(session.lines.last?.style == .link)
        await session.submit("rm Pixly.xcodeproj")
        #expect(session.lines.last?.text == "rm: Pixly.xcodeproj: is a directory")
        #expect(session.removedFiles.isEmpty)
        await session.submit("rm -r Pixly.xcodeproj")
        #expect(session.removedFiles == ["Pixly.xcodeproj"])
    }

    @Test func removingTheSwiftFileBreaksPixly2UntilRestored() async throws {
        let (session, _) = try await sessionWithFiles()
        await session.submit("rm Pixly2.swift")
        await session.compileAndRun(.smooth)
        #expect(session.mode == .shell)
        #expect(session.canRestore)
        #expect(session.restoreTitle == "restore files")
        #expect(session.lines.last?.text == "<unknown>:0: error: no such file or directory: 'Pixly2.swift'")
        await session.submit("git status")
        #expect(session.lines.last?.text.hasSuffix("deleted:    Pixly2.swift") == true)
        await session.restoreFiles()
        await session.compileAndRun(.smooth)
        #expect(session.mode == .program(.smooth))
    }

    @Test func hiddenJokes() async throws {
        let (session, preferences) = try await sessionWithPreferences(FakeIconSwitcher())
        preferences.setTheme(.amber)
        preferences.setAvatar(.heart)
        var earned: [Achievement] = []
        session.onAchievement = { earned.append($0) }
        await session.submit("neofetch")
        #expect(session.lines.contains { $0.label == "Theme" && $0.text == "amber" })
        #expect(session.lines.contains { $0.label == "Avatar" && $0.text == "heart" })
        #expect(session.lines.last?.style == .palette)
        await session.submit("git")
        #expect(session.lines.contains { $0.text.hasPrefix("what is git?") })
        await session.submit("git push --force")
        #expect(session.lines.last?.text == "(just kidding. nothing changed.)")
        await session.submit("git rebase")
        #expect(session.lines.last?.text == "git: 'rebase' is not a git command. See 'git --help'.")
        await session.submit("ping pixel")
        #expect(session.lines.last?.text == "PONG")
        await session.submit("brew coffee")
        #expect(session.lines.last?.text == "418 I'm a teapot")
        await session.submit("make coffee")
        #expect(session.mode == .shell)
        #expect(session.lines.last?.text == "418 I'm a teapot")
        await session.submit("top")
        #expect(session.lines.contains { $0.text.contains("pixel") && $0.text.contains("99.9") })
        #expect(ShellJokes.duration(3_725) == "1 h, 2 mins")
        await session.submit("cat ball.c")
        #expect(earned == [.showOff, .fridayDeploy, .teapot, .teapot, .readTheSource])
    }

    /// Waits until the session asks a question starting with `prefix`, then answers it.
    private func answer(_ text: String, to prefix: String, in session: TerminalSession) async {
        for _ in 0..<200 where session.question?.hasPrefix(prefix) != true {
            await Task.yield()
        }
        #expect(session.question?.hasPrefix(prefix) == true)
        await session.submit(text)
    }
}
