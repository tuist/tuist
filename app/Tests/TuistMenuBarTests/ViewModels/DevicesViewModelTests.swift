import Foundation
import Mockable
import TuistAppStorage
import TuistAutomation
import TuistCore
import TuistTesting
import XCTest

@testable import TuistMenuBar

final class DevicesViewModelTests: TuistUnitTestCase {
    private var subject: DevicesViewModel!
    private var appStorage: MockAppStoring!
    private var deviceService: MockDeviceServicing!

    private let previewURL =
        URL(
            string: "tuist:open-preview?server_url=https://tuist.dev&preview_id=01912892-3778-7297-8ca9-d66ac7ee2a53&full_handle=tuist/ios_app_with_frameworks"
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

        appStorage = MockAppStoring()
        deviceService = MockDeviceServicing()

        subject = DevicesViewModel(
            deviceService: deviceService,
            appStorage: appStorage
        )

        given(appStorage)
            .get(.any as Parameter<PinnedSimulatorsKey.Type>)
            .willReturn([])

        given(appStorage)
            .get(.any as Parameter<SelectedDeviceKey.Type>)
            .willReturn(.simulator(id: iPhone15.id))

        given(appStorage)
            .set(.any as Parameter<SelectedDeviceKey.Type>, value: .any)
            .willReturn()

        Matcher.register(SimulatorDeviceAndRuntime?.self)
        Matcher.register([SimulatorDeviceAndRuntime].self)
        Matcher.register(SelectedDevice?.self)
    }

    override func tearDown() {
        deviceService = nil
        appStorage = nil
        subject = nil

        Matcher.reset()

        super.tearDown()
    }

    func test_pin_simulator() throws {
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

        given(deviceService)
            .simulators
            .willReturn([appleTV, iPhone15, iPhone15Pro])

        try subject.onAppear()

        // When
        subject.simulatorPinned(iPhone15Pro, pinned: true)

        // Then
        XCTAssertEqual(subject.pinnedSimulators, [iPhone15, iPhone15Pro])
        XCTAssertEqual(subject.unpinnedSimulators, [appleTV])
        verify(appStorage)
            .set(.any as Parameter<PinnedSimulatorsKey.Type>, value: .value([iPhone15, iPhone15Pro]))
            .called(1)
    }

    func test_unpin_simulator() throws {
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

        try subject.onAppear()

        given(deviceService)
            .simulators
            .willReturn([appleTV, iPhone15, iPhone15Pro])

        // When
        subject.simulatorPinned(iPhone15, pinned: false)

        // Then
        XCTAssertEqual(subject.pinnedSimulators, [])
        XCTAssertEqual(subject.unpinnedSimulators, [appleTV, iPhone15, iPhone15Pro])
        verify(appStorage)
            .set(.any as Parameter<PinnedSimulatorsKey.Type>, value: .value([]))
            .called(1)
    }

    func test_connected_and_disconnected_devices() {
        // Given
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

        given(deviceService)
            .devices
            .willReturn([iPhone11, iPhone12, watchS9])

        XCTAssertEqual(subject.connectedDevices, [iPhone11, iPhone12])
        XCTAssertEqual(subject.disconnectedDevices, [watchS9])
    }
}
