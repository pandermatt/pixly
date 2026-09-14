import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TerminalView: View {
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(Preferences.self) private var preferences
    @Environment(\.theme) private var theme
    @State private var session = TerminalSession()
    @State private var program: PixlyProgram?
    @State private var smoothProgram: SmoothProgram?
    @State private var showsWelcome = false
    @FocusState private var keyboardFocused: Bool
    #if os(macOS)
    @State private var shellKeys = KeyDownMonitor()
    #endif

    private let bottomID = "bottom"
    private var windowShape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    private var isRunning: Bool {
        program != nil || smoothProgram != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            VStack(spacing: 10) {
                #if os(iOS)
                // On the Mac the real window title bar is the only one. Both games hide it to use
                // the whole screen: the classic port in landscape, Pixly 2.0 always.
                if smoothProgram == nil, program == nil || !isLandscape {
                    TitleBar(title: title, canInterrupt: isRunning, onInterrupt: interruptProgram)
                }
                #endif
                if let program {
                    ProgramScreen(
                        program: program,
                        isLandscape: isLandscape,
                        onInterrupt: interruptProgram,
                        onOpenLeaderboard: { _ = gameCenter.showLeaderboard() }
                    )
                    .transition(.opacity)
                } else if let smoothProgram {
                    SmoothScreen(program: smoothProgram) { interrupted in
                        finishProgram(runtime: smoothProgram.runtime, interrupted: interrupted)
                    }
                    .transition(.opacity)
                } else {
                    shellWindow
                    commandBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            #if os(tvOS)
            // A running game fills the TV (each screen takes its colours to the edges).
            .padding(isRunning ? 0 : 12)
            #else
            .padding(.horizontal, smoothProgram == nil ? 12 : 4)
            .padding(.vertical, smoothProgram == nil ? 6 : 0)
            #endif
        }
        .background { Backdrop() }
        .animation(.smooth(duration: 0.3), value: isRunning)
        #if os(iOS)
        .statusBarHidden(isRunning)
        .persistentSystemOverlays(isRunning ? .hidden : .automatic)
        #endif
        .task { await setUp() }
        .onChange(of: preferences.theme) {
            gameCenter.unlock(.dressUp)
            sendLookToWatch()
        }
        .onChange(of: preferences.avatar) {
            gameCenter.unlock(.dressUp)
            sendLookToWatch()
        }
        .sheet(isPresented: $showsWelcome, onDismiss: welcomeDismissed) {
            WelcomeView(onContinue: finishWelcome)
        }
        .onChange(of: session.mode) { _, mode in
            if mode != .shell { keyboardFocused = false }
            if case .program(let kind) = mode { launchProgram(kind) }
        }
        #if os(macOS)
        .onChange(of: session.acceptsInput) { _, acceptsInput in
            if acceptsInput { keyboardFocused = true }
        }
        #endif
    }

    #if os(iOS)
    private var title: String {
        if program != nil { return "./pixly — 80×25" }
        if smoothProgram != nil { return "./pixly2 — 2.0" }
        return "player@pixly: ~ — zsh"
    }
    #endif

    // MARK: - Shell

    private var shellWindow: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(session.lines) { line in
                        TerminalLineView(line: line)
                    }
                    if session.showsPrompt {
                        PromptLineView(input: session.input, question: session.question)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.top, for: .alignment)
            .onChange(of: session.lines.count) { proxy.scrollTo(bottomID, anchor: .bottom) }
            .onChange(of: session.input) { _, input in
                // A tab that reaches the text field (e.g. from an iPad keyboard) means "complete".
                if input.contains("\t") {
                    session.input = input.replacingOccurrences(of: "\t", with: "")
                    session.complete()
                }
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: keyboardFocused) {
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.windowBackground, in: windowShape)
        .overlay {
            if preferences.scanlines {
                Scanlines().clipShape(windowShape)
            }
        }
        .overlay { windowShape.strokeBorder(theme.stroke, lineWidth: 1) }
        .contentShape(windowShape)
        .onTapGesture {
            if session.acceptsInput { keyboardFocused = true }
        }
        #if !os(tvOS)
        .background(alignment: .bottomLeading) { commandField }
        #endif
        #if os(macOS)
        // The text field would move focus on Tab, so catch it first and complete instead.
        .onAppear { shellKeys.start(handleShellKey) }
        .onDisappear { shellKeys.stop() }
        #endif
        #if !os(tvOS)
        // A controller can start the games too: A is the start button, Y is 2.0. (On tvOS the
        // focus system already presses the buttons.)
        .gameController { [session] button in
            guard !session.isBusy else { return }
            switch button {
            case .a:
                Task {
                    if session.canRestore {
                        await session.restoreFiles()
                    } else {
                        await session.compileAndRun(.classic)
                    }
                }
            case .y:
                Task { await session.compileAndRun(.smooth) }
            default:
                break
            }
        }
        #endif
    }

    #if os(macOS)
    private func handleShellKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 48,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              session.acceptsInput,
              NSApp.keyWindow?.firstResponder is NSTextView
        else { return false }
        session.complete()
        return true
    }
    #endif

    private var commandField: some View {
        TextField("", text: $session.input)
            .focused($keyboardFocused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .onKeyPress(.tab) {
                session.complete()
                return .handled
            }
            #else
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            #endif
            .autocorrectionDisabled()
            .submitLabel(.return)
            .onSubmit {
                let text = session.input
                Task { await session.submit(text) }
                keyboardFocused = true
            }
            .disabled(!session.acceptsInput)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }

    private var commandBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                // After a build failed on removed source files, the same button brings them back.
                Button {
                    Task {
                        if session.canRestore {
                            await session.restoreFiles()
                        } else {
                            await session.compileAndRun(.classic)
                        }
                    }
                } label: {
                    Label(
                        session.canRestore ? session.restoreTitle : "start",
                        systemImage: session.canRestore ? "arrow.uturn.backward" : "play.fill"
                    )
                        .font(Theme.mono(16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.buttonTint)
                .layoutPriority(1)

                Button {
                    Task { await session.compileAndRun(.smooth) }
                } label: {
                    Text(verbatim: "2.0")
                        .font(Theme.mono(16, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Start Pixly 2.0")

                iconButton("trophy.fill", label: "Leaderboard") { Task { await session.run("leaderboard") } }
                iconButton("questionmark", label: "Help") { Task { await session.run("help") } }
            }
        }
        .disabled(session.isBusy)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    /// The Apple Watch app plays in the phone's theme and avatar.
    private func sendLookToWatch() {
        #if os(iOS)
        WatchSync.shared.send()
        #endif
    }

    // MARK: - Lifecycle

    private func setUp() async {
        let gameCenter = gameCenter
        session.preferences = preferences
        session.playerName = { gameCenter.alias ?? "player" }
        session.onOpenLeaderboard = { gameCenter.showLeaderboard() }
        session.onShowWelcome = { showsWelcome = true }
        session.highscores = { ScoreStore().entries }
        session.highscores2 = { ScoreStore(key: SmoothProgram.scoreKey).entries }
        session.onAchievement = { gameCenter.unlock($0) }
        #if os(iOS)
        WatchSync.shared.start(preferences: preferences)
        #endif
        session.resetScores = { program in
            var store = ScoreStore(key: program == .classic ? "scores" : SmoothProgram.scoreKey)
            store.removeAll()
        }
        if preferences.hasSeenWelcome {
            await startShell()
        } else {
            await presentWelcome()
        }
    }

    /// Waits for the window to be up first: a sheet requested while the app is still launching can be dropped.
    private func presentWelcome() async {
        try? await Task.sleep(for: .milliseconds(300))
        showsWelcome = true
    }

    private func finishWelcome() {
        preferences.markWelcomeSeen()
        showsWelcome = false
        Task { await startShell() }
    }

    /// Only Continue counts as having seen the welcome; if the sheet went away any other way, show it again.
    private func welcomeDismissed() {
        guard !preferences.hasSeenWelcome else { return }
        Task { await presentWelcome() }
    }

    /// Signs in to Game Center and plays the boot sequence, once the welcome sheet is out of the way.
    private func startShell() async {
        guard session.mode == .booting else { return }
        gameCenter.authenticate()
        await session.boot()
    }

    private func launchProgram(_ kind: TerminalSession.Program) {
        guard !isRunning else { return }
        let gameCenter = gameCenter
        switch kind {
        case .classic:
            let program = PixlyProgram(preferences: preferences)
            program.playerAlias = { gameCenter.alias }
            program.onScore = { score in
                gameCenter.submit(score: score)
                gameCenter.recordRun(score: score, program: .classic)
            }
            program.onQuit = { runtime in finishProgram(runtime: runtime, interrupted: false) }
            self.program = program
            OrientationController.lockLandscape()
            Task { await program.run() }
        case .smooth:
            // Pixly 2.0 plays in portrait, so the screen is not rotated.
            let program = SmoothProgram(preferences: preferences)
            program.playerAlias = { gameCenter.alias }
            program.onScore = { score in
                gameCenter.submit(score: score, leaderboardID: GameCenterManager.leaderboardID2)
                gameCenter.recordRun(score: score, program: .smooth)
            }
            smoothProgram = program
        }
    }

    private func interruptProgram() {
        finishProgram(runtime: program?.runtime ?? smoothProgram?.runtime ?? 0, interrupted: true)
    }

    private func finishProgram(runtime: TimeInterval, interrupted: Bool) {
        guard isRunning else { return }
        let wasClassic = program != nil
        gameCenter.addJumps((program?.jumpCount ?? 0) + (smoothProgram?.jumpCount ?? 0))
        program?.terminate()
        smoothProgram?.terminate()
        program = nil
        smoothProgram = nil
        session.programExited(runtime: runtime, interrupted: interrupted)
        if wasClassic {
            OrientationController.unlock()
        }
    }
}
