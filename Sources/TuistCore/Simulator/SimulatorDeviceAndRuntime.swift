import Foundation

public struct SimulatorDeviceAndRuntime: Identifiable, Hashable {
    public var id: String {
        device.udid
    }
    
    /// Device
    public let device: SimulatorDevice

    /// Device's runtime.
    public let runtime: SimulatorRuntime
}
