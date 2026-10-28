import Foundation

protocol HomeRepository: Sendable {
    /// month nil = mês atual (decidido pelo servidor, em São Paulo).
    func summary(month: String?) async throws -> HomeSummary
}

struct LiveHomeRepository: HomeRepository {
    let api: APIClient

    func summary(month: String?) async throws -> HomeSummary {
        try await api.get("v1/home", query: month.map { [URLQueryItem(name: "month", value: $0)] } ?? [])
    }
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
}
