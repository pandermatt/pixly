import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    #if os(macOS)
    @State private var keyMonitor = KeyDownMonitor()
    #else
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var keysFocused: Bool
    #endif

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
        #if os(macOS)
        // SwiftUI focus doesn't reach a freshly shown view until it is clicked, which made
        // the arrow keys beep. A local monitor sees every key while the program is on screen.
        .onAppear { keyMonitor.start(handleKeyDown) }
        .onDisappear { keyMonitor.stop() }
        #else
        .background(alignment: .topLeading) { nameField }
        .focusable()
        .focused($keysFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
        .onAppear { keysFocused = true }
        .onChange(of: program.screen) { _, screen in
            if screen != .saveScore {
                nameFieldFocused = false
                keysFocused = true
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { program.pause() }
        }
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

    private var nameField: some View {
        TextField("", text: Binding(get: { program.nameInput }, set: { program.setName($0) }))
            .focused($nameFieldFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { program.saveScore() }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
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
