import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Réglages : profil, apparence, lecteur, paroles, son, bibliothèque.
struct SettingsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    @AppStorage("language") private var language = "system"
    @AppStorage("theme") private var theme = "system"
    @State private var pickingProfile = false
    @State private var importing = false
    @State private var showWifi = false
    @State private var showEqualizer = false
    @State private var customColor = Color.pink

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                appearanceSection
                playerSection
                lyricsSection
                Section {
                    Button {
                        showEqualizer = true
                    } label: {
                        HStack {
                            SettingsLabel(title: L("Égaliseur et vitesse"), icon: "slider.vertical.3", color: .orange)
                            Spacer()
                            Text(player.eqEnabled ? L(AudioEngine.presets.first { $0.id == player.eqPreset }?.name ?? "Personnalisé") : L("Désactivé"))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text(L("Son"))
                }
                librarySection
                Section {
                    Picker(selection: $language) {
                        Text(L("Langue du téléphone")).tag("system")
                        ForEach(Lang.supported, id: \.self) { code in
                            Text(Lang.name(code)).tag(code)
                        }
                    } label: {
                        SettingsLabel(title: L("Langue"), icon: "globe", color: .blue)
                    }
                    Picker(selection: $theme) {
                        Text(L("Automatique (système)")).tag("system")
                        Text(L("Clair")).tag("light")
                        Text(L("Sombre")).tag("dark")
                    } label: {
                        SettingsLabel(title: L("Thème"), icon: "circle.lefthalf.filled", color: .indigo)
                    }
                } header: {
                    Text(L("Général"))
                } footer: {
                    Text(L("Music · version {version} · par Faxel", ["version": version]))
                }
            }
            .miniPlayerInset()
            .navigationTitle(L("Réglages"))
            .importer(isPresented: $importing)
            .sheet(isPresented: $showWifi) {
                WifiTransferView()
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView().environmentObject(player)
            }
            .photoSheet(isPresented: $pickingProfile) { image in
                withAnimation { appearance.setProfileImage(image) }
                AppState.shared.show(L("Photo enregistrée."), .ok)
            }
            .onAppear { customColor = appearance.accent }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Profil

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                Button {
                    pickingProfile = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatar(size: 76)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.accentColor))
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    TextField(L("Votre prénom"), text: $appearance.userName)
                        .font(.system(size: 20, weight: .bold))
                        .textInputAutocapitalization(.words)
                    Text(library.storageText())
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
            if appearance.profileImage != nil {
                Button(role: .destructive) {
                    appearance.setProfileImage(nil)
                } label: {
                    Text(L("Retirer la photo de profil"))
                }
            }
        } header: {
            Text(L("Profil"))
        } footer: {
            Text(L("Votre photo et votre prénom s'affichent sur l'accueil."))
        }
    }

    // MARK: - Apparence

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Couleur"))
                    .font(.system(size: 15, weight: .medium))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Appearance.accents, id: \.self) { hex in
                            Button {
                                withAnimation(.spring(response: 0.3)) { appearance.accentHex = hex }
                                customColor = Color(hex: hex)
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle().stroke(Color.primary, lineWidth: appearance.accentHex == hex ? 3 : 0)
                                            .padding(-4)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        ColorPicker("", selection: $customColor, supportsOpacity: false)
                            .labelsHidden()
                            .onChange(of: customColor) { color in
                                let hex = color.hex
                                if hex != appearance.accentHex { appearance.accentHex = hex }
                            }
                    }
                    .padding(6)
                }
            }
            .padding(.vertical, 4)
            Toggle(isOn: $appearance.animations) {
                SettingsLabel(title: L("Animations"), icon: "sparkles", color: .purple)
            }
        } header: {
            Text(L("Apparence"))
        }
    }

    // MARK: - Lecteur

    private var playerSection: some View {
        Section {
            NavigationLink {
                BackgroundPicker()
            } label: {
                HStack {
                    SettingsLabel(title: L("Fond du lecteur"), icon: appearance.background.icon, color: .pink)
                    Spacer()
                    Text(appearance.background.name).foregroundColor(.secondary)
                }
            }
            Picker(selection: $appearance.coverStyle) {
                ForEach(Appearance.CoverStyle.allCases) { style in
                    Text(style.name).tag(style)
                }
            } label: {
                SettingsLabel(title: L("Pochette"), icon: "opticaldisc", color: .teal)
            }
            Picker(selection: $appearance.visualizer) {
                ForEach(Appearance.Visualizer.allCases) { style in
                    Text(style.name).tag(style)
                }
            } label: {
                SettingsLabel(title: L("Visualiseur"), icon: "waveform", color: .green)
            }
            VStack(alignment: .leading, spacing: 6) {
                SettingsLabel(title: L("Assombrir le fond"), icon: "sun.min.fill", color: .gray)
                Slider(value: $appearance.backgroundDim, in: 0...0.8)
            }
            NavigationLink {
                AppNameView()
            } label: {
                SettingsLabel(title: L("Nom de l'application"), icon: "character.cursor.ibeam", color: .purple)
            }
            NavigationLink {
                UpdatesView()
            } label: {
                SettingsLabel(title: L("Mises à jour"), icon: "arrow.down.circle.fill", color: .green)
            }
            NavigationLink {
                AudioLogView()
            } label: {
                SettingsLabel(title: L("Journal du lecteur"), icon: "list.bullet.rectangle", color: .gray)
            }
        } header: {
            Text(L("Lecteur"))
        } footer: {
            Text(L("Le visualiseur danse au rythme de la musique, l'aurore respire avec les basses."))
        }
    }

    // MARK: - Paroles

    private var lyricsSection: some View {
        Section {
            Toggle(isOn: $appearance.lyricsAuto) {
                SettingsLabel(title: L("Chercher les paroles automatiquement"), icon: "quote.bubble.fill", color: .blue)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SettingsLabel(title: L("Taille des paroles"), icon: "textformat.size", color: .indigo)
                    Spacer()
                    Text("\(Int(appearance.lyricsSize))").foregroundColor(.secondary)
                }
                Slider(value: $appearance.lyricsSize, in: 18...38, step: 1)
            }
        } header: {
            Text(L("Paroles"))
        } footer: {
            Text(L("Paroles trouvées dans le fichier, dans un .lrc du même nom, ou en ligne (LRCLIB). Depuis le lecteur : ⋯ › Paroles pour les générer ou les écrire."))
        }
    }

    // MARK: - Bibliothèque

    private var librarySection: some View {
        Section {
            NavigationLink {
                SourcesView()
            } label: {
                HStack {
                    SettingsLabel(title: L("Sources de musique"), icon: "music.note.house.fill", color: .pink)
                    Spacer()
                    Text("\(library.linkedFolders.count + (library.mediaLibraryEnabled ? 1 : 0) + 1)")
                        .foregroundColor(.secondary)
                }
            }
            Button {
                importing = true
            } label: {
                SettingsLabel(title: L("Importer depuis Fichiers"), icon: "square.and.arrow.down.fill", color: .accentColor)
            }
            .foregroundColor(.primary)
            Button {
                showWifi = true
            } label: {
                SettingsLabel(title: L("Transfert Wi-Fi depuis l'ordinateur"), icon: "wifi", color: .blue)
            }
            .foregroundColor(.primary)
            Button {
                library.scan(force: true) { added in
                    AppState.shared.show(added > 0 ? L("{count} nouveau(x) morceau(x).", ["count": "\(added)"])
                                         : L("Bibliothèque à jour."), .ok)
                }
            } label: {
                SettingsLabel(title: L("Actualiser la bibliothèque"), icon: "arrow.clockwise", color: .green)
            }
            .foregroundColor(.primary)
            Button {
                library.openInFiles()
            } label: {
                SettingsLabel(title: L("Ouvrir dans Fichiers"), icon: "folder.fill", color: .blue)
            }
            .foregroundColor(.primary)
        } header: {
            Text(L("Bibliothèque"))
        } footer: {
            Text(L("Avec 3uTools : Apps › Music › Documents (partage de fichiers), glissez vos sons. Ils apparaissent à l'ouverture de Music ou en tirant la liste vers le bas."))
        }
    }
}

/// Choix du fond du lecteur, avec aperçu animé.
struct BackgroundPicker: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    @State private var picking = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Appearance.Background.allCases) { style in
                    if style == .photo {
                        Button {
                            picking = true
                        } label: {
                            tile(style)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            withAnimation { appearance.background = style }
                        } label: {
                            tile(style)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            if appearance.playerImage != nil {
                Button(role: .destructive) {
                    appearance.setPlayerImage(nil)
                } label: {
                    Text(L("Retirer ma photo du lecteur"))
                }
                .padding(.bottom, 20)
            }
            Text(L("Choisissez « Ma photo » pour mettre une de vos photos en fond du lecteur, avec un lent effet de zoom."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
        .miniPlayerInset()
        .navigationTitle(L("Fond du lecteur"))
        .photoSheet(isPresented: $picking) { image in
            withAnimation { appearance.setPlayerImage(image) }
            AppState.shared.show(L("Photo enregistrée."), .ok)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ style: Appearance.Background) -> some View {
        let colors = LibraryStore.shared.colors(for: player.current)
        return VStack(spacing: 8) {
            ZStack {
                switch style {
                case .aurora:
                    AuroraView(colors: colors, animated: appearance.animations)
                case .artwork:
                    ArtworkBackdrop(url: player.current.flatMap { LibraryStore.shared.artworkURL($0) }, colors: colors,
                                    animated: appearance.animations)
                case .photo:
                    if let image = appearance.playerImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundColor(.white)
                    }
                case .gradient:
                    RainbowBackdrop(colors: colors, animated: appearance.animations)
                case .black:
                    Color.black
                }
            }
            .frame(height: 200)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: appearance.background == style ? 4 : 0)
            )
            Label(style.name, systemImage: style.icon)
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

/// Où Music cherche les sons : son dossier, la musique de l'iPhone, des dossiers liés.
struct SourcesView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var linking = false

    var body: some View {
        List {
            Section {
                HStack {
                    SettingsLabel(title: L("Dossier de Music"), icon: "folder.fill", color: .blue)
                    Spacer()
                    Text("\(library.songs.filter { $0.source == "doc" }.count)").foregroundColor(.secondary)
                }
            } footer: {
                Text(L("Avec 3uTools : Apps › Music › Documents. Avec l'app Fichiers : Sur mon iPhone › Music."))
            }
            Section {
                Toggle(isOn: Binding(get: { library.mediaLibraryEnabled }, set: { library.enableMediaLibrary($0) })) {
                    SettingsLabel(title: L("Musique de l'iPhone"), icon: "music.note", color: .red)
                }
            } footer: {
                Text(L("Les morceaux déjà dans l'app Musique (synchronisés avec iTunes, Finder ou 3uTools). Les titres Apple Music protégés ou non téléchargés ne peuvent pas être lus par une autre app."))
            }
            Section {
                ForEach(library.linkedFolders) { folder in
                    HStack {
                        SettingsLabel(title: folder.name, icon: "folder.badge.gearshape", color: .orange)
                        Spacer()
                        Text("\(library.songs.filter { $0.folderID == folder.id }.count)").foregroundColor(.secondary)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets { library.unlinkFolder(library.linkedFolders[offset].id) }
                }
                Button {
                    linking = true
                } label: {
                    Label(L("Relier un dossier…"), systemImage: "plus.circle.fill")
                }
            } header: {
                Text(L("Dossiers liés"))
            } footer: {
                Text(L("Choisissez par exemple « Sur mon iPhone › Faxel » : les musiques téléchargées avec Faxel apparaîtront ici toutes seules. Balayez pour délier (les fichiers ne sont pas supprimés)."))
            }
        }
        .miniPlayerInset()
        .navigationTitle(L("Sources de musique"))
        .fileImporter(isPresented: $linking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.linkFolder(url)
            }
        }
    }
}
