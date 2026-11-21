import Foundation

/// Counters for one period (a day or an ISO week) that missions read from.
struct PeriodCounters: Codable, Equatable {
    var key = ""
    var walked: Double = 0
    var calmed = 0
    var battlesWon = 0
    var poisVisited = 0
    var talks = 0
    var heals = 0
    var teleports = 0
    var claimed: Set<String> = []

    init(key: String = "") { self.key = key }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        walked = try c.decodeIfPresent(Double.self, forKey: .walked) ?? 0
        calmed = try c.decodeIfPresent(Int.self, forKey: .calmed) ?? 0
        battlesWon = try c.decodeIfPresent(Int.self, forKey: .battlesWon) ?? 0
        poisVisited = try c.decodeIfPresent(Int.self, forKey: .poisVisited) ?? 0
        talks = try c.decodeIfPresent(Int.self, forKey: .talks) ?? 0
        heals = try c.decodeIfPresent(Int.self, forKey: .heals) ?? 0
        teleports = try c.decodeIfPresent(Int.self, forKey: .teleports) ?? 0
        claimed = try c.decodeIfPresent(Set<String>.self, forKey: .claimed) ?? []
    }
}

/// A real place Lorna has visited.
struct VisitedPlace: Codable, Equatable {
    var name: String
    var category: POICategory
    var firstVisit: Date
    var lastVisitDay: String
    var visits: Int
}

/// Lorna's persistent progress. Starts fresh and only grows from real play.
struct PlayerProgress: Codable, Equatable {
    var level = 1
    var xp = 0
    var distanceMeters: Double = 0
    var spiritsMet = 0
    var spiritsCalmed = 0
    var auraUses = 0

    // Phase 2
    var battlesWon = 0
    var bossesDefeated = 0
    var storyChapter = 0          // index of the next chapter to play
    var storyBeat = 0             // resume point inside it
    var inventory: [Item: Int] = [.espresso: 2, .cornetto: 2]
    var powers: [Power: Int] = [.healing: 1, .teleport: 1, .combat: 1]
    var affinity: [Person: Int] = [:]
    var spiritBonds: [SpiritKind: Int] = [:]
    var activeCompanion: Companion?
    var places: [Int: VisitedPlace] = [:]
    var routesCompleted = 0
    var achievementsClaimed: Set<String> = []
    var daily = PeriodCounters()
    var weekly = PeriodCounters()
    /// The prologue auto-plays once; after that it lives in the Story sheet.
    var introSeen = false

    static let xpPerLevel = 1000
    private static let key = "lorna.progress.v1"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        spiritsMet = try c.decodeIfPresent(Int.self, forKey: .spiritsMet) ?? 0
        spiritsCalmed = try c.decodeIfPresent(Int.self, forKey: .spiritsCalmed) ?? 0
        auraUses = try c.decodeIfPresent(Int.self, forKey: .auraUses) ?? 0
        battlesWon = try c.decodeIfPresent(Int.self, forKey: .battlesWon) ?? 0
        bossesDefeated = try c.decodeIfPresent(Int.self, forKey: .bossesDefeated) ?? 0
        storyChapter = try c.decodeIfPresent(Int.self, forKey: .storyChapter) ?? 0
        storyBeat = try c.decodeIfPresent(Int.self, forKey: .storyBeat) ?? 0
        inventory = try c.decodeIfPresent([Item: Int].self, forKey: .inventory) ?? [.espresso: 2, .cornetto: 2]
        powers = try c.decodeIfPresent([Power: Int].self, forKey: .powers) ?? [.healing: 1, .teleport: 1, .combat: 1]
        affinity = try c.decodeIfPresent([Person: Int].self, forKey: .affinity) ?? [:]
        spiritBonds = try c.decodeIfPresent([SpiritKind: Int].self, forKey: .spiritBonds) ?? [:]
        activeCompanion = try c.decodeIfPresent(Companion.self, forKey: .activeCompanion)
        places = try c.decodeIfPresent([Int: VisitedPlace].self, forKey: .places) ?? [:]
        routesCompleted = try c.decodeIfPresent(Int.self, forKey: .routesCompleted) ?? 0
        achievementsClaimed = try c.decodeIfPresent(Set<String>.self, forKey: .achievementsClaimed) ?? []
        daily = try c.decodeIfPresent(PeriodCounters.self, forKey: .daily) ?? PeriodCounters()
        weekly = try c.decodeIfPresent(PeriodCounters.self, forKey: .weekly) ?? PeriodCounters()
        // Players who already started before the prologue existed skip straight to their game.
        introSeen = try c.decodeIfPresent(Bool.self, forKey: .introSeen)
            ?? (level > 1 || storyChapter > 0 || battlesWon > 0 || xp > 0)
    }

    /// Adds XP and returns how many levels were gained.
    @discardableResult
    mutating func addXP(_ amount: Int) -> Int {
        xp += amount
        var gained = 0
        while xp >= Self.xpPerLevel {
            xp -= Self.xpPerLevel
            level += 1
            gained += 1
        }
        return gained
    }

    // MARK: Derived

    var maxHP: Int { 100 + (level - 1) * 8 }
    func power(_ p: Power) -> Int { powers[p] ?? 1 }
    func count(_ item: Item) -> Int { inventory[item] ?? 0 }
    mutating func add(_ item: Item, _ n: Int = 1) { inventory[item] = max(0, count(item) + n) }

    var unlockedCompanions: [Companion] {
        let people = Person.companions.filter { isUnlocked($0) }.map { Companion.person($0) }
        let spirits = SpiritKind.allCases.filter { (spiritBonds[$0] ?? 0) >= 3 }.map { Companion.spirit($0) }
        return people + spirits
    }

    func isUnlocked(_ person: Person) -> Bool {
        switch person {
        case .giulia: storyChapter >= 2
        case .teo: storyChapter >= 3
        case .ottavia: storyChapter >= 1
        case .dario, .vittoria: storyChapter >= 5
        default: false
        }
    }

    func affinityLevel(_ person: Person) -> Int { min(5, (affinity[person] ?? 0) / 100 + 1) }

    /// Rolls the period counters over when the day or week changes.
    mutating func rollPeriods(now: Date = .now) {
        let d = Calendar.dayKey(now), w = Calendar.weekKey(now)
        if daily.key != d { daily = PeriodCounters(key: d) }
        if weekly.key != w { weekly = PeriodCounters(key: w) }
    }

    mutating func count(_ change: (inout PeriodCounters) -> Void) {
        rollPeriods()
        change(&daily)
        change(&weekly)
    }

    static func load() -> PlayerProgress {
        guard let data = UserDefaults.standard.data(forKey: key),
              var value = try? JSONDecoder().decode(PlayerProgress.self, from: data) else { return PlayerProgress() }
        value.rollPeriods()
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

extension PlayerProgress {
    var distanceText: String {
        distanceMeters >= 1000
            ? String(format: "%.1f km", distanceMeters / 1000)
            : "\(Int(distanceMeters.rounded())) m"
    }
}

extension Calendar {
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func weekKey(_ date: Date) -> String {
        let c = Calendar(identifier: .iso8601).dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }
}
