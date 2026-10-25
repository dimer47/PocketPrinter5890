import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI

/// Navigation par onglets: sur telephone, les quatre volets de la version
/// macOS ne tiennent pas cote a cote.
struct RootView: View {
    @StateObject private var transport = PocketPrinter5890BLE()
    @StateObject private var setup = PrinterSetup()
    @StateObject private var brother = BrotherPrinterService()
    @State private var options = PrintOptions()

    var body: some View {
        TabView {
            NavigationView {
                ConnectionView(transport: transport, setup: setup, brother: brother, options: $options)
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("tab.connection", systemImage: "antenna.radiowaves.left.and.right") }

            NavigationView {
                ReceiptView(transport: transport, setup: setup, brother: brother, options: $options)
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("tab.receipt", systemImage: "doc.plaintext") }

            NavigationView {
                PrintToolsView(transport: transport, setup: setup, brother: brother, options: $options)
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("tab.tools", systemImage: "printer") }

            NavigationView {
                SettingsView(transport: transport, setup: setup, options: $options)
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("tab.settings", systemImage: "slider.horizontal.3") }

            NavigationView {
                ConsoleView(transport: transport, setup: setup, brother: brother)
            }
            .navigationViewStyle(.stack)
            .tabItem { Label("tab.console", systemImage: "terminal") }
        }
    }
}
