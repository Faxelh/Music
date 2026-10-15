import SwiftUI

/// Accueil : votre photo et votre nom, mix du jour, écoutés récemment,
/// ajoutés récemment, les plus écoutés, playlists, albums, artistes.
struct HomeView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var app: AppState
    @ObservedObject private var appearance = Appearance.shared
    @State private var importing = false
    @State private var searching = false
    @State private var appeared = false

    var body: some View {
        NavigationStack(path: $app.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if library.songs.isEmpty {
                        if library.loaded {
                            AddMusicCard(importing: $importing)
                                .padding(.horizontal, 16)
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    } else {
                        mixCard
                        sections
                    }
                }
                .padding(.bottom, 30)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
            .miniPlayerInset()
            .navigationBarHidden(true)
            .refreshable {
                await MainActor.run { library.scan(force: true) }
            }
            .libraryDestinations()
            .importer(isPresented: $importing)
            .searchSheet(isPresented: $searching)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Lang.locale)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                Text(appearance.greeting)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Button {
                searching = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(BounceButtonStyle())
            Button {
                app.tab = .settings
            } label: {
                ProfileAvatar(size: 46)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Grande carte animée « Mix du jour » (lecture aléatoire).
    private var mixCard: some View {
        let picks = Array(library.songs.filter { library.artworkURL($0) != nil }.shuffledStable(seed: dayKey).prefix(4))
        let colors = library.colors(for: picks.first)
        return Button {
            if let pick = library.songs.indices.randomElement() {
                player.play(library.songs, start: pick, shuffled: true)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { app.playerOpen = true }
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                AuroraView(colors: colors, animated: appearance.animations)
                    .background(Color.black)
                HStack(spacing: -24) {
                    ForEach(Array(picks.enumerated()), id: \.element.id) { offset, song in
                        SongArtwork(song: song, size: 86, radius: 12)
                            .rotationEffect(.degrees(Double(offset - 1) * 8))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                            .zIndex(Double(4 - offset))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("MIX DU JOUR"))
                        .font(.system(size: 12, weight: .heavy))
                        .opacity(0.85)
                    Text(L("Lecture aléatoire"))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text(L("{count} morceaux rien que pour vous", ["count": "\(library.songs.count)"]))
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0.85)
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(L("Écouter"))
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Capsule().fill(Color.white))
                    .padding(.top, 6)
                }
                .foregroundColor(.white)
                .padding(20)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 18, y: 10)
        }
        .buttonStyle(BounceButtonStyle())
        .padding(.horizontal, 16)
    }

    private var dayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    @ViewBuilder
    private var sections: some View {
        let played = Array(library.recentlyPlayed.prefix(15))
        if !played.isEmpty {
            shelf(L("Écoutés récemment"), route: nil) {
                ForEach(Array(played.enumerated()), id: \.element.id) { index, song in
                    songTile(song, list: played, index: index)
                }
            }
        }
        let added = Array(library.recentlyAdded.prefix(15))
        shelf(L("Ajoutés récemment"), route: .songs) {
            ForEach(Array(added.enumerated()), id: \.element.id) { index, song in
                songTile(song, list: added, index: index)
            }
        }
        let top = Array(library.mostPlayed.prefix(10))
        if top.count >= 3 {
            VStack(alignment: .leading, spacing: 8) {
                title(L("Vos préférés"), route: .mostPlayed)
                VStack(spacing: 0) {
                    ForEach(Array(top.prefix(5).enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.accentColor)
                                .frame(width: 26)
                            SongRow(song: song) { player.play(top, start: index) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        if !library.playlists.isEmpty {
            shelf(L("Mes playlists"), route: .playlists) {
                ForEach(library.playlists) { playlist in
                    NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                        CoverTile(title: playlist.name,
                                  subtitle: L("{count} titre(s)", ["count": "\(library.songs(in: playlist).count)"]),
                                  size: 150) {
                            PlaylistArtwork(playlist: playlist, size: 150, radius: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        let albums = library.albums
        if !albums.isEmpty {
            shelf(L("Albums"), route: .albums) {
                ForEach(albums.prefix(15)) { album in
                    NavigationLink(value: LibraryRoute.album(album.id)) {
                        CoverTile(title: album.name, subtitle: album.subtitle, size: 150) {
                            Artwork(url: album.artwork.flatMap { library.artworkURL($0) }, seed: album.id,
                                    icon: "square.stack.fill", size: 150, radius: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        let artists = library.artists
        if artists.count > 1 {
            shelf(L("Artistes"), route: .artists) {
                ForEach(artists.prefix(15)) { artist in
                    NavigationLink(value: LibraryRoute.artist(artist.id)) {
                        CoverTile(title: artist.name, subtitle: "", size: 110, round: true) {
                            Artwork(url: artist.artwork.flatMap { library.artworkURL($0) }, seed: artist.id,
                                    icon: "music.mic", size: 110, radius: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func songTile(_ song: Song, list: [Song], index: Int) -> some View {
        Button {
            player.play(list, start: index)
        } label: {
            CoverTile(title: song.title, subtitle: song.displayArtist, size: 150) {
                SongArtwork(song: song, size: 150, radius: 0)
            }
        }
        .buttonStyle(BounceButtonStyle())
        .contextMenu { SongMenu(song: song) }
    }

    private func title(_ text: String, route: LibraryRoute?) -> some View {
        Group {
            if let route = route {
                NavigationLink(value: route) {
                    HStack(spacing: 4) {
                        Text(text)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(text).font(.system(size: 22, weight: .bold))
            }
        }
        .padding(.horizontal, 16)
    }

    private func shelf<Items: View>(_ text: String, route: LibraryRoute?, @ViewBuilder items: () -> Items) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title(text, route: route)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    items()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}
