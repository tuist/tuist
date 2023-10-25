import Foundation
import ProjectDescription

public enum LaunchStyle: Codable {
    case automatically
    case waitForExecutableToBeLaunched

    public static func from(launchStyle: ProjectDescription.LaunchStyle) -> TuistGraph.LaunchStyle {
        switch launchStyle {
        case .automatically:
            return .automatically
        case .waitForExecutableToBeLaunched:
            return .waitForExecutableToBeLaunched
        }
    }
}
