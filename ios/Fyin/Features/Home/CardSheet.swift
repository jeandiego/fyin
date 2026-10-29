import SwiftUI

// Board "17 · Cartão · Morph": o card "Cartão" da home vira o MorphSheet, que se transforma
// (cartões → fatura → outra fatura → cartões → card). Só "Ver detalhes do cartão" sai dele, por push na pilha da home.
enum CardsPage: Equatable {
    case cards
    case bill(String)
}

// Ids do matchedGeometryEffect compartilhados entre o card da home e o modal.
enum CardsHero {
    static let shell = "cartao"
    static let label = "cartao.label"
    static let value = "cartao.value"
}

/// Rota da tela do cartão: o cartão e a fatura que estava aberta no modal.
struct CardRoute: Hashable {
    let id: String
    let period: String
}

struct CardSheet: View {
    /// nil até a primeira busca chegar (skeleton) ou se ela falhar sem nada salvo (retry).
    let overview: CardsOverview?
    let failed: Bool
    /// Total que a home já mostra: vale enquanto as faturas não chegam.
    let fallbackTotal: Money
    let open: Bool
    let hero: Namespace.ID
    let maxHeight: CGFloat
    let close: () -> Void
    let retry: () async -> Void
    let details: (CardRoute) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = CardsPage.cards
    @State private var owner: String?
    @State private var period: String?
    /// Período mais novo que o anterior: entra pela direita.
    @State private var forward = true
    @State private var pill: String?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var cardsY: CGFloat = 0
    @State private var retrying = false

    private var card: CardsOverview.Card? {
        guard case .bill(let id) = page else { return nil }
        return overview?.cards.first { $0.id == id }
    }

    private var bill: CardsOverview.Bill? { period.flatMap { card?.bill($0) } }

    var body: some View {
        MorphSheet(open: open, hero: hero, shell: CardsHero.shell, maxHeight: maxHeight, closedFill: .qCard, closedRadius: 18,
                   scroll: $scroll, onScroll: { if page == .cards { cardsY = $0 } }, escape: escape) {
            header
            if let card, let bill {
                billTop(card, bill).transition(.blurFade)
            } else {
                cardsTotal.transition(.blurFade)
            }
        } content: {
            if let card, let bill {
                ZStack(alignment: .top) { billLines(bill).id(bill.period).transition(periodShift) }
                    .transition(.blurFade)
            } else {
                cardsPage.transition(.blurFade)
            }
        } footer: {
            if let card, let period { detailsButton(card, period).transition(.blurFade) }
        }
        .sensoryFeedback(.selection, trigger: owner)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.selection, trigger: period)
        .onChange(of: open) { _, isOpen in
            guard !isOpen else { return }
            if page != .cards { page = .cards; period = nil; scroll.scrollTo(edge: .top) }
            // O valor pousa no card da home, que mostra o total de todos: com filtro, os rolos giram de volta.
            if owner != nil { withAnimation(Motion.spring(Motion.base)) { owner = nil } }
        }
    }

    // MARK: Topo

    private var header: some View {
        HStack {
            if page == .cards {
                Text("Cartão").font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                    .hero(CardsHero.label, in: hero, isSource: open, enabled: !reduceMotion)
                    .padding(.top, 14)
                    .transition(.blurFade)
            } else {
                MorphIconButton(symbol: "arrow.left", label: "Voltar", action: back).keyboardShortcut(.cancelAction)
                    .transition(.blurFade)
            }
            Spacer()
            MorphIconButton(symbol: "xmark", label: "Fechar", action: close)
                .keyboardShortcut(page == .cards ? .cancelAction : nil)
                .blurFade(!open)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 16))
        .frame(height: 60, alignment: .bottom)
    }

    // MARK: Cartões

    private var shown: [CardsOverview.Card] { overview?.cards(of: owner) ?? [] }

    private var shownTotal: Money { overview == nil ? fallbackTotal : CardsOverview.total(of: shown) }

    private var cardsTotal: some View {
        VStack(alignment: .leading, spacing: 6) {
            MorphTotal(money: shownTotal, progress: open ? 1 : 0, from: 24, ink: .qInk)
                .hero(CardsHero.value, in: hero, isSource: open, enabled: !reduceMotion, properties: .position, anchor: .leading)
            Text(countLine).font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                .contentTransition(.opacity)
                .blurFade(!open)
        }
        .padding(EdgeInsets(top: 6, leading: 20, bottom: 0, trailing: 20))
    }

    // "Faturas atuais · 4 cartões de Jean e Poliana"; com filtro, "… · 2 cartões de Poliana · 51,8% do total".
    private var countLine: String {
        guard let overview else { return failed ? "Faturas atuais" : "Buscando as faturas dos cartões" }
        let count = shown.count == 1 ? "1 cartão" : "\(shown.count) cartões"
        guard let owner else {
            let names = overview.owners.map { $0.capitalized(with: PortfolioKind.ptBR) }
            return names.isEmpty ? "Nenhum cartão conectado" : "Faturas atuais · \(count) de \(names.formatted(.list(type: .and).locale(PortfolioKind.ptBR)))"
        }
        let name = owner.capitalized(with: PortfolioKind.ptBR)
        return "Faturas atuais · \(count) de \(name) · \(PortfolioKind.share(shownTotal, of: overview.total)) do total"
    }

    private var cardsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let overview {
                    if overview.owners.count > 1 { ownerFilter(overview.owners) }
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { card in
                            cardRow(card)
                                .overlay(alignment: .bottom) {
                                    if card.id != shown.last?.id {
                                        Rectangle().fill(Color.qOnDarkLine).frame(height: 1).padding(.leading, 72).padding(.trailing, 20)
                                    }
                                }
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 12)
                } else if failed {
                    retryRow
                } else {
                    // Primeira abertura sem nada salvo (board 11): a forma das linhas, com o total que a home já tinha.
                    VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in skeletonRow } }
                        .padding(.vertical, 4)
                        .padding(.bottom, 12)
                }
            }
            .blurFade(!open)
            .animation(open && !reduceMotion ? Motion.spring(Motion.considered).delay(Motion.considered * 0.3) : Motion.standard(Motion.instant), value: open)
        }
    }

    private func ownerFilter(_ owners: [String]) -> some View {
        HStack(spacing: 6) {
            filterPill("Todos", nil)
            ForEach(owners, id: \.self) { filterPill($0.capitalized(with: PortfolioKind.ptBR), $0) }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 6, trailing: 20))
    }

    private func filterPill(_ title: String, _ value: String?) -> some View {
        MorphPill(title: title, selected: owner == value) {
            guard owner != value else { return }
            withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) { owner = value }
        }
    }

    // Cada cartão é uma linha, mesmo no mesmo banco, com a fatura atual pelo ciclo dele.
    private func cardRow(_ card: CardsOverview.Card) -> some View {
        let bill = card.currentBill
        return Button { go(card) } label: {
            HStack(spacing: 12) {
                InstitutionAvatar(institution: card.institution)
                    .hero("\(card.id).avatar", in: hero, enabled: !reduceMotion)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.institution).font(.urbanist(15)).foregroundStyle(.white)
                            .hero("\(card.id).name", in: hero, enabled: !reduceMotion)
                        Text(card.suffix).font(.urbanist(13)).foregroundStyle(Color.qOnDark3)
                    }
                    Text("\(card.ownerName) · \(bill?.due ?? "sem fatura")").font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text((bill?.total ?? Money(0)).full).font(.urbanist(15)).tracking(-0.2).foregroundStyle(.white)
                        .hero("\(card.id).value", in: hero, enabled: !reduceMotion)
                    if let bill { status(bill, size: 12) }
                }
                Image("chevron-right").resizable().frame(width: 16, height: 16).foregroundStyle(Color.qOnDark3)
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Abre a fatura atual do cartão")
    }

    private func status(_ bill: CardsOverview.Bill, text: String? = nil, size: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle().fill(bill.dot).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text ?? bill.label).font(.urbanist(size)).foregroundStyle(Color.qOnDark2).contentTransition(.opacity)
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).frame(width: 40, height: 40).skeleton(true, dark: true, radius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nubank •• 0000").font(.urbanist(15)).skeleton(true, dark: true)
                Text("Titular · vence 10 nov").font(.urbanist(12)).skeleton(true, dark: true)
            }
            Spacer()
            Text("R$ 0.000,00").font(.urbanist(15)).skeleton(true, dark: true)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
        .frame(minHeight: 64)
        .accessibilityHidden(true)
    }

    // Retry Row no lugar das linhas; o total acima continua sendo o da home.
    private var retryRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("As faturas não carregaram").font(.urbanist(15)).foregroundStyle(.white)
                Text("O total acima é o último da Início").font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            } label: {
                Text(retrying ? "Tentando…" : "Tentar agora").font(.urbanist(13, .semibold)).foregroundStyle(Color.qInk)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Color.white, in: .capsule)
            }
            .buttonStyle(PressStyle())
            .disabled(retrying)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.qOnDarkLine))
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 20, trailing: 20))
    }

    // MARK: Fatura

    private func billTop(_ card: CardsOverview.Card, _ bill: CardsOverview.Bill) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                InstitutionAvatar(institution: card.institution, size: 48)
                    .hero("\(card.id).avatar", in: hero, enabled: !reduceMotion)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.institution).font(.urbanist(22)).foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .hero("\(card.id).name", in: hero, enabled: !reduceMotion)
                    Text(card.holder).font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
                }
                .lineLimit(1)
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))

            periodPills(card).padding(.top, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title(bill)).font(.urbanist(13)).foregroundStyle(Color.qOnDark2).contentTransition(.opacity)
                MorphAmount(money: bill.total)
                    .hero("\(card.id).value", in: hero, enabled: !reduceMotion, properties: .position, anchor: .leading)
                status(bill, text: bill.detail, size: 13)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
        }
    }

    // Faturas anteriores, a atual (com ponto) e as futuras; a escolhida fica lime e rola para o centro.
    private func periodPills(_ card: CardsOverview.Card) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(card.bills, id: \.period) { b in
                    MorphPill(title: card.pill(b.period), selected: b.period == period, marked: b.period == card.current) {
                        choose(b.period)
                    }
                    .id(b.period)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $pill, anchor: .center)
    }

    private func billLines(_ bill: CardsOverview.Bill) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if bill.lines.isEmpty {
                emptyBill(bill)
            } else {
                HStack {
                    Text("\(Text(bill.status == .future ? "Parcelas já lançadas" : "Lançamentos").font(.urbanist(13, .semibold)).foregroundStyle(.white)) · \(bill.lines.count)")
                        .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                    Spacer()
                    Text(bill.range).font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
                }
                .padding(.bottom, 4)
                ForEach(Array(bill.lines.enumerated()), id: \.offset) { i, line in
                    lineRow(line)
                        .overlay(alignment: .bottom) {
                            if i < bill.lines.count - 1 { Rectangle().fill(Color.qOnDarkLine).frame(height: 1) }
                        }
                }
                if bill.status == .future {
                    Text("Não é previsão: só o que já está agendado. Compras novas entram até o fechamento, \(MonthLabel.day(bill.closingDate)).")
                        .font(.urbanist(12)).foregroundStyle(Color.qOnDark3)
                        .padding(.top, 12)
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 20, trailing: 20))
    }

    // Sem parcela, sem número inventado: R$ 0,00 em cima e o aviso no lugar da lista.
    private func emptyBill(_ bill: CardsOverview.Bill) -> some View {
        let pending = bill.status == .open || bill.status == .future
        return VStack(alignment: .leading, spacing: 6) {
            Text("Nada lançado para \(MonthLabel.long(bill.period)) ainda").font(.urbanist(17, .semibold)).foregroundStyle(.white)
            Text(pending
                 ? "Parcelas e assinaturas aparecem aqui assim que caírem nesta fatura. Compras novas entram até o fechamento, \(MonthLabel.day(bill.closingDate))."
                 : "O banco não mandou lançamentos desta fatura.")
                .font(.urbanist(13)).foregroundStyle(Color.qOnDark2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.qOnDarkLine))
    }

    private func lineRow(_ line: CardsOverview.Line) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description).font(.urbanist(15)).foregroundStyle(.white).lineLimit(1)
                Text(line.detail).font(.urbanist(12)).foregroundStyle(Color.qOnDark2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.amount.full).font(.urbanist(15)).tracking(-0.2).monospacedDigit().foregroundStyle(.white)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func detailsButton(_ card: CardsOverview.Card, _ period: String) -> some View {
        Button { details(CardRoute(id: card.id, period: period)) } label: {
            Text("Ver detalhes do cartão").font(.urbanist(15)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .overlay(Capsule().stroke(Color.white.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 20, trailing: 20))
    }

    /// Anterior entra pela esquerda, próxima pela direita (12px + fade); com Reduce Motion, só crossfade.
    private var periodShift: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 12 : -12).combined(with: .opacity),
                           removal: .offset(x: forward ? -12 : 12).combined(with: .opacity))
    }

    // MARK: Ações

    // Abre sempre na fatura atual daquele cartão.
    private func go(_ card: CardsOverview.Card) {
        forward = true
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.considered)) {
            page = .bill(card.id)
            period = card.current
            scroll.scrollTo(edge: .top)
        }
        pill = card.current
    }

    // Tocar de novo no mesmo período é ignorado; outro no meio da troca retoma dali.
    private func choose(_ next: String) {
        guard next != period else { return }
        forward = next > (period ?? "")
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) {
            period = next
            pill = next
            scroll.scrollTo(edge: .top)
        }
    }

    // Volta com o filtro e a rolagem de antes; o período escolhido é esquecido.
    private func back() {
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) {
            page = .cards
            period = nil
            scroll.scrollTo(y: cardsY)
        }
    }

    private func escape() {
        if page == .cards { close() } else { back() }
    }
}

// Tela do cartão (board 17, quadro 13): saída provisória do modal, rota já pronta.
struct CardScreen: View {
    let card: CardsOverview.Card?
    let route: CardRoute

    @Environment(\.dismiss) private var dismiss

    private var subtitle: String {
        guard let card, let bill = card.bill(route.period) else { return "" }
        return "\(card.ownerName) · fatura de \(MonthLabel.long(bill.period)) \(bill.label.lowercased())"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.qInk)
                            .frame(width: 44, height: 44).background(Color.qCard, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voltar")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.map { "\($0.institution) \($0.suffix)" } ?? "Cartão")
                            .font(.urbanist(28, .semibold)).tracking(-1.2).foregroundStyle(Color.qInk)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle).font(.urbanist(13)).foregroundStyle(Color.qText2)
                    }
                }
                .padding(.horizontal, 8).padding(.top, 4)

                // Empty State: motivo + um próximo passo.
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "creditcard").font(.system(size: 20)).foregroundStyle(Color.qInk)
                        .frame(width: 40, height: 40).background(Color.qBg, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    Text("A tela do cartão chega na próxima versão").font(.urbanist(17, .semibold)).foregroundStyle(Color.qInk)
                    Text("Limite, todas as faturas e ajustes do cartão vão morar aqui. Por enquanto, a fatura continua no Início.")
                        .font(.urbanist(14)).foregroundStyle(Color.qText2)
                    Button { dismiss() } label: {
                        Text("Voltar para a fatura").font(.urbanist(15)).foregroundStyle(Color.qInk)
                            .padding(.horizontal, 18).frame(height: 44)
                            .background(Color.qBg, in: .capsule)
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.qCard, in: .rect(cornerRadius: 18))
            }
            .padding(.horizontal, 12).padding(.bottom, 24)
        }
        .background(Color.qBg)
    }
}

#Preview {
    @Previewable @Namespace var hero
    @Previewable @State var overview: CardsOverview?
    ZStack(alignment: .bottom) {
        Color.qBg.ignoresSafeArea()
        CardSheet(overview: overview, failed: false, fallbackTotal: Money(3420), open: true, hero: hero, maxHeight: 760,
                  close: {}, retry: {}, details: { _ in })
            .padding(8)
    }
    .task { overview = try? await PreviewHomeRepository().cards() }
}
