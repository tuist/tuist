import Basic
import Foundation
import TuistCore
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

extension XCTestCase {
    func sharedMockEnvironment(file: StaticString = #file, line: UInt = #line) -> MockEnvironment? {
        guard let mock = Environment.shared as? MockEnvironment else {
            let message = "Environment hasn't been mocked." +
            "You can call mockEnvironment(), or mockSharedInstances() to mock the file handler or the environment respectively."
            XCTFail(message, file: file, line: line)
            return nil
        }
        return mock
    }
}
