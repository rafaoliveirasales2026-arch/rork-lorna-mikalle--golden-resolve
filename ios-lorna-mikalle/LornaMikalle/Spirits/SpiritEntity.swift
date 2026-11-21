import RealityKit
import UIKit
import simd

/// A spirit wandering the real streets: translucent glowing figure that drifts around a home point.
final class SpiritEntity {
    let id = UUID()
    let kind: SpiritKind
    let root = Entity()
    private let body = Entity()
    var home: SIMD2<Double>
    private(set) var position: SIMD2<Double>
    private var target: SIMD2<Double>
    private var heading: Float = 0
    private var phase = Float.random(in: 0...(2 * .pi))
    private var pause: Float = 0
    /// False on encounter stages: the spirit only hovers and sways in place.
    var wanders = true

    init(kind: SpiritKind, home: SIMD2<Double>) {
        self.kind = kind
        self.home = home
        self.position = home
        self.target = home
        root.name = "spirit-\(kind.rawValue)"
        root.addChild(body)
        Self.buildFigure(kind: kind, into: body)
        root.position = GeoProjection.world(home)
    }

    /// Head height in world space (for label projection).
    var labelAnchor: SIMD3<Float> {
        root.position + SIMD3(0, 2.3 * kind.scale + 0.3, 0)
    }

    func update(deltaTime dt: Float, roadHint: (() -> SIMD2<Double>?)? = nil) {
        phase += dt
        let toTarget = target - position
        let dist = simd_length(toTarget)
        if !wanders {
            // Hover in place.
        } else if dist < 0.5 {
            pause -= dt
            if pause <= 0 {
                let angle = Double.random(in: 0..<(2 * .pi))
                let r = Double.random(in: 3...12)
                target = home + SIMD2(cos(angle), sin(angle)) * r
                pause = Float.random(in: 0.8...2.5)
            }
        } else {
            let speed = 0.75 * Double(dt)
            position += toTarget / dist * min(speed, dist)
            let desired = atan2(Float(toTarget.x), Float(-toTarget.y))
            var delta = desired - heading
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            heading += delta * min(1, dt * 3)
        }
        let bob = 0.35 + 0.14 * sin(phase * 1.7)
        root.position = GeoProjection.world(position, y: Float(bob))
        if wanders { root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0]) }
        body.orientation = simd_quatf(angle: 0.06 * sin(phase * 1.3), axis: [0, 0, 1])
    }

    func face(_ worldPoint: SIMD3<Float>) {
        let d = worldPoint - root.position
        heading = atan2(d.x, d.z)
        root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
    }

    func place(at planar: SIMD2<Double>) {
        position = planar
        target = planar
        home = planar
        root.position = GeoProjection.world(planar, y: 0.35)
    }

    // MARK: - Figure

    static func buildFigure(kind: SpiritKind, into parent: Entity) {
        let s = kind.scale
        let glow = UIColor(hex: kind.glow)

        func ghost(_ alpha: Float, _ color: UIColor = glow) -> UnlitMaterial {
            var m = UnlitMaterial(color: color)
            m.blending = .transparent(opacity: .init(floatLiteral: alpha))
            m.faceCulling = .none
            return m
        }

        let robe = ModelEntity(mesh: .generateCone(height: 1.35 * s, radius: 0.42 * s), materials: [ghost(0.5)])
        robe.position.y = 0.95 * s
        let chest = ModelEntity(mesh: .generateSphere(radius: 0.2 * s), materials: [ghost(0.6)])
        chest.position.y = 1.5 * s
        let head = ModelEntity(mesh: .generateSphere(radius: 0.2 * s), materials: [ghost(0.72, UIColor(hex: 0xE6F6FF))])
        head.position.y = 1.85 * s
        let hair = ModelEntity(mesh: .generateCone(height: 0.9 * s, radius: 0.24 * s), materials: [ghost(0.4)])
        hair.position = [0, 1.62 * s, -0.08 * s]
        hair.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.75 * s), materials: [ghost(0.12)])
        halo.position.y = 1.2 * s
        for e in [robe, chest, head, hair, halo] {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            parent.addChild(e)
        }

        // Eyes: two tiny bright points facing forward (+Z).
        for x: Float in [-0.07, 0.07] {
            let eye = ModelEntity(mesh: .generateSphere(radius: 0.025 * s), materials: [UnlitMaterial(color: .white)])
            eye.position = [x * s, 1.87 * s, 0.18 * s]
            parent.addChild(eye)
        }

        if kind.hasLantern {
            var paper = UnlitMaterial(color: UIColor(hex: 0xCFF0FF))
            paper.blending = .transparent(opacity: .init(floatLiteral: 0.92))
            let lantern = ModelEntity(mesh: .generateSphere(radius: 0.17), materials: [paper])
            lantern.scale = [1, 1.2, 1]
            lantern.position = [0.42, 1.05, 0.3]
            parent.addChild(lantern)
            let lanternLight = PointLight()
            lanternLight.light.color = UIColor(hex: 0x9FD8F5)
            lanternLight.light.intensity = 2500
            lanternLight.light.attenuationRadius = 4
            lanternLight.position = lantern.position
            parent.addChild(lanternLight)
        }

        // Drifting motes.
        var motes = ParticleEmitterComponent()
        motes.emitterShape = .sphere
        motes.emitterShapeSize = SIMD3(repeating: 0.5 * s)
        motes.birthLocation = .volume
        motes.speed = 0.08
        motes.mainEmitter.birthRate = 40
        motes.mainEmitter.lifeSpan = 1.8
        motes.mainEmitter.size = 0.025
        motes.mainEmitter.acceleration = [0, 0.25, 0]
        motes.mainEmitter.blendMode = .additive
        motes.mainEmitter.opacityCurve = .linearFadeOut
        motes.mainEmitter.color = .constant(.single(glow))
        let moteEntity = Entity()
        moteEntity.components.set(motes)
        moteEntity.position.y = 1.0 * s
        parent.addChild(moteEntity)
    }
}
