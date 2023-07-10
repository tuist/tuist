import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistGraph
import TuistSupport

public protocol SimulatorControlling {
    /// Finds first available device defined by given parameters
    /// - Parameters:
    ///     - platform: Given platform
    ///     - version: Specific version, ignored if nil
    ///     - minVersion: Minimum version of the OS
    ///     - deviceName: Specific device name (eg. iPhone X)
    func findAvailableDevice(
        platform: Platform,
        version: Version?,
        minVersion: Version?,
        deviceName: String?
    ) async throws -> SimulatorDeviceAndRuntime

    /// Installs an app on a given simulator.
    /// - Parameters:
    ///   - path: The path to the app to install in the simulator.
    ///   - device: The simulator device to install the app on.
    func installApp(at path: AbsolutePath, device: SimulatorDevice) throws

    /// Opens the simulator application & launches app on the given simulator.
    /// - Parameters:
    ///   - bundleId: The bundle id of the app to launch.
    ///   - device: The simulator device to install the app on.
    ///   - arguments: Any additional arguments to pass the app on launch.
    func launchApp(bundleId: String, device: SimulatorDevice, arguments: [String]) throws

    /// Finds the simulator destination for the target platform
    /// - Parameters:
    ///     - targetPlatform: Given platform
    ///     - version: Specific version, ignored if nil
    ///     - deviceName: Specific device name (eg. iPhone X)
    func destination(
        for targetPlatform: Platform,
        version: Version?,
        deviceName: String?
    ) async throws -> String

    /// Returns the simulator destination for the macOS platform
    func macOSDestination() -> String
}

public enum SimulatorControllerError: Equatable, FatalError {
    case simctlError(String)
    case deviceNotFound(Platform, Version?, String?, [SimulatorDeviceAndRuntime])
    case simulatorNotFound(udid: String)

    public var type: ErrorType {
        switch self {
        case .simctlError,
             .deviceNotFound,
             .simulatorNotFound:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .simctlError(output):
            return output
        case let .deviceNotFound(platform, version, deviceName, devices):
            return "Could not find a suitable device for \(platform.caseValue)\(version.map { " \($0)" } ?? "")\(deviceName.map { ", device name \($0)" } ?? ""). Did find \(devices.map { "\($0.device.name) (\($0.runtime.description))" }.joined(separator: ", "))"
        case let .simulatorNotFound(udid):
            return "Could not find simulator with UDID: \(udid)"
        }
    }
}

public final class SimulatorController: SimulatorControlling {
    private let jsonDecoder = JSONDecoder()

    public init() {}

    /// Returns the list of simulator devices that are available in the system.
    func devices() async throws -> [SimulatorDevice] {
        let output = try await System.shared.runAndCollectOutput(["/usr/bin/xcrun", "simctl", "list", "devices", "--json"])
        let data = output.standardOutput.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let devicesJSON = dictionary["devices"] as? [String: [[String: Any]]]
        else {
            return []
        }

        let devices = try devicesJSON.flatMap { runtimeIdentifier, devicesJSON -> [SimulatorDevice] in
            try devicesJSON.map { deviceJSON -> SimulatorDevice in
                var deviceJSON = deviceJSON
                deviceJSON["runtimeIdentifier"] = runtimeIdentifier
                let deviceJSONData = try JSONSerialization.data(withJSONObject: deviceJSON, options: [])
                return try self.jsonDecoder.decode(SimulatorDevice.self, from: deviceJSONData)
            }
        }
        return devices
    }

    /// Returns the list of simulator runtimes that are available in the system.
    func runtimes() async throws -> [SimulatorRuntime] {
        let output = try await System.shared.runAndCollectOutput(["/usr/bin/xcrun", "simctl", "list", "runtimes", "--json"])
        let data = output.standardOutput.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any],
              let runtimesJSON = dictionary["runtimes"] as? [Any]
        else {
            return []
        }

        let runtimesData = try JSONSerialization.data(withJSONObject: runtimesJSON, options: [])
        let runtimes = try self.jsonDecoder.decode([SimulatorRuntime].self, from: runtimesData)
        return runtimes
    }

    /// - Parameters:
    ///     - platform: Optionally filter by platform
    ///     - deviceName: Optionally filter by device name
    /// - Returns: the list of simulator devices and runtimes.
    func devicesAndRuntimes() async throws -> [SimulatorDeviceAndRuntime] {
        async let runtimesTask = runtimes()
        async let devicesTask = devices()
        let (runtimes, devices) = try await (runtimesTask, devicesTask)
        return devices.compactMap { device -> SimulatorDeviceAndRuntime? in
            guard let runtime = runtimes.first(where: { $0.identifier == device.runtimeIdentifier }) else { return nil }
            return SimulatorDeviceAndRuntime(device: device, runtime: runtime)
        }
    }

    public func findAvailableDevice(
        platform: Platform,
        version: Version?,
        minVersion: Version?,
        deviceName: String?
    ) async throws -> SimulatorDeviceAndRuntime {
        let devicesAndRuntimes = try await devicesAndRuntimes()
        let availableDevices = devicesAndRuntimes
            .sorted(by: { $0.runtime.version >= $1.runtime.version })
            .filter { simulatorDeviceAndRuntime in
                guard simulatorDeviceAndRuntime.device.isAvailable else { return false }
                let nameComponents = simulatorDeviceAndRuntime.runtime.name.components(separatedBy: " ")
                guard nameComponents.first == platform.caseValue else { return false }
                let deviceVersion = nameComponents.last?.version()
                if let version = version {
                    guard deviceVersion == version else { return false }
                } else if let minVersion = minVersion, let deviceVersion = deviceVersion {
                    guard deviceVersion >= minVersion else { return false }
                }
                if let deviceName = deviceName {
                    guard simulatorDeviceAndRuntime.device.name == deviceName else { return false }
                }
                return true
            }
        guard let device = availableDevices.first(where: { !$0.device.isShutdown }) ?? availableDevices.first
        else { throw SimulatorControllerError.deviceNotFound(platform, version, deviceName, devicesAndRuntimes) }
        return device
    }

    public func installApp(at path: AbsolutePath, device: SimulatorDevice) throws {
        logger.debug("Installing app at \(path) on simulator device with id \(device.udid)")
        let device = try device.booted()
        try System.shared.run(["/usr/bin/xcrun", "simctl", "install", device.udid, path.pathString])
    }

    public func launchApp(bundleId: String, device: SimulatorDevice, arguments: [String]) throws {
        logger.debug("Launching app with bundle id \(bundleId) on simulator device with id \(device.udid)")
        let device = try device.booted()
        try System.shared.run(["/usr/bin/open", "-a", "Simulator"])
        try System.shared.run(["/usr/bin/xcrun", "simctl", "launch", device.udid, bundleId] + arguments)
    }

    /// https://www.mokacoding.com/blog/xcodebuild-destination-options/
    /// https://www.mokacoding.com/blog/how-to-always-run-latest-simulator-cli/
    public func destination(
        for targetPlatform: Platform,
        version: Version?,
        deviceName: String?
    ) async throws -> String {
        var platform: Platform!
        switch targetPlatform {
        case .iOS: platform = .iOS
        case .watchOS: platform = .watchOS
        case .tvOS: platform = .tvOS
        case .visionOS: platform = .visionOS
        case .macOS:
            return macOSDestination()
        }

        let deviceAndRuntime = try await findAvailableDevice(
            platform: platform,
            version: version,
            minVersion: nil,
            deviceName: deviceName
        )
        return "id=\(deviceAndRuntime.device.udid)"
    }

    public func macOSDestination() -> String {
        let arch: String
        switch DeveloperEnvironment.shared.architecture {
        case .arm64:
            arch = "arm64"
        case .x8664:
            arch = "x86_64"
        }
        return "platform=macOS,arch=\(arch)"
    }
}

extension SimulatorDevice {
    /// Attempts to boot the simulator.
    /// - returns: The `SimulatorDevice` with updated `isShutdown` field.
    fileprivate func booted() throws -> Self {
        guard isShutdown else { return self }
        try System.shared.run(["/usr/bin/xcrun", "simctl", "boot", udid])
        return SimulatorDevice(
            dataPath: dataPath,
            logPath: logPath,
            udid: udid,
            isAvailable: isAvailable,
            deviceTypeIdentifier: deviceTypeIdentifier,
            state: "Booted",
            name: name,
            availabilityError: availabilityError,
            runtimeIdentifier: runtimeIdentifier
        )
    }
}
