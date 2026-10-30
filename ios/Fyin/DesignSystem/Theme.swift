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
    static let qWarn = Color(hex: 0xF4B740)
    static let qAttnInk = Color(hex: 0x9A4A12)
    static let qAccentSoft = Color(hex: 0xEEF9C4)
    static let qLine = Color(hex: 0xE7E5E0)
    static let qSoft = Color(hex: 0xE9E9E8)
    static let qOkInk = Color(hex: 0x3E5A3A)
    static let qOkTint = Color(hex: 0xD6E6CF)
    static let qAttnTint = Color(hex: 0xFDDCC0)
    static let qInfoInk = Color(hex: 0x2E4A80)
    static let qInfoTint = Color(hex: 0xD3DFF7)
    static let qGlowLime = Color(hex: 0xB4E02A)
    static let qHairline = Color(hex: 0x0E0D0D, alpha: 0.08)
    static let qScrim = Color(hex: 0x0E0D0D, alpha: 0.35)
    static let qOnDarkLine = Color.white.opacity(0.12)
    static let qOnDark2 = Color.white.opacity(0.55)
    static let qOnDark3 = Color.white.opacity(0.3)
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
    /// Mola sem overshoot (o quadro 13 proíbe bounce); retoma do ponto atual se interrompida.
    static func spring(_ duration: Double) -> Animation { .spring(duration: duration, bounce: 0) }
}
