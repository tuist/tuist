import Basic
import Foundation
@testable import xpmenvkit

class MockEnvironmentController: EnvironmentControlling {
    var versionsDirectory: AbsolutePath
    var settingsPath: AbsolutePath
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?
    var pathVersionCallCount: UInt = 0
    var pathVersionStub: ((String) -> AbsolutePath)?

    init(versionsDirectory: AbsolutePath,
         settingsPath: AbsolutePath) {
        self.versionsDirectory = versionsDirectory
        self.settingsPath = settingsPath
    }

    func setup() throws {
        setupCallCount += 1
        if let setupErrorStub = setupErrorStub {
            throw setupErrorStub
        }
    }

    func path(version: String) -> AbsolutePath {
        pathVersionCallCount += 1
        return pathVersionStub?(version) ?? AbsolutePath("/test")
    }
}
