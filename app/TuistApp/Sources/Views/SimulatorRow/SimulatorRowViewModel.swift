import Command
import Foundation
import TuistCore
import TuistSupport

@Observable
final class SimulatorRowViewModel {
    private let simulatorController: SimulatorControlling
    private let commandRunner: CommandRunning

    init(
        simulatorController: SimulatorControlling = SimulatorController(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.simulatorController = simulatorController
        self.commandRunner = commandRunner
    }

    func launchSimulator(_ simulator: SimulatorDeviceAndRuntime) async throws {
        _ = try simulatorController.booted(device: simulator.device, forced: true)
        _ = try await commandRunner.run(arguments: ["open", "-a", "Simulator"]).concatenatedString()
    }
}
