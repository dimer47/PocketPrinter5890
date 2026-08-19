import AppKit
import SwiftUI

/// Ramene la fenetre dans l'ecran si la position restauree n'y tient plus.
///
/// macOS memorise la position de la fenetre et la restaure telle quelle, y
/// compris lorsqu'elle designe un ecran externe debranche depuis. La fenetre
/// s'ouvre alors hors champ et parait tronquee.
final class WindowGuard: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.recenterOffscreenWindows() }
    }

    private func recenterOffscreenWindows() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame

        for window in NSApplication.shared.windows {
            let frame = window.frame
            // Une fenetre est consideree hors champ des qu'elle ne recouvre
            // pas au moins une bonne part de sa surface avec un ecran.
            let intersection = frame.intersection(visible)
            let covered = intersection.width * intersection.height
            let total = frame.width * frame.height
            guard total > 0, covered / total < 0.6 else { continue }

            var corrected = frame
            corrected.size.width = min(frame.width, visible.width)
            corrected.size.height = min(frame.height, visible.height)
            corrected.origin.x = visible.midX - corrected.width / 2
            corrected.origin.y = visible.midY - corrected.height / 2
            window.setFrame(corrected, display: true)
        }
    }
}

@main
struct PocketPrinter5890App: App {
    @NSApplicationDelegateAdaptor(WindowGuard.self) private var windowGuard
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
