import SwiftUI

// Board "16 · Patrimônio investido · Morph": a linha da home vira o MorphSheet, que se transforma
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
    @State private var currency = DisplayCurrency.brl
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var accountsY: CGFloat = 0

    var body: some View {
        MorphSheet(open: open, hero: hero, shell: PortfolioHero.shell, maxHeight: maxHeight, scroll: $scroll,
                   onScroll: { if page == .accounts { accountsY = $0 } }, escape: escape) {
            header
            if page == .accounts { accountsTotal.transition(.blurFade) }
        } content: {
            switch page {
            case .accounts: accountsPage.transition(.blurFade)
            case .detail(let id):
                if let account = portfolio.accounts.first(where: { $0.id == id }) {
                    detailPage(account).transition(.blurFade)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: owner)
        .sensoryFeedback(.selection, trigger: currency)
        .sensoryFeedback(.selection, trigger: page)
        .onChange(of: open) { _, isOpen in
            guard !isOpen else { return }
            if page != .accounts { page = .accounts; scroll.scrollTo(edge: .top) }
            currency = .brl
            // O valor pousa na linha da home, que mostra o total de todos: com filtro, os rolos giram de volta
            // enquanto o modal encolhe, em vez de o número trocar de uma vez no pouso.
            if owner != nil { withAnimation(Motion.spring(Motion.base)) { owner = nil } }
        }
    }

    // MARK: Topo

    private var header: some View {
        HStack {
            if case .detail = page {
                MorphIconButton(symbol: "arrow.left", label: "Voltar", action: back).keyboardShortcut(.cancelAction)
                    .transition(.blurFade)
            } else {
                Text("Patrimônio investido").font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                    .hero(PortfolioHero.label, in: hero, isSource: open, enabled: !reduceMotion)
                    .padding(.top, 14)
                    .transition(.blurFade)
            }
            Spacer()
            MorphIconButton(symbol: "xmark", label: "Fechar", action: close)
                .keyboardShortcut(page == .accounts ? .cancelAction : nil)
                .blurFade(!open)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 16))
        .frame(height: 60, alignment: .bottom)
    }

    // MARK: Contas

    private var shown: [Portfolio.Account] { portfolio.accounts(of: owner) }

    private var shownTotal: Money { Money(shown.reduce(0) { $0 + $1.total.value }) }

    private var accountsTotal: some View {
        VStack(alignment: .leading, spacing: 6) {
            MorphTotal(money: shownTotal, progress: open ? 1 : 0)
                .hero(PortfolioHero.value, in: hero, isSource: open, enabled: !reduceMotion, properties: .position, anchor: .leading)
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
        MorphPill(title: title, selected: owner == value) {
            guard owner != value else { return }
            withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) { owner = value }
        }
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
        // Conta sem dólar (ou sem cotação) ignora a escolha: nada a alternar.
        let dollar = account.hasDollar(rate: portfolio.usdRate)
        let shownCurrency = dollar ? currency : .brl
        return VStack(alignment: .leading, spacing: 0) {
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
                HStack {
                    Text("Total investido").font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                    Spacer()
                    if dollar { currencyToggle }
                }
                // Uma só instância nos dois modos: os rolos giram do valor em reais para o em dólar.
                let usd = shownCurrency == .usd ? account.totalUsd : nil
                MorphAmount(money: usd ?? account.total, symbol: usd == nil ? "R$ " : "US$ ")
                    .hero("\(account.id).value", in: hero, enabled: !reduceMotion, properties: .position, anchor: .leading)
                Text("\(PortfolioKind.share(account.total, of: portfolio.total)) do patrimônio · \(positions(account.positionCount))")
                    .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                if dollar, let rate = portfolio.usdRate.flatMap(PortfolioKind.decimal) {
                    Text(rateNote(rate))
                        .font(.urbanist(12)).foregroundStyle(Color.qOnDark3)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))

            ForEach(account.groups, id: \.kind) { group($0, in: account, currency: shownCurrency) }
            Color.clear.frame(height: 20)
        }
    }

    private func positions(_ n: Int) -> String { n == 1 ? "1 posição" : "\(n) posições" }

    // "R$ | US$": reais é o padrão e o dólar é a leitura original da corretora.
    private var currencyToggle: some View {
        SegmentedSwitch(options: [DisplayCurrency.brl, .usd], selection: $currency, label: "Moeda") { $0 == .brl ? "R$" : "US$" }
    }

    // "Convertido pela PTAX de 28 out · US$ 1 = R$ 5,4512".
    private func rateNote(_ rate: Decimal) -> String {
        let day = portfolio.usdRateDate.map { " de \(MonthLabel.day($0))" } ?? ""
        let value = rate.formatted(.number.precision(.fractionLength(4)).locale(PortfolioKind.ptBR))
        return "Convertido pela PTAX\(day) · US$ 1 = R$ \(value)"
    }

    private func group(_ group: Portfolio.Group, in account: Portfolio.Account, currency: DisplayCurrency) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(Text(PortfolioKind.label(group.kind)).font(.urbanist(13, .semibold)).foregroundStyle(.white)) · \(group.positions.count)")
                    .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                Spacer()
                let usd = currency == .usd ? group.totalUsd : nil
                let total = usd ?? group.total
                HStack(spacing: 0) {
                    SlotText(text: usd == nil ? total.full : total.fullUsd, value: total.value)
                    Text(" · \(PortfolioKind.share(group.total, of: account.total))")
                }
                .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
            }
            .padding(.bottom, 4)
            ForEach(Array(group.positions.enumerated()), id: \.offset) { i, position in
                positionRow(position, label: PortfolioKind.label(group.kind), in: account, currency: currency)
                    .overlay(alignment: .bottom) {
                        if i < group.positions.count - 1 { Rectangle().fill(Color.qOnDarkLine).frame(height: 1) }
                    }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
    }

    private func positionRow(_ p: Portfolio.Position, label: String, in account: Portfolio.Account, currency: DisplayCurrency) -> some View {
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
                    SlotText(text: p.value(currency), value: p.amount(currency).value)
                        .font(.urbanist(15)).tracking(-0.2).foregroundStyle(.white)
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

