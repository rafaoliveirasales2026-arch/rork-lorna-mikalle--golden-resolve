import SwiftUI

// MARK: - People

/// Named characters in Lorna's story. Some become battle companions.
enum Person: String, CaseIterable, Codable, Identifiable {
    case giulia, teo, dario, vittoria, ottavia, benassi, rocco, nina, saverio, thug
    var id: String { rawValue }

    var name: String {
        switch self {
        case .giulia: "Giulia Ferri"
        case .teo: "Matteo \u{201C}Teo\u{201D} Ricci"
        case .dario: "Dario \u{201C}Il Gatto\u{201D} Monti"
        case .vittoria: "Vittoria Sangalli"
        case .ottavia: "Nonna Ottavia"
        case .benassi: "Prof. Aurelio Benassi"
        case .rocco: "Rocco Ferraccio"
        case .nina: "Nina \u{201C}La Lama\u{201D}"
        case .saverio: "Don Saverio Corvo"
        case .thug: "Corvonero Thug"
        }
    }

    var shortName: String {
        switch self {
        case .giulia: "Giulia"
        case .teo: "Teo"
        case .dario: "Dario"
        case .vittoria: "Vittoria"
        case .ottavia: "Nonna"
        case .benassi: "Benassi"
        case .rocco: "Rocco"
        case .nina: "Nina"
        case .saverio: "Don Saverio"
        case .thug: "Thug"
        }
    }

    var role: String {
        switch self {
        case .giulia: "Classmate · street artist"
        case .teo: "Classmate · hacker"
        case .dario: "Ex-courier of the Famiglia"
        case .vittoria: "Undercover Carabiniera"
        case .ottavia: "Lorna's grandmother"
        case .benassi: "Music teacher · composer"
        case .rocco: "Corvonero enforcer"
        case .nina: "Corvonero lieutenant"
        case .saverio: "Head of Famiglia Corvonero"
        case .thug: "Corvonero foot soldier"
        }
    }

    var portrait: String { "portrait_\(rawValue)" }
    var tint: Color {
        switch self {
        case .giulia: Theme.blueBright
        case .teo: Color(hex: 0x6FD3A8)
        case .dario: Color(hex: 0x9BE36F)
        case .vittoria: Color(hex: 0x8FA8FF)
        case .ottavia: Theme.apricot
        case .benassi: Theme.gold
        case .rocco, .nina, .saverio, .thug: Color(hex: 0xE0585B)
        }
    }

    /// Battle skill for companions.
    var skill: (name: String, detail: String)? {
        switch self {
        case .giulia: ("Sketch Snare", "Traps the enemy: it loses its next turn")
        case .teo: ("Hack the Lights", "Enemy attacks deal 35% less for 2 turns")
        case .dario: ("Ambush", "Deals 50 damage from the shadows")
        case .vittoria: ("Arrest Protocol", "70 damage to Corvonero members, 35 to spirits")
        case .ottavia: ("Brodo della Nonna", "Heals 55 HP and restores 20 Aura")
        default: nil
        }
    }

    static let companions: [Person] = [.giulia, .teo, .dario, .vittoria, .ottavia]
}

/// A battle partner: a human friend from the story or a befriended spirit.
enum Companion: Hashable, Codable, Identifiable {
    case person(Person)
    case spirit(SpiritKind)

    var id: String {
        switch self {
        case .person(let p): "p-\(p.rawValue)"
        case .spirit(let k): "s-\(k.rawValue)"
        }
    }

    var name: String {
        switch self {
        case .person(let p): p.shortName
        case .spirit(let k): k.name
        }
    }

    var skill: (name: String, detail: String) {
        switch self {
        case .person(let p): p.skill ?? ("Help", "Assists Lorna")
        case .spirit(let k): k.allySkill
        }
    }

    var tint: Color {
        switch self {
        case .person(let p): p.tint
        case .spirit(let k): k.glowColor
        }
    }
}

// MARK: - Items

enum Item: String, CaseIterable, Codable, Identifiable {
    case espresso, cornetto, gelato, santino, auraShard
    var id: String { rawValue }

    var name: String {
        switch self {
        case .espresso: "Espresso"
        case .cornetto: "Cornetto"
        case .gelato: "Gelato al pistacchio"
        case .santino: "Lucky Santino"
        case .auraShard: "Aura Shard"
        }
    }

    var detail: String {
        switch self {
        case .espresso: "Restores 40 Aura in battle."
        case .cornetto: "Restores 40 HP in battle."
        case .gelato: "Restores 25 HP and 25 Aura."
        case .santino: "Blocks the next enemy hit completely."
        case .auraShard: "Spend in the Bag to strengthen Lorna's powers."
        }
    }

    var symbol: String {
        switch self {
        case .espresso: "cup.and.saucer.fill"
        case .cornetto: "croissant.fill"
        case .gelato: "birthday.cake.fill"
        case .santino: "seal.fill"
        case .auraShard: "diamond.fill"
        }
    }

    var tint: Color {
        switch self {
        case .espresso: Color(hex: 0xC8875A)
        case .cornetto: Theme.apricot
        case .gelato: Color(hex: 0x9FD88A)
        case .santino: Theme.spirit
        case .auraShard: Theme.gold
        }
    }

    var usableInBattle: Bool { self != .auraShard }
}

// MARK: - Upgrades

enum Power: String, CaseIterable, Codable, Identifiable {
    case healing, teleport, combat
    var id: String { rawValue }

    var title: String {
        switch self {
        case .healing: "Healing"
        case .teleport: "Teleportation"
        case .combat: "Strategic Combat"
        }
    }

    var symbol: String {
        switch self {
        case .healing: "cross.case.fill"
        case .teleport: "arrow.triangle.swap"
        case .combat: "bolt.fill"
        }
    }

    func effect(level: Int) -> String {
        switch self {
        case .healing: "Heal restores \(Int(35 * (1 + 0.15 * Double(level - 1)))) HP"
        case .teleport: "Counter-strike after a dodge: \(10 + 6 * level) damage"
        case .combat: "Golden Burst ×\(String(format: "%.2f", 1 + 0.12 * Double(level - 1)))"
        }
    }

    static let maxLevel = 5
    static func cost(toReach level: Int) -> Int { level * 2 }
}

// MARK: - Enemies

/// What the enemy shows it will do next turn (telegraphed).
enum EnemyIntent: Equatable {
    case attack(Int)
    case heavy(Int)
    case charge
    case guardUp
    case drain(Int)

    var title: String {
        switch self {
        case .attack(let n): "Attack · \(n)"
        case .heavy(let n): "Heavy blow · \(n)"
        case .charge: "Charging up"
        case .guardUp: "Guarding"
        case .drain(let n): "Aura drain · \(n)"
        }
    }

    var symbol: String {
        switch self {
        case .attack: "hand.raised.fill"
        case .heavy: "exclamationmark.triangle.fill"
        case .charge: "bolt.badge.clock.fill"
        case .guardUp: "shield.fill"
        case .drain: "drop.fill"
        }
    }

    var hint: String {
        switch self {
        case .attack: "Guard halves it."
        case .heavy: "Teleport to dodge it!"
        case .charge: "A heavy blow is coming."
        case .guardUp: "Damage against it is halved."
        case .drain: "Steals Aura."
        }
    }
}

struct EnemyProfile: Equatable {
    let name: String
    let title: String
    let maxHP: Int
    let attack: Int
    let isBoss: Bool
    let isHuman: Bool
    let portrait: Person?
    let spirit: SpiritKind?
    /// HP fractions at which a boss enters a new phase, with its line.
    let phases: [(threshold: Double, line: String)]

    static func == (a: EnemyProfile, b: EnemyProfile) -> Bool { a.name == b.name && a.maxHP == b.maxHP }

    static func spirit(_ kind: SpiritKind, level: Int) -> EnemyProfile {
        EnemyProfile(name: kind.name, title: "\(kind.category) · \(kind.threatStars)",
                     maxHP: kind.maxHP + level * 6, attack: kind.attack + level / 2,
                     isBoss: false, isHuman: false, portrait: nil, spirit: kind, phases: [])
    }

    /// A gentler copy for the opening chapters, where players are still learning the moves.
    func eased(hp: Double, attack: Double) -> EnemyProfile {
        EnemyProfile(name: name, title: title,
                     maxHP: max(30, Int((Double(maxHP) * hp).rounded())),
                     attack: max(6, Int((Double(self.attack) * attack).rounded())),
                     isBoss: isBoss, isHuman: isHuman, portrait: portrait, spirit: spirit, phases: phases)
    }

    static let thug = EnemyProfile(name: "Corvonero Thug", title: "Foot soldier", maxHP: 110, attack: 12,
                                   isBoss: false, isHuman: true, portrait: .thug, spirit: nil, phases: [])
    static let courier = EnemyProfile(name: "Night Courier", title: "Corvonero runner", maxHP: 95, attack: 14,
                                      isBoss: false, isHuman: true, portrait: .thug, spirit: nil, phases: [])
    static let rocco = EnemyProfile(
        name: "Rocco Ferraccio", title: "Boss · The Iron Fist", maxHP: 260, attack: 18,
        isBoss: true, isHuman: true, portrait: .rocco, spirit: nil,
        phases: [(0.5, "\u{201C}Enough games, ragazzina. Now I get serious.\u{201D}")])
    static let nina = EnemyProfile(
        name: "Nina \u{201C}La Lama\u{201D}", title: "Boss · The Blade", maxHP: 300, attack: 20,
        isBoss: true, isHuman: true, portrait: .nina, spirit: nil,
        phases: [(0.6, "\u{201C}You dodge well. Let\u{2019}s see you dodge two blades.\u{201D}"),
                 (0.25, "\u{201C}Why\u{2026} why does your gold feel so warm?\u{201D}")])
    static let saverio = EnemyProfile(
        name: "Don Saverio Corvo", title: "Final boss · Il Corvo", maxHP: 420, attack: 22,
        isBoss: true, isHuman: true, portrait: .saverio, spirit: nil,
        phases: [(0.66, "\u{201C}The ravens answer only to me. Come, my children.\u{201D}"),
                 (0.33, "\u{201C}A song? You think a SONG can end the Famiglia?\u{201D}")])
}
