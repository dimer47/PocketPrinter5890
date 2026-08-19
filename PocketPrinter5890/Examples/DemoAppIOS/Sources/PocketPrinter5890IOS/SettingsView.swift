import PocketPrinter5890BLE
import PocketPrinter5890Kit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var transport: PocketPrinter5890BLE
    @Binding var options: PrintOptions
    @State private var autoShutdown = 15.0

    var body: some View {
        List {
            Section("settings.print") {
                Picker("settings.width", selection: $options.width) {
                    ForEach(PrinterWidth.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("settings.density", selection: $options.density) {
                    ForEach(PrintDensity.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("settings.paper", selection: $options.paperMode) {
                    ForEach(PaperMode.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                VStack(alignment: .leading) {
                    Text(String(
                        format: NSLocalizedString("settings.feed", comment: ""),
                        options.trailingFeedDots,
                        options.trailingFeedDots / 8
                    ))
                    Slider(
                        value: Binding(
                            get: { Double(options.trailingFeedDots) },
                            set: { options.trailingFeedDots = Int($0) }
                        ),
                        in: 0...1200, step: 10
                    )
                }
            }

            Section("settings.transport") {
                Toggle("settings.creditFlow", isOn: $transport.useCreditFlowControl)
                VStack(alignment: .leading) {
                    Text(String(
                        format: NSLocalizedString("settings.packet", comment: ""),
                        transport.maxChunkSize
                    ))
                    Slider(
                        value: Binding(
                            get: { Double(transport.maxChunkSize) },
                            set: { transport.maxChunkSize = Int($0) }
                        ),
                        in: 20...500, step: 10
                    )
                }
            }

            Section("settings.device") {
                VStack(alignment: .leading) {
                    Text(autoShutdown == 0
                         ? NSLocalizedString("shutdown.disabled", comment: "")
                         : String(format: NSLocalizedString("shutdown.delay", comment: ""),
                                  Int(autoShutdown)))
                    Slider(value: $autoShutdown, in: 0...240, step: 5)
                    Text("shutdown.hint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button("shutdown.apply") {
                    PocketPrinter(transport: transport, options: options)
                        .setAutoShutdown(minutes: Int(autoShutdown))
                }
                Button("settings.read") {
                    PocketPrinter(transport: transport, options: options).readSettings()
                }
            }
            .disabled(!transport.isConnected)
        }
        .navigationTitle("tab.settings")
    }
}
