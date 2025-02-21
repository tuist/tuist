import Mockable
import ServiceContextModule
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph

enum AppRunnerError: FatalError, Equatable {
    case invalidSimulatorPlatform(String)
    case selectedPlatformNotFound(String)
    case appNotFoundForPhysicalDevice(PhysicalDevice)

    var description: String {
        switch self {
        case let .invalidSimulatorPlatform(platform):
            "The chosen simulator's platform \(platform) is invalid"
        case let .selectedPlatformNotFound(platform):
            "No app bundle for the selected platform \(platform) was found."
        case let .appNotFoundForPhysicalDevice(physicalDevice):
            "No app bundle for the device \(physicalDevice.name) was found."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidSimulatorPlatform, .appNotFoundForPhysicalDevice:
            return .abort
        case .selectedPlatformNotFound:
            return .bug
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

public final class AppRunner: AppRunning {
    private let simulatorController: SimulatorControlling
    private let deviceController: DeviceControlling
    private let userInputReader: UserInputReading

    public convenience init() {
        self.init(
            simulatorController: SimulatorController(),
            deviceController: DeviceController(),
            userInputReader: UserInputReader()
        )
    }

    init(
        simulatorController: SimulatorControlling,
        deviceController: DeviceControlling,
        userInputReader: UserInputReading
    ) {
        self.simulatorController = simulatorController
        self.deviceController = deviceController
        self.userInputReader = userInputReader
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
            try await self.simulatorController.findAvailableDevices(
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
            simulator = try userInputReader.readValue(
                asking: "Select the simulator device where you want to run the app:",
                values: devices,
                valueDescription: { "\($0.device.name) (\($0.device.udid))" }
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

        ServiceContext.current?.logger?.notice("Installing and launching \(appBundle.infoPlist.name) on \(simulator.device.name)")
        let device = try simulatorController.booted(device: simulator.device)
        try simulatorController.installApp(at: appBundle.path, device: device)
        try await simulatorController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: device, arguments: [])
        ServiceContext.current?.alerts?.append(.success(.alert("\(appBundle.infoPlist.name) was successfully launched 📲")))
    }
}

extension Version {
    init(_ version: XcodeGraph.Version) {
        self.init(version.major, version.minor, version.patch)
    }
}
