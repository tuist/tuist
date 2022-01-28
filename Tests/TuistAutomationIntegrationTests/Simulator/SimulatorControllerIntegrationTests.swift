import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCore
@testable import TuistSupportTesting

final class SimulatorControllerIntegrationTests: TuistTestCase {
    var subject: SimulatorController!

    override func setUp() {
        super.setUp()
        subject = SimulatorController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_devices() async throws {
        // Given
        let got = try await subject.devices()

        // Then
        let devices = try XCTUnwrap(got)
        XCTAssertNotEmpty(devices)
    }

    func test_runtimes() async throws {
        // Given
        let got = try await subject.runtimes()

        // Then
        let runtimes = try XCTUnwrap(got)
        XCTAssertNotEmpty(runtimes)
    }

    func test_devicesAndRuntimes() async throws {
        // Given
        let got = try await subject.devicesAndRuntimes()

        // Then
        let runtimes = try XCTUnwrap(got)
        XCTAssertNotEmpty(runtimes)
    }

    func test_findAvailableDevice() async throws {
        // When
        let got = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: nil,
            deviceName: nil
        )

        // Then
        XCTAssertTrue(got.device.isAvailable)
    }
}
