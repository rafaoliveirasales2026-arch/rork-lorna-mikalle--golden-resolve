import RealityKit
import SwiftUI

/// Root screen: the real-street 3D world with Lorna, wandering spirits and the HUD.
struct ExploreView: View {
    @Environment(GameState.self) private var game
    @Environment(LocationService.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = ExplorationScene()
    @State private var dragStart: (yaw: Float, pitch: Float)?
    @State private var zoomStart: Float?

    var body: some View {
        @Bindable var game = game
        ZStack {
            GeometryReader { geo in
                RealityView { content in
                    await scene.setup(in: &content, game: game, location: location)
                }
                .onAppear { scene.viewSize = geo.size }
                .onChange(of: geo.size) { _, size in scene.viewSize = size }
                .gesture(orbitGesture.simultaneously(with: zoomGesture))
            }
            .ignoresSafeArea()
            .background(Theme.ink)

            ExploreHUD()

            if location.access != .granted {
                LocationGateView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: location.access)
        .onAppear {
            location.onDistanceWalked = { meters in game.addWalked(meters: meters) }
            location.start()
            AudioManager.shared.startMusic()
            game.presentIntroIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            // Battery: no GPS or audio while the app is not on screen.
            switch phase {
            case .active:
                location.start()
                AudioManager.shared.resume()
            case .background:
                location.stop()
                AudioManager.shared.suspend()
            default:
                break
            }
        }
        .fullScreenCover(item: $game.encounter) { session in
            EncounterFlowView(session: session)
        }
        .fullScreenCover(item: $game.storyRun) { run in
            StoryPlayerView(run: run)
        }
        .fullScreenCover(isPresented: $game.showIntro) {
            IntroCinematicView()
        }
        .sheet(item: $game.activeSheet) { sheet in
            Group {
                switch sheet {
                case .profile: ProfileView()
                case .story: StoryListView()
                case .missions: MissionsView()
                case .team: TeamView()
                case .bag: BagView()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? (scene.cameraYaw, scene.cameraPitch)
                if dragStart == nil {
                    dragStart = start
                    game.followHeading = false
                }
                scene.cameraYaw = start.yaw - Float(value.translation.width) * 0.008
                let pitch = start.pitch + Float(value.translation.height) * 0.004
                scene.cameraPitch = min(max(pitch, 20 * .pi / 180), 65 * .pi / 180)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? scene.cameraDistance
                if zoomStart == nil { zoomStart = start }
                scene.cameraDistance = min(max(start / Float(value.magnification), 4), 40)
            }
            .onEnded { _ in zoomStart = nil }
    }
}
