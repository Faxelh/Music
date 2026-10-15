import SwiftUI
import UIKit

/// Sélection de plusieurs morceaux pour les exporter, les partager, les ranger ou les supprimer.
final class SelectionModel: ObservableObject {
    @Published var active = false
    @Published var ids: Set<String> = []

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func start() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { active = true }
    }

    func finish() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            active = false
            ids = []
        }
    }
}

/// Rond coché au début d'une ligne.
struct SelectionCheck: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(selected ? Color.accentColor : Color.clear)
            Circle().stroke(selected ? Color.accentColor : Color.secondary, lineWidth: 2)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// Barre du bas en mode sélection : tout sélectionner, Fichiers, Partager, Playlist, File, Favoris, Supprimer.
struct SelectionBar: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var sheets: SheetCenter
    @ObservedObject var selection: SelectionModel
    let all: [Song]
    @State private var exportURLs: [URL]?
    @State private var shareURLs: [URL]?
    @State private var confirmDelete = false

    private var allSelected: Bool { !all.isEmpty && selection.ids.count >= all.count }

    var body: some View {
        let picked = all.filter { selection.ids.contains($0.id) }
        let files = picked.filter { !$0.isIpod && FileManager.default.fileExists(atPath: $0.url.path) }.map { $0.url }
        VStack(spacing: 10) {
            HStack {
                Button(allSelected ? L("Tout désélectionner") : L("Tout sélectionner")) {
                    selection.ids = allSelected ? [] : Set(all.map { $0.id })
                }
                .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(L("{count} sélectionné(s)", ["count": "\(picked.count)"]))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 0) {
                action(L("Fichiers"), "folder", enabled: !files.isEmpty) { exportURLs = files }
                action(L("Partager"), "square.and.arrow.up", enabled: !files.isEmpty) { shareURLs = files }
                action(L("Playlist"), "text.badge.plus", enabled: !picked.isEmpty) {
                    sheets.addToPlaylist = picked
                    selection.finish()
                }
                action(L("File"), "text.append", enabled: !picked.isEmpty) {
                    player.addToQueue(picked)
                    AppState.shared.show(L("Ajouté à la file de lecture."), .ok)
                    selection.finish()
                }
                action(L("Favoris"), "heart", enabled: !picked.isEmpty) {
                    library.setFavorites(picked)
                    selection.finish()
                }
                action(L("Supprimer"), "trash", enabled: !picked.isEmpty, destructive: true) { confirmDelete = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sheet(isPresented: Binding(get: { exportURLs != nil }, set: { if !$0 { exportURLs = nil } })) {
            FilesExporter(urls: exportURLs ?? []) { saved in
                exportURLs = nil
                if saved {
                    AppState.shared.show(L("{count} élément(s) enregistré(s) dans Fichiers.", ["count": "\(files.count)"]), .ok)
                    selection.finish()
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { shareURLs != nil }, set: { if !$0 { shareURLs = nil } })) {
            ShareSheet(items: shareURLs ?? [])
                .ignoresSafeArea()
        }
        .confirmationDialog(L("Supprimer {count} élément(s) ?", ["count": "\(picked.count)"]),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Supprimer les fichiers"), role: .destructive) {
                library.deleteMany(picked)
                selection.finish()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Les fichiers seront effacés de l'iPhone."))
        }
    }

    private func action(_ title: String, _ icon: String, enabled: Bool, destructive: Bool = false,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(enabled ? (destructive ? Color.red : Color.primary) : Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)
    }
}

/// « Enregistrer dans Fichiers » : l'utilisateur choisit le dossier.
struct FilesExporter: UIViewControllerRepresentable {
    let urls: [URL]
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: (Bool) -> Void

        init(done: @escaping (Bool) -> Void) {
            self.done = done
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            done(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            done(false)
        }
    }
}

/// Feuille de partage d'iOS (AirDrop, WhatsApp…) pour plusieurs fichiers.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Bouton « Sélectionner » / « OK ».
struct SelectButton: View {
    @ObservedObject var selection: SelectionModel

    var body: some View {
        Button {
            if selection.active { selection.finish() } else { selection.start() }
        } label: {
            Text(selection.active ? L("OK") : L("Sélectionner"))
                .font(.system(size: 15, weight: .semibold))
        }
    }
}
