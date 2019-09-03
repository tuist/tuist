import Foundation
import SPMUtility
import TuistCore

final class MockXcodeController: XcodeControlling {
    var selectedStub: Result<Xcode, Error>?
    var selectedVersionStub: Version = Version(0, 0, 0)
    
    func selected() throws -> Xcode? {
        guard let selectedStub = selectedStub else { return nil }

        switch selectedStub {
        case let .failure(error): throw error
        case let .success(xcode): return xcode
        }
    }
    
    func selectedVersion() throws -> Version {
        return selectedVersionStub
    }
}
