import Combine
import Path
import SwiftUI
import TuistAndroid
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
                        androidDevices(viewModel.unpinnedAndroidEmulators)
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
        if !viewModel.devices.isEmpty || !viewModel.androidPhysicalDevices.isEmpty
            || !viewModel.pinnedSimulators.isEmpty || !viewModel.pinnedAndroidEmulators.isEmpty
        {
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
                connectedDevicesList()
                deviceList("Disconnected", devices: viewModel.disconnectedDevices)

                if !viewModel.pinnedSimulators.isEmpty {
                    Text("Simulators")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(4)

                    simulators(viewModel.pinnedSimulators)
                }

                if !viewModel.pinnedAndroidEmulators.isEmpty {
                    Text("Android Emulators")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(4)

                    androidDevices(viewModel.pinnedAndroidEmulators)
                }
            }
            .padding(.bottom, 2)

            Divider()
        }
    }

    @ViewBuilder
    private func connectedDevicesList() -> some View {
        let connected = viewModel.connectedDevices
        let androidPhysical = viewModel.androidPhysicalDevices
        if !connected.isEmpty || !androidPhysical.isEmpty {
            Text("Connected")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(4)

            ForEach(connected) { device in
                let selected = switch viewModel.selectedDevice {
                case let .device(selectedDevice):
                    selectedDevice.id == device.id
                case .simulator, .androidDevice, .none:
                    false
                }

                PhysicalDeviceRow(
                    device: device,
                    selected: selected,
                    onSelected: viewModel.selectPhysicalDevice
                )
            }

            ForEach(androidPhysical, id: \.id) { device in
                let selected = switch viewModel.selectedDevice {
                case let .androidDevice(selectedDevice):
                    device.id == selectedDevice.id
                case .simulator, .device, .none:
                    false
                }

                AndroidDeviceRow(
                    device: device,
                    selected: selected,
                    onSelected: { viewModel.selectAndroidDevice($0) }
                )
            }
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
                case .simulator, .androidDevice, .none:
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
            case .device, .androidDevice, .none:
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

    private func androidDevices(_ devices: [AndroidDevice]) -> some View {
        ForEach(devices, id: \.id) { device in
            let selected = switch viewModel.selectedDevice {
            case let .androidDevice(selectedDevice):
                device.id == selectedDevice.id
            case .simulator, .device, .none:
                false
            }

            return AndroidDeviceRow(
                device: device,
                selected: selected,
                pinned: viewModel.pinnedAndroidEmulators.contains(where: { $0.id == device.id })
            ) { device in
                viewModel.selectAndroidDevice(device)
            } onPinned: { device, pinned in
                viewModel.androidEmulatorPinned(device, pinned: pinned)
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
