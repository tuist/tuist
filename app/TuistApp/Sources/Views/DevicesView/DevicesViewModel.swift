import Command
import FileSystem
import Foundation
import SwiftUI
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

enum SimulatorsViewModelError: FatalError, Equatable {
    case noSelectedSimulator
    case invalidDeeplink(String)
    case invalidDownloadURL(String)
    case appNotFound(Device, [Platform])

    var description: String {
        switch self {
        case .noSelectedSimulator:
            return "To run a preview, you must have a simulator selected."
        case let .invalidDownloadURL(url):
            return "The preview download url \(url) is invalid."
        case let .appNotFound(device, platforms):
            let name: String
            let platform: String
            switch device {
            case let .simulator(simulator):
                name = simulator.device.name
                platform = simulator.runtime.platform?.caseValue ?? simulator.runtime.name
            case let .device(device):
                name = device.name
                platform = device.platform.caseValue
            }
            return "Couldn't install the app for \(name). The \(name)'s platform is \(platform) and the app includes only the following platforms: \(platforms.map(\.caseValue).joined(separator: ", "))"
        case let .invalidDeeplink(deeplink):
            return "The preview deeplink \(deeplink) is invalid."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidDownloadURL:
            return .bug
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
