import SwiftUI

struct ExploreHUD: View {
    @Environment(GameState.self) private var game
    @Environment(LocationService.self) private var location
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Group {
                poiLabels
                spiritLabels
                storyLabels
                occlusionMarker

                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    bottomCluster
                }
                .padding(.horizontal, sizeClass == .regular ? 32 : 20)
                .padding(.bottom, 4)
            }
            // The HUD steps aside while the camera pushes in for a story moment.
            .opacity(game.storyLaunching ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: game.storyLaunching)

            toastStack
        }
    }

    // MARK: - Toasts

    private var toastStack: some View {
        VStack(spacing: 8) {
            ForEach(game.toasts) { toast in
                HStack(spacing: 12) {
                    Image(systemName: toast.symbol)
                        .font(.title3)
                        .foregroundStyle(toast.tint)
                        .symbolEffect(.bounce, value: toast.id)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toast.title)
                            .font(.headline)
                            .foregroundStyle(Theme.cream)
                            .lineLimit(1)
                        if !toast.detail.isEmpty {
                            Text(toast.detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.creamDim)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: 420)
                .hudGlass(in: Capsule())
                .overlay(Capsule().strokeBorder(toast.tint.opacity(0.5), lineWidth: 0.8))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: game.toasts)
        .allowsHitTesting(false)
        .sensoryFeedback(.success, trigger: game.toasts.count) { old, new in new > old }
    }

    // MARK: - Places & Lorna marker

    private var poiLabels: some View {
        ZStack {
            ForEach(game.nearbyPOIs) { info in
                if let point = game.poiLabelPositions[info.id], !hasLandmarkLabel(for: info.id) {
                    POILabel(info: info,
                             isTarget: game.activeRoute?.current?.id == info.id,
                             visited: game.visitedToday(info.poi))
                        .position(x: point.x, y: point.y - 16)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func hasLandmarkLabel(for id: Int) -> Bool {
        game.storyLandmark?.id == id && game.storyMarkers.contains { $0.kind == .landmark }
    }

    // MARK: - Story in the world

    private var storyLabels: some View {
        ZStack {
            ForEach(game.storyMarkers) { marker in
                switch marker.kind {
                case .landmark:
                    if let info = game.storyLandmark, let chapter = game.nextChapter {
                        StoryLandmarkLabel(info: info, chapter: chapter,
                                           echo: game.echoes(info.poi) ? game.storyEcho?.place : nil,
                                           chosen: game.storyStopID == info.id) {
                            if game.storyStopID != info.id { game.walkToStoryStop(info.poi) }
                        }
                        .position(x: marker.point.x, y: marker.point.y - 26)
                    }
                case .giulia:
                    if let chapter = game.nextChapter {
                        GiuliaWorldLabel(chapter: chapter, resume: game.progress.storyBeat > 0) {
                            game.startChapter(chapter)
                        }
                        .position(x: marker.point.x, y: marker.point.y - 24)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var occlusionMarker: some View {
        if let point = game.occludedMarker {
            ZStack {
                Circle()
                    .fill(Theme.gold.opacity(0.25))
                    .frame(width: 54, height: 54)
                Image("LornaPortrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 2))
            }
            .shadow(color: Theme.gold.opacity(0.7), radius: 10)
            .position(point)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityLabel("Lorna is behind a building")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                GameWordmark(compact: sizeClass != .regular)
                Text("Explore")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    .accessibilityAddTraits(.isHeader)
                LocationPill()
                if let status = worldStatusText {
                    Label(status.text, systemImage: status.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .hudGlass(in: Capsule())
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 10) {
                Spacer().frame(height: sizeClass == .regular ? 96 : 84)
                HStack(spacing: 10) {
                    RoundHUDButton(
                        systemImage: game.followHeading ? "location.north.line.fill" : "location.north.line",
                        label: game.followHeading ? "Stop following heading" : "Follow heading",
                        isActive: game.followHeading
                    ) {
                        game.followHeading.toggle()
                    }
                    RoundHUDButton(systemImage: "camera.metering.center.weighted", label: "Reset camera") {
                        game.cameraResetToken += 1
                    }
                }
                AtmosphereMenu()
            }
        }
        .animation(.easeInOut, value: worldStatusText?.text)
    }

    private var worldStatusText: (text: String, icon: String)? {
        let s = game.worldStatus
        switch s.phase {
        case .waitingForGPS:
            return location.access == .granted ? ("Finding your position…", "location.magnifyingglass") : nil
        case _ where s.locating && s.hasWorld:
            return ("Saved streets · finding your position…", "location.magnifyingglass")
        case .loading:
            return s.previewReady && s.loaded == 0
                ? ("Adding street detail…", "building.2")
                : ("Loading map \(s.loaded)/\(s.total)", "building.2")
        case .offline:
            return s.hasWorld
                ? ("Offline · saved streets", "wifi.slash")
                : ("Offline · map will load when you reconnect", "wifi.slash")
        case .failed(let message):
            return ("\(message) · retrying", "exclamationmark.arrow.triangle.2.circlepath")
        case .ready:
            return s.fromCache && s.loaded < s.total ? ("Saved map · refreshing", "clock.arrow.circlepath") : nil
        }
    }

    // MARK: - Spirit labels

    private var spiritLabels: some View {
        ZStack {
            ForEach(game.spirits) { spirit in
                if let point = game.labelPositions[spirit.id] {
                    SpiritLabel(spirit: spirit, inRange: spirit.distance <= GameState.encounterRange)
                        .position(x: point.x, y: point.y - 18)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Bottom

    private var bottomCluster: some View {
        VStack(spacing: 12) {
            objectiveCard
            routeBar
            HStack(alignment: .bottom) {
                SpeedPill()
                Spacer()
                AvatarBadge(level: game.progress.level) { open(.profile) }
            }
            approachButton
                .frame(maxWidth: sizeClass == .regular ? 580 : .infinity)
                .frame(maxWidth: .infinity)
            dock
                .frame(maxWidth: .infinity)
        }
    }

    private func open(_ sheet: GameSheet) {
        AudioManager.shared.play(.uiOpen, volume: 0.7)
        game.activeSheet = sheet
    }

    // MARK: - Dock

    private var dock: some View {
        let readyMissions = readyMissionCount
        return HStack(spacing: 4) {
            DockButton(title: "Story", symbol: "book.closed.fill", badge: nil) { open(.story) }
            DockButton(title: "Missions", symbol: "checklist", badge: readyMissions > 0 ? "\(readyMissions)" : nil) { open(.missions) }
            DockButton(title: "Team", symbol: "person.2.fill", badge: nil) { open(.team) }
            DockButton(title: "Bag", symbol: "bag.fill", badge: nil) { open(.bag) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 440)
        .hudGlass(in: Capsule())
    }

    private var readyMissionCount: Int {
        let p = game.progress
        let daily = Mission.daily(for: Calendar.dayKey(.now)).filter {
            p.daily.key == Calendar.dayKey(.now) && $0.isDone(p.daily) && !p.daily.claimed.contains($0.id)
        }
        let weekly = Mission.weekly(for: Calendar.weekKey(.now)).filter {
            p.weekly.key == Calendar.weekKey(.now) && $0.isDone(p.weekly) && !p.weekly.claimed.contains($0.id)
        }
        let achievements = Achievement.all.filter { $0.value(p) >= $0.target && !p.achievementsClaimed.contains($0.id) }
        return daily.count + weekly.count + achievements.count
    }

    // MARK: - Story objective

    /// The main story, always one tap away. Optionally turns a nearby real place into a story stop.
    @ViewBuilder
    private var objectiveCard: some View {
        if let chapter = game.nextChapter {
            let scene = game.nextScene
            let stop = game.activeRoute == nil ? game.storyStopCandidate : nil
            HStack(spacing: 12) {
                Image(systemName: chapter.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.goldGradient))
                    .shadow(color: Theme.gold.opacity(0.5), radius: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(chapter.number.uppercased()) · \(game.progress.storyBeat > 0 ? "CONTINUE" : "NEXT")")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.gold)
                    Text(chapter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    if let stop, game.echoes(stop.poi), let scene {
                        Text("\(scene.place) · echo at \(stop.poi.name)")
                            .font(.caption)
                            .foregroundStyle(Theme.creamDim)
                            .lineLimit(1)
                    } else if let scene {
                        Text(scene.place)
                            .font(.caption)
                            .foregroundStyle(Theme.creamDim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let stop {
                    Button {
                        game.walkToStoryStop(stop.poi)
                    } label: {
                        Image(systemName: "figure.walk")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.cream)
                            .frame(width: 38, height: 38)
                            .background(Circle().strokeBorder(Theme.blueBright.opacity(0.8), lineWidth: 1.2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Walk to \(stop.poi.name) first, \(Int(stop.distance)) metres, for a story bonus")
                }
                Button {
                    game.startChapter(chapter)
                } label: {
                    Text(game.progress.storyBeat > 0 ? "Continue" : "Play")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(Capsule().fill(Theme.goldGradient))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Play \(chapter.number), \(chapter.english), here")
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: 440)
            .hudGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Button {
                game.playIntro()
            } label: {
                Label("Story complete · Watch the prologue", systemImage: "crown.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .labelStyle(TintedIconLabelStyle(tint: Theme.gold))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
            }
            .buttonStyle(PressableStyle())
            .hudGlass(in: Capsule(), interactive: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Route

    @ViewBuilder
    private var routeBar: some View {
        if let route = game.activeRoute, let stop = route.current {
            let info = game.nearbyPOIs.first { $0.id == stop.id }
            HStack(spacing: 12) {
                Image(systemName: stop.category.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.gold.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.storyStopID == stop.id ? "Story stop · \(game.nextChapter?.number ?? "Next")" : "Stop \(route.index + 1) of \(route.stops.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                    Text(stop.name)
                        .font(.headline)
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    if let info {
                        Text("\(info.bearing.compassName) · \(Int(info.distance)) m")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.creamDim)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    AudioManager.shared.play(.uiTap)
                    game.activeRoute = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End route")
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: 440)
            .hudGlass(in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if game.nearbyPOIs.contains(where: { !game.visitedToday($0.poi) && $0.distance < 900 }) {
            Button {
                game.startRoute()
            } label: {
                Label("Plan a walk · \(min(3, game.nearbyPOIs.filter { !game.visitedToday($0.poi) && $0.distance < 900 }.count)) real places", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .labelStyle(TintedIconLabelStyle(tint: Theme.gold))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
            }
            .buttonStyle(PressableStyle())
            .hudGlass(in: Capsule(), interactive: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    private var approachButton: some View {
        let target = game.nearestInRange
        return Button {
            if let target { game.approach(target) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: target == nil ? "sparkle.magnifyingglass" : "sparkles")
                    .symbolEffect(.pulse, options: .repeating, isActive: target != nil)
                Text(approachTitle(target))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(GoldButtonStyle())
        .disabled(target == nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: target?.id) { old, new in old == nil && new != nil }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: target?.id)
    }

    private func approachTitle(_ target: SpiritInfo?) -> String {
        if let target { return "Approach \(target.kind.name)" }
        if let nearest = game.nearest { return "Walk closer · \(nearest.kind.name) \(Int(nearest.distance)) m" }
        return "Sensing spirits…"
    }
}

// MARK: - Pieces

private struct LocationPill: View {
    @Environment(LocationService.self) private var location

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(location.hasFix ? Theme.success : Theme.apricot)
                .frame(width: 12, height: 12)
                .shadow(color: (location.hasFix ? Theme.success : Theme.apricot).opacity(0.7), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(location.streetName ?? (location.hasFix ? "Your street" : "Locating…"))
                    .font(.headline)
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.creamDim)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 22)
        .padding(.vertical, 10)
        .frame(minWidth: 200, alignment: .leading)
        .hudGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let heading = location.displayHeading?.compassName ?? "—"
        guard location.hasFix else { return "Waiting for GPS" }
        if !location.signalReliable { return "Weak GPS · holding position" }
        return "\(heading) · ±\(Int(location.accuracy.rounded())) m"
    }
}

private struct SpiritLabel: View {
    let spirit: SpiritInfo
    let inRange: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(spirit.kind.glowColor)
                Text("\(spirit.kind.name) · \(Int(spirit.distance)) m")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.cream)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .hudGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(inRange ? Theme.gold : .clear, lineWidth: 1))
            Triangle()
                .fill(Theme.ink.opacity(0.6))
                .frame(width: 10, height: 6)
        }
        .fixedSize()
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct SpeedPill: View {
    @Environment(LocationService.self) private var location

    var body: some View {
        let speed = location.isMoving ? location.speed : 0
        let kmh = speed * 3.6
        let state: (String, String) = !location.isMoving || speed < 0.35 ? ("Standing", "figure.stand") : speed < 2.4 ? ("Walking", "figure.walk") : ("Running", "figure.run")
        HStack(spacing: 12) {
            Image(systemName: state.1)
                .font(.title2)
                .foregroundStyle(Theme.cream)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%.1f km/h", kmh))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText(value: kmh))
                Text(state.0)
                    .font(.subheadline)
                    .foregroundStyle(Theme.creamDim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hudGlass(in: Capsule())
        .animation(.snappy, value: state.0)
        .accessibilityElement(children: .combine)
    }
}

private struct AvatarBadge: View {
    let level: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                Image("LornaPortrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .background(LinearGradient(colors: [Theme.apricot, Theme.plum], startPoint: .top, endPoint: .bottom))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.cream.opacity(0.9), lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                Text("Lv \(level)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.blue))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                    .offset(y: 10)
            }
            .padding(.bottom, 10)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Lorna's profile, level \(level)")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct DockButton: View {
    let title: String
    let symbol: String
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .overlay(alignment: .topTrailing) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Capsule().fill(Theme.gold))
                                .offset(x: 12, y: -8)
                        }
                    }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.creamDim)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(badge.map { "\(title), \($0) ready to claim" } ?? title)
    }
}

/// The story landmark's label, pinned above the shrine: why you are going there.
private struct StoryLandmarkLabel: View {
    let info: POIInfo
    let chapter: Chapter
    let echo: String?
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: chapter.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.goldGradient))
                VStack(alignment: .leading, spacing: 0) {
                    Text(chosen ? "\(chapter.number.uppercased()) · STORY STOP" : "\(chapter.number.uppercased()) · TAP TO SET")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.gold)
                    Text(echo.map { "Echo of \($0)" } ?? info.poi.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text(echo == nil ? "\(Int(info.distance)) m" : "\(info.poi.name) · \(Int(info.distance)) m")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.creamDim)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: 230)
            .hudGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.gold.opacity(chosen ? 0.9 : 0.45), lineWidth: 1))
            .shadow(color: Theme.gold.opacity(chosen ? 0.45 : 0.2), radius: 10)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(PressableStyle())
        .allowsHitTesting(!chosen)
        .accessibilityLabel(chosen
            ? "Story stop for \(chapter.number) at \(info.poi.name), \(Int(info.distance)) metres"
            : "Set \(info.poi.name) as the story stop for \(chapter.number)")
    }
}

/// Giulia waiting in the street: tap to play the chapter with her, right where you stand.
private struct GiuliaWorldLabel: View {
    let chapter: Chapter
    let resume: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(Person.giulia.portrait)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Person.giulia.tint, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Giulia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                    Text("\(resume ? "Continue" : "Play") \(chapter.number)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.goldGradient))
            }
            .padding(.leading, 4)
            .padding(.trailing, 5)
            .padding(.vertical, 4)
            .hudGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(Person.giulia.tint.opacity(0.7), lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Giulia is here. \(resume ? "Continue" : "Play") \(chapter.number), \(chapter.english)")
    }
}

private struct POILabel: View {
    let info: POIInfo
    let isTarget: Bool
    let visited: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: visited ? "checkmark.circle.fill" : info.poi.category.symbol)
                .font(.caption2)
                .foregroundStyle(isTarget ? Theme.gold : (visited ? Theme.success : Theme.apricot))
            Text(info.poi.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
            Text("\(Int(info.distance)) m")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.creamDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: 190)
        .hudGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(isTarget ? Theme.gold : .clear, lineWidth: 1))
        .opacity(visited && !isTarget ? 0.7 : 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AtmosphereMenu: View {
    @Environment(GameState.self) private var game

    var body: some View {
        Menu {
            Picker("Lighting", selection: Binding(
                get: { game.lightingOverride?.rawValue ?? "auto" },
                set: { game.lightingOverride = LightingPreset(rawValue: $0) }
            )) {
                Label("Real sun · \(game.autoPreset.title)", systemImage: "clock").tag("auto")
                ForEach(LightingPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.symbol).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)
            Picker("Weather", selection: Binding(
                get: { game.weatherOverride?.rawValue ?? "live" },
                set: { game.weatherOverride = WeatherCondition(rawValue: $0) }
            )) {
                Label(liveTitle, systemImage: "antenna.radiowaves.left.and.right").tag("live")
                ForEach(WeatherCondition.allCases) { w in
                    Label(w.title, systemImage: w.symbol).tag(w.rawValue)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: game.activeWeather == .rain ? WeatherCondition.rain.symbol : game.activePreset.symbol)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(Theme.cream)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .hudGlass(in: Circle(), interactive: true)
        .accessibilityLabel("Lighting and weather")
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var liveTitle: String {
        if let live = game.liveWeather { return "Live · \(live.summary)" }
        return "Live weather"
    }
}
