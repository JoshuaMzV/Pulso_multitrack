import SwiftUI

/// Exact design tokens and color palette matching PULSO Web (`tokens.css` and `show.css`)
enum PulsoTheme {
    // Stage and Base Surfaces
    static let bg = Color(hex: 0x111111)
    static let panel = Color(hex: 0x1C1916)
    static let panel2 = Color(hex: 0x171412)
    static let cardBg = Color(hex: 0x1A1A1A)
    static let raise = Color(hex: 0x272219)
    static let raiseHover = Color(hex: 0x332C23)
    static let navBtnBg = Color(hex: 0x1F1F1F)
    static let blackBox = Color(hex: 0x08090C)

    // Lines & Borders
    static let border = Color(hex: 0x2A2A2A)
    static let line = Color(hex: 0x2A241E)
    static let line2 = Color(hex: 0x38312A)

    // Typography Colors
    static let textLight = Color(hex: 0xF4F4F4)
    static let ink = Color(hex: 0xEDE7DD)
    static let ink2 = Color(hex: 0xC4BDB3)
    static let textDim = Color(hex: 0x888888)
    static let mut = Color(hex: 0x9C948A)
    static let dim = Color(hex: 0x5C554B)

    // Stage Accents
    static let amber = Color(hex: 0xF0A542)
    static let amberDark = Color(hex: 0xE9A23B)
    static let amberDim = Color(red: 240/255, green: 165/255, blue: 66/255, opacity: 0.15)
    static let amberGlow = Color(red: 240/255, green: 165/255, blue: 66/255, opacity: 0.40)

    static let teal = Color(hex: 0x42CBAA)
    static let tealDim = Color(red: 66/255, green: 203/255, blue: 170/255, opacity: 0.15)
    static let red = Color(hex: 0xE4604E)
    static let green = Color(hex: 0x43B97C)
    static let blue = Color(hex: 0x3B82F6)
    static let purple = Color(hex: 0xA855F7)

    // Corner Radii
    static let radLg: CGFloat = 16
    static let radMd: CGFloat = 10
    static let radSm: CGFloat = 6
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    init(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if clean.count == 6 {
            var val: UInt64 = 0
            Scanner(string: clean).scanHexInt64(&val)
            self.init(hex: UInt(val))
        } else {
            self = PulsoTheme.textDim
        }
    }
}
