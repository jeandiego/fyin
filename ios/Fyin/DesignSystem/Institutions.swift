import SwiftUI

// Identidade visual de cada instituição no avatar. Chave: nome do conector da Pluggy, em minúsculas.
// Para padronizar com a marca real: ajuste a cor aqui ou aponte `logo` para uma imagem do Assets (ela substitui as iniciais).
enum Institutions {
    struct Style {
        var color: Color
        var initials: String
        var ink: Color = .white
        var logo: String?
    }

    private static let styles: [String: Style] = [
        "nubank": Style(color: Color(hex: 0x820AD1), initials: "nu"),
        "mercado pago": Style(color: Color(hex: 0x00B1EA), initials: "mp"),
        "itaú": Style(color: Color(hex: 0xEC7000), initials: "it"),
        "inter": Style(color: Color(hex: 0xFF7A00), initials: "in"),
        "rico": Style(color: Color(hex: 0xE8530E), initials: "ri"),
        "avenue": Style(color: Color(hex: 0x2457F5), initials: "av"),
        "xp investimentos": Style(color: .white, initials: "xp", ink: .qInk),
    ]

    /// Instituição sem cadastro: duas primeiras letras sobre um cinza neutro.
    static func style(_ institution: String) -> Style {
        styles[institution.lowercased()]
            ?? Style(color: .white.opacity(0.12), initials: String(institution.prefix(2)).lowercased())
    }
}

struct InstitutionAvatar: View {
    let institution: String
    var size: CGFloat = 40

    var body: some View {
        let style = Institutions.style(institution)
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(style.color)
            .overlay {
                if let logo = style.logo {
                    Image(logo).resizable().scaledToFit().padding(size * 0.2)
                } else {
                    Text(style.initials).font(.urbanist(size * 0.325, .semibold)).foregroundStyle(style.ink)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
