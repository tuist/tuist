import Foundation
import TSCBasic
import TuistCore
import TuistSupport
@testable import TuistSupportTesting

final class MockXcodeBuildController: XcodeBuildControlling {
    var buildStub: ((XcodeBuildTarget, String, Bool, [XcodeBuildArgument]) -> [SystemEvent<XcodeBuildOutput>])?
    func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        arguments: [XcodeBuildArgument]
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let buildStub = buildStub {
            return buildStub(target, scheme, clean, arguments).asAsyncThrowingStream()
        } else {
            return AsyncThrowingStream {
                throw TestError(
                    "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to build"
                )
            }
        }
    }

    var testStub: (
        (XcodeBuildTarget, String, Bool, XcodeBuildDestination, AbsolutePath?, AbsolutePath?, [XcodeBuildArgument], Int)
            -> [SystemEvent<XcodeBuildOutput>]
    )?
    var testErrorStub: Error?
    func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        destination: XcodeBuildDestination,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument],
        retryCount: Int
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let testStub = testStub {
            let results = testStub(target, scheme, clean, destination, derivedDataPath, resultBundlePath, arguments, retryCount)
            if let testErrorStub = testErrorStub {
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
        (XcodeBuildTarget, String, Bool, AbsolutePath, [XcodeBuildArgument])
            -> [SystemEvent<XcodeBuildOutput>]
    )?
    func archive(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        archivePath: AbsolutePath,
        arguments: [XcodeBuildArgument]
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let archiveStub = archiveStub {
            return archiveStub(target, scheme, clean, archivePath, arguments).asAsyncThrowingStream()
        } else {
            return AsyncThrowingStream {
                throw TestError(
                    "\(String(describing: MockXcodeBuildController.self)) received an unexpected call to archive"
                )
            }
        }
    }

    var createXCFrameworkStub: (([AbsolutePath], AbsolutePath) -> [SystemEvent<XcodeBuildOutput>])?
    func createXCFramework(
        frameworks: [AbsolutePath],
        output: AbsolutePath
    ) -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error> {
        if let createXCFrameworkStub = createXCFrameworkStub {
            return createXCFrameworkStub(frameworks, output).asAsyncThrowingStream()
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
        if let showBuildSettingsStub = showBuildSettingsStub {
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
            return iterator.next()
        }
    }
}
