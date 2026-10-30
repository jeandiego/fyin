import SwiftUI

// Seção "Fora do Open Finance" de Ajustes (Fyin.pen, quadro 18): uma linha por dono já importado + "Importar da B3".
struct B3Section: View {
    let model: B3ViewModel

    var body: some View {
        if !model.statuses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fora do Open Finance").font(.urbanist(13)).foregroundStyle(Color.qText3).padding(.horizontal, 4).padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(model.imported) { status in
                        Button { model.update(status.owner) } label: { ownerRow(status) }.buttonStyle(.plain)
                    }
                    if model.statuses.contains(where: { !$0.imported }) {
                        Button { model.begin() } label: { importRow }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(Color.qCard, in: .rect(cornerRadius: 28))
            }
            .disabled(model.isFlowActive)
        }
    }

    private func ownerRow(_ s: B3Status) -> some View {
        let style = Institutions.style("B3")
        return HStack(spacing: 12) {
            Text(style.initials).font(.urbanist(13, .semibold)).foregroundStyle(style.ink)
                .frame(width: 40, height: 40).background(style.color, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("B3 · Tesouro e ações").font(.urbanist(15)).foregroundStyle(Color.qInk)
                Text(s.line(now: .now)).font(.urbanist(12)).foregroundStyle(Color.qText3)
            }
            Spacer(minLength: 8)
            if s.stale {
                Text("Atualizar").font(.urbanist(12, .semibold)).foregroundStyle(Color.qAttnInk)
                    .padding(.horizontal, 10).frame(height: 24).background(Color.qAttnTint, in: .capsule)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.qText3)
        }
        .frame(height: 60).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Atualiza a posição na B3")
    }

    private var importRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16)).foregroundStyle(Color.qInk)
                .frame(width: 40, height: 40).background(Color.qBg, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Importar da B3").font(.urbanist(15)).foregroundStyle(Color.qInk)
                Text("Tesouro, ações e FIIs da Área do Investidor").font(.urbanist(12)).foregroundStyle(Color.qText3)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.qText3)
        }
        .frame(height: 60).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Sheet do fluxo (explicação → site → leitura), toast de conclusão e háptico. Aplicado em Ajustes pelo FyinApp.
    func b3Flow(_ model: B3ViewModel) -> some View { modifier(B3Flow(model: model)) }
}

private struct B3Flow: ViewModifier {
    let model: B3ViewModel
    @Environment(ToastCenter.self) private var toasts
    /// O site abre em tela cheia, não em sheet: tocar na WebView dentro de uma sheet derrubava o app
    /// (UIKit, _delayTouchesForEvent, iOS 26). Só abre depois que a sheet da explicação terminou de fechar.
    @State private var browsing = false

    private var isBrowserPhase: Bool { model.isFlowActive && model.phase != .explaining }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { model.phase == .explaining }, set: { if !$0 && model.phase == .explaining { model.cancel() } }),
                   onDismiss: { if isBrowserPhase { browsing = true } }) {
                B3ExplainSheet(model: model)
            }
            .fullScreenCover(isPresented: $browsing, onDismiss: { if isBrowserPhase { model.cancel() } }) {
                B3Browser(model: model)
            }
            .onChange(of: model.phase) { old, new in
                // Atualizar (linha de um dono) vai direto ao site; vindo da explicação, quem abre é o onDismiss.
                if new == .idle { browsing = false } else if isBrowserPhase && old != .explaining { browsing = true }
            }
            .sensoryFeedback(.success, trigger: model.finished)
            .onChange(of: model.result) { _, result in
                guard let result else { return }
                // Exceção B3 documentada no board: 5 s, não os 3 s do compacto.
                toasts.show(Toast(id: "b3-import", title: result.summary, lifetime: .seconds(5)))
                model.dismissResult()
            }
    }
}

private struct B3ExplainSheet: View {
    let model: B3ViewModel
    /// Altura medida da explicação: a sheet abraça o conteúdo (o `.medium` cortava o topo em telas menores e com Dynamic Type).
    @State private var height: CGFloat = 560

    var body: some View {
        B3Explain(model: model)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            // Sem raio fixo: o sistema usa o raio concêntrico ao aparelho, como pede o design system.
            // Fundo sólido: o vidro padrão do iOS 26 deixava Ajustes aparecer por trás do texto.
            .presentationBackground(Color.qBg)
    }
}

// Sheet curta: o que vai acontecer, quem guarda a senha e de quem é a posição.
private struct B3Explain: View {
    let model: B3ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Importar da B3").font(.urbanist(20, .semibold)).tracking(-0.4).foregroundStyle(Color.qInk)
                    .accessibilityAddTraits(.isHeader)
                Text("Você entra no site da B3 aqui dentro do app. Sua senha fica com a B3: o Fyin só lê a posição depois que você entrar.")
                    .font(.urbanist(14)).foregroundStyle(Color.qText2).fixedSize(horizontal: false, vertical: true)
            }
            if model.owners.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("De quem é a posição?").font(.urbanist(13)).foregroundStyle(Color.qText3)
                    HStack(spacing: 8) {
                        ForEach(model.statuses) { s in
                            let on = model.owner == s.owner
                            Button { model.owner = s.owner } label: {
                                Text(s.ownerName).font(.urbanist(14, .semibold)).foregroundStyle(on ? .white : Color.qInk)
                                    .padding(.horizontal, 16).frame(height: 36)
                                    .background(on ? Color.qInk : Color.qCard, in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(["Entra com CPF e senha da B3", "Confirma o código, se a B3 pedir", "O Fyin lê a posição e fecha sozinho"].enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.urbanist(12, .semibold)).foregroundStyle(Color.qInk)
                            .frame(width: 24, height: 24).background(Color.qBg, in: .circle)
                        Text(step).font(.urbanist(14)).foregroundStyle(Color.qInk)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.qCard, in: .rect(cornerRadius: 14))
            VStack(spacing: 4) {
                Button { model.enter() } label: {
                    Label("Entrar na B3", systemImage: "arrow.right.circle").font(.urbanist(15, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.qInk, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(model.owner == nil)
                Button { model.cancel() } label: {
                    Text("Agora não").font(.urbanist(15, .semibold)).foregroundStyle(Color.qInk).frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        // 20 nas laterais (padding de tela) e 32 no topo: respiro entre o grabber e o título.
        .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 12)
    }
}

// Site da B3 em tela quase cheia. O Fyin só desenha a barra, o aviso e o painel de leitura; nunca o site.
private struct B3Browser: View {
    let model: B3ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            bar
            notice.padding(.horizontal, 12).padding(.bottom, 12)
            ZStack(alignment: .bottom) {
                Group {
                    if let web = (model.reader as? B3Session)?.webView { B3WebView(webView: web).id(ObjectIdentifier(web)) } else { Color.qSoft }
                }
                .opacity(model.phase == .login ? 1 : 0.5)
                .allowsHitTesting(model.phase == .login)
                panel.padding(12)
            }
        }
        .background(Color.qBg)
        .animation(reduceMotion ? nil : Motion.standard(Motion.base), value: model.phase)
    }

    private var bar: some View {
        HStack {
            Button { model.cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.qInk)
                    .frame(width: 44, height: 44).background(Color.qCard, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar sem importar")
            Spacer()
            VStack(spacing: 2) {
                Text("Área do Investidor").font(.urbanist(15, .semibold)).foregroundStyle(Color.qInk)
                Label("investidor.b3.com.br", systemImage: "lock.fill").labelStyle(.titleAndIcon)
                    .font(.urbanist(12)).foregroundStyle(Color.qText3)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
    }

    private var notice: some View {
        let (icon, text, ink, tint): (String, String, Color, Color) = switch model.phase {
        case .reading, .saving: ("checkmark.circle", "Você entrou. Não precisa tocar em nada.", .qOkInk, .qOkTint)
        case .paused: ("clock.arrow.circlepath", "A leitura pausou. Sua posição salva continua no Fyin.", .qAttnInk, .qAttnTint)
        default: ("checkmark.shield", "O Fyin lê só a sua posição. A senha fica com a B3.", .qInfoInk, .qInfoTint)
        }
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15))
            Text(text).font(.urbanist(13)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ink).padding(.horizontal, 12).padding(.vertical, 10)
        .background(tint, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var panel: some View {
        switch model.phase {
        case .reading, .saving:
            card {
                Text("Lendo sua posição").font(.urbanist(17, .semibold)).foregroundStyle(Color.qInk)
                step("Entrou na Área do Investidor", .done)
                step(model.readingDay.map { "Leu a posição de \(B3Format.day($0))" } ?? "Lendo posição",
                     model.phase == .reading ? .active : .done)
                step("Enviando ao Fyin", model.phase == .saving ? .active : .pending)
                Text("Dados da B3 são do fim do dia anterior.").font(.urbanist(13)).foregroundStyle(Color.qText3)
            }
            .accessibilityElement(children: .combine)
        case .paused(let reason):
            card {
                Text("Pausada por enquanto").font(.urbanist(17, .semibold)).foregroundStyle(Color.qInk)
                Text(reason).font(.urbanist(14)).foregroundStyle(Color.qText2).fixedSize(horizontal: false, vertical: true)
                Button { model.enter() } label: {
                    Text("Entrar de novo").font(.urbanist(15, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.qInk, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        default:
            EmptyView()
        }
    }

    private enum StepState { case done, active, pending }

    private func step(_ text: String, _ state: StepState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.qOk)
            case .active: ProgressView().controlSize(.small).tint(Color.qInk)
            case .pending: Image(systemName: "circle").foregroundStyle(Color.qGhost)
            }
            Text(text).font(.urbanist(15)).foregroundStyle(state == .pending ? Color.qText3 : Color.qInk)
        }
        .frame(height: 24)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.qBg, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.1), radius: 24, y: 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

#Preview {
    @Previewable @State var model = B3ViewModel(repository: PreviewB3Repository(), reader: B3Session())
    ScrollView { B3Section(model: model).padding(12) }
        .b3Flow(model)
        .task { await model.load() }
}
