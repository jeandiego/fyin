import Foundation

// Resposta de GET /v1/investments: o patrimônio investido aberto em contas (instituição × titular), grupos e posições.
struct Portfolio: Decodable, Equatable, Sendable {
    struct Account: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let institution: String
        let owner: String
        /// Ativo declarado à mão: só a linha, sem detalhe.
        let manual: Bool
        let total: Money
        /// Soma das posições em dólar, na moeda original; nil se a conta não tem dólar.
        var totalUsd: Money? = nil
        let groups: [Group]
    }

    struct Group: Decodable, Equatable, Sendable {
        let kind: String
        let total: Money
        var totalUsd: Money? = nil
        let positions: [Position]
    }

    struct Position: Decodable, Equatable, Sendable {
        let name: String
        /// Em reais (já convertido pela PTAX se a posição é em dólar).
        let balance: Money
        /// Na moeda da posição (`currency`).
        let balanceOriginal: Money
        let currency: String
        let code: String?
        let quantity: String?
        let indexer: String?
        let rate: String?
        let fixedRate: String?
        let dueDate: String?
        let taxExempt: Bool?
    }

    let total: Money
    /// PTAX usada nas conversões ("5.4512") e seu dia; nil enquanto o backend não tem cotação.
    var usdRate: String? = nil
    var usdRateDate: String? = nil
    let accounts: [Account]
}

extension Portfolio {
    /// Titulares na ordem em que aparecem (contas já vêm por valor).
    var owners: [String] {
        accounts.reduce(into: []) { if !$0.contains($1.owner) { $0.append($1.owner) } }
    }

    func accounts(of owner: String?) -> [Account] {
        guard let owner else { return accounts }
        return accounts.filter { $0.owner == owner }
    }
}

extension Portfolio.Account {
    var ownerName: String { owner.capitalized(with: Locale(identifier: "pt_BR")) }

    /// "Jean · Caixinhas + CDB" (até dois produtos, os maiores primeiro).
    var subtitle: String {
        let kinds = manual ? ["Bem declarado"] : groups.prefix(2).map { PortfolioKind.label($0.kind) }
        return ([ownerName] + [kinds.joined(separator: " + ")]).joined(separator: " · ")
    }

    /// Só oferece o seletor R$ / US$ se há dólar e cotação para explicar a conversão.
    func hasDollar(rate: String?) -> Bool { totalUsd != nil && rate != nil }

    var positionCount: Int { groups.reduce(0) { $0 + $1.positions.count } }
}

extension Portfolio.Position {
    /// Linha de apoio: "115% do CDI · vence em ago 2027 · isento de IR". Ações: "PETR4 · 200 cotas".
    var detail: String {
        var parts: [String] = []
        if let code, code != name { parts.append(code) }
        if let quantity, let q = Decimal(string: quantity), q > 0, code != nil {
            parts.append("\(q.formatted(.number.locale(PortfolioKind.ptBR))) cotas")
        }
        switch (indexer, rate.flatMap(PortfolioKind.decimal), fixedRate.flatMap(PortfolioKind.decimal)) {
        case let (indexer?, rate?, _) where indexer != "PREFIXADO":
            parts.append("\(PortfolioKind.number(rate))% do \(indexer)")
        case let (indexer?, _, fixed?) where indexer != "PREFIXADO":
            parts.append("\(indexer) + \(PortfolioKind.number(fixed))%")
        case let (_, _, fixed?):
            parts.append("\(PortfolioKind.number(fixed))% a.a.")
        default: break
        }
        if let dueDate { parts.append("vence em \(MonthLabel.monthYear(dueDate))") }
        if taxExempt == true { parts.append("isento de IR") }
        if currency != "BRL" { parts.append(currency) }
        return parts.joined(separator: " · ")
    }

    /// Valor na moeda pedida: em dólar, só posições em USD mudam; as demais seguem em reais.
    func amount(_ currency: DisplayCurrency) -> Money {
        currency == .usd && self.currency == "USD" ? balanceOriginal : balance
    }

    func value(_ currency: DisplayCurrency) -> String {
        currency == .usd && self.currency == "USD" ? balanceOriginal.fullUsd : balance.full
    }
}

/// Moeda de exibição do detalhe de uma conta com dólar; reais é o padrão.
enum DisplayCurrency: Equatable { case brl, usd }

enum PortfolioKind {
    static let ptBR = Locale(identifier: "pt_BR")

    // Subtipos da Pluggy; o que não estiver aqui aparece como veio.
    private static let labels = [
        "RESERVE": "Caixinhas", "MANUAL": "Bens", "FIXED_INCOME": "Renda fixa", "EQUITY": "Renda variável",
        "MUTUAL_FUND": "Fundos", "SECURITY": "Previdência", "ETF": "ETFs", "COE": "COE",
        "TREASURY": "Tesouro Direto", "DEBENTURES": "Debêntures", "CDB": "CDB", "RDB": "RDB", "LCI": "LCI", "LCA": "LCA",
        "LC": "LC", "CRI": "CRI", "CRA": "CRA", "STOCK": "Ações", "BDR": "BDRs", "REAL_ESTATE_FUND": "FIIs",
        "INVESTMENT_FUND": "Fundos", "PENSION": "Previdência",
    ]

    static func label(_ kind: String) -> String { labels[kind] ?? kind.capitalized(with: ptBR) }

    static func decimal(_ text: String) -> Decimal? { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) }

    /// "115", "6,5" — sem zeros à direita.
    static func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(ptBR))
    }

    /// "22,8%" de part sobre whole.
    static func share(_ part: Money, of whole: Money) -> String {
        guard whole.value != 0 else { return "0%" }
        return (part.value / whole.value).formatted(.percent.precision(.fractionLength(1)).locale(ptBR))
    }

    static func fraction(_ part: Money, of whole: Money) -> Double {
        guard whole.value != 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: part.value / whole.value).doubleValue, 0), 1)
    }
}
