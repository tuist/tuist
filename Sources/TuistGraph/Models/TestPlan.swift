import Foundation
import TSCBasic

public struct TestPlan: Hashable, Codable {
    public let name: String
    public let path: AbsolutePath
    public let testTargets: [TestableTarget]
    public let isDefault: Bool

    public init(path: AbsolutePath, testTargets: [TestableTarget], isDefault: Bool) {
        name = path.basenameWithoutExt
        self.path = path
        self.testTargets = testTargets
        self.isDefault = isDefault
    }
}
