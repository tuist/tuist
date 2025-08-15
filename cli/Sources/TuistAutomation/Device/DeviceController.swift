import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

enum DeviceControllerError: FatalError {
    case applicationVerificationFailed
    case fetchingDevicesFailed

    var description: String {
        switch self {
        case .applicationVerificationFailed:
            "The app could not be installed because the verification failed. Make sure that your device is registered in your Apple Developer account."
        case .fetchingDevicesFailed:
            "Fetching the list of devices failed."
        }
    }

    var type: ErrorType {
        switch self {
        case .applicationVerificationFailed, .fetchingDevicesFailed:
            .abort
        }
    }
}

/// Utility to interact with the `devicectl` CLI.
@Mockable
public protocol DeviceControlling {
    func findAvailableDevices() async throws -> [PhysicalDevice]
    func installApp(
        at path: AbsolutePath,
        device: PhysicalDevice
    ) async throws
    func launchApp(
        bundleId: String,
        device: PhysicalDevice
    ) async throws
}

public final class DeviceController: DeviceControlling {
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func findAvailableDevices() async throws -> [PhysicalDevice] {
        try await fileSystem.runInTemporaryDirectory(prefix: "device-controller-find-available-devices") { temporaryPath in
            let devicesListOutputPath = temporaryPath.appending(component: "devices-list-output-path.json")
            _ = try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "devicectl",
                    "list", "devices",
                    "--json-output", devicesListOutputPath.pathString,
                ]
            )
            .concatenatedString()

            let deviceList: DeviceList
            do {
                deviceList = try JSONDecoder().decode(
                    DeviceList.self,
                    from: try await fileSystem.readFile(at: devicesListOutputPath)
                )
            } catch {
                throw DeviceControllerError.fetchingDevicesFailed
            }

            return deviceList.result.devices
                .compactMap(PhysicalDevice.init)
        }
    }

    public func installApp(
        at path: AbsolutePath,
        device: PhysicalDevice
    ) async throws {
        Logger.current.debug("Installing app at \(path) on simulator device with id \(device.id)")
        do {
            _ = try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "devicectl",
                    "device", "install", "app",
                    "--device", device.id,
                    path.pathString,
                ]
            )
            .concatenatedString()
        } catch let error as CommandError {
            if case let .terminated(_, stderr) = error, stderr.contains("ApplicationVerificationFailed") {
                throw DeviceControllerError.applicationVerificationFailed
            } else {
                throw error
            }
        }
    }

    public func launchApp(
        bundleId: String,
        device: PhysicalDevice
    ) async throws {
        Logger.current
            .debug("Launching app with bundle id \(bundleId) on a physical device with id \(device.id)")
        _ = try await commandRunner.run(
            arguments: [
                "/usr/bin/xcrun", "devicectl",
                "device", "process", "launch",
                "--device", device.id,
                bundleId,
            ]
        )
        .concatenatedString()
    }
}

private struct DeviceList: Codable {
    let result: Result

    struct Result: Codable {
        let devices: [Device]

        struct Device: Codable {
            let connectionProperties: ConnectionProperties
            let deviceProperties: DeviceProperties
            let hardwareProperties: HardwareProperties
            let identifier: String

            struct ConnectionProperties: Codable {
                enum TransportType: String, Codable {
                    case localNetwork
                    case wired
                }

                enum TunnelState: String, Codable {
                    case connecting
                    case connected
                    case disconnected
                    case unavailable
                }

                let transportType: TransportType?
                let tunnelState: TunnelState?
            }

            struct DeviceProperties: Codable {
                let name: String?
                let osVersionNumber: String?
            }

            struct HardwareProperties: Codable {
                enum Platform: String, Codable {
                    case iOS
                    case tvOS
                    case watchOS
                    case visionOS
                }

                let udid: String?
                let platform: Platform?
            }
        }
    }
}

extension PhysicalDevice {
    fileprivate init?(_ device: DeviceList.Result.Device) {
        // Some properties from the `devicectl` can be `nil`.
        // However, when some properties, like the `platform`, are missing, we can't properly work with the device.
        // In those cases, we return `nil` here and filter such devices out before passing them to the caller.
        guard let udid = device.hardwareProperties.udid,
              let hardwarePlatform = device.hardwareProperties.platform,
              let name = device.deviceProperties.name
        else { return nil }
        let platform: Platform = switch hardwarePlatform {
        case .iOS: .iOS
        case .tvOS: .tvOS
        case .visionOS: .visionOS
        case .watchOS: .watchOS
        }

        let transportType: PhysicalDevice.TransportType? = switch device.connectionProperties.transportType {
        case .localNetwork: .wifi
        case .wired: .usb
        case .none: .none
        }

        let connectionState: PhysicalDevice.ConnectionState = switch device.connectionProperties.tunnelState {
        case .connected: .connected
        case .connecting, .disconnected, .unavailable, .none: .disconnected
        }

        self.init(
            id: udid,
            name: name,
            platform: platform,
            osVersion: device.deviceProperties.osVersionNumber,
            transportType: transportType,
            connectionState: connectionState
        )
    }
}
