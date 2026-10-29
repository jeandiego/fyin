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
    /// Fatura ou cartão mais à frente que o anterior: entra pela direita.
    @State private var forward = true
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var cardsY: CGFloat = 0
    @State private var retrying = false
    /// Seletor de fatura aberto sobre o topo do modal.
    @State private var picking = false
    /// Arrasto lateral da fatura, já amortecido: troca de cartão ao soltar além de 64pt ou num flick.
    @State private var drag: CGFloat = 0
    /// Direção do arrasto, decidida nos primeiros 8pt: horizontal troca de cartão, vertical fica com a rolagem.
    @State private var lateral: Bool?

    private var card: CardsOverview.Card? {
        guard case .bill(let id) = page else { return nil }
        return overview?.cards.first { $0.id == id }
    }

    private var bill: CardsOverview.Bill? { period.flatMap { card?.bill($0) } }

    var body: some View {
        MorphSheet(open: open, hero: hero, shell: CardsHero.shell, maxHeight: maxHeight, closedFill: .qCard, closedRadius: 18,
                   light: true, scroll: $scroll, onScroll: { if page == .cards { cardsY = $0 } }, escape: escape) {
            header
            if let card, let bill {
                billTop(card, bill).transition(.blurFade)
            } else {
                cardsTotal.transition(.blurFade)
            }
        } content: {
            if let card, let bill {
                ZStack(alignment: .top) {
                    billLines(bill).dragged(drag, dragOpacity).id("\(card.id)·\(bill.period)").transition(shift)
                }
                .transition(.blurFade)
            } else {
                cardsPage.transition(.blurFade)
            }
        } footer: {
            if let card, let period { detailsButton(card, period).transition(.blurFade) }
        }
        .overlay(alignment: .top) {
            if picking, let card, let bill { picker(card, chosen: bill).transition(pickerShift) }
        }
        .simultaneousGesture(cardDrag, isEnabled: bill != nil && !picking)
        .sensoryFeedback(.selection, trigger: owner)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.selection, trigger: period)
        .onChange(of: open) { _, isOpen in
            guard !isOpen else { return }
            picking = false
            if page != .cards { page = .cards; period = nil; scroll.scrollTo(edge: .top) }
            // O valor pousa no card da home, que mostra o total de todos: com filtro, os rolos giram de volta.
            if owner != nil { withAnimation(Motion.spring(Motion.base)) { owner = nil } }
        }
    }

    // MARK: Topo

    private var header: some View {
        HStack {
            if page == .cards {
                Text("Cartão").font(.urbanist(13)).foregroundStyle(Color.qText2)
                    .hero(CardsHero.label, in: hero, isSource: open, enabled: !reduceMotion)
                    .padding(.top, 14)
                    .transition(.blurFade)
            } else {
                MorphIconButton(symbol: "arrow.left", label: "Voltar", light: true, action: back).keyboardShortcut(.cancelAction)
                    .transition(.blurFade)
            }
            Spacer()
            if let bill, page != .cards {
                selector(bill).transition(.blurFade)
                Spacer()
            }
            MorphIconButton(symbol: "xmark", label: "Fechar", light: true, action: close)
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
            MorphTotal(money: shownTotal, progress: open ? 1 : 0, from: 24, ink: .qInk, to: .qInk)
                .hero(CardsHero.value, in: hero, isSource: open, enabled: !reduceMotion, properties: .position, anchor: .leading)
            Text(countLine).font(.urbanist(13)).foregroundStyle(Color.qText2)
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
                                        Rectangle().fill(Color.qLine).frame(height: 1).padding(.leading, 72).padding(.trailing, 20)
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
        MorphPill(title: title, selected: owner == value, light: true) {
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
                        Text(card.institution).font(.urbanist(15)).foregroundStyle(Color.qInk)
                            .hero("\(card.id).name", in: hero, enabled: !reduceMotion)
                        Text(card.suffix).font(.urbanist(13)).foregroundStyle(Color.qText3)
                    }
                    Text("\(card.ownerName) · \(bill?.due ?? "sem fatura")").font(.urbanist(12)).foregroundStyle(Color.qText2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text((bill?.total ?? Money(0)).full).font(.urbanist(15)).tracking(-0.2).foregroundStyle(Color.qInk)
                        .hero("\(card.id).value", in: hero, enabled: !reduceMotion)
                    if let bill { status(bill, size: 12) }
                }
                Image("chevron-right").resizable().frame(width: 16, height: 16).foregroundStyle(Color.qText3)
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
            dot(bill)
            Text(text ?? bill.label).font(.urbanist(size)).foregroundStyle(Color.qText2)
                .contentTransition(.opacity)
        }
    }

    // Futura é um anel: ainda não aconteceu.
    @ViewBuilder private func dot(_ bill: CardsOverview.Bill) -> some View {
        Group {
            if bill.status == .future {
                Circle().strokeBorder(bill.dot, lineWidth: 1.2)
            } else {
                Circle().fill(bill.dot)
            }
        }
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).frame(width: 40, height: 40).skeleton(true, radius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nubank •• 0000").font(.urbanist(15)).skeleton(true)
                Text("Titular · vence 10 nov").font(.urbanist(12)).skeleton(true)
            }
            Spacer()
            Text("R$ 0.000,00").font(.urbanist(15)).skeleton(true)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
        .frame(minHeight: 64)
        .accessibilityHidden(true)
    }

    // Retry Row no lugar das linhas; o total acima continua sendo o da home.
    private var retryRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("As faturas não carregaram").font(.urbanist(15)).foregroundStyle(Color.qInk)
                Text("O total acima é o último da Início").font(.urbanist(12)).foregroundStyle(Color.qText2)
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
                    .overlay(Capsule().stroke(Color.qLine))
            }
            .buttonStyle(PressStyle())
            .disabled(retrying)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.qLine))
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 20, trailing: 20))
    }

    // MARK: Fatura

    private func billTop(_ card: CardsOverview.Card, _ bill: CardsOverview.Bill) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    InstitutionAvatar(institution: card.institution, size: 48)
                        .hero("\(card.id).avatar", in: hero, enabled: !reduceMotion)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.institution).font(.urbanist(22)).foregroundStyle(Color.qInk)
                            .minimumScaleFactor(0.5)
                            .hero("\(card.id).name", in: hero, enabled: !reduceMotion)
                        Text(card.holder).font(.urbanist(12)).foregroundStyle(Color.qText2)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 108))

                VStack(alignment: .leading, spacing: 4) {
                    MorphAmount(money: bill.total, light: true)
                        .hero("\(card.id).value", in: hero, enabled: !reduceMotion, properties: .position, anchor: .leading)
                    status(bill, text: bill.detail, size: 13)
                    if let pending = card.pending(before: bill.period) { pendingRow(pending) }
                }
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 20))
            }
            .dragged(drag, dragOpacity)
            .id(card.id)
            .transition(shift)
        }
        // O paginador fica parado enquanto o conteúdo do cartão desliza por baixo dele.
        .overlay(alignment: .topTrailing) { pager(card).padding(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 12)) }
    }

    // "Novembro 2026 ⌄": abre a lista de faturas do cartão sobre o topo do modal.
    private func selector(_ bill: CardsOverview.Bill) -> some View {
        Button { setPicking(true) } label: { selectorLabel(bill.month, open: false).frame(height: 36) }
            .buttonStyle(PressStyle())
            .overlay(Capsule().stroke(Color.qLine))
            .accessibilityLabel("Fatura de \(bill.month)")
            .accessibilityHint("Escolhe outra fatura do cartão")
    }

    private func selectorLabel(_ month: String, open: Bool) -> some View {
        HStack(spacing: 6) {
            Text(month).font(.urbanist(14, .semibold)).foregroundStyle(Color.qInk).contentTransition(.opacity)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.qText2)
                .rotationEffect(.degrees(open ? 180 : 0))
        }
        .padding(.leading, 14).padding(.trailing, 12)
        .contentShape(Capsule())
    }

    // "‹ 3/5 ›": troca de cartão entre os da lista (com o filtro dela), mantendo o mês aberto.
    @ViewBuilder private func pager(_ card: CardsOverview.Card) -> some View {
        let index = shown.firstIndex { $0.id == card.id } ?? 0
        if shown.count > 1 {
            HStack(spacing: 0) {
                pagerButton("chevron.left", "Cartão anterior", enabled: index > 0) { step(-1) }
                Text("\(index + 1)/\(shown.count)").font(.urbanist(13)).monospacedDigit().foregroundStyle(Color.qText2)
                    .frame(minWidth: 28)
                    .contentTransition(.numericText(countsDown: !forward))
                    .accessibilityLabel("Cartão \(index + 1) de \(shown.count)")
                pagerButton("chevron.right", "Próximo cartão", enabled: index < shown.count - 1) { step(1) }
            }
        }
    }

    private func pagerButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Color.qText2 : Color.qGhost)
                .frame(width: 36, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // A atual ainda tem saldo e é mais antiga que a aberta: avisa em âmbar e leva até ela.
    private func pendingRow(_ pending: CardsOverview.Bill) -> some View {
        Button { pick(pending.period) } label: {
            HStack(spacing: 6) {
                dot(pending)
                Text(pending.pendingLine).font(.urbanist(13, .semibold)).foregroundStyle(Color.qAttnInk)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.qAttnInk)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .padding(.top, 8)
        .accessibilityHint("Abre a fatura com saldo")
    }

    // Lista suspensa: todas as faturas do cartão, com status e valor; a escolhida em q/accent-soft com check.
    private func picker(_ card: CardsOverview.Card, chosen: CardsOverview.Bill) -> some View {
        ZStack(alignment: .top) {
            // Toque fora fecha, sem fechar o modal.
            Color.white.opacity(0.001).onTapGesture { setPicking(false) }.accessibilityHidden(true)
            VStack(spacing: 0) {
                Button { setPicking(false) } label: {
                    selectorLabel(chosen.month, open: true).frame(maxWidth: .infinity).frame(height: 34)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Fechar a lista de faturas")
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(card.bills, id: \.period) { option($0, chosen: $0.period == chosen.period) }
                        }
                        .padding(.horizontal, 4)
                    }
                    // Abre com a escolhida no centro, sem animar a rolagem.
                    .onAppear { proxy.scrollTo(chosen.period, anchor: .center) }
                }
                .scrollIndicators(.hidden)
                .frame(height: min(CGFloat(card.bills.count) * 52, 340))
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    }
                }
            }
            .padding(.bottom, 4)
            .background(Color.white, in: .rect(cornerRadius: 27))
            .overlay(RoundedRectangle(cornerRadius: 27).stroke(Color.qLine))
            .shadow(color: .black.opacity(0.1), radius: 24, y: 12)
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 0, trailing: 16))
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { setPicking(false) }
        }
    }

    private func option(_ b: CardsOverview.Bill, chosen: Bool) -> some View {
        Button { pick(b.period) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.month).font(.urbanist(15)).foregroundStyle(Color.qInk)
                    HStack(spacing: 6) {
                        dot(b)
                        Text(b.short).font(.urbanist(12)).foregroundStyle(Color.qText2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(b.total.full).font(.urbanist(15)).monospacedDigit().foregroundStyle(Color.qInk)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.qInk)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .frame(minHeight: 52)
            .background(chosen ? Color.qAccentSoft : .clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .id(b.period)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Janela de 300pt: a altura do modal não muda ao trocar de fatura ou de cartão; a lista rola dentro dela.
    private static let window: CGFloat = 300

    private func billLines(_ bill: CardsOverview.Bill) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if bill.lines.isEmpty {
                emptyBill(bill)
            } else {
                HStack {
                    Text("\(Text(bill.status == .future ? "Parcelas já lançadas" : "Lançamentos").font(.urbanist(13, .semibold)).foregroundStyle(Color.qInk)) · \(bill.lines.count)")
                        .font(.urbanist(13)).foregroundStyle(Color.qText2)
                    Spacer()
                    Text(bill.range).font(.urbanist(13)).foregroundStyle(Color.qText2)
                }
                .padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(bill.lines.enumerated()), id: \.offset) { i, line in
                            lineRow(line)
                                .overlay(alignment: .bottom) {
                                    if i < bill.lines.count - 1 { Rectangle().fill(Color.qLine).frame(height: 1) }
                                }
                        }
                        if bill.status == .future {
                            Text("Não é previsão: só o que já está agendado. Compras novas entram até o fechamento, \(MonthLabel.day(bill.closingDate)).")
                                .font(.urbanist(12)).foregroundStyle(Color.qText3)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .frame(height: Self.window)
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                    }
                }
            }
        }
        .frame(height: Self.window + 24, alignment: .top)
        .padding(EdgeInsets(top: 24, leading: 20, bottom: 12, trailing: 20))
    }

    // Sem parcela, sem número inventado: R$ 0,00 em cima e o aviso no lugar da lista, na mesma altura.
    private func emptyBill(_ bill: CardsOverview.Bill) -> some View {
        let pending = bill.status == .open || bill.status == .future
        return VStack(alignment: .leading, spacing: 6) {
            Text("Nada lançado para \(MonthLabel.long(bill.period)) ainda").font(.urbanist(17, .semibold)).foregroundStyle(Color.qInk)
            Text(pending
                 ? "Parcelas e assinaturas aparecem aqui assim que caírem nesta fatura. Compras novas entram até o fechamento, \(MonthLabel.day(bill.closingDate))."
                 : "O banco não mandou lançamentos desta fatura.")
                .font(.urbanist(13)).foregroundStyle(Color.qText2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.qBg, in: .rect(cornerRadius: 14))
    }

    private func lineRow(_ line: CardsOverview.Line) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description).font(.urbanist(15)).foregroundStyle(Color.qInk).lineLimit(1)
                Text(line.detail).font(.urbanist(12)).foregroundStyle(Color.qText2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.amount.full).font(.urbanist(15)).tracking(-0.2).monospacedDigit().foregroundStyle(Color.qInk)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func detailsButton(_ card: CardsOverview.Card, _ period: String) -> some View {
        Button { details(CardRoute(id: card.id, period: period)) } label: {
            Text("Ver detalhes do cartão").font(.urbanist(15, .semibold)).foregroundStyle(Color.qInk)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.white, in: .capsule)
                .overlay(Capsule().stroke(Color.qLine))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 20, trailing: 20))
    }

    /// Paginação do quadro 13 (motion/screen, 400ms). O que sai continua de onde o dedo o deixou, mais 16pt, e some
    /// em 70% do tempo na curva padrão; o que entra vem 16pt do outro lado na curva de entrada, um instante depois,
    /// cruzando com a saída. Com Reduce Motion, só crossfade.
    private var shift: AnyTransition {
        guard !reduceMotion else { return .opacity.animation(Motion.standard(Motion.quick)) }
        let d: CGFloat = forward ? 16 : -16
        return .asymmetric(
            insertion: .offset(x: d).combined(with: .opacity)
                .animation(Motion.enter(Motion.screen).delay(Motion.screen * 0.12)),
            removal: .offset(x: -d).combined(with: .opacity)
                .animation(Motion.standard(Motion.screen * 0.7)))
    }

    /// A lista cresce do seletor; com Reduce Motion, só aparece.
    private var pickerShift: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    /// No arrasto o conteúdo esmaece até 55%: a troca se anuncia antes de acontecer.
    private var dragOpacity: Double { 1 - min(0.45, abs(drag) / 140) }

    // A direção trava nos primeiros 8pt (lateral só se dx > 1,2·dy), para não brigar com a rolagem dos lançamentos.
    // Segue o dedo com resistência (borracha nas pontas) e decide na soltura por distância ou velocidade.
    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                let dx = v.translation.width
                if lateral == nil { lateral = abs(dx) > abs(v.translation.height) * 1.2 && shown.count > 1 }
                guard lateral == true else { return }
                let towards = dx < 0 ? 1 : -1
                // A direção já entra na transição durante o arrasto: na soltura a troca é imediata.
                if forward != (towards > 0) { forward = towards > 0 }
                drag = reduceMotion ? 0 : dx * (neighbor(towards) == nil ? 0.12 : 0.35)
            }
            .onEnded { v in
                defer { lateral = nil }
                guard lateral == true else { return }
                let dx = v.translation.width, towards = dx < 0 ? 1 : -1
                let flick = -v.velocity.width * CGFloat(towards) > 450
                if neighbor(towards) != nil, abs(dx) > 64 || flick {
                    step(towards)
                } else {
                    withAnimation(Motion.standard(Motion.base)) { drag = 0 }
                }
            }
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
    }

    private func neighbor(_ offset: Int) -> CardsOverview.Card? {
        guard let card, let i = shown.firstIndex(where: { $0.id == card.id }), shown.indices.contains(i + offset) else { return nil }
        return shown[i + offset]
    }

    // Troca de cartão mantendo o mês; sem fatura nele, a atual do cartão novo.
    private func step(_ offset: Int) {
        guard let next = neighbor(offset) else { return }
        turn(offset > 0) {
            withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) {
                page = .bill(next.id)
                period = next.period(keeping: period)
                drag = 0
            }
        }
    }

    // Tocar de novo na mesma fatura só fecha a lista; outra no meio da troca retoma dali.
    private func pick(_ next: String) {
        setPicking(false)
        guard next != period else { return }
        turn(next > (period ?? "")) {
            withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) { period = next }
        }
    }

    // O que sai usa a transição da última atualização em que ainda existia: se a direção vira,
    // ela precisa chegar à tela uma atualização antes da troca, senão a saída vai para o lado errado.
    private func turn(_ ahead: Bool, _ change: @escaping () -> Void) {
        guard forward != ahead else { return change() }
        forward = ahead
        DispatchQueue.main.async(execute: change)
    }

    private func setPicking(_ value: Bool) {
        withAnimation(reduceMotion ? Motion.standard(Motion.quick) : Motion.spring(Motion.base)) { picking = value }
    }

    // Volta com o filtro e a rolagem de antes; o período escolhido é esquecido.
    private func back() {
        picking = false
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base + 0.04)) {
            page = .cards
            period = nil
            scroll.scrollTo(y: cardsY)
        }
    }

    private func escape() {
        if picking { setPicking(false) } else if page == .cards { close() } else { back() }
    }
}

private extension View {
    // Dentro da identidade do conteúdo: ao trocar de cartão, o que sai fica onde o dedo o deixou e parte dali.
    func dragged(_ x: CGFloat, _ opacity: Double) -> some View { offset(x: x).opacity(opacity) }
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
