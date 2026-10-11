import Foundation

/// Langue de l'interface : français (texte de référence), anglais, espagnol,
/// allemand, russe. Chaque texte affiché passe par L("Texte en français") ;
/// il est cherché dans la table de la langue choisie (Strings_xx.swift),
/// puis en anglais, sinon le français s'affiche.
enum Lang {
    static let supported = ["fr", "en", "es", "de", "ru"]
    static var code = "fr"

    static func resolve(_ choice: String) -> String {
        if supported.contains(choice) { return choice }
        for identifier in Locale.preferredLanguages {
            let base = identifier.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if supported.contains(base) { return base }
        }
        return "en"
    }

    static func apply(_ choice: String) {
        code = resolve(choice)
    }

    static func name(_ choice: String) -> String {
        switch choice {
        case "fr": return "Français"
        case "en": return "English"
        case "es": return "Español"
        case "de": return "Deutsch"
        case "ru": return "Русский"
        default: return L("Langue du téléphone")
        }
    }

    /// Format régional (dates, nombres).
    static var locale: Locale {
        switch code {
        case "en": return Locale(identifier: "en_US")
        case "es": return Locale(identifier: "es_ES")
        case "de": return Locale(identifier: "de_DE")
        case "ru": return Locale(identifier: "ru_RU")
        default: return Locale(identifier: "fr_FR")
        }
    }

    /// Langue chantée proposée par défaut pour générer les paroles.
    static var speechDefault: String {
        switch code {
        case "en": return "en-US"
        case "es": return "es-ES"
        case "de": return "de-DE"
        case "ru": return "ru-RU"
        default: return "fr-FR"
        }
    }
}

func L(_ french: String) -> String {
    switch Lang.code {
    case "en": return EN[french] ?? french
    case "es": return ES[french] ?? EN[french] ?? french
    case "de": return DE[french] ?? EN[french] ?? french
    case "ru": return RU[french] ?? EN[french] ?? french
    default: return french
    }
}

func L(_ french: String, _ values: [String: String]) -> String {
    var text = L(french)
    for (key, value) in values {
        text = text.replacingOccurrences(of: "{" + key + "}", with: value)
    }
    return text
}
