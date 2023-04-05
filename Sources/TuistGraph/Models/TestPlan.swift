import Foundation
import TSCBasic

public struct TestPlan: Hashable, Codable {
    public struct TestTarget: Hashable, Codable {
        public let target: TargetReference
        public let isEnabled: Bool

        public init(target: TargetReference, isEnabled: Bool) {
            self.target = target
            self.isEnabled = isEnabled
        }
    }

    public let name: String
    public let path: AbsolutePath
    public let testTargets: [TestTarget]
    public let isDefault: Bool

    public init(path: AbsolutePath, testTargets: [TestTarget], isDefault: Bool) {
        name = path.basenameWithoutExt
        self.path = path
        self.testTargets = testTargets
        self.isDefault = isDefault
    }
}
