import Foundation
import Testing
@testable import Pixly

@MainActor
struct GameControllerInputTests {
    @Test func theScreenInFrontGetsThePresses() {
        let input = GameControllerInput(observesControllers: false)
        var shell: [ControllerButton] = []
        var game: [ControllerButton] = []
        let shellToken = input.push { shell.append($0) }
        let gameToken = input.push { game.append($0) }

        input.send(.a)
        #expect(game == [.a])
        #expect(shell.isEmpty)

        input.remove(gameToken)
        input.send(.y)
        #expect(shell == [.y])
        input.remove(shellToken)
        input.send(.b)
        #expect(shell == [.y])
    }

    @Test func theStickStepsOncePerPush() {
        let input = GameControllerInput(observesControllers: false)
        var presses: [ControllerButton] = []
        _ = input.push { presses.append($0) }

        for y in [0.2, 0.7, 0.9, 0.5, 0.1, 0.8, -0.4, -0.95] as [Float] {
            input.stickMoved(y)
        }
        #expect(presses == [.up, .up, .down])
    }
}
