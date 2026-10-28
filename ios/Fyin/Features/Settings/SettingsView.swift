import SwiftUI

struct SettingsView: View {
    let model: SettingsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch model.hero {
                case .empty: emptyCard
                default: hero
                }
                if model.hero == .offline { retryRow }
                if !model.items.isEmpty {
                    sectionLabel("Contas conectadas")
                    VStack(spacing: 0) { ForEach(model.items) { bankRow($0) } }
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(Color.qCard, in: .rect(cornerRadius: 28))
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 24)
        }
        .refreshable { await model.load() }
        .background(Color.qBg)
        .animation(Motion.standard(Motion.base), value: model.hero)
        .sensoryFeedback(trigger: model.finishedSyncs) { _, _ in model.needsAttention.isEmpty ? .success : .warning }
        .task { await model.load() }
    }

    // MARK: Cabeçalho

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.qInk)
                    .frame(width: 44, height: 44).background(Color.qCard, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")
            Text("Ajustes").font(.urbanist(28, .semibold)).tracking(-1.2).foregroundStyle(Color.qInk)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 8).padding(.top, 4)
    }

    // MARK: Sync

    private var hero: some View {
        let h = heroText
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                spinner(h.symbol, tint: h.tint, spinning: model.syncing)
                Text(h.status).font(.urbanist(13)).foregroundStyle(.white.opacity(0.55)).contentTransition(.opacity)
            }
            Text(h.big).font(.urbanist(36, .light)).tracking(-1.2).foregroundStyle(.white).contentTransition(.opacity)
            if let sub = h.sub {
                Text(sub).font(.urbanist(13)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
            if let progress = h.progress { progressBar(progress) }
            syncButton
            if let hint = h.hint {
                Text(hint).font(.urbanist(12)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.qInk, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
    }

    private struct HeroText {
        var symbol: String
        var tint: Color
        var status: String
        var big: String
        var sub: String?
        var progress: Double?
        var hint: String?
    }

    private var heroText: HeroText {
        let now = Date.now
        let last = model.lastSync.map { SyncFormat.long($0, now: now) } ?? "—"
        let banks = model.items.count
        let accounts = model.items.reduce(0) { $0 + $1.accounts }
        switch model.hero {
        case .running(let done, let total):
            return HeroText(symbol: "arrow.triangle.2.circlepath", tint: .qAccent, status: "Sincronizando · \(done) de \(total) prontos",
                            big: "Atualizando", progress: total == 0 ? 0 : Double(done) / Double(total) * 0.85 + 0.15,
                            hint: "Pode sair desta tela. A sincronização continua.")
        case .partial(let ok, let total):
            let n = model.needsAttention.count
            return HeroText(symbol: "exclamationmark.circle", tint: Color(hex: 0xF4B740), status: "Atualizado em parte · \(ok) de \(total)",
                            big: last, sub: n == 1 ? "1 banco precisa de você" : "\(n) bancos precisam de você")
        case .offline:
            return HeroText(symbol: "wifi.slash", tint: Color(hex: 0xF4B740), status: "Sem conexão com o servidor",
                            big: last, sub: "Mostrando o último dado salvo", hint: "Puxe a tela ou toque em Tentar agora.")
        default:
            return HeroText(symbol: "checkmark.circle", tint: .qAccent, status: "Tudo atualizado", big: last,
                            sub: "\(banks) \(banks == 1 ? "banco" : "bancos") · \(accounts) \(accounts == 1 ? "conta" : "contas")")
        }
    }

    private func spinner(_ symbol: String, tint: Color, spinning: Bool) -> some View {
        TimelineView(.animation(paused: !spinning || reduceMotion)) { ctx in
            let turn = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint)
                .rotationEffect(.degrees(spinning && !reduceMotion && symbol == "arrow.triangle.2.circlepath" ? turn * 360 : 0))
        }
    }

    private func progressBar(_ value: Double) -> some View {
        Capsule().fill(.white.opacity(0.12)).frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(Color.qAccent).frame(width: g.size.width * value) }
            }
            .animation(reduceMotion ? nil : Motion.standard(Motion.considered), value: value)
    }

    private var syncButton: some View {
        let busy = model.syncing
        let off = busy || model.hero == .offline
        return Button { Task { await model.syncAll() } } label: {
            HStack(spacing: 8) {
                Image("sync").resizable().frame(width: 16, height: 16)
                Text(busy ? "Sincronizando…" : "Sincronizar tudo").font(.urbanist(15, .semibold))
            }
            .foregroundStyle(off ? Color.white.opacity(0.55) : Color.qInk)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(off ? Color.white.opacity(0.12) : Color.qAccent, in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .animation(Motion.standard(Motion.quick), value: off)
    }

    private var retryRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("O servidor do Fyin não respondeu").font(.urbanist(14)).foregroundStyle(Color.qInk)
                if let last = model.lastSync {
                    Text("Último dado salvo: \(SyncFormat.long(last, now: .now).lowercased())")
                        .font(.urbanist(12)).foregroundStyle(Color.qText3)
                }
            }
            Spacer(minLength: 8)
            Button { Task { await model.load() } } label: {
                Text("Tentar agora").font(.urbanist(13, .semibold)).foregroundStyle(Color.qInk)
                    .padding(.horizontal, 16).frame(height: 36)
                    .overlay(Capsule().stroke(Color.qHairline, lineWidth: 1)).background(Color.qBg, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.qCard, in: .rect(cornerRadius: 14))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "link").font(.system(size: 17)).foregroundStyle(Color.qInk)
                .frame(width: 40, height: 40).background(Color.qBg, in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                Text("Conecte sua primeira conta").font(.urbanist(18, .semibold)).tracking(-0.3).foregroundStyle(Color.qInk)
                Text("O Fyin lê saldo e transações pelo Pluggy. Conectar contas pelo app chega em breve.")
                    .font(.urbanist(14)).foregroundStyle(Color.qText2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.qCard, in: .rect(cornerRadius: 28))
    }

    // MARK: Contas

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.urbanist(13)).foregroundStyle(Color.qText3).padding(.horizontal, 4).padding(.top, 4)
    }

    private func bankRow(_ item: ConnectedItem) -> some View {
        let line = item.line(now: .now)
        let (symbol, tint): (String, Color) = switch line.tone {
        case .ok: ("checkmark.circle", .qOk)
        case .running: ("arrow.triangle.2.circlepath", .qInk)
        case .attention: ("clock", Color(hex: 0xF4B740))
        case .error: ("exclamationmark.circle", .qOverInk)
        }
        return HStack(spacing: 12) {
            Text(BankStyle.initials(item.connector)).font(.urbanist(13, .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(BankStyle.color(item.connector), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.connector).font(.urbanist(15)).foregroundStyle(Color.qInk)
                Text("\(item.owner.capitalized) · \(line.text)").font(.urbanist(12)).foregroundStyle(Color.qText3)
            }
            Spacer(minLength: 8)
            spinner(symbol, tint: tint, spinning: line.tone == .running).font(.system(size: 18))
        }
        .frame(height: 60)
        .accessibilityElement(children: .combine)
    }
}

// Cores de marca dos bancos do design (Bank Avatar); o que não está na lista fica em tinta.
private enum BankStyle {
    static func initials(_ name: String) -> String { String(name.folding(options: .diacriticInsensitive, locale: nil).prefix(2)).lowercased() }

    static func color(_ name: String) -> Color {
        let n = name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        return if n.contains("itau") { Color(hex: 0xEC7000) }
        else if n.contains("nubank") { Color(hex: 0x8A05BE) }
        else if n.contains("inter") { Color(hex: 0xFF7A00) }
        else if n.contains("bradesco") { Color(hex: 0xCC092F) }
        else { .qInk }
    }
}
