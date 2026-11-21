import Observation
import RealityKit
import SwiftUI
import UIKit

/// A tiny golden-hour Italian piazza built from primitives (no map data, no streaming), where
/// Lorna walks with the full game's animation player and finds one spirit.
@Observable
final class PiazzaDemoScene {
    private(set) var spiritDistance: Double = 0
    private(set) var foundSpirit = false
    /// Joystick input: x right, y up on screen; length 0…1.
    @ObservationIgnored var input: SIMD2<Float> = .zero
    @ObservationIgnored var exploring = false

    @ObservationIgnored private let root = Entity()
    @ObservationIgnored private let lorna = LornaCharacter()
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private let spirit = Entity()
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var clock: Float = 0
    @ObservationIgnored private var position: SIMD3<Float> = [0, 0, 6]
    @ObservationIgnored private var yaw: Float = .pi
    @ObservationIgnored private var speed: Float = 0
    @ObservationIgnored private var playbackRate: Float = 1
    @ObservationIgnored private var cameraPosition: SIMD3<Float>?
    @ObservationIgnored private var orbit: Float = 0.6
    @ObservationIgnored private var infoTimer: Float = 0
    @ObservationIgnored private var celebrate: Float = 0

    private static let spiritHome: SIMD3<Float> = [9, 0, -9]
    private static let radius: Float = 15.5
    private static let fountainRadius: Float = 2.6

    func setup(in content: inout RealityViewCameraContent) async {
        await buildSky()
        buildPiazza()
        buildLights()
        buildSpirit()

        camera.camera.fieldOfViewInDegrees = 50
        camera.camera.near = 0.1
        camera.camera.far = 200
        root.addChild(camera)
        root.addChild(lorna.container)
        content.add(root)
        update(dt: 1)

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.update(dt: Float(min(event.deltaTime, 0.1)))
        }
        await lorna.build()
    }

    func restart() {
        position = [0, 0, 6]
        yaw = .pi
        speed = 0
        foundSpirit = false
        celebrate = 0
        spirit.scale = .one
    }

    // MARK: - Frame loop

    private func update(dt: Float) {
        clock += dt

        // Movement from the joystick (camera looks toward -Z, so screen-up is -Z).
        let mag = min(simd_length(input), 1)
        var targetSpeed: Float = 0
        if exploring, mag > 0.15 {
            // Walk only: the clip bundles the idle and walk clips, not the run clip.
            targetSpeed = 0.7 + min(1, (mag - 0.15) / 0.73) * 1.2
            let dir = SIMD3<Float>(input.x, 0, -input.y) / max(mag, 0.001)
            let desired = atan2(dir.x, dir.z)
            let delta = Self.wrap(desired - yaw)
            yaw += max(-5 * dt, min(5 * dt, delta * min(1, dt * 9)))
        }
        speed += (targetSpeed - speed) * min(1, dt * 6)
        if speed > 0.05 {
            position += SIMD3(sin(yaw), 0, cos(yaw)) * speed * dt
            let flat = SIMD2(position.x, position.z)
            let d = simd_length(flat)
            if d > Self.radius { position *= Self.radius / d }
            if d < Self.fountainRadius, d > 0.001 { position *= Self.fountainRadius / d }
        }
        lorna.container.position = position
        lorna.face(yaw: yaw)

        // Pose with hysteresis, cadence matched to speed (same rules as the full game).
        let current = lorna.pose ?? .idle
        var next = current
        switch current {
        case .idle: if speed > 0.4 { next = .walk }
        case .walk: if speed < 0.2 { next = .idle }
        case .run: next = .walk
        }
        if next != current { lorna.setPose(next) }
        let targetRate: Float
        switch lorna.pose ?? .idle {
        case .idle: targetRate = 1
        case .walk: targetRate = min(max(speed / 1.35, 0.6), 1.6)
        case .run: targetRate = min(max(speed / 3.6, 0.75), 1.45)
        }
        playbackRate += (targetRate - playbackRate) * min(1, dt * 4)
        lorna.setPlaybackSpeed(playbackRate)

        // Camera: slow showcase orbit on the intro, follow-cam while exploring.
        let focus = position + [0, 1.0, 0]
        let desiredCam: SIMD3<Float>
        if exploring {
            desiredCam = position + [0, 5.0, 7.2]
        } else {
            orbit += dt * 0.16
            desiredCam = position + [sin(orbit) * 5.2, 2.2, cos(orbit) * 5.2]
        }
        let k = min(1, dt * 3)
        let cam = cameraPosition.map { $0 + (desiredCam - $0) * k } ?? desiredCam
        cameraPosition = cam
        camera.look(at: focus, from: cam, relativeTo: nil)

        // Spirit: bob, spin, and a happy burst when found.
        let bob = sin(clock * 2) * 0.18
        spirit.position = Self.spiritHome + [0, 1.4 + bob, 0]
        spirit.orientation = simd_quatf(angle: clock * 0.8, axis: [0, 1, 0])
        if foundSpirit {
            celebrate = min(1, celebrate + dt * 1.5)
            spirit.scale = SIMD3(repeating: 1 + sin(celebrate * .pi) * 0.6)
        }

        infoTimer += dt
        if infoTimer > 0.2 {
            infoTimer = 0
            let d = Double(simd_distance(SIMD2(position.x, position.z), SIMD2(Self.spiritHome.x, Self.spiritHome.z)))
            if abs(d - spiritDistance) > 0.4 { spiritDistance = d }
            if exploring, !foundSpirit, d < 2.4 {
                foundSpirit = true
                // Turn Lorna toward the spirit.
                let to = Self.spiritHome - position
                yaw = atan2(to.x, to.z)
            }
        }
    }

    private static func wrap(_ a: Float) -> Float {
        var d = a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    // MARK: - Building the piazza

    private func material(_ hex: UInt32, roughness: Float = 0.85) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(hex: hex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    private func add(_ mesh: MeshResource, _ mat: some RealityKit.Material, at p: SIMD3<Float>, yaw: Float = 0, shadow: Bool = true) {
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.position = p
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if !shadow { e.components.set(DynamicLightShadowComponent(castsShadow: false)) }
        root.addChild(e)
    }

    private func buildSky() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 128)).image { ctx in
            let colors = [UIColor(hex: 0x4A3348).cgColor, UIColor(hex: 0xC8724A).cgColor,
                          UIColor(hex: 0xF2A541).cgColor, UIColor(hex: 0xFFF4E0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 0.46, 0.5]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 128), options: [.drawsAfterEndLocation])
            }
        }
        var sky = UnlitMaterial(color: UIColor(hex: 0xF2A541))
        if let cg = image.cgImage, let tex = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            sky.color = .init(tint: .white, texture: .init(tex))
        }
        sky.faceCulling = .front
        add(.generateSphere(radius: 90), sky, at: .zero, shadow: false)
    }

    private func buildPiazza() {
        // Paving: warm stone disc with a darker cobble ring and radiating guide lines.
        add(.generateCylinder(height: 0.1, radius: 26), material(0xCDB494), at: [0, -0.05, 0], shadow: false)
        add(.generateCylinder(height: 0.1, radius: 7.5), material(0xB89C78), at: [0, -0.04, 0], shadow: false)
        add(.generateCylinder(height: 0.1, radius: 6.9), material(0xD6C2A2), at: [0, -0.035, 0], shadow: false)
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            add(.generateBox(size: [0.18, 0.02, 9]), material(0xB89C78), at: [sin(a) * 12, 0.01, cos(a) * 12], yaw: a, shadow: false)
        }

        // Fountain.
        add(.generateCylinder(height: 0.55, radius: 2.0), material(0xEDE3D2), at: [0, 0.27, 0])
        var water = material(0x4FA3F7, roughness: 0.15)
        water.emissiveColor = .init(color: UIColor(hex: 0x9FD8F5))
        water.emissiveIntensity = 0.25
        add(.generateCylinder(height: 0.05, radius: 1.8), water, at: [0, 0.53, 0], shadow: false)
        add(.generateCylinder(height: 1.4, radius: 0.22), material(0xEDE3D2), at: [0, 1.2, 0])
        add(.generateCylinder(height: 0.16, radius: 0.85), material(0xEDE3D2), at: [0, 1.9, 0])
        add(.generateSphere(radius: 0.2), material(0xE8B02E, roughness: 0.4), at: [0, 2.15, 0])

        // Ring of Italian facades facing the centre.
        let walls: [UInt32] = [0xD9875C, 0xE9B962, 0xF0DFC0, 0xE7A69A, 0xC56A45, 0xE9B962, 0xF0DFC0]
        let count = 14
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            let h: Float = 9 + Float((i * 7) % 5) * 1.4
            let w: Float = 7.6
            let center = SIMD3<Float>(sin(a) * 21.5, h / 2, cos(a) * 21.5)
            let facing = a + .pi
            add(.generateBox(size: [w, h, 6]), material(walls[i % walls.count]), at: center, yaw: facing)
            // Cornice and terracotta roof cap.
            add(.generateBox(size: [w + 0.4, 0.4, 6.4]), material(0xF4ECDD), at: [center.x, h - 0.1, center.z], yaw: facing)
            add(.generateBox(size: [w, 0.5, 5.6]), material(0xB5523B), at: [center.x, h + 0.3, center.z], yaw: facing, shadow: false)
            // Windows with shutters, facing the piazza.
            let inward = SIMD3<Float>(-sin(a), 0, -cos(a))
            let right = SIMD3<Float>(cos(a), 0, -sin(a))
            let front = center + inward * 3.02
            let floors = Int((h - 3) / 3)
            for f in 0..<floors {
                for c in [-1, 1] {
                    let p = SIMD3<Float>(front.x, 4.2 + Float(f) * 3, front.z) + right * (Float(c) * 1.8)
                    add(.generateBox(size: [1.0, 1.6, 0.06]), material(0x2B3352, roughness: 0.3), at: p, yaw: facing, shadow: false)
                    add(.generateBox(size: [0.42, 1.6, 0.08]), material(i % 2 == 0 ? 0x4F7A5A : 0x8A5A3A), at: p + right * 0.75, yaw: facing, shadow: false)
                    add(.generateBox(size: [0.42, 1.6, 0.08]), material(i % 2 == 0 ? 0x4F7A5A : 0x8A5A3A), at: p - right * 0.75, yaw: facing, shadow: false)
                }
            }
            // Ground-floor door / shop arch.
            add(.generateBox(size: [2.0, 2.6, 0.08]), material(0x3A2A24), at: [front.x, 1.3, front.z], yaw: facing, shadow: false)
        }

        // Trees and lamps.
        for i in 0..<6 {
            let a = Float(i) / 6 * 2 * .pi + 0.3
            let p = SIMD3<Float>(sin(a) * 13.5, 0, cos(a) * 13.5)
            add(.generateCylinder(height: 2.4, radius: 0.16), material(0x6B4A33), at: p + [0, 1.2, 0])
            add(.generateSphere(radius: 1.5), material(0x5E8F4E), at: p + [0, 3.2, 0])
        }
        var lampGlow = UnlitMaterial(color: UIColor(hex: 0xFFD9A0))
        lampGlow.blending = .opaque
        for i in 0..<4 {
            let a = Float(i) / 4 * 2 * .pi + .pi / 4
            let p = SIMD3<Float>(sin(a) * 9.5, 0, cos(a) * 9.5)
            add(.generateCylinder(height: 3.4, radius: 0.07), material(0x2A2428, roughness: 0.5), at: p + [0, 1.7, 0])
            add(.generateSphere(radius: 0.22), lampGlow, at: p + [0, 3.5, 0], shadow: false)
        }
    }

    private func buildLights() {
        let sun = DirectionalLight()
        sun.light.color = UIColor(hex: 0xFFD9A0)
        sun.light.intensity = 3400
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2)
        sun.look(at: .zero, from: [-12, 14, 10], relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.color = UIColor(hex: 0x9FB4FF)
        fill.light.intensity = 1300
        fill.look(at: .zero, from: [10, 8, -12], relativeTo: nil)
        root.addChild(fill)
    }

    private func buildSpirit() {
        let core = ModelEntity(mesh: .generateSphere(radius: 0.32), materials: [UnlitMaterial(color: UIColor(hex: 0xFFF4E0))])
        var haloMaterial = UnlitMaterial(color: UIColor(hex: 0x9FD8F5))
        haloMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.6), materials: [haloMaterial])
        for e in [core, halo] {
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            spirit.addChild(e)
        }
        for i in 0..<3 {
            let a = Float(i) / 3 * 2 * .pi
            let mote = ModelEntity(mesh: .generateSphere(radius: 0.08), materials: [UnlitMaterial(color: UIColor(hex: 0xE8B02E))])
            mote.position = [sin(a) * 0.85, 0.1 * Float(i), cos(a) * 0.85]
            spirit.addChild(mote)
        }
        let glow = PointLight()
        glow.light.color = UIColor(hex: 0x9FD8F5)
        glow.light.intensity = 9000
        glow.light.attenuationRadius = 6
        spirit.addChild(glow)
        root.addChild(spirit)
    }
}
