import Foundation
import SwiftUI

/// Langue de l'interface, surchargeable depuis le menu.
///
/// Par defaut l'application suit la langue du systeme. Le choix explicite
/// sert surtout a verifier les deux traductions sans avoir a changer les
/// reglages de macOS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return NSLocalizedString("language.system", comment: "")
        case .english: return "English"
        case .french: return "Francais"
        }
    }

    /// Locale a appliquer, `nil` pour suivre le systeme.
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }
}

/// Conserve le choix de langue et fournit le bundle correspondant.
@MainActor
final class LanguageSettings: ObservableObject {
    @AppStorage("appLanguage") var language: AppLanguage = .system {
        didSet { objectWillChange.send() }
    }

    /// Locale effective, utilisee par `environment(\.locale)`.
    var effectiveLocale: Locale {
        language.locale ?? Locale.current
    }
}
