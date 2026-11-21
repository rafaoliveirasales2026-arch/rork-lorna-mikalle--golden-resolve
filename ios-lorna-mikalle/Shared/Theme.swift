import SwiftUI
import UIKit

/// The game's shared visual tokens: golden-hour plum ink with gold and deep blue accents.
enum Theme {
    static let ink = Color(hex: 0x2A1E2E)
    static let plum = Color(hex: 0x4A3348)
    static let apricot = Color(hex: 0xF2A541)
    static let gold = Color(hex: 0xE8B02E)
    static let goldLight = Color(hex: 0xF7D774)
    static let goldDeep = Color(hex: 0xC98A12)
    static let blue = Color(hex: 0x3B7BD4)
    static let blueBright = Color(hex: 0x4FA3F7)
    static let spirit = Color(hex: 0x9FD8F5)
    static let cream = Color(hex: 0xFFF4E0)
    static let creamDim = Color(hex: 0xFFF4E0).opacity(0.7)
    static let success = Color(hex: 0x4CD964)

    static let goldGradient = LinearGradient(
        colors: [Color(hex: 0xF7CF4E), Color(hex: 0xE8B02E), Color(hex: 0xC98A12)],
        startPoint: .top, endPoint: .bottom
    )

    static let duskBackdrop = LinearGradient(
        colors: [Color(hex: 0x4A3348), Color(hex: 0x2A1E2E)],
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
