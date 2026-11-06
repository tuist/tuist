#if os(macOS)
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AtlasUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates: Bool

    private let controller: SPUStandardUpdaterController
    private var observations = Set<AnyCancellable>()

    init(startingUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observations)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct AtlasUpdateCommands: Commands {
    @ObservedObject var updater: AtlasUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

struct AtlasUpdateSettingsView: View {
    @ObservedObject var updater: AtlasUpdater

    var body: some View {
        Form {
            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                )
            )
            Button("Check for Updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
            Text("Updates are downloaded from Atlas’s signed macOS release feed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Updates")
    }
}
#endif
