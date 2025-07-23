import Combine
import Path
import SwiftUI
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport

struct DevicesView: View, ErrorViewHandling {
    @State var viewModel: DevicesViewModel
    @EnvironmentObject var deviceService: DeviceService
    @EnvironmentObject var errorHandling: ErrorHandling

    @State var isExpanded = false

    @State private var rotationDegrees = 0.0
    @State private var isRefreshing = false {
        didSet {
            if isRefreshing {
                refreshControlNextTurn()
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: DevicesViewModel
    ) {
        let errorHandling = ErrorHandling()
        do {
            try viewModel.onAppear()
        } catch {
            errorHandling.handle(error: error)
        }
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pinnedDevicesSection()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            HStack {
                Text("Other devices")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(height: 16)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .menuItemStyle()
            .padding(.horizontal, 8)

            if isExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        simulators(viewModel.unpinnedSimulators)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: isExpanded ? NSScreen.main.map { $0.visibleFrame.size.height - 500 } ?? 500 : 0)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func pinnedDevicesSection() -> some View {
        if !viewModel.devices.isEmpty || !viewModel.pinnedSimulators.isEmpty {
            HStack {
                Text("Devices")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    isRefreshing = true
                    Task {
                        do {
                            try await viewModel.refreshDevices()
                        } catch {
                            errorHandling.handle(error: error)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .fontWeight(.medium)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(rotationDegrees))
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 4)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                deviceList("Connected", devices: viewModel.connectedDevices)
                deviceList("Disconnected", devices: viewModel.disconnectedDevices)

                if !viewModel.pinnedSimulators.isEmpty {
                    Text("Simulators")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(4)

                    simulators(viewModel.pinnedSimulators)
                }
            }
            .padding(.bottom, 2)

            Divider()
        }
    }

    @ViewBuilder
    private func deviceList(_ titleKey: LocalizedStringKey, devices: [PhysicalDevice]) -> some View {
        if !devices.isEmpty {
            Text(titleKey)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(4)

            ForEach(devices) { device in
                let selected = switch viewModel.selectedDevice {
                case let .device(selectedDevice):
                    selectedDevice.id == device.id
                case .simulator, .none:
                    false
                }

                PhysicalDeviceRow(
                    device: device,
                    selected: selected,
                    onSelected: viewModel.selectPhysicalDevice
                )
            }
        }
    }

    private func simulators(_ simulators: [SimulatorDeviceAndRuntime]) -> some View {
        ForEach(simulators) { simulator in
            let selected = switch viewModel.selectedDevice {
            case let .simulator(selectedSimulator):
                simulator.device.udid == selectedSimulator.device.udid
            case .device, .none:
                false
            }

            return SimulatorRow(
                simulator: simulator,
                selected: selected,
                pinned: viewModel.pinnedSimulators.contains(where: { $0.device.udid == simulator.device.udid })
            ) { simulator in
                viewModel.selectSimulator(simulator)
            } onPinned: { simulator, pinned in
                viewModel.simulatorPinned(simulator, pinned: pinned)
            }
        }
    }

    private func refreshControlNextTurn() {
        withAnimation(.linear(duration: 0.8)) {
            rotationDegrees += 360
        } completion: {
            if viewModel.isRefreshing {
                refreshControlNextTurn()
            } else {
                isRefreshing = false
                rotationDegrees = .zero
            }
        }
    }
}
