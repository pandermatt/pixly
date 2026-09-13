import Foundation
import Observation
import QuartzCore

/// Avatars drawn with CP437 glyphs, as in the original's "Avatar wechseln" menu.
enum Avatar: String, CaseIterable, Sendable {
    case pixel, heart, diamond

    var glyph: Character {
        switch self {
        case .pixel: "■"
        case .heart: "♥\u{FE0E}"
        case .diamond: "♦\u{FE0E}"
        }
    }

    var title: String {
        switch self {
        case .pixel: "Pixel"
        case .heart: "Heart"
        case .diamond: "Diamond"
        }
    }
}

/// Port of main.c and score.c: the loading bar, menus and save-score window, drawn into an
/// 80×25 console buffer.
@Observable @MainActor
final class PixlyProgram {
    enum Screen: Equatable, Sendable {
        case loading, menu, avatar, settings, theme, appIcon, playing, saveScore, scoreTable, credits, finished
    }

    /// A centred list of entries. Submenus end with an empty line and "Back".
    struct Menu: Sendable {
        let title: String
        let items: [String]
        let firstRow: Int
        var hasBack = false

        /// Number of selectable entries, including Back.
        var count: Int { items.count + (hasBack ? 1 : 0) }

        func isBack(_ selection: Int) -> Bool {
            hasBack && selection == items.count + 1
        }

        func label(_ selection: Int) -> String {
            isBack(selection) ? "Back" : items[selection - 1]
        }

        func row(for selection: Int) -> Int {
            isBack(selection) ? firstRow + items.count + 1 : firstRow + selection - 1
        }

        func selection(atRow row: Int) -> Int? {
            if (firstRow..<firstRow + items.count).contains(row) { return row - firstRow + 1 }
            if hasBack, row == firstRow + items.count + 1 { return items.count + 1 }
            return nil
        }
    }

    enum Key: Equatable, Sendable {
        case space, up, down, enter, escape, backspace
        case character(String)
    }

    static let mainMenu = Menu(title: "", items: ["New Game", "Highscore", "Change Avatar", "Settings", "Credits", "Quit"], firstRow: 10)
    static let avatarMenu = Menu(title: "Avatar", items: Avatar.allCases.map(\.title), firstRow: 12, hasBack: true)
    private static let pressAnyKey = "Press any key to continue . . ."
    #if os(macOS)
    private static let continueHint = "Press enter to continue"
    #else
    private static let continueHint = "Tap here or press enter to continue"
    #endif
    private static let saveBarRow = 17
    private static let nameRow = 16

    private(set) var console = ConsoleBuffer()
    private(set) var screen = Screen.loading
    private(set) var selection = 1
    private(set) var isPaused = false
    private(set) var jumpCount = 0
    private(set) var nameInput = ""
    private(set) var isTypingName = false
    /// The name dialog is open (touch devices, where typing into the console is too small to see).
    var isEditingName = false
    var draftName = ""
    private(set) var scores: ScoreStore
    @ObservationIgnored private(set) var game = PixelEscapeGame()
    @ObservationIgnored private(set) var iconTask: Task<Void, Never>?

    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored var playerAlias: @MainActor () -> String? = { nil }
    @ObservationIgnored var onScore: @MainActor (Int) -> Void = { _ in }
    @ObservationIgnored var onQuit: @MainActor (TimeInterval) -> Void = { _ in }

    @ObservationIgnored private let loadingStep: Duration
    @ObservationIgnored private let startDate = Date()
    @ObservationIgnored private var ticker: DisplayLinkTicker?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var nameTask: Task<Void, Never>?
    @ObservationIgnored private var pendingName = ""
    @ObservationIgnored private var saveScoreBar = ConsoleColor.green
    @ObservationIgnored private var iconStatus: String?
    @ObservationIgnored private var isTerminated = false

    init(preferences: Preferences, defaults: UserDefaults = .standard, loadingStep: Duration = .milliseconds(12)) {
        self.preferences = preferences
        self.loadingStep = loadingStep
        scores = ScoreStore(defaults: defaults)
    }

    var avatar: Avatar {
        preferences.avatar
    }

    var runtime: TimeInterval {
        Date().timeIntervalSince(startDate)
    }

    private var currentMenu: Menu? {
        switch screen {
        case .menu: Self.mainMenu
        case .avatar: Self.avatarMenu
        case .settings: settingsMenu
        case .theme: choiceMenu(title: "Theme", current: preferences.theme)
        case .appIcon: choiceMenu(title: "App Icon", current: preferences.appIcon)
        default: nil
        }
    }

    private var settingsMenu: Menu {
        Menu(
            title: "Settings",
            items: [
                "Theme: \(preferences.theme.title)",
                "App Icon: \(preferences.appIcon.title)",
                "Scanlines: \(preferences.scanlines ? "On" : "Off")",
            ],
            firstRow: 11,
            hasBack: true
        )
    }

    private func choiceMenu(title: String, current: ThemeID) -> Menu {
        Menu(title: title, items: ThemeID.allCases.map { $0 == current ? "\($0.title) (current)" : $0.title }, firstRow: 12, hasBack: true)
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
        iconTask?.cancel()
        preferences.previewTheme = nil
        screen = .finished
    }

    // MARK: - Input

    /// A touch landed on the console (or outside the grid when `cell` is nil).
    func press(at cell: (x: Int, y: Int)?) {
        switch screen {
        case .menu, .avatar, .settings, .theme, .appIcon:
            guard let cell, let menu = currentMenu, let choice = menu.selection(atRow: cell.y) else { return }
            selection = choice
            selectionDidChange(menu)
            confirm()
        case .playing:
            jump()
        case .saveScore:
            // The bottom bar doubles as a button, so the window can be closed without a keyboard.
            if let cell, cell.y == Self.saveBarRow, (20..<60).contains(cell.x), !isTypingName {
                saveScore()
            } else if let cell, cell.y == Self.nameRow, (20..<60).contains(cell.x) {
                #if os(macOS)
                showContinueHint()
                #else
                beginEditingName()
                #endif
            } else {
                showContinueHint()
            }
        case .scoreTable, .credits:
            showMainMenu()
        case .loading, .finished:
            break
        }
    }

    /// Keyboard input, like the `_getch()` loops in main.c and score.c.
    func handle(_ key: Key, isRepeat: Bool = false) {
        let editsName = screen == .saveScore && !isTypingName
        switch key {
        case .enter:
            if !isRepeat { confirm() }
        case .escape:
            if !isRepeat { goBack() }
        case .space:
            switch screen {
            case .playing: jump()
            case .menu, .avatar, .settings, .theme, .appIcon, .scoreTable, .credits: if !isRepeat { confirm() }
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

    /// The pointer moved over the console: an entry under it becomes the selection.
    func hover(at cell: (x: Int, y: Int)) {
        guard let menu = currentMenu, let choice = menu.selection(atRow: cell.y), choice != selection else { return }
        let target = "> \(menu.label(choice)) <"
        let start = ConsoleBuffer.centeredX(target)
        guard (start..<start + target.count).contains(cell.x) else { return }
        selection = choice
        selectionDidChange(menu)
    }

    func moveSelection(_ delta: Int) {
        guard let menu = currentMenu else { return }
        selection = min(max(selection + delta, 1), menu.count)
        selectionDidChange(menu)
    }

    func confirm() {
        if let menu = currentMenu, menu.isBack(selection) {
            goBack()
            return
        }
        switch screen {
        case .menu:
            switch selection {
            case 1: startGame()
            case 2: showScoreTable()
            case 3: showAvatarMenu()
            case 4: showSettings()
            case 5: showCredits()
            default: quit()
            }
        case .avatar:
            preferences.setAvatar(Avatar.allCases[selection - 1])
            showMainMenu(selection: 3)
        case .settings:
            switch selection {
            case 1: showChoiceMenu(.theme, current: preferences.theme)
            case 2: showChoiceMenu(.appIcon, current: preferences.appIcon)
            default:
                preferences.setScanlines(!preferences.scanlines)
                drawMenu(settingsMenu)
            }
        case .theme:
            preferences.setTheme(ThemeID.allCases[selection - 1])
            showSettings(selection: 1)
        case .appIcon:
            applyIcon(ThemeID.allCases[selection - 1])
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

    /// Opens the name dialog with the name typed so far (finishing the Game Center alias first).
    func beginEditingName() {
        guard screen == .saveScore else { return }
        if isTypingName {
            nameInput = pendingName
            drawName()
        }
        stopTypingName()
        draftName = nameInput
        isEditingName = true
    }

    /// Closes the name dialog; saving takes the name and stores the score in one step.
    func finishEditingName(save: Bool) {
        isEditingName = false
        guard save, screen == .saveScore else { return }
        setName(draftName)
        saveScore()
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

    private func goBack() {
        switch screen {
        case .avatar: showMainMenu(selection: 3)
        case .settings: showMainMenu(selection: 4)
        case .theme: showSettings(selection: 1)
        case .appIcon: showSettings(selection: 2)
        case .scoreTable, .credits: showMainMenu()
        default: break
        }
    }

    private func selectionDidChange(_ menu: Menu) {
        if screen == .theme {
            preferences.previewTheme = menu.isBack(selection) ? nil : ThemeID.allCases[selection - 1]
        }
        drawMenu(menu)
    }

    private func applyIcon(_ icon: ThemeID) {
        iconTask?.cancel()
        iconTask = Task { [weak self] in
            guard let self else { return }
            let applied = await self.preferences.setAppIcon(icon)
            guard !Task.isCancelled, self.screen == .appIcon else { return }
            self.iconStatus = applied ? "App icon set to \(icon.title)" : "Not supported on this device"
            if let menu = self.currentMenu {
                self.drawMenu(menu)
            }
        }
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
        // The 30-cell bar spans columns 25–54. The fixed-width "[ 84%]" starts one cell left of
        // the title, so its visible digits sit under the middle of the bar.
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
                c.gotoxy(36, 13)
                c.textcolor(.white, .black)
                c.write(label)
                c.gotoxy(25 + percent * 29 / 100, 14)
                c.write(String(ascii))
            }
        }
    }

    private func showMainMenu(selection: Int = 1) {
        preferences.previewTheme = nil
        screen = .menu
        self.selection = selection
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
        clearScreen()
        drawMenu(Self.avatarMenu)
    }

    private func showSettings(selection: Int = 1) {
        preferences.previewTheme = nil
        screen = .settings
        self.selection = selection
        clearScreen()
        drawMenu(settingsMenu)
    }

    private func showChoiceMenu(_ screen: Screen, current: ThemeID) {
        self.screen = screen
        selection = (ThemeID.allCases.firstIndex(of: current) ?? 0) + 1
        iconStatus = nil
        clearScreen()
        if let menu = currentMenu {
            drawMenu(menu)
        }
    }

    /// Entries are centred like in main.c; the selection is white with a symmetric marker,
    /// the rest dark grey. Avatar and theme menus preview the choice in a strip of tunnel.
    private func drawMenu(_ menu: Menu) {
        let selection = selection
        let screen = screen
        let preview: Character? = switch screen {
        case .avatar: menu.isBack(selection) ? avatar.glyph : Avatar.allCases[selection - 1].glyph
        case .theme: avatar.glyph
        default: nil
        }
        let status = iconStatus
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
                if screen == .theme {
                    // Wall notches and the red bar, so the theme's game colours show too.
                    c.textcolor(.black, .black)
                    c.gotoxy(32, 7)
                    c.write("   ")
                    c.gotoxy(45, 9)
                    c.write("   ")
                    c.textcolor(.red, .red)
                    c.gotoxy(43, 7)
                    c.write(" ")
                    c.gotoxy(43, 8)
                    c.write(" ")
                    c.textcolor(.black, .white)
                }
                for (index, row) in [9, 9, 8, 8].enumerated() {
                    c.gotoxy(36 + index, row)
                    c.write(".")
                }
                c.gotoxy(40, 8)
                c.write(String(preview))
            }
            for choice in 1...menu.count {
                let row = menu.row(for: choice)
                let isSelected = choice == selection
                let text = isSelected ? "> \(menu.label(choice)) <" : menu.label(choice)
                c.textcolor(.white, .black)
                c.gotoxy(1, row)
                c.write(String(repeating: " ", count: ConsoleBuffer.columns))
                c.textcolor(isSelected ? .white : .darkGray, .black)
                c.gotoxy(ConsoleBuffer.centeredX(text), row)
                c.write(text)
            }
            if screen == .appIcon {
                c.textcolor(.white, .black)
                c.gotoxy(1, 19)
                c.write(String(repeating: " ", count: ConsoleBuffer.columns))
                if let status {
                    c.gotoxy(ConsoleBuffer.centeredX(status), 19)
                    c.write(status)
                }
                #if os(macOS)
                let note = "On the Mac the icon changes in the Dock while Pixly runs"
                c.textcolor(.darkGray, .black)
                c.gotoxy(ConsoleBuffer.centeredX(note), 21)
                c.write(note)
                #endif
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

    /// Written into the bottom bar of the save-score window when space (or a stray tap) is pressed.
    private func showContinueHint() {
        let bar = saveScoreBar
        draw { c in
            c.textcolor(.white, bar)
            c.gotoxy(ConsoleBuffer.centeredX(Self.continueHint), Self.saveBarRow)
            c.write(Self.continueHint)
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

    private func clearScreen() {
        draw { c in
            c.textcolor(.white, .black)
            c.clrscr()
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
