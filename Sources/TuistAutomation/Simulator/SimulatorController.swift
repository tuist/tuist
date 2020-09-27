import Foundation
import RxSwift
import TuistSupport
import TuistCore
import struct TSCUtility.Version

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
        platform: Platform?,
        version: Version?,
        deviceName: String?
    ) -> Single<SimulatorDevice?>
}

enum SimulatorControllerError: FatalError {
    case simctlError(String)

    var type: ErrorType {
        switch self {
        case .simctlError: return .abort
        }
    }

    var description: String {
        switch self {
        case let .simctlError(output): return output
        }
    }
}

public final class SimulatorController: SimulatorControlling {
    public init() {}
    
    private let jsonDecoder: JSONDecoder = JSONDecoder()

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
            .debug()
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
        platform: Platform?,
        version: Version?,
        deviceName: String?
    ) -> Single<SimulatorDevice?> {
        devicesAndRuntimes()
            .map {
                let availableDevices = $0
                    .filter { simulatorDeviceAndRuntime in
                        let nameComponents = simulatorDeviceAndRuntime.runtime.name.components(separatedBy: " ")
                        if let platform = platform {
                            guard nameComponents.first == platform.caseValue else { return false }
                        }
                        if let version = version {
                            guard nameComponents.last?.version() == version else { return false }
                        }
                        if let deviceName = deviceName {
                            guard simulatorDeviceAndRuntime.device.name == deviceName else { return false }
                        }
                        return true
                }
                .map(\.device)
                return availableDevices.first(where: { !$0.isShutdown }) ?? availableDevices.first
        }
    }
}
