import ProjectDescription
import XcodeGraph

extension XcodeGraph.LaunchStyle {
    /// Maps a ProjectDescription.LaunchStyle instance into a XcodeGraph.LaunchStyle model.
    /// - Parameters:
    ///   - manifest: Manifest representation of LaunchStyle.
    static func from(manifest: ProjectDescription.LaunchStyle) -> XcodeGraph.LaunchStyle {
        switch manifest {
        case .automatically:
            return .automatically
        case .waitForExecutableToBeLaunched:
            return .waitForExecutableToBeLaunched
        }
    }
}
