import SwiftUI

// Frame "Splash" do Fyin.pen. O UILaunchScreen é só o fundo #161616 (sem imagem: o iOS cacheia o launch
// e mostraria um mascote velho); o Fy entra aqui, com fade e escala suaves.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var blink = false
    @State private var thinking = false
    @State private var exiting = false
    @State private var gone = false

    var body: some View {
        ZStack {
            Color.qInk
            Fy(blink: blink, thinking: thinking)
                .scaleEffect(exiting && !reduceMotion ? 0.001 : entered || reduceMotion ? 1 : 0.88)
                .opacity(entered ? 1 : 0)
            VStack(spacing: 8) {
                Text("fyin").font(.urbanistFixed(34)).tracking(-1.2).foregroundStyle(.white)
                Text("Lendo suas contas…").font(.urbanistFixed(15)).foregroundStyle(.white.opacity(0.55))
            }
            .opacity(thinking && !exiting ? 1 : 0)
            .offset(y: 111)
        }
        .ignoresSafeArea()
        .opacity(gone ? 0 : 1)
        .accessibilityHidden(true)
        .task { await run() }
    }

    private func run() async {
        // shortcut: duração fixa no lugar do fim do sync real, trocar pelo sinal da API.
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.enter(0.5)) { entered = true }
        if !reduceMotion {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeIn(duration: 0.08)) { blink = true }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeOut(duration: 0.12)) { blink = false }
            try? await Task.sleep(for: .milliseconds(120))
        }
        withAnimation(Motion.standard(Motion.considered)) { thinking = true }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(Motion.standard(Motion.considered)) { exiting = true }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 200))
        withAnimation(.easeOut(duration: 0.25)) { gone = true }
        try? await Task.sleep(for: .milliseconds(250))
        onFinish()
    }
}
