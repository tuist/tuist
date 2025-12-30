import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TSCUtility

@testable import TuistCore
@testable import TuistSupport
@testable import TuistTesting

struct SimulatorControllerTests {
    private var subject: SimulatorController!
    private let system = MockSystem()

    init() {
        subject = SimulatorController(
            system: system
        )
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController) func devices_should_returnListOfDevicesFromJson() async throws {
        // Given
        let expectedDevice = try #require(createSystemStubs(devices: true, runtimes: false).first?.device)

        // When
        let devices = try await subject.devices()

        // Then
        #expect(devices == [expectedDevice])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func runtimes_should_returnListOfRuntimesFromJson() async throws {
        // Given
        let expectedRuntime = try #require(createSystemStubs(devices: false, runtimes: true).first?.runtime)

        // When
        let runtimes = try await subject.runtimes()

        // Then
        #expect(runtimes == [expectedRuntime])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func devicesAndRuntimes_should_returnListOfSimulatorDeviceAndRuntimesFromJson() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let devicesAndRuntimes = try await subject.devicesAndRuntimes()

        // Then
        #expect(devicesAndRuntimes == [expectedDeviceAndRuntime])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_throwErrorWhenNoDeviceForPlatform() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // Then
        await #expect(throws: SimulatorControllerError.deviceNotFound(.macOS, nil, nil, [expectedDeviceAndRuntime]), performing: {
            _ = try await subject.findAvailableDevice(platform: .macOS, version: nil, minVersion: nil, deviceName: nil)
        })
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_by_udid_should_throwErrorWhenNoDeviceForPlatform() async throws {
        // Given
        _ = createSystemStubs(devices: true, runtimes: true)

        // Then
        await #expect(throws: SimulatorControllerError.simulatorNotFound(udid: "some-id"), performing: {
            _ = try await subject.findAvailableDevice(udid: "some-id")
        })
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_throwErrorWhenNoDeviceForVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // Then
        await #expect(
            throws: SimulatorControllerError.deviceNotFound(.iOS, .init(15, 0, 0), nil, [expectedDeviceAndRuntime]),
            performing: {
                _ = try await subject.findAvailableDevice(
                    platform: .iOS,
                    version: .init(15, 0, 0),
                    minVersion: nil,
                    deviceName: nil
                )
            }
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_throwErrorWhenNoDeviceWithinMinVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // Then
        await #expect(throws: SimulatorControllerError.deviceNotFound(.iOS, nil, nil, [expectedDeviceAndRuntime]), performing: {
            _ = try await subject.findAvailableDevice(platform: .iOS, version: nil, minVersion: .init(15, 0, 0), deviceName: nil)
        })
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_throwErrorWhenNoDeviceWithDeviceName() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // Then
        await #expect(
            throws: SimulatorControllerError.deviceNotFound(.iOS, nil, "iPad 100", [expectedDeviceAndRuntime]),
            performing: {
                _ = try await subject.findAvailableDevice(platform: .iOS, version: nil, minVersion: nil, deviceName: "iPad 100")
            }
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithUdid() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let device = try await subject.findAvailableDevice(udid: "81F0475F-0A03-4742-92D7-D59ACE3A5895")

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithDeviceNameAndOSVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let device = try await subject.findAvailableDevice(
            deviceName: "iPhone 11",
            version: Version(14, 4, 0)
        )

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithDefaults() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let device = try await subject.findAvailableDevice(platform: .iOS, version: nil, minVersion: nil, deviceName: nil)

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: .init(14, 4, 0),
            minVersion: nil,
            deviceName: nil
        )

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithinMinVersion() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: .init(14, 0, 0),
            deviceName: nil
        )

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithDeviceName() async throws {
        // Given
        let expectedDeviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: nil,
            deviceName: expectedDeviceAndRuntime.device.name
        )

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findDeviceWithMaxVersion_when_noMinVersionAndDeviceNameIsSet() async throws {
        // Given
        let devicesAndRuntimes =
            createSystemStubs(
                devices: true,
                runtimes: true,
                versions: [
                    .init(major: 14, minor: 0),
                    .init(major: 15, minor: 0),
                    .init(major: 16, minor: 0),
                    .init(major: 17, minor: 0),
                ]
            )
        let expectedDeviceAndRuntime = try #require(devicesAndRuntimes.first(where: { $0.runtime.version == "17.0" }))

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: nil,
            minVersion: nil,
            deviceName: nil
        )

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func findAvailableDevice_should_findVersionSpecified_when_lessThanMaxVersion() async throws {
        // Given
        let devicesAndRuntimes =
            createSystemStubs(
                devices: true,
                runtimes: true,
                versions: [
                    .init(major: 16, minor: 0),
                    .init(major: 17, minor: 0),
                ]
            )
        let expectedDeviceAndRuntime = try #require(devicesAndRuntimes.first(where: { $0.runtime.version == "16.0" }))

        // When
        let device = try await subject.findAvailableDevice(
            platform: .iOS,
            version: .init(16, 0, 0),
            minVersion: nil,
            deviceName: nil
        )

        // Then
        #expect(device == expectedDeviceAndRuntime)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController) func installApp_should_bootSimulatorIfNotBooted() throws {
        // Given
        let deviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)
        let appPath = try AbsolutePath(validating: "/path/to/app.App")
        let udid = deviceAndRuntime.device.udid
        let bootCommand = ["/usr/bin/xcrun", "simctl", "boot", udid]
        system.succeedCommand(bootCommand)

        // When
        try? subject.installApp(at: appPath, device: deviceAndRuntime.device)

        // Then
        #expect(system.called(bootCommand) == true)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController) func installApp_should_installAppOnSimulatorWithUdid() throws {
        // Given
        let deviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)
        let appPath = try AbsolutePath(validating: "/path/to/app.App")
        let udid = deviceAndRuntime.device.udid
        let bootCommand = ["/usr/bin/xcrun", "simctl", "boot", udid]
        system.succeedCommand(bootCommand)
        let installCommand = ["/usr/bin/xcrun", "simctl", "install", udid, appPath.pathString]
        system.succeedCommand(installCommand)

        // When
        try subject.installApp(at: appPath, device: deviceAndRuntime.device)

        // Then
        #expect(system.called(installCommand) == true)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController) func launchApp_should_bootSimulatorIfNotBooted() async throws {
        // Given
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test())
        let deviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        let bootCommand = ["/usr/bin/xcrun", "simctl", "boot", udid]
        system.succeedCommand(bootCommand)

        // When
        try? await subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: [])

        // Then
        #expect(system.called(bootCommand) == true)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController) func launchApp_should_openSimulatorApp() async throws {
        // Given
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test())
        let deviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        system.succeedCommand(["/usr/bin/xcrun", "simctl", "boot", udid])
        let openSimAppCommand = ["/usr/bin/open", "-a", "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"]
        system.succeedCommand(openSimAppCommand)

        // When
        try? await subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: [])

        // Then
        #expect(system.called(openSimAppCommand) == true)
    }

    @Test(.inTemporaryDirectory, .withMockedXcodeController) func launchApp_should_launchAppOnSimulator() async throws {
        // Given
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test())
        let deviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        system.succeedCommand(["/usr/bin/xcrun", "simctl", "boot", udid])
        system.succeedCommand(["/usr/bin/open", "-a", "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"])
        let launchAppCommand = ["/usr/bin/xcrun", "simctl", "launch", udid, bundleId]
        system.succeedCommand(launchAppCommand)

        // When
        try await subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: [])

        // Then
        #expect(system.called(launchAppCommand) == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedXcodeController
    ) func launchApp_should_launchAppOnSimulatorWithArguments() async throws {
        // Given
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selected()
            .willReturn(.test())
        let deviceAndRuntime = try #require(createSystemStubs(devices: true, runtimes: true).first)
        let bundleId = "bundleId"
        let udid = deviceAndRuntime.device.udid
        let arguments = ["-arg1", "--arg2", "SomeArg"]
        system.succeedCommand(["/usr/bin/xcrun", "simctl", "boot", udid])
        system.succeedCommand(["/usr/bin/open", "-a", "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"])
        let launchAppCommand = ["/usr/bin/xcrun", "simctl", "launch", udid, bundleId] + arguments
        system.succeedCommand(launchAppCommand)

        // When
        try await subject.launchApp(bundleId: bundleId, device: deviceAndRuntime.device, arguments: arguments)

        // Then
        #expect(system.called(launchAppCommand) == true)
    }

    private func createSystemStubs(
        devices: Bool,
        runtimes: Bool,
        versions: [SimulatorRuntimeVersion] = [.init(major: 14, minor: 4)]
    ) -> [SimulatorDeviceAndRuntime] {
        let stubs = createSimulatorDevicesAndRuntimes(versions: versions)

        if runtimes {
            system.succeedCommand(
                ["/usr/bin/xcrun", "simctl list runtimes", "--json"],
                output: stubs.runtimesJsonResponse
            )
        }

        if devices {
            system.succeedCommand(
                ["/usr/bin/xcrun", "simctl list devices", "--json"],
                output: stubs.devicesJsonResponse
            )
        }

        return stubs.simulators
    }

    private func createSimulatorDevicesAndRuntimes(versions: [SimulatorRuntimeVersion]) -> (
        runtimesJsonResponse: String,
        devicesJsonResponse: String,
        simulators: [SimulatorDeviceAndRuntime]
    ) {
        var runtimes: [SimulatorRuntime] = []
        let runtimesJsonResponse: String = {
            let runtimes = versions.map { version -> String in
                let major = version.major
                let minor = version.minor ?? .zero

                let bundlePath = "/path/to/bundle"
                let buildVersion = "buildVersion"
                let runtimeRoot = "/path/to/runtime/root"
                let identifier = "com.apple.CoreSimulator.SimRuntime.iOS-\(major)-\(minor)"
                let version = "\(major).\(minor)"
                let runtimeName = "iOS \(major).\(minor)"

                runtimes.append(
                    SimulatorRuntime(
                        bundlePath: try! AbsolutePath(validating: bundlePath),
                        buildVersion: buildVersion,
                        runtimeRoot: try! AbsolutePath(validating: runtimeRoot),
                        identifier: identifier,
                        version: .init(major: major, minor: minor, patch: nil),
                        isAvailable: true,
                        name: runtimeName
                    )
                )

                return """
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
                """
            }

            return """
            { "runtimes" : [ \(runtimes.joined(separator: ",")) ]}
            """
        }()

        var devices: [SimulatorDevice] = []
        let devicesJsonResponse: String = {
            let devices = versions.map { version -> String in
                let major = version.major
                let minor = version.minor ?? .zero

                let dataPath = "/path/to/sim/81F0475F-0A03-4742-92D7-D59ACE3A5895/data"
                let logPath = "/path/to/logs/81F0475F-0A03-4742-92D7-D59ACE3A5895"
                let udid = "81F0475F-0A03-4742-92D7-D59ACE3A5895"
                let deviceTypeIdentifier = "com.apple.CoreSimulator.SimDeviceType.iPhone-11"
                let state = "Shutdown"
                let deviceName = "iPhone 11"
                let runTimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-\(major)-\(minor)"

                devices.append(
                    SimulatorDevice(
                        dataPath: try! AbsolutePath(validating: dataPath),
                        logPath: try! AbsolutePath(validating: logPath),
                        udid: udid,
                        isAvailable: true,
                        deviceTypeIdentifier: deviceTypeIdentifier,
                        state: state,
                        name: deviceName,
                        availabilityError: nil,
                        runtimeIdentifier: runTimeIdentifier
                    )
                )

                return """
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

                """
            }

            return """
            { "devices" : { \(devices.joined(separator: ",")) }}
            """
        }()

        let simulators = runtimes.enumerated().map { index, runtime in
            let device = devices[index]
            return SimulatorDeviceAndRuntime(device: device, runtime: runtime)
        }

        return (
            runtimesJsonResponse: runtimesJsonResponse,
            devicesJsonResponse: devicesJsonResponse,
            simulators: simulators
        )
    }
}
