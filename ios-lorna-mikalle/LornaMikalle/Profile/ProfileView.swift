import RealityKit
import SwiftUI
import UIKit

/// Lorna's profile sheet: 3D turntable portrait plus real persisted progress.
struct ProfileView: View {
    @Environment(GameState.self) private var game
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let progress = game.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LornaTurntable()
                    .frame(height: sizeClass == .regular ? 460 : 380)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, Theme.ink], startPoint: .top, endPoint: .bottom)
                            .frame(height: 80)
                            .allowsHitTesting(false)
                    }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lorna Mikalle")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Theme.cream)
                        Text("Golden Determination User")
                            .font(.title3)
                            .foregroundStyle(Theme.gold)
                    }

                    VStack(spacing: 10) {
                        HStack {
                            Text("Level \(progress.level)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Theme.blue))
                            Spacer()
                            Text("\(progress.xp.formatted()) / \(PlayerProgress.xpPerLevel.formatted()) XP")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.cream)
                        }
                        HPBar(value: Double(progress.xp), maxValue: Double(PlayerProgress.xpPerLevel), tint: Theme.gold)
                            .accessibilityLabel("Experience")
                    }

                    VStack(spacing: 0) {
                        statRow("figure.walk", "Distance walked", progress.distanceText)
                        divider
                        statRow("person.2.fill", "Spirits met", "\(progress.spiritsMet)")
                        divider
                        statRow("sparkles", "Spirits calmed", "\(progress.spiritsCalmed)")
                        divider
                        statRow("sun.max", "Aura uses", "\(progress.auraUses)")
                        divider
                        statRow("bolt.fill", "Battles won", "\(progress.battlesWon)")
                        divider
                        statRow("crown.fill", "Bosses defeated", "\(progress.bossesDefeated)")
                        divider
                        statRow("mappin.and.ellipse", "Places discovered", "\(progress.places.count)")
                        divider
                        statRow("point.topleft.down.to.point.bottomright.curvepath.fill", "Routes completed", "\(progress.routesCompleted)")
                        divider
                        statRow("book.closed.fill", "Story", "\(min(progress.storyChapter, Story.chapters.count)) / \(Story.chapters.count)")
                    }
                    .padding(.vertical, 4)
                    .hudGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    AudioSettings()

                    Text("Walk your real streets to meet more spirits.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.creamDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.duskBackdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5).padding(.leading, 64)
    }

    private func statRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 32)
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.cream)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.cream)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Independent music, effects and ambience volumes (saved automatically).
private struct AudioSettings: View {
    @State private var audio = AudioManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sound")
                .font(.headline)
                .foregroundStyle(Theme.cream)
            slider("Music", symbol: "music.note", value: $audio.musicVolume)
            slider("Effects", symbol: "speaker.wave.2.fill", value: $audio.sfxVolume)
            slider("Ambience", symbol: "wind", value: $audio.ambienceVolume)
            Text("Music: “La determinazione d'oro”. The ring/silent switch mutes the game.")
                .font(.caption)
                .foregroundStyle(Theme.creamDim)
        }
        .padding(16)
        .hudGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func slider(_ title: String, symbol: String, value: Binding<Float>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.cream)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(Theme.gold)
                .accessibilityLabel("\(title) volume")
            Text("\(Int(value.wrappedValue * 100))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.creamDim)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// Slowly rotating idle Lorna on a warm golden-hour backdrop; drag to spin.
private struct LornaTurntable: View {
    @State private var model = TurntableModel()

    var body: some View {
        RealityView { content in
            await model.setup(in: &content)
        }
        .gesture(
            DragGesture()
                .onChanged { value in model.drag(Float(value.translation.width)) }
                .onEnded { _ in model.endDrag() }
        )
        .background(LinearGradient(colors: [Theme.plum, Theme.apricot], startPoint: .top, endPoint: .bottom))
        .accessibilityLabel("3D model of Lorna Mikalle")
    }
}

private final class TurntableModel {
    private let root = Entity()
    private let lorna = LornaCharacter()
    private let camera = PerspectiveCamera()
    private var yaw: Float = 0.35
    private var dragBase: Float?
    private var idleTime: Float = 0
    private var subscription: EventSubscription?

    func setup(in content: inout RealityViewCameraContent) async {
        // Backdrop dome with the sheet's golden-hour gradient.
        var builder = MeshBuilder()
        builder.addSphere(center: .zero, radius: SIMD3(repeating: 30), rings: 16, segments: 24)
        var backdrop = UnlitMaterial(color: UIColor(hex: 0xF2A541))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 128)).image { ctx in
            let colors = [UIColor(hex: 0x4A3348).cgColor, UIColor(hex: 0xC8724A).cgColor,
                          UIColor(hex: 0xF2A541).cgColor, UIColor(hex: 0x4A3348).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 0.52, 0.75]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 128), options: [])
            }
        }
        if let cg = image.cgImage, let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            backdrop.color = .init(tint: .white, texture: .init(tex))
        }
        backdrop.faceCulling = .none
        if let mesh = builder.makeMesh(name: "backdrop") {
            root.addChild(ModelEntity(mesh: mesh, materials: [backdrop]))
        }

        let key = DirectionalLight()
        key.light.color = UIColor(hex: 0xFFD9A0)
        key.light.intensity = 3200
        key.look(at: .zero, from: [1.5, 2.5, 2.5], relativeTo: nil)
        let rim = DirectionalLight()
        rim.light.color = UIColor(hex: 0x9FB4FF)
        rim.light.intensity = 1400
        rim.look(at: .zero, from: [-2, 1.5, -2], relativeTo: nil)
        root.addChild(key)
        root.addChild(rim)

        camera.camera.fieldOfViewInDegrees = 30
        camera.look(at: [0, 1.25, 0], from: [0, 1.35, 3.1], relativeTo: nil)
        root.addChild(camera)
        root.addChild(lorna.container)
        content.add(root)

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self else { return }
            if self.dragBase == nil {
                self.idleTime += Float(event.deltaTime)
                self.yaw += Float(event.deltaTime) * 0.25
            }
            self.lorna.face(yaw: self.yaw)
        }
        await lorna.build()
    }

    func drag(_ dx: Float) {
        let base = dragBase ?? yaw
        if dragBase == nil { dragBase = base }
        yaw = base + dx * 0.01
    }

    func endDrag() { dragBase = nil }
}
