import SwiftUI

/// The App Clip: a lightweight taste of Lorna Mikalle — meet Lorna, take a short walk around a
/// piazza, find a spirit — with a clear path to the full GPS game. It shares Lorna's model,
/// animation player and visual identity with the full app, and nothing else.
@main
struct LornaMikalleClipApp: App {
    @State private var invocation = ClipInvocation()

    var body: some Scene {
        WindowGroup {
            ClipRootView()
                .environment(invocation)
                // App Clips launch from an invocation URL (App Clip Code, QR, NFC, Safari banner,
                // Messages, Maps, or Apple's default appclip.apple.com link).
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    invocation.handle(activity.webpageURL)
                }
                .task { await LornaAssets.shared.load() }
                .preferredColorScheme(.dark)
        }
    }
}
