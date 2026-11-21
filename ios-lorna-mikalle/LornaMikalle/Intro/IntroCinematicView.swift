import RealityKit
import SwiftUI

/// The prologue: Lorna's world up to 16 September 2023, 14:10. Tap to advance, Skip any time.
struct IntroCinematicView: View {
    @Environment(GameState.self) private var game
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: IntroStage?
    @State private var index = 0
    @State private var dip = false
    @State private var captionVisible = false
    @State private var titleVisible = false

    private let shots = IntroShot.all
    private var shot: IntroShot { shots[index] }
    private var storyShots: Int { shots.count - 1 }
    private var isReplay: Bool { game.introIsReplay }

    var body: some View {
        ZStack {
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

            atmosphere

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if shot.title {
                    titleCard
                } else {
                    caption
                }
            }
            .frame(maxWidth: sizeClass == .regular ? 680 : .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Color.black
                .opacity(dip ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !shot.title { advance() } }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.selection, trigger: index)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: titleVisible)
        .audioContext(.story)
        .onAppear {
            if stage == nil { stage = IntroStage() }
            reveal()
        }
        .task(id: index) {
            guard !shot.title else { return }
            try? await Task.sleep(for: .seconds(shot.duration))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    // MARK: Layers

    private var atmosphere: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.65), Theme.ink.opacity(0.92)],
                           startPoint: .center, endPoint: .bottom)
            if shot.cast == .lornaGolden {
                RadialGradient(colors: [Theme.gold.opacity(0.3), .clear], center: .center, startRadius: 10, endRadius: 360)
                    .transition(.opacity)
            }
            if shot.fire {
                RadialGradient(colors: [Color(hex: 0xD2421E).opacity(0.28), .clear], center: .top, startRadius: 40, endRadius: 520)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.8), value: index)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(0..<storyShots, id: \.self) { i in
                    SegmentBar(state: i < index ? .done : (i == index ? .active(shot.duration) : .pending))
                        .id(i == index ? "active-\(index)" : "seg-\(i)")
                }
            }
            .accessibilityHidden(true)
            if !shot.title {
                Button {
                    AudioManager.shared.play(.uiTap)
                    go(to: storyShots)
                } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .hudGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Jumps to the end of the prologue")
            }
        }
        .padding(.top, 8)
        .opacity(shot.title ? 0 : 1)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let person = shot.portrait {
                HStack(spacing: 12) {
                    PortraitImage(person: person, size: 64)
                        .shadow(color: person.tint.opacity(0.6), radius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.cream)
                        Text(person.role)
                            .font(.caption)
                            .foregroundStyle(Theme.creamDim)
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Text(shot.eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(shot.fire ? Theme.apricot : Theme.goldLight)
            Text(shot.line)
                .font(.system(size: sizeClass == .regular ? 30 : 24, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                Text("Tap to continue")
            }
            .font(.caption)
            .foregroundStyle(Theme.creamDim.opacity(0.8))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(captionVisible ? 1 : 0)
        .offset(y: captionVisible ? 0 : 18)
        .blur(radius: captionVisible ? 0 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var titleCard: some View {
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lorna Mikalle")
                    .font(.system(size: sizeClass == .regular ? 26 : 20, weight: .heavy).italic())
                    .foregroundStyle(Theme.cream)
                Text("LA DETERMINAZIONE D'ORO")
                    .font(.system(size: sizeClass == .regular ? 44 : 31, weight: .black).italic())
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFF1B0), Theme.gold, Theme.goldDeep],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.gold.opacity(0.8), radius: 14)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 10) {
                    Text("16 settembre 2023 · 14:10")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.goldLight)
                    DiamondRule().frame(width: 80)
                }
                .padding(.leading, 24)
            }
            .rotationEffect(.degrees(-4))
            .scaleEffect(titleVisible ? 1 : 1.5)
            .opacity(titleVisible ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                if isReplay || game.progress.storyChapter > 0 {
                    Button {
                        game.finishIntro(beginStory: false)
                    } label: {
                        Label("Back to the street", systemImage: "figure.walk")
                    }
                    .buttonStyle(GoldButtonStyle())
                } else {
                    Button {
                        game.finishIntro(beginStory: true)
                    } label: {
                        Label("Begin Chapter 1", systemImage: "music.note")
                    }
                    .buttonStyle(GoldButtonStyle())
                    Button("Explore first") {
                        game.finishIntro(beginStory: false)
                    }
                    .buttonStyle(BlueOutlineButtonStyle())
                }
                Button {
                    AudioManager.shared.play(.uiTap)
                    go(to: 0)
                } label: {
                    Label("Watch again", systemImage: "arrow.counterclockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.creamDim)
                }
                .padding(.top, 2)
            }
            .opacity(titleVisible ? 1 : 0)
            .offset(y: titleVisible ? 0 : 24)
        }
    }

    // MARK: Flow

    private func advance() {
        guard index < shots.count - 1 else { return }
        AudioManager.shared.play(.dialogueNext, volume: 0.6)
        go(to: index + 1)
    }

    private func go(to target: Int) {
        guard target != index else { return }
        let cut = reduceMotion ? 0.15 : 0.32
        withAnimation(.easeIn(duration: cut)) {
            dip = true
            captionVisible = false
            titleVisible = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(cut))
            index = target
            stage?.apply(shot: shots[target])
            withAnimation(.easeOut(duration: cut * 1.6)) { dip = false }
            reveal()
        }
    }

    private func reveal() {
        let current = shots[index]
        if current.cast == .lornaGolden && !current.title {
            AudioManager.shared.play(.goldenActivate, volume: 0.8)
        }
        if current.title {
            AudioManager.shared.play(.questComplete, volume: 0.7)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.25)) { titleVisible = true }
        } else {
            withAnimation(.easeOut(duration: 0.7).delay(0.35)) { captionVisible = true }
        }
    }
}

/// One story-style progress segment that fills over the shot's duration.
private struct SegmentBar: View {
    enum Phase: Equatable { case pending, active(Double), done }
    let state: Phase
    @State private var fill: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Theme.goldLight)
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(height: 3)
        .onAppear(perform: start)
        .onChange(of: state) { _, _ in start() }
    }

    private func start() {
        switch state {
        case .pending: fill = 0
        case .done: fill = 1
        case .active(let duration):
            fill = 0
            withAnimation(.linear(duration: duration)) { fill = 1 }
        }
    }
}
