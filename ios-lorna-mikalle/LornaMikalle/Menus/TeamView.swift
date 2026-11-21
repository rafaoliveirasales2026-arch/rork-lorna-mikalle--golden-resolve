import SwiftUI

/// Companions: story friends and befriended spirits. One fights at Lorna's side.
struct TeamView: View {
    @Environment(GameState.self) private var game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let progress = game.progress
        NavigationStack {
            List {
                Section {
                    ForEach(Person.companions) { person in
                        personRow(person, unlocked: progress.isUnlocked(person))
                    }
                } header: {
                    Text("Friends")
                } footer: {
                    Text("Friends join through the story. Winning battles together raises affinity and strengthens their skill.")
                }

                Section {
                    ForEach(SpiritKind.allCases, id: \.self) { kind in
                        spiritRow(kind, bonds: progress.spiritBonds[kind] ?? 0)
                    }
                } header: {
                    Text("Spirit friends")
                } footer: {
                    Text("Calm the same kind of spirit 3 times and it will fight beside Lorna.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.duskBackdrop.ignoresSafeArea())
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.gold)
        .sensoryFeedback(.selection, trigger: game.progress.activeCompanion)
    }

    private func personRow(_ person: Person, unlocked: Bool) -> some View {
        let companion = Companion.person(person)
        let active = game.progress.activeCompanion == companion
        let affinity = game.progress.affinity[person] ?? 0
        let level = game.progress.affinityLevel(person)
        return HStack(spacing: 14) {
            PortraitImage(person: person, size: 54)
                .saturation(unlocked ? 1 : 0)
                .opacity(unlocked ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 4) {
                Text(unlocked ? person.name : "???")
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text(unlocked ? (person.skill.map { "\($0.name): \($0.detail)" } ?? person.role) : unlockHint(person))
                    .font(.caption)
                    .foregroundStyle(Theme.creamDim)
                if unlocked {
                    HStack(spacing: 8) {
                        Text("Affinity \(level)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(person.tint)
                        HPBar(value: Double(level >= 5 ? 100 : affinity % 100), maxValue: 100, tint: person.tint)
                    }
                }
            }
            Spacer(minLength: 4)
            if unlocked { activeButton(companion, active: active) }
        }
        .padding(.vertical, 4)
        .listRowBackground(active ? person.tint.opacity(0.14) : Theme.ink.opacity(0.6))
    }

    private func spiritRow(_ kind: SpiritKind, bonds: Int) -> some View {
        let companion = Companion.spirit(kind)
        let unlocked = bonds >= 3
        let active = game.progress.activeCompanion == companion
        return HStack(spacing: 14) {
            Image(systemName: unlocked ? "sparkles" : "questionmark")
                .font(.title3)
                .foregroundStyle(unlocked ? kind.glowColor : Theme.creamDim)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(kind.glowColor.opacity(unlocked ? 0.18 : 0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(bonds > 0 ? kind.name : "Unknown spirit")
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                Text(unlocked ? "\(kind.allySkill.name): \(kind.allySkill.detail)" : "Calmed \(min(bonds, 3)) / 3")
                    .font(.caption)
                    .foregroundStyle(Theme.creamDim)
            }
            Spacer(minLength: 4)
            if unlocked { activeButton(companion, active: active) }
        }
        .padding(.vertical, 4)
        .listRowBackground(active ? kind.glowColor.opacity(0.14) : Theme.ink.opacity(0.6))
    }

    private func activeButton(_ companion: Companion, active: Bool) -> some View {
        Button {
            AudioManager.shared.play(.uiTap)
            game.progress.activeCompanion = active ? nil : companion
        } label: {
            Text(active ? "In team" : "Choose")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? Theme.ink : Theme.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(active ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.plum)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(active ? "Remove \(companion.name) from team" : "Choose \(companion.name)")
    }

    private func unlockHint(_ person: Person) -> String {
        switch person {
        case .ottavia: "Joins in Chapter 1"
        case .giulia: "Joins in Chapter 2"
        case .teo: "Joins in Chapter 3"
        default: "Joins in Chapter 5"
        }
    }
}
