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
    /// Language the tests run in. Only written into generated plans.
    public let language: String?
    /// Region the tests run in. Only written into generated plans.
    public let region: String?
    public let coverage: Bool?
    public let codeCoverageTargets: [TargetReference]

    public init(
        path: AbsolutePath,
        testTargets: [TestableTarget],
        isDefault: Bool,
        kind: Kind = .referenced
    ) {
        self.init(path: path, testTargets: testTargets, isDefault: isDefault, kind: kind, coverage: nil)
    }

    public init(
        path: AbsolutePath,
        testTargets: [TestableTarget],
        isDefault: Bool,
        kind: Kind = .referenced,
        coverage: Bool?,
        codeCoverageTargets: [TargetReference] = []
    ) {
        self.init(
            path: path,
            testTargets: testTargets,
            isDefault: isDefault,
            kind: kind,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            language: nil,
            region: nil
        )
    }

    public init(
        path: AbsolutePath,
        testTargets: [TestableTarget],
        isDefault: Bool,
        kind: Kind = .referenced,
        coverage: Bool? = nil,
        codeCoverageTargets: [TargetReference] = [],
        language: String?,
        region: String?
    ) {
        name = path.basenameWithoutExt
        self.path = path
        self.testTargets = testTargets
        self.isDefault = isDefault
        self.kind = kind
        self.language = language
        self.region = region
        self.coverage = coverage
        self.codeCoverageTargets = codeCoverageTargets
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, testTargets, isDefault, kind, coverage, codeCoverageTargets, language, region
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(AbsolutePath.self, forKey: .path)
        testTargets = try container.decode([TestableTarget].self, forKey: .testTargets)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        kind = try container.decode(Kind.self, forKey: .kind)
        coverage = try container.decodeIfPresent(Bool.self, forKey: .coverage)
        codeCoverageTargets = try container.decodeIfPresent([TargetReference].self, forKey: .codeCoverageTargets) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language)
        region = try container.decodeIfPresent(String.self, forKey: .region)
    }
}
