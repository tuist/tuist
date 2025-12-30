import Foundation
import Mockable
import TuistAppStorage
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistMenuBar

final class DeviceServiceTests: TuistUnitTestCase {
    private var subject: DeviceService!
    private var simulatorController: MockSimulatorControlling!
    private var getPreviewService: MockGetPreviewServicing!
    private var fileUnarchiver: MockFileUnarchiving!
    private var remoteArtifactDownloader: MockRemoteArtifactDownloading!
    private var appBundleLoader: MockAppBundleLoading!
    private var appStorage: MockAppStoring!
    private var deviceController: MockDeviceControlling!
    private var taskStatusReporter: MockTaskStatusReporting!
    private var menuBarFocusService: MockMenuBarFocusServicing!

    private let previewURL =
        URL(
            string:
            "tuist:open-preview?server_url=https://tuist.dev&preview_id=01912892-3778-7297-8ca9-d66ac7ee2a53&full_handle=tuist/ios_app_with_frameworks"
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
        getPreviewService = .init()
        let fileArchiverFactory = MockFileArchivingFactorying()
        remoteArtifactDownloader = .init()
        appBundleLoader = .init()
        appStorage = .init()
        deviceController = .init()
        taskStatusReporter = .init()
        menuBarFocusService = MockMenuBarFocusServicing()

        subject = DeviceService(
            taskStatusReporter: taskStatusReporter,
            appStorage: appStorage,
            deviceController: deviceController,
            simulatorController: simulatorController,
            getPreviewService: getPreviewService,
            fileArchiverFactory: fileArchiverFactory,
            remoteArtifactDownloader: remoteArtifactDownloader,
            fileSystem: fileSystem,
            appBundleLoader: appBundleLoader,
            menuBarFocusService: menuBarFocusService
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

        given(menuBarFocusService)
            .focus()
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
        getPreviewService = nil
        fileUnarchiver = nil
        remoteArtifactDownloader = nil
        appBundleLoader = nil
        appStorage = nil
        subject = nil
        taskStatusReporter = nil

        Matcher.reset()

        super.tearDown()
    }

    func test_loadDevices_when_appStorage_is_empty_and_no_simulator_is_booted() async throws {
        // Given
        appStorage.reset()
        simulatorController.reset()

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

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
        try await subject.loadDevices()

        // Then
        XCTAssertEqual(subject.selectedDevice, nil)
    }

    func test_loadDevices_when_appStorage_is_empty_and_a_simulator_is_booted() async throws {
        // Given
        appStorage.reset()
        simulatorController.reset()

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

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
        try await subject.loadDevices()

        // Then
        XCTAssertEqual(subject.selectedDevice, .simulator(try XCTUnwrap(simulators.last)))
    }

    func test_loadDevices_when_appStorage_contains_selected_and_pinned_simulators() async throws {
        // Given
        appStorage.reset()

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

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
        try await subject.loadDevices()

        // Then
        XCTAssertEqual(subject.selectedDevice, .simulator(appleTV))
    }

    func test_reloadDevices() async throws {
        // Given
        appStorage.reset()
        deviceController.reset()

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

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
        try await subject.loadDevices()

        // Then
        XCTAssertEqual(subject.devices, [iPhone11, iPhone12, watchS9])
    }

    func test_selectSimulator() async throws {
        // Given
        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        try await subject.loadDevices()

        // When
        await subject.selectDevice(.simulator(iPhone15Pro))

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
        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        deviceController.reset()

        let myiPhone: PhysicalDevice = .test()

        given(deviceController)
            .findAvailableDevices()
            .willReturn([myiPhone])

        try await subject.loadDevices()

        // When
        await subject.selectDevice(.device(myiPhone))

        // Then
        XCTAssertEqual(subject.selectedDevice, .device(myiPhone))
        verify(appStorage)
            .set(
                .any as Parameter<SelectedDeviceKey.Type>,
                value: .value(.device(id: myiPhone.id))
            )
            .called(1)
    }

    func test_launchPreviewDeeplink() async throws {
        // Given
        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        try await subject.loadDevices()

        given(getPreviewService)
            .getPreview(
                .value("01912892-3778-7297-8ca9-d66ac7ee2a53"),
                fullHandle: .value("tuist/ios_app_with_frameworks"),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn(.test())

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
        try await subject.launchPreviewDeeplink(with: previewURL)

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
        verify(menuBarFocusService)
            .focus()
            .called(1)
    }

    func test_launchPreviewDeeplink_when_physical_device_selected() async throws {
        // Given
        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        let myiPhone: PhysicalDevice = .test()
        given(deviceController)
            .findAvailableDevices()
            .willReturn([myiPhone])

        try await subject.loadDevices()

        await subject.selectDevice(.device(myiPhone))

        given(getPreviewService)
            .getPreview(
                .value("01912892-3778-7297-8ca9-d66ac7ee2a53"),
                fullHandle: .value("tuist/ios_app_with_frameworks"),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn(.test())

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

        // When
        try await subject.launchPreviewDeeplink(with: previewURL)

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

    func test_launchPreviewDeeplink_when_physical_device_selected_and_preview_is_ipa() async throws {
        // Given
        let myiPhone: PhysicalDevice = .test()
        given(deviceController)
            .findAvailableDevices()
            .willReturn([myiPhone])

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        try await subject.loadDevices()

        await subject.selectDevice(.device(myiPhone))

        given(getPreviewService)
            .getPreview(
                .value("01912892-3778-7297-8ca9-d66ac7ee2a53"),
                fullHandle: .value("tuist/ios_app_with_frameworks"),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn(
                .test(
                    appBuilds: [
                        .test(supportedPlatforms: [.device(.iOS)]),
                    ]
                )
            )

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

        // When
        try await subject.launchPreviewDeeplink(with: previewURL)

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

    func test_launchPreviewDeeplink_when_no_simulator_selected() async throws {
        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.launchPreviewDeeplink(with: previewURL),
            SimulatorsViewModelError.noSelectedSimulator
        )
    }

    func test_launchPreviewDeeplink_when_deeplink_is_invalid() async throws {
        // Given
        try await subject.loadDevices()

        let invalidDeeplinkURL =
            "tuist:open-preview?server_url=https://tuist.dev&preview_id=01912892-3778-7297-8ca9-d66ac7ee2a53"

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.launchPreviewDeeplink(
                with: try XCTUnwrap(URL(string: invalidDeeplinkURL))
            ),
            SimulatorsViewModelError.invalidDeeplink(invalidDeeplinkURL)
        )
    }

    func test_launchPreviewDeeplink_when_appDownloadFailed() async throws {
        // Given
        try await subject.loadDevices()

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        given(getPreviewService)
            .getPreview(.any, fullHandle: .any, serverURL: .any)
            .willReturn(
                .test(
                    id: "preview-id"
                )
            )

        given(remoteArtifactDownloader)
            .download(url: .any)
            .willReturn(nil)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.launchPreviewDeeplink(with: previewURL),
            DeviceServiceError.appDownloadFailed("preview-id")
        )
    }

    func test_launchPreviewDeeplink_when_appNotFound() async throws {
        // Given
        try await subject.loadDevices()

        await given(taskStatusReporter)
            .add(status: .any)
            .willReturn()

        given(getPreviewService)
            .getPreview(.any, fullHandle: .any, serverURL: .any)
            .willReturn(
                .test(
                    appBuilds: [
                        .test(
                            supportedPlatforms: [.device(.visionOS)]
                        ),
                    ]
                )
            )

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
        given(simulatorController)
            .booted(device: .any, forced: .any)
            .willProduce { device, _ in device }
        given(simulatorController)
            .launchApp(bundleId: .any, device: .any, arguments: .any)
            .willReturn()
        given(simulatorController)
            .installApp(at: .any, device: .any)
            .willReturn()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.launchPreviewDeeplink(with: previewURL),
            SimulatorsViewModelError.appNotFound(.simulator(iPhone15), [.device(.visionOS)])
        )
    }
}
