import SwiftUI
import UIKit

/// Exact design tokens and color palette matching PULSO Web (`tokens.css` and `show.css`)
/// Supports automatic dark and light theme switching via dynamic UIColors.
enum PulsoTheme {
    // Stage and Base Surfaces
    static let bg = Color(UIColor.dynamic(dark: 0x111111, light: 0xF3F4F6))
    static let panel = Color(UIColor.dynamic(dark: 0x1C1916, light: 0xFFFFFF))
    static let panel2 = Color(UIColor.dynamic(dark: 0x171412, light: 0xF9FAFB))
    static let cardBg = Color(UIColor.dynamic(dark: 0x1A1A1A, light: 0xFFFFFF))
    static let card = Color(UIColor.dynamic(dark: 0x1A1A1A, light: 0xFFFFFF))
    static let surface = Color(UIColor.dynamic(dark: 0x1C1916, light: 0xF8F9FA))
    static let raise = Color(UIColor.dynamic(dark: 0x272219, light: 0xEEEEF0))
    static let raiseHover = Color(UIColor.dynamic(dark: 0x332C23, light: 0xE2E4E8))
    static let navBtnBg = Color(UIColor.dynamic(dark: 0x1F1F1F, light: 0xE5E7EB))
    static let blackBox = Color(UIColor.dynamic(dark: 0x08090C, light: 0xE5E7EB))

    // Lines & Borders
    static let border = Color(UIColor.dynamic(dark: 0x2A2A2A, light: 0xE2E5E9))
    static let line = Color(UIColor.dynamic(dark: 0x2A241E, light: 0xE5E7EB))
    static let line2 = Color(UIColor.dynamic(dark: 0x38312A, light: 0xD1D5DB))

    // Typography Colors
    static let textLight = Color(UIColor.dynamic(dark: 0xF4F4F4, light: 0x111827))
    static let ink = Color(UIColor.dynamic(dark: 0xEDE7DD, light: 0x1F2937))
    static let ink2 = Color(UIColor.dynamic(dark: 0xC4BDB3, light: 0x4B5563))
    static let textDim = Color(UIColor.dynamic(dark: 0x888888, light: 0x6B7280))
    static let mut = Color(UIColor.dynamic(dark: 0x9C948A, light: 0x6B7280))
    static let dim = Color(UIColor.dynamic(dark: 0x5C554B, light: 0x9CA3AF))

    // Stage Accents
    static let amber = Color(UIColor.dynamic(dark: 0xF0A542, light: 0xD97706))
    static let amberDark = Color(UIColor.dynamic(dark: 0xE9A23B, light: 0xB45309))
    static let amberDim = Color(UIColor { trait in
        trait.userInterfaceStyle == .light ?
            UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 0.15) :
            UIColor(red: 240/255, green: 165/255, blue: 66/255, alpha: 0.15)
    })
    static let amberGlow = Color(UIColor { trait in
        trait.userInterfaceStyle == .light ?
            UIColor(red: 217/255, green: 119/255, blue: 6/255, alpha: 0.25) :
            UIColor(red: 240/255, green: 165/255, blue: 66/255, alpha: 0.40)
    })

    static let teal = Color(UIColor.dynamic(dark: 0x42CBAA, light: 0x0D9488))
    static let tealDim = Color(UIColor { trait in
        trait.userInterfaceStyle == .light ?
            UIColor(red: 13/255, green: 148/255, blue: 136/255, alpha: 0.15) :
            UIColor(red: 66/255, green: 203/255, blue: 170/255, alpha: 0.15)
    })
    static let red = Color(UIColor.dynamic(dark: 0xE4604E, light: 0xDC2626))
    static let green = Color(UIColor.dynamic(dark: 0x43B97C, light: 0x16A34A))
    static let blue = Color(UIColor.dynamic(dark: 0x3B82F6, light: 0x2563EB))
    static let purple = Color(UIColor.dynamic(dark: 0xA855F7, light: 0x9333EA))

    // Corner Radii
    static let radLg: CGFloat = 16
    static let radMd: CGFloat = 10
    static let radSm: CGFloat = 6
}

extension UIColor {
    static func dynamic(dark: UInt, light: UInt, alpha: CGFloat = 1.0) -> UIColor {
        return UIColor { traitCollection in
            let hex = traitCollection.userInterfaceStyle == .light ? light : dark
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: alpha)
        }
    }
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
        let clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if clean.count == 6 {
            var val: UInt64 = 0
            Scanner(string: clean).scanHexInt64(&val)
            self.init(hex: UInt(val))
        } else {
            self = PulsoTheme.textDim
        }
    }
}
