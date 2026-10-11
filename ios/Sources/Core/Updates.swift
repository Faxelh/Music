import Foundation
import SwiftUI
import UIKit

/// Nouvelle version publiée sur GitHub (Releases, étiquette ios-NUMÉRO).
struct AvailableVersion: Identifiable, Equatable {
    let number: Int
    /// Version affichée, ex. « 2026.1.3 ».
    let version: String
    let ipaURL: URL
    let notes: String
    var id: Int { number }
}

/// Mises à jour (comme Elara) : chaque compilation GitHub publie l'IPA dans « Releases ».
/// L'app compare ce numéro au sien et propose la mise à jour : avec SideStore / AltStore
/// elle s'installe directement, sinon on télécharge l'IPA pour Sideloadly.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "Faxelh/Music"
    static let appName = "Music"
    static let source = "https://github.com/\(repo)/releases/download/ios-source/source.json"

    @Published private(set) var available: AvailableVersion?
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    @Published var sideStoreMissing = false
    @Published private(set) var downloading = false
    @Published private(set) var ipaFile: URL?
    @Published private(set) var downloadFailed = false

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Au plus une fois par jour, sauf si `force`.
    @discardableResult
    @MainActor
    func check(force: Bool = false) async -> AvailableVersion? {
        let key = "updates.last"
        let last = UserDefaults.standard.double(forKey: key)
        if !force, Date().timeIntervalSince1970 - last < 24 * 3600 { return available }
        checking = true
        failed = false
        defer { checking = false }
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=20") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                failed = true
                return nil
            }
            var best: AvailableVersion?
            for release in list {
                guard let tag = release["tag_name"] as? String, tag.hasPrefix("ios-"),
                      let number = Int(tag.dropFirst(4)),
                      let assets = release["assets"] as? [[String: Any]],
                      let ipa = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".ipa") == true }),
                      let link = (ipa["browser_download_url"] as? String).flatMap(URL.init(string:)) else { continue }
                if number > (best?.number ?? 0) {
                    let name = (release["name"] as? String ?? "").split(separator: " ").last.map(String.init) ?? "\(number)"
                    best = AvailableVersion(number: number, version: name, ipaURL: link, notes: release["body"] as? String ?? "")
                }
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
            available = best.flatMap { $0.number > currentBuild ? $0 : nil }
            return available
        } catch {
            failed = true
            return nil
        }
    }

    /// Ouvre SideStore (ou AltStore) sur la source de l'app : elle s'y met à jour toute seule ensuite.
    @MainActor
    func openInSideStore() {
        let encoded = Self.source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? Self.source
        guard let sidestore = URL(string: "sidestore://source?url=\(encoded)"),
              let altstore = URL(string: "altstore://source?url=\(encoded)") else { return }
        sideStoreMissing = false
        UIApplication.shared.open(sidestore) { ok in
            guard !ok else { return }
            UIApplication.shared.open(altstore) { ok2 in
                Task { @MainActor in Updater.shared.sideStoreMissing = !ok2 }
            }
        }
    }

    /// Télécharge l'IPA dans l'app (un lien GitHub ouvrirait l'app GitHub ou Safari).
    @MainActor
    func downloadIPA(_ version: AvailableVersion) async {
        guard !downloading else { return }
        downloading = true
        downloadFailed = false
        ipaFile = nil
        defer { downloading = false }
        do {
            let (temp, response) = try await URLSession.shared.download(from: version.ipaURL)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                downloadFailed = true
                return
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("maj", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("\(Self.appName)-\(version.version).ipa")
            try FileManager.default.moveItem(at: temp, to: target)
            ipaFile = target
        } catch {
            downloadFailed = true
        }
    }
}

/// Proposition de mise à jour au démarrage (une fois par jour).
struct UpdatePrompt: ViewModifier {
    @ObservedObject private var updater = Updater.shared
    @State private var offered: AvailableVersion?
    @State private var sheet = false

    func body(content: Content) -> some View {
        content
            .task {
                if let v = await updater.check(), UserDefaults.standard.integer(forKey: "updates.ignored") != v.number {
                    offered = v
                }
            }
            .alert(
                L("Nouvelle version disponible"),
                isPresented: Binding(get: { offered != nil }, set: { if !$0 { offered = nil } }),
                presenting: offered
            ) { v in
                Button(L("Mettre à jour avec SideStore")) { updater.openInSideStore() }
                Button(L("Télécharger l'IPA (Sideloadly)")) { sheet = true }
                Button(L("Plus tard"), role: .cancel) {
                    UserDefaults.standard.set(v.number, forKey: "updates.ignored")
                }
            } message: { v in
                Text(L("{app} {new} est disponible (vous avez la {old}).",
                       ["app": Updater.appName, "new": v.version, "old": updater.currentVersion]))
            }
            .sheet(isPresented: $sheet) {
                NavigationStack {
                    UpdatesView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("OK")) { sheet = false } } }
                }
            }
    }
}

extension View {
    func updatePrompt() -> some View { modifier(UpdatePrompt()) }
}

/// Réglages › Mises à jour.
struct UpdatesView: View {
    @ObservedObject private var updater = Updater.shared
    @State private var checked = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L("Version installée"))
                    Spacer()
                    Text("\(updater.currentVersion) (\(updater.currentBuild))").foregroundColor(.secondary)
                }
                Button {
                    Task {
                        await updater.check(force: true)
                        checked = true
                    }
                } label: {
                    HStack {
                        Text(L("Rechercher une mise à jour"))
                        Spacer()
                        if updater.checking { ProgressView() }
                    }
                }
                if let v = updater.available {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("{app} {new} est disponible", ["app": Updater.appName, "new": v.version])).font(.headline)
                        if !v.notes.isEmpty { Text(v.notes).font(.caption).foregroundColor(.secondary) }
                    }
                    Button { updater.openInSideStore() } label: {
                        Label(L("Mettre à jour avec SideStore"), systemImage: "arrow.down.app")
                    }
                    if updater.downloading {
                        HStack {
                            Text(L("Téléchargement de l'IPA…"))
                            Spacer()
                            ProgressView()
                        }
                    } else if let file = updater.ipaFile {
                        ShareLink(item: file) {
                            Label(L("Enregistrer l'IPA (Fichiers, AirDrop…)"), systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button { Task { await updater.downloadIPA(v) } } label: {
                            Label(L("Télécharger l'IPA (Sideloadly)"), systemImage: "arrow.down.doc")
                        }
                    }
                    if updater.downloadFailed {
                        Label(L("Le téléchargement de l'IPA a échoué. Réessayez."), systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                } else if checked && !updater.checking {
                    Label(updater.failed ? L("Vérification impossible. Vérifiez la connexion.") : L("L'app est à jour."),
                          systemImage: updater.failed ? "wifi.exclamationmark" : "checkmark.circle")
                        .foregroundColor(updater.failed ? .orange : .green)
                }
            }
            Section {
                Button { updater.openInSideStore() } label: {
                    Label(L("Ajouter à SideStore / AltStore"), systemImage: "plus.app")
                }
                Button {
                    UIPasteboard.general.string = Updater.source
                } label: {
                    Label(L("Copier l'adresse de la source"), systemImage: "doc.on.doc")
                }
                if updater.sideStoreMissing {
                    Label(L("SideStore et AltStore ne sont pas installés sur cet iPhone."), systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
            } footer: {
                Text(L("Avec SideStore ou AltStore, l'app se met à jour toute seule dès qu'une nouvelle version est publiée sur GitHub. Avec Sideloadly : téléchargez l'IPA, envoyez-la sur l'ordinateur (AirDrop, Fichiers…) puis installez-la par-dessus : vos fichiers sont conservés."))
            }
        }
        .navigationTitle(L("Mises à jour"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
