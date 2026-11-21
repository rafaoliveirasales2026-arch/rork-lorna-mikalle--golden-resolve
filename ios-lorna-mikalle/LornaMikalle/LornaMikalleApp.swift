import SwiftUI

@main
struct LornaMikalleApp: App {
    @State private var game = GameState()
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(game)
                .environment(location)
                .task { await LornaAssets.shared.load() }
        }
    }
}
