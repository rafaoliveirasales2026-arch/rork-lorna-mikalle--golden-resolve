import RealityKit
import UIKit

/// Golden Determination: rising gold sparks, flame wisps, a pulsing ground ring and warm light.
final class AuraEffect {
    let root = Entity()
    private let ring = ModelEntity()
    private let sparks = Entity()
    private let flames = Entity()
    private let light = PointLight()
    private var time: Float = 0
    private(set) var isActive = false

    init(height: Float = 1.7) {
        root.name = "aura"

        var sparkEmitter = ParticleEmitterComponent()
        sparkEmitter.emitterShape = .cylinder
        sparkEmitter.emitterShapeSize = [0.55, height * 0.5, 0.55]
        sparkEmitter.birthLocation = .volume
        sparkEmitter.birthDirection = .normal
        sparkEmitter.speed = 0.25
        sparkEmitter.mainEmitter.birthRate = 260
        sparkEmitter.mainEmitter.lifeSpan = 1.3
        sparkEmitter.mainEmitter.size = 0.03
        sparkEmitter.mainEmitter.acceleration = [0, 1.4, 0]
        sparkEmitter.mainEmitter.blendMode = .additive
        sparkEmitter.mainEmitter.opacityCurve = .linearFadeOut
        sparkEmitter.mainEmitter.color = .evolving(
            start: .single(UIColor(hex: 0xFFF1B0)),
            end: .single(UIColor(hex: 0xE8B02E))
        )
        sparkEmitter.isEmitting = false
        sparks.components.set(sparkEmitter)
        sparks.position.y = height * 0.5

        var flameEmitter = ParticleEmitterComponent()
        flameEmitter.emitterShape = .torus
        flameEmitter.emitterShapeSize = [0.6, 0.05, 0.6]
        flameEmitter.birthLocation = .surface
        flameEmitter.birthDirection = .world
        flameEmitter.emissionDirection = [0, 1, 0]
        flameEmitter.speed = 0.9
        flameEmitter.mainEmitter.birthRate = 90
        flameEmitter.mainEmitter.lifeSpan = 1.0
        flameEmitter.mainEmitter.size = 0.16
        flameEmitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.1
        flameEmitter.mainEmitter.blendMode = .additive
        flameEmitter.mainEmitter.opacityCurve = .quickFadeInOut
        flameEmitter.mainEmitter.spreadingAngle = 0.4
        flameEmitter.mainEmitter.color = .evolving(
            start: .single(UIColor(hex: 0xF7D774)),
            end: .single(UIColor(hex: 0xC98A12, alpha: 0.4))
        )
        flameEmitter.isEmitting = false
        flames.components.set(flameEmitter)
        flames.position.y = 0.1

        var ringMaterial = UnlitMaterial()
        if let image = Self.ringImage(), let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            ringMaterial.color = .init(tint: .white, texture: .init(texture))
        } else {
            ringMaterial.color = .init(tint: UIColor(hex: 0xE8B02E))
        }
        ringMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        ringMaterial.faceCulling = .none
        ring.model = ModelComponent(mesh: .generatePlane(width: 2.4, depth: 2.4), materials: [ringMaterial])
        ring.position.y = 0.07
        ring.components.set(DynamicLightShadowComponent(castsShadow: false))

        light.light.color = UIColor(hex: 0xFFC94A)
        light.light.intensity = 0
        light.light.attenuationRadius = 6
        light.position = [0, 1.1, 0.4]

        root.addChild(ring)
        root.addChild(sparks)
        root.addChild(flames)
        root.addChild(light)
        root.isEnabled = false
    }

    func setActive(_ active: Bool) {
        isActive = active
        root.isEnabled = active
        for e in [sparks, flames] {
            if var emitter = e.components[ParticleEmitterComponent.self] {
                emitter.isEmitting = active
                e.components.set(emitter)
            }
        }
    }

    func update(deltaTime: Float) {
        guard isActive else { return }
        time += deltaTime
        let pulse = 1 + 0.08 * sin(time * 5)
        ring.scale = SIMD3(pulse, 1, pulse)
        ring.orientation = simd_quatf(angle: time * 0.6, axis: [0, 1, 0])
        light.light.intensity = 9000 + 3000 * sin(time * 7)
    }

    private static func ringImage() -> CGImage? {
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: 128, y: 128)
            let colors = [
                UIColor(hex: 0xF7D774, alpha: 0.0).cgColor,
                UIColor(hex: 0xF7D774, alpha: 0.35).cgColor,
                UIColor(hex: 0xFFF1B0, alpha: 0.95).cgColor,
                UIColor(hex: 0xE8B02E, alpha: 0.0).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.6, 0.8, 1.0]) {
                cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 126, options: [])
            }
            // Diamond flourishes on the ring.
            cg.setFillColor(UIColor(hex: 0xFFF4E0, alpha: 0.9).cgColor)
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                let p = CGPoint(x: 128 + cos(a) * 102, y: 128 + sin(a) * 102)
                cg.saveGState()
                cg.translateBy(x: p.x, y: p.y)
                cg.rotate(by: .pi / 4)
                cg.fill(CGRect(x: -5, y: -5, width: 10, height: 10))
                cg.restoreGState()
            }
        }
        return image.cgImage
    }
}
