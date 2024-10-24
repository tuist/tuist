import Foundation
import Mockable
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import Tuist

final class DevicesViewModelTests: TuistUnitTestCase {
    private var subject: DevicesViewModel!
    private var simulatorController: MockSimulatorControlling!
    private var downloadPreviewService: MockDownloadPreviewServicing!
    private var fileUnarchiver: MockFileUnarchiving!
    private var remoteArtifactDownloader: MockRemoteArtifactDownloading!
    private var appBundleLoader: MockAppBundleLoading!
    private var appStorage: MockAppStoring!
    private var deviceController: MockDeviceControlling!

    private let previewURL =
        URL(
            string: "tuist:open-preview?server_url=https://cloud.tuist.io&preview_id=01912892-3778-7297-8ca9-d66ac7ee2a53&full_handle=tuist/ios_app_with_frameworks"
        )!

    private let iPhone15: SimulatorDeviceAndRuntime = .test(
        device: .test(
            udid: "iphone-15-id",
            name: "iPhone 15"
        )
    )
    private let iPhone15Pro: SimulatorDeviceAndRuntime = .test(
        device: .test(
            udid: "iphone-15-pro-id",
            name: "iPhone 15 Pro"
        )
    )
    private let appleTV: SimulatorDeviceAndRuntime = .test(
        device: .test(
            udid: "apple-tv-id",
            name: "Apple TV"
        )
    )

    override func setUp() {
        super.setUp()

        simulatorController = .init()
        downloadPreviewService = .init()
        let fileArchiverFactory = MockFileArchivingFactorying()
        remoteArtifactDownloader = .init()
        appBundleLoader = .init()
        appStorage = .init()
        deviceController = .init()

        subject = DevicesViewModel(
            deviceController: deviceController,
            simulatorController: simulatorController,
            downloadPreviewService: downloadPreviewService,
            fileArchiverFactory: fileArchiverFactory,
            remoteArtifactDownloader: remoteArtifactDownloader,
            fileSystem: fileSystem,
            appBundleLoader: appBundleLoader,
            appStorage: appStorage
        )

        given(deviceController)
            .findAvailableDevices()
            .willReturn([])

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(.simulator(id: iPhone15.id))

        given(appStorage)
            .set(.any as Parameter<SelectedDeviceKey.Type>, value: .any)
            .willReturn()

        given(simulatorController)
            .devicesAndRuntimes()
            .willReturn(
                [
                    iPhone15,
                    iPhone15Pro,
                    appleTV,
                ]
            )

        given(deviceController)
            .installApp(at: .any, device: .any)
            .willReturn()

        given(deviceController)
            .launchApp(
                bundleId: .any,
                device: .any
            )
            .willReturn()

        fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        Matcher.register(SimulatorDeviceAndRuntime?.self)
        Matcher.register([SimulatorDeviceAndRuntime].self)
        Matcher.register(SelectedDevice?.self)
    }

    override func tearDown() {
        simulatorController = nil
        downloadPreviewService = nil
        fileUnarchiver = nil
        remoteArtifactDownloader = nil
        appBundleLoader = nil
        appStorage = nil
        subject = nil

        Matcher.reset()

        super.tearDown()
    }

    func test_onAppear_when_appStorage_is_empty_and_no_simulator_is_booted() async throws {
        // Given
        appStorage.reset()
        simulatorController.reset()

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(nil)

        let simulators: [SimulatorDeviceAndRuntime] = [
            .test(
                device: .test(
                    name: "iPhone 15"
                )
            ),
            .test(
                device: .test(
                    name: "iPhone 15 Pro"
                )
            ),
        ]

        given(simulatorController)
            .devicesAndRuntimes()
            .willReturn(simulators)

        // When
        try await subject.onAppear()

        // Then
        XCTAssertEqual(subject.selectedDevice, nil)
        XCTAssertEmpty(subject.pinnedSimulators)
        XCTAssertEqual(subject.unpinnedSimulators, simulators)
    }

    func test_onAppear_when_appStorage_is_empty_and_a_simulator_is_booted() async throws {
        // Given
        appStorage.reset()
        simulatorController.reset()

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(nil)

        let simulators: [SimulatorDeviceAndRuntime] = [
            .test(
                device: .test(
                    name: "iPhone 15"
                )
            ),
            .test(
                device: .test(
                    state: "Booted",
                    name: "iPhone 15 Pro"
                )
            ),
        ]

        given(simulatorController)
            .devicesAndRuntimes()
            .willReturn(simulators)

        // When
        try await subject.onAppear()

        // Then
        XCTAssertEqual(subject.selectedDevice, .simulator(try XCTUnwrap(simulators.last)))
        XCTAssertEmpty(subject.pinnedSimulators)
        XCTAssertEqual(subject.unpinnedSimulators, simulators)
    }

    func test_onAppear_when_appStorage_contains_selected_and_pinned_simulators() async throws {
        // Given
        appStorage.reset()

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn(
                [
                    appleTV,
                    iPhone15,
                ]
            )

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(.simulator(id: appleTV.id))

        // When
        try await subject.onAppear()

        // Then
        XCTAssertEqual(subject.selectedDevice, .simulator(appleTV))
        XCTAssertEqual(subject.pinnedSimulators, [appleTV, iPhone15])
        XCTAssertEqual(subject.unpinnedSimulators, [iPhone15Pro])
    }

    func test_refreshDevices() async throws {
        // Given
        appStorage.reset()
        deviceController.reset()

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(nil)

        let iPhone11 = PhysicalDevice.test(
            name: "iPhone 11",
            transportType: .usb,
            connectionState: .connected
        )

        let iPhone12 = PhysicalDevice.test(
            name: "iPhone 12",
            transportType: .wifi,
            connectionState: .connected
        )

        let watchS9 = PhysicalDevice.test(
            name: "Watch S9",
            transportType: nil,
            connectionState: .disconnected
        )

        given(deviceController)
            .findAvailableDevices()
            .willReturn([iPhone11, iPhone12, watchS9])

        // When
        try await subject.refreshDevices()

        // Then
        XCTAssertEqual(subject.connectedDevices, [iPhone11, iPhone12])
        XCTAssertEqual(subject.disconnectedDevices, [watchS9])
    }

    func test_selectSimulator() async throws {
        // Given
        try await subject.onAppear()

        // When
        subject.selectSimulator(iPhone15Pro)

        // Then
        XCTAssertEqual(subject.selectedDevice, .simulator(iPhone15Pro))
        verify(appStorage)
            .set(
                .any as Parameter<SelectedDeviceKey.Type>,
                value: .value(.simulator(id: iPhone15Pro.id))
            )
            .called(1)
    }

    func test_selectPhysicalDevice() async throws {
        // Given
        deviceController.reset()

        let myiPhone: PhysicalDevice = .test()

        given(deviceController)
            .findAvailableDevices()
            .willReturn([myiPhone])

        try await subject.onAppear()

        // When
        subject.selectPhysicalDevice(myiPhone)

        // Then
        XCTAssertEqual(subject.selectedDevice, .device(myiPhone))
        verify(appStorage)
            .set(
                .any as Parameter<SelectedDeviceKey.Type>,
                value: .value(.device(id: myiPhone.id))
            )
            .called(1)
    }

    func test_pin_simulator() async throws {
        // Given
        appStorage.reset()

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([iPhone15])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(nil)

        given(appStorage)
            .set(.any as Parameter<PinnedSimulatorsKey.Type>, value: .any)
            .willReturn()

        try await subject.onAppear()

        // When
        subject.simulatorPinned(iPhone15Pro, pinned: true)

        // Then
        XCTAssertEqual(subject.pinnedSimulators, [iPhone15, iPhone15Pro])
        XCTAssertEqual(subject.unpinnedSimulators, [appleTV])
        verify(appStorage)
            .set(.any as Parameter<PinnedSimulatorsKey.Type>, value: .value([iPhone15, iPhone15Pro]))
            .called(1)
    }

    func test_unpin_simulator() async throws {
        // Given
        appStorage.reset()

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([iPhone15])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(nil)

        given(appStorage)
            .set(.any as Parameter<PinnedSimulatorsKey.Type>, value: .any)
            .willReturn()

        try await subject.onAppear()

        // When
        subject.simulatorPinned(iPhone15, pinned: false)

        // Then
        XCTAssertEqual(subject.pinnedSimulators, [])
        XCTAssertEqual(subject.unpinnedSimulators, [appleTV, iPhone15, iPhone15Pro])
        verify(appStorage)
            .set(.any as Parameter<PinnedSimulatorsKey.Type>, value: .value([]))
            .called(1)
    }

    func test_onChangeOfURL() async throws {
        // Given
        try await subject.onAppear()

        given(downloadPreviewService)
            .downloadPreview(
                .value("01912892-3778-7297-8ca9-d66ac7ee2a53"),
                fullHandle: .value("tuist/ios_app_with_frameworks"),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn("https://tuist.io/download-link")

        let downloadedArchive = try temporaryPath().appending(component: "archive")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let unarchivedPath = try temporaryPath().appending(component: "unarchived")

        given(fileUnarchiver)
            .unzip()
            .willReturn(unarchivedPath)

        let appPath = unarchivedPath.appending(component: "App.app")
        try fileHandler.touch(appPath)

        given(appBundleLoader)
            .load(.any)
            .willReturn(
                .test(
                    path: appPath,
                    infoPlist: .test(
                        bundleId: "tuist.app",
                        supportedPlatforms: [
                            .simulator(.iOS),
                        ]
                    )
                )
            )

        given(simulatorController)
            .booted(device: .any, forced: .any)
            .willProduce { device, _ in device }

        given(simulatorController)
            .installApp(at: .any, device: .any)
            .willReturn()

        given(simulatorController)
            .launchApp(bundleId: .any, device: .any, arguments: .any)
            .willReturn()

        // When
        try await subject.onChangeOfURL(previewURL)

        // Then
        verify(simulatorController)
            .installApp(
                at: .value(appPath),
                device: .value(iPhone15.device)
            )
            .called(1)
        verify(simulatorController)
            .launchApp(
                bundleId: .value("tuist.app"),
                device: .value(iPhone15.device),
                arguments: .value([])
            )
            .called(1)
    }

    func test_onChangeOfURL_when_physical_device_selected() async throws {
        // Given
        let myiPhone: PhysicalDevice = .test()
        given(deviceController)
            .findAvailableDevices()
            .willReturn([myiPhone])

        try await subject.onAppear()

        subject.selectPhysicalDevice(myiPhone)

        given(downloadPreviewService)
            .downloadPreview(
                .value("01912892-3778-7297-8ca9-d66ac7ee2a53"),
                fullHandle: .value("tuist/ios_app_with_frameworks"),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn("https://tuist.io/download-link")

        let downloadedArchive = try temporaryPath().appending(component: "archive")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let unarchivedPath = try temporaryPath().appending(component: "unarchived")

        given(fileUnarchiver)
            .unzip()
            .willReturn(unarchivedPath)

        let appPath = unarchivedPath.appending(component: "iphoneos-App.app")
        try fileHandler.touch(appPath)

        given(appBundleLoader)
            .load(.value(appPath))
            .willReturn(
                .test(
                    path: appPath,
                    infoPlist: .test(
                        bundleId: "tuist.app",
                        supportedPlatforms: [
                            .device(.iOS),
                        ]
                    )
                )
            )

        let appSimulatorPath = unarchivedPath.appending(component: "iphonesimulator-App.app")
        try fileHandler.touch(appSimulatorPath)

        given(appBundleLoader)
            .load(.any)
            .willReturn(
                .test(
                    path: appSimulatorPath,
                    infoPlist: .test(
                        bundleId: "tuist.app",
                        supportedPlatforms: [
                            .simulator(.iOS),
                        ]
                    )
                )
            )

        // When
        try await subject.onChangeOfURL(previewURL)

        // Then
        verify(deviceController)
            .installApp(
                at: .value(appPath),
                device: .value(myiPhone)
            )
            .called(1)
        verify(deviceController)
            .launchApp(
                bundleId: .value("tuist.app"),
                device: .value(myiPhone)
            )
            .called(1)
    }

    func test_onChangeOfURL_when_physical_device_selected_and_preview_is_ipa() async throws {
        // Given
        let myiPhone: PhysicalDevice = .test()
        given(deviceController)
            .findAvailableDevices()
            .willReturn([myiPhone])

        try await subject.onAppear()

        subject.selectPhysicalDevice(myiPhone)

        given(downloadPreviewService)
            .downloadPreview(
                .value("01912892-3778-7297-8ca9-d66ac7ee2a53"),
                fullHandle: .value("tuist/ios_app_with_frameworks"),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn("https://tuist.io/download-link")

        let downloadedArchive = try temporaryPath().appending(component: "archive")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let unarchivedPath = try temporaryPath().appending(component: "unarchived")

        given(fileUnarchiver)
            .unzip()
            .willReturn(unarchivedPath)

        let payloadPath = unarchivedPath.appending(component: "Payload")
        let appPath = payloadPath.appending(component: "iphoneos-App.app")
        try await fileSystem.makeDirectory(at: appPath)

        given(appBundleLoader)
            .load(.value(appPath))
            .willReturn(
                .test(
                    path: appPath,
                    infoPlist: .test(
                        bundleId: "tuist.app",
                        supportedPlatforms: [
                            .device(.iOS),
                        ]
                    )
                )
            )

        let appSimulatorPath = unarchivedPath.appending(component: "iphonesimulator-App.app")
        try fileHandler.touch(appSimulatorPath)

        given(appBundleLoader)
            .load(.any)
            .willReturn(
                .test(
                    path: appSimulatorPath,
                    infoPlist: .test(
                        bundleId: "tuist.app",
                        supportedPlatforms: [
                            .simulator(.iOS),
                        ]
                    )
                )
            )

        // When
        try await subject.onChangeOfURL(previewURL)

        // Then
        verify(deviceController)
            .installApp(
                at: .value(appPath),
                device: .value(myiPhone)
            )
            .called(1)
        verify(deviceController)
            .launchApp(
                bundleId: .value("tuist.app"),
                device: .value(myiPhone)
            )
            .called(1)
    }

    func test_onChangeOfURL_when_no_simulator_selected() async throws {
        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.onChangeOfURL(previewURL),
            SimulatorsViewModelError.noSelectedSimulator
        )
    }

    func test_onChangeOfURL_when_deeplink_is_invalid() async throws {
        // Given
        try await subject.onAppear()

        let invalidDeeplinkURL =
            "tuist:open-preview?server_url=https://cloud.tuist.io&preview_id=01912892-3778-7297-8ca9-d66ac7ee2a53"

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.onChangeOfURL(
                try XCTUnwrap(URL(string: invalidDeeplinkURL))
            ),
            SimulatorsViewModelError.invalidDeeplink(invalidDeeplinkURL)
        )
    }

    func test_onChangeOfURL_when_appDownloadFailed() async throws {
        // Given
        try await subject.onAppear()

        given(downloadPreviewService)
            .downloadPreview(.any, fullHandle: .any, serverURL: .any)
            .willReturn("https://tuist.io/download-link")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(nil)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.onChangeOfURL(previewURL),
            SimulatorsViewModelError.appDownloadFailed(previewURL.absoluteString)
        )
    }

    func test_onChangeOfURL_when_appNotFound() async throws {
        // Given
        try await subject.onAppear()

        given(downloadPreviewService)
            .downloadPreview(.any, fullHandle: .any, serverURL: .any)
            .willReturn("https://tuist.io/download-link")

        let downloadedArchive = try temporaryPath().appending(component: "archive")

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(downloadedArchive)

        let unarchivedPath = try temporaryPath().appending(component: "unarchived")

        given(fileUnarchiver)
            .unzip()
            .willReturn(unarchivedPath)

        try fileHandler.touch(unarchivedPath.appending(component: "App.app"))

        given(appBundleLoader)
            .load(.any)
            .willReturn(
                .test(
                    infoPlist: .test(
                        supportedPlatforms: [
                            .device(.visionOS),
                            .simulator(.visionOS),
                        ]
                    )
                )
            )

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.onChangeOfURL(previewURL),
            SimulatorsViewModelError.appNotFound(.simulator(iPhone15), [.visionOS])
        )
    }
}
