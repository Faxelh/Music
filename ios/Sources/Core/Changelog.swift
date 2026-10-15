import SwiftUI

/// Une mise à jour de l'historique (HISTORIQUE.json du dépôt, aussi intégré à l'app).
struct ChangeEntry: Decodable, Identifiable, Hashable {
    struct Item: Decodable, Hashable {
        let texte: String
        let plateforme: String?
    }

    let date: String
    let titre: String?
    let items: [Item]

    var id: String { date }

    var time: Date {
        ISO8601DateFormatter().date(from: date) ?? .distantPast
    }

    /// Lignes qui concernent l'iPhone.
    var lines: [String] {
        items.filter { $0.plateforme == nil || $0.plateforme == "ios" }.map { $0.texte }
    }

    var dayText: String {
        time.formatted(.dateTime.day().month(.wide).year().locale(Lang.locale))
    }
}

/// Historique des nouveautés : intégré à l'app (tout ce qui est installé) et en ligne
/// (ce qu'apporte une nouvelle version, avant de l'installer).
enum Changelog {
    static var remoteURL: URL? {
        URL(string: "https://raw.githubusercontent.com/\(Updater.repo)/main/HISTORIQUE.json")
    }

    static let bundled: [ChangeEntry] = {
        guard let url = Bundle.main.url(forResource: "historique", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return Changelog.decode(data)
    }()

    static func decode(_ data: Data) -> [ChangeEntry] {
        let list = (try? JSONDecoder().decode([ChangeEntry].self, from: data)) ?? []
        return list.filter { !$0.lines.isEmpty }.sorted { $0.time > $1.time }
    }

    static func remote() async -> [ChangeEntry] {
        guard let url = remoteURL else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return decode(data)
    }

    /// Les mises à jour publiées après la compilation `build` (minutes depuis 1970).
    static func since(build: Int, in list: [ChangeEntry]) -> [ChangeEntry] {
        let limit = Date(timeIntervalSince1970: Double(build) * 60)
        return list.filter { $0.time > limit }
    }

    /// Texte court pour une alerte : « • correctif » (au plus `limit` lignes).
    static func summary(_ entries: [ChangeEntry], limit: Int = 8) -> String {
        let lines = entries.flatMap { $0.lines }
        guard !lines.isEmpty else { return "" }
        var text = lines.prefix(limit).map { "• " + $0 }.joined(separator: "\n")
        if lines.count > limit {
            text += "\n" + L("… et {count} autre(s)", ["count": "\(lines.count - limit)"])
        }
        return text
    }
}

/// Liste de mises à jour avec leurs correctifs.
struct ChangeList: View {
    let entries: [ChangeEntry]

    var body: some View {
        ForEach(entries) { entry in
            Section {
                ForEach(entry.lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                        Text(line).font(.system(size: 15))
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = entry.titre {
                        Text(title).font(.system(size: 17, weight: .bold)).foregroundColor(.primary).textCase(nil)
                    }
                    Text(entry.dayText).font(.system(size: 12)).textCase(nil)
                }
            }
        }
    }
}

/// Réglages › Historique des nouveautés : tout ce qui a été ajouté ou corrigé.
struct ChangelogView: View {
    @ObservedObject private var updater = Updater.shared
    @State private var upcoming: [ChangeEntry] = []

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L("Version installée"))
                    Spacer()
                    Text(updater.currentVersion).foregroundColor(.secondary)
                }
            }
            if !upcoming.isEmpty {
                Section {
                    Text(L("Pas encore installé : disponible dans la prochaine mise à jour."))
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
                ChangeList(entries: upcoming)
            }
            let installed = Changelog.bundled.filter { entry in !upcoming.contains(where: { $0.id == entry.id }) }
            if installed.isEmpty && upcoming.isEmpty {
                Text(L("Aucun historique pour le moment.")).foregroundColor(.secondary)
            }
            ChangeList(entries: installed)
        }
        .navigationTitle(L("Historique des nouveautés"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            upcoming = Changelog.since(build: updater.currentBuild, in: await Changelog.remote())
        }
    }
}

/// Après une mise à jour : ce qui a changé, et la proposition de changer le nom de l'app.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [ChangeEntry]
    @State private var renaming = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Mise à jour installée"))
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                        Text(AppName.current + " " + Updater.shared.currentVersion)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ChangeList(entries: entries)
                Section {
                    NavigationLink {
                        AppNameView()
                    } label: {
                        Label(L("Changer le nom de l'application"), systemImage: "character.cursor.ibeam")
                    }
                    NavigationLink {
                        ChangelogView()
                    } label: {
                        Label(L("Historique des nouveautés"), systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text(L("Nom actuel : {name}", ["name": AppName.current]))
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Continuer")) { dismiss() }
                }
            }
        }
    }
}
