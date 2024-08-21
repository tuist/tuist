import Command
import Foundation
import MockableTest
import TuistCore
import TuistSupport
import TuistSupportTesting

@testable import Tuist

final class SimulatorRowViewModelTests: TuistUnitTestCase {
    private var subject: SimulatorRowViewModel!
    private var simulatorController: MockSimulatorControlling!
    private var commandRunner: MockCommandRunning!

    private let iPhone15: SimulatorDeviceAndRuntime = .test(
        device: .test(
            udid: "iphone-15-id",
            name: "iPhone 15"
        )
    )

    override func setUp() {
        super.setUp()

        simulatorController = .init()
        commandRunner = .init()
        subject = SimulatorRowViewModel(
            simulatorController: simulatorController,
            commandRunner: commandRunner
        )
    }

    override func tearDown() {
        simulatorController = nil
        commandRunner = nil
        subject = nil

        super.tearDown()
    }

    func test_launchSimulator() async throws {
        // Given
        given(simulatorController)
            .booted(device: .any, forced: .any)
            .willReturn(.test())
        given(commandRunner)
            .run(
                arguments: .value(["open", "-a", "Simulator"]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                .init(
                    unfolding: {
                        nil
                    }
                )
            )

        // When / Then
        try await subject.launchSimulator(iPhone15)
    }
}
