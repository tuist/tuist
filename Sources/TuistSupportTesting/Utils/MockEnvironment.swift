import Foundation
import TSCBasic
import TuistSupport
import XCTest

public class MockEnvironment: Environmenting {
    let directory: TemporaryDirectory
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?

    init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try FileManager.default.createDirectory(at: versionsDirectory.url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    public var isVerbose: Bool = false
    public var cacheDirectoryStub: AbsolutePath?

    public var shouldOutputBeColoured: Bool = false
    public var isStandardOutputInteractive: Bool = false
    public var tuistVariables: [String: String] = [:]

    public var versionsDirectory: AbsolutePath {
        directory.path.appending(component: "Versions")
    }

    public var settingsPath: AbsolutePath {
        directory.path.appending(component: "settings.json")
    }

    public var cacheDirectory: AbsolutePath {
        cacheDirectoryStub ?? directory.path.appending(component: "Cache")
    }

    public var projectDescriptionHelpersCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "ProjectDescriptionHelpers")
    }

    public var xcframeworksCacheDirectory: AbsolutePath {
        cacheDirectory.appending(component: "xcframeworks")
    }

    func path(version: String) -> AbsolutePath {
        versionsDirectory.appending(component: version)
    }
}
