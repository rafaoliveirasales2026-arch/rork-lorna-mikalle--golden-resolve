import RealityKit
import SwiftUI

/// The aura demo: Lorna casts Golden Determination, the strike lands, the spirit's HP drops.
struct GoldenDeterminationView: View {
    let session: EncounterSession
    @Binding var path: [EncounterRoute]
    @Environment(GameState.self) private var game
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var stage: EncounterStage?
    @State private var hasCast = false
    @State private var showTitle = false
    @State private var showResult = false
    @State private var displayedHP: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                if let stage {
                    RealityView { content in
                        await stage.setup(in: &content, size: geo.size)
                    }
                    .onChange(of: geo.size) { _, size in stage.resize(size) }
                }
            }
            .ignoresSafeArea()
            .background(Theme.ink)

            RadialGradient(colors: [Theme.gold.opacity(showTitle ? 0.28 : 0), .clear],
                           center: .center, startRadius: 20, endRadius: 380)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            LinearGradient(colors: [.clear, Theme.ink.opacity(0.5), Theme.ink.opacity(0.9)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                titleCard
                resultCard
                Button {
                    finish()
                } label: {
                    Label(session.isCalmed ? "Continue · Spirit calmed" : "Continue", systemImage: "sparkles")
                }
                .buttonStyle(GoldButtonStyle())
                .opacity(showResult ? 1 : 0.4)
                .disabled(!showResult)
            }
            .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationTitle("Golden Determination")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: showResult)
        .audioContext(.golden)
        .onDisappear { AudioManager.shared.setAura(false) }
        .task {
            guard !hasCast else { return }
            hasCast = true
            displayedHP = session.hp
            stage = EncounterStage(source: game.stageProvider?(), kind: session.kind, mode: .aura)
            AudioManager.shared.play(.goldenActivate)
            AudioManager.shared.setAura(true)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) { showTitle = true }
            try? await Task.sleep(for: .milliseconds(1000))
            AudioManager.shared.play(.specialAttack)
            game.castGoldenDetermination()
            AudioManager.shared.play(.impact, volume: 0.9)
            if session.isCalmed { AudioManager.shared.play(.enemyDefeat) } else { AudioManager.shared.play(.spiritReaction, volume: 0.8) }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                displayedHP = session.hp
                showResult = true
            }
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LA DETERMINAZIONE D'ORO")
                .font(.system(size: sizeClass == .regular ? 40 : 30, weight: .black).italic())
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFF1B0), Theme.gold, Theme.goldDeep],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.gold.opacity(0.8), radius: 12)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 8) {
                Text("Golden Determination")
                    .font(.system(size: 20, weight: .heavy).italic())
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                DiamondRule()
                    .frame(width: 90)
            }
            .padding(.leading, 28)
        }
        .rotationEffect(.degrees(-4))
        .scaleEffect(showTitle ? 1 : 1.6)
        .opacity(showTitle ? 1 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var resultCard: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.title)
                    .foregroundStyle(Theme.goldLight)
                    .symbolEffect(.bounce, value: showResult)
                Text(showResult ? "−\(session.lastDamage)" : "…")
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 110, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                Text(session.isCalmed && showResult
                     ? "\(session.kind.name) calmed · +250 XP"
                     : "\(session.kind.name) HP \(displayedHP) / \(session.kind.maxHP)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText(value: Double(displayedHP)))
                HPBar(value: Double(displayedHP), maxValue: Double(session.kind.maxHP))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .hudGlass(in: Capsule())
    }

    private func finish() {
        if session.isCalmed {
            game.endEncounter()
        } else {
            path.removeAll()
        }
    }
}
