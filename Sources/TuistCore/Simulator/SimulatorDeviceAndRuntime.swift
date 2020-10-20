import Foundation

public struct SimulatorDeviceAndRuntime: Hashable {
    /// Device
    public let device: SimulatorDevice

    /// Device's runtime.
    public let runtime: SimulatorRuntime
}
