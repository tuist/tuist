import ProjectDescription
import TuistGraph

extension TuistGraph.LaunchStyle {
    /// Maps a ProjectDescription.LaunchStyle instance into a TuistGraph.LaunchStyle model.
    /// - Parameters:
    ///   - manifest: Manifest representation of LaunchStyle.
   static func from(manifest: ProjectDescription.LaunchStyle) -> TuistGraph.LaunchStyle {
       switch manifest {
       case .automatically:
           return .automatically
       case .waitForExecutableToBeLaunched:
           return .waitForExecutableToBeLaunched
       }
   }
}
