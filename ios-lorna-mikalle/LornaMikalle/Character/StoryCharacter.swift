import RealityKit
import UIKit
import simd

/// A bundled, rigged story character (friends and family) for cinematics and dialogue scenes.
/// Model front is normalized to world +Z, so yaw = atan2(dir.x, dir.z).
final class StoryCharacter {
    struct Model {
        let base: String
        let idle: String
        let talk: String
        let height: Float

        /// Giulia Ferri: generated model, front +Z, up +Y (from the asset's Orientation line).
        static let giulia = Model(base: "giulia_art_student",
                                  idle: "giulia_art_student-anim-idle-7",
                                  talk: "giulia_art_student-anim-talk-with-left-hand-on-hip",
                                  height: 1.66)
    }

    let container = Entity()
    let model: Model
    private var player: GeneratedModelAnimationPlayer?

    init(_ model: Model) {
        self.model = model
        container.name = model.base
    }

    /// Loads the model and its clips. Leaves the container empty if the bundle lacks them.
    func build() async {
        guard let base = try? await Entity(named: model.base) else { return }
        var clips: [String: Entity] = [:]
        for name in [model.idle, model.talk] {
            if let clip = try? await Entity(named: name) { clips[name] = clip }
        }
        attachGeneratedModelVisual(
            base,
            to: container,
            targetHeight: model.height,
            localFrontAxis: .positiveZ,
            localUpAxis: .positiveY,
            desiredWorldForward: [0, 0, 1]
        )
        player = GeneratedModelAnimationPlayer(container: container, templates: clips, rigClip: model.idle)
        player?.setLoop(model.idle, transition: 0)
    }

    func idle() { player?.setLoop(model.idle, transition: 0.4) }
    func talk() { player?.setLoop(model.talk, transition: 0.35) }

    func face(yaw: Float) {
        container.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}
