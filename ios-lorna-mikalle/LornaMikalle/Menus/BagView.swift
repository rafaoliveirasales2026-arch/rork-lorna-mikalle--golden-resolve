import SwiftUI

/// Items and power upgrades bought with Aura Shards.
struct BagView: View {
    @Environment(GameState.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var upgradeToken = 0

    var body: some View {
        let progress = game.progress
        NavigationStack {
            List {
                Section {
                    ForEach(Power.allCases) { power in
                        powerRow(power, level: progress.power(power), shards: progress.count(.auraShard))
                    }
                } header: {
                    HStack {
                        Text("Golden Determination")
                        Spacer()
                        Label("\(progress.count(.auraShard))", systemImage: Item.auraShard.symbol)
                            .foregroundStyle(Theme.gold)
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Aura Shards come from discovering real places, routes, missions and tough battles.")
                }

                Section("Items") {
                    ForEach(Item.allCases.filter { $0 != .auraShard }) { item in
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol)
                                .font(.title3)
                                .foregroundStyle(item.tint)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(item.tint.opacity(0.16)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.headline).foregroundStyle(Theme.cream)
                                Text(item.detail).font(.caption).foregroundStyle(Theme.creamDim)
                            }
                            Spacer()
                            Text("×\(progress.count(item))")
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(progress.count(item) > 0 ? Theme.cream : Theme.creamDim)
                        }
                        .listRowBackground(Theme.ink.opacity(0.6))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.duskBackdrop.ignoresSafeArea())
            .navigationTitle("Bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.gold)
        .sensoryFeedback(.success, trigger: upgradeToken)
    }

    private func powerRow(_ power: Power, level: Int, shards: Int) -> some View {
        let maxed = level >= Power.maxLevel
        let cost = Power.cost(toReach: level + 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: power.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(power.title).font(.headline).foregroundStyle(Theme.cream)
                    Text(power.effect(level: level)).font(.caption).foregroundStyle(Theme.creamDim)
                }
                Spacer(minLength: 4)
                if maxed {
                    Text("Max").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                } else {
                    Button {
                        game.upgrade(power)
                        upgradeToken += 1
                    } label: {
                        Label("\(cost)", systemImage: Item.auraShard.symbol)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .foregroundStyle(Theme.ink)
                    .disabled(shards < cost)
                    .accessibilityLabel("Upgrade \(power.title) for \(cost) Aura Shards")
                }
            }
            HStack(spacing: 5) {
                ForEach(1...Power.maxLevel, id: \.self) { i in
                    Capsule()
                        .fill(i <= level ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.white.opacity(0.15)))
                        .frame(height: 6)
                }
            }
            .padding(.leading, 48)
            if !maxed {
                Text("Next: \(power.effect(level: level + 1))")
                    .font(.caption)
                    .foregroundStyle(Theme.spirit)
                    .padding(.leading, 48)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.ink.opacity(0.6))
    }
}
