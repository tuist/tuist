import Foundation
import Path
import XcodeProj

/// Describes a generated `.xctestplan` file.
///
/// Unlike a `FileDescriptor`, the test targets are captured as references to `PBXTarget`
/// instances. The PBX blueprint identifiers are only known once `XcodeProj` finalizes
/// references during writing, so the final JSON is assembled in `XcodeProjWriter` after
/// the owning `.xcodeproj` is written.
public struct TestPlanDescriptor {
    /// Absolute path where the generated `.xctestplan` will be written.
    public let path: AbsolutePath

    /// Test targets included in the plan.
    public let testTargets: [TestTarget]

    public struct TestTarget {
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
}
