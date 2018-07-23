import Basic
import Foundation
@testable import TuistEnvKit

class MockEnvironmentController: EnvironmentControlling {
    let directory: TemporaryDirectory
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?

    init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        try FileManager.default.createDirectory(at: versionsDirectory.url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    var versionsDirectory: AbsolutePath {
        return directory.path.appending(component: "Versions")
    }

    var settingsPath: AbsolutePath {
        return directory.path.appending(component: "settings.json")
    }

    func path(version: String) -> AbsolutePath {
        return versionsDirectory.appending(component: version)
    }
}
