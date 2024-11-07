import Foundation
import TuistCore

extension SimulatorDeviceAndRuntime: @retroactive Comparable {
    public static func < (lhs: SimulatorDeviceAndRuntime, rhs: SimulatorDeviceAndRuntime) -> Bool {
        if lhs.device.name == rhs.device.name { return lhs.runtime.name < rhs.runtime.name }
        else { return lhs.device.name < rhs.device.name }
    }
}
