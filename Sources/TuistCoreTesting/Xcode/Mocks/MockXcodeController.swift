import Foundation
import SPMUtility
import TuistCore
import XCTest

final class MockXcodeController: XcodeControlling {
    var selectedStub: Result<Xcode, Error>?
    var selectedVersionStub: Result<Version, Error> = .success(Version(0, 0, 0))

    func selected() throws -> Xcode? {
        guard let selectedStub = selectedStub else { return nil }

        switch selectedStub {
        case let .failure(error): throw error
        case let .success(xcode): return xcode
        }
    }

    func selectedVersion() throws -> Version {
        switch selectedVersionStub {
        case let .failure(error): throw error
        case let .success(version): return version
        }
    }
}

extension XCTestCase {
    func sharedMockXcodeController(file: StaticString = #file, line: UInt = #line) -> MockXcodeController? {
        guard let mock = XcodeController.shared as? MockXcodeController else {
            let message = "XcodeController.shared hasn't been mocked." +
                "You can call mockXcodeController(), or mockSharedInstances() to mock the xcode controller or the environment respectively."
            XCTFail(message, file: file, line: line)
            return nil
        }
        return mock
    }
}
