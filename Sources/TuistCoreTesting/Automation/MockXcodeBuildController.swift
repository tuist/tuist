import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport
@testable import TuistSupportTesting

final class MockXcodeBuildController: XcodeBuildControlling {
    var buildStub: ((XcodeBuildTarget, String, Bool, [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>)?
    func build(_ target: XcodeBuildTarget,
               scheme: String,
               clean: Bool,
               arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        if let buildStub = buildStub {
            return buildStub(target, scheme, clean, arguments)
        } else {
            return Observable
                .error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to build"))
        }
    }

    var testStub: (
        (XcodeBuildTarget, String, Bool, XcodeBuildDestination, AbsolutePath?, AbsolutePath?, [XcodeBuildArgument])
            -> Observable<SystemEvent<XcodeBuildOutput>>
    )?
    func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        destination: XcodeBuildDestination,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument]
    ) -> Observable<SystemEvent<XcodeBuildOutput>> {
        if let testStub = testStub {
            return testStub(target, scheme, clean, destination, derivedDataPath, resultBundlePath, arguments)
        } else {
            return Observable
                .error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to test"))
        }
    }

    var archiveStub: (
        (XcodeBuildTarget, String, Bool, AbsolutePath, [XcodeBuildArgument])
            -> Observable<SystemEvent<XcodeBuildOutput>>
    )?
    func archive(_ target: XcodeBuildTarget,
                 scheme: String,
                 clean: Bool,
                 archivePath: AbsolutePath,
                 arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        if let archiveStub = archiveStub {
            return archiveStub(target, scheme, clean, archivePath, arguments)
        } else {
            return Observable
                .error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to archive"))
        }
    }

    var createXCFrameworkStub: (([AbsolutePath], AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>>)?
    func createXCFramework(frameworks: [AbsolutePath], output: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>> {
        if let createXCFrameworkStub = createXCFrameworkStub {
            return createXCFrameworkStub(frameworks, output)
        } else {
            return Observable
                .error(
                    TestError(
                        "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to createXCFramework"
                    )
                )
        }
    }

    var showBuildSettingsStub: ((XcodeBuildTarget, String, String) -> [String: XcodeBuildSettings])?
    func showBuildSettings(_ target: XcodeBuildTarget, scheme: String,
                           configuration: String) throws -> [String: XcodeBuildSettings]
    {
        if let showBuildSettingsStub = showBuildSettingsStub {
            return showBuildSettingsStub(target, scheme, configuration)
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to showBuildSettings"
            )
        }
    }
}
