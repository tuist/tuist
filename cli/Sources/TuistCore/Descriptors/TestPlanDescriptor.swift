import CryptoKit
import Foundation
import Path
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

    public struct TestTarget: Equatable {
        /// Reference to the PBX target. Its `uuid` becomes the `identifier` in the test plan.
        public let pbxTarget: PBXTarget

        /// `container:` relative path to the `.xcodeproj` that owns the target, as used by Xcode.
        public let containerPath: String

        /// Whether the target runs or is skipped in the plan.
        public let isEnabled: Bool

        public init(pbxTarget: PBXTarget, containerPath: String, isEnabled: Bool) {
            self.pbxTarget = pbxTarget
            self.containerPath = containerPath
            self.isEnabled = isEnabled
        }
    }

    public init(path: AbsolutePath, testTargets: [TestTarget]) {
        self.path = path
        self.testTargets = testTargets
    }

    /// Encodes the descriptor into the Xcode `.xctestplan` JSON format.
    ///
    /// - Note: Must be called after the owning `.xcodeproj` has been written so that
    ///   `pbxTarget.uuid` returns stable blueprint identifiers.
    public func encode() throws -> Data {
        let plan = XCTestPlan(
            configurations: [
                XCTestPlan.Configuration(
                    id: configurationID,
                    name: "Configuration 1",
                    options: [:]
                ),
            ],
            defaultOptions: [:],
            testTargets: testTargets.map { target in
                XCTestPlan.TestTarget(
                    enabled: target.isEnabled ? nil : false,
                    target: XCTestPlan.TargetReference(
                        containerPath: target.containerPath,
                        identifier: target.pbxTarget.uuid,
                        name: target.pbxTarget.name
                    )
                )
            },
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

private struct XCTestPlan: Encodable {
    struct Configuration: Encodable {
        let id: UUID
        let name: String
        let options: [String: String]
    }

    struct TargetReference: Encodable {
        let containerPath: String
        let identifier: String
        let name: String
    }

    struct TestTarget: Encodable {
        let enabled: Bool?
        let target: TargetReference
    }

    let configurations: [Configuration]
    let defaultOptions: [String: String]
    let testTargets: [TestTarget]
    let version: Int
}
