import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistSupportTesting

final class SimulatorControllerIntegrationTests: TuistTestCase {
    var subject: SimulatorController!

    override func setUp() {
        subject = SimulatorController()
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_devices() throws {
        // Given
        let got = try subject.devices().toBlocking().last()

        // Then
        let devices = try XCTUnwrap(got)
        XCTAssertNotEmpty(devices)
    }

    func test_runtimes() throws {
        // Given
        let got = try subject.runtimes().toBlocking().last()

        // Then
        let runtimes = try XCTUnwrap(got)
        XCTAssertNotEmpty(runtimes)
    }

    func test_devicesAndRuntimes() throws {
        // Given
        let got = try subject.devicesAndRuntimes().toBlocking().last()

        // Then
        let runtimes = try XCTUnwrap(got)
        XCTAssertNotEmpty(runtimes)
    }

    func test_findAvailableDevice() throws {
        // When
        let got = try subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: nil,
            deviceName: nil
        )
        .toBlocking()
        .single()

        // Then
        XCTAssertTrue(got.isAvailable)
    }
}
