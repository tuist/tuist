import Foundation
import RxSwift
import TuistSupport
import TuistCore
import struct TSCUtility.Version

@testable import TuistAutomation
@testable import TuistSupportTesting

public final class MockSimulatorController: SimulatorControlling {
    public init() {}

    public var devicesStub: Result<[SimulatorDevice], Error>?
    public func devices() -> Single<[SimulatorDevice]> {
        if let devicesStub = devicesStub {
            switch devicesStub {
            case let .failure(error): return .error(error)
            case let .success(devices): return .just(devices)
            }
        } else {
            return .error(TestError("call to non-stubbed method devices"))
        }
    }

    public var runtimesStub: Result<[SimulatorRuntime], Error>?
    public func runtimes() -> Single<[SimulatorRuntime]> {
        if let runtimesStub = runtimesStub {
            switch runtimesStub {
            case let .failure(error): return .error(error)
            case let .success(runtimes): return .just(runtimes)
            }
        } else {
            return .error(TestError("call to non-stubbed method runtimes"))
        }
    }

    public var devicesAndRuntimesStub: Result<[SimulatorDeviceAndRuntime], Error>?
    public func devicesAndRuntimes() -> Single<[SimulatorDeviceAndRuntime]> {
        if let devicesAndRuntimesStub = devicesAndRuntimesStub {
            switch devicesAndRuntimesStub {
            case let .failure(error): return .error(error)
            case let .success(runtimesAndDevices): return .just(runtimesAndDevices)
            }
        } else {
            return .error(TestError("call to non-stubbed method runtimesAndDevices"))
        }
    }
    
    public var findAvailableDeviceStub: ((Platform, Version?, String?) -> Single<SimulatorDevice>)?
    public func findAvailableDevice(platform: Platform, version: Version?, deviceName: String?) -> Single<SimulatorDevice> {
        findAvailableDeviceStub?(platform, version, deviceName) ?? .just(SimulatorDevice.test())
    }
}
