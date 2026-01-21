import Foundation

public struct ServerTestCase: Codable {
    public let id: String
    public let name: String
    public let moduleName: String
    public let suiteName: String?
    public let avgDuration: Int
    public let isFlaky: Bool
    public let isQuarantined: Bool
    public let url: String

    public var fullIdentifier: String {
        if let suiteName {
            return "\(moduleName)/\(suiteName)/\(name)"
        } else {
            return "\(moduleName)/\(name)"
        }
    }
}

extension ServerTestCase {
    init(_ testCase: Components.Schemas.TestCase) {
        id = testCase.id
        name = testCase.name
        moduleName = testCase.module.name
        suiteName = testCase.suite?.name
        avgDuration = testCase.avg_duration
        isFlaky = testCase.is_flaky
        isQuarantined = testCase.is_quarantined
        url = testCase.url
    }
}

#if DEBUG
    extension ServerTestCase {
        public static func test(
            id: String = "test-case-id",
            name: String = "testExample",
            moduleName: String = "TestModule",
            suiteName: String? = "TestSuite",
            avgDuration: Int = 1000,
            isFlaky: Bool = false,
            isQuarantined: Bool = false,
            url: String = "https://cloud.tuist.io/test-case"
        ) -> Self {
            self.init(
                id: id,
                name: name,
                moduleName: moduleName,
                suiteName: suiteName,
                avgDuration: avgDuration,
                isFlaky: isFlaky,
                isQuarantined: isQuarantined,
                url: url
            )
        }
    }
#endif
