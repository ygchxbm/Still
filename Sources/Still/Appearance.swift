import SwiftUI

extension Palette {
    func color(_ slot: Int) -> Color { let h = hex[slot % 5]; return Color(red: Double((h >> 16) & 255)/255, green: Double((h >> 8) & 255)/255, blue: Double(h & 255)/255) }
    func tone(_ slot: Int, dark: Bool) -> Color {
        dark ? mixed(slot, amount: 0.55, base: 0xffffff) : color(slot)
    }
    // Match CSS color-mix(in srgb, tone amount%, base).
    func mixed(_ slot: Int, amount: Double, base: UInt32) -> Color {
        let h = hex[slot % 5]
        func channel(_ shift: UInt32) -> Double {
            (Double((h >> shift) & 255) * amount + Double((base >> shift) & 255) * (1 - amount)) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }
    static var muted: Color { Color(.sRGB, red: 97/255, green: 123/255, blue: 124/255, opacity: 1) }
}

extension AppearanceMode {
    var title: String { switch self { case .light: "白天"; case .dark: "黑夜"; case .auto: "自动" } }
    var icon: String { switch self { case .light: "sun.max"; case .dark: "moon"; case .auto: "circle.lefthalf.filled" } }
    var appearance: NSAppearance? {
        switch self { case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua); case .auto: nil }
    }
}
