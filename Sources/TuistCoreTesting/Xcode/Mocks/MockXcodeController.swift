import Foundation

import TuistCore

final class MockXcodeController: XcodeControlling {
    var selectedStub: Result<Xcode, Error>?

    func selected() throws -> Xcode? {
        guard let selectedStub = selectedStub else { return nil }

        switch selectedStub {
        case let .failure(error): throw error
        case let .success(xcode): return xcode
        }
    }
}
