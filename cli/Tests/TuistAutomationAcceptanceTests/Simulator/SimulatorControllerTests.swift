import Foundation
import Testing
import TuistSupport

@testable import TuistCore
@testable import TuistTesting

struct SimulatorControllerTests {
    @Test func devices() async throws {
        // Given
        let subject = SimulatorController()
        let got = try await subject.devices()

        // Then
        let devices = try #require(got)
        #expect(devices.isEmpty == false)
    }

    @Test func runtimes() async throws {
        // Given
        let subject = SimulatorController()
        let got = try await subject.runtimes()

        // Then
        let runtimes = try #require(got)
        #expect(runtimes.isEmpty == false)
    }

    @Test func devicesAndRuntimes() async throws {
        // Given
        let subject = SimulatorController()
        let got = try await subject.devicesAndRuntimes()

        // Then
        let runtimes = try #require(got)
        #expect(runtimes.isEmpty == false)
    }

    @Test func findAvailableDevice() async throws {
        // When
        let subject = SimulatorController()
        let got = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: nil,
            deviceName: nil
        )

        // Then
        #expect(got.device.isAvailable)
    }
}
