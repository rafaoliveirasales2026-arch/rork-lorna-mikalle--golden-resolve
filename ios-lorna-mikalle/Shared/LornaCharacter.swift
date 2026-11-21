import RealityKit
import UIKit
import simd

enum LornaPose: Equatable {
    case idle, walk, run
}

/// Loads Lorna's bundled model and clips once; every scene clones from these templates.
final class LornaAssets {
    static let shared = LornaAssets()

    static let base = "lorna_mikalle"
    static let idle = "lorna_mikalle-anim-idle"
    static let walk = "lorna_mikalle-anim-casual-walk-inplace"
    static let run = "lorna_mikalle-anim-lean-forward-sprint-inplace"
    static let cast = "lorna_mikalle-anim-charged-spell-cast"

    private(set) var baseTemplate: Entity?
    private(set) var clipTemplates: [String: Entity] = [:]
    private var loadTask: Task<Void, Never>?

    func load() async {
        if let loadTask { return await loadTask.value }
        let task = Task { @MainActor in
            self.baseTemplate = try? await Entity(named: Self.base)
            for name in [Self.idle, Self.walk, Self.run, Self.cast] {
                if let entity = try? await Entity(named: name) {
                    self.clipTemplates[name] = entity
                }
            }
            // Cleaned, high-resolution skin shared by the model and every clip (same UV layout).
            if let material = await Self.cleanMaterial() {
                if let base = self.baseTemplate { Self.apply(material, to: base) }
                for clip in self.clipTemplates.values { Self.apply(material, to: clip) }
            }
        }
        loadTask = task
        await task.value
    }

    private static func cleanMaterial() async -> PhysicallyBasedMaterial? {
        guard let image = UIImage(named: "lorna_basecolor_clean")?.cgImage,
              let texture = try? await TextureResource(image: image, options: .init(semantic: .color))
        else { return nil }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(texture))
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.2)
        material.emissiveColor = .init(texture: .init(texture))
        material.emissiveIntensity = 0.06
        return material
    }

    private static func apply(_ material: PhysicallyBasedMaterial, to root: Entity) {
        var stack: [Entity] = [root]
        while let entity = stack.popLast() {
            if let model = entity as? ModelEntity, var component = model.model {
                component.materials = Array(repeating: material, count: max(1, component.materials.count))
                model.model = component
            }
            stack.append(contentsOf: entity.children)
        }
    }
}

/// Lorna in a scene: container (world placement + yaw) → runtime → model.
/// Model front is normalized to world +Z, so yaw = atan2(dir.x, dir.z).
final class LornaCharacter {
    let container = Entity()
    private var player: GeneratedModelAnimationPlayer?
    private(set) var pose: LornaPose?
    let height: Float

    init(height: Float = 1.7) {
        self.height = height
        container.name = "lorna"
    }

    func build() async {
        await LornaAssets.shared.load()
        let assets = LornaAssets.shared
        let visual: Entity = assets.baseTemplate?.clone(recursive: true) ?? Self.fallbackFigure()
        attachGeneratedModelVisual(
            visual,
            to: container,
            targetHeight: height,
            localFrontAxis: .positiveZ,
            localUpAxis: .positiveY,
            desiredWorldForward: [0, 0, 1]
        )
        if assets.baseTemplate != nil {
            player = GeneratedModelAnimationPlayer(container: container, templates: assets.clipTemplates, rigClip: LornaAssets.idle)
        }
        setPose(.idle)
    }

    func setPose(_ newPose: LornaPose) {
        guard newPose != pose else { return }
        let transition = Self.transition(from: pose, to: newPose)
        pose = newPose
        switch newPose {
        case .idle: player?.setLoop(LornaAssets.idle, transition: transition)
        case .walk: player?.setLoop(LornaAssets.walk, transition: transition)
        case .run: player?.setLoop(LornaAssets.run, transition: transition)
        }
    }

    /// Crossfade length per pose pair: settling down is a touch slower than starting off.
    private static func transition(from old: LornaPose?, to new: LornaPose) -> Double {
        switch (old, new) {
        case (nil, _): return 0
        case (.idle?, .walk): return 0.3
        case (.walk?, .idle): return 0.4
        case (.walk?, .run), (.run?, .walk): return 0.35
        default: return 0.45
        }
    }

    private var playbackSpeed: Float = 1

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.setSpeed(speed)
    }

    /// Seconds between footfalls at the current cadence (each walk/run cycle has two steps).
    var stepInterval: Double? {
        let rate = Double(max(playbackSpeed, 0.1))
        switch pose {
        case .walk?: return (player?.clipDuration(LornaAssets.walk) ?? 1.1) / 2 / rate
        case .run?: return (player?.clipDuration(LornaAssets.run) ?? 0.68) / 2 / rate
        default: return nil
        }
    }

    func castSpell(restoreAfter: Duration = .milliseconds(2600)) {
        player?.playOnce(LornaAssets.cast, restoreAfter: restoreAfter)
    }

    func face(yaw: Float) {
        container.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    /// Simple stand-in if the bundled model cannot load.
    static func fallbackFigure() -> Entity {
        let root = Entity()
        let jacket = SimpleMaterial(color: UIColor(hex: 0xF2C24B), roughness: 0.7, isMetallic: false)
        let jeans = SimpleMaterial(color: UIColor(hex: 0x2B3A55), roughness: 0.8, isMetallic: false)
        let skin = SimpleMaterial(color: UIColor(hex: 0xF3D3B8), roughness: 0.6, isMetallic: false)
        let hair = SimpleMaterial(color: UIColor(hex: 0x3B2418), roughness: 0.8, isMetallic: false)
        let legs = ModelEntity(mesh: .generateBox(size: [0.3, 0.8, 0.2], cornerRadius: 0.08), materials: [jeans])
        legs.position.y = 0.4
        let torso = ModelEntity(mesh: .generateBox(size: [0.42, 0.55, 0.26], cornerRadius: 0.1), materials: [jacket])
        torso.position.y = 1.08
        let head = ModelEntity(mesh: .generateSphere(radius: 0.15), materials: [skin])
        head.position.y = 1.5
        let hairBack = ModelEntity(mesh: .generateBox(size: [0.32, 0.5, 0.12], cornerRadius: 0.05), materials: [hair])
        hairBack.position = [0, 1.35, -0.12]
        for part in [legs, torso, head, hairBack] { root.addChild(part) }
        return root
    }
}
