import Foundation
import MockableTest
import TuistCore
import TuistSupport
import TuistSupportTesting

@testable import Tuist

final class SimulatorRowViewModelTests: TuistUnitTestCase {
    private var subject: SimulatorRowViewModel!
    private var simulatorController: MockSimulatorControlling!

    private let iPhone15: SimulatorDeviceAndRuntime = .test(
        device: .test(
            udid: "iphone-15-id",
            name: "iPhone 15"
        )
    )

    override func setUp() {
        super.setUp()

        simulatorController = .init()
        subject = SimulatorRowViewModel(
            simulatorController: simulatorController,
            system: system
        )
    }

    override func tearDown() {
        simulatorController = nil
        subject = nil

        super.tearDown()
    }

    func test_launchSimulator() throws {
        // Given
        given(simulatorController)
            .booted(device: .any, forced: .any)
            .willReturn(.test())
        system.succeedCommand(
            [
                "open",
                "-a",
                "Simulator",
            ]
        )

        // When / Then
        try subject.launchSimulator(iPhone15)
    }
}
