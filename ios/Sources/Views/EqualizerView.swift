import SwiftUI

/// Égaliseur 10 bandes, préréglages et vitesse de lecture.
struct EqualizerView: View {
    @EnvironmentObject var player: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle(isOn: Binding(get: { player.eqEnabled }, set: { player.setEqualizer(enabled: $0) })) {
                        Label(L("Égaliseur"), systemImage: "slider.vertical.3")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AudioEngine.presets, id: \.id) { preset in
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        player.applyPreset(preset.id)
                                    }
                                } label: {
                                    Text(L(preset.name))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(player.eqPreset == preset.id ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(Capsule().fill(player.eqPreset == preset.id ? Color.accentColor
                                                                   : Color(.tertiarySystemFill)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<AudioEngine.bandFrequencies.count, id: \.self) { band in
                            VStack(spacing: 8) {
                                Text(gainText(player.eqGains[band]))
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundColor(.secondary)
                                VerticalSlider(value: Binding(get: { Double(player.eqGains[band]) },
                                                              set: { player.setGain(Float($0), band: band) }),
                                               range: -12...12)
                                    .frame(height: 210)
                                Text(frequencyText(AudioEngine.bandFrequencies[band]))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 12)
                    .opacity(player.eqEnabled ? 1 : 0.45)

                    Button {
                        withAnimation { player.applyPreset("flat") }
                    } label: {
                        Label(L("Remettre à plat"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(L("Vitesse"), systemImage: "speedometer")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Text(Fmt.rate(player.rate))
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundColor(.accentColor)
                        }
                        Slider(value: Binding(get: { Double(player.rate) },
                                              set: { player.setRate(Float(($0 * 20).rounded() / 20)) }),
                               in: 0.5...2)
                        Text(L("La voix garde sa hauteur normale quelle que soit la vitesse."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            .navigationTitle(L("Son"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func gainText(_ value: Float) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func frequencyText(_ value: Float) -> String {
        value >= 1000 ? "\(Int(value / 1000))k" : "\(Int(value))"
    }
}

/// Curseur vertical (bandes de l'égaliseur).
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let middle = (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 6)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: abs(fraction - middle) * height)
                    .offset(y: -min(fraction, middle) * height)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: 22, height: 22)
                    .offset(y: -fraction * height + 11)
            }
            .frame(width: geometry.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let ratio = 1 - min(1, max(0, drag.location.y / max(1, height)))
                        let raw = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                        value = (raw * 2).rounded() / 2
                    }
            )
        }
    }
}
