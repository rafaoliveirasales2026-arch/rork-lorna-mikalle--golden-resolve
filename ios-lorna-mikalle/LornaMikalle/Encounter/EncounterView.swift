import RealityKit
import SwiftUI

enum EncounterRoute: Hashable { case golden, battle }

/// Full-screen encounter flow: Encounter → (push) Golden Determination or Battle.
struct EncounterFlowView: View {
    let session: EncounterSession
    @State private var path: [EncounterRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            EncounterView(session: session, path: $path)
                .navigationDestination(for: EncounterRoute.self) { route in
                    switch route {
                    case .golden: GoldenDeterminationView(session: session, path: $path)
                    case .battle: SpiritBattleScreen(session: session, path: $path)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.cream)
        .audioContext(.encounter)
    }
}

/// A full turn-based battle against the encountered spirit, over its live 3D stage.
struct SpiritBattleScreen: View {
    let session: EncounterSession
    @Binding var path: [EncounterRoute]
    @Environment(GameState.self) private var game
    @State private var battle: BattleSession?
    @State private var stage: EncounterStage?

    var body: some View {
        ZStack {
            if let battle {
                BattleView(battle: battle, stage: stage) { outcome in
                    switch outcome {
                    case .won:
                        game.finishBattle(battle, encounter: session)
                        game.endEncounter()
                    case .lost, .fled:
                        game.finishBattle(battle)
                        path.removeAll()
                    }
                } retry: {
                    game.finishBattle(battle)
                    self.battle = game.makeBattle(game.streetSpirit(session.kind))
                }
            } else {
                Theme.ink.ignoresSafeArea()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard battle == nil else { return }
            stage = EncounterStage(source: game.stageProvider?(), kind: session.kind, mode: .encounter)
            battle = game.makeBattle(game.streetSpirit(session.kind))
        }
    }
}

struct EncounterView: View {
    let session: EncounterSession
    @Binding var path: [EncounterRoute]
    @Environment(GameState.self) private var game
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var stage: EncounterStage?

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

            LinearGradient(colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 460)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            controls
                .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .navigationTitle(session.kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    game.endEncounter()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Close")
            }
        }
        .task {
            if stage == nil {
                stage = EncounterStage(source: game.stageProvider?(), kind: session.kind, mode: .encounter)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            SpiritNamePlate(session: session)
            DialogueBox(name: session.kind.name, text: session.dialogue)
                .animation(.easeInOut(duration: 0.25), value: session.dialogueIndex)

            Button {
                path.append(.golden)
            } label: {
                Label("Golden Determination", systemImage: "sparkles")
            }
            .buttonStyle(GoldButtonStyle())
            .sensoryFeedback(.impact(weight: .heavy), trigger: path.count)

            HStack(spacing: 14) {
                Button {
                    path.append(.battle)
                } label: {
                    Label("Battle", systemImage: "bolt.fill")
                }
                .buttonStyle(BlueOutlineButtonStyle())

                Button {
                    game.talk()
                } label: {
                    Label("Talk", systemImage: "bubble.left")
                }
                .buttonStyle(BlueOutlineButtonStyle())
                .sensoryFeedback(.selection, trigger: session.dialogueIndex)

                Button {
                    AudioManager.shared.play(.uiTap)
                    game.endEncounter()
                } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(BlueOutlineButtonStyle())
            }
        }
    }
}

struct SpiritNamePlate: View {
    let session: EncounterSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.blueBright)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.kind.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                    Text("\(session.kind.category) · Threat \(session.kind.threatStars)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.creamDim)
                }
                Spacer()
                Text("HP \(session.hp) / \(session.kind.maxHP)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText(value: Double(session.hp)))
            }
            HPBar(value: Double(session.hp), maxValue: Double(session.kind.maxHP))
        }
        .padding(16)
        .hudGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct DialogueBox: View {
    let name: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Label(name, systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .labelStyle(TintedIconLabelStyle(tint: Theme.blueBright))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.plum.opacity(0.95)))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.8), lineWidth: 1))
                DiamondRule()
            }
            .zIndex(1)

            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.cream)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .id(text)
                .transition(.opacity)
                .panelSurface(cornerRadius: 18)
                .padding(.top, -12)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TintedIconLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
