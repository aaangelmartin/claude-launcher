import SwiftUI

/// a colour from claude code's dark theme, as rgb 0...255
struct RGB: Equatable, Sendable {
    let r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
}

/// claude code's dark theme colours, read from the claude binary's theme table
enum CC {
    static let success = RGB(78, 186, 101)
    static let warning = RGB(255, 193, 7)
    static let error = RGB(255, 107, 128)
}

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255) }
}
