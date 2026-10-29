import Foundation

protocol HomeRepository: Sendable {
    /// month nil = mês atual (decidido pelo servidor, em São Paulo).
    func summary(month: String?) async throws -> HomeSummary
    func portfolio() async throws -> Portfolio
}

struct LiveHomeRepository: HomeRepository {
    let api: APIClient

    func summary(month: String?) async throws -> HomeSummary {
        try await api.get("v1/home", query: month.map { [URLQueryItem(name: "month", value: $0)] } ?? [])
    }

    func portfolio() async throws -> Portfolio { try await api.get("v1/investments") }
}

// Dados fixos para #Preview; não usado no app.
struct PreviewHomeRepository: HomeRepository {
    func summary(month: String?) async throws -> HomeSummary {
        let month = month ?? "2026-10"
        return HomeSummary(
            month: month, months: ["2026-08", "2026-09", "2026-10"], syncedAt: .now.addingTimeInterval(-300),
            balance: Money(24318.52), invested: Money(182450),
            spending: .init(spent: Money(6240), goal: Money(9000), day: 28, daysInMonth: 31, since: nil),
            card: .init(total: Money(3420), closingDate: "2026-10-02", dueDate: "2026-10-15"),
            loans: .init(total: Money(0)))
    }

    func portfolio() async throws -> Portfolio {
        func pos(_ name: String, _ v: Decimal, indexer: String? = "CDI", rate: String? = "100") -> Portfolio.Position {
            .init(name: name, balance: Money(v), balanceOriginal: Money(v), currency: "BRL", code: nil, quantity: nil, indexer: indexer, rate: rate,
                  fixedRate: nil, dueDate: nil, taxExempt: nil)
        }
        return Portfolio(total: Money(186810.16), usdRate: "5.4502", usdRateDate: "2026-10-28", accounts: [
            .init(id: "1", institution: "Mercado Pago", owner: "jean", manual: false, total: Money(120000), groups: [
                .init(kind: "RESERVE", total: Money(120000), positions: [pos("Reserva de emergência", 100000), pos("Viagem", 20000)]),
            ]),
            .init(id: "2", institution: "Nubank", owner: "poliana", manual: false, total: Money(57450), groups: [
                .init(kind: "CDB", total: Money(57450), positions: [pos("CDB Nubank", 57450, rate: "115")]),
            ]),
            .init(id: "3", institution: "Avenue", owner: "jean", manual: false, total: Money(4360.16), totalUsd: Money(800), groups: [
                .init(kind: "ETF", total: Money(4360.16), totalUsd: Money(800), positions: [
                    .init(name: "SPDR S&P 500 ETF Trust", balance: Money(2725.10), balanceOriginal: Money(500), currency: "USD", code: "SPY",
                          quantity: "0.6488", indexer: nil, rate: nil, fixedRate: nil, dueDate: nil, taxExempt: nil),
                    .init(name: "Invesco QQQ Trust", balance: Money(1635.06), balanceOriginal: Money(300), currency: "USD", code: "QQQ",
                          quantity: "0.4", indexer: nil, rate: nil, fixedRate: nil, dueDate: nil, taxExempt: nil),
                ]),
            ]),
            .init(id: "manual-1", institution: "Carro", owner: "jean", manual: true, total: Money(5000), groups: []),
        ])
    }
}
