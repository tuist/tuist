import Foundation
import Sparkle
import SwiftUI

struct MenuBarView: View {
    @State var isExpanded = false
    @StateObject var errorHandling = ErrorHandling()
    private let simulatorsView: DevicesView
    private let viewModel: MenuBarViewModel

    init(
        appDelegate: AppDelegate,
        updaterController: SPUStandardUpdaterController
    ) {
        simulatorsView = DevicesView(appDelegate: appDelegate)
        viewModel = MenuBarViewModel(
            updater: updaterController.updater
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            simulatorsView

            Divider()

            Button("Check for updates", action: viewModel.checkForUpdates)
                .disabled(!viewModel.canCheckForUpdates)
                .menuItemStyle()

            Button("Quit Tuist") {
                NSApplication.shared.terminate(nil)
            }
            .menuItemStyle()
        }
        .padding(8)
        .environmentObject(errorHandling)
    }
}
