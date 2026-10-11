import SwiftUI
import UIKit

/// Journal du lecteur : pour comprendre un souci de lecture (pause, écran verrouillé…).
struct AudioLogView: View {
    @State private var lines: [String] = []
    @State private var copied = false

    var body: some View {
        List {
            Section {
                if lines.isEmpty {
                    Text(L("Rien pour le moment")).foregroundColor(.secondary)
                }
                ForEach(Array(lines.enumerated().reversed()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            } footer: {
                Text(L("Reproduisez le souci, puis copiez ce journal et envoyez-le."))
            }
        }
        .navigationTitle(L("Journal du lecteur"))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(copied ? L("Copié") : L("Copier")) {
                    UIPasteboard.general.string = lines.joined(separator: "\n")
                    copied = true
                }
                Button(L("Effacer")) {
                    AudioLog.clear()
                    lines = []
                }
            }
        }
        .onAppear { lines = AudioLog.all() }
    }
}
