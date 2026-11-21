import RealityKit
import SwiftUI
import UIKit
import simd

/// One beat of the prologue: what the caption says and how the 3D set is lit and framed.
struct IntroShot: Identifiable {
    enum Cast { case none, lorna, withGiulia, lornaGolden }

    let id: Int
    let eyebrow: String
    let line: String
    let duration: Double
    let preset: LightingPreset
    let cast: Cast
    /// Camera eye and look-at at the start and end of the shot (set space: alley runs along Z).
    let fromStart: SIMD3<Float>
    let fromEnd: SIMD3<Float>
    let atStart: SIMD3<Float>
    let atEnd: SIMD3<Float>
    var portrait: Person? = nil
    var fire = false
    var title = false

    /// Canon only: every line restates something the story already establishes.
    static let all: [IntroShot] = [
        IntroShot(id: 0, eyebrow: "Prologue", line: "Some songs wait a long time to be heard.",
                  duration: 5.0, preset: .night, cast: .none,
                  fromStart: [0, 9, 16], fromEnd: [0, 6, 9], atStart: [0, 4, -20], atEnd: [0, 3, -16]),
        IntroShot(id: 1, eyebrow: "1983", line: "The Corvo family burns a music shop. The owner's son, Aurelio Benassi, writes a piece to be brave.",
                  duration: 7.0, preset: .night, cast: .none,
                  fromStart: [-2.2, 1.6, 4], fromEnd: [-1.2, 2.0, -4], atStart: [1.5, 2.4, -24], atEnd: [1.8, 3.2, -26],
                  portrait: .benassi, fire: true),
        IntroShot(id: 2, eyebrow: "La determinazione d'oro", line: "He gives it a name. He never plays it for anyone.",
                  duration: 6.0, preset: .blueHour, cast: .none,
                  fromStart: [2.4, 1.2, -6], fromEnd: [2.0, 4.5, -10], atStart: [0, 2.5, -20], atEnd: [0, 8, -26]),
        IntroShot(id: 3, eyebrow: "Forty years later · Casa Mikalle", line: "Lorna Mikalle lives with her grandmother, Nonna Ottavia.",
                  duration: 6.5, preset: .sunset, cast: .lorna,
                  fromStart: [2.6, 1.4, 4.6], fromEnd: [1.6, 1.5, 3.4], atStart: [0, 1.1, 0], atEnd: [0, 1.2, 0],
                  portrait: .ottavia),
        IntroShot(id: 4, eyebrow: "A melody", line: "Long ago, her grandfather used to hum a song around the house.",
                  duration: 6.0, preset: .sunset, cast: .lorna,
                  fromStart: [-0.9, 1.65, 1.4], fromEnd: [-0.6, 1.6, 1.15], atStart: [0, 1.5, 0], atEnd: [0, 1.52, 0]),
        IntroShot(id: 5, eyebrow: "Liceo Galilei · Aula 3B", line: "Classmates. Ordinary days. Lorna has never seen a spirit.",
                  duration: 6.5, preset: .day, cast: .withGiulia,
                  fromStart: [0.9, 1.45, 3.8], fromEnd: [0.3, 1.4, 3.0], atStart: [0.05, 1.1, 0], atEnd: [0.05, 1.15, 0]),
        IntroShot(id: 6, eyebrow: "Lately", line: "Men with raven pins walk the streets. After dark, the city feels colder.",
                  duration: 6.5, preset: .blueHour, cast: .lorna,
                  fromStart: [0, 0.5, 5.5], fromEnd: [0, 0.6, 4.0], atStart: [0, 1.6, -12], atEnd: [0, 1.4, -10]),
        IntroShot(id: 7, eyebrow: "16 September 2023 · 14:10", line: "The last lesson of a hot Saturday. Professor Benassi decides to play one piece.",
                  duration: 8.0, preset: .day, cast: .lornaGolden,
                  fromStart: [0.4, 0.7, 3.4], fromEnd: [0.2, 1.0, 2.4], atStart: [0, 1.2, 0], atEnd: [0, 1.35, 0],
                  portrait: .benassi),
        IntroShot(id: 8, eyebrow: "", line: "", duration: 0, preset: .day, cast: .lornaGolden,
                  fromStart: [1.4, 0.4, 5.2], fromEnd: [1.0, 0.6, 4.4], atStart: [0, 1.6, -2], atEnd: [0, 1.6, -2],
                  title: true),
    ]
}

/// The prologue set: a small Italian vicolo with real façades, a sky rig, Lorna and her gold.
final class IntroStage {
    let root = Entity()
    private let camera = PerspectiveCamera()
    private let sky = SkyRig()
    private let lorna = LornaCharacter()
    private let aura = AuraEffect()
    private let dust = Entity()
    private let embers = Entity()
    private let fireLight = PointLight()
    private var surfaces: [WorldSurface: ModelEntity] = [:]
    private var windowLights: [PointLight] = []
    private var subscription: EventSubscription?
    private var preset: LightingPreset = .night
    private var shot: IntroShot = IntroShot.all[0]
    private var shotTime: Float = 0
    private var time: Float = 0
    private var aspect: Float = 0.46
    private let giulia = StoryCharacter(.giulia)

    init() {
        root.addChild(sky.root)
        sky.apply(.night, sunAzimuth: 250, sunElevation: nil)
        sky.follow(.zero)

        camera.camera.fieldOfViewInDegrees = 50
        camera.camera.near = 0.05
        camera.camera.far = 1500
        root.addChild(camera)

        buildSet()

        lorna.container.addChild(aura.root)
        root.addChild(lorna.container)
        lorna.face(yaw: 0)
        giulia.container.isEnabled = false
        root.addChild(giulia.container)

        configureDust()
        configureFire()
    }

    func setup(in content: inout RealityViewCameraContent, size: CGSize) async {
        aspect = Float(size.width / max(size.height, 1))
        content.add(root)
        apply(shot: IntroShot.all[0], animated: false)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.update(dt: Float(min(event.deltaTime, 0.1)))
        }
        await lorna.build()
        await giulia.build()
        applyCast()
    }

    func resize(_ size: CGSize) {
        aspect = Float(size.width / max(size.height, 1))
    }

    /// Cuts to a new shot: relights the set, places the cast, restarts the camera move.
    func apply(shot newShot: IntroShot, animated: Bool = true) {
        let previousCast = shot.cast
        shot = newShot
        shotTime = 0
        if newShot.preset != preset || !animated {
            preset = newShot.preset
            sky.apply(preset, sunAzimuth: 235, sunElevation: nil, animated: animated)
            for (surface, entity) in surfaces {
                entity.model?.materials = [WorldMaterials.shared.material(surface, preset: preset)]
            }
            let dark = preset.isDark || preset == .sunset
            for light in windowLights { light.light.intensity = dark ? 9000 : 0 }
        }
        embers.components[ParticleEmitterComponent.self]?.isEmitting = newShot.fire
        fireLight.isEnabled = newShot.fire
        if previousCast != newShot.cast || !animated { applyCast() }
        placeCamera()
    }

    private func applyCast() {
        giulia.container.isEnabled = shot.cast == .withGiulia
        switch shot.cast {
        case .none:
            lorna.container.isEnabled = false
            aura.setActive(false)
        case .lorna:
            lorna.container.isEnabled = true
            lorna.container.position = .zero
            lorna.face(yaw: 0)
            lorna.setPose(.idle)
            aura.setActive(false)
        case .withGiulia:
            // Two classmates chatting: they half-face each other and the camera.
            lorna.container.isEnabled = true
            lorna.container.position = [-0.45, 0, 0]
            lorna.face(yaw: 0.55)
            lorna.setPose(.idle)
            giulia.container.position = [0.55, 0, 0.1]
            giulia.face(yaw: -0.65)
            giulia.talk()
            aura.setActive(false)
        case .lornaGolden:
            lorna.container.isEnabled = true
            lorna.container.position = .zero
            lorna.face(yaw: 0)
            lorna.setPose(.idle)
            if !aura.isActive {
                aura.setActive(true)
                lorna.castSpell(restoreAfter: .milliseconds(2800))
            }
        }
        setDustFrozen(shot.cast == .lornaGolden)
    }

    // MARK: Frame loop

    private func update(dt: Float) {
        time += dt
        shotTime += dt
        sky.update(dt: dt)
        aura.update(deltaTime: dt)

        if shot.fire {
            // Firelight breathes and stutters.
            let flicker = 0.75 + 0.15 * sin(time * 13) + 0.1 * sin(time * 31 + 1.3)
            fireLight.light.intensity = 140_000 * flicker
        }
        placeCamera()
    }

    private func placeCamera() {
        let duration = Float(max(shot.duration, 4))
        let raw = min(shotTime / duration, 1)
        let t = raw * raw * (3 - 2 * raw)
        var from = simd_mix(shot.fromStart, shot.fromEnd, SIMD3(repeating: t))
        let at = simd_mix(shot.atStart, shot.atEnd, SIMD3(repeating: t))
        // Tall phones need more distance to keep the subject framed.
        let pull: Float = aspect < 0.7 ? 1.3 : 1.0
        from = at + (from - at) * pull
        camera.look(at: at, from: from, relativeTo: nil)
        sky.follow(SIMD3(from.x, 0, from.z))
    }

    // MARK: Set building

    /// A vicolo: plaza paving, two rows of façades, a church-like block closing the far end.
    private func buildSet() {
        var builders: [WorldSurface: MeshBuilder] = [:]
        func with(_ surface: WorldSurface, _ body: (inout MeshBuilder) -> Void) {
            var b = builders[surface] ?? MeshBuilder()
            body(&b)
            builders[surface] = b
        }

        // Paving
        with(.plaza) { $0.addQuad([-30, 0, 30], [30, 0, 30], [30, 0, -60], [-30, 0, -60], normal: [0, 1, 0]) }

        // Façades: left row faces +X, right row faces -X, far block faces +Z.
        let palette: [WorldSurface] = [.wallOchre, .wallRoseB, .wallCream, .wallTerracottaB, .wallSienna, .wallOchreB, .wallRose]
        var z: Float = 10
        var index = 0
        while z > -34 {
            let width: Float = [7.5, 6.0, 8.5, 6.8][index % 4]
            let leftH: Float = [13, 16, 11.5, 14.5][index % 4]
            let rightH: Float = [15, 12, 17, 13][(index + 1) % 4]
            addFacade(&builders, a: [-3.6, z], b: [-3.6, z - width], height: leftH, surface: palette[index % palette.count])
            addFacade(&builders, a: [3.6, z - width], b: [3.6, z], height: rightH, surface: palette[(index + 3) % palette.count])
            z -= width
            index += 1
        }
        addFacade(&builders, a: [-7, z], b: [7, z], height: 22, surface: .wallCreamB)

        // Lamp posts along the alley
        let lamps: [SIMD2<Float>] = [[3.2, 4], [-3.2, -6], [3.2, -16], [-3.2, -27]]
        for lamp in lamps {
            do {
                let side = lamp.x, lampZ = lamp.y
                with(.lampPole) { $0.addPrism(base: [side, 0, lampZ], radius: 0.07, height: 3.8, sides: 6, topRadius: 0.05) }
                with(.lampHead) { $0.addSphere(center: [side, 3.95, lampZ], radius: [0.2, 0.25, 0.2]) }
                let light = PointLight()
                light.light.color = UIColor(hex: 0xFFC978)
                light.light.attenuationRadius = 9
                light.position = [side, 3.6, lampZ]
                root.addChild(light)
                windowLights.append(light)
            }
        }

        for (surface, builder) in builders {
            guard let mesh = builder.makeMesh(name: "intro-\(surface.rawValue)") else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [WorldMaterials.shared.material(surface, preset: preset)])
            surfaces[surface] = entity
            root.addChild(entity)
        }
    }

    /// One façade wall (with rusticated plinth and cornice) along a→b in plan (x, z), facing left of a→b.
    private func addFacade(_ builders: inout [WorldSurface: MeshBuilder], a: SIMD2<Float>, b: SIMD2<Float>, height h: Float, surface: WorldSurface) {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.1 else { return }
        let dir = d / len
        // Outward normal in plan (x, z): rotate a→b by +90° so it points into the alley.
        let n2 = SIMD2<Float>(dir.y, -dir.x) * -1
        let normal = SIMD3<Float>(n2.x, 0, n2.y)
        let plinth: Float = min(3.6, h * 0.3)
        let u1 = len / 7.2
        func p(_ q: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(q.x, y, q.y) }

        var wall = builders[surface] ?? MeshBuilder()
        wall.addQuad(p(a, plinth), p(b, plinth), p(b, h), p(a, h), normal: normal,
                     uv: [SIMD2(0, 0), SIMD2(u1, 0), SIMD2(u1, (h - plinth) / 6.4), SIMD2(0, (h - plinth) / 6.4)])
        builders[surface] = wall

        let o = n2 * 0.06
        var base = builders[.plinth] ?? MeshBuilder()
        base.addQuad(p(a + o, 0), p(b + o, 0), p(b + o, plinth), p(a + o, plinth), normal: normal,
                     uv: [SIMD2(0, 0), SIMD2(u1, 0), SIMD2(u1, plinth / 3.6), SIMD2(0, plinth / 3.6)])
        builders[.plinth] = base

        let c = n2 * 0.32
        var cornice = builders[.cornice] ?? MeshBuilder()
        cornice.addQuad(p(a + c, h - 0.5), p(b + c, h - 0.5), p(b + c, h + 0.05), p(a + c, h + 0.05), normal: normal)
        cornice.addQuad(p(a, h + 0.05), p(a + c, h + 0.05), p(b + c, h + 0.05), p(b, h + 0.05), normal: [0, 1, 0])
        builders[.cornice] = cornice

        let s = n2 * 1.4
        var shadow = builders[.contactShadow] ?? MeshBuilder()
        shadow.addQuad(p(a, 0.02), p(a + s, 0.02), p(b + s, 0.02), p(b, 0.02), normal: [0, 1, 0],
                       uv: [SIMD2(0.01, 0), SIMD2(0.99, 0), SIMD2(0.99, 1), SIMD2(0.01, 1)])
        builders[.contactShadow] = shadow
    }

    // MARK: Particles

    /// Sunlit dust around Lorna. On 16 September at 14:10 it stops mid-air.
    private func configureDust() {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = [3.2, 2.4, 3.2]
        emitter.birthLocation = .volume
        emitter.speed = 0.03
        emitter.mainEmitter.birthRate = 70
        emitter.mainEmitter.lifeSpan = 6
        emitter.mainEmitter.size = 0.012
        emitter.mainEmitter.acceleration = [0, -0.015, 0]
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.opacityCurve = .quickFadeInOut
        emitter.mainEmitter.color = .constant(.single(UIColor(hex: 0xFFF4E0, alpha: 0.85)))
        dust.components.set(emitter)
        dust.position = [0, 1.3, 0.6]
        root.addChild(dust)
    }

    private func setDustFrozen(_ frozen: Bool) {
        guard var emitter = dust.components[ParticleEmitterComponent.self] else { return }
        emitter.simulationState = frozen ? .pause : .play
        dust.components.set(emitter)
    }

    /// 1983: firelight and embers at the far end of the street.
    private func configureFire() {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = [5, 0.5, 1.5]
        emitter.birthLocation = .volume
        emitter.birthDirection = .world
        emitter.emissionDirection = [0, 1, 0]
        emitter.speed = 1.6
        emitter.mainEmitter.birthRate = 160
        emitter.mainEmitter.lifeSpan = 3
        emitter.mainEmitter.size = 0.05
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        emitter.mainEmitter.spreadingAngle = 0.5
        emitter.mainEmitter.acceleration = [0.3, 0.6, 0]
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.opacityCurve = .linearFadeOut
        emitter.mainEmitter.color = .evolving(start: .single(UIColor(hex: 0xFFC14D)),
                                              end: .single(UIColor(hex: 0xD2421E, alpha: 0.3)))
        emitter.isEmitting = false
        embers.components.set(emitter)
        embers.position = [1.5, 0.5, -24]
        root.addChild(embers)

        fireLight.light.color = UIColor(hex: 0xFF8A3D)
        fireLight.light.attenuationRadius = 22
        fireLight.position = [1.5, 2.5, -22]
        fireLight.isEnabled = false
        root.addChild(fireLight)
    }
}
