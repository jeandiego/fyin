import Foundation
import Observation

// Estado de Ajustes: os itens conectados e o andamento do sync. O sync roda no servidor;
// aqui só se dispara e se acompanha, então sair da tela não o interrompe.
@MainActor @Observable
final class SettingsViewModel {
    enum Hero: Equatable {
        case empty
        case offline
        case running(done: Int, total: Int)
        case partial(ok: Int, total: Int)
        case upToDate
    }

    private(set) var items: [ConnectedItem] = []
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var starting = false
    /// Sobe a cada sync que termina; a view usa para o feedback tátil.
    private(set) var finishedSyncs = 0

    private var startedCount = 0
    private var polling = false
    private let repository: SettingsRepository
    private let onSynced: @MainActor () async -> Void

    init(repository: SettingsRepository, onSynced: @escaping @MainActor () async -> Void = {}) {
        self.repository = repository
        self.onSynced = onSynced
    }

    var syncing: Bool { starting || items.contains(where: \.isRunning) }

    // Consentimento perto de vencer só aparece na linha do banco; o hero não vira "em parte" por isso.
    var needsAttention: [ConnectedItem] {
        items.filter { !$0.isRunning && ($0.status != "UPDATED" || $0.sync.state == "failed") }
    }

    var hero: Hero {
        if failed { return .offline }
        if loaded && items.isEmpty { return .empty }
        let running = items.filter(\.isRunning).count
        if running > 0 { return .running(done: max(0, startedCount - running), total: max(startedCount, running)) }
        if !needsAttention.isEmpty { return .partial(ok: items.count - needsAttention.count, total: items.count) }
        return .upToDate
    }

    var lastSync: Date? { items.map(\.syncedAt).max() }

    func load() async {
        await reload()
        await pollWhileRunning()
    }

    func syncAll() async {
        guard !syncing else { return }
        starting = true
        defer { starting = false }
        do {
            items = try await repository.syncAll()
            startedCount = items.filter(\.isRunning).count
            failed = false
        } catch {
            failed = true
            return
        }
        await pollWhileRunning()
    }

    private func reload() async {
        do {
            items = try await repository.items()
            loaded = true
            failed = false
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            failed = true
        }
    }

    // Consulta a cada 2 s (o mesmo ritmo que o servidor usa com a Pluggy) até nenhum item estar rodando.
    private func pollWhileRunning() async {
        guard !polling, items.contains(where: \.isRunning) else { return }
        polling = true
        defer { polling = false }
        while items.contains(where: \.isRunning) {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            await reload()
        }
        startedCount = 0
        finishedSyncs += 1
        await onSynced()
    }
}
