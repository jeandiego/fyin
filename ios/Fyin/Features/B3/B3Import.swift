import Foundation

// Espelha GET /v1/b3/imports (internal/b3): um status por dono, importado ou não.
struct B3Status: Decodable, Identifiable, Equatable, Sendable {
    let owner: String
    let importedAt: Date?
    let referenceDate: String?  // YYYY-MM-DD (D-1 da B3)
    let positions: Int
    let total: Money
    /// Mais de 30 dias desde o último import; o servidor decide.
    let stale: Bool

    var id: String { owner }
    var ownerName: String { owner.capitalized(with: Locale(identifier: "pt_BR")) }
    var imported: Bool { importedAt != nil }
}

// Resposta de POST /v1/b3/positions.
struct B3ImportResult: Decodable, Equatable, Sendable {
    let owner: String
    let positions: Int
    let total: Money
    /// Quanto mudou desde o import anterior; nil no primeiro.
    let delta: Money?
    let referenceDate: String
    let importedAt: Date
}

/// O que o leitor tirou do site: as páginas cruas da API de posição e o dia a que se referem.
struct B3Read: Equatable, Sendable {
    let referenceDate: String
    let pages: [String]
}

extension B3Status {
    /// Linha de Ajustes: o que o dono precisa saber primeiro.
    func line(now: Date) -> String {
        guard let importedAt else { return "Importar posição da Área do Investidor" }
        if stale {
            let days = Calendar.current.dateComponents([.day], from: importedAt, to: now).day ?? 0
            return "\(ownerName) · posição de \(days) dias"
        }
        let n = positions == 1 ? "1 título" : "\(positions) títulos"
        return "\(ownerName) · atualizado \(B3Format.when(importedAt, now: now)) · \(n)"
    }
}

extension B3ImportResult {
    /// Texto do toast: o total e, a partir do segundo import, quanto mudou desde a leitura anterior.
    var summary: String {
        guard let delta else { return "B3 importada · \(total.full)" }
        let sign = delta.value < 0 ? "−" : "+"
        return "B3 atualizada · \(sign)\(Money(abs(delta.value)).full)"
    }
}

enum B3Format {
    private static let ptBR = Locale(identifier: "pt_BR")

    /// "9:41" hoje; "24 out" em outro dia.
    static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(.dateTime.hour().minute().locale(ptBR))
            : date.formatted(.dateTime.day().month(.abbreviated).locale(ptBR)).replacingOccurrences(of: ".", with: "")
    }

    /// "2026-10-29" → "29 out". Dia de calendário: formata em GMT para não deslocar.
    static func day(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: .iso8601.year().month().day()) else { return iso }
        return date.formatted(Date.FormatStyle(locale: ptBR, timeZone: .gmt).day().month(.abbreviated))
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ")
    }
}
