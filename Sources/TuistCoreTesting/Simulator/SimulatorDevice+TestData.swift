import Foundation
import TSCBasic
@testable import TuistCore

extension SimulatorDevice {
    static func test(
        dataPath: AbsolutePath = "/Library/Developer/CoreSimulator/Devices/3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC/data",
        logPath: AbsolutePath = "/Library/Logs/CoreSimulator/3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC",
        udid: String = "3A8C9673-C1FD-4E33-8EFA-AEEBF43161CC",
        isAvailable: Bool = true,
        deviceTypeIdentifier: String = "com.apple.CoreSimulator.SimDeviceType.iPad-Air--3rd-generation-",
        state: String = "Shutdown",
        name: String = "iPad Air (3rd generation)",
        availabilityError: String? = nil,
        runtimeIdentifier: String = "com.apple.CoreSimulator.SimRuntime.iOS-13-5"
    ) -> SimulatorDevice {
        SimulatorDevice(
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
