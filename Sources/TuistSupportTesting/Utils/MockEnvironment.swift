import Foundation
import TSCBasic
import TuistSupport
import XCTest

public class MockEnvironment: Environmenting {
    fileprivate let directory: TemporaryDirectory
    fileprivate var setupCallCount: UInt = 0
    fileprivate var setupErrorStub: Error?

    init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try FileManager.default.createDirectory(
            at: versionsDirectory.url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public var isVerbose: Bool = false
    public var queueDirectoryStub: AbsolutePath?
    public var shouldOutputBeColoured: Bool = false
    public var isStandardOutputInteractive: Bool = false
    public var tuistVariables: [String: String] = [:]
    public var tuistConfigVariables: [String: String] = [:]
    public var manifestLoadingVariables: [String: String] = [:]
    public var isStatsEnabled: Bool = true

    public var versionsDirectory: AbsolutePath {
        directory.path.appending(component: "Versions")
    }

    public var settingsPath: AbsolutePath {
        directory.path.appending(component: "settings.json")
    }

    public var automationPath: AbsolutePath? {
        nil
    }

    public var queueDirectory: AbsolutePath {
        queueDirectoryStub ?? directory.path.appending(component: Constants.AsyncQueue.directoryName)
    }

    func path(version: String) -> AbsolutePath {
        versionsDirectory.appending(component: version)
    }

    public func bootstrap() throws {}
}
