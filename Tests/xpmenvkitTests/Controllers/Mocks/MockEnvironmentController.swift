import Basic
import Foundation
@testable import xpmenvkit

class MockEnvironmentController: EnvironmentControlling {
    let directory: TemporaryDirectory    
    var setupCallCount: UInt = 0
    var setupErrorStub: Error?

    init() throws {
       self.directory = try TemporaryDirectory(removeTreeOnDeinit: true)
    }
    
    var versionsDirectory: AbsolutePath {
        return self.directory.path.appending(component: "Versions")
    }
    
    var settingsPath: AbsolutePath {
        return self.directory.path.appending(component: "settings.json")
    }

    func setup() throws {
        setupCallCount += 1
        if let setupErrorStub = setupErrorStub {
            throw setupErrorStub
        }
    }

    func path(version: String) -> AbsolutePath {
        return versionsDirectory.appending(component: version)
    }
}
