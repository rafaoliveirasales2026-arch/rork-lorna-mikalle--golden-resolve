import Foundation
import Observation

/// Reads the URL that launched the App Clip.
///
/// Supported query parameters (all optional), on Apple's default link
/// `https://appclip.apple.com/id?p=app.rork.xxvigeuefbyxvw78vqigs.InstantMikalle` or on a custom
/// domain's advanced experience URL:
/// - `place`: a name to greet the player with, e.g. `?place=Piazza%20Navona`
/// - `spirit`: the spirit name shown in the demo, e.g. `?spirit=Wandering%20Lantern`
@Observable
final class ClipInvocation {
    private(set) var url: URL?
    private(set) var placeName: String?
    private(set) var spiritName = "Wandering Spirit"

    func handle(_ url: URL?) {
        guard let url else { return }
        self.url = url
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return String(raw.prefix(40))
        }
        placeName = value("place")
        if let spirit = value("spirit") { spiritName = spirit }
    }
}
