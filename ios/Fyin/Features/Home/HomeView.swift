import SwiftUI

struct HomeView: View {
    let model: HomeViewModel
    /// Sync da Pluggy em andamento (disparado em Ajustes); a home mostra o mesmo andamento do pull.
    var syncing = false
    var openSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    @Namespace private var hero
    /// Modal do patrimônio: `open` é o destino da geometria; `presented` o mantém visível até recolher de vez.
    @State private var portfolioOpen = false
    @State private var portfolioPresented = false
    @State private var balanceRoom: CGFloat = 0
    @State private var balanceTemplateWidth: CGFloat = 0

    private var loading: Bool { model.loading }
    private var busy: Bool { model.refreshing || syncing }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 8) {
                        balanceCard(safeTop: geo.safeAreaInsets.top)
                        monthCards.padding(.horizontal, 12)
                    }
                    .padding(.bottom, 20)
                }
                .ignoresSafeArea(edges: [.top, .horizontal])
                .scrollEdgeEffectHidden(true, for: .top)
                .refreshable { await model.refresh() }
                .tint(.clear) // esconde o spinner do sistema; o andamento aparece na barra do divisor
                .blur(radius: portfolioOpen ? 6 : 0)
                .accessibilityHidden(portfolioOpen)

                Color.qScrim.ignoresSafeArea()
                    .opacity(portfolioOpen ? 1 : 0)
                    .allowsHitTesting(portfolioOpen)
                    .onTapGesture(perform: closePortfolio)
                    .accessibilityHidden(true)

                if let portfolio = model.portfolio {
                    // Sempre no layout (invisível) para já saber a própria altura quando a linha abrir.
                    PortfolioSheet(portfolio: portfolio, open: portfolioOpen, hero: hero,
                                   maxHeight: geo.size.height + geo.safeAreaInsets.bottom - 12,
                                   close: closePortfolio)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .opacity(reduceMotion ? (portfolioOpen ? 1 : 0) : (portfolioPresented ? 1 : 0))
                        .allowsHitTesting(portfolioOpen)
                        .accessibilityHidden(!portfolioOpen)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .background(Color.qBg)
        .sensoryFeedback(.selection, trigger: model.selected)
        .animation(Motion.standard(Motion.base), value: model.loading)
        .task(id: model.selected) { await model.ensureLoaded() }
    }

    // MARK: Saldo

    private func balanceCard(safeTop: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                monthPills
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes")
                .opacity(loading ? 0 : 1)
            }
            Spacer(minLength: 120)
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saldo em contas").font(.urbanist(14)).foregroundStyle(.white.opacity(0.55))
                        .skeleton(loading, dark: true)
                    HStack(alignment: .top, spacing: 4) {
                        Text("R$").font(.urbanistFixed(22, .regular)).foregroundStyle(.white.opacity(0.3))
                            .padding(.top, 16)
                        // Uma única instância (para os rolos animarem) com tamanho fixo por molde, não pelo valor:
                        // a altura só muda com a largura do aparelho ou ao passar de 1 milhão.
                        balanceDigits(size: balanceFontSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { balanceRoom = $0 }
                            .background(alignment: .leading) {
                                Text(balanceTemplate).font(.urbanistFixed(84, .light)).tracking(-3).monospacedDigit()
                                    .fixedSize().hidden()
                                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { balanceTemplateWidth = $0 }
                            }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("R$ \(balance.whole)\(balance.cents)")
                    .skeleton(loading, dark: true, radius: 12)
                    syncLine.skeleton(loading, dark: true)
                }
                patrimony
            }
        }
        .padding(EdgeInsets(top: safeTop + 14, leading: 32, bottom: 20, trailing: 32))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Encostado no topo: a tela física arredonda os cantos de cima. O fundo sobe além do card
        // para o pull-to-refresh revelar o mesmo tom, sem canto nem branco.
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28)
                .fill(Color.qInk)
                .padding(.top, -1000)
        }
    }

    private var balanceMoney: Money { model.current?.balance ?? Money(0) }

    // Maior saldo que cabe no tamanho atual; 84pt é o tamanho do design.
    private var balanceTemplate: String { abs(balanceMoney.value) >= 1_000_000 ? "0.000.000,00" : "000.000,00" }

    private var balanceFontSize: CGFloat {
        guard balanceRoom > 0, balanceTemplateWidth > 0 else { return 84 }
        return min(84, 84 * balanceRoom / balanceTemplateWidth)
    }
    private var balance: (whole: String, cents: String) { balanceMoney.split }

    private func balanceDigits(size: CGFloat) -> some View {
        HStack(spacing: 0) {
            SlotText(text: balance.whole, value: balanceMoney.value).foregroundStyle(.white)
            SlotText(text: balance.cents, value: balanceMoney.value, firstReel: balance.whole.count)
                .foregroundStyle(.white.opacity(0.3))
        }
        .font(.urbanistFixed(size, .light)).tracking(size * -3 / 84)
        .fixedSize()
    }

    private var monthPills: some View {
        HStack(spacing: 6) {
            ForEach(model.months, id: \.self) { m in
                let selected = m == model.selected
                Button { select(m) } label: {
                    Text(MonthLabel.short(m)).font(.urbanist(13))
                        .foregroundStyle(selected ? Color.qInk : .white.opacity(0.7))
                        .padding(.horizontal, 14).frame(height: 32)
                        .background {
                            if selected {
                                Capsule().fill(Color.qAccent).matchedGeometryEffect(id: "pill", in: pill)
                            } else {
                                Capsule().stroke(.white.opacity(0.16))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(Motion.standard(Motion.base), value: model.selected)
        .skeleton(model.months.isEmpty && !model.failed, dark: true, radius: 16)
    }

    private var syncText: String {
        if syncing { return "Sincronizando com os bancos…" }
        if model.refreshing { return "Atualizando…" }
        if model.failed { return "Não foi possível carregar. Puxe para tentar de novo." }
        guard let syncedAt = model.current?.syncedAt else { return "Ainda não sincronizado" }
        let ago = syncedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(Locale(identifier: "pt_BR")))
        return "Atualizado \(ago)"
    }

    private var syncLine: some View {
        HStack(spacing: 6) {
            TimelineView(.animation(paused: !busy || reduceMotion)) { ctx in
                // 1 volta a cada 1.2s, linear, só enquanto atualiza.
                let turn = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                Image("sync").resizable().frame(width: 13, height: 13)
                    .rotationEffect(.degrees(busy && !reduceMotion ? turn * 360 : 0))
                    .foregroundStyle(busy ? Color.qAccent : .white.opacity(0.55))
            }
            Text(syncText).font(.urbanist(13)).contentTransition(.opacity)
                .foregroundStyle(.white.opacity(busy ? 0.8 : 0.55))
            Spacer(minLength: 8)
        }
        .padding(.top, 6)
    }

    // A linha inteira é o ponto de partida do morph: fundo, rótulo e valor viram o modal (board 16).
    private var patrimony: some View {
        Button(action: openPortfolio) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patrimônio investido").font(.urbanist(13)).foregroundStyle(.white.opacity(0.55))
                        .hero(PortfolioHero.label, in: hero, isSource: !portfolioOpen, enabled: !reduceMotion)
                    slot(model.current?.invested).font(.urbanist(22, .light)).foregroundStyle(.white)
                        .hero(PortfolioHero.value, in: hero, isSource: !portfolioOpen, enabled: !reduceMotion)
                }
                .opacity(portfolioPresented && !reduceMotion ? 0 : 1)
                .skeleton(loading, dark: true)
                Spacer()
            }
            .padding(.top, 16)
            .contentShape(.rect)
            .background {
                Color.qInk.hero(PortfolioHero.shell, in: hero, isSource: !portfolioOpen, enabled: !reduceMotion)
            }
        }
        .buttonStyle(PressStyle())
        .disabled(model.portfolio == nil)
        .accessibilityHint("Abre o patrimônio por conta")
        .overlay(alignment: .top) { divider }
    }

    // O divisor vira barra de progresso indeterminada (a API não informa andamento) enquanto atualiza.
    private var divider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            .overlay {
                GeometryReader { g in
                    TimelineView(.animation(paused: !busy || reduceMotion)) { ctx in
                        // um trecho de 35% da largura cruza o divisor a cada 1.4s, linear
                        let turn = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        let width = g.size.width * 0.35
                        LinearGradient(colors: [.clear, .qAccent, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: reduceMotion ? g.size.width : width)
                            .offset(x: reduceMotion ? 0 : -width + turn * (g.size.width + width))
                    }
                }
                .clipped()
                .frame(height: 2)
                .opacity(busy ? 1 : 0)
                .animation(Motion.standard(Motion.base), value: busy)
                .accessibilityHidden(true)
            }
    }

    // MARK: Cards do mês

    private var monthCards: some View {
        VStack(spacing: 8) {
            spendingCard
            HStack(spacing: 8) {
                smallCard("Cartão", card?.total,
                          card?.closingDate.map { "Fatura fechou \(MonthLabel.day($0))" } ?? "Sem fatura fechada")
                smallCard("Empréstimos", model.current?.loans.total, "Saldo devedor")
            }
        }
    }

    private var card: HomeSummary.Card? { model.current?.card }
    private var spending: HomeSummary.Spending? { model.current?.spending }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHead("Gastos do mês", since: spending?.since)
            HStack(alignment: .bottom, spacing: 14) {
                spendingHeadline.font(.urbanist(56, .light)).tracking(-2).fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        slot(spending?.spent)
                        Text(" de ")
                        slot(spending?.goal)
                    }
                    .font(.urbanist(13)).foregroundStyle(Color.qText2)
                    if let line = daysLine {
                        Text(line).font(.urbanist(12)).foregroundStyle(Color.qText3).contentTransition(.opacity)
                    }
                }
                .padding(.bottom, 8)
            }
            .skeleton(loading)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.qCard
                progressGlow(.qGlowLime).opacity(isOver ? 0 : 1)
                progressGlow(.qOver).opacity(isOver ? 1 : 0)
                Image("grain").resizable().scaledToFill().opacity(0.45).blendMode(.multiply)
            }
            .opacity(loading ? 0 : 1)
            .background(Color.qCard)
            .animation(Motion.standard(Motion.screen), value: isOver)
        }
        .clipShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    // O fundo é a barra: enche da esquerda até o percentual e se dissipa na ponta (cauda de 14% do card).
    // Cresce a partir do valor anterior no mesmo ritmo dos rolos.
    private func progressGlow(_ color: Color) -> some View {
        let progress = min(Double(spending?.percent ?? 0) / 100, 1)
        return GeometryReader { g in
            HStack(spacing: 0) {
                LinearGradient(colors: [color.opacity(0.08), color.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * progress)
                LinearGradient(colors: [color.opacity(0.25), color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: progress > 0 ? g.size.width * 0.14 : 0)
            }
        }
        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.9), value: progress)
    }

    // "18 de 31 dias medidos" quando a conexão começou no meio do mês; senão "Dia 22 de 31" no mês atual.
    private var daysLine: String? {
        guard let s = spending else { return nil }
        if let since = s.since, let first = Int(since.suffix(2)) {
            return "\(s.day - first + 1) de \(s.daysInMonth) dias medidos"
        }
        return s.day < s.daysInMonth ? "Dia \(s.day) de \(s.daysInMonth)" : nil
    }

    private var isOver: Bool { spending?.isOver ?? false }

    /// Valor em reais que gira como slot ao mudar ("R$ 6.240").
    private func slot(_ money: Money?) -> SlotText {
        let money = money ?? Money(0)
        return SlotText(text: money.short, value: money.value)
    }

    // "69%" do gasto sobre a meta. Sem meta ainda (goal 0) não há percentual: "–%".
    @ViewBuilder private var spendingHeadline: some View {
        HStack(spacing: 0) {
            if let percent = spending?.percent {
                SlotText(text: "\(percent)", value: Decimal(percent)).foregroundStyle(Color.qInk)
            } else {
                Text("–").foregroundStyle(Color.qGhost)
            }
            Text("%").foregroundStyle(Color.qGhost)
        }
    }

    private func smallCard(_ title: String, _ value: Money?, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            cardHead(title)
            VStack(alignment: .leading, spacing: 2) {
                slot(value).font(.urbanist(24, .light)).foregroundStyle(Color.qInk)
                Text(sub).font(.urbanist(12)).foregroundStyle(Color.qText3)
                    .contentTransition(.opacity)
                    .animation(Motion.standard(Motion.base), value: sub)
            }
            .skeleton(loading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.qCard, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    // Com `since` (Mês com dados parciais, board 11), o selo "Desde 14 out" toma o lugar da seta.
    private func cardHead(_ title: String, since: String? = nil) -> some View {
        HStack {
            Text(title).font(.urbanist(14)).foregroundStyle(Color.qText3).skeleton(loading)
            Spacer()
            if let since, !loading {
                HStack(spacing: 6) {
                    Image("calendar-blank").resizable().frame(width: 13, height: 13)
                    Text("Desde \(MonthLabel.day(since))").font(.urbanist(12))
                }
                .foregroundStyle(Color.qText2)
                .padding(.horizontal, 10).frame(height: 26)
                .background(.white.opacity(0.8), in: .capsule)
            } else {
                Image("arrow-up-right").resizable().frame(width: 18, height: 18).foregroundStyle(Color.qInk)
                    .opacity(loading ? 0 : 1)
            }
        }
    }

    // MARK: Ações

    private func openPortfolio() {
        portfolioPresented = true
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.considered)) { portfolioOpen = true }
    }

    // Inverso da abertura, mais curto. Se reabrir no meio, a mola retoma dali e o modal não some.
    private func closePortfolio() {
        withAnimation(reduceMotion ? Motion.standard(Motion.base) : Motion.spring(Motion.base)) {
            portfolioOpen = false
        } completion: {
            if !portfolioOpen { portfolioPresented = false }
        }
    }

    // Só a pílula desliza (animação dos seletores); os cards ficam e apenas os números giram.
    private func select(_ m: String) {
        guard m != model.selected else { return }
        model.select(m)
    }
}

// Skeleton na forma exata do conteúdo (frame 10): o conteúdo fica invisível mas ocupa o espaço, então nada pula.
private struct Skeleton: ViewModifier {
    let active: Bool
    let dark: Bool
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(dark ? Color.white.opacity(0.08) : Color.qInk.opacity(0.06))
                        .overlay {
                            if !reduceMotion {
                                GeometryReader { g in
                                    LinearGradient(colors: [.clear, .white.opacity(dark ? 0.08 : 0.5), .clear],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .offset(x: phase * g.size.width)
                                }
                                .clipShape(.rect(cornerRadius: radius))
                            }
                        }
                        .opacity(reduceMotion ? 0.6 : 1)
                        .onAppear {
                            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
                        }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
    }
}

private extension View {
    func skeleton(_ active: Bool, dark: Bool = false, radius: CGFloat = 6) -> some View {
        modifier(Skeleton(active: active, dark: dark, radius: radius))
    }
}

#Preview { HomeView(model: HomeViewModel(repository: PreviewHomeRepository())) }
