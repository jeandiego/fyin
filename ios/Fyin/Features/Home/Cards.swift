import SwiftUI

// Resposta de GET /v1/cards: cada cartão com todas as faturas. Período = "YYYY-MM" do vencimento.
struct CardsOverview: Decodable, Equatable, Sendable {
    struct Card: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let institution: String
        let owner: String
        let name: String
        let last4: String?
        /// Período da fatura atual: a mais antiga com saldo; sem saldo, a aberta.
        let current: String
        let bills: [Bill]
    }

    struct Bill: Decodable, Equatable, Sendable {
        let period: String
        let status: Status
        let openingDate: String
        /// Aberta e futuras: estimado pelo servidor.
        let closingDate: String
        let dueDate: String
        let total: Money
        let paid: Money
        let paidOn: String?
        let lines: [Line]
    }

    enum Status: String, Decodable, Sendable {
        case paid, partial, closed, overdue, open, future
    }

    struct Line: Decodable, Equatable, Sendable {
        let date: String
        let description: String
        let amount: Money
        let installment: Int?
        let installments: Int?
        let purchaseDate: String?
    }

    let total: Money
    let cards: [Card]
}

extension CardsOverview {
    /// Titulares na ordem em que aparecem (a lista já vem por vencimento).
    var owners: [String] { cards.map(\.owner).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }

    func cards(of owner: String?) -> [Card] { owner.map { o in cards.filter { $0.owner == o } } ?? cards }

    /// Soma das faturas atuais dos cartões mostrados.
    static func total(of cards: [Card]) -> Money { Money(cards.reduce(0) { $0 + ($1.currentBill?.total.value ?? 0) }) }
}

extension CardsOverview.Card {
    var currentBill: CardsOverview.Bill? { bill(current) }

    func bill(_ period: String) -> CardsOverview.Bill? { bills.first { $0.period == period } }

    var ownerName: String { owner.capitalized(with: PortfolioKind.ptBR) }

    /// "•• 4821"; sem número conhecido, o nome do cartão ("platinum").
    var suffix: String { last4.map { "•• \($0)" } ?? name.capitalized(with: PortfolioKind.ptBR) }

    /// "Jean · final 4821".
    var holder: String { last4.map { "\(ownerName) · final \($0)" } ?? ownerName }

    /// "Jan 2027" só quando a fatura cai em outro ano que a atual.
    func pill(_ period: String) -> String {
        period.prefix(4) == current.prefix(4) ? MonthLabel.short(period) : "\(MonthLabel.short(period)) \(period.prefix(4))"
    }

    /// "Fatura de janeiro de 2027 · já lançado".
    func title(_ bill: CardsOverview.Bill) -> String {
        let year = bill.period.prefix(4) == current.prefix(4) ? "" : " de \(bill.period.prefix(4))"
        return "Fatura de \(MonthLabel.long(bill.period))\(year)\(bill.status == .future ? " · já lançado" : "")"
    }
}

extension CardsOverview.Bill {
    var label: String {
        switch status {
        case .paid: "Paga"
        case .partial: "Paga em parte"
        case .closed: "Fechada"
        case .overdue: "Vencida"
        case .open: "Aberta"
        case .future: "Futura"
        }
    }

    /// Cor só no ponto; o texto ao lado diz o que houve.
    var dot: Color {
        switch status {
        case .paid, .partial: .qAccent
        case .closed: .qWarn
        case .overdue: .qOver
        case .open: .qOnDark2
        case .future: .qOnDark3
        }
    }

    /// Linha do cartão na lista: "vence 10 nov" ou "venceu 25 out".
    var due: String { "\(status == .overdue ? "venceu" : "vence") \(MonthLabel.day(dueDate))" }

    /// Linha de status sob o total da fatura.
    var detail: String {
        let close = MonthLabel.day(closingDate), due = MonthLabel.day(dueDate)
        switch status {
        case .open, .future: return "\(label) · fecha \(close) · vence \(due)"
        case .closed: return "Fechada · fechou \(close) · vence \(due)"
        case .overdue: return "Vencida · venceu \(due) sem pagamento"
        case .paid: return paidOn.map { "Paga em \(MonthLabel.day($0)) · venceu \(due)" } ?? "Paga · venceu \(due)"
        case .partial: return "Paga em parte · \(paid.full)\(paidOn.map { " em \(MonthLabel.day($0))" } ?? "") · o resto foi para a seguinte"
        }
    }

    /// "4 out – 3 nov".
    var range: String { "\(MonthLabel.day(openingDate)) – \(MonthLabel.day(closingDate))" }
}

extension CardsOverview.Line {
    /// "Parcela 1 de 3 · compra em 27 out" ou "À vista · 25 out".
    var detail: String {
        if let installment, let installments, installments > 1 {
            return "Parcela \(installment) de \(installments) · compra em \(MonthLabel.day(purchaseDate ?? date))"
        }
        return "À vista · \(MonthLabel.day(date))"
    }
}
