import Command
import FileSystem
import Foundation
import SwiftUI
import TuistAppStorage
import TuistAutomation
import TuistCore
import TuistServer
import TuistSimulator
import TuistSupport
import XcodeGraph

enum SimulatorsViewModelError: FatalError, Equatable {
    case noSelectedSimulator
    case invalidDeeplink(String)
    case appNotFound(Device, [DestinationType])

    var description: String {
        switch self {
        case .noSelectedSimulator:
            return "To run a preview, you must have a simulator selected."
        case let .appNotFound(device, destinations):
            let name: String
            let platform: String
            switch device {
            case let .simulator(simulator):
                name = simulator.device.name
                platform = (try? simulator.runtime.platform().caseValue) ?? simulator.runtime.name
            case let .device(device):
                name = device.name
                platform = device.platform.caseValue
            }
            let platforms = destinations.map {
                switch $0 {
                case let .device(platform):
                    return platform.caseValue
                case let .simulator(platform):
                    return "\(platform.caseValue) simulator"
                }
            }
            if platforms.isEmpty {
                return "Couldn't install the app for \(name) as it doesn't include any valid app builds."
            } else {
                return "Couldn't install the app for \(name). The \(name)'s platform is \(platform) and the app includes only the following platforms: \(platforms.joined(separator: ", "))"
            }
        case let .invalidDeeplink(deeplink):
            return "The preview deeplink \(deeplink) is invalid."
        }
    }

    var type: ErrorType {
        switch self {
        case .noSelectedSimulator, .appNotFound, .invalidDeeplink:
            return .abort
        }
    }
}

struct PinnedSimulatorsKey: AppStorageKey {
    static let key = "pinnedSimulators"
    static let defaultValue: [SimulatorDeviceAndRuntime] = []
}

struct SelectedDeviceKey: AppStorageKey {
    static let key = "selectedDevice"
    static let defaultValue: SelectedDevice? = nil
}

enum Device: Codable, Equatable {
    case simulator(SimulatorDeviceAndRuntime)
    case device(PhysicalDevice)
}

enum SelectedDevice: Codable, Equatable {
    case simulator(id: String)
    case device(id: String)
}

@Observable
final class DevicesViewModel: Sendable {
    var devices: [PhysicalDevice] {
        deviceService.devices
    }

    var connectedDevices: [PhysicalDevice] {
        devices.filter { $0.connectionState == .connected }
    }

    var disconnectedDevices: [PhysicalDevice] {
        devices.filter { $0.connectionState == .disconnected }
    }

    var simulators: [SimulatorDeviceAndRuntime] {
        deviceService.simulators
    }

    private(set) var pinnedSimulators: [SimulatorDeviceAndRuntime] = []
    var unpinnedSimulators: [SimulatorDeviceAndRuntime] {
        Set(simulators)
            .subtracting(Set(pinnedSimulators))
            .map { $0 }
            .sorted()
    }

    var selectedDevice: Device? {
        deviceService.selectedDevice
    }

    private(set) var isRefreshing: Bool = false

    private let deviceService: any DeviceServicing
    private let appStorage: AppStoring

    init(
        deviceService: any DeviceServicing,
        appStorage: AppStoring = AppStorage()
    ) {
        self.deviceService = deviceService
        self.appStorage = appStorage
    }

    @MainActor func selectSimulator(_ simulator: SimulatorDeviceAndRuntime) {
        deviceService.selectDevice(.simulator(simulator))
    }

    @MainActor func selectPhysicalDevice(_ device: PhysicalDevice) {
        deviceService.selectDevice(.device(device))
    }

    func simulatorPinned(_ simulator: SimulatorDeviceAndRuntime, pinned: Bool) {
        if pinned {
            pinnedSimulators = (pinnedSimulators + [simulator]).sorted()
        } else {
            pinnedSimulators = pinnedSimulators.filter { $0.id != simulator.id }
        }
        try? appStorage.set(PinnedSimulatorsKey.self, value: pinnedSimulators)
    }

    func refreshDevices() async throws {
        isRefreshing = true
        defer { isRefreshing = false }
        try await deviceService.loadDevices()
    }

    func onAppear() throws {
        pinnedSimulators = try appStorage.get(PinnedSimulatorsKey.self)
    }
}
