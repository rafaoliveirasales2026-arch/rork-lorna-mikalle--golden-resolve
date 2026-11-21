import RealityKit
import SwiftUI
import UIKit

/// Character portrait with a graceful fallback when the image is missing.
struct PortraitImage: View {
    let person: Person
    var size: CGFloat = 56
    var cornerRadius: CGFloat? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.28, style: .continuous)
        Group {
            if UIImage(named: person.portrait) != nil {
                Image(person.portrait)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [person.tint.opacity(0.55), Theme.ink], startPoint: .top, endPoint: .bottom)
                    Text(String(person.shortName.prefix(1)))
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Theme.cream)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(person.tint.opacity(0.8), lineWidth: 1.2))
        .accessibilityHidden(true)
    }
}

/// Turn-based battle UI. Draws over a live 3D stage (spirits) or a portrait backdrop (Corvonero members).
struct BattleView: View {
    let battle: BattleSession
    var stage: EncounterStage?
    let onFinish: (BattleSession.Outcome) -> Void
    let retry: () -> Void

    @Environment(GameState.self) private var game
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var floaters: [Floater] = []
    @State private var shake: CGFloat = 0
    @State private var hurtFlash = false
    @State private var phaseBanner: String?
    @State private var companionBanner: String?

    private struct Floater: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
        let x: CGFloat
        let onEnemy: Bool
    }

    /// Gentle coaching for the first two wins: reads the enemy's intent and suggests the answer.
    private var coachTip: (text: String, symbol: String, tint: Color)? {
        guard game.progress.battlesWon < 2, battle.outcome == nil, !battle.isBusy else { return nil }
        if battle.stunTurns > 0 { return ("It's stunned. Strike freely!", "hand.raised.fill", Theme.cream) }
        switch battle.intent {
        case .heavy: return ("Heavy blow coming. Teleport to dodge it", Power.teleport.symbol, Theme.spirit)
        case .charge: return ("It's charging. Guard, or hit it with Golden Burst now", "shield.fill", Theme.blueBright)
        default: break
        }
        if battle.aura >= BattleAction.burst.auraCost { return ("Aura full enough. Golden Burst hits hardest", "sparkles", Theme.gold) }
        if battle.lornaHP < battle.lornaMaxHP / 2 { return ("Low HP. Heal costs 25 Aura", Power.healing.symbol, Color(hex: 0x6FD3A8)) }
        return ("Strike builds Aura for your powers", "hand.raised.fill", Theme.cream)
    }

    var body: some View {
        ZStack {
            backdrop

            LinearGradient(colors: [Theme.ink.opacity(0.65), .clear, Theme.ink.opacity(0.6), Theme.ink.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            RadialGradient(colors: [.clear, Color(hex: 0xE0585B).opacity(hurtFlash ? 0.45 : 0)],
                           center: .center, startRadius: 120, endRadius: 520)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                topBar
                enemyCard
                Spacer(minLength: 0)
                if let banner = phaseBanner ?? companionBanner {
                    Text(banner)
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .hudGlass(in: Capsule())
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if let tip = coachTip {
                    Label(tip.text, systemImage: tip.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .labelStyle(TintedIconLabelStyle(tint: tip.tint))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .hudGlass(in: Capsule())
                        .id(tip.text)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityLabel("Tip: \(tip.text)")
                }
                lornaPanel
                logView
                actionGrid
            }
            .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            floaterLayer
                .allowsHitTesting(false)

            if let outcome = battle.outcome, outcome != .fled {
                outcomeCard(outcome)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: battle.outcome)
        .animation(.easeInOut(duration: 0.25), value: phaseBanner)
        .animation(.easeInOut(duration: 0.25), value: companionBanner)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: coachTip?.text)
        .sensoryFeedback(trigger: battle.beatToken) { _, _ in
            switch battle.beat {
            case .enemyHit(_, let critical): .impact(weight: critical ? .heavy : .medium)
            case .lornaHit: .impact(weight: .heavy, intensity: 1)
            case .dodged, .blocked: .impact(flexibility: .soft)
            case .lornaHealed: .success
            case .phase: .warning
            case .companion: .impact(weight: .light)
            case .none: nil
            }
        }
        .sensoryFeedback(.success, trigger: battle.outcome == .won)
        .onChange(of: battle.beatToken) { old, new in
            // Play every beat that landed since the last update, staggered so none is lost.
            let fresh = Array(battle.beats.suffix(max(0, min(new - old, battle.beats.count))))
            for (i, beat) in fresh.enumerated() {
                if i == 0 { react(to: beat) } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220 * i))
                        react(to: beat)
                    }
                }
            }
        }
        .onChange(of: battle.outcome) { _, outcome in
            if outcome == .fled { onFinish(.fled) }
        }
        .audioContext(.battle)
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if let stage {
            GeometryReader { geo in
                RealityView { content in
                    await stage.setup(in: &content, size: geo.size)
                }
                .onChange(of: geo.size) { _, size in stage.resize(size) }
            }
            .ignoresSafeArea()
            .background(Theme.ink)
        } else {
            ZStack {
                Theme.duskBackdrop
                RadialGradient(colors: [(battle.enemy.portrait?.tint ?? Theme.gold).opacity(0.35), .clear],
                               center: UnitPoint(x: 0.5, y: 0.38), startRadius: 10, endRadius: 360)
                if let person = battle.enemy.portrait {
                    PortraitImage(person: person, size: sizeClass == .regular ? 300 : 210, cornerRadius: 36)
                        .shadow(color: person.tint.opacity(0.5), radius: 30)
                        .rotationEffect(.degrees(-3))
                        .offset(x: shake, y: -40)
                        .opacity(battle.outcome == .won ? 0.35 : 1)
                        .saturation(battle.outcome == .won ? 0 : 1)
                } else if let kind = battle.enemy.spirit {
                    Image(systemName: "sparkles")
                        .font(.system(size: 120))
                        .foregroundStyle(kind.glowColor)
                        .shadow(color: kind.glowColor, radius: 30)
                        .offset(x: shake, y: -40)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            if !battle.enemy.isBoss && battle.outcome == nil {
                Button {
                    AudioManager.shared.play(.uiTap)
                    battle.flee()
                } label: {
                    Label("Retreat", systemImage: "figure.run")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .hudGlass(in: Capsule(), interactive: true)
            }
            Spacer()
            Text("Turn \(battle.turn)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.creamDim)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .hudGlass(in: Capsule())
        }
    }

    private var enemyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let person = battle.enemy.portrait {
                    PortraitImage(person: person, size: 44)
                } else if let kind = battle.enemy.spirit {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(kind.glowColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(kind.glowColor.opacity(0.18)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(battle.enemy.name)
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text(battle.enemy.title)
                        .font(.caption)
                        .foregroundStyle(battle.enemy.isBoss ? Theme.apricot : Theme.creamDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(battle.enemyHP)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText(value: Double(battle.enemyHP)))
                    .animation(.snappy, value: battle.enemyHP)
            }
            HPBar(value: Double(battle.enemyHP), maxValue: Double(battle.enemy.maxHP), tint: Color(hex: 0xE0585B))

            if battle.outcome == nil {
                HStack(spacing: 8) {
                    Image(systemName: battle.stunTurns > 0 ? "zzz" : battle.intent.symbol)
                        .foregroundStyle(intentColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: isDangerous)
                    Text(battle.stunTurns > 0 ? "Stunned · skips its turn" : "Next: \(battle.intent.title)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.cream)
                    Spacer(minLength: 4)
                    Text(battle.stunTurns > 0 ? "" : battle.intent.hint)
                        .font(.caption)
                        .foregroundStyle(Theme.creamDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(intentColor.opacity(0.16)))
                .overlay(Capsule().strokeBorder(intentColor.opacity(0.5), lineWidth: 0.8))
                .animation(.easeInOut(duration: 0.2), value: battle.intent)
            }
        }
        .padding(14)
        .hudGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var isDangerous: Bool {
        if case .heavy = battle.intent { return battle.stunTurns == 0 }
        return false
    }

    private var intentColor: Color {
        if battle.stunTurns > 0 { return Theme.spirit }
        switch battle.intent {
        case .heavy: return Color(hex: 0xE0585B)
        case .charge: return Theme.apricot
        case .guardUp: return Theme.blueBright
        case .drain: return Theme.spirit
        case .attack: return Theme.cream
        }
    }

    // MARK: Lorna

    private var lornaPanel: some View {
        HStack(spacing: 12) {
            Image("LornaPortrait")
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1.5))
                .offset(x: hurtFlash ? -4 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                statRow(label: "HP", value: battle.lornaHP, max: battle.lornaMaxHP, tint: Theme.blueBright)
                statRow(label: "Aura", value: battle.aura, max: 100, tint: Theme.gold)
            }

            if let companion = battle.companion {
                companionChip(companion)
            }
        }
        .padding(12)
        .hudGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statRow(label: String, value: Int, max: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, alignment: .leading)
            HPBar(value: Double(value), maxValue: Double(max), tint: tint)
            Text("\(value)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.cream)
                .frame(width: 34, alignment: .trailing)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
        }
    }

    private func companionChip(_ companion: Companion) -> some View {
        VStack(spacing: 3) {
            Group {
                if case .person(let p) = companion {
                    PortraitImage(person: p, size: 34)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(companion.tint)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(companion.tint.opacity(0.2)))
                }
            }
            .opacity(battle.companionReady ? 1 : 0.5)
            Text(battle.cooldown > 0 ? "\(battle.cooldown)" : "Ready")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(battle.cooldown > 0 ? Theme.creamDim : companion.tint)
        }
        .frame(width: 50)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(companion.name), \(battle.cooldown > 0 ? "ready in \(battle.cooldown) turns" : "ready")")
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(battle.log.suffix(2).enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(i == battle.log.suffix(2).count - 1 ? Theme.cream : Theme.creamDim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 58, alignment: .topLeading)
        .panelSurface(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.2), value: battle.log)
    }

    // MARK: Actions

    private var actionGrid: some View {
        let inventory = game.progress.inventory
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(.strike, title: "Strike", symbol: "hand.raised.fill", tint: Theme.cream, inventory: inventory)
                actionButton(.burst, title: "Golden Burst", symbol: "sparkles", tint: Theme.gold, inventory: inventory)
                actionButton(.heal, title: "Heal", symbol: Power.healing.symbol, tint: Color(hex: 0x6FD3A8), inventory: inventory)
            }
            HStack(spacing: 10) {
                actionButton(.teleport, title: "Teleport", symbol: Power.teleport.symbol, tint: Theme.spirit, inventory: inventory)
                actionButton(.guardUp, title: "Guard", symbol: "shield.fill", tint: Theme.blueBright, inventory: inventory)
                if let companion = battle.companion {
                    actionButton(.companion, title: companion.skill.name, symbol: "person.2.fill", tint: companion.tint, inventory: inventory)
                } else {
                    itemsMenu(inventory)
                }
            }
            if battle.companion != nil {
                itemsMenu(inventory)
            }
        }
    }

    private func actionButton(_ action: BattleAction, title: String, symbol: String, tint: Color, inventory: [Item: Int]) -> some View {
        let enabled = battle.canUse(action, inventory: inventory)
        return Button {
            Task { await battle.perform(action) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(enabled ? tint : Theme.creamDim)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if action.auraCost > 0 {
                    Text("\(action.auraCost) Aura")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(battle.aura >= action.auraCost ? Theme.gold : Color(hex: 0xE0585B))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink.opacity(enabled ? 0.75 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(enabled ? 0.7 : 0.15), lineWidth: 1))
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }

    private func itemsMenu(_ inventory: [Item: Int]) -> some View {
        let usable = Item.allCases.filter(\.usableInBattle)
        let anyAvailable = usable.contains { battle.canUse(.item($0), inventory: inventory) }
        return Menu {
            ForEach(usable) { item in
                let left = (inventory[item] ?? 0) - (battle.itemsUsedCount(item))
                Button {
                    Task { await battle.perform(.item(item)) }
                } label: {
                    Label("\(item.name) ×\(left) — \(item.detail)", systemImage: item.symbol)
                }
                .disabled(!battle.canUse(.item(item), inventory: inventory))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bag.fill")
                    .foregroundStyle(Theme.apricot)
                Text("Items")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
            }
            .frame(maxWidth: .infinity, minHeight: battle.companion == nil ? 66 : 44)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.apricot.opacity(anyAvailable ? 0.6 : 0.15), lineWidth: 1))
            .opacity(anyAvailable ? 1 : 0.55)
        }
        .disabled(!anyAvailable)
    }

    // MARK: Floaters & reactions

    private var floaterLayer: some View {
        GeometryReader { geo in
            ForEach(floaters) { f in
                FloatingNumber(text: f.text, color: f.color)
                    .position(x: geo.size.width / 2 + f.x, y: f.onEnemy ? geo.size.height * 0.36 : geo.size.height * 0.6)
            }
        }
    }

    private func react(to beat: BattleBeat) {
        switch beat {
        case .enemyHit(let n, let critical):
            spawn(critical ? "−\(n)!" : "−\(n)", color: critical ? Theme.goldLight : Theme.cream, onEnemy: true)
            stage?.recoil()
            if critical { stage?.cast() }
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shake = 14 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) { shake = 0 }
        case .lornaHit(let n):
            spawn("−\(n)", color: Color(hex: 0xE0585B), onEnemy: false)
            withAnimation(.easeOut(duration: 0.12)) { hurtFlash = true }
            withAnimation(.easeIn(duration: 0.4).delay(0.15)) { hurtFlash = false }
        case .lornaHealed(let n):
            spawn("+\(n)", color: Color(hex: 0x6FD3A8), onEnemy: false)
            stage?.cast()
        case .dodged:
            spawn("Dodged!", color: Theme.spirit, onEnemy: false)
        case .blocked:
            spawn("Blocked", color: Theme.blueBright, onEnemy: false)
        case .companion(let name):
            flash(phase: false, name)
        case .phase(let line):
            flash(phase: true, line, seconds: 2.4)
        case .none:
            break
        }
    }

    private func spawn(_ text: String, color: Color, onEnemy: Bool) {
        let f = Floater(text: text, color: color, x: .random(in: -40...40), onEnemy: onEnemy)
        floaters.append(f)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            floaters.removeAll { $0.id == f.id }
        }
    }

    private func flash(phase: Bool, _ text: String, seconds: Double = 1.4) {
        if phase { phaseBanner = text } else { companionBanner = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if phase {
                if phaseBanner == text { phaseBanner = nil }
            } else if companionBanner == text {
                companionBanner = nil
            }
        }
    }

    // MARK: Outcome

    private func outcomeCard(_ outcome: BattleSession.Outcome) -> some View {
        ZStack {
            Theme.ink.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: outcome == .won ? "sparkles" : "heart.slash.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(outcome == .won ? Theme.gold : Color(hex: 0xE0585B))
                    .symbolEffect(.bounce, value: battle.outcome)
                Text(outcome == .won ? (battle.enemy.isHuman ? "Victory" : "Spirit calmed") : "Lorna is exhausted")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.cream)
                if outcome == .won {
                    Text(battle.reward.summary)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.goldLight)
                        .multilineTextAlignment(.center)
                    if game.xpMultiplier > 1 {
                        Text("Event bonus ×\(String(format: "%.2g", game.xpMultiplier)) XP")
                            .font(.subheadline)
                            .foregroundStyle(Theme.apricot)
                    }
                    if case .person(let p) = battle.companion {
                        Text("\(p.shortName) affinity +15")
                            .font(.subheadline)
                            .foregroundStyle(p.tint)
                    }
                    Button {
                        onFinish(.won)
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(GoldButtonStyle())
                } else {
                    Text("Her gold flickers. Catch your breath and try again: watch the enemy's next move and answer it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.creamDim)
                        .multilineTextAlignment(.center)
                    Button {
                        retry()
                    } label: {
                        Label("Try again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(GoldButtonStyle())
                    if !battle.enemy.isBoss || stage != nil {
                        Button {
                            onFinish(.lost)
                        } label: {
                            Text("Back")
                        }
                        .buttonStyle(BlueOutlineButtonStyle())
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .panelSurface(cornerRadius: 28)
            .padding(24)
        }
    }
}

private struct FloatingNumber: View {
    let text: String
    let color: Color
    @State private var up = false

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            .shadow(color: color.opacity(0.6), radius: 10)
            .offset(y: up ? -60 : 0)
            .opacity(up ? 0 : 1)
            .scaleEffect(up ? 1.1 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) { up = true }
            }
    }
}
