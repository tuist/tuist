import FileSystem
import Foundation
import Mockable
import Path
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph

enum AppRunnerError: FatalError, Equatable {
    case invalidSimulatorPlatform(String)
    case selectedPlatformNotFound(String)

    var description: String {
        switch self {
        case let .invalidSimulatorPlatform(platform):
            "The chosen simulator's platform \(platform) is invalid"
        case let .selectedPlatformNotFound(platform):
            "No app bundle for the selected platform \(platform) was found."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidSimulatorPlatform:
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
    private let userInputReader: UserInputReading

    public convenience init() {
        self.init(
            simulatorController: SimulatorController(),
            userInputReader: UserInputReader()
        )
    }

    init(
        simulatorController: SimulatorControlling,
        userInputReader: UserInputReading
    ) {
        self.simulatorController = simulatorController
        self.userInputReader = userInputReader
    }

    public func runApp(
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

        logger.notice("Installing and launching \(appBundle.infoPlist.name) on \(simulator.device.name)")
        let device = try simulatorController.booted(device: simulator.device)
        try simulatorController.installApp(at: appBundle.path, device: device)
        try simulatorController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: device, arguments: [])
        logger.notice("\(appBundle.infoPlist.name) was successfully launched 📲", metadata: .success)
    }
}

extension Version {
    init(_ version: XcodeGraph.Version) {
        self.init(version.major, version.minor, version.patch)
    }
}
