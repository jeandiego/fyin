import SwiftUI

/// "Segmented Control / Escuro" do Fyin.pen: trilho esmaecido e uma pílula branca que desliza até a opção escolhida
/// (mesmo gesto do Chip Group do Arc). Para 2 a 4 opções de rótulo curto sobre fundo escuro; no claro vale o Picker segmentado.
struct SegmentedSwitch<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    /// Nome do grupo para o VoiceOver ("Moeda").
    let label: String
    let title: (Value) -> String

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    withAnimation(reduceMotion ? Motion.standard(Motion.quick) : Motion.spring(Motion.base)) { selection = option }
                } label: {
                    Text(title(option)).font(.urbanist(13, .medium))
                        .foregroundStyle(selected ? Color.qInk : .white.opacity(0.7))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background {
                            if selected { Capsule().fill(.white).matchedGeometryEffect(id: "thumb", in: thumb) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.qOnDarkLine))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
