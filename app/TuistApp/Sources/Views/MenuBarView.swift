import Foundation
import SwiftUI

struct MenuBarView: View {
    @State var isExpanded = false
    @StateObject var errorHandling = ErrorHandling()
    let simulatorsView: SimulatorsView

    init(
        appDelegate: AppDelegate
    ) {
        simulatorsView = SimulatorsView(appDelegate: appDelegate)
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

            Button("Quit Tuist") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .menuItemStyle()
            .padding([.leading, .trailing], 8)
        }
        .padding([.top, .bottom], 8)
        .environmentObject(errorHandling)
    }
}
