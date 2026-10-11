import AVKit
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Images

private let artworkPalettes: [[Color]] = [
    [Color(red: 1.0, green: 0.18, blue: 0.38), Color(red: 1.0, green: 0.55, blue: 0.2)],
    [Color(red: 0.35, green: 0.35, blue: 0.95), Color(red: 0.62, green: 0.25, blue: 0.85)],
    [Color(red: 0.10, green: 0.70, blue: 0.65), Color(red: 0.15, green: 0.35, blue: 0.70)],
    [Color(red: 0.95, green: 0.35, blue: 0.60), Color(red: 0.98, green: 0.65, blue: 0.35)],
    [Color(red: 0.30, green: 0.75, blue: 0.40), Color(red: 0.10, green: 0.45, blue: 0.40)],
    [Color(red: 0.25, green: 0.30, blue: 0.45), Color(red: 0.55, green: 0.45, blue: 0.30)],
]

func artworkColors(_ seed: String) -> [Color] {
    var hash: UInt32 = 5381
    for byte in seed.utf8 {
        hash = (hash &* 33) &+ UInt32(byte)
    }
    return artworkPalettes[Int(hash % UInt32(artworkPalettes.count))]
}

/// Image enregistrée sur l'iPhone (pochette, photo).
struct LocalImage: View {
    let url: URL
    var version = 0
    @State private var image: UIImage?

    init(url: URL, version: Int = 0) {
        self.url = url
        self.version = version
        _image = State(initialValue: ImageCache.shared.image(url))
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .onAppear(perform: load)
        .onChange(of: url) { _ in load() }
        .onChange(of: version) { _ in
            ImageCache.shared.forget(url)
            load()
        }
    }

    private func load() {
        if let cached = ImageCache.shared.image(url) {
            image = cached
            return
        }
        let wanted = url
        ImageCache.shared.load(wanted) { loaded in
            if wanted == url { image = loaded }
        }
    }
}

/// Pochette : image du fichier (ou choisie), sinon un dégradé avec une icône.
struct Artwork: View {
    @ObservedObject private var library = LibraryStore.shared
    let url: URL?
    let seed: String
    var icon = "music.note"
    var size: CGFloat? = 52
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            LinearGradient(colors: artworkColors(seed), startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon)
                .font(.system(size: (size ?? 160) * 0.34, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            if let url = url {
                LocalImage(url: url, version: library.artworkVersion)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct SongArtwork: View {
    @ObservedObject private var library = LibraryStore.shared
    let song: Song
    var size: CGFloat? = 52
    var radius: CGFloat = 8

    var body: some View {
        Artwork(url: library.artworkURL(song), seed: song.id, size: size, radius: radius)
    }
}

struct PlaylistArtwork: View {
    @ObservedObject private var library = LibraryStore.shared
    let playlist: Playlist
    var size: CGFloat? = 56
    var radius: CGFloat = 8

    var body: some View {
        let first = library.songs(in: playlist).first { library.artworkURL($0) != nil }
        let url = library.coverURL(playlist) ?? first.flatMap { library.artworkURL($0) }
        Artwork(url: url, seed: playlist.id, icon: "music.note.list", size: size, radius: radius)
    }
}

/// Photo de profil (ou initiale).
struct ProfileAvatar: View {
    @ObservedObject private var appearance = Appearance.shared
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let image = appearance.profileImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [appearance.accent, appearance.accent.opacity(0.6)], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                if let letter = appearance.userName.trimmingCharacters(in: .whitespaces).first {
                    Text(String(letter).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: size > 60 ? 3 : 1.5))
    }
}

/// Petit indicateur « en cours de lecture » (barres animées).
struct PlayingBars: View {
    var playing: Bool
    var color: Color = .accentColor
    @State private var animate = false
    private static let high: [CGFloat] = [12, 6, 10]
    private static let low: [CGFloat] = [5, 9, 4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: animate && playing ? PlayingBars.high[index] : PlayingBars.low[index])
            }
        }
        .frame(width: 16, height: 14, alignment: .bottom)
        .animation(playing ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: animate)
        .onAppear { animate = true }
    }
}

/// Bouton AirPlay natif.
struct AirPlayButton: UIViewRepresentable {
    var tint: UIColor = .label

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = UIColor(Appearance.shared.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
    }
}

// MARK: - Lignes

/// Ligne d'un morceau : pochette, titre, artiste, menu ⋯.
struct SongRow: View {
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var library: LibraryStore
    let song: Song
    var number: Int? = nil
    var showArtwork = true
    let onTap: () -> Void

    private var isCurrent: Bool { player.current?.id == song.id }

    var body: some View {
        HStack(spacing: 12) {
            if let number = number {
                Text("\(number)")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            if showArtwork {
                ZStack {
                    SongArtwork(song: song, size: 50, radius: 7)
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35))
                            .frame(width: 50, height: 50)
                        PlayingBars(playing: player.isPlaying, color: .white)
                    }
                }
            } else if isCurrent {
                PlayingBars(playing: player.isPlaying)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if library.isFavorite(song) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                    Text(song.album.map { song.displayArtist + " · " + $0 } ?? song.displayArtist)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Menu {
                SongMenu(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            SongMenu(song: song)
        }
    }
}

/// Toutes les actions d'un morceau.
struct SongMenu: View {
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sheets: SheetCenter
    let song: Song

    var body: some View {
        Button {
            player.playNext(song)
            AppState.shared.show(L("Lu ensuite : {title}", ["title": song.title]), .ok)
        } label: {
            Label(L("Lire ensuite"), systemImage: "text.insert")
        }
        Button {
            player.addToQueue([song])
            AppState.shared.show(L("Ajouté à la file de lecture."), .ok)
        } label: {
            Label(L("Ajouter à la file de lecture"), systemImage: "text.append")
        }
        Divider()
        Button {
            library.toggleFavorite(song)
        } label: {
            if library.isFavorite(song) {
                Label(L("Retirer des favoris"), systemImage: "heart.slash")
            } else {
                Label(L("Favori"), systemImage: "heart")
            }
        }
        Button {
            sheets.addToPlaylist = [song]
        } label: {
            Label(L("Ajouter à une playlist"), systemImage: "text.badge.plus")
        }
        Button {
            sheets.artworkFor = song
        } label: {
            Label(L("Changer la pochette"), systemImage: "photo")
        }
        Button {
            sheets.lyricsFor = song
        } label: {
            Label(L("Paroles"), systemImage: "quote.bubble")
        }
        if !song.isIpod {
            ShareLink(item: song.url) {
                Label(L("Partager"), systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        Button(role: .destructive) {
            sheets.deleting = song
        } label: {
            Label(song.isIpod ? L("Retirer de la bibliothèque") : L("Supprimer"), systemImage: "trash")
        }
    }
}

/// Feuilles communes (playlist, pochette, paroles, suppression), affichées depuis la racine.
final class SheetCenter: ObservableObject {
    static let shared = SheetCenter()
    @Published var addToPlaylist: [Song]?
    @Published var artworkFor: Song?
    @Published var lyricsFor: Song?
    @Published var deleting: Song?
}

// MARK: - Tuiles

/// Carré d'album, de playlist ou d'artiste (pochette + nom + détail).
struct CoverTile<Cover: View>: View {
    let title: String
    let subtitle: String
    var size: CGFloat = 160
    var round = false
    @ViewBuilder var cover: () -> Cover

    var body: some View {
        VStack(alignment: round ? .center : .leading, spacing: 5) {
            cover()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: round ? size / 2 : 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: size, alignment: round ? .center : .leading)
    }
}

/// Boutons « Lecture » et « Aléatoire ».
struct PlayShuffleButtons: View {
    @EnvironmentObject var player: AudioEngine
    let songs: [Song]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(songs, start: 0)
            } label: {
                Label(L("Lecture"), systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
            Button {
                if let pick = songs.indices.randomElement() {
                    player.play(songs, start: pick, shuffled: true)
                }
            } label: {
                Label(L("Aléatoire"), systemImage: "shuffle")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .disabled(songs.isEmpty)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(filled ? .white : .accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(filled ? Color.accentColor : Color(.tertiarySystemFill))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Bouton qui rebondit quand on appuie (lecteur).
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

struct CircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.accentColor)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color(.tertiarySystemFill)))
    }
}

struct SettingsLabel: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 29, height: 29)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))
        }
    }
}

/// Bandeau de message en haut de l'écran.
struct ToastBanner: View {
    let toast: Toast

    private var icon: (String, Color) {
        switch toast.kind {
        case .ok: return ("checkmark.circle.fill", .green)
        case .warn: return ("exclamationmark.triangle.fill", .orange)
        case .error: return ("xmark.octagon.fill", .red)
        case .info: return ("info.circle.fill", .accentColor)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.0)
                .foregroundColor(icon.1)
                .font(.system(size: 18))
            Text(toast.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - Feuilles

/// Choisir une playlist (ou en créer une) pour des morceaux.
struct PlaylistPicker: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let songs: [Song]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section(L("Nouvelle playlist")) {
                    HStack {
                        TextField(L("Nom de la playlist"), text: $newName)
                            .submitLabel(.done)
                            .onSubmit(create)
                        Button(L("Créer"), action: create)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                if !library.playlists.isEmpty {
                    Section(L("Mes playlists")) {
                        ForEach(library.playlists) { playlist in
                            Button {
                                let added = library.add(songs.map { $0.id }, to: playlist.id)
                                AppState.shared.show(added > 0 ? L("Ajouté à « {name} ».", ["name": playlist.name])
                                                     : L("Déjà dans « {name} ».", ["name": playlist.name]), .ok)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    PlaylistArtwork(playlist: playlist, size: 44, radius: 6)
                                    Text(playlist.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(playlist.songIDs.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Ajouter à une playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        let playlist = library.createPlaylist(newName, songs: songs.map { $0.id })
        AppState.shared.show(L("« {name} » créée.", ["name": playlist.name]), .ok)
        dismiss()
    }
}

/// Feuilles partagées, branchées une seule fois à la racine.
struct SharedSheets: ViewModifier {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var sheets: SheetCenter
    @State private var pendingSong: Song?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { sheets.addToPlaylist != nil }, set: { if !$0 { sheets.addToPlaylist = nil } })) {
                PlaylistPicker(songs: sheets.addToPlaylist ?? [])
                    .environmentObject(library)
            }
            .sheet(item: $sheets.lyricsFor) { song in
                LyricsEditorView(song: song)
                    .environmentObject(library)
                    .environmentObject(player)
            }
            .photoSheet(isPresented: Binding(get: { sheets.artworkFor != nil },
                                             set: { if !$0 { sheets.artworkFor = nil } })) { image in
                if let song = pendingSong {
                    library.setArtwork(image, for: song)
                    if player.current?.id == song.id { player.refreshArtwork() }
                    AppState.shared.show(L("Pochette mise à jour."), .ok)
                }
                pendingSong = nil
            }
            .onChange(of: sheets.artworkFor) { song in
                if let song = song { pendingSong = song }
            }
            .confirmationDialog(L("Supprimer ce morceau ?"),
                                isPresented: Binding(get: { sheets.deleting != nil }, set: { if !$0 { sheets.deleting = nil } }),
                                titleVisibility: .visible, presenting: sheets.deleting) { song in
                Button(song.isIpod ? L("Retirer de Music") : L("Supprimer le fichier"), role: .destructive) {
                    library.delete(song)
                    sheets.deleting = nil
                }
                let copies = library.duplicates(of: song).count
                if copies > 0 {
                    Button(L("Supprimer partout ({count} copies)", ["count": "\(copies + 1)"]), role: .destructive) {
                        library.delete(song, everywhere: true)
                        sheets.deleting = nil
                    }
                }
                Button(L("Annuler"), role: .cancel) { sheets.deleting = nil }
            } message: { song in
                Text(song.isIpod ? L("« {title} » reste dans l'app Musique de l'iPhone.", ["title": song.title])
                                 : L("« {title} » sera supprimé de l'iPhone.", ["title": song.title]))
            }
    }
}

extension View {
    func sharedSheets() -> some View {
        modifier(SharedSheets())
    }
}

// MARK: - Choix d'une photo

/// Choix d'une photo dans la photothèque (sélecteur d'iOS), qui renvoie l'image.
/// Présenté dans une feuille : il reste stable même quand l'écran se met à jour.
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            let done = onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                DispatchQueue.main.async { done(image) }
            }
        }
    }
}

extension View {
    /// Feuille de choix d'une photo ; `onPick` reçoit l'image (nil si annulé).
    func photoSheet(isPresented: Binding<Bool>, onPick: @escaping (UIImage) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            PhotoPicker { image in
                isPresented.wrappedValue = false
                if let image = image { onPick(image) }
            }
            .ignoresSafeArea()
        }
    }
}
