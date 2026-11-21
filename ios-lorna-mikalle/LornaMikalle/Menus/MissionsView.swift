import SwiftUI

/// Daily and weekly missions, live events and achievements.
struct MissionsView: View {
    @Environment(GameState.self) private var game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let progress = game.progress
        let daily = Mission.daily(for: Calendar.dayKey(.now))
        let weekly = Mission.weekly(for: Calendar.weekKey(.now))
        NavigationStack {
            List {
                if !game.events.isEmpty {
                    Section("Live events") {
                        ForEach(game.events) { event in
                            HStack(spacing: 14) {
                                Image(systemName: event.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Theme.apricot)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.headline).foregroundStyle(Theme.cream)
                                    Text(event.detail).font(.subheadline).foregroundStyle(Theme.creamDim)
                                }
                            }
                            .listRowBackground(Theme.apricot.opacity(0.12))
                        }
                    }
                }

                Section {
                    ForEach(daily) { missionRow($0, counters: progress.daily) }
                } header: {
                    Text("Today")
                } footer: {
                    Text("New missions every day. Walking and place missions need real steps outside.")
                }

                Section("This week") {
                    ForEach(weekly) { missionRow($0, counters: progress.weekly) }
                }

                Section("Achievements") {
                    ForEach(Achievement.all) { achievementRow($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.duskBackdrop.ignoresSafeArea())
            .navigationTitle("Missions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear { game.progress.rollPeriods() }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.gold)
    }

    private func missionRow(_ mission: Mission, counters: PeriodCounters) -> some View {
        let done = mission.isDone(counters)
        let claimed = counters.claimed.contains(mission.id)
        return ProgressRow(
            symbol: mission.metric.symbol,
            title: mission.title,
            subtitle: mission.reward.summary,
            value: mission.progress(counters),
            target: mission.target,
            valueText: mission.progressText(counters),
            state: claimed ? .claimed : (done ? .ready : .running),
            badge: mission.metric.needsWalking ? "figure.walk" : nil
        ) { game.claim(mission) }
    }

    private func achievementRow(_ a: Achievement) -> some View {
        let value = a.value(game.progress)
        let claimed = game.progress.achievementsClaimed.contains(a.id)
        let text = a.target >= 1000
            ? String(format: "%.1f / %.0f km", min(value, a.target) / 1000, a.target / 1000)
            : "\(Int(min(value, a.target))) / \(Int(a.target))"
        return ProgressRow(
            symbol: a.symbol, title: a.title, subtitle: "\(a.detail) · \(a.reward.summary)",
            value: min(value, a.target), target: a.target, valueText: text,
            state: claimed ? .claimed : (value >= a.target ? .ready : .running), badge: nil
        ) { game.claim(a) }
    }
}

struct ProgressRow: View {
    enum RowState { case running, ready, claimed }
    let symbol: String
    let title: String
    let subtitle: String
    let value: Double
    let target: Double
    let valueText: String
    let state: RowState
    let badge: String?
    let claim: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state == .claimed ? "checkmark.seal.fill" : symbol)
                .font(.title3)
                .foregroundStyle(state == .claimed ? Theme.success : Theme.gold)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(Theme.cream)
                    if let badge {
                        Image(systemName: badge)
                            .font(.caption)
                            .foregroundStyle(Theme.spirit)
                            .accessibilityLabel("Needs walking")
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(Theme.creamDim)
                HStack(spacing: 8) {
                    HPBar(value: value, maxValue: target, tint: state == .running ? Theme.blueBright : Theme.gold)
                    Text(valueText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.creamDim)
                        .fixedSize()
                }
            }
            if state == .ready {
                Button("Claim", action: claim)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.ink.opacity(0.6))
        .sensoryFeedback(.success, trigger: state == .claimed)
    }
}
