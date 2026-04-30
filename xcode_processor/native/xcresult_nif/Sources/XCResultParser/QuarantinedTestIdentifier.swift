import Foundation

public struct QuarantinedTestIdentifier: Codable, Sendable, Hashable {
    public let target: String
    public let `class`: String?
    public let method: String?

    public init(target: String, class: String? = nil, method: String? = nil) {
        self.target = target
        self.class = `class`
        self.method = method
    }

    func matches(testCase: TestCase) -> Bool {
        guard testCase.module == target else { return false }
        if let `class`, testCase.testSuite != `class` { return false }
        if let method, testCase.name != method { return false }
        return true
    }
}
