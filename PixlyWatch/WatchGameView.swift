import SwiftUI

/// The classic tunnel stretched over the whole watch face, the score on top. A tap or a turn of
/// the Digital Crown jumps; after a crash, a tap starts the next run.
struct WatchGameView: View {
    @Environment(GameCenterManager.self) private var gameCenter
    @Environment(Preferences.self) private var preferences
    @Environment(\.theme) private var theme
    @State private var game: QuickGame?

    var body: some View {
        Group {
            if let game {
                playfield(game)
            } else {
                theme.console(.black)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: setUp)
    }

    private func playfield(_ game: QuickGame) -> some View {
        board(game)
            .modifier(WatchInput(game: game))
            .overlay(alignment: .top) { scoreboard(game) }
            .overlay { message(game) }
            .modifier(WatchFeedback(game: game))
            .modifier(WatchSounds(game: game))
    }

    /// The screen's clock drives the game's 20 ms ticks; the console is drawn stretched.
    private func board(_ game: QuickGame) -> some View {
        TimelineView(.animation(paused: game.state == .ready || game.isPaused)) { context in
            Canvas { graphics, size in
                let layout = ConsoleLayout(stretching: size, rows: 24)
                ConsoleRenderer.draw(game.console, layout: layout, theme: theme, in: &graphics)
                drawAvatar(row: game.playerRow, layout: layout, in: &graphics)
            }
            .onChange(of: context.date) { _, date in
                game.frame(at: date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// The cell is only a few points wide once stretched, so the avatar is drawn over it at the
    /// height of a row.
    private func drawAvatar(row: Int, layout: ConsoleLayout, in graphics: inout GraphicsContext) {
        guard (1...24).contains(row) else { return }
        let cell = layout.rect(x: ClassicGame.playerX, y: row)
        let side = min(cell.height, cell.width * 3)
        let rect = CGRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side)
        let ink = theme.ink(.black)
        switch preferences.avatar {
        case .pixel:
            graphics.fill(Path(rect), with: .color(ink))
        case .heart, .diamond:
            graphics.fill(Path(rect), with: .color(theme.console(.white)))
            graphics.draw(
                Text(verbatim: String(preferences.avatar.glyph)).font(.system(size: side * 1.2, weight: .bold)).foregroundStyle(ink),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
        }
    }

    private func scoreboard(_ game: QuickGame) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: String(game.score))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
            Text(verbatim: "best \(game.best)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .opacity(0.8)
        }
        .foregroundStyle(theme.colorScheme == .light ? theme.text : theme.prompt)
        .padding(.top, 4)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func message(_ game: QuickGame) -> some View {
        switch game.state {
        case .ready:
            hint("tap to start")
        case .playing:
            if game.isPaused {
                hint("paused · tap")
            }
        case .over:
            VStack(spacing: 4) {
                Text(verbatim: "GAME OVER")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                if game.isNewBest {
                    Text(verbatim: "new best!")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.prompt)
                }
                if game.canRestart {
                    Text(verbatim: "tap to play again")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(theme.console(.black).opacity(0.6)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .allowsHitTesting(false)
    }

    private func setUp() {
        guard game == nil else { return }
        let gameCenter = gameCenter
        let quickGame = QuickGame(preferences: preferences)
        quickGame.playerAlias = { gameCenter.alias }
        // The same leaderboard, achievements and jump count as the classic game on the phone.
        quickGame.onRunEnd = { score, jumps in
            gameCenter.submit(score: score)
            gameCenter.recordRun(score: score, program: .classic)
            gameCenter.addJumps(jumps)
        }
        game = quickGame
    }
}

/// A tap anywhere, or a turn of the Digital Crown, presses (jumps, starts, restarts).
private struct WatchInput: ViewModifier {
    let game: QuickGame
    @State private var isPressing = false
    @State private var crown = 0.0
    @State private var crownAtLastJump = 0.0

    /// How far the crown turns for one jump.
    private let crownPerJump = 0.5

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(tap)
            .focusable()
            .digitalCrownRotation(
                $crown,
                from: -1_000_000.0,
                through: 1_000_000.0,
                sensitivity: .high,
                isContinuous: true,
                isHapticFeedbackEnabled: false
            )
            .onChange(of: crown) { _, value in
                guard abs(value - crownAtLastJump) >= crownPerJump else { return }
                crownAtLastJump = value
                game.press()
            }
    }

    private var tap: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressing else { return }
                isPressing = true
                game.press()
            }
            .onEnded { _ in
                isPressing = false
            }
    }
}

/// A chirp for every jump and a buzz for the crash, the same sounds as on the other devices.
private struct WatchSounds: ViewModifier {
    let game: QuickGame

    func body(content: Content) -> some View {
        content
            .onChange(of: game.jumpCount) {
                GameSound.jump.play()
            }
            .onChange(of: game.state) { old, new in
                if old == .playing, new == .over {
                    GameSound.crash.play()
                }
            }
    }
}

/// A light tap on the wrist per jump, a stronger one on the crash, and a pause when the wrist drops.
private struct WatchFeedback: ViewModifier {
    let game: QuickGame
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .light), trigger: game.jumpCount)
            .sensoryFeedback(trigger: game.state) { old, new in
                old == .playing && new == .over ? .error : nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    game.pause()
                }
            }
    }
}
