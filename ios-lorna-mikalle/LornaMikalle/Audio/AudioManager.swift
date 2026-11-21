import AVFoundation
import Foundation
import Observation
import SwiftUI

enum Sfx: String, CaseIterable {
    case stepStone = "step_stone", stepGrass = "step_grass", stepRun = "step_run"
    case uiTap = "ui_tap", uiOpen = "ui_open", uiNotify = "ui_notify", uiItem = "ui_item"
    case questComplete = "quest_complete", reward, levelUp = "level_up"
    case discovery, spiritAlert = "spirit_alert", encounterStart = "encounter_start"
    case dialogueNext = "dialogue_next", spiritReaction = "spirit_reaction", friendship
    case attackStrike = "attack_strike", impact, dodge, guardUp = "guard", enemyDefeat = "enemy_defeat"
    case bossIntro = "boss_intro", battleStart = "battle_start"
    case goldenActivate = "golden_activate", heal, teleport, specialAttack = "special_attack"
}

enum AudioContext: Int, Comparable {
    case explore, encounter, story, battle, golden

    static func < (a: AudioContext, b: AudioContext) -> Bool { a.rawValue < b.rawValue }

    /// How loud the theme plays in this context (ducking).
    var musicLevel: Float {
        switch self {
        case .explore: 1.0
        case .encounter: 0.35
        case .story: 0.3
        case .battle: 0.45
        case .golden: 0.15
        }
    }

    var ambienceLevel: Float {
        switch self {
        case .explore: 1.0
        case .encounter, .story: 0.45
        case .battle: 0.3
        case .golden: 0.2
        }
    }
}

/// Music (the user's theme, unchanged), sound effects and ambience, each with its own volume.
/// Uses the `.ambient` session: it mixes with other apps and respects the silent switch.
@Observable
final class AudioManager {
    static let shared = AudioManager()

    var musicVolume: Float = (UserDefaults.standard.object(forKey: "audio.music") as? NSNumber)?.floatValue ?? 0.8 {
        didSet { UserDefaults.standard.set(musicVolume, forKey: "audio.music"); refreshLevels(fade: 0.2) }
    }
    var sfxVolume: Float = (UserDefaults.standard.object(forKey: "audio.sfx") as? NSNumber)?.floatValue ?? 0.9 {
        didSet { UserDefaults.standard.set(sfxVolume, forKey: "audio.sfx") }
    }
    var ambienceVolume: Float = (UserDefaults.standard.object(forKey: "audio.ambience") as? NSNumber)?.floatValue ?? 0.6 {
        didSet { UserDefaults.standard.set(ambienceVolume, forKey: "audio.ambience"); refreshLevels(fade: 0.2) }
    }

    @ObservationIgnored private var music: [AVAudioPlayer] = []
    @ObservationIgnored private var activeMusic = 0
    @ObservationIgnored private var crossfading = false
    @ObservationIgnored private var musicStarted = false
    @ObservationIgnored private var loopTimer: Timer?
    @ObservationIgnored private var sfxPool: [Sfx: [AVAudioPlayer]] = [:]
    @ObservationIgnored private var ambience: [String: AVAudioPlayer] = [:]
    @ObservationIgnored private var ambienceTargets: [String: Float] = [:]
    @ObservationIgnored private var auraLoop: AVAudioPlayer?
    @ObservationIgnored private var contexts: [(id: UUID, context: AudioContext)] = []
    @ObservationIgnored private var lastStep = Date.distantPast
    @ObservationIgnored private var isSuspended = false

    private static let crossfade: TimeInterval = 4

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var context: AudioContext { contexts.map(\.context).max() ?? .explore }

    // MARK: - Music

    /// Starts the theme with a 3-second fade-in. Safe to call more than once.
    func startMusic() {
        guard !musicStarted else { return }
        guard let url = Self.url("lorna_theme") else { return }
        music = (0..<2).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
        guard music.count == 2 else { return }
        musicStarted = true
        for p in music { p.prepareToPlay(); p.volume = 0 }
        music[0].play()
        music[0].setVolume(musicTarget, fadeDuration: 3)
        loopTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickLoop() }
        }
    }

    private var musicTarget: Float { musicVolume * context.musicLevel }

    /// Seamless loop: the second player starts ~4 s before the end and the two cross-fade.
    private func tickLoop() {
        guard musicStarted, !isSuspended, music.count == 2 else { return }
        let current = music[activeMusic]
        let remaining = current.duration - current.currentTime
        if !crossfading, current.isPlaying, remaining < Self.crossfade {
            crossfading = true
            let next = music[1 - activeMusic]
            next.currentTime = 0
            next.volume = 0
            next.play()
            next.setVolume(musicTarget, fadeDuration: Self.crossfade)
            current.setVolume(0, fadeDuration: Self.crossfade)
            activeMusic = 1 - activeMusic
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.crossfade + 0.3) { [weak self] in
                current.stop()
                self?.crossfading = false
                // Apply any volume/context change made during the crossfade.
                self?.refreshLevels(fade: 0.6)
            }
        } else if !current.isPlaying, !crossfading {
            current.currentTime = 0
            current.play()
            current.setVolume(musicTarget, fadeDuration: 1)
        }
    }

    // MARK: - Context ducking

    func push(_ context: AudioContext, id: UUID) {
        contexts.removeAll { $0.id == id }
        contexts.append((id, context))
        refreshLevels(fade: 0.8)
    }

    func pop(id: UUID) {
        contexts.removeAll { $0.id == id }
        refreshLevels(fade: 1.2)
    }

    private func refreshLevels(fade: TimeInterval) {
        guard !isSuspended else { return }
        if musicStarted, !crossfading, music.count == 2 {
            music[activeMusic].setVolume(musicTarget, fadeDuration: fade)
        }
        for (name, target) in ambienceTargets {
            ambience[name]?.setVolume(target * ambienceVolume * context.ambienceLevel, fadeDuration: fade)
        }
        auraLoop?.setVolume(sfxVolume * 0.5, fadeDuration: fade)
    }

    // MARK: - App lifecycle

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        music.forEach { $0.pause() }
        ambience.values.forEach { $0.pause() }
        auraLoop?.pause()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        try? AVAudioSession.sharedInstance().setActive(true)
        if musicStarted, music.count == 2 {
            let p = music[activeMusic]
            p.volume = 0
            p.play()
            p.setVolume(musicTarget, fadeDuration: 2)
        }
        for (name, player) in ambience where (ambienceTargets[name] ?? 0) > 0 {
            player.play()
        }
        auraLoop?.play()
        refreshLevels(fade: 1.5)
    }

    // MARK: - Sound effects

    func play(_ sfx: Sfx, volume: Float = 1, pitchJitter: Float = 0.05) {
        guard sfxVolume > 0.01, !isSuspended else { return }
        var pool = sfxPool[sfx] ?? []
        let player: AVAudioPlayer
        if let free = pool.first(where: { !$0.isPlaying }) {
            player = free
        } else if pool.count < 3, let url = Self.url(sfx.rawValue), let new = try? AVAudioPlayer(contentsOf: url) {
            new.enableRate = true
            new.prepareToPlay()
            pool.append(new)
            sfxPool[sfx] = pool
            player = new
        } else if let oldest = pool.first {
            player = oldest
            player.stop()
        } else {
            return
        }
        player.currentTime = 0
        player.rate = 1 + Float.random(in: -pitchJitter...pitchJitter)
        player.volume = min(1, sfxVolume * volume)
        player.play()
    }

    /// Footsteps paced by Lorna's animation (one sound per footfall; nil = standing still).
    func footstep(interval: Double?, running: Bool, onGrass: Bool) {
        guard let interval, interval > 0.15 else { return }
        guard Date().timeIntervalSince(lastStep) > interval else { return }
        lastStep = Date()
        let sfx: Sfx = running ? .stepRun : (onGrass ? .stepGrass : .stepStone)
        play(sfx, volume: 0.35, pitchJitter: 0.08)
    }

    func setAura(_ on: Bool) {
        if on {
            guard auraLoop == nil, let url = Self.url("aura_loop"), let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.numberOfLoops = -1
            p.volume = 0
            p.play()
            p.setVolume(sfxVolume * 0.5, fadeDuration: 0.6)
            auraLoop = p
        } else if let p = auraLoop {
            auraLoop = nil
            p.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { p.stop() }
        }
    }

    // MARK: - Ambience

    /// Cross-fades the looping beds: city or nature by day, night insects/wind after dark, rain on top.
    func setAmbience(dark: Bool, nature: Bool, rain: Bool, windy: Bool) {
        var targets: [String: Float] = [
            "amb_city": (!nature && !dark) ? 0.55 : (!nature ? 0.2 : 0),
            "amb_nature": nature && !dark ? 0.6 : (nature ? 0.2 : 0),
            "amb_night": dark ? 0.5 : 0,
            "amb_rain": rain ? 0.7 : 0,
            "amb_wind": windy || rain ? 0.35 : 0,
        ]
        if rain { targets["amb_city"] = (targets["amb_city"] ?? 0) * 0.5 }
        guard targets != ambienceTargets else { return }
        ambienceTargets = targets
        for (name, target) in targets {
            if target > 0, ambience[name] == nil, let url = Self.url(name), let p = try? AVAudioPlayer(contentsOf: url) {
                p.numberOfLoops = -1
                p.volume = 0
                p.prepareToPlay()
                ambience[name] = p
            }
            guard let p = ambience[name] else { continue }
            if target > 0, !p.isPlaying, !isSuspended { p.play() }
            p.setVolume(target * ambienceVolume * context.ambienceLevel, fadeDuration: 3)
        }
    }

    // MARK: - Files

    private static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Audio")
    }
}

private struct AudioContextModifier: ViewModifier {
    let context: AudioContext
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { AudioManager.shared.push(context, id: id) }
            .onDisappear { AudioManager.shared.pop(id: id) }
    }
}

extension View {
    /// Ducks the music/ambience while this view is on screen.
    func audioContext(_ context: AudioContext) -> some View {
        modifier(AudioContextModifier(context: context))
    }
}
