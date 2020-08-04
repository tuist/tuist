import Foundation
import TSCBasic

/// It represents a simulator device. Devices are obtained using Xcode's CLI simctl
struct SimulatorDevice: Decodable, Hashable, CustomStringConvertible {
    /// Device data path.
    let dataPath: AbsolutePath

    /// Device log path.
    let logPath: AbsolutePath

    /// Device unique identifier (3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC)
    let udid: String

    /// Whether the device is available or not.
    let isAvailable: Bool

    /// Device type identifier (e.g. com.apple.CoreSimulator.SimDeviceType.iPad-Air--3rd-generation-)
    let deviceTypeIdentifier: String?

    /// Device state (e.g. Shutdown)
    let state: String

    /// Returns true if the device is shutdown.
    var isShutdown: Bool {
        state == "Shutdown"
    }

    /// Device name (e.g. iPad Air (3rd generation))
    let name: String

    /// If the device is not available, this provides a description of the error.
    let availabilityError: String?

    /// Device runtime identifier (e.g. com.apple.CoreSimulator.SimRuntime.iOS-13-5)
    let runtimeIdentifier: String

    var description: String {
        name
    }

    public init(dataPath: AbsolutePath,
                logPath: AbsolutePath,
                udid: String,
                isAvailable: Bool,
                deviceTypeIdentifier: String,
                state: String,
                name: String,
                availabilityError: String?,
                runtimeIdentifier: String)
    {
        self.dataPath = dataPath
        self.logPath = logPath
        self.udid = udid
        self.isAvailable = isAvailable
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.state = state
        self.name = name
        self.availabilityError = availabilityError
        self.runtimeIdentifier = runtimeIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case dataPath
        case logPath
        case udid
        case isAvailable
        case deviceTypeIdentifier
        case state
        case name
        case availabilityError
        case runtimeIdentifier
    }
}
