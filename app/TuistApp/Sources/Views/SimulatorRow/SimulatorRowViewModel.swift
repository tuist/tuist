import Foundation
import TuistCore
import TuistSupport

@Observable
final class SimulatorRowViewModel {
    private let simulatorController: SimulatorControlling
    private let system: Systeming

    init(
        simulatorController: SimulatorControlling = SimulatorController(),
        system: Systeming = System.shared
    ) {
        self.simulatorController = simulatorController
        self.system = system
    }

    func launchSimulator(_ simulator: SimulatorDeviceAndRuntime) throws {
        _ = try simulatorController.booted(device: simulator.device, forced: true)
        try system.run(["open", "-a", "Simulator"])
    }
}
