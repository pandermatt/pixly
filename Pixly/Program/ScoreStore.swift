import Foundation

struct ScoreEntry: Codable, Equatable, Sendable {
    var name: String
    var score: Int
}

/// Local highscore table, the successor of pixel_escape.txt.
struct ScoreStore {
    static let maxNameLength = 24
    private static let key = "scores"

    private let defaults: UserDefaults
    private(set) var entries: [ScoreEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([ScoreEntry].self, from: $0) } ?? []
        entries = stored.sorted { $0.score > $1.score }
    }

    var best: Int {
        entries.first?.score ?? 0
    }

    /// `highscore()` from score.c.
    func highscore(_ current: Int) -> Int {
        max(current, best)
    }

    mutating func add(name: String, score: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let entry = ScoreEntry(name: trimmed.isEmpty ? "No Name" : String(trimmed.prefix(Self.maxNameLength)), score: score)
        let index = entries.firstIndex { $0.score < score } ?? entries.endIndex
        entries.insert(entry, at: index)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
