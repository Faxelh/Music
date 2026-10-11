import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// État de l'interface : onglet, messages, lecteur ouvert.
final class AppState: ObservableObject {
    static let shared = AppState()

    // Onglet et écrans ouverts : retrouvés à la prochaine ouverture.
    @Published var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "lastTab") ?? "") ?? .home {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "lastTab") }
    }
    @Published var libraryPath: [LibraryRoute] = AppState.loadPath("libraryPath") {
        didSet { AppState.savePath(libraryPath, "libraryPath") }
    }
    @Published var homePath: [LibraryRoute] = AppState.loadPath("homePath") {
        didSet { AppState.savePath(homePath, "homePath") }
    }
    @Published var searchPath: [LibraryRoute] = AppState.loadPath("searchPath") {
        didSet { AppState.savePath(searchPath, "searchPath") }
    }

    private static func loadPath(_ key: String) -> [LibraryRoute] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let path = try? JSONDecoder().decode([LibraryRoute].self, from: data) else { return [] }
        return path
    }

    private static func savePath(_ path: [LibraryRoute], _ key: String) {
        if let data = try? JSONEncoder().encode(path) { UserDefaults.standard.set(data, forKey: key) }
    }
    @Published var toast: Toast?
    @Published var playerOpen = false

    func show(_ text: String, _ kind: Toast.Kind = .info) {
        let toast = Toast(text: text, kind: kind)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            self.toast = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (kind == .error ? 5 : 3)) { [weak self] in
            guard let self = self, self.toast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
        }
    }
}

/// La bibliothèque : tous les sons du dossier de Music (3uTools, Fichiers,
/// « Ouvrir avec »), leurs balises et pochettes, favoris, playlists, écoutes.
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var songs: [Song] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var playCounts: [String: Int] = [:]
    @Published private(set) var lastPlayed: [String: Double] = [:]
    @Published private(set) var customArtwork: Set<String> = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var linkedFolders: [LinkedFolder] = []
    @Published private(set) var preparing: Set<String> = []
    @Published private(set) var scanning = false
    @Published private(set) var loaded = false
    /// Change à chaque nouvelle pochette (pour rafraîchir les images).
    @Published private(set) var artworkVersion = 0

    private let queue = DispatchQueue(label: "music.library", qos: .userInitiated)
    private var colorCache: [String: [Color]] = [:]
    private var lastScan = Date.distantPast

    // MARK: - Dossiers

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
    }

    static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
    }

    static var artFolder: URL { caches.appendingPathComponent("art", isDirectory: true) }
    static var coverFolder: URL { support.appendingPathComponent("covers", isDirectory: true) }
    static var lyricsFolder: URL { support.appendingPathComponent("lyrics", isDirectory: true) }
    private static var songsCache: URL { caches.appendingPathComponent("songs.json") }
    private static var userFile: URL { support.appendingPathComponent("user.json") }
    private static var foldersFile: URL { support.appendingPathComponent("folders.json") }
    static var ipodFolder: URL { caches.appendingPathComponent("iphone", isDirectory: true) }

    /// Dossiers liés ouverts (accès autorisé gardé pendant toute la session).
    private static let folderLock = NSLock()
    private static var folderBases: [String: URL] = [:]

    static func base(of folderID: String) -> URL? {
        folderLock.lock()
        defer { folderLock.unlock() }
        return folderBases[folderID]
    }

    private static func setBase(_ url: URL?, for folderID: String) {
        folderLock.lock()
        folderBases[folderID] = url
        folderLock.unlock()
    }

    /// Fichier à lire pour un morceau.
    static func fileURL(for song: Song) -> URL {
        switch song.source {
        case "folder":
            let base = song.folderID.flatMap { LibraryStore.base(of: $0) } ?? documents
            return base.appendingPathComponent(song.relative)
        case "ipod":
            return ipodFolder.appendingPathComponent((song.persistentID ?? song.key) + ".m4a")
        default:
            return documents.appendingPathComponent(song.relative.isEmpty ? song.id : song.relative)
        }
    }

    static func hash(_ text: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private init() {
        for folder in [LibraryStore.support, LibraryStore.caches, LibraryStore.artFolder,
                       LibraryStore.coverFolder, LibraryStore.lyricsFolder, LibraryStore.ipodFolder] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if let data = try? Data(contentsOf: LibraryStore.songsCache),
           let saved = try? JSONDecoder().decode([Song].self, from: data) {
            songs = saved
            loaded = !saved.isEmpty
        }
        if let data = try? Data(contentsOf: LibraryStore.userFile),
           let user = try? JSONDecoder().decode(UserData.self, from: data) {
            favorites = Set(user.favorites)
            playlists = user.playlists
            playCounts = user.playCounts
            lastPlayed = user.lastPlayed
            customArtwork = Set(user.customArtwork)
            hidden = Set(user.hidden ?? [])
        }
        if let data = try? Data(contentsOf: LibraryStore.foldersFile),
           let folders = try? JSONDecoder().decode([LinkedFolder].self, from: data) {
            linkedFolders = folders
            for folder in folders { openFolder(folder) }
        }
        scan(force: true)
    }

    // MARK: - Lecture du dossier

    /// Relit le dossier Documents : nouveaux fichiers ajoutés, fichiers disparus retirés.
    func scan(force: Bool = false, completion: ((Int) -> Void)? = nil) {
        guard force || Date().timeIntervalSince(lastScan) > 3 else {
            completion?(0)
            return
        }
        lastScan = Date()
        scanning = true
        let known = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let folders = linkedFolders
        let useIpod = UserDefaults.standard.object(forKey: "useMediaLibrary") as? Bool ?? true
            && MPMediaLibrary.authorizationStatus() == .authorized
        queue.async { [weak self] in
            var found: [Song] = []
            var added = 0
            func add(_ song: Song) {
                if known[song.id] == nil { added += 1 }
                found.append(song)
            }
            for song in LibraryStore.walk(LibraryStore.documents, folder: nil, known: known) { add(song) }
            for folder in folders {
                guard let base = LibraryStore.base(of: folder.id) else { continue }
                for song in LibraryStore.walk(base, folder: folder, known: known) { add(song) }
            }
            if useIpod {
                for song in LibraryStore.iphoneSongs(known: known) { add(song) }
            }
            found.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if let data = try? JSONEncoder().encode(found) {
                try? data.write(to: LibraryStore.songsCache, options: .atomic)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                let visible = found.filter { !self.hidden.contains($0.id) }
                let changed = visible != self.songs
                if changed {
                    self.songs = visible
                    self.artworkVersion += 1
                    self.colorCache = [:]
                }
                self.scanning = false
                self.loaded = true
                if changed { self.cleanUserData() }
                completion?(added)
            }
        }
    }

    /// Sons d'un dossier (Documents de Music ou dossier lié).
    private static func walk(_ root: URL, folder: LinkedFolder?, known: [String: Song]) -> [Song] {
        var result: [Song] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .creationDateKey]
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            let relative = LibraryStore.relativePath(url, root: root)
            let id = folder.map { "f:" + $0.id + ":" + relative } ?? relative
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if var old = known[id], old.modified == modified {
                old.folderName = folder?.name
                result.append(old)
                continue
            }
            var song = autoreleasepool { LibraryStore.readSong(url, id: id) }
            song.relative = relative
            if let folder = folder {
                song.source = "folder"
                song.folderID = folder.id
                song.folderName = folder.name
            }
            song.modified = modified
            song.size = Double(values?.fileSize ?? 0)
            song.added = known[id]?.added ?? (values?.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
            result.append(song)
        }
        return result
    }

    /// Musique déjà sur l'iPhone (app Musique, synchronisée avec iTunes / 3uTools).
    private static func iphoneSongs(known: [String: Song]) -> [Song] {
        guard let items = MPMediaQuery.songs().items else { return [] }
        var result: [Song] = []
        for item in items {
            guard let asset = item.assetURL, !item.hasProtectedAsset, !item.isCloudItem else { continue }
            let pid = String(item.persistentID)
            let id = "ipod:" + pid
            let added = item.dateAdded.timeIntervalSince1970
            if let old = known[id], old.modified == added {
                result.append(old)
                continue
            }
            var song = Song(id: id, title: item.title ?? L("Sans titre"))
            song.source = "ipod"
            song.persistentID = pid
            song.assetLink = asset.absoluteString
            song.artist = item.artist ?? item.albumArtist
            song.album = item.albumTitle
            song.genre = item.genre
            song.trackNumber = item.albumTrackNumber > 0 ? item.albumTrackNumber : nil
            song.duration = item.playbackDuration
            song.modified = added
            song.added = added
            if let year = item.value(forProperty: "year") as? NSNumber, year.intValue > 0 { song.year = year.intValue }
            let target = artFolder.appendingPathComponent(LibraryStore.hash(id) + ".jpg")
            if FileManager.default.fileExists(atPath: target.path) {
                song.hasArtwork = true
            } else if let image = item.artwork?.image(at: CGSize(width: 600, height: 600)) {
                song.hasArtwork = saveImage(image, to: target, side: 700)
            }
            result.append(song)
        }
        return result
    }

    // MARK: - Musique de l'iPhone et dossiers liés

    /// Autorise et ajoute la musique de l'app Musique de l'iPhone.
    func enableMediaLibrary(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "useMediaLibrary")
        guard enabled else {
            scan(force: true)
            return
        }
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self.scan(force: true) { _ in
                        AppState.shared.show(L("Musique de l'iPhone ajoutée à la bibliothèque."), .ok)
                    }
                } else {
                    AppState.shared.show(L("Autorisez l'accès dans Réglages › Music › Médias et Apple Music."), .warn)
                }
            }
        }
    }

    var mediaLibraryEnabled: Bool {
        (UserDefaults.standard.object(forKey: "useMediaLibrary") as? Bool ?? true)
            && MPMediaLibrary.authorizationStatus() == .authorized
    }

    /// Prépare une copie lisible d'un morceau de l'app Musique (une seule fois).
    func prepare(_ song: Song, completion: @escaping (Bool) -> Void) {
        let target = song.url
        if FileManager.default.fileExists(atPath: target.path) {
            completion(true)
            return
        }
        guard let link = song.assetLink, let source = URL(string: link),
              let export = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
            completion(false)
            return
        }
        preparing.insert(song.id)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
        export.outputURL = temporary
        export.outputFileType = .m4a
        export.exportAsynchronously {
            let ok = export.status == .completed
            if ok { try? FileManager.default.moveItem(at: temporary, to: target) } else {
                try? FileManager.default.removeItem(at: temporary)
            }
            DispatchQueue.main.async {
                self.preparing.remove(song.id)
                completion(ok && FileManager.default.fileExists(atPath: target.path))
            }
        }
    }

    private func openFolder(_ folder: LinkedFolder) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        LibraryStore.setBase(url, for: folder.id)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
           let index = linkedFolders.firstIndex(where: { $0.id == folder.id }) {
            linkedFolders[index].bookmark = fresh
            saveFolders()
        }
    }

    /// Relie un dossier de l'app Fichiers (ex. Sur mon iPhone › Faxel) : ses sons apparaissent ici.
    func linkFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            AppState.shared.show(L("Ce dossier ne peut pas être relié."), .error)
            return
        }
        let folder = LinkedFolder(id: UUID().uuidString, name: url.lastPathComponent, bookmark: bookmark)
        linkedFolders.append(folder)
        LibraryStore.setBase(url, for: folder.id)
        saveFolders()
        scan(force: true) { added in
            AppState.shared.show(L("« {name} » relié : {count} morceau(x).", ["name": folder.name, "count": "\(added)"]), .ok)
        }
    }

    func unlinkFolder(_ id: String) {
        if let url = LibraryStore.base(of: id) { url.stopAccessingSecurityScopedResource() }
        LibraryStore.setBase(nil, for: id)
        linkedFolders.removeAll { $0.id == id }
        saveFolders()
        scan(force: true)
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(linkedFolders) {
            try? data.write(to: LibraryStore.foldersFile, options: .atomic)
        }
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        if full.hasPrefix(base + "/") {
            return String(full.dropFirst(base.count + 1))
        }
        let resolved = url.resolvingSymlinksInPath().path
        let resolvedBase = root.resolvingSymlinksInPath().path
        if resolved.hasPrefix(resolvedBase + "/") {
            return String(resolved.dropFirst(resolvedBase.count + 1))
        }
        return url.lastPathComponent
    }

    /// Balises du fichier (titre, artiste, album, n° de piste, pochette).
    private static func readSong(_ url: URL, id: String) -> Song {
        var song = Song(id: id, title: url.deletingPathExtension().lastPathComponent)
        let asset = AVURLAsset(url: url)
        let seconds = asset.duration.seconds
        if seconds.isFinite && seconds > 0 { song.duration = seconds }
        var artwork: Data?
        for item in asset.commonMetadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                if let value = clean(item.stringValue) { song.title = value }
            case .commonKeyArtist:
                song.artist = clean(item.stringValue)
            case .commonKeyAlbumName:
                song.album = clean(item.stringValue)
            case .commonKeyType:
                song.genre = clean(item.stringValue)
            case .commonKeyCreationDate:
                if let text = item.stringValue, let year = Int(text.prefix(4)) { song.year = year }
            case .commonKeyArtwork:
                if artwork == nil { artwork = item.dataValue }
            default:
                break
            }
        }
        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                let identifier = item.identifier?.rawValue ?? ""
                if identifier.hasSuffix("TRCK") || identifier.hasSuffix("trkn") {
                    if let text = item.stringValue, let number = Int(text.split(separator: "/").first ?? "") {
                        song.trackNumber = number
                    } else if let data = item.dataValue, data.count >= 4 {
                        song.trackNumber = Int(data[3])
                    }
                } else if song.artist == nil && (identifier.hasSuffix("TPE2") || identifier.hasSuffix("aART")) {
                    song.artist = clean(item.stringValue)
                } else if song.genre == nil && (identifier.hasSuffix("TCON") || identifier.hasSuffix("%A9gen")) {
                    song.genre = clean(item.stringValue)
                }
            }
        }
        if song.artist == nil, song.title.contains(" - ") {
            // « Artiste - Titre » dans le nom du fichier.
            let parts = song.title.components(separatedBy: " - ")
            if parts.count >= 2 {
                song.artist = parts[0].trimmingCharacters(in: .whitespaces)
                song.title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            }
        }
        let target = artFolder.appendingPathComponent(LibraryStore.hash(id) + ".jpg")
        if let data = artwork, let image = UIImage(data: data) {
            song.hasArtwork = saveImage(image, to: target, side: 700)
        } else {
            try? FileManager.default.removeItem(at: target)
        }
        return song
    }

    private static func clean(_ text: String?) -> String? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @discardableResult
    static func saveImage(_ image: UIImage, to url: URL, side: CGFloat) -> Bool {
        let largest = max(image.size.width, image.size.height)
        var output = image
        if largest > side {
            let scale = side / largest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = output.jpegData(compressionQuality: 0.85) else { return false }
        ImageCache.shared.forget(url)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    // MARK: - Pochettes et couleurs

    func artworkURL(_ song: Song) -> URL? {
        if customArtwork.contains(song.id) {
            return LibraryStore.coverFolder.appendingPathComponent("song-" + song.key + ".jpg")
        }
        return song.hasArtwork ? LibraryStore.artFolder.appendingPathComponent(song.key + ".jpg") : nil
    }

    func setArtwork(_ image: UIImage, for song: Song) {
        let url = LibraryStore.coverFolder.appendingPathComponent("song-" + song.key + ".jpg")
        if LibraryStore.saveImage(image, to: url, side: 900) {
            customArtwork.insert(song.id)
            colorCache[song.id] = nil
            artworkVersion += 1
            saveUser()
        }
    }

    func resetArtwork(for song: Song) {
        let url = LibraryStore.coverFolder.appendingPathComponent("song-" + song.key + ".jpg")
        try? FileManager.default.removeItem(at: url)
        ImageCache.shared.forget(url)
        customArtwork.remove(song.id)
        colorCache[song.id] = nil
        artworkVersion += 1
        saveUser()
    }

    func coverURL(_ playlist: Playlist) -> URL? {
        playlist.hasCover ? LibraryStore.coverFolder.appendingPathComponent("playlist-" + playlist.id + ".jpg") : nil
    }

    /// Couleurs dominantes de la pochette (fonds animés du lecteur).
    func colors(for song: Song?) -> [Color] {
        let fallback = [Color(red: 1, green: 0.18, blue: 0.38), Color(red: 0.55, green: 0.2, blue: 0.85),
                        Color(red: 1, green: 0.55, blue: 0.15), Color(red: 0.15, green: 0.35, blue: 0.9)]
        guard let song = song else { return fallback }
        if let cached = colorCache[song.id] { return cached }
        guard let url = artworkURL(song), let image = UIImage(contentsOfFile: url.path),
              let colors = LibraryStore.dominantColors(image), !colors.isEmpty else {
            let seeded = Array(fallback.shuffledStable(seed: song.id))
            colorCache[song.id] = seeded
            return seeded
        }
        colorCache[song.id] = colors
        return colors
    }

    private static func dominantColors(_ image: UIImage) -> [Color]? {
        let side = 4
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cgImage = small.cgImage, let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let perRow = cgImage.bytesPerRow
        let perPixel = max(3, cgImage.bitsPerPixel / 8)
        var colors: [(Color, Double)] = []
        for (x, y) in [(0, 0), (3, 0), (0, 3), (3, 3), (1, 1), (2, 2)] {
            let offset = y * perRow + x * perPixel
            let red = Double(bytes[offset]) / 255
            let green = Double(bytes[offset + 1]) / 255
            let blue = Double(bytes[offset + 2]) / 255
            let saturation = max(red, green, blue) - min(red, green, blue)
            colors.append((boost(red, green, blue), saturation))
        }
        return colors.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0 }
    }

    /// Couleur un peu plus vive et jamais trop sombre.
    private static func boost(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        let ui = UIColor(red: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        ui.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: Double(min(1, saturation * 1.25 + 0.08)),
                     brightness: Double(max(0.35, min(0.95, brightness * 1.1))))
    }

    // MARK: - Regroupements

    var artists: [MusicGroup] {
        var groups: [String: [Song]] = [:]
        var names: [String: String] = [:]
        for song in songs {
            let name = song.displayArtist
            let key = name.lowercased()
            groups[key, default: []].append(song)
            if names[key] == nil { names[key] = name }
        }
        return groups.map { key, list in
            let albums = Set(list.compactMap { $0.album }).count
            let detail = albums > 0
                ? L("{albums} album(s) · {count} titre(s)", ["albums": "\(albums)", "count": "\(list.count)"])
                : L("{count} titre(s)", ["count": "\(list.count)"])
            let sorted = LibraryStore.albumOrder(list)
            return MusicGroup(id: key, name: names[key] ?? key, subtitle: detail, songs: sorted,
                              artwork: sorted.first { self.artworkURL($0) != nil })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var albums: [MusicGroup] {
        albums(of: songs)
    }

    func albums(of list: [Song]) -> [MusicGroup] {
        var groups: [String: [Song]] = [:]
        var titles: [String: String] = [:]
        for song in list {
            guard let album = song.album else { continue }
            let key = album.lowercased()
            groups[key, default: []].append(song)
            if titles[key] == nil { titles[key] = album }
        }
        return groups.map { key, items in
            let artists = Array(Set(items.map { $0.displayArtist })).sorted()
            let by = artists.count == 1 ? artists[0] : L("Artistes divers")
            let sorted = LibraryStore.albumOrder(items)
            return MusicGroup(id: key, name: titles[key] ?? key, subtitle: by, songs: sorted,
                              artwork: sorted.first { self.artworkURL($0) != nil })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func albumOrder(_ list: [Song]) -> [Song] {
        list.sorted { lhs, rhs in
            let left = lhs.trackNumber ?? Int.max
            let right = rhs.trackNumber ?? Int.max
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var folders: [String] {
        Array(Set(songs.map { $0.folder })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var recentlyAdded: [Song] {
        songs.sorted { $0.added > $1.added }
    }

    var recentlyPlayed: [Song] {
        songs.filter { lastPlayed[$0.id] != nil }.sorted { (lastPlayed[$0.id] ?? 0) > (lastPlayed[$1.id] ?? 0) }
    }

    var mostPlayed: [Song] {
        songs.filter { (playCounts[$0.id] ?? 0) > 0 }.sorted { (playCounts[$0.id] ?? 0) > (playCounts[$1.id] ?? 0) }
    }

    var favoriteSongs: [Song] {
        songs.filter { favorites.contains($0.id) }
    }

    func song(_ id: String) -> Song? {
        songs.first { $0.id == id }
    }

    func songs(in playlist: Playlist) -> [Song] {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.songIDs.compactMap { byID[$0] }
    }

    func playlist(_ id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    // MARK: - Favoris, écoutes

    func isFavorite(_ song: Song) -> Bool { favorites.contains(song.id) }

    func toggleFavorite(_ song: Song) {
        if favorites.contains(song.id) {
            favorites.remove(song.id)
        } else {
            favorites.insert(song.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        saveUser()
    }

    func recordPlay(_ song: Song) {
        playCounts[song.id, default: 0] += 1
        lastPlayed[song.id] = Date().timeIntervalSince1970
        saveUser()
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(_ name: String, songs ids: [String] = []) -> Playlist {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(id: UUID().uuidString, name: clean.isEmpty ? L("Ma playlist") : clean, songIDs: ids)
        playlists.insert(playlist, at: 0)
        saveUser()
        return playlist
    }

    func renamePlaylist(_ id: String, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playlists[index].name = clean
        saveUser()
    }

    func deletePlaylist(_ id: String) {
        if let playlist = playlist(id), let url = coverURL(playlist) {
            try? FileManager.default.removeItem(at: url)
        }
        playlists.removeAll { $0.id == id }
        saveUser()
    }

    /// Ajoute des morceaux (sans doublons) ; renvoie le nombre ajouté.
    @discardableResult
    func add(_ ids: [String], to playlistID: String) -> Int {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return 0 }
        var added = 0
        for id in ids where !playlists[index].songIDs.contains(id) {
            playlists[index].songIDs.append(id)
            added += 1
        }
        saveUser()
        return added
    }

    func remove(at offsets: IndexSet, from playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let visible = songs(in: playlists[index]).map { $0.id }
        let removed = Set(offsets.compactMap { visible.indices.contains($0) ? visible[$0] : nil })
        playlists[index].songIDs.removeAll { removed.contains($0) }
        saveUser()
    }

    func move(from source: IndexSet, to destination: Int, in playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var visible = songs(in: playlists[index]).map { $0.id }
        visible.move(fromOffsets: source, toOffset: destination)
        let hidden = playlists[index].songIDs.filter { !visible.contains($0) }
        playlists[index].songIDs = visible + hidden
        saveUser()
    }

    func setCover(_ image: UIImage, for playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let url = LibraryStore.coverFolder.appendingPathComponent("playlist-" + playlistID + ".jpg")
        if LibraryStore.saveImage(image, to: url, side: 900) {
            playlists[index].hasCover = true
            artworkVersion += 1
            saveUser()
        }
    }

    // MARK: - Fichiers

    static var importFolder: URL {
        documents.appendingPathComponent(Lang.code == "en" ? "Imported" : "Importés", isDirectory: true)
    }

    func importFiles(_ urls: [URL]) {
        let folder = LibraryStore.importFolder
        queue.async { [weak self] in
            var copied = 0
            var refused = 0
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                let ext = url.pathExtension.lowercased()
                guard audioExtensions.contains(ext) || ext == "lrc" else {
                    refused += 1
                    continue
                }
                if url.standardizedFileURL.path.hasPrefix(LibraryStore.documents.standardizedFileURL.path) {
                    copied += 1
                    continue
                }
                let target = LibraryStore.uniqueURL(folder.appendingPathComponent(url.lastPathComponent))
                if (try? FileManager.default.copyItem(at: url, to: target)) != nil {
                    copied += 1
                } else {
                    refused += 1
                }
            }
            DispatchQueue.main.async {
                if copied > 0 {
                    AppState.shared.show(L("{count} fichier(s) importé(s).", ["count": "\(copied)"]), .ok)
                }
                if refused > 0 {
                    AppState.shared.show(L("{count} fichier(s) non pris en charge (formats lus : MP3, M4A, AAC, WAV, FLAC, AIFF).",
                                           ["count": "\(refused)"]), .warn)
                }
                self?.scan(force: true)
            }
        }
    }

    static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        for number in 2...9999 {
            let name = ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
    }

    /// Copies du même morceau ailleurs (autre dossier, musique de l'iPhone…).
    func duplicates(of song: Song) -> [Song] {
        let title = song.title.lowercased()
        let artist = song.displayArtist.lowercased()
        return songs.filter {
            $0.id != song.id && $0.title.lowercased() == title && $0.displayArtist.lowercased() == artist
                && abs($0.duration - song.duration) < 2
        }
    }

    /// Supprime le morceau (et, si demandé, ses copies) : fichier, listes, favoris,
    /// playlists, paroles, pochettes, file de lecture — partout dans Music.
    func delete(_ song: Song, everywhere: Bool = false) {
        let targets = [song] + (everywhere ? duplicates(of: song) : [])
        var removed: [Song] = []
        var failed = 0
        for item in targets {
            if item.isIpod {
                hidden.insert(item.id)
                removed.append(item)
            } else if (try? FileManager.default.removeItem(at: item.url)) != nil
                        || !FileManager.default.fileExists(atPath: item.url.path) {
                let lrc = item.url.deletingPathExtension().appendingPathExtension("lrc")
                try? FileManager.default.removeItem(at: lrc)
                removed.append(item)
            } else {
                failed += 1
            }
        }
        guard !removed.isEmpty else {
            AppState.shared.show(L("Le fichier n'a pas pu être supprimé."), .error)
            return
        }
        for item in removed {
            AudioEngine.shared.forget(item)
            for url in [LibraryStore.lyricsFolder.appendingPathComponent(item.key + ".lrc"),
                        LibraryStore.artFolder.appendingPathComponent(item.key + ".jpg"),
                        LibraryStore.coverFolder.appendingPathComponent("song-" + item.key + ".jpg")] {
                try? FileManager.default.removeItem(at: url)
                ImageCache.shared.forget(url)
            }
            if item.isIpod { try? FileManager.default.removeItem(at: item.url) }
            customArtwork.remove(item.id)
        }
        let ids = Set(removed.map { $0.id })
        songs.removeAll { ids.contains($0.id) }
        colorCache = colorCache.filter { !ids.contains($0.key) }
        artworkVersion += 1
        cleanUserData()
        let snapshot = songs
        queue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: LibraryStore.songsCache, options: .atomic)
            }
        }
        if failed > 0 {
            AppState.shared.show(L("{count} copie(s) n'ont pas pu être supprimées.", ["count": "\(failed)"]), .warn)
        } else if removed.count > 1 {
            AppState.shared.show(L("Supprimé partout ({count} copies).", ["count": "\(removed.count)"]), .info)
        } else {
            AppState.shared.show(song.isIpod ? L("Retiré de la bibliothèque de Music.") : L("Supprimé."), .info)
        }
    }

    /// Retire les références aux fichiers disparus.
    private func cleanUserData() {
        let ids = Set(songs.map { $0.id })
        favorites = favorites.filter { ids.contains($0) }
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { !ids.contains($0) }
        }
        playCounts = playCounts.filter { ids.contains($0.key) }
        lastPlayed = lastPlayed.filter { ids.contains($0.key) }
        saveUser()
    }

    private func saveUser() {
        let user = UserData(hidden: Array(hidden), favorites: Array(favorites), playlists: playlists, playCounts: playCounts,
                            lastPlayed: lastPlayed, customArtwork: Array(customArtwork))
        queue.async {
            if let data = try? JSONEncoder().encode(user) {
                try? data.write(to: LibraryStore.userFile, options: .atomic)
            }
        }
    }

    func openInFiles() {
        let path = LibraryStore.documents.path
        if let url = URL(string: "shareddocuments://" + path), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            AppState.shared.show(L("Vos sons sont dans l'app Fichiers › Sur mon iPhone › Music."), .info)
        }
    }

    func storageText() -> String {
        let used = songs.reduce(0) { $0 + $1.size }
        let total = songs.reduce(0) { $0 + $1.duration }
        let hours = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        return L("{count} morceaux · {hours} h {minutes} min · {size}",
                 ["count": "\(songs.count)", "hours": "\(hours)", "minutes": "\(minutes)",
                  "size": Fmt.size(used).isEmpty ? "0" : Fmt.size(used)])
    }
}

extension Array {
    /// Mélange toujours identique pour une même graine (couleurs par défaut).
    func shuffledStable(seed: String) -> [Element] {
        var generator = SeededGenerator(seed: LibraryStore.hash(seed))
        return shuffled(using: &generator)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = UInt64(seed, radix: 16) ?? 0x9E37_79B9_7F4A_7C15
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Petit cache des images enregistrées sur l'iPhone.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(_ url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let image = image(url) {
            completion(image)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let raw = UIImage(contentsOfFile: url.path)
            let image = raw?.preparingForDisplay() ?? raw
            if let image = image {
                self.cache.setObject(image, forKey: url.path as NSString)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    func forget(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }
}
