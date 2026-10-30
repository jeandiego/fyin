import Foundation
import Observation

// Frame "19 · Toast / Notifications". Sem SwiftUI: a regra de fila, prazo e pilha é testável sozinha.

struct Toast: Identifiable, Equatable {
    enum Tone { case success, error, attention, info }

    enum Content: Equatable {
        case message
        case loading
        /// Só com total conhecido (0 a 1). Nunca inventar percentual.
        case progress(Double)
    }

    struct Action: Equatable {
        let label: String
        let isUndo: Bool
        let perform: @MainActor () -> Void

        static func == (l: Action, r: Action) -> Bool { l.label == r.label && l.isUndo == r.isUndo }
        static func undo(_ perform: @escaping @MainActor () -> Void) -> Action { Action(label: "Desfazer", isUndo: true, perform: perform) }
    }

    enum Lifetime: Equatable {
        case automatic
        /// Fica até dispensar ou agir; a condição também aparece na tela de origem.
        case persistent
        case seconds(Int)
    }

    /// Id da operação: mostrar outro Toast com o mesmo id atualiza o que já está na tela.
    let id: String
    var tone: Tone = .success
    var title: String
    var detail: String?
    var content: Content = .message
    var action: Action?
    var lifetime: Lifetime = .automatic

    var isPersistent: Bool { lifetime == .persistent }

    /// Prazos do board: compacto 3 s · com descrição 6 s · desfazer 5 s · ação 8 s · carregando e progresso 8 s
    /// (depois some da frente e o status fica na origem; a tarefa segue).
    var duration: Duration? {
        switch lifetime {
        case .persistent: return nil
        case .seconds(let s): return .seconds(s)
        case .automatic: break
        }
        if content != .message { return .seconds(8) }
        if let action { return .seconds(action.isUndo ? 5 : 8) }
        return .seconds(detail == nil ? 3 : 6)
    }
}

@MainActor @Observable
final class ToastCenter {
    /// Até 3 na tela, do mais antigo ao mais novo; o último é o da frente.
    static let maxVisible = 3
    /// Visíveis + em espera. Ao exceder, cai o informativo mais antigo da espera.
    static let maxTotal = 5
    private static let collapseAfter = Duration.seconds(4)

    private(set) var visible: [Toast] = []
    private(set) var isExpanded = false
    /// VoiceOver ligado: os prazos sobem para no mínimo 8 s (compacto) e 12 s (com descrição ou ação).
    var voiceOverRunning = false

    private var waiting: [Toast] = []
    private var holds: Set<String> = []
    private var timers: [String: Task<Void, Never>] = [:]
    private var collapseTask: Task<Void, Never>?
    private let sleep: @Sendable (Duration) async -> Void

    init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    private var isPaused: Bool { isExpanded || !holds.isEmpty }

    func show(_ toast: Toast) {
        if let i = visible.firstIndex(where: { $0.id == toast.id }) {
            visible[i] = toast
            if !isPaused { startTimer(for: toast) }
        } else if let i = waiting.firstIndex(where: { $0.id == toast.id }) {
            waiting[i] = toast
        } else if visible.count < Self.maxVisible {
            present(toast)
        } else {
            waiting.append(toast)
            if visible.count + waiting.count > Self.maxTotal {
                waiting.remove(at: waiting.firstIndex(where: { $0.action == nil }) ?? 0)
            }
        }
    }

    /// Dispensar limpa só a apresentação: não cancela a tarefa nem desfaz.
    func dismiss(_ id: String) {
        timers.removeValue(forKey: id)?.cancel()
        holds.remove(id)
        visible.removeAll { $0.id == id }
        waiting.removeAll { $0.id == id }
        while visible.count < Self.maxVisible, !waiting.isEmpty { present(waiting.removeFirst()) }
        if visible.count < 2 { collapse() }
    }

    /// A ação executa uma vez e fecha o Toast.
    func perform(_ id: String) {
        guard let action = visible.first(where: { $0.id == id })?.action else { return }
        dismiss(id)
        action.perform()
    }

    func expand() {
        guard visible.count > 1, !isExpanded else { return }
        isExpanded = true
        cancelTimers()
        collapseTask = Task { [sleep] in
            await sleep(Self.collapseAfter)
            if !Task.isCancelled { collapse() }
        }
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        guard isExpanded else { return }
        isExpanded = false
        resumeIfPossible()
    }

    /// Foco do VoiceOver (ou interação) congela o prazo daquele Toast.
    func hold(_ id: String, _ on: Bool) {
        if on { holds.insert(id); cancelTimers() } else { holds.remove(id); resumeIfPossible() }
    }

    private func present(_ toast: Toast) {
        visible.append(toast)
        if !isPaused { startTimer(for: toast) }
    }

    private func startTimer(for toast: Toast) {
        timers.removeValue(forKey: toast.id)?.cancel()
        guard var duration = toast.duration else { return }
        // shortcut: ao pausar/retomar o prazo recomeça inteiro, não do restante; trocar se o produto pedir exatidão.
        if voiceOverRunning {
            duration = max(duration, .seconds(toast.detail == nil && toast.action == nil ? 8 : 12))
        }
        let id = toast.id
        timers[id] = Task { [sleep] in
            await sleep(duration)
            if !Task.isCancelled { dismiss(id) }
        }
    }

    private func cancelTimers() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
    }

    private func resumeIfPossible() {
        guard !isPaused else { return }
        for toast in visible where timers[toast.id] == nil { startTimer(for: toast) }
    }
}
