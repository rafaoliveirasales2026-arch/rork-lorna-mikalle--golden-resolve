import RealityKit
import UIKit
import simd

/// The main story, placed in the street:
/// - a Naples-style votive shrine (edicola) with a golden light column at the story landmark,
///   visible over the rooftops so the objective reads in the world, not just in the HUD;
/// - Giulia waiting in person during the chapters she is in (one model, never duplicated).
///   With no story stop chosen she waits beside Lorna, so the story stays playable standing still.
final class StoryPresence {
    let root = Entity()

    private let landmark = Entity()
    private let column = ModelEntity()
    private let core = ModelEntity()
    private let halo = ModelEntity()
    private let shrine = Entity()
    private let giulia = StoryCharacter(.giulia)
    private var giuliaLoaded = false

    private(set) var landmarkPOI: PlacedPOI?
    private var landmarkAnchor: SIMD2<Double>?
    private var landmarkChosen = false
    private var landmarkOpacity: Float = 0
    private var anchorRefresh: Float = 0

    private var giuliaSpot: SIMD2<Double>?
    private var companionSpot: SIMD2<Double>?
    private var giuliaOpacity: Float = 0
    private var giuliaYaw: Float = 0
    private var giuliaTalking = false
    private var stillTime: Float = 0

    private var clock: Float = 0
    private var pulse: Float = 0

    /// World anchors for the HUD labels (nil when hidden).
    var landmarkLabelAnchor: SIMD3<Float>? {
        guard landmarkOpacity > 0.4, let landmarkAnchor else { return nil }
        return GeoProjection.world(landmarkAnchor, y: 3.6)
    }
    var giuliaLabelAnchor: SIMD3<Float>? {
        guard giuliaOpacity > 0.6, let giuliaSpot else { return nil }
        return GeoProjection.world(giuliaSpot, y: 2.05)
    }
    var giuliaPlanar: SIMD2<Double>? { giuliaOpacity > 0.6 ? giuliaSpot : nil }
    var landmarkPlanar: SIMD2<Double>? { landmarkOpacity > 0.4 ? landmarkAnchor : nil }

    init() {
        root.addChild(landmark)
        landmark.isEnabled = false
        buildLandmark()
        giulia.container.isEnabled = false
        root.addChild(giulia.container)
    }

    func load() async {
        await giulia.build()
        giuliaLoaded = !giulia.container.children.isEmpty
    }

    /// A short golden flare when a story moment starts here.
    func celebrate() { pulse = 1 }

    // MARK: - Frame update

    func update(dt: Float, game: GameState, lorna: SIMD2<Double>, lornaMoving: Bool, hasFix: Bool,
                cameraYaw: Float, roadSamples: [SIMD2<Double>], isBlocked: (SIMD2<Double>) -> Bool) {
        clock += dt
        pulse = max(0, pulse - dt * 0.7)
        updateLandmark(dt: dt, game: game, lorna: lorna, hasFix: hasFix, roadSamples: roadSamples)
        updateGiulia(dt: dt, game: game, lorna: lorna, lornaMoving: lornaMoving, hasFix: hasFix,
                     cameraYaw: cameraYaw, isBlocked: isBlocked)
    }

    private func updateLandmark(dt: Float, game: GameState, lorna: SIMD2<Double>, hasFix: Bool, roadSamples: [SIMD2<Double>]) {
        let target = hasFix ? game.storyLandmark?.poi : nil
        if target?.id != landmarkPOI?.id {
            // Fade the old landmark out before it moves to the new place.
            if landmarkOpacity > 0.02, landmarkPOI != nil {
                landmarkOpacity = max(0, landmarkOpacity - dt * 2.5)
                applyLandmarkOpacity()
                return
            }
            landmarkPOI = target
            landmarkAnchor = target.map { anchor(for: $0.position, roadSamples: roadSamples) }
            anchorRefresh = 0
        }
        // Streets can arrive after the place: re-seat the shrine onto the street now and then.
        anchorRefresh += dt
        if anchorRefresh > 3, let poi = landmarkPOI {
            anchorRefresh = 0
            landmarkAnchor = anchor(for: poi.position, roadSamples: roadSamples)
        }
        landmarkChosen = landmarkPOI != nil && game.storyStopID == landmarkPOI?.id
        let goal: Float = landmarkPOI == nil || game.encounter != nil ? 0 : 1
        landmarkOpacity += (goal - landmarkOpacity) * min(1, dt * 2)
        applyLandmarkOpacity()
        guard let landmarkAnchor, landmark.isEnabled else { return }

        landmark.position = GeoProjection.world(landmarkAnchor, y: 0)
        // The lit niche turns toward Lorna as she approaches.
        let toLorna = GeoProjection.world(lorna) - landmark.position
        if simd_length(SIMD2(toLorna.x, toLorna.z)) > 1 {
            shrine.orientation = simd_slerp(shrine.orientation,
                                            simd_quatf(angle: atan2(toLorna.x, toLorna.z), axis: [0, 1, 0]),
                                            min(1, dt * 1.5))
        }
        let breathe = 0.5 + 0.5 * sin(clock * 1.6)
        let strength: Float = landmarkChosen ? 1 : 0.55
        column.scale = [1 + pulse * 0.8, strength * (0.9 + 0.1 * breathe) + pulse * 0.3, 1 + pulse * 0.8]
        column.position.y = 30 * column.scale.y
        core.scale = [1, column.scale.y, 1]
        core.position.y = column.position.y
        halo.orientation = simd_quatf(angle: clock * 0.6, axis: [0, 1, 0])
        let haloScale = (landmarkChosen ? 1 : 0.75) * (1 + 0.06 * breathe) + pulse * 1.6
        halo.scale = SIMD3(repeating: haloScale)
    }

    private func applyLandmarkOpacity() {
        landmark.isEnabled = landmarkOpacity > 0.01
        landmark.components.set(OpacityComponent(opacity: landmarkOpacity))
    }

    /// Mapped places are often building centroids; stand the shrine on the nearest street in front.
    private func anchor(for position: SIMD2<Double>, roadSamples: [SIMD2<Double>]) -> SIMD2<Double> {
        var best = position
        var bestDistance = 35.0
        for sample in roadSamples {
            let d = simd_distance(sample, position)
            if d < bestDistance { bestDistance = d; best = sample }
        }
        return best
    }

    private func updateGiulia(dt: Float, game: GameState, lorna: SIMD2<Double>, lornaMoving: Bool, hasFix: Bool,
                              cameraYaw: Float, isBlocked: (SIMD2<Double>) -> Bool) {
        let storyOpen = game.storyRun != nil || game.storyLaunching
        let wanted = giuliaLoaded && hasFix && game.encounter == nil && game.nextChapterFeatures(.giulia)
        stillTime = lornaMoving ? 0 : stillTime + dt

        var desired: SIMD2<Double>?
        if wanted {
            if landmarkChosen, let landmarkAnchor, simd_distance(landmarkAnchor, lorna) < 300 {
                // She waits at the story stop, beside the shrine, on Lorna's side.
                let toLorna = simd_normalize(lorna - landmarkAnchor + SIMD2(1e-6, 0))
                desired = landmarkAnchor + SIMD2(-toLorna.y, toLorna.x) * 1.9 + toLorna * 0.8
                companionSpot = nil
            } else {
                if let spot = companionSpot, simd_distance(spot, lorna) > 35, !storyOpen { companionSpot = nil }
                if companionSpot == nil, stillTime > 2.5 {
                    companionSpot = sideSpot(near: lorna, cameraYaw: cameraYaw, isBlocked: isBlocked)
                }
                desired = companionSpot
            }
        } else {
            companionSpot = nil
        }

        // Never walk her through walls: fade out, re-seat, fade in.
        var goal: Float = desired == nil ? 0 : 1
        if let desired, let current = giuliaSpot, simd_distance(desired, current) > 1.5 { goal = 0 }
        if giuliaOpacity < 0.02 { giuliaSpot = desired }
        if giuliaSpot == nil { goal = 0 }
        giuliaOpacity += (goal - giuliaOpacity) * min(1, dt * (goal > giuliaOpacity ? 2.2 : 3.5))
        if giuliaOpacity < 0.01, goal == 0 { giuliaOpacity = 0 }

        giulia.container.isEnabled = giuliaOpacity > 0.01
        giulia.container.components.set(OpacityComponent(opacity: giuliaOpacity))
        guard let spot = giuliaSpot, giulia.container.isEnabled else { return }
        giulia.container.position = GeoProjection.world(spot)

        let toLorna = GeoProjection.world(lorna) - GeoProjection.world(spot)
        let distance = simd_length(SIMD2(toLorna.x, toLorna.z))
        if distance > 0.3 {
            let yaw = atan2(toLorna.x, toLorna.z)
            var delta = yaw - giuliaYaw
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            giuliaYaw += delta * min(1, dt * 4)
            giulia.face(yaw: giuliaYaw)
        }
        let talk = storyOpen || (distance < 7 && !lornaMoving)
        if talk != giuliaTalking {
            giuliaTalking = talk
            talk ? giulia.talk() : giulia.idle()
        }
    }

    /// A free spot just beside Lorna that the follow camera can see.
    private func sideSpot(near lorna: SIMD2<Double>, cameraYaw: Float, isBlocked: (SIMD2<Double>) -> Bool) -> SIMD2<Double> {
        let toCamera = SIMD2(Double(sin(cameraYaw)), Double(-cos(cameraYaw)))
        let right = SIMD2(Double(cos(cameraYaw)), Double(sin(cameraYaw)))
        let options = [lorna + right * 2.3 + toCamera * 0.7,
                       lorna - right * 2.3 + toCamera * 0.7,
                       lorna + toCamera * 2.6]
        return options.first { !isBlocked($0) } ?? options[0]
    }

    // MARK: - Landmark geometry

    private func buildLandmark() {
        let materials = WorldMaterials.shared
        let preset = LightingPreset.sunset

        func box(_ size: SIMD3<Float>, at p: SIMD3<Float>, _ material: RealityKit.Material, radius: Float = 0.02) -> ModelEntity {
            let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: radius), materials: [material])
            e.position = p
            return e
        }

        // Edicola votiva: plaster niche on a stone plinth, arched top, candle glow and flowers.
        let plaster = materials.material(.wallCream, preset: preset)
        let stone = materials.material(.plinth, preset: preset)
        let trim = materials.material(.cornice, preset: preset)
        shrine.addChild(box([1.5, 0.5, 0.8], at: [0, 0.25, 0], stone))
        shrine.addChild(box([1.2, 1.8, 0.55], at: [0, 1.4, 0], plaster))
        shrine.addChild(box([1.42, 0.1, 0.66], at: [0, 2.32, 0], trim))
        let arch = ModelEntity(mesh: .generateCylinder(height: 0.5, radius: 0.6), materials: [plaster])
        arch.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        arch.position = [0, 2.37, 0]
        shrine.addChild(arch)
        var glow = UnlitMaterial(color: UIColor(hex: 0xFFD98A))
        glow.blending = .opaque
        shrine.addChild(box([0.66, 0.96, 0.06], at: [0, 1.45, 0.26], glow, radius: 0.01))
        let flowers = materials.material(.flowers, preset: preset)
        shrine.addChild(box([0.32, 0.22, 0.22], at: [-0.42, 0.6, 0.3], flowers, radius: 0.06))
        shrine.addChild(box([0.32, 0.22, 0.22], at: [0.42, 0.6, 0.3], flowers, radius: 0.06))
        var flame = UnlitMaterial(color: UIColor(hex: 0xF7D774))
        flame.blending = .opaque
        shrine.addChild(box([0.08, 0.16, 0.08], at: [0, 1.05, 0.36], flame, radius: 0.03))
        let candle = Entity()
        candle.components.set(PointLightComponent(color: UIColor(hex: 0xFFC66B), intensity: 9000, attenuationRadius: 7))
        candle.position = [0, 1.3, 0.8]
        shrine.addChild(candle)

        // A Neapolitan washing line strung over the shrine between two thin poles.
        let pole = materials.material(.lampPole, preset: preset)
        shrine.addChild(box([0.07, 3.1, 0.07], at: [-1.7, 1.55, 0], pole))
        shrine.addChild(box([0.07, 3.1, 0.07], at: [1.7, 1.55, 0], pole))
        shrine.addChild(box([3.4, 0.015, 0.015], at: [0, 3.02, 0], pole, radius: 0))
        let laundry: [(UInt32, Float, SIMD2<Float>)] = [
            (0xFFF4E0, -1.2, [0.42, 0.55]), (0x3B7BD4, -0.6, [0.36, 0.7]),
            (0xE7A69A, 0.55, [0.5, 0.45]), (0xF2A541, 1.15, [0.3, 0.6]),
        ]
        for (hex, x, size) in laundry {
            var cloth = SimpleMaterial(color: UIColor(hex: hex), roughness: 0.9, isMetallic: false)
            cloth.faceCulling = .none
            shrine.addChild(box([size.x, size.y, 0.02], at: [x, 3.0 - size.y / 2, 0], cloth, radius: 0))
        }
        landmark.addChild(shrine)

        // The golden column that reads over the rooftops from blocks away.
        var beam = UnlitMaterial(color: UIColor(hex: 0xE8B02E))
        beam.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        beam.faceCulling = .none
        column.model = ModelComponent(mesh: .generateCylinder(height: 60, radius: 1.1), materials: [beam])
        column.position.y = 30
        column.components.set(DynamicLightShadowComponent(castsShadow: false))
        landmark.addChild(column)
        var coreMaterial = UnlitMaterial(color: UIColor(hex: 0xF7D774))
        coreMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        coreMaterial.faceCulling = .none
        core.model = ModelComponent(mesh: .generateCylinder(height: 60, radius: 0.22), materials: [coreMaterial])
        core.position.y = 30
        core.components.set(DynamicLightShadowComponent(castsShadow: false))
        landmark.addChild(core)

        var ring = MeshBuilder()
        let points = (0...48).map { i -> SIMD2<Float> in
            let a = Float(i) / 48 * 2 * .pi
            return SIMD2(cos(a), sin(a)) * 2.6
        }
        ring.addRibbon(points, width: 0.16, y: 0.06, roundJoins: false)
        var haloMaterial = UnlitMaterial(color: UIColor(hex: 0xE8B02E))
        haloMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        haloMaterial.faceCulling = .none
        halo.model = ModelComponent(mesh: ring.makeMesh(name: "storyHalo") ?? .generatePlane(width: 1, depth: 1), materials: [haloMaterial])
        halo.components.set(DynamicLightShadowComponent(castsShadow: false))
        landmark.addChild(halo)
    }
}
