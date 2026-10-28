import SwiftUI

// Board "16 · Patrimônio investido · Morph": a linha da home vira um único modal que se transforma
// (contas → detalhe → contas → linha). Nada empilha, nada navega.
enum PortfolioPage: Equatable {
    case accounts
    case detail(String)
}

// Ids do matchedGeometryEffect compartilhados entre a linha da home e o modal.
enum PortfolioHero {
    static let shell = "patrimonio"
    static let label = "patrimonio.label"
    static let value = "patrimonio.value"
}

struct PortfolioSheet: View {
    let portfolio: Portfolio
    /// Destino da geometria: aberto (modal) ou recolhido na linha da home.
    let open: Bool
    let hero: Namespace.ID
    /// Status bar → base: acima disso o conteúdo rola dentro do modal.
    let maxHeight: CGFloat
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = PortfolioPage.accounts
    @State private var owner: String?
    @State private var bodyHeight: CGFloat = 0
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var accountsY: CGFloat = 0
    @State private var topHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            // Topo fixo, fora da rolagem: o total viaja da linha da home sem ser recortado pelo ScrollView.
            VStack(alignment: .leading, spacing: 0) {
                header
                if page == .accounts { accountsTotal.transition(.blurFade) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
            ScrollView {
                ZStack(alignment: .top) {
                    switch page {
                    case .accounts: accountsPage.transition(.blurFade)
                    case .detail(let id):
                        if let account = portfolio.accounts.first(where: { $0.id == id }) {
                            detailPage(account).transition(.blurFade)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    // A medida chega depois do layout, fora da transação: anima a altura com a mesma mola.
                    withAnimation(reduceMotion ? nil : Motion.spring(Motion.base)) { bodyHeight = h }
                }
            }
            .scrollPosition($scroll)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                if page == .accounts { accountsY = y }
            }
            .frame(height: min(bodyHeight, max(maxHeight - topHeight, 0)))
        }
        .background {
            RoundedRectangle(cornerRadius: open ? 28 : 0, style: .continuous)
                .fill(Color.qInk)
                .stroke(Color.qOnDarkLine.opacity(open ? 1 : 0))
                .shadow(color: .black.opacity(open ? 0.32 : 0), radius: 30, y: 24)
                .hero(PortfolioHero.shell, in: hero, isSource: open, enabled: !reduceMotion)
        }
        .sensoryFeedback(.selection, trigger: owner)
        .sensoryFeedback(.selection, trigger: page)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { escape() }
        .onChange(of: open) { _, isOpen in
            // Fechado, volta para a lista do início na próxima abertura (o filtro fica).
            if !isOpen, page != .accounts { page = .accounts; scroll.scrollTo(edge: .top) }
        }
    }

    // MARK: Topo

    private var header: some View {
        HStack {
            if case .detail = page {
                iconButton("arrow.left", "Voltar", action: back).keyboardShortcut(.cancelAction)
                    .transition(.blurFade)
            } else {
                Text("Patrimônio investido").font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                    .hero(PortfolioHero.label, in: hero, isSource: open, enabled: !reduceMotion)
                    .padding(.top, 14)
                    .transition(.blurFade)
            }
            Spacer()
            iconButton("xmark", "Fechar", action: close)
                .keyboardShortcut(page == .accounts ? .cancelAction : nil)
                .blurFade(!open)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 16))
        .frame(height: 60, alignment: .bottom)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.qOnDarkLine))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    // MARK: Contas

    private var shown: [Portfolio.Account] { portfolio.accounts(of: owner) }

    private var shownTotal: Money { Money(shown.reduce(0) { $0 + $1.total.value }) }

    private var accountsTotal: some View {
        VStack(alignment: .leading, spacing: 6) {
            amount(shownTotal, size: 44, currency: 18)
                .hero(PortfolioHero.value, in: hero, isSource: open, enabled: !reduceMotion)
            Text(countLine).font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                .contentTransition(.opacity)
                .blurFade(!open)
        }
        .padding(EdgeInsets(top: 6, leading: 20, bottom: 0, trailing: 20))
    }

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if portfolio.owners.count > 1 { ownerFilter }
                LazyVStack(spacing: 0) {
                    ForEach(shown) { account in
                        accountRow(account)
                            .overlay(alignment: .bottom) {
                                if account.id != shown.last?.id {
                                    Rectangle().fill(Color.qOnDarkLine).frame(height: 1).padding(.leading, 72).padding(.trailing, 20)
                                }
                            }
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
                .padding(.bottom, 12)
            }
            .blurFade(!open)
            .animation(open && !reduceMotion ? Motion.spring(Motion.considered).delay(Motion.considered * 0.3) : Motion.standard(Motion.instant), value: open)
        }
    }

    // "3 contas de Jean e Poliana" no total; com filtro, "2 contas de Poliana · 18,7% do total".
    private var countLine: String {
        let count = shown.count == 1 ? "1 conta" : "\(shown.count) contas"
        guard let owner else {
            let names = portfolio.owners.map { $0.capitalized(with: PortfolioKind.ptBR) }
            return names.isEmpty ? "Nenhuma conta" : "\(count) de \(names.formatted(.list(type: .and).locale(PortfolioKind.ptBR)))"
        }
        let name = owner.capitalized(with: PortfolioKind.ptBR)
        return "\(count) de \(name) · \(PortfolioKind.share(shownTotal, of: portfolio.total)) do total"
    }

    private var ownerFilter: some View {
        HStack(spacing: 6) {
            pill("Todos", nil)
            ForEach(portfolio.owners, id: \.self) { pill($0.capitalized(with: PortfolioKind.ptBR), $0) }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 6, trailing: 20))
    }

    private func pill(_ title: String, _ value: String?) -> some View {
        let selected = owner == value
        return Button {
            guard !selected else { return }
            withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) { owner = value }
        } label: {
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

    @ViewBuilder private func accountRow(_ account: Portfolio.Account) -> some View {
        let row = HStack(spacing: 12) {
            InstitutionAvatar(institution: account.institution)
                .hero("\(account.id).avatar", in: hero, enabled: !reduceMotion)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.institution).font(.urbanist(15)).foregroundStyle(.white)
                    .hero("\(account.id).name", in: hero, enabled: !reduceMotion)
                Text(account.subtitle).font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(account.total.full).font(.urbanist(15)).tracking(-0.2).foregroundStyle(.white)
                    .hero("\(account.id).value", in: hero, enabled: !reduceMotion)
                Text(PortfolioKind.share(account.total, of: shownTotal)).font(.urbanist(12)).foregroundStyle(Color.qOnDark3)
                    .contentTransition(.opacity)
            }
            Image("chevron-right").resizable().frame(width: 16, height: 16).foregroundStyle(Color.qOnDark3)
                .opacity(account.manual ? 0 : 1)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
        .frame(minHeight: 64)
        .contentShape(.rect)

        if account.manual {
            row.accessibilityElement(children: .combine)
        } else {
            Button { go(.detail(account.id)) } label: { row }
                .buttonStyle(PressStyle())
                .accessibilityHint("Abre as posições da conta")
        }
    }

    // MARK: Detalhe

    private func detailPage(_ account: Portfolio.Account) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                InstitutionAvatar(institution: account.institution, size: 48)
                    .hero("\(account.id).avatar", in: hero, enabled: !reduceMotion)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.institution).font(.urbanist(22)).foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .hero("\(account.id).name", in: hero, enabled: !reduceMotion)
                    Text(account.subtitle).font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
                }
                .lineLimit(1)
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text("Total investido").font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                amount(account.total, size: 36, currency: 16)
                    .hero("\(account.id).value", in: hero, enabled: !reduceMotion)
                Text("\(PortfolioKind.share(account.total, of: portfolio.total)) do patrimônio · \(positions(account.positionCount))")
                    .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))

            ForEach(account.groups, id: \.kind) { group($0, in: account) }
            Color.clear.frame(height: 20)
        }
    }

    private func positions(_ n: Int) -> String { n == 1 ? "1 posição" : "\(n) posições" }

    private func group(_ group: Portfolio.Group, in account: Portfolio.Account) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(Text(PortfolioKind.label(group.kind)).font(.urbanist(13, .semibold)).foregroundStyle(.white)) · \(group.positions.count)")
                    .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                Spacer()
                Text("\(group.total.full) · \(PortfolioKind.share(group.total, of: account.total))")
                    .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
            }
            .padding(.bottom, 4)
            ForEach(Array(group.positions.enumerated()), id: \.offset) { i, position in
                positionRow(position, label: PortfolioKind.label(group.kind), in: account)
                    .overlay(alignment: .bottom) {
                        if i < group.positions.count - 1 { Rectangle().fill(Color.qOnDarkLine).frame(height: 1) }
                    }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
    }

    private func positionRow(_ p: Portfolio.Position, label: String, in account: Portfolio.Account) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    // A Pluggy às vezes manda o nome vazio: vale o rótulo do produto.
                    Text(p.name.isEmpty ? label : p.name).font(.urbanist(15)).foregroundStyle(.white).lineLimit(2)
                    if !p.detail.isEmpty {
                        Text(p.detail).font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.balance.full).font(.urbanist(15)).tracking(-0.2).foregroundStyle(.white)
                    Text(PortfolioKind.share(p.balance, of: account.total)).font(.urbanist(12)).foregroundStyle(Color.qOnDark3)
                }
            }
            // Peso da posição na conta.
            Capsule().fill(Color.qOnDarkLine).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(.white).frame(width: g.size.width * PortfolioKind.fraction(p.balance, of: account.total))
                    }
                }
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // "R$ 358.041,65": centavos e moeda esmaecidos. Um Text só, para encolher inteiro enquanto viaja da linha.
    private func amount(_ money: Money, size: CGFloat, currency: CGFloat) -> some View {
        let parts = money.split
        return Text("\(Text("R$ ").font(.urbanist(currency, .light)).foregroundStyle(Color.qOnDark3))\(Text(parts.whole).foregroundStyle(.white))\(Text(parts.cents).foregroundStyle(Color.qOnDark3))")
            .font(.urbanist(size, .light)).tracking(size * -0.036)
            .lineLimit(1).minimumScaleFactor(0.3)
            .contentTransition(.opacity)
            .accessibilityLabel(money.full)
    }

    // MARK: Ações

    private func go(_ next: PortfolioPage) {
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.considered)) {
            page = next
            scroll.scrollTo(edge: .top)
        }
    }

    // Volta para a lista com a rolagem de antes.
    private func back() {
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) {
            page = .accounts
            scroll.scrollTo(y: accountsY)
        }
    }

    private func escape() {
        if case .detail = page { back() } else { close() }
    }
}

// Pressão de 100ms (escala 0,98), igual para a linha da home e as linhas do modal.
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
    @ViewBuilder func hero(_ id: String, in namespace: Namespace.ID, isSource: Bool = true, enabled: Bool) -> some View {
        if enabled { matchedGeometryEffect(id: id, in: namespace, isSource: isSource) } else { self }
    }
}
