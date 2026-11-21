import CoreLocation
import Foundation
import Observation
import SwiftUI
import simd

struct SpiritInfo: Identifiable, Equatable {
    let id: UUID
    let kind: SpiritKind
    var distance: Double
}

/// One spirit encounter (Explore → Encounter → Golden Determination / Battle).
@Observable
final class EncounterSession: Identifiable {
    let id = UUID()
    let spiritID: UUID
    let kind: SpiritKind
    var hp: Int
    var dialogueIndex = 0
    var talkedOnce = false
    var lastDamage = 0
    var calmedByBattle = false
    var isCalmed: Bool { hp <= 0 || calmedByBattle }

    init(spiritID: UUID, kind: SpiritKind) {
        self.spiritID = spiritID
        self.kind = kind
        self.hp = kind.maxHP
    }

    var dialogue: String { kind.dialogue[dialogueIndex % kind.dialogue.count] }
}

/// Map loading state shown in the HUD.
struct WorldStatus: Equatable {
    enum Phase: Equatable { case waitingForGPS, loading, ready, offline, failed(String) }
    var phase: Phase = .waitingForGPS
    var loaded = 0
    var total = 9
    var fromCache = false
    var previewReady = false
    /// Saved streets are shown around the last known area while the first GPS fix arrives.
    var locating = false

    var hasWorld: Bool { loaded > 0 || previewReady }
}

/// A real place near Lorna, with its live distance.
struct POIInfo: Identifiable, Equatable {
    let poi: PlacedPOI
    var distance: Double
    var bearing: Double
    var id: Int { poi.id }
}

/// A story label pinned to something in the 3D world (the story landmark or Giulia).
struct StoryMarker: Identifiable, Equatable {
    enum Kind: Equatable { case landmark, giulia }
    let kind: Kind
    var point: CGPoint
    var id: Kind { kind }
}

/// The real place that stands in for the next chapter's location (a café for Bar Stella,
/// a fountain for Piazza della Fontana). Derived only from the story's own scene headings.
struct StoryEcho: Equatable {
    let place: String
    let categories: [POICategory]

    init(place: String) {
        self.place = place
        let p = place.lowercased()
        if p.contains("fontana") { categories = [.fountain, .monument, .park] }
        else if p.contains("bar ") || p.contains("caff") { categories = [.cafe, .market] }
        else if p.contains("fornai") { categories = [.market, .cafe] }
        else if p.contains("liceo") || p.contains("aula") { categories = [.library, .museum, .theatre] }
        else if p.contains("benassi") { categories = [.theatre, .library, .museum] }
        else if p.contains("conceria") { categories = [.landmark, .monument, .museum] }
        else if p.contains("torre") || p.contains("rooftop") { categories = [.viewpoint, .church, .landmark] }
        else if p.contains("porto") { categories = [.viewpoint, .fountain, .monument] }
        else if p.contains("casa") { categories = [.park, .church] }
        else if p.contains("via ") { categories = [.landmark, .monument, .church] }
        else { categories = [] }
    }
}

/// Three real places chained into a walk.
struct WalkRoute: Equatable {
    var stops: [PlacedPOI]
    var index = 0
    var current: PlacedPOI? { index < stops.count ? stops[index] : nil }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = Theme.gold
}

/// A chapter being played in the full-screen story player.
@Observable
final class StoryRun: Identifiable {
    let id = UUID()
    let chapter: Chapter
    var index: Int
    var alarm = 0
    var battle: BattleSession?
    var pendingChoiceReply: [(Speaker, String)] = []

    init(chapter: Chapter, index: Int) {
        self.chapter = chapter
        self.index = index
    }
}

enum GameSheet: String, Identifiable {
    case profile, story, missions, team, bag
    var id: String { rawValue }
}

@Observable
final class GameState {
    static let encounterRange: Double = 45
    static let discoveryRange: Double = 40

    var progress = PlayerProgress.load() {
        didSet { if progress != oldValue { progress.save() } }
    }

    // World
    var spirits: [SpiritInfo] = []
    var labelPositions: [UUID: CGPoint] = [:]
    var worldStatus = WorldStatus()
    /// Where Lorna is on screen when buildings hide her (nil when visible).
    var occludedMarker: CGPoint?
    var nearbyPOIs: [POIInfo] = []
    var poiLabelPositions: [Int: CGPoint] = [:]
    var activeRoute: WalkRoute?

    // Atmosphere
    var lightingOverride: LightingPreset?
    var autoPreset: LightingPreset = .sunset
    var activePreset: LightingPreset { lightingOverride ?? autoPreset }
    var weatherOverride: WeatherCondition?
    var liveWeather: LiveWeather?
    var activeWeather: WeatherCondition { weatherOverride ?? liveWeather?.condition ?? .clear }

    var followHeading = false
    var cameraResetToken = 0

    // Presentation
    var encounter: EncounterSession?
    var activeSheet: GameSheet?
    var storyRun: StoryRun?
    var toasts: [Toast] = []
    /// The prologue cinematic. `introIsReplay` hides the "Begin Chapter 1" hand-off.
    var showIntro = false
    var introIsReplay = false
    /// A real place the player chose to walk to before playing the next chapter.
    var storyStopID: Int?
    /// Screen positions of in-world story labels, published by the explore scene.
    var storyMarkers: [StoryMarker] = []
    /// True for the short camera push-in between tapping Play and the story opening.
    var storyLaunching = false

    var onSpiritCalmed: ((UUID) -> Void)?
    var stageProvider: (() -> EncounterStageSource?)?

    var nearestInRange: SpiritInfo? {
        spirits.filter { $0.distance <= Self.encounterRange }.min { $0.distance < $1.distance }
    }

    var nearest: SpiritInfo? { spirits.min { $0.distance < $1.distance } }

    var events: [GameEvent] { GameEvent.active(preset: activePreset) }
    var xpMultiplier: Double { events.reduce(1) { $0 * $1.xpMultiplier } }

    // MARK: - XP & rewards

    func grant(_ reward: Reward, reason: String? = nil, boosted: Bool = true) {
        let xp = boosted ? Int(Double(reward.xp) * xpMultiplier) : reward.xp
        let levels = progress.addXP(xp)
        for (item, n) in reward.items { progress.add(item, n) }
        if let reason {
            var r = reward
            r.xp = xp
            show(Toast(title: reason, detail: r.summary, symbol: "sparkles"))
        }
        if levels > 0 {
            AudioManager.shared.play(.levelUp)
            show(Toast(title: "Level \(progress.level)!", detail: "Max HP \(progress.maxHP)", symbol: "arrow.up.circle.fill", tint: Theme.blueBright))
        }
    }

    func show(_ toast: Toast) {
        toasts.append(toast)
        if toasts.count > 3 { toasts.removeFirst() }
        let id = toast.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            self?.toasts.removeAll { $0.id == id }
        }
    }

    // MARK: - Encounters

    func approach(_ spirit: SpiritInfo) {
        progress.spiritsMet += 1
        AudioManager.shared.play(.encounterStart)
        encounter = EncounterSession(spiritID: spirit.id, kind: spirit.kind)
    }

    func talk() {
        guard let encounter else { return }
        encounter.dialogueIndex += 1
        AudioManager.shared.play(.dialogueNext)
        if !encounter.talkedOnce {
            encounter.talkedOnce = true
            progress.count { $0.talks += 1 }
            grant(Reward(xp: 20))
        }
    }

    @discardableResult
    func castGoldenDetermination() -> Int {
        guard let encounter else { return 0 }
        let mult = 1 + 0.12 * Double(progress.power(.combat) - 1)
        let damage = Int(Double.random(in: 78...96) * mult)
        encounter.lastDamage = damage
        encounter.hp = max(0, encounter.hp - damage)
        progress.auraUses += 1
        grant(Reward(xp: 40))
        if encounter.isCalmed { calmed(encounter.kind) }
        return damage
    }

    private func calmed(_ kind: SpiritKind) {
        progress.spiritsCalmed += 1
        progress.count { $0.calmed += 1 }
        let before = progress.spiritBonds[kind] ?? 0
        progress.spiritBonds[kind] = before + 1
        grant(Reward(xp: 250), reason: "\(kind.name) calmed")
        if before + 1 == 3 {
            AudioManager.shared.play(.friendship)
            show(Toast(title: "\(kind.name) befriended", detail: "It can now fight at Lorna's side", symbol: "person.2.fill", tint: kind.glowColor))
        }
    }

    func endEncounter() {
        if let encounter, encounter.isCalmed {
            onSpiritCalmed?(encounter.spiritID)
        }
        encounter = nil
    }

    // MARK: - Battles

    func makeBattle(_ enemy: EnemyProfile, ally: Person? = nil) -> BattleSession {
        AudioManager.shared.play(enemy.isBoss ? .bossIntro : .battleStart)
        let companion = ally.map(Companion.person) ?? progress.activeCompanion
        return BattleSession(enemy: enemy, companion: companion, progress: progress)
    }

    /// A street spirit scaled to Lorna. The first levels are gentler while the moves are new.
    func streetSpirit(_ kind: SpiritKind) -> EnemyProfile {
        let base = EnemyProfile.spirit(kind, level: progress.level)
        switch progress.level {
        case ...1: return base.eased(hp: 0.7, attack: 0.65)
        case 2: return base.eased(hp: 0.82, attack: 0.8)
        default: return base
        }
    }

    /// Applies a finished battle to progress. Returns the reward granted (if any).
    @discardableResult
    func finishBattle(_ battle: BattleSession, encounter: EncounterSession? = nil) -> Reward? {
        for (item, n) in battle.itemsUsed { progress.add(item, -n) }
        progress.count {
            $0.heals += battle.healsUsed
            $0.teleports += battle.dodgesLanded
        }
        guard battle.outcome == .won else { return nil }
        progress.battlesWon += 1
        if battle.enemy.isBoss { progress.bossesDefeated += 1 }
        progress.count { $0.battlesWon += 1 }
        if case .person(let p) = battle.companion { progress.affinity[p, default: 0] += 15 }
        let reward = battle.reward
        grant(reward, reason: battle.enemy.isHuman ? "Victory" : "Spirit calmed in battle")
        if let encounter {
            encounter.calmedByBattle = true
            calmed(encounter.kind)
        }
        return reward
    }

    // MARK: - Story

    /// First launch: the prologue plays once, automatically.
    func presentIntroIfNeeded() {
        guard !progress.introSeen, !showIntro, storyRun == nil else { return }
        progress.introSeen = true
        introIsReplay = false
        showIntro = true
    }

    /// Replays the prologue from the Story sheet.
    func playIntro() {
        activeSheet = nil
        AudioManager.shared.play(.uiOpen)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.introIsReplay = true
            self?.showIntro = true
        }
    }

    /// Called when the prologue ends; a first-time player goes straight into Chapter 1.
    func finishIntro(beginStory: Bool) {
        showIntro = false
        guard beginStory, progress.storyChapter == 0 else { return }
        startChapter(Story.chapter1)
    }

    /// The next chapter to play, nil when the story is complete.
    var nextChapter: Chapter? {
        Story.chapters.first { $0.id == progress.storyChapter }
    }

    /// Where the next chapter picks up: the latest scene heading at or before the saved beat.
    var nextScene: (place: String, time: String)? {
        guard let chapter = nextChapter else { return nil }
        let limit = min(progress.storyBeat, chapter.beats.count - 1)
        for beat in chapter.beats[0...max(0, limit)].reversed() {
            if case .scene(let place, let time) = beat { return (place, time) }
        }
        return nil
    }

    /// The real-world echo of where the next chapter takes place.
    var storyEcho: StoryEcho? { nextScene.map { StoryEcho(place: $0.place) } }

    /// True when the next chapter features this friend (her model can wait for Lorna in the world).
    func nextChapterFeatures(_ person: Person) -> Bool {
        guard let chapter = nextChapter else { return false }
        return chapter.beats.contains { beat in
            if case .line(.person(let p), _) = beat { return p == person }
            return false
        }
    }

    /// Real place the player can walk to for a story-stop bonus before the next chapter.
    /// Prefers a place that echoes the chapter's own location (a café for Bar Stella).
    var storyStopCandidate: POIInfo? {
        if let id = storyStopID, let info = nearbyPOIs.first(where: { $0.id == id }) { return info }
        let pool = nearbyPOIs.filter { !visitedToday($0.poi) && $0.distance < 400 }
        if let echo = storyEcho, !echo.categories.isEmpty,
           let match = pool.filter({ echo.categories.contains($0.poi.category) }).min(by: { $0.distance < $1.distance }) {
            return match
        }
        return pool.min { $0.distance < $1.distance }
    }

    /// The place the golden story landmark stands on: the chosen story stop, else the suggestion.
    var storyLandmark: POIInfo? {
        guard nextChapter != nil else { return nil }
        if let id = storyStopID { return nearbyPOIs.first { $0.id == id } }
        return activeRoute == nil ? storyStopCandidate : nil
    }

    /// True when the candidate place genuinely matches the chapter's location type.
    func echoes(_ poi: PlacedPOI) -> Bool {
        storyEcho?.categories.contains(poi.category) ?? false
    }

    func walkToStoryStop(_ poi: PlacedPOI) {
        storyStopID = poi.id
        activeRoute = WalkRoute(stops: [poi])
        AudioManager.shared.play(.uiOpen)
        let detail = echoes(poi) && storyEcho != nil
            ? "Follow the golden light to \(poi.name)"
            : "Walk to \(poi.name) to play on"
        show(Toast(title: "Story stop set", detail: detail, symbol: "figure.walk", tint: Theme.gold))
    }

    func startChapter(_ chapter: Chapter) {
        let resume = progress.storyChapter == chapter.id ? progress.storyBeat : 0
        activeSheet = nil
        storyLaunching = true
        AudioManager.shared.play(.uiOpen)
        Task { @MainActor [weak self] in
            // The world camera pushes in on the story landmark or Giulia meanwhile.
            try? await Task.sleep(for: .milliseconds(650))
            self?.storyRun = StoryRun(chapter: chapter, index: min(resume, chapter.beats.count - 1))
            self?.storyLaunching = false
        }
    }

    func saveStoryPosition(_ run: StoryRun) {
        guard progress.storyChapter == run.chapter.id else { return }
        progress.storyBeat = run.index
    }

    func completeChapter(_ chapter: Chapter) {
        if progress.storyChapter == chapter.id {
            progress.storyChapter = chapter.id + 1
            progress.storyBeat = 0
            AudioManager.shared.play(.questComplete)
        }
    }

    func join(_ person: Person) {
        AudioManager.shared.play(.friendship)
        if progress.activeCompanion == nil { progress.activeCompanion = .person(person) }
        show(Toast(title: "\(person.shortName) joined", detail: person.skill?.name ?? person.role, symbol: "person.badge.plus", tint: person.tint))
    }

    // MARK: - Places & routes

    /// Called by the scene when Lorna is within range of a real place.
    func visit(_ poi: PlacedPOI) {
        let today = Calendar.dayKey(.now)
        if var place = progress.places[poi.id] {
            guard place.lastVisitDay != today else { return }
            place.lastVisitDay = today
            place.visits += 1
            progress.places[poi.id] = place
            progress.count { $0.poisVisited += 1 }
            AudioManager.shared.play(.reward)
            grant(Reward(xp: 60, items: [.espresso: 1]), reason: "Back at \(poi.name)")
        } else {
            progress.places[poi.id] = VisitedPlace(name: poi.name, category: poi.category, firstVisit: .now, lastVisitDay: today, visits: 1)
            progress.count { $0.poisVisited += 1 }
            AudioManager.shared.play(.discovery)
            grant(Reward(xp: 150, items: [.auraShard: 1]), reason: "Discovered \(poi.name)")
        }
        advanceRoute(visited: poi)
        if storyStopID == poi.id {
            storyStopID = nil
            if activeRoute?.stops.count == 1 { activeRoute = nil }
            grant(Reward(xp: 100), reason: "Story stop reached")
            if let chapter = nextChapter, encounter == nil, storyRun == nil { startChapter(chapter) }
        }
    }

    func visitedToday(_ poi: PlacedPOI) -> Bool {
        progress.places[poi.id]?.lastVisitDay == Calendar.dayKey(.now)
    }

    /// Chains up to 3 nearby places Lorna has not visited today, nearest-neighbour order.
    func startRoute() {
        var pool = nearbyPOIs.filter { !visitedToday($0.poi) && $0.distance < 900 }.map(\.poi)
        guard !pool.isEmpty, let first = nearbyPOIs.filter({ pool.map(\.id).contains($0.id) }).min(by: { $0.distance < $1.distance })?.poi else {
            show(Toast(title: "No route available", detail: "No unvisited places within 900 m yet", symbol: "map", tint: Theme.apricot))
            return
        }
        var stops = [first]
        pool.removeAll { $0.id == first.id }
        while stops.count < 3, let last = stops.last,
              let next = pool.min(by: { simd_distance($0.position, last.position) < simd_distance($1.position, last.position) }) {
            stops.append(next)
            pool.removeAll { $0.id == next.id }
        }
        activeRoute = WalkRoute(stops: stops)
        AudioManager.shared.play(.uiOpen)
    }

    private func advanceRoute(visited poi: PlacedPOI) {
        guard var route = activeRoute, route.current?.id == poi.id else { return }
        route.index += 1
        if route.current == nil {
            activeRoute = nil
            progress.routesCompleted += 1
            AudioManager.shared.play(.questComplete)
            grant(Reward(xp: 200 * route.stops.count, items: [.auraShard: route.stops.count, .gelato: 1]), reason: "Route complete")
        } else {
            activeRoute = route
        }
    }

    // MARK: - Missions, achievements, upgrades

    func claim(_ mission: Mission) {
        progress.rollPeriods()
        let counters = mission.weekly ? progress.weekly : progress.daily
        guard mission.isDone(counters), !counters.claimed.contains(mission.id) else { return }
        if mission.weekly { progress.weekly.claimed.insert(mission.id) } else { progress.daily.claimed.insert(mission.id) }
        AudioManager.shared.play(.questComplete)
        grant(mission.reward, reason: mission.title)
    }

    func claim(_ achievement: Achievement) {
        guard achievement.value(progress) >= achievement.target, !progress.achievementsClaimed.contains(achievement.id) else { return }
        progress.achievementsClaimed.insert(achievement.id)
        AudioManager.shared.play(.reward)
        grant(achievement.reward, reason: achievement.title, boosted: false)
    }

    func upgrade(_ power: Power) {
        let current = progress.power(power)
        let cost = Power.cost(toReach: current + 1)
        guard current < Power.maxLevel, progress.count(.auraShard) >= cost else { return }
        progress.add(.auraShard, -cost)
        progress.powers[power] = current + 1
        AudioManager.shared.play(.goldenActivate, volume: 0.7)
    }

    func addWalked(meters: Double) {
        progress.distanceMeters += meters
        progress.count { $0.walked += meters }
    }
}
