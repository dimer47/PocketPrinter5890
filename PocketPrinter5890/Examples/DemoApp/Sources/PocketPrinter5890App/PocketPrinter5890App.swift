import SwiftUI

@main
struct PocketPrinter5890App: App {
    @StateObject private var language = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // La locale explicite permet de basculer de langue sans
                // toucher aux reglages du systeme, ce qui rend les deux
                // traductions verifiables depuis l'application.
                .environment(\.locale, language.effectiveLocale)
                .environmentObject(language)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu(NSLocalizedString("menu.language", comment: "")) {
                Picker(NSLocalizedString("menu.language", comment: ""), selection: $language.language) {
                    ForEach(AppLanguage.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
