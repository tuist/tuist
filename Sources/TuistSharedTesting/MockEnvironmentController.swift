import Basic
import Foundation
@testable import TuistEnvKit
import TuistShared

public class MockEnvironmentController: EnvironmentControlling {
    let directory: TemporaryDirectory
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?

    init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try FileManager.default.createDirectory(at: versionsDirectory.url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    public var versionsDirectory: AbsolutePath {
        return directory.path.appending(component: "Versions")
    }

    public var derivedProjectsDirectory: AbsolutePath {
        return directory.path.appending(component: "DerivedProjects")
    }

    public var settingsPath: AbsolutePath {
        return directory.path.appending(component: "settings.json")
    }

    func path(version: String) -> AbsolutePath {
        return versionsDirectory.appending(component: version)
    }
}
