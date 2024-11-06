import Foundation
import TuistCore

extension [SimulatorDeviceAndRuntime] {
    func sorted() -> Self {
        sorted(by: {
            if $0.device.name == $1.device.name { return $0.runtime.name < $1.runtime.name }
            else { return $0.device.name < $1.device.name }
        })
    }
}
