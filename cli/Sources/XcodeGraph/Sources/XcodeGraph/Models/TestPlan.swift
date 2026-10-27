import Foundation
import Path

public struct TestPlan: Hashable, Codable, Sendable {
    /// How the `.xctestplan` file comes to exist on disk.
    public enum Kind: String, Hashable, Codable, Sendable {
        /// The file already exists on disk and is maintained by the user.
        case referenced
        /// The file is produced by Tuist during project generation.
        case generated
    }

    public let name: String
    public let path: AbsolutePath
    public let testTargets: [TestableTarget]
    public let isDefault: Bool
    public let kind: Kind

    public init(
        path: AbsolutePath,
        testTargets: [TestableTarget],
        isDefault: Bool,
        kind: Kind = .referenced
    ) {
        name = path.basenameWithoutExt
        self.path = path
        self.testTargets = testTargets
        self.isDefault = isDefault
        self.kind = kind
    }
}
