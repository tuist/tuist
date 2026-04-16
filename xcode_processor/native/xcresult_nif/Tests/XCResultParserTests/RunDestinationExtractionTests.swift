import Foundation
import Testing
@testable import XCResultParser

struct RunDestinationExtractionTests {
    @Test
    func extractRunDestinations_withNilInput_returnsEmpty() {
        let result = XCResultParser.extractRunDestinations(from: nil)

        #expect(result.isEmpty)
    }

    @Test
    func extractRunDestinations_withEmptyArray_returnsEmpty() {
        let result = XCResultParser.extractRunDestinations(from: [])

        #expect(result.isEmpty)
    }

    @Test
    func extractRunDestinations_mapsAllRequiredFields() {
        let devices = [
            Device(
                architecture: "arm64",
                deviceId: "ABC",
                deviceName: "iPhone 17",
                modelName: "iPhone 17",
                osBuildNumber: "23E5218e",
                osVersion: "26.4",
                platform: "iOS Simulator"
            ),
        ]

        let result = XCResultParser.extractRunDestinations(from: devices)

        #expect(result.count == 1)
        #expect(result[0].name == "iPhone 17")
        #expect(result[0].platform == "iOS Simulator")
        #expect(result[0].osVersion == "26.4")
    }

    @Test
    func extractRunDestinations_preservesOrder() {
        let devices = [
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: "iPhone 17",
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "26.4",
                platform: "iOS Simulator"
            ),
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: "iPhone 17 Pro",
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "26.4",
                platform: "iOS Simulator"
            ),
        ]

        let result = XCResultParser.extractRunDestinations(from: devices)

        #expect(result.map(\.name) == ["iPhone 17", "iPhone 17 Pro"])
    }

    @Test
    func extractRunDestinations_dropsEntriesMissingDeviceName() {
        let devices = [
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: nil,
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "26.4",
                platform: "iOS Simulator"
            ),
        ]

        let result = XCResultParser.extractRunDestinations(from: devices)

        #expect(result.isEmpty)
    }

    @Test
    func extractRunDestinations_dropsEntriesMissingPlatform() {
        let devices = [
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: "iPhone 17",
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "26.4",
                platform: nil
            ),
        ]

        let result = XCResultParser.extractRunDestinations(from: devices)

        #expect(result.isEmpty)
    }

    @Test
    func extractRunDestinations_dropsEntriesMissingOSVersion() {
        let devices = [
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: "iPhone 17",
                modelName: nil,
                osBuildNumber: nil,
                osVersion: nil,
                platform: "iOS Simulator"
            ),
        ]

        let result = XCResultParser.extractRunDestinations(from: devices)

        #expect(result.isEmpty)
    }

    @Test
    func extractRunDestinations_keepsValidEntriesAlongsideInvalidOnes() {
        let devices = [
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: "iPhone 17",
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "26.4",
                platform: "iOS Simulator"
            ),
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: nil,
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "26.4",
                platform: "iOS Simulator"
            ),
            Device(
                architecture: nil,
                deviceId: nil,
                deviceName: "Apple Watch",
                modelName: nil,
                osBuildNumber: nil,
                osVersion: "11.0",
                platform: "watchOS Simulator"
            ),
        ]

        let result = XCResultParser.extractRunDestinations(from: devices)

        #expect(result.map(\.name) == ["iPhone 17", "Apple Watch"])
        #expect(result.map(\.platform) == ["iOS Simulator", "watchOS Simulator"])
    }
}
