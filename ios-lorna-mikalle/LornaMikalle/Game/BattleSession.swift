import Foundation
import Observation

enum BattleAction: Equatable {
    case strike, burst, heal, teleport, guardUp, companion, item(Item)

    var auraCost: Int {
        switch self {
        case .burst: 40
        case .heal: 25
        case .teleport: 20
        default: 0
        }
    }
}

/// A visual beat the battle view animates (each one bumps `beatToken`).
enum BattleBeat: Equatable {
    case none
    case enemyHit(Int, critical: Bool)
    case lornaHit(Int)
    case lornaHealed(Int)
    case dodged
    case blocked
    case companion(String)
    case phase(String)
}

/// One turn-based fight: Lorna (+ one companion) against a spirit or a Corvonero member.
@Observable
final class BattleSession: Identifiable {
    let id = UUID()
    let enemy: EnemyProfile
    let companion: Companion?
    let level: Int
    let powers: [Power: Int]
    let companionBoost: Double

    var enemyHP: Int
    var enemyAttack: Int
    var intent: EnemyIntent = .attack(10)
    var lornaHP: Int
    let lornaMaxHP: Int
    var aura = 60
    var cooldown = 0
    var log: [String] = []
    var beat: BattleBeat = .none
    var beatToken = 0
    /// Every beat in order (count == beatToken), so the view never drops one that lands in the same
    /// instant as another (a hit that also triggers a boss phase, a dodge + counter, …).
    private(set) var beats: [BattleBeat] = []
    var isBusy = false
    var outcome: Outcome?
    var turn = 1

    var stunTurns = 0
    var weakTurns = 0
    var enemyGuarding = false
    private var charged = false
    private var phaseIndex = 0
    private var lornaGuarding = false
    private var dodging = false
    private var santino = false
    private var lastLornaDamage = 0

    // Counters reported back to progress.
    private(set) var healsUsed = 0
    private(set) var dodgesLanded = 0
    private(set) var itemsUsed: [Item: Int] = [:]

    enum Outcome { case won, lost, fled }

    init(enemy: EnemyProfile, companion: Companion?, progress: PlayerProgress) {
        self.enemy = enemy
        self.companion = companion
        self.level = progress.level
        self.powers = progress.powers
        if case .person(let p) = companion {
            companionBoost = 1 + 0.1 * Double(progress.affinityLevel(p) - 1)
        } else {
            companionBoost = 1
        }
        enemyHP = enemy.maxHP
        enemyAttack = enemy.attack
        lornaMaxHP = progress.maxHP
        lornaHP = progress.maxHP
        intent = chooseIntent()
        log = [enemy.isBoss ? "\(enemy.name) blocks the way!" : "\(enemy.name) appears!"]
    }

    func itemsUsedCount(_ item: Item) -> Int { itemsUsed[item] ?? 0 }

    var enemyFraction: Double { Double(enemyHP) / Double(enemy.maxHP) }
    var companionReady: Bool { companion != nil && cooldown == 0 }
    private func power(_ p: Power) -> Int { powers[p] ?? 1 }

    func canUse(_ action: BattleAction, inventory: [Item: Int]) -> Bool {
        guard outcome == nil, !isBusy else { return false }
        switch action {
        case .companion: return companionReady
        case .item(let item): return item.usableInBattle && (inventory[item] ?? 0) - (itemsUsed[item] ?? 0) > 0
        case .heal: return aura >= action.auraCost && lornaHP < lornaMaxHP
        default: return aura >= action.auraCost
        }
    }

    // MARK: - Turn

    /// Resolves Lorna's action, then the enemy's telegraphed move after a short beat.
    func perform(_ action: BattleAction) async {
        guard outcome == nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        aura -= action.auraCost
        lornaGuarding = false
        dodging = false

        switch action {
        case .strike:
            let dmg = Int(Double(14 + level * 2 + power(.combat) * 2) * Double.random(in: 0.9...1.15))
            hitEnemy(dmg, sfx: .attackStrike)
            aura = min(100, aura + 15)
        case .burst:
            let mult = 1 + 0.12 * Double(power(.combat) - 1)
            let dmg = Int(Double(48 + level * 3) * mult * Double.random(in: 0.95...1.1))
            AudioManager.shared.play(.specialAttack)
            let dealt = hitEnemy(dmg, critical: true, sfx: .impact)
            write("Golden Burst! \(dealt) damage\(dealt < dmg ? " (guarded)" : "").")
        case .heal:
            let amount = Int(35 * (1 + 0.15 * Double(power(.healing) - 1)))
            let healed = healLorna(amount)
            healsUsed += 1
            AudioManager.shared.play(.heal)
            write("Lorna's golden light heals \(healed) HP.")
        case .teleport:
            dodging = true
            AudioManager.shared.play(.teleport)
            write("Lorna blinks out of reach\u{2026}")
        case .guardUp:
            lornaGuarding = true
            aura = min(100, aura + 10)
            AudioManager.shared.play(.guardUp)
            write("Lorna braces herself.")
        case .companion:
            useCompanion()
            cooldown = 4
        case .item(let item):
            useItem(item)
        }

        if checkEnd() { return }
        try? await Task.sleep(for: .milliseconds(850))
        enemyTurn()
        _ = checkEnd()
        cooldown = max(0, cooldown - 1)
        turn += 1
    }

    func flee() {
        guard !enemy.isBoss else { return }
        outcome = .fled
    }

    // MARK: - Pieces

    /// Applies damage and returns what was actually removed from the enemy's HP, so the floating
    /// number, the log and the HP bar always agree.
    @discardableResult
    private func hitEnemy(_ raw: Int, critical: Bool = false, sfx: Sfx = .impact, by attacker: String = "Lorna") -> Int {
        var dmg = raw
        if enemyGuarding { dmg /= 2 }
        dmg = min(max(1, dmg), enemyHP)
        enemyHP -= dmg
        lastLornaDamage = dmg
        emit(.enemyHit(dmg, critical: critical))
        AudioManager.shared.play(sfx)
        if !critical { write(enemyGuarding ? "\(dmg) damage (guarded)." : "\(attacker) strikes for \(dmg).") }
        checkPhase()
        return dmg
    }

    /// Heals and returns the HP actually restored (never over max).
    @discardableResult
    private func healLorna(_ amount: Int) -> Int {
        let healed = max(0, min(lornaMaxHP, lornaHP + amount) - lornaHP)
        lornaHP += healed
        emit(.lornaHealed(healed))
        return healed
    }

    private func useCompanion() {
        guard let companion else { return }
        let b = companionBoost
        AudioManager.shared.play(.friendship)
        emit(.companion(companion.skill.name))
        let who = companion.skill.name
        switch companion {
        case .person(.giulia), .spirit(.bellTowerCrow):
            stunTurns = 1
            write("\(companion.skill.name)! \(enemy.name) is stuck for a turn.")
        case .person(.teo):
            weakTurns = 2
            write("\(companion.skill.name)! Enemy attacks weakened.")
        case .person(.dario):
            hitEnemy(Int(50 * b), by: who)
        case .person(.vittoria):
            hitEnemy(Int((enemy.isHuman ? 70 : 35) * b), by: who)
        case .person(.ottavia):
            let healed = healLorna(Int(55 * b))
            aura = min(100, aura + 20)
            write("Nonna's brodo: +\(healed) HP, +20 Aura.")
        case .spirit(.lanternWisp):
            write("Lantern Light: +\(healLorna(30)) HP.")
        case .spirit(.fontanaNymph):
            let healed = healLorna(40)
            weakTurns = max(weakTurns, 1)
            write("Spring Water: +\(healed) HP.")
        case .spirit(.echoChild):
            hitEnemy(max(8, Int(Double(lastLornaDamage) * 0.6)), by: who)
        case .spirit(.ashenVeil):
            hitEnemy(45, by: who)
        case .spirit(.vespaPhantom):
            hitEnemy(45, by: who)
        default:
            hitEnemy(30, by: who)
        }
    }

    private func useItem(_ item: Item) {
        itemsUsed[item, default: 0] += 1
        AudioManager.shared.play(.uiItem)
        switch item {
        case .espresso:
            aura = min(100, aura + 40)
            write("Espresso! +40 Aura.")
        case .cornetto:
            write("Cornetto: +\(healLorna(40)) HP.")
        case .gelato:
            let healed = healLorna(25)
            aura = min(100, aura + 25)
            write("Gelato: +\(healed) HP, +25 Aura.")
        case .santino:
            santino = true
            write("The Santino glows: the next hit is blocked.")
        case .auraShard:
            break
        }
    }

    private func enemyTurn() {
        enemyGuarding = false
        if stunTurns > 0 {
            stunTurns -= 1
            write("\(enemy.name) can't move!")
            intent = chooseIntent()
            return
        }
        let weak = weakTurns > 0 ? 0.65 : 1.0
        weakTurns = max(0, weakTurns - 1)

        func incoming(_ base: Int) {
            if dodging {
                dodgesLanded += 1
                emit(.dodged)
                AudioManager.shared.play(.dodge)
                let counter = 10 + 6 * power(.teleport)
                write("Dodged! Lorna reappears behind and counters.")
                hitEnemy(counter, by: "Lorna's counter")
                return
            }
            if santino {
                santino = false
                emit(.blocked)
                AudioManager.shared.play(.guardUp)
                write("The Santino blocks the blow.")
                return
            }
            var dmg = Double(base) * weak * Double.random(in: 0.9...1.1)
            if lornaGuarding { dmg *= 0.5 }
            let d = min(max(1, Int(dmg)), lornaHP)
            lornaHP -= d
            emit(.lornaHit(d))
            AudioManager.shared.play(.impact, volume: 0.8)
            write("\(enemy.name) hits Lorna for \(d)\(lornaGuarding ? " (guarded)" : "").")
        }

        switch intent {
        case .attack(let n): incoming(n)
        case .heavy(let n): incoming(n)
        case .charge:
            charged = true
            write("\(enemy.name) is gathering strength\u{2026}")
        case .guardUp:
            enemyGuarding = true
            write("\(enemy.name) takes a defensive stance.")
        case .drain(let n):
            if dodging {
                incoming(n)
            } else {
                aura = max(0, aura - n)
                incoming(n / 2)
                write("It drains \(n) Aura.")
            }
        }
        intent = chooseIntent()
    }

    private func chooseIntent() -> EnemyIntent {
        if charged {
            charged = false
            return .heavy(Int(Double(enemyAttack) * 2.2))
        }
        let roll = Double.random(in: 0..<1)
        let heavyChance = enemy.isBoss ? 0.12 + 0.06 * Double(phaseIndex) : 0
        if roll < heavyChance { return .heavy(Int(Double(enemyAttack) * 1.8)) }
        if roll < heavyChance + 0.2 { return .charge }
        if roll < heavyChance + 0.34 { return enemy.isHuman ? .guardUp : .drain(15 + enemy.attack / 2) }
        return .attack(enemyAttack)
    }

    private func checkPhase() {
        guard phaseIndex < enemy.phases.count, enemyHP > 0,
              enemyFraction <= enemy.phases[phaseIndex].threshold else { return }
        let line = enemy.phases[phaseIndex].line
        phaseIndex += 1
        enemyAttack += 4
        emit(.phase(line))
        AudioManager.shared.play(.bossIntro, volume: 0.7)
        write(line)
    }

    @discardableResult
    private func checkEnd() -> Bool {
        if enemyHP <= 0 {
            reward = makeReward()
            outcome = .won
            AudioManager.shared.play(.enemyDefeat)
            write(enemy.isHuman ? "\(enemy.name) is down!" : "\(enemy.name) is calm again.")
            return true
        }
        if lornaHP <= 0 {
            outcome = .lost
            write("Lorna is exhausted\u{2026}")
            return true
        }
        return false
    }

    private func emit(_ b: BattleBeat) {
        beat = b
        beats.append(b)
        beatToken += 1
    }

    private func write(_ line: String) {
        log.append(line)
        if log.count > 4 { log.removeFirst(log.count - 4) }
    }

    // MARK: - Rewards

    /// Fixed when the battle is won, so the screen shows exactly what is granted.
    private(set) var reward = Reward()

    private func makeReward() -> Reward {
        if enemy.isBoss { return Reward(xp: 600, items: [.auraShard: 2, .gelato: 1]) }
        if enemy.isHuman { return Reward(xp: 180, items: Bool.random() ? [.espresso: 1] : [.cornetto: 1]) }
        let threat = enemy.spirit?.threat ?? 1
        return Reward(xp: 120 + threat * 40, items: threat >= 3 || Int.random(in: 0..<3) == 0 ? [.auraShard: 1] : [:])
    }
}
