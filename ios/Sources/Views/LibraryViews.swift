import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Onglet Bibliothèque.
struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var app: AppState
    @State private var importing = false
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack(path: $app.libraryPath) {
            List {
                Section {
                    row(.playlists, L("Playlists"), "music.note.list", library.playlists.count)
                    row(.artists, L("Artistes"), "music.mic", nil)
                    row(.albums, L("Albums"), "square.stack.fill", nil)
                    row(.songs, L("Morceaux"), "music.note", library.songs.count)
                    row(.favorites, L("Favoris"), "heart.fill", library.favorites.count)
                    row(.mostPlayed, L("Les plus écoutés"), "chart.bar.fill", nil)
                    row(.folders, L("Dossiers"), "folder.fill", nil)
                }
                Section {
                    let recent = Array(library.recentlyAdded.prefix(12))
                    if recent.isEmpty {
                        if library.loaded {
                            AddMusicCard(importing: $importing)
                                .listRowSeparator(.hidden)
                        } else {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 30)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, song in
                                Button {
                                    player.play(recent, start: index)
                                } label: {
                                    GeometryReader { geometry in
                                        CoverTile(title: song.title, subtitle: song.displayArtist, size: geometry.size.width) {
                                            SongArtwork(song: song, size: geometry.size.width, radius: 0)
                                        }
                                    }
                                    .aspectRatio(0.78, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { SongMenu(song: song) }
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(L("Ajoutés récemment"))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .miniPlayerInset()
            .navigationTitle(L("Bibliothèque"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            importing = true
                        } label: {
                            Label(L("Importer depuis Fichiers"), systemImage: "square.and.arrow.down")
                        }
                        Button {
                            newName = ""
                            creating = true
                        } label: {
                            Label(L("Nouvelle playlist"), systemImage: "music.note.list")
                        }
                        Button {
                            library.scan(force: true) { added in
                                AppState.shared.show(added > 0 ? L("{count} nouveau(x) morceau(x).", ["count": "\(added)"])
                                                     : L("Bibliothèque à jour."), .ok)
                            }
                        } label: {
                            Label(L("Actualiser la bibliothèque"), systemImage: "arrow.clockwise")
                        }
                        Button {
                            library.openInFiles()
                        } label: {
                            Label(L("Ouvrir dans Fichiers"), systemImage: "folder")
                        }
                    } label: {
                        CircleIcon(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await MainActor.run { library.scan(force: true) }
            }
            .libraryDestinations()
            .importer(isPresented: $importing)
            .alert(L("Nouvelle playlist"), isPresented: $creating) {
                TextField(L("Nom de la playlist"), text: $newName)
                Button(L("Annuler"), role: .cancel) {}
                Button(L("Créer")) {
                    let playlist = library.createPlaylist(newName)
                    app.libraryPath = [.playlist(playlist.id)]
                }
            }
        }
    }

    private func row(_ route: LibraryRoute, _ title: String, _ icon: String, _ count: Int?) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 19))
                Spacer()
                if let count = count, count > 0 {
                    Text("\(count)").foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Bibliothèque vide : comment ajouter sa musique.
struct AddMusicCard: View {
    @Binding var importing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Ajoutez votre musique"), systemImage: "music.note.house.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.accentColor)
            tip("desktopcomputer", L("Avec 3uTools (ou iTunes / Finder) : Apps › Music › Documents, glissez vos fichiers MP3, M4A, FLAC, WAV… Ils apparaissent ici tout seuls."))
            tip("folder", L("Avec l'app Fichiers : copiez-les dans « Sur mon iPhone › Music », ou touchez « Importer »."))
            tip("square.and.arrow.up", L("Depuis une autre app : Partager › Ouvrir avec Music."))
            Button {
                importing = true
            } label: {
                Label(L("Importer"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.accentColor.opacity(0.12)))
        .padding(.vertical, 6)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Navigation commune

struct LibraryDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: LibraryRoute.self) { route in
            destination(route).miniPlayerInset()
        }
    }

    @ViewBuilder
    private func destination(_ route: LibraryRoute) -> some View {
            switch route {
            case .songs:
                SongListView(kind: .all)
            case .favorites:
                SongListView(kind: .favorites)
            case .mostPlayed:
                SongListView(kind: .mostPlayed)
            case .folder(let name):
                SongListView(kind: .folder(name))
            case .artists:
                ArtistsView()
            case .albums:
                AlbumsView()
            case .playlists:
                PlaylistsView()
            case .folders:
                FoldersView()
            case .artist(let id):
                ArtistView(id: id)
            case .album(let id):
                AlbumView(id: id)
            case .playlist(let id):
                PlaylistView(id: id)
            }
    }
}

struct ImporterModifier: ViewModifier {
    @EnvironmentObject var library: LibraryStore
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.audio, .data],
                             allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                library.importFiles(urls)
            }
        }
    }
}

extension View {
    func libraryDestinations() -> some View {
        modifier(LibraryDestinations())
    }

    func importer(isPresented: Binding<Bool>) -> some View {
        modifier(ImporterModifier(isPresented: isPresented))
    }
}

// MARK: - Listes de morceaux

struct SongListView: View {
    enum Kind: Hashable {
        case all, favorites, mostPlayed
        case folder(String)
    }

    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @AppStorage("songsSort") private var sort = "title"
    let kind: Kind
    @State private var query = ""

    private var title: String {
        switch kind {
        case .all: return L("Morceaux")
        case .favorites: return L("Favoris")
        case .mostPlayed: return L("Les plus écoutés")
        case .folder(let name): return name
        }
    }

    private var songs: [Song] {
        var list: [Song]
        switch kind {
        case .all: list = library.songs
        case .favorites: list = library.favoriteSongs
        case .mostPlayed: list = Array(library.mostPlayed.prefix(100))
        case .folder(let name): list = library.songs.filter { $0.folder == name }
        }
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !text.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(text) || $0.displayArtist.lowercased().contains(text)
                    || ($0.album?.lowercased().contains(text) ?? false)
            }
        }
        if kind == .mostPlayed { return list }
        switch sort {
        case "artist":
            return list.sorted {
                if $0.displayArtist != $1.displayArtist {
                    return $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case "recent":
            return list.sorted { $0.added > $1.added }
        case "duration":
            return list.sorted { $0.duration > $1.duration }
        default:
            return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        let list = songs
        List {
            if list.isEmpty {
                EmptyState(icon: kind == .favorites ? "heart" : "music.note",
                           title: query.isEmpty ? L("Rien ici pour l'instant") : L("Aucun résultat"),
                           subtitle: kind == .favorites ? L("Touchez ♡ dans le lecteur pour ajouter un favori.") : "")
                    .listRowSeparator(.hidden)
            } else {
                PlayShuffleButtons(songs: list)
                    .listRowSeparator(.hidden)
                ForEach(Array(list.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, number: kind == .mostPlayed ? index + 1 : nil) {
                        player.play(list, start: index)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            player.playNext(song)
                        } label: {
                            Label(L("Lire ensuite"), systemImage: "text.insert")
                        }
                        .tint(.accentColor)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            library.toggleFavorite(song)
                        } label: {
                            Label(L("Favori"), systemImage: library.isFavorite(song) ? "heart.slash" : "heart")
                        }
                        .tint(.pink)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .searchable(text: $query, prompt: L("Rechercher"))
        .toolbar {
            if kind != .mostPlayed {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker(L("Trier par"), selection: $sort) {
                            Text(L("Titre")).tag("title")
                            Text(L("Artiste")).tag("artist")
                            Text(L("Ajout récent")).tag("recent")
                            Text(L("Durée")).tag("duration")
                        }
                    } label: {
                        CircleIcon(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }
}

// MARK: - Artistes, albums, dossiers

struct ArtistsView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let artists = library.artists
        List {
            if artists.isEmpty {
                EmptyState(icon: "music.mic", title: L("Aucun artiste"))
                    .listRowSeparator(.hidden)
            }
            ForEach(artists) { artist in
                NavigationLink(value: LibraryRoute.artist(artist.id)) {
                    HStack(spacing: 14) {
                        Artwork(url: artist.artwork.flatMap { library.artworkURL($0) }, seed: artist.id,
                                icon: "music.mic", size: 56, radius: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist.name).font(.system(size: 17, weight: .medium))
                            Text(artist.subtitle).font(.system(size: 13)).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(L("Artistes"))
    }
}

struct AlbumsView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let albums = library.albums
        ScrollView {
            if albums.isEmpty {
                EmptyState(icon: "square.stack", title: L("Aucun album"),
                           subtitle: L("Les albums viennent des informations des fichiers (balise album)."))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                      alignment: .leading, spacing: 22) {
                ForEach(albums) { album in
                    NavigationLink(value: LibraryRoute.album(album.id)) {
                        GeometryReader { geometry in
                            CoverTile(title: album.name, subtitle: album.subtitle, size: geometry.size.width) {
                                Artwork(url: album.artwork.flatMap { library.artworkURL($0) }, seed: album.id,
                                        icon: "square.stack.fill", size: geometry.size.width, radius: 0)
                            }
                        }
                        .aspectRatio(0.8, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle(L("Albums"))
    }
}

struct FoldersView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        List {
            ForEach(library.folders, id: \.self) { folder in
                NavigationLink(value: LibraryRoute.folder(folder)) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder).font(.system(size: 16))
                            Text(L("{count} titre(s)", ["count": "\(library.songs.filter { $0.folder == folder }.count)"]))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Dossiers"))
    }
}

/// En-tête d'album, d'artiste ou de playlist.
struct CollectionHeader<Cover: View>: View {
    let title: String
    let subtitle: String
    let detail: String
    let songs: [Song]
    var round = false
    @ViewBuilder var cover: () -> Cover

    var body: some View {
        VStack(spacing: 10) {
            cover()
                .frame(width: 230, height: 230)
                .clipShape(RoundedRectangle(cornerRadius: round ? 115 : 16, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            Text(title)
                .font(.system(size: 23, weight: .bold))
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
            }
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            PlayShuffleButtons(songs: songs)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

func totalText(_ songs: [Song]) -> String {
    let total = songs.reduce(0) { $0 + $1.duration }
    return L("{count} titre(s) · {time}", ["count": "\(songs.count)", "time": Fmt.duration(total)])
}

struct AlbumView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    let id: String

    var body: some View {
        let album = library.albums.first { $0.id == id }
        let songs = album?.songs ?? []
        List {
            CollectionHeader(title: album?.name ?? "", subtitle: album?.subtitle ?? "", detail: totalText(songs), songs: songs) {
                Artwork(url: album?.artwork.flatMap { library.artworkURL($0) }, seed: id, icon: "square.stack.fill",
                        size: 230, radius: 0)
            }
            .listRowSeparator(.hidden)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, number: song.trackNumber ?? index + 1, showArtwork: false) {
                    player.play(songs, start: index)
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ArtistView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    let id: String

    var body: some View {
        let artist = library.artists.first { $0.id == id }
        let songs = artist?.songs ?? []
        let albums = library.albums(of: songs)
        List {
            CollectionHeader(title: artist?.name ?? "", subtitle: "", detail: totalText(songs), songs: songs, round: true) {
                Artwork(url: artist?.artwork.flatMap { library.artworkURL($0) }, seed: id, icon: "music.mic",
                        size: 230, radius: 0)
            }
            .listRowSeparator(.hidden)
            if !albums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(albums) { album in
                                NavigationLink(value: LibraryRoute.album(album.id)) {
                                    CoverTile(title: album.name, subtitle: "", size: 140) {
                                        Artwork(url: album.artwork.flatMap { library.artworkURL($0) }, seed: album.id,
                                                icon: "square.stack.fill", size: 140, radius: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text(L("Albums")).font(.system(size: 20, weight: .bold)).foregroundColor(.primary).textCase(nil)
                }
            }
            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song) {
                        player.play(songs, start: index)
                    }
                }
            } header: {
                Text(L("Morceaux")).font(.system(size: 20, weight: .bold)).foregroundColor(.primary).textCase(nil)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Playlists

struct PlaylistsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var app: AppState
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            Button {
                newName = ""
                creating = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 60, height: 60)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                    Text(L("Nouvelle playlist…"))
                        .foregroundColor(.accentColor)
                }
            }
            ForEach(library.playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                    HStack(spacing: 14) {
                        PlaylistArtwork(playlist: playlist, size: 60, radius: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name).font(.system(size: 17, weight: .medium))
                            Text(L("{count} titre(s)", ["count": "\(library.songs(in: playlist).count)"]))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        library.deletePlaylist(playlist.id)
                    } label: {
                        Label(L("Supprimer"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(L("Playlists"))
        .alert(L("Nouvelle playlist"), isPresented: $creating) {
            TextField(L("Nom de la playlist"), text: $newName)
            Button(L("Annuler"), role: .cancel) {}
            Button(L("Créer")) {
                let playlist = library.createPlaylist(newName)
                app.libraryPath.append(.playlist(playlist.id))
            }
        }
    }
}

struct PlaylistView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var renaming = false
    @State private var newName = ""
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var choosingPhoto = false

    var body: some View {
        let playlist = library.playlist(id)
        let songs = playlist.map { library.songs(in: $0) } ?? []
        List {
            if let playlist = playlist {
                CollectionHeader(title: playlist.name, subtitle: "", detail: totalText(songs), songs: songs) {
                    PlaylistArtwork(playlist: playlist, size: 230, radius: 0)
                        .onTapGesture { choosingPhoto = true }
                }
                .listRowSeparator(.hidden)
            }
            Button {
                adding = true
            } label: {
                Label(L("Ajouter des morceaux"), systemImage: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song) {
                    player.play(songs, start: index)
                }
            }
            .onDelete { library.remove(at: $0, from: id) }
            .onMove { library.move(from: $0, to: $1, in: id) }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        newName = playlist?.name ?? ""
                        renaming = true
                    } label: {
                        Label(L("Renommer"), systemImage: "pencil")
                    }
                    Button {
                        choosingPhoto = true
                    } label: {
                        Label(L("Choisir une photo de couverture"), systemImage: "photo")
                    }
                    Button {
                        adding = true
                    } label: {
                        Label(L("Ajouter des morceaux"), systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(L("Supprimer la playlist"), systemImage: "trash")
                    }
                } label: {
                    CircleIcon(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .photoSheet(isPresented: $choosingPhoto) { image in
            library.setCover(image, for: id)
        }
        .alert(L("Renommer"), isPresented: $renaming) {
            TextField(L("Nom de la playlist"), text: $newName)
            Button(L("Annuler"), role: .cancel) {}
            Button(L("OK")) { library.renamePlaylist(id, to: newName) }
        }
        .confirmationDialog(L("Supprimer la playlist ?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Supprimer"), role: .destructive) {
                library.deletePlaylist(id)
                dismiss()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Les morceaux restent dans votre bibliothèque."))
        }
        .sheet(isPresented: $adding) {
            SongPicker(playlistID: id)
                .environmentObject(library)
        }
    }
}

/// Choisir plusieurs morceaux à ajouter à une playlist.
struct SongPicker: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlistID: String
    @State private var selected: Set<String> = []
    @State private var query = ""

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = library.songs.filter {
            text.isEmpty || $0.title.lowercased().contains(text) || $0.displayArtist.lowercased().contains(text)
        }
        NavigationStack {
            List(list) { song in
                Button {
                    if selected.contains(song.id) { selected.remove(song.id) } else { selected.insert(song.id) }
                } label: {
                    HStack(spacing: 12) {
                        SongArtwork(song: song, size: 44, radius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).foregroundColor(.primary).lineLimit(1)
                            Text(song.displayArtist).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: selected.contains(song.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(selected.contains(song.id) ? .accentColor : .secondary)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: L("Rechercher"))
            .navigationTitle(L("Ajouter des morceaux"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Ajouter ({count})", ["count": "\(selected.count)"])) {
                        let ordered = library.songs.filter { selected.contains($0.id) }.map { $0.id }
                        library.add(ordered, to: playlistID)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
