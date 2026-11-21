import RealityKit
import simd

enum GeneratedModelAxis: String {
    case positiveX, negativeX, positiveY, negativeY, positiveZ, negativeZ

    var vector: SIMD3<Float> {
        switch self {
        case .positiveX: [1, 0, 0]
        case .negativeX: [-1, 0, 0]
        case .positiveY: [0, 1, 0]
        case .negativeY: [0, -1, 0]
        case .positiveZ: [0, 0, 1]
        case .negativeZ: [0, 0, -1]
        }
    }
}

/// Quaternion for the orthonormal basis built from `front` and `up`.
func generatedModelBasisQuaternion(front: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
    let f = simd_normalize(front)
    let r = simd_normalize(simd_cross(up, f))
    let u = simd_normalize(simd_cross(f, r))
    return simd_quatf(simd_float3x3(r, u, f))
}

func generatedModelOrientationCorrection(
    localFrontAxis: GeneratedModelAxis,
    localUpAxis: GeneratedModelAxis,
    desiredWorldForward: SIMD3<Float>,
    worldUp: SIMD3<Float> = [0, 1, 0]
) -> simd_quatf {
    let localBasis = generatedModelBasisQuaternion(front: localFrontAxis.vector, up: localUpAxis.vector)
    let worldBasis = generatedModelBasisQuaternion(front: desiredWorldForward, up: worldUp)
    return worldBasis * localBasis.inverse
}

/// Normalizes a loaded visual into container → "generated_model_runtime" → visual.
func attachGeneratedModelVisual(
    _ visual: Entity,
    to container: Entity,
    targetHeight: Float,
    localFrontAxis: GeneratedModelAxis?,
    localUpAxis: GeneratedModelAxis = .positiveY,
    desiredWorldForward: SIMD3<Float>? = nil
) {
    let runtime = container.findEntity(named: "generated_model_runtime") ?? {
        let runtime = Entity()
        runtime.name = "generated_model_runtime"
        container.addChild(runtime)
        return runtime
    }()
    runtime.children.forEach { $0.removeFromParent() }
    runtime.addChild(visual)

    let rawBounds = visual.visualBounds(relativeTo: runtime)
    visual.scale *= SIMD3<Float>(repeating: targetHeight / max(rawBounds.extents.y, 0.001))

    if let localFrontAxis, let desiredWorldForward {
        visual.orientation = generatedModelOrientationCorrection(
            localFrontAxis: localFrontAxis,
            localUpAxis: localUpAxis,
            desiredWorldForward: desiredWorldForward
        ) * visual.orientation
    }

    let bounds = visual.visualBounds(relativeTo: runtime)
    visual.position -= SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z)
}

/// Plays generated Meshy animation clips under a model container.
///
/// Every clip file of one Meshy rig shares the same skeleton, so the player keeps ONE animated
/// clone (the "rig") on screen and plays every clip on it with real skeletal crossfades — no
/// pose snapping or restarting. If the device cannot bind a clip to the shared rig (verified at
/// runtime by checking that the skeleton actually moves), it falls back to swapping full clip
/// clones, the documented safe pattern.
final class GeneratedModelAnimationPlayer {
    private let container: Entity
    private var templates: [String: Entity] = [:]
    private var activeAnimation: Entity?
    private var activeController: AnimationPlaybackController?
    private var baseVisual: Entity?
    private var currentLoop: String?
    private var oneShotRestoreTask: Task<Void, Never>?
    private var speed: Float = 1

    // Shared-rig blending
    private var blending = true
    private var rigHolder: Entity?
    private var rigAnimated: Entity?
    private var clips: [String: AnimationResource] = [:]
    private var verified = false
    private var verifyTask: Task<Void, Never>?

    init(container: Entity, templates: [String: Entity], rigClip: String? = nil) {
        self.container = container
        self.templates = templates
        baseVisual = runtime.children.first
        for (name, template) in templates {
            if let clip = template.availableAnimations.first { clips[name] = clip }
        }
        if let rigClip, templates[rigClip] != nil, !clips.isEmpty {
            buildRig(from: rigClip)
        } else {
            blending = false
        }
    }

    deinit {
        verifyTask?.cancel()
        oneShotRestoreTask?.cancel()
    }

    private var runtime: Entity {
        container.findEntity(named: "generated_model_runtime") ?? container
    }

    var currentLoopName: String? { currentLoop }

    /// Length of one cycle of a clip, in seconds at normal speed.
    func clipDuration(_ name: String) -> Double? {
        guard let d = (clips[name] ?? templates[name]?.availableAnimations.first)?.definition.duration, d > 0.1 else { return nil }
        return d
    }

    /// Switches the looping state with a crossfade of `transition` seconds.
    func setLoop(_ resourceName: String?, transition: Double = 0.3) {
        guard resourceName != currentLoop || activeController == nil else { return }
        currentLoop = resourceName
        oneShotRestoreTask?.cancel()
        play(resourceName, looping: true, transition: transition)
    }

    /// Adjusts playback rate of the active loop (walk cadence follows real speed).
    func setSpeed(_ speed: Float) {
        self.speed = speed
        activeController?.speed = speed
    }

    func playOnce(_ resourceName: String?, restoreAfter duration: Duration, transition: Double = 0.25) {
        guard let resourceName else { return }
        play(resourceName, looping: false, transition: transition, rate: 1)
        oneShotRestoreTask?.cancel()
        oneShotRestoreTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.play(self.currentLoop, looping: true, transition: 0.4)
        }
    }

    func stop() {
        currentLoop = nil
        oneShotRestoreTask?.cancel()
        activeController?.stop(blendOutDuration: 0.3)
        activeController = nil
    }

    // MARK: - Shared rig

    private func buildRig(from name: String) {
        guard let template = templates[name] else { blending = false; return }
        let animated = template.clone(recursive: true)
        let holder = Entity()
        holder.addChild(animated)
        runtime.addChild(holder)
        align(holder: holder, template: template)
        rigHolder = holder
        rigAnimated = animated
    }

    private func tearDownRig() {
        verifyTask?.cancel()
        activeController?.stop()
        activeController = nil
        rigHolder?.removeFromParent()
        rigHolder = nil
        rigAnimated = nil
        blending = false
    }

    private func play(_ resourceName: String?, looping: Bool, transition: Double, rate: Float? = nil) {
        if blending, let rigAnimated, let resourceName, let clip = clips[resourceName] {
            let controller = rigAnimated.playAnimation(
                looping ? clip.repeat() : clip,
                transitionDuration: transition,
                blendLayerOffset: 0,
                separateAnimatedValue: false,
                startsPaused: false,
                clock: nil,
                handoffType: .snapshotAndReplace()
            )
            controller.speed = rate ?? speed
            activeController = controller
            if !verified { scheduleVerification(controller: controller) }
            return
        }
        swapPlay(resourceName, looping: looping, rate: rate)
    }

    /// The rig must visibly move under a clip; if the skeleton stays frozen while the clip's
    /// clock advances, this device can't share clips across files — use clone swapping instead.
    private func scheduleVerification(controller: AnimationPlaybackController) {
        verifyTask?.cancel()
        verifyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, let skin = self.skinnedModel(), controller.isPlaying else { return }
            let poseA = skin.jointTransforms
            let timeA = controller.time
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, controller.isPlaying else { return }
            let poseB = skin.jointTransforms
            guard controller.time - timeA > 0.1, !poseA.isEmpty, poseA.count == poseB.count else { return }
            var moved: Float = 0
            for (a, b) in zip(poseA, poseB) {
                moved = max(moved, simd_distance(a.translation, b.translation), simd_length(a.rotation.vector - b.rotation.vector))
            }
            if moved > 1e-4 {
                self.verified = true
            } else {
                let loop = self.currentLoop
                self.tearDownRig()
                self.swapPlay(loop, looping: true, rate: nil)
            }
        }
    }

    private func skinnedModel() -> ModelEntity? {
        guard let rigAnimated else { return nil }
        var stack: [Entity] = [rigAnimated]
        while let e = stack.popLast() {
            if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
            stack.append(contentsOf: e.children)
        }
        return nil
    }

    // MARK: - Fallback: swap full clip clones

    private func swapPlay(_ resourceName: String?, looping: Bool, rate: Float?) {
        activeAnimation?.removeFromParent()
        activeAnimation = nil
        activeController = nil
        baseVisual?.isEnabled = true
        guard let resourceName, let template = templates[resourceName] else { return }

        let animated = template.clone(recursive: true)
        let holder = Entity()
        holder.addChild(animated)
        runtime.addChild(holder)
        align(holder: holder, template: template)
        if let animation = animated.availableAnimations.first {
            let controller = animated.playAnimation(looping ? animation.repeat() : animation, transitionDuration: 0.2)
            controller.speed = rate ?? speed
            activeController = controller
        }
        activeAnimation = holder
    }

    /// Places a clip clone exactly where the base visual stands, at the same height.
    private func align(holder: Entity, template: Entity) {
        if let base = baseVisual {
            let baseImport = base.availableAnimations.isEmpty ? Transform.identity : template.transform
            holder.transform = Transform(matrix: base.transform.matrix * baseImport.matrix.inverse)
            let baseBounds = base.visualBounds(relativeTo: runtime)
            let fit = baseBounds.extents.y / holder.visualBounds(relativeTo: runtime).extents.y
            if fit.isFinite, fit > 0 {
                holder.scale *= SIMD3<Float>(repeating: fit)
            }
            let clipBounds = holder.visualBounds(relativeTo: runtime)
            holder.position += SIMD3<Float>(
                baseBounds.center.x - clipBounds.center.x,
                baseBounds.min.y - clipBounds.min.y,
                baseBounds.center.z - clipBounds.center.z
            )
            base.isEnabled = false
        }
    }
}
