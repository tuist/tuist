import Foundation
import TSCBasic
import TuistCore
import TuistSupport
@testable import TuistSupportTesting

final class MockXcodeBuildController: XcodeBuildControlling {
    var buildStub: ((
        XcodeBuildTarget,
        String,
        XcodeBuildDestination?,
        Bool,
        AbsolutePath?,
        Bool,
        [XcodeBuildArgument],
        [String]
    ) -> Void)?

    func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        clean: Bool,
        arguments: [XcodeBuildArgument],
        passthroughXcodeBuildArguments: [String]
    ) throws {
        if let buildStub {
            buildStub(
                target,
                scheme,
                destination,
                rosetta,
                derivedDataPath,
                clean,
                arguments,
                passthroughXcodeBuildArguments
            )
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to build"
            )
        }
    }

    var testStub: (
        (
            XcodeBuildTarget,
            String,
            Bool,
            XcodeBuildDestination,
            Bool,
            AbsolutePath?,
            AbsolutePath?,
            [XcodeBuildArgument],
            Int,
            [TestIdentifier],
            [TestIdentifier],
            TestPlanConfiguration?,
            [String]
        )
            -> Void
    )?
    var testErrorStub: Error?
    func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        destination: XcodeBuildDestination,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument],
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String]
    ) throws {
        if let testStub {
            testStub(
                target,
                scheme,
                clean,
                destination,
                rosetta,
                derivedDataPath,
                resultBundlePath,
                arguments,
                retryCount,
                testTargets,
                skipTestTargets,
                testPlanConfiguration,
                passthroughXcodeBuildArguments
            )
            if let testErrorStub {
                throw testErrorStub
            }
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to test"
            )
        }
    }

    var archiveStub: (
        (XcodeBuildTarget, String, Bool, AbsolutePath, [XcodeBuildArgument], AbsolutePath?)
            -> Void
    )?
    func archive(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        archivePath: AbsolutePath,
        arguments: [XcodeBuildArgument],
        derivedDataPath: AbsolutePath?
    ) throws {
        if let archiveStub {
            archiveStub(target, scheme, clean, archivePath, arguments, derivedDataPath)
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to archive"
            )
        }
    }

    var createXCFrameworkStub: (
        ([String], AbsolutePath)
            -> Void
    )?
    func createXCFramework(
        arguments: [String],
        output: AbsolutePath
    ) throws {
        if let createXCFrameworkStub {
            createXCFrameworkStub(arguments, output)
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to createXCFramework"
            )
        }
    }

    var showBuildSettingsStub: ((XcodeBuildTarget, String, String, AbsolutePath?) -> [String: XcodeBuildSettings])?
    func showBuildSettings(
        _ target: XcodeBuildTarget,
        scheme: String,
        configuration: String,
        derivedDataPath: AbsolutePath?
    ) throws -> [String: XcodeBuildSettings] {
        if let showBuildSettingsStub {
            return showBuildSettingsStub(target, scheme, configuration, derivedDataPath)
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to showBuildSettings"
            )
        }
    }
}
