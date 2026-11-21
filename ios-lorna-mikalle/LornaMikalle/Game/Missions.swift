import Foundation

/// Rewards granted when a mission, achievement, place or route is completed.
struct Reward: Equatable {
    var xp = 0
    var items: [Item: Int] = [:]

    var summary: String {
        var parts: [String] = []
        if xp > 0 { parts.append("+\(xp) XP") }
        for item in Item.allCases { if let n = items[item], n > 0 { parts.append("\(item.name) ×\(n)") } }
        return parts.joined(separator: " · ")
    }
}

enum MissionMetric: CaseIterable {
    case walk, calm, battles, places, talks, heals, teleports

    func value(_ c: PeriodCounters) -> Double {
        switch self {
        case .walk: c.walked
        case .calm: Double(c.calmed)
        case .battles: Double(c.battlesWon)
        case .places: Double(c.poisVisited)
        case .talks: Double(c.talks)
        case .heals: Double(c.heals)
        case .teleports: Double(c.teleports)
        }
    }

    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .calm: "sparkles"
        case .battles: "bolt.fill"
        case .places: "mappin.and.ellipse"
        case .talks: "bubble.left.fill"
        case .heals: "cross.case.fill"
        case .teleports: "arrow.triangle.swap"
        }
    }

    /// Missions that need real walking say so; the rest also work from the story.
    var needsWalking: Bool { self == .walk || self == .places }
}

struct Mission: Identifiable, Equatable {
    let id: String
    let title: String
    let metric: MissionMetric
    let target: Double
    let reward: Reward
    let weekly: Bool

    func progress(_ c: PeriodCounters) -> Double { min(metric.value(c), target) }
    func isDone(_ c: PeriodCounters) -> Bool { metric.value(c) >= target }

    func progressText(_ c: PeriodCounters) -> String {
        if metric == .walk { return "\(Int(progress(c))) / \(Int(target)) m" }
        return "\(Int(progress(c))) / \(Int(target))"
    }

    /// Daily and weekly missions, chosen deterministically from the date so they are stable all day.
    static func daily(for key: String) -> [Mission] {
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: key.stableHash))
        let walk = [600.0, 1000, 1500][Int.random(in: 0...2, using: &rng)]
        let pool: [Mission] = [
            Mission(id: "d-calm", title: "Calm 2 spirits", metric: .calm, target: 2, reward: Reward(xp: 220, items: [.espresso: 1]), weekly: false),
            Mission(id: "d-battle", title: "Win 2 battles", metric: .battles, target: 2, reward: Reward(xp: 200, items: [.cornetto: 1]), weekly: false),
            Mission(id: "d-talk", title: "Talk with 3 spirits", metric: .talks, target: 3, reward: Reward(xp: 120, items: [.gelato: 1]), weekly: false),
            Mission(id: "d-place", title: "Visit 2 real places", metric: .places, target: 2, reward: Reward(xp: 240, items: [.auraShard: 1]), weekly: false),
            Mission(id: "d-heal", title: "Heal 3 times in battle", metric: .heals, target: 3, reward: Reward(xp: 140, items: [.espresso: 1]), weekly: false),
            Mission(id: "d-tele", title: "Dodge 2 attacks by teleporting", metric: .teleports, target: 2, reward: Reward(xp: 160, items: [.santino: 1]), weekly: false),
        ].shuffled(using: &rng)
        let walkMission = Mission(id: "d-walk", title: "Walk \(Int(walk)) m", metric: .walk, target: walk,
                                  reward: Reward(xp: Int(walk / 5), items: [.auraShard: 1]), weekly: false)
        return [walkMission] + Array(pool.prefix(2))
    }

    static func weekly(for key: String) -> [Mission] {
        [
            Mission(id: "w-walk", title: "Walk 8 km this week", metric: .walk, target: 8000, reward: Reward(xp: 900, items: [.auraShard: 3]), weekly: true),
            Mission(id: "w-calm", title: "Calm 10 spirits", metric: .calm, target: 10, reward: Reward(xp: 800, items: [.auraShard: 2, .gelato: 2]), weekly: true),
            Mission(id: "w-battle", title: "Win 8 battles", metric: .battles, target: 8, reward: Reward(xp: 700, items: [.santino: 2]), weekly: true),
        ]
    }
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let target: Double
    let reward: Reward
    let value: (PlayerProgress) -> Double

    static let all: [Achievement] = [
        Achievement(id: "a-walk5", title: "Passeggiata", detail: "Walk 5 km in total", symbol: "figure.walk", target: 5000, reward: Reward(xp: 500, items: [.auraShard: 2])) { $0.distanceMeters },
        Achievement(id: "a-walk25", title: "Giro d'Italia", detail: "Walk 25 km in total", symbol: "map.fill", target: 25000, reward: Reward(xp: 1500, items: [.auraShard: 5])) { $0.distanceMeters },
        Achievement(id: "a-calm10", title: "Spirit Whisperer", detail: "Calm 10 spirits", symbol: "sparkles", target: 10, reward: Reward(xp: 600, items: [.auraShard: 2])) { Double($0.spiritsCalmed) },
        Achievement(id: "a-calm50", title: "Guardian of the Quarter", detail: "Calm 50 spirits", symbol: "sparkles.rectangle.stack.fill", target: 50, reward: Reward(xp: 2000, items: [.auraShard: 6])) { Double($0.spiritsCalmed) },
        Achievement(id: "a-battle20", title: "Strategist", detail: "Win 20 battles", symbol: "bolt.shield.fill", target: 20, reward: Reward(xp: 800, items: [.santino: 2])) { Double($0.battlesWon) },
        Achievement(id: "a-places10", title: "Flâneuse", detail: "Discover 10 real places", symbol: "mappin.and.ellipse", target: 10, reward: Reward(xp: 700, items: [.auraShard: 3])) { Double($0.places.count) },
        Achievement(id: "a-routes3", title: "Cartographer", detail: "Complete 3 routes", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", target: 3, reward: Reward(xp: 900, items: [.auraShard: 3])) { Double($0.routesCompleted) },
        Achievement(id: "a-friends", title: "Unexpected Allies", detail: "Befriend 3 kinds of spirits", symbol: "person.3.fill", target: 3, reward: Reward(xp: 700, items: [.gelato: 3])) { p in Double(SpiritKind.allCases.filter { (p.spiritBonds[$0] ?? 0) >= 3 }.count) },
        Achievement(id: "a-story", title: "La Determinazione d'Oro", detail: "Finish the main story", symbol: "music.note", target: 6, reward: Reward(xp: 3000, items: [.auraShard: 10])) { Double($0.storyChapter) },
    ]
}

/// Time-limited events computed from the real calendar and sky.
enum GameEvent: String, Identifiable, CaseIterable {
    case anniversary, spiritNight, goldenHour
    var id: String { rawValue }

    var title: String {
        switch self {
        case .anniversary: "16 Settembre · Anniversary"
        case .spiritNight: "Notte degli Spiriti"
        case .goldenHour: "Golden Hour Bonus"
        }
    }

    var detail: String {
        switch self {
        case .anniversary: "The day Lorna heard the song. Double XP all day."
        case .spiritNight: "Weekend nights: more spirits roam, rarer ones appear."
        case .goldenHour: "The real sun is low: +25% XP."
        }
    }

    var symbol: String {
        switch self {
        case .anniversary: "music.note"
        case .spiritNight: "moon.stars.fill"
        case .goldenHour: "sun.horizon.fill"
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .anniversary: 2
        case .spiritNight: 1.25
        case .goldenHour: 1.25
        }
    }

    static func active(now: Date = .now, preset: LightingPreset) -> [GameEvent] {
        var events: [GameEvent] = []
        let c = Calendar.current.dateComponents([.month, .day, .weekday, .hour], from: now)
        if c.month == 9, c.day == 16 { events.append(.anniversary) }
        let weekend = [6, 7, 1].contains(c.weekday ?? 0) // Fri, Sat, Sun
        if weekend, let h = c.hour, h >= 20 || h < 2 { events.append(.spiritNight) }
        if preset == .sunset { events.append(.goldenHour) }
        return events
    }
}

extension String {
    /// FNV-1a: stable across launches (unlike hashValue).
    var stableHash: UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}
