import SwiftUI

/// Hosts the running C program: the 80×25 console, plus contextual Liquid Glass keys on iOS.
/// On the Mac the real keyboard is the only input: arrows, Return, space, q and ⌃C.
struct ProgramScreen: View {
    let program: PixlyProgram
    let isLandscape: Bool
    let onInterrupt: () -> Void
    let onOpenLeaderboard: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var isPressing = false
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var keysFocused: Bool

    private var windowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isLandscape ? 18 : 24, style: .continuous)
    }

    var body: some View {
        let layout = isLandscape ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            console
                .background(.black, in: windowShape)
                .clipShape(windowShape)
                .overlay { windowShape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            #if os(iOS)
            controls
                .frame(width: isLandscape ? 132 : nil)
            #endif
        }
        .background(alignment: .topLeading) { nameField }
        .focusable()
        .focused($keysFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .onAppear { keysFocused = true }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { program.pause() }
        }
        .onChange(of: program.screen) { updateFocus() }
        .onChange(of: program.isTypingName) { updateFocus() }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: program.jumpCount)
        .sensoryFeedback(trigger: program.screen) { old, new in
            old == .playing && new == .saveScore ? .error : nil
        }
    }

    private var console: some View {
        GeometryReader { proxy in
            let layout = ConsoleLayout(size: proxy.size, scale: displayScale)
            let buffer = program.console
            Canvas { context, _ in
                ConsoleRenderer.draw(buffer, layout: layout, in: &context)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPressing else { return }
                        isPressing = true
                        program.press(at: layout.cell(at: value.startLocation))
                    }
                    .onEnded { _ in isPressing = false }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Pixly console")
    }

    #if os(iOS)
    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            let stack = isLandscape ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            stack {
                switch program.screen {
                case .menu, .avatar:
                    key("up", "chevron.up") { program.moveSelection(-1) }
                    key("down", "chevron.down") { program.moveSelection(1) }
                    key("enter", "return", prominent: true) { program.confirm() }
                case .playing:
                    key(program.isPaused ? "resume" : "quit", program.isPaused ? "play.fill" : "q.square") {
                        program.isPaused ? program.jump() : program.quitGame()
                    }
                case .saveScore:
                    key("save", "return", prominent: true) { program.saveScore() }
                    key("edit", "keyboard") { nameFieldFocused = true }
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
    }

    @ViewBuilder
    private func key(_ title: String, _ systemImage: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: isLandscape ? .infinity : nil)
                .padding(.vertical, 4)
        }
        if prominent {
            button.buttonStyle(.glassProminent).tint(Theme.buttonGreen)
        } else {
            button.buttonStyle(.glass)
        }
    }
    #endif

    private var nameField: some View {
        TextField("", text: Binding(get: { program.nameInput }, set: { program.setName($0) }))
            .focused($nameFieldFocused)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #else
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            #endif
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { program.saveScore() }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }

    private func updateFocus() {
        guard program.screen == .saveScore else {
            nameFieldFocused = false
            keysFocused = true
            return
        }
        #if os(macOS)
        // Only hand the keyboard to the name once auto-typing is done, so a space still held
        // from the last jump can't land in (or interrupt) the name.
        if !program.isTypingName { nameFieldFocused = true }
        #endif
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.control), press.key.character == "c" || press.characters == "\u{3}" {
            onInterrupt()
            return .handled
        }
        let isDown = press.phase == .down
        switch press.key {
        case .space:
            // Space jumps; it never confirms, so it can't dismiss the save-score window.
            switch program.screen {
            case .playing:
                program.jump()
            case .scoreTable, .credits:
                if isDown { program.confirm() }
            default:
                return .ignored
            }
        case .upArrow:
            program.moveSelection(-1)
        case .downArrow:
            program.moveSelection(1)
        case .return:
            if isDown { program.confirm() }
        case "q" where program.screen == .playing:
            program.quitGame()
        default:
            // system("PAUSE"): any key continues from the tables.
            guard isDown, program.screen == .scoreTable || program.screen == .credits else { return .ignored }
            program.confirm()
        }
        return .handled
    }
}
