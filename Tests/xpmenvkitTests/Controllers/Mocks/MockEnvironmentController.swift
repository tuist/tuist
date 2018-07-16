import Basic
import Foundation
@testable import xpmenvkit

class MockEnvironmentController: EnvironmentControlling {
    var versionsDirectory: AbsolutePath
    var settingsPath: AbsolutePath
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?
    var pathVersionReferenceCallCount: UInt = 0
    var pathVersionReferenceStub: ((String) -> AbsolutePath)?

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

    func path(versionReference: String) -> AbsolutePath {
        pathVersionReferenceCallCount += 1
        return pathVersionReferenceStub?(versionReference) ?? AbsolutePath("/test")
    }
}
