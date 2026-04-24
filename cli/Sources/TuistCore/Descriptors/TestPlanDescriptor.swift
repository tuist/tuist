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
        let plan = XCTestPlanPayload(
            configurations: [
                XCTestPlanPayload.Configuration(
                    id: UUID(uuidString: "91BDB644-1AEA-4734-9E55-F6DA2F59DF74")!,
                    name: "Configuration 1",
                    options: [:]
                ),
            ],
            defaultOptions: [:],
            testTargets: testTargets.map { target in
                XCTestPlanPayload.TestTarget(
                    enabled: target.isEnabled ? nil : false,
                    target: XCTestPlanPayload.TargetReference(
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
}

private struct XCTestPlanPayload: Encodable {
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
