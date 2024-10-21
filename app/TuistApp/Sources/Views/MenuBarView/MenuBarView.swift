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
            Text("Tuist")
                .font(.title3)
                .bold()
                .background(Color.clear)
                .padding([.leading, .trailing], 8)

            Divider()
                .padding([.leading, .trailing], 8)

            simulatorsView

            Divider()
                .padding([.leading, .trailing], 8)

            Button("Check for updates", action: viewModel.checkForUpdates)
                .disabled(!viewModel.canCheckForUpdates)
                .menuItemStyle()
                .padding([.leading, .trailing], 8)

            Button("Quit Tuist") {
                NSApplication.shared.terminate(nil)
            }
            .menuItemStyle()
            .padding([.leading, .trailing], 8)
        }
        .padding([.top, .bottom], 8)
        .environmentObject(errorHandling)
    }
}
