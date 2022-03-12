import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistGraph
import TuistSupport
@testable import TuistCore
@testable import TuistSupportTesting

public final class MockSimulatorController: SimulatorControlling {
    public init() {}

    public var findAvailableDeviceStub: ((Platform, Version?, Version?, String?) -> SimulatorDeviceAndRuntime)?
    public func findAvailableDevice(
        platform: Platform,
        version: Version?,
        minVersion: Version?,
        deviceName: String?
    ) async throws -> SimulatorDeviceAndRuntime {
        findAvailableDeviceStub?(platform, version, minVersion, deviceName) ?? SimulatorDeviceAndRuntime.test()
    }

    public var installAppStub: ((AbsolutePath, SimulatorDevice) throws -> Void)?
    public func installApp(at path: AbsolutePath, device: SimulatorDevice) throws {
        try installAppStub?(path, device)
    }

    public var launchAppStub: ((String, SimulatorDevice, [String]) throws -> Void)?
    public func launchApp(bundleId: String, device: SimulatorDevice, arguments: [String]) throws {
        try launchAppStub?(bundleId, device, arguments)
    }

    public var destinationStub: ((Platform) -> String)?
    public func destination(for targetPlatform: Platform, version _: Version?, deviceName _: String?) async throws -> String {
        destinationStub?(targetPlatform) ?? "id=\(SimulatorDeviceAndRuntime.test().device.udid)"
    }

    public var macOSDestinationStub: (() -> String)?
    public func macOSDestination() -> String {
        macOSDestinationStub?() ?? "platform=macOS,arch=arm64"
    }
}
