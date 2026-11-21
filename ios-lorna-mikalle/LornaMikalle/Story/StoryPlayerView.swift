import SwiftUI

/// Full-screen chapter player: scene cards, typed dialogue with portraits, choices, inline battles.
struct StoryPlayerView: View {
    let run: StoryRun
    @Environment(GameState.self) private var game
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var visible = 0
    @State private var typing: Task<Void, Never>?
    @State private var alarmFight = false

    private var beats: [StoryBeat] { run.chapter.beats }
    private var isFinished: Bool { run.index >= beats.count && run.pendingChoiceReply.isEmpty }
    private var beat: StoryBeat? { run.index < beats.count ? beats[run.index] : nil }

    /// What is on screen right now (a pending reply line wins over the next beat).
    private var currentLine: (Speaker, String)? {
        if let first = run.pendingChoiceReply.first { return first }
        if case .line(let s, let t)? = beat { return (s, t) }
        return nil
    }

    private var lineKey: String { "\(run.index)-\(run.pendingChoiceReply.count)" }

    var body: some View {
        ZStack {
            background

            if let battle = run.battle {
                BattleView(battle: battle, stage: nil) { outcome in
                    battleFinished(battle, outcome: outcome)
                } retry: {
                    game.finishBattle(battle)
                    run.battle = game.makeBattle(battle.enemy, ally: allyFor(battle))
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 14) {
                    header
                    Spacer(minLength: 0)
                    content
                }
                .frame(maxWidth: sizeClass == .regular ? 680 : .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: run.battle?.id)
        .animation(.easeInOut(duration: 0.3), value: lineKey)
        .preferredColorScheme(.dark)
        .audioContext(.story)
        .task(id: lineKey) { await enter() }
        .onDisappear { typing?.cancel() }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Theme.duskBackdrop
            if case let (speaker, _)? = currentLine, case .person(let p) = speaker {
                PortraitImage(person: p, size: 520, cornerRadius: 0)
                    .blur(radius: 40)
                    .opacity(0.35)
                    .id(p)
                    .transition(.opacity)
            }
            RadialGradient(colors: [Theme.gold.opacity(0.18), .clear],
                           center: UnitPoint(x: 0.5, y: 0.25), startRadius: 10, endRadius: 420)
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.85)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                RoundHUDButton(systemImage: "xmark", label: "Close story") { close() }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(run.chapter.number.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                    Text(run.chapter.title)
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                    if let place = currentPlace {
                        Text(place)
                            .font(.caption)
                            .foregroundStyle(Theme.creamDim)
                    }
                }
            }
            ProgressView(value: Double(min(run.index, beats.count)), total: Double(max(beats.count, 1)))
                .tint(Theme.gold)
            if run.chapter.usesAlarm {
                alarmMeter
            }
        }
        .padding(.top, 8)
    }

    private var currentPlace: String? {
        let upTo = min(run.index, beats.count - 1)
        guard upTo >= 0 else { return nil }
        for i in stride(from: upTo, through: 0, by: -1) {
            if case .scene(let place, _) = beats[i] { return place }
        }
        return nil
    }

    private var alarmMeter: some View {
        let color: Color = run.alarm >= 70 ? Color(hex: 0xE0585B) : (run.alarm >= 40 ? Theme.apricot : Theme.spirit)
        return HStack(spacing: 10) {
            Image(systemName: run.alarm >= 70 ? "exclamationmark.triangle.fill" : "eye.slash.fill")
                .foregroundStyle(color)
                .symbolEffect(.pulse, options: .repeating, isActive: run.alarm >= 70)
            Text("Alarm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.cream)
            HPBar(value: Double(run.alarm), maxValue: 100, tint: color)
            Text("\(min(run.alarm, 100))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.cream)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .hudGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isFinished {
            chapterComplete
        } else if case let (speaker, text)? = currentLine {
            dialogue(speaker: speaker, text: text)
        } else if let beat {
            switch beat {
            case .scene(let place, let time):
                sceneCard(place: place, time: time)
            case .choice(let choices):
                choicePanel(choices)
            case .join(let person):
                joinCard(person)
            case .reward(let reward):
                rewardCard(reward)
            case .alarmCheck:
                alarmCard
            case .battle(let enemy, _):
                battleIntro(enemy)
            case .line:
                EmptyView()
            }
        }
    }

    private func dialogue(speaker: Speaker, text: String) -> some View {
        let shown = String(text.prefix(visible))
        return Button {
            tapDialogue(text)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if speaker != .narrator {
                    HStack(alignment: .bottom, spacing: 10) {
                        speakerPortrait(speaker)
                        Text(speaker.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.cream)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.plum.opacity(0.95)))
                            .overlay(Capsule().strokeBorder(speaker.tint.opacity(0.9), lineWidth: 1))
                            .padding(.bottom, 4)
                        DiamondRule(color: speaker.tint)
                            .padding(.bottom, 14)
                    }
                    .zIndex(1)
                }
                ZStack(alignment: .topLeading) {
                    // Reserve the full height so the box does not grow while typing.
                    Text(text).hidden()
                    Text(shown)
                }
                .font(speaker == .narrator ? .title3.italic() : .title3)
                .foregroundStyle(speaker == .narrator ? Theme.creamDim : Theme.cream)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.top, speaker == .narrator ? 18 : 22)
                .padding(.bottom, 34)
                .panelSurface(cornerRadius: 20)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: visible >= text.count ? "chevron.down" : "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.gold)
                        .symbolEffect(.pulse, options: .repeating, isActive: visible >= text.count)
                        .padding(14)
                }
                .padding(.top, speaker == .narrator ? 0 : -12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speaker == .narrator ? text : "\(speaker.name): \(text)")
        .accessibilityHint("Double-tap to continue")
    }

    @ViewBuilder
    private func speakerPortrait(_ speaker: Speaker) -> some View {
        switch speaker {
        case .person(let p):
            PortraitImage(person: p, size: 72)
        case .lorna:
            Image("LornaPortrait")
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1.2))
        case .spirit(let k):
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(k.glowColor)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(k.glowColor.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(k.glowColor.opacity(0.8), lineWidth: 1.2))
        case .other:
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(Theme.spirit)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.ink.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.spirit.opacity(0.6), lineWidth: 1.2))
        case .narrator:
            EmptyView()
        }
    }

    private func sceneCard(place: String, time: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 8) {
                DiamondRule().frame(width: 120)
                Text(place)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                Text(time)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.gold)
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            Spacer()
            Button { advance() } label: { Label("Continue", systemImage: "arrow.right") }
                .buttonStyle(GoldButtonStyle())
        }
    }

    private func choicePanel(_ choices: [StoryChoice]) -> some View {
        VStack(spacing: 12) {
            Text("What does Lorna do?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button {
                    pick(choice)
                } label: {
                    HStack(spacing: 10) {
                        Text(choice.label)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if run.chapter.usesAlarm && choice.alarm > 0 {
                            Label("+\(choice.alarm)", systemImage: "eye.fill")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.apricot)
                        }
                        if case let (p, _)? = choice.affinity {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(p.tint)
                                .accessibilityLabel("\(p.shortName) will like this")
                        }
                    }
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.ink.opacity(0.8)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.blueBright.opacity(0.8), lineWidth: 1.1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func joinCard(_ person: Person) -> some View {
        VStack(spacing: 14) {
            PortraitImage(person: person, size: 120)
                .shadow(color: person.tint.opacity(0.5), radius: 20)
            Text("\(person.shortName) joins Lorna")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(person.role)
                .font(.subheadline)
                .foregroundStyle(Theme.creamDim)
            if let skill = person.skill {
                VStack(spacing: 4) {
                    Label(skill.name, systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(person.tint)
                    Text(skill.detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .panelSurface(cornerRadius: 18)
            }
            Button {
                game.join(person)
                advance()
            } label: { Label("Welcome, \(person.shortName)", systemImage: "person.badge.plus") }
                .buttonStyle(GoldButtonStyle())
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func rewardCard(_ reward: Reward) -> some View {
        let firstTime = game.progress.storyChapter == run.chapter.id
        return VStack(spacing: 14) {
            Image(systemName: "gift.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.gold)
                .symbolEffect(.bounce, value: run.index)
            Text(firstTime ? reward.summary : "Already collected")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.cream)
                .multilineTextAlignment(.center)
            Button {
                if firstTime {
                    AudioManager.shared.play(.reward)
                    game.grant(reward, reason: run.chapter.title)
                }
                advance()
            } label: { Label(firstTime ? "Collect" : "Continue", systemImage: "sparkles") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(22)
        .panelSurface(cornerRadius: 26)
    }

    private var alarmCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(hex: 0xE0585B))
            Text("Too much noise. A guard heard you!")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.cream)
                .multilineTextAlignment(.center)
            Button {
                alarmFight = true
                run.battle = game.makeBattle(.thug)
            } label: { Label("Fight", systemImage: "bolt.fill") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(22)
        .panelSurface(cornerRadius: 26)
    }

    private func battleIntro(_ enemy: EnemyProfile) -> some View {
        VStack(spacing: 14) {
            if let p = enemy.portrait {
                PortraitImage(person: p, size: 110)
                    .shadow(color: p.tint.opacity(0.5), radius: 18)
            } else if let k = enemy.spirit {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(k.glowColor)
                    .shadow(color: k.glowColor, radius: 18)
            }
            Text(enemy.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(enemy.title)
                .font(.subheadline)
                .foregroundStyle(enemy.isBoss ? Theme.apricot : Theme.creamDim)
            Button {
                startBattle()
            } label: { Label(enemy.isBoss ? "Face the boss" : "Battle", systemImage: "bolt.fill") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(22)
        .panelSurface(cornerRadius: 26)
    }

    private var chapterComplete: some View {
        VStack(spacing: 14) {
            Image(systemName: run.chapter.symbol)
                .font(.system(size: 44))
                .foregroundStyle(Theme.gold)
            Text("\(run.chapter.number) complete")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.cream)
            Text(run.chapter.id + 1 < Story.chapters.count
                 ? "Next: \(Story.chapters[run.chapter.id + 1].title)"
                 : "La determinazione d'oro has been heard.")
                .font(.subheadline)
                .foregroundStyle(Theme.creamDim)
                .multilineTextAlignment(.center)
            Button {
                game.completeChapter(run.chapter)
                game.storyRun = nil
            } label: { Label("Back to the street", systemImage: "map.fill") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(22)
        .panelSurface(cornerRadius: 26)
    }

    // MARK: Flow

    /// Runs when a new line or beat appears.
    private func enter() async {
        typing?.cancel()
        visible = 0
        if case let (_, text)? = currentLine {
            let total = text.count
            let task = Task { @MainActor in
                while visible < total {
                    try? await Task.sleep(for: .milliseconds(22))
                    if Task.isCancelled { return }
                    visible = min(total, visible + 2)
                }
            }
            typing = task
            return
        }
        if case .alarmCheck? = beat, run.alarm < 100 {
            advance()
        } else if case .scene? = beat {
            AudioManager.shared.play(.uiNotify, volume: 0.6)
        }
    }

    private func tapDialogue(_ text: String) {
        if visible < text.count {
            typing?.cancel()
            visible = text.count
            return
        }
        AudioManager.shared.play(.dialogueNext, volume: 0.6)
        if !run.pendingChoiceReply.isEmpty {
            run.pendingChoiceReply.removeFirst()
        } else {
            advance()
        }
    }

    private func advance() {
        run.index += 1
        game.saveStoryPosition(run)
    }

    private func pick(_ choice: StoryChoice) {
        AudioManager.shared.play(.uiTap)
        if case let (person, n)? = choice.affinity {
            game.progress.affinity[person, default: 0] += n
        }
        if run.chapter.usesAlarm { run.alarm = min(100, run.alarm + choice.alarm) }
        run.pendingChoiceReply = choice.reply
        advance()
    }

    private func startBattle() {
        guard case .battle(let enemy, let ally)? = beat else { return }
        run.battle = game.makeBattle(enemy, ally: ally)
    }

    private func allyFor(_ battle: BattleSession) -> Person? {
        if alarmFight { return nil }
        if case .battle(_, let ally)? = beat { return ally }
        return nil
    }

    private func battleFinished(_ battle: BattleSession, outcome: BattleSession.Outcome) {
        game.finishBattle(battle)
        run.battle = nil
        switch outcome {
        case .won:
            if alarmFight {
                alarmFight = false
                run.alarm = 60
            }
            advance()
        case .lost, .fled:
            alarmFight = false
            close()
        }
    }

    private func close() {
        typing?.cancel()
        game.saveStoryPosition(run)
        game.storyRun = nil
    }
}
