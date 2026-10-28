import Foundation
import Observation

// Estado da home: um resumo por mês, guardado para que trocar de mês já visto seja instantâneo.
@MainActor @Observable
final class HomeViewModel {
    private(set) var months: [String] = []
    private(set) var selected: String?
    private(set) var summaries: [String: HomeSummary] = [:]
    private(set) var failed = false
    private(set) var refreshing = false
    /// Patrimônio aberto em contas; sempre o atual, não depende do mês.
    private(set) var portfolio: Portfolio?

    private let repository: HomeRepository

    init(repository: HomeRepository) { self.repository = repository }

    // Enquanto o mês novo carrega, segue mostrando o anterior: os números giram quando ele chega.
    private var lastShown: HomeSummary?

    var current: HomeSummary? {
        if let selected, let summary = summaries[selected] { return summary }
        return lastShown
    }
    var loading: Bool { current == nil && !failed }

    /// Muda o mês na hora (a view anima); os dados vêm de ensureLoaded.
    func select(_ month: String) {
        lastShown = current
        selected = month
    }

    /// Busca o mês selecionado se ainda não está em cache; sem seleção, o mês atual.
    func ensureLoaded() async {
        if selected.flatMap({ summaries[$0] }) == nil { await fetch(selected) }
        if portfolio == nil { portfolio = try? await repository.portfolio() }
        // Busca os outros meses dos seletores em segundo plano para a troca ser instantânea.
        for month in months where summaries[month] == nil {
            if let summary = try? await repository.summary(month: month) { summaries[summary.month] = summary }
        }
    }

    /// Puxar para atualizar: descarta o cache e busca de novo o mês aberto.
    func refresh() async {
        refreshing = true
        defer { refreshing = false }
        let month = selected
        lastShown = current
        summaries = [:]
        // A busca local termina em milissegundos; sem isso a barra não chega a ser vista.
        async let minimum: Void = { try? await Task.sleep(for: .milliseconds(900)) }()
        await fetch(month)
        if let fresh = try? await repository.portfolio() { portfolio = fresh }
        await minimum
    }

    private func fetch(_ month: String?) async {
        do {
            let summary = try await repository.summary(month: month)
            summaries[summary.month] = summary
            months = summary.months
            // Só troca a seleção se o usuário não escolheu outro mês enquanto carregava.
            if selected == nil || selected == month { selected = summary.month }
            failed = false
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
            // usuário trocou de mês antes da resposta
        } catch {
            failed = true
        }
    }
}
