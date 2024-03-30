import Foundation
@testable import TuistKit

public final class MockTuistVersionLoader: TuistVersionLoading {
    var getVersionStub: String = "4.0.1"
    private(set) var getVersionCalls = 0
    public func getVersion() throws -> String {
        getVersionStub
    }
}
