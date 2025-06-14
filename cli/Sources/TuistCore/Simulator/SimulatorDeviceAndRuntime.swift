import Foundation

public struct SimulatorDeviceAndRuntime: Codable, Identifiable, Hashable, Equatable, Sendable {
    public var id: String {
        device.udid
    }

    /// Device
    public let device: SimulatorDevice

    /// Device's runtime.
    public let runtime: SimulatorRuntime
}

#if DEBUG
    extension SimulatorDeviceAndRuntime {
        public static func test(
            device: SimulatorDevice = .test(),
            runtime: SimulatorRuntime = .test()
        ) -> Self {
            Self(
                device: device,
                runtime: runtime
            )
        }
    }
#endif
