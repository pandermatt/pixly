import Foundation

/// Which game a run was played in: the classic port or Pixly 2.0.
enum PixlyGame: Equatable, Sendable {
    case classic, smooth
}

/// Pixly's Game Center achievements. Each needs a matching achievement in App Store Connect with
/// the same ID, title, description and points (and an image); the hidden ones stay secret until earned.
enum Achievement: String, CaseIterable, Sendable {
    case firstEscape, classic500, classic2000, classic5000
    case recompiled, smooth500, smooth1500, smooth3000
    case frequentFlyer, dressUp
    case readTheSource, showOff, teapot, fridayDeploy, restored

    static let jumpGoal = 1_000

    var id: String {
        "ch.pandermatt.pixly.achievement.\(rawValue)"
    }

    var title: String {
        switch self {
        case .firstEscape: "Hello, World"
        case .classic500: "Warming Up"
        case .classic2000: "80×25 Veteran"
        case .classic5000: "consoleio Legend"
        case .recompiled: "Recompiled"
        case .smooth500: "Smooth Operator"
        case .smooth1500: "Liquid Pixel"
        case .smooth3000: "Escape Velocity"
        case .frequentFlyer: "Frequent Flyer"
        case .dressUp: "Dress Up"
        case .readTheSource: "Read the Source"
        case .showOff: "Show-off"
        case .teapot: "418"
        case .fridayDeploy: "Friday Deploy"
        case .restored: "git checkout -- ."
        }
    }

    var description: String {
        switch self {
        case .firstEscape: "Finish your first run of the classic Pixly."
        case .classic500: "Score 500 in the classic Pixly."
        case .classic2000: "Score 2,000 in the classic Pixly."
        case .classic5000: "Score 5,000 in the classic Pixly."
        case .recompiled: "Finish your first run of Pixly 2.0."
        case .smooth500: "Score 500 in Pixly 2.0."
        case .smooth1500: "Score 1,500 in Pixly 2.0."
        case .smooth3000: "Score 3,000 in Pixly 2.0."
        case .frequentFlyer: "Jump 1,000 times."
        case .dressUp: "Change the theme or the avatar."
        case .readTheSource: "Read the source code in the shell."
        case .showOff: "Show off your system with neofetch."
        case .teapot: "Ask the shell for coffee."
        case .fridayDeploy: "Force push to main."
        case .restored: "Break the build, then bring the files back."
        }
    }

    var points: Int {
        switch self {
        case .firstEscape, .recompiled, .dressUp: 10
        case .classic500, .smooth500, .readTheSource, .showOff, .teapot: 20
        case .fridayDeploy, .restored: 30
        case .classic2000, .smooth1500, .frequentFlyer: 50
        case .classic5000, .smooth3000: 100
        }
    }

    /// The shell's secrets aren't listed until someone finds them.
    var isHidden: Bool {
        switch self {
        case .readTheSource, .showOff, .teapot, .fridayDeploy, .restored: true
        default: false
        }
    }

    /// The tiers a finished run reached; finishing at all counts as the first one.
    static func unlocked(byScore score: Int, in program: PixlyGame) -> [Achievement] {
        let tiers: [(score: Int, achievement: Achievement)] = switch program {
        case .classic: [(0, .firstEscape), (500, .classic500), (2_000, .classic2000), (5_000, .classic5000)]
        case .smooth: [(0, .recompiled), (500, .smooth500), (1_500, .smooth1500), (3_000, .smooth3000)]
        }
        return tiers.filter { score >= $0.score }.map(\.achievement)
    }
}

/// What has been earned on this device, so each step is reported once and the ones earned while
/// signed out are sent later. Also counts every jump for Frequent Flyer.
struct AchievementLog {
    private static let progressKey = "achievementProgress"
    private static let pendingKey = "pendingAchievements"
    private static let jumpsKey = "totalJumps"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var totalJumps: Int {
        defaults.integer(forKey: Self.jumpsKey)
    }

    func progress(of achievement: Achievement) -> Double {
        percentages(Self.progressKey)[achievement.rawValue] ?? 0
    }

    /// Returns whether this moved the achievement forward, and so should be reported.
    func record(_ achievement: Achievement, percent: Double) -> Bool {
        var progress = percentages(Self.progressKey)
        guard percent > progress[achievement.rawValue, default: 0] else { return false }
        progress[achievement.rawValue] = percent
        defaults.set(progress, forKey: Self.progressKey)
        return true
    }

    /// Counts the jumps; returns Frequent Flyer's new progress each time it passes another 10 %.
    func addJumps(_ count: Int) -> Double? {
        guard count > 0 else { return nil }
        let total = totalJumps + count
        defaults.set(total, forKey: Self.jumpsKey)
        let percent = Double(min(total, Achievement.jumpGoal) * 10 / Achievement.jumpGoal) * 10
        return percent > progress(of: .frequentFlyer) ? percent : nil
    }

    func keepPending(_ achievement: Achievement, percent: Double) {
        var pending = percentages(Self.pendingKey)
        pending[achievement.rawValue] = max(percent, pending[achievement.rawValue] ?? 0)
        defaults.set(pending, forKey: Self.pendingKey)
    }

    func takePending() -> [(Achievement, Double)] {
        let pending = percentages(Self.pendingKey)
        defaults.removeObject(forKey: Self.pendingKey)
        return pending.compactMap { key, percent in Achievement(rawValue: key).map { ($0, percent) } }
    }

    private func percentages(_ key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }
}
