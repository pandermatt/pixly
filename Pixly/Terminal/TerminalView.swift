import SwiftUI

struct TerminalView: View {
    @Environment(GameCenterManager.self) private var gameCenter
    @State private var session = TerminalSession()
    @State private var program: PixlyProgram?
    @FocusState private var keyboardFocused: Bool

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
        .onChange(of: session.mode) { _, mode in
            if mode != .shell { keyboardFocused = false }
            if mode == .program { launchProgram() }
        }
        #if os(macOS)
        .onChange(of: session.isBusy) { _, isBusy in
            if !isBusy { keyboardFocused = true }
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
                        PromptLineView(input: session.input)
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
            .onChange(of: session.input) { proxy.scrollTo(bottomID, anchor: .bottom) }
            .onChange(of: keyboardFocused) {
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.8), in: windowShape)
        .overlay { Scanlines().clipShape(windowShape) }
        .overlay { windowShape.strokeBorder(.white.opacity(0.1), lineWidth: 1) }
        .contentShape(windowShape)
        .onTapGesture {
            if !session.isBusy { keyboardFocused = true }
        }
        .background(alignment: .bottomLeading) { commandField }
    }

    private var commandField: some View {
        TextField("", text: $session.input)
            .focused($keyboardFocused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            #else
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            #endif
            .autocorrectionDisabled()
            .submitLabel(.return)
            .onSubmit {
                let command = session.input
                Task { await session.submit(command) }
                keyboardFocused = true
            }
            .disabled(session.isBusy)
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
                .tint(Theme.buttonGreen)

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

    // MARK: - Program lifecycle

    private func setUp() async {
        let gameCenter = gameCenter
        session.playerName = { gameCenter.alias ?? "player" }
        session.onOpenLeaderboard = { gameCenter.showLeaderboard() }
        session.highscores = { ScoreStore().entries }
        gameCenter.authenticate()
        await session.boot()
    }

    private func launchProgram() {
        guard program == nil else { return }
        let gameCenter = gameCenter
        let program = PixlyProgram()
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
