import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Hosts the running C program: the 80×25 console, plus contextual Liquid Glass keys on iOS.
/// On the Mac the real keyboard is the only input: arrows, Return, Esc, space, q and ⌃C.
struct ProgramScreen: View {
    let program: PixlyProgram
    let isLandscape: Bool
    /// True when something else hosts the keys — the flat half of a folded phone, or the vertical
    /// bar the system stacks down one side of it — so the console takes the whole width.
    var hidesKeys = false
    let onInterrupt: () -> Void
    let onOpenLeaderboard: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.theme) private var theme
    @State private var isPressing = false
    #if os(macOS)
    @State private var keyMonitor = KeyDownMonitor()
    #else
    @FocusState private var keysFocused: Bool
    #endif
    #if os(tvOS)
    /// tvOS: the menu entry whose invisible row has focus.
    @FocusState private var focusedEntry: Int?
    #endif

    /// A chirp for every jump and a buzz when the pixel hits the wall (quitting with q is silent).
    private struct Sounds: ViewModifier {
        let program: PixlyProgram

        func body(content: Content) -> some View {
            content
                .onChange(of: program.jumpCount) {
                    GameSound.jump.play()
                }
                .onChange(of: program.screen) { old, new in
                    if old == .playing, new == .saveScore, program.game.isOver {
                        GameSound.crash.play()
                    }
                }
        }
    }

    #if !os(tvOS)
    /// Haptics for jumps and the crash, and the menu tick: the Apple TV clicks as focus moves
    /// through a menu, so everywhere else Pixly makes the same tick itself. (A modifier of its own
    /// keeps `body` quick to type-check.)
    private struct Feedback: ViewModifier {
        let program: PixlyProgram

        func body(content: Content) -> some View {
            content
                .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: program.jumpCount)
                .sensoryFeedback(trigger: program.screen) { old, new in
                    old == .playing && new == .saveScore ? .error : nil
                }
                .onChange(of: position) { old, new in
                    if new.isMove(from: old) {
                        GameSound.tick.play()
                    }
                }
                #if os(iOS)
                .sensoryFeedback(trigger: position) { old, new in
                    new.isMove(from: old) ? .selection : nil
                }
                #endif
        }

        private var position: MenuPosition {
            MenuPosition(screen: program.screen, selection: program.selection)
        }
    }

    /// Where the menu selection is: a tick plays when it moves within one menu, not when a new menu opens.
    private struct MenuPosition: Equatable {
        let screen: PixlyProgram.Screen
        let selection: Int

        func isMove(from old: MenuPosition) -> Bool {
            screen == old.screen && selection != old.selection
        }
    }
    #endif

    private var windowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isLandscape ? 18 : 24, style: .continuous)
    }

    var body: some View {
        let layout = isLandscape ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            #if os(tvOS)
            // Full screen: the console's black reaches the edges of the TV, while the 80×25 grid
            // stays inside the safe area.
            remoteControls(
                console
                    .overlay { scanlines }
                    .background { theme.console(.black).ignoresSafeArea() }
            )
            #else
            console
                .overlay { scanlines }
                .background(theme.console(.black), in: windowShape)
                .clipShape(windowShape)
                .overlay { windowShape.strokeBorder(theme.stroke, lineWidth: 1) }
            #endif
            #if os(iOS)
            if !hidesKeys {
                controls
                    .frame(width: isLandscape ? 132 : nil)
            }
            #endif
        }
        #if os(macOS)
        // SwiftUI focus doesn't reach a freshly shown view until it is clicked, which made
        // the arrow keys beep. A local monitor sees every key while the program is on screen.
        .onAppear { keyMonitor.start(handleKeyDown) }
        .onDisappear { keyMonitor.stop() }
        #else
        #if !os(tvOS)
        // (On tvOS the console is a button, which takes focus by itself.)
        .focusable()
        .focused($keysFocused)
        .focusEffectDisabled()
        #endif
        .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
        #if !os(tvOS)
        .onAppear { keysFocused = true }
        .onChange(of: program.screen) { keysFocused = true }
        #endif
        .alert("Enter your name", isPresented: Binding(get: { program.isEditingName }, set: { program.isEditingName = $0 })) {
            TextField("Name", text: Binding(get: { program.draftName }, set: { program.draftName = $0 }))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Save") { program.finishEditingName(save: true) }
            Button("Cancel", role: .cancel) { program.finishEditingName(save: false) }
        } message: {
            Text("It goes into the highscore table with your score.")
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { program.pause() }
        }
        .gameController { button in
            #if os(tvOS)
            // On tvOS everything but A also reaches the focus system, which handles it below.
            guard button == .a else { return }
            #endif
            handleController(button)
        }
        .modifier(Sounds(program: program))
        #if os(tvOS)
        // The Siri Remote (and controllers, through focus): swipes move through menus, Back stops
        // a run or leaves a menu (the main menu goes back to the shell), Play/Pause pauses and saves.
        .onMoveCommand { direction in
            // While a menu row has focus, the focus move itself changes the selection.
            guard focusedEntry == nil else { return }
            switch direction {
            case .up: program.moveSelection(-1)
            case .down: program.moveSelection(1)
            default: break
            }
        }
        .onExitCommand {
            if program.screen == .menu {
                onInterrupt()
            } else {
                handleController(.b)
            }
        }
        .onPlayPauseCommand { handleController(.menu) }
        .onChange(of: focusedEntry) { _, entry in
            if let entry {
                program.select(entry)
            }
        }
        #else
        .modifier(Feedback(program: program))
        #endif
    }

    /// A jumps while playing and confirms in menus, B stops a run or goes back, the d-pad and
    /// stick move through menus, Menu pauses. The save window after a crash ignores A, so a
    /// player still hammering it doesn't skip past the score: Menu saves instead.
    private func handleController(_ button: ControllerButton) {
        switch button {
        case .a:
            if program.isEditingName {
                program.finishEditingName(save: true)
            } else if program.screen == .playing {
                program.jump()
            } else if program.screen != .saveScore {
                program.confirm()
            } else {
                saveWindowClicked()
            }
        case .b:
            program.screen == .playing ? program.quitGame() : program.handle(.escape)
        case .up:
            program.moveSelection(-1)
        case .down:
            program.moveSelection(1)
        case .menu:
            if program.screen == .saveScore {
                program.confirm()
            } else if program.screen == .playing {
                program.isPaused ? program.jump() : program.pause()
            }
        case .y:
            if program.screen == .saveScore {
                program.saveAndRestart()
            }
        }
    }

    /// A on the save window: nothing, except on tvOS, where a click saves once the crash has sunk
    /// in (and until then shows how to continue).
    private func saveWindowClicked() {
        #if os(tvOS)
        if program.canContinue {
            program.confirm()
        } else {
            program.handle(.space)
        }
        #endif
    }

    @ViewBuilder
    private var scanlines: some View {
        if program.preferences.scanlines {
            // Dark lines: invisible on the walls, a CRT stripe across the bright tunnel.
            Scanlines(color: .black.opacity(theme.colorScheme == .light ? 0.08 : 0.3))
        }
    }

    #if os(tvOS)
    /// tvOS: outside menus the console is one big button (a click jumps or continues). In a menu
    /// it sits over focusable rows instead, with no button around them: inside a disabled button
    /// the rows became one focus group, and a swipe jumped straight to the last entry.
    @ViewBuilder
    private func remoteControls(_ console: some View) -> some View {
        if program.currentMenu == nil {
            console.remoteSelect { handleController(.a) }
        } else {
            console.background { menuEntries }
        }
    }

    /// tvOS: the menu entries as focusable rows hidden behind their console lines. Moving
    /// through a menu is then a real focus move, so the Apple TV plays its click and the remote
    /// ticks; the focused row is the selection.
    @ViewBuilder
    private var menuEntries: some View {
        if let menu = program.currentMenu {
            GeometryReader { proxy in
                let layout = ConsoleLayout(size: proxy.size, scale: displayScale, columns: program.console.width)
                // Plain layout, row under row (the empty line before Back is a gap): the focus
                // engine sees each entry exactly on its console line, so up and down go one step.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...menu.count, id: \.self) { choice in
                        let row = layout.rect(x: 1, y: menu.row(for: choice), width: program.console.width)
                        let gap = choice == 1
                            ? row.minY
                            : row.minY - layout.rect(x: 1, y: menu.row(for: choice - 1)).maxY
                        Button {
                            // A real remote may already have confirmed this click through GameController.
                            guard !GameControllerInput.shared.pressedARecently else { return }
                            program.select(choice)
                            program.confirm()
                        } label: {
                            // Opaque, but hidden behind the console: tvOS never focuses invisible views.
                            Rectangle().fill(theme.console(.black))
                        }
                        .buttonStyle(RemoteSelectStyle())
                        .focused($focusedEntry, equals: choice)
                        .accessibilityLabel(menu.label(choice))
                        .frame(width: row.width, height: row.height)
                        .padding(.top, gap)
                    }
                }
                .padding(.leading, layout.origin.x)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .defaultFocus($focusedEntry, program.selection)
            }
            // A new menu starts with focus on its current selection.
            .id(program.screen)
            .task { focusedEntry = program.selection }
        }
    }
    #endif

    private var console: some View {
        GeometryReader { proxy in
            let buffer = program.console
            let layout = ConsoleLayout(size: proxy.size, scale: displayScale, columns: buffer.width)
            let theme = theme
            Canvas { context, _ in
                ConsoleRenderer.draw(buffer, layout: layout, theme: theme, in: &context)
            }
            .contentShape(Rectangle())
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPressing else { return }
                        isPressing = true
                        program.press(at: layout.cell(at: value.startLocation))
                    }
                    .onEnded { _ in isPressing = false }
            )
            .onContinuousHover { phase in
                if case .active(let point) = phase, let cell = layout.cell(at: point) {
                    program.hover(at: cell)
                }
            }
            #endif
            #if os(macOS) || os(tvOS)
            // A wider window or TV shows more of the landscape; the game itself stays the same.
            .onChange(of: proxy.size, initial: true) { _, size in
                program.setColumns(ConsoleLayout.columns(fitting: size))
            }
            #endif
        }
        .accessibilityElement()
        .accessibilityLabel("Pixly console")
        .accessibilityIdentifier("console")
        .accessibilityValue(program.currentMenu.map { $0.label(program.selection) } ?? "")
    }

    #if os(macOS)
    /// Returns whether the event was used. Command shortcuts (⌘Q, ⌘W…) always pass through.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return false }
        if flags.contains(.control) {
            guard event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
            onInterrupt()
            return true
        }
        let key: PixlyProgram.Key = switch event.keyCode {
        case 49: .space
        case 126: .up
        case 125: .down
        case 36, 76: .enter
        case 53: .escape
        case 51: .backspace
        default: .character(event.characters ?? "")
        }
        program.handle(key, isRepeat: event.isARepeat)
        return true
    }
    #else
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.control), press.key.character == "c" || press.characters == "\u{3}" {
            onInterrupt()
            return .handled
        }
        guard !press.modifiers.contains(.command) else { return .ignored }
        let key: PixlyProgram.Key = switch press.key {
        case .space: .space
        case .upArrow: .up
        case .downArrow: .down
        case .return: .enter
        case .escape: .escape
        case .delete: .backspace
        default: .character(press.characters)
        }
        program.handle(key, isRepeat: press.phase == .repeat)
        return .handled
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            let stack = isLandscape ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            stack {
                switch program.screen {
                case .menu, .avatar, .settings, .theme, .appIcon:
                    key("up", "chevron.up") { program.moveSelection(-1) }
                    key("down", "chevron.down") { program.moveSelection(1) }
                    key("enter", "return", prominent: true) { program.confirm() }
                    if program.screen != .menu {
                        key("back", "chevron.left") { program.handle(.escape) }
                    }
                case .playing:
                    key(program.isPaused ? "resume" : "quit", program.isPaused ? "play.fill" : "q.square") {
                        program.isPaused ? program.jump() : program.quitGame()
                    }
                case .saveScore:
                    key("name", "pencil") { program.beginEditingName() }
                    key("restart", "arrow.clockwise") { program.saveAndRestart() }
                    key("save", "return", prominent: true) { program.saveScore() }
                case .scoreTable:
                    key("Game Center", "trophy.fill") { onOpenLeaderboard() }
                    key("back", "return", prominent: true) { program.confirm() }
                case .credits:
                    key("back", "return", prominent: true) { program.confirm() }
                case .loading, .finished:
                    EmptyView()
                }
                if isLandscape {
                    Spacer(minLength: 0)
                    key("⌃C", "xmark") { onInterrupt() }
                }
            }
            .frame(maxWidth: isLandscape ? .infinity : nil, maxHeight: isLandscape ? .infinity : nil)
        }
        .font(Theme.mono(14, weight: .semibold))
        .animation(.smooth(duration: 0.25), value: program.screen)
        #if os(iOS)
        .background { columnTouchArea }
        #endif
    }

    #if os(iOS)
    /// The space around the keys works like the console: a touch jumps while playing, and after a
    /// crash it continues (once the score has been on screen for a moment).
    private var columnTouchArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        program.press(at: nil)
                    }
                    .onEnded { _ in isPressing = false }
            )
    }
    #endif

    @ViewBuilder
    private func key(_ title: String, _ systemImage: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: isLandscape ? .infinity : nil)
                .padding(.vertical, 4)
        }
        if prominent {
            button.buttonStyle(.glassProminent).tint(theme.buttonTint)
        } else {
            button.buttonStyle(.glass)
        }
    }
    #endif
}

#if os(macOS)
@MainActor
final class KeyDownMonitor {
    private var token: Any?

    func start(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handler(event) } ? nil : event
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}
#endif
