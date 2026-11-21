import RealityKit
import StoreKit
import SwiftUI

/// App Clip flow: meet Lorna → short piazza walk → find the spirit → get the full game.
struct ClipRootView: View {
    enum Phase { case intro, walking, found }

    @Environment(ClipInvocation.self) private var invocation
    @State private var scene = PiazzaDemoScene()
    @State private var phase: Phase = .intro
    @State private var showStore = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            RealityView { content in
                await scene.setup(in: &content)
            }
            .ignoresSafeArea()
            .accessibilityLabel("Lorna Mikalle in a sunlit Italian piazza")

            LinearGradient(colors: [Theme.ink.opacity(0.75), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                header
                Spacer()
                switch phase {
                case .intro: introCard.transition(.move(edge: .bottom).combined(with: .opacity))
                case .walking: walkingControls.transition(.opacity)
                case .found: foundCard.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: phase)
        .onChange(of: scene.foundSpirit) { _, found in
            if found { phase = .found; scene.exploring = false; scene.input = .zero }
        }
        .sensoryFeedback(.success, trigger: phase == .found)
        .appStoreOverlay(isPresented: $showStore) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                GameWordmark(compact: true)
                if let place = invocation.placeName {
                    Label("Welcome to \(place)", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .hudGlass(in: Capsule())
                }
            }
            Spacer()
            if phase == .walking {
                Button { openFullGame() } label: {
                    Label("Full game", systemImage: "arrow.down.app.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .hudGlass(in: Capsule(), interactive: true)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Intro

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image("LornaPortrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meet Lorna Mikalle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                    Text("Golden Determination User")
                        .font(.subheadline)
                        .foregroundStyle(Theme.gold)
                }
            }
            DiamondRule().frame(width: 120)
            Text("In the full game, your real walks move Lorna through a 3D version of your own streets, where spirits wait to be calmed. Try a short stroll around the piazza and find the hidden spirit.")
                .font(.body)
                .foregroundStyle(Theme.creamDim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                scene.exploring = true
                phase = .walking
            } label: {
                Label("Take a short walk", systemImage: "sparkles")
            }
            .buttonStyle(GoldButtonStyle())
            Button { openFullGame() } label: {
                Label("Get the full game", systemImage: "arrow.down.app")
            }
            .buttonStyle(BlueOutlineButtonStyle())
        }
        .padding(20)
        .panelSurface(cornerRadius: 24)
    }

    // MARK: - Walking

    private var walkingControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Theme.spirit)
                Text("\(invocation.spiritName) · \(Int(scene.spiritDistance.rounded())) m")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText(value: scene.spiritDistance))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .hudGlass(in: Capsule())

            HStack(alignment: .bottom) {
                Joystick { scene.input = $0 }
                Spacer()
                Text("Drag to walk\naround the piazza.")
                    .font(.footnote)
                    .foregroundStyle(Theme.creamDim)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Found

    private var foundCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.spirit)
                Text("You found the \(invocation.spiritName)!")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.cream)
            }
            DiamondRule().frame(width: 120)
            Text("Calm spirits with the Golden Determination, battle bosses, make friends and follow Lorna's story, all by walking your real streets.")
                .font(.body)
                .foregroundStyle(Theme.creamDim)
                .fixedSize(horizontal: false, vertical: true)
            Button { openFullGame() } label: {
                Label("Get the full game", systemImage: "sparkles")
            }
            .buttonStyle(GoldButtonStyle())
            Button {
                scene.restart()
                scene.exploring = true
                phase = .walking
            } label: {
                Text("Walk again")
            }
            .buttonStyle(BlueOutlineButtonStyle())
        }
        .padding(20)
        .panelSurface(cornerRadius: 24)
    }

    private func openFullGame() {
        showStore = true
    }
}

/// Glass thumbstick: reports a vector with length 0…1 (y up).
private struct Joystick: View {
    let onChange: (SIMD2<Float>) -> Void
    @State private var offset: CGSize = .zero
    private let radius: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: radius * 2, height: radius * 2)
                .hudGlass(in: Circle())
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1))
            Circle()
                .fill(Theme.goldGradient)
                .frame(width: 46, height: 46)
                .shadow(color: Theme.gold.opacity(0.5), radius: 8)
                .offset(offset)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var v = value.translation
                    let len = sqrt(v.width * v.width + v.height * v.height)
                    if len > radius { v = CGSize(width: v.width / len * radius, height: v.height / len * radius) }
                    offset = v
                    onChange(SIMD2(Float(v.width / radius), Float(-v.height / radius)))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { offset = .zero }
                    onChange(.zero)
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: offset == .zero)
        .accessibilityLabel("Movement stick")
    }
}
