import SwiftUI

// MARK: - Glass surfaces

extension View {
    /// Dark plum-tinted Liquid Glass on iOS 26, translucent material before.
    @ViewBuilder
    func hudGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                interactive
                    ? .regular.tint(Theme.ink.opacity(0.35)).interactive()
                    : .regular.tint(Theme.ink.opacity(0.35)),
                in: shape
            )
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(Theme.ink.opacity(0.35), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    /// Opaque-ish panel used for content cards (name plates, dialogue, stats).
    func panelSurface(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.ink.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}

// MARK: - Buttons

struct GoldButtonStyle: ButtonStyle {
    var height: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        GoldButtonBody(configuration: configuration, height: height)
    }

    private struct GoldButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.title3.weight(.semibold))
                .foregroundStyle(isEnabled ? Theme.cream : Theme.creamDim)
                .frame(maxWidth: .infinity, minHeight: height)
                .padding(.horizontal, 20)
                .background {
                    Capsule()
                        .fill(isEnabled ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.ink.opacity(0.6)))
                        .overlay(
                            Capsule().strokeBorder(
                                isEnabled ? Theme.goldLight.opacity(0.8) : Color.white.opacity(0.15),
                                lineWidth: 1
                            )
                        )
                        .shadow(color: isEnabled ? Theme.gold.opacity(0.45) : .clear, radius: 14, y: 4)
                }
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .brightness(configuration.isPressed ? -0.05 : 0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

struct BlueOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.cream)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Theme.ink.opacity(0.7)))
            .overlay(Capsule().strokeBorder(Theme.blueBright.opacity(0.85), lineWidth: 1.2))
            .shadow(color: Theme.blue.opacity(0.35), radius: 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Circular glass HUD button (compass, camera reset, close, back).
struct RoundHUDButton: View {
    let systemImage: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? Theme.gold : Theme.cream)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hudGlass(in: Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

// MARK: - Wordmark & ornaments

struct GameWordmark: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lorna Mikalle —")
            HStack(spacing: 6) {
                Text("La Determinazione d'Oro")
                DiamondRule()
                    .frame(width: compact ? 28 : 44)
            }
        }
        .font(.system(size: compact ? 14 : 17, weight: .heavy).italic())
        .foregroundStyle(
            LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom)
        )
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lorna Mikalle, La Determinazione d'Oro")
    }
}

/// Thin gold hairline ending in a small diamond — the anime UI flourish.
struct DiamondRule: View {
    var color: Color = Theme.gold

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(height: 1)
            Rectangle()
                .stroke(color, lineWidth: 1)
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(45))
        }
        .frame(height: 10)
    }
}

struct HPBar: View {
    let value: Double
    let maxValue: Double
    var tint: Color = Theme.blueBright

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, value / max(maxValue, 1)))))
                    .shadow(color: tint.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
        .accessibilityElement()
        .accessibilityLabel("Health")
        .accessibilityValue("\(Int(value)) of \(Int(maxValue))")
    }
}
