import Combine
import Path
import SwiftUI
import TuistCore
import TuistServer
import TuistSupport

struct SimulatorsView: View, ErrorViewHandling {
    @State var viewModel = SimulatorsViewModel()
    @EnvironmentObject var errorHandling: ErrorHandling
    @State var isExpanded = false
    private var cancellables = Set<AnyCancellable>()

    init(appDelegate: AppDelegate) {
        // We can't rely on the SimulatorsView to be rendered before a deeplink is triggered.
        // Instead, we listen to the deeplink URL through an `AppDelegate` callback
        // that's eagerly set up in this `init` on startup.
        let viewModel = viewModel
        let errorHandling = ErrorHandling()
        Task {
            do {
                try await viewModel.onAppear()
            } catch {
                errorHandling.handle(error: error)
            }
        }
        appDelegate.onChangeOfURLs.sink { urls in
            Task {
                do {
                    try await viewModel.onChangeOfURL(urls.first)
                } catch {
                    errorHandling.handle(error: error)
                }
            }
        }
        .store(in: &cancellables)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if !viewModel.pinnedSimulators.isEmpty {
                    Text("Pinned simulators")
                        .font(.headline)
                        .fontWeight(.medium)
                        .padding(.leading, 4)

                    simulators(viewModel.pinnedSimulators)

                    Divider()
                }

                HStack {
                    Text("Other simulators")
                        .font(.headline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(height: 16)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isExpanded.toggle()
                }
                .menuItemStyle()

                if isExpanded {
                    VStack(spacing: 0) {
                        simulators(viewModel.unpinnedSimulators)
                    }
                }
            }
            .padding([.leading, .trailing], 8)
        }
        .frame(height: isExpanded ? NSScreen.main.map { $0.visibleFrame.size.height - 300 } ?? 500 : nil)
    }

    private func simulators(_ simulators: [SimulatorDeviceAndRuntime]) -> some View {
        ForEach(simulators) { simulator in
            SimulatorRow(
                simulator: simulator,
                selected: simulator.device.udid == viewModel.selectedSimulator?.device.udid,
                pinned: viewModel.pinnedSimulators.contains(where: { $0.device.udid == simulator.device.udid })
            ) { simulator in
                viewModel.selectSimulator(simulator)
            } onPinned: { simulator, pinned in
                viewModel.simulatorPinned(simulator, pinned: pinned)
            }
        }
    }
}
