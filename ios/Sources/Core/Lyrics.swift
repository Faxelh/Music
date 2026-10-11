import AVFoundation
import Foundation
import Speech

/// Une ligne de paroles (time = nil pour des paroles non synchronisées).
struct LyricLine: Identifiable, Equatable {
    let id: Int
    var time: Double?
    var text: String
}

/// Paroles d'un morceau.
struct Lyrics: Equatable {
    enum Source: String {
        case saved, file, embedded, online, generated, manual
    }

    var lines: [LyricLine]
    var source: Source

    var isSynced: Bool { lines.contains { $0.time != nil } }

    var plainText: String { lines.map { $0.text }.joined(separator: "\n") }

    /// Index de la ligne chantée au temps donné.
    func currentIndex(at seconds: Double) -> Int? {
        var found: Int?
        for (offset, line) in lines.enumerated() {
            guard let time = line.time else { continue }
            if time <= seconds + 0.15 { found = offset } else { break }
        }
        return found
    }

    /// Format LRC : « [01:23.45] texte ».
    var lrc: String {
        lines.map { line in
            guard let time = line.time else { return line.text }
            return "[" + LyricsParser.stamp(time) + "]" + line.text
        }.joined(separator: "\n")
    }
}

enum LyricsParser {
    /// Lit du LRC (synchronisé) ou du texte simple.
    static func parse(_ raw: String) -> [LyricLine] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var timed: [(Double, String)] = []
        var plain: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                if let seconds = time(String(tag)) {
                    times.append(seconds)
                    line = line[line.index(after: close)...]
                } else {
                    // Balises [ar:], [ti:], [offset:]… : ignorées.
                    line = ""
                    break
                }
            }
            let content = line.trimmingCharacters(in: .whitespaces)
            if times.isEmpty {
                if !rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("[") { plain.append(content) }
            } else {
                for value in times { timed.append((value, content)) }
            }
        }
        if !timed.isEmpty {
            return timed.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
        }
        while plain.first?.isEmpty == true { plain.removeFirst() }
        while plain.last?.isEmpty == true { plain.removeLast() }
        return plain.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
    }

    /// « 01:23.45 » → 83,45 s.
    static func time(_ tag: String) -> Double? {
        let parts = tag.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    static func stamp(_ seconds: Double) -> String {
        let value = max(0, seconds)
        let minutes = Int(value / 60)
        let rest = value - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, rest)
    }
}

/// Résultat de la recherche en ligne (LRCLIB, base libre de paroles).
struct OnlineLyrics: Identifiable, Hashable {
    let id: Int
    let track: String
    let artist: String
    let album: String
    let duration: Double
    let synced: String?
    let plain: String?

    var hasSynced: Bool { !(synced ?? "").isEmpty }
}

/// Paroles : enregistrées, fichier .lrc à côté du son, balise du fichier,
/// recherche en ligne, génération par reconnaissance vocale.
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var songID: String?
    @Published private(set) var loading = false
    @Published private(set) var generating = false
    @Published private(set) var generationProgress: Double = 0
    @Published private(set) var results: [OnlineLyrics] = []
    @Published private(set) var searching = false

    private var task: SFSpeechRecognitionTask?

    private static func savedURL(_ song: Song) -> URL {
        LibraryStore.lyricsFolder.appendingPathComponent(song.key + ".lrc")
    }

    /// Charge les paroles du morceau (sans réseau). Lance la recherche en ligne si demandé.
    func load(_ song: Song, autoSearch: Bool) {
        guard songID != song.id else { return }
        songID = song.id
        lyrics = nil
        results = []
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LyricsStore.localLyrics(song)
            DispatchQueue.main.async {
                guard self.songID == song.id else { return }
                self.lyrics = found
                self.loading = false
                if found == nil && autoSearch {
                    self.fetchBest(song)
                }
            }
        }
    }

    private static func localLyrics(_ song: Song) -> Lyrics? {
        if let text = try? String(contentsOf: savedURL(song), encoding: .utf8) {
            let lines = LyricsParser.parse(text)
            if !lines.isEmpty { return Lyrics(lines: lines, source: .saved) }
        }
        let sibling = song.isIpod ? URL(fileURLWithPath: "/dev/null/none.lrc")
            : song.url.deletingPathExtension().appendingPathExtension("lrc")
        if let text = (try? String(contentsOf: sibling, encoding: .utf8)) ?? (try? String(contentsOf: sibling, encoding: .isoLatin1)) {
            let lines = LyricsParser.parse(text)
            if !lines.isEmpty { return Lyrics(lines: lines, source: .file) }
        }
        let asset = AVURLAsset(url: song.assetURL)
        var text = asset.lyrics
        if text == nil || text?.isEmpty == true {
            for format in asset.availableMetadataFormats {
                for item in asset.metadata(forFormat: format) {
                    let identifier = item.identifier?.rawValue ?? ""
                    if identifier.hasSuffix("USLT") || identifier.hasSuffix("%A9lyr") || identifier.hasSuffix("SYLT") {
                        text = item.stringValue
                    }
                }
            }
        }
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Lyrics(lines: LyricsParser.parse(text), source: .embedded)
        }
        return nil
    }

    func save(_ lyrics: Lyrics, for song: Song) {
        let text = lyrics.lrc
        try? text.write(to: LyricsStore.savedURL(song), atomically: true, encoding: .utf8)
        if songID == song.id {
            self.lyrics = lyrics
        }
    }

    func delete(for song: Song) {
        try? FileManager.default.removeItem(at: LyricsStore.savedURL(song))
        songID = nil
        load(song, autoSearch: false)
    }

    // MARK: - En ligne (LRCLIB)

    private static func request(_ path: String, _ items: [URLQueryItem]) -> URLRequest? {
        var components = URLComponents(string: "https://lrclib.net/api/" + path)
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Music iOS 1.0 (https://github.com/Faxelh)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func decode(_ data: Data) -> [OnlineLyrics] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let array = object as? [[String: Any]] {
            list = array
        } else if let single = object as? [String: Any] {
            list = [single]
        } else {
            return []
        }
        return list.compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            let synced = item["syncedLyrics"] as? String
            let plain = item["plainLyrics"] as? String
            guard !(synced ?? "").isEmpty || !(plain ?? "").isEmpty else { return nil }
            return OnlineLyrics(id: id, track: item["trackName"] as? String ?? "",
                                artist: item["artistName"] as? String ?? "",
                                album: item["albumName"] as? String ?? "",
                                duration: (item["duration"] as? NSNumber)?.doubleValue ?? 0,
                                synced: synced, plain: plain)
        }
    }

    /// Cherche des paroles en ligne pour ce morceau (titre + artiste).
    func search(_ song: Song, query: String? = nil, completion: (() -> Void)? = nil) {
        var items: [URLQueryItem]
        if let query = query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            items = [URLQueryItem(name: "q", value: query)]
        } else {
            items = [URLQueryItem(name: "track_name", value: LyricsStore.cleanTitle(song.title))]
            if let artist = song.artist { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        }
        guard let request = LyricsStore.request("search", items) else { return }
        searching = true
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var found = data.map { LyricsStore.decode($0) } ?? []
            // Les plus proches de la durée du morceau d'abord, synchronisées avant.
            found.sort { lhs, rhs in
                if lhs.hasSynced != rhs.hasSynced { return lhs.hasSynced }
                return abs(lhs.duration - song.duration) < abs(rhs.duration - song.duration)
            }
            DispatchQueue.main.async {
                self.searching = false
                self.results = found
                completion?()
            }
        }.resume()
    }

    /// Recherche automatique : prend le meilleur résultat s'il correspond bien.
    func fetchBest(_ song: Song) {
        search(song) { [weak self] in
            guard let self = self, self.songID == song.id, self.lyrics == nil,
                  let best = self.results.first,
                  song.duration <= 0 || best.duration <= 0 || abs(best.duration - song.duration) < 6 else { return }
            self.use(best, for: song)
        }
    }

    func use(_ result: OnlineLyrics, for song: Song) {
        let text = result.hasSynced ? (result.synced ?? "") : (result.plain ?? "")
        let lines = LyricsParser.parse(text)
        guard !lines.isEmpty else { return }
        let found = Lyrics(lines: lines, source: .online)
        save(found, for: song)
    }

    /// « Titre (Official Video) [Clip] » → « Titre ».
    static func cleanTitle(_ title: String) -> String {
        var text = title
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        if let feat = text.range(of: " feat", options: .caseInsensitive) {
            text = String(text[..<feat.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Génération par reconnaissance vocale

    /// Écoute le morceau et en tire des paroles synchronisées (expérimental :
    /// fonctionne mieux quand la voix est claire).
    func generate(_ song: Song, language: String, completion: @escaping (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion(L("Autorisez la reconnaissance vocale dans Réglages › Music."))
                    return
                }
                LibraryStore.shared.prepare(song) { ok in
                    guard ok || !song.isIpod else {
                        completion(L("Lecture impossible : « {title} ».", ["title": song.title]))
                        return
                    }
                    self.startGeneration(song, language: language, completion: completion)
                }
            }
        }
    }

    private func startGeneration(_ song: Song, language: String, completion: @escaping (String?) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
            completion(L("Reconnaissance vocale indisponible pour cette langue."))
            return
        }
        task?.cancel()
        let request = SFSpeechURLRecognitionRequest(url: song.url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = false
        generating = true
        generationProgress = 0
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let result = result {
                    let segments = result.bestTranscription.segments
                    if let last = segments.last, song.duration > 0 {
                        self.generationProgress = min(1, (last.timestamp + last.duration) / song.duration)
                    }
                    if result.isFinal {
                        self.generating = false
                        let lines = LyricsStore.lines(from: segments)
                        guard !lines.isEmpty else {
                            completion(L("Aucune voix reconnue dans ce morceau."))
                            return
                        }
                        self.save(Lyrics(lines: lines, source: .generated), for: song)
                        completion(nil)
                    }
                } else if error != nil {
                    self.generating = false
                    completion(L("La génération a échoué. Essayez une autre langue ou un morceau où la voix est plus claire."))
                }
            }
        }
    }

    func cancelGeneration() {
        task?.cancel()
        task = nil
        generating = false
    }

    /// Regroupe les mots en lignes (pause de plus de 0,7 s ou 8 mots).
    private static func lines(from segments: [SFTranscriptionSegment]) -> [LyricLine] {
        var lines: [LyricLine] = []
        var words: [String] = []
        var start: Double?
        var lastEnd: Double = 0
        for segment in segments {
            let gap = segment.timestamp - lastEnd
            if !words.isEmpty && (gap > 0.7 || words.count >= 8) {
                lines.append(LyricLine(id: lines.count, time: start, text: words.joined(separator: " ")))
                words = []
                start = nil
            }
            if start == nil { start = segment.timestamp }
            words.append(segment.substring)
            lastEnd = segment.timestamp + segment.duration
        }
        if !words.isEmpty {
            lines.append(LyricLine(id: lines.count, time: start, text: words.joined(separator: " ")))
        }
        return lines.map { line in
            var copy = line
            if let first = copy.text.first {
                copy.text = first.uppercased() + copy.text.dropFirst()
            }
            return copy
        }
    }
}
