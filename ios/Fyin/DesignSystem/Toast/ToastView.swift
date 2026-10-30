import SwiftUI

// Componente "Toast" (msYJe) do Fyin.pen, superfície escura: para telas claras. Uma anatomia só:
// ícone ou atividade → mensagem + descrição → ação → fechar; progresso embaixo. Slots ausentes não ocupam espaço.
struct ToastView: View {
    let toast: Toast
    let center: ToastCenter
    /// Atrás da frente, com a pilha recolhida, só a borda aparece: o conteúdo some e a altura iguala a da frente.
    var showsContent = true
    var fixedHeight: CGFloat?
    var interactive = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focused: Bool
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            if typeSize.isAccessibilitySize { reflowed } else { row }
            if case .progress(let value) = toast.content { track(value) }
        }
        .opacity(showsContent ? 1 : 0)
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: fixedHeight, alignment: .top)
        .background(Color.qInk, in: .rect(cornerRadius: 28))
        .shadow(color: .qShadow, radius: 24, y: 8)
        .offset(y: drag)
        .opacity(1 - Double(drag) / 240)
        .gesture(interactive ? swipe : nil)
        .accessibilityElement(children: .contain)
        .accessibilityFocused($focused)
        .onChange(of: focused) { center.hold(toast.id, focused) }
        .accessibilityAction(named: "Dispensar notificação") { center.dismiss(toast.id) }
        .onAppear { AccessibilityNotification.Announcement([toast.title, toast.detail].compactMap { $0 }.joined(separator: ". ")).post() }
    }

    private var row: some View {
        HStack(spacing: 12) {
            icon
            texts
            Spacer(minLength: 0)
            if let action = toast.action { actionButton(action) }
            if toast.isPersistent { closeButton }
        }
    }

    // Dynamic Type de acessibilidade: ícone, texto e ação refluem na vertical; a ação ocupa a largura.
    private var reflowed: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                icon
                if toast.isPersistent { Spacer(minLength: 0); closeButton }
            }
            texts
            if let action = toast.action { actionButton(action).frame(maxWidth: .infinity) }
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(toast.title).font(.urbanist(14)).foregroundStyle(Color.qOnDark)
            if let detail = toast.detail { Text(detail).font(.urbanist(13)).foregroundStyle(Color.qOnDark2) }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var icon: some View {
        Group {
            if toast.content == .loading {
                if reduceMotion { Image(systemName: "ellipsis") } else { ProgressView().tint(Color.qOnDark) }
            } else {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    private func actionButton(_ action: Toast.Action) -> some View {
        Button { center.perform(toast.id) } label: {
            Text(action.label).font(.urbanist(13, .semibold)).foregroundStyle(Color.qAccent)
                .padding(.horizontal, 12).frame(minHeight: typeSize.isAccessibilitySize ? 48 : 44)
                .background(Color.white.opacity(0.1), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button { center.dismiss(toast.id) } label: {
            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.qOnDark)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dispensar notificação")
    }

    private func track(_ value: Double) -> some View {
        Capsule().fill(Color.qOnDarkLine).frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { Capsule().fill(Color.qAccent).frame(width: $0.size.width * min(max(value, 0), 1)) }
            }
            .padding(.bottom, 4)
            .accessibilityElement()
            .accessibilityLabel("Progresso")
            .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) por cento")
    }

    // Arrastar 44 pt (ou um gesto rápido) para a borda dispensa só este Toast; incompleto volta.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag = max($0.translation.height, 0) }
            .onEnded {
                if $0.translation.height > 44 || $0.predictedEndTranslation.height > 120 {
                    center.dismiss(toast.id)
                } else {
                    withAnimation(reduceMotion ? nil : Motion.spring(Motion.base)) { drag = 0 }
                }
            }
    }

    private var symbol: String {
        switch toast.tone {
        case .success: "checkmark"
        case .error: "exclamationmark.circle"
        case .attention: "exclamationmark.triangle"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        if toast.content == .loading { return .qOnDark }
        return switch toast.tone {
        case .success: .qAccent
        case .error: .qOverTint
        case .attention: .qAttnTint
        case .info: .qInfoTint
        }
    }
}

/// Pilha na base: o mais novo na frente, os anteriores espiando atrás (até 3). Tocar na pilha abre
/// todos, cada um dispensável; sozinho, o Toast não responde a toque no corpo.
struct ToastStack: View {
    let center: ToastCenter
    @State private var heights: [String: CGFloat] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private let peek: CGFloat = 10
    private let gap: CGFloat = 8

    var body: some View {
        let items = center.visible
        let count = items.count
        let expanded = center.isExpanded
        let frontHeight = items.last.flatMap { heights[$0.id] } ?? 60

        ZStack(alignment: .bottom) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, toast in
                let depth = count - 1 - index
                let collapsedBack = depth > 0 && !expanded
                let fixed: CGFloat? = collapsedBack ? frontHeight : nil
                ToastView(toast: toast, center: center, showsContent: !collapsedBack, fixedHeight: fixed, interactive: !collapsedBack)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if fixed == nil { heights[toast.id] = $0 } }
                    .scaleEffect(collapsedBack ? 1 - 0.05 * CGFloat(depth) : 1, anchor: .bottom)
                    .offset(y: -offset(depth: depth, items: items, expanded: expanded))
                    .zIndex(Double(index))
                    .onTapGesture { if count > 1 { expanded ? center.collapse() : center.expand() } }
                    .accessibilityHidden(collapsedBack)
                    .transition(transition)
            }
        }
        .frame(maxWidth: 420)
        .animation(reduceMotion ? .easeInOut(duration: Motion.quick) : Motion.spring(Motion.considered), value: items)
        .animation(reduceMotion ? .easeInOut(duration: Motion.quick) : Motion.spring(Motion.considered), value: expanded)
        .onChange(of: voiceOver, initial: true) { center.voiceOverRunning = voiceOver }
    }

    // Entrada: +12 → 0 pt, opacidade e escala 0,98 → 1. Reduzir Movimento: só crossfade.
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let move: AnyTransition = .offset(y: 12)
        let scale: AnyTransition = .scale(scale: 0.98)
        return AnyTransition.opacity.combined(with: move).combined(with: scale)
    }

    private func offset(depth: Int, items: [Toast], expanded: Bool) -> CGFloat {
        guard depth > 0 else { return 0 }
        guard expanded else { return CGFloat(depth) * peek }
        // Expandida: cada um sobe a altura de todos os que estão à frente, mais o espaço entre eles.
        return (0..<depth).reduce(0) { $0 + (heights[items[items.count - 1 - $1].id] ?? 60) + gap }
    }
}

extension View {
    /// Apresentador dos Toasts: aplicado uma vez na raiz do app pelo FyinApp; as features usam `@Environment(ToastCenter.self)`.
    /// Fica 12 pt acima do teclado e da safe area, com 20 pt de margem; não bloqueia toque no resto da tela.
    func toastHost(_ center: ToastCenter) -> some View {
        environment(center).overlay(alignment: .bottom) {
            ToastStack(center: center).padding(.horizontal, 20).padding(.bottom, 12)
        }
    }
}
