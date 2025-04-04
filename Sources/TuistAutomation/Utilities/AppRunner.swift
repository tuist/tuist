import Foundation
import Mockable
import ServiceContextModule
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph

enum AppRunnerError: LocalizedError, Equatable {
    case invalidSimulatorPlatform(String)
    case selectedPlatformNotFound(String)
    case appNotFoundForPhysicalDevice(PhysicalDevice)

    var errorDescription: String? {
        switch self {
        case let .invalidSimulatorPlatform(platform):
            "The chosen simulator's platform \(platform) is invalid"
        case let .selectedPlatformNotFound(platform):
            "No app bundle for the selected platform \(platform) was found."
        case let .appNotFoundForPhysicalDevice(physicalDevice):
            "No app bundle for the device \(physicalDevice.name) was found."
        }
    }
}

@Mockable
public protocol AppRunning {
    func runApp(
        _ appBundles: [AppBundle],
        version: Version?,
        device: String?
    ) async throws
}

public struct AppRunner: AppRunning {
    private let simulatorController: SimulatorControlling
    private let deviceController: DeviceControlling

    public init() {
        self.init(
            simulatorController: SimulatorController(),
            deviceController: DeviceController()
        )
    }

    init(
        simulatorController: SimulatorControlling,
        deviceController: DeviceControlling
    ) {
        self.simulatorController = simulatorController
        self.deviceController = deviceController
    }

    public func runApp(
        _ appBundles: [AppBundle],
        version: Version?,
        device: String?
    ) async throws {
        if let device, let physicalDevice = try await deviceController.findAvailableDevices()
            .first(where: { $0.name == device })
        {
            try await runApp(
                on: physicalDevice,
                appBundles: appBundles
            )
        } else {
            try await runAppOnSimulator(
                appBundles,
                version: version,
                device: device
            )
        }
    }

    private func runApp(
        on physicalDevice: PhysicalDevice,
        appBundles: [AppBundle]
    ) async throws {
        guard let appBundle = appBundles.first(
            where: { appBundle in
                appBundle.infoPlist.supportedPlatforms.contains(.device(physicalDevice.platform))
            }
        ) else {
            throw AppRunnerError.appNotFoundForPhysicalDevice(physicalDevice)
        }

        try await deviceController.installApp(at: appBundle.path, device: physicalDevice)
        try await deviceController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: physicalDevice)
    }

    private func runAppOnSimulator(
        _ appBundles: [AppBundle],
        version: Version?,
        device: String?
    ) async throws {
        let simulatorPlatforms: [Platform] = appBundles
            .map(\.infoPlist)
            .flatMap(\.supportedPlatforms)
            .compactMap {
                switch $0 {
                case .device:
                    return nil
                case let .simulator(platform):
                    return platform
                }
            }

        let platformsWithVersions: [Platform: Version] = appBundles.reduce([:]) { acc, appBundle in
            var acc = acc
            for supportedPlatform in appBundle.infoPlist.supportedPlatforms {
                switch supportedPlatform {
                case .device:
                    continue
                case let .simulator(platform):
                    if let minimumVersion = acc[platform] {
                        acc[platform] = min(
                            minimumVersion,
                            Version(appBundle.infoPlist.minimumOSVersion)
                        )
                    } else {
                        acc[platform] = Version(appBundle.infoPlist.minimumOSVersion)
                    }
                }
            }
            return acc
        }

        let devices = try await simulatorPlatforms.concurrentMap { platform in
            try await simulatorController.findAvailableDevices(
                platform: platform,
                version: version,
                minVersion: platformsWithVersions[platform],
                deviceName: device
            )
        }
        .flatMap { $0 }

        let simulator: SimulatorDeviceAndRuntime
        let bootedDevices = devices.filter { !$0.device.isShutdown }
        if bootedDevices.count == 1, let bootedDevice = bootedDevices.first {
            simulator = bootedDevice
        } else {
            simulator = ServiceContext.current!.ui!.singleChoicePrompt(
                title: nil,
                question: "Select a simulator device",
                options: devices.sorted(by: {
                    if $0.device.isShutdown != $1.device.isShutdown {
                        if $0.device.isShutdown {
                            return false
                        } else {
                            return true
                        }
                    } else {
                        return $0.device.description < $1.device.description
                    }
                }),
                description: nil,
                collapseOnSelection: true,
                filterMode: .enabled,
                autoselectSingleChoice: true
            )
        }

        guard let platformName = simulator.runtime.name
            .components(separatedBy: " ").first,
            let simulatorPlatform = Platform(commandLineValue: platformName)
        else { throw AppRunnerError.invalidSimulatorPlatform(simulator.runtime.name) }

        guard let appBundle = appBundles.first(where: {
            $0.infoPlist.supportedPlatforms.contains(.simulator(simulatorPlatform))
        })
        else { throw AppRunnerError.selectedPlatformNotFound(simulatorPlatform.caseValue) }

        try await ServiceContext.current?.ui?.progressStep(
            message: "Installing \(appBundle.infoPlist.name) on \(simulator.device.name)",
            successMessage: "\(appBundle.infoPlist.name) was successfully launched 📲",
            errorMessage: nil,
            showSpinner: true
        ) { updateProgress in
            let device = try simulatorController.booted(device: simulator.device)
            try simulatorController.installApp(at: appBundle.path, device: device)
            updateProgress("Launching \(appBundle.infoPlist.name) on \(simulator.device.name)")
            try await simulatorController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: device, arguments: [])
        }
    }
}

extension Version {
    init(_ version: XcodeGraph.Version) {
        self.init(version.major, version.minor, version.patch)
    }
}

extension SimulatorDeviceAndRuntime: @retroactive CustomStringConvertible {
    public var description: String {
        let description = "\(device.name) \(device.udid)"
        if device.isShutdown {
            return description
        } else {
            return description + " (Booted)"
        }
    }
}
