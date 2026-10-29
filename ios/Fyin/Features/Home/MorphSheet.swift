import SwiftUI

// Superfície única dos morphs da home (boards 16 e 17): um card da home vira este modal e ele se transforma
// por dentro (lista → detalhe → lista → card). Nada empilha. Quem usa decide topo, corpo e rodapé.
struct MorphSheet<Top: View, Content: View, Footer: View>: View {
    /// Destino da geometria: aberto (modal) ou recolhido no card da home.
    let open: Bool
    let hero: Namespace.ID
    /// Id do matchedGeometryEffect do fundo, o mesmo do card de origem na home.
    let shell: String
    /// Status bar → base: acima disso o corpo rola dentro do modal.
    let maxHeight: CGFloat
    /// Fundo e raio do card de origem: recolhido, o modal tem a cara dele.
    var closedFill = Color.qInk
    var closedRadius: CGFloat = 0
    /// Aberto em superfície clara (q/card), como a fatura do cartão; a lista continua escura.
    var light = false
    @Binding var scroll: ScrollPosition
    var onScroll: (CGFloat) -> Void = { _ in }
    let escape: () -> Void
    @ViewBuilder let top: Top
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bodyHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 60
    @State private var footerHeight: CGFloat = 0
    @State private var edges = ScrollEdges()
    /// Sombra só com o modal parado: desenhá-la numa forma que muda a cada frame da mola custa caro.
    @State private var lifted = false

    /// Lado da rolagem com mais conteúdo além da borda: só ali o fade aparece.
    private struct ScrollEdges: Equatable {
        var top = false
        var bottom = false
    }

    // Fade discreto nas bordas da rolagem (16pt em cima, 28pt embaixo) para o texto não terminar em corte seco.
    private var scrollFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(edges.top ? 0 : 1), .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(edges.bottom ? 0 : 1)], startPoint: .top, endPoint: .bottom).frame(height: 28)
        }
        .animation(Motion.standard(Motion.quick), value: edges)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Topo fixo, fora da rolagem: o valor viaja do card da home sem ser recortado pelo ScrollView.
            VStack(alignment: .leading, spacing: 0) { top }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
            ScrollView {
                PageStack { content }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        // A medida chega depois do layout, fora da transação: anima a altura (quadro 13, 320ms).
                        withAnimation(reduceMotion ? nil : Motion.spring(Motion.considered)) { bodyHeight = h }
                    }
            }
            .scrollPosition($scroll)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in onScroll(y) }
            .onScrollGeometryChange(for: ScrollEdges.self) {
                ScrollEdges(top: $0.contentOffset.y > 1, bottom: $0.contentOffset.y + $0.containerSize.height < $0.contentSize.height - 1)
            } action: { _, new in edges = new }
            .frame(height: min(bodyHeight, max(maxHeight - topHeight - footerHeight, 0)))
            // O conteúdo nunca passa da forma do modal: cantos de baixo concêntricos aos do aparelho, topo reto.
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(0)), isUniform: false))
            .mask { scrollFade }
            // Preso embaixo: a lista rola por trás dele.
            footer.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .background {
            // Cantos de baixo concêntricos aos do aparelho; os de cima, longe deles, ficam nos 28 do design.
            ConcentricRectangle(corners: .concentric(minimum: .fixed(open ? 28 : closedRadius)), isUniform: false)
                .fill(open ? (light ? Color.qCard : Color.qInk) : closedFill)
                .stroke((light ? Color.qHairline : Color.qOnDarkLine).opacity(open ? 1 : 0))
                .hero(shell, in: hero, isSource: open, enabled: !reduceMotion)
        }
        // Fora do matchedGeometryEffect: fica no retângulo do modal aberto e só aparece quando ele pousa.
        .background {
            ConcentricRectangle(corners: .concentric(minimum: .fixed(28)), isUniform: false)
                .fill(light ? Color.qCard : Color.qInk)
                .shadow(color: .black.opacity(0.32), radius: 30, y: 24)
                .opacity(lifted ? 1 : 0)
        }
        .onChange(of: open) { _, isOpen in
            // Fechando, some na hora: o modal encolhe e a sombra ficaria no tamanho aberto.
            guard isOpen else { lifted = false; return }
            withAnimation(Motion.standard(Motion.quick).delay(Motion.considered)) { lifted = true }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { escape() }
    }
}

/// Pilha das páginas do modal: o que sai continua desenhado, mas a altura é só a do que entra.
/// Sem isso a altura vai ao maior dos dois durante a troca e só corrige quando a saída termina (sobe em dois tempos).
private struct PageStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let staying = subviews.filter { !$0[Leaving.self] }
        let sizes = (staying.isEmpty ? Array(subviews) : staying).map { $0.sizeThatFits(.init(width: proposal.width, height: nil)) }
        return CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: nil))
        }
    }
}

private struct Leaving: LayoutValueKey {
    static let defaultValue = false
}

private struct LeavingMark: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { content.layoutValue(key: Leaving.self, value: on) }
}

extension MorphSheet where Footer == EmptyView {
    init(open: Bool, hero: Namespace.ID, shell: String, maxHeight: CGFloat, scroll: Binding<ScrollPosition>,
         onScroll: @escaping (CGFloat) -> Void = { _ in }, escape: @escaping () -> Void,
         @ViewBuilder top: () -> Top, @ViewBuilder content: () -> Content) {
        self.init(open: open, hero: hero, shell: shell, maxHeight: maxHeight, scroll: scroll, onScroll: onScroll,
                  escape: escape, top: top, content: content, footer: { EmptyView() })
    }
}

/// Botão redondo de 44pt do topo do modal (Voltar, Fechar). Claro: disco branco sobre q/card.
struct MorphIconButton: View {
    let symbol: String
    let label: String
    var light = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(light ? Color.qInk : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(light ? Color.white : .clear))
                .overlay(Circle().stroke(light ? .clear : Color.qOnDarkLine))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Filter Pill do modal. Escuro: escolhida em lime. Claro (q/card): brancas, escolhida em q/ink.
struct MorphPill: View {
    let title: String
    let selected: Bool
    var light = false
    let action: () -> Void

    private var fill: Color { light ? (selected ? .qInk : .white) : (selected ? .qAccent : .clear) }
    private var ink: Color { light ? (selected ? .white : .qInk) : (selected ? .qInk : .white.opacity(0.7)) }
    private var line: Color { light ? (selected ? .qInk : .qLine) : (selected ? .qAccent : .white.opacity(0.16)) }

    var body: some View {
        Button(action: action) {
            Text(title).font(.urbanist(13, light && selected ? .semibold : .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(line))
            .animation(Motion.standard(Motion.quick), value: selected)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// Total do modal. Em progress 0 é idêntico ao valor do card da home (`from` pt, tinta `ink`, sem centavos)
// e cresce até o do modal (44pt, R$ e centavos esmaecidos) junto com a mola: a troca entre os dois não aparece.
// Os dígitos são SlotText, então o filtro gira os rolos como o saldo da home.
struct MorphTotal: View, Animatable {
    let money: Money
    var progress: Double
    var from: CGFloat = 22
    var ink = Color.white
    /// Tinta aberta: branco no modal escuro, q/ink no claro.
    var to = Color.white

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }

    // Os dígitos ficam sempre em 44pt e crescem por escala: mudar a fonte a cada frame refazia o layout
    // e remedia a altura de cada rolo do SlotText durante toda a mola. Só o "R$" muda de tamanho de verdade.
    var body: some View {
        let parts = money.split
        let tint = ink.mix(with: to, by: progress)
        let scale = lerp(from / 44, 1)
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("R$ ").font(.urbanist(lerp(from, 18) / scale, .light)).foregroundStyle(tint.opacity(lerp(1, 0.3)))
            SlotText(text: parts.whole, value: money.value).foregroundStyle(tint)
            SlotText(text: parts.cents, value: money.value, firstReel: parts.whole.count)
                .foregroundStyle(to.opacity(0.3)).opacity(progress)
        }
        .font(.urbanist(44, .light)).tracking(-1.6)
        .fixedSize()
        .scaleEffect(scale, anchor: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(money.full)
    }
}

// "R$ 358.041,65": centavos e moeda esmaecidos. Os dígitos são SlotText: trocar o valor gira os rolos.
struct MorphAmount: View {
    let money: Money
    var symbol = "R$ "
    var size: CGFloat = 36
    var currency: CGFloat = 16
    /// Sobre q/card: dígitos em q/ink, R$ e centavos em q/ghost.
    var light = false

    var body: some View {
        let parts = money.split
        let faint = light ? Color.qGhost : Color.qOnDark3
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(symbol).font(.urbanist(currency, .light)).foregroundStyle(faint)
            SlotText(text: parts.whole, value: money.value).foregroundStyle(light ? Color.qInk : .white)
            SlotText(text: parts.cents, value: money.value, firstReel: parts.whole.count).foregroundStyle(faint)
        }
        .font(.urbanist(size, .light)).tracking(size * -0.036)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(symbol == "R$ " ? money.full : money.fullUsd)
    }
}

// Pressão de 100ms (escala 0,98), igual para os cards da home e as linhas do modal.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.standard(Motion.instant), value: configuration.isPressed)
    }
}

// Entrada e saída do conteúdo do modal: fade com blur de 4px.
private struct BlurFade: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        content.opacity(hidden ? 0 : 1).blur(radius: hidden ? 4 : 0)
    }
}

extension AnyTransition {
    static let blurFade = AnyTransition.modifier(active: BlurFade(hidden: true), identity: BlurFade(hidden: false))
    /// Troca de página do corpo do modal: só fade (blur numa lista inteira custa caro) e a altura segue a que entra.
    static let page = AnyTransition.opacity.combined(with: .modifier(active: LeavingMark(on: true), identity: LeavingMark(on: false)))
}

extension View {
    func blurFade(_ hidden: Bool) -> some View { modifier(BlurFade(hidden: hidden)) }

    /// matchedGeometryEffect que some com Reduce Motion (aí tudo vira crossfade).
    @ViewBuilder func hero(_ id: String, in namespace: Namespace.ID, isSource: Bool = true, enabled: Bool,
                           properties: MatchedGeometryProperties = .frame, anchor: UnitPoint = .center) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace, properties: properties, anchor: anchor, isSource: isSource)
        } else {
            self
        }
    }
}
