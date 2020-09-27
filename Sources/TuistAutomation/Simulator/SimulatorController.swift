import Foundation
import RxSwift
import TuistSupport

protocol SimulatorControlling {
    /// Returns the list of simulator devices that are available in the system.
    func devices() -> Single<[SimulatorDevice]>

    /// Returns the list of simulator runtimes that are available in the system.
    func runtimes() -> Single<[SimulatorRuntime]>

    /// Returns the list of simulator devices and runtimes.
    func devicesAndRuntimes() -> Single<[SimulatorDeviceAndRuntime]>
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

final class SimulatorController: SimulatorControlling {
    private let jsonDecoder: JSONDecoder = JSONDecoder()

    func devices() -> Single<[SimulatorDevice]> {
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

    func runtimes() -> Single<[SimulatorRuntime]> {
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

    func devicesAndRuntimes() -> Single<[SimulatorDeviceAndRuntime]> {
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
}
