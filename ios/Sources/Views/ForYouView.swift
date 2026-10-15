import SwiftUI

/// Une sélection automatique de la bibliothèque (favoris, à redécouvrir…).
struct SmartMix: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    let songs: [Song]
}

/// Tout ce que « Découvrir » affiche, calculé une fois par affichage.
private struct DiscoverData {
    var mixes: [SmartMix] = []
    var decades: [SmartMix] = []
    var genres: [SmartMix] = []
    var radios: [Song] = []
    var artistOfDay: MusicGroup?
    var albumOfDay: MusicGroup?
    var totalPlays = 0
    var topArtist: String?
    var topSong: Song?

    init(_ library: LibraryStore, day: String) {
        let songs = library.songs
        guard !songs.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        let month: Double = 30 * 24 * 3600
        let counts = library.playCounts
        let last = library.lastPlayed

        var found: [SmartMix] = []
        func mix(_ id: String, _ title: String, _ subtitle: String, _ icon: String,
                 _ colors: [Color], _ list: [Song], min: Int = 3) {
            guard list.count >= min else { return }
            found.append(SmartMix(id: id, title: title, subtitle: subtitle, icon: icon, colors: colors, songs: list))
        }

        mix("favorites", L("Mes favoris"), L("Vos coups de cœur"), "heart.fill",
            [Color(red: 1, green: 0.2, blue: 0.4), Color(red: 0.75, green: 0.1, blue: 0.5)],
            library.favoriteSongs, min: 2)
        mix("loop", L("En boucle"), L("Ce que vous écoutez le plus"), "flame.fill",
            [Color(red: 1, green: 0.45, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.2)],
            Array(library.mostPlayed.prefix(50)))
        mix("new", L("Nouveautés"), L("Ajoutés ces 30 derniers jours"), "sparkles",
            [Color(red: 0.2, green: 0.6, blue: 1), Color(red: 0.4, green: 0.3, blue: 0.95)],
            songs.filter { now - $0.added < month }.sorted { $0.added > $1.added })
        mix("rediscover", L("À redécouvrir"), L("Pas écoutés depuis un mois"), "clock.arrow.circlepath",
            [Color(red: 0.15, green: 0.7, blue: 0.55), Color(red: 0.1, green: 0.4, blue: 0.6)],
            songs.filter { song in
                guard let played = last[song.id] else { return false }
                return now - played > month
            }.shuffledStable(seed: day))
        mix("never", L("Jamais écoutés"), L("Laissez-vous surprendre"), "questionmark.circle.fill",
            [Color(red: 0.55, green: 0.35, blue: 0.95), Color(red: 0.25, green: 0.2, blue: 0.6)],
            songs.filter { (counts[$0.id] ?? 0) == 0 }.shuffledStable(seed: day))
        mix("short", L("Express"), L("Des titres de moins de 3 minutes"), "hare.fill",
            [Color(red: 0.95, green: 0.75, blue: 0.1), Color(red: 0.95, green: 0.45, blue: 0.1)],
            songs.filter { $0.duration > 0 && $0.duration < 180 }, min: 5)
        mix("long", L("Grand format"), L("Des titres de plus de 6 minutes"), "tortoise.fill",
            [Color(red: 0.3, green: 0.35, blue: 0.5), Color(red: 0.15, green: 0.2, blue: 0.3)],
            songs.filter { $0.duration > 360 })
        mixes = found

        // Décennies (d'après l'année des morceaux).
        var byDecade: [Int: [Song]] = [:]
        for song in songs {
            if let year = song.year, year > 1900 { byDecade[year / 10 * 10, default: []].append(song) }
        }
        decades = byDecade.filter { $0.value.count >= 3 }.keys.sorted().map { decade in
            SmartMix(id: "decade\(decade)", title: L("Années {decade}", ["decade": decade < 2000 ? "\(decade % 100)" : "\(decade)"]),
                     subtitle: L("{count} titre(s)", ["count": "\(byDecade[decade]?.count ?? 0)"]),
                     icon: "calendar", colors: artworkColors("decade\(decade)"), songs: byDecade[decade] ?? [])
        }

        // Genres.
        var byGenre: [String: [Song]] = [:]
        var genreNames: [String: String] = [:]
        for song in songs {
            guard let genre = song.genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty else { continue }
            let key = genre.lowercased()
            byGenre[key, default: []].append(song)
            if genreNames[key] == nil { genreNames[key] = genre }
        }
        genres = byGenre.keys.sorted { (byGenre[$0]?.count ?? 0) > (byGenre[$1]?.count ?? 0) }.prefix(12).map { key in
            SmartMix(id: "genre" + key, title: genreNames[key] ?? key,
                     subtitle: L("{count} titre(s)", ["count": "\(byGenre[key]?.count ?? 0)"]),
                     icon: "guitars.fill", colors: artworkColors(key), songs: byGenre[key] ?? [])
        }

        // Radios : à partir de vos titres préférés (sinon au hasard).
        let favoriteSeeds: [Song] = Array(library.mostPlayed.prefix(4)) + Array(library.favoriteSongs.shuffledStable(seed: day).prefix(4))
        var seen = Set<String>()
        radios = (Array(favoriteSeeds) + songs.shuffledStable(seed: day + "radio").prefix(8))
            .filter { seen.insert($0.id).inserted }
            .prefix(8)
            .map { $0 }

        let artists = library.artists.filter { $0.songs.count >= 2 && $0.name != L("Artiste inconnu") }
        artistOfDay = artists.shuffledStable(seed: day + "artist").first
        let albums = library.albums.filter { $0.songs.count >= 2 }
        albumOfDay = albums.shuffledStable(seed: day + "album").first

        totalPlays = counts.values.reduce(0, +)
        var perArtist: [String: Int] = [:]
        for song in songs {
            if let count = counts[song.id], count > 0 { perArtist[song.displayArtist, default: 0] += count }
        }
        topArtist = perArtist.max { $0.value < $1.value }?.key
        topSong = library.mostPlayed.first
    }
}

/// Onglet « Découvrir » : recherche, mix automatiques, radios, artiste du jour,
/// statistiques d'écoute, décennies et genres.
struct ForYouView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var app: AppState
    @ObservedObject private var appearance = Appearance.shared
    @State private var path: [LibraryRoute] = []
    @State private var searching = false
    @State private var appeared = false

    private var dayKey: String { LibraryStore.dayKey(Date()) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let data = DiscoverData(library, day: dayKey)
                VStack(alignment: .leading, spacing: 26) {
                    header
                    searchField
                    if library.songs.isEmpty {
                        EmptyState(icon: "sparkles", title: L("Rien à découvrir pour l'instant"),
                                   subtitle: L("Ajoutez de la musique : vos mix et vos statistiques apparaîtront ici."))
                    } else {
                        if !data.mixes.isEmpty { mixGrid(data.mixes) }
                        if !data.radios.isEmpty { radios(data.radios) }
                        if let artist = data.artistOfDay { artistCard(artist) }
                        statsCard(data)
                        if let album = data.albumOfDay { albumCard(album) }
                        if !data.decades.isEmpty { chips(L("Par décennie"), data.decades) }
                        if !data.genres.isEmpty { genreGrid(data.genres) }
                    }
                }
                .padding(.bottom, 30)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            }
            .miniPlayerInset()
            .navigationBarHidden(true)
            .libraryDestinations()
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
            }
        }
        .searchSheet(isPresented: $searching)
    }

    // MARK: - En-tête et recherche

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Pour vous").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                Text(L("Découvrir"))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
            }
            Spacer()
            Button {
                shuffleAll()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(library.songs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var searchField: some View {
        Button {
            searching = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(L("Morceaux, artistes, albums"))
                Spacer()
            }
            .font(.system(size: 16))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Mix

    private func mixGrid(_ mixes: [SmartMix]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Vos mix"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(mixes) { mix in
                    Button {
                        play(mix.songs, shuffled: mix.id != "loop" && mix.id != "new")
                    } label: {
                        mixTile(mix)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .contextMenu { mixMenu(mix) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func mixTile(_ mix: SmartMix) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: mix.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: mix.icon)
                .font(.system(size: 54, weight: .bold))
                .foregroundColor(.white.opacity(0.18))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 10, y: -4)
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: mix.icon)
                    .font(.system(size: 17, weight: .bold))
                Spacer(minLength: 0)
                Text(mix.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Text(L("{count} titre(s)", ["count": "\(mix.songs.count)"]))
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.85)
            }
            .foregroundColor(.white)
            .padding(12)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: (mix.colors.first ?? .black).opacity(0.25), radius: 8, y: 4)
    }

    @ViewBuilder
    private func mixMenu(_ mix: SmartMix) -> some View {
        Button {
            play(mix.songs, shuffled: false)
        } label: {
            Label(L("Lecture"), systemImage: "play.fill")
        }
        Button {
            play(mix.songs, shuffled: true)
        } label: {
            Label(L("Aléatoire"), systemImage: "shuffle")
        }
        Button {
            player.addToQueue(mix.songs)
            AppState.shared.show(L("Ajouté à la file de lecture."), .ok)
        } label: {
            Label(L("Ajouter à la file de lecture"), systemImage: "text.append")
        }
        Button {
            let playlist = library.createPlaylist(mix.title, songs: mix.songs.map { $0.id })
            AppState.shared.show(L("Playlist « {name} » créée.", ["name": playlist.name]), .ok)
        } label: {
            Label(L("Enregistrer comme playlist"), systemImage: "text.badge.plus")
        }
    }

    // MARK: - Radios

    private func radios(_ seeds: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Radios"), detail: L("Une sélection sans fin autour d'un titre"))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(seeds) { song in
                        Button {
                            startRadio(song)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack(alignment: .bottomLeading) {
                                    SongArtwork(song: song, size: 140, radius: 0)
                                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                    HStack(spacing: 5) {
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                        Text(L("RADIO"))
                                    }
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(10)
                                }
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text(song.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(song.displayArtist)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Artiste et album du jour

    private func artistCard(_ artist: MusicGroup) -> some View {
        let colors = library.colors(for: artist.artwork)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Artiste du jour"))
            HStack(spacing: 14) {
                Artwork(url: artist.artwork.flatMap { library.artworkURL($0) }, seed: artist.id,
                        icon: "music.mic", size: 84, radius: 42)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                    Text(artist.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.8)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Button {
                            play(artist.songs, shuffled: true)
                        } label: {
                            Label(L("Écouter"), systemImage: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(BounceButtonStyle())
                        NavigationLink(value: LibraryRoute.artist(artist.id)) {
                            Text(L("Voir"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Capsule().fill(Color.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .foregroundColor(.white)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                ZStack {
                    LinearGradient(colors: colors.count > 1 ? colors : [.purple, .indigo],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Color.black.opacity(0.25)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func albumCard(_ album: MusicGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Album à réécouter"))
            HStack(spacing: 14) {
                NavigationLink(value: LibraryRoute.album(album.id)) {
                    Artwork(url: album.artwork.flatMap { library.artworkURL($0) }, seed: album.id,
                            icon: "square.stack.fill", size: 96, radius: 12)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(2)
                    Text(album.subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(L("{count} titre(s)", ["count": "\(album.songs.count)"]) + " · "
                         + Fmt.clock(album.songs.reduce(0) { $0 + $1.duration }))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Button {
                        play(album.songs, shuffled: false)
                    } label: {
                        Label(L("Lecture"), systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Statistiques

    private func statsCard(_ data: DiscoverData) -> some View {
        let week = library.listeningMinutes(days: 7)
        let weekMinutes = week.reduce(0) { $0 + $1.minutes }
        let peak = max(1, week.map { $0.minutes }.max() ?? 1)
        let streak = library.listeningStreak
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Votre écoute"))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    stat(formatMinutes(weekMinutes), L("cette semaine"))
                    Spacer()
                    stat("\(data.totalPlays)", L("écoutes"))
                    Spacer()
                    stat("\(streak)", streak > 1 ? L("jours de suite") : L("jour de suite"))
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(week.enumerated()), id: \.offset) { offset, entry in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(offset == week.count - 1 ? Color.accentColor : Color.accentColor.opacity(0.45))
                                .frame(height: max(4, CGFloat(entry.minutes / peak) * 70))
                            Text(entry.day.formatted(.dateTime.weekday(.narrow).locale(Lang.locale)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 92, alignment: .bottom)
                if data.topArtist != nil || data.topSong != nil {
                    Divider()
                    if let artist = data.topArtist {
                        HStack {
                            Label(L("Artiste n°1"), systemImage: "music.mic")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(artist).fontWeight(.semibold).lineLimit(1)
                        }
                        .font(.system(size: 14))
                    }
                    if let song = data.topSong {
                        Button {
                            if let index = library.mostPlayed.firstIndex(where: { $0.id == song.id }) {
                                play(library.mostPlayed, start: index, shuffled: false)
                            }
                        } label: {
                            HStack {
                                Label(L("Titre n°1"), systemImage: "trophy.fill")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(song.title).fontWeight(.semibold).lineLimit(1).foregroundColor(.primary)
                                Text("×\(library.playCounts[song.id] ?? 0)")
                                    .foregroundColor(.accentColor)
                                    .fontWeight(.bold)
                            }
                            .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                } else if weekMinutes < 1 {
                    Text(L("Écoutez un peu de musique : vos statistiques se rempliront ici."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 16)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.accentColor)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return "\(total / 60) h \(String(format: "%02d", total % 60))"
    }

    // MARK: - Décennies et genres

    private func chips(_ title: String, _ list: [SmartMix]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list) { mix in
                        Button {
                            play(mix.songs, shuffled: true)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mix.title)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                Text(mix.subtitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .opacity(0.85)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: mix.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            )
                        }
                        .buttonStyle(BounceButtonStyle())
                        .contextMenu { mixMenu(mix) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func genreGrid(_ list: [SmartMix]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Genres"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(list) { mix in
                    Button {
                        play(mix.songs, shuffled: true)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: mix.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mix.title)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .lineLimit(2)
                                Text(mix.subtitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .opacity(0.85)
                            }
                            .foregroundColor(.white)
                            .padding(12)
                        }
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .contextMenu { mixMenu(mix) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Outils

    private func sectionTitle(_ text: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 22, weight: .bold))
            if let detail = detail {
                Text(detail).font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func play(_ songs: [Song], start: Int = 0, shuffled: Bool) {
        guard !songs.isEmpty else { return }
        let first = shuffled ? (songs.indices.randomElement() ?? 0) : start
        player.play(songs, start: first, shuffled: shuffled)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func shuffleAll() {
        play(library.songs, shuffled: true)
    }

    private func startRadio(_ song: Song) {
        player.play(library.radio(for: song))
        AppState.shared.show(L("Radio : {title}", ["title": song.title]), .ok)
    }
}

/// La recherche (morceaux, artistes, albums, playlists) dans une feuille.
struct SearchSheet: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: { AppState.shared.searchPath = [] }) {
            SearchView()
                .sharedSheets()
                .environmentObject(LibraryStore.shared)
                .environmentObject(AudioEngine.shared)
                .environmentObject(AppState.shared)
                .environmentObject(SheetCenter.shared)
                .tint(Appearance.shared.accent)
                .accentColor(Appearance.shared.accent)
        }
    }
}

extension View {
    func searchSheet(isPresented: Binding<Bool>) -> some View {
        modifier(SearchSheet(isPresented: isPresented))
    }
}
