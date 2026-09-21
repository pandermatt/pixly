import SwiftUI

/// When an iPhone is left partly folded on a table the game stands in the upper half and the flat
/// lower half becomes a control surface. Every other posture — and every other platform — renders
/// `content` exactly as it does today.
///
/// This sits above the game screens on purpose. `ProgramScreen` and `SmoothScreen` re-evaluate
/// their bodies on every frame; `TerminalView` does not, so the controls built here are a sibling
/// of the game rather than a child of it, and are never rebuilt while the pixel bobs.
struct TabletopSplit<Content: View, Controls: View>: View {
    /// The flat half is only worth having while a game is on screen.
    let isActive: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let controls: Controls

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.1, *), isActive {
            // `.overlay` puts the primary in the part below the fold, so the controls are the
            // primary and the game the secondary: the tabletop pose falls out without any
            // geometry maths of our own.
            //
            // Not a branch we can drop in favour of always arranging: with no active division
            // `.overlay` draws the primary *over* the secondary, which would paint the control
            // surface across the game when the phone is flat.
            ArrangementView {
                controls
            } secondary: {
                content
            }
            .arrangementViewStyle(.overlay)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Watches for the crease, and reports whether the phone is folded into the tabletop pose.
/// Belongs in a `.background` so its proxy spans the whole window; it draws nothing.
struct TabletopProbe: View {
    @Binding var isTabletop: Bool

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            DivisionProbe(isTabletop: $isTabletop)
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
@available(iOS 27.1, *)
private struct DivisionProbe: View {
    @Binding var isTabletop: Bool

    var body: some View {
        GeometryReader { proxy in
            // Queried without `.includeInactive`: the crease keeps a region when the phone is
            // flat, and only an active one means it is really folded.
            let division = proxy.reservedRegions(kind: .division).first
            // Rotate the phone and the crease becomes a full-height vertical band. That is a book
            // pose held in two hands, not a tabletop, so the layout is left alone.
            let tabletop = division.map { $0.frame.width > $0.frame.height } ?? false
            Color.clear
                .onChange(of: tabletop, initial: true) { _, folded in isTabletop = folded }
        }
    }
}

// MARK: - The surface

/// The flat half, laid out like a handheld: something to navigate with under one thumb and the
/// keys under the other, with a switch in the middle for a left-handed grip.
@available(iOS 27.1, *)
private struct TabletopSurface<Pad: View, Keys: View>: View {
    let preferences: Preferences
    @ViewBuilder let pad: Pad
    @ViewBuilder let keys: Keys

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            if preferences.leftHanded {
                keys.frame(maxWidth: .infinity, maxHeight: .infinity)
                HandednessSwitch(preferences: preferences)
                pad.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                pad.frame(maxWidth: .infinity, maxHeight: .infinity)
                HandednessSwitch(preferences: preferences)
                keys.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        // An arrangement aligns its halves leading, where the old layout centred things; without
        // this the surface would sit against one edge. The frame goes here, *before* the
        // background: wrapped around the finished tile it would grow the layout box and leave the
        // fill at its old size, centred in the gap.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { theme.console(.black) }
    }
}

/// Mirrors the surface. Deliberately small and quiet: it is set once, not used during a run.
@available(iOS 27.1, *)
private struct HandednessSwitch: View {
    let preferences: Preferences

    var body: some View {
        Button {
            preferences.setLeftHanded(!preferences.leftHanded)
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(preferences.leftHanded ? "Right-handed controls" : "Left-handed controls")
    }
}

/// A key on the surface. Matte on purpose — the screen is what should be looked at, so nothing
/// here is tinted or prominent.
@available(iOS 27.1, *)
private struct TabletopKey: View {
    let title: String
    let systemImage: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.mono(isPrimary ? 19 : 15, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glass)
        // Not a capsule: these tiles are big enough that half their short side rounds them into
        // ovals. A fixed radius echoes the console window's own corners instead.
        .buttonBorderShape(.roundedRectangle(radius: 22))
    }
}

/// After a crash the thumb is still hammering where jump was. Leaving a dead key there means a
/// stray press can't reach save or restart by accident.
@available(iOS 27.1, *)
private struct SpentJump: View {
    var body: some View {
        TabletopKey(title: "jump", systemImage: "arrow.up", isPrimary: true) {}
            .disabled(true)
            .accessibilityHint("Unavailable until the next run")
    }
}

// MARK: - The classic game

/// The classic port's keys, re-hosted on the flat half. Mirrors the screen-by-screen switch in
/// `ProgramScreen.controls`, which is hidden while this is up so no key exists in two places.
@available(iOS 27.1, *)
struct ClassicTabletopControls: View {
    let program: PixlyProgram
    let preferences: Preferences

    var body: some View {
        TabletopSurface(preferences: preferences) {
            switch program.screen {
            case .menu, .avatar, .settings, .theme, .appIcon:
                VStack(spacing: 12) {
                    TabletopKey(title: "up", systemImage: "chevron.up") { program.moveSelection(-1) }
                    TabletopKey(title: "down", systemImage: "chevron.down") { program.moveSelection(1) }
                }
            case .playing:
                // Quitting lives on the key column when the phone is flat, so it has to stay
                // reachable here too.
                TabletopKey(title: program.isPaused ? "resume" : "quit", systemImage: program.isPaused ? "play.fill" : "q.square") {
                    program.isPaused ? program.jump() : program.quitGame()
                }
            case .saveScore:
                VStack(spacing: 12) {
                    TabletopKey(title: "name", systemImage: "pencil") { program.beginEditingName() }
                    TabletopKey(title: "save", systemImage: "return") { program.saveScore() }
                    TabletopKey(title: "restart", systemImage: "arrow.clockwise", isPrimary: true) { program.saveAndRestart() }
                }
            default:
                Color.clear
            }
        } keys: {
            switch program.screen {
            case .menu, .avatar, .settings, .theme, .appIcon:
                VStack(spacing: 12) {
                    TabletopKey(title: "enter", systemImage: "return", isPrimary: true) { program.confirm() }
                    if program.screen != .menu {
                        TabletopKey(title: "back", systemImage: "chevron.left") { program.handle(.escape) }
                    }
                }
            case .playing:
                TabletopKey(title: "jump", systemImage: "arrow.up", isPrimary: true) { program.press(at: nil) }
            case .saveScore:
                SpentJump()
            case .scoreTable, .credits:
                TabletopKey(title: "back", systemImage: "return", isPrimary: true) { program.confirm() }
            case .loading, .finished:
                Color.clear
            }
        }
    }
}

// MARK: - Pixly 2.0

/// Pixly 2.0 has nothing to steer with, so the navigation side carries the score instead.
@available(iOS 27.1, *)
struct SmoothTabletopControls: View {
    let program: SmoothProgram
    let preferences: Preferences
    /// Saves and leaves, the way the game-over panel's own Exit does.
    let onExit: () -> Void

    var body: some View {
        TabletopSurface(preferences: preferences) {
            if program.result == nil {
                SmoothTabletopScore(program: program)
            } else {
                // The game-over panel already carries the score, so the readout gives way to the
                // keys and the jump side goes dead.
                VStack(spacing: 12) {
                    TabletopKey(title: "exit", systemImage: "xmark") { program.save(); onExit() }
                    TabletopKey(title: "retry", systemImage: "arrow.clockwise", isPrimary: true) { program.saveAndRetry() }
                }
            }
        } keys: {
            if program.result == nil {
                TabletopKey(title: "jump", systemImage: "arrow.up", isPrimary: true) { program.jump() }
            } else {
                SpentJump()
            }
        }
    }
}

/// The score, in a view of its own: it changes on every frame, and nothing else on the surface
/// should be rebuilt that often.
@available(iOS 27.1, *)
private struct SmoothTabletopScore: View {
    let program: SmoothProgram

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: String(program.game.score))
                .font(.system(size: 38, weight: .bold, design: .monospaced))
            Text("score")
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(theme.dim)
            Text(verbatim: String(program.best))
                .font(Theme.mono(19, weight: .semibold))
                .padding(.top, 12)
            Text("best")
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(theme.dim)
        }
        .foregroundStyle(theme.colorScheme == .light ? theme.text : theme.prompt)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
