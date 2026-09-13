import Foundation
import Testing
@testable import Pixly

struct AchievementTests {
    @Test func scoreTiersPerGame() {
        #expect(Achievement.unlocked(byScore: 0, in: .classic) == [.firstEscape])
        #expect(Achievement.unlocked(byScore: 2_400, in: .classic) == [.firstEscape, .classic500, .classic2000])
        #expect(Achievement.unlocked(byScore: 1_600, in: .smooth) == [.recompiled, .smooth500, .smooth1500])
    }

    @Test func everyAchievementFitsAppStoreConnect() {
        let ids = Achievement.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Achievement.allCases.map(\.points).reduce(0, +) <= 1_000)
        #expect(Achievement.allCases.allSatisfy { (1...100).contains($0.points) && $0.id.count <= 100 })
        #expect(Achievement.allCases.allSatisfy { !$0.title.isEmpty && !$0.description.isEmpty })
    }

    @Test func progressIsReportedOnceAndPendingIsKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "pixly-achievements-\(UUID().uuidString)"))
        let log = AchievementLog(defaults: defaults)
        #expect(log.record(.showOff, percent: 100))
        #expect(!log.record(.showOff, percent: 100))

        #expect(log.addJumps(99) == nil)
        #expect(log.addJumps(1) == 10)
        #expect(log.record(.frequentFlyer, percent: 10))
        #expect(log.addJumps(50) == nil)
        #expect(log.addJumps(5_000) == 100)
        #expect(log.totalJumps == 5_150)

        log.keepPending(.teapot, percent: 100)
        log.keepPending(.frequentFlyer, percent: 40)
        let pending = Dictionary(uniqueKeysWithValues: log.takePending())
        #expect(pending == [.teapot: 100, .frequentFlyer: 40])
        #expect(log.takePending().isEmpty)
    }
}
