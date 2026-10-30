import Foundation

protocol B3Repository: Sendable {
    func imports() async throws -> [B3Status]
    /// Repassa as páginas cruas da B3; o backend valida, tira o CPF e grava.
    func save(owner: String, read: B3Read) async throws -> B3ImportResult
}

struct LiveB3Repository: B3Repository {
    let api: APIClient

    func imports() async throws -> [B3Status] { try await api.get("v1/b3/imports") }

    func save(owner: String, read: B3Read) async throws -> B3ImportResult {
        // As páginas vão como JSON, não como texto: o servidor recebe exatamente o que a B3 devolveu.
        let pages = try read.pages.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
        let body = try JSONSerialization.data(withJSONObject: ["owner": owner, "referenceDate": read.referenceDate, "pages": pages])
        return try await api.post("v1/b3/positions", json: body)
    }
}

struct PreviewB3Repository: B3Repository {
    func imports() async throws -> [B3Status] {
        [B3Status(owner: "jean", importedAt: .now.addingTimeInterval(-3 * 86_400), referenceDate: "2026-10-29", positions: 1,
                  total: Money(41_230.18), stale: false),
         B3Status(owner: "poliana", importedAt: nil, referenceDate: nil, positions: 0, total: Money(0), stale: false)]
    }

    func save(owner: String, read: B3Read) async throws -> B3ImportResult {
        B3ImportResult(owner: owner, positions: 1, total: Money(41_542.58), delta: Money(312.40), referenceDate: read.referenceDate, importedAt: .now)
    }
}
