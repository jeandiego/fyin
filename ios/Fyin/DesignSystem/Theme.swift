import SwiftUI

// Tokens "q/*" do Fyin.pen.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    static let qBg = Color(hex: 0xFFFFFF)
    static let qInk = Color(hex: 0x161616)
    static let qCard = Color(hex: 0xF3F3F2)
    static let qText2 = Color(hex: 0x5F5F5F)
    static let qText3 = Color(hex: 0x737373)
    static let qGhost = Color(hex: 0xB5B5B5)
    static let qAccent = Color(hex: 0xD4F55A)
    static let qOk = Color(hex: 0x4E6B4A)
    static let qOver = Color(hex: 0xF0735A)
    static let qOverInk = Color(hex: 0xB5462F)
    static let qGlowLime = Color(hex: 0xB4E02A)
    static let qHairline = Color(hex: 0x0E0D0D, alpha: 0.08)
}

extension Font {
    static func urbanist(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom(urbanistName(weight), size: size)
    }

    static func urbanistFixed(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom(urbanistName(weight), fixedSize: size)
    }

    private static func urbanistName(_ weight: Font.Weight) -> String {
        switch weight {
        case .light: "Urbanist-Light"
        case .regular: "Urbanist-Regular"
        case .semibold: "Urbanist-SemiBold"
        default: "Urbanist-Medium"
        }
    }
}

// Frame "13 · Movimento e feedback".
enum Motion {
    static let instant = 0.10
    static let quick = 0.16
    static let base = 0.24
    static let considered = 0.32
    static let screen = 0.40

    static func standard(_ duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
    static func enter(_ duration: Double) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }
}
