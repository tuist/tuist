import Foundation

public struct SimulatorDeviceAndRuntime: Hashable {
    /// Device
    let device: SimulatorDevice

    /// Device's runtime.
    let runtime: SimulatorRuntime
}
