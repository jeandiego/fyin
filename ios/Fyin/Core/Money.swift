import Foundation

// Valor monetário vindo da API como texto decimal ("6240.00"); nunca passa por Double.
struct Money: Decodable, Equatable, Sendable {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "valor inválido \(text)"))
        }
        self.value = value
    }

    private static let ptBR = Locale(identifier: "pt_BR")

    /// "R$ 6.240", sem centavos (cards).
    var short: String { "R$ " + value.formatted(.number.precision(.fractionLength(0)).locale(Self.ptBR)) }

    /// ("24.318", ",52"), para o saldo com centavos esmaecidos.
    var split: (whole: String, cents: String) {
        let text = value.formatted(.number.precision(.fractionLength(2)).locale(Self.ptBR))
        guard let comma = text.lastIndex(of: ",") else { return (text, ",00") }
        return (String(text[..<comma]), String(text[comma...]))
    }
}
