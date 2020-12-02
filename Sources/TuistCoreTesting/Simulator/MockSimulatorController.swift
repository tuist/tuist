import Foundation
import RxSwift
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistSupport

@testable import TuistCore
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

    public func findAvailableDevice(platform: Platform) -> Single<SimulatorDeviceAndRuntime> {
        self.findAvailableDevice(platform: platform,
                                 version: nil,
                                 minVersion: nil,
                                 deviceName: nil)
    }

    public var findAvailableDeviceStub: ((Platform, Version?, Version?, String?) -> Single<SimulatorDeviceAndRuntime>)?
    public func findAvailableDevice(platform: Platform, version: Version?, minVersion: Version?, deviceName: String?) -> Single<SimulatorDeviceAndRuntime> {
        findAvailableDeviceStub?(platform, version, minVersion, deviceName) ?? .just(SimulatorDeviceAndRuntime.test())
    }

    public func bootSimulator(_: SimulatorDeviceAndRuntime) -> Observable<SystemEvent<Data>> {
        Observable.empty()
    }

    public func shutdownSimulator(_: String) -> Observable<SystemEvent<Data>> {
        Observable.empty()
    }

    public func installAppBuilt(appPath _: AbsolutePath) -> Observable<SystemEvent<Data>> {
        Observable.empty()
    }

    public func launchApp(bundleId _: String) -> Observable<SystemEvent<Data>> {
        Observable.empty()
    }
}
