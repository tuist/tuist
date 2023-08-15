import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.Destination {
    /// Maps a ProjectDescription.Package instance into a TuistGraph.Package model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    ///   - generatorPaths: Generator paths.
    static func from(
        platform: ProjectDescription.Platform,
        deploymentTarget: ProjectDescription.DeploymentTarget?
    ) throws -> TuistGraph.Destinations {
        switch (platform, deploymentTarget) {
        case (.macOS, _):
            return [.mac]
        case let (.iOS, .some(.iOS(_, devices, supportsMacDesignedForIOS: supportsMacDesignedForIOS))):
            var destinations: [Destination] = []

            if devices.contains(.iphone) {
                destinations.append(.iPhone)
            }

            if devices.contains(.ipad) {
                destinations.append(.iPad)
            }

            if devices.contains(.mac) {
                destinations.append(.macCatalyst)
            }

            if devices.contains(.vision) {
                destinations.append(.appleVisionWithiPadDesign)
            }

            if supportsMacDesignedForIOS {
                destinations.append(.macWithiPadDesign)
            }

            return Set(destinations)
        case (.iOS, _): // an iOS platform, but `nil` deployment target.
            return .iOS
        case (.tvOS, _):
            return .tvOS
        case (.watchOS, _):
            return .watchOS
        case (.visionOS, _):
            return .visionOS
        }
    }
}
