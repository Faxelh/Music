import SwiftUI
import UIKit

/// Personnalisation : profil (nom + photo), couleur, fond du lecteur,
/// style de pochette, visualiseur, animations.
final class Appearance: ObservableObject {
    static let shared = Appearance()

    enum Background: String, CaseIterable, Identifiable {
        case aurora, artwork, photo, gradient, black
        var id: String { rawValue }

        var name: String {
            switch self {
            case .aurora: return L("Aurore animée")
            case .artwork: return L("Pochette floue")
            case .photo: return L("Ma photo")
            case .gradient: return L("Dégradé arc-en-ciel")
            case .black: return L("Noir profond")
            }
        }

        var icon: String {
            switch self {
            case .aurora: return "sparkles"
            case .artwork: return "photo.fill"
            case .photo: return "person.crop.square.fill"
            case .gradient: return "rainbow"
            case .black: return "moon.fill"
            }
        }
    }

    enum CoverStyle: String, CaseIterable, Identifiable {
        case square, round, vinyl, cd, cassette, card, polaroid, neon, stack, floating
        var id: String { rawValue }

        var name: String {
            switch self {
            case .square: return L("Pochette")
            case .round: return L("Rond qui pulse")
            case .vinyl: return L("Vinyle qui tourne")
            case .cd: return L("CD irisé")
            case .cassette: return L("Cassette")
            case .card: return L("Carte 3D")
            case .polaroid: return L("Polaroid")
            case .neon: return L("Néon")
            case .stack: return L("Pile de pochettes")
            case .floating: return L("Reflet flottant")
            }
        }
    }

    enum Visualizer: String, CaseIterable, Identifiable {
        case bars, mirror, rainbow, dots, wave, line, ring, particles, pulse, halo, none
        var id: String { rawValue }

        var name: String {
            switch self {
            case .bars: return L("Barres")
            case .mirror: return L("Barres miroir")
            case .rainbow: return L("Arc-en-ciel")
            case .dots: return L("Points")
            case .wave: return L("Onde")
            case .line: return L("Ligne lumineuse")
            case .ring: return L("Anneau")
            case .particles: return L("Particules")
            case .pulse: return L("Ondes de choc")
            case .halo: return L("Halo")
            case .none: return L("Aucun")
            }
        }

        /// Dessiné autour de la pochette (sinon en dessous).
        var surroundsCover: Bool {
            self == .ring || self == .particles || self == .pulse || self == .halo
        }
    }

    static let accents: [String] = ["FF2D60", "FF9500", "FFCC00", "34C759", "00C7BE", "0A84FF", "5E5CE6", "BF5AF2", "FF375F", "A2845E"]

    @Published var userName: String { didSet { save("userName", userName) } }
    @Published var accentHex: String { didSet { save("accentHex", accentHex) } }
    @Published var background: Background { didSet { save("playerBackground", background.rawValue) } }
    @Published var coverStyle: CoverStyle { didSet { save("coverStyle", coverStyle.rawValue) } }
    @Published var visualizer: Visualizer { didSet { save("visualizer", visualizer.rawValue) } }
    @Published var animations: Bool { didSet { save("animations", animations) } }
    @Published var backgroundDim: Double { didSet { save("backgroundDim", backgroundDim) } }
    @Published var lyricsAuto: Bool { didSet { save("lyricsAuto", lyricsAuto) } }
    @Published var lyricsSize: Double { didSet { save("lyricsSize", lyricsSize) } }
    @Published private(set) var profileImage: UIImage?
    @Published private(set) var playerImage: UIImage?

    var accent: Color { Color(hex: accentHex) }

    private static var profileURL: URL { LibraryStore.support.appendingPathComponent("profile.jpg") }
    private static var playerURL: URL { LibraryStore.support.appendingPathComponent("player.jpg") }

    private init() {
        let defaults = UserDefaults.standard
        userName = defaults.string(forKey: "userName") ?? ""
        accentHex = defaults.string(forKey: "accentHex") ?? "FF2D60"
        background = Background(rawValue: defaults.string(forKey: "playerBackground") ?? "") ?? .aurora
        coverStyle = CoverStyle(rawValue: defaults.string(forKey: "coverStyle") ?? "") ?? .square
        visualizer = Visualizer(rawValue: defaults.string(forKey: "visualizer") ?? "") ?? .bars
        animations = defaults.object(forKey: "animations") as? Bool ?? true
        backgroundDim = defaults.object(forKey: "backgroundDim") as? Double ?? 0.35
        lyricsAuto = defaults.object(forKey: "lyricsAuto") as? Bool ?? true
        lyricsSize = defaults.object(forKey: "lyricsSize") as? Double ?? 26
        profileImage = UIImage(contentsOfFile: Appearance.profileURL.path)
        playerImage = UIImage(contentsOfFile: Appearance.playerURL.path)
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func setProfileImage(_ image: UIImage?) {
        if let image = image {
            LibraryStore.saveImage(image, to: Appearance.profileURL, side: 600)
            profileImage = UIImage(contentsOfFile: Appearance.profileURL.path)
        } else {
            try? FileManager.default.removeItem(at: Appearance.profileURL)
            profileImage = nil
        }
    }

    func setPlayerImage(_ image: UIImage?) {
        if let image = image {
            LibraryStore.saveImage(image, to: Appearance.playerURL, side: 1600)
            playerImage = UIImage(contentsOfFile: Appearance.playerURL.path)
            background = .photo
        } else {
            try? FileManager.default.removeItem(at: Appearance.playerURL)
            playerImage = nil
            if background == .photo { background = .aurora }
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        if hour < 5 || hour >= 18 {
            base = L("Bonsoir")
        } else if hour < 12 {
            base = L("Bonjour")
        } else {
            base = L("Bon après-midi")
        }
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? base : base + ", " + name
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let ui = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(max(0, min(1, red)) * 255), Int(max(0, min(1, green)) * 255),
                      Int(max(0, min(1, blue)) * 255))
    }
}
