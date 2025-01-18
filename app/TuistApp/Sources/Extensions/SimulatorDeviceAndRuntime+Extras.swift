import Foundation
import TuistCore

#if swift(>=6)
extension SimulatorDeviceAndRuntime: @retroactive Comparable {
    public static func < (lhs: SimulatorDeviceAndRuntime, rhs: SimulatorDeviceAndRuntime) -> Bool {
        if lhs.device.name == rhs.device.name { return lhs.runtime.name < rhs.runtime.name }
        else { return lhs.device.name < rhs.device.name }
    }
}
#else
extension SimulatorDeviceAndRuntime: Comparable {
    public static func < (lhs: SimulatorDeviceAndRuntime, rhs: SimulatorDeviceAndRuntime) -> Bool {
        if lhs.device.name == rhs.device.name { return lhs.runtime.name < rhs.runtime.name }
        else { return lhs.device.name < rhs.device.name }
    }
}
#endif
