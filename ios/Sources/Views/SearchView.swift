import SwiftUI

/// Recherche dans la bibliothèque : morceaux, artistes, albums, playlists,
/// et parcours par genre.
struct SearchView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var app: AppState
    @AppStorage("searchQuery") private var query = ""
    @Environment(\.dismiss) private var dismiss
    /// Ouverte dans une feuille (depuis Découvrir ou l'Accueil) : bouton Fermer.
    var inSheet = true

    private var text: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var body: some View {
        NavigationStack(path: $app.searchPath) {
            List {
                if text.isEmpty {
                    genres
                } else {
                    results
                }
            }
            .listStyle(.plain)
            .miniPlayerInset()
            .navigationTitle(L("Rechercher"))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("Morceaux, artistes, albums"))
            .libraryDestinations()
            .toolbar {
                if inSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Fermer")) { dismiss() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var genres: some View {
        let names = Array(Set(library.songs.compactMap { $0.genre })).sorted()
        if names.isEmpty {
            EmptyState(icon: "magnifyingglass", title: L("Cherchez dans votre musique"),
                       subtitle: L("Titre, artiste, album… tout est cherché pendant que vous tapez."))
                .listRowSeparator(.hidden)
        } else {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(names, id: \.self) { genre in
                        Button {
                            let songs = library.songs.filter { $0.genre == genre }
                            if let pick = songs.indices.randomElement() {
                                player.play(songs, start: pick, shuffled: true)
                            }
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                LinearGradient(colors: artworkColors(genre), startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text(genre)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .padding(12)
                            }
                            .frame(height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                Text(L("Genres")).font(.system(size: 21, weight: .bold)).foregroundColor(.primary).textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let songs = library.songs.filter {
            $0.title.lowercased().contains(text) || $0.displayArtist.lowercased().contains(text)
                || ($0.album?.lowercased().contains(text) ?? false)
        }
        let artists = library.artists.filter { $0.name.lowercased().contains(text) }
        let albums = library.albums.filter { $0.name.lowercased().contains(text) || $0.subtitle.lowercased().contains(text) }
        let playlists = library.playlists.filter { $0.name.lowercased().contains(text) }
        if songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty {
            EmptyState(icon: "magnifyingglass", title: L("Aucun résultat"),
                       subtitle: L("Rien pour « {query} ».", ["query": query]))
                .listRowSeparator(.hidden)
        }
        if !artists.isEmpty {
            Section(header: header(L("Artistes"))) {
                ForEach(artists.prefix(6)) { artist in
                    NavigationLink(value: LibraryRoute.artist(artist.id)) {
                        HStack(spacing: 12) {
                            Artwork(url: artist.artwork.flatMap { library.artworkURL($0) }, seed: artist.id,
                                    icon: "music.mic", size: 46, radius: 23)
                            Text(artist.name).font(.system(size: 16, weight: .medium))
                        }
                    }
                }
            }
        }
        if !albums.isEmpty {
            Section(header: header(L("Albums"))) {
                ForEach(albums.prefix(6)) { album in
                    NavigationLink(value: LibraryRoute.album(album.id)) {
                        HStack(spacing: 12) {
                            Artwork(url: album.artwork.flatMap { library.artworkURL($0) }, seed: album.id,
                                    icon: "square.stack.fill", size: 46, radius: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name).font(.system(size: 16, weight: .medium))
                                Text(album.subtitle).font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        if !playlists.isEmpty {
            Section(header: header(L("Playlists"))) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                        HStack(spacing: 12) {
                            PlaylistArtwork(playlist: playlist, size: 46, radius: 6)
                            Text(playlist.name).font(.system(size: 16, weight: .medium))
                        }
                    }
                }
            }
        }
        if !songs.isEmpty {
            Section(header: header(L("Morceaux"))) {
                ForEach(Array(songs.prefix(60).enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song) {
                        player.play(Array(songs.prefix(60)), start: index)
                    }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(.primary).textCase(nil)
    }
}
