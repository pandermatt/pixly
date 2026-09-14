import Foundation
import Testing
@testable import Pixly

struct GameSoundTests {
    @Test(arguments: GameSound.allCases)
    func everySoundIsShortAndFades(_ sound: GameSound) {
        let samples = sound.samples()
        #expect(!samples.isEmpty)
        #expect(samples.count < GameSound.sampleRate / 2)
        #expect(samples.allSatisfy { abs($0) <= 1 })

        let window = samples.count / 5
        let start = samples.prefix(window).map(abs).max() ?? 0
        let end = samples.suffix(window).map(abs).max() ?? 0
        #expect(start > 0.2)
        #expect(end < start)
    }

    @Test func theJumpRisesAndTheCrashLastsLonger() {
        let jump = GameSound.jump.samples()
        func crossings(_ part: ArraySlice<Double>) -> Int {
            zip(part, part.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        }
        let third = jump.count / 3
        #expect(crossings(jump.suffix(third)) > crossings(jump.prefix(third)))
        #expect(GameSound.crash.samples().count > jump.count * 3)
        #expect(GameSound.tick.samples().count < jump.count)
    }
}
