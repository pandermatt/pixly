import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Pixly 2.0 in portrait: a stepped tunnel, a flying pixel and a glass game-over panel,
/// all in the current theme's colours.
struct SmoothScreen: View {
    let program: SmoothProgram
    /// True when the vertical bar hosts the looks and the way out, so they are not drawn here too.
    var hidesControls = false
    let onExit: (_ interrupted: Bool) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPressing = false
    #if os(macOS)
    @State private var keyMonitor = KeyDownMonitor()
    #else
    @FocusState private var keysFocused: Bool
    #endif
    /// tvOS: a moment after the crash, a click saves & retries.
    @State private var canClickToSave = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        ZStack {
            #if os(tvOS)
            // Full screen: the tunnel runs to the edges of the TV; the HUD and panel stay in the safe area.
            playfield
                .remoteSelect { handleController(.a) }
                .ignoresSafeArea()
            #elseif os(iOS)
            // Full screen: the tunnel runs behind the Dynamic Island and into the corners; the HUD
            // and the controls stay in the safe area.
            playfield
                .ignoresSafeArea()
            #else
            playfield
            #endif
            hud
            #if !os(tvOS)
            if !hidesControls {
                readyControls
            }
            #endif
            if let result = program.result {
                // Dims the frozen frame so the panel reads well over any tunnel colour.
                (theme.colorScheme == .light ? Color.white.opacity(0.45) : theme.console(.black).opacity(0.5))
                    .allowsHitTesting(false)
                    #if os(tvOS) || os(iOS)
                    .ignoresSafeArea()
                    #endif
                    .transition(.opacity)
                gameOver(result)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        #if os(tvOS) || os(iOS)
        .background { theme.console(.black).ignoresSafeArea() }
        #else
        .background(theme.console(.black), in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.stroke, lineWidth: 1) }
        #endif
        .animation(.smooth(duration: 0.3), value: program.result)
        .onAppear { program.start() }
        #if os(macOS)
        .onAppear { keyMonitor.start(handleKeyDown) }
        .onDisappear { keyMonitor.stop() }
        #else
        // Only while playing: with the game-over panel up, a focusable screen hands focus to the
        // name field whenever a menu closes, which pops up the keyboard.
        #if !os(tvOS)
        // (On tvOS the playfield is a button that keeps focus the whole time, so the remote's
        // Back and Play/Pause always arrive.)
        .focusable(program.result == nil)
        .focused($keysFocused)
        .focusEffectDisabled()
        #endif
        .onKeyPress(phases: .down, action: handleKeyPress)
        #if !os(tvOS)
        .onAppear { keysFocused = true }
        #endif
        #if !os(tvOS)
        .onChange(of: program.result == nil) { _, isPlaying in
            keysFocused = isPlaying
        }
        #endif
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
        .modifier(SmoothSounds(program: program))
        #if os(tvOS)
        .onExitCommand { handleController(.b) }
        .onPlayPauseCommand { handleController(.menu) }
        // Clicks in the first moments after a crash were still meant for jumping.
        .task(id: program.result) {
            canClickToSave = false
            guard program.result != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            canClickToSave = !Task.isCancelled
        }
        #else
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: program.jumpCount)
        .sensoryFeedback(trigger: program.result) { old, new in
            old == nil && new != nil ? .error : nil
        }
        #endif
    }

    private var playfield: some View {
        GeometryReader { proxy in
            let game = program.game
            let particles = program.particles
            let avatar = program.preferences.avatar
            let theme = theme
            Canvas { context, size in
                SmoothRenderer.draw(game, particles: particles, avatar: avatar, theme: theme, in: &context, size: size)
            }
            .overlay {
                if program.preferences.scanlines {
                    Scanlines(color: .black.opacity(theme.colorScheme == .light ? 0.06 : 0.25))
                }
            }
            .contentShape(Rectangle())
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        program.jump()
                    }
                    .onEnded { _ in isPressing = false }
            )
            #endif
            .onAppear { program.resize(aspect: proxy.size.width / max(proxy.size.height, 1)) }
            .onChange(of: proxy.size) { _, size in
                program.resize(aspect: size.width / max(size.height, 1))
            }
        }
    }

    /// The HUD sits on the wall: the main colour on dark walls, ink on Light's.
    private var hudColor: Color {
        theme.colorScheme == .light ? theme.text : theme.prompt
    }

    private var hudLabel: Color {
        theme.dim
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: String(program.game.score))
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                    Text("score")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(hudLabel)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: String(program.best))
                        .font(Theme.mono(22, weight: .semibold))
                    Text("best")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(hudLabel)
                }
            }
            .foregroundStyle(hudColor)
            .padding(20)

            Spacer()

            if program.game.state == .ready || program.isPaused {
                Text(program.isPaused ? pausedHint : jumpHint)
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    // 110 clears the looks row; with those in the vertical bar the hint drops to
                    // where that row used to sit.
                    .padding(.bottom, hidesControls ? 24 : 110)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: program.game.state)
        .allowsHitTesting(false)
    }

    /// Before the first jump and while paused: theme, avatar and the way out, at the bottom.
    /// Hidden during a run so a tap near the bottom always jumps.
    private var readyControls: some View {
        VStack {
            Spacer()
            if program.result == nil, program.game.state == .ready || program.isPaused {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        SmoothLooks(preferences: program.preferences)
                        Button {
                            onExit(true)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Exit Pixly 2.0")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
                .font(Theme.mono(14, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: program.game.state)
        .animation(.smooth(duration: 0.25), value: program.isPaused)
    }

    #if os(macOS)
    private var jumpHint: String { "press space to jump" }
    private var pausedHint: String { "paused · press space" }
    #elseif os(tvOS)
    private var jumpHint: String { "click to jump" }
    private var pausedHint: String { "paused · click to continue" }
    #else
    private var jumpHint: String { "tap to jump" }
    private var pausedHint: String { "paused · tap to continue" }
    #endif

    private func gameOver(_ result: SmoothProgram.Result) -> some View {
        VStack(spacing: 18) {
            if result.isNewHighscore {
                Text("NEW HIGHSCORE")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(theme.buttonTint, in: .capsule)
            }
            Text("GAME OVER")
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
            HStack(spacing: 40) {
                stat("score", result.score)
                stat("best", result.best)
            }
            #if os(tvOS)
            // Nothing to focus, and a click only saves after a moment: a player still clicking
            // can't skip the result. The name is the Game Center alias.
            Text(verbatim: canClickToSave ? "click: save & retry   back: exit" : "back: exit")
                .font(Theme.mono(14, weight: .semibold))
                .foregroundStyle(theme.dim)
            #else
            TextField("Your name", text: Binding(get: { program.name }, set: { program.name = String($0.prefix(ScoreStore.maxNameLength)) }))
                .textFieldStyle(.plain)
                .font(Theme.mono(17))
                .multilineTextAlignment(.center)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { program.saveAndRetry() }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(theme.text.opacity(0.08), in: .capsule)
            looks
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: program.saveAndRetry) {
                        Label("Save & Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(theme.buttonTint)
                    Button(action: exitAfterSaving) {
                        Label("Exit", systemImage: "xmark")
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            .font(Theme.mono(15, weight: .semibold))
            if GameControllerInput.shared.isConnected {
                Text(verbatim: "☰ save & retry   B exit")
                    .font(Theme.mono(12, weight: .medium))
                    .foregroundStyle(theme.dim)
            }
            #endif
        }
        .foregroundStyle(theme.text)
        .padding(24)
        .frame(maxWidth: 380)
        // Strongly tinted so the panel stays readable over the tunnel: dark glass for dark themes,
        // paper for the light one (whose text is ink).
        .glassEffect(.regular.tint(panelTint), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(20)
    }

    /// Theme and avatar, changed right from the game-over panel. Both are the shared settings,
    /// so the classic game uses the same choice.
    private var looks: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                SmoothLooks(preferences: program.preferences)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .font(Theme.mono(14, weight: .semibold))
    }

    private var panelTint: Color {
        theme.colorScheme == .light ? Color(hex: 0xFCFBF8, opacity: 0.9) : theme.console(.black).opacity(0.85)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: String(value))
                .font(Theme.mono(26, weight: .bold))
                .foregroundStyle(theme.prompt)
            Text(label)
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(theme.dim)
        }
    }

    private func exitAfterSaving() {
        program.save()
        onExit(false)
    }

    /// A jumps, B exits, Menu pauses. On game over A does nothing, so a player still hammering
    /// it doesn't skip the result: Menu saves & retries, B saves & exits.
    private func handleController(_ button: ControllerButton) {
        if program.result != nil {
            switch button {
            case .menu: program.saveAndRetry()
            case .b: exitAfterSaving()
            #if os(tvOS)
            case .a where canClickToSave: program.saveAndRetry()
            #endif
            default: break
            }
            return
        }
        switch button {
        case .a: program.jump()
        case .b: onExit(true)
        case .menu: program.isPaused ? program.jump() : program.pause()
        default: break
        }
    }

    #if os(macOS)
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return false }
        if flags.contains(.control) {
            guard event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
            onExit(true)
            return true
        }
        if program.result != nil {
            // Let the name field receive typing; only Return and Esc belong to the panel.
            switch event.keyCode {
            case 36, 76:
                program.saveAndRetry()
                return true
            case 53:
                exitAfterSaving()
                return true
            default:
                return false
            }
        }
        switch event.keyCode {
        case 49, 126:
            if !event.isARepeat { program.jump() }
        case 53:
            onExit(true)
        default:
            break
        }
        return true
    }
    #else
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.control), press.key.character == "c" {
            onExit(true)
            return .handled
        }
        if program.result != nil {
            switch press.key {
            case .return:
                program.saveAndRetry()
            case .escape:
                exitAfterSaving()
            default:
                return .ignored
            }
            return .handled
        }
        switch press.key {
        case .space, .upArrow:
            program.jump()
        case .escape:
            onExit(true)
        default:
            return .ignored
        }
        return .handled
    }
    #endif
}

/// A chirp for every jump and a buzz for the crash.
private struct SmoothSounds: ViewModifier {
    let program: SmoothProgram

    func body(content: Content) -> some View {
        content
            .onChange(of: program.jumpCount) {
                GameSound.jump.play()
            }
            .onChange(of: program.result) { old, new in
                if old == nil, new != nil {
                    GameSound.crash.play()
                }
            }
    }
}

/// The theme and avatar menus. A view of its own so it only redraws when a preference changes:
/// while the pixel bobs the screen redraws every frame, and a macOS menu rebuilt that often
/// can't be used.
private struct SmoothLooks: View {
    let preferences: Preferences

    var body: some View {
        Menu {
            Picker("Theme", selection: Binding(get: { preferences.theme }, set: { preferences.setTheme($0) })) {
                ForEach(ThemeID.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(preferences.theme.title, systemImage: "paintpalette.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        Menu {
            Picker("Avatar", selection: Binding(get: { preferences.avatar }, set: { preferences.setAvatar($0) })) {
                ForEach(Avatar.allCases, id: \.self) { avatar in
                    Text(verbatim: "\(avatar.emoji ?? "■") \(avatar.title)").tag(avatar)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(verbatim: "\(preferences.avatar.emoji ?? "■") \(preferences.avatar.title)")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }
}

enum SmoothRenderer {
    /// The trail takes the avatar's colour: the pixel's ink, the heart's red, the diamond's blue.
    static func trailColor(for avatar: Avatar, ink: Color) -> Color {
        switch avatar {
        case .pixel: ink
        case .heart: Color(hex: 0xE8323C)
        case .diamond: Color(hex: 0x4FB8F0)
        }
    }

    static func draw(
        _ game: SmoothEscapeGame,
        particles: [SmoothProgram.Particle],
        avatar: Avatar,
        theme: PixlyTheme,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard size.height > 0 else { return }
        let scale = size.height
        let left = game.distance
        let right = left + size.width / scale
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (x - left) * scale, y: y * scale)
        }

        let isLight = theme.colorScheme == .light
        let walls = theme.console(.black)
        let ink = theme.ink(.black)
        let trail = trailColor(for: avatar, ink: ink)
        // Edges and sparks in the theme's main colour; on Light's paper, ink edges and sparks in
        // the avatar's colour.
        let accent = isLight ? trail : theme.prompt
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(walls))

        // The tunnel is carved out of the walls column by column, so its edges are right-angled
        // steps like the original's.
        let width = SmoothEscapeGame.columnWidth
        let columns = Array(stride(from: SmoothEscapeGame.columnStart(left), through: right + width, by: width))
        guard !columns.isEmpty else { return }
        var topEdge: [CGPoint] = []
        var bottomEdge: [CGPoint] = []
        for column in columns {
            let top = game.top(at: column + width / 2)
            topEdge.append(point(column, top))
            topEdge.append(point(column + width, top))
        }
        for column in columns.reversed() {
            let bottom = game.bottom(at: column + width / 2)
            bottomEdge.append(point(column + width, bottom))
            bottomEdge.append(point(column, bottom))
        }
        var tunnel = Path()
        tunnel.addLines(topEdge + bottomEdge)
        tunnel.closeSubpath()
        context.fill(tunnel, with: .color(theme.console(.white)))

        var edges = Path()
        edges.addLines(topEdge)
        edges.addLines(bottomEdge)
        let edgeColor = isLight ? ink.opacity(0.35) : accent.opacity(0.85)
        context.stroke(edges, with: .color(edgeColor), style: StrokeStyle(lineWidth: isLight ? 1 : 1.5, lineJoin: .miter))

        let barColor = theme.console(.red)
        for bar in game.bars where bar.x + SmoothEscapeGame.Bar.width >= left && bar.x <= right {
            let rect = CGRect(
                x: (bar.x - left) * scale,
                y: bar.top * scale,
                width: SmoothEscapeGame.Bar.width * scale,
                height: (bar.bottom - bar.top) * scale
            )
            // Rounded like the pixel.
            context.fill(Path(roundedRect: rect, cornerRadius: rect.width * 0.35), with: .color(barColor))
        }

        for (index, dot) in game.trail.enumerated() {
            let fraction = Double(index + 1) / Double(game.trail.count)
            let radius = SmoothEscapeGame.radius * scale * (0.25 + 0.45 * fraction)
            let center = point(dot.x, dot.y)
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(trail.opacity(0.15 + 0.55 * fraction)))
        }

        for particle in particles {
            let fade = max(0, 1 - particle.life / particle.lifetime)
            let radius = 0.006 * scale * (0.5 + fade)
            let center = point(particle.x, particle.y)
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(accent.opacity(fade)))
        }

        // The pixel tilts with its speed.
        let center = point(game.playerWorldX, game.playerY)
        let side = SmoothEscapeGame.radius * 2.3 * scale
        var body = context
        body.translateBy(x: center.x, y: center.y)
        body.rotate(by: .radians(min(max(game.velocity * 0.4, -0.5), 0.6)))
        let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        if let emoji = avatar.emoji {
            body.draw(Text(verbatim: emoji).font(.system(size: side * 1.15)), at: .zero, anchor: .center)
        } else {
            body.fill(Path(roundedRect: rect, cornerRadius: side * 0.22), with: .color(ink))
        }
    }
}
