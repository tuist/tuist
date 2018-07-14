import Basic
import Foundation
@testable import xpmenvkit

class MockEnvironmentController: EnvironmentControlling {
    var versionsDirectory: AbsolutePath
    var settingsPath: AbsolutePath
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?

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
}
