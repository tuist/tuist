import ProjectDescription
import XcodeProjectGenerator

extension XcodeProjectGenerator.LaunchStyle {
    /// Maps a ProjectDescription.LaunchStyle instance into a XcodeProjectGenerator.LaunchStyle model.
    /// - Parameters:
    ///   - manifest: Manifest representation of LaunchStyle.
    static func from(manifest: ProjectDescription.LaunchStyle) -> XcodeProjectGenerator.LaunchStyle {
        switch manifest {
        case .automatically:
            return .automatically
        case .waitForExecutableToBeLaunched:
            return .waitForExecutableToBeLaunched
        }
    }
}
