import ProjectDescription
import XcodeGraph

extension XcodeGraph.MergedBinaryType {
    /// Maps a ProjectDescription.MergedBinaryType instance into a XcodeGraph.MergedBinaryType model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    static func from(manifest: ProjectDescription.MergedBinaryType) throws -> XcodeGraph.MergedBinaryType {
        switch manifest {
        case .automatic:
            return .automatic
        case .disabled:
            return .disabled
        case let .manual(mergeableDependencies):
            return .manual(mergeableDependencies: mergeableDependencies)
        }
    }
}
