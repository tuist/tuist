import Foundation

public final class MockTuistVersionLoader: TuistVersionLoading {
    var getVersionStub: String = "4.0.1"
    private(set) var getVersionCalls = 0
    func getVersion() throws -> String {
        getVersionStub
    }
}
