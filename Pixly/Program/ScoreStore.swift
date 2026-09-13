import Foundation

struct ScoreEntry: Codable, Equatable, Sendable {
    var name: String
    var score: Int
}

/// Local highscore table, the successor of pixel_escape.txt. Each game mode keeps its own `key`.
struct ScoreStore {
    static let maxNameLength = 24

    private let defaults: UserDefaults
    private let key: String
    private(set) var entries: [ScoreEntry]

    init(defaults: UserDefaults = .standard, key: String = "scores") {
        self.defaults = defaults
        self.key = key
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ScoreEntry].self, from: $0) } ?? []
        entries = stored.sorted { $0.score > $1.score }
    }

    var best: Int {
        entries.first?.score ?? 0
    }

    /// `highscore()` from score.c.
    func highscore(_ current: Int) -> Int {
        max(current, best)
    }

    /// `rm highscore.txt`: the table starts over.
    mutating func removeAll() {
        entries = []
        defaults.removeObject(forKey: key)
    }

    mutating func add(name: String, score: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let entry = ScoreEntry(name: trimmed.isEmpty ? "No Name" : String(trimmed.prefix(Self.maxNameLength)), score: score)
        let index = entries.firstIndex { $0.score < score } ?? entries.endIndex
        entries.insert(entry, at: index)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
