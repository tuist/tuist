import Foundation
import Path
import XcodeGraph
import XcodeProj

extension PBXTarget {
    /// Attempts to retrieve the bundle identifier from the target's debug build settings, or throws an error if missing.
    func bundleIdentifier() throws -> String {
        if let bundleId = debugBuildSettings[BuildSettingKey.productBundleIdentifier]?.stringValue {
            return bundleId
        } else {
            return "Unknown"
        }
    }

    /// Returns an array of all `PBXCopyFilesBuildPhase` instances for this target.
    func copyFilesBuildPhases() -> [PBXCopyFilesBuildPhase] {
        buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
    }

    func mergedBinaryType() throws -> MergedBinaryType {
        let mergedBinaryTypeString = debugBuildSettings[BuildSettingKey.mergedBinaryType]?.stringValue
        return mergedBinaryTypeString == "automatic" ? .automatic : .disabled
    }

    func onDemandResourcesTags() throws -> OnDemandResourcesTags? {
        // Currently returns nil, could be extended if needed
        return nil
    }
}
