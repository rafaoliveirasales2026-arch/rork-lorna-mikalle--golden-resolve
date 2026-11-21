import SwiftUI
import UIKit

enum SpiritKind: String, CaseIterable, Codable {
    case lanternWisp, echoChild, ashenVeil, fontanaNymph, bellTowerCrow, vespaPhantom

    var name: String {
        switch self {
        case .lanternWisp: "Lantern Wisp"
        case .echoChild: "Echo Child"
        case .ashenVeil: "Ashen Veil"
        case .fontanaNymph: "Fontana Nymph"
        case .bellTowerCrow: "Bell Tower Crow"
        case .vespaPhantom: "Vespa Phantom"
        }
    }

    var category: String {
        switch self {
        case .lanternWisp: "Lost Spirit"
        case .echoChild: "Mimic Spirit"
        case .ashenVeil: "Wrath Spirit"
        case .fontanaNymph: "Water Spirit"
        case .bellTowerCrow: "Omen Spirit"
        case .vespaPhantom: "Speed Spirit"
        }
    }

    /// Threat level out of 3.
    var threat: Int {
        switch self {
        case .lanternWisp: 2
        case .echoChild: 1
        case .ashenVeil: 3
        case .fontanaNymph: 1
        case .bellTowerCrow: 2
        case .vespaPhantom: 3
        }
    }

    var threatStars: String {
        String(repeating: "★", count: threat) + String(repeating: "☆", count: 3 - threat)
    }

    var maxHP: Int {
        switch self {
        case .lanternWisp: 120
        case .echoChild: 90
        case .ashenVeil: 160
        case .fontanaNymph: 100
        case .bellTowerCrow: 130
        case .vespaPhantom: 150
        }
    }

    var dialogue: [String] {
        switch self {
        case .lanternWisp: [
            "\u{201C}You can see me? Then\u{2026} help me find the way home, or leave this street.\u{201D}",
            "\u{201C}My lantern used to light this road. Now nobody looks up anymore.\u{201D}",
            "\u{201C}Your eyes are gold\u{2026} like the lamps when they were new.\u{201D}",
        ]
        case .echoChild: [
            "\u{201C}You can see me? You can see me? \u{2026}see me?\u{201D}",
            "\u{201C}I copy the footsteps of people walking past. Yours are loud.\u{201D}",
            "\u{201C}Play with me before the streetlights change.\u{201D}",
        ]
        case .ashenVeil: [
            "\u{201C}This street remembers what you forgot. Turn back.\u{201D}",
            "\u{201C}Every corner here burned once. I am what stayed.\u{201D}",
            "\u{201C}Gold won\u{2019}t burn. Let\u{2019}s test that.\u{201D}",
        ]
        case .fontanaNymph: [
            "\u{201C}Somebody threw a coin and wished for a scooter. I am not a dealership.\u{201D}",
            "\u{201C}Every fountain in Italy is connected. We gossip through the pipes.\u{201D}",
            "\u{201C}You smell like espresso and destiny. Mostly espresso.\u{201D}",
        ]
        case .bellTowerCrow: [
            "\u{201C}CAW. The bells rang thirteen times last night. Nobody counted but me.\u{201D}",
            "\u{201C}The ravens in black suits are not my cousins. Tell them that.\u{201D}",
            "\u{201C}Bring me a shiny thing and I\u{2019}ll tell you a secret. CAW.\u{201D}",
        ]
        case .vespaPhantom: [
            "\u{201C}VRRRM. I was a scooter in 1962. I was happier then.\u{201D}",
            "\u{201C}Catch me if you\u{2026} oh. You teleport. That\u{2019}s cheating.\u{201D}",
            "\u{201C}The couriers ride too fast in these streets. I know their routes.\u{201D}",
        ]
        }
    }

    var glow: UInt32 {
        switch self {
        case .lanternWisp: 0x9FD8F5
        case .echoChild: 0xB8E8FF
        case .ashenVeil: 0xC7B3F0
        case .fontanaNymph: 0x7FE3D4
        case .bellTowerCrow: 0xA8B4E8
        case .vespaPhantom: 0xF5C08A
        }
    }

    var scale: Float {
        switch self {
        case .lanternWisp: 1.0
        case .echoChild: 0.7
        case .ashenVeil: 1.2
        case .fontanaNymph: 0.95
        case .bellTowerCrow: 0.8
        case .vespaPhantom: 1.05
        }
    }

    var hasLantern: Bool { self == .lanternWisp }
    var glowColor: Color { Color(hex: glow) }

    /// Attack power used in battles.
    var attack: Int { 8 + threat * 5 }

    /// What this spirit does for Lorna once befriended (3 bonds).
    var allySkill: (name: String, detail: String) {
        switch self {
        case .lanternWisp: ("Lantern Light", "Heals Lorna 30 HP")
        case .echoChild: ("Echo", "Repeats Lorna's last hit at 60%")
        case .ashenVeil: ("Ember Veil", "Deals 45 damage")
        case .fontanaNymph: ("Spring Water", "Heals 40 HP and clears weakness")
        case .bellTowerCrow: ("Thirteenth Bell", "Stuns the enemy for a turn")
        case .vespaPhantom: ("Sting Run", "Three quick 15-damage hits")
        }
    }

    /// Spirits that only appear in certain conditions.
    static func spawnPool(isNight: Bool, nearWater: Bool, spiritNight: Bool) -> [SpiritKind] {
        var pool: [SpiritKind] = [.lanternWisp, .echoChild, .bellTowerCrow, .vespaPhantom]
        if isNight || spiritNight { pool += [.ashenVeil, .lanternWisp] } else { pool += [.echoChild, .vespaPhantom] }
        if nearWater { pool += [.fontanaNymph, .fontanaNymph] } else { pool.append(.fontanaNymph) }
        if spiritNight { pool += [.ashenVeil, .bellTowerCrow] }
        return pool
    }
}
