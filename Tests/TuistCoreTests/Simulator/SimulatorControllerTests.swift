import Foundation
import TSCBasic
import XCTest

@testable import TuistCore
@testable import TuistSupport
@testable import TuistSupportTesting

final class SimulatorControllerTests: TuistUnitTestCase {
    private var subject: SimulatorController!

    override func setUp() {
        super.setUp()
        subject = SimulatorController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_devices_should_returnListOfDevicesFromJson() async throws {
        // Given
        let expectedDevice = createSystemStubs(devices: true, runtimes: false).device

        // When
        let devices = try await subject.devices()

        // Then
        XCTAssertEqual(devices, [expectedDevice])
    }

    func test_runtimes_should_returnListOfRuntimesFromJson() async throws {
        // Given
        let expectedRuntime = createSystemStubs(devices: false, runtimes: true).runtime

        // When
        let runtimes = try await subject.runtimes()

        // Then
        XCTAssertEqual(runtimes, [expectedRuntime])
    }

    func test_devicesAndRuntimes_should_returnListOfSimulatorDeviceAndRuntimesFromJson() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // When
        let devicesAndRuntimes = try await subject.devicesAndRuntimes()

        // Then
        XCTAssertEqual(devicesAndRuntimes, [expectedDeviceAndRuntime])
    }

    func test_findAvailableDevice_should_throwErrorWhenNoDeviceForPlatform() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // Then
        await XCTAssertThrowsSpecific(
            // When
            _ = try await subject.findAvailableDevice(platform: .macOS, version: nil, minVersion: nil, deviceName: nil),
            SimulatorControllerError.deviceNotFound(.macOS, nil, nil, [expectedDeviceAndRuntime])
        )
    }

    func test_findAvailableDevice_should_throwErrorWhenNoDeviceForVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // Then
        await XCTAssertThrowsSpecific(
            // When
            _ = try await subject.findAvailableDevice(platform: .iOS, version: .init(15, 0, 0), minVersion: nil, deviceName: nil),
            SimulatorControllerError.deviceNotFound(.iOS, .init(15, 0, 0), nil, [expectedDeviceAndRuntime])
        )
    }

    func test_findAvailableDevice_should_throwErrorWhenNoDeviceWithinMinVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // Then
        await XCTAssertThrowsSpecific(
            // When
            _ = try await subject.findAvailableDevice(platform: .iOS, version: nil, minVersion: .init(15, 0, 0), deviceName: nil),
            SimulatorControllerError.deviceNotFound(.iOS, nil, nil, [expectedDeviceAndRuntime])
        )
    }

    func test_findAvailableDevice_should_throwErrorWhenNoDeviceWithDeviceName() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // Then
        await XCTAssertThrowsSpecific(
            // When
            _ = try await subject.findAvailableDevice(platform: .iOS, version: nil, minVersion: nil, deviceName: "iPad 100"),
            SimulatorControllerError.deviceNotFound(.iOS, nil, "iPad 100", [expectedDeviceAndRuntime])
        )
    }

    func test_findAvailableDevice_should_findDeviceWithDefaults() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // When
        let device = try await subject.findAvailableDevice(platform: .iOS, version: nil, minVersion: nil, deviceName: nil)

        // Then
        XCTAssertEqual(device, expectedDeviceAndRuntime)
    }

    func test_findAvailableDevice_should_findDeviceWithVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: .init(14, 4, 0),
            minVersion: nil,
            deviceName: nil
        )

        // Then
        XCTAssertEqual(device, expectedDeviceAndRuntime)
    }

    func test_findAvailableDevice_should_findDeviceWithinMinVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: .init(14, 0, 0),
            deviceName: nil
        )

        // Then
        XCTAssertEqual(device, expectedDeviceAndRuntime)
    }

    func test_findAvailableDevice_should_findDeviceWithDeviceName() async throws {
        // Given
        let expectedDeviceAndRuntime = createSystemStubs(devices: true, runtimes: true)

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: nil,
            deviceName: expectedDeviceAndRuntime.device.name
        )

        // Then
        XCTAssertEqual(device, expectedDeviceAndRuntime)
    }

    func test_installApp_should_bootSimulatorIfNotBooted() throws {
        // Given
        let deviceAndRuntime = createSystemStubs(devices: true, runtimes: true)
        let appPath = try AbsolutePath(validating: "/path/to/app.App")
        let udid = deviceAndRuntime.device.udid
        let bootCommand = ["/usr/bin/xcrun", "simctl", "boot", udid]
        system.succeedCommand(bootCommand)

        // When
        try? subject.installApp(at: appPath, device: deviceAndRuntime.device)

        // Then
        XCTAssertTrue(system.called(bootCommand))
    }

    func test_installApp_should_installAppOnSimulatorWithUdid() throws {
        // Given
        let deviceAndRuntime = createSystemStubs(devices: true, runtimes: true)
        let appPath = try AbsolutePath(validating: "/path/to/app.App")
        let udid = deviceAndRuntime.device.udid
        let bootCommand = ["/usr/bin/xcrun", "simctl", "boot", udid]
        system.succeedCommand(bootCommand)
        let installCommand = ["/usr/bin/xcrun", "simctl", "install", udid, appPath.pathString]
        system.succeedCommand(installCommand)

        // When
        try subject.installApp(at: appPath, device: deviceAndRuntime.device)

        // Then
        XCTAssertTrue(system.called(installCommand))
    }

    func test_launchApp_should_bootSimulatorIfNotBooted() throws {
        // Given
        let deviceAndRuntime = createSystemStubs(devices: true, runtimes: true)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        let bootCommand = ["/usr/bin/xcrun", "simctl", "boot", udid]
        system.succeedCommand(bootCommand)

        // When
        try? subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: [])

        // Then
        XCTAssertTrue(system.called(bootCommand))
    }

    func test_launchApp_should_openSimulatorApp() throws {
        // Given
        let deviceAndRuntime = createSystemStubs(devices: true, runtimes: true)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        system.succeedCommand(["/usr/bin/xcrun", "simctl", "boot", udid])
        let openSimAppCommand = ["/usr/bin/open", "-a", "Simulator"]
        system.succeedCommand(openSimAppCommand)

        // When
        try? subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: [])

        // Then
        XCTAssertTrue(system.called(openSimAppCommand))
    }

    func test_launchApp_should_launchAppOnSimulator() throws {
        // Given
        let deviceAndRuntime = createSystemStubs(devices: true, runtimes: true)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        system.succeedCommand(["/usr/bin/xcrun", "simctl", "boot", udid])
        system.succeedCommand(["/usr/bin/open", "-a", "Simulator"])
        let launchAppCommand = ["/usr/bin/xcrun", "simctl", "launch", udid, bundleId]
        system.succeedCommand(launchAppCommand)

        // When
        try subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: [])

        // Then
        XCTAssertTrue(system.called(launchAppCommand))
    }

    func test_launchApp_should_launchAppOnSimulatorWithArguments() throws {
        // Given
        let deviceAndRuntime = createSystemStubs(devices: true, runtimes: true)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        let arguments = ["-arg1", "--arg2", "SomeArg"]
        system.succeedCommand(["/usr/bin/xcrun", "simctl", "boot", udid])
        system.succeedCommand(["/usr/bin/open", "-a", "Simulator"])
        let launchAppCommand = ["/usr/bin/xcrun", "simctl", "launch", udid, bundleId] + arguments
        system.succeedCommand(launchAppCommand)

        // When
        try subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: arguments)

        // Then
        XCTAssertTrue(system.called(launchAppCommand))
    }

    private func createSystemStubs(devices: Bool, runtimes: Bool) -> SimulatorDeviceAndRuntime {
        let bundlePath = "/path/to/bundle"
        let buildVersion = "buildVersion"
        let runtimeRoot = "/path/to/runtime/root"
        let identifier = "com.apple.CoreSimulator.SimRuntime.iOS-14-4"
        let version = "14.4"
        let runtimeName = "iOS 14.4"
        let runtimesJsonResponse = """
        {
          "runtimes" : [
            {
              "bundlePath" : "\(bundlePath)",
              "buildversion" : "\(buildVersion)",
              "runtimeRoot" : "\(runtimeRoot)",
              "identifier" : "\(identifier)",
              "version" : "\(version)",
              "isAvailable" : true,
              "supportedDeviceTypes" : [],
              "name" : "\(runtimeName)"
            }
          ]
        }
        """
        let dataPath = "/path/to/sim/81F0475F-0A03-4742-92D7-D59ACE3A5895/data"
        let logPath = "/path/to/logs/81F0475F-0A03-4742-92D7-D59ACE3A5895"
        let udid = "81F0475F-0A03-4742-92D7-D59ACE3A5895"
        let deviceTypeIdentifier = "com.apple.CoreSimulator.SimDeviceType.iPhone-11"
        let state = "Shutdown"
        let deviceName = "iPhone 11"
        let runTimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-14-4"
        let devicesJsonResponse = """
        {
          "devices" : {
            "\(runTimeIdentifier)" : [
              {
                "dataPath" : "\(dataPath)",
                "logPath" : "\(logPath)",
                "udid" : "\(udid)",
                "isAvailable" : true,
                "deviceTypeIdentifier" : "\(deviceTypeIdentifier)",
                "state" : "\(state)",
                "name" : "\(deviceName)"
              }
            ]
          }
        }
        """

        if runtimes {
            system.stubs["/usr/bin/xcrun simctl list runtimes --json"] = (nil, runtimesJsonResponse, 0)
        }

        if devices {
            system.stubs["/usr/bin/xcrun simctl list devices --json"] = (nil, devicesJsonResponse, 0)
        }

        return SimulatorDeviceAndRuntime(
            device: SimulatorDevice(
                dataPath: try! AbsolutePath(validating: dataPath),
                logPath: try! AbsolutePath(validating: logPath),
                udid: udid,
                isAvailable: true,
                deviceTypeIdentifier: deviceTypeIdentifier,
                state: state,
                name: deviceName,
                availabilityError: nil,
                runtimeIdentifier: runTimeIdentifier
            ),
            runtime: SimulatorRuntime(
                bundlePath: try! AbsolutePath(validating: bundlePath),
                buildVersion: buildVersion,
                runtimeRoot: try! AbsolutePath(validating: runtimeRoot),
                identifier: identifier,
                version: .init(major: 14, minor: 4, patch: nil),
                isAvailable: true,
                name: runtimeName
            )
        )
    }
}
