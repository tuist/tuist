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
        VStack(alignment: .leading, spacing: 0) {
            simulatorsView

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Button("Check for updates", action: viewModel.checkForUpdates)
                .disabled(!viewModel.canCheckForUpdates)
                .padding(.vertical, 2)
                .menuItemStyle()
                .padding(.horizontal, 8)

            Button("Quit Tuist") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.vertical, 2)
            .menuItemStyle()
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .environmentObject(errorHandling)
    }
}
