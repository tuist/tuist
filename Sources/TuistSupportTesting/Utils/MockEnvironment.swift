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
        try FileManager.default.createDirectory(at: versionsDirectory.url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    public var isVerbose: Bool = false
    public var cacheDirectoryStub: AbsolutePath?
    public var queueDirectoryStub: AbsolutePath?
    public var shouldOutputBeColoured: Bool = false
    public var isStandardOutputInteractive: Bool = false
    public var tuistVariables: [String: String] = [:]
    public var manifestLoadingVariables: [String: String] = [:]

    public var versionsDirectory: AbsolutePath {
        directory.path.appending(component: "Versions")
    }

    public var settingsPath: AbsolutePath {
        directory.path.appending(component: "settings.json")
    }

    public var cacheDirectory: AbsolutePath {
        cacheDirectoryStub ?? directory.path.appending(component: "Cache")
    }

    public var queueDirectory: AbsolutePath {
        queueDirectoryStub ?? directory.path.appending(component: Constants.AsyncQueue.directoryName)
    }

    public var projectDescriptionHelpersCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "ProjectDescriptionHelpers")
    }

    public var projectsCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "Projects")
    }
    
    public var buildCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "BuildCache")
    }

    func path(version: String) -> AbsolutePath {
        versionsDirectory.appending(component: version)
    }
}
