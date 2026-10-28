import SwiftUI

// Porta do Slot text da Arc (uiarc.dev/components/slot-text): cada dígito é um rolo que gira
// na direção em que o número mudou, com uma volta extra, e pousa sem passar do alvo.
// Os rolos param um após o outro, da esquerda para a direita; o borrão acompanha a velocidade.
// Símbolos e separadores ("R$", ".", ",") ficam parados; caracteres novos crescem, removidos somem.
// Herda fonte, cor e tracking do pai.
struct SlotText: View {
    let text: String
    /// Valor numérico de `text`, só para saber a direção do giro.
    let value: Decimal
    /// Posição do primeiro rolo na fila de pouso, para encadear dois SlotText (ex.: reais e centavos).
    var firstReel = 0
    var duration = 0.9
    var stagger = 0.07
    var spins = 1

    @State private var lastValue: Decimal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chars = Array(text)
        let slots = chars.indices.map { Slot(fromEnd: chars.count - $0, index: $0, char: chars[$0]) }
        let direction = value >= (lastValue ?? value) ? 1 : -1
        HStack(spacing: 0) {
            // Identidade contada a partir do fim: 999 → 1.000 gira só os dígitos; "1" e "." entram.
            ForEach(slots, id: \.fromEnd) { slot in
                Group {
                    if let digit = slot.char.wholeNumberValue {
                        Reel(digit: digit, direction: direction, spins: spins, reduceMotion: reduceMotion,
                             landing: duration + Double(firstReel + slot.index) * stagger)
                    } else {
                        Text(String(slot.char))
                    }
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
            }
        }
        .monospacedDigit()
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0), value: chars.count)
        .onChange(of: value) { _, new in lastValue = new }
        .onAppear { lastValue = value }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct Slot {
    let fromEnd: Int
    let index: Int
    let char: Character
}

private struct Reel: View {
    let digit: Int
    let direction: Int
    let spins: Int
    let reduceMotion: Bool
    let landing: Double

    // Posições na fita infinita 0…9; o dígito visível é posição mod 10.
    @State private var from: Int
    @State private var to: Int
    // Cresce 1 a cada giro; o efeito anima de spin-1 até spin.
    @State private var spin = 0
    @State private var progress = 0.0
    @State private var cell: CGFloat = 0

    init(digit: Int, direction: Int, spins: Int, reduceMotion: Bool, landing: Double) {
        self.digit = digit
        self.direction = direction
        self.spins = spins
        self.reduceMotion = reduceMotion
        self.landing = landing
        _from = State(initialValue: digit)
        _to = State(initialValue: digit)
    }

    var body: some View {
        let low = min(from, to), high = max(from, to)
        Text("0").hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cell = $0 }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(low...high, id: \.self) { p in
                        Text(String((p % 10 + 10) % 10)).frame(height: cell)
                    }
                }
                .fixedSize()
                .modifier(ReelEffect(t: progress - Double(spin - 1), from: from, to: to, low: low, cell: cell, landing: landing))
            }
            .clipped()
            // Esmaece as bordas do rolo para os dígitos vizinhos não aparecerem cortados durante o giro.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: digit) { old, new in
                let steps = ((new - old) * direction % 10 + 10) % 10
                from = old
                to = old + direction * (steps + 10 * spins)
                guard !reduceMotion else { from = to; return }
                spin += 1
                // Linear de propósito: a curva de pouso fica no ReelEffect, que também precisa da velocidade.
                withAnimation(.linear(duration: landing)) { progress = Double(spin) }
            }
    }
}

private struct ReelEffect: ViewModifier, Animatable {
    var t: Double
    let from, to, low: Int
    let cell: CGFloat
    let landing: Double

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(max(t, 0), 1)
        // Saída rápida e pouso longo e suave (ease-out quártico), sem overshoot.
        let eased = 1 - pow(1 - t, 4)
        let position = Double(from) + Double(to - from) * eased
        let cellsPerSecond = abs(Double(to - from)) * 4 * pow(1 - t, 3) / landing
        content
            .offset(y: -CGFloat(position - Double(low)) * cell)
            .blur(radius: min(cellsPerSecond / 40, 1) * cell * 0.06)
    }
}

#Preview {
    @Previewable @State var value: Decimal = 3321
    VStack(spacing: 24) {
        SlotText(text: Money(value).short, value: value).font(.urbanist(56, .light))
        Button("Trocar") { value = value == 3321 ? 1450 : value == 1450 ? 12480 : 3321 }
    }
}
