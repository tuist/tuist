import Foundation
import Mockable
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import TuistSupportTesting

@testable import TuistAutomation

struct AppRunnerTests {
    private let subject: AppRunner
    private let simulatorController = MockSimulatorControlling()
    private let deviceController = MockDeviceControlling()

    init() {
        subject = AppRunner(
            simulatorController: simulatorController,
            deviceController: deviceController
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

        given(deviceController)
            .findAvailableDevices()
            .willReturn([])

        Matcher.register([SimulatorDeviceAndRuntime].self)
    }

    @Test
    func test_run_single_app_bundle_with_one_currently_booted_device() async throws {
        try await withMockedDependencies {
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
    }

    @Test
    func test_run_single_app_bundle_with_specific_device() async throws {
        try await withMockedDependencies {
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
    }

    @Test
    func test_run_single_app_bundle_with_specific_version() async throws {
        try await withMockedDependencies {
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
    }

    @Test
    func test_run_mutliple_app_bundles_with_one_currently_booted_device() async throws {
        try await withMockedDependencies {
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
    }

    @Test
    func test_run_mutliple_app_bundles_with_physical_device_when_no_matching_bundle_exists() async throws {
        try await withMockedDependencies {
            // Given
            let iosSimulatorAppBundle: AppBundle = .test(
                infoPlist: .test(
                    supportedPlatforms: [
                        .simulator(.iOS),
                    ]
                )
            )
            let visionOSSimulatorAppBundle: AppBundle = .test(
                infoPlist: .test(
                    supportedPlatforms: [
                        .simulator(.visionOS),
                    ]
                )
            )

            deviceController.reset()

            let myVisionPro: PhysicalDevice = .test(
                name: "My Vision Pro",
                platform: .visionOS
            )
            given(deviceController)
                .findAvailableDevices()
                .willReturn(
                    [
                        myVisionPro,
                    ]
                )

            // When / Then
            await #expect(
                throws: AppRunnerError.appNotFoundForPhysicalDevice(myVisionPro)
            ) {
                try await subject.runApp(
                    [
                        iosSimulatorAppBundle,
                        visionOSSimulatorAppBundle,
                    ],
                    version: nil,
                    device: "My Vision Pro"
                )
            }
        }
    }

    @Test
    func test_run_mutliple_app_bundles_with_physical_device() async throws {
        try await withMockedDependencies {
            // Given
            let iosSimulatorAppBundle: AppBundle = .test(
                infoPlist: .test(
                    supportedPlatforms: [
                        .simulator(.iOS),
                    ]
                )
            )
            let visionOSSimulatorAppBundle: AppBundle = .test(
                infoPlist: .test(
                    supportedPlatforms: [
                        .simulator(.visionOS),
                    ]
                )
            )
            let visionOSDeviceAppBundle: AppBundle = .test(
                infoPlist: .test(
                    supportedPlatforms: [
                        .device(.visionOS),
                    ]
                )
            )

            deviceController.reset()

            let myVisionPro: PhysicalDevice = .test(
                name: "My Vision Pro",
                platform: .visionOS
            )
            given(deviceController)
                .findAvailableDevices()
                .willReturn(
                    [
                        myVisionPro,
                    ]
                )
            given(deviceController)
                .installApp(at: .any, device: .any)
                .willReturn()

            given(deviceController)
                .launchApp(bundleId: .any, device: .any)
                .willReturn()

            // When
            try await subject.runApp(
                [
                    iosSimulatorAppBundle,
                    visionOSSimulatorAppBundle,
                    visionOSDeviceAppBundle,
                ],
                version: nil,
                device: "My Vision Pro"
            )

            // Then
            verify(deviceController)
                .installApp(
                    at: .value(visionOSDeviceAppBundle.path),
                    device: .value(myVisionPro)
                )
                .called(1)

            verify(deviceController)
                .launchApp(
                    bundleId: .value(visionOSDeviceAppBundle.infoPlist.bundleId),
                    device: .value(myVisionPro)
                )
                .called(1)
        }
    }

    @Test
    func test_run_mutliple_app_bundles_with_no_booted_device() async throws {
        try await withMockedDependencies {
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
                    []
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
}
