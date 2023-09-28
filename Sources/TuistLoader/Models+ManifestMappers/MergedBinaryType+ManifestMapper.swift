import ProjectDescription
import TuistGraph

extension TuistGraph.MergedBinaryType {
    /// Maps a ProjectDescription.MergedBinaryType instance into a TuistGraph.MergedBinaryType model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    static func from(manifest: ProjectDescription.MergedBinaryType) throws -> TuistGraph.MergedBinaryType {
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
