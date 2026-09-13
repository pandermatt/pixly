import Foundation
import Observation
import QuartzCore

/// The original offered CP437 characters 254, 1 and 3; the rest are more glyphs from that set.
enum Avatar: String, CaseIterable, Sendable {
    case pixel, smiley, heart, darkSmiley, diamond, club, spade, sun, note

    var glyph: Character {
        switch self {
        case .pixel: "■"
        case .smiley: "☺\u{FE0E}"
        case .heart: "♥\u{FE0E}"
        case .darkSmiley: "☻\u{FE0E}"
        case .diamond: "♦\u{FE0E}"
        case .club: "♣\u{FE0E}"
        case .spade: "♠\u{FE0E}"
        case .sun: "☼\u{FE0E}"
        case .note: "♪\u{FE0E}"
        }
    }

    var title: String {
        switch self {
        case .pixel: "Pixel"
        case .smiley: "Smiley"
        case .heart: "Heart"
        case .darkSmiley: "Dark Smiley"
        case .diamond: "Diamond"
        case .club: "Club"
        case .spade: "Spade"
        case .sun: "Sun"
        case .note: "Note"
        }
    }
}

/// Port of main.c and score.c: the loading bar, menus and save-score window, drawn into an
/// 80×25 console buffer.
@Observable @MainActor
final class PixlyProgram {
    enum Screen: Equatable, Sendable {
        case loading, menu, avatar, playing, saveScore, scoreTable, credits, finished
    }

    struct Menu: Sendable {
        let title: String
        let items: [String]
        let firstRow: Int
    }

    static let mainMenu = Menu(title: "", items: ["New Game", "Highscore", "Change Avatar", "Credits", "Quit"], firstRow: 10)
    static let avatarMenu = Menu(title: "Avatar", items: Avatar.allCases.map(\.title), firstRow: 12)
    private static let pressAnyKey = "Press any key to continue . . ."
    private static let pressEnter = "Press enter to continue"
    private static let avatarKey = "avatar"

    private(set) var console = ConsoleBuffer()
    private(set) var screen = Screen.loading
    private(set) var selection = 1
    private(set) var isPaused = false
    private(set) var jumpCount = 0
    private(set) var nameInput = ""
    private(set) var isTypingName = false
    private(set) var avatar: Avatar
    private(set) var scores: ScoreStore
    @ObservationIgnored private(set) var game = PixelEscapeGame()

    @ObservationIgnored var playerAlias: @MainActor () -> String? = { nil }
    @ObservationIgnored var onScore: @MainActor (Int) -> Void = { _ in }
    @ObservationIgnored var onQuit: @MainActor (TimeInterval) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loadingStep: Duration
    @ObservationIgnored private let startDate = Date()
    @ObservationIgnored private var ticker: DisplayLinkTicker?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var nameTask: Task<Void, Never>?
    @ObservationIgnored private var pendingName = ""
    @ObservationIgnored private var saveScoreBar = ConsoleColor.green
    @ObservationIgnored private var isTerminated = false

    init(defaults: UserDefaults = .standard, loadingStep: Duration = .milliseconds(12)) {
        self.defaults = defaults
        self.loadingStep = loadingStep
        scores = ScoreStore(defaults: defaults)
        avatar = defaults.string(forKey: Self.avatarKey).flatMap(Avatar.init(rawValue:)) ?? .pixel
    }

    var runtime: TimeInterval {
        Date().timeIntervalSince(startDate)
    }

    private var currentMenu: Menu? {
        switch screen {
        case .menu: Self.mainMenu
        case .avatar: Self.avatarMenu
        default: nil
        }
    }

    // MARK: - Lifecycle

    func run() async {
        guard screen == .loading, !isTerminated else { return }
        await showLoading(title: "Pixly", ascii: "_")
        guard !isTerminated else { return }
        showMainMenu()
    }

    func terminate() {
        isTerminated = true
        stopTicker()
        nameTask?.cancel()
        screen = .finished
    }

    // MARK: - Input

    /// A touch landed on the console (or outside the grid when `cell` is nil).
    func press(at cell: (x: Int, y: Int)?) {
        switch screen {
        case .menu, .avatar:
            guard let cell, let menu = currentMenu else { return }
            let index = cell.y - menu.firstRow
            guard menu.items.indices.contains(index) else { return }
            selection = index + 1
            drawMenu(menu)
            confirm()
        case .playing:
            jump()
        case .scoreTable, .credits:
            showMainMenu()
        case .loading, .saveScore, .finished:
            break
        }
    }

    enum Key: Equatable, Sendable {
        case space, up, down, enter, backspace
        case character(String)
    }

    /// Keyboard input, like the `_getch()` loops in main.c and score.c.
    func handle(_ key: Key, isRepeat: Bool = false) {
        let editsName = screen == .saveScore && !isTypingName
        switch key {
        case .enter:
            if !isRepeat { confirm() }
        case .space:
            switch screen {
            case .playing: jump()
            case .menu, .avatar, .scoreTable, .credits: if !isRepeat { confirm() }
            // Space selects everywhere except here, where only Enter may close the window.
            case .saveScore: showContinueHint()
            case .loading, .finished: break
            }
        case .up:
            moveSelection(-1)
        case .down:
            moveSelection(1)
        case .backspace:
            if editsName { setName(String(nameInput.dropLast())) }
        case .character(let text):
            switch screen {
            case .playing where text.lowercased() == "q":
                quitGame()
            case .saveScore where editsName:
                let printable = text.filter { $0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol }
                setName(nameInput + printable)
            case .scoreTable, .credits:
                // system("PAUSE"): any key continues.
                if !isRepeat { confirm() }
            default:
                break
            }
        }
    }

    func moveSelection(_ delta: Int) {
        guard let menu = currentMenu else { return }
        selection = min(max(selection + delta, 1), menu.items.count)
        drawMenu(menu)
    }

    func confirm() {
        switch screen {
        case .menu:
            switch selection {
            case 1: startGame()
            case 2: showScoreTable()
            case 3: showAvatarMenu()
            case 4: showCredits()
            default: quit()
            }
        case .avatar:
            avatar = Avatar.allCases[selection - 1]
            defaults.set(avatar.rawValue, forKey: Self.avatarKey)
            showMainMenu()
        case .saveScore:
            saveScore()
        case .scoreTable, .credits:
            showMainMenu()
        case .loading, .playing, .finished:
            break
        }
    }

    func jump() {
        guard screen == .playing else { return }
        if isPaused {
            isPaused = false
            lastTimestamp = nil
        }
        game.jump()
        jumpCount += 1
        renderGame()
    }

    /// The `q` key: stop playing and save the score so far.
    func quitGame() {
        guard screen == .playing else { return }
        endGame()
    }

    func pause() {
        guard screen == .playing, !isPaused else { return }
        isPaused = true
        renderGame()
    }

    func setName(_ name: String) {
        guard screen == .saveScore else { return }
        stopTypingName()
        nameInput = String(name.prefix(ScoreStore.maxNameLength))
        drawName()
    }

    func saveScore() {
        guard screen == .saveScore else { return }
        if isTypingName {
            nameInput = pendingName
        }
        stopTypingName()
        scores.add(name: nameInput, score: game.score)
        showMainMenu()
    }

    // MARK: - Game loop

    /// One 20 ms step of the `while (restart == 1)` loop in main.c.
    func advance() {
        guard screen == .playing else { return }
        game.tick()
        renderGame()
        if game.isOver {
            endGame()
        }
    }

    private func startGame() {
        game = PixelEscapeGame()
        isPaused = false
        accumulator = 0
        lastTimestamp = nil
        screen = .playing
        renderGame()
        if ticker == nil {
            let ticker = DisplayLinkTicker { [weak self] timestamp in
                self?.frame(timestamp)
            }
            self.ticker = ticker
            ticker.start()
        }
    }

    private func frame(_ timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard screen == .playing, !isPaused, let lastTimestamp else { return }
        accumulator += min(timestamp - lastTimestamp, 0.1)
        while accumulator >= PixelEscapeGame.tickInterval, screen == .playing {
            accumulator -= PixelEscapeGame.tickInterval
            advance()
        }
    }

    private func stopTicker() {
        ticker?.stop()
        ticker = nil
        lastTimestamp = nil
    }

    private func endGame() {
        stopTicker()
        onScore(game.score)
        showSaveScore(score: game.score)
    }

    // MARK: - Screens

    private func showLoading(title: String, ascii: Character) async {
        // The 30-cell bar spans columns 25–54; title and a fixed-width "[ 84%]" share its centre.
        screen = .loading
        draw { c in
            c.textcolor(.white, .black)
            c.clrscr()
            c.gotoxy(40 - (title.count + 1) / 2, 12)
            c.write(title)
            c.textcolor(.lightBlue, .black)
            c.gotoxy(25, 14)
            c.write(String(repeating: ascii, count: 30))
        }
        for percent in 0...100 {
            guard !isTerminated else { return }
            if loadingStep > .zero {
                try? await Task.sleep(for: loadingStep)
            }
            let label = "[" + pad(String(percent), 3) + "%]"
            draw { c in
                c.gotoxy(37, 13)
                c.textcolor(.white, .black)
                c.write(label)
                c.gotoxy(25 + percent * 29 / 100, 14)
                c.write(String(ascii))
            }
        }
    }

    private func showMainMenu() {
        screen = .menu
        selection = 1
        let glyph = avatar.glyph
        draw { c in
            c.textcolor(.white, .black)
            c.clrscr()
            c.gotoxy(40, 8)
            c.write(String(glyph))
        }
        drawMenu(Self.mainMenu)
    }

    private func showAvatarMenu() {
        screen = .avatar
        selection = (Avatar.allCases.firstIndex(of: avatar) ?? 0) + 1
        draw { c in
            c.textcolor(.white, .black)
            c.clrscr()
        }
        drawMenu(Self.avatarMenu)
    }

    /// Entries are centred like in main.c; the selection is white with a symmetric marker,
    /// the rest dark grey. The avatar menu also previews the highlighted avatar.
    private func drawMenu(_ menu: Menu) {
        let selection = selection
        let preview = screen == .avatar ? Avatar.allCases[selection - 1].glyph : nil
        draw { c in
            c.textcolor(.white, .black)
            c.gotoxy(ConsoleBuffer.centeredX(menu.title), 5)
            c.write(menu.title)
            if let preview {
                // A strip of tunnel with the avatar and its trail, as it looks in the game.
                c.textcolor(.black, .white)
                for y in 7...9 {
                    c.gotoxy(32, y)
                    c.write(String(repeating: " ", count: 16))
                }
                for (index, row) in [9, 9, 8, 8].enumerated() {
                    c.gotoxy(36 + index, row)
                    c.write(".")
                }
                c.gotoxy(40, 8)
                c.write(String(preview))
            }
            for (index, item) in menu.items.enumerated() {
                let row = menu.firstRow + index
                let isSelected = index + 1 == selection
                let text = isSelected ? "> \(item) <" : item
                c.textcolor(.white, .black)
                c.gotoxy(1, row)
                c.write(String(repeating: " ", count: ConsoleBuffer.columns))
                c.textcolor(isSelected ? .white : .darkGray, .black)
                c.gotoxy(ConsoleBuffer.centeredX(text), row)
                c.write(text)
            }
        }
    }

    private func showScoreTable() {
        screen = .scoreTable
        let entries = scores.entries.prefix(13)
        draw { c in
            c.textcolor(.white, .black)
            c.clrscr()
            c.write("\n\n\n\n")
            c.write("  " + pad("Rank", 20) + " " + pad("Score", 10) + pad("Name", 26) + "\n")
            c.write("\n")
            for (index, entry) in entries.enumerated() {
                c.write("  " + pad(String(index + 1), 20) + " " + pad(String(entry.score), 10) + "  " + pad(entry.name, 24) + "\n")
            }
            c.write("\n\n\n\n")
            c.write("\t\t   " + Self.pressAnyKey)
        }
    }

    private func showCredits() {
        screen = .credits
        draw { c in
            c.textcolor(.white, .black)
            c.clrscr()
            c.gotoxy(20, 11)
            c.write("© Pascal Andermatt, Jan Huber, Adrian Schrempp")
            c.gotoxy(24, 13)
            c.write(Self.pressAnyKey)
        }
    }

    private func quit() {
        terminate()
        onQuit(runtime)
    }

    /// `showSaveScore()` from score.c.
    private func showSaveScore(score: Int) {
        screen = .saveScore
        let isHighscore = score > scores.best
        saveScoreBar = isHighscore ? .green : .lightRed
        draw { c in
            for y in 8..<18 {
                let isBar = y > 16 || y < 9
                c.textcolor(.white, isBar ? (isHighscore ? .green : .lightRed) : .white)
                c.gotoxy(20, y)
                c.write(String(repeating: " ", count: 40))
            }
            if isHighscore {
                c.textcolor(.white, .green)
                c.gotoxy(ConsoleBuffer.centeredX("NEW HIGHSCORE"), 8)
                c.write("NEW HIGHSCORE")
            }
            c.textcolor(.black, .white)
            c.gotoxy(ConsoleBuffer.centeredX("GAME OVER!"), 10)
            c.write("GAME OVER!")
            c.gotoxy(ConsoleBuffer.centeredX("GAME OVER!"), 11)
            c.write("__________")
            let congratulations = "Congratulations, your score is \(score)"
            c.gotoxy(ConsoleBuffer.centeredX(congratulations), 13)
            c.write(congratulations)
            let prompt = "Please enter your name:"
            c.gotoxy(ConsoleBuffer.centeredX(prompt), 14)
            c.write(prompt)
        }
        nameInput = ""
        drawName()
        typeName(playerAlias() ?? "")
    }

    /// Types the Game Center alias into the prompt. Runs (after a short pause) even without an
    /// alias, so keys still held from playing don't immediately edit the name.
    private func typeName(_ name: String) {
        nameTask?.cancel()
        pendingName = String(name.prefix(ScoreStore.maxNameLength))
        isTypingName = true
        nameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let name = self?.pendingName else { return }
            for character in name {
                guard !Task.isCancelled, let self, self.screen == .saveScore else { return }
                self.nameInput.append(character)
                self.drawName()
                try? await Task.sleep(for: .milliseconds(Int.random(in: 60...120)))
            }
            guard !Task.isCancelled else { return }
            self?.isTypingName = false
        }
    }

    /// Written into the bottom bar of the save-score window when space is pressed.
    private func showContinueHint() {
        let bar = saveScoreBar
        draw { c in
            c.textcolor(.white, bar)
            c.gotoxy(ConsoleBuffer.centeredX(Self.pressEnter), 17)
            c.write(Self.pressEnter)
        }
    }

    private func stopTypingName() {
        nameTask?.cancel()
        isTypingName = false
    }

    private func drawName() {
        let name = nameInput
        draw { c in
            c.textcolor(.black, .white)
            c.gotoxy(20, 16)
            c.write(String(repeating: " ", count: 40))
            c.gotoxy(ConsoleBuffer.centeredX(name), 16)
            c.write(name)
        }
    }

    private func renderGame() {
        let game = game
        let glyph = avatar.glyph
        let highscore = scores.highscore(game.score)
        let isPaused = isPaused
        draw { c in
            for y in 1...24 {
                for x in 1...ConsoleBuffer.columns {
                    c.set(x, y, .init(character: " ", foreground: .black, background: game.isSolid(x: x, y: y) ? .black : .white))
                }
            }
            if let obstacleX = game.obstacleX {
                for y in game.obstacleStart..<game.obstacleStart + PixelEscapeGame.obstacleHeight {
                    c.set(obstacleX, y, .init(character: " ", foreground: .red, background: .red))
                }
            }
            for (index, row) in game.tail.enumerated() where (1...24).contains(row) && !game.isSolid(x: index + 1, y: row) {
                c.set(index + 1, row, .init(character: ".", foreground: .black, background: .white))
            }
            if (1...24).contains(game.y) {
                c.set(PixelEscapeGame.playerX, game.y, .init(character: glyph, foreground: .black, background: .white))
            }

            c.textcolor(.white, .black)
            c.gotoxy(1, 25)
            c.write(String(repeating: " ", count: ConsoleBuffer.columns - 1))
            c.gotoxy(2, 25)
            c.write(String(game.score))
            c.gotoxy(70, 25)
            c.write(pad(String(highscore), 9))
            if isPaused {
                #if os(macOS)
                let text = "PAUSED - press space to continue"
                #else
                let text = "PAUSED - tap to continue"
                #endif
                c.gotoxy(ConsoleBuffer.centeredX(text), 25)
                c.write(text)
            }
        }
    }

    private func draw(_ body: (inout ConsoleBuffer) -> Void) {
        var buffer = console
        body(&buffer)
        console = buffer
    }
}

/// printf's right-aligned `%Ns`.
private func pad(_ text: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - text.count)) + text
}
