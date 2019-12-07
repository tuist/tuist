import Foundation
@testable import SPMUtility

public extension ArgumentParser {
    static func test(usage: String = "test",
                     overview: String = "overview") -> ArgumentParser {
        ArgumentParser(usage: usage, overview: overview)
    }
}
