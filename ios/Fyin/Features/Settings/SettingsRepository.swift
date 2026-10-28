import Foundation

protocol SettingsRepository: Sendable {
    func items() async throws -> [ConnectedItem]
    /// Dispara o sync de todos os itens e volta na hora, com o andamento de cada um.
    func syncAll() async throws -> [ConnectedItem]
}

struct LiveSettingsRepository: SettingsRepository {
    let api: APIClient

    func items() async throws -> [ConnectedItem] { try await api.get("v1/items") }
    func syncAll() async throws -> [ConnectedItem] { try await api.post("v1/sync") }
}
