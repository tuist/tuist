import Foundation
import RxSwift
import struct TSCUtility.Version
import TuistCore
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

    func findAvailableDevice(
        platform: Platform,
        version: Version?,
        deviceName: String?
    ) -> Single<SimulatorDevice>
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

    public func findAvailableDevice(
        platform: Platform,
        version: Version?,
        deviceName: String?
    ) -> Single<SimulatorDevice> {
        devicesAndRuntimes()
            .flatMap { devicesAndRuntimes in
                let availableDevices = devicesAndRuntimes
                    .filter { simulatorDeviceAndRuntime in
                        let nameComponents = simulatorDeviceAndRuntime.runtime.name.components(separatedBy: " ")
                        guard nameComponents.first == platform.caseValue else { return false }
                        if let version = version {
                            guard nameComponents.last?.version() == version else { return false }
                        }
                        if let deviceName = deviceName {
                            guard simulatorDeviceAndRuntime.device.name == deviceName else { return false }
                        }
                        return true
                    }
                    .map(\.device)
                guard
                    let device = availableDevices.first(where: { !$0.isShutdown }) ?? availableDevices.first
                else { return .error(SimulatorControllerError.deviceNotFound(platform, version, deviceName, devicesAndRuntimes)) }

                return .just(device)
            }
    }
}
