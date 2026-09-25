import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistLogging
import TuistServer
import TuistSupport
import XCResultParser

/// Lists the tests a run could have executed and records them in the result bundle
/// (`TestEnumeration.fileName`), so the run's report says which candidates it left out whoever
/// processes the bundle.
///
/// The list comes from `xcodebuild -enumerate-tests` over the products the run just built, with
/// the run's own arguments minus its filters. It costs a second or two on a small project and is
/// bounded by `TUIST_TEST_ENUMERATION_TIMEOUT_SECONDS` (60 by default; 0 turns it off). Behind the
/// `COVERAGE` client flag with the rest of coverage and test selection.
@Mockable
public protocol TestEnumerationServicing {
    /// Nil when the tests could not be listed; never throws, since the list only enriches the run.
    func record(
        resultBundlePath: AbsolutePath?,
        target: XcodeBuildTarget?,
        scheme: String?,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        testPlan: String?,
        xcodebuildArguments: [String]
    ) async -> TestEnumeration?
}

/// What `tuist test` knows about a run beyond its passthrough arguments, for listing its tests.
struct TestEnumerationContext {
    let target: XcodeBuildTarget?
    let scheme: String?
    let destination: XcodeBuildDestination?
    let rosetta: Bool
    let derivedDataPath: AbsolutePath?
    let testPlan: String?
    let arguments: [String]
}

public struct TestEnumerationService: TestEnumerationServicing {
    static let timeoutVariable = "TUIST_TEST_ENUMERATION_TIMEOUT_SECONDS"
    static let defaultTimeout: TimeInterval = 60

    private let fileSystem: FileSysteming
    private let xcodeBuildController: XcodeBuildControlling

    public init(
        fileSystem: FileSysteming = FileSystem(),
        xcodeBuildController: XcodeBuildControlling
    ) {
        self.fileSystem = fileSystem
        self.xcodeBuildController = xcodeBuildController
    }

    public func record(
        resultBundlePath: AbsolutePath?,
        target: XcodeBuildTarget?,
        scheme: String?,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        testPlan: String?,
        xcodebuildArguments: [String]
    ) async -> TestEnumeration? {
        let timeout = Self.timeout(variables: Environment.current.variables)
        guard ClientFeatureFlags.contains("COVERAGE"), timeout > 0, let resultBundlePath else { return nil }
        do {
            guard try await fileSystem.exists(resultBundlePath) else { return nil }
            return try await fileSystem.runInTemporaryDirectory(prefix: "test-enumeration") { directory in
                let outputPath = directory.appending(component: "tests.json")
                try await withTimeout(.seconds(timeout), onTimeout: { throw TestEnumerationError.timedOut(timeout) }) {
                    try await xcodeBuildController.enumerateTests(
                        target,
                        scheme: scheme,
                        destination: destination,
                        rosetta: rosetta,
                        derivedDataPath: derivedDataPath,
                        testPlan: testPlan,
                        passthroughXcodeBuildArguments: xcodebuildArguments,
                        outputPath: outputPath
                    )
                }
                let enumeration = try TestEnumeration(
                    xcodebuildOutput: Data(contentsOf: URL(fileURLWithPath: outputPath.pathString))
                )
                guard !enumeration.tests.isEmpty else { return nil }
                try enumeration.write(toResultBundle: URL(fileURLWithPath: resultBundlePath.pathString))
                return enumeration
            }
        } catch {
            Logger.current.debug("The run's tests could not be enumerated: \(error.localizedDescription)")
            return nil
        }
    }

    static func timeout(variables: [String: String]) -> TimeInterval {
        guard let value = variables[timeoutVariable], let seconds = TimeInterval(value), seconds >= 0 else {
            return defaultTimeout
        }
        return seconds
    }
}

enum TestEnumerationError: LocalizedError {
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case let .timedOut(seconds): "xcodebuild did not list the tests within \(Int(seconds)) seconds."
        }
    }
}
