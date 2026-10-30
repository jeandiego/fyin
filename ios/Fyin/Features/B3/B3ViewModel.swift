import Foundation
import Observation

// Importar a posição da B3: escolher o dono, entrar no site, ler e gravar. A leitura é do app (WebView);
// o backend só recebe as páginas. Erro nunca apaga a posição que já estava gravada.
@MainActor @Observable
final class B3ViewModel {
    enum Phase: Equatable {
        case idle
        case explaining        // sheet curta antes de abrir o site
        case login             // WebView aberta, esperando a pessoa entrar
        case reading           // lendo as páginas de posição
        case saving            // enviando ao Fyin
        case paused(String)    // falhou; o texto diz a causa e a saída
    }

    private(set) var statuses: [B3Status] = []
    private(set) var phase: Phase = .idle
    /// Dono da posição sendo importada; escolhido na sheet ou pela linha tocada.
    var owner: String?
    /// Último import concluído, para o toast.
    private(set) var result: B3ImportResult?
    /// Sobe a cada import que termina; a view usa para o feedback tátil.
    private(set) var finished = 0
    /// Dia a que a leitura em andamento se refere, para a etapa "Lendo posição de 29 out".
    private(set) var readingDay: String?

    let reader: B3Reader
    private let repository: B3Repository
    private let onImported: @MainActor () async -> Void

    init(repository: B3Repository, reader: B3Reader, onImported: @escaping @MainActor () async -> Void = {}) {
        self.repository = repository
        self.reader = reader
        self.onImported = onImported
    }

    var owners: [String] { statuses.map(\.owner) }
    var imported: [B3Status] { statuses.filter(\.imported) }
    var isFlowActive: Bool { phase != .idle }

    func load() async {
        do {
            statuses = try await repository.imports()
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            // Sem servidor a seção some; o resto de Ajustes já mostra que está offline.
        }
    }

    /// "Importar da B3": abre a explicação com o primeiro dono que ainda não importou.
    func begin() {
        owner = statuses.first(where: { !$0.imported })?.owner ?? statuses.first?.owner
        phase = .explaining
    }

    /// Linha de um dono já importado: vai direto ao site, sem a explicação.
    func update(_ owner: String) {
        self.owner = owner
        enter()
    }

    /// "Entrar na B3" e "Entrar de novo".
    func enter() {
        guard owner != nil else { return }
        phase = .login
        reader.start { [weak self] in
            Task { await self?.loggedIn() }
        }
    }

    func cancel() {
        phase = .idle
        readingDay = nil
    }

    func dismissResult() { result = nil }

    func loggedIn() async {
        guard phase == .login, let owner else { return }
        phase = .reading
        let read: B3Read
        do {
            read = try await reader.read()
        } catch B3ReadError.session {
            phase = .paused("A sessão na B3 terminou. Entre de novo para atualizar.")
            return
        } catch {
            phase = .paused("Não consegui ler a posição na B3. O site pode ter mudado. Sua posição salva continua no Fyin.")
            return
        }
        readingDay = read.referenceDate
        phase = .saving
        do {
            result = try await repository.save(owner: owner, read: read)
        } catch {
            phase = .paused("O servidor do Fyin não respondeu. Nada foi gravado; tente de novo em instantes.")
            return
        }
        phase = .idle
        readingDay = nil
        finished += 1
        await load()
        await onImported()
    }
}
