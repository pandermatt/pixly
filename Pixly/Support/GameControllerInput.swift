@preconcurrency import GameController
import SwiftUI

/// The controller buttons Pixly listens to.
enum ControllerButton: Sendable {
    case a, b, y, menu, up, down
}

/// Game controllers (Xbox, PlayStation, MFi): each press goes to the screen that is in front,
/// which registers with `.gameController { … }`. A jumps and confirms, B goes back, the d-pad
/// and the left stick move through menus.
@Observable @MainActor
final class GameControllerInput {
    static let shared = GameControllerInput()

    /// A gamepad is connected, so screens can show which buttons do what.
    private(set) var isConnected = false

    @ObservationIgnored private var handlers: [(id: UUID, handle: @MainActor (ControllerButton) -> Void)] = []
    @ObservationIgnored private var stickDirection: ControllerButton?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(observesControllers: Bool = true) {
        guard observesControllers else { return }
        for controller in GCController.controllers() {
            configure(controller)
        }
        refreshConnection()
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { notification in
            nonisolated(unsafe) let controller = notification.object as? GCController
            MainActor.assumeIsolated {
                if let controller {
                    GameControllerInput.shared.configure(controller)
                }
                GameControllerInput.shared.refreshConnection()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                GameControllerInput.shared.refreshConnection()
            }
        })
    }

    private func refreshConnection() {
        isConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    /// The newest handler receives the presses until it is removed.
    func push(_ handler: @escaping @MainActor (ControllerButton) -> Void) -> UUID {
        let id = UUID()
        handlers.append((id, handler))
        return id
    }

    func remove(_ id: UUID) {
        handlers.removeAll { $0.id == id }
    }

    func send(_ button: ControllerButton) {
        if button == .a {
            lastAPress = .now
        }
        handlers.last?.handle(button)
    }

    @ObservationIgnored private var lastAPress: Date?

    /// A controller's A (or the Siri Remote's click) was just handled, so the same press arriving
    /// again as a button press should be ignored.
    var pressedARecently: Bool {
        lastAPress.map { Date.now.timeIntervalSince($0) < 1 } ?? false
    }

    /// The left stick acts like the d-pad: one step each time it is pushed past the middle.
    func stickMoved(_ y: Float) {
        if abs(y) < 0.3 {
            stickDirection = nil
        }
        let direction: ControllerButton? = y > 0.6 ? .up : y < -0.6 ? .down : nil
        guard let direction, direction != stickDirection else { return }
        stickDirection = direction
        send(direction)
    }

    private func configure(_ controller: GCController) {
        controller.handlerQueue = .main
        guard let gamepad = controller.extendedGamepad else {
            // The Siri Remote: a click jumps like A; its swipes and buttons go through focus.
            if let remote = controller.microGamepad {
                bind(remote.buttonA, to: .a)
            }
            return
        }
        bind(gamepad.buttonA, to: .a)
        bind(gamepad.buttonB, to: .b)
        bind(gamepad.buttonY, to: .y)
        bind(gamepad.buttonMenu, to: .menu)
        bind(gamepad.dpad.up, to: .up)
        bind(gamepad.dpad.down, to: .down)
        gamepad.leftThumbstick.yAxis.valueChangedHandler = { _, value in
            MainActor.assumeIsolated {
                GameControllerInput.shared.stickMoved(value)
            }
        }
    }

    private func bind(_ button: GCControllerButtonInput, to name: ControllerButton) {
        button.pressedChangedHandler = { _, _, isPressed in
            guard isPressed else { return }
            MainActor.assumeIsolated {
                GameControllerInput.shared.send(name)
            }
        }
    }
}

#if os(tvOS)
extension View {
    /// A click on the remote while this view has focus. The view becomes one big button: clicks
    /// that don't come through GameController (the simulator's remote, some remotes) still
    /// arrive, and ones that already did are skipped.
    func remoteSelect(isEnabled: Bool = true, perform action: @escaping @MainActor () -> Void) -> some View {
        Button {
            guard !GameControllerInput.shared.pressedARecently else { return }
            action()
        } label: {
            self
        }
        .buttonStyle(RemoteSelectStyle())
        .disabled(!isEnabled)
    }
}

/// No highlight or lift: the console draws its own selection.
struct RemoteSelectStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif

extension View {
    /// Handles controller presses while this view is on screen.
    func gameController(_ handler: @escaping @MainActor (ControllerButton) -> Void) -> some View {
        modifier(GameControllerModifier(handler: handler))
    }
}

private struct GameControllerModifier: ViewModifier {
    let handler: @MainActor (ControllerButton) -> Void
    @State private var token: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                token = GameControllerInput.shared.push(handler)
            }
            .onDisappear {
                if let token {
                    GameControllerInput.shared.remove(token)
                }
                token = nil
            }
    }
}
