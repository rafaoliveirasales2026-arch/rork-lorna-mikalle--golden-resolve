import RealityKit
import SwiftUI
import UIKit
import simd

/// A small cinematic set built from a clone of the live street: Lorna facing a spirit.
final class EncounterStage {
    enum Mode { case encounter, aura }

    let root = Entity()
    private let camera = PerspectiveCamera()
    private let sky = SkyRig()
    private let lorna = LornaCharacter()
    private let spirit: SpiritEntity
    private let aura = AuraEffect()
    private let mode: Mode
    private let origin: SIMD3<Float>
    private let rotation: simd_quatf
    private let forwardYaw: Float
    private var subscription: EventSubscription?
    private var time: Float = 0
    private var aspect: Float = 0.46
    private var hitTime: Float?

    init(source: EncounterStageSource?, kind: SpiritKind, mode: Mode) {
        self.mode = mode
        origin = source?.origin ?? .zero
        forwardYaw = source?.forwardYaw ?? 0
        rotation = simd_quatf(angle: forwardYaw, axis: [0, 1, 0])
        spirit = SpiritEntity(kind: kind, home: GeoProjection.planar(world: origin))
        spirit.wanders = false

        let preset = source?.preset ?? .sunset
        root.addChild(sky.root)
        sky.apply(preset, weather: source?.weather ?? .clear, sunAzimuth: source?.sunAzimuth ?? 250, sunElevation: source?.sunElevation)
        sky.follow(origin)

        if let world = source?.world {
            root.addChild(world)
        } else {
            let ground = ModelEntity(mesh: .generatePlane(width: 400, depth: 400),
                                     materials: [WorldMaterials.shared.material(.road, preset: preset)])
            root.addChild(ground)
        }

        camera.camera.fieldOfViewInDegrees = 55
        camera.camera.near = 0.05
        camera.camera.far = 1500
        root.addChild(camera)
        root.addChild(lorna.container)
        root.addChild(spirit.root)
        lorna.container.addChild(aura.root)
    }

    private func world(_ local: SIMD3<Float>) -> SIMD3<Float> { origin + rotation.act(local) }

    func setup(in content: inout RealityViewCameraContent, size: CGSize) async {
        aspect = Float(size.width / max(size.height, 1))
        content.add(root)

        switch mode {
        case .encounter:
            lorna.container.position = world([-0.75, 0, 0])
            lorna.face(yaw: forwardYaw + .pi / 2 + 0.5)
            spirit.place(at: GeoProjection.planar(world: world([0.85, 0, 1.0])))
            spirit.face(lorna.container.position + rotation.act([0, 0, -1.5]))
        case .aura:
            lorna.container.position = world([-0.25, 0, 0])
            lorna.face(yaw: forwardYaw + .pi * 0.85)
            spirit.place(at: GeoProjection.planar(world: world([1.5, 0, 3.4])))
            spirit.face(lorna.container.position)
            aura.setActive(true)
        }
        placeCamera()

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.update(dt: Float(min(event.deltaTime, 0.1)))
        }

        await lorna.build()
        if mode == .aura {
            lorna.castSpell(restoreAfter: .milliseconds(2800))
            hitTime = 0.9
        }
    }

    /// The spirit recoils (battle hit).
    func recoil() { hitTime = time }

    /// Lorna casts her golden light (battle burst / heal).
    func cast() {
        lorna.castSpell(restoreAfter: .milliseconds(1800))
        aura.setActive(true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            if self?.mode == .encounter { self?.aura.setActive(false) }
        }
    }

    func resize(_ size: CGSize) {
        aspect = Float(size.width / max(size.height, 1))
        placeCamera()
    }

    private func placeCamera() {
        switch mode {
        case .encounter:
            // Fit both characters horizontally whatever the aspect ratio.
            let halfWidthNeeded: Float = 1.35
            let tanHalf = tan(Float(27.5) * .pi / 180)
            let distance = min(max(halfWidthNeeded / (tanHalf * aspect), 3.6), 9)
            camera.look(at: world([0.05, 0.25 + distance * 0.02, 0.4]),
                        from: world([-0.25, 1.35, -distance]), relativeTo: nil)
        case .aura:
            let distance: Float = aspect < 0.7 ? 3.6 : 3.0
            camera.look(at: world([0.25, 0.75, 0.6]),
                        from: world([0.4, 0.55, -distance]), relativeTo: nil)
        }
    }

    private func update(dt: Float) {
        time += dt
        sky.update(dt: dt)
        spirit.update(deltaTime: dt)
        aura.update(deltaTime: dt)

        // Spirit recoils when the golden strike lands.
        if let hit = hitTime, time > hit {
            let t = time - hit
            let push = max(0, 1 - t / 0.8)
            spirit.root.scale = SIMD3(repeating: 1 + 0.08 * push * sin(t * 30))
            if t > 1.2 { hitTime = nil; spirit.root.scale = .one }
        }
    }
}
