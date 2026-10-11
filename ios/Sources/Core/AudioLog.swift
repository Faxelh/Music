import Foundation

/// Journal du lecteur (diagnostic) : les 120 derniers événements audio, gardés même
/// si iOS ferme l'app. Visible dans Réglages → « Journal du lecteur ».
enum AudioLog {
    private static let key = "audioLog"
    private static let limit = 120
    private static let queue = DispatchQueue(label: "audio.log")
    private static var lines: [String] = UserDefaults.standard.stringArray(forKey: key) ?? []
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func add(_ text: String) {
        let line = formatter.string(from: Date()) + "  " + text
        queue.async {
            lines.append(line)
            if lines.count > limit { lines.removeFirst(lines.count - limit) }
            UserDefaults.standard.set(lines, forKey: key)
        }
    }

    static func all() -> [String] {
        queue.sync { lines }
    }

    static func clear() {
        queue.async {
            lines = []
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
