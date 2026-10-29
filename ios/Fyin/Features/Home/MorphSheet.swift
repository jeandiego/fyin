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
                ZStack(alignment: .top) { content }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        // A medida chega depois do layout, fora da transação: anima a altura com a mesma mola.
                        withAnimation(reduceMotion ? nil : Motion.spring(Motion.base)) { bodyHeight = h }
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
                .shadow(color: .black.opacity(open ? 0.32 : 0), radius: 30, y: 24)
                .hero(shell, in: hero, isSource: open, enabled: !reduceMotion)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { escape() }
    }
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

/// Filter Pill sobre o modal escuro: escolhida em lime.
struct MorphPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.urbanist(13))
            .foregroundStyle(selected ? Color.qInk : .white.opacity(0.7))
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(selected ? Color.qAccent : .clear))
            .overlay(Capsule().stroke(selected ? Color.qAccent : .white.opacity(0.16)))
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

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }

    var body: some View {
        let parts = money.split
        let tint = ink.mix(with: .white, by: progress)
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("R$ ").font(.urbanist(lerp(from, 18), .light)).foregroundStyle(tint.opacity(lerp(1, 0.3)))
            SlotText(text: parts.whole, value: money.value).foregroundStyle(tint)
            SlotText(text: parts.cents, value: money.value, firstReel: parts.whole.count)
                .foregroundStyle(.white.opacity(0.3)).opacity(progress)
        }
        .font(.urbanist(lerp(from, 44), .light)).tracking(lerp(0, -1.6))
        .fixedSize()
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
