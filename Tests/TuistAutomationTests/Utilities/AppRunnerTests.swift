import Foundation
import MockableTest
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistAutomation

final class AppRunnerTests: TuistUnitTestCase {
    private var subject: AppRunner!
    private var simulatorController: MockSimulatorControlling!
    private var userInputReader: MockUserInputReading!

    override func setUp() {
        super.setUp()

        simulatorController = .init()
        userInputReader = .init()
        subject = AppRunner(
            simulatorController: simulatorController,
            userInputReader: userInputReader
        )

        given(simulatorController)
            .launchApp(
                bundleId: .any,
                device: .any,
                arguments: .any
            )
            .willReturn()

        given(simulatorController)
            .booted(device: .any)
            .willProduce { $0 }

        Matcher.register([SimulatorDeviceAndRuntime].self)
    }

    override func tearDown() {
        subject = nil
        userInputReader = nil
        simulatorController = nil

        Matcher.reset()

        super.tearDown()
    }

    func test_run_single_app_bundle_with_one_currently_booted_device() async throws {
        // Given
        let appBundle: AppBundle = .test()
        let simulatorDeviceAndRuntime: SimulatorDeviceAndRuntime = .test(
            device: .test(state: "Booted")
        )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.iOS),
                version: .value(nil),
                minVersion: .value(Version("17.4.0")),
                deviceName: .value(nil)
            )
            .willReturn(
                [
                    simulatorDeviceAndRuntime,
                ]
            )

        given(simulatorController)
            .installApp(
                at: .value(appBundle.path),
                device: .value(simulatorDeviceAndRuntime.device)
            )
            .willReturn()

        // When
        try await subject.runApp(
            [appBundle],
            version: nil,
            device: nil
        )

        // Then
        verify(simulatorController)
            .launchApp(
                bundleId: .value(appBundle.infoPlist.bundleId),
                device: .value(simulatorDeviceAndRuntime.device),
                arguments: .value([])
            )
            .called(1)
    }

    func test_run_single_app_bundle_with_specific_device() async throws {
        // Given
        let appBundle: AppBundle = .test()
        let simulatorDeviceAndRuntime: SimulatorDeviceAndRuntime = .test(
            device: .test(name: "iPhone 15 Pro")
        )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.iOS),
                version: .value(nil),
                minVersion: .value(Version("17.4.0")),
                deviceName: .value("iPhone 15 Pro")
            )
            .willReturn(
                [
                    simulatorDeviceAndRuntime,
                ]
            )

        given(simulatorController)
            .installApp(
                at: .value(appBundle.path),
                device: .value(simulatorDeviceAndRuntime.device)
            )
            .willReturn()

        given(userInputReader)
            .readValue(
                asking: .any,
                values: .value([simulatorDeviceAndRuntime]),
                valueDescription: .any
            )
            .willReturn(simulatorDeviceAndRuntime)

        // When
        try await subject.runApp(
            [appBundle],
            version: nil,
            device: "iPhone 15 Pro"
        )

        // Then
        verify(simulatorController)
            .launchApp(
                bundleId: .value(appBundle.infoPlist.bundleId),
                device: .value(simulatorDeviceAndRuntime.device),
                arguments: .value([])
            )
            .called(1)
    }

    func test_run_single_app_bundle_with_specific_version() async throws {
        // Given
        let appBundle: AppBundle = .test()
        let simulatorDeviceAndRuntime: SimulatorDeviceAndRuntime = .test(
            device: .test(
                name: "iPhone 15 Pro"
            )
        )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.iOS),
                version: .value(Version("18.0.0")),
                minVersion: .value(Version("17.4.0")),
                deviceName: .value(nil)
            )
            .willReturn(
                [
                    simulatorDeviceAndRuntime,
                ]
            )

        given(simulatorController)
            .installApp(
                at: .value(appBundle.path),
                device: .value(simulatorDeviceAndRuntime.device)
            )
            .willReturn()

        given(userInputReader)
            .readValue(
                asking: .any,
                values: .value([simulatorDeviceAndRuntime]),
                valueDescription: .any
            )
            .willReturn(simulatorDeviceAndRuntime)

        // When
        try await subject.runApp(
            [appBundle],
            version: Version("18.0.0"),
            device: nil
        )

        // Then
        verify(simulatorController)
            .launchApp(
                bundleId: .value(appBundle.infoPlist.bundleId),
                device: .value(simulatorDeviceAndRuntime.device),
                arguments: .value([])
            )
            .called(1)
    }

    func test_run_single_app_bundle_with_multiple_booted_devices() async throws {
        // Given
        let appBundle: AppBundle = .test()
        let simulatorDeviceAndRuntimeOne: SimulatorDeviceAndRuntime = .test(
            device: .test(
                state: "Booted",
                name: "iPhone 15"
            )
        )
        let simulatorDeviceAndRuntimeTwo: SimulatorDeviceAndRuntime = .test(
            device: .test(
                state: "Booted",
                name: "iPhone 15 Pro"
            )
        )
        let simulatorDeviceAndRuntimeThree: SimulatorDeviceAndRuntime = .test(
            device: .test(
                state: "Shutdown",
                name: "iPhone 16 Pro"
            )
        )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.iOS),
                version: .value(nil),
                minVersion: .value(Version("17.4.0")),
                deviceName: .value(nil)
            )
            .willReturn(
                [
                    simulatorDeviceAndRuntimeOne,
                    simulatorDeviceAndRuntimeTwo,
                    simulatorDeviceAndRuntimeThree,
                ]
            )

        given(userInputReader)
            .readValue(
                asking: .any,
                values: .value([simulatorDeviceAndRuntimeOne, simulatorDeviceAndRuntimeTwo, simulatorDeviceAndRuntimeThree]),
                valueDescription: .any
            )
            .willReturn(simulatorDeviceAndRuntimeTwo)

        given(simulatorController)
            .installApp(
                at: .value(appBundle.path),
                device: .value(simulatorDeviceAndRuntimeTwo.device)
            )
            .willReturn()

        // When
        try await subject.runApp(
            [appBundle],
            version: nil,
            device: nil
        )

        // Then
        verify(simulatorController)
            .launchApp(
                bundleId: .value(appBundle.infoPlist.bundleId),
                device: .value(simulatorDeviceAndRuntimeTwo.device),
                arguments: .value([])
            )
            .called(1)
    }

    func test_run_mutliple_app_bundles_with_one_currently_booted_device() async throws {
        // Given
        let appBundleOne: AppBundle = .test(
            infoPlist: .test(
                supportedPlatforms: [
                    .simulator(.iOS),
                ]
            )
        )
        let appBundleTwo: AppBundle = .test(
            infoPlist: .test(
                supportedPlatforms: [
                    .simulator(.visionOS),
                ]
            )
        )
        let appBundleThree: AppBundle = .test(
            infoPlist: .test(
                supportedPlatforms: [
                    .device(.visionOS),
                ]
            )
        )
        let simulatorDeviceAndRuntime: SimulatorDeviceAndRuntime = .test(
            device: .test(
                state: "Booted"
            ),
            runtime: .test(
                name: "visionOS 2.0"
            )
        )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.visionOS),
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(
                [
                    simulatorDeviceAndRuntime,
                ]
            )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.iOS),
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn([.test()])

        given(simulatorController)
            .installApp(
                at: .value(appBundleTwo.path),
                device: .value(simulatorDeviceAndRuntime.device)
            )
            .willReturn()

        // When
        try await subject.runApp(
            [
                appBundleOne,
                appBundleTwo,
                appBundleThree,
            ],
            version: nil,
            device: nil
        )

        // Then
        verify(simulatorController)
            .launchApp(
                bundleId: .value(appBundleTwo.infoPlist.bundleId),
                device: .value(simulatorDeviceAndRuntime.device),
                arguments: .value([])
            )
            .called(1)
    }

    func test_run_mutliple_app_bundles_with_no_booted_device() async throws {
        // Given
        let appBundleOne: AppBundle = .test(
            infoPlist: .test(
                supportedPlatforms: [
                    .simulator(.iOS),
                ]
            )
        )
        let appBundleTwo: AppBundle = .test(
            infoPlist: .test(
                supportedPlatforms: [
                    .simulator(.visionOS),
                ]
            )
        )
        let appBundleThree: AppBundle = .test(
            infoPlist: .test(
                supportedPlatforms: [
                    .device(.visionOS),
                ]
            )
        )
        let visionOSSimulatorDeviceAndRuntime: SimulatorDeviceAndRuntime = .test(
            runtime: .test(
                name: "visionOS 2.0"
            )
        )

        let iOSSimulatorDeviceAndRuntime: SimulatorDeviceAndRuntime = .test(
            runtime: .test(
                name: "iOS 18.0"
            )
        )

        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.visionOS),
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(
                [
                    visionOSSimulatorDeviceAndRuntime,
                ]
            )
        given(simulatorController)
            .findAvailableDevices(
                platform: .value(.iOS),
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(
                [
                    iOSSimulatorDeviceAndRuntime,
                ]
            )

        given(userInputReader)
            .readValue(
                asking: .any,
                values: .value([iOSSimulatorDeviceAndRuntime, visionOSSimulatorDeviceAndRuntime]),
                valueDescription: .any
            )
            .willReturn(iOSSimulatorDeviceAndRuntime)

        given(simulatorController)
            .installApp(
                at: .value(appBundleTwo.path),
                device: .value(iOSSimulatorDeviceAndRuntime.device)
            )
            .willReturn()

        // When
        try await subject.runApp(
            [
                appBundleOne,
                appBundleTwo,
                appBundleThree,
            ],
            version: nil,
            device: nil
        )

        // Then
        verify(simulatorController)
            .launchApp(
                bundleId: .value(appBundleTwo.infoPlist.bundleId),
                device: .value(iOSSimulatorDeviceAndRuntime.device),
                arguments: .value([])
            )
            .called(1)
    }
}
