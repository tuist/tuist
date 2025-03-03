import Foundation
import Path
import TuistSupport

/// It represents a simulator device. Devices are obtained using Xcode's CLI simctl
public struct SimulatorDevice: Codable, Hashable, CustomStringConvertible, Equatable {
    /// Device data path.
    public let dataPath: AbsolutePath

    /// Device log path.
    public let logPath: AbsolutePath

    /// Device unique identifier (3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC)
    public let udid: String

    /// Whether the device is available or not.
    public let isAvailable: Bool

    /// Device type identifier (e.g. com.apple.CoreSimulator.SimDeviceType.iPad-Air--3rd-generation-)
    public let deviceTypeIdentifier: String?

    /// Device state (e.g. Shutdown)
    public let state: String

    /// Returns true if the device is shutdown.
    public var isShutdown: Bool {
        state == "Shutdown"
    }

    /// Device name (e.g. iPad Air (3rd generation))
    public let name: String

    /// If the device is not available, this provides a description of the error.
    public let availabilityError: String?

    /// Device runtime identifier (e.g. com.apple.CoreSimulator.SimRuntime.iOS-13-5)
    public let runtimeIdentifier: String

    public var description: String {
        name
    }

    public init(
        dataPath: AbsolutePath,
        logPath: AbsolutePath,
        udid: String,
        isAvailable: Bool,
        deviceTypeIdentifier: String?,
        state: String,
        name: String,
        availabilityError: String?,
        runtimeIdentifier: String
    ) {
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
}

#if DEBUG
    extension SimulatorDevice {
        public static func test(
            dataPath: AbsolutePath = "/Library/Developer/CoreSimulator/Devices/3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC/data",
            logPath: AbsolutePath = "/Library/Logs/CoreSimulator/3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC",
            udid: String = "3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC",
            isAvailable: Bool = true,
            deviceTypeIdentifier: String = "com.apple.CoreSimulator.SimDeviceType.iPad-Air--3rd-generation-",
            state: String = "Shutdown",
            name: String = "iPad Air (3rd generation)",
            availabilityError: String? = nil,
            runtimeIdentifier: String = "com.apple.CoreSimulator.SimRuntime.iOS-13-5"
        ) -> Self {
            Self(
                dataPath: dataPath,
                logPath: logPath,
                udid: udid,
                isAvailable: isAvailable,
                deviceTypeIdentifier: deviceTypeIdentifier,
                state: state,
                name: name,
                availabilityError: availabilityError,
                runtimeIdentifier: runtimeIdentifier
            )
        }
    }
#endif
