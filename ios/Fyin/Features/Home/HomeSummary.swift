import Foundation

// Resposta de GET /v1/home. Meses no formato "YYYY-MM".
struct HomeSummary: Decodable, Equatable, Sendable {
    struct Spending: Decodable, Equatable, Sendable {
        let spent: Money
        let goal: Money
        let day: Int
        let daysInMonth: Int
        /// 1º dia com dados ("YYYY-MM-DD") quando uma conexão começou no meio do mês.
        let since: String?
    }

    struct Card: Decodable, Equatable, Sendable {
        let total: Money
        let closingDate: String?
        let dueDate: String?
    }

    struct Loans: Decodable, Equatable, Sendable {
        let total: Money
    }

    let month: String
    let months: [String]
    let syncedAt: Date?
    let balance: Money
    let invested: Money
    let spending: Spending
    let card: Card
    let loans: Loans
}

extension HomeSummary.Spending {
    /// nil enquanto não há meta (goal 0).
    var percent: Int? {
        guard goal.value > 0 else { return nil }
        // Via Double: NSDecimalNumber.intValue devolve lixo com dízimas longas (6240/9000).
        return Int((NSDecimalNumber(decimal: spent.value / goal.value).doubleValue * 100).rounded(.down))
    }

    // Acima de 85% o brilho do card de gastos vira coral (frame 11).
    var isOver: Bool { (percent ?? 0) > 85 }
}

enum MonthLabel {
    private static let ptBR = Locale(identifier: "pt_BR")
    // As datas da API são dias de calendário; em GMT o formatador não desloca o dia.
    private static let style = Date.FormatStyle(locale: ptBR, timeZone: .gmt)

    /// "2026-10" → "Out".
    static func short(_ month: String) -> String {
        guard let date = try? Date("\(month)-01", strategy: .iso8601.year().month().day()) else { return month }
        let text = date.formatted(style.month(.abbreviated))
        return text.replacingOccurrences(of: ".", with: "").capitalized(with: ptBR)
    }

    /// "2026-10-02" → "2 out".
    static func day(_ isoDate: String) -> String {
        guard let date = try? Date(isoDate, strategy: .iso8601.year().month().day()) else { return isoDate }
        return date.formatted(style.day().month(.abbreviated))
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ")
    }

    /// "2027-08-15" → "ago 2027".
    static func monthYear(_ isoDate: String) -> String {
        guard let date = try? Date(isoDate, strategy: .iso8601.year().month().day()) else { return isoDate }
        return date.formatted(style.month(.abbreviated).year())
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ")
    }
}
