import ProjectDescription
import XcodeProjectGenerator

extension XcodeProjectGenerator.MergedBinaryType {
    /// Maps a ProjectDescription.MergedBinaryType instance into a XcodeProjectGenerator.MergedBinaryType model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    static func from(manifest: ProjectDescription.MergedBinaryType) throws -> XcodeProjectGenerator.MergedBinaryType {
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
