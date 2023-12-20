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
        Bool,
        AbsolutePath?
    ) -> [SystemEvent<XcodeBuildOutput>])?

    func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        clean: Bool,
        arguments: [XcodeBuildArgument],
        rawXcodebuildLogs: Bool,
        rawXcodebuildLogsPath: AbsolutePath?
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let buildStub {
            return buildStub(
                target,
                scheme,
                destination,
                rosetta,
                derivedDataPath,
                clean,
                arguments,
                rawXcodebuildLogs,
                rawXcodebuildLogsPath
            ).asAsyncThrowingStream()
        } else {
            return AsyncThrowingStream {
                throw TestError(
                    "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to build"
                )
            }
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
            Bool,
            AbsolutePath?
        )
            -> [SystemEvent<XcodeBuildOutput>]
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
        rawXcodebuildLogs: Bool,
        rawXcodebuildLogsPath: AbsolutePath?
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let testStub {
            let results = testStub(
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
                rawXcodebuildLogs,
                rawXcodebuildLogsPath
            )
            if let testErrorStub {
                return AsyncThrowingStream {
                    throw testErrorStub
                }
            } else {
                return results.asAsyncThrowingStream()
            }
        } else {
            return AsyncThrowingStream {
                throw TestError(
                    "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to test"
                )
            }
        }
    }

    var archiveStub: (
        (XcodeBuildTarget, String, Bool, AbsolutePath, [XcodeBuildArgument], Bool, AbsolutePath?)
            -> [SystemEvent<XcodeBuildOutput>]
    )?
    func archive(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        archivePath: AbsolutePath,
        arguments: [XcodeBuildArgument],
        rawXcodebuildLogs: Bool,
        rawXcodebuildLogsPath: AbsolutePath?
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let archiveStub {
            return archiveStub(target, scheme, clean, archivePath, arguments, rawXcodebuildLogs, rawXcodebuildLogsPath)
                .asAsyncThrowingStream()
        } else {
            return AsyncThrowingStream {
                throw TestError(
                    "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to archive"
                )
            }
        }
    }

    var createXCFrameworkStub: (([AbsolutePath], AbsolutePath, Bool, AbsolutePath?) -> [SystemEvent<XcodeBuildOutput>])?
    func createXCFramework(
        frameworks: [AbsolutePath],
        output: AbsolutePath,
        rawXcodebuildLogs: Bool,
        rawXcodebuildLogsPath: AbsolutePath?
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let createXCFrameworkStub {
            return createXCFrameworkStub(frameworks, output, rawXcodebuildLogs, rawXcodebuildLogsPath).asAsyncThrowingStream()
        } else {
            return AsyncThrowingStream {
                throw TestError(
                    "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to createXCFramework"
                )
            }
        }
    }

    var showBuildSettingsStub: ((XcodeBuildTarget, String, String) -> [String: XcodeBuildSettings])?
    func showBuildSettings(
        _ target: XcodeBuildTarget,
        scheme: String,
        configuration: String
    ) throws -> [String: XcodeBuildSettings] {
        if let showBuildSettingsStub {
            return showBuildSettingsStub(target, scheme, configuration)
        } else {
            throw TestError(
                "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to showBuildSettings"
            )
        }
    }
}

extension Collection {
    func asAsyncThrowingStream() -> AsyncThrowingStream<Element, Error> {
        var iterator = makeIterator()
        return AsyncThrowingStream {
            iterator.next()
        }
    }
}
