import Metal
import RealityKit
import UIKit
import simd

/// Time-of-day look. Chosen automatically from the real sun, or overridden by the player.
enum LightingPreset: String, CaseIterable, Identifiable {
    case day, sunset, blueHour, night
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .sunset: "Golden hour"
        case .blueHour: "Blue hour"
        case .night: "Night"
        }
    }

    var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .sunset: "sun.horizon.fill"
        case .blueHour: "moon.haze.fill"
        case .night: "moon.stars.fill"
        }
    }

    static func from(sunElevation: Double) -> LightingPreset {
        if sunElevation > 12 { return .day }
        if sunElevation > -2 { return .sunset }
        if sunElevation > -8 { return .blueHour }
        return .night
    }

    var isDark: Bool { self == .night || self == .blueHour }

    var zenith: UInt32 {
        switch self {
        case .day: 0x3F86DA
        case .sunset: 0x3A2A5C
        case .blueHour: 0x1B2A6B
        case .night: 0x070B1E
        }
    }
    var midSky: UInt32 {
        switch self {
        case .day: 0x8EC2F2
        case .sunset: 0xC4607A
        case .blueHour: 0x4A5FB0
        case .night: 0x1A2148
        }
    }
    var horizon: UInt32 {
        switch self {
        case .day: 0xF6EBD4
        case .sunset: 0xF6A65A
        case .blueHour: 0xC48BB0
        case .night: 0x3A3560
        }
    }

    var sunColor: UInt32 {
        switch self {
        case .day: 0xFFF3D6
        case .sunset: 0xFFA860
        case .blueHour: 0x9AA8FF
        case .night: 0x9FB4FF
        }
    }
    var sunIntensity: Float {
        switch self {
        case .day: 3600
        case .sunset: 2600
        case .blueHour: 1100
        case .night: 700
        }
    }
    var fillColor: UInt32 {
        switch self {
        case .day: 0xBFD9FF
        case .sunset: 0xC98BB0
        case .blueHour: 0x6C7FD8
        case .night: 0x4A5A9A
        }
    }
    var fillIntensity: Float {
        switch self {
        case .day: 900
        case .sunset: 700
        case .blueHour: 520
        case .night: 380
        }
    }
    /// Multiplies every surface tint so the world darkens convincingly at night.
    var surfaceBrightness: CGFloat {
        switch self {
        case .day: 1.0
        case .sunset: 0.9
        case .blueHour: 0.6
        case .night: 0.42
        }
    }
    var lampGlow: Float {
        switch self {
        case .day: 0
        case .sunset: 1.4
        case .blueHour: 2.6
        case .night: 3.2
        }
    }
    var windowGlow: Float {
        switch self {
        case .day: 0
        case .sunset: 0.35
        case .blueHour: 1.0
        case .night: 1.4
        }
    }
    /// Elevation used for the light when the player forces a preset.
    var fallbackElevation: Double {
        switch self {
        case .day: 52
        case .sunset: 13
        case .blueHour: 30
        case .night: 38
        }
    }
}

/// Weather as shown in the world. `.rain` also wets streets and starts the rain emitter.
enum WeatherCondition: String, CaseIterable, Identifiable, Sendable {
    case clear, cloudy, rain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .cloudy: "Cloudy"
        case .rain: "Rain"
        }
    }

    var symbol: String {
        switch self {
        case .clear: "sun.max"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        }
    }

    var cloudOpacity: Float {
        switch self {
        case .clear: 0.35
        case .cloudy: 0.85
        case .rain: 0.95
        }
    }
    var sunScale: Float {
        switch self {
        case .clear: 1
        case .cloudy: 0.55
        case .rain: 0.38
        }
    }
    /// Grey veil painted over the sky gradient.
    var overcast: CGFloat {
        switch self {
        case .clear: 0
        case .cloudy: 0.38
        case .rain: 0.58
        }
    }
}

/// Sky dome, sun, fill, clouds, haze and rain. One instance per scene.
/// Preset/weather changes cross-fade over a few seconds when `update` is driven.
final class SkyRig {
    let root = Entity()
    private let domeBack = ModelEntity()
    private let domeFront = ModelEntity()
    private let clouds = ModelEntity()
    private let haze = ModelEntity()
    private let rain = Entity()
    private let sun = DirectionalLight()
    private let fill = DirectionalLight()
    private(set) var preset: LightingPreset?
    private(set) var weather: WeatherCondition = .clear
    private var lastAzimuth: Double = -999

    private struct LightState {
        var sunColor: SIMD3<Float>
        var sunIntensity: Float
        var fillColor: SIMD3<Float>
        var fillIntensity: Float
        var sunDirection: SIMD3<Float>
        var cloudOpacity: Float
        var hazeColor: SIMD3<Float>
    }
    private var current: LightState?
    private var from: LightState?
    private var to: LightState?
    private var transition: Float = 1
    private static let duration: Float = 3.5
    private var cloudSpin: Float = 0
    private var hazeMaterial = UnlitMaterial()
    private var cloudMaterial = UnlitMaterial()

    init(radius: Float = 900) {
        var builder = MeshBuilder()
        builder.addSphere(center: .zero, radius: SIMD3(repeating: radius), rings: 24, segments: 36)
        domeBack.model = ModelComponent(mesh: builder.makeMesh(name: "sky") ?? .generateSphere(radius: radius), materials: [])
        var inner = MeshBuilder()
        inner.addSphere(center: .zero, radius: SIMD3(repeating: radius * 0.97), rings: 24, segments: 36)
        domeFront.model = ModelComponent(mesh: inner.makeMesh(name: "skyFade") ?? .generateSphere(radius: radius * 0.97), materials: [])
        domeFront.components.set(OpacityComponent(opacity: 0))
        domeFront.isEnabled = false
        root.addChild(domeBack)
        root.addChild(domeFront)

        buildClouds()
        buildHaze()
        buildRain()

        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 60, depthBias: 2.5)
        root.addChild(sun)
        root.addChild(fill)
    }

    /// Keeps the dome, clouds and haze centred on the camera target so the horizon never ends.
    func follow(_ point: SIMD3<Float>) {
        let flat = SIMD3(point.x, 0, point.z)
        domeBack.position = flat
        domeFront.position = flat
        haze.position = flat
        clouds.position = SIMD3(point.x, 170, point.z)
        rain.position = SIMD3(point.x, point.y + 16, point.z)
    }

    func apply(_ preset: LightingPreset, weather: WeatherCondition = .clear, sunAzimuth: Double, sunElevation: Double?, animated: Bool = false) {
        let azimuthChanged = abs(sunAzimuth - lastAzimuth) > 2
        let changed = preset != self.preset || weather != self.weather
        guard changed || azimuthChanged else { return }
        let fade = animated && changed && current != nil
        self.preset = preset
        self.weather = weather
        lastAzimuth = sunAzimuth

        // Real sun azimuth; elevation clamped into the preset's mood range.
        let lightAzimuth = preset.isDark ? sunAzimuth + 180 : sunAzimuth
        let realElevation = sunElevation ?? preset.fallbackElevation
        let elevation: Double = switch preset {
        case .day: min(max(realElevation, 25), 70)
        case .sunset: min(max(realElevation, 9), 18)
        case .blueHour, .night: preset.fallbackElevation
        }

        let target = LightState(
            sunColor: Self.rgb(preset.sunColor),
            sunIntensity: preset.sunIntensity * weather.sunScale,
            fillColor: Self.rgb(preset.fillColor),
            fillIntensity: preset.fillIntensity * (weather == .clear ? 1 : 1.15),
            sunDirection: Self.direction(azimuth: lightAzimuth, elevation: elevation),
            cloudOpacity: weather.cloudOpacity * (preset == .night ? 0.5 : 1),
            hazeColor: Self.rgb(Self.hazeHex(preset: preset, weather: weather))
        )

        var material = UnlitMaterial()
        if let image = Self.skyImage(preset: preset, weather: weather, sunAzimuth: lightAzimuth, sunElevation: elevation),
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            material.color = .init(tint: UIColor(hex: preset.midSky))
        }
        material.faceCulling = .none

        if fade, let current {
            // New sky fades in on the inner dome, then becomes the back dome.
            domeFront.model?.materials = [material]
            domeFront.components.set(OpacityComponent(opacity: 0))
            domeFront.isEnabled = true
            from = current
            to = target
            transition = 0
        } else {
            domeBack.model?.materials = [material]
            domeFront.isEnabled = false
            from = nil
            to = nil
            transition = 1
            set(target)
        }
        rain.components[ParticleEmitterComponent.self]?.isEmitting = weather == .rain
        rain.isEnabled = weather == .rain
    }

    /// Drives cross-fades and cloud drift. Call every frame from scenes that animate the sky.
    func update(dt: Float) {
        cloudSpin += dt * 0.004
        clouds.orientation = simd_quatf(angle: cloudSpin, axis: [0, 1, 0])

        guard transition < 1, let from, let to else { return }
        transition = min(1, transition + dt / Self.duration)
        let t = transition * transition * (3 - 2 * transition)
        set(LightState(
            sunColor: simd_mix(from.sunColor, to.sunColor, SIMD3(repeating: t)),
            sunIntensity: from.sunIntensity + (to.sunIntensity - from.sunIntensity) * t,
            fillColor: simd_mix(from.fillColor, to.fillColor, SIMD3(repeating: t)),
            fillIntensity: from.fillIntensity + (to.fillIntensity - from.fillIntensity) * t,
            sunDirection: simd_normalize(simd_mix(from.sunDirection, to.sunDirection, SIMD3(repeating: t)) + SIMD3(0, 0.001, 0)),
            cloudOpacity: from.cloudOpacity + (to.cloudOpacity - from.cloudOpacity) * t,
            hazeColor: simd_mix(from.hazeColor, to.hazeColor, SIMD3(repeating: t))
        ))
        domeFront.components.set(OpacityComponent(opacity: t))
        if transition >= 1 {
            domeBack.model?.materials = domeFront.model?.materials ?? []
            domeFront.isEnabled = false
            self.from = nil
            self.to = nil
        }
    }

    private func set(_ state: LightState) {
        current = state
        sun.light.color = Self.color(state.sunColor)
        sun.light.intensity = state.sunIntensity
        sun.look(at: .zero, from: state.sunDirection * 100, relativeTo: nil)

        fill.light.color = Self.color(state.fillColor)
        fill.light.intensity = state.fillIntensity
        let fillDir = simd_normalize(SIMD3(-state.sunDirection.x, 0.8, -state.sunDirection.z))
        fill.look(at: .zero, from: fillDir * 100, relativeTo: nil)

        clouds.components.set(OpacityComponent(opacity: state.cloudOpacity))
        hazeMaterial.color = .init(tint: Self.color(state.hazeColor), texture: hazeMaterial.color.texture)
        haze.model?.materials = [hazeMaterial]
    }

    // MARK: - Pieces

    private func buildClouds() {
        var mesh = MeshBuilder()
        let r: Float = 1100
        mesh.addQuad([-r, 0, -r], [r, 0, -r], [r, 0, r], [-r, 0, r], normal: [0, -1, 0],
                     uv: [SIMD2(0, 0), SIMD2(3, 0), SIMD2(3, 3), SIMD2(0, 3)])
        cloudMaterial.color = .init(tint: .white)
        if let image = Self.cloudImage(), let tex = try? TextureResource(image: image, options: .init(semantic: .color)) {
            cloudMaterial.color = .init(tint: UIColor(white: 1, alpha: 1), texture: .init(tex, sampler: Self.repeatSampler))
        }
        cloudMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        cloudMaterial.faceCulling = .none
        clouds.model = ModelComponent(mesh: mesh.makeMesh(name: "clouds") ?? .generatePlane(width: 2 * r, depth: 2 * r), materials: [cloudMaterial])
        clouds.components.set(DynamicLightShadowComponent(castsShadow: false))
        clouds.components.set(OpacityComponent(opacity: 0.35))
        root.addChild(clouds)
    }

    /// Soft ring of horizon-coloured haze: depth, and it hides the edge of loaded map tiles.
    private func buildHaze() {
        var mesh = MeshBuilder()
        let radius: Float = 400, height: Float = 140, sides = 48
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi
            let a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let p0 = SIMD3(cos(a0) * radius, -2, sin(a0) * radius)
            let p1 = SIMD3(cos(a1) * radius, -2, sin(a1) * radius)
            let n = -simd_normalize(SIMD3(cos((a0 + a1) / 2), 0, sin((a0 + a1) / 2)))
            let u0 = Float(i) / Float(sides), u1 = Float(i + 1) / Float(sides)
            mesh.addQuad(p0, p1, p1 + SIMD3(0, height, 0), p0 + SIMD3(0, height, 0), normal: n,
                         uv: [SIMD2(u0, 0), SIMD2(u1, 0), SIMD2(u1, 1), SIMD2(u0, 1)])
        }
        if let image = Self.hazeImage(), let tex = try? TextureResource(image: image, options: .init(semantic: .color)) {
            hazeMaterial.color = .init(tint: .white, texture: .init(tex))
        }
        hazeMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        hazeMaterial.faceCulling = .none
        haze.model = ModelComponent(mesh: mesh.makeMesh(name: "haze") ?? .generatePlane(width: 1, depth: 1), materials: [hazeMaterial])
        haze.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(haze)
    }

    private func buildRain() {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = [44, 1, 44]
        emitter.birthLocation = .volume
        emitter.birthDirection = .world
        emitter.emissionDirection = [0.06, -1, 0.02]
        emitter.speed = 16
        emitter.speedVariation = 2
        emitter.mainEmitter.birthRate = 2600
        emitter.mainEmitter.lifeSpan = 1.4
        emitter.mainEmitter.size = 0.018
        emitter.mainEmitter.stretchFactor = 9
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.color = .constant(.single(UIColor(red: 0.82, green: 0.88, blue: 1, alpha: 0.55)))
        emitter.mainEmitter.opacityCurve = .constant
        emitter.isEmitting = false
        rain.components.set(emitter)
        rain.isEnabled = false
        root.addChild(rain)
    }

    private static func hazeHex(preset: LightingPreset, weather: WeatherCondition) -> UInt32 {
        guard weather != .clear else { return preset.horizon }
        switch preset {
        case .day: return 0xC9CCD4
        case .sunset: return 0xC99A8A
        case .blueHour: return 0x6F6F9A
        case .night: return 0x2E2F48
        }
    }

    // MARK: - Helpers

    static let repeatSampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat
        d.tAddressMode = .repeat
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        return .init(d)
    }()

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    static func color(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
    }

    /// World direction toward a sky point (x = east, z = south).
    static func direction(azimuth: Double, elevation: Double) -> SIMD3<Float> {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        return SIMD3(Float(sin(a) * cos(e)), Float(sin(e)), Float(-cos(a) * cos(e)))
    }

    /// Equirectangular gradient (v = 0 is the zenith) with a baked sun glow and stars at night.
    static func skyImage(preset: LightingPreset, weather: WeatherCondition = .clear, sunAzimuth: Double, sunElevation: Double) -> CGImage? {
        let width = 256, height = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(hex: preset.zenith).cgColor, UIColor(hex: preset.midSky).cgColor,
                          UIColor(hex: preset.horizon).cgColor, UIColor(hex: 0x2A1E2E).cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 0.32, 0.5, 0.58]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [.drawsAfterEndLocation])
            }

            // Sphere UV: theta = u * 2π with direction (cosθ, ·, sinθ). Azimuth A maps to θ = A - 90°.
            var theta = (sunAzimuth - 90).truncatingRemainder(dividingBy: 360)
            if theta < 0 { theta += 360 }
            let sunX = CGFloat(theta / 360) * CGFloat(width)
            let sunY = CGFloat((90 - sunElevation) / 180) * CGFloat(height)

            if preset.isDark {
                var rng = SystemRandomNumberGenerator()
                let stars = weather == .clear ? (preset == .night ? 180 : 70) : 12
                for _ in 0..<stars {
                    let x = CGFloat.random(in: 0..<CGFloat(width), using: &rng)
                    let y = CGFloat.random(in: 0..<CGFloat(height) * 0.42, using: &rng)
                    let s = CGFloat.random(in: 0.5...1.4, using: &rng)
                    cg.setFillColor(UIColor.white.withAlphaComponent(.random(in: 0.4...0.95)).cgColor)
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
                }
                if weather == .clear {
                    cg.setFillColor(UIColor(hex: 0xFFF4E0).cgColor)
                    cg.fillEllipse(in: CGRect(x: sunX - 3, y: sunY - 3, width: 6, height: 6))
                }
            } else {
                let glowColor = UIColor(hex: preset == .sunset ? 0xFFD27A : 0xFFFBEA)
                let strength: CGFloat = weather == .clear ? 0.95 : 0.35
                let glow = [glowColor.withAlphaComponent(strength).cgColor, glowColor.withAlphaComponent(0.0).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1]) {
                    for offset in [-CGFloat(width), 0, CGFloat(width)] {
                        let c = CGPoint(x: sunX + offset, y: sunY)
                        cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                              endRadius: preset == .sunset ? 46 : 26, options: [])
                    }
                }
            }

            if weather.overcast > 0 {
                let veil = preset.isDark ? UIColor(hex: 0x2B2C40) : UIColor(hex: preset == .sunset ? 0xA88C94 : 0xB9BEC8)
                cg.setFillColor(veil.withAlphaComponent(weather.overcast).cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: width, height: Int(Double(height) * 0.56)))
            }
        }
        return image.cgImage
    }

    /// Soft cumulus puffs on transparent, tiling.
    private static func cloudImage() -> CGImage? {
        let size = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            let cg = ctx.cgContext
            var seed: UInt64 = 0xC10D5
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            let colors = [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            for _ in 0..<26 {
                let cx = rnd() * CGFloat(size), cy = rnd() * CGFloat(size)
                for _ in 0..<5 {
                    let r = 10 + rnd() * 26
                    let c = CGPoint(x: cx + (rnd() - 0.5) * 50, y: cy + (rnd() - 0.5) * 20)
                    for dx in [-CGFloat(size), 0, CGFloat(size)] {
                        for dy in [-CGFloat(size), 0, CGFloat(size)] {
                            let p = CGPoint(x: c.x + dx, y: c.y + dy)
                            cg.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
                        }
                    }
                }
            }
        }.cgImage
    }

    /// White with alpha: opaque at the bottom, fading to clear at the top (v = 0).
    private static func hazeImage() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 128), format: format).image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor,
                          UIColor.white.withAlphaComponent(0.55).cgColor,
                          UIColor.white.withAlphaComponent(0.92).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 128), options: [])
            }
        }.cgImage
    }
}
