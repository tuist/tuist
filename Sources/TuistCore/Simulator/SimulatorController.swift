import Foundation
import RxSwift
import struct TSCUtility.Version
import TuistSupport

public protocol SimulatorControlling {
    /// Returns the list of simulator devices that are available in the system.
    func devices() -> Single<[SimulatorDevice]>

    /// Returns the list of simulator runtimes that are available in the system.
    func runtimes() -> Single<[SimulatorRuntime]>

    /// - Parameters:
    ///     - platform: Optionally filter by platform
    ///     - deviceName: Optionally filter by device name
    /// - Returns: the list of simulator devices and runtimes.
    func devicesAndRuntimes() -> Single<[SimulatorDeviceAndRuntime]>

    /// Find an available device for the given platform.
    /// Available devices are sorted by their runtime version, meaning the ones with higher runtime
    /// will be preferred over the ones with a lower runtime.
    /// - Parameter platform: Platform.
    func findAvailableDevice(platform: Platform) -> Single<SimulatorDeviceAndRuntime>

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
    ) -> Single<SimulatorDeviceAndRuntime>
}

public enum SimulatorControllerError: FatalError {
    case simctlError(String)
    case deviceNotFound(Platform, Version?, String?, [SimulatorDeviceAndRuntime])

    public var type: ErrorType {
        switch self {
        case .simctlError, .deviceNotFound:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .simctlError(output):
            return output
        case let .deviceNotFound(platform, version, deviceName, devices):
            return "Could not find a suitable device for \(platform.caseValue)\(version.map { " \($0)" } ?? "")\(deviceName.map { ", device name \($0)" } ?? ""). Did find \(devices.map { "\($0.device.name) (\($0.runtime.description))" }.joined(separator: ", "))"
        }
    }
}

public final class SimulatorController: SimulatorControlling {
    private let jsonDecoder = JSONDecoder()

    public init() {}

    public func devices() -> Single<[SimulatorDevice]> {
        System.shared.observable(["/usr/bin/xcrun", "simctl", "list", "devices", "--json"])
            .mapToString()
            .collectOutput()
            .asSingle()
            .flatMap { output in
                do {
                    let data = output.standardOutput.data(using: .utf8)!
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let dictionary = json as? [String: Any],
                        let devicesJSON = dictionary["devices"] as? [String: [[String: Any]]]
                    else {
                        return .just([])
                    }

                    let devices = try devicesJSON.flatMap { (runtimeIdentifier, devicesJSON) -> [SimulatorDevice] in
                        try devicesJSON.map { (deviceJSON) -> SimulatorDevice in
                            var deviceJSON = deviceJSON
                            deviceJSON["runtimeIdentifier"] = runtimeIdentifier
                            let deviceJSONData = try JSONSerialization.data(withJSONObject: deviceJSON, options: [])
                            return try self.jsonDecoder.decode(SimulatorDevice.self, from: deviceJSONData)
                        }
                    }

                    return .just(devices)
                } catch {
                    return .error(error)
                }
            }
    }

    public func runtimes() -> Single<[SimulatorRuntime]> {
        System.shared.observable(["/usr/bin/xcrun", "simctl", "list", "runtimes", "--json"])
            .mapToString()
            .collectOutput()
            .asSingle()
            .flatMap { output in
                do {
                    let data = output.standardOutput.data(using: .utf8)!
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let dictionary = json as? [String: Any],
                        let runtimesJSON = dictionary["runtimes"] as? [Any]
                    else {
                        return .just([])
                    }

                    let runtimesData = try JSONSerialization.data(withJSONObject: runtimesJSON, options: [])
                    let runtimes = try self.jsonDecoder.decode([SimulatorRuntime].self, from: runtimesData)
                    return .just(runtimes)
                } catch {
                    return .error(error)
                }
            }
    }

    public func devicesAndRuntimes() -> Single<[SimulatorDeviceAndRuntime]> {
        runtimes()
            .flatMap { (runtimes) -> Single<([SimulatorDevice], [SimulatorRuntime])> in
                self.devices().map { ($0, runtimes) }
            }
            .map { (input) -> [SimulatorDeviceAndRuntime] in
                input.0.compactMap { (device) -> SimulatorDeviceAndRuntime? in
                    guard let runtime = input.1.first(where: { $0.identifier == device.runtimeIdentifier }) else { return nil }
                    return SimulatorDeviceAndRuntime(device: device, runtime: runtime)
                }
            }
    }

    public func findAvailableDevice(platform: Platform) -> Single<SimulatorDeviceAndRuntime> {
        self.findAvailableDevice(platform: platform, version: nil, minVersion: nil, deviceName: nil)
    }

    public func findAvailableDevice(
        platform: Platform,
        version: Version?,
        minVersion: Version?,
        deviceName: String?
    ) -> Single<SimulatorDeviceAndRuntime> {
        devicesAndRuntimes()
            .flatMap { devicesAndRuntimes in
                let availableDevices = devicesAndRuntimes
                    .sorted(by: { $0.runtime.version >= $1.runtime.version })
                    .filter { simulatorDeviceAndRuntime in
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
                guard
                    let device = availableDevices.first(where: { !$0.device.isShutdown }) ?? availableDevices.first
                else { return .error(SimulatorControllerError.deviceNotFound(platform, version, deviceName, devicesAndRuntimes)) }

                return .just(device)
            }
    }
}
