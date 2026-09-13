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
    @State private var showsWelcome = false
    @FocusState private var keyboardFocused: Bool
    #if os(macOS)
    @State private var shellKeys = KeyDownMonitor()
    #endif

    private let bottomID = "bottom"
    private var windowShape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            VStack(spacing: 10) {
                #if os(iOS)
                // On the Mac the real window title bar is the only one.
                if program == nil || !isLandscape {
                    TitleBar(title: title, canInterrupt: program != nil, onInterrupt: interruptProgram)
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
                } else {
                    shellWindow
                    commandBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background { Backdrop() }
        .animation(.smooth(duration: 0.3), value: program == nil)
        #if os(iOS)
        .statusBarHidden(program != nil)
        .persistentSystemOverlays(program != nil ? .hidden : .automatic)
        #endif
        .task { await setUp() }
        .sheet(isPresented: $showsWelcome, onDismiss: welcomeDismissed) {
            WelcomeView(onContinue: finishWelcome)
        }
        .onChange(of: session.mode) { _, mode in
            if mode != .shell { keyboardFocused = false }
            if mode == .program { launchProgram() }
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
        return session.mode == .compiling ? "gcc — zsh" : "player@pixly: ~ — zsh"
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
            .scrollDismissesKeyboard(.interactively)
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
        .background(alignment: .bottomLeading) { commandField }
        #if os(macOS)
        // The text field would move focus on Tab, so catch it first and complete instead.
        .onAppear { shellKeys.start(handleShellKey) }
        .onDisappear { shellKeys.stop() }
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
                Button {
                    Task { await session.compileAndRun() }
                } label: {
                    Label("start", systemImage: "play.fill")
                        .font(Theme.mono(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.buttonTint)

                iconButton("trophy.fill", label: "Leaderboard") { Task { await session.run("leaderboard") } }
                iconButton("questionmark", label: "Help") { Task { await session.run("help") } }
                #if os(iOS)
                iconButton("keyboard", label: "Keyboard") { keyboardFocused.toggle() }
                #endif
            }
        }
        .disabled(session.isBusy)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    // MARK: - Lifecycle

    private func setUp() async {
        let gameCenter = gameCenter
        session.preferences = preferences
        session.playerName = { gameCenter.alias ?? "player" }
        session.onOpenLeaderboard = { gameCenter.showLeaderboard() }
        session.onShowWelcome = { showsWelcome = true }
        session.highscores = { ScoreStore().entries }
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

    private func launchProgram() {
        guard program == nil else { return }
        let gameCenter = gameCenter
        let program = PixlyProgram(preferences: preferences)
        program.playerAlias = { gameCenter.alias }
        program.onScore = { gameCenter.submit(score: $0) }
        program.onQuit = { runtime in finishProgram(runtime: runtime, interrupted: false) }
        self.program = program
        OrientationController.lockLandscape()
        Task { await program.run() }
    }

    private func interruptProgram() {
        finishProgram(runtime: program?.runtime ?? 0, interrupted: true)
    }

    private func finishProgram(runtime: TimeInterval, interrupted: Bool) {
        guard let program else { return }
        program.terminate()
        self.program = nil
        session.programExited(runtime: runtime, interrupted: interrupted)
        OrientationController.unlock()
    }
}
