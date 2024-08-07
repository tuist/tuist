import Foundation
import Path
@testable import TuistCore

extension SimulatorDeviceAndRuntime {
    public static func test(
        device: SimulatorDevice = .test(),
        runtime: SimulatorRuntime = .test()
    ) -> SimulatorDeviceAndRuntime {
        SimulatorDeviceAndRuntime(device: device, runtime: runtime)
    }
}
