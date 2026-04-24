import Foundation
import Path

public struct TestPlan: Hashable, Codable, Sendable {
    public let name: String
    public let path: AbsolutePath
    public let testTargets: [TestableTarget]
    public let isDefault: Bool
    /// When `true`, the `.xctestplan` file at `path` is (re)written by Tuist during generation.
    public let isGenerated: Bool

    public init(
        path: AbsolutePath,
        testTargets: [TestableTarget],
        isDefault: Bool,
        isGenerated: Bool = false
    ) {
        name = path.basenameWithoutExt
        self.path = path
        self.testTargets = testTargets
        self.isDefault = isDefault
        self.isGenerated = isGenerated
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case testTargets
        case isDefault
        case isGenerated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(AbsolutePath.self, forKey: .path)
        testTargets = try container.decode([TestableTarget].self, forKey: .testTargets)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        isGenerated = try container.decodeIfPresent(Bool.self, forKey: .isGenerated) ?? false
    }
}
