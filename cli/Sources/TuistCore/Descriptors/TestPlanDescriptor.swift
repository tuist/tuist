@preconcurrency import AnyCodable
import CryptoKit
import Foundation
import Path
import XcodeGraph
import XcodeProj

/// Describes a generated `.xctestplan` file.
///
/// Unlike a `FileDescriptor`, the test targets are captured as references to `PBXTarget`
/// instances. Their PBX blueprint identifiers are only finalized when `XcodeProj` writes the
/// owning `.xcodeproj`, so the final JSON is assembled at side-effect execution time rather
/// than up front.
public struct TestPlanDescriptor: Equatable {
    /// Absolute path where the generated `.xctestplan` will be written.
    public let path: AbsolutePath

    /// Test targets included in the plan.
    public let testTargets: [TestTarget]

    public let coverage: Bool?
    public let codeCoverageTargets: [CodeCoverageTarget]

    public struct CodeCoverageTarget: Equatable {
        public let pbxTarget: PBXTarget
        public let containerPath: String

        public init(pbxTarget: PBXTarget, containerPath: String) {
            self.pbxTarget = pbxTarget
            self.containerPath = containerPath
        }
    }

    public struct TestTarget: Equatable {
        /// Reference to the PBX target. Its `uuid` becomes the `identifier` in the test plan.
        public let pbxTarget: PBXTarget

        /// `container:` relative path to the `.xcodeproj` that owns the target, as used by Xcode.
        public let containerPath: String

        /// Whether the target runs or is skipped in the plan.
        public let isEnabled: Bool

        /// How the target's tests run in parallel. Controls the `parallelizable` field in the
        /// generated `.xctestplan`.
        public let parallelization: TestableTarget.Parallelization

        public init(
            pbxTarget: PBXTarget,
            containerPath: String,
            isEnabled: Bool,
            parallelization: TestableTarget.Parallelization
        ) {
            self.pbxTarget = pbxTarget
            self.containerPath = containerPath
            self.isEnabled = isEnabled
            self.parallelization = parallelization
        }
    }

    /// Language the tests run in, written as the plan's default `language` option.
    public let language: String?

    /// Region the tests run in, written as the plan's default `region` option.
    public let region: String?

    public init(path: AbsolutePath, testTargets: [TestTarget]) {
        self.init(path: path, testTargets: testTargets, coverage: nil)
    }

    @_disfavoredOverload
    public init(
        path: AbsolutePath,
        testTargets: [TestTarget],
        coverage: Bool?,
        codeCoverageTargets: [CodeCoverageTarget] = []
    ) {
        self.init(
            path: path,
            testTargets: testTargets,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            language: nil,
            region: nil
        )
    }

    @_disfavoredOverload
    public init(
        path: AbsolutePath,
        testTargets: [TestTarget],
        coverage: Bool? = nil,
        codeCoverageTargets: [CodeCoverageTarget] = [],
        language: String?,
        region: String?
    ) {
        self.path = path
        self.testTargets = testTargets
        self.coverage = coverage
        self.codeCoverageTargets = codeCoverageTargets
        self.language = language
        self.region = region
    }

    /// Encodes the descriptor into the Xcode `.xctestplan` JSON format.
    ///
    /// - Note: Must be called after the owning `.xcodeproj` has been written so that
    ///   `pbxTarget.uuid` returns stable blueprint identifiers.
    public func encode() throws -> Data {
        var defaultOptions = [
            "language": language,
            "region": region,
        ].compactMapValues { $0 }.mapValues { AnyCodable($0) }
        var coverageOptions: [String: Any] = [:]
        if !codeCoverageTargets.isEmpty {
            coverageOptions["targets"] = codeCoverageTargets.map { target in
                [
                    "containerPath": target.containerPath,
                    "identifier": target.pbxTarget.uuid,
                    "name": target.pbxTarget.name,
                ]
            }
        }
        if let coverage {
            defaultOptions["codeCoverage"] = coverage ? AnyCodable(coverageOptions) : AnyCodable(false)
        }
        let plan = XCTestPlan(
            testTargets: testTargets.map { target in
                XCTestPlan.TestTarget(
                    target: XCTestPlan.TestTargetReference(
                        containerPath: target.containerPath,
                        identifier: target.pbxTarget.uuid,
                        name: target.pbxTarget.name
                    ),
                    enabled: target.isEnabled ? nil : false,
                    parallelizable: target.parallelization.xcTestPlanValue
                )
            },
            configurations: [
                XCTestPlan.Configuration(id: configurationID, name: "Configuration 1"),
            ],
            defaultOptions: defaultOptions,
            version: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(plan)
    }

    /// Deterministic UUID derived from the plan's absolute path.
    ///
    /// Keeps the configuration ID stable across regenerations (no git churn when a plan is
    /// pinned to a checked-in location) while being unique per plan.
    private var configurationID: UUID {
        let digest = Array(SHA256.hash(data: Data(path.pathString.utf8)).prefix(16))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

extension TestableTarget.Parallelization {
    /// Maps parallelization onto the `parallelizable` field of an `.xctestplan`.
    ///
    /// Xcode treats an absent `parallelizable` as "Swift Testing only", so `swiftTestingOnly`
    /// returns `nil` (the key gets omitted during encoding).
    fileprivate var xcTestPlanValue: Bool? {
        switch self {
        case .all: true
        case .none: false
        case .swiftTestingOnly: nil
        }
    }
}
