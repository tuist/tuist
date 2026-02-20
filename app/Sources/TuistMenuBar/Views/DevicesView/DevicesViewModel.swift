import Command
import FileSystem
import Foundation
import SwiftUI
import TuistAndroid
import TuistAppStorage
import TuistAutomation
import TuistCore
import TuistLogging
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
            case let .androidDevice(androidDevice):
                name = androidDevice.name
                platform = "Android"
            }
            let platforms = destinations.map {
                switch $0 {
                case let .device(platform):
                    return platform.caseValue
                case let .simulator(platform):
                    return "\(platform.caseValue) simulator"
                case .android:
                    return "Android"
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

struct PinnedAndroidDevicesKey: AppStorageKey {
    static let key = "pinnedAndroidDevices"
    static let defaultValue: [AndroidDevice] = []
}

struct SelectedDeviceKey: AppStorageKey {
    static let key = "selectedDevice"
    static let defaultValue: SelectedDevice? = nil
}

enum Device: Codable, Equatable {
    case simulator(SimulatorDeviceAndRuntime)
    case device(PhysicalDevice)
    case androidDevice(AndroidDevice)
}

enum SelectedDevice: Codable, Equatable {
    case simulator(id: String)
    case device(id: String)
    case androidDevice(id: String)
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

    var androidDevices: [AndroidDevice] {
        deviceService.androidDevices
    }

    var androidPhysicalDevices: [AndroidDevice] {
        androidDevices.filter { $0.type == .device }
    }

    var androidEmulators: [AndroidDevice] {
        androidDevices.filter { $0.type == .emulator }
    }

    private(set) var pinnedSimulators: [SimulatorDeviceAndRuntime] = []
    var unpinnedSimulators: [SimulatorDeviceAndRuntime] {
        Set(simulators)
            .subtracting(Set(pinnedSimulators))
            .map { $0 }
            .sorted()
    }

    private(set) var pinnedAndroidEmulators: [AndroidDevice] = []
    var unpinnedAndroidEmulators: [AndroidDevice] {
        Set(androidEmulators)
            .subtracting(Set(pinnedAndroidEmulators))
            .sorted(by: { $0.name < $1.name })
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

    @MainActor func selectAndroidDevice(_ device: AndroidDevice) {
        deviceService.selectDevice(.androidDevice(device))
    }

    func simulatorPinned(_ simulator: SimulatorDeviceAndRuntime, pinned: Bool) {
        if pinned {
            pinnedSimulators = (pinnedSimulators + [simulator]).sorted()
        } else {
            pinnedSimulators = pinnedSimulators.filter { $0.id != simulator.id }
        }
        try? appStorage.set(PinnedSimulatorsKey.self, value: pinnedSimulators)
    }

    func androidEmulatorPinned(_ device: AndroidDevice, pinned: Bool) {
        if pinned {
            pinnedAndroidEmulators = (pinnedAndroidEmulators + [device]).sorted(by: { $0.name < $1.name })
        } else {
            pinnedAndroidEmulators = pinnedAndroidEmulators.filter { $0.id != device.id }
        }
        try? appStorage.set(PinnedAndroidDevicesKey.self, value: pinnedAndroidEmulators)
    }

    func refreshDevices() async throws {
        isRefreshing = true
        defer { isRefreshing = false }
        try await deviceService.loadDevices()
    }

    func onAppear() throws {
        pinnedSimulators = try appStorage.get(PinnedSimulatorsKey.self)
        pinnedAndroidEmulators = try appStorage.get(PinnedAndroidDevicesKey.self)
    }
}
