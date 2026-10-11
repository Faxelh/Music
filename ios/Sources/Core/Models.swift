import Foundation
import MediaPlayer
import SwiftUI

let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "flac", "aif", "aiff", "caf", "m4b", "alac"]

/// Un morceau du dossier de Music (copié avec 3uTools, l'app Fichiers…).
struct Song: Identifiable, Hashable, Codable {
    /// Chemin relatif au dossier Documents : identifiant stable.
    var id: String
    var title: String
    var artist: String?
    var album: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var duration: Double = 0
    var hasArtwork = false
    var size: Double = 0
    var modified: Double = 0
    var added: Double = 0
    /// « doc » (dossier de Music), « folder » (dossier lié), « ipod » (musique de l'iPhone).
    var source = "doc"
    var folderID: String?
    var folderName: String?
    /// Chemin dans le dossier (doc, folder).
    var relative = ""
    /// Musique de l'iPhone : identifiant et adresse dans la bibliothèque d'iOS.
    var persistentID: String?
    var assetLink: String?

    /// Fichier lisible (pour la musique de l'iPhone : la copie préparée par Music).
    var url: URL { LibraryStore.fileURL(for: self) }

    /// Adresse pour lire les balises et les paroles intégrées.
    var assetURL: URL {
        if source == "ipod", let link = assetLink, let url = URL(string: link) { return url }
        return url
    }

    var isIpod: Bool { source == "ipod" }

    var displayArtist: String { artist ?? L("Artiste inconnu") }

    var folder: String {
        switch source {
        case "ipod":
            return L("Musique de l'iPhone")
        case "folder":
            let parent = (relative as NSString).deletingLastPathComponent
            let name = folderName ?? L("Dossier lié")
            return parent.isEmpty ? name : name + " › " + parent
        default:
            let parent = (relative.isEmpty ? id : relative) as NSString
            let path = parent.deletingLastPathComponent
            return path.isEmpty ? L("Music") : path
        }
    }

    /// Clé courte pour les fichiers liés (pochette, paroles).
    var key: String { LibraryStore.hash(id) }
}

/// Une playlist (avec sa photo de couverture facultative).
struct Playlist: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var songIDs: [String]
    var hasCover = false
    var created: Double = Date().timeIntervalSince1970
}

/// Artiste ou album.
struct MusicGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let songs: [Song]
    let artwork: Song?
}

/// Données personnelles de la bibliothèque (enregistrées sur l'iPhone).
struct UserData: Codable {
    var hidden: [String]? = []
    var favorites: [String] = []
    var playlists: [Playlist] = []
    var playCounts: [String: Int] = [:]
    var lastPlayed: [String: Double] = [:]
    var customArtwork: [String] = []
}

/// Un dossier de l'app Fichiers relié à Music (ex. Sur mon iPhone › Faxel).
struct LinkedFolder: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var bookmark: Data
}

enum LibraryRoute: Hashable, Codable {
    case songs
    case artists
    case albums
    case playlists
    case favorites
    case mostPlayed
    case folders
    case artist(String)
    case album(String)
    case playlist(String)
    case folder(String)
}

enum AppTab: String, Hashable {
    case home, library, search, settings
}

struct Toast: Identifiable, Equatable {
    enum Kind {
        case info, ok, warn, error
    }

    let id = UUID()
    let text: String
    let kind: Kind
}
