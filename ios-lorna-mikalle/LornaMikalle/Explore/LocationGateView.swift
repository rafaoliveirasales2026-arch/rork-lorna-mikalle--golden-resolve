import SwiftUI
import UIKit

/// Explains why GPS is needed; separate states for "not asked yet" and "denied/restricted".
struct LocationGateView: View {
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.duskBackdrop.ignoresSafeArea()
            RadialGradient(colors: [Theme.apricot.opacity(0.45), .clear], center: .top, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                Image("LornaPortrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .background(LinearGradient(colors: [Theme.apricot, Theme.plum], startPoint: .top, endPoint: .bottom))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 2))
                    .shadow(color: Theme.gold.opacity(0.4), radius: 18)

                GameWordmark()

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Theme.creamDim)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 12) {
                    reason("figure.walk", "Lorna moves only when you really walk")
                    reason("person.2.fill", "Spirits appear on the streets around you")
                    reason("lock.fill", "Your location stays on this device")
                }
                .padding(18)
                .panelSurface()

                Spacer()

                Button(action: primaryAction) {
                    Label(buttonTitle, systemImage: isBlocked ? "gear" : "location.fill")
                }
                .buttonStyle(GoldButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
    }

    private var isBlocked: Bool { location.access == .denied || location.access == .restricted }

    private var title: String {
        switch location.access {
        case .denied: "Location is turned off"
        case .restricted: "Location is restricted"
        default: "Walk your real streets"
        }
    }

    private var message: String {
        switch location.access {
        case .denied: "Lorna can't follow you without your location. Turn it on for this app in Settings to keep exploring."
        case .restricted: "Location access is limited on this device, so exploration can't start. Check Screen Time or device management settings."
        default: "This game uses your GPS position to move Lorna through a 3D version of your neighbourhood."
        }
    }

    private var buttonTitle: String { isBlocked ? "Open Settings" : "Allow Location" }

    private func primaryAction() {
        if isBlocked {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } else {
            location.requestPermission()
        }
    }

    private func reason(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.cream)
        }
    }
}
