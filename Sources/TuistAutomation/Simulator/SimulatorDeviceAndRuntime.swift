import Foundation

struct SimulatorDeviceAndRuntime: Hashable {
    /// Device
    let device: SimulatorDevice

    /// Device's runtime.
    let runtime: SimulatorRuntime
}
