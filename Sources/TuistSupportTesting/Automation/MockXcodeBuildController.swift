import Foundation
import RxSwift
import TSCBasic
@testable import TuistSupport

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
            return Observable.error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to build"))
        }
    }

    var testStub: ((XcodeBuildTarget, String, Bool, XcodeBuildDestination, AbsolutePath?, [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>)? // swiftlint:disable:this line_length
    func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        destination: XcodeBuildDestination,
        derivedDataPath: AbsolutePath?,
        arguments: [XcodeBuildArgument]
    ) -> Observable<SystemEvent<XcodeBuildOutput>> {
        if let testStub = testStub {
            return testStub(target, scheme, clean, destination, derivedDataPath, arguments)
        } else {
            return Observable.error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to test"))
        }
    }

    var invokedArchive = false
    var invokedArchiveCount = 0
    var invokedArchiveParameters: ArchiveParameters?
    var invokedArchiveParametersList = [ArchiveParameters]()
    var archiveStub: ((ArchiveParameters) -> Observable<SystemEvent<XcodeBuildOutput>>)?
    func archive(_ target: XcodeBuildTarget,
                 scheme: String,
                 clean: Bool,
                 archivePath: AbsolutePath,
                 arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        let parameters = ArchiveParameters(
            target: target,
            scheme: scheme,
            clean: clean,
            archivePath: archivePath,
            arguments: arguments
        )
        
        invokedArchive = true
        invokedArchiveCount += 1
        invokedArchiveParameters = parameters
        invokedArchiveParametersList.append(parameters)
        
        if let archiveStub = archiveStub {
            return archiveStub(parameters)
        } else {
            return Observable.error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to archive"))
        }
    }

    var invokedCreateXCFramework = false
    var invokedCreateXCFrameworkCount = 0
    var invokedCreateXCFrameworkParameters: CreateXCFrameworkParameters?
    var invokedCreateXCFrameworkParametersList = [CreateXCFrameworkParameters]()
    var createXCFrameworkStub: ((CreateXCFrameworkParameters) -> Observable<SystemEvent<XcodeBuildOutput>>)?
    func createXCFramework(frameworks: [AbsolutePath], output: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>> {
        let parameters = CreateXCFrameworkParameters(
            frameworks: frameworks,
            output: output
        )
        
        invokedCreateXCFramework = true
        invokedCreateXCFrameworkCount += 1
        invokedCreateXCFrameworkParameters = parameters
        invokedCreateXCFrameworkParametersList.append(parameters)
        
        if let createXCFrameworkStub = createXCFrameworkStub {
            return createXCFrameworkStub(parameters)
        } else {
            return Observable.error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to createXCFramework"))
        }
    }

    var showBuildSettingsStub: ((XcodeBuildTarget, String, String) -> Single<[String: XcodeBuildSettings]>)?
    func showBuildSettings(_ target: XcodeBuildTarget, scheme: String, configuration: String) -> Single<[String: XcodeBuildSettings]> {
        if let showBuildSettingsStub = showBuildSettingsStub {
            return showBuildSettingsStub(target, scheme, configuration)
        } else {
            return Single.error(TestError("\(String(describing: MockXcodeBuildController.self)) received an unexpected call to showBuildSettings"))
        }
    }
}

extension MockXcodeBuildController {
    struct ArchiveParameters: Equatable {
        let target: XcodeBuildTarget
        let scheme: String
        let clean: Bool
        let archivePath: AbsolutePath
        let arguments: [XcodeBuildArgument]
        
        init(
            target: XcodeBuildTarget,
            scheme: String,
            clean: Bool,
            archivePath: AbsolutePath,
            arguments: [XcodeBuildArgument]
        ) {
            self.target = target
            self.scheme = scheme
            self.clean = clean
            self.archivePath = archivePath
            self.arguments = arguments
        }
    }
    
    struct CreateXCFrameworkParameters: Equatable {
        let frameworks: [AbsolutePath]
        let output: AbsolutePath
        
        init(
            frameworks: [AbsolutePath],
            output: AbsolutePath
        ) {
            self.frameworks = frameworks
            self.output = output
        }
    }
}
