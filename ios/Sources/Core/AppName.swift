import Network
import SwiftUI
import UIKit

/// Nom de l'application choisi par l'utilisateur.
///
/// iOS ne laisse pas une app renommer son icône (le nom est figé dans l'app signée).
/// On enregistre donc le nom (affiché dans l'app) et on peut créer sur l'écran d'accueil
/// une icône à ce nom : un petit profil « raccourci » qui ouvre l'app, installé depuis Réglages.
enum AppName {
    static var defaultName: String { Updater.appName }
    /// Adresse qui ouvre l'app (déclarée dans project.yml).
    static var urlScheme: String { Updater.appName == "Faxel" ? "faxel" : "faxelmusic" }

    static var current: String {
        let saved = UserDefaults.standard.string(forKey: "appName.custom")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultName : saved
    }

    static func set(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        UserDefaults.standard.set(clean == defaultName ? "" : clean, forKey: "appName.custom")
    }

    /// Au premier lancement d'une nouvelle version : le numéro de la version d'avant (sinon nil).
    static func justUpdated() -> Int? {
        let defaults = UserDefaults.standard
        let last = defaults.integer(forKey: "appName.build")
        let now = Updater.shared.currentBuild
        if last != now { defaults.set(now, forKey: "appName.build") }
        return last > 0 && last < now ? last : nil
    }

    /// Icône de l'app (pour l'aperçu et l'icône de l'écran d'accueil).
    static var icon: UIImage? {
        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last, let image = UIImage(named: last) {
            return image
        }
        return UIImage(named: "AppIcon")
    }

    /// Profil de configuration : une icône « nom » sur l'écran d'accueil qui ouvre l'app.
    static func profile(named name: String) -> Data? {
        let base = (Bundle.main.bundleIdentifier ?? "com.faxel.app") + ".nom"
        var clip: [String: Any] = [
            "FullScreen": true,
            "IsRemovable": true,
            "Label": name,
            "PayloadDescription": name,
            "PayloadDisplayName": name,
            "PayloadIdentifier": base + ".icone",
            "PayloadType": "com.apple.webClip.managed",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
            "Precomposed": true,
            "URL": urlScheme + "://",
        ]
        if let png = icon?.pngData() { clip["Icon"] = png }
        let root: [String: Any] = [
            "PayloadContent": [clip],
            "PayloadDescription": L("Icône « {name} » sur l'écran d'accueil.", ["name": name]),
            "PayloadDisplayName": name,
            // Même identifiant à chaque fois : un nouveau nom remplace l'ancienne icône.
            "PayloadIdentifier": base,
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
        ]
        return try? PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    /// Ouvre le profil dans Safari (seul Safari sait l'installer).
    static func installHomeIcon(named name: String, done: @escaping (Bool) -> Void) {
        guard let data = profile(named: name) else { return done(false) }
        ProfileServer.shared.serve(data) { url in
            guard let url = url else { return done(false) }
            let safari = URL(string: "x-safari-" + url.absoluteString)
            if let safari = safari {
                UIApplication.shared.open(safari) { ok in
                    if ok { done(true) } else { UIApplication.shared.open(url) { done($0) } }
                }
            } else {
                UIApplication.shared.open(url) { done($0) }
            }
        }
    }
}

/// Mini serveur sur l'iPhone lui-même (127.0.0.1) : Safari y télécharge le profil.
final class ProfileServer {
    static let shared = ProfileServer()
    private var listener: NWListener?
    private var payload = Data()
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var stopWork: DispatchWorkItem?

    func serve(_ data: Data, ready: @escaping (URL?) -> Void) {
        stop()
        payload = data
        var answered = false
        let answer: (URL?) -> Void = { url in
            DispatchQueue.main.async {
                guard !answered else { return }
                answered = true
                ready(url)
            }
        }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: parameters, on: .any) else { return answer(nil) }
        let body = data
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                var response = Data(("HTTP/1.1 200 OK\r\n"
                    + "Content-Type: application/x-apple-aspen-config\r\n"
                    + "Content-Disposition: attachment; filename=\"icone.mobileconfig\"\r\n"
                    + "Content-Length: \(body.count)\r\n"
                    + "Connection: close\r\n\r\n").utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                if let port = listener?.port?.rawValue {
                    answer(URL(string: "http://127.0.0.1:\(port)/icone.mobileconfig"))
                } else {
                    answer(nil)
                }
            case .failed:
                answer(nil)
                DispatchQueue.main.async { self?.stop() }
            default:
                break
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        // L'app passe en arrière-plan quand Safari s'ouvre : on garde le serveur 2 minutes.
        task = UIApplication.shared.beginBackgroundTask { [weak self] in self?.stop() }
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        listener?.cancel()
        listener = nil
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }
}

/// Réglages › Nom de l'application.
struct AppNameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = AppName.current
    @State private var saved = false
    @State private var opening = false
    @State private var failed = false
    /// Ouvert après une mise à jour (dans une feuille) : bouton « OK ».
    var inSheet = false

    private var clean: String {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? AppName.defaultName : String(text.prefix(30))
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Group {
                        if let icon = AppName.icon {
                            Image(uiImage: icon).resizable()
                        } else {
                            RoundedRectangle(cornerRadius: 16).fill(Color.accentColor)
                        }
                    }
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    Text(clean)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                TextField(AppName.defaultName, text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(save)
                Button(L("Enregistrer"), action: save)
                if clean != AppName.defaultName {
                    Button(L("Nom d'origine")) {
                        name = AppName.defaultName
                        save()
                    }
                }
            } footer: {
                Text(saved ? L("Nom enregistré.") : L("Le nom est utilisé dans l'app."))
            }

            Section {
                Button {
                    save()
                    opening = true
                    AppName.installHomeIcon(named: clean) { ok in
                        opening = false
                        failed = !ok
                    }
                } label: {
                    HStack {
                        Label(L("Créer l'icône « {name} »", ["name": clean]), systemImage: "apps.iphone.badge.plus")
                        if opening {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(opening)
                VStack(alignment: .leading, spacing: 6) {
                    step(1, L("Touchez « Créer l'icône », puis « Autoriser » dans Safari."))
                    step(2, L("Ouvrez Réglages › Profil téléchargé (en haut) › Installer."))
                    step(3, L("L'icône « {name} » apparaît sur l'écran d'accueil. Appuyez longuement sur l'ancienne icône › Retirer de l'écran d'accueil (l'app reste dans la bibliothèque d'apps).", ["name": clean]))
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            } header: {
                Text(L("Sur l'écran d'accueil"))
            } footer: {
                Text(failed ? L("Impossible d'ouvrir Safari. Réessayez.")
                     : L("iOS ne permet pas à une app de renommer elle-même son icône : cette icône à votre nom ouvre l'app. Pour changer de nom plus tard, recommencez ici."))
            }
        }
        .navigationTitle(L("Nom de l'application"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
    }

    private func save() {
        AppName.set(name)
        name = AppName.current
        withAnimation { saved = true }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
        }
    }
}

/// Après une mise à jour : la liste des nouveautés et correctifs, et la proposition
/// de changer le nom de l'application.
struct AppNameAfterUpdate: ViewModifier {
    @State private var news: [ChangeEntry]?

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { news.map { WhatsNew(entries: $0) } }, set: { if $0 == nil { news = nil } })) { item in
                WhatsNewView(entries: item.entries)
            }
            .task {
                guard let previous = AppName.justUpdated() else { return }
                var entries = Changelog.since(build: previous, in: Changelog.bundled)
                if entries.isEmpty { entries = Array(Changelog.bundled.prefix(1)) }
                try? await Task.sleep(nanoseconds: 800_000_000)
                news = entries
            }
    }
}

private struct WhatsNew: Identifiable {
    let entries: [ChangeEntry]
    var id: String { entries.map { $0.id }.joined() }
}
