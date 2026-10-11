import SwiftUI
import UIKit

/// Paroles en direct dans le lecteur : la ligne chantée s'illumine et défile toute seule.
struct LiveLyricsView: View {
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var sheets: SheetCenter
    @ObservedObject private var store = LyricsStore.shared
    @ObservedObject private var appearance = Appearance.shared
    let song: Song

    var body: some View {
        Group {
            if store.songID != song.id || store.loading {
                ProgressView()
                    .tint(.white)
                    .frame(maxHeight: .infinity)
            } else if let lyrics = store.lyrics, !lyrics.lines.isEmpty {
                if lyrics.isSynced {
                    synced(lyrics)
                } else {
                    plain(lyrics)
                }
            } else {
                missing
            }
        }
        .onAppear { store.load(song, autoSearch: appearance.lyricsAuto) }
        .onChange(of: song.id) { _ in store.load(song, autoSearch: appearance.lyricsAuto) }
        .onChange(of: store.songID) { id in
            if id != song.id { store.load(song, autoSearch: false) }
        }
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let time = liveTime(player, at: context.date)
            let current = lyrics.currentIndex(at: time)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: 120)
                        ForEach(lyrics.lines) { line in
                            lineView(line, current: current)
                                .id(line.id)
                                .onTapGesture {
                                    if let start = line.time {
                                        player.seek(to: start)
                                        if !player.isPlaying { player.resume() }
                                    }
                                }
                        }
                        Color.clear.frame(height: 220)
                    }
                    .padding(.horizontal, 28)
                }
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                           .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .onChange(of: current) { value in
                    guard let value = value else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        proxy.scrollTo(value, anchor: UnitPoint(x: 0.5, y: 0.38))
                    }
                }
                .onAppear {
                    if let value = current { proxy.scrollTo(value, anchor: UnitPoint(x: 0.5, y: 0.38)) }
                }
            }
        }
    }

    private func lineView(_ line: LyricLine, current: Int?) -> some View {
        let isCurrent = line.id == current
        let distance = current.map { abs(line.id - $0) } ?? 3
        let blur = appearance.animations && !isCurrent ? min(2.5, Double(distance) * 0.7) : 0
        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: appearance.lyricsSize, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(isCurrent ? 1 : (line.id < (current ?? -1) ? 0.3 : 0.42)))
            .shadow(color: .white.opacity(isCurrent ? 0.45 : 0), radius: 10)
            .blur(radius: blur)
            .scaleEffect(isCurrent ? 1.04 : 1, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isCurrent)
    }

    private func plain(_ lyrics: Lyrics) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Paroles non synchronisées · touchez « Synchroniser » pour les caler sur la musique."))
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.6)
                Text(lyrics.plainText)
                    .font(.system(size: appearance.lyricsSize * 0.8, weight: .bold, design: .rounded))
                    .lineSpacing(8)
                Button(L("Synchroniser")) { sheets.lyricsFor = song }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
        }
    }

    private var missing: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "quote.bubble")
                .font(.system(size: 44))
                .opacity(0.7)
            Text(store.searching ? L("Recherche des paroles…") : L("Pas encore de paroles pour ce titre"))
                .font(.system(size: 18, weight: .bold))
                .multilineTextAlignment(.center)
            if store.searching {
                ProgressView().tint(.white)
            } else {
                Button {
                    sheets.lyricsFor = song
                } label: {
                    Label(L("Trouver ou générer les paroles"), systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 50)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

/// Feuille « Paroles » : chercher en ligne, générer, écrire, synchroniser.
struct LyricsEditorView: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var store = LyricsStore.shared
    @Environment(\.dismiss) private var dismiss
    let song: Song

    @State private var query = ""
    @State private var text = ""
    @State private var language = Lang.speechDefault
    @State private var message: String?
    @State private var syncing = false

    private let languages: [(String, String)] = [
        ("fr-FR", "Français"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("es-ES", "Español"),
        ("pt-BR", "Português"), ("it-IT", "Italiano"), ("de-DE", "Deutsch"), ("ru-RU", "Русский"), ("ar-SA", "العربية"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SongArtwork(song: song, size: 56, radius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title).font(.system(size: 16, weight: .semibold))
                            Text(song.displayArtist).font(.system(size: 14)).foregroundColor(.secondary)
                            Text(sourceText).font(.system(size: 12)).foregroundColor(.accentColor)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField(L("Titre et artiste"), text: $query)
                            .submitLabel(.search)
                            .onSubmit(search)
                        Button(action: search) {
                            if store.searching {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                    ForEach(store.results.prefix(12)) { result in
                        Button {
                            store.use(result, for: song)
                            load()
                            message = L("Paroles enregistrées.")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.track).foregroundColor(.primary).lineLimit(1)
                                    Text([result.artist, Fmt.duration(result.duration)].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(result.hasSynced ? L("Synchronisées") : L("Texte"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(result.hasSynced ? .green : .secondary)
                            }
                        }
                    }
                } header: {
                    Text(L("Chercher en ligne"))
                } footer: {
                    Text(L("Paroles synchronisées de LRCLIB, base libre et gratuite."))
                }

                Section {
                    Picker(L("Langue chantée"), selection: $language) {
                        ForEach(languages, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                    if store.generating {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: store.generationProgress)
                            HStack {
                                Text(L("Écoute du morceau… {percent} %", ["percent": "\(Int(store.generationProgress * 100))"]))
                                    .font(.system(size: 13))
                                Spacer()
                                Button(L("Annuler")) { store.cancelGeneration() }
                            }
                        }
                    } else {
                        Button {
                            message = nil
                            store.generate(song, language: language) { error in
                                if let error = error {
                                    message = error
                                } else {
                                    load()
                                    message = L("Paroles générées et synchronisées.")
                                }
                            }
                        } label: {
                            Label(L("Générer les paroles"), systemImage: "waveform.and.mic")
                        }
                    }
                } header: {
                    Text(L("Générer automatiquement"))
                } footer: {
                    Text(L("Music écoute le morceau et écrit les paroles avec leur minutage, directement sur l'iPhone. Expérimental : le résultat est meilleur quand la voix est claire. Vous pourrez corriger le texte ensuite."))
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 200)
                    Button {
                        let lines = LyricsParser.parse(text)
                        guard !lines.isEmpty else {
                            message = L("Écrivez ou collez d'abord des paroles.")
                            return
                        }
                        store.save(Lyrics(lines: lines, source: .manual), for: song)
                        message = L("Paroles enregistrées.")
                    } label: {
                        Label(L("Enregistrer"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        let lines = LyricsParser.parse(text)
                        guard !lines.isEmpty else {
                            message = L("Écrivez ou collez d'abord des paroles.")
                            return
                        }
                        syncing = true
                    } label: {
                        Label(L("Synchroniser ligne par ligne"), systemImage: "hand.tap")
                    }
                    if store.lyrics?.source == .saved || store.lyrics?.source == .manual || store.lyrics?.source == .online
                        || store.lyrics?.source == .generated {
                        Button(role: .destructive) {
                            store.delete(for: song)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { load() }
                        } label: {
                            Label(L("Supprimer les paroles enregistrées"), systemImage: "trash")
                        }
                    }
                } header: {
                    Text(L("Écrire ou corriger"))
                } footer: {
                    Text(L("Format libre ou LRC : [01:23.45] une ligne. Pour synchroniser, lancez le morceau et touchez « Ligne suivante » au début de chaque ligne."))
                }
            }
            .navigationTitle(L("Paroles"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.regularMaterial))
                        .padding(.bottom, 8)
                        .onTapGesture { self.message = nil }
                }
            }
            .onAppear {
                query = [LyricsStore.cleanTitle(song.title), song.artist ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
                store.load(song, autoSearch: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { load() }
            }
            .onChange(of: store.lyrics) { _ in load() }
            .fullScreenCover(isPresented: $syncing) {
                LyricsSyncView(song: song, lines: LyricsParser.parse(text).map { $0.text }) { synced in
                    store.save(synced, for: song)
                    load()
                    message = L("Paroles synchronisées.")
                }
                .environmentObject(player)
            }
        }
    }

    private var sourceText: String {
        guard store.songID == song.id, let lyrics = store.lyrics else { return L("Aucune parole") }
        switch lyrics.source {
        case .saved: return lyrics.isSynced ? L("Paroles synchronisées enregistrées") : L("Paroles enregistrées")
        case .file: return L("Fichier .lrc à côté du morceau")
        case .embedded: return L("Paroles intégrées au fichier")
        case .online: return L("Trouvées en ligne")
        case .generated: return L("Générées par Music")
        case .manual: return L("Écrites à la main")
        }
    }

    private func load() {
        guard store.songID == song.id, let lyrics = store.lyrics else { return }
        text = lyrics.isSynced ? lyrics.lrc : lyrics.plainText
    }

    private func search() {
        store.search(song, query: query)
    }
}

/// Synchronisation manuelle : la musique joue, on touche au début de chaque ligne.
struct LyricsSyncView: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var clock = AudioEngine.shared.clock
    @Environment(\.dismiss) private var dismiss
    let song: Song
    let lines: [String]
    let onSave: (Lyrics) -> Void

    @State private var times: [Double?] = []
    @State private var cursor = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(times.indices.contains(offset) && times[offset] != nil
                                     ? LyricsParser.stamp(times[offset] ?? 0) : "--:--.--")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(line.isEmpty ? "♪" : line)
                                    .font(.system(size: offset == cursor ? 20 : 16, weight: offset == cursor ? .bold : .regular))
                                    .foregroundColor(offset == cursor ? .accentColor : .primary)
                            }
                            .id(offset)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: cursor) { value in
                        withAnimation { proxy.scrollTo(value, anchor: .center) }
                    }
                }
                VStack(spacing: 12) {
                    Text(Fmt.clock(clock.currentTime) + " / " + Fmt.clock(clock.duration))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Button {
                            if cursor > 0 {
                                cursor -= 1
                                times[cursor] = nil
                            }
                        } label: {
                            Label(L("Retour"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        Button {
                            player.toggle()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        .frame(width: 90)
                    }
                    Button {
                        guard cursor < lines.count else { return }
                        times[cursor] = max(0, player.currentTime - 0.2)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        cursor += 1
                    } label: {
                        Text(cursor < lines.count ? L("Ligne suivante") : L("Terminé"))
                            .font(.system(size: 20, weight: .bold))
                            .frame(height: 70)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(cursor >= lines.count)
                }
                .padding(16)
                .background(.bar)
            }
            .navigationTitle(L("Synchroniser"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Enregistrer")) {
                        var last = 0.0
                        let synced = lines.enumerated().map { offset, text -> LyricLine in
                            let time = (times.indices.contains(offset) ? times[offset] : nil) ?? last
                            last = time
                            return LyricLine(id: offset, time: time, text: text)
                        }
                        onSave(Lyrics(lines: synced, source: .manual))
                        dismiss()
                    }
                    .disabled(cursor == 0)
                }
            }
            .onAppear {
                times = Array(repeating: nil, count: lines.count)
                if player.current?.id == song.id {
                    player.seek(to: 0)
                    if !player.isPlaying { player.resume() }
                } else {
                    player.play([song])
                }
            }
        }
    }
}
