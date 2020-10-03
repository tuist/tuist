import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistSupport

public protocol SimulatorControlling {
    /// Returns the list of simulator devices that are available in the system.
    func devices() -> Single<[SimulatorDevice]>

    /// Returns the list of simulator runtimes that are available in the system.
    func runtimes() -> Single<[SimulatorRuntime]>

    /// Returns the list of simulator devices and runtimes.
    func devicesAndRuntimes() -> Single<[SimulatorDeviceAndRuntime]>

    /// Returns an available device for a given platform
//    func findAvailableDevice(for platform: Platform) throws -> Single<SimulatorDevice>

    /// Boots a given simulator
//    func bootSimulator(_ simulator: SimulatorDevice) -> Completable

    /// Installs app built on a given simulator
//    func installAppBuilt(simulatorDevice: SimulatorDevice, appPath: AbsolutePath) -> Completable

    /// Launches a given app on a given simulator
//    func launchApp(simulator: SimulatorDevice, bundleId: String) -> Completable
}

public enum SimulatorControllerError: FatalError {
    case simctlError(String)

    public var type: ErrorType {
        switch self {
        case .simctlError: return .abort
        }
    }

    public var description: String {
        switch self {
        case let .simctlError(output): return output
        }
    }
}

public final class SimulatorController: SimulatorControlling {
    private let jsonDecoder: JSONDecoder = JSONDecoder()

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

//    public func findAvailableDevice(for platform: Platform) throws -> Single<SimulatorDevice> {
//        devices()
//            .flatMap { simulators -> Single<SimulatorDevice> in
//                if let simulator = simulators.filter({ $0.runtimeIdentifier.contains(platform.caseValue) && !($0.availabilityError != nil)}).first {
//                    return .just(simulator)
//                } else {
//                    return .error(SimulatorControllerError.simctlError("Couldn't find an available device for \(platform.caseValue)"))
//                }
//            }
//    }

//    public func bootSimulator(_ simulator: SimulatorDevice) -> Completable {
//        logger.log(level: .notice, "Booting \(simulator.description)", metadata: .section)
//        _ = try System.shared.observable(["/usr/bin/xcrun", "simctl", "boot", "\(simulator.udid)"])
//            .mapToString()
//            .toBlocking()
//            .last()
//    }

//    public func installAppBuilt(simulatorDevice: SimulatorDevice, appPath: AbsolutePath) -> Completable {
    // logger.log(level: .notice, "Installing \(target.name)", metadata: .section)
//        _ = try System.shared.observable(["/usr/bin/xcrun", "simctl", "install", "booted", "\(appPath!)"])
//            .mapToString()
//            .toBlocking()
//            .last()
//    }

//    public func launchApp(simulator: SimulatorDevice, bundleId: String) -> Completable {
//        logger.log(level: .notice, "Launching \(target.name)", metadata: .section)
//        _ = try System.shared.observable(["/usr/bin/xcrun", "simctl", "launch", "booted", "\(target.bundleId)"])
//            .mapToString()
//            .toBlocking()
//            .last()
//    }
}
